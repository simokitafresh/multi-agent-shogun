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
  grep -Fq 'FAIL0; SKIP0; no expectation relaxation' "$generated"
  grep -Fq 'shared fixture/cache first; switch to production script at plateau' "$generated"
}

@test "generator returns no candidate when completed evidence already claims target" {
  printf 'r\tx\tc\tunit\tbats\ttests/unit/slow.bats\t2\t12.5\tpass\t0\n' >> "$TMP/logs/test_timing_ledger.tsv"
  cat > "$TMP/queue/reports/kotaro_report_done.yaml" <<'YAML'
status: completed
target_path: tests/unit/slow.bats
YAML
  run env SHOGUN_REPO_ROOT="$TMP" TEST_TIMING_LEDGER="$TMP/logs/test_timing_ledger.tsv" bash "$ROOT/scripts/test_speed_task_generator.sh" next
  [ "$status" -ne 0 ]
}

@test "idle priority is reflux then test speed then script speed then legacy" {
  body=$(sed -n '/handle_confirmed_idle()/,/^}/p' "$ROOT/scripts/ninja_monitor.sh")
  order=$(printf '%s\n' "$body" | grep -E '_handle_(reflux|test_speed|speed_training|training)_auto_deploy' | sed -E 's/.*_handle_([^ ]+) .*/\1/' | tr '\n' ' ')
  [ "$order" = "reflux_auto_deploy test_speed_auto_deploy speed_training_auto_deploy training_auto_deploy " ]
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

  for task_status in done completed failed assigned acknowledged in_progress; do
    cat > "$TMP/queue/tasks/hayate.yaml" <<YAML
task:
  status: $task_status
  ac_version: original-$task_status
YAML
    printf 'status: completed\nac_version_read: original-%s\n' "$task_status" > "$TMP/queue/reports/hayate_report_fixture.yaml"
    task_before=$(sha256sum "$TMP/queue/tasks/hayate.yaml")
    report_before=$(sha256sum "$TMP/queue/reports/hayate_report_fixture.yaml")

    run env -i PATH="$PATH" HOME="$HOME" SHOGUN_REPO_ROOT="$TMP" bash -c '
      SCRIPT_DIR=$1
      yaml_field_get() { sed -n "s/^[[:space:]]*$2:[[:space:]]*//p" "$1" | head -n 1; }
      log() { :; }
      eval "$2"
      _handle_test_speed_auto_deploy hayate
    ' _ "$TMP" "$function_body"
    [ "$status" -ne 0 ]
    [ "$(sha256sum "$TMP/queue/tasks/hayate.yaml")" = "$task_before" ]
    [ "$(sha256sum "$TMP/queue/reports/hayate_report_fixture.yaml")" = "$report_before" ]
  done

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
