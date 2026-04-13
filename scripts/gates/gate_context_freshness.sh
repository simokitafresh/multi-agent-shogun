#!/usr/bin/env bash
# ============================================================
# gate_context_freshness.sh
# dashboardと同じ監視対象に対してlast_updated鮮度を自動チェックする
#
# Usage:
#   bash scripts/gates/gate_context_freshness.sh
#
# チェック内容:
#   scripts/context_freshness_check.sh --dashboard-warnings と同じ対象
#   （直近completed cmdがあるactive projectのcontext）のみを監視する
#   各context/*.mdの先頭コメントから last_updated を解析
#   フォーマット: <!-- last_updated: YYYY-MM-DD --> または
#                <!-- last_updated: YYYY-MM-DD cmd_XXX ... -->
#   基準日からの経過日数:
#     7日超 → WARN
#     14日超 → ALERT
#     last_updated未記載 → WARN（「未記載」と明示）
#
# Exit code: 0=全OK, 1=1つ以上ALERT, 2=WARNのみ(ALERTなし)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CONTEXT_DIR="$SCRIPT_DIR/context"
CHECK_SCRIPT="$SCRIPT_DIR/scripts/context_freshness_check.sh"

HAS_ALERT=0
HAS_WARN=0
ALERT_LIST=()

emit_actionable() {
    local message="$1"
    local action="$2"
    echo "$message"
    echo "  action: $action"
}

TODAY_EPOCH=$(date +%s)

if [ ! -f "$CHECK_SCRIPT" ]; then
    echo "WARN: context_freshness_check.sh not found"
    echo "  action: scripts/context_freshness_check.sh を復旧せよ。"
    exit 2
fi

mapfile -t target_rel_paths < <(
    bash "$CHECK_SCRIPT" --dashboard-warnings 2>/dev/null \
        | sed -nE 's/^WARN: ([^ ]+) last_updated .*$/\1/p' \
        | sort -u
)

if [ "${#target_rel_paths[@]}" -eq 0 ]; then
    echo "--- 総合判定: OK ---"
    exit 0
fi

for rel_path in "${target_rel_paths[@]}"; do
    file="$SCRIPT_DIR/$rel_path"
    [ -f "$file" ] || continue

    basename_file=$(basename "$file")

    # Extract last_updated date from <!-- last_updated: YYYY-MM-DD ... -->
    # head -10 to limit search to file header
    last_updated=$(head -10 "$file" \
        | grep -oE 'last_updated:[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}' \
        | head -1 \
        | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}') || true

    if [ -z "$last_updated" ]; then
        emit_actionable \
            "WARN: ${basename_file} (last_updated 未記載)" \
            "${basename_file} に <!-- last_updated: YYYY-MM-DD --> を追記せよ。"
        HAS_WARN=1
        continue
    fi

    # Calculate days since last_updated
    file_epoch=$(date -d "$last_updated" +%s 2>/dev/null) || {
        emit_actionable \
            "WARN: ${basename_file} (last_updated日付パース失敗: ${last_updated})" \
            "${basename_file} の last_updated 日付形式を YYYY-MM-DD に修正せよ。"
        HAS_WARN=1
        continue
    }

    days_ago=$(( (TODAY_EPOCH - file_epoch) / 86400 ))

    if [ "$days_ago" -gt 14 ]; then
        emit_actionable \
            "ALERT: ${basename_file} (${days_ago}日前更新)" \
            "${basename_file} の内容を確認し、最新情報へ更新せよ。"
        HAS_ALERT=1
        ALERT_LIST+=("${basename_file}(${days_ago}日)")
    elif [ "$days_ago" -gt 7 ]; then
        emit_actionable \
            "WARN: ${basename_file} (${days_ago}日前更新)" \
            "${basename_file} の鮮度を確認し、必要なら更新せよ。"
        HAS_WARN=1
    else
        echo "OK: ${basename_file} (${days_ago}日前更新)"
    fi
done

# ALERT時のntfy送信（WARNのみの場合は送信しない）
if [ "$HAS_ALERT" -gt 0 ] && [ ${#ALERT_LIST[@]} -gt 0 ]; then
    alert_summary=$(IFS=', '; echo "${ALERT_LIST[*]}")
    bash "$SCRIPT_DIR/scripts/ntfy.sh" "【将軍】context鮮度ALERT: ${alert_summary}" || true
fi

# 総合判定
if [ "$HAS_ALERT" -gt 0 ]; then
    echo "--- 総合判定: ALERT ---"
    exit 1
elif [ "$HAS_WARN" -gt 0 ]; then
    echo "--- 総合判定: WARN ---"
    exit 2
else
    echo "--- 総合判定: OK ---"
    exit 0
fi
