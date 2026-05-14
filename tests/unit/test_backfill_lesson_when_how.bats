#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_BACKFILL_SCRIPT="$PROJECT_ROOT/scripts/backfill_lesson_when_how.py"
    export SRC_SYNC_SCRIPT="$PROJECT_ROOT/scripts/sync_lessons.sh"
    [ -f "$SRC_BACKFILL_SCRIPT" ] || return 1
    [ -f "$SRC_SYNC_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/backfill_lesson_when_how.XXXXXX")"
    export TEST_ROOT="$TEST_TMPDIR/root"
    export EXT_PROJECT="$TEST_TMPDIR/extproj"

    mkdir -p \
        "$TEST_ROOT/scripts" \
        "$TEST_ROOT/config" \
        "$TEST_ROOT/logs" \
        "$TEST_ROOT/projects/testproj" \
        "$EXT_PROJECT/tasks"

    cp "$SRC_BACKFILL_SCRIPT" "$TEST_ROOT/scripts/backfill_lesson_when_how.py"
    cp "$SRC_SYNC_SCRIPT" "$TEST_ROOT/scripts/sync_lessons.sh"
    chmod +x "$TEST_ROOT/scripts/backfill_lesson_when_how.py" "$TEST_ROOT/scripts/sync_lessons.sh"

    cat > "$TEST_ROOT/config/projects.yaml" <<EOF
projects:
  - id: testproj
    path: $EXT_PROJECT
EOF
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "backfill_lesson_when_how infers missing when/how and syncs lessons index" {
    cat > "$EXT_PROJECT/tasks/lessons.md" <<'EOF'
### L001: lesson_write.shで新規教訓を登録する時
- **日付**: 2026-05-15
- **tags**: [infra]
- **if**: lesson_write.shで新規教訓を登録する時
- **then**: --when と --how を明示して登録する
- **when**: 未設定
- **how**: 未設定
- IF lesson_write.shで新規教訓を登録する時 THEN --when と --how を明示して登録する

### L002: 既存whenを維持する
- **日付**: 2026-05-15
- **tags**: [infra]
- **when**: 既に発動条件がある時
- **how**: 既に手順がある時
- これは変更しない
EOF

    cat > "$TEST_ROOT/projects/testproj/lessons.yaml" <<'EOF'
ssot_path: /tmp/dummy
last_synced: '2026-05-15T00:00:00'
lessons: []
EOF

    run env BACKFILL_LESSON_SCRIPT_DIR="$TEST_ROOT" \
        python3 "$TEST_ROOT/scripts/backfill_lesson_when_how.py" testproj
    [ "$status" -eq 0 ]
    [[ "$output" == *"testproj: when 1/2 -> 2/2; how 1/2 -> 2/2"* ]]

    run python3 -c "
import yaml
from pathlib import Path
md = Path('$EXT_PROJECT/tasks/lessons.md').read_text(encoding='utf-8')
assert '- **when**: lesson_write.shで新規教訓を登録する時' in md
assert '- **how**: --when と --how を明示して登録する' in md
assert '- **when**: 未設定' not in md
assert '- **how**: 未設定' not in md
with open('$TEST_ROOT/projects/testproj/lessons.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
lessons = data['lessons']
by_id = {lesson['id']: lesson for lesson in lessons}
assert by_id['L001']['when'] == 'lesson_write.shで新規教訓を登録する時', by_id['L001']
assert by_id['L001']['how'] == '--when と --how を明示して登録する', by_id['L001']
assert by_id['L002']['when'] == '既に発動条件がある時', by_id['L002']
print('ok')
"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]

    run grep -F "testproj: total=2 when=1/2(50.0%) -> 2/2(100.0%); how=1/2(50.0%) -> 2/2(100.0%)" "$TEST_ROOT/logs/lesson_when_how_backfill_cmd_2748.log"
    [ "$status" -eq 0 ]
}
