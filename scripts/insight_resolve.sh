#!/usr/bin/env bash
# shellcheck disable=SC1091
# insight_resolve.sh — insightをresolvedステータスに変更
# Usage: bash scripts/insight_resolve.sh <insight_id> "<reason>" "<action_artifact>"
# @source: cmd_1502

set -euo pipefail
_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
SCRIPT_DIR="${_self%/*}"
REPO_ROOT="${SCRIPT_DIR%/*}"
unset _self

if [ "$#" -ne 3 ]; then
    echo "Usage: bash scripts/insight_resolve.sh <insight_id> \"<reason>\" \"<action_artifact>\"" >&2
    exit 1
fi

INSIGHT_ID="$1"
REASON="$2"
ACTION_ARTIFACT="$3"
INSIGHTS_FILE="${INSIGHTS_FILE:-$REPO_ROOT/queue/insights.yaml}"

if [ ! -f "$INSIGHTS_FILE" ]; then
    echo "ERROR: insights file not found: $INSIGHTS_FILE" >&2
    exit 1
fi

if [ "${INSIGHT_ALLOW_RESOLVE_WITH_CORRUPT:-0}" != "1" ]; then
    corrupt_dir="$(dirname "$INSIGHTS_FILE")"
    corrupt_base="$(basename "$INSIGHTS_FILE")"
    shopt -s nullglob
    corrupt_leftovers=("${corrupt_dir}/${corrupt_base}.corrupt."*)
    shopt -u nullglob
    if [ "${#corrupt_leftovers[@]}" -gt 0 ]; then
        echo "ERROR: unresolved corrupt insight quarantine remains in queue root: ${#corrupt_leftovers[@]} file(s)" >&2
        exit 1
    fi
fi

if ! grep -q "id: ${INSIGHT_ID}" "$INSIGHTS_FILE"; then
    echo "ERROR: insight not found: $INSIGHT_ID" >&2
    exit 1
fi

if [ -z "${REASON//[[:space:]]/}" ] || [ -z "${ACTION_ARTIFACT//[[:space:]]/}" ]; then
    echo "ERROR: resolved_reason and action_artifact must be non-empty" >&2
    exit 1
fi

# One lock + one atomic replace keeps the four resolution fields indivisible.
# shellcheck source=lib/yaml_field_set.sh
source "$SCRIPT_DIR/lib/yaml_field_set.sh"
(
flock -w 5 200 || { echo "ERROR: lock timeout" >&2; exit 1; }
INSIGHT_ID_ENV="$INSIGHT_ID" REASON_ENV="$REASON" ACTION_ARTIFACT_ENV="$ACTION_ARTIFACT" \
INSIGHTS_FILE_ENV="$INSIGHTS_FILE" RESOLVED_AT_ENV="$(date -Iseconds)" python3 - <<'PY'
import json
import os
import pathlib
import tempfile
import time

path = pathlib.Path(os.environ["INSIGHTS_FILE_ENV"])
lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
target_id = os.environ["INSIGHT_ID_ENV"]
start = next((i for i, line in enumerate(lines) if line.strip() == f"- id: {target_id}"), None)
if start is None:
    raise SystemExit(f"ERROR: insight not found: {os.environ['INSIGHT_ID_ENV']}")
end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("- id: ")), len(lines))
fields = {
    "status": "resolved",
    "resolved_reason": os.environ["REASON_ENV"],
    "action_artifact": os.environ["ACTION_ARTIFACT_ENV"],
    "resolved_at": os.environ["RESOLVED_AT_ENV"],
}
block = lines[start:end]
for key, value in fields.items():
    encoded = value if key == "status" else json.dumps(value, ensure_ascii=False)
    replacement = f"  {key}: {encoded}\n"
    index = next((i for i, line in enumerate(block) if line.startswith(f"  {key}:")), None)
    if index is None:
        block.append(replacement)
    else:
        block[index] = replacement
lines[start:end] = block
fd, tmp = tempfile.mkstemp(prefix=".insights-resolve.", suffix=".tmp", dir=path.parent)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        stream.writelines(lines)
        stream.flush()
        os.fsync(stream.fileno())
    sleep_sec = float(os.environ.get("INSIGHT_TEST_SLEEP_BEFORE_REPLACE", "0") or "0")
    if sleep_sec > 0:
        time.sleep(sleep_sec)
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
PY
) 200>"$(lock_path "$INSIGHTS_FILE")"

echo "OK: $INSIGHT_ID → resolved"
