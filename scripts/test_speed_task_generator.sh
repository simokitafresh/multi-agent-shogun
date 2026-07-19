#!/usr/bin/env bash
# test_speed_task_generator.sh — timing ledgerから未攻略unit速度タスクを生成/配備する
set -euo pipefail

ROOT="${SHOGUN_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LEDGER="${TEST_TIMING_LEDGER:-$ROOT/logs/test_timing_ledger.tsv}"
OUT_DIR="${TEST_SPEED_TASK_DIR:-$ROOT/queue/training}"
THRESHOLD="${TEST_SPEED_THRESHOLD_SEC:-10}"
CAMPAIGN_LEDGER="${TEST_SPEED_CAMPAIGN_LEDGER:-$ROOT/logs/test_speed_campaign_ledger.tsv}"
SPEED_TRAINING_LEDGER="${SPEED_TRAINING_LEDGER:-$ROOT/logs/script_speed_training_ledger.yaml}"
MIN_ROUNDS=2
MAX_ROUNDS=3
CAMPAIGN_BUDGET_SEC=600

test_hygiene_evaluate() {
    local inventory="${TEST_HYGIENE_INVENTORY:-$ROOT/docs/research/ci-test-elimination-inventory-20260719.csv}"
    local push_wall="${TEST_HYGIENE_PUSH_WALL_SEC:-0}" new_tests="${TEST_HYGIENE_NEW_TESTS_7D:-0}"
    local hygiene_root="${TEST_HYGIENE_ROOT:-$ROOT}" new_list="${TEST_HYGIENE_NEW_TEST_LIST:-}"
    [ -r "$inventory" ] || { echo "BLOCK:test_hygiene_inventory_missing" >&2; return 2; }
    python3 - "$inventory" "$push_wall" "$new_tests" "$hygiene_root" "$new_list" <<'PY'
import csv, json, os, re, subprocess, sys
path, wall_raw, new_raw, root, new_list = sys.argv[1:]
rows = list(csv.DictReader(open(path, encoding="utf-8", newline="")))
present = [r for r in rows if os.path.isfile(os.path.join(root, r.get("test_file", "")))]
undeclared = [r for r in present if r.get("classification") != "push-maintain"]
fail_zero = [r for r in undeclared if r.get("fail_30d") in {"0", "zero", "fail0"}]
wall = float(wall_raw); new_tests = int(new_raw)
files = sorted({r.get("test_file", "") for r in present if r.get("test_file")})
if new_list:
    try: recent_files = set(open(new_list, encoding="utf-8").read().splitlines())
    except OSError: recent_files = set()
else:
    try:
        out = subprocess.run(["git", "-C", root, "log", "--since=7.days", "--diff-filter=A", "--name-only", "--format="],
                             check=True, capture_output=True, text=True, timeout=3).stdout
        recent_files = {line for line in out.splitlines() if line.startswith("tests/")}
    except Exception: recent_files = set()
quality_pass = 0
for rel in sorted(set(files) & recent_files):
    try: text = open(f"{root}/{rel}", encoding="utf-8").read()
    except OSError: continue
    match = re.search(r"(?m)^# test_necessity:\s*(\S.*)$", text)
    if not match: continue
    claim = match.group(1).strip()
    # A filename, generic quality word, or short label is a formal declaration,
    # not an invariant. Require subject + enforced behavior + failure boundary.
    if len(claim) >= 30 and re.search(r"(BLOCK|FAIL|SKIP|exactly|原子的|混入|重複|欠落|不変量|恒久化)", claim):
        quality_pass += 1
declaration_rate = quality_pass * 100.0 / new_tests if new_tests else 0.0
fail_zero_rate = len(fail_zero) * 100.0 / len(undeclared) if undeclared else 0.0
reasons = []
if wall > 170: reasons.append("push_wall_gt_170")
if fail_zero_rate > 20: reasons.append("fail0_ratio_gt_20")
if new_tests > 50: reasons.append("new_tests_gt_50_per_week")
if declaration_rate > 30: reasons.append("declaration_rate_gt_30")
print(json.dumps({"trigger": bool(reasons), "reasons": reasons, "push_wall_sec": wall,
 "fail_zero_rate": round(fail_zero_rate, 3), "new_tests_7d": new_tests,
 "declaration_rate": round(declaration_rate, 3), "declaration_quality_pass_files": quality_pass,
 "present_inventory_files": len(files), "undeclared_present": len(undeclared)}, sort_keys=True))
PY
}

# PD-132 pause is shared by the script-speed and test-speed lanes.  Only an
# explicit running state reopens generation/deployment; missing or malformed
# state is fail-closed so an incomplete recovery cannot create new work.
require_speed_training_running() {
    local status
    status=$(awk '
      /^[[:space:]]*global_status:[[:space:]]*/ {
        value=$0; sub(/^[^:]*:[[:space:]]*/, "", value)
        gsub(/[[:space:]"]/, "", value); print tolower(value); exit
      }
    ' "$SPEED_TRAINING_LEDGER" 2>/dev/null) || status=""
    if [ "$status" != running ]; then
        printf 'PAUSED: speed training global_status=%s\n' "${status:-missing}" >&2
        return 3
    fi
}

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
    malformed = 0
    for path in directory.rglob("*.yaml"):
        try:
            raw = yaml.safe_load(path.read_text(encoding="utf-8"))
        except (OSError, yaml.YAMLError) as exc:
            malformed += 1
            print(f"WARN: candidate scan skipped malformed YAML path={path} error={type(exc).__name__}", file=sys.stderr)
            continue
        if not isinstance(raw, dict):
            malformed += 1
            print(f"WARN: candidate scan skipped non-dict YAML path={path} root={type(raw).__name__}", file=sys.stderr)
            continue
        data = raw.get("task", raw)
        if not isinstance(data, dict):
            malformed += 1
            print(f"WARN: candidate scan skipped non-dict task path={path} root={type(data).__name__}", file=sys.stderr)
            continue
        yield data, path
    if malformed:
        print(f"WARN: candidate scan continued after invalid entries count={malformed} directory={directory}", file=sys.stderr)

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

# Timing rows are historical evidence, not proof that a test can still be
# measured.  Default-delete may remove a test after its timing row was written.
# Require both the live worktree file and the baseline HEAD blob before the row
# can become work; otherwise an idle ninja receives an impossible A/B task.
target_is_measurable() {
    local target="$1" root_real target_real rel
    root_real=$(realpath -m -- "$ROOT") || return 1
    case "$target" in
      /*) target_real=$(realpath -m -- "$target") || return 1 ;;
      *)  target_real=$(realpath -m -- "$ROOT/$target") || return 1 ;;
    esac
    case "$target_real" in
      "$root_real"/*) rel=${target_real#"$root_real"/} ;;
      *) return 1 ;;
    esac
    [ -f "$target_real" ] || return 1
    if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
       git -C "$ROOT" rev-parse --verify HEAD >/dev/null 2>&1; then
        git -C "$ROOT" cat-file -e "HEAD:$rel" 2>/dev/null || return 1
    fi
}

next_target() {
    [ -r "$LEDGER" ] || return 1
    local wall target
    while IFS=$'\t' read -r wall target; do
        if ! target_is_measurable "$target"; then
            printf 'WARN: stale timing target skipped target=%s reason=missing_worktree_or_head\n' "$target" >&2
            continue
        fi
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
    local ab_base="${8:-}" ab_candidate="${9:-}" ab_command="${10:-}" ab_n="${11:-}" ab_base_p50="${12:-}" ab_base_p95="${13:-}" ab_candidate_p50="${14:-}" ab_candidate_p95="${15:-}"
    mkdir -p "$(dirname "$CAMPAIGN_LEDGER")"
    (
        flock 8
        if [ ! -s "$CAMPAIGN_LEDGER" ]; then
            printf 'campaign_id\tround_index\ttarget_path\tbest_wall\tlast_wall\tapproach\tstop_reason\tab_base_commit\tab_candidate_commit\tab_command\tab_samples\tab_base_p50\tab_base_p95\tab_candidate_p50\tab_candidate_p95\n' > "$CAMPAIGN_LEDGER"
        fi
        # monitor callbacks are at-least-once; make each campaign round idempotent.
        # malformed quality values from an older callback are append-onlyで訂正可能にする。
        # 正常な同一roundは従来どおりexactly-once。invalid quality_*だけは完了証跡ではない。
        awk -F '\t' -v c="$campaign" -v r="$round" '
          NR>1 && $1==c && $2==r {
            if ($7 ~ /^quality_/ && $7 != "quality_fail" && $7 != "quality_skip") next
            found=1
          }
          END{exit !found}
        ' "$CAMPAIGN_LEDGER" && exit 0
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$campaign" "$round" "$target" "$best" "$last" "$approach" "$stop" "$ab_base" "$ab_candidate" "$ab_command" "$ab_n" "$ab_base_p50" "$ab_base_p95" "$ab_candidate_p50" "$ab_candidate_p95" >> "$CAMPAIGN_LEDGER"
    ) 8>"${CAMPAIGN_LEDGER}.lock"
}

emit_round_task() {
    local campaign="$1" round="$2" target="$3" best="$4" elapsed="$5" slug stamp file report baseline_commit
    target_is_measurable "$target" || {
        printf 'BLOCK:target_not_measurable target=%s reason=missing_worktree_or_head\n' "$target" >&2
        return 2
    }
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
  purpose: "round ${round}/${MAX_ROUNDS}: last-good commitとcandidate commitを同一環境A/B交互測定してunit testを高速化する"
  command: "支配項を実測し、共有fixture/cache化を優先する。last-good/candidateを同一command・同一環境でwarmup後に各10回以上交互測定し、p50/p95双方が非退行かつ一方strict短縮の場合だけcandidateを採用する。best_so_far=${best}sは選定参考のみ。FAIL/SKIPは即停止。"
  acceptance_criteria:
    - id: AC1
      description: "last-good/candidate commitを同一commandでwarmup後各10回以上A/B交互測定し、p50/p95と支配項を実測、FAIL=0・SKIP=0で完走する"
    - id: AC2
      description: "related_lessonsが注入された場合のみ有用性を検証する。round別report/commitを作り、speed_result(last_wall/approach/quality=pass|fail|skip/dominant/elapsed_sec/ctx_percent)とtest_results(status=pass, wall_sec=有限非負値, failures=0, skips=0)を構造化記録する。品質説明文はqualityへ混ぜずresult.detailsへ記録する。完了後はmonitor callbackが自動継承する"
  related_lessons: []
  speed_campaign:
    campaign_id: "$campaign"
    round_index: $round
    min_rounds: $MIN_ROUNDS
    max_rounds: $MAX_ROUNDS
    campaign_budget_sec: $CAMPAIGN_BUDGET_SEC
    elapsed_sec: $elapsed
    best_wall: $best
    baseline_policy: same_run_interleaved_ab
    baseline_commit: "$baseline_commit"
    ab_contract:
      min_samples_each: 10
      order: alternating
      warmup_each: 1
      adoption: "candidate_p50<=last_good_p50 && candidate_p95<=last_good_p95 && (candidate_p50<last_good_p50 || candidate_p95<last_good_p95)"
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
    local observed_last="${13:-$last}" ab_base="${14:-}" ab_candidate="${15:-}" ab_command="${16:-}" ab_n="${17:-}" ab_base_p50="${18:-}" ab_base_p95="${19:-}" ab_candidate_p50="${20:-}" ab_candidate_p95="${21:-}"
    case "$quality" in
      pass|fail|skip) ;;
      *) echo "BLOCK:quality_invalid expected=pass|fail|skip actual=$quality" >&2; return 2 ;;
    esac
    if [ -n "$ab_base" ] || [ -n "$ab_candidate" ]; then
        [ -n "$ab_base" ] && [ -n "$ab_candidate" ] && [ -n "$ab_command" ] && [ "$ab_n" -ge 10 ] 2>/dev/null || { echo "BLOCK:ab_evidence_missing" >&2; return 2; }
        if ! awk -v bp50="$ab_base_p50" -v bp95="$ab_base_p95" -v cp50="$ab_candidate_p50" -v cp95="$ab_candidate_p95" 'BEGIN{exit !(cp50<=bp50 && cp95<=bp95 && (cp50<bp50 || cp95<bp95))}'; then
            stop="ab_not_improved"
            last="$best"
        fi
    fi
    if [ -z "${14:-}" ] && awk -v b="$best" -v l="$last" 'BEGIN{exit !(l>=b)}' && [ -n "$baseline_commit" ] && \
       [ -n "$result_commit" ] && [ "$baseline_commit" != "$result_commit" ]; then
        echo "BLOCK:deterioration_commit_adopted baseline=$baseline_commit result=$result_commit" >&2
        return 2
    fi
    adopted_best=$(awk -v b="$best" -v l="$last" 'BEGIN { printf "%.3f", (l < b ? l : b) }')
    stop="${stop:-}"
    if [ "$quality" != pass ]; then stop="quality_${quality}";
    elif awk -v e="$elapsed" -v b="$CAMPAIGN_BUDGET_SEC" 'BEGIN{exit !(e>=b)}'; then stop="budget";
    elif [ "$round" -ge "$MAX_ROUNDS" ]; then stop="max_rounds";
    elif [ "$round" -ge "$MIN_ROUNDS" ] && [ "$dominant" = none ]; then stop="no_next_dominant"; fi
    append_campaign "$campaign" "$round" "$target" "$adopted_best" "$observed_last" "$approach" "$stop" "$ab_base" "$ab_candidate" "$ab_command" "$ab_n" "$ab_base_p50" "$ab_base_p95" "$ab_candidate_p50" "$ab_candidate_p95"
    [ -z "$stop" ] || { printf 'STOP:%s\n' "$stop"; return 0; }
    next=$((round + 1))
    file=$(emit_round_task "$campaign" "$next" "$target" "$adopted_best" "$elapsed")
    if [ "$round" -ge 2 ] && [ "$ctx" -ge 70 ]; then printf 'CLEAR_REQUIRED ledger=%s\n' "$CAMPAIGN_LEDGER"; fi
    printf '%s\n' "$file"
}

command_name="${1:-generate}"
case "$command_name" in
  generate|deploy|continue|continue-deploy|complete-deploy)
    require_speed_training_running || exit $?
    ;;
esac

case "$command_name" in
  hygiene-evaluate) test_hygiene_evaluate ;;
  hygiene-deploy)
    ninja="${2:?ninja required}"
    metrics=$(test_hygiene_evaluate)
    python3 - "$metrics" <<'PY' | grep -qx true || { echo "NO_CANDIDATE"; exit 1; }
import json,sys
print(str(json.loads(sys.argv[1])["trigger"]).lower())
PY
    tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
    python3 - "$tmp" "$metrics" <<'PY'
import datetime,json,sys
out,metrics=sys.argv[1:]
stamp=datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
task_id=f"cmd_training_test_hygiene_{stamp}"
task={"task":{"parent_cmd":task_id,"task_id":task_id,"project":"infra","task_type":"test_hygiene","status":"assigned",
 "report_filename":f"test_hygiene_report_{task_id}.yaml","report_path":f"queue/reports/test_hygiene_report_{task_id}.yaml",
 "purpose":"Remove undeclared permanent tests selected by measured hygiene thresholds",
 "hygiene_metrics":json.loads(metrics),"acceptance_criteria":[
 {"id":"AC1","description":"Every retained test has a concrete test_necessity invariant"},
 {"id":"AC2","description":"Undeclared tests are removed with contract-test overlap 0 and SKIP 0"}]}}
with open(out,"w",encoding="utf-8") as f:
 json.dump(task,f,ensure_ascii=False,sort_keys=True,indent=2); f.write("\n")
PY
    "${DEPLOY_TASK:-$ROOT/scripts/deploy_task.sh}" --yaml "$tmp" "$ninja"
    ;;
  next) next_target ;;
  generate) generate ;;
  deploy)
    ninja="${2:?ninja required}"
    task=$(generate) || exit 1
    bash "$ROOT/scripts/deploy_task.sh" --yaml "$task" "$ninja"
    ;;
  complete-deploy)
    ninja="${2:?ninja required}"; task_file="${3:?task file required}"; report_file="${4:?report file required}"
    eval "$(python3 - "$task_file" "$report_file" <<'PY'
import math, shlex, statistics, sys, yaml
t=(yaml.safe_load(open(sys.argv[1])) or {}).get('task', {})
r=yaml.safe_load(open(sys.argv[2])) or {}
c=t.get('speed_campaign') or {}; s=r.get('speed_result') or {}

def measurement_rows(value):
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        if 'wall_sec' in value:
            return [value]
        return [item for item in value.values() if isinstance(item, dict)]
    return []

valid_walls=[]
for result in measurement_rows(r.get('test_results')):
    status=str(result.get('status', '')).strip().lower()
    failures=result.get('failures', result.get('failed'))
    skips=result.get('skips', result.get('skipped'))
    wall=result.get('wall_sec')
    try:
        wall=float(wall)
        failures=int(failures)
        skips=int(skips)
    except (TypeError, ValueError, OverflowError):
        continue
    if status == 'pass' and failures == 0 and skips == 0 and math.isfinite(wall) and wall >= 0:
        valid_walls.append(wall)
if not valid_walls:
    raise SystemExit('BLOCK:no_valid_test_measurements')
round_best=min(valid_walls)
ab=r.get('speed_ab') or {}
policy=str(c.get('baseline_policy') or '')
ab_vals=[]
if policy == 'same_run_interleaved_ab':
    base=list(ab.get('last_good_samples_ms') or [])
    cand=list(ab.get('candidate_samples_ms') or [])
    if len(base) < 10 or len(cand) < 10 or len(base) != len(cand):
        raise SystemExit('BLOCK:ab_evidence_missing')
    try:
        base=[float(x) for x in base]; cand=[float(x) for x in cand]
    except (TypeError, ValueError):
        raise SystemExit('BLOCK:ab_evidence_non_numeric')
    if not all(math.isfinite(x) and x >= 0 for x in base+cand):
        raise SystemExit('BLOCK:ab_evidence_non_numeric')
    def p95(xs):
        ys=sorted(xs); return ys[max(0, math.ceil(.95*len(ys))-1)]
    required=(ab.get('last_good_commit'), ab.get('candidate_commit'), ab.get('command'))
    if any(v in (None, '') for v in required): raise SystemExit('BLOCK:ab_evidence_missing')
    if required[0] == required[1]: raise SystemExit('BLOCK:ab_commits_identical')
    if ab.get('order') != 'alternating': raise SystemExit('BLOCK:ab_order_invalid')
    try: warmup=int(ab.get('warmup_each'))
    except (TypeError, ValueError): raise SystemExit('BLOCK:ab_warmup_invalid')
    if warmup < 1: raise SystemExit('BLOCK:ab_warmup_invalid')
    sequence=ab.get('sequence')
    if sequence is not None:
        expected=['L' if i % 2 == 0 else 'C' for i in range(len(base)*2)]
        if sequence != expected: raise SystemExit('BLOCK:ab_sequence_not_alternating')
    ab_vals=[*required, len(base), statistics.median(base), p95(base), statistics.median(cand), p95(cand)]
vals=[c.get('campaign_id'), c.get('round_index'), t.get('target_path'), c.get('best_wall'),
      round_best, s.get('approach'), s.get('quality'), s.get('dominant','none'),
      s.get('elapsed_sec', c.get('elapsed_sec',0)), s.get('ctx_percent',0),
      c.get('baseline_commit',''), r.get('commit_hash',''), s.get('last_wall')]
if any(v in (None, '') for v in vals[:7]): raise SystemExit('missing speed_result callback fields')
if vals[12] in (None, ''): raise SystemExit('missing speed_result last_wall observation')
vals.extend(ab_vals)
print('set -- ' + ' '.join(shlex.quote(str(v)) for v in vals))
PY
)"
    task=$(continue_campaign "$@") || exit $?
    [[ "$task" == STOP:* ]] && { printf '%s\n' "$task"; exit 0; }
    task=$(printf '%s\n' "$task" | tail -n 1)
    bash "$ROOT/scripts/deploy_task.sh" --yaml "$task" "$ninja"
    ;;
  continue) shift; continue_campaign "$@" ;;
  continue-deploy)
    ninja="${2:?ninja required}"; shift 2
    task=$(continue_campaign "$@") || exit 1
    [[ "$task" == STOP:* ]] && { printf '%s\n' "$task"; exit 0; }
    task=$(printf '%s\n' "$task" | tail -n 1)
    bash "$ROOT/scripts/deploy_task.sh" --yaml "$task" "$ninja"
    ;;
  *) echo "usage: $0 {next|generate|deploy NINJA|continue ...|continue-deploy NINJA ...|complete-deploy NINJA TASK REPORT}" >&2; exit 2 ;;
esac
