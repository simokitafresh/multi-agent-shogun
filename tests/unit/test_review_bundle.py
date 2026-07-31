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
    for relative in ("queue/reports", "queue/archive/reports", "queue/gates/cmd_ok"):
        (tmp_path / relative).mkdir(parents=True)
    return tmp_path


def test_resolve_report_accepts_direct_live_and_archive(tmp_path):
    root = _root(tmp_path)
    live = root / "queue/reports/worker_report_cmd_ok.yaml"
    archived = root / "queue/archive/reports/worker_report_cmd_ok.yaml"
    live.write_text("parent_cmd: cmd_ok\n", encoding="utf-8")
    archived.write_text("parent_cmd: cmd_ok\n", encoding="utf-8")

    assert review_bundle._resolve_report(root, live)[1] == live
    assert review_bundle._resolve_report(root, archived, allow_archived=True)[1] == archived


@pytest.mark.parametrize(
    "kind",
    ["nested", "symlink_escape", "archive_alias", "live_alias", "symlink_chain", "missing"],
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
    else:
        candidate = archive / "missing.yaml"

    with pytest.raises(ValueError):
        review_bundle._resolve_report(root, candidate, allow_archived=True)


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
        "parent_cmd: cmd_ok\nstatus: completed\nverdict: PASS\n"
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
