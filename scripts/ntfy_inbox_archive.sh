#!/bin/bash
# ntfy_inbox_archive.sh — processed済み+7日超のntfy_inboxメッセージをアーカイブ
# Usage: bash scripts/ntfy_inbox_archive.sh
# Called from shutsujin_departure.sh before watcher startup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

# Python スクリプトを一時ファイルに書き出し（サブシェル内でheredoc使用不可のため）
_PY_SCRIPT=$(mktemp /tmp/ntfy_inbox_archive_XXXXXX.py)
trap 'rm -f "$_PY_SCRIPT"' EXIT

cat > "$_PY_SCRIPT" << 'PYEOF'
import yaml, os, sys, tempfile
from datetime import datetime, timezone, timedelta

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

# atomic write: archive
tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(archive_path), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w') as f:
        yaml.dump(arch_data, f, allow_unicode=True, default_flow_style=False)
    os.replace(tmp_path, archive_path)
except:
    os.unlink(tmp_path)
    raise

# atomic write: inbox (keep only non-archived)
data['inbox'] = keep
tmp_fd2, tmp_path2 = tempfile.mkstemp(dir=os.path.dirname(inbox_path), suffix='.tmp')
try:
    with os.fdopen(tmp_fd2, 'w') as f:
        yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
    os.replace(tmp_path2, inbox_path)
except:
    os.unlink(tmp_path2)
    raise

print(f'Archived {len(archive)} old ntfy messages (>{days} days)')
PYEOF

# flock で排他ロック（L169教訓: atomic操作必須）
(
    flock -w 10 200 || { echo "[ntfy_inbox_archive] ERROR: flock timeout" >&2; exit 1; }
    INBOX_PATH="$INBOX" ARCHIVE_PATH="$ARCHIVE" DAYS="$DAYS" "$PYTHON" "$_PY_SCRIPT"
) 200>"$LOCKFILE"
