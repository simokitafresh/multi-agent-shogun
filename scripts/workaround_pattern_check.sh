#!/usr/bin/env bash
# workaround_pattern_check.sh — ワークアラウンド反復パターン検出 (cmd_1153 AC1)
# logs/karo_workarounds.yaml を読み、同一issue/categoryが閾値(3回)以上のパターンを検出。
# 検出時: 家老inboxにworkaround_patternで通知。冪等性: 通知済みフラグで重複通知防止。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$REPO_ROOT/logs/karo_workarounds.yaml"
NOTIFIED_FILE="$REPO_ROOT/logs/workaround_notified.yaml"
LOCK_FILE="/tmp/workaround_pattern_check.lock"
THRESHOLD=3

# --- ログファイルが無ければ何もしない ---
if [[ ! -f "$LOG_FILE" ]]; then
    echo "[workaround_pattern_check] No workaround log found, skip"
    exit 0
fi

# --- 通知済みファイル初期化 ---
if [[ ! -f "$NOTIFIED_FILE" ]]; then
    echo "notified:" > "$NOTIFIED_FILE"
fi

# --- flock排他 ---
(
    flock -w 10 200 || { echo "[workaround_pattern_check] Failed to acquire lock" >&2; exit 1; }

    # issue別の出現回数を集計
    # karo_workarounds.yaml の issue: "..." 行を抽出してカウント
    declare -A issue_counts
    declare -A category_counts

    while IFS= read -r line; do
        # issue行を抽出
        if [[ "$line" =~ issue:\ \"(.+)\" ]]; then
            issue="${BASH_REMATCH[1]}"
            issue_counts["$issue"]=$(( ${issue_counts["$issue"]:-0} + 1 ))
        fi
        # category行を抽出
        if [[ "$line" =~ category:\ \"(.+)\" ]]; then
            cat="${BASH_REMATCH[1]}"
            category_counts["$cat"]=$(( ${category_counts["$cat"]:-0} + 1 ))
        fi
    done < "$LOG_FILE"

    detected=0

    # --- issue別パターン検出 ---
    for issue in "${!issue_counts[@]}"; do
        count=${issue_counts["$issue"]}
        if [[ $count -ge $THRESHOLD ]]; then
            # 通知済みチェック（issue:のキーで管理）
            pattern_key="issue:${issue}"
            if grep -qF "$pattern_key" "$NOTIFIED_FILE" 2>/dev/null; then
                continue
            fi

            echo "[workaround_pattern_check] PATTERN: issue=\"${issue}\" ${count}回"
            bash "$SCRIPT_DIR/inbox_write.sh" karo \
                "パターン検出: issue=\"${issue}\" ${count}回" \
                workaround_pattern workaround_check >> /dev/null 2>&1
            echo "  - \"$pattern_key\"" >> "$NOTIFIED_FILE"
            detected=$((detected + 1))
        fi
    done

    # --- category別パターン検出 ---
    for cat in "${!category_counts[@]}"; do
        count=${category_counts["$cat"]}
        if [[ $count -ge $THRESHOLD ]]; then
            pattern_key="category:${cat}"
            if grep -qF "$pattern_key" "$NOTIFIED_FILE" 2>/dev/null; then
                continue
            fi

            echo "[workaround_pattern_check] PATTERN: category=\"${cat}\" ${count}回"
            bash "$SCRIPT_DIR/inbox_write.sh" karo \
                "パターン検出: category=\"${cat}\" ${count}回" \
                workaround_pattern workaround_check >> /dev/null 2>&1
            echo "  - \"$pattern_key\"" >> "$NOTIFIED_FILE"
            detected=$((detected + 1))
        fi
    done

    if [[ $detected -eq 0 ]]; then
        echo "[workaround_pattern_check] No new patterns detected"
    else
        echo "[workaround_pattern_check] Detected ${detected} new pattern(s)"
    fi

) 200>"$LOCK_FILE"
