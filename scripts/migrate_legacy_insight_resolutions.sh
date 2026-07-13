#!/usr/bin/env bash
# One-shot repair: legacy evidence-less done entries return to pending.
set -euo pipefail

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
root="${_self%/scripts/migrate_legacy_insight_resolutions.sh}"
file="${INSIGHTS_FILE:-$root/queue/insights.yaml}"
source "$root/scripts/lib/yaml_field_set.sh"
[ -f "$file" ] || { echo "ERROR: insights file not found: $file" >&2; exit 1; }

(
  flock -w 5 200 || { echo "ERROR: lock timeout" >&2; exit 1; }
  INSIGHTS_FILE_ENV="$file" python3 - <<'PY'
import os, pathlib, tempfile

path = pathlib.Path(os.environ["INSIGHTS_FILE_ENV"])
lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
changed = 0
starts = [i for i, line in enumerate(lines) if line.startswith("- id: ")]
for n, start in reversed(list(enumerate(starts))):
    end = starts[n + 1] if n + 1 < len(starts) else len(lines)
    block = lines[start:end]
    fields = {}
    for line in block:
        if line.startswith("  ") and ":" in line:
            key, value = line.strip().split(":", 1)
            fields[key] = value.strip().strip('"\'')
    if fields.get("status") not in ("done", "resolved"):
        continue
    if fields.get("resolved_reason") and fields.get("action_artifact") and fields.get("resolved_at"):
        continue
    for i, line in enumerate(block):
        if line.startswith("  status:"):
            block[i] = "  status: pending\n"
        elif line.startswith(("  resolved_at:", "  resolved_reason:", "  action_artifact:")):
            block[i] = ""
    lines[start:end] = block
    changed += 1
fd, tmp = tempfile.mkstemp(prefix=".insights-migrate.", suffix=".tmp", dir=path.parent)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        stream.writelines(lines); stream.flush(); os.fsync(stream.fileno())
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
print(f"migrated={changed}")
PY
) 200>"$(lock_path "$file")"
