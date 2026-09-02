#!/usr/bin/env bats
# test_necessity: U7 must keep every legacy runtime push path inert while the
# publisher owns origin publication; the default-off path must remain callable.
# regression_justification: without an executable flag contract, the legacy
# autopush and push-lane paths can publish concurrently with the publisher.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  GATE="$ROOT/scripts/cmd_complete_gate.sh"
  MON="$ROOT/scripts/ninja_monitor.sh"
  SAFE="$ROOT/scripts/safe_shared_main_ff.sh"
  FLAG="$ROOT/queue/flags/publisher_single"
  source "$ROOT/scripts/lib/publisher_single_flag.sh"
  export ROOT
  export -f publisher_single_enabled
  export PUSH_LANE_LOG="$BATS_TEST_TMPDIR/push-lane.log"
  : > "$PUSH_LANE_LOG"
}

@test "PUBLISHER_SINGLE=1 disables cmd_complete_gate autopush and direct source push" {
  gate_functions="$(sed -n '/^push_from_clean_worktree()/,/^}/p; /^push_task_repositories()/,/^}/p' "$GATE")"
  run bash -c "$gate_functions
PUBLISHER_SINGLE=1 push_task_repositories
PUBLISHER_SINGLE=1 push_from_clean_worktree repo origin/main origin refs/heads/main deadbeef source
"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^PUBLISHER_SINGLE cmd_complete_gate push=0 result=SKIP reason=publisher_request$' <<<"$output")" -eq 2 ]
}

@test "PUBLISHER_SINGLE=1 disables push_lane publication with one log row" {
  monitor_function="$(sed -n '/^push_lane_publish_one()/,/^}/p' "$MON")"
  run bash -c "push_lane_log() { printf '%s\\n' \"\$1\" >> \"$PUSH_LANE_LOG\"; }
export -f push_lane_log
$monitor_function
PUBLISHER_SINGLE=1 push_lane_publish_one repo origin deadbeef
"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^PUBLISHER_SINGLE push_lane push=0 result=SKIP reason=publisher_request$' "$PUSH_LANE_LOG")" -eq 1 ]
}

@test "PUBLISHER_SINGLE=1 disables both safe_shared_main_ff push paths" {
  auto_output="$(PUBLISHER_SINGLE=1 bash "$SAFE" --auto-push-if-ready /does/not/exist GREEN)"
  [ "$auto_output" = "PUBLISHER_SINGLE safe_shared_main_ff push=0 result=SKIP reason=publisher_request" ]

  fallback_function="$(sed -n '/^isolated_publish_fallback()/,/^}/p' "$SAFE")"
  run bash -c "$fallback_function
PUBLISHER_SINGLE=1 isolated_publish_fallback deadbeef
"
  [ "$status" -eq 0 ]
  [ "$output" = "PUBLISHER_SINGLE safe_shared_main_ff push=0 result=SKIP reason=publisher_request" ]
}

@test "PUBLISHER_SINGLE unset retains the normal safe auto-push path" {
  repo="$BATS_TEST_TMPDIR/repo"
  origin="$BATS_TEST_TMPDIR/origin.git"
  git init -q --bare "$origin"
  git init -q -b main "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name test
  printf 'base\n' > "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -qm base
  git -C "$repo" remote add origin "$origin"
  git -C "$repo" push -q -u origin main
  printf 'next\n' >> "$repo/file.txt"
  git -C "$repo" commit -qam next

  run env -u PUBLISHER_SINGLE SAFE_SHARED_MAIN_FF_AUTO_PUSH_THRESHOLD=1 bash "$SAFE" --auto-push-if-ready "$repo" GREEN
  [ "$status" -eq 0 ]
  [[ "$output" == *"push=1"* ]]
  [ "$(git --git-dir "$origin" rev-parse refs/heads/main)" = "$(git -C "$repo" rev-parse HEAD)" ]
}

@test "publisher flag file disables three legacy paths and removal restores them" {
  mkdir -p "$(dirname "$FLAG")"
  : > "$FLAG"

  gate_functions="$(sed -n '/^push_from_clean_worktree()/,/^}/p; /^push_task_repositories()/,/^}/p' "$GATE")"
  run bash -c "$gate_functions
unset PUBLISHER_SINGLE
push_task_repositories
push_from_clean_worktree repo origin/main origin refs/heads/main deadbeef source
"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^PUBLISHER_SINGLE cmd_complete_gate push=0 result=SKIP reason=publisher_request$' <<<"$output")" -eq 2 ]

  monitor_function="$(sed -n '/^push_lane_publish_one()/,/^}/p' "$MON")"
  run bash -c "push_lane_log() { printf '%s\\n' \"\$1\" >> \"$PUSH_LANE_LOG\"; }
export -f push_lane_log
$monitor_function
unset PUBLISHER_SINGLE
push_lane_publish_one repo origin deadbeef
"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^PUBLISHER_SINGLE push_lane push=0 result=SKIP reason=publisher_request$' "$PUSH_LANE_LOG")" -eq 1 ]

  repo="$BATS_TEST_TMPDIR/flag-file-repo"
  origin="$BATS_TEST_TMPDIR/flag-file-origin.git"
  git init -q --bare "$origin"
  git init -q -b main "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name test
  printf 'base\n' > "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -qm base
  git -C "$repo" remote add origin "$origin"
  git -C "$repo" push -q -u origin main
  printf 'next\n' >> "$repo/file.txt"
  git -C "$repo" commit -qam next

  auto_output="$(env -u PUBLISHER_SINGLE bash "$SAFE" --auto-push-if-ready "$repo" GREEN)"
  [ "$auto_output" = "PUBLISHER_SINGLE safe_shared_main_ff push=0 result=SKIP reason=publisher_request" ]

  rm -f "$FLAG"
  run env -u PUBLISHER_SINGLE SAFE_SHARED_MAIN_FF_AUTO_PUSH_THRESHOLD=1 bash "$SAFE" --auto-push-if-ready "$repo" GREEN
  [ "$status" -eq 0 ]
  [[ "$output" == *"push=1"* ]]
  [ "$(git --git-dir "$origin" rev-parse refs/heads/main)" = "$(git -C "$repo" rev-parse HEAD)" ]
}
