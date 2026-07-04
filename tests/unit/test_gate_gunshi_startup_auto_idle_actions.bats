#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_gunshi_startup.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gunshi_auto_idle.XXXXXX")"
    mkdir -p \
        "$TEST_TMPDIR/scripts/gates" \
        "$TEST_TMPDIR/memory" \
        "$TEST_TMPDIR/queue/inbox" \
        "$TEST_TMPDIR/queue" \
        "$TEST_TMPDIR/logs" \
        "$TEST_TMPDIR/projects/infra" \
        "$TEST_TMPDIR/docs/research"

    cp "$SRC_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_gunshi_startup.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_gunshi_startup.sh"
    cp "$PROJECT_ROOT/scripts/gates/session_alerts_render.sh" "$TEST_TMPDIR/scripts/gates/session_alerts_render.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/session_alerts_render.sh"

    cat > "$TEST_TMPDIR/memory/deepdive_why_chain_20260321.md" <<'EOF'
前文
## Phase 1
phase1
EOF
    cat > "$TEST_TMPDIR/queue/inbox/gunshi.yaml" <<'EOF'
messages: []
EOF
    cat > "$TEST_TMPDIR/logs/gunshi_stats.yaml" <<'EOF'
# 累計: total=1
# accuracy公式: approved/total
# verdict分布: APPROVE=1
# workaround率推移: 0%
EOF
    cat > "$TEST_TMPDIR/projects/infra/lessons_gunshi.yaml" <<'EOF'
- id: LG001
  title: manual lesson
  automated: false
EOF
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "gate_gunshi_startup writes auto_idle_actions for WARN recommendation" {
    run bash -c "cd '$TEST_TMPDIR' && scripts/gates/gate_gunshi_startup.sh"
    [ "$status" -eq 0 ] || {
        echo "status=$status"
        echo "$output"
        return 1
    }
    [[ "$output" == *"■ 推薦行動（WARN/ALERTから自動導出）"* ]]
    [[ "$output" == *"idle Step 3: 未自動化教訓のgate化を実施"* ]]
    [[ "$output" == *"auto_idle_actions.txt: $TEST_TMPDIR/queue/auto_idle_actions.txt"* ]]

    run cat "$TEST_TMPDIR/queue/auto_idle_actions.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"idle Step 3: 未自動化教訓のgate化を実施"* ]]
}

@test "gate_gunshi_startup unread count ignores read false text inside message content" {
    cat > "$TEST_TMPDIR/queue/inbox/gunshi.yaml" <<'EOF'
messages:
- id: msg_1
  content: |
    literal payload:
    read: false
  read: true
- id: msg_2
  content: normal unread
  read: false
EOF

    run bash -c "cd '$TEST_TMPDIR' && scripts/gates/gate_gunshi_startup.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"未読: 1件"* ]]
}

@test "gate_gunshi_startup skips expensive gate sync when inbox has no new gate_result" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'EOF'
- cmd_id: cmd_100
  review_type: report
  verdict: APPROVE
EOF
    cat > "$TEST_TMPDIR/scripts/gunshi_gate_sync.sh" <<'EOF'
#!/usr/bin/env bash
touch "$PWD/sync_called"
echo "SYNC_CALLED"
EOF
    chmod +x "$TEST_TMPDIR/scripts/gunshi_gate_sync.sh"

    run bash -c "cd '$TEST_TMPDIR' && scripts/gates/gate_gunshi_startup.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"自動sync実行: SKIP: inbox内に未反映cmdのgate_resultなし（archive全走査省略）"* ]]
    [[ "$output" == *"GATE結果未反映: 1→1件 (sync後)"* ]]
    [ ! -e "$TEST_TMPDIR/sync_called" ]
}

@test "gate_gunshi_startup runs gate sync when inbox has new gate_result" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'EOF'
- cmd_id: cmd_100
  review_type: report
  verdict: APPROVE
EOF
    cat > "$TEST_TMPDIR/queue/inbox/gunshi.yaml" <<'EOF'
messages:
  - id: msg_1
    type: gate_result
    read: false
    body: "cmd_100 gate_result: CLEAR"
EOF
    cat > "$TEST_TMPDIR/scripts/gunshi_gate_sync.sh" <<'EOF'
#!/usr/bin/env bash
touch "$PWD/sync_called"
echo "SYNC_CALLED"
EOF
    chmod +x "$TEST_TMPDIR/scripts/gunshi_gate_sync.sh"

    run bash -c "cd '$TEST_TMPDIR' && scripts/gates/gate_gunshi_startup.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"自動sync実行: SYNC_CALLED"* ]]
    [ -e "$TEST_TMPDIR/sync_called" ]
}
