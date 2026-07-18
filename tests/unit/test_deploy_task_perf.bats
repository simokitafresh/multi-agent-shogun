#!/usr/bin/env bats

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

@test "task mutation profiling records bounded report scans" {
    run python3 - "$PROJECT_ROOT/scripts/deploy_task.sh" <<'PY'
import pathlib, re, sys
s = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
assert "TASK_MUTATION_PHASE phase=${phase}" in s
assert "TASK_MUTATION_SUMMARY report_scans=" in s
assert re.search(r"DEPLOY_TASK_REPORT_SCAN_COUNT=.*#_report_scan_files", s)
PY
    [ "$status" -eq 0 ]
}

@test "deadline receipt contract distinguishes success and timeout" {
    run python3 - "$PROJECT_ROOT/scripts/deploy_task.sh" <<'PY'
import pathlib, sys
s = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
assert "return 124" in s
assert "DEPLOY_RECEIPT" in s
assert "deploy_task_exit_nudge" in s
PY
    [ "$status" -eq 0 ]
}

@test "active report pointer removes repeated all-report glob from hot path" {
    run python3 - "$PROJECT_ROOT/scripts/deploy_task.sh" <<'PY'
import pathlib, sys
s = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
assert '.deploy_active_${ninja_name}' in s
assert 'One-time migration' in s
assert 'printf \'%s\\n\' "$report_rel_path"' in s
PY
    [ "$status" -eq 0 ]
}
