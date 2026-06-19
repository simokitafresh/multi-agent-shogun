#!/usr/bin/env bash
# BLOCK Codex hook events that violate multi-CLI principles.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS_FILE="${1:-$PROJECT_ROOT/.codex/hooks.json}"

python3 - "$HOOKS_FILE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text())
except FileNotFoundError:
    print(f"BLOCK: missing Codex hooks file: {path}")
    sys.exit(1)
except json.JSONDecodeError as exc:
    print(f"BLOCK: invalid JSON in {path}: {exc}")
    sys.exit(1)

hooks = data.get("hooks", {})
if not isinstance(hooks, dict):
    print(f"BLOCK: hooks must be an object in {path}")
    sys.exit(1)

forbidden = [event for event in ("Stop", "UserPromptSubmit") if event in hooks]
if forbidden:
    print(
        "BLOCK: .codex/hooks.json contains forbidden event(s): "
        + ", ".join(forbidden)
    )
    print(
        "Reason: Codex Stop/UserPromptSubmit must be handled by daemon/startup "
        "equivalents, not Claude hook semantics."
    )
    sys.exit(1)

print("PASS: Codex hooks contain only allowed events")
PY
