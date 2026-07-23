"""Generation identity contracts for report publication.

test_necessity: A normal redeploy must not let a stale split-task identity
override the current task generation in the report consumed by review gates.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "scripts/lib/deploy_task_report_publication_fast.py"
sys.path.insert(0, str(SOURCE.parent))
SPEC = importlib.util.spec_from_file_location("generation_identity", SOURCE)
assert SPEC and SPEC.loader
FAST = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = FAST
SPEC.loader.exec_module(FAST)


def test_current_task_id_wins_over_stale_subtask_id() -> None:
    task = """task:
  assigned_to: kotaro
  task_id: cmd_4128_full
  _ac_task_id: cmd_4128_full
  subtask_id: cmd_4127_docs_context
  parent_cmd: cmd_4128
  task_type: full
  project: dm-signal
  purpose: gate/hook変更でないUI修正
  ac_version: current
  report_id: rpt-12345678-1234-4123-8123-123456789abc
  report_path: queue/reports/kotaro_report_cmd_4128.yaml
  acceptance_criteria:
  - id: AC1
    checks:
    - check: current generation remains authoritative
""".encode()
    template = b"""worker_id: old
report_id: rpt-12345678-1234-4123-8123-123456789abc
report_identity_version: 2
task_id: old
parent_cmd: old
task_type: old
timestamp: ""
status: pending
ac_version_read: old
result: {summary: "", details: ""}
purpose_validation: {cmd_purpose: "", fit: true, purpose_gap: ""}
simplicity_check: ""
assumption_check: ""
task_clarity: {score: "", unclear_points: "", discretion_fills: ""}
status_detail: ""
test_triage: ""
commit_contract: {required: true}
files_modified: [{path: "", change: ""}]
lesson_candidate: {found: false}
lessons_useful: []
skill_candidate: {found: false}
decision_candidate: {found: false}
knowledge_candidate: {found: false}
assumption_invalidation: {found: false}
hook_failures: {count: 0}
post_deploy_evidence: {required: false}
operational_simulation: {command: "", expected: "", actual: "", result: ""}
binary_checks: {}
self_gate_check: {lesson_ref: PASS}
verdict: ""
"""

    report = FAST.build_publication(task, template).report_bytes

    assert yaml.safe_load(report)["task_id"] == "cmd_4128_full"
    assert FAST.build_publication(task, template).task_metadata_patch[
        "variation_checks_required"
    ] is False


def test_positional_assignment_maps_to_explicit_criterion_id() -> None:
    task = {
        "assigned_acs": ["AC2"],
        "acceptance_criteria": [
            {"id": "R1", "checks": ["first"]},
            {"id": "R2", "checks": ["second"]},
        ],
    }

    assert FAST._criteria(task) == [("R2", ["second"])]
