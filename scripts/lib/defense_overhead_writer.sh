#!/bin/bash
# Common, sourceable JSONL writer for defense/gate timing events.

DEFENSE_OVERHEAD_REPO_ROOT="${DEFENSE_OVERHEAD_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DEFENSE_OVERHEAD_ASYNC_PIDS=()
SELF_RETRO_ASYNC_PIDS=()

defense_overhead_write() {
    local source_name="${1:-}" check_id="${2:-}" wall_ms="${3:-}"
    local verdict="${4:-}" event_id="${5:-}" metadata_json="${6-}"
    local ledger="${DEFENSE_OVERHEAD_LEDGER:-${DEFENSE_OVERHEAD_REPO_ROOT}/logs/defense_overhead.jsonl}"
    local lock_file="${ledger}.lock" line index_file index_lock helper prepare_rc append_rc
    local max_bytes="${DEFENSE_OVERHEAD_MAX_BYTES:-67108864}"
    local keep_lines="${DEFENSE_OVERHEAD_KEEP_LINES:-50000}"

    [ "${DEFENSE_OVERHEAD_ENABLED:-1}" = "1" ] || return 0
    [[ "$source_name" =~ ^[A-Za-z0-9_.:-]+$ ]] || return 2
    [[ "$check_id" =~ ^[A-Za-z0-9_.:-]+$ ]] || return 2
    [[ "$wall_ms" =~ ^[0-9]+$ ]] || return 2
    [[ "$verdict" =~ ^(PASS|FAIL|BLOCK|WARN)$ ]] || return 2
    [[ "$event_id" =~ ^[A-Za-z0-9_.:-]+$ ]] || return 2
    [[ "$max_bytes" =~ ^[0-9]+$ && "$keep_lines" =~ ^[0-9]+$ ]] || return 2
    [ -d "$(dirname "$ledger")" ] || return 3
    [ -n "$metadata_json" ] || metadata_json='{}'
    # agent=実行者(cmd_4478 §6.1-4)。SHOGUN_AGENT_ID → TMUX_PANE が有効な時だけその pane の @agent_id → '-'。
    # target 無指定の tmux display は multi-client で別 pane に誤帰属するため必ず -t を付ける。fail-open(解決不能でも書く)。
    local agent="${SHOGUN_AGENT_ID:-}"
    if [ -z "$agent" ] && [ -n "${TMUX_PANE:-}" ]; then
        agent="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
    fi
    [[ "$agent" =~ ^[a-z0-9_-]{1,32}$ ]] || agent='-'

    line="$(python3 - "$source_name" "$check_id" "$wall_ms" "$verdict" "$event_id" "$metadata_json" "$agent" <<'PY'
import datetime, json, sys
source, check_id, wall_ms, verdict, event_id, metadata_raw, agent = sys.argv[1:]
try:
    metadata = json.loads(metadata_raw)
except (TypeError, ValueError):
    raise SystemExit(2)
if not isinstance(metadata, dict):
    raise SystemExit(2)
reserved = {"timestamp", "source", "check_id", "wall_ms", "verdict", "event_id", "agent"}
if reserved.intersection(metadata) or any(
    not isinstance(key, str) or not isinstance(value, (str, int, float, bool)) or value is None
    for key, value in metadata.items()
):
    raise SystemExit(2)
row = {
    "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "source": source, "check_id": check_id, "wall_ms": int(wall_ms),
    "verdict": verdict, "event_id": event_id, "agent": agent,
}
row.update(metadata)
print(json.dumps(row, ensure_ascii=False, separators=(",", ":")))
PY
    )" || return 3

    # The 69MB production ledger lives on DrvFS.  Scanning it while holding the
    # append lock made otherwise unrelated writers exceed their 2s lock budget.
    # Keep an exact UNIQUE event_id index on ext4 and build/rebuild it outside
    # the ledger lock.  The helper records ledger device/inode/offset and, while
    # the append lock is held below, reconciles every tail row before querying
    # or appending.  Thus a crash after the JSONL append can only make the
    # sidecar stale; the next writer repairs it from the immutable ledger tail.
    helper="${DEFENSE_OVERHEAD_REPO_ROOT}/scripts/lib/defense_overhead_event_index.py"
    [ -f "$helper" ] || return 3
    if [ -n "${DEFENSE_OVERHEAD_INDEX:-}" ]; then
        index_file="$DEFENSE_OVERHEAD_INDEX"
    elif [[ "$ledger" == /mnt/c/* || "$ledger" == /mnt/d/* ]] \
        && [ -f "${DEFENSE_OVERHEAD_REPO_ROOT}/scripts/lib/lock_path.sh" ]; then
        # shellcheck source=scripts/lib/lock_path.sh
        source "${DEFENSE_OVERHEAD_REPO_ROOT}/scripts/lib/lock_path.sh"
        index_lock="$(lock_path "${ledger}.event-index")"
        index_file="${index_lock%.lock}.sqlite3"
    else
        index_file="${ledger}.event-index.sqlite3"
    fi
    index_lock="${index_file}.build.lock"
    exec {DEFENSE_OVERHEAD_INDEX_FD}>>"$index_lock" || return 3
    flock -w "${DEFENSE_OVERHEAD_INDEX_BUILD_TIMEOUT:-120}" "$DEFENSE_OVERHEAD_INDEX_FD" || {
        eval "exec ${DEFENSE_OVERHEAD_INDEX_FD}>&-"; return 3;
    }
    # Keep the tracked hot ledger below GitHub's 100 MiB hard limit.  Rotation
    # owns the same index-build -> append lock order as every writer, so no row
    # can land between the size check and the atomic generation change.  Full
    # history remains in the ignored logs/archive directory; the tracked file
    # retains a bounded recent window for existing consumers.
    if [ -f "$ledger" ] && [ "$(stat -c %s "$ledger" 2>/dev/null || echo 0)" -gt "$max_bytes" ]; then
        exec {DEFENSE_OVERHEAD_ROTATE_FD}>>"$lock_file" || {
            flock -u "$DEFENSE_OVERHEAD_INDEX_FD"
            eval "exec ${DEFENSE_OVERHEAD_INDEX_FD}>&-"
            return 3
        }
        flock -w "${DEFENSE_OVERHEAD_LOCK_TIMEOUT:-2}" "$DEFENSE_OVERHEAD_ROTATE_FD" || {
            eval "exec ${DEFENSE_OVERHEAD_ROTATE_FD}>&-"
            flock -u "$DEFENSE_OVERHEAD_INDEX_FD"
            eval "exec ${DEFENSE_OVERHEAD_INDEX_FD}>&-"
            return 3
        }
        if [ "$(stat -c %s "$ledger" 2>/dev/null || echo 0)" -gt "$max_bytes" ]; then
            archive_dir="$(dirname "$ledger")/archive"
            mkdir -p "$archive_dir"
            archive_file="$archive_dir/defense_overhead_$(date -u +%Y%m%dT%H%M%S)_$(stat -c %i "$ledger").jsonl"
            rotated_tmp="${ledger}.rotate.$$"
            mv -- "$ledger" "$archive_file" || append_rc=3
            if [ "${append_rc:-0}" -eq 0 ]; then
                tail -n "$keep_lines" "$archive_file" > "$rotated_tmp" || append_rc=3
                mv -- "$rotated_tmp" "$ledger" || append_rc=3
            fi
            rm -f -- "$rotated_tmp"
        fi
        flock -u "$DEFENSE_OVERHEAD_ROTATE_FD"
        eval "exec ${DEFENSE_OVERHEAD_ROTATE_FD}>&-"
        [ "${append_rc:-0}" -eq 0 ] || {
            flock -u "$DEFENSE_OVERHEAD_INDEX_FD"
            eval "exec ${DEFENSE_OVERHEAD_INDEX_FD}>&-"
            return 3
        }
    fi
    prepare_rc=0
    python3 "$helper" prepare "$ledger" "$index_file" || prepare_rc=$?
    flock -u "$DEFENSE_OVERHEAD_INDEX_FD"
    eval "exec ${DEFENSE_OVERHEAD_INDEX_FD}>&-"
    [ "$prepare_rc" -eq 0 ] || return 3

    exec {DEFENSE_OVERHEAD_FD}>>"$lock_file" || return 3
    flock -w "${DEFENSE_OVERHEAD_LOCK_TIMEOUT:-2}" "$DEFENSE_OVERHEAD_FD" || {
        eval "exec ${DEFENSE_OVERHEAD_FD}>&-"; return 3;
    }
    append_rc=0
    python3 "$helper" append "$ledger" "$index_file" "$line" "$event_id" || append_rc=$?
    flock -u "$DEFENSE_OVERHEAD_FD"
    eval "exec ${DEFENSE_OVERHEAD_FD}>&-"
    [ "$append_rc" -eq 0 ] && return 0
    [ "$append_rc" -eq 4 ] && return 4
    return 3
}

defense_overhead_write_async() {
    [ "${DEFENSE_OVERHEAD_ENABLED:-1}" = "1" ] || return 0
    ( defense_overhead_write "$@" ) >/dev/null 2>&1 &
    DEFENSE_OVERHEAD_ASYNC_PIDS+=("$!")
    return 0
}

# The caller owns the temporary ledger directory and must wait for every
# detached telemetry writer before its process exits.  This preserves the
# non-blocking call contract while preventing the shell from orphaning the
# writer during parallel inbox delivery.
defense_overhead_drain_async() {
    local pid
    for pid in "${DEFENSE_OVERHEAD_ASYNC_PIDS[@]}"; do
        wait "$pid" || true
    done
    DEFENSE_OVERHEAD_ASYNC_PIDS=()
}

# Submit multiple five-field events through one detached subshell so hot-path
# callers pay one fork regardless of the number of timing checkpoints.
defense_overhead_write_batch_async() {
    [ "${DEFENSE_OVERHEAD_ENABLED:-1}" = "1" ] || return 0
    [ $(( $# % 5 )) -eq 0 ] || return 0
    (
        while [ "$#" -ge 5 ]; do
            defense_overhead_write "$1" "$2" "$3" "$4" "$5" || true
            shift 5
        done
    ) >/dev/null 2>&1 &
    DEFENSE_OVERHEAD_ASYNC_PIDS+=("$!")
    return 0
}

# Deep post-terminal retrospective.  This deliberately has its own append-only
# ledger so the stable defense_overhead.jsonl schema remains backward compatible.
_self_retro_should_emit_insight() {
    local ledger="$1" improvement="$2" wall_ms="$3" phase_ms_json="$4" threshold="$5"
    python3 - "$ledger" "$improvement" "$wall_ms" "$phase_ms_json" "$threshold" <<'PY'
import json, sys

ledger, improvement, wall_ms, phases_raw, threshold = sys.argv[1:]
phases = json.loads(phases_raw)
seen = 0
try:
    with open(ledger, encoding="utf-8") as fh:
        for raw in fh:
            try:
                row = json.loads(raw)
            except (TypeError, ValueError):
                continue
            seen += row.get("improvement_candidate") == improvement
except OSError:
    raise SystemExit(0)

known_template = seen >= int(threshold)
zero_signal = int(wall_ms) == 0 or max(phases.values()) == 0
raise SystemExit(1 if known_template and zero_signal else 0)
PY
}

self_retro_write() {
    local endpoint="${1:-}" task_id="${2:-}" wall_ms="${3:-}" phase_ms_json="${4:-}"
    local cause_class="${5:-}" cause_structure="${6:-}" improvement="${7:-}"
    local binary_criterion="${8:-}" origin="${9:-}"
    local ledger="${SELF_RETRO_LEDGER:-${DEFENSE_OVERHEAD_REPO_ROOT}/logs/self_retro.jsonl}"
    local lock_file="${ledger}.lock" line event_id
    [[ "$endpoint" =~ ^(ninja_report|karo_cmd_complete|gunshi_review_bundle|shogun_gate_clear)$ ]] || return 2
    [[ "$task_id" =~ ^cmd_[A-Za-z0-9_]+$ ]] || return 2
    [[ "$wall_ms" =~ ^[0-9]+$ ]] || return 2
    [ -d "$(dirname "$ledger")" ] || return 3
    line="$(python3 - "$endpoint" "$task_id" "$wall_ms" "$phase_ms_json" "$cause_class" "$cause_structure" "$improvement" "$binary_criterion" "$origin" <<'PY'
import datetime, hashlib, json, sys
endpoint, task_id, wall_ms, phases, cause_class, cause, improvement, criterion, origin = sys.argv[1:]
try: phases = json.loads(phases)
except (TypeError, ValueError): raise SystemExit(2)
if not isinstance(phases, dict) or not phases or any(not isinstance(v, int) or isinstance(v, bool) or v < 0 for v in phases.values()): raise SystemExit(2)
if not all(x.strip() for x in (cause_class, cause, improvement, criterion, origin)): raise SystemExit(2)
event_id = hashlib.sha256((endpoint + "\0" + task_id).encode()).hexdigest()
print(json.dumps({"timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(), "event_id": event_id,
 "endpoint": endpoint, "task_id": task_id, "wall_ms": int(wall_ms), "phase_ms": phases,
 "cause_class": cause_class, "cause_structure": cause, "improvement_candidate": improvement,
 "binary_criterion": criterion, "origin": origin}, ensure_ascii=False, separators=(",", ":")))
PY
    )" || return 2
    event_id="$(printf '%s' "$line" | sed -n 's/.*"event_id":"\([^"]*\)".*/\1/p')"
    exec {SELF_RETRO_FD}>>"$lock_file" || return 3
    flock -w "${SELF_RETRO_LOCK_TIMEOUT:-1}" "$SELF_RETRO_FD" || { eval "exec ${SELF_RETRO_FD}>&-"; return 3; }
    if [ -f "$ledger" ] && grep -Fq "\"event_id\":\"${event_id}\"" "$ledger"; then
        flock -u "$SELF_RETRO_FD"; eval "exec ${SELF_RETRO_FD}>&-"; return 4
    fi
    printf '%s\n' "$line" >>"$ledger" || { flock -u "$SELF_RETRO_FD"; eval "exec ${SELF_RETRO_FD}>&-"; return 3; }
    flock -u "$SELF_RETRO_FD"; eval "exec ${SELF_RETRO_FD}>&-"
    local repeats
    repeats="$(grep -Fc "\"cause_class\":\"${cause_class}\"" "$ledger" 2>/dev/null || true)"
    if [ "${repeats:-0}" -ge "${SELF_RETRO_FIX_KNOWN_THRESHOLD:-3}" ] \
      && _self_retro_should_emit_insight "$ledger" "$improvement" "$wall_ms" "$phase_ms_json" "${SELF_RETRO_FIX_KNOWN_THRESHOLD:-3}" \
      && [ -x "${DEFENSE_OVERHEAD_REPO_ROOT}/scripts/insight_write.sh" ]; then
        INSIGHT_FIX_KNOWN=true INSIGHT_TARGET_FILE="$ledger" INSIGHT_VERIFY_COMMAND="grep -Fq '$event_id' '$ledger'" \
          bash "${DEFENSE_OVERHEAD_REPO_ROOT}/scripts/insight_write.sh" \
          "self-retro dominant cause=${cause_class}; candidate=${improvement}; criterion=${binary_criterion}" high self_retro >/dev/null 2>&1 || true
    fi
}

self_retro_write_async() {
    local endpoint="${1:-}" task_id="${2:-}" wall_ms="${3:-}"
    ( self_retro_write "$@" || defense_overhead_write self_retro "${endpoint}" "${wall_ms:-0}" WARN "self-retro-fallback-${task_id}-${endpoint}" || true ) >/dev/null 2>&1 &
    SELF_RETRO_ASYNC_PIDS+=("$!")
    return 0
}

# The shell that owns async self-retro submissions must drain them before it
# tears down their ledger directory. Writer failures remain non-blocking, but
# process lifetime is explicit instead of racing filesystem cleanup.
self_retro_drain() {
    local pid
    for pid in "${SELF_RETRO_ASYNC_PIDS[@]}"; do
        wait "$pid" || true
    done
    SELF_RETRO_ASYNC_PIDS=()
}
