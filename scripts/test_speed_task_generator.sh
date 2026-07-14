#!/usr/bin/env bash
# test_speed_task_generator.sh — timing ledgerから未攻略unit速度タスクを生成/配備する
set -euo pipefail

ROOT="${SHOGUN_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LEDGER="${TEST_TIMING_LEDGER:-$ROOT/logs/test_timing_ledger.tsv}"
OUT_DIR="${TEST_SPEED_TASK_DIR:-$ROOT/queue/training}"
THRESHOLD="${TEST_SPEED_THRESHOLD_SEC:-10}"
CAMPAIGN_LEDGER="${TEST_SPEED_CAMPAIGN_LEDGER:-$ROOT/logs/test_speed_campaign_ledger.tsv}"
MIN_ROUNDS=2
MAX_ROUNDS=3
CAMPAIGN_BUDGET_SEC=600

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

append_campaign() {
    local campaign="$1" round="$2" target="$3" best="$4" last="$5" approach="$6" stop="$7"
    mkdir -p "$(dirname "$CAMPAIGN_LEDGER")"
    (
        flock 8
        if [ ! -s "$CAMPAIGN_LEDGER" ]; then
            printf 'campaign_id\tround_index\ttarget_path\tbest_wall\tlast_wall\tapproach\tstop_reason\n' > "$CAMPAIGN_LEDGER"
        fi
        # monitor callbacks are at-least-once; make each campaign round idempotent.
        awk -F '\t' -v c="$campaign" -v r="$round" 'NR>1 && $1==c && $2==r {found=1} END{exit !found}' "$CAMPAIGN_LEDGER" && exit 0
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$campaign" "$round" "$target" "$best" "$last" "$approach" "$stop" >> "$CAMPAIGN_LEDGER"
    ) 8>"${CAMPAIGN_LEDGER}.lock"
}

emit_round_task() {
    local campaign="$1" round="$2" target="$3" best="$4" elapsed="$5" slug stamp file report baseline_commit
    slug=$(basename "$target" .bats | tr -c '[:alnum:]_-' '_')
    stamp=$(date +%Y%m%d%H%M%S)
    file="$OUT_DIR/test_speed_${campaign#cmd_training_test_speed_}_r${round}_${stamp}.yaml"
    report="test_speed_report_${campaign}_r${round}.yaml"
    baseline_commit=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')
    cat > "$file" <<YAML
task:
  parent_cmd: "${campaign}"
  task_id: "${campaign}_r${round}_${stamp}"
  report_filename: "$report"
  report_path: "queue/reports/$report"
  task_type: training
  estimated_minutes: 5
  project: infra
  target_path: "$target"
  status: assigned
  purpose: "round ${round}/${MAX_ROUNDS}: best_so_far ${best}s を基準にunit testを高速化する"
  command: "支配項を実測し、共有fixture/cache化を優先する。頭打ちなら被テストscript本体へ切り替える。best_so_far=${best}s未満のみ改善として採用し、悪化runはcommitせずlast-goodへ戻す。検証は bash scripts/run_timed_bats.sh $target でFAIL0/SKIP0を強制する。"
  acceptance_criteria:
    - id: AC1
      description: "best_so_far ${best}sとの比較、変更前後wall秒、支配項を実測し、FAIL=0・SKIP=0で全量完走する"
    - id: AC2
      description: "related_lessonsが注入された場合のみ有用性を検証する。round別report/commitを作り、speed_result(last_wall/approach/quality/dominant/elapsed_sec/ctx_percent)を記録する。完了後はmonitor callbackが自動継承する"
  related_lessons: []
  speed_campaign:
    campaign_id: "$campaign"
    round_index: $round
    min_rounds: $MIN_ROUNDS
    max_rounds: $MAX_ROUNDS
    campaign_budget_sec: $CAMPAIGN_BUDGET_SEC
    elapsed_sec: $elapsed
    best_wall: $best
    baseline_policy: best_so_far
    baseline_commit: "$baseline_commit"
    ctx_clear_after_round2_at_percent: 70
  completion_callback:
    runner: "scripts/test_speed_task_generator.sh"
    action: "complete-deploy"
  speed_evidence:
    source: "logs/test_timing_ledger.tsv"
    before_wall_sec: $best
    quality_contract: "FAIL0; SKIP0; no expectation relaxation; shared fixture/cache first; switch to production script at plateau; deterioration is not adopted"
YAML
    printf '%s\n' "$file"
}

generate() {
    local picked wall target slug stamp file campaign
    mkdir -p "$OUT_DIR"
    exec 9>"$OUT_DIR/.test_speed_task_generator.lock"
    flock 9
    picked=$(next_target) || { echo "NO_CANDIDATE"; return 1; }
    wall=${picked%%$'\t'*}; target=${picked#*$'\t'}
    slug=$(basename "$target" .bats | tr -c '[:alnum:]_-' '_')
    stamp=$(date +%Y%m%d%H%M%S)
    campaign="cmd_training_test_speed_${slug}_${stamp}"
    append_campaign "$campaign" 0 "$target" "$wall" "$wall" selected ""
    emit_round_task "$campaign" 1 "$target" "$wall" 0
}

continue_campaign() {
    local campaign="${1:?campaign_id required}" round="${2:?round required}" target="${3:?target required}"
    local best="${4:?best_wall required}" last="${5:?last_wall required}" approach="${6:?approach required}"
    local quality="${7:?quality pass|fail|skip required}" dominant="${8:-none}" elapsed="${9:-0}" ctx="${10:-0}"
    local adopted_best stop next file baseline_commit="${11:-}" result_commit="${12:-}"
    if awk -v b="$best" -v l="$last" 'BEGIN{exit !(l>=b)}' && [ -n "$baseline_commit" ] && \
       [ -n "$result_commit" ] && [ "$baseline_commit" != "$result_commit" ]; then
        echo "BLOCK:deterioration_commit_adopted baseline=$baseline_commit result=$result_commit" >&2
        return 2
    fi
    adopted_best=$(awk -v b="$best" -v l="$last" 'BEGIN { printf "%.3f", (l < b ? l : b) }')
    stop=""
    if [ "$quality" != pass ]; then stop="quality_${quality}";
    elif [ "$elapsed" -ge "$CAMPAIGN_BUDGET_SEC" ]; then stop="budget";
    elif [ "$round" -ge "$MAX_ROUNDS" ]; then stop="max_rounds";
    elif [ "$round" -ge "$MIN_ROUNDS" ] && [ "$dominant" = none ]; then stop="no_next_dominant"; fi
    append_campaign "$campaign" "$round" "$target" "$adopted_best" "$last" "$approach" "$stop"
    [ -z "$stop" ] || { printf 'STOP:%s\n' "$stop"; return 0; }
    next=$((round + 1))
    file=$(emit_round_task "$campaign" "$next" "$target" "$adopted_best" "$elapsed")
    if [ "$round" -ge 2 ] && [ "$ctx" -ge 70 ]; then printf 'CLEAR_REQUIRED ledger=%s\n' "$CAMPAIGN_LEDGER"; fi
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
  complete-deploy)
    ninja="${2:?ninja required}"; task_file="${3:?task file required}"; report_file="${4:?report file required}"
    eval "$(python3 - "$task_file" "$report_file" <<'PY'
import shlex, sys, yaml
t=(yaml.safe_load(open(sys.argv[1])) or {}).get('task', {})
r=yaml.safe_load(open(sys.argv[2])) or {}
c=t.get('speed_campaign') or {}; s=r.get('speed_result') or {}
vals=[c.get('campaign_id'), c.get('round_index'), t.get('target_path'), c.get('best_wall'),
      s.get('last_wall'), s.get('approach'), s.get('quality'), s.get('dominant','none'),
      s.get('elapsed_sec', c.get('elapsed_sec',0)), s.get('ctx_percent',0),
      c.get('baseline_commit',''), r.get('commit_hash','')]
if any(v in (None, '') for v in vals[:7]): raise SystemExit('missing speed_result callback fields')
print('set -- ' + ' '.join(shlex.quote(str(v)) for v in vals))
PY
)"
    task=$(continue_campaign "$@") || exit $?
    [[ "$task" == STOP:* ]] && { printf '%s\n' "$task"; exit 0; }
    task=$(printf '%s\n' "$task" | tail -n 1)
    bash "$ROOT/scripts/deploy_task.sh" --direct --yaml "$task" "$ninja"
    ;;
  continue) shift; continue_campaign "$@" ;;
  continue-deploy)
    ninja="${2:?ninja required}"; shift 2
    task=$(continue_campaign "$@") || exit 1
    [[ "$task" == STOP:* ]] && { printf '%s\n' "$task"; exit 0; }
    task=$(printf '%s\n' "$task" | tail -n 1)
    bash "$ROOT/scripts/deploy_task.sh" --direct --yaml "$task" "$ninja"
    ;;
  *) echo "usage: $0 {next|generate|deploy NINJA|continue ...|continue-deploy NINJA ...|complete-deploy NINJA TASK REPORT}" >&2; exit 2 ;;
esac
