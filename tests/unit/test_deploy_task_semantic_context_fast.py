"""Contract tests for the F1 semantic-context fast helper."""

from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
import textwrap
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


def _cache_fixture(tmp_path: Path) -> tuple[dict[str, str], Path, Path, Path]:
    index_path = tmp_path / "index.md"
    index_path.write_bytes(INDEX)
    skills_root = tmp_path / "skills"
    skill_dir = skills_root / "fixture-skill"
    skill_dir.mkdir(parents=True)
    (skill_dir / "SKILL.md").write_text(
        "# fixture skill\nTRIGGER: fixture trigger\n", encoding="utf-8"
    )
    counter = tmp_path / "producer.count"
    mode = tmp_path / "producer.mode"
    mode.write_text("hit\n", encoding="utf-8")
    search = tmp_path / "semantic_search_fixture.sh"
    search.write_text(
        textwrap.dedent(
            f"""\
            #!/bin/bash
            count=0
            [ ! -f {str(counter)!r} ] || count=$(<{str(counter)!r})
            printf '%s\\n' "$((count + 1))" > {str(counter)!r}
            mode=$(<{str(mode)!r})
            case "$mode" in
              no_match) printf 'NO_MATCH: fixture\\n'; exit 1 ;;
              fail) exit 7 ;;
            esac
            printf '%s\\n' \\
              '## fixture_concept — Fixture concept' \\
              'matched: fixture trigger' \\
              'aliases: fixture trigger' \\
              'resources:' \\
              '- skills: fixture-skill' \\
              '- file: `docs/research/fixture.md`'
            """
        ),
        encoding="utf-8",
    )
    search.chmod(0o755)
    env = os.environ.copy()
    env.update(
        {
            "DEPLOY_TASK_LIB_ONLY": "1",
            "SEMANTIC_INDEX_PATH": str(index_path),
            "SEMANTIC_DISABLE_CAUSAL": "1",
            "SEMANTIC_DISABLE_MEMORY_DB": "1",
            "SEMANTIC_DISABLE_LLM": "1",
            "SEMANTIC_DISABLE_SEARCH_LOG": "1",
            "SEMANTIC_MEMORY_DB_PATH": str(tmp_path / "absent-memory.db"),
            "DEPLOY_TASK_SEMANTIC_SEARCH_SCRIPT": str(search),
            "DEPLOY_TASK_SKILLS_ROOT": str(skills_root),
            "DEPLOY_TASK_WAVE_CACHE_DIR": str(tmp_path / "wave-cache"),
        }
    )
    return env, index_path, skill_dir / "SKILL.md", mode


def _run_cached_injection(
    tmp_path: Path,
    env: dict[str, str],
    *,
    project: str = "infra",
    suffix: str,
) -> subprocess.CompletedProcess[str]:
    task_path = tmp_path / f"task-{suffix}.yaml"
    task_path.write_text(
        "task:\n"
        f'  project: "{project}"\n'
        '  purpose: "fixture trigger cache contract"\n'
        '  target_path: "scripts/fixture.py"\n'
        '  description: "fixture"\n',
        encoding="utf-8",
    )
    return subprocess.run(
        [
            "bash",
            "-c",
            'source scripts/deploy_task.sh; log(){ printf "[TEST] %s\\n" "$1" >&2; }; '
            'inject_semantic_concepts "$1"',
            "bash",
            str(task_path),
        ],
        cwd=ROOT,
        env=env,
        check=True,
        capture_output=True,
        text=True,
    )


# test_necessity: a positive semantic result is reused only for the exact purpose/target/project and is invalidated by index or skill source-generation changes.
def test_positive_cache_key_and_source_generation_invalidation(tmp_path: Path) -> None:
    env, index_path, skill_path, _mode = _cache_fixture(tmp_path)
    counter = tmp_path / "producer.count"

    _run_cached_injection(tmp_path, env, suffix="cold")
    warm = _run_cached_injection(tmp_path, env, suffix="warm")
    assert counter.read_text(encoding="utf-8").strip() == "1"
    assert "wave_cache: hit namespace=semantic_context_v2" in warm.stderr

    _run_cached_injection(tmp_path, env, project="dm-signal", suffix="project")
    assert counter.read_text(encoding="utf-8").strip() == "2"

    index_path.write_bytes(INDEX + b"\n<!-- generation two -->\n")
    _run_cached_injection(tmp_path, env, suffix="index-generation")
    assert counter.read_text(encoding="utf-8").strip() == "3"

    skill_path.write_text(
        "# fixture skill generation two\nTRIGGER: fixture trigger\n", encoding="utf-8"
    )
    _run_cached_injection(tmp_path, env, suffix="skill-generation")
    assert counter.read_text(encoding="utf-8").strip() == "4"


# test_necessity: NO_MATCH and producer failure never create a reusable semantic cache entry, so every later request retries the current two-layer contract.
@pytest.mark.parametrize("mode_value", ["no_match", "fail"])
def test_no_match_and_failure_are_not_cached(tmp_path: Path, mode_value: str) -> None:
    env, _index_path, _skill_path, mode = _cache_fixture(tmp_path)
    counter = tmp_path / "producer.count"
    mode.write_text(mode_value + "\n", encoding="utf-8")

    first = _run_cached_injection(tmp_path, env, suffix=f"{mode_value}-one")
    second = _run_cached_injection(tmp_path, env, suffix=f"{mode_value}-two")
    assert counter.read_text(encoding="utf-8").strip() == "2"
    assert "NO_MATCH" in first.stderr
    assert "NO_MATCH" in second.stderr
    assert not list((tmp_path / "wave-cache").glob("*.snapshot"))
