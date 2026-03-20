#!/usr/bin/env bash
# karo_workaround_log.sh — 家老ワークアラウンド記録スクリプト
# Usage: bash scripts/karo_workaround_log.sh <cmd_id> <ninja_name> "<issue>" "<fix>"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$REPO_ROOT/logs/karo_workarounds.yaml"
LOCK_FILE="/tmp/karo_workarounds.lock"

# --- Argument validation ---
if [[ $# -ne 4 ]]; then
    echo "[karo_workaround_log] Usage: bash scripts/karo_workaround_log.sh <cmd_id> <ninja_name> \"<issue>\" \"<fix>\"" >&2
    exit 1
fi

CMD_ID="$1"
NINJA_NAME="$2"
ISSUE="$3"
FIX="$4"

if [[ -z "$CMD_ID" || -z "$NINJA_NAME" || -z "$ISSUE" || -z "$FIX" ]]; then
    echo "[karo_workaround_log] Error: All arguments must be non-empty" >&2
    exit 1
fi

# --- Category auto-classification ---
classify_category() {
    local issue="$1"
    if [[ "$issue" == *"null"* || "$issue" == *"空"* ]]; then
        echo "format_error"
    elif [[ "$issue" == *"未記入"* || "$issue" == *"missing"* ]]; then
        echo "missing_field"
    elif [[ "$issue" == *"テンプレート"* || "$issue" == *"template"* ]]; then
        echo "template_gap"
    else
        echo "instruction_gap"
    fi
}

CATEGORY=$(classify_category "$ISSUE")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Count same-issue occurrences ---
count_same_issue() {
    if [[ ! -f "$LOG_FILE" ]]; then
        echo 0
        return
    fi
    local count
    local escaped
    escaped=$(printf '%s' "$ISSUE" | sed "s/[[\\.\\*\\^\\$\\(\\)\\+\\?\\{\\|]/\\\\&/g")
    count=$(grep -c "issue: \"${escaped}\"" "$LOG_FILE" 2>/dev/null || true)
    echo "$count"
}

# --- Append entry with flock ---
(
    flock -w 10 200 || { echo "[karo_workaround_log] Error: Failed to acquire lock" >&2; exit 1; }

    SAME_COUNT=$(count_same_issue)
    OCCURRENCE=$((SAME_COUNT + 1))

    # Initialize file if it doesn't exist
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "entries:" > "$LOG_FILE"
    fi

    # Append entry
    cat >> "$LOG_FILE" <<EOF
  - timestamp: "$TIMESTAMP"
    cmd: "$CMD_ID"
    ninja: "$NINJA_NAME"
    issue: "$ISSUE"
    fix: "$FIX"
    category: "$CATEGORY"
EOF

    if [[ $OCCURRENCE -gt 1 ]]; then
        echo "[karo_workaround_log] Logged: $CMD_ID/$NINJA_NAME [$CATEGORY] (同種${OCCURRENCE}回目)"
    else
        echo "[karo_workaround_log] Logged: $CMD_ID/$NINJA_NAME [$CATEGORY]"
    fi

) 200>"$LOCK_FILE"
