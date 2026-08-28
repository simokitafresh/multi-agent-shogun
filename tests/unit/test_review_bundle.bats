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
