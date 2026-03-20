#!/usr/bin/env bash
# workaround_pattern_check.sh — ワークアラウンド反復パターン検出+追跡 (cmd_1153 AC1 + cmd_1159 AC1)
# logs/karo_workarounds.yaml を読み、同一issue/categoryが閾値(3回)以上のパターンを検出。
# 検出時: 家老inboxにworkaround_patternで通知。冪等性: 通知済みフラグで重複通知防止。
# cmd_1159: パターンをworkaround_patterns.yamlに記録し、resolved後のREGRESSION/EFFECTIVE判定。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$REPO_ROOT/logs/karo_workarounds.yaml"
NOTIFIED_FILE="$REPO_ROOT/logs/workaround_notified.yaml"
PATTERNS_FILE="$REPO_ROOT/logs/workaround_patterns.yaml"
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

# --- パターン追跡ファイル初期化 ---
if [[ ! -f "$PATTERNS_FILE" ]]; then
    echo "patterns:" > "$PATTERNS_FILE"
fi

# --- flock排他 ---
(
    flock -w 10 200 || { echo "[workaround_pattern_check] Failed to acquire lock" >&2; exit 1; }

    # issue別の出現回数を集計
    # karo_workarounds.yaml の issue: "..." 行を抽出してカウント
    declare -A issue_counts
    declare -A category_counts

    while IFS= read -r _wpc_line; do
        # issue行を抽出
        if [[ "$_wpc_line" =~ issue:\ \"(.+)\" ]]; then
            _wpc_issue="${BASH_REMATCH[1]}"
            issue_counts["$_wpc_issue"]=$(( ${issue_counts["$_wpc_issue"]:-0} + 1 ))
        fi
        # category行を抽出
        if [[ "$_wpc_line" =~ category:\ \"(.+)\" ]]; then
            _wpc_cat="${BASH_REMATCH[1]}"
            category_counts["$_wpc_cat"]=$(( ${category_counts["$_wpc_cat"]:-0} + 1 ))
        fi
    done < "$LOG_FILE"

    detected=0
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # --- record_pattern: パターンをworkaround_patterns.yamlに記録 ---
    record_pattern() {
        local _rp_pattern_id="$1"
        local _rp_category="$2"
        local _rp_count="$3"
        # 既に記録済みならcountだけ更新
        if grep -qF "pattern_id: \"${_rp_pattern_id}\"" "$PATTERNS_FILE" 2>/dev/null; then
            # count更新: sedで該当エントリのcountを書き換え
            # pattern_idの次の行にcountがある前提
            sed -i "/${_rp_pattern_id}/,/count:/{s/count: .*/count: ${_rp_count}/}" "$PATTERNS_FILE"
            return
        fi
        # 新規記録
        cat >> "$PATTERNS_FILE" <<YAML_EOF
  - pattern_id: "${_rp_pattern_id}"
    category: "${_rp_category}"
    count: ${_rp_count}
    first_seen: "${now}"
    notified_at: "${now}"
YAML_EOF
    }

    # --- check_regression: resolved済みパターンの再発/有効性チェック ---
    check_resolved_patterns() {
        # patterns.yamlからresolved済みエントリを抽出
        # resolved_at が存在する行の直前にpattern_idがあるはず
        local _crp_in_entry=false
        local _crp_pid=""
        local _crp_cat=""
        local _crp_resolved=""

        while IFS= read -r _crp_line; do
            if [[ "$_crp_line" =~ pattern_id:\ \"(.+)\" ]]; then
                _crp_pid="${BASH_REMATCH[1]}"
                _crp_cat=""
                _crp_resolved=""
                _crp_in_entry=true
            fi
            if $_crp_in_entry && [[ "$_crp_line" =~ category:\ \"(.+)\" ]]; then
                _crp_cat="${BASH_REMATCH[1]}"
            fi
            if $_crp_in_entry && [[ "$_crp_line" =~ resolved_at:\ \"(.+)\" ]]; then
                _crp_resolved="${BASH_REMATCH[1]}"
            fi
            # エントリの終わり(次のエントリか末尾)でチェック
            if $_crp_in_entry && [[ -n "$_crp_pid" ]] && [[ -n "$_crp_resolved" ]]; then
                # resolved済みパターンの再発チェック
                local _crp_current_count=0
                if [[ "$_crp_pid" == issue:* ]]; then
                    local _crp_issue_name="${_crp_pid#issue:}"
                    _crp_current_count="${issue_counts["$_crp_issue_name"]:-0}"
                elif [[ "$_crp_pid" == category:* ]]; then
                    local _crp_cat_name="${_crp_pid#category:}"
                    _crp_current_count="${category_counts["$_crp_cat_name"]:-0}"
                fi

                if [[ $_crp_current_count -ge $THRESHOLD ]]; then
                    echo "[workaround_pattern_check] REGRESSION: ${_crp_pid} 再発(${_crp_current_count}件)"
                    bash "$SCRIPT_DIR/inbox_write.sh" karo \
                        "REGRESSION: ${_crp_pid} 再発(${_crp_current_count}件)" \
                        workaround_pattern workaround_check >> /dev/null 2>&1
                else
                    echo "[workaround_pattern_check] EFFECTIVE: ${_crp_pid} 修正有効"
                fi
                _crp_in_entry=false
                _crp_pid=""
                _crp_resolved=""
            fi
        done < "$PATTERNS_FILE"
    }

    # --- resolved済みパターンのチェック（新規検出前に実施） ---
    check_resolved_patterns

    # --- issue別パターン検出 ---
    for _wpc_issue in "${!issue_counts[@]}"; do
        count=${issue_counts["$_wpc_issue"]}
        if [[ $count -ge $THRESHOLD ]]; then
            # 通知済みチェック（issue:のキーで管理）
            pattern_key="issue:${_wpc_issue}"
            if grep -qF "$pattern_key" "$NOTIFIED_FILE" 2>/dev/null; then
                # 既に通知済み→countだけ更新（追跡用）
                record_pattern "$pattern_key" "$_wpc_issue" "$count"
                continue
            fi

            echo "[workaround_pattern_check] PATTERN: issue=\"${_wpc_issue}\" ${count}回"
            bash "$SCRIPT_DIR/inbox_write.sh" karo \
                "パターン検出: issue=\"${_wpc_issue}\" ${count}回" \
                workaround_pattern workaround_check >> /dev/null 2>&1
            echo "  - \"$pattern_key\"" >> "$NOTIFIED_FILE"
            record_pattern "$pattern_key" "$_wpc_issue" "$count"
            detected=$((detected + 1))
        fi
    done

    # --- category別パターン検出 ---
    for _wpc_cat in "${!category_counts[@]}"; do
        count=${category_counts["$_wpc_cat"]}
        if [[ $count -ge $THRESHOLD ]]; then
            pattern_key="category:${_wpc_cat}"
            if grep -qF "$pattern_key" "$NOTIFIED_FILE" 2>/dev/null; then
                # 既に通知済み→countだけ更新（追跡用）
                record_pattern "$pattern_key" "$_wpc_cat" "$count"
                continue
            fi

            echo "[workaround_pattern_check] PATTERN: category=\"${_wpc_cat}\" ${count}回"
            bash "$SCRIPT_DIR/inbox_write.sh" karo \
                "パターン検出: category=\"${_wpc_cat}\" ${count}回" \
                workaround_pattern workaround_check >> /dev/null 2>&1
            echo "  - \"$pattern_key\"" >> "$NOTIFIED_FILE"
            record_pattern "$pattern_key" "$_wpc_cat" "$count"
            detected=$((detected + 1))
        fi
    done

    if [[ $detected -eq 0 ]]; then
        echo "[workaround_pattern_check] No new patterns detected"
    else
        echo "[workaround_pattern_check] Detected ${detected} new pattern(s)"
    fi

) 200>"$LOCK_FILE"
