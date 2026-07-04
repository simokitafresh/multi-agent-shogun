#!/usr/bin/env bats
# test_lesson_deprecate.bats - lesson_deprecate.sh unit tests
# Covers: inline format (infra), block format (dm-signal), error cases, re-deprecation

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC="$PROJECT_ROOT/scripts/lesson_deprecate.sh"
    [ -f "$SRC" ] || return 1
}

setup() {
    export SANDBOX
    SANDBOX="$(mktemp -d "$BATS_TMPDIR/lesson_dep.XXXXXX")"
    mkdir -p "$SANDBOX/scripts" "$SANDBOX/projects/infra" "$SANDBOX/projects/dm-signal"
    cp "$SRC" "$SANDBOX/scripts/lesson_deprecate.sh"
    chmod +x "$SANDBOX/scripts/lesson_deprecate.sh"

    # inline形式 (infra)
    cat > "$SANDBOX/projects/infra/lessons.yaml" <<'EOF'
lessons:
- {id: L001, title: 'inline lesson one', summary: 'test summary', tags: [infra]}
- {id: L002, title: 'inline lesson two', summary: 'another summary', tags: [infra]}
- {id: L003, title: 'already deprecated', summary: 'was deprecated', deprecated: true, deprecated_at: '2026-01-01T00:00:00+09:00', deprecated_reason: 'old reason', deprecated_by: 'cmd_old'}
EOF

    # ブロック形式 (dm-signal)
    cat > "$SANDBOX/projects/dm-signal/lessons.yaml" <<'EOF'
lessons:
- id: L010
  title: block lesson one
  summary: block summary
  tags:
  - dm-signal
- id: L011
  title: block lesson two
  summary: block summary two
  tags:
  - dm-signal
- id: L012
  title: already deprecated block
  summary: deprecated block lesson
  deprecated: true
  deprecated_at: '2026-01-01T00:00:00+09:00'
  deprecated_reason: 'old block reason'
  deprecated_by: 'cmd_old_block'
EOF
}

teardown() {
    rm -rf "$SANDBOX"
}

run_script() {
    LESSON_DEPRECATE_ROOT="$SANDBOX" bash "$SANDBOX/scripts/lesson_deprecate.sh" "$@"
}

# ── inline形式テスト ──

@test "inline: deprecate fresh lesson succeeds" {
    run run_script infra L001 "test reason" cmd_test
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEPRECATED: infra/L001"* ]]
    grep -q "deprecated: true" "$SANDBOX/projects/infra/lessons.yaml"
    grep -q "deprecated_reason: 'test reason'" "$SANDBOX/projects/infra/lessons.yaml"
    grep -q "deprecated_by: 'cmd_test'" "$SANDBOX/projects/infra/lessons.yaml"
}

@test "normal operation delegates to lesson_write retire path" {
    cat > "$SANDBOX/scripts/lesson_write.sh" <<'EOF'
#!/usr/bin/env bash
echo "$*" > "$(cd "$(dirname "$0")/.." && pwd)/lesson_write_called.log"
exit 0
EOF
    chmod +x "$SANDBOX/scripts/lesson_write.sh"

    run bash "$SANDBOX/scripts/lesson_deprecate.sh" infra L001 "legacy reason" cmd_test
    [ "$status" -eq 0 ]
    [[ "$output" == *"delegating to lesson_write.sh --retire"* ]]
    [ "$(cat "$SANDBOX/lesson_write_called.log")" = "infra --retire L001" ]
    ! grep -q "L001.*deprecated: true" "$SANDBOX/projects/infra/lessons.yaml"
}

@test "inline: deprecate without cmd_id succeeds" {
    run run_script infra L001 "no cmd reason"
    [ "$status" -eq 0 ]
    grep -q "deprecated: true" "$SANDBOX/projects/infra/lessons.yaml"
    ! grep -q "deprecated_by" <(grep "L001" "$SANDBOX/projects/infra/lessons.yaml")
}

@test "inline: re-deprecation updates existing deprecated fields" {
    run run_script infra L003 "updated reason" cmd_new
    [ "$status" -eq 0 ]
    # 古いreason/cmdが置き換えられること
    ! grep -q "old reason" "$SANDBOX/projects/infra/lessons.yaml"
    grep -q "deprecated_reason: 'updated reason'" "$SANDBOX/projects/infra/lessons.yaml"
    grep -q "deprecated_by: 'cmd_new'" "$SANDBOX/projects/infra/lessons.yaml"
}

@test "inline: lesson not found exits immediately without retry" {
    run run_script infra L999 "should fail"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    # リトライメッセージが出ないこと
    ! [[ "$output" == *"Lock timeout"* ]]
}

@test "inline: other lessons are unmodified after deprecation" {
    run run_script infra L001 "deprecate one"
    [ "$status" -eq 0 ]
    # L002が変更されていないこと
    grep -q "L002" "$SANDBOX/projects/infra/lessons.yaml"
    grep -q "inline lesson two" "$SANDBOX/projects/infra/lessons.yaml"
}

# ── ブロック形式テスト ──

@test "block: deprecate fresh lesson succeeds" {
    run run_script dm-signal L010 "block test reason" cmd_blk
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEPRECATED: dm-signal/L010"* ]]
    grep -A 10 "^- id: L010" "$SANDBOX/projects/dm-signal/lessons.yaml" | grep -q "deprecated: true"
    grep -A 10 "^- id: L010" "$SANDBOX/projects/dm-signal/lessons.yaml" | grep -q "deprecated_reason: 'block test reason'"
}

@test "block: deprecate without cmd_id succeeds" {
    run run_script dm-signal L010 "no cmd reason"
    [ "$status" -eq 0 ]
    grep -A 10 "^- id: L010" "$SANDBOX/projects/dm-signal/lessons.yaml" | grep -q "deprecated: true"
}

@test "block: re-deprecation updates existing deprecated fields" {
    run run_script dm-signal L012 "updated block reason" cmd_new_blk
    [ "$status" -eq 0 ]
    ! grep -A 10 "^- id: L012" "$SANDBOX/projects/dm-signal/lessons.yaml" | grep -q "old block reason"
    grep -A 10 "^- id: L012" "$SANDBOX/projects/dm-signal/lessons.yaml" | grep -q "deprecated_reason: 'updated block reason'"
}

@test "block: lesson not found exits without retry" {
    run run_script dm-signal L999 "should fail"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    ! [[ "$output" == *"Lock timeout"* ]]
}

@test "block: other lessons are unmodified after deprecation" {
    run run_script dm-signal L010 "deprecate one"
    [ "$status" -eq 0 ]
    grep -q "^- id: L011" "$SANDBOX/projects/dm-signal/lessons.yaml"
    grep -q "block lesson two" "$SANDBOX/projects/dm-signal/lessons.yaml"
}

# ── エラーケース ──

@test "missing project exits with error" {
    run run_script nonexistent L001 "reason"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
}

@test "missing arguments exits with usage message" {
    run run_script infra
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "single-quote in reason is escaped correctly (inline)" {
    run run_script infra L001 "it's a test" cmd_sq
    [ "$status" -eq 0 ]
    grep -q "deprecated_reason: 'it''s a test'" "$SANDBOX/projects/infra/lessons.yaml"
}

@test "single-quote in reason is escaped correctly (block)" {
    run run_script dm-signal L010 "don't fail" cmd_sq
    [ "$status" -eq 0 ]
    grep -A 10 "^- id: L010" "$SANDBOX/projects/dm-signal/lessons.yaml" | grep -q "deprecated_reason: 'don''t fail'"
}
