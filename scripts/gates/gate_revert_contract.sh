#!/usr/bin/env bash
# gate_revert_contract.sh — enforce the notification/re-measurement revert lane
# Usage: gate_revert_contract.sh check <command>
set -euo pipefail

command_text="${2:-}"
if [[ "${1:-}" != "check" || -z "$command_text" ]]; then
    echo "Usage: gate_revert_contract.sh check <command>" >&2
    exit 2
fi

python3 - "$command_text" <<'PY'
import shlex
import sys

command = sys.argv[1]
try:
    tokens = shlex.split(command)
except ValueError as exc:
    print(f"BLOCK: malformed command: {exc}")
    raise SystemExit(1)

segments = []
current = []
for token in tokens:
    if token in {"&&", "||", ";", "|"}:
        if current:
            segments.append(current)
        current = []
    else:
        current.append(token)
if current:
    segments.append(current)

for segment in segments:
    if len(segment) < 2 or segment[0].split("/")[-1] != "git":
        continue
    if segment[1] != "revert":
        continue
    if any("revert_with_receipt.sh" in value for value in segment):
        continue
    print("BLOCK: direct git revert is not allowed; use scripts/revert_with_receipt.sh")
    raise SystemExit(1)

print("PASS: revert command is not a direct git revert")
PY
