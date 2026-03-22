#!/bin/bash
# add_injection_count.sh — 全教訓エントリにinjection_count: 0を追加（ワンショット）
# Usage: bash scripts/oneshot/add_injection_count.sh
# 冪等: 既にinjection_countがあるエントリはスキップ

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

add_injection_count() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "SKIP: $file not found"
        return 0
    fi

    local lockfile="${file}.lock"

    (
        flock -w 10 200 || { echo "ERROR: lock timeout for $file" >&2; exit 1; }

        python3 << PYEOF
import yaml, os, tempfile

cache_file = "$file"

with open(cache_file, encoding='utf-8') as f:
    content = f.read()

data = yaml.safe_load(content)
if not data or 'lessons' not in data:
    print(f'SKIP: No lessons in {cache_file}')
    raise SystemExit(0)

added = 0
skipped = 0
for lesson in data['lessons']:
    if 'injection_count' not in lesson:
        lesson['injection_count'] = 0
        added += 1
    else:
        skipped += 1

if added == 0:
    print(f'OK: {cache_file} — all {skipped} entries already have injection_count')
    raise SystemExit(0)

# Preserve header comments
header_lines = []
for line in content.split('\n'):
    if line.startswith('#'):
        header_lines.append(line)
    else:
        break
header = '\n'.join(header_lines) + '\n' if header_lines else ''

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(cache_file), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
        f.write(header)
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2, sort_keys=False)
    os.replace(tmp_path, cache_file)
except Exception:
    os.unlink(tmp_path)
    raise

print(f'OK: {cache_file} — added injection_count to {added} entries (skipped {skipped})')
PYEOF

    ) 200>"$lockfile"
}

echo "=== injection_count追加 ==="
add_injection_count "$SCRIPT_DIR/projects/infra/lessons.yaml"
add_injection_count "$SCRIPT_DIR/projects/dm-signal/lessons.yaml"
echo "=== 完了 ==="
