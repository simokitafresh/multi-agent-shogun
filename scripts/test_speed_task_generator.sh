#!/usr/bin/env bash
# test_speed_task_generator.sh — timing ledgerから未攻略unit速度タスクを生成/配備する
set -euo pipefail

ROOT="${SHOGUN_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LEDGER="${TEST_TIMING_LEDGER:-$ROOT/logs/test_timing_ledger.tsv}"
OUT_DIR="${TEST_SPEED_TASK_DIR:-$ROOT/queue/training}"
THRESHOLD="${TEST_SPEED_THRESHOLD_SEC:-10}"

active_or_completed() {
    local target="$1"
    local file
    while read -r file; do
        rg -q 'status:[[:space:]]*(assigned|acknowledged|in_progress|done|completed)' "$file" && return 0
    done < <(rg -l --fixed-strings "$target" "$ROOT/queue/tasks" "$ROOT/queue/reports" "$ROOT/queue/archive/reports" 2>/dev/null || true)
    return 1
}

next_target() {
    [ -r "$LEDGER" ] || return 1
    local wall target
    while IFS=$'\t' read -r wall target; do
        active_or_completed "$target" || { printf '%s\t%s\n' "$wall" "$target"; return 0; }
    done < <(awk -F '\t' -v threshold="$THRESHOLD" '
      NR == 1 { for (i=1;i<=NF;i++) h[$i]=i; next }
      $(h["runner"]) == "bats" && $(h["wall_sec"])+0 > threshold && $(h["status"]) != "skip" {
        file=$(h["test_file"]); wall=$(h["wall_sec"])+0
        if (!(file in worst) || wall > worst[file]) worst[file]=wall
      }
      END { for (file in worst) printf "%.3f\t%s\n", worst[file], file }
    ' "$LEDGER" | sort -nr)
    return 1
}

generate() {
    local picked wall target slug stamp file
    picked=$(next_target) || { echo "NO_CANDIDATE"; return 1; }
    wall=${picked%%$'\t'*}; target=${picked#*$'\t'}
    slug=$(basename "$target" .bats | tr -c '[:alnum:]_-' '_')
    stamp=$(date +%Y%m%d%H%M%S)
    file="$OUT_DIR/test_speed_${slug}_${stamp}.yaml"
    mkdir -p "$OUT_DIR"
    cat > "$file" <<YAML
task:
  parent_cmd: "cmd_training_test_speed_${slug}_${stamp}"
  task_id: "cmd_training_test_speed_${slug}_${stamp}"
  task_type: training
  project: infra
  target_path: "$target"
  status: assigned
  purpose: "実測 ${wall}s のunit testを契約不変のまま5分以内へ高速化する"
  command: "支配項を実測し、共有fixture/cache化を優先する。頭打ちなら被テストscript本体へ切り替える。期待値緩和、SKIP/xfail追加、対象縮小は禁止。"
  acceptance_criteria:
    - id: AC1
      description: "変更前後wall秒と支配項を実測し、FAIL=0・SKIP=0で対象bats全量完走する"
    - id: AC2
      description: "生成物をdeploy契約とgate_report_format契約に従い報告しscope限定commitする"
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
