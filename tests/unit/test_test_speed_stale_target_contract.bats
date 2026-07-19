#!/usr/bin/env bats
# test_necessity: Speed generation must exclude timing targets absent from the worktree or baseline HEAD so an impossible A/B task is never deployed.
# regression_justification: overlaps_existing=true; generic candidate tests did not model default-delete racing a historical timing ledger.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  TMP="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$TMP/logs" "$TMP/queue/tasks" "$TMP/queue/reports" \
    "$TMP/queue/archive/reports" "$TMP/queue/training" "$TMP/tests/unit"
  printf 'run_id\trepo\tcommit_sha\tsuite_root\trunner\ttest_file\ttest_id_count\twall_sec\tstatus\tskip_count\n' > "$TMP/logs/test_timing_ledger.tsv"
  printf 'global_status: running\n' > "$TMP/logs/script_speed_training_ledger.yaml"
}

@test "missing worktree target is skipped before campaign reservation" {
  touch "$TMP/tests/unit/live.bats"
  printf 'old\tx\tc\tunit\tbats\ttests/unit/deleted.bats\t2\t99.0\tpass\t0\n' >> "$TMP/logs/test_timing_ledger.tsv"
  printf 'new\tx\tc\tunit\tbats\ttests/unit/live.bats\t2\t12.0\tpass\t0\n' >> "$TMP/logs/test_timing_ledger.tsv"

  run env SHOGUN_REPO_ROOT="$TMP" TEST_TIMING_LEDGER="$TMP/logs/test_timing_ledger.tsv" \
    bash "$ROOT/scripts/test_speed_task_generator.sh" next

  [ "$status" -eq 0 ]
  [[ "$output" == *'stale timing target skipped target=tests/unit/deleted.bats'* ]]
  [[ "$output" == *$'12.000\ttests/unit/live.bats'* ]]
  [[ "$output" != *$'99.000\ttests/unit/deleted.bats'* ]]
}

@test "worktree-only target missing from baseline HEAD is skipped" {
  git -C "$TMP" init -q
  git -C "$TMP" config user.email contract@example.invalid
  git -C "$TMP" config user.name contract
  touch "$TMP/tests/unit/tracked.bats"
  git -C "$TMP" add tests/unit/tracked.bats
  git -C "$TMP" commit -qm baseline
  touch "$TMP/tests/unit/untracked.bats"
  printf 'new\tx\tc\tunit\tbats\ttests/unit/untracked.bats\t2\t99.0\tpass\t0\n' >> "$TMP/logs/test_timing_ledger.tsv"
  printf 'new\tx\tc\tunit\tbats\ttests/unit/tracked.bats\t2\t12.0\tpass\t0\n' >> "$TMP/logs/test_timing_ledger.tsv"

  run env SHOGUN_REPO_ROOT="$TMP" TEST_TIMING_LEDGER="$TMP/logs/test_timing_ledger.tsv" \
    bash "$ROOT/scripts/test_speed_task_generator.sh" next

  [ "$status" -eq 0 ]
  [[ "$output" == *'stale timing target skipped target=tests/unit/untracked.bats'* ]]
  [[ "$output" == *$'12.000\ttests/unit/tracked.bats'* ]]
}

@test "round emission blocks when a previously selected target disappears" {
  run env SHOGUN_REPO_ROOT="$TMP" TEST_SPEED_TASK_DIR="$TMP/queue/training" \
    bash "$ROOT/scripts/test_speed_task_generator.sh" continue campaign 1 tests/unit/deleted.bats 12 11 cache pass cache 1 0

  [ "$status" -eq 2 ]
  [[ "$output" == *'BLOCK:target_not_measurable'* ]]
  [ "$(find "$TMP/queue/training" -name 'test_speed_*.yaml' -type f | wc -l)" -eq 0 ]
}
