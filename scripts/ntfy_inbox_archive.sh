#!/bin/bash
# ntfy_inbox_archive.sh — processed済み+7日超のntfy_inboxメッセージをアーカイブ
# Usage: bash scripts/ntfy_inbox_archive.sh
# Called from shutsujin_departure.sh before watcher startup

set -euo pipefail

_SELF="${BASH_SOURCE[0]}"
case "$_SELF" in
    */*) _SCRIPT_DIR="${_SELF%/*}" ;;
    *) _SCRIPT_DIR="." ;;
esac
SCRIPT_DIR="${_SCRIPT_DIR}/.."
[[ "$SCRIPT_DIR" != /* ]] && SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)"
unset _SELF _SCRIPT_DIR
INBOX="$SCRIPT_DIR/queue/ntfy_inbox.yaml"
ARCHIVE="$SCRIPT_DIR/queue/ntfy_inbox_archive.yaml"
LOCKFILE="${INBOX}.lock"
DAYS=7

# inbox不在なら即終了（エラーなし）
if [ ! -f "$INBOX" ]; then
    echo "[ntfy_inbox_archive] No inbox file found, skipping."
    exit 0
fi

# venv のPython使用（yaml依存）
PYTHON="$SCRIPT_DIR/.venv/bin/python3"
if [ ! -f "$PYTHON" ]; then
    PYTHON="python3"
fi

# flock で排他ロック（L169教訓: atomic操作必須）
(
    flock -w 10 200 || { echo "[ntfy_inbox_archive] ERROR: flock timeout" >&2; exit 1; }
    PYTHONPATH="$SCRIPT_DIR" INBOX_PATH="$INBOX" ARCHIVE_PATH="$ARCHIVE" DAYS="$DAYS" "$PYTHON" - << 'PYEOF'
import yaml, os, sys
from datetime import datetime, timezone, timedelta
from scripts.lib.yaml_atomic import atomic_yaml_write

inbox_path = os.environ['INBOX_PATH']
archive_path = os.environ['ARCHIVE_PATH']
days = int(os.environ['DAYS'])

with open(inbox_path, 'r') as f:
    data = yaml.safe_load(f) or {}

entries = data.get('inbox', [])
if not entries:
    sys.exit(0)

cutoff = datetime.now(timezone(timedelta(hours=9))) - timedelta(days=days)
keep, archive = [], []

for e in entries:
    ts = e.get('timestamp', '')
    try:
        dt = datetime.fromisoformat(str(ts))
        if dt < cutoff and e.get('status') == 'processed':
            archive.append(e)
        else:
            keep.append(e)
    except (ValueError, TypeError):
        keep.append(e)

if not archive:
    sys.exit(0)

# アーカイブに追記
arch_data = {}
if os.path.exists(archive_path):
    with open(archive_path, 'r') as f:
        arch_data = yaml.safe_load(f) or {}

arch_entries = arch_data.get('inbox', [])
arch_entries.extend(archive)
arch_data['inbox'] = arch_entries

atomic_yaml_write(archive_path, arch_data)

# atomic write: inbox (keep only non-archived)
data['inbox'] = keep
atomic_yaml_write(inbox_path, data)

print(f'Archived {len(archive)} old ntfy messages (>{days} days)')
PYEOF
) 200>"$LOCKFILE"
