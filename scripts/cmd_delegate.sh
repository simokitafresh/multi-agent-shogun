#!/usr/bin/env bash
# cmd_delegate.sh — cmd委任の原子的実行（将軍ワークフロー Step 3）
#
# Usage:
#   bash scripts/cmd_delegate.sh <cmd_id> "<message>"
#
# Example:
#   bash scripts/cmd_delegate.sh cmd_539 "cmd_539を書いた。配備せよ。"
#
# Behavior:
#   1. shogun_to_karo.yaml に cmd_id が存在し status=pending か検証
#   2. delegated_at が既にあれば ALREADY_DELEGATED で終了（冪等性）
#   3. 初回委任時のみ cmd_save.sh を自動実行。PASS(exit 0)時のみ次へ進む
#   4. inbox_write.sh karo "<msg>" cmd_new shogun を実行
#   5. 成功後、delegated_at: <ISO8601> を cmd エントリに追加
#   6. 出力: DELEGATED: cmd_XXX at 2026-03-04T18:17:05
#
# Exit codes:
#   0 — 委任成功 or 既に委任済み
#   1 — エラー（cmd未発見/status不正/inbox_write失敗）

set -euo pipefail

if [ -n "${CMD_DELEGATE_SCRIPT_DIR:-}" ]; then
    SCRIPT_DIR="$CMD_DELEGATE_SCRIPT_DIR"
    PROJECT_DIR="${CMD_DELEGATE_PROJECT_DIR:-${SCRIPT_DIR%/scripts}}"
else
    _cmd_delegate_self="${BASH_SOURCE[0]}"
    [[ "$_cmd_delegate_self" != /* ]] && _cmd_delegate_self="$PWD/$_cmd_delegate_self"
    SCRIPT_DIR="${_cmd_delegate_self%/scripts/cmd_delegate.sh}"
    PROJECT_DIR="${SCRIPT_DIR%/scripts}"
    unset _cmd_delegate_self
fi
SHOGUN_TO_KARO="$PROJECT_DIR/queue/shogun_to_karo.yaml"
KARO_INBOX="$PROJECT_DIR/queue/inbox/karo.yaml"
DASHBOARD="$PROJECT_DIR/dashboard.md"
ARCHIVE_DIR="$PROJECT_DIR/queue/archive/cmds"

CMD_ID="${1:-}"
MESSAGE="${2:-}"

if [ -z "$CMD_ID" ] || [ -z "$MESSAGE" ]; then
    echo "Usage: cmd_delegate.sh <cmd_id> \"<message>\"" >&2
    exit 1
fi

if [ ! -f "$SHOGUN_TO_KARO" ]; then
    echo "ERROR: shogun_to_karo.yaml not found: $SHOGUN_TO_KARO" >&2
    exit 1
fi

# Source yaml_field_set for field get/set
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/yaml_field_set.sh"

find_undeployed_pending_cmds() {
    local yaml_file="$1"
    local current_cmd="$2"

    awk -v current_cmd="$current_cmd" '
function trim(s) {
    sub(/^[[:space:]]+/, "", s)
    sub(/[[:space:]]+$/, "", s)
    return s
}
function unquote(s) {
    s = trim(s)
    if (length(s) >= 2) {
        if (substr(s, 1, 1) == "\"" && substr(s, length(s), 1) == "\"") {
            s = substr(s, 2, length(s) - 2)
        } else if (substr(s, 1, 1) == "'"'"'" && substr(s, length(s), 1) == "'"'"'") {
            s = substr(s, 2, length(s) - 2)
        }
    }
    return trim(s)
}
function flush_block() {
    if (cmd_id != "" && cmd_id != current_cmd && status == "pending" && delegated_at != "") {
        print cmd_id " (delegated_at=" delegated_at ")"
    }
    cmd_id = ""
    status = ""
    delegated_at = ""
}
BEGIN {
    in_commands = 0
    cmd_id = ""
    status = ""
    delegated_at = ""
}
/^commands:[[:space:]]*$/ {
    in_commands = 1
    next
}
in_commands && $0 !~ /^[[:space:]]/ && $0 !~ /^$/ {
    flush_block()
    exit
}
in_commands && /^  - id:[[:space:]]*/ {
    flush_block()
    cmd_id = $0
    sub(/^  - id:[[:space:]]*/, "", cmd_id)
    cmd_id = unquote(cmd_id)
    next
}
in_commands && /^  [^[:space:]-][^:]*:[[:space:]]*$/ {
    flush_block()
    cmd_id = $0
    sub(/^  /, "", cmd_id)
    sub(/:[[:space:]]*$/, "", cmd_id)
    cmd_id = unquote(cmd_id)
    next
}
in_commands && /^    status:[[:space:]]*/ {
    status = $0
    sub(/^    status:[[:space:]]*/, "", status)
    status = unquote(status)
    next
}
in_commands && /^    delegated_at:[[:space:]]*/ {
    delegated_at = $0
    sub(/^    delegated_at:[[:space:]]*/, "", delegated_at)
    delegated_at = unquote(delegated_at)
    next
}
END {
    flush_block()
}
' "$yaml_file" 2>/dev/null || true
}

# Step 1: cmd_id が存在し status=pending か検証
status=$(_yaml_field_get_in_block "$SHOGUN_TO_KARO" "$CMD_ID" "status" 2>/dev/null) || {
    echo "ERROR: cmd_id '$CMD_ID' not found in shogun_to_karo.yaml" >&2
    exit 1
}

if [ "$status" != "pending" ]; then
    echo "ERROR: cmd_id '$CMD_ID' status is '$status', expected 'pending'" >&2
    exit 1
fi

# Step 2: delegated_at が既にあれば冪等に終了
existing_delegated=$(_yaml_field_get_in_block "$SHOGUN_TO_KARO" "$CMD_ID" "delegated_at" 2>/dev/null) || true
if [ -n "$existing_delegated" ]; then
    echo "ALREADY_DELEGATED: $CMD_ID at $existing_delegated"
    exit 0
fi

# Step 3: 初回委任前に cmd_save.sh を強制実行
cmd_save_exit=0
if bash "$SCRIPT_DIR/cmd_save.sh" "$CMD_ID"; then
    cmd_save_exit=0
else
    cmd_save_exit=$?
fi

if [ "$cmd_save_exit" -eq 1 ]; then
    echo "BLOCK: GATE未通過。修正してからcmd_save.sh→inbox_writeを手動実行せよ" >&2
    exit 1
fi

if [ "$cmd_save_exit" -ne 0 ]; then
    echo "ERROR: cmd_save.sh failed for $CMD_ID (exit=$cmd_save_exit)" >&2
    exit "$cmd_save_exit"
fi

# Step 3.4: 他の未配備cmd検出チェック（status=pending + delegated_at存在 → WARNING）
# 事故防止: 家老が委任を受けたが配備を忘れたパターンを次の委任前に警告 (cmd_1686事故)
undeployed_cmds=$(find_undeployed_pending_cmds "$SHOGUN_TO_KARO" "$CMD_ID")

if [ -n "$undeployed_cmds" ]; then
    echo "WARN: 委任済みだが未配備のcmdを検出。家老が処理していない可能性がある:" >&2
    while IFS= read -r line; do
        echo "  - $line" >&2
    done <<< "$undeployed_cmds"
fi

# Step 3.5: 家老inboxに既にcmd_idが存在するかチェック（別経路委任の検出）
if [ -f "$KARO_INBOX" ] && grep -Fqm1 "$CMD_ID" "$KARO_INBOX" 2>/dev/null; then
    echo "WARN: $CMD_ID is already mentioned in karo inbox (previously sent via another path)" >&2
    echo "BLOCK: Refusing to send duplicate. If re-delegation is intended, remove existing inbox entry first." >&2
    exit 1
fi

# Step 3.6: dashboardパイプラインに既にcmd_idが載っているかチェック（WARN only — secondary data）
if [ -f "$DASHBOARD" ] && grep -Fqm1 "$CMD_ID" "$DASHBOARD" 2>/dev/null; then
    echo "WARN: $CMD_ID is already listed in dashboard.md (karo may already be aware). Proceeding — dashboard is secondary data." >&2
fi

# Step 3.7: archiveに完了済みとして存在するかチェック
if [ -d "$ARCHIVE_DIR" ]; then
    shopt -s nullglob
    archived_matches=("$ARCHIVE_DIR/${CMD_ID}_"*)
    shopt -u nullglob
    if [ "${#archived_matches[@]}" -gt 0 ]; then
        echo "BLOCK: $CMD_ID is already archived (completed). Cannot re-delegate." >&2
        exit 1
    fi
fi

# Step 4: status=delegated + delegated_at を先に設定（inbox_writeのcmd_new guardがstatus確認するため）
printf -v TIMESTAMP '%(%Y-%m-%dT%H:%M:%S)T' -1
yaml_field_set "$SHOGUN_TO_KARO" "$CMD_ID" "status" "delegated" || {
    echo "ERROR: Failed to set status=delegated for $CMD_ID" >&2
    exit 1
}
yaml_field_set "$SHOGUN_TO_KARO" "$CMD_ID" "delegated_at" "\"$TIMESTAMP\"" || {
    echo "ERROR: Failed to set delegated_at for $CMD_ID" >&2
    exit 1
}

# Step 5: inbox_write.sh で家老に通知（status=delegated済みなのでguard通過）
bash "$SCRIPT_DIR/inbox_write.sh" karo "$MESSAGE" cmd_new shogun || {
    echo "ERROR: inbox_write.sh failed for $CMD_ID — status=delegatedは維持(手動inbox_writeで再送可)" >&2
    exit 1
}

# Step 6: 成功出力
echo "DELEGATED: $CMD_ID at $TIMESTAMP"
