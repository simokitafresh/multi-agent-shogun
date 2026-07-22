#!/usr/bin/env bats
# test_necessity: related-lesson injection must isolate one malformed source,
# preserve all healthy-source lessons, and identify the rejected source.

setup() {
    export REPO_ROOT
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "mixed healthy and malformed lesson sources isolate only malformed source" {
    run python3 - "$REPO_ROOT" <<'PY'
import importlib.util
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
path = root / "scripts/lib/deploy_task_related_lessons_fast.py"
spec = importlib.util.spec_from_file_location("selector", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

healthy = b"lessons:\n- id: L901\n  title: healthy one\n  summary: yaml lesson injection\n  status: confirmed\n- id: L902\n  title: healthy two\n  summary: second healthy lesson\n  status: confirmed\n"
broken = b"lessons:\n- id: L999\n  title: broken\n  summary: 'unterminated\n"
errors = []
lessons = module.parse_lessons(
    [healthy, broken], ["infra", "dm-signal"],
    ["projects/infra/lessons.yaml", "projects/dm-signal/lessons.yaml"], errors,
)
assert [item["id"] for item in lessons] == ["L901", "L902"]
assert len(errors) == 1
assert errors[0]["level"] == "ERROR"
assert errors[0]["source_project"] == "dm-signal"
assert errors[0]["source_path"] == "projects/dm-signal/lessons.yaml"
print(json.dumps({"healthy": len(lessons), "broken": 0, "errors": errors}, ensure_ascii=False))
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *'"healthy": 2'* ]]
    [[ "$output" == *'"broken": 0'* ]]
    [[ "$output" == *'"level": "ERROR"'* ]]
    [[ "$output" == *'projects/dm-signal/lessons.yaml'* ]]
}
