#!/usr/bin/env bash
# revert_with_receipt.sh — notification-bound, measured git revert wrapper.
# Usage: revert_with_receipt.sh <commit> <reason> [repo]
set -euo pipefail

SELF="${BASH_SOURCE[0]}"
[[ "$SELF" = /* ]] || SELF="$PWD/$SELF"
ROOT="${SELF%/scripts/revert_with_receipt.sh}"
REPO="${3:-$ROOT}"
COMMIT="${1:-}"
REASON="${2:-}"

if [[ ! "$COMMIT" =~ ^[0-9a-fA-F]{7,40}$ || -z "$REASON" ]]; then
    echo "Usage: revert_with_receipt.sh <commit> <reason> [repo]" >&2
    exit 2
fi
REPO="$(realpath "$REPO")"
[[ -d "$REPO/.git" || -f "$REPO/.git" ]] || {
    echo "BLOCK: git repository not found: $REPO" >&2
    exit 1
}

bash "$ROOT/scripts/gates/gate_revert_contract.sh" check \
    "bash scripts/revert_with_receipt.sh $COMMIT <reason>"

git -C "$REPO" cat-file -e "$COMMIT^{commit}"
COMMIT_FULL="$(git -C "$REPO" rev-parse "$COMMIT^{commit}")"

OWNER=""
OWNER_TASK=""
for task_file in "$ROOT"/queue/tasks/*.yaml "$ROOT"/queue/archive/reports/*.yaml "$ROOT"/queue/reports/*.yaml; do
    [[ -f "$task_file" ]] || continue
    if ! grep -qF "$COMMIT_FULL" "$task_file" 2>/dev/null; then
        continue
    fi
    candidate="$(awk '/^worker_id:/{print $2; exit}' "$task_file" 2>/dev/null | tr -d "'\"" || true)"
    if [[ -z "$candidate" ]]; then
        candidate="$(awk '/^  worker_id:/{print $2; exit}' "$task_file" 2>/dev/null | tr -d "'\"" || true)"
    fi
    if [[ -n "$candidate" ]]; then
        OWNER="$candidate"
        OWNER_TASK="$task_file"
        break
    fi
done

[[ -n "$OWNER" ]] || OWNER="unknown"
if [[ "$OWNER" != "unknown" && -x "$ROOT/scripts/inbox_write.sh" ]]; then
    bash "$ROOT/scripts/inbox_write.sh" "$OWNER" \
        "変更元通知: commit ${COMMIT_FULL} の復帰を開始する。復帰後の再計測receiptを確認せよ。" \
        revert_notice "$(tmux display-message -t "${TMUX_PANE:-}" -p '#{@agent_id}' 2>/dev/null || printf 'unknown')" notify_owner
fi

git -C "$REPO" revert --no-edit "$COMMIT_FULL"
AFTER_COMMIT="$(git -C "$REPO" rev-parse HEAD)"

MEASURE_COMMAND="${REVERT_MEASURE_COMMAND:-}"
if [[ -z "$MEASURE_COMMAND" && -n "$OWNER_TASK" ]]; then
    MEASURE_COMMAND="bash scripts/run_tests.sh task $OWNER_TASK"
fi
if [[ -z "$MEASURE_COMMAND" ]]; then
    MEASURE_COMMAND="bash scripts/detector_fp_rate.sh --out $ROOT/logs/detector_fp_rate.yaml"
fi

set +e
(cd "$REPO" && bash -c "$MEASURE_COMMAND")
MEASURE_RC=$?
set -e

RECEIPT="$ROOT/logs/revert_receipts.jsonl"
mkdir -p "${RECEIPT%/*}"
REVERT_RECEIPT_COMMIT="$COMMIT_FULL" \
REVERT_RECEIPT_AFTER="$AFTER_COMMIT" \
REVERT_RECEIPT_OWNER="$OWNER" \
REVERT_RECEIPT_MEASURE="$MEASURE_COMMAND" \
REVERT_RECEIPT_RC="$MEASURE_RC" \
REVERT_RECEIPT_REASON="$REASON" \
REVERT_RECEIPT_TS="$(date -Iseconds)" \
REVERT_RECEIPT_PATH="$RECEIPT" python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ["REVERT_RECEIPT_PATH"])
record = {
    "ts": os.environ["REVERT_RECEIPT_TS"],
    "reverted_commit": os.environ["REVERT_RECEIPT_COMMIT"],
    "after_commit": os.environ["REVERT_RECEIPT_AFTER"],
    "owner": os.environ["REVERT_RECEIPT_OWNER"],
    "reason": os.environ["REVERT_RECEIPT_REASON"],
    "measurement_command": os.environ["REVERT_RECEIPT_MEASURE"],
    "measurement_rc": int(os.environ["REVERT_RECEIPT_RC"]),
}
with path.open("a", encoding="utf-8") as handle:
    handle.write(json.dumps(record, ensure_ascii=False) + "\n")
PY

if [[ "$MEASURE_RC" -ne 0 ]]; then
    echo "BLOCK: revert completed but post-revert measurement failed rc=$MEASURE_RC" >&2
    exit 1
fi
echo "REVERT_RECEIPT commit=$COMMIT_FULL after=$AFTER_COMMIT owner=$OWNER measurement_rc=0"
