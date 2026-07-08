#!/bin/bash
# semantic-links: [[YAML安全書込み]], [[inbox処理規律]]
# inbox_mark_read.sh — inboxメッセージの既読化（排他ロック＋アトミック書込み）
# Usage: bash scripts/inbox_mark_read.sh <agent_id> <msg_id...>
#   msg_id指定: そのメッセージのみ read:true に変更（複数指定可。1件ずつ逐次処理）
#   msg_id省略: 未読がある場合はBLOCK（処理していない別件を既読化する事故を防ぐ）
#   例外: INBOX_MARK_READ_ALLOW_ALL=1 指定時のみ全 read:false を read:true に変更
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

# 複数msg_id対応(2026-07-07 軍師発見バグ: $3以降が無視され1件しかmarkされない):
# 3個以上の引数は1件ずつ自己呼出しへ分解し、既存の単一msg_idロジック(flock/awk/bulletin連携)を変更しない
if [ $# -gt 2 ]; then
    _imr_agent="$1"
    shift
    _imr_rc=0
    for _imr_mid in "$@"; do
        bash "${BASH_SOURCE[0]}" "$_imr_agent" "$_imr_mid" || _imr_rc=$?
    done
    exit "$_imr_rc"
fi

AGENT_ID="$1"
MSG_ID="${2:-}"

if [ -z "$AGENT_ID" ]; then
    echo "Usage: inbox_mark_read.sh <agent_id> <msg_id...>" >&2
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

record_task_acknowledged_at() {
    local agent_id="$1"
    local task_file="$SCRIPT_DIR/queue/tasks/${agent_id}.yaml"
    local yfs="$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
    local ack_ts
    local status=""
    local ack_existing=""

    [ -f "$task_file" ] || return 0
    [ -f "$yfs" ] || return 0

    status=$(awk -F': *' '
        /^task:/ { in_task=1; next }
        in_task && /^  status:/ { gsub(/["'\'']/, "", $2); print $2; exit }
        !in_task && /^status:/ { gsub(/["'\'']/, "", $2); print $2; exit }
    ' "$task_file" 2>/dev/null || true)
    case "$status" in
        assigned|acknowledged|in_progress) ;;
        *) return 0 ;;
    esac

    ack_existing=$(awk -F': *' '
        /^task:/ { in_task=1; next }
        in_task && /^  acknowledged_at:/ { gsub(/["'\'']/, "", $2); print $2; exit }
        !in_task && /^acknowledged_at:/ { gsub(/["'\'']/, "", $2); print $2; exit }
    ' "$task_file" 2>/dev/null || true)
    [ -z "$ack_existing" ] || return 0

    ack_ts=$(date '+%Y-%m-%dT%H:%M:%S')
    bash "$yfs" "$task_file" task acknowledged_at "$ack_ts" >/dev/null 2>&1 || true
}

resolve_inbox_file_path() {
    local inbox_file="$1"
    local resolved=""

    resolved=$(readlink -f "$inbox_file" 2>/dev/null || true)
    if [ -n "$resolved" ]; then
        printf '%s\n' "$resolved"
        return 0
    fi

    local inbox_dir inbox_base resolved_dir
    inbox_dir="${inbox_file%/*}"
    inbox_base="${inbox_file##*/}"
    resolved_dir=$(readlink -f "$inbox_dir" 2>/dev/null || true)
    if [ -n "$resolved_dir" ]; then
        printf '%s/%s\n' "$resolved_dir" "$inbox_base"
    else
        printf '%s\n' "$inbox_file"
    fi
}

INBOX="$(resolve_inbox_file_path "$INBOX")"
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

if [ -z "$MSG_ID" ] \
    && [ "${INBOX_MARK_READ_ALLOW_ALL:-}" != "1" ] \
    && grep -q "^  read:[[:space:]]*false[[:space:]]*$" "$INBOX" 2>/dev/null; then
    echo "[inbox_mark_read] ERROR: msg_id is required when unread messages exist. Use INBOX_MARK_READ_ALLOW_ALL=1 only for audited bulk acknowledgement." >&2
    exit 2
fi

# Atomic mark-read with flock (3 retries, same pattern as inbox_write.sh)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    CONFIRM_LIST_FILE="/tmp/.imr_bulletin_$$"
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
        _tmp="${_inbox_dir}/.imr_$$.tmp"

        if grep -q "type:[[:space:]]*['\"]*bulletin_notify['\"]*[[:space:]]*$" "$INBOX" 2>/dev/null; then
            extract_bulletin_confirms "$INBOX" "$MSG_ID" > "$CONFIRM_LIST_FILE"
        else
            : > "$CONFIRM_LIST_FILE"
        fi

        if [ -z "$MSG_ID" ]; then
            # Mark all: only message-level read fields, not literal content lines.
            _changed=$(grep -c "^  read:[[:space:]]*false[[:space:]]*$" "$INBOX" 2>/dev/null || echo 0)
            sed 's/^\(  read:[[:space:]]*\)false[[:space:]]*$/\1true/' "$INBOX" > "$_tmp" \
                || { rm -f "$_tmp"; exit 1; }
        else
            # Mark specific msg_id: stateful awk pass (no python3)
            _cnt_file="/tmp/.imr_cnt_$$"
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
            read -r _changed < "$_cnt_file" 2>/dev/null || _changed=0
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
        record_task_acknowledged_at "$AGENT_ID"
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
