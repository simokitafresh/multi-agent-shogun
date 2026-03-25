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

        INBOX_PATH="$INBOX" MSG_ID="$MSG_ID" AGENT_ID="$AGENT_ID" python3 -c "
import yaml, sys, os, tempfile

inbox_path = os.environ['INBOX_PATH']
msg_id = os.environ.get('MSG_ID', '')
agent_id = os.environ['AGENT_ID']

try:
    with open(inbox_path, encoding='utf-8') as f:
        raw_text = f.read()

    data = yaml.safe_load(raw_text)
    if not data or not data.get('messages'):
        print('[inbox_mark_read] No messages in inbox')
        sys.exit(0)

    # Identify target message IDs
    target_ids = set()
    for m in data['messages']:
        if m.get('read', False):
            continue
        if msg_id and str(m.get('id', '')) != msg_id:
            continue
        target_ids.add(str(m.get('id', '')))

    if not target_ids:
        if msg_id:
            print(f'[inbox_mark_read] msg_id={msg_id} not found or already read')
        else:
            print('[inbox_mark_read] No unread messages')
        sys.exit(0)

    # Text-based replacement: find each target ID block, flip read: false -> read: true
    # This preserves original YAML formatting (no yaml.dump round-trip)
    lines = raw_text.split('\n')
    in_target = False
    changed = 0
    for i, line in enumerate(lines):
        stripped = line.lstrip()
        if stripped.startswith('- '):
            in_target = False
            # Handle '- id: xxx' (id as first field of list item)
            inner = stripped[2:].lstrip()
            if inner.startswith('id:'):
                val = inner.split(':', 1)[1].strip().strip(\"'\\\"\")
                if val in target_ids:
                    in_target = True
        elif stripped.startswith('id:'):
            val = stripped.split(':', 1)[1].strip().strip(\"'\\\"\")
            if val in target_ids:
                in_target = True
        if in_target and 'read: false' in line:
            lines[i] = line.replace('read: false', 'read: true')
            in_target = False
            changed += 1

    if changed == 0:
        print('[inbox_mark_read] No changes made')
        sys.exit(0)

    # Atomic write: preserve original text formatting
    new_text = '\n'.join(lines)
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(inbox_path), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
            f.write(new_text)
        os.replace(tmp_path, inbox_path)
    except:
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
