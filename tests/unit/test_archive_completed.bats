#!/usr/bin/env bats
# test_archive_completed.bats - unit tests for scripts/archive_completed.sh

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_ARCHIVE_SCRIPT="$PROJECT_ROOT/scripts/archive_completed.sh"
    export SRC_FIELD_GET_SCRIPT="$PROJECT_ROOT/scripts/lib/field_get.sh"

    [ -f "$SRC_ARCHIVE_SCRIPT" ] || return 1
    [ -f "$SRC_FIELD_GET_SCRIPT" ] || return 1
    command -v awk >/dev/null 2>&1 || return 1
    command -v flock >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/archive_completed.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"

    mkdir -p "$TEST_PROJECT/scripts/lib" "$TEST_PROJECT/queue"
    cp "$SRC_ARCHIVE_SCRIPT" "$TEST_PROJECT/scripts/archive_completed.sh"
    cp "$SRC_FIELD_GET_SCRIPT" "$TEST_PROJECT/scripts/lib/field_get.sh"

    # postconditionで呼ばれても外部通知しないようにスタブ化
    cat > "$TEST_PROJECT/scripts/ntfy.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$TEST_PROJECT/scripts/archive_completed.sh" \
        "$TEST_PROJECT/scripts/lib/field_get.sh" \
        "$TEST_PROJECT/scripts/ntfy.sh"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "archives cmd when status is missing but cmd exists in completed_changelog" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_520
    purpose: "test purpose"
    project: infra
YAML

    cat > "$TEST_PROJECT/queue/completed_changelog.yaml" <<'YAML'
entries:
  - id: cmd_520
    completed_at: "2026-03-04T00:00:00"
YAML

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]

    run grep -q "cmd_520" "$TEST_PROJECT/queue/shogun_to_karo.yaml"
    [ "$status" -eq 1 ]

    run bash -lc "compgen -G '$TEST_PROJECT/queue/archive/cmds/cmd_520_completed_*.yaml' >/dev/null"
    [ "$status" -eq 0 ]
}

@test "keeps cmd when status is missing and completed_changelog has no exact cmd match" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_521
    purpose: "test purpose"
    project: infra
YAML

    cat > "$TEST_PROJECT/queue/completed_changelog.yaml" <<'YAML'
entries:
  - id: cmd_5210
    completed_at: "2026-03-04T00:00:00"
YAML

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]

    run grep -q "id: cmd_521" "$TEST_PROJECT/queue/shogun_to_karo.yaml"
    [ "$status" -eq 0 ]

    run bash -lc "compgen -G '$TEST_PROJECT/queue/archive/cmds/cmd_521_*.yaml' >/dev/null"
    [ "$status" -eq 1 ]
}

@test "preserves existing status-based archive behavior" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_530
    status: completed
    purpose: "status completed"
    project: infra
YAML

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]

    run grep -q "cmd_530" "$TEST_PROJECT/queue/shogun_to_karo.yaml"
    [ "$status" -eq 1 ]

    run bash -lc "compgen -G '$TEST_PROJECT/queue/archive/cmds/cmd_530_completed_*.yaml' >/dev/null"
    [ "$status" -eq 0 ]
}
