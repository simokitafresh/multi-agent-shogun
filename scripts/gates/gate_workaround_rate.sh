#!/bin/bash
# gate_workaround_rate.sh — karo_workarounds.yamlの直近N件からworkaround率を計算
# Usage: bash scripts/gates/gate_workaround_rate.sh [--last N]
# Output: OK/WARN/ALERT + WA率 + カテゴリ内訳
# 閾値: OK=<15%, WARN=15-30%, ALERT=>30%
# GATE判定には影響しない（情報表示のみ）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WA_FILE="$SCRIPT_DIR/logs/karo_workarounds.yaml"
LAST_N=10

# 引数パース
while [ $# -gt 0 ]; do
    case "$1" in
        --last)
            LAST_N="${2:-10}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

echo "■ Workaround率 (直近${LAST_N}件)"

if [ ! -f "$WA_FILE" ]; then
    echo "  SKIP: karo_workarounds.yaml不在"
    exit 0
fi

# Python で workaround率計算 + カテゴリ内訳
result=$(WAFILE="$WA_FILE" LAST_N="$LAST_N" python3 -c '
import os, sys

filepath = os.environ["WAFILE"]
last_n = int(os.environ.get("LAST_N", "10"))

items = []

try:
    with open(filepath, encoding="utf-8") as f:
        lines = f.readlines()
except Exception as e:
    print(f"ERROR|0|0|0|parse_error|{e}")
    sys.exit(0)

# パーサー: YAMLが不統一なため行ベースで解析
# workaround: true/false/yes/no と karo_workaround: yes/no の両方に対応
current = None
for line in lines:
    s = line.rstrip()
    # 新エントリ開始: "- cmd:" or "- cmd_id:" or "- timestamp:" (inline dict style)
    if s.startswith("- cmd:") or s.startswith("- cmd_id:"):
        if current is not None:
            items.append(current)
        cmd_val = s.split(":", 1)[1].strip().strip("\"").strip("'"'"'")
        current = {"cmd": cmd_val, "workaround": None, "category": "uncategorized"}
    elif s.strip().startswith("- timestamp:") and current is None:
        # inline dict entries (indented with "  - timestamp:")
        current = {"cmd": "", "workaround": None, "category": "uncategorized"}
    elif current is not None:
        stripped = s.strip()
        if stripped.startswith("- ") and ":" in stripped and not stripped.startswith("- check:"):
            # Could be start of new inline entry
            pass
        if ":" in stripped:
            key, _, val = stripped.partition(":")
            key = key.strip().lstrip("- ").strip()
            val = val.strip().strip("\"").strip("'"'"'")
            val_lower = val.lower()
            if key == "workaround":
                current["workaround"] = val_lower in ("true", "yes")
            elif key == "karo_workaround":
                current["workaround"] = val_lower in ("true", "yes")
            elif key == "category":
                current["category"] = val if val else "uncategorized"
            elif key == "cmd" and not current.get("cmd"):
                current["cmd"] = val
            elif key == "cmd_id" and not current.get("cmd"):
                current["cmd"] = val
            elif key == "issue" and current.get("workaround") is None:
                # inline dict entries with "issue" field = workaround
                current["workaround"] = True
                current["category"] = val[:40] if val else "uncategorized"

if current is not None:
    items.append(current)

# workaround フィールドが None のエントリを除外（パース不良）
items = [i for i in items if i.get("workaround") is not None]

if not items:
    print("OK|0|0|0|none|no data")
    sys.exit(0)

# 直近N件
last = items[-last_n:] if len(items) >= last_n else items
total = len(last)
wa_count = sum(1 for i in last if i["workaround"])

# 率
rate = (wa_count / total * 100) if total > 0 else 0

# カテゴリ内訳
cats = {}
for i in last:
    if i["workaround"]:
        cat = i.get("category", "uncategorized")
        cats[cat] = cats.get(cat, 0) + 1

cat_parts = [f"{k}:{v}" for k, v in sorted(cats.items(), key=lambda x: -x[1])]
cat_str = ", ".join(cat_parts) if cat_parts else "none"

# 判定
if rate < 15:
    level = "OK"
elif rate <= 30:
    level = "WARN"
else:
    level = "ALERT"

print(f"{level}|{rate:.0f}|{wa_count}|{total}|{cat_str}")
' 2>/dev/null || echo "ERROR|0|0|0|python_error")

IFS='|' read -r LEVEL RATE WA_COUNT TOTAL CATS <<< "$result"

echo "  WA率: ${RATE}% (${WA_COUNT}/${TOTAL}件) — ${LEVEL}"
if [ "$WA_COUNT" -gt 0 ] && [ -n "$CATS" ] && [ "$CATS" != "none" ]; then
    echo "  カテゴリ内訳: ${CATS}"
fi

if [ "$LEVEL" = "ALERT" ]; then
    echo "  ⚠ ALERT: workaround率が30%超過。構造的問題の可能性"
elif [ "$LEVEL" = "WARN" ]; then
    echo "  注意: workaround率が15-30%。傾向監視を推奨"
fi
