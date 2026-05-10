#!/usr/bin/env bats
# test_gate_knowledge_freshness.bats — AI開発知識辞書の verified_at 鮮度判定を検証

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_knowledge_freshness.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/knowledge_freshness.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" \
             "$TEST_TMPDIR/docs/research/systems-knowledge-base/systems" \
             "$TEST_TMPDIR/docs/research/systems-knowledge-base/sources"

    cp "$SRC_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_knowledge_freshness.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_knowledge_freshness.sh"

    TODAY="2026-04-19"
    STALE_DATE="2026-03-19"

    _write_table "systems/ace.md" "$TODAY"
    _write_list "systems/claude-code.md" "$TODAY"
    _write_table "systems/gsd.md" "$TODAY"
    _write_table "systems/gstack.md" "$TODAY"
    _write_table "systems/karpathy-principles.md" "$TODAY"
    _write_table "systems/oshio.md" "$TODAY"
    _write_table "systems/vercel.md" "$TODAY"
    _write_list "sources/gyakusegawa.md" "$TODAY"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

_write_table() {
    local rel_path="$1" verified_at="$2"
    local abs_path="$TEST_TMPDIR/docs/research/systems-knowledge-base/$rel_path"
    mkdir -p "$(dirname "$abs_path")"
    cat > "$abs_path" <<EOF
# Test

## Verification

| Field | Value |
|-------|-------|
| verified_at | $verified_at |
EOF
}

_write_list() {
    local rel_path="$1" verified_at="$2"
    local abs_path="$TEST_TMPDIR/docs/research/systems-knowledge-base/$rel_path"
    mkdir -p "$(dirname "$abs_path")"
    cat > "$abs_path" <<EOF
# Test

## Verification

- verified_at: $verified_at
EOF
}

@test "all 8 knowledge files fresh → OK" {
    run env \
        KNOWLEDGE_FRESHNESS_ROOT="$TEST_TMPDIR" \
        KNOWLEDGE_FRESHNESS_TODAY="$TODAY" \
        bash "$TEST_TMPDIR/scripts/gates/gate_knowledge_freshness.sh"

    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c '^FRESH: ')" -eq 8 ]
    [[ "$output" == *"知識鮮度: OK — fresh=8 stale=0 warn=0 total=8"* ]]
}

@test "31-day-old verified_at → STALE and ALERT" {
    _write_table "systems/ace.md" "$STALE_DATE"

    run env \
        KNOWLEDGE_FRESHNESS_ROOT="$TEST_TMPDIR" \
        KNOWLEDGE_FRESHNESS_TODAY="$TODAY" \
        bash "$TEST_TMPDIR/scripts/gates/gate_knowledge_freshness.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"STALE: docs/research/systems-knowledge-base/systems/ace.md (31 days old"* ]]
    [[ "$output" == *"知識鮮度: ALERT — fresh=7 stale=1 warn=0 total=8"* ]]
}

@test "multiple stale files → TOP3 update candidates sorted by age desc" {
    _write_table "systems/ace.md" "2026-03-19"
    _write_table "systems/gsd.md" "2026-02-01"
    _write_table "systems/gstack.md" "2026-01-15"
    _write_list "sources/gyakusegawa.md" "2025-12-31"

    run env \
        KNOWLEDGE_FRESHNESS_ROOT="$TEST_TMPDIR" \
        KNOWLEDGE_FRESHNESS_TODAY="$TODAY" \
        bash "$TEST_TMPDIR/scripts/gates/gate_knowledge_freshness.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"■ STALE更新候補 TOP3 (経過日数降順)"* ]]
    [[ "$output" == *"1. docs/research/systems-knowledge-base/sources/gyakusegawa.md (109 days old; verified_at=2025-12-31)"* ]]
    [[ "$output" == *"2. docs/research/systems-knowledge-base/systems/gstack.md (94 days old; verified_at=2026-01-15)"* ]]
    [[ "$output" == *"3. docs/research/systems-knowledge-base/systems/gsd.md (77 days old; verified_at=2026-02-01)"* ]]
    [[ "$output" == *"python3 scripts/update_verified_at.py docs/research/systems-knowledge-base/sources/gyakusegawa.md 2026-04-19"* ]]
    [[ "$output" != *"4. docs/research/systems-knowledge-base/systems/ace.md"* ]]
}
