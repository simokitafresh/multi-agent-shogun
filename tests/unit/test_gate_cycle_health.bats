#!/usr/bin/env bats
# test_gate_cycle_health.bats — gate_cycle_health.sh unit tests
# cmd_1553: サイクル停滞検知heartbeatのテスト可能分岐を検証

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_cycle_health.sh"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cycle_health.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" \
             "$TEST_TMPDIR/scripts" \
             "$TEST_TMPDIR/queue/reports" \
             "$TEST_TMPDIR/queue/inbox" \
             "$TEST_TMPDIR/projects" \
             "$TEST_TMPDIR/logs"

    # Copy the gate script
    cp "$SRC_GATE_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_cycle_health.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_cycle_health.sh"

    # Mock inbox_write.sh (no-op, record calls)
    cat > "$TEST_TMPDIR/scripts/inbox_write.sh" <<'MOCK'
#!/usr/bin/env bash
echo "MOCK_INBOX_WRITE: $*" >> "${BASH_SOURCE[0]%.sh}.log"
exit 0
MOCK
    chmod +x "$TEST_TMPDIR/scripts/inbox_write.sh"

    # Mock ntfy.sh (no-op, record calls)
    cat > "$TEST_TMPDIR/scripts/ntfy.sh" <<'MOCK'
#!/usr/bin/env bash
echo "MOCK_NTFY: $*" >> "${BASH_SOURCE[0]%.sh}.log"
exit 0
MOCK
    chmod +x "$TEST_TMPDIR/scripts/ntfy.sh"

    # Default: empty karo_snapshot (all ninjas working, no idle)
    cat > "$TEST_TMPDIR/queue/karo_snapshot.txt" <<'EOF'
# 家老陣形図(karo_snapshot)
ninja|hayate|cmd_100_impl|in_progress|infra|CTX:30%
ninja|kagemaru|cmd_101_impl|in_progress|infra|CTX:25%
ninja|hanzo|cmd_102_impl|in_progress|dm-signal|CTX:20%
ninja|saizo|cmd_103_impl|in_progress|dm-signal|CTX:15%
ninja|kotaro|cmd_104_impl|in_progress|infra|CTX:10%
ninja|tobisaru|cmd_105_impl|in_progress|infra|CTX:5%
EOF

    # Default: no insights file
    # Default: no pending reports
    # Default: dm-signal.yaml with 100% principle PI ratio
    cat > "$TEST_TMPDIR/projects/dm-signal.yaml" <<'EOF'
production_invariants:
  entries:
    - id: PI-001
      implication: "全てのパイプラインに適用される原理"
    - id: PI-002
      implication: "任意のティッカーの信頼境界を検証"
EOF

    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_cycle_health.sh"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# === Test 1: 全忍者稼働+GATE未処理0 → HEALTHY ===
@test "all ninjas working, no pending reports → STATUS: OK" {
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS: OK"* ]]
    [[ "$output" == *"サイクル稼働中"* ]]
    # ALERTが出ていないこと
    [[ "$output" != *"ALERT"* ]] || [[ "$output" == *"STATUS: OK"* ]]
}

# === Test 2: idle忍者あり → ALERT+idle名表示 ===
@test "idle ninjas >= 4 → ALERT with idle names" {
    cat > "$TEST_TMPDIR/queue/karo_snapshot.txt" <<'EOF'
# 家老陣形図(karo_snapshot)
ninja|hayate|cmd_100_impl|in_progress|infra|CTX:30%
ninja|kagemaru|cmd_101_impl|in_progress|infra|CTX:25%
idle|hanzo,saizo,kotaro,tobisaru
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS: ALERT"* ]]
    [[ "$output" == *"idle忍者"* ]]
    [[ "$output" == *"4名"* ]]
    [[ "$output" == *"hanzo,saizo,kotaro,tobisaru"* ]]
}

# === Test 3: GATE未処理あり → ALERT+件数表示 ===
@test "pending reports > 3 → ALERT with count" {
    # Create 4 completed reports with recent timestamps
    for i in 1 2 3 4; do
        local rpath="$TEST_TMPDIR/queue/reports/ninja${i}_report_cmd_90${i}.yaml"
        cat > "$rpath" <<EOF
status: completed
worker_id: ninja${i}
parent_cmd: cmd_90${i}
EOF
        # Ensure file mtime is within 24 hours (just created, so it is)
    done

    # No CLEAR entries in gate_metrics.log
    echo "" > "$TEST_TMPDIR/logs/gate_metrics.log"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"GATE未処理報告: 4件"* ]]
}

# === Test 4: PI原理率表示 ===
@test "PI ratio is displayed" {
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PI原理率: 100%"* ]]
}

# === Test 5: 複合ALERT (idle + GATE未処理同時) ===
@test "compound ALERT: idle + pending reports" {
    # idle ninjas
    cat > "$TEST_TMPDIR/queue/karo_snapshot.txt" <<'EOF'
# 家老陣形図(karo_snapshot)
ninja|hayate|cmd_100_impl|in_progress|infra|CTX:30%
idle|kagemaru,hanzo,saizo,kotaro,tobisaru
EOF

    # 4 pending reports
    for i in 1 2 3 4; do
        local rpath="$TEST_TMPDIR/queue/reports/ninja${i}_report_cmd_80${i}.yaml"
        cat > "$rpath" <<EOF
status: completed
worker_id: ninja${i}
parent_cmd: cmd_80${i}
EOF
    done
    echo "" > "$TEST_TMPDIR/logs/gate_metrics.log"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS: ALERT"* ]]
    [[ "$output" == *"idle忍者"* ]]
    [[ "$output" == *"GATE未処理報告"* ]]
    # Forced nudge to karo should have been triggered
    [ -f "$TEST_TMPDIR/scripts/inbox_write.log" ]
}

# === Test 6: idle忍者2名 → INFO (ALERTではない) ===
@test "idle ninjas 2 → INFO not ALERT" {
    cat > "$TEST_TMPDIR/queue/karo_snapshot.txt" <<'EOF'
ninja|hayate|cmd_100_impl|in_progress|infra|CTX:30%
ninja|kagemaru|cmd_101_impl|in_progress|infra|CTX:25%
ninja|hanzo|cmd_102_impl|in_progress|dm-signal|CTX:20%
ninja|saizo|cmd_103_impl|in_progress|dm-signal|CTX:15%
idle|kotaro,tobisaru
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"idle忍者: 2名"* ]]
    # Should be INFO, not ALERT for idle
    [[ "$output" != *"手が遊んでいる"* ]]
}

# === Test 7: PI原理率低い → ALERT ===
@test "PI ratio < 20% → ALERT" {
    cat > "$TEST_TMPDIR/projects/dm-signal.yaml" <<'EOF'
production_invariants:
  entries:
    - id: PI-001
      implication: "特定のティッカーXYZでキャッシュ無効化"
    - id: PI-002
      implication: "特定のパイプラインABCで例外処理"
    - id: PI-003
      implication: "個別のエッジケース対応"
    - id: PI-004
      implication: "特定ケースの修正"
    - id: PI-005
      implication: "個別バグ修正"
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PI原理率: 0%"* ]]
    [[ "$output" == *"個別防御に偏っている"* ]]
}

# === Test 8: insights > 15 → ALERT ===
@test "insights > 15 → ALERT" {
    # Create insights.yaml with 18 entries (16 unresolved + 2 resolved)
    {
        for i in $(seq 1 16); do
            echo "- id: insight_$i"
            echo "  content: test insight $i"
        done
        echo "- id: insight_17"
        echo "  status: resolved"
        echo "- id: insight_18"
        echo "  status: resolved"
    } > "$TEST_TMPDIR/queue/insights.yaml"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"insights: 16件未消化"* ]]
    [[ "$output" == *"気づきが行動に変わっていない"* ]]
}

# === Test 9: GATE CLEAR済みの報告は除外される ===
@test "CLEAR-ed reports are excluded from pending count" {
    # Create 2 completed reports
    for i in 1 2; do
        local rpath="$TEST_TMPDIR/queue/reports/ninja${i}_report_cmd_70${i}.yaml"
        cat > "$rpath" <<EOF
status: completed
worker_id: ninja${i}
parent_cmd: cmd_70${i}
EOF
    done

    # Mark one as CLEAR in gate_metrics.log (tab-separated format)
    printf "2026-03-30T05:00:00\tCLEAR\tcmd_701\tninja1\n" > "$TEST_TMPDIR/logs/gate_metrics.log"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"GATE未処理報告: 1件"* ]]
}
