#!/usr/bin/env bats

load '../helpers/cmd_gate_scaffold'

setup_file() {
    cmd_gate_setup_file
}

setup() {
    cmd_gate_scaffold "cmd_gate_lock"
    export SCRIPT_DIR="$TEST_PROJECT"
    export CMD_ID="$TEST_CMD_ID"
}

teardown() {
    cmd_gate_teardown
}

@test "cmd_complete_gate exits 0 when same CMD_ID lock is already held" {
    local lock_file locker_pid

    source "$TEST_PROJECT/scripts/lib/lock_path.sh"
    lock_file="$(lock_path "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/cmd_complete_gate.lock")"

    bash -lc '
        exec 9>"$1"
        flock -n 9 || exit 1
        sleep 2
    ' _ "$lock_file" &
    locker_pid=$!
    sleep 0.2

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"

    wait "$locker_pid"

    [ "$status" -eq 0 ]
    [[ "$output" == *"cmd_complete_gate already running (CMD_ID lock)"* ]]
}

@test "cmd_complete_gate still allows single already-cleared early exit" {
    cat > "$TEST_PROJECT/logs/gate_metrics.log" <<EOF
2026-04-19T14:00:00	${TEST_CMD_ID}	CLEAR	report_gate	review	codex	unknown	none	test title
EOF

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Already CLEARED"* ]]
}
