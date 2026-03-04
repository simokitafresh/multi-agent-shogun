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

    mkdir -p "$TEST_PROJECT/scripts/lib" "$TEST_PROJECT/queue" "$TEST_PROJECT/context" "$TEST_PROJECT/queue/reports"
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

# ============================================================
# chronicle append tests (AC2/AC4)
# ============================================================

@test "chronicle: creates file and appends entry on cmd archive" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_550
    status: completed
    purpose: "chronicle test"
    project: infra
YAML

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]

    # chronicle file should exist
    [ -f "$TEST_PROJECT/context/cmd-chronicle.md" ]

    # should contain the cmd entry
    run grep -q "cmd_550" "$TEST_PROJECT/context/cmd-chronicle.md"
    [ "$status" -eq 0 ]

    # should contain purpose
    run grep -q "chronicle test" "$TEST_PROJECT/context/cmd-chronicle.md"
    [ "$status" -eq 0 ]

    # should contain project
    run grep -q "infra" "$TEST_PROJECT/context/cmd-chronicle.md"
    [ "$status" -eq 0 ]
}

@test "chronicle: auto-generates month section with table header" {
    # Create chronicle without current month
    cat > "$TEST_PROJECT/context/cmd-chronicle.md" <<'MD'
# CMD年代記
<!-- last_updated: 2026-01-01 -->

## 2026-01

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| cmd_100 | old test | infra | 01-15 | — |
MD

    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_551
    status: completed
    purpose: "month section test"
    project: dm-signal
YAML

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]

    # current month section should be auto-generated
    local year_month
    year_month="$(date '+%Y-%m')"
    run grep -q "^## ${year_month}$" "$TEST_PROJECT/context/cmd-chronicle.md"
    [ "$status" -eq 0 ]

    # old month section should still exist
    run grep -q "^## 2026-01$" "$TEST_PROJECT/context/cmd-chronicle.md"
    [ "$status" -eq 0 ]

    # new entry should be present
    run grep -q "cmd_551" "$TEST_PROJECT/context/cmd-chronicle.md"
    [ "$status" -eq 0 ]
}

@test "chronicle: includes report summary in key_result" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_552
    status: completed
    purpose: "report summary test"
    project: infra
YAML

    # Create a report with summary field
    cat > "$TEST_PROJECT/queue/reports/hanzo_report_cmd_552.yaml" <<'YAML'
parent_cmd: cmd_552
status: done
summary: "All ACs passed. Chronicle append works correctly."
YAML

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]

    # key_result should contain truncated summary (30 chars)
    run grep "cmd_552" "$TEST_PROJECT/context/cmd-chronicle.md"
    [ "$status" -eq 0 ]
    # summary should appear (first 30 chars)
    [[ "$output" == *"All ACs passed"* ]]
}

@test "chronicle: existing archive behavior unaffected" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_553
    status: completed
    purpose: "should archive"
    project: infra
  - id: cmd_554
    purpose: "should keep (no status)"
    project: infra
YAML

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]

    # cmd_553 should be archived (not in queue)
    run grep -q "cmd_553" "$TEST_PROJECT/queue/shogun_to_karo.yaml"
    [ "$status" -eq 1 ]

    # cmd_554 should be kept (in queue)
    run grep -q "cmd_554" "$TEST_PROJECT/queue/shogun_to_karo.yaml"
    [ "$status" -eq 0 ]

    # chronicle should only contain cmd_553
    run grep -q "cmd_553" "$TEST_PROJECT/context/cmd-chronicle.md"
    [ "$status" -eq 0 ]
    run grep -q "cmd_554" "$TEST_PROJECT/context/cmd-chronicle.md"
    [ "$status" -eq 1 ]
}
