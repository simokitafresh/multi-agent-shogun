#!/usr/bin/env bats
# contract test: structured zero-tolerance contradiction must fail closed
# test_necessity: zero-tolerance AC=yesと構造化不一致件数>0の矛盾を必ずBLOCKし、散文では偽陽性にしない。
# origin: [[cmd_karo_hotfix_zero_tolerance_conflict_20260802]] -> [[構造化件数と二値判定の分離]] -> [[偽PASS防止]]

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    MAIN="$REPO_ROOT/scripts/gates/gate_report_format_main.py"
}

setup_file() {
    DUPLICATE_FIXTURE_TEMPLATE="$BATS_FILE_TMPDIR/reflux-duplicate-template"
    UNIQUE_FIXTURE_TEMPLATE="$BATS_FILE_TMPDIR/reflux-unique-template"
    export DUPLICATE_FIXTURE_TEMPLATE UNIQUE_FIXTURE_TEMPLATE

    for template in "$DUPLICATE_FIXTURE_TEMPLATE" "$UNIQUE_FIXTURE_TEMPLATE"; do
        mkdir -p "$template/queue/archive"
        printf 'insights: []\n' > "$template/queue/archive/insights_archive.yaml"
        git -C "$template" init -q
        git -C "$template" config user.email test@example.invalid
        git -C "$template" config user.name test
    done

    cat > "$UNIQUE_FIXTURE_TEMPLATE/queue/insights.yaml" <<'YAML'
insights:
- id: INS-20260804-142209841-2aaf
  source: self_retro
  status: resolved
  priority: high
  occurrence_count: 15
  last_seen: "2026-08-04T17:44:06+09:00"
YAML
    cp "$UNIQUE_FIXTURE_TEMPLATE/queue/insights.yaml" \
        "$DUPLICATE_FIXTURE_TEMPLATE/queue/insights.yaml"
    cat >> "$DUPLICATE_FIXTURE_TEMPLATE/queue/insights.yaml" <<'YAML'
- id: INS-20260804-142209841-2aaf
  source: self_retro
  status: resolved
  priority: high
  occurrence_count: 15
  last_seen: "2026-08-04T17:44:06+09:00"
YAML

    git -C "$UNIQUE_FIXTURE_TEMPLATE" add queue/insights.yaml
    git -C "$UNIQUE_FIXTURE_TEMPLATE" commit -qm baseline
    git -C "$DUPLICATE_FIXTURE_TEMPLATE" add queue/insights.yaml
    git -C "$DUPLICATE_FIXTURE_TEMPLATE" commit -qm baseline
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

# test_necessity: reconnaissance reports are read-only findings and must not
# inherit implementation commit contracts; implementation reports must retain
# the required commit identity checks.
# regression_justification: recon2 reports previously reached the shared gate
# with implementation-only commit/investigation requirements and caused repeat
# FAIL/revision rounds.
@test "recon task types require finding evidence and skip commit contract" {
    run python3 - "$MAIN" <<'PY'
import importlib.util
import pathlib
import sys

spec = importlib.util.spec_from_file_location("gate_main", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

finding = {
    "observation_target": "gate report validator",
    "result": "recon2 commit checks are not applicable",
    "evidence_path": "scripts/gates/gate_report_format_main.py",
}
recon_report = {
    "task_type": "recon2",
    "finding": finding,
    "commit_hash": "",
}
recon_task = {
    "task_type": "recon2",
    "commit_contract": {"required": True, "planned_paths": ["scripts"]},
}
assert module._is_recon_report(recon_report, recon_task)
assert module._recon_finding_contract_issues(recon_report) == []
assert module.commit_contract_errors(recon_report, recon_task, pathlib.Path(".")) == []
assert module._recon_finding_contract_issues(
    {"task_type": "scout", "finding": {"result": "known"}}
)

impl_report = {"task_type": "impl", "commit_hash": ""}
impl_task = {
    "task_type": "impl",
    "commit_contract": {"required": True, "planned_paths": ["scripts"]},
}
errors = module.commit_contract_errors(impl_report, impl_task, pathlib.Path("."))
assert "required commit_hash is missing or invalid" in errors, errors
print("recon2 finding PASS; recon commit checks skipped; impl commit contract BLOCK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"recon2 finding PASS; recon commit checks skipped; impl commit contract BLOCK"* ]]
}

# test_necessity: exercise the real gate main with a task/report fixture so the
# task-match boundary is covered, not only the individual helper functions.
@test "recon fixture passes on finding while implementation fixture requires commit" {
    run python3 - "$MAIN" <<'PY'
import importlib.util
import pathlib
import sys
import tempfile

spec = importlib.util.spec_from_file_location("gate_main", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def fixture(task_type, required, finding):
    root = pathlib.Path(tempfile.mkdtemp(prefix="gate-report-contract-"))
    (root / "queue/tasks").mkdir(parents=True)
    (root / "queue/reports").mkdir()
    (root / "queue/tasks/saizo.yaml").write_text(
        """task:
  parent_cmd: cmd_fixture
  task_type: %s
  commit_contract:
    required: %s
    task_type: %s
    planned_paths: []
  acceptance_criteria:
  - id: AC1
    checks:
    - check: finding
  related_lessons: []
""" % (task_type, str(required).lower(), task_type), encoding="utf-8")
    body = {
        "worker_id": "saizo",
        "task_id": "cmd_fixture_normal",
        "parent_cmd": "cmd_fixture",
        "task_type": task_type,
        "ac_version_read": "fixture123",
        "timestamp": "2026-08-27T03:12:00+09:00",
        "status": "completed",
        "result": {"summary": "fixture result"},
        "binary_checks": {
            "AC1": [{"check": "finding", "result": "yes"}],
            "commit": [{
                "check": (
                    "git commitが完了したか"
                    if required
                    else "commit N/A証跡とコード変更・stage/commitを実行していないことを確認"
                ),
                "result": "yes",
            }],
        },
        "files_modified": [],
        "lesson_candidate": {"found": False, "no_lesson_reason": "fixture only"},
        "lessons_useful": [],
        "purpose_validation": {"cmd_purpose": "fixture", "fit": True, "purpose_gap": ""},
        "assumption_invalidation": {"found": False, "affected_cmds": [], "detail": ""},
        "verdict": "PASS",
    }
    if finding:
        body["finding"] = {
            "observation_target": "gate",
            "result": "finding recorded",
            "evidence_path": "scripts/gates/gate_report_format_main.py",
        }
    import yaml
    report = root / "queue/reports/report.yaml"
    report.write_text(yaml.safe_dump(body, allow_unicode=True, sort_keys=False), encoding="utf-8")
    return report

recon = fixture("recon2", False, True)
sys.argv = [sys.argv[0], str(recon)]
recon_rc = module.main()
print(f"recon_rc={recon_rc}")
assert recon_rc == 0

impl = fixture("impl", True, False)
sys.argv = [sys.argv[0], str(impl)]
impl_rc = module.main()
print(f"impl_rc={impl_rc}")
assert impl_rc == 1
print("recon fixture PASS; implementation fixture commit contract FAIL")
PY
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"recon fixture PASS; implementation fixture commit contract FAIL"* ]]
}

# test_necessity: ci_fix clean-repro is a typed terminal checkpoint rather than
# a normal AC, so it must not create an intermediate binary check and must be
# validated exactly at the completed-report boundary.
@test "ci_fix final checkpoint validates report evidence without AC injection" {
    run python3 - "$MAIN" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gate_report_format_main", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
task = {
    "task_type": "ci_fix",
    "acceptance_criteria": [{"id": "AC1", "description": "existing contract"}],
    "final_checkpoint": {
        "type": "ci_fix_clean_repro",
        "required": True,
        "evidence_field": "ci_fix_clean_repro_evidence",
    },
}
assert len(task["acceptance_criteria"]) == 1
valid = {
    "e2_harness_command": "bash tests/e2_clean_ci.sh",
    "pre_fix_receipt": {"path": "pre.json", "status": "FAIL", "source_commit": "a" * 40,
                         "fixed_target": "tests/unit/x.bats#10", "started_at": "2026-07-20T01:00:00+09:00",
                         "failures": 1, "skips": 0},
    "post_fix_receipt": {"path": "post.json", "status": "PASS", "source_commit": "a" * 40,
                          "fixed_target": "tests/unit/x.bats#10", "started_at": "2026-07-20T01:10:00+09:00",
                          "failures": 0, "skips": 0},
    "push_started_at": "2026-07-20T01:20:00+09:00",
}
assert mod._ci_fix_final_checkpoint_issues(task, {"status": "completed", "ci_fix_clean_repro_evidence": valid}) == []
invalid = dict(valid)
invalid["post_fix_receipt"] = dict(valid["post_fix_receipt"], skips=1)
errors = mod._ci_fix_final_checkpoint_issues(task, {"status": "completed", "ci_fix_clean_repro_evidence": invalid})
assert any("post receipt must be PASS FAIL0 SKIP0" in error for error in errors), errors
assert mod._ci_fix_final_checkpoint_issues(task, {"status": "in_progress"}) == []
assert mod._ci_fix_final_checkpoint_issues({"task_type": "impl", "acceptance_criteria": []}, {"status": "completed"}) == []
print("checkpoint PASS; invalid evidence BLOCK; intermediate AC count=1")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"checkpoint PASS; invalid evidence BLOCK; intermediate AC count=1"* ]]
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
    local template="$UNIQUE_FIXTURE_TEMPLATE"
    if [[ "$mode" == "duplicate" || "$mode" == "archive" || "$mode" == "missing" || "$mode" == "field-change" || "$mode" == "duplicate-increase" ]]; then
        template="$DUPLICATE_FIXTURE_TEMPLATE"
    fi
    cp -a "$template" "$fixture"

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

run_duplicate_preimage_case() {
    local fixture="$1"
    local mode="$2"
    local output
    local rc
    make_duplicate_preimage_fixture "$fixture" "$mode"
    if output="$(GATE_NO_LOG=1 \
        env GATE_REPORT_FORMAT_REFLUX_CONTRACT_TEST=1 \
            GATE_REPO_ROOT_OVERRIDE="$fixture" \
            GATE_REFLUX_UNCOMMITTED_PATHS=' M queue/insights.yaml' \
            bash "$REPO_ROOT/scripts/gates/gate_report_format.sh" "$fixture/report.yaml" 2>&1)"; then
        rc=0
    else
        rc=$?
    fi
    printf '%s\n' "$rc" > "$fixture/.rc"
    printf '%s' "$output" > "$fixture/.output"
}

@test "reflux duplicate preimage six-case boundary is fail-closed" {
    local cases=(current archive missing field-change duplicate-increase unique)
    local expect_path=(0 0 1 1 1 0)
    local i fixture
    local -a pids=()
    for i in "${!cases[@]}"; do
        fixture="$BATS_TEST_TMPDIR/reflux-duplicate-${cases[$i]}"
        run_duplicate_preimage_case "$fixture" "${cases[$i]}" &
        local pid=$!
        pids+=("$pid")
    done
    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done
    for i in "${!cases[@]}"; do
        fixture="$BATS_TEST_TMPDIR/reflux-duplicate-${cases[$i]}"
        [ "$(<"$fixture/.rc")" -eq 0 ]
        output="$(<"$fixture/.output")"
        if [ "${expect_path[$i]}" -eq 1 ]; then
            [[ "$output" == *"queue/insights.yaml"* ]]
        else
            [[ "$output" != *"queue/insights.yaml"* ]]
        fi
    done
}
