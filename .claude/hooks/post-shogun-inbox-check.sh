#!/usr/bin/env bash
[ -z "$TMUX_PANE" ] && exit 0
# Prefer the hook-injected root; retain git discovery for standalone use.
_REPO_ROOT="${SHOGUN_ROOT:-}"
if [ -z "$_REPO_ROOT" ]; then
_REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[ -z "$_REPO_ROOT" ] && exit 0
SCRIPT_DIR="$_REPO_ROOT"
_REPORT_TERMINAL_STATE_LIB="${SCRIPT_DIR}/scripts/lib/report_terminal_state.sh"
_REPORT_TERMINAL_STATE_READY=0
if [ -r "$_REPORT_TERMINAL_STATE_LIB" ] && source "$_REPORT_TERMINAL_STATE_LIB" 2>/dev/null && \
   declare -F report_terminal_state >/dev/null 2>&1; then
    _REPORT_TERMINAL_STATE_READY=1
fi
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
    stat -c '%n:%y:%s' "$1" 2>/dev/null
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

INBOX="${SHOGUN_INBOX_PATH:-${SCRIPT_DIR}/queue/inbox/shogun.yaml}"
[ -f "$INBOX" ] || exit 0

# 復帰完了チェック: マーカーが存在しない or 480分超過(前セッション残骸)→警告(LS084)
# TTL 90分は長時間セッション(101分実測 2026-06-12)で現役マーカーを誤検知した。
# 残骸の主検知はclear_prep_check.shのマーカー削除側に移し、TTLは終日セッション安全網として480分
RECOVERY_MARKER="${SHOGUN_RECOVERY_MARKER:-${SCRIPT_DIR}/logs/shogun_recovery_complete}"
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

# 殿の未回答直近指示を取得(LS055: 最新指示を保持しつつPostToolUse注入を有界化)
LORD_CONV="${SHOGUN_LORD_CONV_PATH:-${SCRIPT_DIR}/queue/lord_conversation.jsonl}"
LORD_LAST=""
if [ -f "$LORD_CONV" ]; then
    _LORD_STAMP=$(file_stamp "$LORD_CONV")
    _LORD_CACHE="/tmp/shogun_lord_last_${TMUX_PANE}"
    _LORD_META="${_LORD_CACHE}.meta"
    _LORD_CACHED_STAMP=""
    _LORD_PENDING_NOW="${SHOGUN_LORD_PENDING_NOW:-$(date +%s 2>/dev/null)}"
    _LORD_PENDING_TTL="${SHOGUN_LORD_PENDING_TTL_SEC:-3600}"
    _LORD_CACHE_KEY="${_LORD_STAMP}|$((_LORD_PENDING_NOW / 60))|${_LORD_PENDING_TTL}"
    [ -r "$_LORD_META" ] && { IFS= read -r _LORD_CACHED_STAMP; } < "$_LORD_META"
    if [ -r "$_LORD_CACHE" ] && [ "$_LORD_CACHED_STAMP" = "$_LORD_CACHE_KEY" ]; then
        { IFS= read -r LORD_LAST; } < "$_LORD_CACHE"
    else
        LORD_LAST=$(tail -200 "$LORD_CONV" 2>/dev/null | \
            SHOGUN_LORD_PENDING_TTL_SEC="$_LORD_PENDING_TTL" \
            SHOGUN_LORD_PENDING_NOW="$_LORD_PENDING_NOW" python3 -c '
import datetime as dt, json, os, sys, time

ttl = max(0, int(os.environ.get("SHOGUN_LORD_PENDING_TTL_SEC", "3600")))
now_raw = os.environ.get("SHOGUN_LORD_PENDING_NOW", "").strip()
now = float(now_raw) if now_raw else time.time()
pending = []
for raw in sys.stdin:
    try:
        event = json.loads(raw)
    except (TypeError, ValueError):
        continue
    direction = str(event.get("direction") or "")
    agent = str(event.get("agent") or "")
    target = str(event.get("target") or "")
    if direction == "response" and agent == "shogun" and target == "lord":
        pending.clear()
        continue
    if direction != "inbound" or agent not in {"", "lord"} or target not in {"", "shogun"}:
        continue
    summary = " ".join(str(event.get("summary") or "").split())
    if not summary:
        continue
    ts_raw = str(event.get("ts") or "")
    try:
        stamp = dt.datetime.fromisoformat(ts_raw.replace("Z", "+00:00")).timestamp()
    except ValueError:
        continue
    pending.append((stamp, ts_raw, summary))

seen = set(); selected = []
for stamp, ts_raw, summary in reversed(pending):
    key = summary.casefold()
    if now - stamp > ttl or key in seen:
        continue
    seen.add(key); selected.append((ts_raw, summary))
    if len(selected) == 3:
        break
print(" | ".join(f"{ts[11:16]} {summary[:70]}" for ts, summary in selected), end="")
' 2>/dev/null)
        printf '%s\n' "$LORD_LAST" > "$_LORD_CACHE" 2>/dev/null
        printf '%s\n' "$_LORD_CACHE_KEY" > "$_LORD_META" 2>/dev/null
    fi
fi

# ─── GATE CLEAR 効果再確認リマインダー（cmd_3259: 洗脳#6構造防止） ───
# 未読gate_clearメッセージから数値改善目的のcmdを検出し、効果検証リマインダーを強制注入
EFFECT_REMIND=""
if [ "${UNREAD:-0}" -gt 0 ]; then
    _STKY="${SHOGUN_TO_KARO_PATH:-${SCRIPT_DIR}/queue/shogun_to_karo.yaml}"
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
            # LS-A09(41): 相互検証強制(殿指摘2026-08-12 11:57) — gate_clear検分は速度/機能ACだけでなく
            # 目的AC(工程ToBeとdiffの整合)と報告数値1点の自己再実行を要求する
            if [ -n "$_gc_cmds" ]; then
                EFFECT_REMIND="${EFFECT_REMIND:+${EFFECT_REMIND}\\n}★相互検証(LS-A09(41)): GATE CLEAR検分前に(1)このcommitは工程の目的(ToBe)へ近づくか離れるかをdiff現物で判定 (2)報告の核心数値を最低1点、自分のコマンドで再実行して突合せよ。速度/機能AC PASSは目的整合の証明ではない"
            fi
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
        SELF_DRIVE="★自走チェック: CLEAR後に殿待ちで止まるな。insightキュー=${_insight_count}件 掲示板action_required=${_blt_action_count}件"
    fi
fi

# ─── 陣形図 failed/stall忍者検出（殿22:41「家老へナッジせよ」自動化） ───
NINJA_ALERT=""
_snapshot="${SCRIPT_DIR}/queue/karo_snapshot.txt"
if [ -f "$_snapshot" ]; then
    # snapshot is only a candidate index.  Task YAML + live pane state are the
    # decision sources, so a freshly deployed task cannot become a false stall.
    _alert_now="${SHOGUN_ALERT_NOW:-$(date +%s 2>/dev/null)}"
    _alert_grace="${SHOGUN_SNAPSHOT_GRACE_SEC:-120}"
    _task_dir="${SHOGUN_TASK_DIR:-${SCRIPT_DIR}/queue/tasks}"
    _pane_states=$(tmux list-panes -a -F '#{@agent_id}|#{@agent_state}' 2>/dev/null || true)
    _failed=""
    _stall=""
    while IFS='|' read -r _kind _agent _task _snap_status _rest; do
        [ "$_kind" = "ninja" ] || continue
        _task_file="${_task_dir}/${_agent}.yaml"
        [ -f "$_task_file" ] || continue
        _task_status=$(awk '/^[[:space:]]*status:/{gsub(/["'\''[:space:]]/,"",$2); print $2; exit}' "$_task_file")
        _deployed=$(awk '/^[[:space:]]*deployed_at:/{sub(/^[^:]*:[[:space:]]*/,""); gsub(/["'\'']/,""); print; exit}' "$_task_file")
        _deployed_epoch=0
        [ -n "$_deployed" ] && _deployed_epoch=$(date -d "$_deployed" +%s 2>/dev/null || echo 0)
        _pane_state=$(printf '%s\n' "$_pane_states" | awk -F'|' -v a="$_agent" '$1==a{print $2; exit}')
        if [ "$_snap_status" = "failed" ] && [ "$_task_status" = "failed" ]; then
            _report_rel=$(awk '/^[[:space:]]*report_path:/{v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/["'\'' ]/,"",v); print v; exit}' "$_task_file" 2>/dev/null)
            _report_state="UNKNOWN"
            if [ "$_REPORT_TERMINAL_STATE_READY" -eq 1 ] && [ -n "$_report_rel" ]; then
                case "$_report_rel" in
                    /*) _report_path="$_report_rel" ;;
                    *) _report_path="${SCRIPT_DIR}/$_report_rel" ;;
                esac
                _report_state=$(report_terminal_state "$_report_path" 2>/dev/null) || _report_state="UNKNOWN"
            fi
            # A complete blocked report is already terminal evidence.  Every
            # other state (including SUCCESS mismatch, OPEN, missing/UNKNOWN,
            # or an unavailable SSOT) remains an actionable failed alert.
            if [ "$_report_state" != "CLOSED_BLOCKED" ]; then
                _failed="${_failed:+${_failed},}${_agent}"
            fi
        elif [ "$_snap_status" = "assigned" ] && printf '%s' "$_rest" | grep -q 'CTX:0%'; then
            _age=$((_alert_now - _deployed_epoch))
            if [ "$_task_status" = "assigned" ] && [ "$_deployed_epoch" -gt 0 ] && \
               [ "$_age" -ge "$_alert_grace" ] && [ "$_pane_state" = "idle" ]; then
                _stall="${_stall:+${_stall},}${_agent}"
            fi
        fi
    done < "$_snapshot"
    if [ -n "$_failed" ] || [ -n "$_stall" ]; then
        # Session-scope dedup: only alert when failed/stall set changes (LS094)
        _dedup_file="${SHOGUN_SNAPSHOT_DEDUP_FILE:-/tmp/shogun_snapshot_alert_dedup}"
        _current_set="f=${_failed}|s=${_stall}"
        _prev_set=""
        [ -f "$_dedup_file" ] && _prev_set=$(cat "$_dedup_file" 2>/dev/null || true)
        if [ "$_current_set" = "$_prev_set" ]; then
            NINJA_ALERT=""
        else
            echo "$_current_set" > "$_dedup_file"
            NINJA_ALERT="★陣形図異常: "
            [ -n "$_failed" ] && NINJA_ALERT="${NINJA_ALERT}failed=[${_failed}] "
            [ -n "$_stall" ] && NINJA_ALERT="${NINJA_ALERT}stall疑い=[${_stall}] "
            NINJA_ALERT="${NINJA_ALERT}— 家老へナッジまたはcapture-paneで実態確認せよ"
        fi
    fi
fi

# ─── 委任初回検分の自動注入(殿裁定2026-07-28 02:28「意思依存は洗脳だ」) ───
# inbox_write.sh(将軍→家老 task_assigned)が立てたmarkerを検知し、猶予経過後の
# 最初のPostToolUseで家老paneを自動captureして注入する。将軍の意志に依存しない。
DELEGATION_VERIFY=""
_DELEG_MARKER="${SHOGUN_DELEGATION_MARKER:-/tmp/shogun_delegation_pending}"
if [ -f "$_DELEG_MARKER" ]; then
    _deleg_ts=$(cat "$_DELEG_MARKER" 2>/dev/null || echo 0)
    _deleg_now="${SHOGUN_DELEG_NOW:-$(date +%s 2>/dev/null)}"
    _deleg_grace="${SHOGUN_DELEG_GRACE_SEC:-120}"
    case "$_deleg_ts" in ''|*[!0-9]*) _deleg_ts=0 ;; esac
    if [ "$_deleg_ts" -gt 0 ] && [ $((_deleg_now - _deleg_ts)) -ge "$_deleg_grace" ]; then
        _karo_pane=$(tmux list-panes -a -F '#{@agent_id}|#{pane_id}' 2>/dev/null | awk -F'|' '$1=="karo"{print $2; exit}')
        if [ -n "$_karo_pane" ]; then
            _karo_tail=$(tmux capture-pane -t "$_karo_pane" -p 2>/dev/null | grep -v '^[[:space:]]*$' | tail -5 | tr '\n' ' ' | cut -c1-400)
            DELEGATION_VERIFY="★委任初回検分(自動capture): 家老pane実態=[${_karo_tail:-取得失敗}] — 委任内容と実態が一致するか判定せよ。並列度・配備方式の乖離は即是正指示"
            rm -f "$_DELEG_MARKER" 2>/dev/null
        fi
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
# [MEM:]事前リマインダ(2026-08-23根治): 三層preflight成功済みターンでは応答直前まで
# [MEM:]必須を毎tool後に注入する。stop hookの事後BLOCK(1往復浪費)を事前注入で防ぐ。
# 検出はstop_check_inbox.shのhas_successful_three_layer_preflightと同一のevidence正本を参照。
_MEM_EVIDENCE_DIR="${THREE_LAYER_PREACTION_EVIDENCE_DIR:-$SCRIPT_DIR/logs/preaction_memory}"
if ls "$_MEM_EVIDENCE_DIR"/evidence_shogun_*.json >/dev/null 2>&1; then
    if grep -l '"status": *"success"' "$_MEM_EVIDENCE_DIR"/evidence_shogun_*.json >/dev/null 2>&1; then
        MSG="${MSG:+${MSG}\\n}★[MEM:]必須: 本ターンは三層preflight成功済み。殿への応答に[MEM: memory_db/semantic/obsidian]引用タグ(不要時は[MEM: n/a — 理由])を必ず含めよ。タグ欠落はstop hookでBLOCKされ1往復を失う"
    fi
fi
if [ -n "$EFFECT_REMIND" ]; then
    MSG="${MSG:+${MSG}\\n}${EFFECT_REMIND}"
fi
# escalation未対処検出(Q6自動化ターゲット: 洗脳#5先送り防止)
ESCALATION_UNREAD=0
ESCALATION_NEW=""
if [ -f "$INBOX" ]; then
    _esc_state="${SHOGUN_ESCALATION_DEDUP_FILE:-/tmp/shogun_escalation_alert_dedup}"
    ESCALATION_NEW=$(INBOX_PATH="$INBOX" STATE_PATH="$_esc_state" python3 -c '
import fcntl, hashlib, os, yaml
p=os.environ["INBOX_PATH"]; state=os.environ["STATE_PATH"]
data=yaml.safe_load(open(p, encoding="utf-8")) or {}
active=[]
for m in data.get("messages", []):
    if m.get("type") != "escalation" or m.get("read") is not False or str(m.get("actioned_by") or "").strip(): continue
    raw="|".join(str(m.get(k) or "").strip() for k in ("from","action","content"))
    sig=hashlib.sha256(raw.encode()).hexdigest(); active.append(sig)
os.makedirs(os.path.dirname(state) or ".", exist_ok=True)
with open(state,"a+",encoding="utf-8") as f:
    fcntl.flock(f, fcntl.LOCK_EX); f.seek(0); seen=set(f.read().splitlines())
    new=[s for s in active if s not in seen]
    if new: f.seek(0,2); f.write("".join(s+"\n" for s in new)); f.flush(); os.fsync(f.fileno())
print(f"{len(active)}|{len(new)}")
' 2>/dev/null || printf '0|0')
    ESCALATION_UNREAD=${ESCALATION_NEW%%|*}
    ESCALATION_NEW=${ESCALATION_NEW#*|}
fi
if [ "${ESCALATION_NEW:-0}" -gt 0 ]; then
    MSG="${MSG:+${MSG}\\n}⚠ CRITICAL 新規エスカレーション${ESCALATION_NEW}件（未対処計${ESCALATION_UNREAD}件）— 即時行動せよ(洗脳#5先送り防止)"
fi
if [ -n "$SELF_DRIVE" ]; then
    MSG="${MSG:+${MSG}\\n}${SELF_DRIVE}"
fi
if [ -n "$NINJA_ALERT" ]; then
    MSG="${MSG:+${MSG}\\n}${NINJA_ALERT}"
fi
if [ -n "$DELEGATION_VERIFY" ]; then
    _dv_escaped=$(printf '%s' "$DELEGATION_VERIFY" | sed 's/\\/\\\\/g; s/"/\\"/g')
    MSG="${MSG:+${MSG}\\n}${_dv_escaped}"
fi

[ -n "$MSG" ] && printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$MSG"
