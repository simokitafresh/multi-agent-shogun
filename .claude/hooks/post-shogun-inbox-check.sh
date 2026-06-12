#!/bin/dash
[ -z "$TMUX_PANE" ] && exit 0
SCRIPT_DIR="${SHOGUN_ROOT:-/mnt/c/tools/multi-agent-shogun}"
_NON_SHOGUN_CACHE="/tmp/shogun_not_shogun_${TMUX_PANE}"
[ -e "$_NON_SHOGUN_CACHE" ] && exit 0

is_file_older_than_minutes() {
    _path="$1"
    _minutes="$2"
    [ -f "$_path" ] || return 1

    _mtime=$(stat -c %Y "$_path" 2>/dev/null) || return 1
    _now="${_NOW:-}"
    if [ -z "$_now" ]; then
        _NOW=$(date +%s 2>/dev/null) || return 1
        _now="$_NOW"
    fi
    [ $((_now - _mtime)) -gt $((_minutes * 60)) ]
}

file_stamp() {
    stat -c '%Y:%s' "$1" 2>/dev/null
}

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
if [ "${AGENT_ID:-}" != "shogun" ] || is_file_older_than_minutes "$_AID_CACHE" 30; then
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

# 復帰完了チェック: マーカーが存在しない or 480分超過(前セッション残骸)→警告(LS084)
# TTL 90分は長時間セッション(101分実測 2026-06-12)で現役マーカーを誤検知した。
# 残骸の主検知はclear_prep_check.shのマーカー削除側に移し、TTLは終日セッション安全網として480分
RECOVERY_MARKER="${SHOGUN_RECOVERY_MARKER:-/tmp/shogun_recovery_complete}"
RECOVERY_STALE=""
if [ ! -f "$RECOVERY_MARKER" ]; then
    RECOVERY_STALE=1
elif is_file_older_than_minutes "$RECOVERY_MARKER" 480; then
    RECOVERY_STALE=1
fi

# awk でカウント。inbox未変更時はmtime+sizeキャッシュで再解析を避ける。
_INBOX_STAMP=$(file_stamp "$INBOX")
_UNREAD_CACHE="/tmp/shogun_unread_${TMUX_PANE}"
_UNREAD_META="${_UNREAD_CACHE}.meta"
_UNREAD_CACHED_STAMP=""
[ -r "$_UNREAD_META" ] && { IFS= read -r _UNREAD_CACHED_STAMP; } < "$_UNREAD_META"
if [ -r "$_UNREAD_CACHE" ] && [ "$_UNREAD_CACHED_STAMP" = "$_INBOX_STAMP" ]; then
    { IFS= read -r UNREAD; } < "$_UNREAD_CACHE"
else
    UNREAD=$(awk '/read: false/{n++}END{print n+0}' "$INBOX")
    printf '%s\n' "$UNREAD" > "$_UNREAD_CACHE" 2>/dev/null
    printf '%s\n' "$_INBOX_STAMP" > "$_UNREAD_META" 2>/dev/null
fi

# 殿の直近指示を取得(LS055: 100億回従う原理的保証)
LORD_CONV="${SHOGUN_LORD_CONV_PATH:-/mnt/c/tools/multi-agent-shogun/queue/lord_conversation.jsonl}"
LORD_LAST=""
if [ -f "$LORD_CONV" ]; then
    _LORD_STAMP=$(file_stamp "$LORD_CONV")
    _LORD_CACHE="/tmp/shogun_lord_last_${TMUX_PANE}"
    _LORD_META="${_LORD_CACHE}.meta"
    _LORD_CACHED_STAMP=""
    [ -r "$_LORD_META" ] && { IFS= read -r _LORD_CACHED_STAMP; } < "$_LORD_META"
    if [ -r "$_LORD_CACHE" ] && [ "$_LORD_CACHED_STAMP" = "$_LORD_STAMP" ]; then
        { IFS= read -r LORD_LAST; } < "$_LORD_CACHE"
    else
        LORD_LAST=$(tail -100 "$LORD_CONV" 2>/dev/null | awk '
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
        target = json_value($0, "target")
        if (target != "" && target != "shogun") next
        if(summary) { ts=substr(ts_raw,12,5); lines[++n] = ts " " substr(summary,1,70) }
    }END{
        start = (n > 5) ? n - 4 : 1
        for(i=start; i<=n; i++) printf "%s | ", lines[i]
    }' 2>/dev/null)
        printf '%s\n' "$LORD_LAST" > "$_LORD_CACHE" 2>/dev/null
        printf '%s\n' "$_LORD_STAMP" > "$_LORD_META" 2>/dev/null
    fi
fi

# ─── GATE CLEAR 効果再確認リマインダー（cmd_3259: 洗脳#6構造防止） ───
# 未読gate_clearメッセージから数値改善目的のcmdを検出し、効果検証リマインダーを強制注入
EFFECT_REMIND=""
if [ "${UNREAD:-0}" -gt 0 ]; then
    _STKY="${SHOGUN_TO_KARO_PATH:-/mnt/c/tools/multi-agent-shogun/queue/shogun_to_karo.yaml}"
    if [ -f "$_STKY" ]; then
        _STKY_STAMP=$(file_stamp "$_STKY")
        _EFFECT_KEY="${_INBOX_STAMP}|${_STKY_STAMP}"
        _EFFECT_CACHE="/tmp/shogun_effect_remind_${TMUX_PANE}"
        _EFFECT_META="${_EFFECT_CACHE}.meta"
        _EFFECT_CACHED_KEY=""
        [ -r "$_EFFECT_META" ] && { IFS= read -r _EFFECT_CACHED_KEY; } < "$_EFFECT_META"
        if [ -r "$_EFFECT_CACHE" ] && [ "$_EFFECT_CACHED_KEY" = "$_EFFECT_KEY" ]; then
            EFFECT_REMIND=$(cat "$_EFFECT_CACHE" 2>/dev/null)
        else
            _gc_cmds=$(awk '
            /^- /{ if(gc&&ur&&c){ if(match(c,/cmd_[0-9]+/)) print substr(c,RSTART,RLENGTH) } gc=0;ur=0;c="" }
            /type:.*gate_clear/{ gc=1 } /read: false/{ ur=1 }
            /content:.*GATE CLEAR/{ s=$0; sub(/.*content:[[:space:]]*\047?/,"",s); sub(/\047?[[:space:]]*$/,"",s); c=s }
            END{ if(gc&&ur&&c){ if(match(c,/cmd_[0-9]+/)) print substr(c,RSTART,RLENGTH) } }
            ' "$INBOX" 2>/dev/null)
            for _gc_cmd in $_gc_cmds; do
                _purpose=$(awk -v cmd="$_gc_cmd" '
                /^  [a-zA-Z_].*:$/{ k=$0; gsub(/^[[:space:]]+|:[[:space:]]*$/,"",k); f=(k==cmd) }
                f && /purpose:/{ sub(/.*purpose:[[:space:]]*"?/,""); sub(/"[[:space:]]*$/,""); print; exit }
                ' "$_STKY" 2>/dev/null)
                [ -z "$_purpose" ] && continue
                _hi=$(printf '%s' "$_purpose" | grep -cE '改善|向上|削減|短縮|高速化|最適化|増加|減少|improve|optimize|reduce|increase|boost' 2>/dev/null) || _hi=0
                _hm=$(printf '%s' "$_purpose" | grep -ciE '精度|率|rate|precision|recall|accuracy|速度|speed|件数|count|偽陽性|FP|useful|score|スコア' 2>/dev/null) || _hm=0
                if [ "$_hi" -gt 0 ] && [ "$_hm" -gt 0 ]; then
                    _kws=$(printf '%s' "$_purpose" | grep -oE '改善|向上|削減|短縮|高速化|最適化|精度|率|useful|speed|precision|recall|accuracy|score|偽陽性' 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')
                    EFFECT_REMIND="${EFFECT_REMIND:+${EFFECT_REMIND}\\n}⚠効果再確認: ${_gc_cmd}は数値改善目的(${_kws:-metrics})。計測スクリプト再実行で修正前→後の差分を確認せよ。例: bash scripts/gates/gate_shogun_startup.sh"
                fi
            done
            printf '%s\n' "$EFFECT_REMIND" > "$_EFFECT_CACHE" 2>/dev/null
            printf '%s\n' "$_EFFECT_KEY" > "$_EFFECT_META" 2>/dev/null
        fi
    fi
fi

# ─── GATE CLEAR後 自走チェック（L5: CLEAR→殿待ち停止防止） ───
# insightキュー件数+掲示板action_required件数を強制表示し、自走を促す
SELF_DRIVE=""
if [ -n "$EFFECT_REMIND" ]; then
    _insight_count=0
    _blt_action_count=0
    _insight_file="${SCRIPT_DIR}/queue/insights.yaml"
    _blt_file="${SCRIPT_DIR}/queue/bulletin_board.yaml"
    if [ -f "$_insight_file" ]; then
        _insight_count=$(grep -c "status: pending" "$_insight_file" 2>/dev/null || echo 0)
    fi
    if [ -f "$_blt_file" ]; then
        _blt_action_count=$(awk '/action_type:.*action_required/{ar=1} ar && /actioned_by:.*'\'''\''/{c++; ar=0} END{print c+0}' "$_blt_file" 2>/dev/null || echo 0)
    fi
    if [ "$_insight_count" -gt 0 ] || [ "$_blt_action_count" -gt 0 ]; then
        SELF_DRIVE="★自走チェック: CLEAR後に殿待ちで止まるな(LS-A06/LS049)。insightキュー=${_insight_count}件 掲示板action_required=${_blt_action_count}件"
    fi
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
if [ -n "$EFFECT_REMIND" ]; then
    MSG="${MSG:+${MSG}\\n}${EFFECT_REMIND}"
fi
if [ -n "$SELF_DRIVE" ]; then
    MSG="${MSG:+${MSG}\\n}${SELF_DRIVE}"
fi

[ -n "$MSG" ] && printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$MSG"
