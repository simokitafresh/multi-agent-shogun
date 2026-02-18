#!/bin/bash
# inbox_mark_read.sh — inboxメッセージの既読化（排他ロック付き）
# Usage: bash scripts/inbox_mark_read.sh <agent_id> <message_id> [message_id2 ...]
# Example: bash scripts/inbox_mark_read.sh karo msg_20260218_030345_29582e5c msg_20260218_040543_6409c36a

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_ID="$1"; shift

if [ -z "$AGENT_ID" ] || [ $# -eq 0 ]; then
    echo "Usage: inbox_mark_read.sh <agent_id> <message_id> [message_id2 ...]" >&2
    exit 1
fi

INBOX_FILE="$SCRIPT_DIR/queue/inbox/${AGENT_ID}.yaml"
LOCKFILE="${INBOX_FILE}.lock"

if [ ! -f "$INBOX_FILE" ]; then
    echo "ERROR: $INBOX_FILE not found" >&2
    exit 1
fi

# Collect message IDs as JSON array for python
MSG_IDS_JSON=$(printf '%s\n' "$@" | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin]))")

(
    flock -w 10 200 || { echo "ERROR: lock timeout" >&2; exit 1; }

    python3 -c "
import yaml, sys, os, tempfile, json

inbox_path = '$INBOX_FILE'
msg_ids = json.loads('$MSG_IDS_JSON')

try:
    with open(inbox_path) as f:
        data = yaml.safe_load(f)

    if not data or not data.get('messages'):
        print('WARNING: No messages in inbox', file=sys.stderr)
        sys.exit(0)

    changed = 0
    for msg in data['messages']:
        if msg.get('id') in msg_ids and not msg.get('read', False):
            msg['read'] = True
            changed += 1

    if changed == 0:
        print('No messages updated (already read or not found)', file=sys.stderr)
        sys.exit(0)

    # Atomic write: tmp file + rename
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(inbox_path), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, inbox_path)
    except:
        os.unlink(tmp_path)
        raise

    print(f'Marked {changed} message(s) as read', file=sys.stderr)

except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" || exit 1

) 200>"$LOCKFILE"
