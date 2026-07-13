#!/usr/bin/env bash
# Restore complete, missing insight blocks from the newest corrupt tail by ID.
set -euo pipefail

self="${BASH_SOURCE[0]}"
[[ "$self" != /* ]] && self="$PWD/$self"
root="${self%/scripts/restore_insights_from_corrupt.sh}"
live="${INSIGHTS_FILE:-$root/queue/insights.yaml}"
archive="${INSIGHT_CORRUPT_ARCHIVE_DIR:-$root/queue/archive/insights_corrupt}"
artifact="${INSIGHT_RESTORE_ARTIFACT:-$archive/restore-$(date +%Y%m%d-%H%M%S).json}"
source "$root/scripts/lib/yaml_field_set.sh"

latest="$(find "$archive" -maxdepth 1 -type f -name 'insights.yaml.corrupt.*' -printf '%T@ %p\n' | sort -nr | head -1 | cut -d' ' -f2-)"
[[ -n "$latest" && -f "$latest" ]] || { echo "ERROR: corrupt fragment not found" >&2; exit 1; }

(
  flock -w 5 200 || { echo "ERROR: lock timeout" >&2; exit 1; }
  LIVE="$live" FRAGMENT="$latest" ARTIFACT="$artifact" python3 - <<'PY'
import hashlib, json, os, pathlib, re, tempfile, yaml

live = pathlib.Path(os.environ['LIVE'])
fragment = pathlib.Path(os.environ['FRAGMENT'])
artifact = pathlib.Path(os.environ['ARTIFACT'])

def blocks(text):
    lines = text.splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if line.startswith('- id: ')]
    return [lines[start:(starts[n + 1] if n + 1 < len(starts) else len(lines))]
            for n, start in enumerate(starts)]

before_text = live.read_text(encoding='utf-8')
before_rows = yaml.safe_load(before_text).get('insights') or []
before_ids = [str(row.get('id')) for row in before_rows]
existing = set(before_ids)
restored = []
append = []
for block in blocks(fragment.read_text(encoding='utf-8')):
    parsed = yaml.safe_load(''.join(block))
    if not isinstance(parsed, list) or len(parsed) != 1 or not isinstance(parsed[0], dict):
        continue
    entry_id = str(parsed[0].get('id') or '')
    if not entry_id or entry_id in existing:
        continue
    append.extend(block)
    restored.append(entry_id)
    existing.add(entry_id)

after_text = before_text
if append:
    if not after_text.endswith('\n'):
        after_text += '\n'
    after_text += ''.join(append)
    fd, tmp = tempfile.mkstemp(prefix='.insights-restore.', suffix='.tmp', dir=live.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            stream.write(after_text); stream.flush(); os.fsync(stream.fileno())
        os.replace(tmp, live)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

after_rows = yaml.safe_load(live.read_text(encoding='utf-8')).get('insights') or []
after_ids = [str(row.get('id')) for row in after_rows]
duplicates = sorted({item for item in after_ids if after_ids.count(item) > 1})
record = {
    'live_file': str(live), 'fragment': str(fragment),
    'before_count': len(before_ids), 'after_count': len(after_ids),
    'before_ids_sha256': hashlib.sha256('\n'.join(sorted(before_ids)).encode()).hexdigest(),
    'after_ids_sha256': hashlib.sha256('\n'.join(sorted(after_ids)).encode()).hexdigest(),
    'added_ids': sorted(set(after_ids) - set(before_ids)),
    'removed_ids': sorted(set(before_ids) - set(after_ids)),
    'restored_ids': restored, 'duplicate_ids': duplicates,
}
artifact.write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
if duplicates or record['removed_ids']:
    raise SystemExit('ERROR: restore invariant failed')
print(f"restored={len(restored)} before={len(before_ids)} after={len(after_ids)} artifact={artifact}")
PY
) 200>"$(lock_path "$live")"

# A restored legacy/incomplete resolved entry must return to pending.
INSIGHTS_FILE="$live" bash "$root/scripts/migrate_legacy_insight_resolutions.sh"
