"""test_necessity: report commit identity is a cross-task safety contract."""

from pathlib import Path
from subprocess import CalledProcessError, CompletedProcess
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


def _external_fixture(tmp_path):
    repo = (tmp_path / "external-repo").resolve()
    repo.mkdir()
    projects = tmp_path / "projects"
    projects.mkdir()
    (projects / "dm-signal.yaml").write_text(
        f"project:\n  id: dm-signal\n  path: {repo}\n",
        encoding="utf-8",
    )
    return repo


def _external_git(repo, *, missing=False):
    def run(command, **_kwargs):
        assert command[command.index("-C") + 1] == str(repo)
        if "rev-parse" in command:
            return CompletedProcess(command, 0, stdout=f"{repo}\n")
        if missing:
            raise CalledProcessError(128, command)
        if "--format=%s" in command:
            return CompletedProcess(command, 0, stdout=f"{TASK_ID}: owned commit\n")
        return CompletedProcess(command, 0, stdout="scripts/a.sh\nscripts/b.py\n")

    return run


def test_external_project_existing_commit_uses_project_repository(tmp_path):
    repo = _external_fixture(tmp_path)
    task = {**_task(), "project": "dm-signal"}
    with patch(
        "scripts.gates.gate_report_format_main.subprocess.run",
        side_effect=_external_git(repo),
    ):
        assert commit_contract_errors(_report(), task, tmp_path) == []


def test_external_project_missing_commit_stays_fail_closed(tmp_path):
    repo = _external_fixture(tmp_path)
    task = {**_task(), "project": "dm-signal"}
    with patch(
        "scripts.gates.gate_report_format_main.subprocess.run",
        side_effect=_external_git(repo, missing=True),
    ):
        assert commit_contract_errors(_report(), task, tmp_path) == [
            "commit_hash does not resolve to a readable commit"
        ]


@patch("scripts.gates.gate_report_format_main.subprocess.run", side_effect=_git)
def test_infra_project_keeps_platform_repository(_run, tmp_path):
    report = {**_report(), "project": "infra"}
    assert commit_contract_errors(report, _task(), tmp_path) == []
    assert all(command[command.index("-C") + 1] == str(tmp_path) for command in (call.args[0] for call in _run.call_args_list))


def test_unknown_project_is_rejected_without_git_fallback(tmp_path):
    task = {**_task(), "project": "unknown-project"}
    assert commit_contract_errors(_report(), task, tmp_path) == [
        "unknown project: unknown-project"
    ]
