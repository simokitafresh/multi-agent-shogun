#!/usr/bin/env bash
# workaround_pattern_check.sh — ワークアラウンド反復パターン検出+追跡 (cmd_1153 AC1 + cmd_1159 AC1)
# logs/karo_workarounds.yaml を読み、同一issue/root_signatureが閾値(3回)以上の
# 未解決パターンを検出。category単独集計は異根のworkaroundを混ぜるため禁止。
# 検出時: 家老inboxにworkaround_patternで通知。冪等性: 通知済みフラグで重複通知防止。
# cmd_1159: パターンをworkaround_patterns.yamlに記録し、resolved後のREGRESSION/EFFECTIVE判定。

set -euo pipefail

# SCRIPT_DIR/REPO_ROOT: subprocesses廃止 (dirname/cd/pwd 3fork削減)
if [[ "${BASH_SOURCE[0]}" == */* ]]; then
    SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
else
    SCRIPT_DIR="."
fi
REPO_ROOT="${SCRIPT_DIR}/.."
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
    # awk 1パスで抽出・集計（bash while+regex の代替: 大幅高速化）
    declare -A issue_counts
    declare -A signature_counts

    while IFS=$'\t' read -r _wpc_type _wpc_key _wpc_cnt; do
        case "$_wpc_type" in
            i) issue_counts["$_wpc_key"]=$_wpc_cnt ;;
            s) signature_counts["$_wpc_key"]=$_wpc_cnt ;;
        esac
    done < <(awk '
        function scalar(line,    value) {
            sub(/^[^:]*:[[:space:]]*/, "", line)
            value = line
            sub(/[[:space:]]+$/, "", value)
            if ((value ~ /^'"'"'.*'"'"'$/) || (value ~ /^".*"$/)) {
                value = substr(value, 2, length(value) - 2)
            }
            return value
        }
        function reset_entry() {
            workaround = ""
            issue_name = ""
            category = ""
            root_signature = ""
            resolved_by_cmd = ""
        }
        function flush_entry(    signature) {
            if (workaround != "true" || resolved_by_cmd != "") return
            if (issue_name != "") issue[issue_name]++
            if (category == "") return
            signature = root_signature
            if (signature == "") signature = category "::general"
            sig[signature]++
        }
        BEGIN { reset_entry() }
        /^- cmd_id:[[:space:]]*/ {
            flush_entry()
            reset_entry()
            next
        }
        /^  workaround:[[:space:]]*/ { workaround = scalar($0); next }
        /^  issue:[[:space:]]*/ { issue_name = scalar($0); next }
        /^  category:[[:space:]]*/ { category = scalar($0); next }
        /^  root_signature:[[:space:]]*/ { root_signature = scalar($0); next }
        /^  resolved_by_cmd:[[:space:]]*/ { resolved_by_cmd = scalar($0); next }
        END {
            flush_entry()
            for (k in issue) print "i\t" k "\t" issue[k]
            for (k in sig)   print "s\t" k "\t" sig[k]
        }
    ' "$LOG_FILE")

    detected=0
    # date -u → printf builtin でサブプロセス削減
    TZ=UTC printf -v _wpc_now '%(%Y-%m-%dT%H:%M:%S)TZ' -1
    now="$_wpc_now"
    # cat → $(<file) でサブプロセス削減
    _wpc_notified_cache=$(<"$NOTIFIED_FILE")
    # patterns_fileキャッシュ (grep -qF サブプロセス排除用)
    _wpc_patterns_cache=$(<"$PATTERNS_FILE")

    # --- record_pattern: パターンをworkaround_patterns.yamlに記録 ---
    record_pattern() {
        local _rp_pattern_id="$1"
        local _rp_category="$2"
        local _rp_count="$3"
        # 既に記録済みならcountだけ更新 (grep -qF → bash substring matchでサブプロセス削減)
        if [[ "$_wpc_patterns_cache" == *"pattern_id: \"${_rp_pattern_id}\""* ]]; then
            # count更新: sedで該当エントリのcountを書き換え
            # pattern_idの次の行にcountがある前提
            sed -i "/${_rp_pattern_id}/,/count:/{s/count: .*/count: ${_rp_count}/}" "$PATTERNS_FILE"
            return
        fi
        # 新規記録 (cat >>heredoc → printf builtin でサブプロセス削減)
        printf '  - pattern_id: "%s"\n    category: "%s"\n    count: %s\n    first_seen: "%s"\n    notified_at: "%s"\n' \
            "${_rp_pattern_id}" "${_rp_category}" "${_rp_count}" "${now}" "${now}" >> "$PATTERNS_FILE"
        _wpc_patterns_cache=$(<"$PATTERNS_FILE")
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
                elif [[ "$_crp_pid" == root_signature:* ]]; then
                    local _crp_signature="${_crp_pid#root_signature:}"
                    _crp_current_count="${signature_counts["$_crp_signature"]:-0}"
                elif [[ "$_crp_pid" == category:* ]]; then
                    # category-only patterns predate root_signature. They cannot be
                    # compared safely because heterogeneous causes were aggregated.
                    _crp_current_count=0
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
            if [[ "$_wpc_notified_cache" == *"$pattern_key"* ]]; then
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

    # --- root_signature別パターン検出 ---
    for _wpc_sig in "${!signature_counts[@]}"; do
        count=${signature_counts["$_wpc_sig"]}
        if [[ $count -ge $THRESHOLD ]]; then
            _wpc_cat="${_wpc_sig%%::*}"
            pattern_key="root_signature:${_wpc_sig}"
            if [[ "$_wpc_notified_cache" == *"$pattern_key"* ]]; then
                # 既に通知済み→countだけ更新（追跡用）
                record_pattern "$pattern_key" "$_wpc_cat" "$count"
                continue
            fi

            echo "[workaround_pattern_check] PATTERN: root_signature=\"${_wpc_sig}\" ${count}回 (category=\"${_wpc_cat}\")"
            bash "$SCRIPT_DIR/inbox_write.sh" karo \
                "パターン検出: root_signature=\"${_wpc_sig}\" ${count}回 (category=\"${_wpc_cat}\")" \
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
