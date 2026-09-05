#!/usr/bin/env bats
# test_necessity: the public single-review command must preserve the existing
# batch transaction order: precheck, bundle, rich ledger, approval, one notify.

# test_necessity: canonical LGTM notification is the durable post-approval
# boundary.  Keeping it before report-resolution/manifest work prevents a
# caller timeout from dropping the Karo wake-up after the approval was saved.
# regression_justification: cmd_4378 (2026-08-23) observed 4/4 review_bundle
# invocations hitting rc=124 at 30s and 3/4 LGTM notifications missing.
@test "canonical LGTM publishes before post-approval report resolution" {
  script="$BATS_TEST_DIRNAME/../../scripts/review_approval.sh"
  notify_line=$(grep -n 'python3 .*review_bundle.py.* notify' "$script" | head -1 | cut -d: -f1)
  reports_line=$(grep -n '^mapfile -t reports' "$script" | head -1 | cut -d: -f1)
  [ -n "$notify_line" ]
  [ -n "$reports_line" ]
  [ "$notify_line" -lt "$reports_line" ]
}

@test "single APPROVE completes the review transaction once in canonical order" {
  root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root/scripts/gates" "$root/scripts/lib" "$root/queue/reports" \
    "$root/queue/tasks" "$root/queue/gates" "$root/logs"
  ln -s "$BATS_TEST_DIRNAME/../../scripts/review_bundle.py" "$root/scripts/review_bundle.py"
  cat >"$root/scripts/gates/gate_gunshi_report_precheck.sh" <<'SH'
#!/bin/sh
echo precheck >>"$TEST_CALLS"
SH
  cat >"$root/scripts/gunshi_log_append.sh" <<'SH'
#!/bin/sh
test -s "$TEST_ROOT/queue/gates/cmd_one/sg7_bundle.json"
echo ledger >>"$TEST_CALLS"
cat >"$TEST_ROOT/logs/gunshi_review_log.yaml"
SH
  cat >"$root/scripts/review_approval.sh" <<'SH'
#!/bin/sh
test "$REVIEW_APPROVAL_CANONICAL_ENTRY" = review_bundle
grep -q 'cmd_id: cmd_one' "$TEST_ROOT/logs/gunshi_review_log.yaml"
printf '%s\n' "$@" >"$TEST_ROOT/approval.args"
echo approval >>"$TEST_CALLS"
SH
  cat >"$root/scripts/lib/review_approval.sh" <<'SH'
review_two_phase_ready_gunshi() { echo notify >>"$TEST_CALLS"; return 0; }
SH
  cat >"$root/scripts/inbox_write.sh" <<'SH'
#!/bin/sh
echo inbox >>"$TEST_CALLS"
SH
  chmod +x "$root/scripts/gates/gate_gunshi_report_precheck.sh" \
    "$root/scripts/gunshi_log_append.sh" "$root/scripts/review_approval.sh" "$root/scripts/inbox_write.sh"
  cat >"$root/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_one:
    acceptance_criteria: [one]
    target_path: scripts/review_bundle.py
    project: infra
YAML
  cat >"$root/queue/reports/worker_report_cmd_one.yaml" <<'YAML'
parent_cmd: cmd_one
report_id: rpt-one
status: completed
verdict: PASS
binary_checks: {AC1: [{result: yes}]}
result: {summary: measured pass}
YAML
  cat >"$root/queue/tasks/worker.yaml" <<'YAML'
task: {parent_cmd: cmd_one, report_filename: worker_report_cmd_one.yaml}
YAML
  cat >"$root/review-entry.yaml" <<'YAML'
cmd_id: cmd_one
review_type: report
verdict: LGTM
observations: [measured]
brainwash_check: numeric evidence 1/1
verified_files: [scripts/review_bundle.py]
operational_simulation: {result: PASS}
YAML
  export TEST_ROOT="$root" TEST_CALLS="$root/calls"

  run env -u REVIEW_APPROVAL_CANONICAL_ENTRY -u REVIEW_APPROVAL_SKIP_LEDGER_CHECK \
    python3 "$root/scripts/review_bundle.py" --root "$root" single \
    --cmd cmd_one --verdict APPROVE --report queue/reports/worker_report_cmd_one.yaml \
    --review-entry "$root/review-entry.yaml"
  echo "$output" >&3
  [ "$status" -eq 0 ]
  [ "$(grep -c '^precheck$' "$TEST_CALLS")" -eq 1 ]
  [ "$(grep -c '^ledger$' "$TEST_CALLS")" -eq 1 ]
  [ "$(grep -c '^approval$' "$TEST_CALLS")" -eq 1 ]
  [ "$(grep -c '^inbox$' "$TEST_CALLS")" -eq 1 ]
  [ "$(tr '\n' ' ' <"$TEST_CALLS")" = "precheck ledger approval notify inbox " ]
  [ "$(wc -l <"$root/approval.args")" -eq 4 ]
}

@test "single report correction scope reaches canonical approval and stays typed" {
  root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root/scripts/gates" "$root/scripts/lib" "$root/queue/reports" \
    "$root/queue/tasks" "$root/queue/gates" "$root/logs"
  ln -s "$BATS_TEST_DIRNAME/../../scripts/review_bundle.py" "$root/scripts/review_bundle.py"
  cat >"$root/scripts/gates/gate_gunshi_report_precheck.sh" <<'SH'
#!/bin/sh
exit 0
SH
  cat >"$root/scripts/gunshi_log_append.sh" <<'SH'
#!/bin/sh
cat >"$TEST_ROOT/logs/gunshi_review_log.yaml"
SH
  cat >"$root/scripts/review_approval.sh" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >"$TEST_ROOT/approval.args"
test "$REVIEW_APPROVAL_CANONICAL_ENTRY" = review_bundle
SH
  cat >"$root/scripts/lib/review_approval.sh" <<'SH'
review_two_phase_ready_gunshi() { return 0; }
SH
  cat >"$root/scripts/inbox_write.sh" <<'SH'
#!/bin/sh
exit 0
SH
  chmod +x "$root/scripts/gates/gate_gunshi_report_precheck.sh" \
    "$root/scripts/gunshi_log_append.sh" "$root/scripts/review_approval.sh" \
    "$root/scripts/inbox_write.sh"
  cat >"$root/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_report_scope:
    acceptance_criteria: [one]
    target_path: scripts/review_bundle.py
    project: infra
YAML
  cat >"$root/queue/reports/worker_report_cmd_report_scope.yaml" <<'YAML'
parent_cmd: cmd_report_scope
report_id: rpt-report-scope
status: completed
verdict: PASS
binary_checks: {AC1: [{result: yes}]}
result: {summary: measured pass}
YAML
  cat >"$root/queue/tasks/worker.yaml" <<'YAML'
task: {parent_cmd: cmd_report_scope, report_filename: worker_report_cmd_report_scope.yaml}
YAML
  cat >"$root/review-entry.yaml" <<'YAML'
cmd_id: cmd_report_scope
review_type: report
YAML

  run env TEST_ROOT="$root" python3 "$root/scripts/review_bundle.py" --root "$root" single \
    --cmd cmd_report_scope --verdict APPROVE \
    --report queue/reports/worker_report_cmd_report_scope.yaml \
    --review-entry "$root/review-entry.yaml" --correction-scope report
  [ "$status" -eq 0 ]
  [ "$(sed -n '5p' "$root/approval.args")" = report ]
  [ "$(wc -l <"$root/approval.args")" -eq 5 ]

  run python3 "$root/scripts/review_bundle.py" --root "$root" single \
    --cmd cmd_report_scope --verdict APPROVE \
    --report queue/reports/worker_report_cmd_report_scope.yaml \
    --review-entry "$root/review-entry.yaml" --correction-scope invalid
  [ "$status" -ne 0 ]
}

@test "single accepts one matching mapping from a sequence and rejects ambiguity" {
  root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root/queue/gates"
  cat >"$root/entries.yaml" <<'YAML'
- {cmd_id: other, verdict: LGTM}
- {cmd_id: cmd_one, verdict: LGTM, observations: [measured], reviewed_at: 2026-08-09 17:00:00}
YAML
  run python3 - "$root" <<'PY'
import argparse, sys
from pathlib import Path
sys.path.insert(0, str(Path.cwd()))
from scripts import review_bundle
root = Path(sys.argv[1])
captured = {}
review_bundle.batch = lambda args: captured.update(review_bundle.load(args.manifest)) or 0
args = argparse.Namespace(root=str(root), cmd='cmd_one', report='r.yaml', verdict='APPROVE', review_entry=str(root/'entries.yaml'), fail_reason=None)
assert review_bundle.single(args) == 0
assert captured['reviews'][0]['review_entry']['cmd_id'] == 'cmd_one'
PY
  [ "$status" -eq 0 ]
  printf '%s\n' '- {cmd_id: cmd_one}' '- {cmd_id: cmd_one}' >"$root/entries.yaml"
  run python3 - "$root" <<'PY'
import argparse, sys
from pathlib import Path
sys.path.insert(0, str(Path.cwd()))
from scripts import review_bundle
root = Path(sys.argv[1])
args = argparse.Namespace(root=str(root), cmd='cmd_one', report='r.yaml', verdict='APPROVE', review_entry=str(root/'entries.yaml'), fail_reason=None)
review_bundle.single(args)
PY
  [ "$status" -ne 0 ]
}

# test_necessity: every canonical single review ledger entry must carry the
# requested cmd_id even when the supplied mapping omitted it.
# regression_justification: the production path previously forwarded 3/3
# mapping fixtures without cmd_id, making review state attribution ambiguous.
@test "single binds missing mapping cmd_id and blocks mismatches before persistence" {
  root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root/queue/gates"
  for i in 0 1 2; do
    cat >"$root/entry-$i.yaml" <<YAML
review_type: report
verdict: LGTM
reviewed_at: 2026-08-29T15:00:0${i}+09:00
YAML
  done
  run python3 - "$root" <<'PY'
import argparse
import sys
from pathlib import Path
from scripts import review_bundle

root = Path(sys.argv[1])
captured = []
old_batch = review_bundle.batch
try:
    def fake_batch(args):
        captured.append(review_bundle.load(args.manifest)["reviews"][0]["review_entry"])
        return 0
    review_bundle.batch = fake_batch
    for i in range(3):
        args = argparse.Namespace(
            root=str(root), cmd=f"cmd_fixture_{i}", report="missing.yaml",
            verdict="APPROVE", review_entry=str(root / f"entry-{i}.yaml"),
            fail_reason=None,
        )
        assert review_bundle.single(args) == 0
finally:
    review_bundle.batch = old_batch

assert len(captured) == 3
assert [entry["cmd_id"] for entry in captured] == [
    "cmd_fixture_0", "cmd_fixture_1", "cmd_fixture_2"
]
assert [entry["reviewed_at"] for entry in captured] == [
    "2026-08-29T15:00:00+09:00",
    "2026-08-29T15:00:01+09:00",
    "2026-08-29T15:00:02+09:00",
]

mismatch = root / "mismatch.yaml"
mismatch.write_text("cmd_id: cmd_other\nreview_type: report\n", encoding="utf-8")
args = argparse.Namespace(
    root=str(root), cmd="cmd_expected", report="missing.yaml",
    verdict="APPROVE", review_entry=str(mismatch), fail_reason=None,
)
before = len(captured)
try:
    review_bundle.single(args)
except ValueError as exc:
    assert "cmd_id mismatch" in str(exc)
else:
    raise AssertionError("mismatched mapping cmd_id must be rejected")
assert len(captured) == before, "mismatch must block before batch persistence"
PY
  [ "$status" -eq 0 ]
}

# test_necessity: SG7 honest-fail approval must name exactly the report's
# binary no paths; omitting an AC or naming an unrelated AC remains rejected.
# regression_justification: a no-count-only override could authorize an
# unreviewed failed check from another AC.
@test "honest FAIL producer binds approved failed check paths exactly" {
  run python3 - <<'PY'
from scripts import review_bundle

report = {
    "status": "failed",
    "verdict": "FAIL",
    "binary_checks": {
        "AC1": [{"check": "baseline", "result": "yes"}],
        "AC2": [{"check": "approved failure", "result": "no"}],
        "AC3": [{"check": "second failure", "result": False}],
    },
}
good = {"review_entry": {
    "review_type": "report",
    "verdict": "LGTM",
    "report_verdict": "FAIL",
    "approved_failed_check_paths": ["binary_checks.AC2[0]", "binary_checks.AC3[0]"],
}}
bad_missing = {"review_entry": {
    **good["review_entry"],
    "approved_failed_check_paths": ["binary_checks.AC2[0]"],
}}
bad_extra = {"review_entry": {
    **good["review_entry"],
    "approved_failed_check_paths": ["binary_checks.AC2[0]", "binary_checks.AC3[0]", "binary_checks.AC9[0]"],
}}
assert review_bundle._is_honest_fail_review(good, report)
assert not review_bundle._is_honest_fail_review(bad_missing, report)
assert not review_bundle._is_honest_fail_review(bad_extra, report)
assert review_bundle._approved_failed_check_paths(good["review_entry"]) == ["binary_checks.AC2[0]", "binary_checks.AC3[0]"]
print("approved=2 actual_no=2 missing=reject extra=reject")
PY
  [ "$status" -eq 0 ]
  [ "$output" = "approved=2 actual_no=2 missing=reject extra=reject" ]
}

# test_necessity: T106 review entries with valid N/A precheck evidence must
# reach the batch precheck unchanged; malformed values must remain fail-closed.
# regression_justification: the single path previously omitted precheck_na,
# turning a valid N/A review into an unnecessary report precheck execution.
@test "single propagates mapping precheck_na and preserves batch validation" {
  run python3 - <<'PY'
import argparse
import tempfile
from pathlib import Path
from scripts import review_bundle

def args(root, entry):
    return argparse.Namespace(root=str(root), cmd="cmd_na", report="r.yaml",
                              verdict="APPROVE", review_entry=str(entry),
                              fail_reason=None)

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    valid_entry = root / "valid.yaml"
    valid_entry.write_text(
        "cmd_id: cmd_na\n"
        "precheck_na: {reason: not applicable, evidence: T106 fixture}\n",
        encoding="utf-8",
    )
    captured = {}
    old_batch = review_bundle.batch
    review_bundle.batch = lambda call: captured.update(review_bundle.load(call.manifest)) or 0
    try:
        assert review_bundle.single(args(root, valid_entry)) == 0
    finally:
        review_bundle.batch = old_batch
    item = captured["reviews"][0]
    assert item["precheck_na"] == {
        "reason": "not applicable", "evidence": "T106 fixture"
    }

    invalid_entry = root / "invalid.yaml"
    invalid_entry.write_text(
        "cmd_id: cmd_na\nprecheck_na: [wrong]\n", encoding="utf-8"
    )
    try:
        review_bundle.single(args(root, invalid_entry))
    except ValueError as exc:
        assert "precheck_na must be a mapping" in str(exc)
    else:
        raise AssertionError("non-mapping precheck_na must be rejected")

    calls = []
    old_run = review_bundle.subprocess.run
    try:
        review_bundle.subprocess.run = lambda *call, **kwargs: calls.append(call) or type(
            "Proc", (), {"stdout": "PASS\n", "returncode": 0}
        )()
        assert review_bundle._batch_precheck(
            root, {"cmd": "cmd_na", "report": "r.yaml", "verdict": "APPROVE"}
        )["status"] == "PASS"
    finally:
        review_bundle.subprocess.run = old_run
    assert len(calls) == 1, calls

    assert review_bundle._batch_precheck(
        root,
        {"cmd": "cmd_na", "report": "r.yaml", "verdict": "APPROVE",
         "precheck_na": {"reason": "not applicable", "evidence": "T106 fixture"}},
    )["status"] == "N/A"
PY
  [ "$status" -eq 0 ]
}

@test "direct Gunshi LGTM is structurally rejected before report processing" {
  run bash "$BATS_TEST_DIRNAME/../../scripts/review_approval.sh" cmd_direct gunshi LGTM nowhere.yaml
  [ "$status" -eq 2 ]
  [[ "$output" == *"direct Gunshi LGTM is not a normal entry point"* ]]
  [[ "$output" == *"review_bundle.py single"* ]]
}

@test "single keeps warning-only precheck non-blocking but rejects real errors" {
  run python3 - <<'PY'
import argparse
from pathlib import Path
from types import SimpleNamespace
from scripts import review_bundle

class Proc:
    def __init__(self, output, rc):
        self.stdout = output
        self.returncode = rc

item = {"cmd": "cmd_warning", "report": "report.yaml", "verdict": "APPROVE"}
old_run = review_bundle.subprocess.run
try:
    review_bundle.subprocess.run = lambda *args, **kwargs: Proc(
        "WARN: advisory only\n=== 総合: ERRORS=0 ===\n", 1
    )
    result = review_bundle._batch_precheck(Path("."), item)
    assert result["status"] == "WARN", result

    review_bundle.subprocess.run = lambda *args, **kwargs: Proc(
        "ERROR: report defect\n=== 総合: ERRORS=1 ===\n", 1
    )
    try:
        review_bundle._batch_precheck(Path("."), item)
    except ValueError as exc:
        assert "precheck failed cmd=cmd_warning" in str(exc)
    else:
        raise AssertionError("positive ERRORS must remain blocked")
finally:
    review_bundle.subprocess.run = old_run
PY
  [ "$status" -eq 0 ]
}

@test "snapshot identity permits terminal-idle report reuse but stays fail-closed" {
  run python3 - <<'PY'
import tempfile
from pathlib import Path
import yaml
from scripts import review_bundle

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    (root / "queue/tasks").mkdir(parents=True)
    snapshot = {
        "task_id": "cmd_old_normal", "parent_cmd": "cmd_old",
        "issued_cmd_id": "cmd_old", "ac_fingerprint": "v1",
        "purpose": "old purpose", "acceptance_criteria": [{"id": "AC1"}],
        "project": "infra", "report_id": "rpt-old",
        "report_identity_version": 2, "report_fingerprint": "fp-old",
    }
    report = {
        "worker_id": "kotaro", "task_id": "cmd_old_normal",
        "ac_version_read": "v1", "report_id": "rpt-old",
        "report_identity_version": 2, "report_fingerprint": "fp-old",
        "task_contract_snapshot": snapshot,
    }
    task_path = root / "queue/tasks/kotaro.yaml"
    task_path.write_text(yaml.safe_dump({"task": {
        "task_id": "cmd_old_normal", "parent_cmd": "cmd_old",
        "ac_version": "v1", "report_id": "rpt-old",
    }}), encoding="utf-8")
    review_bundle._snapshot_command(root, report, "cmd_old")

    mismatch = dict(report, report_id="rpt-other")
    try:
        review_bundle._snapshot_command(root, mismatch, "cmd_old")
    except ValueError as exc:
        assert "identity mismatch" in str(exc)
    else:
        raise AssertionError("same-generation report identity mismatch must block")

    task_path.write_text(yaml.safe_dump({"task": {
        "task_id": "cmd_new_normal", "parent_cmd": "cmd_new",
        "ac_version": "v2", "report_id": "rpt-new",
    }}), encoding="utf-8")
    review_bundle._snapshot_command(root, report, "cmd_old")

    tampered = dict(report, task_contract_snapshot=dict(snapshot, report_fingerprint="fp-tampered"))
    try:
        review_bundle._snapshot_command(root, tampered, "cmd_old")
    except ValueError as exc:
        assert "report-generation identity" in str(exc)
    else:
        raise AssertionError("tampered immutable snapshot must block")
PY
  [ "$status" -eq 0 ]
}

# test_necessity: INS-20260905-135853 — gate_gunshi_report_precheck.sh's SG-PRE28
# (LG044/ac_evidence_mapping) used to leave the shell ERRORS counter at 0 even
# though the engine had already fixed GATE_PREDICTION=BLOCK for the same
# condition. A direct terminal run then showed "ERRORS=0" while exiting 1, and
# review_bundle.py's _batch_precheck (which trusts an "ERRORS=0" match in the
# evidence text to downgrade a nonzero exit to an advisory WARN) silently let a
# real honest-report/AC-evidence gap through review. Both invocation paths must
# reach the identical verdict for the identical fixture.
setup_gunshi_precheck_parity_fixture() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  GATE="$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck.sh"
  FIX_DIR="$BATS_TEST_TMPDIR/parity_fixture"
  mkdir -p "$FIX_DIR/tasks"
  cat > "$FIX_DIR/tasks/kagemaru.yaml" <<'YAML'
task:
  binary_checks:
    AC1:
      - check: concrete check
        result: yes
YAML
  cat > "$FIX_DIR/report.yaml" <<'YAML'
worker_id: kagemaru
parent_cmd: cmd_parity_fixture
status: completed
timestamp: "2026-09-05T00:00:00"
origin: "[[cmd_parity_fixture]] -> [[fixture_cause]] -> [[fixture_result]]"
assumption_check: "未確認前提なし"
ac_version_read: fixture
task_clarity:
  score: 100
  unclear_points: なし
  discretion_fills: なし
result:
  summary: "fixture summary"
files_modified:
  - path: scripts/report_field_set.sh
    change: fixture change
purpose_validation:
  cmd_purpose: fixture
  fit: true
  purpose_gap: ""
lesson_candidate:
  found: false
  no_lesson_reason: fixture
lessons_useful: []
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
decision_candidate:
  found: true
  title: fixture decision (honest_report_flag trigger)
  detail: fixture detail needing lord judgement
ac_evidence_mapping:
  AC1: ""
binary_checks:
  AC1:
    - check: concrete check
      result: yes
operational_simulation:
  command: "bash scripts/gates/gate_gunshi_report_precheck.sh fixture"
  expected: "exit 0/1"
  actual: "exit 1"
  result: PASS
verdict: PASS
YAML
  export GUNSHI_PRECHECK_TASKS_DIR="$FIX_DIR/tasks"
  export GATE_NO_LOG=1
}

@test "direct shell ERRORS count matches its own BLOCK exit for ac_evidence_mapping gap" {
  setup_gunshi_precheck_parity_fixture
  export GUNSHI_PRECHECK_CACHE_DIR="$FIX_DIR/cache_direct"
  run bash "$GATE" "$FIX_DIR/report.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GATE_PREDICTION=BLOCK"* ]]
  [[ "$output" == *"正直報告あり×AC evidence mapping欠落(LG044)"* ]]
  # The historical bug: ERRORS stayed 0 while GATE_PREDICTION was already BLOCK.
  # A fail-closed gate must count this condition, not just narrate it.
  [[ "$output" == *"=== 総合: ERRORS=1 ==="* ]]
  [[ "$output" != *"=== 総合: ERRORS=0 ==="* ]]
}

@test "review_bundle internal precheck rejects the same fixture it shell-BLOCKs on" {
  setup_gunshi_precheck_parity_fixture
  export GUNSHI_PRECHECK_CACHE_DIR="$FIX_DIR/cache_bundle"
  run python3 - "$REPO_ROOT" "$FIX_DIR/report.yaml" <<'PY'
import sys
sys.path.insert(0, f"{sys.argv[1]}/scripts")
import review_bundle
from pathlib import Path

root = Path(sys.argv[1]).resolve()
item = {"report": sys.argv[2], "cmd": "cmd_parity_fixture", "verdict": "APPROVE", "review_entry": {}}
try:
    result = review_bundle._batch_precheck(root, item)
except ValueError as exc:
    print(f"BLOCKED: {exc}"[:200])
    raise SystemExit(0)
raise SystemExit(f"expected precheck to raise (BLOCK), got status={result['status']!r}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"BLOCKED:"* ]]
  # The historical bug shape: silently downgraded to an advisory warning while
  # a real AC-evidence gap on an honest report went unreviewed.
  [[ "$output" != *"status=\"WARN\""* ]]
}

@test "ac_evidence_mapping gap verdict is identical across cwd and cache warm/cold state" {
  setup_gunshi_precheck_parity_fixture
  export GUNSHI_PRECHECK_CACHE_DIR="$FIX_DIR/cache_shared"

  # Different cwd, absolute report path: same repo/task resolution root either way.
  # (docs/ is used rather than /tmp: REPO_ROOT resolves via BASH_SOURCE regardless
  # of cwd, but an unrelated helper — scripts/lib/repo_root.sh get_repo_root, used
  # transitively via project_path.sh — still shells out to a bare
  # `git rev-parse --show-toplevel` with no -C anchor, so a cwd outside any git
  # worktree breaks unrelated to this fixture. That gap is tracked separately and
  # is out of this hotfix's target_path; this test stays inside the same repo.)
  run bash -c 'cd "$1" && bash "$2" "$3"' _ "$REPO_ROOT/docs" "$GATE" "$FIX_DIR/report.yaml"
  cwd_status="$status"; cwd_output="$output"
  [ "$cwd_status" -eq 1 ]
  [[ "$cwd_output" == *"=== 総合: ERRORS=1 ==="* ]]

  # Cache cold (first call above already populated it) vs warm (this repeat call
  # must hit the cache and still agree with the cold-path verdict). A cache hit
  # legitimately adds a "cache応答" stderr note, so compare the substantive
  # verdict (exit status + ERRORS tally), not the byte-for-byte merged output.
  run bash "$GATE" "$FIX_DIR/report.yaml"
  [ "$status" -eq "$cwd_status" ]
  [[ "$output" == *"cache応答"* ]]
  [[ "$output" == *"=== 総合: ERRORS=1 ==="* ]]
}
