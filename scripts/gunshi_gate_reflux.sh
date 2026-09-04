#!/usr/bin/env bash
# gunshi_gate_reflux.sh — GATE CLEAR時に軍師レビューログのgate_resultを自動更新
# Usage: bash scripts/gunshi_gate_reflux.sh <cmd_id> <gate_result>
# cmd_complete_gate.shのGATE CLEARセクションから呼び出される（ベストエフォート）

set -euo pipefail

CMD_ID="${1:?Usage: gunshi_gate_reflux.sh <cmd_id> <gate_result>}"
GATE_RESULT="${2:?Usage: gunshi_gate_reflux.sh <cmd_id> <gate_result>}"
GATE_SYNCED_AT="$(date -Iseconds)"

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
LOG_FILE="${GUNSHI_REVIEW_LOG:-$SCRIPT_DIR/logs/gunshi_review_log.yaml}"
LEDGER_WRITER="$SCRIPT_DIR/scripts/ledger_writer.sh"
if [ -f "$SCRIPT_DIR/scripts/lib/publisher_single_flag.sh" ]; then
    source "$SCRIPT_DIR/scripts/lib/publisher_single_flag.sh"
else
    publisher_single_enabled() {
        local _publisher_root="${1:-${SCRIPT_DIR:-}}"
        [[ "${PUBLISHER_SINGLE:-0}" = 1 ]] || {
            [[ -n "$_publisher_root" && -f "$_publisher_root/queue/flags/publisher_single" ]]
        }
    }
fi

case "$GATE_RESULT" in
    CLEAR|BLOCK|FAIL|WARN|N/A) ;;
    *)
        echo "gunshi_gate_reflux: invalid gate_result: $GATE_RESULT" >&2
        exit 1
        ;;
esac

if [ ! -f "$LOG_FILE" ]; then
    exit 0
fi

# During the single-publisher rollout the shared review log is immutable from
# the gate process.  Queue one generation-bound reflux operation instead of
# letting this legacy updater replace the root file directly.
if publisher_single_enabled "$SCRIPT_DIR"; then
    if [ ! -x "$LEDGER_WRITER" ]; then
        echo "gunshi_gate_reflux: BLOCK PUBLISHER_SINGLE requires executable ledger_writer.sh" >&2
        exit 2
    fi
    op_path="$(LEDGER_SOURCE_FILE="$LOG_FILE" bash "$LEDGER_WRITER" reflux review_log "$CMD_ID" "$GATE_RESULT" "$GATE_SYNCED_AT")"
    echo "  gunshi_gate_reflux: LEDGER-ROUTE queued op=$op_path (${CMD_ID} → ${GATE_RESULT})"
    exit 0
fi

# 該当cmd_idのエントリのgate_resultを更新する。
# - gate_result: null / "" は <GATE_RESULT> に置換
# - gate_resultフィールド不在の既存entryには review_type 直後へ挿入
# 同一cmd_idに複数エントリ(draft+report)がありえるので全て更新
# archiveファイルは対象外（LOG_FILEのみ操作）

# 方針: 行指向の状態機械。YAML全体の再serializeは禁止。
TMPFILE="${LOG_FILE}.tmp.$$"
COUNT_TMPFILE="/tmp/gunshi_gate_reflux_count.$$"
trap 'rm -f "$TMPFILE" "$COUNT_TMPFILE"' EXIT

source "$SCRIPT_DIR/scripts/lib/lock_path.sh"
LOCK_FILE="$(lock_path "$LOG_FILE")"

(
    flock -w 10 9
    python3 - "$CMD_ID" "$GATE_RESULT" "$GATE_SYNCED_AT" "$LOG_FILE" "$TMPFILE" <<'PY' >"$COUNT_TMPFILE"
import os
import re
import sys

cmd_id, gate_result, gate_synced_at, log_file, tmp_file = sys.argv[1:6]

try:
    with open(log_file, encoding="utf-8") as f:
        lines = f.readlines()
except FileNotFoundError:
    print(0)
    sys.exit(0)

cmd_re = re.compile(r'^- cmd_id:\s*["\']?' + re.escape(cmd_id) + r'["\']?\s*$')
entry_start_re = re.compile(r'^- cmd_id:')
top_level_re = re.compile(r'^[^- #\s][^:]*:')
gate_null_re = re.compile(r'^(\s*gate_result:\s*)(null|""|\'\')(\s*(?:#.*)?)$')
gate_any_re = re.compile(r'^\s*gate_result:')
gate_value_re = re.compile(r'^\s*gate_result:\s*["\']?([^"\'#\s]+)')
gate_synced_re = re.compile(r'^\s*gate_synced_at:')
review_type_re = re.compile(r'^\s*review_type:')

updated = 0
out = []
entry = []
match_cmd = False

def flush_entry():
    global updated
    if not entry:
        return
    if not match_cmd:
        out.extend(entry)
        return

    has_gate = any(gate_any_re.match(line) for line in entry)
    has_gate_synced = any(gate_synced_re.match(line) for line in entry)
    existing_values = [m.group(1) for line in entry if (m := gate_value_re.match(line))]
    # Preserve an already-final different result together with its original
    # timestamp.  Updating only gate_synced_at would falsely claim the stale
    # result was synchronized by this invocation.
    if existing_values and all(value not in {"null", gate_result} for value in existing_values):
        out.extend(entry)
        return
    local = []
    inserted = False
    local_updated = 0
    for line in entry:
        if gate_synced_re.match(line):
            line = re.sub(r'^(\s*gate_synced_at:\s*).*$' , rf'\g<1>{gate_synced_at}', line)
            local_updated = 1
        if gate_any_re.match(line):
            if gate_null_re.match(line):
                line = gate_null_re.sub(r'\1' + gate_result + r'\3', line)
                local_updated = 1
        local.append(line)
        if (not has_gate) and (not inserted) and review_type_re.match(line):
            local.append(f"  gate_result: {gate_result}\n")
            local.append(f"  gate_synced_at: {gate_synced_at}\n")
            inserted = True
            local_updated = 1
            has_gate = True
            has_gate_synced = True

    if (not has_gate) and (not inserted):
        insert_at = 1 if local else 0
        local.insert(insert_at, f"  gate_result: {gate_result}\n")
        local.insert(insert_at + 1, f"  gate_synced_at: {gate_synced_at}\n")
        local_updated = 1
        has_gate_synced = True
    elif has_gate and not has_gate_synced:
        gate_index = next((i for i, line in enumerate(local) if gate_any_re.match(line)), 0)
        local.insert(gate_index + 1, f"  gate_synced_at: {gate_synced_at}\n")
        local_updated = 1

    updated += local_updated
    out.extend(local)

for line in lines:
    if entry_start_re.match(line) or (entry and top_level_re.match(line)):
        flush_entry()
        entry = []
        match_cmd = False

    if entry_start_re.match(line):
        match_cmd = bool(cmd_re.match(line))
        entry.append(line)
    elif entry:
        entry.append(line)
    else:
        out.append(line)

flush_entry()

with open(tmp_file, "w", encoding="utf-8") as f:
    f.writelines(out)

print(updated)
PY

    # The replacement belongs to the same critical section as the read and
    # transform.  Moving after flock release lets two concurrent reflux runs
    # overwrite each other's updates with stale snapshots.
    read -r UPDATE_COUNT < "$COUNT_TMPFILE" 2>/dev/null || UPDATE_COUNT="0"
    if [ "$UPDATE_COUNT" -gt 0 ]; then
        mv "$TMPFILE" "$LOG_FILE"
    else
        rm -f "$TMPFILE"
    fi
) 9>"$LOCK_FILE"

read -r UPDATE_COUNT < "$COUNT_TMPFILE" 2>/dev/null || UPDATE_COUNT="0"

if [ "$UPDATE_COUNT" -gt 0 ]; then
    echo "  gunshi_gate_reflux: ${UPDATE_COUNT} entries updated (${CMD_ID} → ${GATE_RESULT})"
fi
