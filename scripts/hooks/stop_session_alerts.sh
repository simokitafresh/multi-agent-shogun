#!/usr/bin/env bash
# semantic-links: [[Hook自動化フレームワーク]], [[覚醒設計書v3]]
# @source: cmd_3401 (session_alerts.txt stop hookリアルタイム表示)
# 目的: session_alerts.txtの未完了ALERTを毎応答表示し、起動時チェックの忘却を防止する
# 設計: 覚醒設計書v3(掲示板 blt_20260616_000901_115882)
# L4: BLOCK文言で未完了alert+最新BLOCK状態をリアルタイム表示
set -euo pipefail

_sa_self="${BASH_SOURCE[0]}"
case "$_sa_self" in
  */scripts/hooks/*) SHOGUN_ROOT="${_sa_self%/scripts/hooks/stop_session_alerts.sh}" ;;
  scripts/hooks/*) SHOGUN_ROOT="." ;;
  *) SHOGUN_ROOT="$(cd "${_sa_self%/*}/../.." && pwd)" ;;
esac
SHOGUN_ROOT="${STOP_SESSION_ALERTS_ROOT:-$SHOGUN_ROOT}"

# --- agent_idを取得 ---
AGENT_ID=""
if [[ -n "${TMUX_PANE:-}" ]]; then
    AGENT_ID="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
fi
AGENT_ID="${AGENT_ID:-${MOCK_AGENT_ID:-unknown}}"

# --- agent_idからロール判定し、ロール固有のsession_alertsファイルを選択 ---
# 忍者はsession_alertsの対象外（将軍専用ALERTが表示される問題の構造修正 cmd_3487）
AGENT_ROLE=""
case "$AGENT_ID" in
    shogun*) AGENT_ROLE="shogun" ;;
    karo*)   AGENT_ROLE="karo" ;;
    gunshi*) AGENT_ROLE="gunshi" ;;
    *)       AGENT_ROLE="" ;;  # 忍者・不明はスキップ
esac

if [[ -z "$AGENT_ROLE" ]]; then
    exit 0
fi

ALERTS_FILE="$SHOGUN_ROOT/queue/session_alerts_${AGENT_ROLE}.txt"

# --- ファイル不在または空の場合はスキップ（startup gate未完了時の防御: 穴D対策） ---
if [[ ! -f "$ALERTS_FILE" ]] || [[ ! -s "$ALERTS_FILE" ]]; then
    exit 0
fi

# --- 未完了アイテムを確認 ---
TODO_COUNT=0
TODO_COUNT=$(grep -c '^\[TODO\]' "$ALERTS_FILE" 2>/dev/null || true)

if [[ "${TODO_COUNT:-0}" -eq 0 ]]; then
    exit 0
fi

# --- 未完了ALERTを収集 ---
ALERT_CONTENT=""
ALERT_CONTENT=$(grep '^\[TODO\]' "$ALERTS_FILE" | head -20 || true)

# --- ループ防止: 同一ハッシュがBLOCK_BYPASS_THRESHOLD回繰り返されたら通過（修正不能と判断） ---
# Level4強化(blt_20260701_235735+blt_20260702_002604): 旧ロジックは1回で通過(トグル)→3セッション積残の原因
# Tool-less escape(cmd_karo_hotfix_stop_hook_toolless_escape_2026070506):
# ファイル操作不可セッションでは成果物へ依頼文を書かず、事実だけ残して閾値後に自動通過する。
BLOCK_BYPASS_THRESHOLD=5

FAIL_HASH_FILE="${STOP_SESSION_ALERTS_FAIL_HASH_FILE:-/tmp/stop_session_alerts_${AGENT_ID}_fail_hash}"
CURRENT_HASH="$(printf '%s' "$ALERT_CONTENT" | md5sum | cut -d' ' -f1)"
CURRENT_COUNT=1

if [[ -f "$FAIL_HASH_FILE" ]]; then
    PREV_HASH="$(head -1 "$FAIL_HASH_FILE")"
    PREV_COUNT="$(sed -n '2p' "$FAIL_HASH_FILE" 2>/dev/null || echo 0)"
    PREV_COUNT="${PREV_COUNT:-0}"
    if [[ "$CURRENT_HASH" = "$PREV_HASH" ]]; then
        PREV_COUNT=$((PREV_COUNT + 1))
        CURRENT_COUNT="$PREV_COUNT"
        if [[ "$PREV_COUNT" -ge "$BLOCK_BYPASS_THRESHOLD" ]]; then
            rm -f "$FAIL_HASH_FILE" 2>/dev/null || true
            # W3(cmd_3748): 無音通過の禁止。逃げ道を使ったら必ず記録を残す(棚卸しA2)。
            _BYPASS_SCRIPT="${STOP_SESSION_ALERTS_BULLETIN_SCRIPT:-$SHOGUN_ROOT/scripts/bulletin_write.sh}"
            _BYPASS_SAMPLE="$(printf '%s' "$ALERT_CONTENT" | head -3 | tr '\n' ' / ')"
            if [[ -f "$_BYPASS_SCRIPT" ]]; then
                BULLETIN_ROOT_OVERRIDE="$SHOGUN_ROOT" bash "$_BYPASS_SCRIPT" "$AGENT_ID" \
                    "stop hook自動通過: ${AGENT_ROLE}の同一BLOCKが${BLOCK_BYPASS_THRESHOLD}回連続到達し無条件通過。残件${TODO_COUNT}件(先頭3件): ${_BYPASS_SAMPLE}" \
                    "true" "action_required" >/dev/null 2>&1 || true
            fi
            exit 0
        fi
        printf '%s\n%s\n' "$CURRENT_HASH" "$PREV_COUNT" > "$FAIL_HASH_FILE"
    else
        printf '%s\n1\n' "$CURRENT_HASH" > "$FAIL_HASH_FILE"
    fi
else
    printf '%s\n1\n' "$CURRENT_HASH" > "$FAIL_HASH_FILE"
fi

# --- BLOCKとして未完了ALERTを表示 ---
ESCAPED="$(printf '%s' "$ALERT_CONTENT" | head -20 | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' '|' | sed 's/|/\\n/g')"
REMAINING_BLOCKS=$((BLOCK_BYPASS_THRESHOLD - CURRENT_COUNT))
if [[ "$REMAINING_BLOCKS" -lt 1 ]]; then
    REMAINING_BLOCKS=1
fi

cat <<HOOK_JSON
{
  "decision": "block",
  "reason": "⚠ SESSION ALERTS 未完了あり(${TODO_COUNT}件)。対応してから完了せよ。\n通常経路: queue/session_alerts_${AGENT_ROLE}.txt の [TODO] を [DONE] に更新したら通過する。\nファイル操作ツールが無い場合: 成果物本文へ依頼文や /clear 依頼を書かず、最後の応答に「tool unavailable: session_alerts未処理」と事実だけ記録して終了せよ。同一BLOCKは閾値到達後に自動通過する(現在${CURRENT_COUNT}/${BLOCK_BYPASS_THRESHOLD}, 残り${REMAINING_BLOCKS}回)。殿へCLI操作を依頼するな。\n\n${ESCAPED}"
}
HOOK_JSON
exit 0
