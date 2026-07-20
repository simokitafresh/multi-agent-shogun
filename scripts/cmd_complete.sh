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
BUNDLE_PATH="${2:-queue/gates/${CMD_ID}/sg7_bundle.json}"
[[ "$BUNDLE_PATH" = /* ]] || BUNDLE_PATH="$ROOT_DIR/$BUNDLE_PATH"

CHECKPOINT_DIR="${CMD_COMPLETE_CHECKPOINT_DIR:-$ROOT_DIR/queue/gates/$CMD_ID}"
CHECKPOINT_PATH="$CHECKPOINT_DIR/completion_checkpoint.json"
CHECKPOINT_LOCK="$CHECKPOINT_DIR/completion_checkpoint.lock"
mkdir -p "$CHECKPOINT_DIR"
exec 9>"$CHECKPOINT_LOCK"
flock 9

[[ -f "$BUNDLE_PATH" ]] || { printf '[cmd_complete] FAILED bundle missing: %s\n' "$BUNDLE_PATH" >&2; exit 1; }
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

    mapfile -t CHECKPOINT_COMPLETED < <(python3 - "$CHECKPOINT_PATH" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
print(data["project"])
print(*data["completed"], sep="\n")
PY
    )
    CHECKPOINT_PROJECT="${CHECKPOINT_COMPLETED[0]:-}"
    CHECKPOINT_COMPLETED=("${CHECKPOINT_COMPLETED[@]:1}")
}

checkpoint_has() {
    local completed_step
    for completed_step in "${CHECKPOINT_COMPLETED[@]}"; do
        [[ "$completed_step" != "$1" ]] || return 0
    done
    return 1
}

checkpoint_project() {
    printf '%s\n' "$CHECKPOINT_PROJECT"
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
    CHECKPOINT_COMPLETED+=("$step")
    [[ -z "$project" ]] || CHECKPOINT_PROJECT="$project"
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
    shift
    printf '[cmd_complete] START %s\n' "$name" >&2
    if "$@"; then
        printf '[cmd_complete] PASS %s\n' "$name" >&2
    else
        local rc=$?
        printf '[cmd_complete] FAILED %s\n' "$name" >&2
        return "$rc"
    fi
}

run_step_with_retry() {
    local name="$1" max_attempts="$2" retry_delay="$3"
    local attempt rc=0
    shift 3
    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        printf '[cmd_complete] START %s attempt=%d/%d\n' "$name" "$attempt" "$max_attempts" >&2
        if "$@"; then
            printf '[cmd_complete] PASS %s attempt=%d/%d\n' "$name" "$attempt" "$max_attempts" >&2
            return 0
        else
            rc=$?
        fi
        if (( attempt < max_attempts )); then
            printf '[cmd_complete] RETRY %s after transient failure rc=%d\n' "$name" "$rc" >&2
            sleep "$retry_delay"
        fi
    done
    printf '[cmd_complete] FAILED %s after %d attempts\n' "$name" "$max_attempts" >&2
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

run_checkpointed cmd_complete_gate bash "$SCRIPT_DIR/cmd_complete_gate.sh" "$CMD_ID"
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
# dashboard_update has its own 10s flock wait, but several independently
# completed commands can legitimately queue behind one writer.  A single lock
# timeout is transient, while publishing later steps without dashboard is not;
# bounded retry keeps the sequence fail-closed without requiring manual reruns.
if checkpoint_has dashboard; then
    printf '[cmd_complete] SKIP dashboard checkpoint_verified\n' >&2
else
    run_step_with_retry dashboard "${CMD_COMPLETE_DASHBOARD_ATTEMPTS:-3}" \
        "${CMD_COMPLETE_DASHBOARD_RETRY_DELAY:-1}" \
        bash "$SCRIPT_DIR/dashboard_update.sh" "$CMD_ID" --bundle "$BUNDLE_PATH"
    checkpoint_mark dashboard
fi
if checkpoint_has ntfy; then
    printf '[cmd_complete] SKIP ntfy checkpoint_verified\n' >&2
else
    run_step_with_retry ntfy "${CMD_COMPLETE_NTFY_ATTEMPTS:-3}" \
        "${CMD_COMPLETE_NTFY_RETRY_DELAY:-1}" \
        timeout "${CMD_COMPLETE_NTFY_TIMEOUT:-25}" \
        bash "$SCRIPT_DIR/ntfy_cmd.sh" "$CMD_ID" "完了"
    checkpoint_mark ntfy
fi
run_checkpointed inbox_archive archive_inbox_after_completion_hint

printf '[cmd_complete] COMPLETE %s\n' "$CMD_ID"
CMD_COMPLETE_WALL_MS=$(( $(date +%s%3N) - CMD_COMPLETE_STARTED_MS ))
self_retro_write_async karo_cmd_complete "$CMD_ID" "$CMD_COMPLETE_WALL_MS" \
  "{\"completion_total\":${CMD_COMPLETE_WALL_MS}}" completion_pipeline \
  "SG7 consume through archive completed" "reduce dominant completion phase without weakening checkpoints" \
  "all ordered checkpoints complete and duplicate event count is 0" \
  "[[cmd_complete]] -> [[completion_pipeline]] -> [[fix_known]]"
