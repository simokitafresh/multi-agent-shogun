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

@test "inbox watcher dependency hash reloads when respawn helper changes" {
  repo="$BATS_TEST_DIRNAME/../.."
  grep -q 'scripts/lib/respawn_recovery.sh' "$repo/scripts/inbox_watcher.sh"
  cp "$repo/scripts/lib/respawn_recovery.sh" "$root/dep"
  run bash -c '
    source "$1/scripts/lib/script_update.sh"
    SCRIPT_PATH=/bin/true; SCRIPT_HASH=$(stat -c %Y /bin/true)
    WATCHED_DEPS=("$2/dep"); DEPS_HASH=$(compute_deps_hash)
    STARTUP_TIME=0; MIN_UPTIME=0
    touch -d "2030-01-01" "$2/dep"
    exec() { printf "RELOADED:%s\n" "$*"; }
    check_script_update watcher pane
  ' _ "$repo" "$root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RELOADED:/bin/true watcher pane"* ]]
}

@test "launch injects node PATH, active sender is karo, and unknown CTX is not ready" {
  repo="$BATS_TEST_DIRNAME/../.."
  run bash -c 'source "$1/scripts/lib/respawn_recovery.sh"; respawn_recovery_launch_command "$1" "/bin/codex"' _ "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *'PATH="/bin:$PATH"'* ]]

  run bash -c 'source "$1/scripts/lib/respawn_recovery.sh"; respawn_recovery_notify "$1" tester gen-sender clear' _ "$root"
  [ "$status" -eq 0 ]
  grep -q '|recovery|karo|continue_same_task' "$TEST_RECOVERY_LOG"

  mkdir -p "$root/proc/303"
  printf '303 (ready fixture) S 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 333 0\n' > "$root/proc/303/stat"
  cat > "$root/tmux-ready" <<'SH'
#!/usr/bin/env bash
case "$1:$*" in
  display-message:*pane_dead*) printf '0\n' ;;
  display-message:*) printf '303\n' ;;
  capture-pane:*) printf 'OpenAI Codex CTX:%s%%\n' "${FIXTURE_CTX:-?}" ;;
esac
SH
  chmod +x "$root/tmux-ready"
  export RESPAWN_RECOVERY_TMUX_BIN="$root/tmux-ready" RESPAWN_RECOVERY_PROC_ROOT="$root/proc"
  run bash -c 'source "$1/scripts/lib/respawn_recovery.sh"; respawn_recovery_ready pane' _ "$repo"
  [ "$status" -ne 0 ]
  export FIXTURE_CTX=0
  run bash -c 'source "$1/scripts/lib/respawn_recovery.sh"; respawn_recovery_ready pane' _ "$repo"
  [ "$status" -eq 0 ]
  sed -i 's/OpenAI Codex CTX:%s%%/OpenAI Codex Context %s%% used/' "$root/tmux-ready"
  run bash -c 'source "$1/scripts/lib/respawn_recovery.sh"; respawn_recovery_ready pane' _ "$repo"
  [ "$status" -eq 0 ]
}
