#!/bin/bash
# knowledge_metrics.sh — 教訓効果メトリクス+淘汰候補検出
# Usage: bash scripts/knowledge_metrics.sh [--json] [--since YYYY-MM-DD] [--threshold N] [--model] [--time]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TSV_FILE="$SCRIPT_DIR/logs/lesson_tracking.tsv"
LESSONS_DIR="$SCRIPT_DIR/projects"

# デフォルト値
THRESHOLD=5
SINCE=""
JSON_OUTPUT=false
MODEL_OUTPUT=false
TIME_OUTPUT=false
SETTINGS_FILE="$SCRIPT_DIR/config/settings.yaml"

# 引数解析
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --since)
            SINCE="$2"
            shift 2
            ;;
        --threshold)
            THRESHOLD="$2"
            shift 2
            ;;
        --model)
            MODEL_OUTPUT=true
            shift
            ;;
        --time)
            TIME_OUTPUT=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# ─── --time モード: タスク所要時間集計 ───
if [ "$TIME_OUTPUT" = true ]; then
    python3 - "$SCRIPT_DIR" "$SETTINGS_FILE" <<'TIME_PYEOF'
import sys
import re
from datetime import datetime
from pathlib import Path
from collections import defaultdict

base_dir = Path(sys.argv[1])
settings_file = Path(sys.argv[2])
queue_tasks_dir = base_dir / "queue" / "tasks"
archive_tasks_dir = base_dir / "archive" / "tasks"

def strip_quotes(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value

def parse_task_yaml(yaml_path: Path):
    fields = {}
    pattern = re.compile(r"^\s*(task_id|assigned_to|task_type|deployed_at|completed_at):\s*(.+?)\s*$")
    try:
        for line in yaml_path.read_text(encoding="utf-8").splitlines():
            m = pattern.match(line)
            if not m:
                continue
            key = m.group(1)
            if key in fields:
                continue
            fields[key] = strip_quotes(m.group(2))
    except Exception:
        return None
    return fields

def parse_iso(ts: str):
    ts = ts.strip()
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    return datetime.fromisoformat(ts)

def normalize_task_type(task_type: str, task_id: str) -> str:
    t = (task_type or "").lower()
    if t in ("recon", "review", "impl"):
        return t
    if t in ("implement", "implementation"):
        return "impl"
    tid = (task_id or "").lower()
    if "_recon_" in tid:
        return "recon"
    if "_review_" in tid:
        return "review"
    if "_impl_" in tid:
        return "impl"
    return "unknown"

def load_ninja_models(path: Path):
    ninja_model = {}
    try:
        import yaml  # type: ignore
        settings = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        agents = settings.get("cli", {}).get("agents", {})
        for ninja, cfg in agents.items():
            if not isinstance(cfg, dict):
                continue
            if cfg.get("type") == "codex":
                ninja_model[ninja] = "codex"
            elif "sonnet" in str(cfg.get("model_name", "")).lower():
                ninja_model[ninja] = "sonnet"
            else:
                ninja_model[ninja] = "opus"
    except Exception:
        current_ninja = None
        in_agents = False
        for raw in path.read_text(encoding="utf-8").splitlines():
            if raw.strip() == "agents:" and raw.startswith("  "):
                in_agents = True
                continue
            if in_agents and re.match(r"^\s{2}[a-z_]+:", raw):
                in_agents = False
            if not in_agents:
                continue
            ninja_match = re.match(r"^\s{4}([a-z_]+):\s*$", raw)
            if ninja_match:
                current_ninja = ninja_match.group(1)
                if current_ninja not in ninja_model:
                    ninja_model[current_ninja] = "opus"
                continue
            if not current_ninja:
                continue
            if re.search(r"^\s{6}type:\s*codex\s*$", raw):
                ninja_model[current_ninja] = "codex"
            elif re.search(r"^\s{6}model_name:.*sonnet", raw):
                ninja_model[current_ninja] = "sonnet"
    return ninja_model

def list_yaml_files():
    files = []
    if queue_tasks_dir.is_dir():
        files.extend(sorted(queue_tasks_dir.glob("*.yaml")))
    if archive_tasks_dir.is_dir():
        files.extend(sorted(archive_tasks_dir.rglob("*.yaml")))
    return files

files = list_yaml_files()
ninja_model = load_ninja_models(settings_file) if settings_file.is_file() else {}
durations = []

for file_path in files:
    fields = parse_task_yaml(file_path)
    if not fields:
        continue
    deployed_at = fields.get("deployed_at")
    completed_at = fields.get("completed_at")
    if not deployed_at or not completed_at:
        continue
    try:
        start_dt = parse_iso(deployed_at)
        end_dt = parse_iso(completed_at)
        duration_min = (end_dt - start_dt).total_seconds() / 60.0
    except Exception:
        continue
    if duration_min < 0:
        continue
    task_id = fields.get("task_id", file_path.stem)
    assigned_to = fields.get("assigned_to", "unknown")
    task_type = normalize_task_type(fields.get("task_type", ""), task_id)
    source = "queue" if str(file_path).startswith(str(queue_tasks_dir)) else "archive"
    durations.append({
        "task_id": task_id,
        "assigned_to": assigned_to,
        "model": ninja_model.get(assigned_to, "opus"),
        "task_type": task_type,
        "duration_min": duration_min,
        "source": source,
    })

# 同一task_idの重複はqueue優先で1件化
dedup = {}
for item in durations:
    tid = item["task_id"]
    if tid not in dedup:
        dedup[tid] = item
    elif dedup[tid]["source"] == "archive" and item["source"] == "queue":
        dedup[tid] = item
durations = list(dedup.values())

if not durations:
    print("=== 所要時間 ===")
    print("所要時間: データなし（deployed_at/completed_at付きサブタスクなし）")
    sys.exit(0)

def avg_by(key):
    bucket = defaultdict(list)
    for item in durations:
        bucket[item[key]].append(item["duration_min"])
    return {k: (sum(v) / len(v), len(v)) for k, v in bucket.items()}

ninja_avg = avg_by("assigned_to")
model_avg = avg_by("model")
task_type_avg = avg_by("task_type")
slowest = sorted(durations, key=lambda x: x["duration_min"], reverse=True)[:5]

print("=== 所要時間 ===")
print("1) 忍者別平均所要時間（分）")
for ninja in sorted(ninja_avg.keys()):
    avg, n = ninja_avg[ninja]
    print(f"  - {ninja}: {avg:.1f}分 (N={n})")

print("2) モデル別平均所要時間（分）")
for model in ["opus", "sonnet", "codex"]:
    if model in model_avg:
        avg, n = model_avg[model]
        print(f"  - {model}: {avg:.1f}分 (N={n})")
for model in sorted(k for k in model_avg.keys() if k not in {"opus", "sonnet", "codex"}):
    avg, n = model_avg[model]
    print(f"  - {model}: {avg:.1f}分 (N={n})")

print("3) タスク種別別平均所要時間（分）")
for t in ["recon", "impl", "review"]:
    if t in task_type_avg:
        avg, n = task_type_avg[t]
        print(f"  - {t}: {avg:.1f}分 (N={n})")
for t in sorted(k for k in task_type_avg.keys() if k not in {"recon", "impl", "review"}):
    avg, n = task_type_avg[t]
    print(f"  - {t}: {avg:.1f}分 (N={n})")

print("4) 最遅タスクTOP5")
for idx, item in enumerate(slowest, start=1):
    print(f"  {idx}. {item['task_id']}: {item['duration_min']:.1f}分")
TIME_PYEOF
    exit 0
fi

# TSVファイル存在チェック
if [ ! -f "$TSV_FILE" ] || [ ! -s "$TSV_FILE" ]; then
    if [ "$JSON_OUTPUT" = true ]; then
        echo '{"error": null, "message": "データ不足: lesson_tracking.tsvが空または未作成", "elimination_candidates": [], "delta": {}}'
    else
        echo "データ不足: lesson_tracking.tsvが空または未作成"
    fi
    exit 0
fi

# データ行があるかチェック（#コメント行とヘッダのみの場合）
DATA_LINES=$(awk '!/^\s*#/ && !/^\s*$/{c++} END{print c+0}' "$TSV_FILE" 2>/dev/null)
if [ "$DATA_LINES" -eq 0 ]; then
    if [ "$JSON_OUTPUT" = true ]; then
        echo '{"error": null, "message": "データ不足: lesson_tracking.tsvが空または未作成", "elimination_candidates": [], "delta": {}}'
    else
        echo "データ不足: lesson_tracking.tsvが空または未作成"
    fi
    exit 0
fi

# Python3でTSV解析+集計
python3 - "$TSV_FILE" "$LESSONS_DIR" "$THRESHOLD" "$SINCE" "$JSON_OUTPUT" <<'PYEOF'
import sys
import csv
import json
import os
from collections import defaultdict
from pathlib import Path

tsv_file = sys.argv[1]
lessons_dir = sys.argv[2]
threshold = int(sys.argv[3])
since = sys.argv[4] if sys.argv[4] else None
json_output = sys.argv[5] == "true"

# === lesson ID → project 逆引きマップ構築 + deprecated集合 ===
lesson_project_map = {}
deprecated_lessons = set()
for project_dir in Path(lessons_dir).iterdir():
    lessons_file = project_dir / "lessons.yaml"
    if not lessons_file.is_file():
        continue
    project_name = project_dir.name
    current_lid = None
    with open(lessons_file, "r") as f:
        for line in f:
            stripped = line.strip()
            if stripped.startswith("- id:"):
                current_lid = stripped.split(":", 1)[1].strip()
                lesson_project_map[current_lid] = project_name
            elif current_lid and stripped.startswith("deprecated:") and "true" in stripped.lower():
                deprecated_lessons.add(current_lid)

# === TSVデータ読み込み ===
rows = []
with open(tsv_file, "r") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 6:
            continue
        timestamp, cmd_id, ninja, gate_result, injected_ids, referenced_ids = parts[:6]
        # --since フィルタ
        if since and timestamp < since:
            continue
        rows.append({
            "timestamp": timestamp,
            "cmd_id": cmd_id,
            "ninja": ninja,
            "gate_result": gate_result,
            "injected_ids": injected_ids,
            "referenced_ids": referenced_ids,
        })

if not rows:
    if json_output:
        print(json.dumps({
            "error": None,
            "message": "データ不足: lesson_tracking.tsvが空または未作成",
            "elimination_candidates": [],
            "delta": {}
        }))
    else:
        print("データ不足: lesson_tracking.tsvが空または未作成")
    sys.exit(0)

# === 出力(1): 淘汰候補リスト ===
# 注入回数: injected_idsに含まれる各lesson IDの出現回数
# 参照回数: referenced_idsに含まれる各lesson IDの出現回数
inject_count = defaultdict(int)
inject_ninjas = defaultdict(set)
ref_count = defaultdict(int)

for row in rows:
    if row["injected_ids"] != "none":
        for lid in row["injected_ids"].split(","):
            lid = lid.strip()
            if lid:
                inject_count[lid] += 1
                inject_ninjas[lid].add(row["ninja"])
    if row["referenced_ids"] != "none":
        for lid in row["referenced_ids"].split(","):
            lid = lid.strip()
            if lid:
                ref_count[lid] += 1

# 注入≥threshold かつ 参照0回の教訓（deprecated済みは除外）
elimination_candidates = []
for lid in sorted(inject_count.keys()):
    if inject_count[lid] >= threshold and ref_count.get(lid, 0) == 0:
        if lid in deprecated_lessons:
            continue
        project = lesson_project_map.get(lid, "unknown")
        ninjas = sorted(inject_ninjas[lid])
        elimination_candidates.append({
            "lesson_id": lid,
            "project": project,
            "inject_count": inject_count[lid],
            "ref_count": 0,
            "ninjas": ninjas,
        })

# === 出力(2): Raw Δ（教訓効果の差分 — 既存互換） ===
with_lessons_total = 0
with_lessons_clear = 0
without_lessons_total = 0
without_lessons_clear = 0

for row in rows:
    is_clear = row["gate_result"] == "CLEAR"
    if row["injected_ids"] != "none":
        with_lessons_total += 1
        if is_clear:
            with_lessons_clear += 1
    else:
        without_lessons_total += 1
        if is_clear:
            without_lessons_clear += 1

# === 正規化処理 (AC1-AC4) ===
# AC2: テストcmd除外 (cmd_test_* / cmd_TEST*)
test_cmd_count = 0
non_test_rows = []
for row in rows:
    cid = row["cmd_id"]
    if cid.startswith("cmd_test_") or cid.startswith("cmd_TEST"):
        test_cmd_count += 1
    else:
        non_test_rows.append(row)

# AC4: ninja=none/空行フィルタ
ninja_none_count = 0
clean_rows = []
for row in non_test_rows:
    if row["ninja"] == "none" or not row["ninja"].strip():
        ninja_none_count += 1
    else:
        clean_rows.append(row)

# gate_resultが有効な値のみ保持（ヘッダ行混入防止）
valid_rows = [r for r in clean_rows if r["gate_result"] in ("CLEAR", "BLOCK")]

# AC1: cmd単位dedup (CLEAR優先で最終結果のみ採用)
pre_dedup_count = len(valid_rows)
cmd_final = {}
for row in valid_rows:
    cid = row["cmd_id"]
    if cid not in cmd_final:
        cmd_final[cid] = row
    else:
        existing = cmd_final[cid]
        if row["gate_result"] == "CLEAR":
            cmd_final[cid] = row
        elif existing["gate_result"] != "CLEAR":
            cmd_final[cid] = row  # 最新BLOCKを保持
dedup_rows = list(cmd_final.values())

# AC3: 構造BLOCK分離 — gate_metrics.logからBLOCK理由取得
STRUCTURAL_PATTERNS = ["missing_gate", "archive_gate", "lesson_gate", "review_gate"]
gate_log_path = os.path.join(os.path.dirname(tsv_file), "gate_metrics.log")
cmd_block_reasons = defaultdict(list)
if os.path.isfile(gate_log_path):
    with open(gate_log_path, "r") as gf:
        for gline in gf:
            gline = gline.strip()
            if not gline:
                continue
            gparts = gline.split("\t")
            if len(gparts) >= 4 and gparts[2] == "BLOCK":
                cmd_block_reasons[gparts[1]].append(gparts[3])

def is_structural_block(cmd_id):
    """cmd_idの最終BLOCK理由が全て構造的パターンならTrue."""
    reasons = cmd_block_reasons.get(cmd_id, [])
    if not reasons:
        return False
    last_reason = reasons[-1]
    individual = [r.strip() for r in last_reason.split("|")]
    return all(
        any(pat in reason for pat in STRUCTURAL_PATTERNS)
        for reason in individual
    )

structural_block_count = 0
quality_rows = []
for row in dedup_rows:
    if row["gate_result"] == "BLOCK" and is_structural_block(row["cmd_id"]):
        structural_block_count += 1
    else:
        quality_rows.append(row)

# Normalized Δ計算
n_with_total = 0
n_with_clear = 0
n_without_total = 0
n_without_clear = 0
for row in quality_rows:
    is_clear = row["gate_result"] == "CLEAR"
    if row["injected_ids"] != "none":
        n_with_total += 1
        if is_clear:
            n_with_clear += 1
    else:
        n_without_total += 1
        if is_clear:
            n_without_clear += 1

# === 出力 ===
if json_output:
    # Raw delta (既存互換)
    delta = {}
    if with_lessons_total > 0:
        delta["with_lessons_rate"] = round(with_lessons_clear / with_lessons_total * 100, 1)
        delta["with_lessons_n"] = with_lessons_total
        delta["with_lessons_clear"] = with_lessons_clear
    if without_lessons_total > 0:
        delta["without_lessons_rate"] = round(without_lessons_clear / without_lessons_total * 100, 1)
        delta["without_lessons_n"] = without_lessons_total
        delta["without_lessons_clear"] = without_lessons_clear
    if with_lessons_total > 0 and without_lessons_total > 0:
        delta["delta_pp"] = round(
            (with_lessons_clear / with_lessons_total - without_lessons_clear / without_lessons_total) * 100, 1
        )
    delta["sample_warning"] = []
    if with_lessons_total > 0 and with_lessons_total < 10:
        delta["sample_warning"].append(f"教訓あり N={with_lessons_total}")
    if without_lessons_total > 0 and without_lessons_total < 10:
        delta["sample_warning"].append(f"教訓なし N={without_lessons_total}")

    # Normalized delta
    normalized_delta = {}
    normalized_delta["filters"] = {
        "test_cmd_excluded": test_cmd_count,
        "ninja_none_excluded": ninja_none_count,
        "pre_dedup_rows": pre_dedup_count,
        "post_dedup_rows": len(dedup_rows),
        "structural_block_excluded": structural_block_count,
    }
    if n_with_total > 0:
        normalized_delta["with_lessons_rate"] = round(n_with_clear / n_with_total * 100, 1)
        normalized_delta["with_lessons_n"] = n_with_total
        normalized_delta["with_lessons_clear"] = n_with_clear
    if n_without_total > 0:
        normalized_delta["without_lessons_rate"] = round(n_without_clear / n_without_total * 100, 1)
        normalized_delta["without_lessons_n"] = n_without_total
        normalized_delta["without_lessons_clear"] = n_without_clear
    if n_with_total > 0 and n_without_total > 0:
        normalized_delta["delta_pp"] = round(
            (n_with_clear / n_with_total - n_without_clear / n_without_total) * 100, 1
        )
    normalized_delta["sample_warning"] = []
    if n_with_total > 0 and n_with_total < 10:
        normalized_delta["sample_warning"].append(f"教訓あり N={n_with_total}")
    if n_without_total > 0 and n_without_total < 10:
        normalized_delta["sample_warning"].append(f"教訓なし N={n_without_total}")

    # 注入率・参照率計算 (既存互換)
    total_rows = with_lessons_total + without_lessons_total
    inject_rate_pct = round(with_lessons_total / total_rows * 100, 1) if total_rows > 0 else None
    ref_with_lesson = sum(
        1 for r in rows
        if r["injected_ids"] != "none" and r["referenced_ids"] != "none"
    )
    ref_rate_pct = round(ref_with_lesson / with_lessons_total * 100, 1) if with_lessons_total > 0 else None

    result = {
        "elimination_candidates": elimination_candidates,
        "delta": delta,
        "normalized_delta": normalized_delta,
        "inject_rate": inject_rate_pct,
        "ref_rate": ref_rate_pct,
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
else:
    # テキスト出力
    print("=== 淘汰候補 ===")
    if elimination_candidates:
        print(f"{'LESSON_ID':<12}{'PROJECT':<12}{'注入回数':<10}{'参照回数':<10}注入先忍者")
        for c in elimination_candidates:
            ninjas_str = ",".join(c["ninjas"])
            print(f"{c['lesson_id']:<12}{c['project']:<12}{c['inject_count']:<10}{c['ref_count']:<10}{ninjas_str}")
    else:
        print(f"(注入{threshold}回以上・参照0回の教訓なし)")
    print()
    print("=== Δ（教訓効果）[raw] ===")
    if with_lessons_total > 0:
        rate_with = with_lessons_clear / with_lessons_total * 100
        print(f"教訓あり CLEAR率: {rate_with:.1f}% ({with_lessons_clear}/{with_lessons_total})")
    else:
        print("教訓あり CLEAR率: データなし")
    if without_lessons_total > 0:
        rate_without = without_lessons_clear / without_lessons_total * 100
        print(f"教訓なし CLEAR率: {rate_without:.1f}% ({without_lessons_clear}/{without_lessons_total})")
    else:
        print("教訓なし CLEAR率: データなし")
    if with_lessons_total > 0 and without_lessons_total > 0:
        delta_pp = (with_lessons_clear / with_lessons_total - without_lessons_clear / without_lessons_total) * 100
        sign = "+" if delta_pp >= 0 else ""
        print(f"Δ = {sign}{delta_pp:.1f}pp")
    else:
        print("Δ = 算出不可（片方のデータなし）")
    warnings = []
    if 0 < with_lessons_total < 10:
        warnings.append(f"N={with_lessons_total} (教訓あり)")
    if 0 < without_lessons_total < 10:
        warnings.append(f"N={without_lessons_total} (教訓なし)")
    if warnings:
        print(f"⚠ サンプル不足（参考値）: {', '.join(warnings)}")
    print()
    print("=== Δ（教訓効果）[normalized] ===")
    print(f"フィルタ: テストcmd除外={test_cmd_count}件, ninja=none除外={ninja_none_count}件, "
          f"cmd dedup={pre_dedup_count}→{len(dedup_rows)}件, 構造BLOCK除外={structural_block_count}件")
    if n_with_total > 0:
        rate_with_n = n_with_clear / n_with_total * 100
        print(f"教訓あり CLEAR率: {rate_with_n:.1f}% ({n_with_clear}/{n_with_total})")
    else:
        print("教訓あり CLEAR率: データなし")
    if n_without_total > 0:
        rate_without_n = n_without_clear / n_without_total * 100
        print(f"教訓なし CLEAR率: {rate_without_n:.1f}% ({n_without_clear}/{n_without_total})")
    else:
        print("教訓なし CLEAR率: データなし")
    if n_with_total > 0 and n_without_total > 0:
        delta_pp_n = (n_with_clear / n_with_total - n_without_clear / n_without_total) * 100
        sign_n = "+" if delta_pp_n >= 0 else ""
        print(f"Δ = {sign_n}{delta_pp_n:.1f}pp")
    else:
        print("Δ = 算出不可（片方のデータなし）")
    n_warnings = []
    if 0 < n_with_total < 10:
        n_warnings.append(f"N={n_with_total} (教訓あり)")
    if 0 < n_without_total < 10:
        n_warnings.append(f"N={n_without_total} (教訓なし)")
    if n_warnings:
        print(f"⚠ サンプル不足（参考値）: {', '.join(n_warnings)}")
PYEOF

# ─── --model モード: モデル別CLEAR率集計 ───
if [ "$MODEL_OUTPUT" = true ]; then
    if [ ! -f "$SETTINGS_FILE" ]; then
        echo "ERROR: settings.yaml not found: $SETTINGS_FILE" >&2
        exit 1
    fi

    python3 - "$TSV_FILE" "$SETTINGS_FILE" "$SINCE" <<'MODEL_PYEOF'
import sys
import os

tsv_file = sys.argv[1]
settings_file = sys.argv[2]
since = sys.argv[3] if sys.argv[3] else None

# === settings.yaml読み込み: ninja→model マッピング ===
ninja_model = {}
try:
    import yaml
    with open(settings_file, encoding="utf-8") as f:
        settings = yaml.safe_load(f)
    agents = settings.get("cli", {}).get("agents", {})
    for name, cfg in agents.items():
        if not isinstance(cfg, dict):
            continue
        if cfg.get("type") == "codex":
            ninja_model[name] = "codex"
        elif "sonnet" in str(cfg.get("model_name", "")):
            ninja_model[name] = "sonnet"
        else:
            ninja_model[name] = "opus"
except ImportError:
    # yaml未使用時フォールバック: grep+awk
    import subprocess
    result = subprocess.run(
        ["awk", "/^    [a-z]+:/{name=$1; gsub(/:/, \"\", name)} "
         "/type: codex/{m[name]=\"codex\"} "
         "/model_name:.*sonnet/{m[name]=\"sonnet\"} "
         "END{for(n in m) print n, m[n]}", settings_file],
        capture_output=True, text=True
    )
    for line in result.stdout.strip().split("\n"):
        parts = line.split()
        if len(parts) == 2:
            ninja_model[parts[0]] = parts[1]

def get_model(ninja_name):
    return ninja_model.get(ninja_name, "opus")

# === TSVデータ読み込み ===
from collections import defaultdict

rows = []
with open(tsv_file, "r") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("timestamp"):
            continue
        parts = line.split("\t")
        if len(parts) < 6:
            continue
        timestamp, cmd_id, ninja_str, gate_result = parts[0], parts[1], parts[2], parts[3]
        task_type = parts[6] if len(parts) >= 7 else "unknown"
        if since and timestamp < since:
            continue
        # ninjaフィールドはカンマ区切り（複数名）
        ninja_names = [n.strip() for n in ninja_str.split(",") if n.strip()]
        for ninja_name in ninja_names:
            model = get_model(ninja_name)
            rows.append({
                "model": model,
                "gate_result": gate_result,
                "task_type": task_type,
            })

if not rows:
    print("データ不足: モデル別集計に十分なデータなし")
    sys.exit(0)

# === テーブル1: モデル別CLEAR率 ===
model_stats = defaultdict(lambda: {"clear": 0, "block": 0})
for r in rows:
    if r["gate_result"] == "CLEAR":
        model_stats[r["model"]]["clear"] += 1
    elif r["gate_result"] == "BLOCK":
        model_stats[r["model"]]["block"] += 1

print("=== モデル別CLEAR率 ===")
print(f"{'モデル':<10}{'CLEAR':<8}{'BLOCK':<8}{'CLEAR率':<12}{'N':<6}")
for model in ["opus", "sonnet", "codex"]:
    s = model_stats.get(model, {"clear": 0, "block": 0})
    n = s["clear"] + s["block"]
    if n == 0:
        print(f"{model:<10}{'0':<8}{'0':<8}{'---':<12}{'0':<6}")
    elif n < 10:
        rate = s["clear"] / n * 100
        print(f"{model:<10}{s['clear']:<8}{s['block']:<8}{rate:.1f}% ⚠データ不足  {n:<6}")
    else:
        rate = s["clear"] / n * 100
        print(f"{model:<10}{s['clear']:<8}{s['block']:<8}{rate:.1f}%{'':7}{n:<6}")

# === テーブル2: モデル×種別CLEAR率 ===
print()
print("=== モデル×種別CLEAR率 ===")
model_type_stats = defaultdict(lambda: defaultdict(lambda: {"clear": 0, "block": 0}))
for r in rows:
    tt = r["task_type"]
    if tt == "unknown":
        continue
    if r["gate_result"] == "CLEAR":
        model_type_stats[r["model"]][tt]["clear"] += 1
    elif r["gate_result"] == "BLOCK":
        model_type_stats[r["model"]][tt]["block"] += 1

# 存在する種別を収集
all_types = sorted({r["task_type"] for r in rows if r["task_type"] != "unknown"})
if not all_types:
    print("(task_typeデータなし — 将来データで蓄積)")
else:
    header = f"{'モデル':<10}" + "".join(f"{t:<12}" for t in all_types)
    print(header)
    for model in ["opus", "sonnet", "codex"]:
        cells = []
        for tt in all_types:
            s = model_type_stats[model][tt]
            n = s["clear"] + s["block"]
            if n == 0:
                cells.append(f"{'---':<12}")
            elif n < 10:
                rate = s["clear"] / n * 100
                cells.append(f"{rate:.0f}%(N={n})⚠  ")
            else:
                rate = s["clear"] / n * 100
                cells.append(f"{rate:.0f}%(N={n})    ")
        print(f"{model:<10}" + "".join(cells))

# === 所要時間 ===
print()
print("=== 所要時間 ===")
print("所要時間: データ蓄積中（deployed_at/completed_atの記録整備後に算出可能）")

MODEL_PYEOF
fi
