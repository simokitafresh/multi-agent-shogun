#!/usr/bin/env bats
# 先送りストリーク検出のセッション統合(KARO_STREAK_SESSION_GAP_SEC)
# run=タイムスタンプ変化のみの代理計測は「2分半で3セッション連続」の誤CRITICALを生んだ(2026-07-02)。
# gate本体からawkプログラムを抽出して実コードを検証する。

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    GATE="$PROJECT_ROOT/scripts/gates/gate_karo_startup.sh"
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/karo_streak.XXXXXX")"
    AWK_PROG="$TEST_TMPDIR/streak.awk"
    sed -n '/_streak_result=\$(awk/,/"\$_current_alerts_file" "\$STARTUP_ALERT_HISTORY"/p' "$GATE" \
        | sed '1d' | sed '$s/.*/}/' > "$AWK_PROG"
    [ -s "$AWK_PROG" ]
    printf 'KEY_A\n' > "$TEST_TMPDIR/cur.txt"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

run_streak() {
    awk -F'\t' -v threshold=3 -v min_gap=1800 -f "$AWK_PROG" "$TEST_TMPDIR/cur.txt" "$1"
}

run_streak_threshold_one() {
    awk -F'\t' -v threshold=1 -v min_gap=1800 -f "$AWK_PROG" "$TEST_TMPDIR/cur.txt" "$1"
}

@test "threshold 1 emits current key without previous sessions" {
    : > "$TEST_TMPDIR/hist.tsv"
    run run_streak_threshold_one "$TEST_TMPDIR/hist.tsv"
    [ "$status" -eq 0 ]
    [ "$output" = "KEY_A" ]
}

@test "gap秒未満の連続runは同一セッションに統合され誤CRITICALを出さない" {
    printf '2026-07-02T21:24:05+0900\tKEY_A\n2026-07-02T21:25:24+0900\tKEY_A\n' > "$TEST_TMPDIR/hist.tsv"
    run run_streak "$TEST_TMPDIR/hist.tsv"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "gap秒以上離れた真の反復セッションはstreakを検出する" {
    printf '2026-07-02T18:00:00+0900\tKEY_A\n2026-07-02T19:00:00+0900\tKEY_A\n' > "$TEST_TMPDIR/hist.tsv"
    run run_streak "$TEST_TMPDIR/hist.tsv"
    [ "$status" -eq 0 ]
    [ "$output" = "KEY_A" ]
}

@test "間にクリーンセッション(__OK__)が挟まればstreakは切れる" {
    printf '2026-07-02T17:00:00+0900\tKEY_A\n2026-07-02T18:00:00+0900\t__OK__\n2026-07-02T19:00:00+0900\tKEY_A\n' > "$TEST_TMPDIR/hist.tsv"
    run run_streak "$TEST_TMPDIR/hist.tsv"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
