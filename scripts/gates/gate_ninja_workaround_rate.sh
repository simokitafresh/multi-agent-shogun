#!/bin/bash
# gate_ninja_workaround_rate.sh — 忍者別workaround率を集計
# 目的: karo_workarounds.yamlから直近N cmd分の忍者別workaround件数/率を出力
# Usage: bash scripts/gates/gate_ninja_workaround_rate.sh [--last N] [--quiet] [--ninja NAME]
#   --last N     : 直近N件を対象 (default: 30)
#   --quiet      : サマリ1行のみ出力 (gate_karo_startup.sh統合用)
#   --ninja NAME : 指定忍者のみの履歴を表示 (SG9用)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WA_FILE="$SCRIPT_DIR/logs/karo_workarounds.yaml"

LAST_N=30
QUIET=false
NINJA_FILTER=""

while [ $# -gt 0 ]; do
    case "$1" in
        --last) LAST_N="$2"; shift 2 ;;
        --quiet) QUIET=true; shift ;;
        --ninja) NINJA_FILTER="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [ ! -f "$WA_FILE" ]; then
    if [ "$QUIET" = true ]; then
        echo "  workaround集計: データなし (karo_workarounds.yaml不在)"
    else
        echo "ERROR: $WA_FILE が存在しない"
    fi
    exit 0
fi

WAFILE="$WA_FILE" LAST_N="$LAST_N" QUIET="$QUIET" NINJA_FILTER="$NINJA_FILTER" python3 << 'PYEOF'
import os, re, sys

wa_file = os.environ["WAFILE"]
last_n = int(os.environ["LAST_N"])
quiet = os.environ["QUIET"] == "true"
ninja_filter = os.environ.get("NINJA_FILTER", "")

# --- ninja name mapping (Japanese → romaji) ---
NINJA_JP_MAP = {
    "疾風": "hayate",
    "影丸": "kagemaru",
    "半蔵": "hanzo",
    "才蔵": "saizo",
    "小太郎": "kotaro",
    "飛猿": "tobisaru",
}
NINJA_NAMES = {"hayate", "kagemaru", "hanzo", "saizo", "kotaro", "tobisaru"}

def extract_ninja(entry):
    """エントリから忍者名(romaji)を抽出"""
    # 1. explicit ninja field
    ninja = entry.get("ninja", "")
    if ninja and ninja in NINJA_NAMES:
        return ninja

    # 2. Search detail/root_cause/issue for Japanese names
    text = " ".join([
        str(entry.get("detail", "")),
        str(entry.get("root_cause", "")),
        str(entry.get("issue", "")),
        str(entry.get("workaround_detail", "")),
    ])
    for jp, romaji in NINJA_JP_MAP.items():
        if jp in text:
            return romaji

    # 3. Search for romaji names in text
    for name in NINJA_NAMES:
        if name in text.lower():
            return name

    return "unknown"

def is_workaround(entry):
    """エントリがworkaroundかどうか判定"""
    wa = entry.get("workaround")
    if wa is not None:
        if isinstance(wa, bool):
            return wa
        return str(wa).lower() in ("true", "yes")
    kwa = entry.get("karo_workaround")
    if kwa is not None:
        return str(kwa).lower() in ("true", "yes")
    return False

# --- Parse YAML (robust: try yaml first, fallback to manual) ---
entries = []

try:
    import yaml
    with open(wa_file) as f:
        data = yaml.safe_load(f)
    if data and isinstance(data, dict):
        items = data.get("workarounds", [])
        if isinstance(items, list):
            entries = [e for e in items if isinstance(e, dict)]
except Exception:
    pass

if not entries:
    # Fallback: line-by-line parsing
    try:
        with open(wa_file) as f:
            lines = f.readlines()
        current = None
        for line in lines:
            s = line.rstrip()
            if re.match(r'^- (cmd|cmd_id):', s):
                if current is not None:
                    entries.append(current)
                current = {"_src": "top"}
                key, _, val = s[2:].partition(":")
                current[key.strip()] = val.strip().strip("'\"")
            elif re.match(r'^  - (timestamp|cmd):', s) and s.startswith("  - "):
                if current is not None:
                    entries.append(current)
                current = {"_src": "nested"}
                key, _, val = s.strip()[2:].partition(":")
                current[key.strip()] = val.strip().strip("'\"")
            elif current is not None and ":" in s:
                stripped = s.strip()
                if stripped.startswith("- "):
                    continue
                key, _, val = stripped.partition(":")
                key = key.strip()
                val = val.strip().strip("'\"")
                if key == "workaround":
                    current["workaround"] = val.lower() in ("true", "yes")
                elif key == "karo_workaround":
                    current["karo_workaround"] = val
                else:
                    current[key] = val
        if current is not None:
            entries.append(current)
    except Exception as e:
        if not quiet:
            print(f"ERROR: パース失敗 — {e}", file=sys.stderr)
        sys.exit(0)

# --- Take last N entries ---
target = entries[-last_n:] if len(entries) > last_n else entries
total = len(target)

if total == 0:
    if quiet:
        print("  忍者別workaround: データなし")
    else:
        print("対象エントリなし")
    sys.exit(0)

# --- Aggregate per ninja ---
stats = {}
for entry in target:
    ninja = extract_ninja(entry)
    wa = is_workaround(entry)
    if ninja not in stats:
        stats[ninja] = {"total": 0, "workaround": 0}
    stats[ninja]["total"] = stats[ninja]["total"] + 1
    if wa:
        stats[ninja]["workaround"] = stats[ninja]["workaround"] + 1

# --- Calculate totals ---
total_wa = sum(s["workaround"] for s in stats.values())
total_clean = total - total_wa

# --- Ninja filter mode (SG9) ---
if ninja_filter:
    s = stats.get(ninja_filter, {"total": 0, "workaround": 0})
    if s["total"] == 0:
        print(f"=== {ninja_filter} workaround履歴 (直近{total}件中) ===")
        print(f"  担当件数: 0 — 対象期間にエントリなし")
    else:
        rate = s["workaround"] / s["total"] * 100
        print(f"=== {ninja_filter} workaround履歴 (直近{total}件中) ===")
        print(f"  担当件数: {s['total']}  WA件数: {s['workaround']}  WA率: {rate:.1f}%")
        # Show individual workaround entries for this ninja
        wa_entries = [e for e in target if extract_ninja(e) == ninja_filter and is_workaround(e)]
        if wa_entries:
            print(f"  直近workaround詳細:")
            for e in wa_entries[-5:]:
                cmd = e.get("cmd", e.get("cmd_id", "?"))
                cat = e.get("category", e.get("root_cause", "?"))
                print(f"    - {cmd}: {cat}")
        else:
            print(f"  workaroundなし: clean")
    sys.exit(0)

# --- Output ---
if quiet:
    # gate_karo_startup.sh統合用: 1行サマリ + workaround多い忍者
    worst = sorted(
        [(n, s) for n, s in stats.items() if s["workaround"] > 0],
        key=lambda x: -x[1]["workaround"]
    )
    if worst:
        parts = [f"{n}:{s['workaround']}/{s['total']}" for n, s in worst]
        print(f"  忍者別workaround(直近{total}件): " + ", ".join(parts))
    else:
        print(f"  忍者別workaround(直近{total}件): 全員clean")
else:
    print(f"=== 忍者別workaround率 (直近{total}件) ===")
    print("")
    # Sort by workaround count desc, then name
    sorted_stats = sorted(stats.items(), key=lambda x: (-x[1]["workaround"], x[0]))
    print(f"{'忍者':<12} {'WA件数':>7} {'担当件数':>8} {'WA率':>7}")
    print("-" * 38)
    for ninja, s in sorted_stats:
        rate = (s["workaround"] / s["total"] * 100) if s["total"] > 0 else 0
        print(f"{ninja:<12} {s['workaround']:>7} {s['total']:>8} {rate:>6.1f}%")
    print("-" * 38)
    print(f"{'合計':<12} {total_wa:>7} {total:>8} {total_wa/total*100:>6.1f}%")
    print("")
    # Top offenders
    worst = sorted(
        [(n, s) for n, s in stats.items() if s["workaround"] > 0],
        key=lambda x: -x[1]["workaround"]
    )
    if worst:
        print("要注意忍者:")
        for n, s in worst[:3]:
            rate = s["workaround"] / s["total"] * 100
            print(f"  {n}: {s['workaround']}件 ({rate:.0f}%)")
    else:
        print("全員clean: workaroundなし")
PYEOF
