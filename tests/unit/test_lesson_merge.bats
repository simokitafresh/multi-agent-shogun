#!/usr/bin/env bats
# test_lesson_merge.bats — lesson_merge.sh unit tests
# Covers: basic merge, normalize_id, error cases, already-deprecated detection

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC="$PROJECT_ROOT/scripts/lesson_merge.sh"
    [ -f "$SRC" ] || return 1
}

setup() {
    export SANDBOX
    SANDBOX="$(mktemp -d "$BATS_TMPDIR/lesson_merge.XXXXXX")"
    mkdir -p "$SANDBOX/scripts/lib" "$SANDBOX/config" "$SANDBOX/tasks"

    cp "$PROJECT_ROOT/scripts/lib/lock_path.sh" "$SANDBOX/scripts/lib/"

    # Mock sync_lessons.sh (no-op)
    cat > "$SANDBOX/scripts/sync_lessons.sh" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$SANDBOX/scripts/sync_lessons.sh"

    # Minimal config/projects.yaml
    cat > "$SANDBOX/config/projects.yaml" <<CONF
projects:
  - id: testprj
    path: "$SANDBOX"
CONF

    # Fresh lessons.md with 3 test entries
    cat > "$SANDBOX/tasks/lessons.md" <<'LESS'
# Test Lessons

### L001: First lesson
- **status**: confirmed
- **日付**: 2026-01-01
- first lesson content

### L002: Second lesson
- **status**: confirmed
- **日付**: 2026-01-02
- second lesson content

### L003: Third lesson
- **status**: confirmed
- **日付**: 2026-01-03
- third lesson content
LESS
}

teardown() {
    rm -rf "$SANDBOX"
}

# ─── Basic merge ───────────────────────────────────────────────────────────────

@test "lesson_merge: L001+L002 creates L004 with merged content" {
    run env LESSON_MERGE_SCRIPT_DIR="$SANDBOX" bash "$SRC" \
        testprj L001 L002 "Merged title" "Merged summary"
    [ "$status" -eq 0 ]
    [[ "$output" == *"L001 + L002 → L004"* ]]
    [[ "$output" == *"Done. New lesson: L004"* ]]
    grep -q "### L004: Merged title" "$SANDBOX/tasks/lessons.md"
    grep -q "merged_from.*L001.*L002" "$SANDBOX/tasks/lessons.md"
}

@test "lesson_merge: source entries get deprecated_by set" {
    run env LESSON_MERGE_SCRIPT_DIR="$SANDBOX" bash "$SRC" \
        testprj L001 L002 "Merged title" "Merged summary"
    [ "$status" -eq 0 ]
    grep -A 10 "### L001:" "$SANDBOX/tasks/lessons.md" | grep -q "deprecated_by.*L004"
    grep -A 10 "### L002:" "$SANDBOX/tasks/lessons.md" | grep -q "deprecated_by.*L004"
}

@test "lesson_merge: source entries get status: deprecated" {
    run env LESSON_MERGE_SCRIPT_DIR="$SANDBOX" bash "$SRC" \
        testprj L001 L002 "Merged title" "Merged summary"
    [ "$status" -eq 0 ]
    grep -A 10 "### L001:" "$SANDBOX/tasks/lessons.md" | grep -q "status.*deprecated"
    grep -A 10 "### L002:" "$SANDBOX/tasks/lessons.md" | grep -q "status.*deprecated"
}

@test "lesson_merge: untouched entry L003 is unchanged" {
    run env LESSON_MERGE_SCRIPT_DIR="$SANDBOX" bash "$SRC" \
        testprj L001 L002 "Merged title" "Merged summary"
    [ "$status" -eq 0 ]
    # L003 should still be confirmed
    grep -A 5 "### L003:" "$SANDBOX/tasks/lessons.md" | grep -q "status.*confirmed"
    # L003 should have no deprecated_by
    ! grep -A 10 "### L003:" "$SANDBOX/tasks/lessons.md" | grep -q "deprecated_by"
}

# ─── normalize_id ──────────────────────────────────────────────────────────────

@test "lesson_merge: accepts short ID L1 normalizes to L001" {
    # Add short-form lesson
    cat >> "$SANDBOX/tasks/lessons.md" <<'EOF'

### L010: Tenth lesson
- **status**: confirmed
- **日付**: 2026-01-10
- tenth content
EOF
    run env LESSON_MERGE_SCRIPT_DIR="$SANDBOX" bash "$SRC" \
        testprj L1 L10 "Normalized merge" "summary"
    [ "$status" -eq 0 ]
    [[ "$output" == *"L001 + L010"* ]]
}

@test "lesson_merge: accepts zero-padded L002 same as L2" {
    run env LESSON_MERGE_SCRIPT_DIR="$SANDBOX" bash "$SRC" \
        testprj L002 L003 "Padded merge" "summary"
    [ "$status" -eq 0 ]
    [[ "$output" == *"L002 + L003"* ]]
}

# ─── Error cases ───────────────────────────────────────────────────────────────

@test "lesson_merge: fails if project not found" {
    run env LESSON_MERGE_SCRIPT_DIR="$SANDBOX" bash "$SRC" \
        BADPROJECT L001 L002 "title" "summary"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"BADPROJECT"* ]]
}

@test "lesson_merge: fails if source_id_1 == source_id_2" {
    run env LESSON_MERGE_SCRIPT_DIR="$SANDBOX" bash "$SRC" \
        testprj L001 L001 "title" "summary"
    [ "$status" -ne 0 ]
    [[ "$output" == *"同じ"* ]]
}

@test "lesson_merge: fails if source ID not found in lessons.md" {
    run env LESSON_MERGE_SCRIPT_DIR="$SANDBOX" bash "$SRC" \
        testprj L001 L999 "title" "summary"
    [ "$status" -ne 0 ]
    [[ "$output" == *"L999"* ]] || [[ "$output" == *"見つからない"* ]]
}

@test "lesson_merge: fails if source is already deprecated" {
    # Mark L001 as deprecated first
    sed -i 's/- \*\*status\*\*: confirmed/- **status**: deprecated/' "$SANDBOX/tasks/lessons.md"
    run env LESSON_MERGE_SCRIPT_DIR="$SANDBOX" bash "$SRC" \
        testprj L001 L002 "title" "summary"
    [ "$status" -ne 0 ]
    [[ "$output" == *"deprecated"* ]]
}

@test "lesson_merge: fails with missing arguments" {
    run env LESSON_MERGE_SCRIPT_DIR="$SANDBOX" bash "$SRC"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage"* ]]
}
