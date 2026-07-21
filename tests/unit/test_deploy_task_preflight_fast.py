"""Fixed-SHA parity contract for the batched deploy preflight adapter.

test_necessity: valid, malformed, missing-path, and duplicate-active fixtures
must have inspection-set difference 0 and per-function rc difference 0 against
the actual fixed-SHA ``scripts/deploy_task.sh`` functions.
"""

from __future__ import annotations

import importlib.util
import statistics
import subprocess
import sys
import time
from pathlib import Path

import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]
DEPLOY = ROOT / "scripts/deploy_task.sh"
SPEC = importlib.util.spec_from_file_location("deploy_task_preflight_fast", ROOT / "scripts/lib/deploy_task_preflight_fast.py")
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def write(path: Path, value: object) -> Path:
    path.write_text(yaml.safe_dump(value), encoding="utf-8")
    return path


def baseline(source: Path, active: Path, cmd_id: str) -> tuple[tuple[str, int], ...]:
    script = r'''
set +e
export DEPLOY_TASK_LIB_ONLY=1
source "$1"
set +e
deploy_task_destructive_signal_precheck "$2" "$4" >/dev/null 2>&1; a=$?
should_skip_same_cmd_resolve "$3" "$4" fixture-worker >/dev/null 2>&1; b=$?
printf '%s\t%s\n' "$a" "$b"
'''
    result = subprocess.run(["bash", "-c", script, "baseline", str(DEPLOY), str(source), str(active), cmd_id],
                            check=True, capture_output=True, text=True)
    values = tuple(int(value) for value in result.stdout.strip().split("\t"))
    return tuple(zip(MODULE.FUNCTIONS, values))


@pytest.mark.parametrize("fixture", ["valid", "malformed", "missing", "duplicate"])
def test_fixed_sha_preflight_set_and_rc_parity(tmp_path, fixture):
    cmd_id = "cmd_fixture"
    source = write(tmp_path / "source.yaml", {"task": {"id": cmd_id, "purpose": "safe"}})
    active = write(tmp_path / "active.yaml", {"task": {"parent_cmd": "other", "status": "idle"}})
    if fixture == "malformed":
        source.write_text("task: [", encoding="utf-8")
    elif fixture == "missing":
        source = tmp_path / "missing.yaml"
    elif fixture == "duplicate":
        active = write(tmp_path / "active.yaml", {
            "task": {"parent_cmd": cmd_id, "status": "assigned", "task_id": "fixture_normal",
                     "report_path": "scripts/deploy_task.sh"}
        })

    expected = baseline(source, active, cmd_id)
    actual = MODULE.run_preflight(DEPLOY, source, active, cmd_id)
    assert tuple(name for name, _ in actual.checks) == tuple(name for name, _ in expected)
    assert actual.checks == expected
    assert actual.rc == (0 if all(rc == 0 for _, rc in expected) else 2)


def test_nine_run_median_below_natural_receipt(tmp_path, capsys):
    source = write(tmp_path / "source.yaml", {"task": {"id": "cmd_perf", "purpose": "safe"}})
    active = write(tmp_path / "active.yaml", {"task": {"parent_cmd": "other", "status": "idle"}})
    samples = []
    for _ in range(9):
        started = time.perf_counter()
        MODULE.run_preflight(DEPLOY, source, active, "cmd_perf")
        samples.append((time.perf_counter() - started) * 1000)
    median = statistics.median(samples)
    print(f"preflight_median_ms={median:.3f}")
    assert median < 8686

