#!/usr/bin/env bats
# test_gate_shogun_startup.bats — gate_shogun_startup.sh unit tests
# cmd_1556: 将軍起動ゲート15項目チェックのテスト可能分岐を検証

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_shogun_startup.sh"
    export REAL_GIT_BIN
    REAL_GIT_BIN="$(command -v git)"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1
    # Source once per file (function-only load) and export for run subshell
    SHOGUN_STARTUP_LIB_ONLY=1 source "$SRC_GATE_SCRIPT"
    export -f run_gate_shogun_startup

    # Build shared base directory once — all default-pass fixtures
    # Each test does: cp -a "$SHARED_BASE/." "$TEST_TMPDIR/" instead of recreating files
    export SHARED_BASE="$BATS_FILE_TMPDIR/base"
    mkdir -p "$SHARED_BASE/scripts/gates" \
             "$SHARED_BASE/queue/inbox" \
             "$SHARED_BASE/queue/archive" \
             "$SHARED_BASE/queue/tasks" \
             "$SHARED_BASE/memory" \
             "$SHARED_BASE/logs" \
             "$SHARED_BASE/context" \
             "$SHARED_BASE/config" \
             "$SHARED_BASE/instructions" \
             "$SHARED_BASE/bin" \
             "$SHARED_BASE/fakehome/.claude/projects/-mnt-c-tools-multi-agent-shogun/memory"

    # Gate 1 mock: gate_shogun_memory.sh → OK
    cat > "$SHARED_BASE/scripts/gates/gate_shogun_memory.sh" <<'MOCK'
#!/usr/bin/env bash
echo "Memory健全度: OK"
MOCK
    chmod +x "$SHARED_BASE/scripts/gates/gate_shogun_memory.sh"

    # Gate 2 mock: gate_p_average_freshness.sh → OK
    cat > "$SHARED_BASE/scripts/gates/gate_p_average_freshness.sh" <<'MOCK'
#!/usr/bin/env bash
echo "p̄鮮度: OK"
MOCK
    chmod +x "$SHARED_BASE/scripts/gates/gate_p_average_freshness.sh"

    # Gate 3 mock: gate_cmd_state.sh → OK
    cat > "$SHARED_BASE/scripts/gates/gate_cmd_state.sh" <<'MOCK'
#!/usr/bin/env bash
echo "cmd委任状態: OK"
MOCK
    chmod +x "$SHARED_BASE/scripts/gates/gate_cmd_state.sh"

    # Gate 12 mock: gate_loop_health.sh → OK
    cat > "$SHARED_BASE/scripts/gates/gate_loop_health.sh" <<'MOCK'
#!/usr/bin/env bash
echo "Total fires: 10"
echo "FAIL: 0"
echo "AUTO-FIXED: 0"
echo "Loop Status: OK"
MOCK
    chmod +x "$SHARED_BASE/scripts/gates/gate_loop_health.sh"

    # Gate 13 mock: gate_lesson_health.sh → OK
    cat > "$SHARED_BASE/scripts/gates/gate_lesson_health.sh" <<'MOCK'
#!/usr/bin/env bash
echo "教訓健全度: OK"
MOCK
    chmod +x "$SHARED_BASE/scripts/gates/gate_lesson_health.sh"

    # Gate 4: inbox with no unread
    cat > "$SHARED_BASE/queue/inbox/shogun.yaml" <<'EOF'
messages:
- content: test
  read: true
  id: msg_1
EOF

    # Gate 5: fresh snapshot (fixed future date — Gate 5 only displays, no staleness check)
    cat > "$SHARED_BASE/queue/karo_snapshot.txt" <<'EOF'
# 家老陣形図(karo_snapshot)
# Generated: 2099-01-01T00:00:00
ninja|hayate|cmd_100_impl|in_progress|infra|CTX:30%
ninja|kagemaru|cmd_101_impl|in_progress|infra|CTX:25%
EOF

    # Gate 6: required deepdive file
    echo "# deepdive content" > "$SHARED_BASE/memory/deepdive_why_chain_20260321.md"

    # Gate 7: lord-conversation-index (no rulings)
    cat > "$SHARED_BASE/context/lord-conversation-index.md" <<'EOF'
# Lord Conversation Index
## 殿の直近裁定・方針
## その他
EOF

    # Gate 8: no insights file (simplest pass case)
    # (omit insights.yaml → "キューなし")

    # Gate 9: design quality + workarounds (minimal pass)
    cat > "$SHARED_BASE/logs/cmd_design_quality.yaml" <<'EOF'
- cmd_id: cmd_100
  karo_rework: false
  gate_result: PASS
EOF
    cat > "$SHARED_BASE/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_100
  workaround: false
  category: none
EOF

    # Gate 11: dashboard + review log (no proposals)
    echo "# Dashboard" > "$SHARED_BASE/dashboard.md"
    cat > "$SHARED_BASE/logs/gunshi_review_log.yaml" <<'EOF'
entries: []
EOF

    # Gate 14: no gunshi context files (pass)
    # (no gunshi-*.md in context/)

    # Gate 15: minimal knowledge map files for progress detection
    echo "# CLAUDE.md" > "$SHARED_BASE/CLAUDE.md"
    echo "# instructions" > "$SHARED_BASE/instructions/shogun.md"
    echo "# projects" > "$SHARED_BASE/config/projects.yaml"

    # HOME override for MEMORY.md path (Gate 15)
    echo "# MEMORY index" > "$SHARED_BASE/fakehome/.claude/projects/-mnt-c-tools-multi-agent-shogun/memory/MEMORY.md"

    # Mock git for rev-list (unpushed count)
    cat > "$SHARED_BASE/bin/git" <<'MOCK'
#!/usr/bin/env bash
if [ "$1" = "rev-list" ]; then
    echo "0"
elif [ "$1" = "log" ]; then
    echo "unknown"
elif [ "$1" = "status" ]; then
    exit 0
else
    "$REAL_GIT_BIN" "$@"
fi
MOCK
    chmod +x "$SHARED_BASE/bin/git"
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/shogun_startup.XXXXXX")"
    cp -a "$SHARED_BASE/." "$TEST_TMPDIR/"

    export ORIG_HOME="$HOME"
    export HOME="$TEST_TMPDIR/fakehome"
    export ORIG_PATH="$PATH"
    export PATH="$TEST_TMPDIR/bin:$PATH"
    export SHOGUN_STARTUP_ROOT="$TEST_TMPDIR"
}

teardown() {
    export PATH="$ORIG_PATH"
    export HOME="$ORIG_HOME"
    unset SHOGUN_STARTUP_ROOT
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# === Test 1: 全項目正常 → 総合判定OK ===
@test "all checks pass → 総合判定: OK" {
    run run_gate_shogun_startup
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

    run run_gate_shogun_startup
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

    run run_gate_shogun_startup
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

    run run_gate_shogun_startup
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

    run run_gate_shogun_startup
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

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"未読: 2件"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

# === Test 7: 陣形図不在 → WARN ===
@test "snapshot missing → WARN 陣形図不在" {
    rm -f "$TEST_TMPDIR/queue/karo_snapshot.txt"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: karo_snapshot.txt不在"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

# === Test 8: 必読ファイル不在 → ALERT ===
@test "deepdive missing → 総合判定: ALERT" {
    rm -f "$TEST_TMPDIR/memory/deepdive_why_chain_20260321.md"

    run run_gate_shogun_startup
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

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"全忍者idle"* ]]
    [[ "$output" == *"idle時自己分析に入れ"* ]]
}

# === Test 10: active忍者あり → idle trigger OFF ===
@test "active ninjas → no idle trigger" {
    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" != *"全忍者idle"* ]]
    [[ "$output" == *"稼働中cmd"* ]]
}

# Test 11 (--brief mode) は 2026-04-12 殿裁定で削除。
# 呼出元session_start_injectへの統合が21日間未実現のままdead code化したため撤去。

# === Test 12: 教訓健全度 ALERT → 総合判定ALERT ===
@test "lesson health ALERT → 総合判定: ALERT" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh" <<'MOCK'
#!/usr/bin/env bash
echo "教訓健全度: ALERT — 未振り分け10件"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh"

    run run_gate_shogun_startup
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

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

# === Test 14: 未処理PROPOSAL → WARN ===
@test "pending proposals → WARN with proposal count" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'EOF'
- cmd_id: cmd_test_prop
  proposals:
    - id: GP-999
      description: "テスト提案"
      status: pending
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"未処理PROPOSAL"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

# Test 15 (--brief + ALERT) は 2026-04-12 殿裁定で削除。Test 11と同じ理由。

# === Test 16: AC注入一致 → WARNING無し (cmd_1668) ===
@test "AC injection match → OK, no WARNING" {
    mkdir -p "$TEST_TMPDIR/queue/tasks"
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  status: in_progress
  parent_cmd: cmd_100
  acceptance_criteria:
  - id: AC1
    description: "test ac1"
    criteria: "test criteria1"
  - id: AC2
    description: "test ac2"
    criteria: "test criteria2"
EOF
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_100:
    status: pending
    acceptance_criteria:
      - id: AC1
        description: "test ac1"
      - id: AC2
        description: "test ac2"
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"AC注入検証"* ]]
    [[ "$output" != *"WARNING: AC不一致"* ]]
    [[ "$output" == *"OK: 稼働中1件のAC整合確認"* ]]
}

# === Test 17: AC注入不一致(件数差) → WARNING出力 (cmd_1668) ===
@test "AC injection count mismatch → WARNING" {
    mkdir -p "$TEST_TMPDIR/queue/tasks"
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  status: in_progress
  parent_cmd: cmd_100
  acceptance_criteria:
  - id: AC1
    description: "test"
    criteria: "test"
EOF
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_100:
    status: pending
    acceptance_criteria:
      - id: AC1
        description: "test"
      - id: AC2
        description: "test2"
      - id: AC3
        description: "test3"
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: AC不一致"* ]]
    [[ "$output" == *"hayate(cmd_100)"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

# === Test 18: scout_exempt=true cmd → AC不一致でもWARNINGなし (AC2修正検証) ===
@test "scout_exempt=true cmd → AC mismatch skipped, no WARNING" {
    mkdir -p "$TEST_TMPDIR/queue/tasks"
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  status: assigned
  parent_cmd: cmd_100
  acceptance_criteria:
  - id: AC1
    description: "test"
EOF
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_100:
    status: pending
    scout_exempt: true
    acceptance_criteria:
      - id: AC1
        description: "test"
      - id: AC2
        description: "test2"
      - id: AC3
        description: "test3"
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING: AC不一致"* ]]
}

# === Test 19: 直近7日内にinbound>0の日あり + 昨日inbound=0 → INFO not ALERT (AC1修正検証) ===
@test "recent 7-day archive has inbound + yesterday inbound=0 → INFO not ALERT" {
    mkdir -p "$TEST_TMPDIR/logs/lord_conversation_archive"
    local yesterday two_days_ago
    yesterday=$(date -d "yesterday" '+%Y-%m-%d' 2>/dev/null || date -v-1d '+%Y-%m-%d' 2>/dev/null || echo "2099-01-01")
    two_days_ago=$(date -d "2 days ago" '+%Y-%m-%d' 2>/dev/null || date -v-2d '+%Y-%m-%d' 2>/dev/null || echo "")
    # 昨日のファイル: inbound=0 (outboundのみ)
    printf '{"direction": "outbound", "content": "test"}\n' \
        > "$TEST_TMPDIR/logs/lord_conversation_archive/${yesterday}.jsonl"
    # 2日前のファイル: inbound>0 (直近7日内に有効な記録あり)
    if [ -n "$two_days_ago" ]; then
        printf '{"direction": "inbound", "content": "recent"}\n' \
            > "$TEST_TMPDIR/logs/lord_conversation_archive/${two_days_ago}.jsonl"
    fi

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" != *"ALERT: ${yesterday}.jsonlのinbound=0"* ]]
    [[ "$output" == *"INFO: ${yesterday} inbound=0"* ]]
}
