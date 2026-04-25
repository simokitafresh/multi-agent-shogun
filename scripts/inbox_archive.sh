#!/bin/bash
# inbox_archive.sh — read:trueメッセージをアーカイブに退避
# Usage: bash scripts/inbox_archive.sh <agent_id>
# Example: bash scripts/inbox_archive.sh karo

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/lock_path.sh" 2>/dev/null \
    || lock_path() { printf '/tmp/shogun_lock_%s.lock' "$(printf '%s' "$1" | md5sum | cut -c1-16)"; }
AGENT="$1"

if [ -z "$AGENT" ]; then
    echo "Usage: inbox_archive.sh <agent_id>" >&2
    exit 1
fi

INBOX="$SCRIPT_DIR/queue/inbox/${AGENT}.yaml"
LOCKFILE="$(lock_path "$INBOX")"

if [ ! -f "$INBOX" ]; then
    echo "[inbox_archive] No inbox file for $AGENT" >&2
    exit 0
fi

ARCHIVE_DIR="$SCRIPT_DIR/archive/inbox"
mkdir -p "$ARCHIVE_DIR"

DATE_STAMP=$(date +%Y%m%d)
ARCHIVE_FILE="$ARCHIVE_DIR/${AGENT}_${DATE_STAMP}.yaml"

# Atomic archive with flock (same lock as inbox_write.sh)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 5 200 || exit 1

        INBOX_PATH="$INBOX" ARCHIVE_PATH="$ARCHIVE_FILE" AGENT_ID="$AGENT" python3 -c "
import yaml, sys, os, tempfile

inbox_path = os.environ['INBOX_PATH']
archive_path = os.environ['ARCHIVE_PATH']
agent_id = os.environ['AGENT_ID']

# Load inbox
with open(inbox_path, encoding='utf-8') as f:
    data = yaml.safe_load(f)

if not data or not data.get('messages'):
    print('[inbox_archive] No messages in inbox')
    sys.exit(0)

msgs = data['messages']
unread = [m for m in msgs if not m.get('read', False)]
read_msgs = [m for m in msgs if m.get('read', False)]

print(f'[inbox_archive] {agent_id}: total={len(msgs)}, read={len(read_msgs)}, unread={len(unread)}')

if not read_msgs:
    print('[inbox_archive] No read messages to archive')
    sys.exit(0)

if unread:
    print(f'[inbox_archive] NOTE: {len(unread)} unread messages will be preserved')

# yaml.dump禁止(CLAUDE.md): 手動YAML構築でデータ消失を防止
def _sv(v):
    if isinstance(v, bool): return str(v).lower()
    s = str(v)
    if '\n' in s:
        return '|-\n' + '\n'.join('    ' + ln for ln in s.split('\n'))
    sq = chr(39)
    return sq + s.replace(sq, sq+sq) + sq

def _write_msg_entries(f, messages):
    for m in messages:
        keys = ['content', 'from', 'id', 'read', 'timestamp', 'type']
        extra = sorted(k for k in m if k not in keys)
        first = True
        for k in keys + extra:
            if k not in m: continue
            p = '- ' if first else '  '
            first = False
            f.write(f'{p}{k}: {_sv(m[k])}\n')

def _write_messages(f, messages):
    if not messages:
        f.write('messages: []\n')
    else:
        f.write('messages:\n')
        _write_msg_entries(f, messages)

# Write archive (append-only: avoid loading existing archive for O(k) performance)
if os.path.exists(archive_path):
    # Existing archive: append entries directly (O(k), no full reload)
    with open(archive_path, 'a', encoding='utf-8') as f:
        _write_msg_entries(f, read_msgs)
else:
    # New archive file: create atomically with header
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(archive_path), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
            f.write('messages:\n')
            _write_msg_entries(f, read_msgs)
        os.replace(tmp_path, archive_path)
    except Exception:
        os.unlink(tmp_path)
        raise

# Rewrite inbox with unread only (atomic)
new_data = {'messages': unread} if unread else {'messages': []}
tmp_fd2, tmp_path2 = tempfile.mkstemp(dir=os.path.dirname(inbox_path), suffix='.tmp')
try:
    with os.fdopen(tmp_fd2, 'w', encoding='utf-8') as f:
        _write_messages(f, new_data['messages'])
    os.replace(tmp_path2, inbox_path)
except Exception:
    os.unlink(tmp_path2)
    raise

print(f'[inbox_archive] Archived {len(read_msgs)} messages to {archive_path}')
" || exit 1

    ) 200>"$LOCKFILE"; then
        exit 0
    else
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[inbox_archive] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[inbox_archive] Failed to acquire lock after $max_attempts attempts" >&2
            exit 1
        fi
    fi
done
