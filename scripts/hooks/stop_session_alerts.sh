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

# --- ループ防止: 同一ハッシュが繰り返される場合は通過（修正不能と判断） ---

FAIL_HASH_FILE="/tmp/stop_session_alerts_${AGENT_ID}_fail_hash"
CURRENT_HASH="$(printf '%s' "$ALERT_CONTENT" | md5sum | cut -d' ' -f1)"

if [[ -f "$FAIL_HASH_FILE" ]]; then
    PREV_HASH="$(< "$FAIL_HASH_FILE")"
    if [[ "$CURRENT_HASH" = "$PREV_HASH" ]]; then
        # 同一ALERTが繰り返し発生 → 通過（エージェントが解消不能なALERTに無限ループしないよう）
        rm -f "$FAIL_HASH_FILE" 2>/dev/null || true
        exit 0
    fi
fi

printf '%s' "$CURRENT_HASH" > "$FAIL_HASH_FILE"

# --- BLOCKとして未完了ALERTを表示 ---
ESCAPED="$(printf '%s' "$ALERT_CONTENT" | head -20 | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' '|' | sed 's/|/\\n/g')"

cat <<HOOK_JSON
{
  "decision": "block",
  "reason": "⚠ SESSION ALERTS 未完了あり(${TODO_COUNT}件)。対応してから完了せよ。\nqueue/session_alerts_${AGENT_ROLE}.txt の [TODO] を [DONE] に更新したら通過する。\n\n${ESCAPED}"
}
HOOK_JSON
exit 0
