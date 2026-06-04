#!/usr/bin/env bats
# test_deploy_task_three_layer_candidates.bats — deploy_task.sh candidate backlog WARN

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "deploy_three_layer_candidates"
    mkdir -p "$TEST_PROJECT/data"
}

teardown() {
    deploy_task_teardown
}

create_candidate_db() {
    local obsidian_count="$1"
    local contradiction_count="$2"
    local duplicate_count="$3"
    python3 - "$TEST_PROJECT/data/multi_agent_shogun_memory.db" \
        "$obsidian_count" "$contradiction_count" "$duplicate_count" <<'PY'
import sqlite3
import sys

db_path = sys.argv[1]
counts = {
    "obsidian_candidate": int(sys.argv[2]),
    "contradiction_candidate": int(sys.argv[3]),
    "duplicate_candidate": int(sys.argv[4]),
}

conn = sqlite3.connect(db_path)
conn.execute("CREATE TABLE events (id TEXT PRIMARY KEY, state TEXT DEFAULT 'raw')")
idx = 0
for state, count in counts.items():
    for _ in range(count):
        idx += 1
        conn.execute("INSERT INTO events (id, state) VALUES (?, ?)", (f"event:{idx}", state))
conn.commit()
conn.close()
PY
}

@test "cmd_3181 AC2/AC3: candidate合計が閾値超過ならWARNを出し戻り値0" {
    create_candidate_db 6 3 2

    run bash -lc "source '$TEST_PROJECT/scripts/deploy_task.sh'; warn_three_layer_candidate_backlog"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: three_layer_candidate_backlog total=11 threshold=10"* ]]
    [[ "$output" == *"obsidian_candidate=6"* ]]
    [[ "$output" == *"contradiction_candidate=3"* ]]
    [[ "$output" == *"duplicate_candidate=2"* ]]
}

@test "cmd_3181 AC4: candidate件数0ならWARNなし" {
    create_candidate_db 0 0 0

    run bash -lc "source '$TEST_PROJECT/scripts/deploy_task.sh'; warn_three_layer_candidate_backlog"
    [ "$status" -eq 0 ]
    [[ "$output" != *"three_layer_candidate_backlog"* ]]
}

@test "cmd_3181 AC3: candidate合計が閾値超過でも配備フローは中断しない" {
    create_candidate_db 10 1 0

    run bash -lc "
        source '$TEST_PROJECT/scripts/deploy_task.sh'
        warn_three_layer_candidate_backlog
        echo after_warn
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: three_layer_candidate_backlog total=11 threshold=10"* ]]
    [[ "$output" == *"after_warn"* ]]
}

@test "cmd_3181 AC1: deploy_task_main calls three-layer candidate backlog check" {
    run grep -F "warn_three_layer_candidate_backlog || true" "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]
}
