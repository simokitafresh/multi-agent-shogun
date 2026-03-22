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
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

REPO="simokitafresh/multi-agent-shogun"
WORKFLOW="test.yml"
LAST_ALERT_FILE="/tmp/last_ci_alert_run_id"
LAST_NOTIFY_FILE="/tmp/last_ci_notify_state"
STATUS_MODE=false

[[ "${1:-}" == "--status" ]] && STATUS_MODE=true

# gh CLI check
if ! command -v gh &>/dev/null; then
    $STATUS_MODE && echo "UNKNOWN"
    exit 1
fi

# Get latest run on main branch
run_json=$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --branch main --limit 1 --json status,conclusion,databaseId 2>/dev/null || true)

if [[ -z "$run_json" ]] || [[ "$run_json" == "[]" ]]; then
    $STATUS_MODE && echo "UNKNOWN"
    exit 1
fi

conclusion=$(echo "$run_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0].get('conclusion') or '')" 2>/dev/null || true)
run_id=$(echo "$run_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0].get('databaseId') or '')" 2>/dev/null || true)

if [[ -z "$conclusion" ]] || [[ "$conclusion" == "None" ]]; then
    # Still in progress
    $STATUS_MODE && echo "UNKNOWN"
    exit 0
fi

failed_jobs=""
if [[ "$conclusion" == "failure" && -n "$run_id" ]]; then
    failed_jobs=$(gh run view "$run_id" --repo "$REPO" --json jobs 2>/dev/null \
        | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    failed = [j['name'] for j in data.get('jobs', []) if j.get('conclusion') == 'failure']
    print(', '.join(failed) if failed else 'unknown')
except Exception:
    print('unknown')
" 2>/dev/null || echo "unknown")
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
    echo "$run_id" > "$LAST_ALERT_FILE"
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
