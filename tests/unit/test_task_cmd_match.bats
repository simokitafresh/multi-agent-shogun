#!/usr/bin/env bats

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  TMPROOT=$(mktemp -d)
  mkdir -p "$TMPROOT/tasks"
  source "$ROOT/scripts/lib/task_cmd_match.sh"
}

teardown() {
  rm -rf "$TMPROOT"
}

@test "exact parent cmd excludes prefixed recon child" {
  printf 'task:\n  parent_cmd: cmd_3878\n' > "$TMPROOT/tasks/main.yaml"
  printf 'task:\n  parent_cmd: cmd_3878_recon3\n' > "$TMPROOT/tasks/child.yaml"

  run list_task_files_for_cmd "$TMPROOT/tasks" cmd_3878

  [ "$status" -eq 0 ]
  [ "$output" = "$TMPROOT/tasks/main.yaml" ]
}

@test "quoted exact cmd_id and trailing comment are accepted" {
  printf 'task:\n  cmd_id: "cmd_3878" # current\n' > "$TMPROOT/tasks/quoted.yaml"

  run task_file_matches_cmd "$TMPROOT/tasks/quoted.yaml" cmd_3878

  [ "$status" -eq 0 ]
}

@test "regex metacharacters in id are matched literally" {
  printf 'task:\n  parent_cmd: cmd_test.a\n' > "$TMPROOT/tasks/literal.yaml"
  printf 'task:\n  parent_cmd: cmd_testXa\n' > "$TMPROOT/tasks/other.yaml"

  run list_task_files_for_cmd "$TMPROOT/tasks" 'cmd_test.a'

  [ "$status" -eq 0 ]
  [ "$output" = "$TMPROOT/tasks/literal.yaml" ]
}
