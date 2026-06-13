#!/usr/bin/env bats
# test_gate_fire_log.bats — scripts/gate_fire_log.sh のユニットテスト

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    SCRIPT="$REPO_ROOT/scripts/gate_fire_log.sh"
    TMP_DIR="$(mktemp -d)"
    TMP_LOG="$TMP_DIR/gate_fire_log.yaml"
    export GATE_FIRE_LOG_CACHE_DIR="$TMP_DIR"
}

teardown() {
    rm -rf "$TMP_DIR" 2>/dev/null || true
}

# ファイル不在 → healed=0 fail_total=0 fail_live=0
@test "no log file returns zeros" {
    run env GATE_FIRE_LOG_FILE="$TMP_DIR/nonexistent.yaml" bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "healed=0 fail_total=0 fail_live=0" ]
}

# FAIL のみ → healed=0
@test "fail only: healed=0 fail_total=2" {
    cat > "$TMP_LOG" << 'EOF'
- ts: "2026-01-01T00:00:01+09:00", file: "queue/reports/a.yaml", gate: "g", result: FAIL, reasons: "x"
- ts: "2026-01-01T00:00:02+09:00", file: "queue/reports/b.yaml", gate: "g", result: FAIL, reasons: "y"
EOF
    run env GATE_FIRE_LOG_FILE="$TMP_LOG" bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "healed=0 fail_total=2 fail_live=0" ]
}

# FAIL → PASS → healed=1
@test "fail then pass: healed=1" {
    cat > "$TMP_LOG" << 'EOF'
- ts: "2026-01-01T00:00:01+09:00", file: "queue/reports/a.yaml", gate: "g", result: FAIL, reasons: "x"
- ts: "2026-01-01T00:00:02+09:00", file: "queue/reports/a.yaml", gate: "g", result: PASS
EOF
    run env GATE_FIRE_LOG_FILE="$TMP_LOG" bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "healed=1 fail_total=1 fail_live=0" ]
}

# PASS のみ → healed=0 fail_total=0
@test "pass only: all zeros" {
    cat > "$TMP_LOG" << 'EOF'
- ts: "2026-01-01T00:00:01+09:00", file: "queue/reports/a.yaml", gate: "g", result: PASS
- ts: "2026-01-01T00:00:02+09:00", file: "queue/reports/b.yaml", gate: "g", result: PASS
EOF
    run env GATE_FIRE_LOG_FILE="$TMP_LOG" bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "healed=0 fail_total=0 fail_live=0" ]
}

# キャッシュヒット: 2回目は同じ結果
@test "cache hit returns same result" {
    cat > "$TMP_LOG" << 'EOF'
- ts: "2026-01-01T00:00:01+09:00", file: "queue/reports/a.yaml", gate: "g", result: FAIL, reasons: "x"
- ts: "2026-01-01T00:00:02+09:00", file: "queue/reports/a.yaml", gate: "g", result: PASS
EOF
    run env GATE_FIRE_LOG_FILE="$TMP_LOG" bash "$SCRIPT"
    first="$output"
    run env GATE_FIRE_LOG_FILE="$TMP_LOG" bash "$SCRIPT"
    [ "$output" = "$first" ]
}

# 空ファイル → zeros
@test "empty log file returns zeros" {
    touch "$TMP_LOG"
    run env GATE_FIRE_LOG_FILE="$TMP_LOG" bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "healed=0 fail_total=0 fail_live=0" ]
}
