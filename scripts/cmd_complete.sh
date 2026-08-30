#!/usr/bin/env bash
# cmd_complete.sh — SG7 GATE CLEAR後の既存完了処理を順序保証して直列実行
# Usage: bash scripts/cmd_complete.sh <cmd_id> [sg7_bundle.json]

set -euo pipefail

CMD_ID="${1:-}"
if [[ ! "$CMD_ID" =~ ^cmd_[A-Za-z0-9_]+$ ]]; then
    printf 'Usage: cmd_complete.sh <cmd_id> [sg7_bundle.json]\n' >&2
    exit 2
fi

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${CMD_COMPLETE_SCRIPT_DIR:-$SELF_DIR}"
ROOT_DIR="${CMD_COMPLETE_ROOT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=scripts/lib/defense_overhead_writer.sh
source "$ROOT_DIR/scripts/lib/defense_overhead_writer.sh"
CMD_COMPLETE_STARTED_MS="$(date +%s%3N)"
declare -A CMD_COMPLETE_STEP_MS=()
BUNDLE_PATH="${2:-queue/gates/${CMD_ID}/sg7_bundle.json}"
[[ "$BUNDLE_PATH" = /* ]] || BUNDLE_PATH="$ROOT_DIR/$BUNDLE_PATH"

# Internal entry point for the one durable completion worker. It runs the
# whole gate exactly once, persists its terminal result, then re-enters the
# checkpointed wrapper to finish quality/status/archive/dashboard/notification.
if [[ "${CMD_COMPLETE_GATE_WORKER:-0}" = "1" ]]; then
    _worker_checkpoint_dir="${CMD_COMPLETE_CHECKPOINT_DIR:?}"
    _worker_generation="${SHOGUN_COMPLETION_GENERATION:?}"
    _worker_snapshot="${CMD_COMPLETE_SOURCE_SNAPSHOT:?}"
    _worker_clear_marker="$_worker_checkpoint_dir/gate_worker.clear.json"
    _worker_success_marker="$_worker_checkpoint_dir/gate_worker.success.json"
    _worker_failure_marker="$_worker_checkpoint_dir/gate_worker.failed.json"
    _write_worker_marker() {
        python3 - "$1" "$2" "$CMD_ID" "$_worker_generation" "$3" <<'PY'
import json, os, sys, tempfile, time
path, state, cmd_id, generation, rc = sys.argv[1:]
data = {"version": 1, "state": state, "cmd_id": cmd_id,
        "completion_generation": generation, "rc": int(rc),
        "persisted_at_ns": time.time_ns()}
fd, tmp = tempfile.mkstemp(prefix=".gate_worker_marker.", dir=os.path.dirname(path))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(data, fh, sort_keys=True); fh.write("\n"); fh.flush(); os.fsync(fh.fileno())
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
    }
    if env CMD_COMPLETE_WRAPPER_ACTIVE=1 \
        CMD_COMPLETE_GATE_CLEAR_MARKER="$_worker_clear_marker" \
        SHOGUN_COMPLETION_GENERATION="$_worker_generation" \
        bash "$SCRIPT_DIR/cmd_complete_gate.sh" "$CMD_ID"; then
        # cmd_complete_gate may return from its Already-CLEAR fast path before
        # it sees CMD_COMPLETE_GATE_CLEAR_MARKER. The worker itself owns the
        # generation-bound success boundary, so publish the same durable clear
        # receipt on every successful gate return before continuation.
        _write_worker_marker "$_worker_clear_marker" clear 0 || exit 98
        _write_worker_marker "$_worker_success_marker" success 0 || exit 98
    else
        _worker_rc=$?
        _write_worker_marker "$_worker_failure_marker" failed "$_worker_rc" || exit 99
        exit "$_worker_rc"
    fi
    exec env CMD_COMPLETE_GATE_WORKER=0 CMD_COMPLETE_GATE_CONTINUATION=1 \
        CMD_COMPLETE_ASYNC_TAIL_WORKER=1 \
        CMD_COMPLETE_ROOT_DIR="$ROOT_DIR" CMD_COMPLETE_SCRIPT_DIR="$SCRIPT_DIR" \
        CMD_COMPLETE_CHECKPOINT_DIR="$_worker_checkpoint_dir" \
        CMD_COMPLETE_SOURCE_SNAPSHOT="$_worker_snapshot" \
        bash "$_worker_snapshot" "$CMD_ID" "$BUNDLE_PATH"
fi

CHECKPOINT_DIR="${CMD_COMPLETE_CHECKPOINT_DIR:-$ROOT_DIR/queue/gates/$CMD_ID}"
CHECKPOINT_PATH="$CHECKPOINT_DIR/completion_checkpoint.json"
CHECKPOINT_LOCK="$CHECKPOINT_DIR/completion_checkpoint.lock"
mkdir -p "$CHECKPOINT_DIR"
exec 9>"$CHECKPOINT_LOCK"
flock 9

[[ -f "$BUNDLE_PATH" ]] || { printf '[cmd_complete] FAILED bundle missing: %s\n' "$BUNDLE_PATH" >&2; exit 1; }
BUNDLE_IDENTITY="$(python3 - "$BUNDLE_PATH" "$CMD_ID" <<'PY'
import json, re, sys
review = (json.load(open(sys.argv[1], encoding="utf-8")) or {}).get("review") or {}
cmd_id = str(review.get("cmd_id") or "")
generation = str(review.get("report_fingerprint") or "")
if cmd_id != sys.argv[2]:
    raise SystemExit("[cmd_complete] FAILED bundle review.cmd_id mismatch")
if not re.fullmatch(r"[0-9a-f]{64}", generation):
    raise SystemExit("[cmd_complete] FAILED bundle review.report_fingerprint missing/invalid")
print(generation)
PY
)" || exit 1
export SHOGUN_COMPLETION_GENERATION="$BUNDLE_IDENTITY"
BUNDLE_FINGERPRINT="$(sha256sum "$BUNDLE_PATH" | awk '{print $1}')"

# A completed report remains at its logical queue path as a compatibility
# symlink. It is terminal only when it resolves inside the archive report
# root and matches the exact completion generation. Other links stay active
# so completion fails closed instead of trusting a stale or escaped target.
completion_report_symlink_is_terminal() {
    local report_file="$1" archive_dir target expected target_hash link_hash
    [[ -L "$report_file" ]] || return 1
    archive_dir="$(realpath -e -- "$ROOT_DIR/queue/archive/reports" 2>/dev/null)" || return 1
    target="$(realpath -e -- "$report_file" 2>/dev/null)" || return 1
    case "$target" in
        "$archive_dir"/*) ;;
        *) return 1 ;;
    esac
    [[ -f "$target" ]] || return 1
    expected="${SHOGUN_COMPLETION_GENERATION:-${BUNDLE_IDENTITY:-}}"
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
    target_hash="$(sha256sum -- "$target" 2>/dev/null | awk '{print $1}')" || return 1
    link_hash="$(sha256sum -- "$report_file" 2>/dev/null | awk '{print $1}')" || return 1
    [[ "$target_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ "$link_hash" == "$target_hash" && "$target_hash" == "$expected" ]]
}

completion_report_parent_cmd_matches() {
    local report_file="$1" expected_cmd="$2"
    python3 - "$report_file" "$expected_cmd" <<'PY'
import sys

import yaml

path, expected = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as fh:
        report = yaml.safe_load(fh) or {}
except Exception:
    # An unreadable matching report is still active; archive_terminal must not
    # silently treat an unresolved identity as completed.
    raise SystemExit(0)

if not isinstance(report, dict):
    raise SystemExit(0)

parent_cmd = report.get("parent_cmd")
if parent_cmd is None:
    # Legacy reports without identity metadata remain active fail-closed.
    raise SystemExit(0)
raise SystemExit(0 if str(parent_cmd) == expected else 1)
PY
}

completion_active_report_count() {
    local report_file count=0
    while IFS= read -r -d '' report_file; do
        if [[ -L "$report_file" ]] && completion_report_symlink_is_terminal "$report_file"; then
            continue
        fi
        count=$((count + 1))
    done < <(find "$ROOT_DIR/queue/reports" -maxdepth 1 \
        \( -type f -o -type l \) ! -name '.*' \
        -name "*_report_${CMD_ID}.yaml" -print0 2>/dev/null \
        | while IFS= read -r -d '' report_file; do
            if completion_report_parent_cmd_matches "$report_file" "$CMD_ID"; then
                printf '%s\0' "$report_file"
            fi
        done)
    printf '%s\n' "$count"
}

# Bash reads a script incrementally.  A deploy/rebuild which replaces this
# canonical file while the detached tail is still running can therefore make
# the already-running shell parse a different generation halfway through
# (for example, a trailing fragment becomes ``point: command not found``).
# Freeze the complete source before any checkpoint work and re-enter from that
# immutable copy.  Preserve the operational roots because the snapshot lives
# below CHECKPOINT_DIR, not below the source script directory.
CMD_COMPLETE_SOURCE_SNAPSHOT="${CMD_COMPLETE_SOURCE_SNAPSHOT:-}"
if [[ -z "$CMD_COMPLETE_SOURCE_SNAPSHOT" ]]; then
    _cmd_complete_source_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    _cmd_complete_snapshot_tmp="$(mktemp "$CHECKPOINT_DIR/.cmd_complete_source.XXXXXX.sh")"
    if ! cp -- "$_cmd_complete_source_file" "$_cmd_complete_snapshot_tmp"; then
        rm -f -- "$_cmd_complete_snapshot_tmp"
        printf '[cmd_complete] FAILED source snapshot copy: %s\n' "$_cmd_complete_source_file" >&2
        exit 1
    fi
    chmod 700 "$_cmd_complete_snapshot_tmp"
    CMD_COMPLETE_SOURCE_SNAPSHOT="$_cmd_complete_snapshot_tmp"
    export CMD_COMPLETE_SOURCE_SNAPSHOT
    export CMD_COMPLETE_ROOT_DIR="$ROOT_DIR"
    export CMD_COMPLETE_SCRIPT_DIR="$SCRIPT_DIR"
    export CMD_COMPLETE_CHECKPOINT_DIR="$CHECKPOINT_DIR"
    exec bash "$CMD_COMPLETE_SOURCE_SNAPSHOT" "$@"
fi
STEP_ORDER=(sg7_consume lesson_review cmd_complete_gate quality_log status_completed archive_terminal dashboard ntfy inbox_archive)

checkpoint_init() {
    python3 - "$CHECKPOINT_PATH" "$CMD_ID" "$BUNDLE_FINGERPRINT" "${STEP_ORDER[@]}" <<'PY'
import json, os, sys, tempfile
path, cmd_id, fingerprint, *order = sys.argv[1:]
data = None
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        raise SystemExit(f"[cmd_complete] FAILED corrupt checkpoint: {exc}")
    required = {"version", "cmd_id", "bundle_fingerprint", "completed", "project"}
    if set(data) != required or data["version"] != 1 or data["cmd_id"] != cmd_id:
        raise SystemExit("[cmd_complete] FAILED invalid checkpoint identity/schema")
    completed = data["completed"]
    if not isinstance(completed, list) or completed != order[:len(completed)]:
        raise SystemExit("[cmd_complete] FAILED checkpoint step order/prefix invalid")
if data is None or data["bundle_fingerprint"] != fingerprint:
    data = {"version": 1, "cmd_id": cmd_id, "bundle_fingerprint": fingerprint,
            "completed": [], "project": ""}
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".completion_checkpoint.", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, sort_keys=True)
            fh.write("\n")
            fh.flush(); os.fsync(fh.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)
PY
}

checkpoint_has() {
    python3 - "$CHECKPOINT_PATH" "$1" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh: data = json.load(fh)
raise SystemExit(0 if sys.argv[2] in data["completed"] else 1)
PY
}

checkpoint_project() {
    python3 - "$CHECKPOINT_PATH" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh: print(json.load(fh)["project"])
PY
}

checkpoint_mark() {
    local step="$1" project="${2:-}"
    python3 - "$CHECKPOINT_PATH" "$step" "$project" "${STEP_ORDER[@]}" <<'PY'
import json, os, sys, tempfile
path, step, project, *order = sys.argv[1:]
with open(path, encoding="utf-8") as fh: data = json.load(fh)
expected = order[len(data["completed"])] if len(data["completed"]) < len(order) else None
if step != expected:
    raise SystemExit(f"[cmd_complete] FAILED checkpoint step leap: expected={expected} actual={step}")
data["completed"].append(step)
if project: data["project"] = project
fd, tmp = tempfile.mkstemp(prefix=".completion_checkpoint.", dir=os.path.dirname(path))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(data, fh, sort_keys=True); fh.write("\n"); fh.flush(); os.fsync(fh.fileno())
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
}

run_checkpointed() {
    local name="$1"
    shift
    if checkpoint_has "$name"; then
        printf '[cmd_complete] SKIP %s checkpoint_verified\n' "$name" >&2
        return 0
    fi
    run_step "$name" "$@"
    checkpoint_mark "$name"
}

checkpoint_init

run_step() {
    local name="$1"
    local started_ms elapsed_ms
    shift
    started_ms="$(date +%s%3N)"
    printf '[cmd_complete] START %s\n' "$name" >&2
    if "$@"; then
        elapsed_ms=$(( $(date +%s%3N) - started_ms ))
        CMD_COMPLETE_STEP_MS["$name"]="$elapsed_ms"
        printf '[cmd_complete] PASS %s wall_ms=%d\n' "$name" "$elapsed_ms" >&2
    else
        local rc=$?
        elapsed_ms=$(( $(date +%s%3N) - started_ms ))
        CMD_COMPLETE_STEP_MS["$name"]="$elapsed_ms"
        printf '[cmd_complete] FAILED %s wall_ms=%d rc=%d\n' "$name" "$elapsed_ms" "$rc" >&2
        return "$rc"
    fi
}

run_step_with_retry() {
    local name="$1" max_attempts="$2" retry_delay="$3"
    local attempt rc=0 attempt_started_ms attempt_wall_ms total_started_ms
    shift 3
    total_started_ms="$(date +%s%3N)"
    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        attempt_started_ms="$(date +%s%3N)"
        printf '[cmd_complete] START %s attempt=%d/%d\n' "$name" "$attempt" "$max_attempts" >&2
        if "$@"; then
            attempt_wall_ms=$(( $(date +%s%3N) - attempt_started_ms ))
            CMD_COMPLETE_STEP_MS["$name"]=$(( $(date +%s%3N) - total_started_ms ))
            printf '[cmd_complete] PASS %s attempt=%d/%d wall_ms=%d\n' "$name" "$attempt" "$max_attempts" "$attempt_wall_ms" >&2
            return 0
        else
            rc=$?
        fi
        attempt_wall_ms=$(( $(date +%s%3N) - attempt_started_ms ))
        printf '[cmd_complete] ATTEMPT_FAILED %s attempt=%d/%d wall_ms=%d reason=exit_rc_%d\n' \
            "$name" "$attempt" "$max_attempts" "$attempt_wall_ms" "$rc" >&2
        if (( attempt < max_attempts )); then
            printf '[cmd_complete] RETRY %s after transient failure rc=%d\n' "$name" "$rc" >&2
            sleep "$retry_delay"
        fi
    done
    CMD_COMPLETE_STEP_MS["$name"]=$(( $(date +%s%3N) - total_started_ms ))
    printf '[cmd_complete] FAILED %s after %d attempts wall_ms=%d reason=exit_rc_%d\n' \
        "$name" "$max_attempts" "${CMD_COMPLETE_STEP_MS[$name]}" "$rc" >&2
    return "$rc"
}

run_status_step() {
    local output rc=0 archive_hit=""
    printf '[cmd_complete] START status_completed\n' >&2
    output="$(bash "$SCRIPT_DIR/gates/gate_yaml_status.sh" "$CMD_ID" 2>&1)" || rc=$?
    printf '%s\n' "$output"
    if (( rc == 0 )); then
        printf '[cmd_complete] PASS status_completed\n' >&2
        return 0
    fi
    if [[ "$output" != *"not found"* ]]; then
        printf '[cmd_complete] FAILED status_completed\n' >&2
        return "$rc"
    fi
    archive_hit="$(find "$ROOT_DIR/queue/archive/cmds" -maxdepth 1 -type f -name "${CMD_ID}_*.yaml" -print -quit 2>/dev/null || true)"
    if [[ -n "$archive_hit" ]] \
        && awk -v id="$CMD_ID" 'index($0,id) && /CLEAR/ {found=1} END {exit !found}' "$ROOT_DIR/logs/gate_metrics.log"; then
        printf '[cmd_complete] PASS status_completed (archived CLEAR evidence)\n' >&2
        return 0
    fi
    # Direct karo/training commands have no shogun_to_karo archive entry.
    # SG7 was consumed with verdict=APPROVE and cmd_complete_gate returned
    # success earlier in this same wrapper; the correlated CLEAR metric is the
    # terminal evidence. archive.done is deliberately asynchronous and cannot
    # be a prerequisite here without a race.
    if [[ -f "$BUNDLE_PATH" ]] \
        && awk -v id="$CMD_ID" 'index($0,id) && /CLEAR/ {found=1} END {exit !found}' "$ROOT_DIR/logs/gate_metrics.log"; then
        printf '[cmd_complete] PASS status_completed (direct SG7/CLEAR evidence)\n' >&2
        return 0
    fi
    printf '[cmd_complete] FAILED status_completed (archive or direct completion evidence incomplete)\n' >&2
    return "$rc"
}

archive_inbox_after_completion_hint() {
    local inbox_path="$ROOT_DIR/queue/inbox/karo.yaml"
    local hint_id terminal_id
    local -a hint_ids=() terminal_ids=()

    if [[ -f "$inbox_path" ]]; then
        mapfile -t hint_ids < <(python3 - "$inbox_path" "$CMD_ID" <<'PY'
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

path, cmd_id = sys.argv[1:]
with open(path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
messages = data.get("messages", []) if isinstance(data, dict) else []
expected = f"GATE CLEAR — {cmd_id} 完了。/cmd-complete スキルで完了処理を実行せよ。"
for message in messages:
    if not isinstance(message, dict):
        continue
    if message.get("type") != "skill_hint" or message.get("read") is not False:
        continue
    if str(message.get("content") or "") != expected:
        continue
    message_id = str(message.get("id") or "")
    if message_id:
        print(message_id)
PY
        )

        mapfile -t terminal_ids < <(python3 - "$inbox_path" "$CMD_ID" <<'PY'
import sys
import yaml

path, cmd_id = sys.argv[1:]
terminal_types = {
    "report_received",
    "report_review_result",
    "accept_report",
    "run_cmd_complete",
    "gate_clear_required",
}
with open(path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
messages = data.get("messages", []) if isinstance(data, dict) else []
for message in messages:
    if not isinstance(message, dict):
        continue
    if message.get("read") is not False:
        continue
    if str(message.get("parent_cmd") or "") != cmd_id:
        continue
    if message.get("type") not in terminal_types:
        continue
    message_id = str(message.get("id") or "")
    if message_id:
        print(message_id)
PY
        )
    fi

    printf '[cmd_complete] inbox_terminal_drain parent_cmd=%s selected=%d\n' \
        "$CMD_ID" "$(( ${#hint_ids[@]} + ${#terminal_ids[@]} ))" >&2
    for hint_id in "${hint_ids[@]}"; do
        bash "$SCRIPT_DIR/inbox_mark_read.sh" karo "$hint_id"
    done
    for terminal_id in "${terminal_ids[@]}"; do
        bash "$SCRIPT_DIR/inbox_mark_read.sh" karo "$terminal_id"
    done
    bash "$SCRIPT_DIR/inbox_archive.sh" karo
}

# The archive worker is launched asynchronously by cmd_complete_gate.  That is
# useful for the gate caller, but it is not a terminal guarantee for this
# wrapper: dashboard, ntfy, and COMPLETE must not become public before the
# report lifecycle is closed.  Re-run only the real archive worker and accept
# success only after both durable postconditions are visible.
archive_terminal_has_reopened_report() {
    local report status
    while IFS= read -r report; do
        status="$(awk -F: '$1 ~ /^[[:space:]]*status[[:space:]]*$/ { print $2; exit }' "$report" 2>/dev/null \
            | tr -d '[:space:]' | tr -d "\"'")"
        case "$status" in
            pending|revision_requested|assigned|acknowledged|in_progress)
                return 0
                ;;
        esac
    done < <(find "$ROOT_DIR/queue/reports" -maxdepth 1 -type f \
        -name "*_report_${CMD_ID}*.yaml" -print 2>/dev/null)
    return 1
}

archive_terminal() {
    local archive_script="$SCRIPT_DIR/archive_completed.sh"
    local marker="$CHECKPOINT_DIR/archive.done"
    local attempts="${CMD_COMPLETE_ARCHIVE_ATTEMPTS:-3}"
    local delay="${CMD_COMPLETE_ARCHIVE_RETRY_DELAY:-1}"
    local attempt active_count

    # Test fixtures that intentionally model only the wrapper may omit the
    # archive worker.  Production roots always contain this script; absence in
    # a real root is a fail-closed error.
    if [[ ! -f "$archive_script" ]]; then
        if [[ -n "${CMD_COMPLETE_TEST_LOG:-}" ]]; then
            printf '[cmd_complete] SKIP archive_terminal (fixture archive worker absent)\n' >&2
            return 0
        fi
        printf '[cmd_complete] FAILED archive_terminal worker missing: %s\n' "$archive_script" >&2
        return 1
    fi

    for ((attempt = 1; attempt <= attempts; attempt++)); do
        active_count="$(completion_active_report_count)"
        if [[ -f "$marker" && "$active_count" -eq 0 ]]; then
            printf '[cmd_complete] PASS archive_terminal marker=present active_reports=0 attempt=%d\n' "$attempt" >&2
            return 0
        fi
        printf '[cmd_complete] START archive_terminal attempt=%d/%d marker=%s active_reports=%s\n' \
            "$attempt" "$attempts" "$([[ -f "$marker" ]] && echo present || echo missing)" "$active_count" >&2
        env ARCHIVE_COMPLETED_PROJECT_DIR="$ROOT_DIR" \
            ARCHIVE_REQUIRE_CLEAR_RECEIPT=1 \
            SHOGUN_COMPLETION_GENERATION="$BUNDLE_IDENTITY" \
            bash "$archive_script" 3 "$CMD_ID" || true
        active_count="$(completion_active_report_count)"
        if [[ -f "$marker" && "$active_count" -eq 0 ]]; then
            printf '[cmd_complete] PASS archive_terminal marker=present active_reports=0 attempt=%d\n' "$attempt" >&2
            return 0
        fi
        if [[ "$active_count" -gt 0 ]] && archive_terminal_has_reopened_report; then
            printf '[cmd_complete] BLOCK archive_terminal reopened_report_preserved active_reports=%s attempt=%d\n' \
                "$active_count" "$attempt" >&2
            return 1
        fi
        [[ "$attempt" -lt "$attempts" ]] && sleep "$delay"
    done
    printf '[cmd_complete] FAILED archive_terminal marker_or_report_postcondition incomplete after %d attempts\n' "$attempts" >&2
    return 1
}

run_ntfy_once() {
    local receipt="$CHECKPOINT_DIR/ntfy_delivery_receipt.json"
    if python3 - "$receipt" "$CMD_ID" "$BUNDLE_FINGERPRINT" "$BUNDLE_IDENTITY" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError):
    raise SystemExit(1)
expected = {"version": 1, "cmd_id": sys.argv[2], "bundle_fingerprint": sys.argv[3],
            "completion_generation": sys.argv[4], "delivered": True}
raise SystemExit(0 if data == expected else 1)
PY
    then
        printf '[cmd_complete] SKIP ntfy durable_receipt_verified\n' >&2
        return 0
    fi
    timeout "${CMD_COMPLETE_NTFY_TIMEOUT:-25}" bash "$SCRIPT_DIR/ntfy_cmd.sh" "$CMD_ID" "完了" || return $?
    python3 - "$receipt" "$CMD_ID" "$BUNDLE_FINGERPRINT" "$BUNDLE_IDENTITY" <<'PY'
import json, os, sys, tempfile
path, cmd_id, bundle_fp, generation = sys.argv[1:]
data = {"version": 1, "cmd_id": cmd_id, "bundle_fingerprint": bundle_fp,
        "completion_generation": generation, "delivered": True}
fd, tmp = tempfile.mkstemp(prefix=".ntfy_delivery_receipt.", dir=os.path.dirname(path))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(data, fh, sort_keys=True); fh.write("\n"); fh.flush(); os.fsync(fh.fileno())
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
    if [[ "${CMD_COMPLETE_TEST_CRASH_AFTER_NTFY_RECEIPT:-0}" = "1" ]]; then
        printf '[cmd_complete] TEST_CRASH after ntfy receipt\n' >&2
        exit 97
    fi
}

gate_worker_marker_matches() {
    local marker="$1" expected_state="$2"
    python3 - "$marker" "$expected_state" "$CMD_ID" "$BUNDLE_IDENTITY" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError):
    raise SystemExit(1)
expected = {
    "version": 1,
    "state": sys.argv[2],
    "cmd_id": sys.argv[3],
    "completion_generation": sys.argv[4],
}
raise SystemExit(0 if all(data.get(k) == v for k, v in expected.items()) else 1)
PY
}

# Wait for each generation-bound terminal marker in one process.  Spawning a
# fresh python3 (plus date) every 50ms made concurrent public observers contend
# on DrvFS process startup and could push the nominally detached boundary past
# five seconds.  Keep the same CLEAR-before-failure precedence while polling
# inside one interpreter.
wait_for_gate_worker_terminal() {
    local clear_marker="$1" failure_marker="$2" timeout_seconds="$3"
    python3 - "$clear_marker" "$failure_marker" "$CMD_ID" "$BUNDLE_IDENTITY" "$timeout_seconds" <<'PY'
import json
import sys
import time

clear_path, failure_path, cmd_id, generation, timeout_text = sys.argv[1:]
expected = {
    "version": 1,
    "cmd_id": cmd_id,
    "completion_generation": generation,
}

def matches(path, state):
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return False
    return isinstance(data, dict) and data.get("state") == state and all(
        data.get(key) == value for key, value in expected.items()
    )

deadline = time.monotonic() + int(timeout_text)
while True:
    if matches(clear_path, "clear"):
        raise SystemExit(0)
    if matches(failure_path, "failed"):
        raise SystemExit(1)
    if time.monotonic() >= deadline:
        raise SystemExit(2)
    time.sleep(0.05)
PY
}

# A busy single-flight observer can persist a failed marker before the worker
# that owns the same generation publishes its terminal CLEAR.  Marker state is
# generation-bound, so a newer valid CLEAR is the authoritative terminal fact;
# an older/equal CLEAR must never erase a real failure.
gate_worker_recover_newer_clear() {
    local failure_marker="$1" clear_marker="$2" success_marker="$3"
    python3 - "$failure_marker" "$clear_marker" "$success_marker" "$CMD_ID" "$BUNDLE_IDENTITY" <<'PY'
import json, os, sys, tempfile, time

failure_path, clear_path, success_path, cmd_id, generation = sys.argv[1:]
expected = {
    "version": 1,
    "cmd_id": cmd_id,
    "completion_generation": generation,
}

def read(path):
    try:
        with open(path, encoding="utf-8") as fh:
            value = json.load(fh)
    except (OSError, ValueError):
        return None
    return value if isinstance(value, dict) else None

failure = read(failure_path)
clear = read(clear_path)
if not failure or not clear:
    raise SystemExit(1)
if any(failure.get(key) != value for key, value in expected.items()):
    raise SystemExit(1)
if any(clear.get(key) != value for key, value in expected.items()):
    raise SystemExit(1)
if failure.get("state") != "failed" or clear.get("state") != "clear":
    raise SystemExit(1)
try:
    failure_ts = int(failure["persisted_at_ns"])
    clear_ts = int(clear["persisted_at_ns"])
except (KeyError, TypeError, ValueError):
    raise SystemExit(1)
if clear_ts <= failure_ts:
    raise SystemExit(1)

existing = read(success_path)
if existing and all(existing.get(key) == value for key, value in {
    **expected, "state": "success"
}.items()):
    raise SystemExit(0)

data = dict(expected, state="success", rc=0, persisted_at_ns=time.time_ns(),
            recovered_from="clear")
os.makedirs(os.path.dirname(success_path), exist_ok=True)
fd, tmp = tempfile.mkstemp(prefix=".gate_worker_recovered.", dir=os.path.dirname(success_path))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(data, fh, sort_keys=True)
        fh.write("\n")
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, success_path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
PY
}

launch_or_observe_durable_gate_worker() {
    local worker_log="$CHECKPOINT_DIR/completion_tail.log"
    local reservation="$CHECKPOINT_DIR/gate_worker.reserved.json"
    local launch_receipt="$CHECKPOINT_DIR/gate_worker.launch.json"
    local clear_marker="$CHECKPOINT_DIR/gate_worker.clear.json"
    local success_marker="$CHECKPOINT_DIR/gate_worker.success.json"
    local failure_marker="$CHECKPOINT_DIR/gate_worker.failed.json"
    local tmux_bin="${CMD_COMPLETE_TMUX_BIN:-tmux}"
    local launcher="" socket="" worker_cmd="" worker_log_q="" worker_target="" worker_scope=""
    local wait_rc
    CMD_COMPLETE_RECOVERED_CLEAR=0

    if gate_worker_marker_matches "$failure_marker" failed; then
        if gate_worker_recover_newer_clear "$failure_marker" "$clear_marker" "$success_marker"; then
            printf '[cmd_complete] RECOVERED durable gate CLEAR superseded failure marker=%s\n' "$failure_marker" >&2
            CMD_COMPLETE_RECOVERED_CLEAR=1
            return 0
        fi
        printf '[cmd_complete] FAILED durable gate worker marker=%s\n' "$failure_marker" >&2
        return 1
    fi

    if ! gate_worker_marker_matches "$launch_receipt" launched; then
        if ! command -v "$tmux_bin" >/dev/null 2>&1; then
            printf '[cmd_complete] FAILED durable gate worker tmux unavailable\n' >&2
            return 1
        fi
        # Reserve this generation before launch.  O_EXCL closes the
        # launch-before-receipt crash gap; the stable private tmux session name
        # is the recoverable single-flight identity on the next invocation.
        if ! python3 - "$reservation" "$CMD_ID" "$BUNDLE_IDENTITY" <<'PY'
import json, os, sys, time
path, cmd_id, generation = sys.argv[1:]
expected = {"version": 1, "state": "reserved", "cmd_id": cmd_id,
            "completion_generation": generation}
try:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
except FileExistsError:
    try:
        data = json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError):
        raise SystemExit(1)
    raise SystemExit(0 if all(data.get(k) == v for k, v in expected.items()) else 1)
with os.fdopen(fd, "w", encoding="utf-8") as fh:
    data = dict(expected, persisted_at_ns=time.time_ns())
    json.dump(data, fh, sort_keys=True); fh.write("\n"); fh.flush(); os.fsync(fh.fileno())
PY
        then
            printf '[cmd_complete] FAILED durable gate worker reservation invalid\n' >&2
            return 1
        fi
        printf -v worker_cmd '%q ' env CMD_COMPLETE_GATE_WORKER=1 \
            CMD_COMPLETE_ROOT_DIR="$ROOT_DIR" CMD_COMPLETE_SCRIPT_DIR="$SCRIPT_DIR" \
            CMD_COMPLETE_CHECKPOINT_DIR="$CHECKPOINT_DIR" \
            CMD_COMPLETE_SOURCE_SNAPSHOT="$CMD_COMPLETE_SOURCE_SNAPSHOT" \
            SHOGUN_COMPLETION_GENERATION="$BUNDLE_IDENTITY" \
            bash "$CMD_COMPLETE_SOURCE_SNAPSHOT" "$CMD_ID" "$BUNDLE_PATH"
        if [[ -n "${CMD_COMPLETE_TEST_LOG:-}" ]]; then
            printf -v _gate_test_env '%q ' "CMD_COMPLETE_TEST_LOG=$CMD_COMPLETE_TEST_LOG"
            worker_cmd="env $_gate_test_env${worker_cmd#env }"
        fi
        printf -v worker_log_q '%q' "$worker_log"
        # Include the checkpoint path identity as well as cmd/generation.
        # Isolated roots can legitimately exercise the same logical command;
        # sharing a global tmux target would recover the wrong root's worker.
        worker_scope="$(printf '%s' "$CHECKPOINT_DIR" | sha256sum | cut -c1-8)"
        worker_target="cc_${CMD_ID//[^A-Za-z0-9_-]/_}_${BUNDLE_IDENTITY:0:8}_${worker_scope}"
        if "$tmux_bin" display-message -p '#S' >/dev/null 2>&1; then
            if "$tmux_bin" has-session -t "$worker_target" >/dev/null 2>&1; then
                launcher="tmux-session-recovered"
            elif "$tmux_bin" new-session -d -s "$worker_target" \
                "$worker_cmd </dev/null >>$worker_log_q 2>&1"; then
                launcher="tmux-session"
            else
                launcher="failed"
            fi
        else
            socket="cmd-complete-gate-${CMD_ID//[^A-Za-z0-9_-]/_}-${BUNDLE_IDENTITY:0:12}-${worker_scope}"
            if "$tmux_bin" -L "$socket" has-session -t completion >/dev/null 2>&1; then
                launcher="tmux-private-recovered"
            elif "$tmux_bin" -L "$socket" new-session -d -s completion \
                "$worker_cmd </dev/null >>$worker_log_q 2>&1" 9>&-; then
                launcher="tmux-private"
            else
                launcher="failed"
            fi
        fi
        if [[ "$launcher" = "failed" ]]; then
                python3 - "$failure_marker" "$CMD_ID" "$BUNDLE_IDENTITY" <<'PY'
import json, os, sys, tempfile, time
path, cmd_id, generation = sys.argv[1:]
data = {"version": 1, "state": "failed", "cmd_id": cmd_id,
        "completion_generation": generation, "rc": 1,
        "reason": "launch_failed", "persisted_at_ns": time.time_ns()}
fd, tmp = tempfile.mkstemp(prefix=".gate_worker_failed.", dir=os.path.dirname(path))
with os.fdopen(fd, "w", encoding="utf-8") as fh:
    json.dump(data, fh, sort_keys=True); fh.write("\n"); fh.flush(); os.fsync(fh.fileno())
os.replace(tmp, path)
PY
            printf '[cmd_complete] FAILED durable gate worker launch\n' >&2
            return 1
        fi
        if [[ "${CMD_COMPLETE_TEST_CRASH_AFTER_GATE_LAUNCH:-0}" = "1" ]]; then
            printf '[cmd_complete] TEST_CRASH after durable gate launch before receipt\n' >&2
            return 96
        fi
        python3 - "$launch_receipt" "$CMD_ID" "$BUNDLE_IDENTITY" "$launcher" <<'PY'
import json, os, sys, tempfile, time
path, cmd_id, generation, launcher = sys.argv[1:]
data = {"version": 1, "state": "launched", "cmd_id": cmd_id,
        "completion_generation": generation, "launcher": launcher,
        "persisted_at_ns": time.time_ns()}
fd, tmp = tempfile.mkstemp(prefix=".gate_worker_launch.", dir=os.path.dirname(path))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(data, fh, sort_keys=True); fh.write("\n"); fh.flush(); os.fsync(fh.fileno())
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
        gate_worker_marker_matches "$launch_receipt" launched || {
            printf '[cmd_complete] FAILED durable gate worker launch receipt invalid\n' >&2
            return 1
        }
        printf '[cmd_complete] QUEUED completion_tail launcher=%s log=%s\n' "$launcher" "$worker_log"
    fi

    # The public observer has persisted the generation-bound reservation and
    # launch receipt and will not mutate checkpoints again. Release fd9 before
    # waiting for CLEAR so the same durable worker can re-enter this script,
    # acquire the lock, and continue the ordered checkpoint tail. Reservation
    # plus the stable tmux target prevent a concurrent caller from relaunching.
    if ! flock -u 9; then
        printf '[cmd_complete] FAILED durable gate worker checkpoint lock release\n' >&2
        return 1
    fi
    exec 9>&-
    printf '[cmd_complete] RELEASED checkpoint_lock before_clear_wait\n' >&2
    if [[ -n "${CMD_COMPLETE_TEST_HOLD_AFTER_LOCK_RELEASE:-}" ]]; then
        sleep "$CMD_COMPLETE_TEST_HOLD_AFTER_LOCK_RELEASE"
    fi

    if wait_for_gate_worker_terminal "$clear_marker" "$failure_marker" \
        "${CMD_COMPLETE_GATE_CLEAR_TIMEOUT:-3600}"; then
        printf '[cmd_complete] GATE CLEAR durable_worker_receipt_verified\n'
        return 0
    else
        wait_rc=$?
    fi
    if [[ "$wait_rc" -eq 1 ]]; then
        printf '[cmd_complete] FAILED durable gate worker before CLEAR marker=%s\n' "$failure_marker" >&2
    else
        printf '[cmd_complete] FAILED durable gate worker CLEAR marker timeout=%ss\n' \
            "${CMD_COMPLETE_GATE_CLEAR_TIMEOUT:-3600}" >&2
    fi
    return 1
}

if checkpoint_has sg7_consume; then
    printf '[cmd_complete] SKIP sg7_consume checkpoint_verified\n' >&2
    PROJECT_ID="$(checkpoint_project)"
else
    consume_output="$(run_step sg7_consume python3 "$SCRIPT_DIR/review_bundle.py" \
        --root "$ROOT_DIR" consume --cmd "$CMD_ID" --bundle "$BUNDLE_PATH" --expect-verdict APPROVE)" || {
        printf '%s\n' "$consume_output" >&2
        exit 1
    }
    printf '%s\n' "$consume_output"
    PROJECT_ID="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read().splitlines()[-1])["project"])' <<<"$consume_output")"
    checkpoint_mark sg7_consume "$PROJECT_ID"
fi
[[ -n "$PROJECT_ID" ]] || { printf '[cmd_complete] FAILED checkpoint project missing\n' >&2; exit 1; }

run_checkpointed lesson_review bash "$SCRIPT_DIR/lesson_review.sh" "$PROJECT_ID"

if [[ -n "${CMD_COMPLETE_WORKAROUND_NINJA:-}" ]]; then
    run_step workaround_log bash "$SCRIPT_DIR/karo_workaround_log.sh" "$CMD_ID" \
        "$CMD_COMPLETE_WORKAROUND_NINJA" "${CMD_COMPLETE_WORKAROUND_DETAIL:?}" \
        "${CMD_COMPLETE_WORKAROUND_METHOD:?}"
fi

if checkpoint_has cmd_complete_gate; then
    printf '[cmd_complete] SKIP cmd_complete_gate checkpoint_verified\n' >&2
elif [[ "${CMD_COMPLETE_GATE_CONTINUATION:-0}" = "1" ]]; then
    if ! gate_worker_marker_matches "$CHECKPOINT_DIR/gate_worker.success.json" success; then
        printf '[cmd_complete] FAILED cmd_complete_gate durable success marker missing\n' >&2
        exit 1
    fi
    checkpoint_mark cmd_complete_gate
    printf '[cmd_complete] PASS cmd_complete_gate durable_success_marker_verified\n' >&2
elif [[ "${CMD_COMPLETE_SYNC_TAIL:-0}" != "1" ]] \
    && grep -q 'CMD_COMPLETE_GATE_CLEAR_MARKER' "$SCRIPT_DIR/cmd_complete_gate.sh"; then
    if launch_or_observe_durable_gate_worker; then
        if [[ "${CMD_COMPLETE_RECOVERED_CLEAR:-0}" = "1" ]]; then
            if ! gate_worker_marker_matches "$CHECKPOINT_DIR/gate_worker.success.json" success; then
                printf '[cmd_complete] FAILED recovered CLEAR success marker missing\n' >&2
                exit 1
            fi
            checkpoint_mark cmd_complete_gate
            printf '[cmd_complete] PASS cmd_complete_gate recovered_clear_checkpointed\n' >&2
        else
            exit 0
        fi
    else
        exit $?
    fi
else
    run_checkpointed cmd_complete_gate env CMD_COMPLETE_WRAPPER_ACTIVE=1 \
        bash "$SCRIPT_DIR/cmd_complete_gate.sh" "$CMD_ID"
fi
# cmd_complete_gate performs the fail-closed, command-correlated freshness
# check before CLEAR. Do not run the dashboard-wide freshness monitor here:
# an unrelated commit after another context's source_commit would otherwise
# permanently block this already-reviewed command. The global monitor remains
# active in its dashboard/startup callers; completion uses the narrower check.
run_checkpointed quality_log bash "$SCRIPT_DIR/cmd_quality_log.sh" "$CMD_ID" CLEAR \
    "${CMD_COMPLETE_KARO_REWORK:-no}" "${CMD_COMPLETE_SUPPLEMENTARY_CMDS:-0}"
if checkpoint_has status_completed; then
    printf '[cmd_complete] SKIP status_completed checkpoint_verified\n' >&2
else
    run_status_step
    checkpoint_mark status_completed
fi
# Dashboard publication, notification delivery, and inbox archival remain
# strictly checkpoint ordered, but are not part of the interactive caller's
# latency boundary.  The detached worker re-enters this same script, verifies
# the bundle/checkpoint identity under the same lock, and resumes at dashboard.
# A worker crash is therefore safely retryable by the next invocation.
if [[ "${CMD_COMPLETE_SYNC_TAIL:-0}" != "1" ]] \
    && [[ "${CMD_COMPLETE_ASYNC_TAIL_WORKER:-0}" != "1" ]]; then
    _tail_log="$CHECKPOINT_DIR/completion_tail.log"
    _tmux_bin="${CMD_COMPLETE_TMUX_BIN:-tmux}"
    if command -v "$_tmux_bin" >/dev/null 2>&1; then
        printf -v _tail_cmd '%q ' env CMD_COMPLETE_ASYNC_TAIL_WORKER=1 \
            CMD_COMPLETE_ROOT_DIR="$ROOT_DIR" CMD_COMPLETE_SCRIPT_DIR="$SCRIPT_DIR" \
            CMD_COMPLETE_CHECKPOINT_DIR="$CHECKPOINT_DIR" \
            CMD_COMPLETE_SOURCE_SNAPSHOT="$CMD_COMPLETE_SOURCE_SNAPSHOT" \
            bash "$CMD_COMPLETE_SOURCE_SNAPSHOT" "$CMD_ID" "$BUNDLE_PATH"
        if [[ -n "${CMD_COMPLETE_TEST_LOG:-}" ]]; then
            printf -v _tail_test_env '%q ' "CMD_COMPLETE_TEST_LOG=$CMD_COMPLETE_TEST_LOG"
            _tail_cmd="env $_tail_test_env${_tail_cmd#env }"
        fi
        printf -v _tail_log_q '%q' "$_tail_log"
        if "$_tmux_bin" display-message -p '#S' >/dev/null 2>&1; then
            "$_tmux_bin" run-shell -b "$_tail_cmd </dev/null >>$_tail_log_q 2>&1"
            printf '[cmd_complete] QUEUED completion_tail launcher=tmux log=%s\n' "$_tail_log"
        else
            # CI commonly installs tmux without starting a server.  A private
            # one-shot session supplies the same durable server boundary and
            # exits with the worker instead of turning the public call sync.
            _tail_socket="cmd-complete-${CMD_ID//[^A-Za-z0-9_-]/_}-$$"
            # A newly spawned tmux server inherits open descriptors from this
            # process.  Do not let it retain the checkpoint lock while the
            # worker re-enters this script and waits to acquire that lock.
            "$_tmux_bin" -L "$_tail_socket" new-session -d \
                "$_tail_cmd </dev/null >>$_tail_log_q 2>&1" 9>&-
            printf '[cmd_complete] QUEUED completion_tail launcher=tmux-private log=%s\n' "$_tail_log"
        fi
    else
        printf '[cmd_complete] FALLBACK completion_tail mode=sync reason=tmux_unavailable log=%s\n' "$_tail_log" >&2
        flock -u 9
        exec 9>&-
        env CMD_COMPLETE_ASYNC_TAIL_WORKER=1 \
            CMD_COMPLETE_ROOT_DIR="$ROOT_DIR" CMD_COMPLETE_SCRIPT_DIR="$SCRIPT_DIR" \
            CMD_COMPLETE_CHECKPOINT_DIR="$CHECKPOINT_DIR" \
            CMD_COMPLETE_SOURCE_SNAPSHOT="$CMD_COMPLETE_SOURCE_SNAPSHOT" \
            bash "$CMD_COMPLETE_SOURCE_SNAPSHOT" "$CMD_ID" "$BUNDLE_PATH" \
            </dev/null >>"$_tail_log" 2>&1 9>&-
    fi
    exit 0
fi
run_checkpointed archive_terminal archive_terminal
# Distinct commands have distinct checkpoint locks, so their detached tails can
# otherwise enter dashboard_update's 10s flock concurrently and each start an
# independent retry loop.  Queue them once at the wrapper boundary instead.
# The lock is released immediately after dashboard publication; ntfy/archive
# retain per-command ordering without blocking the next dashboard publisher.
if checkpoint_has dashboard; then
    printf '[cmd_complete] SKIP dashboard checkpoint_verified\n' >&2
elif [[ "${CMD_COMPLETE_DASHBOARD_ENABLED:-0}" = "1" ]]; then
    COMPLETION_DASHBOARD_LOCK="${CMD_COMPLETE_DASHBOARD_LOCK:-$ROOT_DIR/queue/gates/completion_dashboard.lock}"
    mkdir -p "$(dirname "$COMPLETION_DASHBOARD_LOCK")"
    exec 8>"$COMPLETION_DASHBOARD_LOCK"
    _dashboard_queue_started_ms="$(date +%s%3N)"
    printf '[cmd_complete] QUEUED dashboard_singleflight\n' >&2
    flock 8
    printf '[cmd_complete] ACQUIRED dashboard_singleflight wait_ms=%d\n' \
        "$(( $(date +%s%3N) - _dashboard_queue_started_ms ))" >&2

    run_step_with_retry dashboard "${CMD_COMPLETE_DASHBOARD_ATTEMPTS:-3}" \
        "${CMD_COMPLETE_DASHBOARD_RETRY_DELAY:-1}" \
        env DASHBOARD_CALLER_SINGLEFLIGHT=1 \
        bash "$SCRIPT_DIR/dashboard_update.sh" "$CMD_ID" --bundle "$BUNDLE_PATH"
    checkpoint_mark dashboard
    flock -u 8
    exec 8>&-
else
    printf '[cmd_complete] SKIP dashboard disabled_by_default(lord ruling 2026-08-17)\n' >&2
    checkpoint_mark dashboard
fi
if checkpoint_has ntfy; then
    printf '[cmd_complete] SKIP ntfy checkpoint_verified\n' >&2
else
    run_step_with_retry ntfy "${CMD_COMPLETE_NTFY_ATTEMPTS:-3}" \
        "${CMD_COMPLETE_NTFY_RETRY_DELAY:-1}" \
        run_ntfy_once
    checkpoint_mark ntfy
fi
run_checkpointed inbox_archive archive_inbox_after_completion_hint

printf '[cmd_complete] COMPLETE %s\n' "$CMD_ID"
CMD_COMPLETE_WALL_MS=$(( $(date +%s%3N) - CMD_COMPLETE_STARTED_MS ))
CMD_COMPLETE_PHASE_JSON="$(python3 - "${CMD_COMPLETE_STEP_MS[sg7_consume]:-0}" \
  "${CMD_COMPLETE_STEP_MS[lesson_review]:-0}" "${CMD_COMPLETE_STEP_MS[cmd_complete_gate]:-0}" \
  "${CMD_COMPLETE_STEP_MS[quality_log]:-0}" "${CMD_COMPLETE_STEP_MS[dashboard]:-0}" \
  "${CMD_COMPLETE_STEP_MS[ntfy]:-0}" "${CMD_COMPLETE_STEP_MS[inbox_archive]:-0}" \
  "$CMD_COMPLETE_WALL_MS" <<'PY'
import json, sys
names = ("sg7_consume", "lesson_review", "cmd_complete_gate", "quality_log",
         "dashboard", "ntfy", "inbox_archive", "completion_total")
print(json.dumps(dict(zip(names, map(int, sys.argv[1:]))), separators=(",", ":")))
PY
)"
self_retro_write_async karo_cmd_complete "$CMD_ID" "$CMD_COMPLETE_WALL_MS" \
  "$CMD_COMPLETE_PHASE_JSON" completion_pipeline \
  "SG7 consume through archive completed" "reduce dominant completion phase without weakening checkpoints" \
  "all ordered checkpoints complete and duplicate event count is 0" \
  "[[cmd_complete]] -> [[completion_pipeline]] -> [[fix_known]]"
source "$SCRIPT_DIR/lib/retro_pane_prompt.sh"
retro_pane_prompt_async "$SCRIPT_DIR/.." karo "cmd_complete:$CMD_ID" cmd_complete
