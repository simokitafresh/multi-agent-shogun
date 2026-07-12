#!/usr/bin/env bats
setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd); T=$(mktemp -d)
  mkdir -p "$T/queue/archive/cmds" "$T/queue/archive/reports" "$T/queue/tasks" "$T/queue/gates/cmd_3869/review_approvals" "$T/logs"
  printf 'commands:\n  cmd_3869:\n    status: completed\n' > "$T/queue/archive/cmds/cmd_3869_completed_x.yaml"
  printf 'task:\n  parent_cmd: cmd_3869\n  status: done\n' > "$T/queue/tasks/ninja.yaml"
  printf 'worker_id: ninja\nparent_cmd: cmd_3869\nstatus: completed\n' > "$T/queue/archive/reports/ninja_report_cmd_3869.yaml"
  touch "$T/queue/gates/cmd_3869/archive.done" "$T/queue/gates/cmd_3869/completion_notified.done" "$T/queue/gates/cmd_3869/review_approvals/a"
  printf 'old\tcmd_3869\tCLEAR\n' > "$T/logs/gate_metrics.log"
}
teardown() { rm -rf "$T"; }
@test "dry-run changes zero files and reopen invalidates every completion layer" {
  before=$(find "$T" -type f -exec sha256sum {} + | sort | sha256sum)
  run env CMD_REOPEN_ROOT="$T" bash "$ROOT/scripts/cmd_reopen.sh" --dry-run cmd_3869; [ "$status" -eq 0 ]
  after=$(find "$T" -type f -exec sha256sum {} + | sort | sha256sum); [ "$before" = "$after" ]
  run env CMD_REOPEN_ROOT="$T" bash "$ROOT/scripts/cmd_reopen.sh" cmd_3869; [ "$status" -eq 0 ]
  [ -f "$T/queue/reopened_cmds/cmd_3869.yaml" ]; [ ! -e "$T/queue/gates/cmd_3869/archive.done" ]; [ ! -e "$T/queue/gates/cmd_3869/completion_notified.done" ]; [ ! -d "$T/queue/gates/cmd_3869/review_approvals" ]
  run tail -1 "$T/logs/gate_metrics.log"; [[ "$output" == *$'cmd_3869\tREOPEN'* ]]
}
