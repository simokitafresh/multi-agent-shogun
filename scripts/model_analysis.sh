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
#   1. logs/gate_metrics.log    — CLEAR/BLOCK結果
#   2. config/settings.yaml     — ninja→model mapping
#   3. logs/lesson_tracking.tsv — cmd→ninja mapping
#   4. logs/ninja_monitor.log   — AUTO-DONE/TASK-CLEAR → cmd→ninja
#   5. logs/deploy_task.log     — deployment complete → cmd→ninja
#   6. queue/archive/           — inbox+report+cmd archives → cmd→ninja
#
# Sections:
#   A: モデル別CLEAR率
#   B: BLOCK理由分布(モデル別)
#   C: 種別適性(モデル×task_type)
#   D: コスト効率
#   E: トレンド(直近20cmd窓)
#   F: Bloom Level × Model CLEAR率
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE_LOG="$SCRIPT_DIR/logs/gate_metrics.log"
SETTINGS="$SCRIPT_DIR/config/settings.yaml"
TRACKING="$SCRIPT_DIR/logs/lesson_tracking.tsv"
NINJA_MONITOR="$SCRIPT_DIR/logs/ninja_monitor.log"
DEPLOY_LOG="$SCRIPT_DIR/logs/deploy_task.log"
ARCHIVE_DIR="$SCRIPT_DIR/queue/archive"

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

export GATE_LOG SETTINGS TRACKING NINJA_MONITOR DEPLOY_LOG ARCHIVE_DIR MODE CMP_MODEL1 CMP_MODEL2

python3 << 'PYEOF'
import os, sys, json, re
from collections import defaultdict, OrderedDict

# ─── Config ───
GATE_LOG = os.environ["GATE_LOG"]
SETTINGS = os.environ["SETTINGS"]
TRACKING = os.environ["TRACKING"]
NINJA_MONITOR = os.environ.get("NINJA_MONITOR", "")
DEPLOY_LOG = os.environ.get("DEPLOY_LOG", "")
ARCHIVE_DIR = os.environ.get("ARCHIVE_DIR", "")
MODE = os.environ["MODE"]
CMP_MODEL1 = os.environ.get("CMP_MODEL1", "").lower()
CMP_MODEL2 = os.environ.get("CMP_MODEL2", "").lower()

COST_WEIGHTS = {"opus": 5, "sonnet": 1, "codex": 0.2}
ALL_NINJAS = ["sasuke", "kirimaru", "hayate", "kagemaru", "hanzo", "saizo", "kotaro", "tobisaru"]
ALL_NINJAS_SET = set(ALL_NINJAS)

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

# ─── Parse ninja_monitor.log for cmd→ninjas (AUTO-DONE + TASK-CLEAR) ───
def parse_ninja_monitor():
    cmd_ninjas = defaultdict(set)
    if not NINJA_MONITOR or not os.path.isfile(NINJA_MONITOR):
        return cmd_ninjas
    with open(NINJA_MONITOR, "r") as f:
        for line in f:
            m = re.search(r"AUTO-DONE: (\w+) .*parent_cmd=(cmd_\d+)", line)
            if m and m.group(1) in ALL_NINJAS_SET:
                cmd_ninjas[m.group(2)].add(m.group(1))
                continue
            m = re.search(r"TASK-CLEAR: (\w+) .*was: (cmd_\d+)", line)
            if m and m.group(1) in ALL_NINJAS_SET:
                cmd_ninjas[m.group(2)].add(m.group(1))
                continue
            m = re.search(r"TASK-CLEAR: (\w+) .*was: subtask_(\d+)", line)
            if m and m.group(1) in ALL_NINJAS_SET:
                cmd_ninjas["cmd_" + m.group(2)].add(m.group(1))
    return cmd_ninjas

monitor_ninjas = parse_ninja_monitor()

# ─── Parse deploy_task.log for cmd→ninjas ───
def parse_deploy_log():
    cmd_ninjas = defaultdict(set)
    if not DEPLOY_LOG or not os.path.isfile(DEPLOY_LOG):
        return cmd_ninjas
    with open(DEPLOY_LOG, "r") as f:
        for line in f:
            m = re.search(r"\[DEPLOY\] (\w+): deployment complete \(type=(cmd_\d+)\)", line)
            if m and m.group(1) in ALL_NINJAS_SET:
                cmd_ninjas[m.group(2)].add(m.group(1))
    return cmd_ninjas

deploy_ninjas = parse_deploy_log()

# ─── Parse archived inbox/report/cmd files for cmd→ninjas ───
def parse_archives():
    cmd_ninjas = defaultdict(set)
    if not ARCHIVE_DIR or not os.path.isdir(ARCHIVE_DIR):
        return cmd_ninjas
    try:
        import yaml
    except ImportError:
        return cmd_ninjas
    # Archived karo inbox → ninja reports with cmd refs
    for fname in os.listdir(ARCHIVE_DIR):
        if not fname.startswith("inbox_karo") or not fname.endswith(".yaml"):
            continue
        try:
            with open(os.path.join(ARCHIVE_DIR, fname), "r") as f:
                data = yaml.safe_load(f)
            if not data or "messages" not in data:
                continue
            for msg in data["messages"]:
                frm = msg.get("from", "")
                content = msg.get("content", "")
                if frm not in ALL_NINJAS_SET:
                    continue
                for c in re.findall(r"cmd_?(\d+)", content):
                    cmd_ninjas["cmd_" + c].add(frm)
        except Exception:
            continue
    # Archived ninja inbox → cmd refs
    for fname in os.listdir(ARCHIVE_DIR):
        if not fname.startswith("inbox_") or fname.startswith("inbox_karo") or fname.startswith("inbox_shogun"):
            continue
        if not fname.endswith(".yaml"):
            continue
        nm = re.match(r"inbox_(\w+)_\d+\.yaml", fname)
        if not nm:
            continue
        ninja = nm.group(1)
        if ninja not in ALL_NINJAS_SET:
            continue
        try:
            with open(os.path.join(ARCHIVE_DIR, fname), "r") as f:
                data = yaml.safe_load(f)
            if not data or "messages" not in data:
                continue
            for msg in data["messages"]:
                content = msg.get("content", "")
                for c in re.findall(r"cmd_?(\d+)", content):
                    cmd_ninjas["cmd_" + c].add(ninja)
        except Exception:
            continue
    # Archived report filenames
    reports_dir = os.path.join(ARCHIVE_DIR, "reports")
    if os.path.isdir(reports_dir):
        for fname in os.listdir(reports_dir):
            m = re.match(r"^([a-z]+)_report.*?(cmd_?\d+)", fname)
            if m and m.group(1) in ALL_NINJAS_SET:
                cmd_id = m.group(2)
                if not cmd_id.startswith("cmd_"):
                    cmd_id = "cmd_" + cmd_id[3:]
                cmd_ninjas[cmd_id].add(m.group(1))
    # Archived cmd YAML text → ninja name mentions
    cmds_dir = os.path.join(ARCHIVE_DIR, "cmds")
    if os.path.isdir(cmds_dir):
        for fname in os.listdir(cmds_dir):
            m = re.match(r"(cmd_\d+)_", fname)
            if not m:
                continue
            cmd_id = m.group(1)
            try:
                with open(os.path.join(cmds_dir, fname), "r") as f:
                    content = f.read()
                for n in ALL_NINJAS:
                    if n in content:
                        cmd_ninjas[cmd_id].add(n)
            except Exception:
                continue
    return cmd_ninjas

archive_ninjas = parse_archives()

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

        if cmd_id.lower().startswith("cmd_test"):
            continue

        entry = {
            "timestamp": ts,
            "cmd_id": cmd_id,
            "result": result,
            "detail": detail,
            "task_type": "",
            "models": set(),
            "bloom_level": "unknown",
        }

        if len(parts) >= 6:
            entry["task_type"] = parts[4]
            model_str = parts[5].lower()
            if model_str:
                for m in model_str.split(","):
                    m = m.strip()
                    if m:
                        entry["models"].add(m)
            if len(parts) >= 7 and parts[6].strip():
                entry["bloom_level"] = parts[6].strip()
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

# ─── Pre-dedup: collect all ninjas per cmd from ALL sources ───
cmd_all_ninjas = defaultdict(set)
for e in entries:
    detail_ninjas = extract_ninjas_from_detail(e["detail"])
    cmd_all_ninjas[e["cmd_id"]].update(detail_ninjas)
    if e["cmd_id"] in tracking_ninjas:
        cmd_all_ninjas[e["cmd_id"]].update(tracking_ninjas[e["cmd_id"]])
# Merge ninja_monitor, deploy_task, and archive sources
for src in (monitor_ninjas, deploy_ninjas, archive_ninjas):
    for cmd_id, ninjas in src.items():
        cmd_all_ninjas[cmd_id].update(ninjas)

# ─── Cmd-level dedup (keep last result per cmd) ───
cmd_latest = OrderedDict()
for e in entries:
    cmd_latest[e["cmd_id"]] = e

deduped = list(cmd_latest.values())
deduped.sort(key=lambda x: x["timestamp"])

# ─── Post-dedup: resolve models from pre-collected ninjas ───
for e in deduped:
    if not e["models"]:
        ninjas = cmd_all_ninjas.get(e["cmd_id"], set())
        for n in ninjas:
            if n in ninja_model:
                e["models"].add(ninja_model[n])
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

def section_c_detail():
    """Extended section C with data quality indicator and model×type matrix."""
    matrix = defaultdict(lambda: defaultdict(lambda: {"clear": 0, "total": 0}))
    total_entries = 0
    unknown_entries = 0
    for e in deduped:
        ttype = e["task_type"] if e["task_type"] else "unknown"
        total_entries += 1
        if ttype == "unknown":
            unknown_entries += 1
        for m in e["models"]:
            matrix[m][ttype]["total"] += 1
            if e["result"] == "CLEAR":
                matrix[m][ttype]["clear"] += 1
    # Data quality
    unknown_pct = (unknown_entries / total_entries * 100) if total_entries > 0 else 0.0
    if unknown_pct < 5:
        reliability = "高"
    elif unknown_pct < 20:
        reliability = "中"
    else:
        reliability = "低"
    data_quality = {
        "unknown": unknown_entries,
        "total": total_entries,
        "pct": round(unknown_pct, 1),
        "reliability": reliability,
    }
    # Model × type matrix (exclude unknown model row & unknown type col for the detail matrix)
    known_types = sorted(t for t in set(
        t for m_data in matrix.values() for t in m_data.keys()
    ) if t != "unknown")
    known_models = sorted(m for m in matrix.keys() if m != "unknown")
    model_type_matrix = {}
    for m in known_models:
        model_type_matrix[m] = {}
        model_total_clear = 0
        model_total_all = 0
        for t in known_types:
            s = matrix[m][t]
            if s["total"] > 0:
                rate = round(s["clear"] / s["total"] * 100, 1)
                model_type_matrix[m][t] = {"clear": s["clear"], "total": s["total"], "rate": rate}
                model_total_clear += s["clear"]
                model_total_all += s["total"]
        # Overall for known types only
        if model_total_all > 0:
            model_type_matrix[m]["_overall"] = {
                "clear": model_total_clear,
                "total": model_total_all,
                "rate": round(model_total_clear / model_total_all * 100, 1),
            }
    return {
        "data_quality": data_quality,
        "known_types": known_types,
        "model_type_matrix": model_type_matrix,
    }

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
# Section F: Bloom Level × Model CLEAR率
# ═══════════════════════════════════════════════════════
def section_f():
    matrix = defaultdict(lambda: defaultdict(lambda: {"clear": 0, "total": 0}))
    for e in deduped:
        bl = e.get("bloom_level", "unknown") or "unknown"
        for m in e["models"]:
            matrix[bl][m]["total"] += 1
            if e["result"] == "CLEAR":
                matrix[bl][m]["clear"] += 1
    results = {}
    for bl in sorted(matrix.keys()):
        model_stats = {}
        for m in sorted(matrix[bl].keys()):
            s = matrix[bl][m]
            rate = (s["clear"] / s["total"] * 100) if s["total"] > 0 else 0.0
            model_stats[m] = {"clear": s["clear"], "total": s["total"], "rate": rate}
        results[bl] = model_stats
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
    cd = section_c_detail()
    dq = cd["data_quality"]
    known_types = cd["known_types"]
    mtx = cd["model_type_matrix"]
    print()
    print("[C] 種別適性 (モデル × タスク種別)")
    print("-" * 50)
    print("  データ品質: unknown %d/%d (%.1f%%) — 信頼性: %s" % (
        dq["unknown"], dq["total"], dq["pct"], dq["reliability"]))
    print()
    if not known_types:
        print("  (タスク種別データなし — backfill実行後に精度向上)")
    else:
        # Build header
        col_w = 14
        header = "  %-12s" % "Model"
        for t in known_types:
            header += "| %-*s" % (col_w, t)
        header += "| %-*s" % (col_w, "総合")
        print(header)
        sep = "  " + "-" * 12
        for _ in known_types:
            sep += "|" + "-" * (col_w + 1)
        sep += "|" + "-" * (col_w + 1)
        print(sep)
        for m in sorted(mtx.keys()):
            row = "  %-12s" % m
            for t in known_types:
                if t in mtx[m]:
                    s = mtx[m][t]
                    if s["total"] >= 5:
                        cell = "%d%% (%d/%d)" % (int(s["rate"]), s["clear"], s["total"])
                    else:
                        cell = "N/A (%d件)" % s["total"]
                else:
                    cell = "—"
                row += "| %-*s" % (col_w, cell)
            # Overall
            if "_overall" in mtx[m]:
                ov = mtx[m]["_overall"]
                if ov["total"] >= 5:
                    ov_cell = "%d%%" % int(ov["rate"])
                else:
                    ov_cell = "N/A (%d件)" % ov["total"]
            else:
                ov_cell = "—"
            row += "| %-*s" % (col_w, ov_cell)
            print(row)
    # Also print legacy full table (including unknown) as sub-section
    c = section_c()
    print()
    print("  [C-full] 全種別(unknown含む)")
    all_types = sorted(set(t for m_data in c.values() for t in m_data.keys()))
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

    # Section F
    f = section_f()
    print()
    print("[F] Bloom Level × Model CLEAR率")
    print("-" * 50)
    print("  %-14s %-12s %-8s %-8s %-10s" % ("bloom_level", "Model", "CLEAR", "Total", "Rate"))
    print("  %-14s %-12s %-8s %-8s %-10s" % ("-----------", "-----", "-----", "-----", "----"))
    for bl in sorted(f.keys()):
        for m, s in sorted(f[bl].items(), key=lambda x: -x[1]["rate"]):
            rate_str = "%.1f%%" % s["rate"]
            print("  %-14s %-12s %-8d %-8d %s" % (bl, m, s["clear"], s["total"], rate_str))

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
        "section_c_detail": section_c_detail(),
        "section_d": section_d(),
        "section_e": section_e(),
        "section_f": section_f(),
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

    # Type-specific comparison
    cd = section_c_detail()
    mtx = cd["model_type_matrix"]
    known_types = cd["known_types"]
    if known_types and m1 in mtx and m2 in mtx:
        print()
        print("  --- 種別別CLEAR率 ---")
        print("  %-25s %-18s %-18s %s" % ("種別", m1.upper(), m2.upper(), "Winner"))
        print("  %s %s %s %s" % ("-" * 25, "-" * 18, "-" * 18, "-" * 8))
        for t in known_types:
            s1 = mtx[m1].get(t, {})
            s2 = mtx[m2].get(t, {})
            n1 = s1.get("total", 0)
            n2 = s2.get("total", 0)
            if n1 >= 5:
                c1 = "%d%%(%d/%d)" % (int(s1["rate"]), s1["clear"], n1)
            elif n1 > 0:
                c1 = "N/A(%d件)" % n1
            else:
                c1 = "—"
            if n2 >= 5:
                c2 = "%d%%(%d/%d)" % (int(s2["rate"]), s2["clear"], n2)
            elif n2 > 0:
                c2 = "N/A(%d件)" % n2
            else:
                c2 = "—"
            if n1 >= 5 and n2 >= 5:
                w = m1 if s1["rate"] >= s2["rate"] else m2
            else:
                w = "—"
            print("  %-25s %-18s %-18s %s" % (t, c1, c2, w))

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
