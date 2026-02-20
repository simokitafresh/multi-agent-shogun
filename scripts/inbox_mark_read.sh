#!/bin/bash
# inbox_mark_read.sh — inboxメッセージの既読化（排他ロック＋アトミック書込み）
# Usage: bash scripts/inbox_mark_read.sh <agent_id> [msg_id]
#   msg_id指定: そのメッセージのみ read:true に変更
#   msg_id省略: 全 read:false を read:true に変更
#
# inbox_write.sh と同じ lockfile (${INBOX}.lock) で flock を取得し、
# mkstemp + os.replace によるアトミック書込みで Lost Update を防止する。
# Claude Code の Edit tool による既読化を置き換える。

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_ID="$1"
MSG_ID="${2:-}"

if [ -z "$AGENT_ID" ]; then
    echo "Usage: inbox_mark_read.sh <agent_id> [msg_id]" >&2
    exit 1
fi

INBOX="$SCRIPT_DIR/queue/inbox/${AGENT_ID}.yaml"
LOCKFILE="${INBOX}.lock"

if [ ! -f "$INBOX" ]; then
    echo "[inbox_mark_read] No inbox file for $AGENT_ID" >&2
    exit 0
fi

# Atomic mark-read with flock (3 retries, same pattern as inbox_write.sh)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 5 200 || exit 1

        python3 -c "
import yaml, sys, os, tempfile

inbox_path = '$INBOX'
msg_id = '$MSG_ID'

try:
    with open(inbox_path) as f:
        data = yaml.safe_load(f)

    if not data or not data.get('messages'):
        print('[inbox_mark_read] No messages in inbox')
        sys.exit(0)

    changed = 0
    for m in data['messages']:
        if m.get('read', False):
            continue
        if msg_id and m.get('id') != msg_id:
            continue
        m['read'] = True
        changed += 1

    if changed == 0:
        if msg_id:
            print(f'[inbox_mark_read] msg_id={msg_id} not found or already read')
        else:
            print('[inbox_mark_read] No unread messages')
        sys.exit(0)

    # Atomic write: tmp file + rename (same pattern as inbox_write.sh)
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(inbox_path), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, inbox_path)
    except:
        os.unlink(tmp_path)
        raise

    print(f'[inbox_mark_read] Marked {changed} message(s) as read for $AGENT_ID')

except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" || exit 1

    ) 200>"$LOCKFILE"; then
        exit 0
    else
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[inbox_mark_read] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[inbox_mark_read] Failed to acquire lock after $max_attempts attempts" >&2
            exit 1
        fi
    fi
done
