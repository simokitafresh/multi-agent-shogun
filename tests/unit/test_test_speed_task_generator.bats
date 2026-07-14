#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/logs" "$TMP/queue/tasks" "$TMP/queue/reports" "$TMP/queue/archive/reports" "$TMP/queue/training"
  printf 'run_id\trepo\tcommit_sha\tsuite_root\trunner\ttest_file\ttest_id_count\twall_sec\tstatus\tskip_count\n' > "$TMP/logs/test_timing_ledger.tsv"
}
teardown() { rm -rf "$TMP"; }

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
