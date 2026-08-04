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

# test_necessity: the report gate must distinguish a legitimate duplicate
# insight eviction from data loss while preserving the existing unique-ID
# contract.  This is the focused six-case regression contract for
# cmd_karo_fix_reflux_duplicate_preimage_gate_20260804.
# regression_justification: commit 52f29f2c6 removed one of two identical
# insight entries; rejecting the duplicate preimage blocks valid reflux
# reports, while accepting an unverified disappearance can hide data loss.
make_duplicate_preimage_fixture() {
    local fixture="$1"
    local mode="$2"
    local insight_id="INS-20260804-142209841-2aaf"
    mkdir -p "$fixture/queue/archive"
    cat > "$fixture/queue/insights.yaml" <<YAML
insights:
- id: $insight_id
  source: self_retro
  status: resolved
  priority: high
  occurrence_count: 15
  last_seen: "2026-08-04T17:44:06+09:00"
YAML
    if [[ "$mode" == "duplicate" || "$mode" == "archive" || "$mode" == "missing" || "$mode" == "field-change" || "$mode" == "duplicate-increase" ]]; then
        cat >> "$fixture/queue/insights.yaml" <<YAML
- id: $insight_id
  source: self_retro
  status: resolved
  priority: high
  occurrence_count: 15
  last_seen: "2026-08-04T17:44:06+09:00"
YAML
    fi
    printf 'insights: []\n' > "$fixture/queue/archive/insights_archive.yaml"
    git -C "$fixture" init -q
    git -C "$fixture" config user.email test@example.invalid
    git -C "$fixture" config user.name test
    git -C "$fixture" add queue/insights.yaml
    git -C "$fixture" commit -qm baseline

    if [[ "$mode" == "duplicate-increase" ]]; then
        cat >> "$fixture/queue/insights.yaml" <<YAML
- id: $insight_id
  source: self_retro
  status: resolved
  priority: high
  occurrence_count: 15
  last_seen: "2026-08-04T17:44:06+09:00"
YAML
    else
        if [[ "$mode" == "duplicate" || "$mode" == "archive" || "$mode" == "missing" || "$mode" == "field-change" ]]; then
            awk 'BEGIN {records=0} /^- id:/{records++} records <= 1 {print}' \
                "$fixture/queue/insights.yaml" > "$fixture/queue/insights.yaml.trim"
            mv "$fixture/queue/insights.yaml.trim" "$fixture/queue/insights.yaml"
        fi
        sed -i 's/status: resolved/status: archived/; s/occurrence_count: 15/occurrence_count: 16/; s/17:44:06/18:31:00/' "$fixture/queue/insights.yaml"
    fi
    git -C "$fixture" add queue/insights.yaml
    git -C "$fixture" commit -qm reflux_duplicate_preimage
    local commit_hash
    commit_hash="$(git -C "$fixture" rev-parse HEAD)"

    case "$mode" in
        current|unique)
            cp "$fixture/queue/insights.yaml" "$fixture/queue/insights.yaml.current"
            mv "$fixture/queue/insights.yaml.current" "$fixture/queue/insights.yaml"
            ;;
        archive)
            printf 'insights: []\n' > "$fixture/queue/insights.yaml"
            cp "$fixture/queue/insights.yaml" "$fixture/queue/archive/insights_archive.yaml"
            git -C "$fixture" show "$commit_hash:queue/insights.yaml" > "$fixture/queue/archive/insights_archive.yaml"
            ;;
        missing)
            printf 'insights: []\n' > "$fixture/queue/insights.yaml"
            ;;
        field-change)
            sed -i 's/status: archived/status: archived/; s/priority: high/priority: low/' "$fixture/queue/insights.yaml"
            ;;
        duplicate-increase)
            :
            ;;
    esac
    cat > "$fixture/report.yaml" <<YAML
worker_id: saizo
commit_hash: $commit_hash
task_contract_snapshot:
  acceptance_criteria:
  - id: AC1
    checks:
    - check: "$insight_id"
  parent_cmd: cmd_karo_fix_reflux_duplicate_preimage_gate_20260804
  task_id: cmd_karo_fix_reflux_duplicate_preimage_gate_20260804_normal
YAML
}

@test "reflux duplicate preimage six-case boundary is fail-closed" {
    local cases=(current archive missing field-change duplicate-increase unique)
    local expect_path=(0 0 1 1 1 0)
    local i fixture
    for i in "${!cases[@]}"; do
        fixture="$BATS_TEST_TMPDIR/reflux-duplicate-${cases[$i]}"
        make_duplicate_preimage_fixture "$fixture" "${cases[$i]}"
        run env GATE_REPORT_FORMAT_REFLUX_CONTRACT_TEST=1 \
            GATE_REPO_ROOT_OVERRIDE="$fixture" \
            GATE_REFLUX_UNCOMMITTED_PATHS=' M queue/insights.yaml' \
            bash "$REPO_ROOT/scripts/gates/gate_report_format.sh" "$fixture/report.yaml"
        if [ "${expect_path[$i]}" -eq 1 ]; then
            [[ "$output" == *"queue/insights.yaml"* ]]
        else
            [[ "$output" != *"queue/insights.yaml"* ]]
        fi
    done
}
