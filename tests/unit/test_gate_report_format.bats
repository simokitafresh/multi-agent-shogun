#!/usr/bin/env bats
# contract test: structured zero-tolerance contradiction must fail closed
# test_necessity: zero-tolerance AC=yesと構造化不一致件数>0の矛盾を必ずBLOCKし、散文では偽陽性にしない。
# origin: [[cmd_karo_hotfix_zero_tolerance_conflict_20260802]] -> [[構造化件数と二値判定の分離]] -> [[偽PASS防止]]

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    MAIN="$REPO_ROOT/scripts/gates/gate_report_format_main.py"
}

run_detector() {
    run python3 - "$MAIN" "$1" "$2" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gate_report_format_main", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
task = {"acceptance_criteria": [{"id": "AC1", "description": sys.argv[3]}]}
report = {"result": {"details": {"mismatch_count": int(sys.argv[2])}},
          "binary_checks": {"AC1": [{"check": "parity", "result": "yes"}]}}
print(mod._zero_tolerance_conflict_errors(report, task))
PY
}

@test "positive structured mismatch with zero-tolerance yes is blocked" {
    run_detector 1 "許容誤差はゼロ"
    [ "$status" -eq 0 ]
    [[ "$output" == *"zero-tolerance contradiction"* ]]
}

@test "zero mismatch passes and non-zero-tolerance report is unaffected" {
    run_detector 0 "許容誤差はゼロ"
    [ "$output" = "[]" ]
    run_detector 3 "差異を参考値として報告する"
    [ "$output" = "[]" ]
}

@test "free-form prose is not scanned as a structured count" {
    run python3 - "$MAIN" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gate_report_format_main", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
task = {"acceptance_criteria": [{"id": "AC1", "description": "zero-tolerance parity"}]}
report = {"result": {"details": "mismatch_count=9"},
          "binary_checks": {"AC1": [{"check": "parity", "result": "yes"}]}}
print(mod._zero_tolerance_conflict_errors(report, task))
PY
    [ "$output" = "[]" ]
}
