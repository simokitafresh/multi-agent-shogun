#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TEST_DIR="${TEST_DIR:-$REPO_ROOT/tests/unit}"

report_contract_tests() {
    local tf
    for tf in \
        "$TEST_DIR/test_affected_tests_report_contract.bats" \
        "$TEST_DIR/test_gate_report_autofix.bats" \
        "$TEST_DIR/test_gate_report_format_cmd_3558.bats" \
        "$TEST_DIR/test_gate_report_format_cmd_3630_env_info.bats" \
        "$TEST_DIR/test_gate_report_format_lu_warn.bats" \
        "$TEST_DIR/test_gate_report_format_pass_no_improvement.bats" \
        "$TEST_DIR/test_gate_report_revision_terminal.bats" \
        "$TEST_DIR/test_report_template_gate_compat.bats"; do
        [ -f "$tf" ] && printf '%s\n' "$tf"
    done
}

for changed in "$@"; do
    case "$changed" in
        scripts/gates/gate_report_format_main.py|scripts/gates/gate_report_format_combined.py|scripts/deploy_task.sh)
            report_contract_tests
            if [[ "$changed" == scripts/deploy_task.sh ]]; then
                for tf in "$TEST_DIR"/test_deploy_task*.bats; do
                    [ -f "$tf" ] && printf '%s\n' "$tf"
                done
            fi
            ;;
    esac
done | sort -u
