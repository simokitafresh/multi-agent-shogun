#!/bin/bash
# inbox_mark_read.sh — inboxメッセージの既読化（排他ロック＋アトミック書込み）
# Usage: bash scripts/inbox_mark_read.sh <agent_id> [msg_id]
#   msg_id指定: そのメッセージのみ read:true に変更
#   msg_id省略: 全 read:false を read:true に変更
#
# inbox_write.sh と同じ lockfile (${INBOX}.lock) で flock を取得し、
# mkstemp + os.replace によるアトミック書込みで Lost Update を防止する。
# python3 を廃止し bash+sed/awk で代替 (python3 startup ~25ms 削減)

set -e

# SCRIPT_DIR: string ops instead of $(cd) subshell (~5ms savings on WSL2)
_imr_self="${BASH_SOURCE[0]}"
[[ "$_imr_self" != /* ]] && _imr_self="$PWD/$_imr_self"
SCRIPT_DIR="${_imr_self%/scripts/inbox_mark_read.sh}"
unset _imr_self

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

        # Fast early exit: no unread messages in file
        if ! grep -q "read: false" "$INBOX" 2>/dev/null; then
            if [ -n "$MSG_ID" ]; then
                echo "[inbox_mark_read] msg_id=$MSG_ID not found or already read"
            else
                echo "[inbox_mark_read] No unread messages"
            fi
            exit 0
        fi

        # Atomic write: mktemp in same dir + mv (same as original python3 os.replace)
        _inbox_dir="${INBOX%/*}"
        _tmp=$(mktemp "${_inbox_dir}/.imr_XXXXXX.tmp")

        if [ -z "$MSG_ID" ]; then
            # Mark all: only message-level read fields, not literal content lines.
            _changed=$(grep -c "^  read:[[:space:]]*false[[:space:]]*$" "$INBOX" 2>/dev/null || echo 0)
            sed 's/^\(  read:[[:space:]]*\)false[[:space:]]*$/\1true/' "$INBOX" > "$_tmp" \
                || { rm -f "$_tmp"; exit 1; }
        else
            # Mark specific msg_id: stateful awk pass (no python3)
            _cnt_file=$(mktemp /tmp/.imr_cnt_XXXXXX)
            awk -v msg_id="$MSG_ID" -v cnt_file="$_cnt_file" '
                BEGIN { changed=0; current_id="" }
                {
                    stripped=$0
                    gsub(/^[[:space:]]+/,"",stripped)
                    if (stripped ~ /^- /) {
                        current_id=""
                        inner=stripped
                        sub(/^-[[:space:]]*/,"",inner)
                        gsub(/^[[:space:]]+/,"",inner)
                        if (inner ~ /^id:/) {
                            current_id=inner
                            sub(/^id:[[:space:]]*/,"",current_id)
                            gsub(/^[ \t'"'"'"]*/,"",current_id)
                            gsub(/[ \t'"'"'"]*$/,"",current_id)
                        }
                    } else if (stripped ~ /^id:/ && current_id=="") {
                        current_id=stripped
                        sub(/^id:[[:space:]]*/,"",current_id)
                        gsub(/^[ \t'"'"'"]*/,"",current_id)
                        gsub(/[ \t'"'"'"]*$/,"",current_id)
                    } else if ($0 ~ /^  read:[[:space:]]*false[[:space:]]*$/ && current_id!="") {
                        if (msg_id=="" || current_id==msg_id) {
                            sub(/read:[[:space:]]*false[[:space:]]*$/,"read: true")
                            changed++
                        }
                    }
                    print
                }
                END { print changed > cnt_file }
            ' "$INBOX" > "$_tmp" || { rm -f "$_tmp" "$_cnt_file"; exit 1; }
            _changed=$(cat "$_cnt_file" 2>/dev/null || echo 0)
            rm -f "$_cnt_file"
        fi

        if [ "${_changed:-0}" -eq 0 ]; then
            rm -f "$_tmp"
            if [ -n "$MSG_ID" ]; then
                echo "[inbox_mark_read] msg_id=$MSG_ID not found or already read"
            else
                echo "[inbox_mark_read] No unread messages"
            fi
            exit 0
        fi

        mv "$_tmp" "$INBOX"
        echo "[inbox_mark_read] Marked ${_changed} message(s) as read for $AGENT_ID"

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
