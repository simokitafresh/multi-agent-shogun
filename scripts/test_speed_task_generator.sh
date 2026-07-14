#!/usr/bin/env bash
# test_speed_task_generator.sh — timing ledgerから未攻略unit速度タスクを生成/配備する
set -euo pipefail

ROOT="${SHOGUN_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LEDGER="${TEST_TIMING_LEDGER:-$ROOT/logs/test_timing_ledger.tsv}"
OUT_DIR="${TEST_SPEED_TASK_DIR:-$ROOT/queue/training}"
THRESHOLD="${TEST_SPEED_THRESHOLD_SEC:-10}"

active_or_completed() {
    local target="$1"
    python3 - "$ROOT" "$target" <<'PY'
import os
import sys
from pathlib import Path

import yaml

root = Path(sys.argv[1]).resolve()
target = sys.argv[2]

def canonical(value):
    if not value:
        return None
    path = Path(str(value))
    return Path(os.path.normpath(path if path.is_absolute() else root / path))

def documents(directory):
    if not directory.is_dir():
        return
    for path in directory.rglob("*.yaml"):
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        except (OSError, yaml.YAMLError):
            continue
        yield data.get("task", data), path

wanted = canonical(target)
tasks = []
for directory in (root / "queue" / "tasks", root / "queue" / "training"):
    for data, path in documents(directory) or []:
        if canonical(data.get("target_path")) == wanted:
            tasks.append((data, path))

# Active ownership remains fail-closed and does not require a report.
if any(str(data.get("status", "")) in {"assigned", "acknowledged", "in_progress"}
       for data, _ in tasks):
    raise SystemExit(0)

reports = []
for directory in (root / "queue" / "reports", root / "queue" / "archive" / "reports"):
    reports.extend(documents(directory) or [])

# A terminal task is permanently claimed only when a corresponding completed
# report exists.  This preserves retries for failed/incomplete work while also
# allowing reports to omit/reformat target_path.
for task, _ in tasks:
    if str(task.get("status", "")) not in {"done", "completed"}:
        continue
    task_ids = {str(task.get(key)) for key in ("task_id", "parent_cmd") if task.get(key)}
    for report, _ in reports:
        if str(report.get("status", "")) != "completed":
            continue
        report_ids = {str(report.get(key)) for key in ("task_id", "parent_cmd") if report.get(key)}
        report_target = canonical(report.get("target_path"))
        if (task_ids and task_ids & report_ids) or report_target == wanted:
            raise SystemExit(0)

raise SystemExit(1)
PY
}

next_target() {
    [ -r "$LEDGER" ] || return 1
    local wall target
    while IFS=$'\t' read -r wall target; do
        active_or_completed "$target" || { printf '%s\t%s\n' "$wall" "$target"; return 0; }
    done < <(awk -F '\t' -v threshold="$THRESHOLD" '
      NR == 1 { for (i=1;i<=NF;i++) h[$i]=i; next }
      $(h["runner"]) == "bats" {
        file=$(h["test_file"])
        latest_wall[file]=$(h["wall_sec"])+0
        latest_status[file]=$(h["status"])
      }
      END {
        for (file in latest_wall)
          if (latest_wall[file] > threshold && latest_status[file] != "skip")
            printf "%.3f\t%s\n", latest_wall[file], file
      }
    ' "$LEDGER" | sort -nr)
    return 1
}

generate() {
    local picked wall target slug stamp file
    mkdir -p "$OUT_DIR"
    exec 9>"$OUT_DIR/.test_speed_task_generator.lock"
    flock 9
    picked=$(next_target) || { echo "NO_CANDIDATE"; return 1; }
    wall=${picked%%$'\t'*}; target=${picked#*$'\t'}
    slug=$(basename "$target" .bats | tr -c '[:alnum:]_-' '_')
    stamp=$(date +%Y%m%d%H%M%S)
    file="$OUT_DIR/test_speed_${slug}_${stamp}.yaml"
    cat > "$file" <<YAML
task:
  parent_cmd: "cmd_training_test_speed_${slug}_${stamp}"
  task_id: "cmd_training_test_speed_${slug}_${stamp}"
  task_type: training
  estimated_minutes: 5
  project: infra
  target_path: "$target"
  status: assigned
  purpose: "実測 ${wall}s のunit testを契約不変のまま5分以内へ高速化する"
  command: "支配項を実測し、共有fixture/cache化を優先する。頭打ちなら被テストscript本体へ切り替える。検証は bash scripts/run_timed_bats.sh $target で実行し台帳追記を強制する。期待値緩和、SKIP/xfail追加、対象縮小は禁止。"
  acceptance_criteria:
    - id: AC1
      description: "変更前後wall秒と支配項を実測し、bash scripts/run_timed_bats.sh $target により台帳へ追記し、FAIL=0・SKIP=0で対象bats全量完走する"
    - id: AC2
      description: "related_lessonsが注入された場合のみ各教訓の有用性を検証し、生成物をdeploy契約とgate_report_format契約に従い報告してscope限定commitする"
  related_lessons: []
  speed_evidence:
    source: "logs/test_timing_ledger.tsv"
    before_wall_sec: $wall
    quality_contract: "FAIL0; SKIP0; no expectation relaxation; shared fixture/cache first; switch to production script at plateau"
YAML
    printf '%s\n' "$file"
}

case "${1:-generate}" in
  next) next_target ;;
  generate) generate ;;
  deploy)
    ninja="${2:?ninja required}"
    task=$(generate) || exit 1
    bash "$ROOT/scripts/deploy_task.sh" --direct --yaml "$task" "$ninja"
    ;;
  *) echo "usage: $0 {next|generate|deploy NINJA}" >&2; exit 2 ;;
esac
