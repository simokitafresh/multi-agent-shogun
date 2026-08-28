#!/usr/bin/env bats
# test_necessity: 不変量=「registered_at=行の初出 commit 時刻、started_at=初めて [~]/[x] になった commit 時刻、
#   resolved_at=初めて [x] になった commit 時刻。reopen([x]→[~])しても first 値は保持され reopened=yes」。
#   これが崩れると殿のタイムスタンプ(登録/着手/解決)が歴史修正され回転計測が信用できなくなる(歴史修正禁止原則)。

setup() {
    ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TMP="$(mktemp -d)"; R="$TMP/repo"; mkdir -p "$R/queue"
    git -C "$TMP" init -q repo
    c() { git -C "$R" add -A; GIT_COMMITTER_DATE="$1" git -C "$R" -c user.email=t@t -c user.name=t commit -q -m "$2" --date="$1"; }
    printf -- '- [ ] T01(a) 登録のみ ★w\n' >"$R/queue/shogun_todo_map.md"; c 2026-08-27T10:00:00+09:00 reg
    printf -- '- [~] T01(a) 着手 ★w\n- [ ] T02(b) 新規 ★w\n' >"$R/queue/shogun_todo_map.md"; c 2026-08-27T11:00:00+09:00 start
    printf -- '- [x] T01(a) 解決 ★w\n- [x] T02(b) 直行 ★w\n' >"$R/queue/shogun_todo_map.md"; c 2026-08-27T13:30:00+09:00 resolve
    printf -- '- [~] T01(a) 再開 ★w\n- [x] T02(b) 直行 ★w\n' >"$R/queue/shogun_todo_map.md"; c 2026-08-27T14:00:00+09:00 reopen
}
teardown() { rm -rf "$TMP"; }

@test "first-seen timestamps are immutable and reopen is flagged" {
    run python3 "$ROOT/scripts/todo_map_timestamps.py" --repo "$R" --now 2026-08-27T15:00:00+09:00
    [ "$status" -eq 0 ]
    t01="$(grep '^T01' "$R/queue/shogun_todo_map_timestamps.tsv")"
    [[ "$t01" == $'T01\t~\t2026-08-27T10:00:00+09:00\t2026-08-27T11:00:00+09:00\t2026-08-27T13:30:00+09:00\t60\t150\tyes' ]]
    t02="$(grep '^T02' "$R/queue/shogun_todo_map_timestamps.tsv")"
    [[ "$t02" == $'T02\tx\t2026-08-27T11:00:00+09:00\t2026-08-27T13:30:00+09:00\t2026-08-27T13:30:00+09:00\t150\t0\tno' ]]
}

@test "uncommitted new row is provisionally registered at --now" {
    printf -- '- [~] T01(a) 再開 ★w\n- [x] T02(b) 直行 ★w\n- [ ] T03(c) 未commit ★w\n' >"$R/queue/shogun_todo_map.md"
    run python3 "$ROOT/scripts/todo_map_timestamps.py" --repo "$R" --now 2026-08-27T15:00:00+09:00
    [ "$status" -eq 0 ]
    grep -q $'^T03\t \t2026-08-27T15:00:00+09:00\t\t\t\t\tno$' "$R/queue/shogun_todo_map_timestamps.tsv"
}
