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

CATEGORY=$(classify_category "$ISSUE")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Count category entries excluding resolved (AC1+AC3: cmd_1211) ---
count_category_entries() {
    local category="$1"
    if [[ ! -f "$LOG_FILE" ]]; then
        echo 0
        return
    fi
    python3 -c "
import yaml, re, sys

with open('${LOG_FILE}', 'r') as f:
    data = yaml.safe_load(f) or {}

# Support both 'entries:' and 'workarounds:' top-level keys
entries = data.get('entries', data.get('workarounds', []))
if not isinstance(entries, list):
    entries = []

target_cat = sys.argv[1]
count = 0
for e in entries:
    if not isinstance(e, dict):
        continue
    # Use stored category or auto-classify from detail/issue text
    cat = e.get('category', '')
    if not cat:
        text = e.get('detail', e.get('issue', ''))
        if re.search(r'lessons_useful|binary_checks|dict|list|string|フォーマット|lesson_candidate', text):
            cat = 'report_yaml_format'
        elif re.search(r'消失|missing|not found', text):
            cat = 'file_disappearance'
        else:
            cat = 'uncategorized'
    # Exclude resolved entries (AC3)
    resolved = e.get('resolved_by_cmd', '')
    if cat == target_cat and not resolved:
        count += 1

print(count)
" "$category" 2>/dev/null || echo 0
}

# --- Append entry with flock ---
(
    flock -w 10 200 || { echo "[karo_workaround_log] Error: Failed to acquire lock" >&2; exit 1; }

    CAT_COUNT=$(count_category_entries "$CATEGORY")
    OCCURRENCE=$((CAT_COUNT + 1))

    # Initialize file if it doesn't exist
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "entries:" > "$LOG_FILE"
    fi

    # Append entry (AC3: resolved_by_cmd field included)
    cat >> "$LOG_FILE" <<EOF
  - timestamp: "$TIMESTAMP"
    cmd: "$CMD_ID"
    ninja: "$NINJA_NAME"
    issue: "$ISSUE"
    fix: "$FIX"
    category: "$CATEGORY"
    resolved_by_cmd: ""
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

) 200>"$LOCK_FILE"
