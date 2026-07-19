#!/usr/bin/env bats
# test_necessity: verified respawn must emit one durable recovery per active task generation without mutating task state.

setup() {
  root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root/scripts/lib" "$root/queue/tasks" "$root/queue/inbox" "$root/state"
  cp "$BATS_TEST_DIRNAME/../../scripts/lib/respawn_recovery.sh" "$root/scripts/lib/"
  cat > "$root/scripts/inbox_write.sh" <<'SH'
#!/usr/bin/env bash
printf '%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5" >> "$TEST_RECOVERY_LOG"
SH
  chmod +x "$root/scripts/inbox_write.sh"
  cat > "$root/queue/tasks/tester.yaml" <<'YAML'
task:
  status: in_progress
  parent_cmd: cmd_parent
  task_id: task_1
YAML
  export TEST_RECOVERY_LOG="$root/recovery.log"
  export RESPAWN_RECOVERY_STATE_DIR="$root/state"
}

@test "active task is notified once per generation and task remains unchanged" {
  before=$(sha256sum "$root/queue/tasks/tester.yaml" | cut -d' ' -f1)
  run bash -c 'source "$1/scripts/lib/respawn_recovery.sh"; respawn_recovery_notify "$1" tester generation-1 clear; respawn_recovery_notify "$1" tester generation-1 clear; respawn_recovery_notify "$1" tester generation-2 dead' _ "$root"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$TEST_RECOVERY_LOG")" -eq 2 ]
  [ "$before" = "$(sha256sum "$root/queue/tasks/tester.yaml" | cut -d' ' -f1)" ]
  [ "$(grep -c 'parent_cmd=cmd_parent task_id=task_1' "$TEST_RECOVERY_LOG")" -eq 2 ]
}

@test "idle and done tasks produce no notification" {
  sed -i 's/in_progress/idle/' "$root/queue/tasks/tester.yaml"
  run bash -c 'source "$1/scripts/lib/respawn_recovery.sh"; respawn_recovery_notify "$1" tester generation-1 clear' _ "$root"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_RECOVERY_LOG" ]
  sed -i 's/idle/done/' "$root/queue/tasks/tester.yaml"
  run bash -c 'source "$1/scripts/lib/respawn_recovery.sh"; respawn_recovery_notify "$1" tester generation-2 dead' _ "$root"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_RECOVERY_LOG" ]
}

@test "missing generation fails closed" {
  run bash -c 'source "$1/scripts/lib/respawn_recovery.sh"; respawn_recovery_notify "$1" tester unknown clear' _ "$root"
  [ "$status" -ne 0 ]
  [ ! -e "$TEST_RECOVERY_LOG" ]
}

@test "all respawn boundaries use shared recovery and clear_command has no direct clear" {
  repo="$BATS_TEST_DIRNAME/../.."
  run grep -q 'respawn_recovery_notify' "$repo/scripts/respawn_dead_agent.sh"
  [ "$status" -eq 0 ]
  run grep -q 'clear-command' "$repo/scripts/inbox_watcher.sh"
  [ "$status" -eq 0 ]
  run grep -q 'cli-dead' "$repo/scripts/ninja_monitor.sh"
  [ "$status" -eq 0 ]
  run grep -F 'send_cli_command "/clear"' "$repo/scripts/inbox_watcher.sh"
  [ "$status" -ne 0 ]
  run grep -R 'deploy_task.sh' "$root"
  [ "$status" -ne 0 ]
}

@test "taskless safe recovery content is durable once and dangerous content is rejected" {
  rm "$root/queue/tasks/tester.yaml"
  run bash -c 'source "$1/scripts/lib/respawn_recovery.sh"; respawn_recovery_notify "$1" tester generation-1 clear "安全な復帰指示"; respawn_recovery_notify "$1" tester generation-1 clear "安全な復帰指示"' _ "$root"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$TEST_RECOVERY_LOG")" -eq 1 ]
  grep -q '安全な復帰指示' "$TEST_RECOVERY_LOG"
  run bash -c 'source "$1/scripts/lib/respawn_recovery.sh"; respawn_recovery_notify "$1" tester generation-2 clear "bad;command"' _ "$root"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$TEST_RECOVERY_LOG")" -eq 1 ]
}

@test "real tmux pane generation is nonempty and pid-starttime fixture changes by respawn" {
  repo="$BATS_TEST_DIRNAME/../.."
  run bash -c 'source "$1/scripts/lib/respawn_recovery.sh"; respawn_recovery_generation "$TMUX_PANE"' _ "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+:[0-9]+$ ]]

  mkdir -p "$root/proc/101" "$root/proc/202"
  printf '101 (fixture one) S 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 111 0\n' > "$root/proc/101/stat"
  printf '202 (fixture two) S 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 222 0\n' > "$root/proc/202/stat"
  printf '#!/usr/bin/env bash\ncat "$RESPAWN_PID_FILE"\n' > "$root/tmux-fixture"
  chmod +x "$root/tmux-fixture"
  printf '101\n' > "$root/pid"
  export RESPAWN_PID_FILE="$root/pid" RESPAWN_RECOVERY_TMUX_BIN="$root/tmux-fixture" RESPAWN_RECOVERY_PROC_ROOT="$root/proc"
  run bash -c 'source "$1/scripts/lib/respawn_recovery.sh"; respawn_recovery_generation pane' _ "$repo"
  [ "$output" = "101:111" ]
  printf '202\n' > "$root/pid"
  run bash -c 'source "$1/scripts/lib/respawn_recovery.sh"; respawn_recovery_generation pane' _ "$repo"
  [ "$output" = "202:222" ]
}
