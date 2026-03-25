#!/usr/bin/env bats
# test_sync_lessons.bats - sync_lessons.sh unit tests
# Merged from: test_sync_lessons_if_then_compat.bats + test_sync_lessons_injection_count_sync.bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SYNC_SCRIPT="$PROJECT_ROOT/scripts/sync_lessons.sh"
    [ -f "$SRC_SYNC_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/sync_lessons.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    export EXT_PROJECT="$TEST_TMPDIR/extproj"

    mkdir -p \
        "$TEST_PROJECT/scripts" \
        "$TEST_PROJECT/config" \
        "$TEST_PROJECT/logs" \
        "$TEST_PROJECT/projects/testproj" \
        "$EXT_PROJECT/tasks"

    cp "$SRC_SYNC_SCRIPT" "$TEST_PROJECT/scripts/sync_lessons.sh"
    chmod +x "$TEST_PROJECT/scripts/sync_lessons.sh"

    cat > "$TEST_PROJECT/config/projects.yaml" <<EOF
projects:
  - id: testproj
    path: $EXT_PROJECT
EOF
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "sync_lessons succeeds when existing lessons.yaml includes optional if_then" {
    cat > "$EXT_PROJECT/tasks/lessons.md" <<'EOF'
---
title: test
---

## 教訓索引（自動追記）

### L001: sample lesson
- **日付**: 2026-03-05
- **出典**: cmd_575
- sample summary text
EOF

    cat > "$TEST_PROJECT/projects/testproj/lessons.yaml" <<'EOF'
ssot_path: /tmp/dummy
last_synced: '2026-03-05T00:00:00'
lessons:
  - id: L001
    title: sample lesson
    summary: sample summary text
    helpful_count: 2
    harmful_count: 0
    injection_count: 3
    if_then:
      if: trigger
      then: action
      because: reason
EOF

    run bash "$TEST_PROJECT/scripts/sync_lessons.sh" testproj
    [ "$status" -eq 0 ]

    run python3 -c "
import yaml
with open('$TEST_PROJECT/projects/testproj/lessons.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
lessons = data.get('lessons', [])
assert lessons and lessons[0].get('id') == 'L001'
print('ok')
"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "sync_lessons writes back project-local injection_count from lesson_impact.tsv" {
    cat > "$EXT_PROJECT/tasks/lessons.md" <<'EOF'
### L001: sample lesson
- sample summary text
EOF

    cat > "$TEST_PROJECT/projects/testproj/lessons.yaml" <<'EOF'
ssot_path: /tmp/dummy
last_synced: '2026-03-05T00:00:00'
lessons:
  - id: L001
    title: sample lesson
    summary: sample summary text
    helpful_count: 2
    harmful_count: 0
    injection_count: 0
EOF

    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-03-13T01:00:00	cmd_100	sasuke	L001	injected	CLEAR	yes	testproj	impl	routine
2026-03-13T01:05:00	cmd_101	sasuke	L001	injected	BLOCK	no	testproj	impl	routine
2026-03-13T01:07:00	cmd_101a	sasuke	L001	injected	PENDING	pending	testproj	impl	routine
2026-03-13T01:10:00	cmd_102	sasuke	L001	injected	CLEAR	yes	otherproj	impl	routine
EOF

    run bash "$TEST_PROJECT/scripts/sync_lessons.sh" testproj
    [ "$status" -eq 0 ]

    run python3 -c "
import yaml
with open('$TEST_PROJECT/projects/testproj/lessons_archive.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
lesson = data['lessons'][0]
assert lesson['id'] == 'L001'
assert lesson['helpful_count'] == 2
assert lesson['injection_count'] == 2
print('ok')
"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}
