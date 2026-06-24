#!/usr/bin/env bash
# Validate Codex hook events against multi-CLI adapter principles.
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

forbidden = [event for event in ("Stop",) if event in hooks]
if forbidden:
    print(
        "BLOCK: .codex/hooks.json contains forbidden event(s): "
        + ", ".join(forbidden)
    )
    print(
        "Reason: Codex Stop must remain daemon/safe-adapter controlled until "
        "block/re-prompt behavior is verified for this system."
    )
    sys.exit(1)

def command_hooks(event):
    out = []
    for group in hooks.get(event, []):
        for hook in group.get("hooks", []):
            if isinstance(hook, dict):
                out.append(hook.get("command", ""))
    return out

session_cmds = command_hooks("SessionStart")
if hooks.get("SessionStart") and not any("codex_session_start.sh" in c for c in session_cmds):
    print("BLOCK: Codex SessionStart must use codex_session_start.sh adapter")
    sys.exit(1)

prompt_cmds = command_hooks("UserPromptSubmit")
if hooks.get("UserPromptSubmit"):
    adapter_cmds = [c for c in prompt_cmds if "codex_user_prompt_submit.sh" in c]
    if len(prompt_cmds) != 1 or len(adapter_cmds) != 1:
        print(
            "BLOCK: Codex UserPromptSubmit must be exactly one sequential adapter "
            "(codex_user_prompt_submit.sh). Codex runs multiple same-event hooks concurrently."
        )
        sys.exit(1)

print("PASS: Codex hooks match adapter policy")
PY
