#!/usr/bin/env bash
# ============================================================
# model_analysis.sh — モデル特性5軸分析ツール
#
# Usage:
#   bash scripts/model_analysis.sh --detail          # 人間用テーブル(5セクション)
#   bash scripts/model_analysis.sh --summary         # key=value (dashboard統合用)
#   bash scripts/model_analysis.sh --json            # 機械可読JSON
#   bash scripts/model_analysis.sh --compare opus sonnet  # 2モデル対比
#
# Data Sources:
#   1. logs/gate_metrics.log  — CLEAR/BLOCK結果
#   2. config/settings.yaml   — ninja→model mapping
#   3. logs/lesson_tracking.tsv — cmd→ninja mapping
#
# Sections:
#   A: モデル別CLEAR率
#   B: BLOCK理由分布(モデル別)
#   C: 種別適性(モデル×task_type)
#   D: コスト効率
#   E: トレンド(直近20cmd窓)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE_LOG="$SCRIPT_DIR/logs/gate_metrics.log"
SETTINGS="$SCRIPT_DIR/config/settings.yaml"
TRACKING="$SCRIPT_DIR/logs/lesson_tracking.tsv"

# Argument parse
MODE=""
CMP_MODEL1=""
CMP_MODEL2=""

case "${1:-}" in
    --detail)  MODE="detail" ;;
    --summary) MODE="summary" ;;
    --json)    MODE="json" ;;
    --compare)
        MODE="compare"
        CMP_MODEL1="${2:-}"
        CMP_MODEL2="${3:-}"
        if [[ -z "$CMP_MODEL1" ]] || [[ -z "$CMP_MODEL2" ]]; then
            echo "ERROR: --compare requires two model names (e.g. --compare opus sonnet)" >&2
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 --detail | --summary | --json | --compare <model1> <model2>" >&2
        exit 1
        ;;
esac

# Data file check
if [[ ! -f "$GATE_LOG" ]]; then
    echo "ERROR: gate_metrics.log not found: $GATE_LOG" >&2
    exit 1
fi

export GATE_LOG SETTINGS TRACKING MODE CMP_MODEL1 CMP_MODEL2

python3 << 'PYEOF'
import os, sys, json, re
from collections import defaultdict, OrderedDict

# ─── Config ───
GATE_LOG = os.environ["GATE_LOG"]
SETTINGS = os.environ["SETTINGS"]
TRACKING = os.environ["TRACKING"]
MODE = os.environ["MODE"]
CMP_MODEL1 = os.environ.get("CMP_MODEL1", "").lower()
CMP_MODEL2 = os.environ.get("CMP_MODEL2", "").lower()

COST_WEIGHTS = {"opus": 5, "sonnet": 1, "codex": 0.2}
ALL_NINJAS = ["sasuke", "kirimaru", "hayate", "kagemaru", "hanzo", "saizo", "kotaro", "tobisaru"]

# ─── Parse settings.yaml for ninja→model map ───
def parse_ninja_model_map():
    nmap = {}
    if not os.path.isfile(SETTINGS):
        return nmap
    in_agents = False
    cur_ninja = ""
    cur_type = ""
    cur_model = ""
    with open(SETTINGS, "r") as f:
        for line in f:
            stripped = line.rstrip()
            if re.match(r"^\s*agents:", stripped):
                in_agents = True
                continue
            if in_agents and re.match(r"^[^\s]", stripped):
                in_agents = False
                continue
            if not in_agents:
                continue
            m = re.match(r"^    ([a-z]+):", stripped)
            if m:
                if cur_ninja:
                    nmap[cur_ninja] = _resolve_model(cur_type, cur_model)
                cur_ninja = m.group(1)
                cur_type = ""
                cur_model = ""
                continue
            if cur_ninja:
                tm = re.match(r"^\s+type:\s*(\S+)", stripped)
                if tm:
                    cur_type = tm.group(1)
                mm = re.match(r"^\s+model_name:\s*(\S+)", stripped)
                if mm:
                    cur_model = mm.group(1)
    if cur_ninja:
        nmap[cur_ninja] = _resolve_model(cur_type, cur_model)
    return nmap

def _resolve_model(ctype, model_name):
    if ctype == "codex":
        return "codex"
    if "sonnet" in model_name:
        return "sonnet"
    if "haiku" in model_name:
        return "haiku"
    return "opus"

ninja_model = parse_ninja_model_map()

# ─── Parse lesson_tracking.tsv for cmd→ninjas map ───
def parse_tracking():
    cmd_ninjas = {}
    if not os.path.isfile(TRACKING):
        return cmd_ninjas
    with open(TRACKING, "r") as f:
        for i, line in enumerate(f):
            if i == 0:
                continue
            parts = line.strip().split("\t")
            if len(parts) < 3:
                continue
            cmd_id = parts[1]
            ninjas = [n.strip() for n in parts[2].split(",") if n.strip()]
            if cmd_id not in cmd_ninjas:
                cmd_ninjas[cmd_id] = set()
            cmd_ninjas[cmd_id].update(ninjas)
    return cmd_ninjas

tracking_ninjas = parse_tracking()

# ─── Extract ninja names from BLOCK detail column ───
def extract_ninjas_from_detail(detail):
    ninjas = set()
    if not detail or detail == "all_gates_passed":
        return ninjas
    tokens = detail.split("|")
    for tok in tokens:
        m = re.match(r"^([a-z]+):", tok)
        if m and m.group(1) in ALL_NINJAS:
            ninjas.add(m.group(1))
    return ninjas

# ─── BLOCK reason classification ───
def classify_block_reason(detail):
    if not detail or detail == "all_gates_passed":
        return []
    reasons = []
    tokens = detail.split("|")
    for tok in tokens:
        tok_lower = tok.lower()
        if "missing_gate:" in tok_lower:
            reasons.append("missing_gate")
        elif "unreviewed_lessons:" in tok_lower:
            reasons.append("unreviewed_lessons")
        elif "empty_lesson_referenced:" in tok_lower:
            reasons.append("unreviewed_lessons")
        elif "lesson_done_source:" in tok_lower or "lesson_done_missing" in tok_lower:
            reasons.append("lesson_processing")
        elif "lesson_candidate" in tok_lower:
            reasons.append("lesson_processing")
        elif "draft_lessons:" in tok_lower:
            reasons.append("lesson_processing")
        else:
            reasons.append("code_quality")
    return reasons

# ─── Parse gate_metrics.log ───
entries = []

with open(GATE_LOG, "r") as f:
    for line in f:
        line = line.rstrip("\n\r")
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        ts = parts[0]
        cmd_id = parts[1]
        result = parts[2]
        detail = parts[3]

        if cmd_id.startswith("cmd_test"):
            continue

        entry = {
            "timestamp": ts,
            "cmd_id": cmd_id,
            "result": result,
            "detail": detail,
            "task_type": "",
            "models": set(),
        }

        if len(parts) >= 6:
            entry["task_type"] = parts[4]
            model_str = parts[5].lower()
            if model_str:
                entry["models"].add(model_str)
        else:
            ninjas = set()
            if cmd_id in tracking_ninjas:
                ninjas.update(tracking_ninjas[cmd_id])
            detail_ninjas = extract_ninjas_from_detail(detail)
            ninjas.update(detail_ninjas)
            for n in ninjas:
                if n in ninja_model:
                    entry["models"].add(ninja_model[n])

        entries.append(entry)

# ─── Cmd-level dedup (keep last result per cmd) ───
cmd_latest = OrderedDict()
for e in entries:
    cmd_latest[e["cmd_id"]] = e

deduped = list(cmd_latest.values())
deduped.sort(key=lambda x: x["timestamp"])

for e in deduped:
    if not e["models"]:
        e["models"].add("unknown")

# ═══════════════════════════════════════════════════════
# Section A: モデル別CLEAR率
# ═══════════════════════════════════════════════════════
def section_a():
    model_stats = defaultdict(lambda: {"clear": 0, "total": 0})
    for e in deduped:
        for m in e["models"]:
            model_stats[m]["total"] += 1
            if e["result"] == "CLEAR":
                model_stats[m]["clear"] += 1
    results = {}
    for m in sorted(model_stats.keys()):
        s = model_stats[m]
        rate = (s["clear"] / s["total"] * 100) if s["total"] > 0 else 0.0
        results[m] = {"clear": s["clear"], "total": s["total"], "rate": rate}
    return results

# ═══════════════════════════════════════════════════════
# Section B: BLOCK理由分布(モデル別)
# ═══════════════════════════════════════════════════════
def section_b():
    model_reasons = defaultdict(lambda: defaultdict(int))
    model_block_total = defaultdict(int)
    for e in deduped:
        if e["result"] != "BLOCK":
            continue
        reasons = classify_block_reason(e["detail"])
        for m in e["models"]:
            for r in reasons:
                model_reasons[m][r] += 1
                model_block_total[m] += 1
    results = {}
    for m in sorted(model_reasons.keys()):
        total = model_block_total[m]
        reasons_pct = {}
        for r, cnt in sorted(model_reasons[m].items(), key=lambda x: -x[1]):
            pct = (cnt / total * 100) if total > 0 else 0.0
            reasons_pct[r] = {"count": cnt, "pct": pct}
        results[m] = {"total_blocks": total, "reasons": reasons_pct}
    return results

# ═══════════════════════════════════════════════════════
# Section C: 種別適性(モデル×task_type)
# ═══════════════════════════════════════════════════════
def section_c():
    matrix = defaultdict(lambda: defaultdict(lambda: {"clear": 0, "total": 0}))
    for e in deduped:
        ttype = e["task_type"] if e["task_type"] else "unknown"
        for m in e["models"]:
            matrix[m][ttype]["total"] += 1
            if e["result"] == "CLEAR":
                matrix[m][ttype]["clear"] += 1
    results = {}
    for m in sorted(matrix.keys()):
        type_stats = {}
        for t in sorted(matrix[m].keys()):
            s = matrix[m][t]
            rate = (s["clear"] / s["total"] * 100) if s["total"] > 0 else 0.0
            type_stats[t] = {"clear": s["clear"], "total": s["total"], "rate": rate}
        results[m] = type_stats
    return results

# ═══════════════════════════════════════════════════════
# Section D: コスト効率
# ═══════════════════════════════════════════════════════
def section_d():
    a_data = section_a()
    results = {}
    for m, stats in a_data.items():
        weight = COST_WEIGHTS.get(m, 1)
        efficiency = stats["rate"] / weight if weight > 0 else 0.0
        results[m] = {
            "clear_rate": stats["rate"],
            "cost_weight": weight,
            "efficiency": efficiency,
            "n": stats["total"],
        }
    return results

# ═══════════════════════════════════════════════════════
# Section E: トレンド(直近20cmd窓)
# ═══════════════════════════════════════════════════════
def section_e():
    model_cmds = defaultdict(list)
    for e in deduped:
        for m in e["models"]:
            model_cmds[m].append(e["result"])

    results = {}
    for m in sorted(model_cmds.keys()):
        cmds = model_cmds[m]
        n = len(cmds)
        if n < 2:
            results[m] = {"current_rate": None, "prev_rate": None, "trend": "insufficient_data", "n": n}
            continue
        window = min(20, n)
        recent = cmds[-window:]
        recent_clear = sum(1 for r in recent if r == "CLEAR")
        recent_rate = (recent_clear / len(recent) * 100) if recent else 0.0

        remaining = cmds[:-window]
        if len(remaining) >= 5:
            prev_window = min(20, len(remaining))
            prev = remaining[-prev_window:]
            prev_clear = sum(1 for r in prev if r == "CLEAR")
            prev_rate = (prev_clear / len(prev) * 100) if prev else 0.0
            delta = recent_rate - prev_rate
            if delta > 2:
                trend = "up"
            elif delta < -2:
                trend = "down"
            else:
                trend = "stable"
            results[m] = {
                "current_rate": recent_rate,
                "prev_rate": prev_rate,
                "trend": trend,
                "delta": delta,
                "n": n,
            }
        else:
            results[m] = {
                "current_rate": recent_rate,
                "prev_rate": None,
                "trend": "no_prev_window",
                "n": n,
            }
    return results

# ═══════════════════════════════════════════════════════
# Output Formatters
# ═══════════════════════════════════════════════════════

TREND_ARROWS = {"up": "↑", "down": "↓", "stable": "→", "no_prev_window": "—", "insufficient_data": "—"}

def output_detail():
    print("=" * 60)
    print("  Model Analysis — 5-Axis Report")
    print("=" * 60)

    # Section A
    a = section_a()
    print()
    print("[A] モデル別CLEAR率")
    print("-" * 50)
    print("  %-12s %-8s %-8s %-10s" % ("Model", "CLEAR", "Total", "Rate"))
    print("  %-12s %-8s %-8s %-10s" % ("-----", "-----", "-----", "----"))
    for m, s in sorted(a.items(), key=lambda x: -x[1]["rate"]):
        clr = s["clear"]
        tot = s["total"]
        rate = s["rate"]
        print("  %-12s %-8d %-8d %.1f%%" % (m, clr, tot, rate))

    # Section B
    b = section_b()
    print()
    print("[B] BLOCK理由分布(モデル別)")
    print("-" * 50)
    for m in sorted(b.keys()):
        data = b[m]
        tb = data["total_blocks"]
        print("  %s (total blocks: %d)" % (m, tb))
        for r, info in data["reasons"].items():
            cnt = info["count"]
            pct = info["pct"]
            print("    %-25s %4d (%.1f%%)" % (r, cnt, pct))

    # Section C
    c = section_c()
    print()
    print("[C] 種別適性(モデル×task_type)")
    print("-" * 50)
    all_types = set()
    for m_data in c.values():
        all_types.update(m_data.keys())
    all_types = sorted(all_types)
    header = "  %-12s" % "Model"
    for t in all_types:
        header += " %-15s" % t
    print(header)
    print("  " + "-" * (12 + 16 * len(all_types)))
    for m in sorted(c.keys()):
        row = "  %-12s" % m
        for t in all_types:
            if t in c[m]:
                s = c[m][t]
                cell = "%.1f%%(N=%d)" % (s["rate"], s["total"])
                row += " %-15s" % cell
            else:
                row += " %-15s" % "—"
        print(row)

    # Section D
    d = section_d()
    print()
    print("[D] コスト効率 (CLEAR率 ÷ コスト重み)")
    print("-" * 50)
    print("  %-12s %-10s %-8s %-10s %-6s" % ("Model", "CLEAR率", "コスト", "効率", "N"))
    print("  %-12s %-10s %-8s %-10s %-6s" % ("-----", "------", "----", "----", "--"))
    for m, s in sorted(d.items(), key=lambda x: -x[1]["efficiency"]):
        cr = "%.1f%%" % s["clear_rate"]
        cw = "x%.1f" % s["cost_weight"]
        eff = "%.1f" % s["efficiency"]
        nn = str(s["n"])
        print("  %-12s %-10s %-8s %-10s %-6s" % (m, cr, cw, eff, nn))

    # Section E
    e = section_e()
    print()
    print("[E] トレンド(直近20cmd窓)")
    print("-" * 50)
    print("  %-12s %-10s %-10s %-12s %-6s" % ("Model", "Current", "Previous", "Trend", "N"))
    print("  %-12s %-10s %-10s %-12s %-6s" % ("-----", "-------", "--------", "-----", "--"))
    for m in sorted(e.keys()):
        s = e[m]
        cur = "%.1f%%" % s["current_rate"] if s["current_rate"] is not None else "—"
        prev = "%.1f%%" % s["prev_rate"] if s.get("prev_rate") is not None else "—"
        arrow = TREND_ARROWS.get(s["trend"], "?")
        trend_str = "%s %s" % (arrow, s["trend"])
        nn = str(s["n"])
        print("  %-12s %-10s %-10s %-12s %-6s" % (m, cur, prev, trend_str, nn))

    print()
    print("=" * 60)

def output_summary():
    a = section_a()
    for m in sorted(a.keys()):
        if m == "unknown":
            continue
        s = a[m]
        print("%s_clear_rate=%.1f" % (m, s["rate"]))
        print("%s_n=%d" % (m, s["total"]))

def output_json():
    result = {
        "section_a": section_a(),
        "section_b": section_b(),
        "section_c": section_c(),
        "section_d": section_d(),
        "section_e": section_e(),
        "metadata": {
            "total_entries": len(entries),
            "deduped_cmds": len(deduped),
            "models_detected": sorted(set(m for e in deduped for m in e["models"])),
        },
    }
    def convert(obj):
        if isinstance(obj, set):
            return sorted(list(obj))
        if isinstance(obj, dict):
            return {k: convert(v) for k, v in obj.items()}
        if isinstance(obj, list):
            return [convert(i) for i in obj]
        return obj
    print(json.dumps(convert(result), indent=2, ensure_ascii=False))

def output_compare():
    m1, m2 = CMP_MODEL1, CMP_MODEL2
    a = section_a()
    d = section_d()
    e = section_e()

    print("=" * 50)
    print("  Head-to-Head: %s vs %s" % (m1.upper(), m2.upper()))
    print("=" * 50)

    def get_a(model):
        return a.get(model, {"clear": 0, "total": 0, "rate": 0.0})

    def get_d(model):
        return d.get(model, {"clear_rate": 0.0, "cost_weight": 1, "efficiency": 0.0, "n": 0})

    def get_e(model):
        return e.get(model, {"current_rate": None, "prev_rate": None, "trend": "—", "n": 0})

    a1, a2 = get_a(m1), get_a(m2)
    d1, d2 = get_d(m1), get_d(m2)
    e1, e2 = get_e(m1), get_e(m2)

    print()
    print("  %-25s %-18s %-18s %s" % ("Metric", m1.upper(), m2.upper(), "Winner"))
    print("  %s %s %s %s" % ("-" * 25, "-" * 18, "-" * 18, "-" * 8))

    # CLEAR rate
    w = m1 if a1["rate"] >= a2["rate"] else m2
    c1 = "%.1f%%(N=%d)" % (a1["rate"], a1["total"])
    c2 = "%.1f%%(N=%d)" % (a2["rate"], a2["total"])
    print("  %-25s %-18s %-18s %s" % ("CLEAR率", c1, c2, w))

    # Cost efficiency
    w = m1 if d1["efficiency"] >= d2["efficiency"] else m2
    e1_s = "%.1f" % d1["efficiency"]
    e2_s = "%.1f" % d2["efficiency"]
    print("  %-25s %-18s %-18s %s" % ("コスト効率", e1_s, e2_s, w))

    # Trend
    cur1 = "%.1f%%" % e1["current_rate"] if e1["current_rate"] is not None else "—"
    cur2 = "%.1f%%" % e2["current_rate"] if e2["current_rate"] is not None else "—"
    t1 = TREND_ARROWS.get(e1.get("trend", "—"), "—")
    t2 = TREND_ARROWS.get(e2.get("trend", "—"), "—")
    print("  %-25s %-18s %-18s %s" % ("直近トレンド", "%s %s" % (cur1, t1), "%s %s" % (cur2, t2), "—"))

    # N
    print("  %-25s %-18s %-18s" % ("サンプル数", str(a1["total"]), str(a2["total"])))
    print()
    print("=" * 50)

# ─── Dispatch ───
if MODE == "detail":
    output_detail()
elif MODE == "summary":
    output_summary()
elif MODE == "json":
    output_json()
elif MODE == "compare":
    output_compare()
PYEOF
