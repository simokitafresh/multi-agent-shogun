#!/usr/bin/env bash
# gate_queue_yaml_parse.sh — queue/ operational YAML parse guard.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT_DIR="${QUEUE_YAML_PARSE_ROOT:-$SCRIPT_DIR}"

python3 - "$ROOT_DIR" <<'PY'
import glob
import sys
from pathlib import Path

import yaml

root = Path(sys.argv[1])
patterns = [
    "queue/shogun_to_karo.yaml",
    "queue/pending_decisions.yaml",
    "queue/insights.yaml",
    "queue/inbox/*.yaml",
    "queue/tasks/*.yaml",
    "queue/reports/*.yaml",
]

paths = []
seen = set()
for pattern in patterns:
    for raw in glob.glob(str(root / pattern)):
        path = Path(raw)
        if path.name.endswith(".lock") or path.name.startswith("."):
            continue
        rel = path.relative_to(root).as_posix()
        if rel in seen:
            continue
        seen.add(rel)
        paths.append(path)

errors = []
for path in sorted(paths):
    rel = path.relative_to(root).as_posix()
    try:
        with path.open(encoding="utf-8") as fh:
            yaml.safe_load(fh)
    except yaml.YAMLError as exc:
        mark = getattr(exc, "problem_mark", None) or getattr(exc, "context_mark", None)
        if mark is not None:
            location = f"{rel}:{mark.line + 1}:{mark.column + 1}"
        else:
            location = f"{rel}:line_unknown"
        problem = getattr(exc, "problem", None) or str(exc).splitlines()[0]
        errors.append(f"{location}: {problem}")
    except OSError as exc:
        errors.append(f"{rel}:io_error: {exc}")

if errors:
    print("ALERT: queue YAML parse error")
    for item in errors:
        print(f"  - {item}")
    sys.exit(1)

print(f"OK: queue YAML parse clean ({len(paths)} files)")
PY
