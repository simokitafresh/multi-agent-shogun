#!/bin/bash
# Common, sourceable JSONL writer for defense/gate timing events.

DEFENSE_OVERHEAD_REPO_ROOT="${DEFENSE_OVERHEAD_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

defense_overhead_write() {
    local source_name="${1:-}" check_id="${2:-}" wall_ms="${3:-}"
    local verdict="${4:-}" event_id="${5:-}"
    local ledger="${DEFENSE_OVERHEAD_LEDGER:-${DEFENSE_OVERHEAD_REPO_ROOT}/logs/defense_overhead.jsonl}"
    local lock_file="${ledger}.lock" line

    [ "${DEFENSE_OVERHEAD_ENABLED:-1}" = "1" ] || return 0
    [[ "$source_name" =~ ^[A-Za-z0-9_.:-]+$ ]] || return 2
    [[ "$check_id" =~ ^[A-Za-z0-9_.:-]+$ ]] || return 2
    [[ "$wall_ms" =~ ^[0-9]+$ ]] || return 2
    [[ "$verdict" =~ ^(PASS|FAIL|BLOCK|WARN)$ ]] || return 2
    [[ "$event_id" =~ ^[A-Za-z0-9_.:-]+$ ]] || return 2
    [ -d "$(dirname "$ledger")" ] || return 3

    line="$(python3 - "$source_name" "$check_id" "$wall_ms" "$verdict" "$event_id" <<'PY'
import datetime, json, sys
source, check_id, wall_ms, verdict, event_id = sys.argv[1:]
print(json.dumps({
    "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "source": source, "check_id": check_id, "wall_ms": int(wall_ms),
    "verdict": verdict, "event_id": event_id,
}, ensure_ascii=False, separators=(",", ":")))
PY
    )" || return 3

    exec {DEFENSE_OVERHEAD_FD}>>"$lock_file" || return 3
    flock -w "${DEFENSE_OVERHEAD_LOCK_TIMEOUT:-2}" "$DEFENSE_OVERHEAD_FD" || {
        eval "exec ${DEFENSE_OVERHEAD_FD}>&-"; return 3;
    }
    if [ -f "$ledger" ] && grep -Fq "\"event_id\":\"${event_id}\"" "$ledger"; then
        flock -u "$DEFENSE_OVERHEAD_FD"; eval "exec ${DEFENSE_OVERHEAD_FD}>&-"; return 4
    fi
    printf '%s\n' "$line" >>"$ledger" || {
        flock -u "$DEFENSE_OVERHEAD_FD"; eval "exec ${DEFENSE_OVERHEAD_FD}>&-"; return 3;
    }
    flock -u "$DEFENSE_OVERHEAD_FD"
    eval "exec ${DEFENSE_OVERHEAD_FD}>&-"
}

defense_overhead_write_async() {
    [ "${DEFENSE_OVERHEAD_ENABLED:-1}" = "1" ] || return 0
    ( defense_overhead_write "$@" ) >/dev/null 2>&1 &
    return 0
}
