"""Contract tests for review_bundle report path boundaries.

test_necessity: notify must accept only direct live/archive reports selected by
the bundle's logical report key, while rejecting path and identity escapes.
"""
from pathlib import Path
from types import SimpleNamespace
import hashlib
import json
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor

import pytest
import yaml

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


def test_autogen_review_uses_durable_report_receipt_after_worker_redeployment(tmp_path):
    """test_necessity: a cmd_karo report receipt must survive the next worker lease."""
    root = _root(tmp_path)
    report = root / "queue/reports/saizo_report_cmd_karo_speed.yaml"
    report.write_text(
        "worker_id: saizo\nparent_cmd: cmd_karo_speed\ntask_id: cmd_karo_speed_normal\n"
        "report_id: rpt-speed\nreport_identity_version: 2\n"
        "timestamp: '2026-08-10T03:20:00+09:00'\nstatus: completed\nverdict: PASS\n"
        "ac_version_read: old-ac\ntask_contract_snapshot:\n"
        "  parent_cmd: cmd_karo_speed\n  issued_cmd_id: cmd_karo_speed\n"
        "  task_id: cmd_karo_speed_normal\n  ac_fingerprint: old-ac\n"
        "  purpose: speed up one test\n  project: infra\n"
        "  acceptance_criteria: [{id: AC1}]\n",
        encoding="utf-8",
    )
    (root / "queue/tasks/saizo.yaml").write_text(
        "task:\n  parent_cmd: cmd_next\n  task_id: cmd_next_normal\n"
        "  ac_version: next-ac\n  report_id: rpt-next\n",
        encoding="utf-8",
    )
    receipt = root / "archive/inbox/karo_20260810.yaml"
    receipt.parent.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256(report.read_bytes()).hexdigest()
    receipt.write_text(
        "messages:\n- type: report_received\n  report_id: rpt-speed\n"
        "  report_identity_version: 2\n"
        f"  report_fingerprint: {digest}\n"
        "  report_path: queue/reports/saizo_report_cmd_karo_speed.yaml\n"
        "  task_id: cmd_karo_speed_normal\n  parent_cmd: cmd_karo_speed\n",
        encoding="utf-8",
    )

    report_data = review_bundle.load(report)
    command, task_path = review_bundle.find_command(
        root, "cmd_karo_speed", report_data, report, requested_verdict="APPROVE"
    )
    assert command["project"] == "infra"
    assert command["acceptance_criteria"] == [{"id": "AC1"}]
    assert task_path == root / "queue/tasks/saizo.yaml"

    receipt.write_text("messages: []\n", encoding="utf-8")
    with pytest.raises(ValueError, match="immutable report-generation identity"):
        review_bundle.find_command(root, "cmd_karo_speed", report_data, report, requested_verdict="APPROVE")


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


def test_single_review_notification_is_singleflight_per_generation(tmp_path, monkeypatch):
    """test_necessity: duplicate report notifications must execute one review flight."""
    root = _root(tmp_path)
    cmd = "cmd_singleflight"
    (root / "queue/gates" / cmd).mkdir(parents=True, exist_ok=True)
    report = root / "queue/reports/worker_report_cmd_singleflight.yaml"
    report.write_text(
        "worker_id: worker\n"
        "task_id: cmd_singleflight_normal\n"
        "report_id: rpt-singleflight\n"
        "report_identity_version: 2\n"
        "parent_cmd: cmd_singleflight\n"
        "ac_version_read: ac-v1\n"
        "status: completed\n"
        "verdict: PASS\n"
        "commit_hash: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        "result: {summary: singleflight fixture}\n",
        encoding="utf-8",
    )
    (root / "queue/tasks/worker.yaml").write_text(
        "task:\n"
        "  task_id: cmd_singleflight_normal\n"
        "  parent_cmd: cmd_singleflight\n"
        "  report_filename: worker_report_cmd_singleflight.yaml\n"
        "  ac_version: ac-v1\n",
        encoding="utf-8",
    )
    entry = root / "review-entry.yaml"
    entry.write_text("cmd_id: cmd_singleflight\nreview_type: draft\n", encoding="utf-8")
    args = SimpleNamespace(
        root=str(root), cmd=cmd, report=str(report), verdict="APPROVE",
        review_entry=str(entry), fail_reason=None,
    )
    calls = []
    calls_lock = threading.Lock()

    def fake_batch(namespace):
        with calls_lock:
            calls.append(namespace.manifest)
        time.sleep(0.1)
        return 0

    monkeypatch.setattr(review_bundle, "batch", fake_batch)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: review_bundle.single(args), range(2)))

    assert results == [0, 0]
    assert len(calls) == 1
    terminal = review_bundle.load(root / "queue/gates" / cmd / "single_review_terminal.json")
    assert terminal["status"] == "success"


def test_single_review_failure_reopens_only_after_approval_state_change(tmp_path, monkeypatch):
    """test_necessity: true same-state failures stay fail-closed across retries."""
    root = _root(tmp_path)
    cmd = "cmd_singleflight_failure"
    (root / "queue/gates" / cmd).mkdir(parents=True, exist_ok=True)
    report = root / "queue/reports/worker_report_cmd_singleflight_failure.yaml"
    report.write_text(
        "worker_id: worker\n"
        "task_id: cmd_singleflight_failure_normal\n"
        "report_id: rpt-singleflight-failure\n"
        "report_identity_version: 2\n"
        "parent_cmd: cmd_singleflight_failure\n",
        encoding="utf-8",
    )
    (root / "queue/tasks/worker.yaml").write_text(
        "task:\n"
        "  task_id: cmd_singleflight_failure_normal\n"
        "  parent_cmd: cmd_singleflight_failure\n",
        encoding="utf-8",
    )
    entry = root / "review-entry.yaml"
    entry.write_text("cmd_id: cmd_singleflight_failure\nreview_type: report\n", encoding="utf-8")
    args = SimpleNamespace(
        root=str(root), cmd=cmd, report=str(report), verdict="APPROVE",
        review_entry=str(entry), fail_reason=None,
    )
    calls = []

    def failing_then_success(namespace):
        calls.append(namespace.manifest)
        if len(calls) == 1:
            raise ValueError("measured review failure")
        return 0

    monkeypatch.setattr(review_bundle, "batch", failing_then_success)
    with pytest.raises(ValueError, match="measured review failure"):
        review_bundle.single(args)
    with pytest.raises(ValueError, match="singleflight terminal failure"):
        review_bundle.single(args)
    assert len(calls) == 1

    logical = f"queue/reports/{report.name}"
    approval_key = hashlib.sha256(logical.encode("utf-8")).hexdigest()
    approval_dir = root / "queue/gates" / cmd / "review_approvals" / "reports" / approval_key
    approval_dir.mkdir(parents=True)
    (approval_dir / "karo.yaml").write_text("result: ACCEPT\n", encoding="utf-8")
    assert review_bundle.single(args) == 0
    assert len(calls) == 2


@pytest.mark.parametrize("receipt_kind", ["matching", "stale", "mismatch"])
def test_single_review_failure_token_only_changes_for_late_matching_receipt(
    tmp_path, monkeypatch, receipt_kind
):
    """test_necessity: only a new exact report receipt may reopen a failed review terminal."""
    root = _root(tmp_path)
    cmd = "cmd_singleflight_receipt"
    report = root / "queue/reports/worker_report_cmd_singleflight_receipt.yaml"
    report.write_text(
        "worker_id: worker\n"
        "task_id: cmd_singleflight_receipt_normal\n"
        "report_id: rpt-singleflight-receipt\n"
        "report_identity_version: 2\n"
        "parent_cmd: cmd_singleflight_receipt\n",
        encoding="utf-8",
    )
    (root / "queue/tasks/worker.yaml").write_text(
        "task:\n"
        "  task_id: cmd_singleflight_receipt_normal\n"
        "  parent_cmd: cmd_singleflight_receipt\n",
        encoding="utf-8",
    )
    entry = root / "review-entry.yaml"
    entry.write_text("cmd_id: cmd_singleflight_receipt\nreview_type: report\n", encoding="utf-8")
    args = SimpleNamespace(
        root=str(root), cmd=cmd, report=str(report), verdict="APPROVE",
        review_entry=str(entry), fail_reason=None,
    )
    calls = []
    token_before_receipt = review_bundle._singleflight_token(root, args, {
        "cmd_id": cmd, "review_type": "report"
    })

    def failing_batch(namespace):
        calls.append(namespace.manifest)
        raise ValueError("measured review failure")

    monkeypatch.setattr(review_bundle, "batch", failing_batch)
    with pytest.raises(ValueError, match="measured review failure"):
        review_bundle.single(args)

    digest = hashlib.sha256(report.read_bytes()).hexdigest()
    receipt = {
        "messages": [{
            "type": "report_received",
            "report_id": "rpt-singleflight-receipt",
            "report_identity_version": 2,
            "report_fingerprint": digest if receipt_kind == "matching" else "0" * 64,
            "report_path": "queue/reports/worker_report_cmd_singleflight_receipt.yaml",
            "task_id": "cmd_singleflight_receipt_normal",
            "parent_cmd": "cmd_singleflight_receipt",
        }]
    }
    if receipt_kind == "mismatch":
        receipt["messages"][0]["task_id"] = "cmd_other_normal"
    (root / "queue/inbox").mkdir(parents=True, exist_ok=True)
    (root / "queue/inbox/karo.yaml").write_text(yaml.safe_dump(receipt), encoding="utf-8")

    if receipt_kind == "matching":
        token_after_receipt = review_bundle._singleflight_token(root, args, {
            "cmd_id": cmd, "review_type": "report"
        })
        assert token_after_receipt != token_before_receipt
        payload = review_bundle._receipt_generation_identity(root, report, review_bundle.load(report))
        assert payload == {
            "report_id": "rpt-singleflight-receipt",
            "report_identity_version": "2",
            "report_fingerprint": digest,
            "report_path": "queue/reports/worker_report_cmd_singleflight_receipt.yaml",
            "task_id": "cmd_singleflight_receipt_normal",
            "parent_cmd": "cmd_singleflight_receipt",
        }
        with pytest.raises(ValueError, match="measured review failure"):
            review_bundle.single(args)
        assert len(calls) == 2
        with pytest.raises(ValueError, match="singleflight terminal failure"):
            review_bundle.single(args)
        assert len(calls) == 2
    else:
        assert review_bundle._singleflight_token(root, args, {
            "cmd_id": cmd, "review_type": "report"
        }) == token_before_receipt
        with pytest.raises(ValueError, match="singleflight terminal failure"):
            review_bundle.single(args)
        assert len(calls) == 1


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


@pytest.mark.parametrize("fixture", ["receipt_match", "receipt_fingerprint_mismatch", "task_not_replaced"])
def test_split_child_receipt_is_the_only_superseded_task_escape(tmp_path, fixture):
    """test_necessity: only an exact durable receipt may authorize a superseded split report."""
    root = _root(tmp_path)
    (root / "queue/archive/cmds").mkdir(parents=True)
    cmd = "cmd_4410_ac3"
    (root / "queue/archive/cmds/cmd_4410_done.yaml").write_text(
        "commands:\n  cmd_4410:\n    acceptance_criteria:\n      AC1: {description: docs}\n"
        "      AC2: {description: architecture}\n      AC3: {description: isolation}\n"
        "    target_path: README.md\n    project: infra\n",
        encoding="utf-8",
    )
    report = root / "queue/reports/tobisaru_report_cmd_4410_ac3.yaml"
    report.write_text(
        "worker_id: tobisaru\nparent_cmd: cmd_4410_ac3\ntask_id: cmd_4410_ac3_normal\n"
        "report_id: rpt-4410-ac3\nreport_identity_version: 2\nac_version_read: ac-v1\n"
        "status: completed\nverdict: PASS\nresult: {summary: measured}\n"
        "task_contract_snapshot:\n  parent_cmd: cmd_4410_ac3\n  issued_cmd_id: cmd_4410_ac3\n"
        "  task_id: cmd_4410_ac3_normal\n  ac_fingerprint: ac-v1\n  purpose: isolate\n"
        "  acceptance_criteria: [{id: AC3}]\n  project: infra\n",
        encoding="utf-8",
    )
    (root / "queue/inbox").mkdir(parents=True)
    digest = hashlib.sha256(report.read_bytes()).hexdigest()
    receipt_digest = digest if fixture == "receipt_match" else "0" * 64
    receipt = {
        "messages": [{
            "type": "report_received", "report_id": "rpt-4410-ac3",
            "report_identity_version": 2, "report_fingerprint": receipt_digest,
            "report_path": "queue/reports/tobisaru_report_cmd_4410_ac3.yaml",
            "task_id": "cmd_4410_ac3_normal", "parent_cmd": "cmd_4410_ac3",
        }]
    }
    (root / "queue/inbox/karo.yaml").write_text(yaml.safe_dump(receipt), encoding="utf-8")

    if fixture == "task_not_replaced":
        task = {
            "task_id": "cmd_4410_ac3_normal", "parent_cmd": cmd,
            "issued_cmd_id": "cmd_wrong", "report_filename": "wrong.yaml",
            "subtask_id": "ac3", "ac_version": "ac-v1", "report_id": "rpt-4410-ac3",
        }
    else:
        task = {
            "task_id": "cmd_next_normal", "parent_cmd": "cmd_next",
            "issued_cmd_id": "cmd_next", "report_filename": "worker_report_cmd_next.yaml",
            "ac_version": "ac-v2", "report_id": "rpt-next",
        }
    (root / "queue/tasks/tobisaru.yaml").write_text(yaml.safe_dump({"task": task}), encoding="utf-8")
    report_data = review_bundle.load(report)

    if fixture == "receipt_match":
        command, source = review_bundle.find_command(root, cmd, report_data, report, requested_verdict="APPROVE")
        assert source == root / "queue/archive/cmds/cmd_4410_done.yaml"
        assert command["project"] == "infra"
    else:
        with pytest.raises(ValueError, match="identity mismatch|report-generation identity"):
            review_bundle.find_command(root, cmd, report_data, report, requested_verdict="APPROVE")


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


def test_approve_accepts_completed_pass_no_improvement_from_autogen_snapshot(tmp_path):
    """test_necessity: APPROVE must preserve a measured no-improvement report as a valid success state.

    regression_justification: the autogen fallback and APPROVE validation each
    previously admitted only completed/PASS, blocking truthful PASS_NO_IMPROVEMENT
    reports before review_bundle could generate the approval bundle.
    """
    root = _root(tmp_path)
    cmd = "cmd_karo_pass_no_improvement"
    report = root / f"queue/reports/worker_report_{cmd}.yaml"
    task = root / "queue/tasks/worker.yaml"
    task.write_text(
        f"task:\n  parent_cmd: {cmd}\n  task_id: {cmd}_normal\n  ac_version: ac1\n"
        f"  report_id: rpt-no-improvement\n  report_filename: {report.name}\n",
        encoding="utf-8",
    )
    report.write_text(
        f"parent_cmd: {cmd}\ntask_id: {cmd}_normal\nworker_id: worker\n"
        "report_id: rpt-no-improvement\nac_version_read: ac1\n"
        "status: completed\nverdict: PASS_NO_IMPROVEMENT\n"
        "binary_checks: {AC1: [{result: yes}]}\nresult: {summary: measured no improvement}\n"
        f"task_contract_snapshot: {{parent_cmd: {cmd}, issued_cmd_id: {cmd}, task_id: {cmd}_normal, "
        "ac_fingerprint: ac1, purpose: probe, acceptance_criteria: [one], project: infra}\n",
        encoding="utf-8",
    )
    args = SimpleNamespace(
        root=str(root), report=str(report), cmd=cmd, verdict="APPROVE",
        allow_archived=False, fail_reason=None,
    )

    assert review_bundle.generate(args) == 0
    bundle = review_bundle.load(root / f"queue/gates/{cmd}/sg7_bundle.json")
    assert bundle["review"]["verdict"] == "APPROVE"
