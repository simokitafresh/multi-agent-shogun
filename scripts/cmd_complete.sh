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
run_step context_freshness bash "$SCRIPT_DIR/gates/gate_context_freshness.sh"
run_step quality_log bash "$SCRIPT_DIR/cmd_quality_log.sh" "$CMD_ID" CLEAR \
    "${CMD_COMPLETE_KARO_REWORK:-no}" "${CMD_COMPLETE_SUPPLEMENTARY_CMDS:-0}"
run_step status_completed bash "$SCRIPT_DIR/gates/gate_yaml_status.sh" "$CMD_ID"
run_step dashboard bash "$SCRIPT_DIR/dashboard_update.sh" "$CMD_ID" --bundle "$BUNDLE_PATH"
run_step ntfy bash "$SCRIPT_DIR/ntfy_cmd.sh" "$CMD_ID" "完了"
run_step inbox_archive bash "$SCRIPT_DIR/inbox_archive.sh" karo

printf '[cmd_complete] COMPLETE %s\n' "$CMD_ID"
