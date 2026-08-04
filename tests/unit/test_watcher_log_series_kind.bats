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
if [ "$with_task" = "broken" ]; then
# task_assignedはあるが task_publication_fingerprint が identity を作れない形(deployed_atなし)
cat > "$tmp/root/queue/tasks/$agent.yaml" <<YAML
task:
  task_id: cmd_kind_fixture_normal
YAML
elif [ "$with_task" = "yes" ]; then
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

# test_necessity: 同一taskへの新しい未読指示はmessage集合が変われば再度nudgeされる。
@test "same task generation gets a new fingerprint when unread message set changes" {
    run bash -c '
set -euo pipefail
tmp="$(mktemp -d)"; trap "rm -rf \"$tmp\"" EXIT
mkdir -p "$tmp/queue/tasks"
cat > "$tmp/queue/tasks/kagemaru.yaml" <<YAML
task:
  task_id: cmd_same_task
  deployed_at: "2026-08-01T03:00:00"
YAML
export INBOX_WATCHER_LIB_ONLY=1 SHOGUN_STATE_DIR="$tmp/state"
source "'"$PROJECT_ROOT"'/scripts/inbox_watcher.sh" kagemaru dummy-pane
SCRIPT_DIR="$tmp"
first=$(task_publication_fingerprint unread_set_one)
same=$(task_publication_fingerprint unread_set_one)
second=$(task_publication_fingerprint unread_set_two)
printf "same=%s changed=%s\n" "$([[ "$first" = "$same" ]] && echo yes || echo no)" "$([[ "$first" != "$second" ]] && echo yes || echo no)"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"same=yes changed=yes"* ]]
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

@test "AC2: kindはfingerprintの文字列ではなく代入位置で決まる(task fp生成に失敗すればkind=inbox)" {
    # task_assignedがあってもtask_publication_fingerprintがidentityを作れなければ
    # current_fpはunread集合fpのまま。kindはその代入に追従しなければならない。
    run _run_watcher task_assigned broken 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"[SEND-RESULT] pasted"*"kind=inbox"* ]]
    [[ "$output" != *"fingerprint=task-"* ]]
}

@test "AC2: 実装はfingerprintの接頭辞から系列を推定しない" {
    # 系列名はcurrent_fpへの代入位置(entry / live_fp / task_publication_fingerprint)で立て、
    # 出力へ持ち回る。fingerprint文字列を見て系列を判定するコードがあってはならない。
    run grep -nE 'task-\*\)|= *"task-|=~ *\^task-|\$\{[a-z_]+#task-\}' "$PROJECT_ROOT/scripts/inbox_watcher.sh"
    [ "$status" -ne 0 ]
}

@test "AC3: attempted行の系列は分岐前でも未確定ではない — 唯一の呼び出し元がunread集合fpを渡す" {
    # attempted(:1004)は再取得分岐(:1019-1024)より前にあるが、send_wakeupの呼び出しは1箇所のみで、
    # そこで渡されるのはget_unread_infoのunread集合fpである。∴entry時点でinbox系列が確定している。
    run grep -cE '^[[:space:]]*send_wakeup "' "$PROJECT_ROOT/scripts/inbox_watcher.sh"
    [ "$output" = "1" ]
    run grep -nE '^[[:space:]]*send_wakeup "\$normal_count" "\$has_task_assigned" "\$_current_fp"' "$PROJECT_ROOT/scripts/inbox_watcher.sh"
    [ "$status" -eq 0 ]
    # _current_fp は get_unread_info の出力から読まれた値であり、task fpではない
    run grep -nE 'read -r normal_count has_specials _current_fp' "$PROJECT_ROOT/scripts/inbox_watcher.sh"
    [ "$status" -eq 0 ]
}

@test "AC4: kind=は行末に追加され既存フィールドの順序を変えない" {
    run _run_watcher report_received no 1
    [ "$status" -eq 0 ]
    # 既存解析が依拠する前置フィールド順(agent= → observed_count= → fingerprint=)が不変
    [[ "$output" =~ \[SEND-RESULT\]\ attempted\ agent=[a-z_]+\ observed_count=[0-9]+\ fingerprint=[a-z0-9-]+\ kind=[a-z]+ ]]
}

# test_necessity: generic watcher nudges must refresh the task SSOT while
# limiting executable supplements to unread messages for that current task.
@test "task nudge scopes RC reuse to unread current-task supplements" {
    ! grep -q '前taskの情報は無効' "$PROJECT_ROOT/scripts/inbox_watcher.sh"
    [ "$(grep -c 'read:falseかつ現task_id一致' "$PROJECT_ROOT/scripts/inbox_watcher.sh")" -eq 2 ]
    ! grep -q '既存成果の再利用可否はinbox本文とRC指示に従え' "$PROJECT_ROOT/scripts/inbox_watcher.sh"
}
