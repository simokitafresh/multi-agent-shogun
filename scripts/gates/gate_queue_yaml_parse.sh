#!/usr/bin/env bash
# gate_queue_yaml_parse.sh — queue/ operational YAML parse guard.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT_DIR="${QUEUE_YAML_PARSE_ROOT:-$SCRIPT_DIR}"

python3 - "$ROOT_DIR" "$SCRIPT_DIR/scripts/lib" <<'PY'
import glob
import sys
from pathlib import Path

import yaml

sys.path.insert(0, sys.argv[2])
from yaml_safe_read import safe_load_retry  # noqa: E402

root = Path(sys.argv[1])
patterns = [
    "queue/shogun_to_karo.yaml",
    "queue/pending_decisions.yaml",
    "queue/insights.yaml",
    "queue/inbox/*.yaml",
    "queue/tasks/*.yaml",
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

def load(path):
    # cmd_karo_hotfix_queue_yaml_atomicity_202607110113:
    # safe_load_retry()(scripts/lib/yaml_safe_read.py)がFileNotFoundErrorのみ
    # リトライする。YAMLError/他のOSErrorはそのまま即エラーにする
    # (実際の破損を握りつぶさないため)。
    try:
        return safe_load_retry(path), None
    except FileNotFoundError as exc:
        return None, ("io_error", exc)
    except yaml.YAMLError as exc:
        return None, ("yaml_error", exc)
    except OSError as exc:
        return None, ("io_error", exc)


# Reports are already format-checked before completion.  At startup only the
# report named by a live task is operational; reparsing hundreds of historical
# compatibility files on WSL 9p made this gate take minutes.
for task_path in [path for path in paths if path.relative_to(root).as_posix().startswith("queue/tasks/")]:
    document, err = load(task_path)
    if err is not None or not isinstance(document, dict):
        continue
    task = document.get("task") if isinstance(document.get("task"), dict) else document
    report_value = str(task.get("report_path") or "").strip()
    if not report_value:
        continue
    report_path = Path(report_value)
    if not report_path.is_absolute():
        report_path = root / report_path
    try:
        rel = report_path.relative_to(root).as_posix()
    except ValueError:
        continue
    if rel.startswith("queue/reports/") and rel.endswith(".yaml") and rel not in seen:
        seen.add(rel)
        paths.append(report_path)


errors = []
for path in sorted(paths):
    rel = path.relative_to(root).as_posix()
    _, err = load(path)
    if err is None:
        continue
    kind, exc = err
    if kind == "yaml_error":
        mark = getattr(exc, "problem_mark", None) or getattr(exc, "context_mark", None)
        if mark is not None:
            location = f"{rel}:{mark.line + 1}:{mark.column + 1}"
        else:
            location = f"{rel}:line_unknown"
        problem = getattr(exc, "problem", None) or str(exc).splitlines()[0]
        errors.append(f"{location}: {problem}")
    else:
        errors.append(f"{rel}:io_error: {exc}")

if errors:
    print("ALERT: queue YAML parse error")
    for item in errors:
        print(f"  - {item}")
    sys.exit(1)

print(f"OK: queue YAML parse clean ({len(paths)} files)")
PY
