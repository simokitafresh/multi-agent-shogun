#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TEST_DIR="${TEST_DIR:-$REPO_ROOT/tests/unit}"

for changed in "$@"; do
    case "$changed" in
        scripts/gates/gate_report_format_main.py|scripts/gates/gate_report_format_combined.py|scripts/deploy_task.sh)
            grep -rl 'gate_report_format' "$TEST_DIR"/test_*.bats 2>/dev/null || true
            if [[ "$changed" == scripts/gates/* ]]; then
                for tf in "$TEST_DIR"/test_gate*.bats; do
                    [ -f "$tf" ] && printf '%s\n' "$tf"
                done
            fi
            if [[ "$changed" == scripts/deploy_task.sh ]]; then
                for tf in "$TEST_DIR"/test_deploy_task*.bats; do
                    [ -f "$tf" ] && printf '%s\n' "$tf"
                done
            fi
            ;;
    esac
done | sort -u
