#!/bin/bash
# inbox_archive.sh — read:trueメッセージをアーカイブに退避
# Usage: bash scripts/inbox_archive.sh <agent_id>
# Example: bash scripts/inbox_archive.sh karo

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT="$1"

if [ -z "$AGENT" ]; then
    echo "Usage: inbox_archive.sh <agent_id>" >&2
    exit 1
fi

INBOX="$SCRIPT_DIR/queue/inbox/${AGENT}.yaml"
LOCKFILE="${INBOX}.lock"

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

        python3 -c "
import yaml, sys, os, tempfile

inbox_path = '$INBOX'
archive_path = '$ARCHIVE_FILE'

# Load inbox
with open(inbox_path) as f:
    data = yaml.safe_load(f)

if not data or not data.get('messages'):
    print('[inbox_archive] No messages in inbox')
    sys.exit(0)

msgs = data['messages']
unread = [m for m in msgs if not m.get('read', False)]
read_msgs = [m for m in msgs if m.get('read', False)]

print(f'[inbox_archive] $AGENT: total={len(msgs)}, read={len(read_msgs)}, unread={len(unread)}')

if not read_msgs:
    print('[inbox_archive] No read messages to archive')
    sys.exit(0)

if unread:
    print(f'[inbox_archive] NOTE: {len(unread)} unread messages will be preserved')

# Append to archive file
if os.path.exists(archive_path):
    with open(archive_path) as f:
        archive_data = yaml.safe_load(f) or {}
else:
    archive_data = {}

if not archive_data.get('messages'):
    archive_data['messages'] = []

archive_data['messages'].extend(read_msgs)

# Write archive (atomic)
tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(archive_path), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w') as f:
        yaml.dump(archive_data, f, default_flow_style=False, allow_unicode=True, indent=2)
    os.replace(tmp_path, archive_path)
except:
    os.unlink(tmp_path)
    raise

# Rewrite inbox with unread only (atomic)
new_data = {'messages': unread} if unread else {'messages': []}
tmp_fd2, tmp_path2 = tempfile.mkstemp(dir=os.path.dirname(inbox_path), suffix='.tmp')
try:
    with os.fdopen(tmp_fd2, 'w') as f:
        yaml.dump(new_data, f, default_flow_style=False, allow_unicode=True, indent=2)
    os.replace(tmp_path2, inbox_path)
except:
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
