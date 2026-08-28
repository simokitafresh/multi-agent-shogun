#!/usr/bin/env bats
# test_necessity: Multi-round preserves best-so-far and rejects false improvement after deterioration; violation is BLOCK.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  TMP="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$TMP/logs" "$TMP/queue/tasks" "$TMP/queue/reports" "$TMP/queue/archive/reports" "$TMP/queue/training" "$TMP/tests/unit"
  touch "$TMP/tests/unit/slow.bats" "$TMP/tests/unit/worse.bats" "$TMP/tests/unit/current.bats" "$TMP/tests/unit/stale.bats"
  printf 'run_id\trepo\tcommit_sha\tsuite_root\trunner\ttest_file\ttest_id_count\twall_sec\tstatus\tskip_count\n' > "$TMP/logs/test_timing_ledger.tsv"
  printf 'global_status: running\n' > "$TMP/logs/script_speed_training_ledger.yaml"
}

@test "generator selects worst unclaimed threshold breach and embeds quality contract" {
  printf 'r\tx\tc\tunit\tbats\ttests/unit/slow.bats\t2\t12.5\tpass\t0\n' >> "$TMP/logs/test_timing_ledger.tsv"
  printf 'r\tx\tc\tunit\tbats\ttests/unit/worse.bats\t2\t21.0\tpass\t0\n' >> "$TMP/logs/test_timing_ledger.tsv"
  cat > "$TMP/queue/tasks/hayate.yaml" <<'YAML'
task:
  target_path: tests/unit/worse.bats
  status: in_progress
YAML
  run env SHOGUN_REPO_ROOT="$TMP" TEST_TIMING_LEDGER="$TMP/logs/test_timing_ledger.tsv" TEST_SPEED_TASK_DIR="$TMP/queue/training" bash "$ROOT/scripts/test_speed_task_generator.sh" generate
  [ "$status" -eq 0 ]
  generated="$output"
  grep -Fq 'target_path: "tests/unit/slow.bats"' "$generated"
  grep -Fq 'estimated_minutes: 5' "$generated"
  grep -Fq 'min_rounds: 2' "$generated"
  grep -Fq 'max_rounds: 3' "$generated"
  grep -Fq 'baseline_policy: same_run_interleaved_ab' "$generated"
  grep -Fq 'min_samples_each: 10' "$generated"
  grep -Fq 'order: alternating' "$generated"
  grep -Fq 'report_filename: "test_speed_report_' "$generated"
  grep -Fq 'action: "complete-deploy"' "$generated"
  grep -Fq 'quality=pass|fail|skip' "$generated"
  grep -Fq 'test_results(status=pass, wall_sec=有限非負値, failures=0, skips=0)' "$generated"
  grep -Fq 'speed_ab(last_good_commit/candidate_commit/command/order=alternating/warmup_each/sequence/各10samples/p50/p95/adopted)' "$generated"
  grep -Fq 'FAIL0; SKIP0; no expectation relaxation' "$generated"
  grep -Fq 'shared fixture/cache first; switch to production script at plateau' "$generated"
}

@test "production deploy contract preserves unique round reports and complete-deploy reaches assigned R2" {
  mkdir -p "$TMP/scripts/lib" "$TMP/bin"
  cp "$ROOT/scripts/test_speed_task_generator.sh" "$TMP/scripts/"
  cp "$ROOT/scripts/lib/field_get.sh" "$ROOT/scripts/lib/yaml_field_set.sh" "$TMP/scripts/lib/"
  extract_function() { sed -n "/^$1()/,/^}/p" "$ROOT/scripts/deploy_task.sh"; }
  eval "$(extract_function inject_report_filename)"
  eval "$(extract_function deploy_task_speed_campaign_report_is_explicit)"
  eval "$(extract_function deploy_task_normalize_report_metadata)"
  field_get() { FIELD_GET_NO_LOG=1 bash "$TMP/scripts/lib/field_get.sh" "$@"; }
  yaml_field_set() { bash "$TMP/scripts/lib/yaml_field_set.sh" "$@"; }
  log() { :; }
  cat > "$TMP/scripts/deploy_task.sh" <<SH
#!/usr/bin/env bash
set -euo pipefail
source "$TMP/scripts/lib/field_get.sh"
source "$TMP/scripts/lib/yaml_field_set.sh"
$(extract_function inject_report_filename)
$(extract_function deploy_task_speed_campaign_report_is_explicit)
$(extract_function deploy_task_normalize_report_metadata)
$(extract_function inject_done_redeploy_hints)
log() { :; }
NINJA_NAME="\$3"
cp "\$2" "$TMP/queue/tasks/\$3.yaml"
deploy_task_normalize_report_metadata "$TMP/queue/tasks/\$3.yaml"
_DEPLOY_DONE_REUSE=1
_DEPLOY_DONE_REPORT_PATH=queue/reports/r1.yaml
inject_done_redeploy_hints "$TMP/queue/tasks/\$3.yaml"
report=\$(FIELD_GET_NO_LOG=1 field_get "$TMP/queue/tasks/\$3.yaml" report_path "")
mkdir -p "$TMP/\$(dirname "\$report")"
printf 'status: pending\n' > "$TMP/\$report"
SH
  chmod +x "$TMP/scripts/deploy_task.sh"
  task1="$TMP/queue/training/r1.yaml"
  cat > "$task1" <<'YAML'
task:
  parent_cmd: camp
  task_id: camp_r1
  target_path: tests/unit/slow.bats
  speed_campaign:
    campaign_id: camp
    round_index: 1
    best_wall: 10
    elapsed_sec: 0
    baseline_commit: same
YAML
  report1="$TMP/queue/reports/r1.yaml"
  cat > "$report1" <<'YAML'
status: completed
commit_hash: same
speed_result: {last_wall: 9, approach: cache, quality: pass, dominant: cache, elapsed_sec: 10, ctx_percent: 10}
test_results:
  - {status: PASS, failures: 0, skips: 0, wall_sec: 9}
YAML
  run env SHOGUN_REPO_ROOT="$TMP" TEST_SPEED_TASK_DIR="$TMP/queue/training" TEST_SPEED_CAMPAIGN_LEDGER="$TMP/logs/campaign.tsv" \
    bash "$ROOT/scripts/test_speed_task_generator.sh" complete-deploy hayate "$task1" "$report1"
  [ "$status" -eq 0 ]
  grep -Fq 'round_index: 2' "$TMP/queue/tasks/hayate.yaml"
  r2_report=$(sed -n 's/^[[:space:]]*report_filename:[[:space:]]*"\([^" ]*\)"$/\1/p' "$TMP/queue/tasks/hayate.yaml")
  [ "$r2_report" = 'test_speed_report_camp_r2.yaml' ]
  [ -f "$TMP/queue/reports/$r2_report" ]
  [ "$(sed -n 's/^[[:space:]]*status:[[:space:]]*//p' "$TMP/queue/tasks/hayate.yaml" | head -1)" = assigned ]
  [ "$r2_report" != r1.yaml ]
  [ -f "$report1" ]
}

@test "complete-deploy derives order-independent round best from valid R2 measurements" {
  mkdir -p "$TMP/scripts"
  cp "$ROOT/scripts/test_speed_task_generator.sh" "$TMP/scripts/"
  cat > "$TMP/scripts/deploy_task.sh" <<'SH'
#!/usr/bin/env bash
cp "$2" "$SHOGUN_REPO_ROOT/deployed.yaml"
SH
  chmod +x "$TMP/scripts/deploy_task.sh"
  task="$TMP/queue/training/r2.yaml"
  cat > "$task" <<'YAML'
task:
  target_path: tests/unit/slow.bats
  speed_campaign:
    campaign_id: camp-r2
    round_index: 2
    best_wall: 10
    elapsed_sec: 10
    baseline_commit: same
YAML

  for order in normal reversed; do
    report="$TMP/queue/reports/$order.yaml"
    if [ "$order" = normal ]; then walls='[4.285, 5.196]'; else walls='[5.196, 4.285]'; fi
    python3 - "$report" "$walls" <<'PY'
import sys, yaml
walls=yaml.safe_load(sys.argv[2])
data={
  'commit_hash': 'same',
  'speed_result': {'last_wall': 5.196, 'approach': 'fixture', 'quality': 'pass', 'dominant': 'cache', 'elapsed_sec': 20, 'ctx_percent': 10},
  'test_results': [
    {'status': 'PASS', 'failures': 0, 'skips': 0, 'wall_sec': walls[0]},
    {'status': 'PASS', 'failures': 0, 'skips': 0, 'wall_sec': walls[1]},
    {'status': 'FAIL', 'failures': 0, 'skips': 0, 'wall_sec': 1},
    {'status': 'PASS', 'failures': 1, 'skips': 0, 'wall_sec': 2},
    {'status': 'PASS', 'failures': 0, 'skips': 1, 'wall_sec': 3},
    {'status': 'PASS', 'failures': 0, 'skips': 0, 'wall_sec': 'not-a-number'},
  ],
}
with open(sys.argv[1], 'w') as fh: yaml.safe_dump(data, fh)
PY
    ledger="$TMP/logs/campaign-$order.tsv"
    run env SHOGUN_REPO_ROOT="$TMP" TEST_SPEED_TASK_DIR="$TMP/queue/training" TEST_SPEED_CAMPAIGN_LEDGER="$ledger" \
      bash "$ROOT/scripts/test_speed_task_generator.sh" complete-deploy hayate "$task" "$report"
    [ "$status" -eq 0 ]
    grep -Fq 'best_wall: 4.285' "$TMP/deployed.yaml"
    [ "$(awk -F '\t' '$1=="camp-r2" && $2==2 {print $4 ":" $5}' "$ledger")" = '4.285:5.196' ]
  done
}

@test "complete-deploy blocks when no quality-valid numeric measurement exists" {
  task="$TMP/queue/training/invalid-r2.yaml"
  cat > "$task" <<'YAML'
task:
  target_path: tests/unit/slow.bats
  speed_campaign: {campaign_id: invalid, round_index: 2, best_wall: 10, baseline_commit: same}
YAML
  report="$TMP/queue/reports/invalid-r2.yaml"
  cat > "$report" <<'YAML'
commit_hash: same
speed_result: {last_wall: 5.196, approach: fixture, quality: pass}
test_results:
  - {status: FAIL, failures: 0, skips: 0, wall_sec: 4.285}
  - {status: PASS, failures: 0, skips: 0, wall_sec: nope}
YAML
  run env SHOGUN_REPO_ROOT="$TMP" TEST_SPEED_CAMPAIGN_LEDGER="$TMP/logs/invalid.tsv" \
    bash "$ROOT/scripts/test_speed_task_generator.sh" complete-deploy hayate "$task" "$report"
  [ "$status" -ne 0 ]
  [[ "$output" == *'BLOCK:no_valid_test_measurements'* ]]
  [ ! -e "$TMP/logs/invalid.tsv" ]
}

@test "invalid quality blocks before ledger mutation and malformed legacy round remains correctable" {
  ledger="$TMP/logs/quality-invalid.tsv"
  run env SHOGUN_REPO_ROOT="$TMP" TEST_SPEED_TASK_DIR="$TMP/queue/training" TEST_SPEED_CAMPAIGN_LEDGER="$ledger" \
    bash "$ROOT/scripts/test_speed_task_generator.sh" continue camp-quality 1 tests/unit/slow.bats 10 9 fixture "18/18 PASS" cache 10 0 same same 9
  [ "$status" -ne 0 ]
  [[ "$output" == *'BLOCK:quality_invalid'* ]]
  [ ! -e "$ledger" ]

  printf 'campaign_id\tround_index\ttarget_path\tbest_wall\tlast_wall\tapproach\tstop_reason\n' > "$ledger"
  printf 'camp-quality\t1\ttests/unit/slow.bats\t9\t9\tfixture\tquality_18/18 PASS\n' >> "$ledger"
  run env SHOGUN_REPO_ROOT="$TMP" TEST_SPEED_TASK_DIR="$TMP/queue/training" TEST_SPEED_CAMPAIGN_LEDGER="$ledger" \
    bash "$ROOT/scripts/test_speed_task_generator.sh" continue camp-quality 1 tests/unit/slow.bats 10 9 fixture pass cache 10 0 same same 9
  [ "$status" -eq 0 ]
  [ "$(awk -F '\t' '$1=="camp-quality" && $2==1 {n++} END{print n+0}' "$ledger")" -eq 2 ]
  [ "$(awk -F '\t' '$1=="camp-quality" && $2==1 {stop=$7} END{print stop}' "$ledger")" = '' ]
}

@test "round best preserves a faster previous best and existing campaign stop contracts" {
  ledger="$TMP/logs/previous-best.tsv"
  run env SHOGUN_REPO_ROOT="$TMP" TEST_SPEED_TASK_DIR="$TMP/queue/training" TEST_SPEED_CAMPAIGN_LEDGER="$ledger" \
    bash "$ROOT/scripts/test_speed_task_generator.sh" continue camp-prev 1 tests/unit/slow.bats 4.000 4.285 fixture pass cache 20 0 same same 5.196
  [ "$status" -eq 0 ]
  r2=$(printf '%s\n' "$output" | tail -n 1)
  grep -Fq 'round_index: 2' "$r2"
  grep -Fq 'min_rounds: 2' "$r2"
  grep -Fq 'max_rounds: 3' "$r2"
  grep -Fq 'campaign_budget_sec: 600' "$r2"
  grep -Fq 'best_wall: 4.000' "$r2"
  [ "$(awk -F '\t' '$1=="camp-prev" {print $4 ":" $5}' "$ledger")" = '4.000:5.196' ]
}

# test_necessity: floating-point campaign elapsed time must stop cleanly at the budget without shell integer errors.
@test "floating elapsed seconds are compared numerically for campaign budget" {
  ledger="$TMP/logs/float-budget.tsv"
  run env SHOGUN_REPO_ROOT="$TMP" TEST_SPEED_TASK_DIR="$TMP/queue/training" TEST_SPEED_CAMPAIGN_LEDGER="$ledger" \
    bash "$ROOT/scripts/test_speed_task_generator.sh" continue camp-float-budget 1 tests/unit/slow.bats 10 9 fixture pass cache 600.5 0 same same 9
  [ "$status" -eq 0 ]
  [ "$output" = 'STOP:budget' ]
  [ "$(awk -F '\t' '$1=="camp-float-budget" {print $7}' "$ledger")" = budget ]
}

@test "production deploy contract normalizes arbitrary direct YAML report metadata" {
  task="$TMP/queue/training/arbitrary.yaml"
  cat > "$task" <<'YAML'
task:
  parent_cmd: cmd_plain
  report_filename: caller_chosen.yaml
  report_path: queue/reports/caller_chosen.yaml
YAML
  extract_function() { sed -n "/^$1()/,/^}/p" "$ROOT/scripts/deploy_task.sh"; }
  source "$ROOT/scripts/lib/field_get.sh"
  source "$ROOT/scripts/lib/yaml_field_set.sh"
  eval "$(extract_function inject_report_filename)"
  eval "$(extract_function deploy_task_speed_campaign_report_is_explicit)"
  eval "$(extract_function deploy_task_normalize_report_metadata)"
  log() { :; }
  NINJA_NAME=hayate
  deploy_task_normalize_report_metadata "$task"
  grep -Fq 'report_filename: hayate_report_cmd_plain.yaml' "$task"
  ! grep -Fq 'caller_chosen.yaml' "$task"
}

@test "deteriorating round cannot adopt a different commit" {
  run env SHOGUN_REPO_ROOT="$TMP" TEST_SPEED_CAMPAIGN_LEDGER="$TMP/logs/campaign.tsv" \
    bash "$ROOT/scripts/test_speed_task_generator.sh" continue camp 1 t 10 15 retry pass cache 10 0 baseline changed
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK:deterioration_commit_adopted"* ]]
}

@test "campaign ledger serializes concurrent append and deduplicates one round" {
  ledger="$TMP/logs/campaign.tsv"
  for i in $(seq 1 12); do
    env SHOGUN_REPO_ROOT="$TMP" TEST_SPEED_CAMPAIGN_LEDGER="$ledger" \
      bash "$ROOT/scripts/test_speed_task_generator.sh" continue camp 3 t 10 9 "try$i" pass cache 10 0 >/dev/null &
  done
  wait
  [ "$(wc -l < "$ledger")" -eq 2 ]
  [ "$(awk -F '\t' '$1=="camp" && $2==3 {n++} END{print n+0}' "$ledger")" -eq 1 ]
}

@test "multi-round preserves best-so-far and rejects false improvement after deterioration" {
  ledger="$TMP/logs/campaign.tsv"
  run env SHOGUN_REPO_ROOT="$TMP" TEST_SPEED_TASK_DIR="$TMP/queue/training" TEST_SPEED_CAMPAIGN_LEDGER="$ledger" \
    bash "$ROOT/scripts/test_speed_task_generator.sh" continue camp 1 tests/unit/slow.bats 10 15 regression pass cache 120 20
  [ "$status" -eq 0 ]
  r2=$(printf '%s\n' "$output" | tail -n 1)
  grep -Fq 'round_index: 2' "$r2"
  grep -Fq 'best_wall: 10.000' "$r2"

  run env SHOGUN_REPO_ROOT="$TMP" TEST_SPEED_TASK_DIR="$TMP/queue/training" TEST_SPEED_CAMPAIGN_LEDGER="$ledger" \
    bash "$ROOT/scripts/test_speed_task_generator.sh" continue camp 2 tests/unit/slow.bats 10 12 retry pass cache 300 75
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLEAR_REQUIRED"* ]]
  r3=$(printf '%s\n' "$output" | tail -n 1)
  grep -Fq 'round_index: 3' "$r3"
  grep -Fq 'best_wall: 10.000' "$r3"
  [ "$(awk -F '\t' 'NR>1 && $4=="10.000" {n++} END{print n+0}' "$ledger")" -eq 2 ]
}

@test "multi-round records all four stop conditions" {
  ledger="$TMP/logs/campaign.tsv"
  run env SHOGUN_REPO_ROOT="$TMP" TEST_SPEED_CAMPAIGN_LEDGER="$ledger" bash "$ROOT/scripts/test_speed_task_generator.sh" continue cfail 1 t 10 10 x fail cache 1
  [[ "$output" == 'STOP:quality_fail' ]]
  run env SHOGUN_REPO_ROOT="$TMP" TEST_SPEED_CAMPAIGN_LEDGER="$ledger" bash "$ROOT/scripts/test_speed_task_generator.sh" continue cbudget 1 t 10 9 x pass cache 600
  [[ "$output" == 'STOP:budget' ]]
  run env SHOGUN_REPO_ROOT="$TMP" TEST_SPEED_CAMPAIGN_LEDGER="$ledger" bash "$ROOT/scripts/test_speed_task_generator.sh" continue cnone 2 t 10 9 x pass none 100
  [[ "$output" == 'STOP:no_next_dominant' ]]
  run env SHOGUN_REPO_ROOT="$TMP" TEST_SPEED_CAMPAIGN_LEDGER="$ledger" bash "$ROOT/scripts/test_speed_task_generator.sh" continue cmax 3 t 10 9 x pass cache 100
  [[ "$output" == 'STOP:max_rounds' ]]
}

@test "same-run AB accepts only dual-nonregression with one strict improvement and records evidence" {
  ledger="$TMP/logs/ab.tsv"
  run env SHOGUN_REPO_ROOT="$TMP" TEST_SPEED_TASK_DIR="$TMP/queue/training" TEST_SPEED_CAMPAIGN_LEDGER="$ledger" \
    bash "$ROOT/scripts/test_speed_task_generator.sh" continue cab 1 tests/unit/slow.bats 10 9 cache pass cache 10 0 base cand 9 base cand 'run same' 10 100 120 99 120
  [ "$status" -eq 0 ]
  [ "$(awk -F '\t' 'NR==2 {print $8":"$9":"$11":"$12":"$13":"$14":"$15}' "$ledger")" = 'base:cand:10:100:120:99:120' ]
  [[ "$output" != STOP:* ]]
}

@test "same-run AB blocks missing evidence and retains last-good on either metric regression" {
  run env SHOGUN_REPO_ROOT="$TMP" TEST_SPEED_CAMPAIGN_LEDGER="$TMP/logs/missing.tsv" \
    bash "$ROOT/scripts/test_speed_task_generator.sh" continue c 1 t 10 9 x pass cache 1 0 base cand 9 base cand '' 9 100 120 99 119
  [ "$status" -eq 2 ]; [[ "$output" == *'BLOCK:ab_evidence_missing'* ]]

  for metrics in '100 120 99 121' '100 120 101 119' '100 120 100 120'; do
    set -- $metrics
    ledger="$TMP/logs/regress-$1-$3.tsv"
    run env SHOGUN_REPO_ROOT="$TMP" TEST_SPEED_CAMPAIGN_LEDGER="$ledger" \
      bash "$ROOT/scripts/test_speed_task_generator.sh" continue "c$1$3" 1 t 10 9 x pass cache 1 0 base cand 9 base cand same 10 "$1" "$2" "$3" "$4"
    [ "$status" -eq 0 ]; [[ "$output" == 'STOP:ab_not_improved' ]]
    [ "$(awk -F '\t' 'NR==2 {print $4}' "$ledger")" = '10.000' ]
  done
}

@test "complete-deploy blocks identical commits invalid order warmup and sequence" {
  mkdir -p "$TMP/scripts"
  cp "$ROOT/scripts/test_speed_task_generator.sh" "$TMP/scripts/"
  task="$TMP/queue/training/ab-validation.yaml"
  cat > "$task" <<'YAML'
task:
  target_path: tests/unit/slow.bats
  speed_campaign: {campaign_id: ab-validation, round_index: 1, best_wall: 10, baseline_policy: same_run_interleaved_ab, baseline_commit: base}
YAML
  report="$TMP/queue/reports/ab-validation.yaml"
  python3 - "$report" <<'PY'
import yaml,sys
d={'commit_hash':'candidate','speed_result':{'last_wall':9,'approach':'cache','quality':'pass'},
   'test_results':[{'status':'PASS','failures':0,'skips':0,'wall_sec':9}],
   'speed_ab':{'last_good_commit':'base','candidate_commit':'candidate','command':'run same',
      'order':'alternating','warmup_each':1,'last_good_samples_ms':[100]*10,
      'candidate_samples_ms':[99]*10,'sequence':['L','C']*10}}
yaml.safe_dump(d,open(sys.argv[1],'w'))
PY
  for mutation in identical order warmup sequence; do
    cp "$report" "$report.$mutation"
    python3 - "$report.$mutation" "$mutation" <<'PY'
import sys,yaml
p=sys.argv[1]; k=sys.argv[2]; d=yaml.safe_load(open(p)); a=d['speed_ab']
if k=='identical': a['candidate_commit']=a['last_good_commit']
elif k=='order': a['order']='grouped'
elif k=='warmup': a['warmup_each']=0
else: a['sequence']=['L','L']*10
yaml.safe_dump(d,open(p,'w'))
PY
    run env SHOGUN_REPO_ROOT="$TMP" TEST_SPEED_CAMPAIGN_LEDGER="$TMP/logs/$mutation.tsv" \
      bash "$ROOT/scripts/test_speed_task_generator.sh" complete-deploy hayate "$task" "$report.$mutation"
    [ "$status" -ne 0 ]; [[ "$output" == *'BLOCK:ab_'* ]]
    [ ! -e "$TMP/logs/$mutation.tsv" ]
  done
}

@test "generator returns no candidate when completed evidence already claims target" {
  printf 'r\tx\tc\tunit\tbats\ttests/unit/slow.bats\t2\t12.5\tpass\t0\n' >> "$TMP/logs/test_timing_ledger.tsv"
  cat > "$TMP/queue/tasks/kotaro.yaml" <<YAML
task:
  task_id: cmd_speed_done
  target_path: "$TMP/tests/unit/slow.bats"
  status: done
YAML
  cat > "$TMP/queue/reports/kotaro_report_done.yaml" <<'YAML'
task_id: cmd_speed_done
status: completed
target_path: tests/unit/slow.bats
YAML
  run env SHOGUN_REPO_ROOT="$TMP" TEST_TIMING_LEDGER="$TMP/logs/test_timing_ledger.tsv" bash "$ROOT/scripts/test_speed_task_generator.sh" next
  [ "$status" -ne 0 ]
}

@test "generator preserves retry and active ownership semantics" {
  printf 'r\tx\tc\tunit\tbats\ttests/unit/slow.bats\t2\t12.5\tpass\t0\n' >> "$TMP/logs/test_timing_ledger.tsv"
  cat > "$TMP/queue/tasks/kotaro.yaml" <<'YAML'
task:
  task_id: cmd_speed_failed
  target_path: tests/unit/slow.bats
  status: failed
YAML
  run env SHOGUN_REPO_ROOT="$TMP" TEST_TIMING_LEDGER="$TMP/logs/test_timing_ledger.tsv" bash "$ROOT/scripts/test_speed_task_generator.sh" next
  [ "$status" -eq 0 ]

  sed -i 's/status: failed/status: in_progress/' "$TMP/queue/tasks/kotaro.yaml"
  run env SHOGUN_REPO_ROOT="$TMP" TEST_TIMING_LEDGER="$TMP/logs/test_timing_ledger.tsv" bash "$ROOT/scripts/test_speed_task_generator.sh" next
  [ "$status" -ne 0 ]
}

@test "candidate scan warns and continues across malformed and non-dict YAML" {
  printf 'r\tx\tc\tunit\tbats\ttests/unit/slow.bats\t2\t12.5\tpass\t0\n' >> "$TMP/logs/test_timing_ledger.tsv"
  printf -- '- scalar-root\n' > "$TMP/queue/tasks/scalar.yaml"
  printf 'task: [not, a, mapping]\n' > "$TMP/queue/tasks/list-task.yaml"
  printf 'task: {broken\n' > "$TMP/queue/reports/broken.yaml"
  cat > "$TMP/queue/tasks/other.yaml" <<'YAML'
task:
  target_path: tests/unit/other.bats
  status: in_progress
YAML

  run env SHOGUN_REPO_ROOT="$TMP" TEST_TIMING_LEDGER="$TMP/logs/test_timing_ledger.tsv" bash "$ROOT/scripts/test_speed_task_generator.sh" next
  [ "$status" -eq 0 ]
  [[ "$output" == *$'12.500\ttests/unit/slow.bats'* ]]
  [[ "$output" == *'invalid entries count=2'* ]]
  [[ "$output" == *'invalid entries count=1'* ]]
  [[ "$output" != *Traceback* ]]
}

@test "direct template injection preserves generated test-speed contract byte-for-byte" {
  printf 'r\tx\tc\tunit\tbats\ttests/unit/slow.bats\t2\t12.5\tpass\t0\n' >> "$TMP/logs/test_timing_ledger.tsv"
  run env SHOGUN_REPO_ROOT="$TMP" TEST_TIMING_LEDGER="$TMP/logs/test_timing_ledger.tsv" TEST_SPEED_TASK_DIR="$TMP/queue/training" bash "$ROOT/scripts/test_speed_task_generator.sh" generate
  [ "$status" -eq 0 ]
  generated="$output"
  before=$(sha256sum "$generated")

  run env DEPLOY_TASK_LIB_ONLY=1 bash -c '
    set -euo pipefail
    source "$1/scripts/deploy_task.sh"
    log() { :; }
    inject_direct_training_template "$2" cmd_training_test_speed_fixture
  ' _ "$ROOT" "$generated"
  [ "$status" -eq 0 ]
  [ "$(sha256sum "$generated")" = "$before" ]
  grep -Fq 'purpose: "round 1/3: last-good commitとcandidate commitを同一環境A/B交互測定' "$generated"
  grep -Fq 'baseline_policy: same_run_interleaved_ab' "$generated"
  grep -Fq 'quality_contract: "FAIL0; SKIP0;' "$generated"
  ! grep -Fq 'L4修行:' "$generated"
}

@test "canonical absolute and relative active targets remain claimed" {
  printf 'r\tx\tc\tunit\tbats\ttests/unit/slow.bats\t2\t12.5\tpass\t0\n' >> "$TMP/logs/test_timing_ledger.tsv"
  for task_status in assigned acknowledged in_progress; do
    for target in 'tests/unit/slow.bats' "$TMP/tests/unit/slow.bats"; do
      cat > "$TMP/queue/tasks/kotaro.yaml" <<YAML
task:
  target_path: "$target"
  status: $task_status
YAML
      run env SHOGUN_REPO_ROOT="$TMP" TEST_TIMING_LEDGER="$TMP/logs/test_timing_ledger.tsv" bash "$ROOT/scripts/test_speed_task_generator.sh" next
      [ "$status" -ne 0 ]
    done
  done
}

@test "parallel generate reserves one canonical target only" {
  printf 'r\tx\tc\tunit\tbats\ttests/unit/slow.bats\t2\t12.5\tpass\t0\n' >> "$TMP/logs/test_timing_ledger.tsv"
  env SHOGUN_REPO_ROOT="$TMP" TEST_TIMING_LEDGER="$TMP/logs/test_timing_ledger.tsv" TEST_SPEED_TASK_DIR="$TMP/queue/training" bash "$ROOT/scripts/test_speed_task_generator.sh" generate > "$TMP/first.out" &
  first_pid=$!
  env SHOGUN_REPO_ROOT="$TMP" TEST_TIMING_LEDGER="$TMP/logs/test_timing_ledger.tsv" TEST_SPEED_TASK_DIR="$TMP/queue/training" bash "$ROOT/scripts/test_speed_task_generator.sh" generate > "$TMP/second.out" &
  second_pid=$!
  wait "$first_pid" || true
  wait "$second_pid" || true

  [ "$(find "$TMP/queue/training" -name 'test_speed_*.yaml' -type f | wc -l)" -eq 1 ]
  [ "$(grep -l 'target_path: "tests/unit/slow.bats"' "$TMP"/queue/training/test_speed_*.yaml | wc -l)" -eq 1 ]
}

@test "latest ledger measurement controls threshold candidacy" {
  printf 'old\tx\tc\tunit\tbats\ttests/unit/stale.bats\t2\t99.0\tpass\t0\n' >> "$TMP/logs/test_timing_ledger.tsv"
  printf 'old\tx\tc\tunit\tbats\ttests/unit/current.bats\t2\t8.0\tpass\t0\n' >> "$TMP/logs/test_timing_ledger.tsv"
  printf 'new\tx\tc\tunit\tbats\ttests/unit/stale.bats\t2\t8.0\tpass\t0\n' >> "$TMP/logs/test_timing_ledger.tsv"
  printf 'new\tx\tc\tunit\tbats\ttests/unit/current.bats\t2\t14.0\tpass\t0\n' >> "$TMP/logs/test_timing_ledger.tsv"

  run env SHOGUN_REPO_ROOT="$TMP" TEST_TIMING_LEDGER="$TMP/logs/test_timing_ledger.tsv" bash "$ROOT/scripts/test_speed_task_generator.sh" next
  [ "$status" -eq 0 ]
  [[ "$output" == *$'14.000\ttests/unit/current.bats'* ]]
  [[ "$output" != *"stale.bats"* ]]
}

@test "generated lesson check is satisfiable for empty and nonempty related_lessons" {
  printf 'r\tx\tc\tunit\tbats\ttests/unit/slow.bats\t2\t12.5\tpass\t0\n' >> "$TMP/logs/test_timing_ledger.tsv"
  run env SHOGUN_REPO_ROOT="$TMP" TEST_TIMING_LEDGER="$TMP/logs/test_timing_ledger.tsv" TEST_SPEED_TASK_DIR="$TMP/queue/training" bash "$ROOT/scripts/test_speed_task_generator.sh" generate
  [ "$status" -eq 0 ]
  generated="$output"
  grep -Fq 'related_lessons: []' "$generated"
  grep -Fq 'related_lessonsが注入された場合のみ' "$generated"
  sed -i 's/related_lessons: \[\]/related_lessons: [{id: L001}]/' "$generated"
  grep -Fq 'related_lessons: [{id: L001}]' "$generated"
  grep -Fq 'related_lessonsが注入された場合のみ' "$generated"
}

@test "idle priority is reflux then script speed then test speed then legacy" {
  body=$(sed -n '/handle_confirmed_idle()/,/^}/p' "$ROOT/scripts/ninja_monitor.sh")
  order=$(printf '%s\n' "$body" | grep -oE '_schedule_reflux_auto_deploy_background|_handle_(speed_training|test_speed|training)_auto_deploy' | tr '\n' ' ')
  [ "$order" = "_schedule_reflux_auto_deploy_background _handle_speed_training_auto_deploy _handle_test_speed_auto_deploy _handle_training_auto_deploy " ]
}

@test "test speed auto-deploy only replaces an explicitly idle task" {
  mkdir -p "$TMP/scripts" "$TMP/queue/tasks" "$TMP/queue/reports"
  cat > "$TMP/scripts/test_speed_task_generator.sh" <<'SH'
#!/usr/bin/env bash
printf 'task:\n  status: assigned\n  ac_version: replacement\n' > "$SHOGUN_REPO_ROOT/queue/tasks/$2.yaml"
printf 'DEPLOYED\n'
SH
  chmod +x "$TMP/scripts/test_speed_task_generator.sh"
  function_body=$(sed -n '/^_handle_test_speed_auto_deploy()/,/^}/p' "$ROOT/scripts/ninja_monitor.sh")

  run env -i PATH="$PATH" HOME="$HOME" SHOGUN_REPO_ROOT="$TMP" bash -c '
    SCRIPT_DIR=$1
    yaml_field_get() { sed -n "s/^[[:space:]]*$2:[[:space:]]*//p" "$1" | head -n 1; }
    log() { :; }
    eval "$2"

    for task_status in done completed failed assigned acknowledged in_progress; do
      printf "task:\n  status: %s\n  ac_version: original-%s\n" \
        "$task_status" "$task_status" > "$1/queue/tasks/hayate.yaml"
      printf "status: completed\nac_version_read: original-%s\n" \
        "$task_status" > "$1/queue/reports/hayate_report_fixture.yaml"
      task_before=$(sha256sum "$1/queue/tasks/hayate.yaml")
      report_before=$(sha256sum "$1/queue/reports/hayate_report_fixture.yaml")

      if _handle_test_speed_auto_deploy hayate; then
        exit 1
      fi
      [ "$(sha256sum "$1/queue/tasks/hayate.yaml")" = "$task_before" ]
      [ "$(sha256sum "$1/queue/reports/hayate_report_fixture.yaml")" = "$report_before" ]
    done
  ' _ "$TMP" "$function_body"
  [ "$status" -eq 0 ]

  cat > "$TMP/queue/tasks/hayate.yaml" <<'YAML'
task:
  status: idle
  ac_version: original-idle
YAML
  run env -i PATH="$PATH" HOME="$HOME" SHOGUN_REPO_ROOT="$TMP" bash -c '
    SCRIPT_DIR=$1
    yaml_field_get() { sed -n "s/^[[:space:]]*$2:[[:space:]]*//p" "$1" | head -n 1; }
    log() { :; }
    eval "$2"
    _handle_test_speed_auto_deploy hayate
  ' _ "$TMP" "$function_body"
  [ "$status" -eq 0 ]
  grep -Fq 'status: assigned' "$TMP/queue/tasks/hayate.yaml"
  grep -Fq 'ac_version: replacement' "$TMP/queue/tasks/hayate.yaml"
}

@test "shared pause blocks generate deploy continue-deploy and complete-deploy without mutation" {
  mkdir -p "$TMP/scripts"
  printf 'global_status: paused\n' > "$TMP/logs/script_speed_training_ledger.yaml"
  printf 'r\tx\tc\tunit\tbats\ttests/unit/slow.bats\t2\t12.5\tpass\t0\n' >> "$TMP/logs/test_timing_ledger.tsv"
  cat > "$TMP/scripts/deploy_task.sh" <<'SH'
#!/usr/bin/env bash
printf deployed >> "$SHOGUN_REPO_ROOT/deployed"
SH
  chmod +x "$TMP/scripts/deploy_task.sh"
  task="$TMP/queue/training/r1.yaml"
  report="$TMP/queue/reports/r1.yaml"
  printf 'task:\n  speed_campaign: {}\n' > "$task"
  printf 'status: completed\n' > "$report"

  for invocation in \
    "generate" \
    "deploy hayate" \
    "continue-deploy hayate camp 1 t 10 9 x pass cache 1 0" \
    "complete-deploy hayate $task $report"; do
    before=$(find "$TMP/queue" -type f -printf '%p:%s\n' | sort | sha256sum)
    run env SHOGUN_REPO_ROOT="$TMP" bash "$ROOT/scripts/test_speed_task_generator.sh" $invocation
    [ "$status" -eq 3 ]
    [[ "$output" == *"PAUSED:"* ]]
    [ "$(find "$TMP/queue" -type f -printf '%p:%s\n' | sort | sha256sum)" = "$before" ]
    [ ! -e "$TMP/deployed" ]
  done
}

@test "monitor test-speed auto-deploy shares pause contract and running still deploys" {
  mkdir -p "$TMP/scripts" "$TMP/queue/tasks"
  cp "$ROOT/scripts/test_speed_task_generator.sh" "$TMP/scripts/"
  cat > "$TMP/scripts/deploy_task.sh" <<'SH'
#!/usr/bin/env bash
printf deployed > "$SHOGUN_REPO_ROOT/deployed"
SH
  chmod +x "$TMP/scripts/deploy_task.sh"
  printf 'r\tx\tc\tunit\tbats\ttests/unit/slow.bats\t2\t12.5\tpass\t0\n' >> "$TMP/logs/test_timing_ledger.tsv"
  printf 'task:\n  status: idle\n' > "$TMP/queue/tasks/hayate.yaml"
  function_body=$(sed -n '/^_handle_test_speed_auto_deploy()/,/^}/p' "$ROOT/scripts/ninja_monitor.sh")

  for state in paused broken; do
    printf 'global_status: %s\n' "$state" > "$TMP/logs/script_speed_training_ledger.yaml"
    run env -i PATH="$PATH" HOME="$HOME" SHOGUN_REPO_ROOT="$TMP" bash -c '
      SCRIPT_DIR=$1
      yaml_field_get() { sed -n "s/^[[:space:]]*$2:[[:space:]]*//p" "$1" | head -n 1; }
      log() { :; }
      eval "$2"
      _handle_test_speed_auto_deploy hayate
    ' _ "$TMP" "$function_body"
    [ "$status" -ne 0 ]
    [ ! -e "$TMP/deployed" ]
  done

  printf 'global_status: running\n' > "$TMP/logs/script_speed_training_ledger.yaml"
  run env -i PATH="$PATH" HOME="$HOME" SHOGUN_REPO_ROOT="$TMP" bash -c '
    SCRIPT_DIR=$1
    yaml_field_get() { sed -n "s/^[[:space:]]*$2:[[:space:]]*//p" "$1" | head -n 1; }
    log() { :; }
    eval "$2"
    _handle_test_speed_auto_deploy hayate
  ' _ "$TMP" "$function_body"
  [ "$status" -eq 0 ]
  [ -f "$TMP/deployed" ]
}

@test "active test-speed campaign suppresses recurrence auto-pause until callback" {
  function_body=$(sed -n '/^_speed_training_active_test_campaign()/,/^}/p' "$ROOT/scripts/ninja_monitor.sh")
  eval "$function_body"
  SCRIPT_DIR="$TMP"

  printf 'task:\n  parent_cmd: cmd_training_test_speed_fixture\n  status: in_progress\n' > "$TMP/queue/tasks/kagemaru.yaml"
  run _speed_training_active_test_campaign
  [ "$status" -eq 0 ]

  printf 'task:\n  parent_cmd: cmd_training_test_speed_fixture\n  status: idle\n' > "$TMP/queue/tasks/kagemaru.yaml"
  run _speed_training_active_test_campaign
  [ "$status" -ne 0 ]

  cat > "$TMP/queue/tasks/kagemaru.yaml" <<'YAML'
task:
  parent_cmd: cmd_training_test_speed_fixture
  status: done
  speed_campaign:
    campaign_id: cmd_training_test_speed_fixture
    round_index: 1
YAML
  run _speed_training_active_test_campaign
  [ "$status" -eq 0 ]

  printf 'campaign_id\tround_index\ncmd_training_test_speed_fixture\t1\n' > "$TMP/logs/test_speed_campaign_ledger.tsv"
  run _speed_training_active_test_campaign
  [ "$status" -ne 0 ]
}
