#!/usr/bin/env bats
# test_sync_lessons_if_then_compat.bats - cmd_575 optional if_then compatibility

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SYNC_SCRIPT="$PROJECT_ROOT/scripts/sync_lessons.sh"
    [ -f "$SRC_SYNC_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/sync_if_then.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    export EXT_PROJECT="$TEST_TMPDIR/extproj"

    mkdir -p \
        "$TEST_PROJECT/scripts" \
        "$TEST_PROJECT/config" \
        "$TEST_PROJECT/projects/testproj" \
        "$EXT_PROJECT/tasks"

    cp "$SRC_SYNC_SCRIPT" "$TEST_PROJECT/scripts/sync_lessons.sh"
    chmod +x "$TEST_PROJECT/scripts/sync_lessons.sh"

    cat > "$TEST_PROJECT/config/projects.yaml" <<EOF
projects:
  - id: testproj
    path: $EXT_PROJECT
EOF

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
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "sync_lessons succeeds when existing lessons.yaml includes optional if_then" {
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
