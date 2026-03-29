#!/usr/bin/env bats
# test_gate_cycle_health.bats — gate_cycle_health.sh + insight_resolve.sh unit tests
# cmd_1502: サイクル停滞検知heartbeatテスト + insight解決ヘルパー

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export SRC_GATE="$PROJECT_ROOT/scripts/gates/gate_cycle_health.sh"
    export SRC_RESOLVE="$PROJECT_ROOT/scripts/insight_resolve.sh"
    export SRC_YAML_FIELD_SET="$PROJECT_ROOT/scripts/lib/yaml_field_set.sh"
    [ -f "$SRC_GATE" ] || return 1
    [ -f "$SRC_RESOLVE" ] || return 1
    [ -f "$SRC_YAML_FIELD_SET" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cycle_health.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" \
             "$TEST_TMPDIR/scripts/lib" \
             "$TEST_TMPDIR/queue/reports" \
             "$TEST_TMPDIR/projects"

    # Copy scripts to tmp dir (SCRIPT_DIR resolves to TEST_TMPDIR)
    cp "$SRC_GATE" "$TEST_TMPDIR/scripts/gates/gate_cycle_health.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_cycle_health.sh"

    cp "$SRC_RESOLVE" "$TEST_TMPDIR/scripts/insight_resolve.sh"
    chmod +x "$TEST_TMPDIR/scripts/insight_resolve.sh"

    cp "$SRC_YAML_FIELD_SET" "$TEST_TMPDIR/scripts/lib/yaml_field_set.sh"

    # Mock inbox_write.sh and ntfy.sh (prevent real side effects)
    printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_TMPDIR/scripts/inbox_write.sh"
    chmod +x "$TEST_TMPDIR/scripts/inbox_write.sh"

    printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_TMPDIR/scripts/ntfy.sh"
    chmod +x "$TEST_TMPDIR/scripts/ntfy.sh"

    # PI fixture: 100% principle ratio (no ALERT)
    cat > "$TEST_TMPDIR/projects/dm-signal.yaml" <<'PIYAML'
production_invariants:
  entries:
    - implication: "全てに適用される原理"
PIYAML

    # Clear cooldown to prevent test interference
    rm -f /tmp/cycle_health_cooldown

    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_cycle_health.sh"
    export TEST_RESOLVE="$TEST_TMPDIR/scripts/insight_resolve.sh"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
    rm -f /tmp/cycle_health_cooldown
}

# ============================================================
# gate_cycle_health.sh tests (AC1)
# ============================================================

# --- Test 1: insights閾値超え → ALERT ---
@test "gate: insights exceeding threshold triggers ALERT" {
    # 20 pending + 1 resolved = 21 total, 20 unresolved > threshold 15
    {
        echo "insights:"
        for i in $(seq 1 20); do
            printf -- "- id: INS-TEST-%03d\n  status: pending\n" "$i"
        done
        printf -- "- id: INS-TEST-RESOLVED\n  status: resolved\n"
    } > "$TEST_TMPDIR/queue/insights.yaml"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT"* ]]
    [[ "$output" == *"insights:"* ]]
    [[ "$output" == *"20件未消化"* ]]
}

# --- Test 2: idle忍者4名以上 → ALERT ---
@test "gate: 4+ idle ninjas triggers ALERT" {
    cat > "$TEST_TMPDIR/queue/karo_snapshot.txt" <<'EOF'
# karo_snapshot
idle|hayate,kagemaru,hanzo,saizo
EOF

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT"* ]]
    [[ "$output" == *"idle忍者"* ]]
    [[ "$output" == *"4名"* ]]
}

# --- Test 3: 全正常 → OK ---
@test "gate: all healthy yields OK status" {
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
    [[ "$output" != *"STATUS: ALERT"* ]]
}

# --- Test 4: 推奨アクション表示確認 ---
@test "gate: recommended actions displayed when issues exist" {
    # 3 pending + 1 resolved (below ALERT threshold, but > 0 → MANUAL action)
    {
        echo "insights:"
        for i in $(seq 1 3); do
            printf -- "- id: INS-TEST-%03d\n  status: pending\n" "$i"
        done
        printf -- "- id: INS-TEST-RESOLVED\n  status: resolved\n"
    } > "$TEST_TMPDIR/queue/insights.yaml"

    # 1 idle ninja (below ALERT threshold, but > 0 → MANUAL action)
    cat > "$TEST_TMPDIR/queue/karo_snapshot.txt" <<'EOF'
# karo_snapshot
idle|hayate
EOF

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
    [[ "$output" == *"将軍が即実行せよ"* ]]
    [[ "$output" == *"insights"* ]]
    [[ "$output" == *"idle忍者"* ]]
}

# ============================================================
# insight_resolve.sh tests (AC2)
# ============================================================

# --- Test 5: 既存insightのresolve → status確認 ---
@test "resolve: sets status=resolved and resolved_reason" {
    cat > "$TEST_TMPDIR/queue/insights.yaml" <<'EOF'
insights:
- id: INS-TEST-001
  ts: '2026-03-29T00:00:00+09:00'
  insight: test insight
  priority: medium
  source: manual
  status: pending
EOF

    run bash "$TEST_RESOLVE" INS-TEST-001 "fixed by cmd_1502"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]

    run grep "status: resolved" "$TEST_TMPDIR/queue/insights.yaml"
    [ "$status" -eq 0 ]

    run grep "resolved_reason" "$TEST_TMPDIR/queue/insights.yaml"
    [ "$status" -eq 0 ]
}

# --- Test 6: 存在しないID → エラー ---
@test "resolve: errors on non-existing insight ID" {
    cat > "$TEST_TMPDIR/queue/insights.yaml" <<'EOF'
insights:
- id: INS-TEST-001
  status: pending
EOF

    run bash "$TEST_RESOLVE" INS-NONEXISTENT "some reason"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}
