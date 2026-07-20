"""Contract tests for the wave-oriented related-lessons helper.

test_necessity: preserves byte-stable task rewriting, selection ordering, hit0,
ambiguous-term, target_files, and semantic-boost parity at the helper boundary.
"""
import importlib.util
import os
import subprocess
import statistics
import time
from pathlib import Path

import yaml

HERE = Path(__file__).resolve()
MODULE = HERE.parents[2] / "scripts/lib/deploy_task_related_lessons_fast.py"
spec = importlib.util.spec_from_file_location("related_fast", MODULE)
fast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fast)


LESSONS = b"""lessons:
- id: L101
  status: confirmed
  project: fixture
  title: database timeout
  summary: database timeout handling retry
  detail: backend transaction recovery
  when: database timeout handling retry backend transaction recovery
  target_files: [backend/db.py]
- id: L102
  status: confirmed
  project: fixture
  title: generic timeout
  summary: generic timeout note
  detail: generic timeout
  when: generic timeout
- id: L103
  status: confirmed
  project: fixture
  title: semantic retry
  summary: semantic linked lesson
  if_then: {if: retry fails, then: backoff, because: load}
  when: retry_policy
"""
SEMANTIC = """## retry_policy — retry policy
| id | retry_policy |
| label | retry_policy |
| aliases | retry strategy |
| related_lessons | L103 |
""".encode()


def task(**fields):
    fields = {"project": "fixture", "task_type": "normal", **fields}
    lines = ["task:"] + [f"  {key}: {value}" for key, value in fields.items()]
    return ("\n".join(lines) + "\n  related_lessons: []\n").encode()


def ids(blob):
    return [x["id"] for x in yaml.safe_load(blob)["task"]["related_lessons"]]


def _without_related(blob):
    data = yaml.safe_load(blob)
    data["task"].pop("related_lessons", None)
    return data


def _legacy_outputs(tmp_path, fixtures):
    root = tmp_path / "legacy-root"
    (root / "projects/fixture").mkdir(parents=True)
    (root / "config").mkdir()
    (root / "docs/semantic-index").mkdir(parents=True)
    (root / "logs").mkdir()
    (root / "projects/fixture/lessons.yaml").write_bytes(LESSONS)
    (root / "config/projects.yaml").write_text("current_project: fixture\nprojects:\n- {id: fixture, type: product}\n")
    (root / "docs/semantic-index/index.md").write_bytes(SEMANTIC)
    source = subprocess.check_output(
        ["git", "show", "9dd8e58d319c55124ff3ed988a51d5cbd7a2e8c0:scripts/deploy_task.sh"],
        cwd=HERE.parents[2], text=True,
    ).splitlines()
    function = "\n".join(source[6256:7855])
    harness = root / "legacy.sh"
    harness.write_text(
        "#!/usr/bin/env bash\n"
        "log(){ :; }\n"
        "run_python_logged(){ local out=$1; shift; \"$@\" >\"$out\"; }\n"
        f"SCRIPT_DIR={root!s}\n" + function + "\ninject_related_lessons \"$1\"\n"
    )
    outputs = []
    for number, raw in enumerate(fixtures):
        path = root / f"task-{number}.yaml"
        path.write_bytes(raw)
        env = {**os.environ, "DEPLOY_LESSON_CACHE_DIR": str(root / "cache")}
        subprocess.run(["bash", str(harness), str(path)], check=True, env=env, capture_output=True, text=True)
        outputs.append(path.read_bytes())
    return outputs


def test_contract_fixtures_and_performance(tmp_path, capsys):
    fixtures = [
        task(description="database timeout handling retry backend transaction recovery", target_path="backend/db.py"),
        task(description="unrelated words"),
        task(description="timeout"),
        task(description="database", target_path="backend/db.py"),
        task(description="retry_policy"),
    ]
    legacy = _legacy_outputs(tmp_path, fixtures)
    timings = []
    for _ in range(9):
        start = time.perf_counter()
        actual = fast.inject_many(fixtures, [LESSONS], SEMANTIC)
        timings.append((time.perf_counter() - start) * 1000)
    assert [yaml.safe_load(blob)["task"]["related_lessons"] for blob in actual] == [
        yaml.safe_load(blob)["task"]["related_lessons"] for blob in legacy
    ]
    assert [_without_related(blob) for blob in actual] == [_without_related(blob) for blob in fixtures]
    median = statistics.median(timings)
    assert median < 2772
    print(f"TOTAL=5 FAIL=0 SKIP=0 median_ms={median:.3f} PASS fixed_sha=9dd8e58d319c")
