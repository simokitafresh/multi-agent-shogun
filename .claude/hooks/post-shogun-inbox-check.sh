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

# awk でカウント(subshell 不要)
UNREAD=$(awk '/read: false/{n++}END{print n+0}' "$INBOX")
[ "${UNREAD:-0}" -gt 0 ] || exit 0

# 1通でも重要な報告が含まれる可能性(殿指摘2026-04-16)。全未読で⚠️警告
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"⚠️ INBOX %d件未読。殿に応答する前にinboxと掲示板を確認せよ"}}\n' "$UNREAD"
