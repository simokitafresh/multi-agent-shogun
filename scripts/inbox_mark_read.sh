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
CONFIRM_SCRIPT="$SCRIPT_DIR/scripts/bulletin_confirm.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/scripts/lib/lock_path.sh" 2>/dev/null \
    || lock_path() { printf '/tmp/shogun_lock_%s.lock' "$(printf '%s' "$1" | md5sum | cut -c1-16)"; }
LOCKFILE="$(lock_path "$INBOX")"
CONFIRM_LIST_FILE=""

extract_bulletin_confirms() {
    local inbox_file="$1"
    local msg_filter="${2:-}"
    awk -v msg_filter="$msg_filter" '
        function trim(v) {
            gsub(/^[ \t'\''"]+/, "", v)
            gsub(/[ \t'\''"]+$/, "", v)
            return v
        }
        function reset_msg() {
            current_id=""
            current_type=""
            current_content=""
            current_read=""
        }
        function maybe_emit() {
            if (current_id == "" || current_type != "bulletin_notify" || current_read != "false") {
                return
            }
            if (msg_filter != "" && current_id != msg_filter) {
                return
            }
            content = current_content
            if (match(content, /掲示板新規投稿\([^)]+\)/)) {
                entry_id = substr(content, RSTART + length("掲示板新規投稿("), RLENGTH - length("掲示板新規投稿(") - 1)
                if (entry_id != "") {
                    print entry_id
                }
            }
        }
        BEGIN { reset_msg() }
        /^[[:space:]]*-[[:space:]]*/ {
            maybe_emit()
            reset_msg()
            line=$0
            sub(/^[[:space:]]*-[[:space:]]*/, "", line)
            key=line
            sub(/:.*/, "", key)
            val=line
            sub(/^[^:]*:[[:space:]]*/, "", val)
            key=trim(key)
            val=trim(val)
            if (key == "id") current_id=val
            else if (key == "type") current_type=val
            else if (key == "content") current_content=val
            else if (key == "read") current_read=val
            next
        }
        {
            line=$0
            sub(/^[[:space:]]+/, "", line)
            key=line
            sub(/:.*/, "", key)
            val=line
            sub(/^[^:]*:[[:space:]]*/, "", val)
            key=trim(key)
            val=trim(val)
            if (key == "id") current_id=val
            else if (key == "type") current_type=val
            else if (key == "content") current_content=val
            else if (key == "read") current_read=val
        }
        END { maybe_emit() }
    ' "$inbox_file" 2>/dev/null || true
}

confirm_bulletin_reads() {
    local entry_id
    local confirm_output
    local confirm_rc

    for entry_id in "$@"; do
        [ -n "$entry_id" ] || continue
        if [ ! -x "$CONFIRM_SCRIPT" ] && [ ! -f "$CONFIRM_SCRIPT" ]; then
            echo "[inbox_mark_read] WARN: bulletin_confirm.sh not found; skipped bulletin_confirm for $entry_id" >&2
            continue
        fi
        set +e
        confirm_output=$(bash "$CONFIRM_SCRIPT" "$AGENT_ID" "$entry_id" 2>&1)
        confirm_rc=$?
        set -e
        if [ "$confirm_rc" -ne 0 ]; then
            echo "[inbox_mark_read] WARN: bulletin_confirm failed for $entry_id: $confirm_output" >&2
        else
            echo "[inbox_mark_read] bulletin_confirmed $entry_id"
        fi
    done
}

if [ ! -f "$INBOX" ]; then
    echo "[inbox_mark_read] No inbox file for $AGENT_ID" >&2
    exit 0
fi

# Atomic mark-read with flock (3 retries, same pattern as inbox_write.sh)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    CONFIRM_LIST_FILE=$(mktemp /tmp/.imr_bulletin_XXXXXX)
    if (
        flock -w 5 200 || exit 1

        # Fast early exit: no unread messages in file
        if ! grep -q "^  read:[[:space:]]*false[[:space:]]*$" "$INBOX" 2>/dev/null; then
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

        extract_bulletin_confirms "$INBOX" "$MSG_ID" > "$CONFIRM_LIST_FILE"

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
        if [ -s "$CONFIRM_LIST_FILE" ]; then
            mapfile -t _bulletin_entries < "$CONFIRM_LIST_FILE"
            confirm_bulletin_reads "${_bulletin_entries[@]}"
        fi
        rm -f "$CONFIRM_LIST_FILE"
        exit 0
    else
        rm -f "$CONFIRM_LIST_FILE"
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
