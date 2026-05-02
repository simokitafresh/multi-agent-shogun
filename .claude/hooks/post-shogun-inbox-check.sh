#!/bin/dash
[ -z "$TMUX_PANE" ] && exit 0
_NON_SHOGUN_CACHE="/tmp/shogun_not_shogun_${TMUX_PANE}"
[ -e "$_NON_SHOGUN_CACHE" ] && exit 0

# PostToolUse hook: 将軍のinbox未読件数を表示
# 将軍ペインでのみ発火。未読>0の時だけJSON stdout出力。
# 目的: 殿との対話中にinbox通知が埋もれる盲点の解消(軍師分析 2026-04-16)
# cmd_2074: agent_id キャッシュ + awk カウントで高速化

# Cache agent_id per pane to avoid tmux IPC on every PostToolUse invocation
# TTL 30min: ペイン再配置(/reset-layout)後に古い値が残る問題を防止(2026-04-26 gunshi修正)
_AID_CACHE="/tmp/shogun_aid_${TMUX_PANE}"
if [ -r "$_AID_CACHE" ]; then
    { IFS= read -r AGENT_ID; } < "$_AID_CACHE"
fi
if [ "${AGENT_ID:-}" != "shogun" ] || [ -n "$(find "$_AID_CACHE" -mmin +30 2>/dev/null)" ]; then
    AGENT_ID=$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null)
    if [ "$AGENT_ID" = "shogun" ]; then
        rm -f "$_NON_SHOGUN_CACHE" 2>/dev/null
        printf '%s\n' "$AGENT_ID" > "$_AID_CACHE" 2>/dev/null
    elif [ -n "$AGENT_ID" ]; then
        : > "$_NON_SHOGUN_CACHE" 2>/dev/null
        printf '%s\n' "$AGENT_ID" > "$_AID_CACHE" 2>/dev/null
    fi
fi
[ "$AGENT_ID" = "shogun" ] || exit 0

INBOX="${SHOGUN_INBOX_PATH:-/mnt/c/tools/multi-agent-shogun/queue/inbox/shogun.yaml}"
[ -f "$INBOX" ] || exit 0

# 復帰完了チェック: マーカーが存在しない or 90分超過(前セッション残骸)→警告(LS084)
RECOVERY_MARKER="${SHOGUN_RECOVERY_MARKER:-/tmp/shogun_recovery_complete}"
RECOVERY_STALE=""
if [ ! -f "$RECOVERY_MARKER" ]; then
    RECOVERY_STALE=1
elif [ -n "$(find "$RECOVERY_MARKER" -mmin +90 2>/dev/null)" ]; then
    RECOVERY_STALE=1
fi

# awk でカウント(subshell 不要)
UNREAD=$(awk '/read: false/{n++}END{print n+0}' "$INBOX")

# 殿の直近指示を取得(LS055: 100億回従う原理的保証)
LORD_CONV="${SHOGUN_LORD_CONV_PATH:-/mnt/c/tools/multi-agent-shogun/queue/lord_conversation.jsonl}"
LORD_LAST=""
if [ -f "$LORD_CONV" ]; then
    LORD_LAST=$(tail -50 "$LORD_CONV" 2>/dev/null | awk '
    function json_value(line, key,    s, prefix) {
        s = line
        prefix = "\"" key "\"[[:space:]]*:[[:space:]]*\""
        if (match(s, prefix)) {
            s = substr(s, RSTART + RLENGTH)
            if (match(s, /"/)) return substr(s, 1, RSTART - 1)
        }
        return ""
    }
    /"direction"[[:space:]]*:[[:space:]]*"inbound"/{
        ts_raw = json_value($0, "ts")
        summary = json_value($0, "summary")
        if(summary) { ts=substr(ts_raw,12,5); lines[++n] = ts " " substr(summary,1,70) }
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
