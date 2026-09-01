#!/bin/bash
# Receipt contract provenance: cmd_karo_hotfix_inbox_processing_receipt_20260901.
# semantic-links: [[YAML安全書込み]], [[inbox処理規律]]
# inbox_mark_read.sh — inboxメッセージの既読化（排他ロック＋アトミック書込み）
# Usage: bash scripts/inbox_mark_read.sh <agent_id> <msg_id...>
#   msg_id指定: 明示されたメッセージだけを1回のflock+atomic rewriteでread:trueに変更
#   msg_id省略: 未読がある場合はBLOCK（処理していない別件を既読化する事故を防ぐ）
#   環境変数による全件既読化も禁止。Read後に到着した別件を巻き込むため。
#
# inbox_write.sh と同じ lockfile (${INBOX}.lock) で flock を取得し、
# mkstemp + os.replace によるアトミック書込みで Lost Update を防止する。
# python3 を廃止し bash+sed/awk で代替 (python3 startup ~25ms 削減)

set -e

# SCRIPT_DIR: string ops instead of $(cd) subshell (~5ms savings on WSL2)
_imr_self="${BASH_SOURCE[0]}"
[[ "$_imr_self" != /* ]] && _imr_self="$PWD/$_imr_self"
SCRIPT_DIR="${INBOX_MARK_READ_ROOT_OVERRIDE:-${_imr_self%/scripts/inbox_mark_read.sh}}"
unset _imr_self

INBOX_MARK_READ_TOTAL_T0_US="${EPOCHREALTIME/./}"
INBOX_MARK_READ_TOTAL_T0_US="${INBOX_MARK_READ_TOTAL_T0_US:0:16}"
DEFENSE_OVERHEAD_REPO_ROOT="${DEFENSE_OVERHEAD_REPO_ROOT:-$SCRIPT_DIR}"
if [ -f "$SCRIPT_DIR/scripts/lib/defense_overhead_writer.sh" ]; then
    # shellcheck source=scripts/lib/defense_overhead_writer.sh
    source "$SCRIPT_DIR/scripts/lib/defense_overhead_writer.sh"
else
    defense_overhead_write_async() { return 0; }
fi
INBOX_MARK_READ_TOTAL_RECORDED=0
inbox_mark_read_record_total() {
    local rc="${1:-0}" now_us wall_ms verdict
    [ "${INBOX_MARK_READ_TOTAL_RECORDED:-0}" -eq 0 ] || return 0
    INBOX_MARK_READ_TOTAL_RECORDED=1
    now_us="${EPOCHREALTIME/./}"
    now_us="${now_us:0:16}"
    wall_ms=$(( (now_us - INBOX_MARK_READ_TOTAL_T0_US + 999) / 1000 ))
    verdict=PASS
    [ "$rc" -eq 0 ] || verdict=FAIL
    defense_overhead_write_async inbox_mark_read inbox_mark_read_total "$wall_ms" "$verdict" \
        "inbox-mark-read-${BASHPID}-${INBOX_MARK_READ_TOTAL_T0_US}" || true
}
inbox_mark_read_total_on_exit() { local rc=$?; inbox_mark_read_record_total "$rc"; return "$rc"; }
trap inbox_mark_read_total_on_exit EXIT

AGENT_ID="$1"
shift || true
AUTO_INFO_MODE=false
if [ "${1:-}" = "--auto-info" ]; then
    AUTO_INFO_MODE=true
    shift
fi
MSG_IDS=("$@")
MSG_ID="${MSG_IDS[0]:-}"

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
    # YAML null scalars are parsed as missing values.  Treat the canonical
    # spellings as empty, while preserving any real timestamp verbatim.
    local ack_normalized="${ack_existing//[[:space:]]/}"
    case "$ack_normalized" in
        ""|null|Null|NULL|"~") ack_existing="" ;;
        *) return 0 ;;
    esac

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
RECEIPT_DIR="${INBOX_MARK_READ_RECEIPT_DIR:-$SCRIPT_DIR/logs/inbox_read_receipts}"
RECEIPT_FILE="$RECEIPT_DIR/${AGENT_ID}.json"
REVIEW_LOG="$SCRIPT_DIR/logs/gunshi_review_log.yaml"
CONFIRM_LIST_FILE=""

# inbox_read.sh publishes one generation-bound receipt for every unread
# message.  Validate all requested IDs before changing the inbox.  The
# generation excludes read flags, so receipts from one read remain usable for
# several sequential marks, while content/new-message changes fail closed.
verify_read_receipt() {
    [ "$AUTO_INFO_MODE" = true ] && return 0
    [ -n "$MSG_ID" ] || return 0
    local verified_file="/tmp/.imr_receipt_verified_$$"
    python3 - "$INBOX" "$AGENT_ID" "$RECEIPT_FILE" "$ID_LIST_FILE" "$verified_file" "$REVIEW_LOG" <<'PY'
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone, timedelta

import yaml

inbox, agent, receipt_path, ids_path, verified_path, review_log_path = sys.argv[1:]
try:
    with open(receipt_path, encoding="utf-8") as fh:
        receipt = json.load(fh)
except FileNotFoundError:
    print(f"BLOCK: no inbox read receipt for agent={agent}; read inbox before mark_read", file=sys.stderr)
    raise SystemExit(2)
except Exception as exc:
    print(f"BLOCK: invalid inbox read receipt for agent={agent}: {exc}", file=sys.stderr)
    raise SystemExit(2)

if receipt.get("version") != 1 or receipt.get("agent") != agent:
    print("BLOCK: inbox read receipt identity mismatch", file=sys.stderr)
    raise SystemExit(2)
entries = receipt.get("entries")
if not isinstance(entries, list) or not entries:
    print("BLOCK: inbox read receipt has no consumable entries", file=sys.stderr)
    raise SystemExit(2)
entry_by_id = {}
for entry in entries:
    if not isinstance(entry, dict) or not entry.get("msg_id") or not entry.get("content_hash"):
        print("BLOCK: malformed inbox read receipt entry", file=sys.stderr)
        raise SystemExit(2)
    msg_id = str(entry["msg_id"])
    if msg_id in entry_by_id:
        print(f"BLOCK: duplicate inbox read receipt entry msg_id={msg_id}", file=sys.stderr)
        raise SystemExit(2)
    entry_by_id[msg_id] = entry

with open(ids_path, encoding="utf-8") as fh:
    wanted = [line.strip() for line in fh if line.strip()]
if not wanted:
    raise SystemExit(0)

with open(inbox, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
messages = data.get("messages", [])
if not isinstance(messages, list):
    print("BLOCK: inbox messages must be a list", file=sys.stderr)
    raise SystemExit(2)

def identity(message):
    return {key: str(message.get(key, "")) for key in ("id", "from", "timestamp", "type", "content")}

identities, current = [], {}
for message in messages:
    if not isinstance(message, dict):
        print("BLOCK: inbox message must be a mapping", file=sys.stderr)
        raise SystemExit(2)
    item = identity(message)
    if not item["id"] or item["id"] in current:
        print("BLOCK: missing or duplicate inbox message id", file=sys.stderr)
        raise SystemExit(2)
    identities.append(item)
    current[item["id"]] = message
generation = hashlib.sha256(json.dumps(
    identities, ensure_ascii=False, sort_keys=True, separators=(",", ":")
).encode("utf-8")).hexdigest()
if receipt.get("generation") != generation:
    print("BLOCK: stale inbox read receipt generation; reread inbox", file=sys.stderr)
    raise SystemExit(2)

for msg_id in wanted:
    message = current.get(msg_id)
    entry = entry_by_id.get(msg_id)
    if message is None or entry is None:
        print(f"BLOCK: inbox read receipt does not cover msg_id={msg_id}", file=sys.stderr)
        raise SystemExit(2)
    if message.get("read") is not False:
        print(f"BLOCK: msg_id={msg_id} was not unread when read receipt was issued", file=sys.stderr)
        raise SystemExit(2)
    content_hash = hashlib.sha256(str(message.get("content", "")).encode("utf-8")).hexdigest()
    if entry.get("content_hash") != content_hash:
        print(f"BLOCK: inbox read receipt content hash mismatch msg_id={msg_id}", file=sys.stderr)
        raise SystemExit(2)


def parse_timestamp(value):
    text = str(value or "").strip().strip("'\"")
    if not text:
        return None
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone(timedelta(hours=9)))
    return parsed.astimezone(timezone.utc)


def nested_values(node, key=None):
    if isinstance(node, dict):
        for child_key, child in node.items():
            if key is None or str(child_key) == key:
                yield child
            yield from nested_values(child, key)
    elif isinstance(node, list):
        for child in node:
            yield from nested_values(child, key)


def nested_strings(node):
    if isinstance(node, dict):
        for child in node.values():
            yield from nested_strings(child)
    elif isinstance(node, list):
        for child in node:
            yield from nested_strings(child)
    elif isinstance(node, str):
        yield node


def report_name_from_content(content):
    match = re.search(r"report\s*[=:]\s*['\"]?([A-Za-z0-9_.-]+\.ya?ml)\b", str(content or ""), re.IGNORECASE)
    return os.path.basename(match.group(1)) if match else ""


def entry_has_cmd_id(entry, cmd_id):
    if isinstance(entry, dict):
        if str(entry.get("cmd_id") or "") == cmd_id:
            return True
        return any(entry_has_cmd_id(child, cmd_id) for child in entry.values())
    if isinstance(entry, list):
        return any(entry_has_cmd_id(child, cmd_id) for child in entry)
    return False


def entry_matches_report(entry, report_name):
    if any(os.path.basename(value.strip().strip("'\"")) == report_name for value in nested_strings(entry)):
        return True
    match = re.match(r"^[^/]+_report_(cmd_.+)\.ya?ml$", report_name)
    return bool(match and entry_has_cmd_id(entry, match.group(1)))


review_messages = [
    message for msg_id, message in ((msg_id, current[msg_id]) for msg_id in wanted)
    if str(message.get("type") or "") in {"report_review"}
]
if review_messages:
    try:
        with open(review_log_path, encoding="utf-8") as fh:
            review_data = yaml.safe_load(fh) or []
    except Exception:
        review_data = None
    if isinstance(review_data, list):
        review_entries = [item for item in review_data if isinstance(item, dict)]
    elif isinstance(review_data, dict):
        candidate = review_data.get("reviews")
        review_entries = candidate if isinstance(candidate, list) else [review_data]
        review_entries = [item for item in review_entries if isinstance(item, dict)]
    else:
        review_entries = []
    for message in review_messages:
        report_name = report_name_from_content(message.get("content"))
        message_at = parse_timestamp(message.get("timestamp"))
        matched = False
        if report_name and message_at is not None:
            for review_entry in review_entries:
                if not entry_matches_report(review_entry, report_name):
                    continue
                review_times = [parse_timestamp(value) for value in nested_values(review_entry, "reviewed_at")]
                if any(review_at is not None and review_at >= message_at for review_at in review_times):
                    matched = True
                    break
        if not matched:
            print(
                f"BLOCK: review not recorded msg_id={message.get('id', '')} report={report_name or '<missing>'}",
                file=sys.stderr,
            )
            raise SystemExit(2)

with open(verified_path, "w", encoding="utf-8") as fh:
    fh.write("\n".join(wanted) + "\n")
PY
}

consume_read_receipt() {
    [ "$AUTO_INFO_MODE" = true ] && return 0
    [ -n "$MSG_ID" ] || return 0
    local consumed_file="/tmp/.imr_receipt_consumed_$$"
    python3 - "$RECEIPT_FILE" "$ID_LIST_FILE" "$consumed_file" <<'PY'
import json
import os
import sys
import tempfile

receipt_path, ids_path, output_path = sys.argv[1:]
with open(receipt_path, encoding="utf-8") as fh:
    payload = json.load(fh)
with open(ids_path, encoding="utf-8") as fh:
    consumed = {line.strip() for line in fh if line.strip()}
remaining = [entry for entry in payload.get("entries", []) if str(entry.get("msg_id", "")) not in consumed]
if not remaining:
    os.unlink(receipt_path)
else:
    payload["entries"] = remaining
    directory = os.path.dirname(receipt_path)
    fd, temporary = tempfile.mkstemp(prefix=f".{os.path.basename(receipt_path)}.", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False, sort_keys=True)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(temporary, receipt_path)
    except Exception:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise
PY
}

auto_digest_info_messages() {
    local digest="${INBOX_INFO_DIGEST_FILE:-$SCRIPT_DIR/logs/inbox_info_digest.jsonl}"
    local ids_file="/tmp/.imr_auto_info_ids_$$"
    mkdir -p "${digest%/*}"
    python3 - "$INBOX" "$digest" >"$ids_file" <<'PY' || return $?
import fcntl, json, os, sys, yaml
inbox, digest = sys.argv[1:]
# gate_clear is an actionable completion event: preserve it unread so the
# recipient can self-drive the post-clear workflow after the watcher nudge.
allowed = {"low", "info", "heartbeat", "status_update", "retro_answer"}
try:
    data = yaml.safe_load(open(inbox, encoding="utf-8")) or {}
except Exception as exc:
    print(f"BLOCK: inbox parse failed: {exc}", file=sys.stderr)
    raise SystemExit(2)
eligible = []
for msg in data.get("messages", []):
    if not isinstance(msg, dict) or msg.get("read") is True or msg.get("type") not in allowed:
        continue
    required = ("id", "from", "type", "timestamp", "content")
    if any(msg.get(k) in (None, "") for k in required):
        print(f"BLOCK: classified info message missing required fields id={msg.get('id','')}", file=sys.stderr)
        raise SystemExit(2)
    eligible.append(msg)
if not eligible:
    raise SystemExit(0)
os.makedirs(os.path.dirname(digest), exist_ok=True)
with open(digest, "a+", encoding="utf-8") as out:
    try:
        fcntl.flock(out.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("BLOCK: info digest lock busy", file=sys.stderr)
        raise SystemExit(3)
    out.seek(0)
    seen = set()
    for line in out:
        try: seen.add(str(json.loads(line)["msg_id"]))
        except Exception: continue
    for msg in eligible:
        msg_id = str(msg["id"])
        if msg_id not in seen:
            record = {"msg_id": msg_id, "from": str(msg["from"]), "type": str(msg["type"]),
                      "timestamp": str(msg["timestamp"]), "content": str(msg["content"])}
            out.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
            seen.add(msg_id)
    out.flush(); os.fsync(out.fileno())
for msg in eligible:
    print(msg["id"])
PY
    mapfile -t MSG_IDS < "$ids_file"
    MSG_ID="${MSG_IDS[0]:-}"
    [ -n "$MSG_ID" ] || return 0
}

# A commander inbox is not governed by the ninja-only task_id filter.  In
# particular, a shogun task_assigned row must remain visible until Karo has
# left a durable processing trace.  Check the trace while holding the same
# inbox lock as the mark-read rewrite so a concurrent writer cannot make an
# unprocessed command appear handled (T122).
karo_task_assignment_rows() {
    local inbox_file="$1" id_file="$2"
    awk -v id_file="$id_file" '
        function trim(value) {
            gsub(/^[ \t'\''"]+/, "", value)
            gsub(/[ \t'\''"]+$/, "", value)
            return value
        }
        function reset_record() {
            delete record
            record_count=0
            record_id=""
            record_from=""
            record_type=""
            record_read=""
            raw_record=""
        }
        function flush_record(    i,line,value) {
            if (record_count == 0) return
            for (i=1; i<=record_count; i++) {
                line=record[i]
                if (line ~ /^- id:/) {
                    value=line
                    sub(/^- id:[[:space:]]*/, "", value)
                    record_id=trim(value)
                } else if (line ~ /^  id:/) {
                    value=line
                    sub(/^  id:[[:space:]]*/, "", value)
                    record_id=trim(value)
                } else if (line ~ /^  from:/) {
                    value=line; sub(/^  from:[[:space:]]*/, "", value); record_from=trim(value)
                } else if (line ~ /^  type:/) {
                    value=line; sub(/^  type:[[:space:]]*/, "", value); record_type=trim(value)
                } else if (line ~ /^  read:/) {
                    value=line; sub(/^  read:[[:space:]]*/, "", value); record_read=trim(value)
                }
            }
            if ((record_id in wanted) && record_from == "shogun" && record_type == "task_assigned" && record_read == "false") {
                gsub(/[[:space:]]+/, " ", raw_record)
                gsub(/\t/, " ", raw_record)
                print record_id "\t" raw_record
            }
            reset_record()
        }
        BEGIN {
            while ((getline wanted_id < id_file) > 0) if (wanted_id != "") wanted[wanted_id]=1
            close(id_file)
            reset_record()
        }
        /^- / {
            flush_record()
            record[++record_count]=$0
            raw_record=$0
            next
        }
        {
            if (record_count > 0) {
                record[++record_count]=$0
                raw_record=raw_record " " $0
            }
        }
        END { flush_record() }
    ' "$inbox_file"
}

karo_task_assignment_has_evidence() {
    local message_id="$1" raw_record="$2"
    local task_file="$SCRIPT_DIR/queue/tasks/karo.yaml"
    local evidence_file cmd_id cmd_ids

    # A task YAML update is valid only when it names the assigned command and
    # has left Karo in a non-idle lifecycle state.  The pre-existing idle task
    # file therefore cannot accidentally authorize acknowledgement.
    cmd_ids="$(printf '%s' "$raw_record" | grep -oE 'cmd_[A-Za-z0-9_]+' | sort -u || true)"
    if [ -f "$task_file" ] && [ -n "$cmd_ids" ] \
        && grep -qE '^  status:[[:space:]]*(acknowledged|in_progress|done|failed)[[:space:]]*$' "$task_file"; then
        while IFS= read -r cmd_id; do
            [ -n "$cmd_id" ] || continue
            if grep -qF "$cmd_id" "$task_file"; then
                return 0
            fi
        done <<< "$cmd_ids"
    fi

    # Karo's commander completion is normally recorded on the bulletin board;
    # a direct reply in the shogun inbox is also an accepted durable trace.
    for evidence_file in \
        "$SCRIPT_DIR/queue/bulletin_board.yaml" \
        "$SCRIPT_DIR/queue/inbox/shogun.yaml"; do
        [ -f "$evidence_file" ] || continue
        if grep -qF "$message_id" "$evidence_file"; then
            return 0
        fi
        while IFS= read -r cmd_id; do
            [ -n "$cmd_id" ] || continue
            if grep -qF "$cmd_id" "$evidence_file"; then
                return 0
            fi
        done <<< "$cmd_ids"
    done
    return 1
}

karo_guard_unprocessed_shogun_assignments() {
    [ "$AGENT_ID" = "karo" ] || return 0
    local rows_file="/tmp/.imr_karo_task_rows_$$"
    karo_task_assignment_rows "$INBOX" "$ID_LIST_FILE" > "$rows_file"
    local message_id raw_record
    while IFS=$'\t' read -r message_id raw_record; do
        [ -n "$message_id" ] || continue
        if ! karo_task_assignment_has_evidence "$message_id" "$raw_record"; then
            rm -f "$rows_file"
            echo "BLOCK: Karo cannot mark shogun task_assigned msg_id=$message_id read without task YAML, bulletin, or reply-inbox processing evidence" >&2
            return 2
        fi
    done < "$rows_file"
    rm -f "$rows_file"
    return 0
}

if [ "$AUTO_INFO_MODE" = true ]; then
    auto_digest_info_messages || exit $?
    [ -n "$MSG_ID" ] || { echo "[inbox_mark_read] auto-info eligible=0"; exit 0; }
fi

extract_bulletin_confirms() {
    local inbox_file="$1"
    local msg_filter_file="${2:-}"
    awk -v msg_filter_file="$msg_filter_file" '
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
            if (filter_count > 0 && !(current_id in filters)) {
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
        BEGIN {
            reset_msg()
            while ((getline filter_id < msg_filter_file) > 0) {
                filters[filter_id]=1
                filter_count++
            }
            close(msg_filter_file)
        }
        /^-[[:space:]]/ {
            maybe_emit()
            reset_msg()
            line=$0
            sub(/^-[[:space:]]*/, "", line)
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
        /^  [A-Za-z0-9_.-]+:[[:space:]]*/ {
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
    && grep -q "^  read:[[:space:]]*false[[:space:]]*$" "$INBOX" 2>/dev/null; then
    echo "[inbox_mark_read] ERROR: msg_id is required when unread messages exist. Bulk acknowledgement is forbidden because it can consume messages that arrived after the inbox read." >&2
    exit 2
fi

# --- bulk mark-read guard (2026-09-01 15:44 家老報告 blt_154408) ---
# 軍師が `grep read:false | while read id; do inbox_mark_read.sh gunshi $id; done`
# で未読を本文処理前に一括既読化し、cmd_4436 review 依頼と影丸 v3 formal review が
# 消化された(重送 8 回)。1 呼出し 1 ID は正しく通るが、短い窓に連続する呼出しは
# 「読む前に消す」ループでしか起きない。窓内の呼出し回数で機械判定し BLOCK する。
# 正規の複数件処理は 1 呼出しに複数 ID を渡すか、1 件ずつ本文を処理してから呼ぶ。
INBOX_MARK_READ_BULK_WINDOW_SEC="${INBOX_MARK_READ_BULK_WINDOW_SEC:-10}"
INBOX_MARK_READ_BULK_MAX_CALLS="${INBOX_MARK_READ_BULK_MAX_CALLS:-2}"
INBOX_MARK_READ_LEDGER_DIR="${INBOX_MARK_READ_LEDGER_DIR:-$SCRIPT_DIR/logs/inbox_mark_read_ledger}"
bulk_mark_read_guard() {
    [ "$AUTO_INFO_MODE" = false ] || return 0
    [ -n "$MSG_ID" ] || return 0
    [[ "$INBOX_MARK_READ_BULK_WINDOW_SEC" =~ ^[0-9]+$ && "$INBOX_MARK_READ_BULK_MAX_CALLS" =~ ^[0-9]+$ ]] || return 0
    [ "$INBOX_MARK_READ_BULK_WINDOW_SEC" -gt 0 ] || return 0
    local ledger="$INBOX_MARK_READ_LEDGER_DIR/${AGENT_ID}.tsv" now recent
    mkdir -p "$INBOX_MARK_READ_LEDGER_DIR" 2>/dev/null || return 0
    now="${EPOCHSECONDS:-$(date +%s)}"
    # Count DISTINCT other message ids marked inside the window: a retry of the
    # same id (lock busy, test loops) is not a bulk pattern; N different ids
    # within seconds is.
    recent=0
    if [ -f "$ledger" ]; then
        recent="$(awk -v n="$now" -v w="$INBOX_MARK_READ_BULK_WINDOW_SEC" -v me="$MSG_ID" '($1+0) >= (n-w) && $2 != me && !seen[$2]++ {c++} END{print c+0}' "$ledger" 2>/dev/null || echo 0)"
    fi
    if [ "$recent" -ge "$INBOX_MARK_READ_BULK_MAX_CALLS" ]; then
        # 2026-09-01 15:49 家老 REJECT(blt_154942): 本番で家老が gate 通知→LGTM ACCEPT→
        # accept_report 照合の正規 3 件を順次処理して 3 件目が BLOCK=偽陽性。窓内件数は
        # 未処理 loop と高速な正規処理を区別できない。既定は WARN+ledger(観測)に留め、
        # BLOCK は INBOX_MARK_READ_BULK_ENFORCE=1 の明示時のみ。真の判定は inbox 読取経路の
        # 処理 receipt(msg_id+content hash)一致=次弾(INS 登録)。
        if [ "${INBOX_MARK_READ_BULK_ENFORCE:-0}" = "1" ]; then
            echo "BLOCK: bulk mark-read pattern — ${recent} other message(s) marked read for ${AGENT_ID} in the last ${INBOX_MARK_READ_BULK_WINDOW_SEC}s (limit ${INBOX_MARK_READ_BULK_MAX_CALLS}). Read and process each message before marking it; do not loop over read:false ids. msg_id=${MSG_ID} stays unread." >&2
            return 1
        fi
        echo "[inbox_mark_read] WARN(bulk-pattern): ${recent} other message(s) marked read for ${AGENT_ID} in the last ${INBOX_MARK_READ_BULK_WINDOW_SEC}s — read each message before marking (observe-only; INBOX_MARK_READ_BULK_ENFORCE=1 to block)" >&2
        printf '%s\t%s\tWARN\n' "$now" "$MSG_ID" >> "$INBOX_MARK_READ_LEDGER_DIR/${AGENT_ID}.warn.tsv" 2>/dev/null || true
    fi
    printf '%s\t%s\n' "$now" "$MSG_ID" >> "$ledger" 2>/dev/null || true
    # keep the ledger small: drop rows older than 10 windows
    if [ -f "$ledger" ] && [ "$(wc -l < "$ledger")" -gt 200 ]; then
        awk -v n="$now" -v w="$INBOX_MARK_READ_BULK_WINDOW_SEC" '($1+0) >= (n-10*w)' "$ledger" > "$ledger.tmp" 2>/dev/null && mv "$ledger.tmp" "$ledger" 2>/dev/null || rm -f "$ledger.tmp"
    fi
    return 0
}

# Atomic mark-read with flock (3 retries, same pattern as inbox_write.sh)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    CONFIRM_LIST_FILE="/tmp/.imr_bulletin_$$"
    ID_LIST_FILE="/tmp/.imr_ids_$$"
    printf '%s\n' "${MSG_IDS[@]}" | awk 'NF && !seen[$0]++' > "$ID_LIST_FILE"
    if (
        flock -w 5 200 || exit 1

        verify_read_receipt || exit 2
        karo_guard_unprocessed_shogun_assignments || exit 2
        bulk_mark_read_guard || exit 2

        # Fast early exit: no unread messages in file
        if ! grep -q "^  read:[[:space:]]*false[[:space:]]*$" "$INBOX" 2>/dev/null; then
            if [ -n "$MSG_ID" ]; then
                echo "[inbox_mark_read] ERROR: msg_id=$MSG_ID not found or already read" >&2
                exit 2
            else
                echo "[inbox_mark_read] No unread messages"
            fi
            exit 0
        fi

        # Consume the receipt before the inbox rewrite.  If the rewrite then
        # fails, the message remains unread and the caller must reread; a
        # consumed receipt can never authorize a second mark.
        consume_read_receipt || exit 2

        # Atomic write: mktemp in same dir + mv (same as original python3 os.replace)
        _inbox_dir="${INBOX%/*}"
        _tmp="${_inbox_dir}/.imr_$$.tmp"

        if grep -q "type:[[:space:]]*['\"]*bulletin_notify['\"]*[[:space:]]*$" "$INBOX" 2>/dev/null; then
            extract_bulletin_confirms "$INBOX" "$ID_LIST_FILE" > "$CONFIRM_LIST_FILE"
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
            awk -v id_file="$ID_LIST_FILE" -v cnt_file="$_cnt_file" '
                function normalized_id(line,    value) {
                    value=line
                    if (value ~ /^- id:/) sub(/^- id:[[:space:]]*/, "", value)
                    else if (value ~ /^  id:/) sub(/^  id:[[:space:]]*/, "", value)
                    else return ""
                    gsub(/^[ \t'"'"'"]*/, "", value)
                    gsub(/[ \t'"'"'"]*$/, "", value)
                    return value
                }
                function flush_record(    i,record_id,line) {
                    if (record_count == 0) return
                    record_id=""
                    for (i=1; i<=record_count; i++) {
                        if (record[i] ~ /^- id:/ || record[i] ~ /^  id:/) {
                            record_id=normalized_id(record[i])
                            break
                        }
                    }
                    for (i=1; i<=record_count; i++) {
                        line=record[i]
                        if (record_id in wanted && line ~ /^  read:[[:space:]]*false[[:space:]]*$/) {
                            sub(/read:[[:space:]]*false[[:space:]]*$/, "read: true", line)
                            changed++
                        }
                        print line
                    }
                    delete record
                    record_count=0
                }
                BEGIN {
                    changed=0
                    record_count=0
                    while ((getline wanted_id < id_file) > 0) wanted[wanted_id]=1
                    close(id_file)
                }
                {
                    if ($0 ~ /^- /) {
                        flush_record()
                        record[++record_count]=$0
                    } else if (record_count > 0) {
                        record[++record_count]=$0
                    } else {
                        print
                    }
                }
                END {
                    flush_record()
                    print changed > cnt_file
                }
            ' "$INBOX" > "$_tmp" || { rm -f "$_tmp" "$_cnt_file"; exit 1; }
            read -r _changed < "$_cnt_file" 2>/dev/null || _changed=0
            rm -f "$_cnt_file"
        fi

        if [ "${_changed:-0}" -eq 0 ]; then
            rm -f "$_tmp"
            if [ -n "$MSG_ID" ]; then
                echo "[inbox_mark_read] ERROR: msg_id=$MSG_ID not found or already read" >&2
                exit 2
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
        rm -f "$ID_LIST_FILE"
        exit 0
    else
        operation_rc=$?
        rm -f "$CONFIRM_LIST_FILE" "$ID_LIST_FILE"
        # Contract/state mismatches are semantic failures, not lock contention.
        # Preserve them for callers instead of retrying and collapsing them to rc=1.
        if [ "$operation_rc" -eq 2 ]; then
            exit 2
        fi
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
