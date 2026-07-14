#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  TMP="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$TMP/logs" "$TMP/queue/tasks" "$TMP/queue/reports" "$TMP/queue/archive/reports" "$TMP/queue/training"
  printf 'run_id\trepo\tcommit_sha\tsuite_root\trunner\ttest_file\ttest_id_count\twall_sec\tstatus\tskip_count\n' > "$TMP/logs/test_timing_ledger.tsv"
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
  grep -Fq 'baseline_policy: best_so_far' "$generated"
  grep -Fq 'report_filename: "test_speed_report_' "$generated"
  grep -Fq 'action: "complete-deploy"' "$generated"
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
log() { :; }
NINJA_NAME="\$4"
cp "\$3" "$TMP/queue/tasks/\$4.yaml"
deploy_task_normalize_report_metadata "$TMP/queue/tasks/\$4.yaml"
report=\$(FIELD_GET_NO_LOG=1 field_get "$TMP/queue/tasks/\$4.yaml" report_path "")
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
  order=$(printf '%s\n' "$body" | grep -E '_handle_(reflux|test_speed|speed_training|training)_auto_deploy' | sed -E 's/.*_handle_([^ ]+) .*/\1/' | tr '\n' ' ')
  [ "$order" = "reflux_auto_deploy speed_training_auto_deploy test_speed_auto_deploy training_auto_deploy " ]
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
