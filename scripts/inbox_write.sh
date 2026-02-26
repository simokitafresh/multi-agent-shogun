#!/bin/bash
# inbox_write.sh — メールボックスへのメッセージ書き込み（排他ロック付き）
# Usage: bash scripts/inbox_write.sh <target_agent> <content> [type] [from]
# Example: bash scripts/inbox_write.sh karo "半蔵、任務完了" report_received hanzo

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$1"
CONTENT="$2"
TYPE="${3:-wake_up}"
FROM="${4:-unknown}"
NINJA_NAMES="sasuke kirimaru hayate kagemaru hanzo saizo kotaro tobisaru"

# Validate arguments
if [ -z "$TARGET" ] || [ -z "$CONTENT" ]; then
    echo "Usage: inbox_write.sh <target_agent> <content> [type] [from]" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

if [[ "$TARGET" == cmd_* ]]; then
    echo "ERROR: 第1引数はtarget_agent（例: karo, sasuke）。cmd_idではない。" >&2
    echo "Usage: inbox_write.sh <target_agent> <content> [type] [from]" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

# HIGH-2: パストラバーサル防止 — TARGETを許可リストで検証
ALLOWED_TARGETS="karo sasuke kirimaru hayate kagemaru hanzo saizo kotaro tobisaru shogun gunshi"
valid_target=0
for allowed in $ALLOWED_TARGETS; do
    if [ "$TARGET" = "$allowed" ]; then
        valid_target=1
        break
    fi
done
if [ "$valid_target" -eq 0 ]; then
    echo "ERROR: Invalid target agent: '$TARGET'. Allowed: $ALLOWED_TARGETS" >&2
    exit 1
fi

INBOX="$SCRIPT_DIR/queue/inbox/${TARGET}.yaml"
LOCKFILE="${INBOX}.lock"

# Validate sender/target relationship
is_ninja_sender=0
for ninja in $NINJA_NAMES; do
    if [ "$FROM" = "$ninja" ]; then
        is_ninja_sender=1
        break
    fi
done

if [ "$is_ninja_sender" -eq 1 ] && [ "$TARGET" = "shogun" ]; then
    echo "ERROR: Ninja cannot send inbox to shogun directly. Use karo as relay." >&2
    exit 1
fi

if [ "$FROM" = "ninja_monitor" ] && [ "$TARGET" != "karo" ] && [ "$TARGET" != "shogun" ]; then
    echo "ERROR: ninja_monitor can send only to karo or shogun." >&2
    exit 1
fi

# Initialize inbox if not exists
if [ ! -f "$INBOX" ]; then
    mkdir -p "$(dirname "$INBOX")"
    echo "messages: []" > "$INBOX"
fi

# Generate unique message ID (timestamp-based)
MSG_ID="msg_$(date +%Y%m%d_%H%M%S)_$(head -c 4 /dev/urandom | xxd -p)"
TIMESTAMP=$(date "+%Y-%m-%dT%H:%M:%S")

# Atomic write with flock (3 retries)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 5 200 || exit 1

        # Add message via python3 — HIGH-1: 全変数を環境変数経由で渡す（インジェクション防止）
        INBOX_PATH="$INBOX" MSG_ID="$MSG_ID" MSG_FROM="$FROM" \
        MSG_TIMESTAMP="$TIMESTAMP" MSG_TYPE="$TYPE" MSG_CONTENT="$CONTENT" \
        python3 -c "
import yaml, sys, os

try:
    inbox_path  = os.environ['INBOX_PATH']
    msg_id      = os.environ['MSG_ID']
    msg_from    = os.environ['MSG_FROM']
    msg_ts      = os.environ['MSG_TIMESTAMP']
    msg_type    = os.environ['MSG_TYPE']
    msg_content = os.environ['MSG_CONTENT']

    # Load existing inbox
    with open(inbox_path) as f:
        data = yaml.safe_load(f)

    # Initialize if needed
    if not data:
        data = {}
    if not data.get('messages'):
        data['messages'] = []

    # Add new message
    new_msg = {
        'id':        msg_id,
        'from':      msg_from,
        'timestamp': msg_ts,
        'type':      msg_type,
        'content':   msg_content,
        'read':      False
    }
    data['messages'].append(new_msg)

    # Overflow protection: keep max 50 messages
    if len(data['messages']) > 50:
        msgs   = data['messages']
        unread = [m for m in msgs if not m.get('read', False)]
        read   = [m for m in msgs if m.get('read', False)]
        # Keep all unread + newest 30 read messages
        data['messages'] = unread + read[-30:]

    # Atomic write: tmp file + rename (prevents partial reads)
    import tempfile
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(inbox_path), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, inbox_path)
    except:
        os.unlink(tmp_path)
        raise

except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" || exit 1

    ) 200>"$LOCKFILE"; then
        # Success — inbox message persisted

        # Hook: report_received from ninja → auto-update task YAML to done
        if [ "$TYPE" = "report_received" ]; then
            is_ninja=0
            for ninja in $NINJA_NAMES; do
                if [ "$FROM" = "$ninja" ]; then
                    is_ninja=1
                    break
                fi
            done

            if [ "$is_ninja" -eq 1 ]; then
                TASK_YAML="$SCRIPT_DIR/queue/tasks/${FROM}.yaml"
                TASK_LOCKFILE="${TASK_YAML}.lock"

                if [ -f "$TASK_YAML" ]; then
                    (
                        flock -w 5 201 || exit 0  # Lock failure is non-fatal

                        TASK_PATH="$TASK_YAML" python3 -c "
import yaml, tempfile, os, sys

task_path = os.environ['TASK_PATH']
try:
    with open(task_path) as f:
        data = yaml.safe_load(f)

    if not data or 'task' not in data:
        sys.exit(0)

    current_status = data['task'].get('status', '')
    # done/failed/blocked — do not overwrite (idempotent)
    if current_status in ('done', 'failed', 'blocked'):
        sys.exit(0)

    # assigned/in_progress → done
    data['task']['status'] = 'done'

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_path), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_path)
    except:
        os.unlink(tmp_path)
        raise
except Exception as e:
    print(f'[inbox_write] task-auto-done WARN: {e}', file=sys.stderr)
"
                    ) 201>"$TASK_LOCKFILE"
                fi
            fi
        fi

        exit 0
    else
        # Lock timeout or error
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[inbox_write] Lock timeout for $INBOX (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[inbox_write] Failed to acquire lock after $max_attempts attempts for $INBOX" >&2
            exit 1
        fi
    fi
done
