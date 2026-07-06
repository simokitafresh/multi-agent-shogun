#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export PRECHECK="$PROJECT_ROOT/scripts/gates/gate_gunshi_report_precheck.sh"
    [ -f "$PRECHECK" ] || return 1
}

@test "generated grid-search sqlite artifacts are skipped by precheck line/causal scans" {
    run bash -c '
        set -euo pipefail
        eval "$(sed -n "/^is_generated_large_artifact()/,/^}/p" "$1")"
        is_generated_large_artifact "outputs/grid_search/run/foo.db"
        is_generated_large_artifact "/mnt/c/Python_app/DM-signal/outputs/grid_search/foo.sqlite3"
        is_generated_large_artifact "outputs/grid_search/foo.db-wal"
    ' _ "$PRECHECK"
    [ "$status" -eq 0 ]
}

@test "ordinary source files are not treated as generated large artifacts" {
    run bash -c '
        set -euo pipefail
        eval "$(sed -n "/^is_generated_large_artifact()/,/^}/p" "$1")"
        ! is_generated_large_artifact "scripts/gates/gate_gunshi_report_precheck.sh"
        ! is_generated_large_artifact "context/dm-signal.md"
    ' _ "$PRECHECK"
    [ "$status" -eq 0 ]
}
