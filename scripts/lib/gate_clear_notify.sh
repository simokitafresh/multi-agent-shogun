#!/usr/bin/env bash
# gate_clear_notify.sh — GATE CLEAR終端のshogun/karo通知(ntfy + inbox_write)一式。
#
# cmd_karo_hotfix_t3s40_post_source_v6: extracted (moved, not duplicated) out
# of scripts/cmd_complete_gate.sh so a standalone durable-worker script
# (scripts/gate_clear_terminal_notify.sh) can source the exact same
# definitions instead of re-implementing them (a duplicate copy would drift).
# cmd_complete_gate.sh now sources this file at its original definition site;
# the 3 emergency-override synchronous call sites and the terminal
# durable-async call site both call the same in-memory functions.
#
# Depends on: SCRIPT_DIR (repo root), append_line_locked/log_gate_stderr_file
# (scripts/lib/append_line_locked.sh, which itself depends on lock_path).
# Callers that also need LOG_DIR/CMD_ID/ARCHIVE_AUTO_HANDLED (used by
# log_gate_stderr_file / notify_karo_cmd_complete_skill_hint) must set those
# before calling send_clear_notifications_once.

if ! declare -F append_line_locked >/dev/null 2>&1; then
    _GCN_LIB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    # shellcheck source=scripts/lib/append_line_locked.sh
    source "$_GCN_LIB_SCRIPT_DIR/lib/append_line_locked.sh"
    unset _GCN_LIB_SCRIPT_DIR
fi

LAST_GATE_NOTIFY_ROUTE=""
CLEAR_NOTIFICATION_SENT=false

dispatch_gate_notification_async() {
    local route="$1"
    shift
    local log_file="$SCRIPT_DIR/logs/cmd_complete_gate_async.log"

    # Notification delivery is deliberately outside the completion decision.
    # Match deploy_task.sh's fire-and-forget boundary so endpoint retries and
    # ntfy_batch's bounded flock cannot delay or alter the gate result.
    (
        if ! bash "$@" >> "$log_file" 2>&1; then
            printf '%(%Y-%m-%dT%H:%M:%S%z)T notification route=%s status=failed\n' -1 "$route" >> "$log_file"
        fi
    ) </dev/null &
    return 0
}

send_high_notification() {
    local message="$1"
    LAST_GATE_NOTIFY_ROUTE="ntfy.sh"
    dispatch_gate_notification_async "$LAST_GATE_NOTIFY_ROUTE" \
        "$SCRIPT_DIR/scripts/ntfy.sh" "$message"
}

send_info_cmd_notification() {
    local cmd_id="$1"
    local message="$2"
    local batch_script="$SCRIPT_DIR/scripts/ntfy_batch.sh"

    if [ -x "$batch_script" ]; then
        LAST_GATE_NOTIFY_ROUTE="ntfy_batch.sh"
        # ntfy_batch.sh accepts the message as its sole argument.
        dispatch_gate_notification_async "$LAST_GATE_NOTIFY_ROUTE" \
            "$batch_script" "$message"
    else
        LAST_GATE_NOTIFY_ROUTE="ntfy_cmd.sh"
        dispatch_gate_notification_async "$LAST_GATE_NOTIFY_ROUTE" \
            "$SCRIPT_DIR/scripts/ntfy_cmd.sh" "$cmd_id" "$message"
    fi
}

gate_clear_notify_dedup_key() {
    local cmd_id="$1"
    if [[ "$cmd_id" =~ ^(cmd_karo_hotfix_ga[0-9]+)(_.+)?$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    if [[ "$cmd_id" =~ ^(.+)_[0-9]{12,14}$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    printf '%s\n' "$cmd_id"
}

# cmd_karo_hotfix_gate_clear_notify_dedup_20260728: 旧dedupはqueue/inbox/{shogun,karo}.yaml
# (live inboxのみ)をgrep/re-parseする方式だった。karoは完了時手順でinbox_archive.shを高頻度
# 実行するため、1度目の通知が既読化→archiveへ退避された直後に同一cmd(family)が再GATE実行
# (BLOCK→修正→CLEAR)されると、live inboxに見つからず「未送信」と誤判定し重複配送していた
# (実測: cmd_3513/cmd_3869/cmd_4122でkaro skill_hintが2通ずつ配送。archive.doneと同じ
# queue/gates/{key}/配下に永続flagを置き、archiveの影響を受けない冪等境界にする。
# 別プロセスの同時実行に対しては (set -C) のO_EXCL相当でatomicにclaimし、
# check-then-actのレース窓を閉じる。
gate_clear_notify_flag_path() {
    local recipient="$1" cmd_id="$2" key
    key="$(gate_clear_notify_dedup_key "$cmd_id")"
    printf '%s/queue/gates/%s/notify_%s.done\n' "$SCRIPT_DIR" "$key" "$recipient"
}

# 移行backfill (家老差分レビュー2回目でグローバルmarker/lock方式を撤回): 本修正より前に
# queue/inbox(live)またはarchive/inboxへ配送済みのcmdはflagが存在しないため、無対応だと
# 次回の再GATEで1通だけ余計に送られてしまう。グローバルmarkerで「移行済み」を1回だけ判定
# する設計は、(a) marker未確定の間に他プロセスがclaimへ素通りできる競合、(b) 1ファイルの
# parse失敗を握り潰したままmarkerを確定させ欠落を永続化する、という2つの穴を持っていた。
# 対象key(recipient+cmd family)のflagをatomicにclaimできたプロセスだけがそのkeyの
# live+archive履歴を1回走査する設計にすると、claim自体が排他制御を兼ねるため上記2つの
# 穴が構造的に消える: 敗者はflag存在で即SKIP(履歴走査自体を行わない)、勝者はkeyごとに
# 高々1回だけ走査し、parse失敗はそのkeyについてだけ「証跡なし」扱いになる(他keyへ波及しない)。
gate_clear_notify_historical_evidence() {
    local recipient="$1" cmd_id="$2" key type_match f
    key="$(gate_clear_notify_dedup_key "$cmd_id")"
    case "$recipient" in
        shogun) type_match='gate_clear' ;;
        karo) type_match='skill_hint' ;;
        *) return 1 ;;
    esac

    for f in "$SCRIPT_DIR/queue/inbox/${recipient}.yaml" "$SCRIPT_DIR/archive/inbox/${recipient}_"*.yaml; do
        [ -f "$f" ] || continue
        # 高速前置フィルタ: keyが出現しないファイルはpython3起動を払わずに除外する。
        # 該当メッセージのcontentは常にkey(または家族名の元となった長いcmd_id)を
        # 部分文字列として含むため、この前置grepは偽陰性を生まない。
        grep -qF -- "$key" "$f" 2>/dev/null || continue
        if GCN_KEY="$key" GCN_TYPE="$type_match" python3 - "$f" <<'PY' 2>/dev/null
import os
import re
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

path = sys.argv[1]
key = os.environ["GCN_KEY"]
type_match = os.environ["GCN_TYPE"]


def dedup_key(cmd_id):
    m = re.match(r"^(cmd_karo_hotfix_ga[0-9]+)(_.+)?$", cmd_id)
    if m:
        return m.group(1)
    m = re.match(r"^(.+)_[0-9]{12,14}$", cmd_id)
    if m:
        return m.group(1)
    return cmd_id


try:
    data = yaml.safe_load(open(path, encoding="utf-8")) or {}
except Exception:
    sys.exit(1)

for msg in data.get("messages") or []:
    if not isinstance(msg, dict) or msg.get("type") != type_match:
        continue
    content = str(msg.get("content") or "")
    m = re.search(r"GATE CLEAR\s+—\s+(\S+)\s+完了", content)
    if m and dedup_key(m.group(1)) == key:
        sys.exit(0)
sys.exit(1)
PY
        then
            return 0
        fi
    done
    return 1
}

gate_clear_notify_claim() {
    local recipient="$1" cmd_id="$2" flag_file
    flag_file="$(gate_clear_notify_flag_path "$recipient" "$cmd_id")"
    mkdir -p "$(dirname "$flag_file")" 2>/dev/null

    if ! ( set -C; printf '%s\n' "$cmd_id" > "$flag_file" ) 2>/dev/null; then
        return 1
    fi

    if gate_clear_notify_historical_evidence "$recipient" "$cmd_id"; then
        printf '%s\tbackfill\n' "$cmd_id" > "$flag_file"
        return 1
    fi

    return 0
}

notify_shogun_gate_clear() {
    local cmd_id="$1"
    local message="${2:-GATE CLEAR — ${cmd_id} 完了}"
    local stderr_tmp flag_file
    stderr_tmp="$(mktemp)"
    flag_file="$(gate_clear_notify_flag_path shogun "$cmd_id")"

    if ! gate_clear_notify_claim shogun "$cmd_id"; then
        echo "  shogun inbox: SKIP (gate clear notify dedup)"
        rm -f "$stderr_tmp"
        return 0
    fi

    if timeout 10 bash "$SCRIPT_DIR/scripts/inbox_write.sh" shogun "$message" gate_clear cmd_complete_gate 2>"$stderr_tmp"; then
        echo "  shogun inbox: OK (gate clear notify)"
    else
        log_gate_stderr_file "notify_shogun_gate_clear inbox_write" "$stderr_tmp"
        echo "  [INFO] shogun inbox: WARN (gate clear notify failed, non-blocking)"
        # 直前のgate_clear_notify_claimが成功した(=このプロセスが排他的に作成した)flagのみを
        # 対象とするため、他プロセスのclaimを誤って消す競合はない。送信失敗時にflagを残すと
        # 通知が永久に欠落するため、次回の再試行を許可するためロールバックする。
        rm -f "$flag_file"
    fi
    rm -f "$stderr_tmp"
}

notify_karo_cmd_complete_skill_hint() {
    local cmd_id="$1"
    local message="GATE CLEAR — ${cmd_id} 完了。/cmd-complete スキルで完了処理を実行せよ。"
    local flag_file
    flag_file="$(gate_clear_notify_flag_path karo "$cmd_id")"

    # 自動archive(queued/sync/既存)を本gateが担った場合、hintの指示内容は機械が実行済み。
    # 送ると家老inboxに完了済cmdのゾンビhintが永久残留する(2026-08-26実測16件/未読19件、最古10h47m)。
    if [ "${ARCHIVE_AUTO_HANDLED:-0}" = "1" ]; then
        echo "  karo /cmd-complete hint: SKIP (archive auto-handled by gate)"
        return 0
    fi
    if ! gate_clear_notify_claim karo "$cmd_id"; then
        echo "  karo /cmd-complete hint: SKIP (dedup — already in inbox)"
    elif timeout 10 bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$message" skill_hint cmd_complete_gate 2>/dev/null; then
        echo "  karo /cmd-complete hint: OK"
    else
        echo "  [INFO] karo /cmd-complete hint: WARN (non-blocking)"
        rm -f "$flag_file"
    fi
}

send_clear_notifications_once() {
    local cmd_id="$1"
    local phase="${2:-GATE CLEAR}"

    if [ "${CLEAR_NOTIFICATION_SENT:-false}" = true ]; then
        echo "  clear notification: SKIP (already sent)"
        return 0
    fi

    echo "Auto-notification (${phase}):"
    if send_info_cmd_notification "$cmd_id" "GATE CLEAR — ${cmd_id} 完了" 2>/dev/null; then
        echo "  ${LAST_GATE_NOTIFY_ROUTE}: OK (INFO)"
    else
        echo "  [INFO] ${LAST_GATE_NOTIFY_ROUTE:-notification}: WARN (INFO notification failed, non-blocking)" >&2
    fi
    notify_shogun_gate_clear "$cmd_id" "GATE CLEAR — ${cmd_id} 完了"
    notify_karo_cmd_complete_skill_hint "$cmd_id"
    CLEAR_NOTIFICATION_SENT=true
}
