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

# Validate agent_id: only lowercase letters and underscores allowed (path traversal prevention)
if [[ ! "$AGENT_ID" =~ ^[a-z_]+$ ]]; then
    echo "ERROR: Invalid agent_id '$AGENT_ID'. Only lowercase letters and underscores allowed." >&2
    exit 1
fi

INBOX="$SCRIPT_DIR/queue/inbox/${AGENT_ID}.yaml"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/scripts/lib/lock_path.sh" 2>/dev/null \
    || lock_path() { printf '/tmp/shogun_lock_%s.lock' "$(printf '%s' "$1" | md5sum | cut -c1-16)"; }
LOCKFILE="$(lock_path "$INBOX")"

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

        INBOX_PATH="$INBOX" MSG_ID="$MSG_ID" AGENT_ID="$AGENT_ID" python3 -c "
import sys, os, tempfile

inbox_path = os.environ['INBOX_PATH']
msg_id = os.environ.get('MSG_ID', '')
agent_id = os.environ['AGENT_ID']

try:
    with open(inbox_path, encoding='utf-8') as f:
        raw_text = f.read()

    # Fast early exit: no unread messages in file (avoids yaml.safe_load cost)
    if 'read: false' not in raw_text:
        if msg_id:
            print(f'[inbox_mark_read] msg_id={msg_id} not found or already read')
        else:
            print('[inbox_mark_read] No unread messages')
        sys.exit(0)

    # Single-pass: identify target IDs and replace read: false -> true
    # (replaces yaml.safe_load + separate text scan with one combined pass)
    lines = raw_text.split('\n')
    current_id = None
    changed = 0
    for i, line in enumerate(lines):
        stripped = line.lstrip()
        if stripped.startswith('- '):
            current_id = None
            inner = stripped[2:].lstrip()
            if inner.startswith('id:'):
                current_id = inner.split(':', 1)[1].strip().strip(\"'\\\"\"  )
        elif stripped.startswith('id:') and current_id is None:
            current_id = stripped.split(':', 1)[1].strip().strip(\"'\\\"\"  )
        elif stripped.startswith('read:') and current_id is not None:
            if 'false' in stripped:
                if not msg_id or current_id == msg_id:
                    lines[i] = line.replace('read: false', 'read: true')
                    changed += 1

    if changed == 0:
        if msg_id:
            print(f'[inbox_mark_read] msg_id={msg_id} not found or already read')
        else:
            print('[inbox_mark_read] No unread messages')
        sys.exit(0)

    # Atomic write: preserve original text formatting
    new_text = '\n'.join(lines)
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(inbox_path), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
            f.write(new_text)
        os.replace(tmp_path, inbox_path)
    except Exception:
        os.unlink(tmp_path)
        raise

    print(f'[inbox_mark_read] Marked {changed} message(s) as read for {agent_id}')

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
