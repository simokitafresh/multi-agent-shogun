#!/usr/bin/env bash
# ============================================================
# ci_status_check.sh
# CI赤検知+ntfy通知スクリプト (cmd_715 AC3)
#
# Usage:
#   bash scripts/ci_status_check.sh           # 赤検知→ntfy通知(ninja_monitor用)
#   bash scripts/ci_status_check.sh --status  # CI状態を標準出力(dashboard用)
#
# Output (--status mode):
#   GREEN                          # CI緑
#   RED:<run_id>:<failed_jobs>     # CI赤
#   UNKNOWN                        # 取得失敗
#
# Exit:
#   0: 成功
#   1: gh CLI不在 or API失敗
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

REPO="simokitafresh/multi-agent-shogun"
WORKFLOW="test.yml"
LAST_NOTIFY_FILE="/tmp/last_ci_notify_state"
STATUS_MODE=false

[[ "${1:-}" == "--status" ]] && STATUS_MODE=true

# gh CLI check
if ! command -v gh &>/dev/null; then
    $STATUS_MODE && echo "UNKNOWN"
    exit 1
fi

# Get latest run on main branch
run_json=$(timeout 15 gh run list --repo "$REPO" --workflow "$WORKFLOW" --branch main --limit 1 --json status,conclusion,databaseId 2>/dev/null || true)

if [[ -z "$run_json" ]] || [[ "$run_json" == "[]" ]]; then
    $STATUS_MODE && echo "UNKNOWN"
    exit 1
fi

read -r conclusion run_id <<< "$(echo "$run_json" | jq -r '.[0] | "\(.conclusion // "") \(.databaseId // "")"' 2>/dev/null || true)"

if [[ -z "$conclusion" ]] || [[ "$conclusion" == "None" ]]; then
    # Still in progress
    $STATUS_MODE && echo "UNKNOWN"
    exit 0
fi

failed_jobs=""
if [[ "$conclusion" == "failure" && -n "$run_id" ]]; then
    failed_jobs=$(timeout 15 gh run view "$run_id" --repo "$REPO" --json jobs 2>/dev/null \
        | jq -r '[.jobs[] | select(.conclusion == "failure") | .name] | if length == 0 then "unknown" else join(", ") end' \
        2>/dev/null || echo "unknown")
fi

if $STATUS_MODE; then
    if [[ "$conclusion" == "failure" ]]; then
        echo "RED:${run_id}:${failed_jobs}"
    elif [[ "$conclusion" == "success" ]]; then
        echo "GREEN"
    else
        echo "UNKNOWN"
    fi
    exit 0
fi

last_notified=""
[[ -f "$LAST_NOTIFY_FILE" ]] && last_notified=$(cat "$LAST_NOTIFY_FILE" 2>/dev/null || true)

if [[ "$conclusion" == "failure" ]]; then
    if [[ "$last_notified" == "failure:${run_id}" ]]; then
        exit 0
    fi
    bash "$SCRIPT_DIR/ntfy.sh" "CI赤: run ${run_id} ${failed_jobs}"
    echo "failure:${run_id}" > "$LAST_NOTIFY_FILE"
    exit 0
fi

if [[ "$conclusion" == "success" ]]; then
    if [[ "$last_notified" == "success:${run_id}" ]]; then
        exit 0
    fi
    bash "$SCRIPT_DIR/ntfy_batch.sh" "CI緑: run ${run_id}"
    echo "success:${run_id}" > "$LAST_NOTIFY_FILE"
    exit 0
fi
