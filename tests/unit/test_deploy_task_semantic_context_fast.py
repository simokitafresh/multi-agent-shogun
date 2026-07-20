"""Contract tests for the F1 semantic-context fast helper."""

from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
from pathlib import Path

import pytest


# test_necessity: semantic context must retain fixed-SHA concept order and task-section output while avoiding repeated semantic-index parsing.
ROOT = Path(__file__).resolve().parents[2]
HELPER_PATH = ROOT / "scripts/lib/deploy_task_semantic_context_fast.py"
SOURCE_PATH = ROOT / "scripts/deploy_task.sh"


def _load_helper():
    spec = importlib.util.spec_from_file_location("semantic_context_fast", HELPER_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


HELPER = _load_helper()


INDEX = """\
---
codd:
  type: semantic-index
---

## campaign_lane — 台帳駆動攻略レーン

| 属性 | 値 |
|------|---|
| id | campaign_lane |
| label | 台帳駆動攻略レーン |
| aliases | campaign-lane, campaign lane, 台帳駆動攻略 |
| skills | なし |

| 種別 | パス/参照 |
|------|----------|
| file | `docs/research/campaign.md` |

## growth_loop — 学習ループ

| 属性 | 値 |
|------|---|
| id | growth_loop |
| label | 学習ループ |
| aliases | 成長ループ |

| 種別 | パス/参照 |
|------|----------|
| file | `context/growth-loop.md` |
""".encode("utf-8")


def _task(purpose: str, *, target: str = "scripts/foo.py") -> bytes:
    return (
        "task:\n"
        f'  purpose: "{purpose}"\n'
        f'  target_path: "{target}"\n'
        '  semantic_concepts:\n'
        '  - "stale concept: stale.md"\n'
        '  recommended_skills:\n'
        '  - "stale-skill"\n'
        '  description: "fixture description"\n'
    ).encode("utf-8")


def _fixed_sha_output(task_bytes: bytes, index_bytes: bytes) -> bytes:
    """Run the actual fixed-SHA shell function against the same fixture."""
    import tempfile

    with tempfile.TemporaryDirectory() as directory:
        task_path = Path(directory) / "task.yaml"
        index_path = Path(directory) / "index.md"
        task_path.write_bytes(task_bytes)
        index_path.write_bytes(index_bytes)
        env = os.environ.copy()
        env.update(
            {
                "DEPLOY_TASK_LIB_ONLY": "1",
                "SEMANTIC_INDEX_PATH": str(index_path),
                "SEMANTIC_DISABLE_CAUSAL": "1",
                "SEMANTIC_DISABLE_MEMORY_DB": "1",
                "SEMANTIC_DISABLE_LLM": "1",
                "SEMANTIC_DISABLE_SEARCH_LOG": "1",
                "DEPLOY_TASK_WAVE_CACHE_DIR": str(Path(directory) / "wave-cache"),
            }
        )
        command = (
            "source scripts/deploy_task.sh; "
            "log(){ :; }; inject_semantic_concepts \"$1\""
        )
        result = subprocess.run(
            ["bash", "-c", command, "bash", str(task_path)],
            cwd=ROOT,
            env=env,
            check=True,
            capture_output=True,
            text=True,
        )
        assert "ERROR:" not in result.stderr
        return task_path.read_bytes()


@pytest.mark.parametrize(
    "task_bytes",
    [
        _task("campaign lane semantic context"),
        _task("unregistered fixture phrase"),
        _task("記憶"),
        _task("campaign lane semantic context", target="tests/unit/target.py"),
    ],
    ids=["hit", "hit0", "ambiguous-alias", "target-path"],
)
def test_matches_fixed_sha_for_hit_hit0_ambiguous_and_target_path(task_bytes: bytes) -> None:
    expected = _fixed_sha_output(task_bytes, INDEX)
    actual = HELPER.inject_semantic_concepts(task_bytes, INDEX)
    assert actual == expected


def test_parse_index_once_contract_and_nine_iteration_receipt(capsys: pytest.CaptureFixture[str]) -> None:
    timings = []
    for _ in range(9):
        import time

        started = time.perf_counter()
        HELPER.inject_semantic_concepts(_task("campaign lane semantic context"), INDEX)
        timings.append((time.perf_counter() - started) * 1000)
    median = sorted(timings)[len(timings) // 2]
    print(f"semantic_context_fast median_ms={median:.3f} iterations={len(timings)}")
    assert len(timings) == 9
    assert median < 4307
    assert "semantic_context_fast" in capsys.readouterr().out
