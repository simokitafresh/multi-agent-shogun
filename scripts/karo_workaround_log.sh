#!/usr/bin/env bash
# karo_workaround_log.sh — 家老ワークアラウンド記録スクリプト
# Usage: bash scripts/karo_workaround_log.sh <cmd_id> <ninja_name> "<issue>" "<fix>"
#
# AC1(cmd_1211): カテゴリ別件数カウント。2件目WARN、3件目以上ALERT(ntfy+insight_write)
# AC2(cmd_1211): classify_category改善(report_yaml_format/file_disappearance/uncategorized)
# AC3(cmd_1211): resolved_by_cmdフィールド追加。resolved済みはALERTカウント除外

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$REPO_ROOT/logs/karo_workarounds.yaml"
LOCK_FILE="/tmp/karo_workarounds.lock"

# --- Argument validation ---
CLEAN_MODE=false
if [[ "${1:-}" = "--clean" ]]; then
    CLEAN_MODE=true
    shift
    if [[ $# -lt 2 ]]; then
        echo "[karo_workaround_log] Usage: bash scripts/karo_workaround_log.sh --clean <cmd_id> <ninja_name>" >&2
        exit 1
    fi
    CMD_ID="$1"
    NINJA_NAME="$2"
    ISSUE=""
    FIX=""
    if [[ -z "$CMD_ID" || -z "$NINJA_NAME" ]]; then
        echo "[karo_workaround_log] Error: cmd_id and ninja_name must be non-empty" >&2
        exit 1
    fi
else
    if [[ $# -ne 4 ]]; then
        echo "[karo_workaround_log] Usage: bash scripts/karo_workaround_log.sh <cmd_id> <ninja_name> \"<issue>\" \"<fix>\"" >&2
        echo "  --clean mode: bash scripts/karo_workaround_log.sh --clean <cmd_id> <ninja_name>" >&2
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
fi

# --- Category auto-classification (AC2: cmd_1211) ---
classify_category() {
    local issue="$1"
    local pattern_report="lessons_useful|binary_checks|dict|list|string|フォーマット|lesson_candidate"
    local pattern_disappear="消失|missing|not found"
    if [[ "$issue" =~ $pattern_report ]]; then
        echo "report_yaml_format"
    elif [[ "$issue" =~ $pattern_disappear ]]; then
        echo "file_disappearance"
    else
        echo "uncategorized"
    fi
}

if [[ "$CLEAN_MODE" = true ]]; then
    CATEGORY="clean"
else
    CATEGORY=$(classify_category "$ISSUE")
fi
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Count category entries excluding resolved (AC1+AC3: cmd_1211, GP-084: Python→awk) ---
count_category_entries() {
    local category="$1"
    if [[ ! -f "$LOG_FILE" ]]; then
        echo 0
        return
    fi
    awk -v target="$category" '
    /^- (cmd_id|timestamp):/ {
        if (n > 0 && cat == target && !resolved) count++
        n++; cat=""; resolved=0; detail=""
    }
    /^  category:/ { sub(/^  category: */, ""); gsub(/[" ]/, ""); cat=$0 }
    /^  resolved_by_cmd:/ {
        v=$0; sub(/^  resolved_by_cmd: */, "", v); gsub(/[" ]/, "", v)
        if (v != "") resolved=1
    }
    # Auto-classify entries without category from detail/issue
    /^  (detail|issue):/ && cat == "" {
        if ($0 ~ /lessons_useful|binary_checks|dict|list|string|lesson_candidate/) cat="report_yaml_format"
        else if ($0 ~ /missing|not found/) cat="file_disappearance"
        else cat="uncategorized"
    }
    END {
        if (n > 0 && cat == target && !resolved) count++
        print count+0
    }
    ' "$LOG_FILE"
}

# --- Append entry with flock ---
(
    flock -w 10 200 || { echo "[karo_workaround_log] Error: Failed to acquire lock" >&2; exit 1; }

    # Initialize file if it doesn't exist
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
    fi

    if [[ "$CLEAN_MODE" = true ]]; then
        # --clean mode: workaround: false, category: clean を記録
        cat >> "$LOG_FILE" <<EOF
- cmd_id: $CMD_ID
  timestamp: '$TIMESTAMP'
  ninja: $NINJA_NAME
  workaround: false
  category: clean
  detail: ''
  root_cause: ''
  resolved_by_cmd: ''
EOF
        echo "[karo_workaround_log] Clean: $CMD_ID/$NINJA_NAME [clean]"
    else
        CAT_COUNT=$(count_category_entries "$CATEGORY")
        OCCURRENCE=$((CAT_COUNT + 1))

        # GP-086: Append entry in standard flat-list format (matches manual karo entries)
        # Old format used nested "entries:" + 2-space indent → YAML structure conflict with manual entries
        cat >> "$LOG_FILE" <<EOF
- cmd_id: $CMD_ID
  timestamp: '$TIMESTAMP'
  ninja: $NINJA_NAME
  workaround: true
  category: $CATEGORY
  detail: '$ISSUE'
  root_cause: '$FIX'
  resolved_by_cmd: ''
EOF

        # --- Alert mechanism (AC1: cmd_1211) ---
        if [[ $OCCURRENCE -ge 3 ]]; then
            echo "[karo_workaround_log] ALERT: カテゴリ「${CATEGORY}」が${OCCURRENCE}件。構造対策cmdを起票せよ"
            bash "$SCRIPT_DIR/ntfy.sh" "【家老ALERT】workaround同一カテゴリ「${CATEGORY}」が${OCCURRENCE}件。構造対策cmd起票を強制" 2>/dev/null || true
            bash "$SCRIPT_DIR/insight_write.sh" "workaround同一カテゴリ「${CATEGORY}」が${OCCURRENCE}件蓄積。構造対策cmdの起票が必要" "high" "karo_workaround_log" 2>/dev/null || true
        elif [[ $OCCURRENCE -eq 2 ]]; then
            echo "[karo_workaround_log] WARN: 同一カテゴリ「${CATEGORY}」が2件。構造対策cmdの起票を検討せよ"
        else
            echo "[karo_workaround_log] Logged: $CMD_ID/$NINJA_NAME [$CATEGORY]"
        fi
    fi

) 200>"$LOCK_FILE"
