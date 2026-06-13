#!/usr/bin/env bash
# gunshi_gate_reflux.sh — GATE CLEAR時に軍師レビューログのgate_resultを自動更新
# Usage: bash scripts/gunshi_gate_reflux.sh <cmd_id> <gate_result>
# cmd_complete_gate.shのGATE CLEARセクションから呼び出される（ベストエフォート）

set -euo pipefail

CMD_ID="${1:?Usage: gunshi_gate_reflux.sh <cmd_id> <gate_result>}"
GATE_RESULT="${2:?Usage: gunshi_gate_reflux.sh <cmd_id> <gate_result>}"

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
LOG_FILE="${GUNSHI_REVIEW_LOG:-$SCRIPT_DIR/logs/gunshi_review_log.yaml}"

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
    python3 - "$CMD_ID" "$GATE_RESULT" "$LOG_FILE" "$TMPFILE" <<'PY' >"$COUNT_TMPFILE"
import os
import re
import sys

cmd_id, gate_result, log_file, tmp_file = sys.argv[1:5]

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
    local = []
    inserted = False
    local_updated = 0
    for line in entry:
        if gate_any_re.match(line):
            if gate_null_re.match(line):
                line = gate_null_re.sub(r'\1' + gate_result + r'\3', line)
                local_updated += 1
        local.append(line)
        if (not has_gate) and (not inserted) and review_type_re.match(line):
            local.append(f"  gate_result: {gate_result}\n")
            inserted = True
            local_updated += 1
            has_gate = True

    if (not has_gate) and (not inserted):
        insert_at = 1 if local else 0
        local.insert(insert_at, f"  gate_result: {gate_result}\n")
        local_updated += 1

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
) 9>"$LOCK_FILE"

read -r UPDATE_COUNT < "$COUNT_TMPFILE" 2>/dev/null || UPDATE_COUNT="0"

if [ "$UPDATE_COUNT" -gt 0 ]; then
    mv "$TMPFILE" "$LOG_FILE"
    echo "  gunshi_gate_reflux: ${UPDATE_COUNT} entries updated (${CMD_ID} → ${GATE_RESULT})"
fi
