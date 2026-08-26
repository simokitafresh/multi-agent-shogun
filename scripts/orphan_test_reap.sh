#!/usr/bin/env bash
# orphan_test_reap.sh — 親を失った(=/init直下)テスト実行系プロセス樹を列挙/停止する。
# 2026-08-27 02:35 発端: test_heavy_job_admission.bats のfixture run_tests.sh unit が孤児化し
# 全unit suiteを再帰起動して自己増殖(root 27・bats-exec-suite 32本・load 66)。
# pgid単位のkillでは heavy_job_admission.sh が新pgidを切るため子孫が残り再増殖した。
# ∴ 孤児root→子孫を再帰展開し、反復して静止まで回収する。
# 使い方: bash scripts/orphan_test_reap.sh          # dry-run(列挙のみ)
#         bash scripts/orphan_test_reap.sh --kill   # 停止(将軍はD006により実行しない。殿が実行)
#         EXTRA_PATTERN='hanzo_e38d94bd2c010891' bash scripts/orphan_test_reap.sh --kill  # 古worktree由来も対象
set -u
MODE=list
[ "${1:-}" = "--kill" ] && MODE=kill
PATTERN='bats-exec|bats-core/bats |run_tests.sh|run_with_receipt.sh|heavy_job_admission'
EXTRA_PATTERN="${EXTRA_PATTERN:-}"
INIT_PIDS="$(ps -eo pid=,comm= | awk '$2=="init" || $2=="/init" {print $1}' | tr '\n' ' ')"
[ -z "$INIT_PIDS" ] && INIT_PIDS="1"
# tmux pane配下(正規実行)は除外: 祖先にtmuxがあるものは触らない
is_orphan_root() {
    local pp; pp="$(ps -o ppid= -p "$1" 2>/dev/null | tr -d ' ')"
    for i in $INIT_PIDS; do [ "$pp" = "$i" ] && return 0; done
    return 1
}
descendants() {  # 再帰展開
    local p="$1"; echo "$p"
    for c in $(pgrep -P "$p" 2>/dev/null); do descendants "$c"; done
}
collect() {
    ps -eo pid=,args= | awk -v pat="$PATTERN" -v ext="$EXTRA_PATTERN" '$0 ~ pat || (ext != "" && $0 ~ ext) {print $1}' | while read -r p; do
        if is_orphan_root "$p"; then descendants "$p"; fi
        if [ -n "$EXTRA_PATTERN" ] && ps -o args= -p "$p" 2>/dev/null | grep -qE "$EXTRA_PATTERN"; then descendants "$p"; fi
    done | sort -un
}
if [ "$MODE" = list ]; then
    pids="$(collect)"; n=$(printf '%s\n' "$pids" | grep -c .)
    echo "orphan_test_procs=$n"
    [ -n "$pids" ] && ps -o pid,ppid,pgid,etimes,args -p "$(echo "$pids" | tr '\n' ',' | sed 's/,$//')" 2>/dev/null | cut -c1-160
    exit 0
fi
for round in 1 2 3 4 5 6; do
    pids="$(collect)"; n=$(printf '%s\n' "$pids" | grep -c .)
    echo "round=$round targets=$n"
    [ "$n" -eq 0 ] && break
    # shellcheck disable=SC2086
    kill -TERM $pids 2>/dev/null; sleep 2
    # shellcheck disable=SC2086
    kill -KILL $pids 2>/dev/null; sleep 1
done
echo "remaining=$(collect | grep -c .)"
