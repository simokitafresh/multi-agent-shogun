#!/usr/bin/env bash
# Shared scaffold for cmd_complete_gate test family.
# Usage: load '../helpers/cmd_gate_scaffold' in test files.

cmd_gate_setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    export SRC_CONTEXT_FRESHNESS_SCRIPT="$PROJECT_ROOT/scripts/context_freshness_check.sh"
    export SRC_FIELD_GET_SCRIPT="$PROJECT_ROOT/scripts/lib/field_get.sh"
    export SRC_LOCK_PATH_SCRIPT="$PROJECT_ROOT/scripts/lib/lock_path.sh"
    export SRC_YAML_FIELD_SET_SCRIPT="$PROJECT_ROOT/scripts/lib/yaml_field_set.sh"
    export SRC_GUNSHI_NOTIFY_SCRIPT="$PROJECT_ROOT/scripts/lib/gunshi_notify.sh"

    [ -f "$SRC_GATE_SCRIPT" ] || return 1
    [ -f "$SRC_CONTEXT_FRESHNESS_SCRIPT" ] || return 1
    [ -f "$SRC_FIELD_GET_SCRIPT" ] || return 1
    [ -f "$SRC_LOCK_PATH_SCRIPT" ] || return 1
    [ -f "$SRC_YAML_FIELD_SET_SCRIPT" ] || return 1
    [ -f "$SRC_GUNSHI_NOTIFY_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

cmd_gate_scaffold() {
    local tmpdir_prefix="${1:-cmd_gate}"
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/${tmpdir_prefix}.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    export TEST_CMD_ID="cmd_999"

    mkdir -p \
        "$TEST_PROJECT/scripts/lib" \
        "$TEST_PROJECT/scripts/gates" \
        "$TEST_PROJECT/queue/tasks" \
        "$TEST_PROJECT/queue/reports" \
        "$TEST_PROJECT/queue/gates/$TEST_CMD_ID" \
        "$TEST_PROJECT/queue/inbox" \
        "$TEST_PROJECT/config" \
        "$TEST_PROJECT/logs" \
        "$TEST_PROJECT/context" \
        "$TEST_PROJECT/tasks"

    ln -s "$SRC_GATE_SCRIPT" "$TEST_PROJECT/scripts/cmd_complete_gate.sh"
    ln -s "$SRC_CONTEXT_FRESHNESS_SCRIPT" "$TEST_PROJECT/scripts/context_freshness_check.sh"
    ln -s "$SRC_FIELD_GET_SCRIPT" "$TEST_PROJECT/scripts/lib/field_get.sh"
    ln -s "$SRC_LOCK_PATH_SCRIPT" "$TEST_PROJECT/scripts/lib/lock_path.sh"
    ln -s "$SRC_YAML_FIELD_SET_SCRIPT" "$TEST_PROJECT/scripts/lib/yaml_field_set.sh"
    ln -s "$SRC_GUNSHI_NOTIFY_SCRIPT" "$TEST_PROJECT/scripts/lib/gunshi_notify.sh"

    # Non-blocking script stubs required by cmd_complete_gate.sh
    local stubs=(auto_draft_lesson inbox_archive lesson_impact_analysis dashboard_update gist_sync ntfy_cmd ntfy)
    for stub in "${stubs[@]}"; do
        printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_PROJECT/scripts/${stub}.sh"
    done
    printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_PROJECT/scripts/gates/gate_yaml_status.sh"
    printf '#!/usr/bin/env bash\necho "OK"\nexit 0\n' > "$TEST_PROJECT/scripts/gates/gate_dc_duplicate.sh"

    chmod +x "$TEST_PROJECT/scripts/"*.sh "$TEST_PROJECT/scripts/lib/"*.sh "$TEST_PROJECT/scripts/gates/"*.sh

    # Gate bypass flags
    cat > "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/archive.done" <<'EOF'
timestamp: 2026-03-04T00:00:00
source: test
EOF
    cat > "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/lesson.done" <<'EOF'
timestamp: 2026-03-04T00:00:00
source: lesson_check
EOF
}

cmd_gate_teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}
