#!/usr/bin/env bash
# cmd_friction_log.sh — cmd分解フリクション記録スクリプト
# Usage: bash scripts/cmd_friction_log.sh <cmd_id> <friction_type> "<detail>"
# friction_type: ambiguous_scope | missing_context | too_many_acs | unclear_dependency | other

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$REPO_ROOT/logs/cmd_friction.yaml"
LOCK_FILE="/tmp/cmd_friction.lock"

# --- Argument validation ---
if [[ $# -ne 3 ]]; then
    echo "[cmd_friction_log] Usage: bash scripts/cmd_friction_log.sh <cmd_id> <friction_type> \"<detail>\"" >&2
    exit 1
fi

CMD_ID="$1"
FRICTION_TYPE="$2"
DETAIL="$3"

if [[ -z "$CMD_ID" || -z "$FRICTION_TYPE" || -z "$DETAIL" ]]; then
    echo "[cmd_friction_log] Error: All arguments must be non-empty" >&2
    exit 1
fi

# --- Validate friction_type ---
VALID_TYPES="ambiguous_scope missing_context too_many_acs unclear_dependency other"
if ! echo "$VALID_TYPES" | grep -qw "$FRICTION_TYPE"; then
    echo "[cmd_friction_log] Error: Invalid friction_type '$FRICTION_TYPE'. Valid: $VALID_TYPES" >&2
    exit 1
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Append entry with flock ---
(
    flock -w 10 200 || { echo "[cmd_friction_log] Error: Failed to acquire lock" >&2; exit 1; }

    # Initialize file if it doesn't exist
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "entries:" > "$LOG_FILE"
    fi

    # Append entry
    cat >> "$LOG_FILE" <<EOF
  - cmd_id: "$CMD_ID"
    friction_type: "$FRICTION_TYPE"
    detail: "$DETAIL"
    timestamp: "$TIMESTAMP"
EOF

    echo "[cmd_friction_log] Logged: $CMD_ID [$FRICTION_TYPE]"

) 200>"$LOCK_FILE"
