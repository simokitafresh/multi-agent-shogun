"""test_necessity: report commit identity is a cross-task safety contract."""

from pathlib import Path
from subprocess import CompletedProcess
from unittest.mock import patch

from scripts.gates.gate_report_format_main import commit_contract_errors


GOOD = "2d1093e900000000000000000000000000000000"
FOREIGN = "73d6aef000000000000000000000000000000000"
TASK_ID = "cmd_fixture_normal"
PARENT = "cmd_fixture"


def _task(required=True):
    return {
        "task_id": TASK_ID,
        "target_path": ["scripts/a.sh", "scripts/b.py"],
        "commit_contract": {"required": required},
    }


def _opt_in_task():
    task = _task()
    task["commit_identity_contract_required"] = True
    return task


def _report(commit_hash=GOOD, evidence_hash=GOOD, source="terminal_ledger"):
    return {
        "task_id": TASK_ID,
        "parent_cmd": PARENT,
        "commit_hash": commit_hash,
        "commit_identity_evidence": {
            "source": source,
            "run_id": TASK_ID,
            "commit_hash": evidence_hash,
        },
    }


def _git(command, **_kwargs):
    if "--format=%s" in command:
        return CompletedProcess(command, 0, stdout=f"{TASK_ID}: owned commit\n")
    return CompletedProcess(command, 0, stdout="scripts/a.sh\nscripts/b.py\n")


@patch("scripts.gates.gate_report_format_main.subprocess.run", side_effect=_git)
def test_same_run_owned_commit_passes(_run):
    assert commit_contract_errors(_report(), _task(), Path(".")) == []


@patch("scripts.gates.gate_report_format_main.subprocess.run", side_effect=_git)
def test_tobisaru_foreign_head_hash_is_rejected(_run):
    errors = commit_contract_errors(_report(FOREIGN, GOOD), _task(), Path("."))
    assert any("evidence hash differs" in error for error in errors)


@patch("scripts.gates.gate_report_format_main.subprocess.run", side_effect=_git)
def test_foreign_run_id_is_rejected(_run):
    report = _report()
    report["commit_identity_evidence"]["run_id"] = "other_ninja_task"
    errors = commit_contract_errors(report, _task(), Path("."))
    assert any("run_id mismatch" in error for error in errors)


@patch("scripts.gates.gate_report_format_main.subprocess.run", side_effect=_git)
def test_missing_target_path_is_rejected(_run):
    def missing_target(command, **_kwargs):
        if "--format=%s" in command:
            if "log" in command:
                return CompletedProcess(command, 0, stdout="other task\n")
            return CompletedProcess(command, 0, stdout=f"{TASK_ID}: owned commit\n")
        return CompletedProcess(command, 0, stdout="scripts/a.sh\n")

    _run.side_effect = missing_target
    errors = commit_contract_errors(_report(), _task(), Path("."))
    assert errors == ["commit/task history does not contain target_path: scripts/b.py"]


def test_optional_commit_contract_does_not_require_hash_or_evidence():
    assert commit_contract_errors({}, _task(required=False), Path(".")) == []


@patch("scripts.gates.gate_report_format_main.subprocess.run", side_effect=_git)
def test_legacy_required_report_without_evidence_remains_compatible(_run):
    report = _report()
    report.pop("commit_identity_evidence")
    assert commit_contract_errors(report, _task(), Path(".")) == []


def test_opt_in_contract_requires_same_run_evidence():
    report = _report()
    report.pop("commit_identity_evidence")
    assert commit_contract_errors(report, _opt_in_task(), Path(".")) == [
        "commit_identity_evidence is required by opt-in contract"
    ]
