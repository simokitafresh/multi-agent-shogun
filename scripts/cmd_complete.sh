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
BUNDLE_PATH="${2:-queue/gates/${CMD_ID}/sg7_bundle.json}"
[[ "$BUNDLE_PATH" = /* ]] || BUNDLE_PATH="$ROOT_DIR/$BUNDLE_PATH"

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
    if [[ "$CMD_ID" =~ ^cmd_(karo|training)_ ]] \
        && [[ -f "$BUNDLE_PATH" ]] \
        && awk -v id="$CMD_ID" 'index($0,id) && /CLEAR/ {found=1} END {exit !found}' "$ROOT_DIR/logs/gate_metrics.log"; then
        printf '[cmd_complete] PASS status_completed (direct SG7/CLEAR evidence)\n' >&2
        return 0
    fi
    printf '[cmd_complete] FAILED status_completed (archive or direct completion evidence incomplete)\n' >&2
    return "$rc"
}

consume_output="$(run_step sg7_consume python3 "$SCRIPT_DIR/review_bundle.py" \
    --root "$ROOT_DIR" consume --cmd "$CMD_ID" --bundle "$BUNDLE_PATH" --expect-verdict APPROVE)" || {
    printf '%s\n' "$consume_output" >&2
    exit 1
}
printf '%s\n' "$consume_output"
spec_json="$(printf '%s\n' "$consume_output" | tail -n 1)"
PROJECT_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["project"])' <<<"$spec_json")"

run_step lesson_review bash "$SCRIPT_DIR/lesson_review.sh" "$PROJECT_ID"

if [[ -n "${CMD_COMPLETE_WORKAROUND_NINJA:-}" ]]; then
    run_step workaround_log bash "$SCRIPT_DIR/karo_workaround_log.sh" "$CMD_ID" \
        "$CMD_COMPLETE_WORKAROUND_NINJA" "${CMD_COMPLETE_WORKAROUND_DETAIL:?}" \
        "${CMD_COMPLETE_WORKAROUND_METHOD:?}"
fi

run_step cmd_complete_gate bash "$SCRIPT_DIR/cmd_complete_gate.sh" "$CMD_ID"
# cmd_complete_gate performs the fail-closed, command-correlated freshness
# check before CLEAR. Do not run the dashboard-wide freshness monitor here:
# an unrelated commit after another context's source_commit would otherwise
# permanently block this already-reviewed command. The global monitor remains
# active in its dashboard/startup callers; completion uses the narrower check.
run_step quality_log bash "$SCRIPT_DIR/cmd_quality_log.sh" "$CMD_ID" CLEAR \
    "${CMD_COMPLETE_KARO_REWORK:-no}" "${CMD_COMPLETE_SUPPLEMENTARY_CMDS:-0}"
run_status_step
# dashboard_update has its own 10s flock wait, but several independently
# completed commands can legitimately queue behind one writer.  A single lock
# timeout is transient, while publishing later steps without dashboard is not;
# bounded retry keeps the sequence fail-closed without requiring manual reruns.
run_step_with_retry dashboard "${CMD_COMPLETE_DASHBOARD_ATTEMPTS:-3}" \
    "${CMD_COMPLETE_DASHBOARD_RETRY_DELAY:-1}" \
    bash "$SCRIPT_DIR/dashboard_update.sh" "$CMD_ID" --bundle "$BUNDLE_PATH"
run_step ntfy bash "$SCRIPT_DIR/ntfy_cmd.sh" "$CMD_ID" "完了"
run_step inbox_archive bash "$SCRIPT_DIR/inbox_archive.sh" karo

printf '[cmd_complete] COMPLETE %s\n' "$CMD_ID"
