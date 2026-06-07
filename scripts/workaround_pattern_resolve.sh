#!/usr/bin/env bash
# workaround_pattern_resolve.sh — ワークアラウンドパターンの解決記録 (cmd_1159 AC2)
# 引数: pattern_id fix_cmd_id
# 動作: workaround_patterns.yamlの該当エントリにresolved_at+fix_cmd_idを追記
# 冪等: 既にresolved済みなら何もしない

set -euo pipefail

# SCRIPT_DIR/REPO_ROOT: string ops instead of $(cd) subshells (~15ms savings on WSL2)
_wpr_self="${BASH_SOURCE[0]}"
[[ "$_wpr_self" != /* ]] && _wpr_self="$PWD/$_wpr_self"
SCRIPT_DIR="${_wpr_self%/scripts/workaround_pattern_resolve.sh}/scripts"
REPO_ROOT="${_wpr_self%/scripts/workaround_pattern_resolve.sh}"
unset _wpr_self
PATTERNS_FILE="$REPO_ROOT/logs/workaround_patterns.yaml"
LOCK_FILE="/tmp/workaround_pattern_resolve.lock"

usage() {
    echo "Usage: $0 <pattern_id> <fix_cmd_id>"
    echo "  pattern_id: e.g. 'issue:Read_before_Write' or 'category:yaml_parse'"
    echo "  fix_cmd_id: e.g. 'cmd_1160'"
    exit 1
}

if [[ $# -lt 2 ]]; then
    usage
fi

PATTERN_ID="$1"
FIX_CMD_ID="$2"

# --- パターン追跡ファイルが無ければエラー ---
if [[ ! -f "$PATTERNS_FILE" ]]; then
    echo "[workaround_pattern_resolve] ERROR: $PATTERNS_FILE not found" >&2
    exit 1
fi

# --- flock排他 ---
(
    flock -w 10 200 || { echo "[workaround_pattern_resolve] Failed to acquire lock" >&2; exit 1; }

    # 1 awk pass: grep×1+awk×4+wc×1(計5ファイル読)→awk×1(1ファイル読)に統合 (~30ms削減)
    # pid_line/next_pid_line/resolved_exists/insert_lineを一括取得
    _pr_pid_line=0 _pr_next_pid_line=0 _pr_resolved_exists=0 _pr_insert_line=0 _pr_count_line=0
    while IFS=$'\t' read -r _k _v; do
        case "$_k" in
            pid_line)       _pr_pid_line="$_v" ;;
            next_pid_line)  _pr_next_pid_line="$_v" ;;
            resolved)       _pr_resolved_exists=1 ;;
            notified_line)  _pr_insert_line="$_v" ;;
            count_line)     _pr_count_line="$_v" ;;
        esac
    done < <(awk -v pid="$PATTERN_ID" '
        /pattern_id:/ {
            if (_state == 0 && index($0, "\"" pid "\"") > 0) {
                _state = 1; pid_line = NR; printf "pid_line\t%d\n", NR
            } else if (_state >= 1) {
                printf "next_pid_line\t%d\n", NR; exit
            }
        }
        _state == 1 && /resolved_at:/  { print "resolved\t1" }
        _state == 1 && !_notified && /notified_at:/ { _notified=1; printf "notified_line\t%d\n", NR }
        _state == 1 && !_count   && /count:/        { _count=1;    printf "count_line\t%d\n",    NR }
        END { if (_state == 0) printf "not_found\t1\n" }
    ' "$PATTERNS_FILE")

    if [[ "$_pr_pid_line" -eq 0 ]]; then
        echo "[workaround_pattern_resolve] ERROR: pattern_id=\"${PATTERN_ID}\" not found in $PATTERNS_FILE" >&2
        exit 1
    fi

    if [[ "$_pr_resolved_exists" -eq 1 ]]; then
        echo "[workaround_pattern_resolve] Already resolved: ${PATTERN_ID} (idempotent, no-op)"
        exit 0
    fi

    # insert_lineはnotified_at優先、無ければcount行
    if [[ "$_pr_insert_line" -eq 0 ]]; then
        _pr_insert_line="$_pr_count_line"
    fi

    if [[ "$_pr_insert_line" -eq 0 ]]; then
        echo "[workaround_pattern_resolve] ERROR: Cannot find insertion point for ${PATTERN_ID}" >&2
        exit 1
    fi

    # next_pid_line未設定(最後のエントリ)はawkのEOF+1で処理済み
    # TZ=UTC printf組込みで$(date -u)サブプロセス廃止(~10ms削減)
    TZ=UTC printf -v _pr_now '%(%Y-%m-%dT%H:%M:%SZ)T' -1
    # 原子的挿入: awk単一パスでtemp fileに書き、mvで置換（2回sed -iの非原子性+メタ文字注入を解消）
    _pr_tmpfile="${PATTERNS_FILE}.tmp.$$"
    awk -v insert_after="${_pr_insert_line}" \
        -v resolved_val="${_pr_now}" \
        -v fix_val="${FIX_CMD_ID}" \
        '{ print }
         NR == insert_after {
           printf "    resolved_at: \"%s\"\n", resolved_val
           printf "    fix_cmd_id: \"%s\"\n", fix_val
         }' \
        "$PATTERNS_FILE" > "$_pr_tmpfile"
    mv "$_pr_tmpfile" "$PATTERNS_FILE"

    echo "[workaround_pattern_resolve] Resolved: ${PATTERN_ID} by ${FIX_CMD_ID} at ${_pr_now}"

) 200>"$LOCK_FILE"
