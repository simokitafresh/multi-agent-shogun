"""Contract tests for fast report publication.

test_necessity: preserve the fixed-SHA deploy report contract across new,
same-identity pending, and different-identity stale publication while proving
one atomic output, valid YAML, complete required fields, and the speed budget.
"""

from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
import time
from pathlib import Path

import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "scripts/lib/deploy_task_report_publication_fast.py"
sys.path.insert(0, str(SOURCE.parent))
SPEC = importlib.util.spec_from_file_location("report_publication_fast", SOURCE)
assert SPEC and SPEC.loader
FAST = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = FAST
SPEC.loader.exec_module(FAST)


REPORT_ID = "rpt-12345678-1234-4123-8123-123456789abc"


def task_bytes(report_id: str = REPORT_ID) -> bytes:
    return f"""task:
  assigned_to: saizo
  task_id: fast_report_fixture
  parent_cmd: cmd_fast_report_fixture
  task_type: full
  project: infra
  purpose: report publication parity
  ac_version: fixture-ac
  report_filename: saizo_report_cmd_fast_report_fixture.yaml
  report_path: queue/reports/saizo_report_cmd_fast_report_fixture.yaml
  report_id: {report_id}
  target_path: scripts/lib/deploy_task_report_publication_fast.py
  related_lessons:
  - id: L922
  - id: L310
  acceptance_criteria:
  - id: AC1
    description: required fields remain complete
    checks:
    - check: required field missing count is zero
  - id: AC2
    description: YAML parses without error
    checks:
    - check: YAML parse error count is zero
""".encode()


def canonical_template() -> bytes:
    return f"""# canonical fixed-SHA report template fixture
worker_id: old
report_id: {REPORT_ID}
report_identity_version: 2
task_id: old
parent_cmd: old
task_type: old
timestamp: ""
status: pending
ac_version_read: old
result:
  summary: "fixed SHA template"
  details: ""
purpose_validation:
  cmd_purpose: ""
  fit: true
  purpose_gap: ""
simplicity_check: ""
assumption_check: ""
task_clarity: {{score: "", unclear_points: "", discretion_fills: ""}}
status_detail: ""
test_triage: ""
commit_contract: {{required: true, reason: implementation_path_present, task_type: full, planned_paths: scripts/lib/deploy_task_report_publication_fast.py}}
files_modified:
- path: ""
  change: ""
lesson_candidate: {{found: false, no_lesson_reason: known, title: "", detail: "", project: infra}}
lessons_useful: []
skill_candidate: {{found: false}}
decision_candidate: {{found: false}}
knowledge_candidate: {{found: false}}
assumption_invalidation: {{found: false, affected_cmds: [], detail: ""}}
hook_failures: {{count: 0, details: ""}}
post_deploy_evidence: {{required: false, run_completed: false}}
operational_simulation: {{command: "", expected: "", actual: "", result: ""}}
binary_checks: {{}}
self_gate_check: {{lesson_ref: PASS, lesson_candidate: PASS, status_valid: PASS, purpose_fit: PASS}}
verdict: ""
""".encode()


def parsed(data: bytes) -> dict:
    value = yaml.safe_load(data)
    assert isinstance(value, dict)
    return value


def run_fixed_sha_generator(tmp_path: Path) -> tuple[bytes, bytes]:
    """Execute the read-only fixed-SHA generator in an isolated root."""
    fixture_root = tmp_path / "fixed-sha-root"
    scripts = fixture_root / "scripts"
    queue = fixture_root / "queue"
    scripts.mkdir(parents=True)
    (queue / "tasks").mkdir(parents=True)
    (queue / "reports").mkdir()
    (fixture_root / "archive/reports/stale").mkdir(parents=True)
    (fixture_root / "logs").mkdir()
    (scripts / "deploy_task.sh").symlink_to(ROOT / "scripts/deploy_task.sh")
    (scripts / "lib").symlink_to(ROOT / "scripts/lib", target_is_directory=True)
    (fixture_root / "lib").symlink_to(ROOT / "lib", target_is_directory=True)
    (fixture_root / "config").symlink_to(ROOT / "config", target_is_directory=True)
    # Memory lookup is outside this helper's contract.  The fixed generator is
    # intentionally allowed to take its fail-soft, no-result branch.
    (scripts / "semantic_search.sh").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    (scripts / "semantic_search.sh").chmod(0o755)
    task = queue / "tasks/saizo.yaml"
    task.write_bytes(task_bytes())
    command = 'source "$1"; generate_report_template saizo fast_report_fixture cmd_fast_report_fixture infra "$2"'
    proc = subprocess.run(
        ["bash", "-c", command, "fixed-sha", os.fspath(scripts / "deploy_task.sh"), os.fspath(task)],
        cwd=ROOT,
        env={**os.environ, "DEPLOY_TASK_ROOT_OVERRIDE": os.fspath(fixture_root), "DEPLOY_TASK_LIB_ONLY": "1"},
        text=True,
        capture_output=True,
        check=False,
        timeout=15,
    )
    assert proc.returncode == 0, proc.stderr
    report = queue / "reports/saizo_report_cmd_fast_report_fixture.yaml"
    return task.read_bytes(), report.read_bytes()


def assert_contract(report: bytes) -> None:
    value = parsed(report)
    assert set(FAST.REQUIRED_REPORT_KEYS) <= value.keys()
    assert value["report_id"] == REPORT_ID
    assert [entry["id"] for entry in value["lessons_useful"]] == ["L922", "L310"]
    assert list(value["binary_checks"]) == ["AC1", "AC2", "commit"]


def test_new_report_has_current_contract_and_metadata_patch() -> None:
    result = FAST.build_publication(task_bytes(), canonical_template())
    assert not result.reused_existing
    assert_contract(result.report_bytes)
    assert result.task_metadata_patch == {
        "report_id": REPORT_ID,
        "report_identity_version": 2,
        "report_path": "queue/reports/saizo_report_cmd_fast_report_fixture.yaml",
        "report_filename": "saizo_report_cmd_fast_report_fixture.yaml",
        "variation_checks_required": False,
        "commit_contract": {
            "required": True,
            "reason": "implementation_path_present",
            "task_type": "full",
            "planned_paths": [
                "scripts/lib/deploy_task_report_publication_fast.py"
            ],
        },
    }


def test_fixed_sha_current_generator_has_field_level_parity(tmp_path: Path) -> None:
    generated_task, current = run_fixed_sha_generator(tmp_path)
    current_value = parsed(current)
    current_id = current_value["report_id"]
    result = FAST.build_publication(generated_task, current, report_id=current_id)
    fast_value = parsed(result.report_bytes)
    assert fast_value == current_value


def test_same_identity_pending_report_is_reused_byte_for_byte() -> None:
    generated = FAST.build_publication(task_bytes(), canonical_template()).report_bytes
    existing = generated.replace(b'summary: "fixed SHA template"', b'summary: "worker progress retained"')
    result = FAST.build_publication(task_bytes(), canonical_template(), existing)
    assert result.reused_existing
    assert result.report_bytes == existing
    assert_contract(result.report_bytes)


def test_different_identity_stale_report_is_never_reused() -> None:
    stale = canonical_template().replace(REPORT_ID.encode(), b"rpt-aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    stale = stale.replace(b"lessons_useful: []", b"lessons_useful: BROKEN_STALE_VALUE")
    result = FAST.build_publication(task_bytes(), canonical_template(), stale)
    assert not result.reused_existing
    assert b"BROKEN_STALE_VALUE" not in result.report_bytes
    assert_contract(result.report_bytes)


def test_only_owned_sections_change_in_template() -> None:
    marker = b"# immutable-template-marker\n"
    template = marker + canonical_template()
    report = FAST.build_publication(task_bytes(), template).report_bytes
    assert report.startswith(marker)
    assert b"result:\n  summary: \"fixed SHA template\"" in report


def test_atomic_publish_leaves_one_complete_yaml(tmp_path: Path) -> None:
    result = FAST.build_publication(task_bytes(), canonical_template())
    destination = tmp_path / "reports/report.yaml"
    FAST.atomic_publish(result.report_bytes, destination, ext4_temp_dir=tmp_path)
    assert destination.read_bytes() == result.report_bytes
    assert not list(destination.parent.glob(".report.yaml.publish.*"))
    assert_contract(destination.read_bytes())


def test_malformed_task_fails_without_publishing(tmp_path: Path) -> None:
    destination = tmp_path / "report.yaml"
    with pytest.raises((ValueError, yaml.YAMLError)):
        result = FAST.build_publication(b"task: [unterminated", canonical_template())
        FAST.atomic_publish(result.report_bytes, destination, ext4_temp_dir=tmp_path)
    assert not destination.exists()


def test_nine_run_median_is_below_fixed_sha_baseline(capsys: pytest.CaptureFixture[str]) -> None:
    durations = []
    for _ in range(9):
        started = time.perf_counter()
        report = FAST.build_publication(task_bytes(), canonical_template()).report_bytes
        durations.append((time.perf_counter() - started) * 1000)
        assert_contract(report)
    median_ms = sorted(durations)[4]
    print(f"PERF median_ms={median_ms:.3f} baseline_ms=1579")
    assert median_ms < 1579


def test_source_uses_no_yaml_serializer_and_cli_emits_valid_metadata(tmp_path: Path) -> None:
    source = SOURCE.read_text(encoding="utf-8")
    assert "yaml.dump(" not in source
    assert "yaml.safe_dump(" not in source
    task = tmp_path / "task.yaml"
    template = tmp_path / "template.yaml"
    report = tmp_path / "report.yaml"
    task.write_bytes(task_bytes())
    template.write_bytes(canonical_template())
    proc = subprocess.run(
        [os.fspath(SOURCE), "--task", os.fspath(task), "--template", os.fspath(template), "--report", os.fspath(report), "--temp-dir", os.fspath(tmp_path)],
        text=True,
        capture_output=True,
        check=False,
    )
    assert proc.returncode == 0, proc.stderr
    assert '"report_id":"' + REPORT_ID + '"' in proc.stdout
    assert_contract(report.read_bytes())
