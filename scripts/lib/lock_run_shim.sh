#!/bin/bash
# lock_run_shim.sh — 単一 publisher 化 U1: flock + GNU timeout supervisor(publisher_queue.sh lock-run の実体)
#
# Usage: lock_run_shim.sh --bound <sec> --lock-file <path> --run-dir <path> [--run-id <id>] -- <command...>
#
# 契約(設計書 §9.1 U1):
#   (1) command は GNU `timeout -k 10 <sec> -- bash -c '...'` 直下で起動。setsid は使わない
#       (GNU timeoutが自分でcommandを新process groupに置き、期限でgroup全体へTERM→10s後KILLを
#       timeout自身が送るため。shimは信号送出コマンドを一切書かない=D006禁止コマンド0)
#   (2) wait後に <run_id>.rc の有無でrcを写像:
#         rc fileあり → その値(childが124を返しても固有失敗として区別)
#         rc fileなし ∧ timeout rc∈{124,137} → rc=210(timeout専用)
#         rc fileなし ∧ その他 → rc=211
#   (3) timeoutの子group PGID(=timeoutが直接起動する内側bashのPID)を記録し、
#       ps -eo pid,pgid,sid,lstart,cmd を全走査して同PGIDのprocess数をsurvivorとしてdone receiptへ書く
#   (4) done receipt(rc/reason/親子孫のPID・PGID・SID/survivor数)はshimだけが書く
#   取得失敗(flock timeout) rc=4
set -e

BOUND=""
LOCK_FILE=""
RUN_DIR=""
RUN_ID=""

while [ $# -gt 0 ]; do
    case "$1" in
        --bound) BOUND="$2"; shift 2 ;;
        --lock-file) LOCK_FILE="$2"; shift 2 ;;
        --run-dir) RUN_DIR="$2"; shift 2 ;;
        --run-id) RUN_ID="$2"; shift 2 ;;
        --) shift; break ;;
        *) echo "lock_run_shim: unknown arg: $1" >&2; exit 1 ;;
    esac
done

if [ -z "$BOUND" ] || [ -z "$LOCK_FILE" ] || [ -z "$RUN_DIR" ] || [ $# -eq 0 ]; then
    echo "lock_run_shim: --bound/--lock-file/--run-dir と -- <command...> は必須" >&2
    exit 1
fi
[ -n "$RUN_ID" ] || RUN_ID="$(date +%s%N)_$$"

# 防御的二重チェック: lock/run先が /tmp または tracked repo root 配下なら拒否(H2、AC1停止条件)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for _p in "$(dirname "$LOCK_FILE")" "$RUN_DIR"; do
    _real="$(mkdir -p "$_p" 2>/dev/null; cd "$_p" 2>/dev/null && pwd)"
    case "$_real" in
        /tmp|/tmp/*)
            echo "lock_run_shim: FATAL path under /tmp: $_real" >&2
            exit 2
            ;;
        "$REPO_ROOT"|"$REPO_ROOT"/*)
            echo "lock_run_shim: FATAL path under tracked repo root: $_real" >&2
            exit 2
            ;;
    esac
done

mkdir -p "$RUN_DIR"
RC_FILE="$RUN_DIR/${RUN_ID}.rc"
PGID_FILE="$RUN_DIR/${RUN_ID}.pgid"
DONE_FILE="$RUN_DIR/${RUN_ID}.done"
rm -f "$RC_FILE" "$PGID_FILE" "$DONE_FILE"

# ps -eo pid,ppid,pgid,sid,cmd の中から同PGIDの全プロセスをJSON配列にして返す
ps_snapshot_json_for_pgid() {
    local want="$1"
    { ps -eo pid=,ppid=,pgid=,sid=,cmd= 2>/dev/null || true; } | while IFS= read -r _line; do
        set -- $_line
        local pid="$1" ppid="$2" pgid="$3" sid="$4"
        [ "$pgid" = "$want" ] || continue
        shift 4
        local cmd_rest="$*"
        jq -n --arg pid "$pid" --arg ppid "$ppid" --arg pgid "$pgid" --arg sid "$sid" --arg cmd "$cmd_rest" \
            '{pid:($pid|tonumber),ppid:($ppid|tonumber),pgid:($pgid|tonumber),sid:($sid|tonumber),cmd:$cmd}'
    done | jq -s '.'
}

exec 9>"$LOCK_FILE"
if ! flock -w 300 9; then
    echo "lock_run_shim: flock acquire failed(300s) run_id=$RUN_ID lock=$LOCK_FILE" >&2
    exit 4
fi

# 注1: GNU timeoutはDURATION引数の後に"--"を置くと、それ自体をCOMMANDとして解釈してしまう
# (実測: `timeout -k 10 5 -- cmd` は "failed to run command '--'" で失敗する。DURATION以降は
# 素のCOMMAND [ARG...] を渡す)。
# 注2: このinner bash自身がTERMをtrapしていないと、groupへのTERM一斉送信でinner bashが
# 即死し、timeoutは「子が終了した」とみなしてKILL escalationを一切送らない。結果、TERMを
# 無視するcommand(の子孫)だけが生き残って検出漏れになる(実測で確認済み)。inner bashも
# TERMを無視し、KILL(trap不可)でのみgroup全体が確実に終わるようにする。
# 注3: PGIDは "$$" ではなく `ps -o pgid=` の実測値を記録する(実測: GNU timeoutは自分自身を
# 新process groupのleaderにし、子孫は全員timeout自身のPIDと同じpgidを継承する。spec文言の
# 「timeout子のPID」を$$と仮定するとsurvivor走査が0件になる=誤検出の実バグを本実装で検出)。
RC_FILE="$RC_FILE" PGID_FILE="$PGID_FILE" \
    timeout -k 10 "$BOUND" bash -c '
        trap "" TERM
        ps -o pgid= -p "$$" | tr -d " " > "$PGID_FILE"
        "$@"
        echo $? > "$RC_FILE"
    ' bash "$@" &
TIMEOUT_SHELL_PID=$!

# 内側bashが $$ をPGID_FILEへ書くのを待つ(起動直後、非busy-loop)
_i=0
while [ "$_i" -lt 50 ]; do
    [ -s "$PGID_FILE" ] && break
    sleep 0.1
    _i=$((_i + 1))
done

PGID=""
[ -s "$PGID_FILE" ] && PGID="$(cat "$PGID_FILE")"

PIDS_AT_START="[]"
if [ -n "$PGID" ]; then
    # 単発snapshotは孫プロセスのfork完了前後で取りこぼす実測があったため、
    # 短間隔で複数回scanし最も多くのprocessを捉えたsnapshotを採用する
    START_BEST_COUNT=0
    _j=0
    while [ "$_j" -lt 10 ]; do
        _snap="$(ps_snapshot_json_for_pgid "$PGID")"
        _cnt="$(printf '%s' "$_snap" | jq 'length')"
        if [ "$_cnt" -gt "$START_BEST_COUNT" ]; then
            PIDS_AT_START="$_snap"
            START_BEST_COUNT="$_cnt"
        fi
        sleep 0.1
        _j=$((_j + 1))
    done
fi

set +e
wait "$TIMEOUT_SHELL_PID"
TIMEOUT_STATUS=$?
set -e

RC=""
REASON=""
if [ -s "$RC_FILE" ]; then
    RC="$(cat "$RC_FILE")"
    REASON="child_reported_rc"
elif [ "$TIMEOUT_STATUS" -eq 124 ] || [ "$TIMEOUT_STATUS" -eq 137 ]; then
    RC=210
    REASON="bound_timeout(timeout_status=$TIMEOUT_STATUS)"
else
    RC=211
    REASON="child_unknown_termination(timeout_status=$TIMEOUT_STATUS)"
fi

SURVIVORS_AT_END="[]"
SURVIVOR_COUNT=0
if [ -n "$PGID" ]; then
    SURVIVORS_AT_END="$(ps_snapshot_json_for_pgid "$PGID")"
    SURVIVOR_COUNT="$(printf '%s' "$SURVIVORS_AT_END" | jq 'length')"
fi

jq -n \
    --arg run_id "$RUN_ID" \
    --argjson rc "$RC" \
    --arg reason "$REASON" \
    --arg pgid "${PGID:-0}" \
    --argjson pids_at_start "$PIDS_AT_START" \
    --argjson survivors_at_end "$SURVIVORS_AT_END" \
    --argjson survivor_count "$SURVIVOR_COUNT" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{run_id:$run_id, rc:$rc, reason:$reason, pgid:($pgid|tonumber), pids_at_start:$pids_at_start,
      survivors_at_end:$survivors_at_end, survivor_count:$survivor_count, ts:$ts, writer:"lock_run_shim"}' \
    > "$DONE_FILE.tmp.$$"
mv "$DONE_FILE.tmp.$$" "$DONE_FILE"

rm -f "$RC_FILE" "$PGID_FILE"
exec 9>&-
exit "$RC"
