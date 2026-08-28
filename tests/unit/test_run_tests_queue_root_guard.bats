#!/usr/bin/env bats
# test_necessity: run_tests.sh must reject fixture execution that resolves its
# queue root to the production queue while accepting an isolated mktemp root.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  RUNNER="$ROOT/scripts/run_tests.sh"
  PRODUCTION="$BATS_TEST_TMPDIR/production"
  FIXTURE="$BATS_TEST_TMPDIR/fixture"
  mkdir -p "$PRODUCTION/queue/tasks" "$PRODUCTION/queue/reports" "$FIXTURE/queue/tasks" "$FIXTURE/queue/reports"
}

@test "production queue root is rejected for fixture execution" {
  run env -u RUN_TESTS_QUEUE_ROOT_GUARD_CHECKED REPO_ROOT="$PRODUCTION" RUN_TESTS_FIXTURE_ROOT="$FIXTURE" \
    RUN_TESTS_PRODUCTION_QUEUE_ROOT="$PRODUCTION/queue" \
    bash -c 'source "$1"; run_tests_queue_root_guard' _ "$RUNNER"
  [ "$status" -eq 2 ]
  [[ "$output" == *"writable_matching_paths=1"* ]]
  [[ "$output" == *"BLOCK: run_tests fixture queue root resolves to production queue"* ]]
}

@test "isolated mktemp queue root is accepted" {
  run env -u RUN_TESTS_QUEUE_ROOT_GUARD_CHECKED REPO_ROOT="$FIXTURE" RUN_TESTS_FIXTURE_ROOT="$FIXTURE" \
    RUN_TESTS_PRODUCTION_QUEUE_ROOT="$PRODUCTION/queue" \
    bash -c 'source "$1"; run_tests_queue_root_guard' _ "$RUNNER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"resolved_queue_root=$FIXTURE/queue"* ]]
  [[ "$output" == *"writable_matching_paths=0"* ]]
  [[ "$output" != *"BLOCK:"* ]]
}
