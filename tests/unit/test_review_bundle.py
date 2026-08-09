"""Contract tests for review_bundle report path boundaries.

test_necessity: notify must accept only direct live/archive reports selected by
the bundle's logical report key, while rejecting path and identity escapes.
"""
from pathlib import Path
from types import SimpleNamespace
import json
import subprocess

import pytest

from scripts import review_bundle


def _root(tmp_path: Path) -> Path:
    for relative in ("queue/reports", "queue/archive/reports", "queue/gates/cmd_ok", "queue/tasks"):
        (tmp_path / relative).mkdir(parents=True)
    return tmp_path


def _register(root: Path, report: Path, report_id="rpt-ok"):
    report.write_text(f"parent_cmd: cmd_ok\nreport_id: {report_id}\n", encoding="utf-8")
    if report.parent == root / "queue/reports":
        (root / "queue/tasks/worker.yaml").write_text(
            f"task:\n  parent_cmd: cmd_ok\n  report_filename: {report.name}\n", encoding="utf-8"
        )


def test_review_bundle_uses_parent_cmd_contract_after_worker_redeployment(tmp_path):
    """test_necessity: old report review must not mutate a later worker lease."""
    root = _root(tmp_path)
    (root / "queue/gates/cmd_4274").mkdir(parents=True, exist_ok=True)
    (root / "queue/shogun_to_karo.yaml").write_text(
        "commands:\n"
        "  cmd_4274:\n"
        "    acceptance_criteria: [{id: AC1, description: old contract}]\n"
        "    target_path: scripts/review_bundle.py\n"
        "    project: infra\n",
        encoding="utf-8",
    )
    report = root / "queue/reports/saizo_report_cmd_4274.yaml"
    report.write_text(
        "worker_id: saizo\nparent_cmd: cmd_4274\ntask_id: cmd_4274_full\n"
        "ac_version_read: b4003b4b\nreport_id: rpt-4274\nstatus: completed\nverdict: PASS\n"
        "binary_checks: {AC1: [{result: yes}]}\nresult: {summary: old report measured}\n",
        encoding="utf-8",
    )
    task = root / "queue/tasks/saizo.yaml"
    task.write_text(
        "task:\n  parent_cmd: cmd_4277\n  task_id: cmd_4277_full\n"
        "  ac_version: cf5a1428\n  status: acknowledged\n",
        encoding="utf-8",
    )
    report_before = report.read_bytes()
    task_before = task.read_bytes()
    args = SimpleNamespace(
        root=str(root), report=str(report), cmd="cmd_4274", verdict="APPROVE",
        allow_archived=False, fail_reason=None,
    )

    assert review_bundle.generate(args) == 0
    assert report.read_bytes() == report_before
    assert task.read_bytes() == task_before
    bundle = review_bundle.load(root / "queue/gates/cmd_4274/sg7_bundle.json")
    assert bundle["review"]["cmd_id"] == "cmd_4274"
    assert bundle["review"]["cmd_spec_summary"]["project"] == "infra"


@pytest.mark.parametrize("archived", [False, True])
def test_resolve_report_accepts_direct_live_and_archive(tmp_path, archived):
    root = _root(tmp_path)
    base = "queue/archive/reports" if archived else "queue/reports"
    report = root / base / "worker_report_cmd_ok.yaml"
    _register(root, report)
    assert review_bundle._resolve_report(root, report, "cmd_ok", allow_archived=archived)[1] == report


@pytest.mark.parametrize(
    "kind",
    ["nested", "symlink_escape", "archive_alias", "live_alias", "symlink_chain", "traversal", "missing"],
)
def test_resolve_report_rejects_archive_boundary_escapes(tmp_path, kind):
    root = _root(tmp_path)
    archive = root / "queue/archive/reports"
    if kind == "nested":
        candidate = archive / "nested/report.yaml"
        candidate.parent.mkdir()
        candidate.write_text("parent_cmd: cmd_ok\n", encoding="utf-8")
    elif kind == "symlink_escape":
        outside = root / "outside.yaml"
        outside.write_text("parent_cmd: cmd_ok\n", encoding="utf-8")
        candidate = archive / "report.yaml"
        candidate.symlink_to(outside)
    elif kind == "archive_alias":
        target = archive / "target.yaml"
        target.write_text("parent_cmd: cmd_ok\n", encoding="utf-8")
        candidate = archive / "alias.yaml"
        candidate.symlink_to(target)
    elif kind == "live_alias":
        live = root / "queue/reports"
        target = live / "target.yaml"
        target.write_text("parent_cmd: cmd_ok\n", encoding="utf-8")
        candidate = live / "alias.yaml"
        candidate.symlink_to(target)
    elif kind == "symlink_chain":
        target = archive / "target.yaml"
        target.write_text("parent_cmd: cmd_ok\n", encoding="utf-8")
        link = archive / "link.yaml"
        link.symlink_to(target)
        candidate = archive / "chain.yaml"
        candidate.symlink_to(link)
    elif kind == "traversal":
        target = archive / "target.yaml"
        _register(root, target)
        candidate = Path(str(archive / ".." / "reports" / "target.yaml"))
    else:
        candidate = archive / "missing.yaml"

    with pytest.raises(ValueError):
        review_bundle._resolve_report(root, candidate, "cmd_ok", allow_archived=True)


def test_notify_uses_archive_logical_key_and_checks_parent_cmd(tmp_path, monkeypatch):
    root = _root(tmp_path)
    report = root / "queue/archive/reports/worker_report_cmd_ok.yaml"
    report.write_text("parent_cmd: cmd_ok\n", encoding="utf-8")
    bundle = root / "queue/gates/cmd_ok/sg7_bundle.json"
    review_bundle.atomic_json(bundle, {"review": {
        "cmd_id": "cmd_other", "verdict": "APPROVE", "reviewer": "gunshi",
        "report": "queue/archive/reports/worker_report_cmd_ok.yaml",
        "report_fingerprint": "unused", "cmd_spec_summary": {
            "acceptance_criteria_count": 1, "scope": "x", "project": "infra",
        }, "dashboard_line": "- **cmd_other**: complete",
    }})
    monkeypatch.setattr(review_bundle.subprocess, "run", lambda *a, **kw: None)

    with pytest.raises(ValueError, match="bundle cmd mismatch"):
        review_bundle.notify(SimpleNamespace(root=str(root), cmd="cmd_ok", bundle=str(bundle)))


def test_cli_archive_generate_then_notify_once_with_same_logical_identity(tmp_path):
    root = _root(tmp_path)
    (root / "scripts/lib").mkdir(parents=True)
    (root / "scripts/review_bundle.py").symlink_to(Path(review_bundle.__file__).resolve())
    (root / "scripts/lib/review_approval.sh").write_text(
        "review_two_phase_ready_gunshi() { return 0; }\n", encoding="utf-8"
    )
    (root / "scripts/inbox_write.sh").write_text(
        "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$(dirname \"$0\")/../inbox.calls\"\n",
        encoding="utf-8",
    )
    (root / "scripts/inbox_write.sh").chmod(0o755)
    (root / "queue/shogun_to_karo.yaml").write_text(
        "commands:\n  cmd_ok:\n    acceptance_criteria: [one]\n    target_path: scripts/review_bundle.py\n    project: infra\n",
        encoding="utf-8",
    )
    report = root / "queue/archive/reports/worker_report_cmd_ok.yaml"
    report.write_text(
        "parent_cmd: cmd_ok\nreport_id: rpt-ok\nstatus: completed\nverdict: PASS\n"
        "binary_checks: {AC1: [{result: yes}]}\nresult: {summary: done}\n",
        encoding="utf-8",
    )
    cli = ["python3", str(Path(review_bundle.__file__).resolve()), "--root", str(root)]
    subprocess.run(cli + ["generate", "--cmd", "cmd_ok", "--verdict", "APPROVE",
                          "--report", str(report), "--allow-archived"], check=True)
    bundle = root / "queue/gates/cmd_ok/sg7_bundle.json"
    subprocess.run(cli + ["notify", "--cmd", "cmd_ok", "--bundle", str(bundle)], check=True)

    stored = json.loads(bundle.read_text(encoding="utf-8"))["review"]["report"]
    assert stored == "queue/archive/reports/worker_report_cmd_ok.yaml"
    assert (root / "inbox.calls").read_text(encoding="utf-8").count("report_review_result") == 1


def test_cli_failed_archive_report_generates_fail_bundle(tmp_path):
    root = _root(tmp_path)
    (root / "queue/shogun_to_karo.yaml").write_text(
        "commands:\n  cmd_ok:\n    acceptance_criteria: [one]\n    target_path: scripts/review_bundle.py\n    project: infra\n",
        encoding="utf-8",
    )
    report = root / "queue/archive/reports/worker_report_cmd_ok.yaml"
    report.write_text(
        "parent_cmd: cmd_ok\nreport_id: rpt-failed\nstatus: failed\nverdict: FAIL\n"
        "result: {summary: failed as measured}\n",
        encoding="utf-8",
    )
    args = SimpleNamespace(root=str(root), report=str(report), cmd="cmd_ok", verdict="FAIL",
                           allow_archived=True, fail_reason="measured failure")
    assert review_bundle.generate(args) == 0


def test_specless_failed_report_generates_fail_bundle_from_snapshot(tmp_path):
    root = _root(tmp_path); cmd = "cmd_karo_probe"
    report = root / f"queue/reports/worker_report_{cmd}.yaml"
    task = root / "queue/tasks/worker.yaml"
    task.write_text(
        f"task:\n  parent_cmd: {cmd}\n  task_id: {cmd}_normal\n  ac_version: ac1\n"
        f"  report_id: rpt-failed\n  report_filename: {report.name}\n",
        encoding="utf-8",
    )
    report.write_text(
        f"parent_cmd: {cmd}\ntask_id: {cmd}_normal\nworker_id: worker\nreport_id: rpt-failed\n"
        "ac_version_read: ac1\nstatus: failed\nverdict: FAIL\nresult: {summary: failed}\n"
        f"task_contract_snapshot: {{parent_cmd: {cmd}, issued_cmd_id: {cmd}, task_id: {cmd}_normal, "
        "ac_fingerprint: ac1, purpose: probe, acceptance_criteria: [one], project: infra}\n",
        encoding="utf-8",
    )
    args = SimpleNamespace(root=str(root), report=str(report), cmd=cmd, verdict="FAIL",
                           allow_archived=False, fail_reason="measured failure")
    assert review_bundle.generate(args) == 0


@pytest.mark.parametrize("mutation", [None, "missing_subtask", "foreign_ac", "wrong_issued", "wrong_report"])
def test_split_child_resolves_only_verified_longest_ancestor(tmp_path, mutation):
    """test_necessity: spec-less split reports cannot invent or escape their saved parent contract."""
    root = _root(tmp_path); cmd = "cmd_4225_frontend_impl"
    (root / "queue/archive/cmds").mkdir(parents=True)
    (root / "queue/archive/cmds/cmd_4225_done.yaml").write_text(
        "commands:\n  cmd_4225:\n    acceptance_criteria:\n      AC1: {description: backend}\n"
        "      AC2: {description: frontend}\n    target_path: app\n    project: demo\n",
        encoding="utf-8",
    )
    report = root / f"queue/reports/worker_report_{cmd}.yaml"
    issued = "cmd_wrong" if mutation == "wrong_issued" else cmd
    filename = "wrong.yaml" if mutation == "wrong_report" else report.name
    subtask = "" if mutation == "missing_subtask" else "frontend_price"
    assigned = "[AC9]" if mutation == "foreign_ac" else "[AC2]"
    (root / "queue/tasks/worker.yaml").write_text(
        f"task:\n  parent_cmd: {cmd}\n  issued_cmd_id: {issued}\n  task_id: {cmd}_normal\n"
        f"  subtask_id: {subtask!r}\n  assigned_acs: {assigned}\n  ac_version: ac1\n"
        f"  report_id: rpt-split\n  report_filename: {filename}\n",
        encoding="utf-8",
    )
    report.write_text(
        f"parent_cmd: {cmd}\ntask_id: {cmd}_normal\nworker_id: worker\nreport_id: rpt-split\n"
        "ac_version_read: ac1\nstatus: completed\nverdict: PASS\n"
        "binary_checks: {AC2: [{result: yes}]}\nresult: {summary: measured}\n"
        f"task_contract_snapshot: {{parent_cmd: {cmd}, issued_cmd_id: {cmd}, task_id: {cmd}_normal, "
        "ac_fingerprint: ac1, purpose: frontend, acceptance_criteria: [{id: AC2}], project: demo}\n",
        encoding="utf-8",
    )
    args = SimpleNamespace(root=str(root), report=str(report), cmd=cmd, verdict="APPROVE",
                           allow_archived=False, fail_reason=None)
    if mutation is None:
        assert review_bundle.generate(args) == 0
        bundle = review_bundle.load(root / f"queue/gates/{cmd}/sg7_bundle.json")
        assert bundle["review"]["cmd_spec_summary"]["acceptance_criteria_count"] == 2
    else:
        with pytest.raises(ValueError):
            review_bundle.generate(args)


@pytest.mark.parametrize(
    ("has_spec", "review_verdict", "report_status", "report_verdict", "accepted"),
    [
        (has_spec, review_verdict, report_status, report_verdict, accepted)
        for has_spec in (False, True)
        for review_verdict, report_status, report_verdict, accepted in (
            ("APPROVE", "completed", "PASS", True),
            ("APPROVE", "failed", "FAIL", False),
            ("FAIL", "completed", "PASS", True),
            ("FAIL", "failed", "FAIL", True),
        )
    ],
)
def test_review_and_report_verdict_axes_contract(
    tmp_path, has_spec, review_verdict, report_status, report_verdict, accepted
):
    """test_necessity: review verdict must not overwrite the reporter verdict axis."""
    root = _root(tmp_path); cmd = "cmd_karo_matrix"
    report = root / f"queue/reports/worker_report_{cmd}.yaml"
    task = root / "queue/tasks/worker.yaml"
    task.write_text(
        f"task:\n  parent_cmd: {cmd}\n  task_id: {cmd}_normal\n  ac_version: ac1\n"
        f"  report_id: rpt-matrix\n  report_filename: {report.name}\n",
        encoding="utf-8",
    )
    if has_spec:
        (root / "queue/shogun_to_karo.yaml").write_text(
            f"commands:\n  {cmd}:\n    acceptance_criteria: [one]\n"
            "    target_path: scripts/review_bundle.py\n    project: infra\n",
            encoding="utf-8",
        )
    report.write_text(
        f"parent_cmd: {cmd}\ntask_id: {cmd}_normal\nworker_id: worker\nreport_id: rpt-matrix\n"
        f"ac_version_read: ac1\nstatus: {report_status}\nverdict: {report_verdict}\n"
        "binary_checks: {AC1: [{result: yes}]}\nresult: {summary: measured}\n"
        f"task_contract_snapshot: {{parent_cmd: {cmd}, issued_cmd_id: {cmd}, task_id: {cmd}_normal, "
        "ac_fingerprint: ac1, purpose: probe, acceptance_criteria: [one], project: infra}\n",
        encoding="utf-8",
    )
    args = SimpleNamespace(
        root=str(root), report=str(report), cmd=cmd, verdict=review_verdict,
        allow_archived=False, fail_reason="review evidence mismatch",
    )
    if accepted:
        assert review_bundle.generate(args) == 0
        assert review_bundle.load(root / f"queue/gates/{cmd}/sg7_bundle.json")["review"]["verdict"] == review_verdict
    else:
        with pytest.raises(ValueError):
            review_bundle.generate(args)
