#!/usr/bin/env bats
# test_cmd_save_completed_ninjas.bats — Check 5: 未コミット変更時の直近完了忍者表示

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    eval "$(sed -n '/^show_recent_completed_ninjas()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f show_recent_completed_ninjas

    eval "$(sed -n '/^show_uncommitted_changes_warning()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f show_uncommitted_changes_warning

}

setup() {
    export PROJECT_DIR="$BATS_TEST_TMPDIR/project"
    mkdir -p "$PROJECT_DIR/queue"
}

@test "Check5.1: 未コミット変更がある時は直近完了忍者一覧を表示" {
    cat > "$PROJECT_DIR/queue/karo_snapshot.txt" <<'SNAPSHOT'
# 家老陣形図(karo_snapshot) — ninja_monitor.sh自動生成
# Generated: 2026-04-15T16:59:15
ninja|hayate|cmd_1912_impl|done|infra|CTX:20%|M:GPT
ninja|hanzo|cmd_1910_exact|completed|infra|CTX:0%|M:So
ninja|saizo|cmd_1913_impl|acknowledged|infra|CTX:20%|M:GPT
report|hayate|cmd_1912_impl|completed
report|kagemaru|cmd_1909_exact|completed
SNAPSHOT

    run show_uncommitted_changes_warning $'scripts/cmd_save.sh\ntests/unit/test_cmd_save_completed_ninjas.bats'
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: 未コミット変更を検出"* ]]
    [[ "$output" == *"scripts/cmd_save.sh"* ]]
    [[ "$output" == *"tests/unit/test_cmd_save_completed_ninjas.bats"* ]]
    [[ "$output" == *"直近完了忍者一覧: hayate, kagemaru, hanzo"* ]]
}

@test "Check5.2: 未コミット変更がない時は追加表示なし" {
    cat > "$PROJECT_DIR/queue/karo_snapshot.txt" <<'SNAPSHOT'
report|hayate|cmd_1912_impl|completed
SNAPSHOT

    run show_uncommitted_changes_warning ""
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ -z "$output" ]]
}

@test "Check5.3: karo_snapshot.txt不在でもエラーにならない" {
    run show_uncommitted_changes_warning $'scripts/cmd_save.sh\nconfig/projects.yaml'
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: 未コミット変更を検出"* ]]
    [[ "$output" != *"直近完了忍者一覧"* ]]
}
