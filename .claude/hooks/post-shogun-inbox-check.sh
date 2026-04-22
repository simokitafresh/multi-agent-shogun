#!/usr/bin/env bash
# PostToolUse hook: 将軍のinbox未読件数を表示
# 将軍ペインでのみ発火。未読>0の時だけJSON stdout出力。
# 目的: 殿との対話中にinbox通知が埋もれる盲点の解消(軍師分析 2026-04-16)
# cmd_2074: agent_id キャッシュ + awk カウントで高速化

[[ -z "$TMUX_PANE" ]] && exit 0

# Cache agent_id per pane to avoid tmux IPC on every PostToolUse invocation
_AID_CACHE="/tmp/shogun_aid_${TMUX_PANE//[^a-zA-Z0-9_]/_}"
if [[ -f "$_AID_CACHE" ]]; then
    { IFS= read -r AGENT_ID; } < "$_AID_CACHE"
else
    AGENT_ID=$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null)
    [[ -n "$AGENT_ID" ]] && printf '%s\n' "$AGENT_ID" > "$_AID_CACHE" 2>/dev/null
fi
[ "$AGENT_ID" = "shogun" ] || exit 0

INBOX="/mnt/c/tools/multi-agent-shogun/queue/inbox/shogun.yaml"
[ -f "$INBOX" ] || exit 0

# 復帰完了チェック: マーカーが存在しない or 90分超過(前セッション残骸)→警告(LS084)
RECOVERY_MARKER="/tmp/shogun_recovery_complete"
RECOVERY_STALE=""
if [ ! -f "$RECOVERY_MARKER" ]; then
    RECOVERY_STALE=1
elif [ -n "$(find "$RECOVERY_MARKER" -mmin +90 2>/dev/null)" ]; then
    RECOVERY_STALE=1
fi

# awk でカウント(subshell 不要)
UNREAD=$(awk '/read: false/{n++}END{print n+0}' "$INBOX")

# 殿の直近指示を取得(LS055: 100億回従う原理的保証)
LORD_CONV="/mnt/c/tools/multi-agent-shogun/queue/lord_conversation.jsonl"
LORD_LAST=""
if [ -f "$LORD_CONV" ]; then
    LORD_LAST=$(tail -50 "$LORD_CONV" 2>/dev/null | awk '/"direction"[[:space:]]*:[[:space:]]*"inbound"/{
        match($0, /"ts"[[:space:]]*:[[:space:]]*"([^"]*)"/, t)
        match($0, /"summary"[[:space:]]*:[[:space:]]*"([^"]*)"/, a)
        if(a[1]) { ts=substr(t[1],12,5); lines[++n] = ts " " substr(a[1],1,70) }
    }END{
        start = (n > 5) ? n - 4 : 1
        for(i=start; i<=n; i++) printf "%s | ", lines[i]
    }' 2>/dev/null)
fi

# 出力組立て
MSG=""
if [ "${RECOVERY_STALE:-}" = "1" ]; then
    MSG="⚠️ RECOVERY INCOMPLETE — 復帰手順(Step 1-11)を完了してから殿に応答せよ"
fi
if [ "${UNREAD:-0}" -gt 0 ]; then
    MSG="${MSG:+${MSG}\\n}⚠️ INBOX ${UNREAD}件未読。殿に応答する前にinboxと掲示板を確認せよ"
fi
if [ -n "$LORD_LAST" ]; then
    MSG="${MSG:+${MSG}\\n}★確認すべき事: ${LORD_LAST}"
fi

[ -n "$MSG" ] && printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$MSG"
