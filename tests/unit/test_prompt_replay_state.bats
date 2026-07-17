#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "task publication fingerprint ignores duplicate inbox message ids" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export INBOX_WATCHER_LIB_ONLY=1
export SHOGUN_STATE_DIR="$BATS_TEST_TMPDIR/state"; mkdir -p "$SHOGUN_STATE_DIR"
source "$PROJECT_ROOT/scripts/inbox_watcher.sh" saizo pane
SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; AGENT_ID=saizo
mkdir -p "$SCRIPT_DIR/queue/tasks"
cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<EOF
task:
  task_id: cmd_generation_one
  deployed_at: 2026-07-18T07:50:23
EOF
first=$(task_publication_fingerprint)
# A retry changes only inbox identity, not task publication identity.
second=$(task_publication_fingerprint)
[ "$first" = "$second" ]
sed -i "s/07:50:23/07:51:23/" "$SCRIPT_DIR/queue/tasks/saizo.yaml"
third=$(task_publication_fingerprint)
[ "$first" != "$third" ]
'
    [ "$status" -eq 0 ]
}

@test "source event is consumed once across pane generations with four timestamps" {
    ledger="$BATS_TEST_TMPDIR/consumed.tsv"
    run env PROMPT_STATE_AGENT_ID=saizo \
        PROMPT_STATE_SOURCE_EVENT_ID=event-one \
        PROMPT_STATE_RECEIVED_TS=2026-07-18T01:50:00+09:00 \
        PROMPT_STATE_SEND_TS=2026-07-18T01:50:01+09:00 \
        PROMPT_STATE_PANE_GENERATION=100 \
        PROMPT_STATE_CONSUMED_LEDGER="$ledger" \
        PROMPT_STATE_PREFLIGHT_CMD=/nonexistent \
        bash "$PROJECT_ROOT/scripts/hooks/prompt_state_inject.sh" <<<'{"prompt":"replay fixture"}'
    [ "$status" -eq 0 ]
    [ "$(awk -F '\t' 'NR==1{print NF}' "$ledger")" -eq 5 ]
    [ "$(cut -f1 "$ledger")" = event-one ]

    run env PROMPT_STATE_AGENT_ID=saizo \
        PROMPT_STATE_SOURCE_EVENT_ID=event-one \
        PROMPT_STATE_PANE_GENERATION=200 \
        PROMPT_STATE_CONSUMED_LEDGER="$ledger" \
        PROMPT_STATE_PREFLIGHT_CMD=/nonexistent \
        bash "$PROJECT_ROOT/scripts/hooks/prompt_state_inject.sh" <<<'{"prompt":"replay fixture"}'
    [ "$status" -eq 2 ]
    [[ "$output" == *"delayed replay suppressed"* ]]
    [ "$(wc -l < "$ledger")" -eq 1 ]
}

@test "deploy publication records generation before delivery and interruption fallback" {
    deploy="$PROJECT_ROOT/scripts/deploy_task.sh"
    record_line=$(grep -n 'record_deployed_at "$task_yaml"' "$deploy" | tail -1 | cut -d: -f1)
    release_line=$(grep -n 'deploy_task_release_lock "$deploy_lock_fd"' "$deploy" | tail -2 | head -1 | cut -d: -f1)
    delivery_line=$(grep -n 'DEPLOY_TASK_PHASE=delivery' "$deploy" | tail -1 | cut -d: -f1)
    [ "$record_line" -lt "$release_line" ]
    [ "$release_line" -lt "$delivery_line" ]
}

@test "monitor notification dedupe uses fingerprint acknowledged generation and cooldown" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"; unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$BATS_TEST_TMPDIR/state"; LOG="$BATS_TEST_TMPDIR/log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/scripts" "$STATE_DIR"
printf "task:\n  acknowledged_at: 2026-07-18T08:00:00\n" > "$SCRIPT_DIR/queue/tasks/saizo.yaml"
cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<EOF
#!/bin/bash
echo SEND >> "$LOG"
EOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"
log(){ :; }; EPOCHSECONDS=1000; NINJA_MONITOR_NOTIFY_COOLDOWN=600
notify_karo_throttled session_alert saizo "same alert"
notify_karo_throttled session_alert saizo "same alert"
[ "$(grep -c SEND "$LOG")" -eq 1 ]
sed -i "s/08:00:00/08:01:00/" "$SCRIPT_DIR/queue/tasks/saizo.yaml"
notify_karo_throttled session_alert saizo "same alert"
[ "$(grep -c SEND "$LOG")" -eq 2 ]
notify_karo_throttled ctx_alert saizo "action required"
[ "$(grep -c SEND "$LOG")" -eq 3 ]
'
    [ "$status" -eq 0 ]
}
