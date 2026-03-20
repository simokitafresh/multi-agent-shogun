#!/usr/bin/env bash
# workaround_pattern_resolve.sh — ワークアラウンドパターンの解決記録 (cmd_1159 AC2)
# 引数: pattern_id fix_cmd_id
# 動作: workaround_patterns.yamlの該当エントリにresolved_at+fix_cmd_idを追記
# 冪等: 既にresolved済みなら何もしない

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
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

    # パターンが存在するか確認
    if ! grep -qF "pattern_id: \"${PATTERN_ID}\"" "$PATTERNS_FILE" 2>/dev/null; then
        echo "[workaround_pattern_resolve] ERROR: pattern_id=\"${PATTERN_ID}\" not found in $PATTERNS_FILE" >&2
        exit 1
    fi

    # 既にresolved済みかチェック（pattern_idブロック内にresolved_atがあるか）
    # pattern_idの行番号を取得
    _pr_pid_line=$(grep -nF "pattern_id: \"${PATTERN_ID}\"" "$PATTERNS_FILE" | head -1 | cut -d: -f1)

    # pattern_idから次のpattern_idまでの範囲でresolved_atを探す
    _pr_next_pid_line=$(awk "NR > ${_pr_pid_line} && /pattern_id:/ { print NR; exit }" "$PATTERNS_FILE")
    if [[ -z "$_pr_next_pid_line" ]]; then
        _pr_next_pid_line=$(wc -l < "$PATTERNS_FILE")
        _pr_next_pid_line=$((_pr_next_pid_line + 1))
    fi

    _pr_resolved_exists=$(awk "NR > ${_pr_pid_line} && NR < ${_pr_next_pid_line} && /resolved_at:/" "$PATTERNS_FILE")
    if [[ -n "$_pr_resolved_exists" ]]; then
        echo "[workaround_pattern_resolve] Already resolved: ${PATTERN_ID} (idempotent, no-op)"
        exit 0
    fi

    # notified_at行の後にresolved_at+fix_cmd_idを挿入
    _pr_notified_line=$(awk "NR > ${_pr_pid_line} && NR < ${_pr_next_pid_line} && /notified_at:/ { print NR; exit }" "$PATTERNS_FILE")
    if [[ -z "$_pr_notified_line" ]]; then
        # notified_atが無い場合はcount行の後に挿入
        _pr_notified_line=$(awk "NR > ${_pr_pid_line} && NR < ${_pr_next_pid_line} && /count:/ { print NR; exit }" "$PATTERNS_FILE")
    fi

    if [[ -z "$_pr_notified_line" ]]; then
        echo "[workaround_pattern_resolve] ERROR: Cannot find insertion point for ${PATTERN_ID}" >&2
        exit 1
    fi

    _pr_now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    sed -i "${_pr_notified_line}a\\    resolved_at: \"${_pr_now}\"\n    fix_cmd_id: \"${FIX_CMD_ID}\"" "$PATTERNS_FILE"

    echo "[workaround_pattern_resolve] Resolved: ${PATTERN_ID} by ${FIX_CMD_ID} at ${_pr_now}"

) 200>"$LOCK_FILE"
