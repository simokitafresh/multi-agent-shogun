#!/usr/bin/env bats
# test_necessity: cmd_save --preflight and cmd_publish must keep the same shared preflight gate set and lesson-cap boundary.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SHARED="$PROJECT_ROOT/scripts/lib/cmd_shared_preflight.sh"
    SAVE="$PROJECT_ROOT/scripts/cmd_save.sh"
    PUBLISH="$PROJECT_ROOT/scripts/cmd_publish.sh"
    TEST_TMPDIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

write_lessons() {
    local count="$1" i
    : > "$TEST_TMPDIR/lessons.yaml"
    for ((i = 1; i <= count; i++)); do
        printf -- '- id: LS%03d\n  summary: active\n' "$i" >> "$TEST_TMPDIR/lessons.yaml"
    done
}

run_shared_as_save() {
    run bash -c 'source "$1"; cmd_shared_preflight "$2" 35' _ "$SHARED" "$TEST_TMPDIR/lessons.yaml"
}

run_shared_as_publish() {
    run bash -c 'source "$1"; cmd_shared_preflight "$2" 35' _ "$SHARED" "$TEST_TMPDIR/lessons.yaml"
}

@test "AC1/AC3: cmd_save and cmd_publish source and call the same shared preflight" {
    run grep -F 'source "$SCRIPT_DIR/lib/cmd_shared_preflight.sh"' "$SAVE"
    [ "$status" -eq 0 ]
    run grep -F 'source "$PROJECT_DIR/scripts/lib/cmd_shared_preflight.sh"' "$PUBLISH"
    [ "$status" -eq 0 ]
    [ "$(grep -c 'cmd_shared_preflight ' "$SAVE")" -eq 1 ]
    [ "$(grep -c 'cmd_shared_preflight ' "$PUBLISH")" -eq 1 ]
    run bash -c 'source "$1"; printf "%s\n" "${CMD_SHARED_PREFLIGHT_GATES[@]}"' _ "$SHARED"
    [ "$status" -eq 0 ]
    [ "$output" = "lesson_cap" ]
}

@test "AC2: active lessons 32 PASS on both paths" {
    write_lessons 32
    run_shared_as_save
    [ "$status" -eq 0 ]
    run_shared_as_publish
    [ "$status" -eq 0 ]
}

@test "AC2: active lessons 33 BLOCK on both paths with truthful boundary" {
    write_lessons 33
    run_shared_as_save
    [ "$status" -eq 1 ]
    [[ "$output" == *"32件以下"* ]]
    [[ "$output" == *"33件以上でBLOCK"* ]]
    run_shared_as_publish
    [ "$status" -eq 1 ]
    [[ "$output" == *"32件以下"* ]]
    [[ "$output" == *"33件以上でBLOCK"* ]]
}
