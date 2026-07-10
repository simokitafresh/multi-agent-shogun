#!/usr/bin/env bash
# gate_queue_yaml_parse.sh — queue/ operational YAML parse guard.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT_DIR="${QUEUE_YAML_PARSE_ROOT:-$SCRIPT_DIR}"

python3 - "$ROOT_DIR" <<'PY'
import glob
import sys
import time
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


def load(path):
    # cmd_karo_hotfix_queue_yaml_atomicity_202607110113:
    # yaml_field_set.shの公開はmktemp+mv(atomic rename)へ修正済みだが、WSL2 drvfs越しの
    # renameはPOSIX同様の完全な原子性を保証しない(実測: 数百readに1回、rename直後の
    # 一瞬だけ宛先パスがENOENTになる。中身が壊れるのではなく一時的に不在になるだけ)。
    # FileNotFoundErrorのみ1回だけ短い待機を挟んで再読込し、それでも消えている場合や
    # YAMLError/他のOSErrorはそのまま即エラーにする(実際の破損を握りつぶさないため)。
    try:
        with path.open(encoding="utf-8") as fh:
            return yaml.safe_load(fh), None
    except FileNotFoundError:
        time.sleep(0.05)
        try:
            with path.open(encoding="utf-8") as fh:
                return yaml.safe_load(fh), None
        except FileNotFoundError as exc:
            return None, ("io_error", exc)
        except yaml.YAMLError as exc:
            return None, ("yaml_error", exc)
        except OSError as exc:
            return None, ("io_error", exc)
    except yaml.YAMLError as exc:
        return None, ("yaml_error", exc)
    except OSError as exc:
        return None, ("io_error", exc)


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
