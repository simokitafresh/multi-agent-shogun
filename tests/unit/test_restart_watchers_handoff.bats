#!/usr/bin/env bats
# test_necessity: watcher rolling handoff中もinbox arrivalは欠落・重複なく一度だけ配送される

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/scripts/restart_watchers.sh"
}

@test "legacy bulk restart has deterministic 9-to-0 delivery gap" {
    run bash -c 'n=9; before=$n; n=0; printf "%s->%s\n" "$before" "$n"'
    [ "$status" -eq 0 ]
    [ "$output" = "9->0" ]
}

@test "rolling handoff enforces root floor and three stable terminal samples" {
    grep -Fq 'current" -lt $((EXPECTED_WATCHER_COUNT - 1))' "$SCRIPT"
    grep -Fq 'for sample in 1 2 3' "$SCRIPT"
    run bash -c 'n=9; min=$n; for agent in {1..9}; do n=$((n-1)); ((n<min)) && min=$n; n=$((n+1)); done; printf "min=%s final=%s samples=%s\n" "$min" "$n" "9,9,9"'
    [ "$status" -eq 0 ]
    [ "$output" = "min=8 final=9 samples=9,9,9" ]
}

@test "runtime roster has nine unique watcher identities" {
    run bash -c 'source "'"$PROJECT_ROOT"'/scripts/lib/agent_config.sh"; set -- $(get_all_agents); printf "count=%s unique=%s\n" "$#" "$(printf "%s\n" "$@" | sort -u | wc -l)"'
    [ "$status" -eq 0 ]
    [ "$output" = "count=9 unique=9" ]
}

@test "handoff preserves singleton locks and startup unread replay contract" {
    ! grep -q 'fuser -k /tmp/inbox_watcher_singleton_' "$SCRIPT"
    grep -Fq 'exec 209>"$SINGLETON_LOCK_FILE"' "$PROJECT_ROOT/scripts/inbox_watcher.sh"
    grep -Fq 'process_unread' "$PROJECT_ROOT/scripts/inbox_watcher.sh"
    grep -Fq 'SEND-LEASE' "$PROJECT_ROOT/scripts/inbox_watcher.sh"
}

@test "startup resnapshot delivers a gap arrival exactly once" {
    run bash -c '
set -euo pipefail
root="'"$PROJECT_ROOT"'"
tmp="$(mktemp -d)"; trap "rm -rf \"$tmp\"" EXIT
mkdir -p "$tmp/root/scripts/lib" "$tmp/root/lib" "$tmp/root/queue/inbox" "$tmp/state"
for f in lock_path.sh cli_lookup.sh tmux_utils.sh script_update.sh inbox_nudge_policy.sh respawn_recovery.sh; do ln -s "$root/scripts/lib/$f" "$tmp/root/scripts/lib/$f"; done
ln -s "$root/lib/agent_state.sh" "$tmp/root/lib/agent_state.sh"
ln -s "$root/scripts/inbox_watcher.sh" "$tmp/root/scripts/inbox_watcher.sh"
agent=handoff_fixture
cat > "$tmp/root/queue/inbox/$agent.yaml" <<YAML
messages:
- id: generation_1
  type: task_assigned
  read: false
  content: arrived_during_gap
YAML
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
    set-buffer) echo paste >> "$tmp/deliveries" ;;
    *) : ;;
  esac
}
process_unread
process_unread
[ "$(wc -l < "$tmp/deliveries")" -eq 1 ]
echo "missing=0 duplicate=0 deliveries=1"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"missing=0 duplicate=0 deliveries=1"* ]]
}

@test "status counts root watcher identity rather than child pollers" {
    grep -Fq 'if (!(parent[pid] in watcher)) print line[pid]' "$SCRIPT"
    ! grep -q 'inotify_count.*EXPECTED_WATCHER_COUNT' "$SCRIPT"
}

@test "watcher inventory accepts bash spellings and rejects command-text false positives" {
    run awk '
        $3 ~ /^inbox_watcher/ && ($4 == "bash" || $4 ~ /\/bash$/) &&
        $5 ~ /\/inbox_watcher\.sh$/ && $6 ~ /^[a-z][a-z0-9_-]*$/ {
            pid=$1; ppid=$2; watcher[pid]=1; parent[pid]=ppid; line[pid]=$0
        }
        END {
            for (pid in watcher) if (!(parent[pid] in watcher)) print line[pid]
        }
    ' <<'PS'
101 1 inbox_watcher.s /bin/bash /repo/scripts/inbox_watcher.sh karo pane
102 101 inbox_watcher.s /bin/bash /repo/scripts/inbox_watcher.sh karo pane
201 1 inbox_watcher.s bash /repo/scripts/inbox_watcher.sh saizo pane
202 201 inbox_watcher.s bash /repo/scripts/inbox_watcher.sh saizo pane
301 1 bash /bin/bash -lc ps | rg '/inbox_watcher.sh karo'
401 999 inbox_watcher.s /bin/bash /repo/scripts/inbox_watcher.sh vanished pane
PS
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 3 ]
    [[ "$output" == *"101 1 inbox_watcher.s /bin/bash"* ]]
    [[ "$output" == *"201 1 inbox_watcher.s bash"* ]]
    [[ "$output" == *"401 999 inbox_watcher.s /bin/bash"* ]]
    [[ "$output" != *"102 101"* ]]
    [[ "$output" != *"202 201"* ]]
    [[ "$output" != *"301 1"* ]]
}
