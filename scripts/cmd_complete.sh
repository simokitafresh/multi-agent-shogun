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
STEP_ORDER=(sg7_consume lesson_review cmd_complete_gate quality_log status_completed dashboard ntfy inbox_archive)

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
        && grep -Fq "$CMD_ID" "$ROOT_DIR/dashboard.md" \
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
    local hint_id
    local -a hint_ids=()

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
    fi

    for hint_id in "${hint_ids[@]}"; do
        bash "$SCRIPT_DIR/inbox_mark_read.sh" karo "$hint_id"
    done
    bash "$SCRIPT_DIR/inbox_archive.sh" karo
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

run_checkpointed cmd_complete_gate env CMD_COMPLETE_WRAPPER_ACTIVE=1 \
    bash "$SCRIPT_DIR/cmd_complete_gate.sh" "$CMD_ID"
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
            bash "$SCRIPT_DIR/cmd_complete.sh" "$CMD_ID" "$BUNDLE_PATH"
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
            bash "$SCRIPT_DIR/cmd_complete.sh" "$CMD_ID" "$BUNDLE_PATH" \
            </dev/null >>"$_tail_log" 2>&1 9>&-
    fi
    exit 0
fi
# Distinct commands have distinct checkpoint locks, so their detached tails can
# otherwise enter dashboard_update's 10s flock concurrently and each start an
# independent retry loop.  Queue them once at the wrapper boundary instead.
# The lock is released immediately after dashboard publication; ntfy/archive
# retain per-command ordering without blocking the next dashboard publisher.
COMPLETION_DASHBOARD_LOCK="${CMD_COMPLETE_DASHBOARD_LOCK:-$ROOT_DIR/queue/gates/completion_dashboard.lock}"
mkdir -p "$(dirname "$COMPLETION_DASHBOARD_LOCK")"
exec 8>"$COMPLETION_DASHBOARD_LOCK"
_dashboard_queue_started_ms="$(date +%s%3N)"
printf '[cmd_complete] QUEUED dashboard_singleflight\n' >&2
flock 8
printf '[cmd_complete] ACQUIRED dashboard_singleflight wait_ms=%d\n' \
    "$(( $(date +%s%3N) - _dashboard_queue_started_ms ))" >&2

if checkpoint_has dashboard; then
    printf '[cmd_complete] SKIP dashboard checkpoint_verified\n' >&2
else
    run_step_with_retry dashboard "${CMD_COMPLETE_DASHBOARD_ATTEMPTS:-3}" \
        "${CMD_COMPLETE_DASHBOARD_RETRY_DELAY:-1}" \
        env DASHBOARD_CALLER_SINGLEFLIGHT=1 \
        bash "$SCRIPT_DIR/dashboard_update.sh" "$CMD_ID" --bundle "$BUNDLE_PATH"
    checkpoint_mark dashboard
fi
flock -u 8
exec 8>&-
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
