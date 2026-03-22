#!/usr/bin/env bats
# ═══════════════════════════════════════════════════════════════
# E2E-011: slim_reports retention behavior
# ═══════════════════════════════════════════════════════════════
# Verifies slim_yaml.py keeps unprocessed reports for active cmds,
# archives old reports for done cmds, and preserves canonical reports.
#
# Adapted from yohey-w/multi-agent-shogun for local layout.
# NOTE: Requires scripts/slim_yaml.py which may not exist locally.
# ═══════════════════════════════════════════════════════════════

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

    [ -f "$PROJECT_ROOT/scripts/slim_yaml.py" ] || {
        echo "slim_yaml.py not found at $PROJECT_ROOT/scripts/ — skipping all tests" >&2
        export SLIM_YAML_MISSING=1
        return 0
    }

    command -v python3 &>/dev/null || {
        echo "python3 not available" >&2
        return 1
    }
}

setup() {
    [ "${SLIM_YAML_MISSING:-}" = "1" ] && skip "slim_yaml.py not found"

    source "$PROJECT_ROOT/tests/helpers/assertions.bash"
}

build_tmp_project() {
    local root="$1"
    mkdir -p "$root/scripts" "$root/queue"/{inbox,tasks,reports,archive,archive/reports}
}

run_slim_yaml() {
    local root="$1"
    local agent="$2"
    python3 "$root/scripts/slim_yaml.py" "$agent"
}

seed_yaml() {
    local file="$1" value="$2"
    printf '%s\n' "$value" > "$file"
}

@test "E2E-011-A: unprocessed report with active cmd is kept" {
    local root
    root="$(mktemp -d "/tmp/e2e_slim_retention_XXXXXX")"
    build_tmp_project "$root"
    cp "$PROJECT_ROOT/scripts/slim_yaml.py" "$root/scripts/"

    seed_yaml "$root/queue/shogun_to_karo.yaml" $'commands:\n  - id: cmd_test\n    status: pending\n'
    seed_yaml "$root/queue/reports/sasuke_cmd_test_report.yaml" $'parent_cmd: cmd_test\nstatus: done\n'
    seed_yaml "$root/queue/reports/sasuke_report.yaml" $'parent_cmd: cmd_ignored\nstatus: done\n'

    touch -d "2 days ago" "$root/queue/reports/sasuke_cmd_test_report.yaml"
    touch -d "2 days ago" "$root/queue/reports/sasuke_report.yaml"

    run run_slim_yaml "$root" karo
    [ "$status" -eq 0 ]

    # Active parent_cmd means this report is kept.
    [ -f "$root/queue/reports/sasuke_cmd_test_report.yaml" ]
    # Canonical report is always preserved.
    [ -f "$root/queue/reports/sasuke_report.yaml" ]

    rm -rf "$root"
}

@test "E2E-011-B: old report for done cmd is archived" {
    local root
    root="$(mktemp -d "/tmp/e2e_slim_retention_XXXXXX")"
    build_tmp_project "$root"
    cp "$PROJECT_ROOT/scripts/slim_yaml.py" "$root/scripts/"

    seed_yaml "$root/queue/shogun_to_karo.yaml" $'commands:\n  - id: cmd_test\n    status: done\n'
    seed_yaml "$root/queue/reports/sasuke_cmd_test_report.yaml" $'parent_cmd: cmd_test\nstatus: done\n'
    seed_yaml "$root/queue/reports/sasuke_report.yaml" $'parent_cmd: cmd_ignored\nstatus: done\n'

    touch -d "2 days ago" "$root/queue/reports/sasuke_cmd_test_report.yaml"
    touch -d "2 days ago" "$root/queue/reports/sasuke_report.yaml"

    run run_slim_yaml "$root" karo
    [ "$status" -eq 0 ]

    # Non-canonical report is archived.
    [ ! -f "$root/queue/reports/sasuke_cmd_test_report.yaml" ]
    [ -f "$root/queue/archive/reports/sasuke_cmd_test_report.yaml" ]
    # Canonical report remains.
    [ -f "$root/queue/reports/sasuke_report.yaml" ]

    rm -rf "$root"
}

@test "E2E-011-C: canonical report remains even if old and complete" {
    local root
    root="$(mktemp -d "/tmp/e2e_slim_retention_XXXXXX")"
    build_tmp_project "$root"
    cp "$PROJECT_ROOT/scripts/slim_yaml.py" "$root/scripts/"

    seed_yaml "$root/queue/shogun_to_karo.yaml" $'commands:\n  - id: cmd_test\n    status: done\n'
    seed_yaml "$root/queue/reports/sasuke_report.yaml" $'parent_cmd: cmd_done\nstatus: done\n'
    touch -d "2 days ago" "$root/queue/reports/sasuke_report.yaml"

    run run_slim_yaml "$root" karo
    [ "$status" -eq 0 ]

    # Canonical report is always retained.
    [ -f "$root/queue/reports/sasuke_report.yaml" ]

    rm -rf "$root"
}
