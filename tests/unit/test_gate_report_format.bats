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

# test_necessity: shared self-retro metadata may arrive after a reflux commit
# on the same YAML hunk, but a worker status edit must remain observable as
# uncommitted.  This is the exact false-positive/true-positive boundary from
# cmd_karo_hotfix_reflux_shared_dirty_commit_contract_20260804.
# regression_justification: queue/insights.yaml is a bounded shared producer
# queue; leaving this contract untested reopens the Kotaro 4+ FAIL loop.
@test "reflux shared producer same-hunk metadata is suppressed but worker edit is retained" {
    local fixture="$BATS_TEST_TMPDIR/reflux-gate"
    mkdir -p "$fixture/queue/archive"
    cat > "$fixture/queue/insights.yaml" <<'YAML'
insights:
- id: INS-20260804-142000313-9813
  source: self_retro
  status: pending
  occurrence_count: 1
  last_seen: "2026-08-04T15:00:00+09:00"
YAML
    printf 'insights: []\n' > "$fixture/queue/archive/insights_archive.yaml"
    git -C "$fixture" init -q
    git -C "$fixture" config user.email test@example.invalid
    git -C "$fixture" config user.name test
    git -C "$fixture" add queue/insights.yaml
    git -C "$fixture" commit -qm baseline
    sed -i 's/status: pending/status: resolved/; s/occurrence_count: 1/occurrence_count: 2/; s/15:00:00/15:52:52/' "$fixture/queue/insights.yaml"
    git -C "$fixture" add queue/insights.yaml
    git -C "$fixture" commit -qm reflux_worker_commit
    local commit_hash
    commit_hash="$(git -C "$fixture" rev-parse HEAD)"
    sed -i 's/occurrence_count: 2/occurrence_count: 3/; s/15:52:52/16:05:44/' "$fixture/queue/insights.yaml"
    cat > "$fixture/report.yaml" <<YAML
worker_id: kotaro
commit_hash: $commit_hash
task_contract_snapshot:
  acceptance_criteria:
  - id: AC1
    checks:
    - check: "INS-20260804-142000313-9813"
  parent_cmd: cmd_reflux_insight_fixture
  task_id: cmd_reflux_insight_fixture_exact
YAML
    run env GATE_REPORT_FORMAT_REFLUX_CONTRACT_TEST=1 \
        GATE_REPO_ROOT_OVERRIDE="$fixture" \
        GATE_REFLUX_UNCOMMITTED_PATHS=' M queue/insights.yaml' \
        bash "$REPO_ROOT/scripts/gates/gate_report_format.sh" "$fixture/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" != *$'\n M queue/insights.yaml'* ]]

    sed -i 's/status: resolved/status: pending/' "$fixture/queue/insights.yaml"
    run env GATE_REPORT_FORMAT_REFLUX_CONTRACT_TEST=1 \
        GATE_REPO_ROOT_OVERRIDE="$fixture" \
        GATE_REFLUX_UNCOMMITTED_PATHS=' M queue/insights.yaml' \
        bash "$REPO_ROOT/scripts/gates/gate_report_format.sh" "$fixture/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"queue/insights.yaml"* ]]
}
