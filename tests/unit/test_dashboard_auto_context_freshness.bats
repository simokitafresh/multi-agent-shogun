#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_DASHBOARD_SCRIPT="$PROJECT_ROOT/scripts/dashboard_auto_section.sh"
    export SRC_CONTEXT_FRESHNESS_SCRIPT="$PROJECT_ROOT/scripts/context_freshness_check.sh"
    export SRC_AGENT_CONFIG_SCRIPT="$PROJECT_ROOT/scripts/lib/agent_config.sh"

    [ -f "$SRC_DASHBOARD_SCRIPT" ] || return 1
    [ -f "$SRC_CONTEXT_FRESHNESS_SCRIPT" ] || return 1
    [ -f "$SRC_AGENT_CONFIG_SCRIPT" ] || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/dashboard_ctx.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"

    mkdir -p \
        "$TEST_PROJECT/scripts/lib" \
        "$TEST_PROJECT/config" \
        "$TEST_PROJECT/context" \
        "$TEST_PROJECT/queue/archive/cmds" \
        "$TEST_PROJECT/queue/tasks" \
        "$TEST_PROJECT/logs"

    cp "$SRC_DASHBOARD_SCRIPT" "$TEST_PROJECT/scripts/dashboard_auto_section.sh"
    cp "$SRC_CONTEXT_FRESHNESS_SCRIPT" "$TEST_PROJECT/scripts/context_freshness_check.sh"
    cp "$SRC_AGENT_CONFIG_SCRIPT" "$TEST_PROJECT/scripts/lib/agent_config.sh"
    chmod +x \
        "$TEST_PROJECT/scripts/dashboard_auto_section.sh" \
        "$TEST_PROJECT/scripts/context_freshness_check.sh" \
        "$TEST_PROJECT/scripts/lib/agent_config.sh"

    cat > "$TEST_PROJECT/config/projects.yaml" <<EOF
projects:
  - id: dm-signal
    status: active
    context_file: context/dm-signal.md
    context_files:
      - file: context/dm-signal-core.md
  - id: infra
    status: active
    context_file: context/infrastructure.md
EOF

    cat > "$TEST_PROJECT/config/settings.yaml" <<'EOF'
cli:
  default: codex
  agents: {}
EOF

    cat > "$TEST_PROJECT/queue/karo_snapshot.txt" <<'EOF'
idle|sasuke,kirimaru,hayate,kagemaru,hanzo,saizo,kotaro,tobisaru
EOF

    cat > "$TEST_PROJECT/context/infrastructure.md" <<'EOF'
# Infra
<!-- last_updated: 2026-03-01 cmd_001 -->
EOF

    cat > "$TEST_PROJECT/context/dm-signal.md" <<'EOF'
# DM
<!-- last_updated: 2026-03-10 cmd_002 -->
EOF

    cat > "$TEST_PROJECT/context/dm-signal-core.md" <<'EOF'
# DM Core
<!-- last_updated: 2026-03-10 cmd_003 -->
EOF
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

write_archived_cmd() {
    local project_id="$1"
    local file_name="$2"
    # Use a recent date (within CONTEXT_STALE_DAYS=7) so the cmd is detected as "recent"
    local recent_date
    recent_date="$(date -d '2 days ago' '+%Y-%m-%dT%H:%M:%S+09:00')"
    cat > "$TEST_PROJECT/queue/archive/cmds/$file_name" <<EOF
commands:
- id: cmd_test
  project: $project_id
  status: completed
  completed_at: "$recent_date"
EOF
}

@test "dashboard auto section shows context freshness warning for stale context with recent completed cmd" {
    write_archived_cmd "infra" "cmd_test_completed_20260311.yaml"

    run bash "$TEST_PROJECT/scripts/dashboard_auto_section.sh" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"### Context鮮度警告"* ]]
    [[ "$output" == *"WARN: context/infrastructure.md last_updated"* ]]
}

@test "dashboard auto section suppresses warning when project has no recent completed cmd" {
    run bash "$TEST_PROJECT/scripts/dashboard_auto_section.sh" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"### Context鮮度警告"* ]]
    [[ "$output" == *$'\nなし\n'* ]]
}
