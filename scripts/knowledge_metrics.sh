#!/bin/bash
# knowledge_metrics.sh — 教訓効果メトリクス+淘汰候補検出
# Usage: bash scripts/knowledge_metrics.sh [--json] [--since YYYY-MM-DD] [--threshold N]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TSV_FILE="$SCRIPT_DIR/logs/lesson_tracking.tsv"
LESSONS_DIR="$SCRIPT_DIR/projects"

# デフォルト値
THRESHOLD=5
SINCE=""
JSON_OUTPUT=false
MODEL_OUTPUT=false
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
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

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
DATA_LINES=$(grep -cv '^\s*#\|^\s*$' "$TSV_FILE" 2>/dev/null || echo 0)
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

# === lesson ID → project 逆引きマップ構築 ===
lesson_project_map = {}
for project_dir in Path(lessons_dir).iterdir():
    lessons_file = project_dir / "lessons.yaml"
    if not lessons_file.is_file():
        continue
    project_name = project_dir.name
    with open(lessons_file, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith("- id:"):
                lid = line.split(":", 1)[1].strip()
                lesson_project_map[lid] = project_name

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

# 注入≥threshold かつ 参照0回の教訓
elimination_candidates = []
for lid in sorted(inject_count.keys()):
    if inject_count[lid] >= threshold and ref_count.get(lid, 0) == 0:
        project = lesson_project_map.get(lid, "unknown")
        ninjas = sorted(inject_ninjas[lid])
        elimination_candidates.append({
            "lesson_id": lid,
            "project": project,
            "inject_count": inject_count[lid],
            "ref_count": 0,
            "ninjas": ninjas,
        })

# === 出力(2): Δ（教訓効果の差分） ===
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

# === 出力 ===
if json_output:
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

    result = {
        "elimination_candidates": elimination_candidates,
        "delta": delta,
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
    print("=== Δ（教訓効果） ===")
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
    # サンプル不足警告
    warnings = []
    if 0 < with_lessons_total < 10:
        warnings.append(f"N={with_lessons_total} (教訓あり)")
    if 0 < without_lessons_total < 10:
        warnings.append(f"N={without_lessons_total} (教訓なし)")
    if warnings:
        print(f"⚠ サンプル不足（参考値）: {', '.join(warnings)}")
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
