#!/usr/bin/env bats
# test_gate_shogun_startup.bats — gate_shogun_startup.sh unit tests
# cmd_1556: 将軍起動ゲート15項目チェックのテスト可能分岐を検証

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_shogun_startup.sh"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/shogun_startup.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" \
             "$TEST_TMPDIR/queue/inbox" \
             "$TEST_TMPDIR/queue/archive" \
             "$TEST_TMPDIR/memory" \
             "$TEST_TMPDIR/logs" \
             "$TEST_TMPDIR/context" \
             "$TEST_TMPDIR/config" \
             "$TEST_TMPDIR/instructions"

    # Copy the gate script
    cp "$SRC_GATE_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_shogun_startup.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_shogun_startup.sh"

    # --- Default fixtures: all checks pass ---

    # Gate 1 mock: gate_shogun_memory.sh → OK
    cat > "$TEST_TMPDIR/scripts/gates/gate_shogun_memory.sh" <<'MOCK'
#!/usr/bin/env bash
echo "Memory健全度: OK"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_shogun_memory.sh"

    # Gate 2 mock: gate_p_average_freshness.sh → OK
    cat > "$TEST_TMPDIR/scripts/gates/gate_p_average_freshness.sh" <<'MOCK'
#!/usr/bin/env bash
echo "p̄鮮度: OK"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_p_average_freshness.sh"

    # Gate 3 mock: gate_cmd_state.sh → OK
    cat > "$TEST_TMPDIR/scripts/gates/gate_cmd_state.sh" <<'MOCK'
#!/usr/bin/env bash
echo "cmd委任状態: OK"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_cmd_state.sh"

    # Gate 12 mock: gate_loop_health.sh → OK
    cat > "$TEST_TMPDIR/scripts/gates/gate_loop_health.sh" <<'MOCK'
#!/usr/bin/env bash
echo "Total fires: 10"
echo "FAIL: 0"
echo "AUTO-FIXED: 0"
echo "Loop Status: OK"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_loop_health.sh"

    # Gate 13 mock: gate_lesson_health.sh → OK
    cat > "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh" <<'MOCK'
#!/usr/bin/env bash
echo "教訓健全度: OK"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh"

    # Gate 4: inbox with no unread
    cat > "$TEST_TMPDIR/queue/inbox/shogun.yaml" <<'EOF'
messages:
- content: test
  read: true
  id: msg_1
EOF

    # Gate 5: fresh snapshot
    local now_time
    now_time=$(date '+%Y-%m-%dT%H:%M:%S')
    cat > "$TEST_TMPDIR/queue/karo_snapshot.txt" <<EOF
# 家老陣形図(karo_snapshot)
# Generated: $now_time
ninja|hayate|cmd_100_impl|in_progress|infra|CTX:30%
ninja|kagemaru|cmd_101_impl|in_progress|infra|CTX:25%
EOF

    # Gate 6: required deepdive file
    echo "# deepdive content" > "$TEST_TMPDIR/memory/deepdive_why_chain_20260321.md"

    # Gate 7: lord-conversation-index (no rulings)
    cat > "$TEST_TMPDIR/context/lord-conversation-index.md" <<'EOF'
# Lord Conversation Index
## 殿の直近裁定・方針
## その他
EOF

    # Gate 8: no insights file (simplest pass case)
    # (omit insights.yaml → "キューなし")

    # Gate 9: design quality + workarounds (minimal pass)
    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
- cmd_id: cmd_100
  karo_rework: false
  gate_result: PASS
EOF
    cat > "$TEST_TMPDIR/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_100
  workaround: false
  category: none
EOF

    # Gate 11: dashboard + review log (no proposals)
    echo "# Dashboard" > "$TEST_TMPDIR/dashboard.md"
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'EOF'
entries: []
EOF

    # Gate 14: no gunshi context files (pass)
    # (no gunshi-*.md in context/)

    # Gate 15: minimal knowledge map files for progress detection
    echo "# CLAUDE.md" > "$TEST_TMPDIR/CLAUDE.md"
    echo "# instructions" > "$TEST_TMPDIR/instructions/shogun.md"
    echo "# projects" > "$TEST_TMPDIR/config/projects.yaml"

    # HOME override for MEMORY.md path (Gate 15)
    export ORIG_HOME="$HOME"
    export HOME="$TEST_TMPDIR/fakehome"
    mkdir -p "$HOME/.claude/projects/-mnt-c-tools-multi-agent-shogun/memory"
    echo "# MEMORY index" > "$HOME/.claude/projects/-mnt-c-tools-multi-agent-shogun/memory/MEMORY.md"

    # Mock git for rev-list (unpushed count)
    mkdir -p "$TEST_TMPDIR/bin"
    cat > "$TEST_TMPDIR/bin/git" <<'MOCK'
#!/usr/bin/env bash
if [ "$1" = "rev-list" ]; then
    echo "0"
elif [ "$1" = "log" ]; then
    echo "unknown"
else
    command git "$@"
fi
MOCK
    chmod +x "$TEST_TMPDIR/bin/git"

    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_shogun_startup.sh"
    export ORIG_PATH="$PATH"
    export PATH="$TEST_TMPDIR/bin:$PATH"
}

teardown() {
    export PATH="$ORIG_PATH"
    export HOME="$ORIG_HOME"
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# === Test 1: 全項目正常 → 総合判定OK ===
@test "all checks pass → 総合判定: OK" {
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"総合判定: OK"* ]]
}

# === Test 2: Memory健全度 ALERT → 総合判定ALERT ===
@test "Memory ALERT → 総合判定: ALERT" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_shogun_memory.sh" <<'MOCK'
#!/usr/bin/env bash
echo "Memory健全度: ALERT — MCP obs超過"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_shogun_memory.sh"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT"* ]]
    [[ "$output" == *"Memory健全度"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 3: p̄鮮度 ALERT → 総合判定ALERT ===
@test "p̄鮮度 ALERT → 総合判定: ALERT" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_p_average_freshness.sh" <<'MOCK'
#!/usr/bin/env bash
echo "p̄鮮度: ALERT — 7日超過"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_p_average_freshness.sh"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 4: cmd委任状態 ALERT → 総合判定ALERT ===
@test "cmd状態 ALERT → 総合判定: ALERT" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_cmd_state.sh" <<'MOCK'
#!/usr/bin/env bash
echo "cmd委任状態: ALERT — 長期滞留"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_cmd_state.sh"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT"* ]]
    [[ "$output" == *"cmd委任状態"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 5: 複合ALERT — Memory + 必読ファイル不在 ===
@test "compound: Memory ALERT + deepdive missing → 総合判定: ALERT with multiple alerts" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_shogun_memory.sh" <<'MOCK'
#!/usr/bin/env bash
echo "Memory健全度: ALERT"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_shogun_memory.sh"
    rm -f "$TEST_TMPDIR/memory/deepdive_why_chain_20260321.md"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Memory健全度"* ]]
    [[ "$output" == *"必読ファイル不在"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 6: inbox未読あり → WARN ===
@test "inbox 2 unread → 総合判定: WARN" {
    cat > "$TEST_TMPDIR/queue/inbox/shogun.yaml" <<'EOF'
messages:
- content: msg1
  read: false
  id: msg_1
- content: msg2
  read: false
  id: msg_2
- content: msg3
  read: true
  id: msg_3
EOF

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"未読: 2件"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

# === Test 7: 陣形図不在 → WARN ===
@test "snapshot missing → WARN 陣形図不在" {
    rm -f "$TEST_TMPDIR/queue/karo_snapshot.txt"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: karo_snapshot.txt不在"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

# === Test 8: 必読ファイル不在 → ALERT ===
@test "deepdive missing → 総合判定: ALERT" {
    rm -f "$TEST_TMPDIR/memory/deepdive_why_chain_20260321.md"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT"* ]]
    [[ "$output" == *"必読ファイル不在"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 9: idle自走トリガー ON (全忍者idle) ===
@test "all ninjas idle → idle trigger ON" {
    cat > "$TEST_TMPDIR/queue/karo_snapshot.txt" <<EOF
# 家老陣形図(karo_snapshot)
# Generated: $(date '+%Y-%m-%dT%H:%M:%S')
ninja|hayate|cmd_100_impl|idle|infra|CTX:0%
ninja|kagemaru|cmd_101_impl|idle|infra|CTX:0%
ninja|hanzo|cmd_102_impl|done|infra|CTX:0%
EOF

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"全忍者idle"* ]]
    [[ "$output" == *"idle時自己分析に入れ"* ]]
}

# === Test 10: active忍者あり → idle trigger OFF ===
@test "active ninjas → no idle trigger" {
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"全忍者idle"* ]]
    [[ "$output" == *"稼働中cmd"* ]]
}

# === Test 11: --brief モード → 一行サマリ出力 ===
@test "--brief mode → single line summary with startup_gate" {
    run bash "$TEST_GATE" --brief
    [ "$status" -eq 0 ]
    [[ "$output" == *"startup_gate: OK"* ]]
    [[ "$output" == *"idle_trigger:"* ]]
    [[ "$output" == *"必読:"* ]]
    # brief modeでは「■」セクションヘッダがないこと
    [[ "$output" != *"■ Memory健全度"* ]]
}

# === Test 12: 教訓健全度 ALERT → 総合判定ALERT ===
@test "lesson health ALERT → 総合判定: ALERT" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh" <<'MOCK'
#!/usr/bin/env bash
echo "教訓健全度: ALERT — 未振り分け10件"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT"* ]]
    [[ "$output" == *"教訓健全度"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 13: p̄鮮度 WARN (ALERTではない) → 総合判定WARN ===
@test "p̄鮮度 WARN → 総合判定: WARN" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_p_average_freshness.sh" <<'MOCK'
#!/usr/bin/env bash
echo "p̄鮮度: WARN — 3日超過"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_p_average_freshness.sh"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

# === Test 14: 未処理PROPOSAL → WARN ===
@test "pending proposals → WARN with proposal count" {
    echo "# Dashboard [PROPOSAL] item1 [PROPOSAL] item2" > "$TEST_TMPDIR/dashboard.md"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"未処理PROPOSAL"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

# === Test 15: --brief + ALERT → ALERT in single line ===
@test "--brief + Memory ALERT → single line with ALERT" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_shogun_memory.sh" <<'MOCK'
#!/usr/bin/env bash
echo "Memory健全度: ALERT"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_shogun_memory.sh"

    run bash "$TEST_GATE" --brief
    [ "$status" -eq 0 ]
    [[ "$output" == *"startup_gate: ALERT"* ]]
    [[ "$output" == *"Memory健全度"* ]]
}
