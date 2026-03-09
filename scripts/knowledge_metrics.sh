#!/bin/bash
# knowledge_metrics.sh — 教訓効果メトリクス+淘汰候補検出
# Usage: bash scripts/knowledge_metrics.sh [--json] [--since YYYY-MM-DD] [--threshold N] [--model] [--time] [--by-project] [--by-model]

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
BY_PROJECT_OUTPUT=false
BY_MODEL_BREAKDOWN_OUTPUT=false
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
        --by-project)
            BY_PROJECT_OUTPUT=true
            shift
            ;;
        --by-model)
            BY_MODEL_BREAKDOWN_OUTPUT=true
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
            model_name = str(cfg.get("model_name", "")).lower()
            if cfg.get("type") == "codex":
                ninja_model[ninja] = "codex"
            elif "haiku" in model_name:
                ninja_model[ninja] = "haiku"
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
            elif re.search(r"^\s{6}model_name:.*haiku", raw):
                ninja_model[current_ninja] = "haiku"
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
for model in ["opus", "codex", "haiku"]:
    if model in model_avg:
        avg, n = model_avg[model]
        print(f"  - {model}: {avg:.1f}分 (N={n})")
for model in sorted(k for k in model_avg.keys() if k not in {"opus", "codex", "haiku"}):
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
python3 - "$TSV_FILE" "$LESSONS_DIR" "$THRESHOLD" "$SINCE" "$JSON_OUTPUT" "$BY_PROJECT_OUTPUT" "$BY_MODEL_BREAKDOWN_OUTPUT" "$SCRIPT_DIR" <<'PYEOF'
import sys
import json
import os
from collections import defaultdict
from pathlib import Path

tsv_file = sys.argv[1]
lessons_dir = sys.argv[2]
threshold = int(sys.argv[3])
since = sys.argv[4] if sys.argv[4] else None
json_output = sys.argv[5] == "true"
by_project_output = sys.argv[6] == "true"
by_model_output = sys.argv[7] == "true"
base_dir = Path(sys.argv[8])

try:
    import yaml as _yaml
except Exception:
    _yaml = None

def split_csv(value):
    text = str(value or "").strip()
    if not text or text == "none":
        return []
    return [item.strip() for item in text.split(",") if item.strip()]

def to_int(value):
    try:
        return int(value or 0)
    except Exception:
        return 0

def percent(numerator, denominator):
    if denominator <= 0:
        return None
    return round(numerator / denominator * 100, 1)

def dedup_cmd_rows(items):
    final = {}
    for item in items:
        cmd_id = item["cmd_id"]
        existing = final.get(cmd_id)
        if existing is None:
            final[cmd_id] = item
            continue
        if item["gate_result"] == "CLEAR":
            final[cmd_id] = item
        elif existing["gate_result"] != "CLEAR":
            final[cmd_id] = item
    return list(final.values())

def load_cmd_metadata(root_dir):
    metadata = {}
    candidates = [root_dir / "queue" / "shogun_to_karo.yaml"]
    archive_dir = root_dir / "queue" / "archive" / "cmds"
    if archive_dir.is_dir():
        candidates.extend(sorted(archive_dir.glob("*.yaml")))

    if _yaml is None:
        return metadata

    for path in candidates:
        if not path.is_file():
            continue
        try:
            data = _yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        except Exception:
            continue

        commands = []
        if isinstance(data, dict):
            if isinstance(data.get("commands"), list):
                commands = data.get("commands", [])
            elif "id" in data:
                commands = [data]
        elif isinstance(data, list):
            commands = data

        for command in commands:
            if not isinstance(command, dict):
                continue
            cmd_id = str(command.get("id", "")).strip()
            if not cmd_id:
                continue
            metadata[cmd_id] = {
                "project": str(command.get("project", "unknown") or "unknown").strip() or "unknown",
                "title": str(command.get("title", "") or "").strip(),
            }
    return metadata

def load_gate_rows(gate_log_path):
    records = []
    if not os.path.isfile(gate_log_path):
        return records
    with open(gate_log_path, "r", encoding="utf-8") as gf:
        for raw in gf:
            line = raw.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) < 3:
                continue
            timestamp = parts[0]
            if since and timestamp < since:
                continue
            records.append({
                "timestamp": timestamp,
                "cmd_id": parts[1],
                "gate_result": parts[2],
                "detail": parts[3] if len(parts) >= 4 else "",
                "task_type": parts[4] if len(parts) >= 5 else "unknown",
                "models_csv": parts[5] if len(parts) >= 6 else "unknown",
                "bloom_levels": parts[6] if len(parts) >= 7 else "unknown",
                "injected_ids": parts[7] if len(parts) >= 8 else "none",
                "title": parts[8] if len(parts) >= 9 else "",
            })
    return records

def load_lesson_catalog(root_dir):
    lesson_catalog = {}
    deprecated = set()
    if _yaml is None:
        return lesson_catalog, deprecated

    root = Path(root_dir)
    if not root.is_dir():
        return lesson_catalog, deprecated

    for project_dir in root.iterdir():
        lessons_file = project_dir / "lessons.yaml"
        if not lessons_file.is_file():
            continue
        try:
            payload = _yaml.safe_load(lessons_file.read_text(encoding="utf-8")) or {}
        except Exception:
            continue
        lessons = payload.get("lessons", []) if isinstance(payload, dict) else []
        for lesson in lessons:
            if not isinstance(lesson, dict):
                continue
            lesson_id = str(lesson.get("id", "")).strip()
            if not lesson_id:
                continue
            is_deprecated = str(lesson.get("status", "confirmed")).lower() == "deprecated" or bool(lesson.get("deprecated", False))
            if is_deprecated:
                deprecated.add(lesson_id)
            lesson_catalog[lesson_id] = {
                "id": lesson_id,
                "project": project_dir.name,
                "title": str(lesson.get("title", "") or "").strip() or lesson_id,
                "injection_count": to_int(lesson.get("injection_count", 0)),
                "helpful_count": to_int(lesson.get("helpful_count", 0)),
                "deprecated": is_deprecated,
            }
    return lesson_catalog, deprecated

# === lesson ID → metadata 逆引きマップ構築 + deprecated集合 ===
lesson_catalog, deprecated_lessons = load_lesson_catalog(lessons_dir)
lesson_project_map = {lid: meta["project"] for lid, meta in lesson_catalog.items()}

# === lesson_tracking.tsv 読み込み ===
rows = []
with open(tsv_file, "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("timestamp"):
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
            "task_type": parts[6] if len(parts) >= 7 else "unknown",
        })

if not rows:
    if json_output:
        print(json.dumps({
            "error": None,
            "message": "データ不足: lesson_tracking.tsvが空または未作成",
            "elimination_candidates": [],
            "delta": {},
            "normalized_delta": {},
            "inject_rate": None,
            "ref_rate": None,
            "lesson_effectiveness": None,
            "problem_lessons": 0,
            "top_helpful": [],
            "bottom_lessons": [],
            "by_project": [],
            "by_model": [],
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
dedup_rows = dedup_cmd_rows(valid_rows)

# AC3: 構造BLOCK分離 — gate_metrics.logからBLOCK理由取得
STRUCTURAL_PATTERNS = ["missing_gate", "archive_gate", "lesson_gate", "review_gate"]
gate_log_path = os.path.join(os.path.dirname(tsv_file), "gate_metrics.log")
gate_rows = load_gate_rows(gate_log_path)
dedup_gate_rows = {row["cmd_id"]: row for row in dedup_cmd_rows([r for r in gate_rows if r["gate_result"] in ("CLEAR", "BLOCK")])}
cmd_block_reasons = defaultdict(list)
if os.path.isfile(gate_log_path):
    with open(gate_log_path, "r", encoding="utf-8") as gf:
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

# 共通集計
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

normalized_delta = {
    "filters": {
        "test_cmd_excluded": test_cmd_count,
        "ninja_none_excluded": ninja_none_count,
        "pre_dedup_rows": pre_dedup_count,
        "post_dedup_rows": len(dedup_rows),
        "structural_block_excluded": structural_block_count,
    }
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

total_rows = with_lessons_total + without_lessons_total
inject_rate_pct = round(with_lessons_total / total_rows * 100, 1) if total_rows > 0 else None
ref_with_lesson = sum(
    1 for r in rows
    if r["injected_ids"] != "none" and r["referenced_ids"] != "none"
)
ref_rate_pct = round(ref_with_lesson / with_lessons_total * 100, 1) if with_lessons_total > 0 else None

dedup_inject_count = defaultdict(int)
dedup_ref_count = defaultdict(int)
for row in dedup_rows:
    for lesson_id in split_csv(row["injected_ids"]):
        dedup_inject_count[lesson_id] += 1
    for lesson_id in split_csv(row["referenced_ids"]):
        dedup_ref_count[lesson_id] += 1

active_lessons = []
for lesson_id, meta in lesson_catalog.items():
    if meta["deprecated"]:
        continue
    reference_total = max(meta["helpful_count"], dedup_ref_count.get(lesson_id, 0))
    injection_total = max(meta["injection_count"], dedup_inject_count.get(lesson_id, 0), reference_total)
    effect_rate = percent(reference_total, injection_total) if injection_total > 0 else None
    active_lessons.append({
        "id": lesson_id,
        "project": meta["project"],
        "title": meta["title"],
        "reference_count": reference_total,
        "injection_count": injection_total,
        "effectiveness_rate": effect_rate,
    })

helpful_positive = sum(1 for lesson in active_lessons if lesson["reference_count"] > 0)
problem_count = sum(
    1 for lesson in active_lessons
    if lesson["injection_count"] >= 10 and lesson["reference_count"] == 0
)
top_helpful = sorted(
    [lesson for lesson in active_lessons if lesson["reference_count"] > 0],
    key=lambda lesson: (-lesson["reference_count"], -lesson["injection_count"], lesson["id"])
)[:5]
bottom_lessons = sorted(
    [lesson for lesson in active_lessons if lesson["injection_count"] > 0],
    key=lambda lesson: (
        lesson["effectiveness_rate"] if lesson["effectiveness_rate"] is not None else 101.0,
        -lesson["injection_count"],
        lesson["id"],
    )
)[:5]
lesson_effectiveness_data = {
    "lesson_effectiveness": round(helpful_positive / len(active_lessons) * 100, 1) if active_lessons else 0.0,
    "problem_lessons": problem_count,
    "top_helpful": top_helpful,
    "bottom_lessons": bottom_lessons,
}

cmd_metadata = load_cmd_metadata(base_dir)
project_stats = defaultdict(lambda: {"total": 0, "injected": 0, "referenced": 0, "effective": 0})
for row in quality_rows:
    project = cmd_metadata.get(row["cmd_id"], {}).get("project", "unknown") or "unknown"
    injected = bool(split_csv(row["injected_ids"]))
    referenced = bool(split_csv(row["referenced_ids"]))
    project_stats[project]["total"] += 1
    if injected:
        project_stats[project]["injected"] += 1
        if referenced:
            project_stats[project]["referenced"] += 1
        if row["gate_result"] == "CLEAR":
            project_stats[project]["effective"] += 1

by_project = []
for project, stats in project_stats.items():
    by_project.append({
        "project": project,
        "inject_rate": percent(stats["injected"], stats["total"]),
        "ref_rate": percent(stats["referenced"], stats["injected"]),
        "effectiveness_rate": percent(stats["effective"], stats["injected"]),
        "n": stats["total"],
        "injected_n": stats["injected"],
    })
by_project.sort(key=lambda item: (item["project"] == "unknown", -(item["n"] or 0), item["project"]))

model_stats = defaultdict(lambda: {"total": 0, "injected": 0, "referenced": 0, "effective": 0})
for row in quality_rows:
    gate_meta = dedup_gate_rows.get(row["cmd_id"], {})
    models = split_csv(gate_meta.get("models_csv", "unknown")) or ["unknown"]
    injected = bool(split_csv(row["injected_ids"]))
    referenced = bool(split_csv(row["referenced_ids"]))
    for model_name in models:
        model_stats[model_name]["total"] += 1
        if injected:
            model_stats[model_name]["injected"] += 1
            if referenced:
                model_stats[model_name]["referenced"] += 1
            if row["gate_result"] == "CLEAR":
                model_stats[model_name]["effective"] += 1

def extract_model_family(label):
    low = label.lower().replace("-", " ").replace("_", " ")
    if "opus" in low and ("4.6" in low or "4 6" in low):
        return "opus_4_6"
    if "gpt" in low and ("5.4" in low or "5 4" in low):
        return "gpt_5_4"
    if "codex" in low and ("5.4" in low or "5 4" in low):
        return "gpt_5_4"
    import re as _re
    return _re.sub(r"[^a-z0-9]+", "_", low).strip("_") or "unknown"

def build_active_families_from_settings(settings_path, profiles_path):
    families = set()
    try:
        settings = _yaml.safe_load(Path(settings_path).read_text(encoding="utf-8")) or {} if _yaml else {}
        profiles_data = _yaml.safe_load(Path(profiles_path).read_text(encoding="utf-8")) or {} if _yaml else {}
    except Exception:
        return families
    cli = settings.get("cli", {}) if isinstance(settings, dict) else {}
    agents = cli.get("agents", {}) if isinstance(cli, dict) else {}
    default_cli = str(cli.get("default", "claude") or "claude")
    effort = str(settings.get("effort", "") or "").strip()
    profiles = profiles_data.get("profiles", {}) if isinstance(profiles_data, dict) else {}
    for ninja, cfg in agents.items():
        cli_type = default_cli
        model_label = ""
        has_explicit_model = False
        if isinstance(cfg, str):
            cli_type = cfg or default_cli
        elif isinstance(cfg, dict):
            cli_type = str(cfg.get("type") or default_cli)
            model_label = str(cfg.get("model_name") or "")
            has_explicit_model = bool(model_label.strip())
        if not model_label.strip():
            profile = profiles.get(cli_type, {}) if isinstance(profiles, dict) else {}
            model_label = str(profile.get("display_name") or cli_type or "")
        if has_explicit_model and effort and effort not in model_label.split():
            model_label = f"{model_label} {effort}"
        families.add(extract_model_family(model_label.strip()))
    return families

settings_path = base_dir / "config" / "settings.yaml"
profiles_path = base_dir / "config" / "cli_profiles.yaml"
active_families = build_active_families_from_settings(settings_path, profiles_path)

by_model = []
for model_name, stats in model_stats.items():
    if model_name == "unknown" or extract_model_family(model_name) not in active_families:
        continue
    by_model.append({
        "model": model_name,
        "display_name": model_name.replace("_", " "),
        "ref_rate": percent(stats["referenced"], stats["injected"]),
        "effectiveness_rate": percent(stats["effective"], stats["injected"]),
        "n": stats["total"],
        "injected_n": stats["injected"],
    })
by_model.sort(key=lambda item: (item["model"] == "unknown", -(item["n"] or 0), item["display_name"].lower()))

# === 出力 ===
if json_output:
    result = {
        "elimination_candidates": elimination_candidates,
        "delta": delta,
        "normalized_delta": normalized_delta,
        "inject_rate": inject_rate_pct,
        "ref_rate": ref_rate_pct,
        "lesson_effectiveness": lesson_effectiveness_data.get("lesson_effectiveness"),
        "problem_lessons": lesson_effectiveness_data.get("problem_lessons", 0),
        "top_helpful": lesson_effectiveness_data.get("top_helpful", []),
        "bottom_lessons": lesson_effectiveness_data.get("bottom_lessons", []),
        "by_project": by_project if by_project_output else [],
        "by_model": by_model if by_model_output else [],
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

    if by_project_output:
        print()
        print("=== PJ別注入率・効果率 ===")
        print(f"{'PJ':<18}{'注入率':<10}{'参照率':<10}{'効果率':<10}{'N':<6}")
        for item in by_project:
            print(
                f"{item['project']:<18}"
                f"{(f'{item['inject_rate']:.1f}%' if item['inject_rate'] is not None else '—'):<10}"
                f"{(f'{item['ref_rate']:.1f}%' if item['ref_rate'] is not None else '—'):<10}"
                f"{(f'{item['effectiveness_rate']:.1f}%' if item['effectiveness_rate'] is not None else '—'):<10}"
                f"{item['n']:<6}"
            )

    if by_model_output:
        print()
        print("=== モデル別参照率・効果率 ===")
        print(f"{'モデル':<26}{'参照率':<10}{'効果率':<10}{'N':<6}")
        for item in sorted(by_model, key=lambda row: (-row["n"], row["display_name"].lower())):
            print(
                f"{item['display_name']:<26}"
                f"{(f'{item['ref_rate']:.1f}%' if item['ref_rate'] is not None else '—'):<10}"
                f"{(f'{item['effectiveness_rate']:.1f}%' if item['effectiveness_rate'] is not None else '—'):<10}"
                f"{item['n']:<6}"
            )

    print()
    print("=== Top 5 有効教訓 ===")
    if top_helpful:
        print(f"{'教訓':<10}{'PJ':<14}{'参照回数':<10}{'注入回数':<10}{'効果率':<10}")
        for lesson in top_helpful:
            effect_text = f"{lesson['effectiveness_rate']:.1f}%" if lesson["effectiveness_rate"] is not None else "—"
            print(
                f"{lesson['id']:<10}{lesson['project']:<14}{lesson['reference_count']:<10}"
                f"{lesson['injection_count']:<10}{effect_text:<10}"
            )
    else:
        print("(有効教訓なし)")

    print()
    print("=== Bottom 5 低効果教訓 ===")
    if bottom_lessons:
        print(f"{'教訓':<10}{'PJ':<14}{'参照回数':<10}{'注入回数':<10}{'効果率':<10}")
        for lesson in bottom_lessons:
            effect_text = f"{lesson['effectiveness_rate']:.1f}%" if lesson["effectiveness_rate"] is not None else "—"
            print(
                f"{lesson['id']:<10}{lesson['project']:<14}{lesson['reference_count']:<10}"
                f"{lesson['injection_count']:<10}{effect_text:<10}"
            )
    else:
        print("(低効果教訓なし)")
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
        model_name = str(cfg.get("model_name", "")).lower()
        if cfg.get("type") == "codex":
            ninja_model[name] = "codex"
        elif "haiku" in model_name:
            ninja_model[name] = "haiku"
        else:
            ninja_model[name] = "opus"
except ImportError:
    # yaml未使用時フォールバック: grep+awk
    import subprocess
    result = subprocess.run(
        ["awk", "/^    [a-z]+:/{name=$1; gsub(/:/, \"\", name)} "
         "/type: codex/{m[name]=\"codex\"} "
         "/model_name:.*haiku/{m[name]=\"haiku\"} "
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
for model in ["opus", "codex", "haiku"]:
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
    for model in ["opus", "codex", "haiku"]:
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
