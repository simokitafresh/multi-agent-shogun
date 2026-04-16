#!/usr/bin/env bash
# PostToolUse hook: 将軍のinbox未読件数を表示
# 将軍ペインでのみ発火。未読>0の時だけJSON stdout出力。
# 目的: 殿との対話中にinbox通知が埋もれる盲点の解消(軍師分析 2026-04-16)

AGENT_ID=$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null)
[ "$AGENT_ID" = "shogun" ] || exit 0

INBOX="/mnt/c/tools/multi-agent-shogun/queue/inbox/shogun.yaml"
[ -f "$INBOX" ] || exit 0

# grep -c で未読件数カウント(軽量)
UNREAD=$(grep -c 'read: false' "$INBOX" 2>/dev/null || echo 0)
[ "$UNREAD" -gt 0 ] 2>/dev/null || exit 0

# 1通でも重要な報告が含まれる可能性(殿指摘2026-04-16)。全未読で⚠️警告
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"⚠️ INBOX %d件未読。殿に応答する前にinboxと掲示板を確認せよ"}}\n' "$UNREAD"
