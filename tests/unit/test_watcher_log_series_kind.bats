#!/usr/bin/env bats
# test_necessity: inbox_watcherの[SEND-RESULT]/[SEND-LEASE]行は、どのfingerprint計算経路
# (unread集合fp / task_publication_fingerprint)を通ったかをkind=で自己申告し続ける

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

# 実スクリプトをlibとしてsourceし、実際のsend_wakeup/process_unreadの出力を得る。
# $1=inbox内unreadのtype, $2=queue/tasks/<agent>.yamlを置くか(yes/no), $3=process_unread回数
_run_watcher() {
    local msg_type="$1" with_task="$2" rounds="$3"
    bash -c '
set -euo pipefail
root="'"$PROJECT_ROOT"'"; msg_type="'"$msg_type"'"; with_task="'"$with_task"'"; rounds="'"$rounds"'"
tmp="$(mktemp -d)"; trap "rm -rf \"$tmp\"" EXIT
mkdir -p "$tmp/root/scripts/lib" "$tmp/root/lib" "$tmp/root/queue/inbox" "$tmp/root/queue/tasks" "$tmp/state"
for f in lock_path.sh cli_lookup.sh tmux_utils.sh script_update.sh inbox_nudge_policy.sh respawn_recovery.sh; do
  ln -s "$root/scripts/lib/$f" "$tmp/root/scripts/lib/$f"
done
ln -s "$root/lib/agent_state.sh" "$tmp/root/lib/agent_state.sh"
ln -s "$root/scripts/inbox_watcher.sh" "$tmp/root/scripts/inbox_watcher.sh"
agent=kind_fixture
cat > "$tmp/root/queue/inbox/$agent.yaml" <<YAML
messages:
- id: msg_kind_fixture_1
  type: $msg_type
  read: false
  content: fixture
YAML
if [ "$with_task" = "yes" ]; then
cat > "$tmp/root/queue/tasks/$agent.yaml" <<YAML
task:
  task_id: cmd_kind_fixture_normal
  deployed_at: "2026-07-26T14:00:00"
YAML
fi
export SHOGUN_STATE_DIR="$tmp/state" INBOX_WATCHER_LIB_ONLY=1
source "$tmp/root/scripts/inbox_watcher.sh" "$agent" dummy-pane
unset INBOX_WATCHER_LIB_ONLY
get_effective_cli_type() { echo codex; }
agent_has_self_watch() { return 1; }
check_agent_busy() { return 0; }
sleep() { :; }
timeout() { shift; "$@"; }
tmux() {
  case "$1" in
    display-message)
      case "${*: -1}" in
        *agent_id*) echo "$agent" ;;
        *) echo idle ;;
      esac ;;
    *) : ;;
  esac
}
i=0; while [ "$i" -lt "$rounds" ]; do process_unread; i=$((i+1)); done
' 2>&1
}

@test "AC3/AC4(i): inbox系列(unread集合fingerprint)の行に kind=inbox が付く" {
    run _run_watcher report_received no 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"[SEND-RESULT] attempted"*"kind=inbox"* ]]
    [[ "$output" == *"[SEND-RESULT] pasted"*"kind=inbox"* ]]
    # 実出力にtask系列が混入していないこと(陰性対照)
    [[ "$output" != *"kind=task"* ]]
}

@test "AC3/AC4(ii): task系列(task_publication_fingerprint)の行に kind=task が付く" {
    run _run_watcher task_assigned yes 2
    [ "$status" -eq 0 ]
    # 1回目: 送信行はin-lock再取得後のtask fp
    [[ "$output" == *"[SEND-RESULT] pasted"*"fingerprint=task-"*"kind=task"* ]]
    # 2回目: 同一task fpはlease済み → SEND-LEASE行にkind=task
    [[ "$output" == *"[SEND-LEASE] Skipping delivered fingerprint"*"task-"*"kind=task"* ]]
}

@test "AC3: 本日の実例2行はkind=を見るだけで別系列と機械判定できる" {
    run _run_watcher task_assigned yes 2
    [ "$status" -eq 0 ]
    # 誤読の実例と同じ隣接(attempted → Skipping)が再現し、kind=が両者を分離する
    local attempted_kind lease_kind
    attempted_kind=$(printf '%s\n' "$output" | grep -m1 '\[SEND-RESULT\] attempted' | grep -o 'kind=[a-z]*')
    lease_kind=$(printf '%s\n' "$output" | grep -m1 '\[SEND-LEASE\] Skipping' | grep -o 'kind=[a-z]*')
    [ "$attempted_kind" = "kind=inbox" ]
    [ "$lease_kind" = "kind=task" ]
    [ "$attempted_kind" != "$lease_kind" ]
}

@test "AC4: kind=は行末に追加され既存フィールドの順序を変えない" {
    run _run_watcher report_received no 1
    [ "$status" -eq 0 ]
    # 既存解析が依拠する前置フィールド順(agent= → observed_count= → fingerprint=)が不変
    [[ "$output" =~ \[SEND-RESULT\]\ attempted\ agent=[a-z_]+\ observed_count=[0-9]+\ fingerprint=[a-z0-9-]+\ kind=[a-z]+ ]]
}
