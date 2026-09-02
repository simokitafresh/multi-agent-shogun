#!/usr/bin/env bats
# test_publisher_queue.bats — 単一 publisher 化 U1
# (scripts/publisher_queue.sh / scripts/lib/lock_run_shim.sh / scripts/lib/publisher_event.sh)
#
# test_necessity: origin公開経路をflock 1本で直列化する土台(FIFO queue・lock-runの有界化・
# events.jsonlの単一writer)が、並行投入順序・排他直列・TERM無視の有界kill・rc写像・
# D14整合を守ることを二値で固定する。設計書 docs/research/single_publisher_asis_tobe_5w1h_20260902.md
# §9.1 U1 / §6 D14 D15。
#
# STATE_DIRはH2(§13)によりtracked repo root配下・/tmp配下が起動拒否(rc=2)対象のため、
# fixtureは$HOME配下(repo外・/tmp外)にmktemp -d --tmpdir=$HOMEで作る。

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    FIXTURE_ROOT="$(mktemp -d --tmpdir="$HOME" publisher_queue_bats_root.XXXXXX)"
    mkdir -p "$FIXTURE_ROOT/scripts/lib"
    cp "$PROJECT_ROOT/scripts/publisher_queue.sh" "$FIXTURE_ROOT/scripts/publisher_queue.sh"
    cp "$PROJECT_ROOT/scripts/lib/lock_run_shim.sh" "$FIXTURE_ROOT/scripts/lib/lock_run_shim.sh"
    cp "$PROJECT_ROOT/scripts/lib/publisher_event.sh" "$FIXTURE_ROOT/scripts/lib/publisher_event.sh"
    cat > "$FIXTURE_ROOT/scripts/inbox_write.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${INBOX_WRITE_STUB_LOG:-/dev/null}"
exit 0
STUB
    # U5(cmd_4453): enqueue が呼ぶ admit gate はここでは対象外(このfileのtest_necessity=
    # FIFO/並行/lock-run機構)。admission判定自体はtest_publisher_admit.batsが固定するため、
    # ここでは常時admitのstubで機構テストを汚染しない。
    cat > "$FIXTURE_ROOT/scripts/publisher_admit.sh" <<'STUB'
#!/bin/bash
exit 0
STUB
    chmod +x "$FIXTURE_ROOT/scripts/publisher_queue.sh" \
        "$FIXTURE_ROOT/scripts/lib/lock_run_shim.sh" \
        "$FIXTURE_ROOT/scripts/lib/publisher_event.sh" \
        "$FIXTURE_ROOT/scripts/inbox_write.sh" \
        "$FIXTURE_ROOT/scripts/publisher_admit.sh"

    git -C "$FIXTURE_ROOT" init -q
    git -C "$FIXTURE_ROOT" -c user.email=t@t -c user.name=t add -A
    git -C "$FIXTURE_ROOT" -c user.email=t@t -c user.name=t commit -q -m init

    STATE_DIR="$(mktemp -d --tmpdir="$HOME" publisher_queue_bats_state.XXXXXX)"
    export SHOGUN_STATE_DIR="$STATE_DIR"
    export INBOX_WRITE_STUB_LOG="$FIXTURE_ROOT/inbox_stub.log"
    PQ="$FIXTURE_ROOT/scripts/publisher_queue.sh"
    SHIM="$FIXTURE_ROOT/scripts/lib/lock_run_shim.sh"
    EVLIB="$FIXTURE_ROOT/scripts/lib/publisher_event.sh"
}

teardown() {
    [ -n "$FIXTURE_ROOT" ] && find "$FIXTURE_ROOT" -depth -delete 2>/dev/null
    [ -n "$STATE_DIR" ] && find "$STATE_DIR" -depth -delete 2>/dev/null
    [ -n "$STATE_DIR" ] && rm -f "${STATE_DIR}_src_restart_req.yaml" 2>/dev/null
}

# test_necessity: STATE_DIRがtracked root配下・/tmp配下だと起動拒否(rc=2)しないと、
# H2実績(/tmp再起動消失)とH2再発防止(root汚染)が構造的に崩れる。
@test "STATE_DIR under /tmp or tracked repo root refuses to start with rc=2" {
    run env SHOGUN_STATE_DIR=/tmp/publisher_queue_reject_test bash "$PQ" enqueue /dev/null
    [ "$status" -eq 2 ]
    [[ "$output" == *"/tmp"* ]]

    run env SHOGUN_STATE_DIR="$FIXTURE_ROOT/state_under_root" bash "$PQ" enqueue /dev/null
    [ "$status" -eq 2 ]
    [[ "$output" == *"repo root"* ]]
}

# test_necessity: enqueueが払い出すseqはflock下でグローバル単調増加であり、真の並行呼出しでも
# 重複・欠落が0であることを構造で保証する(FIFO順序の土台)。
@test "enqueue assigns strictly increasing seq under true concurrency with 0 dup and 0 loss" {
    local i
    for i in 1 2 3 4 5 6; do
        printf 'task_id: task_%s\n' "$i" > "$FIXTURE_ROOT/req_$i.yaml"
    done
    for i in 1 2 3 4 5 6; do
        bash "$PQ" enqueue "$FIXTURE_ROOT/req_$i.yaml" >> "$FIXTURE_ROOT/enqueue_paths.log" &
    done
    wait

    run bash -c "wc -l < '$FIXTURE_ROOT/enqueue_paths.log'"
    [ "$status" -eq 0 ]
    [ "$output" -eq 6 ]

    # ファイル名の <seq> 部分(第2要素)が6件すべて相異なることを確認する
    run bash -c "basename -a \$(cat '$FIXTURE_ROOT/enqueue_paths.log') | cut -d_ -f2 | sort -u | wc -l"
    [ "$status" -eq 0 ]
    [ "$output" -eq 6 ]

    run bash -c "ls '$STATE_DIR/publish_queue'/*.request | wc -l"
    [ "$status" -eq 0 ]
    [ "$output" -eq 6 ]
}

# test_necessity: dequeueはFIFO先頭を投入順どおりに返し、peekは削除せず、空queueはrc=3を返す
# ことを二値で固定する(publisher/wrapperがrequestを取り違えると誤commitに直結する)。
@test "dequeue returns FIFO submission order, peek does not remove, empty queue rc=3" {
    local i
    for i in 1 2 3 4 5 6; do
        printf 'task_id: task_%s\n' "$i" > "$FIXTURE_ROOT/req_$i.yaml"
        # submission順を親の同期呼出しで明示する。真の並行enqueueの
        # seq重複・欠落は前testとAC1の8並行×20反復で別途検証する。
        bash "$PQ" enqueue "$FIXTURE_ROOT/req_$i.yaml" >/dev/null
    done

    run bash "$PQ" peek
    [ "$status" -eq 0 ]
    peeked="$output"
    run bash "$PQ" peek
    [ "$status" -eq 0 ]
    [ "$output" = "$peeked" ]
    [[ "$peeked" == *"task_1.request" ]]

    local n order=""
    for n in 1 2 3 4 5 6; do
        run bash "$PQ" dequeue
        [ "$status" -eq 0 ]
        order="$order $(basename "$output")"
    done
    [[ "$order" == *"task_1.request"*"task_2.request"*"task_3.request"*"task_4.request"*"task_5.request"*"task_6.request" ]]

    run bash "$PQ" dequeue
    [ "$status" -eq 3 ]
    [ -z "$output" ]
}

# test_necessity: requestの永続性は再起動(dirをmvして戻す)を跨いで保たれ、かつqueue操作は
# STATE_DIRの外(tracked root)に一切副作用を残さない(C3: root porcelain差分0)ことを固定する。
@test "request survives restart-equivalent relocation and leaves tracked root porcelain clean" {
    # request source は STATE_DIR 側(git管理外)に置く。FIXTURE_ROOT(tracked root相当)に
    # 置くと"root porcelain差分0"の検証対象そのものを汚してしまうため。
    printf 'task_id: restart_probe\n' > "${STATE_DIR}_src_restart_req.yaml"
    run bash "$PQ" enqueue "${STATE_DIR}_src_restart_req.yaml"
    [ "$status" -eq 0 ]

    local moved="${STATE_DIR}_relocated"
    mv "$STATE_DIR" "$moved"
    mv "$moved" "$STATE_DIR"

    run bash "$PQ" dequeue
    [ "$status" -eq 0 ]
    [ -f "$output" ]
    run grep -c 'restart_probe' "$output"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]

    run git -C "$FIXTURE_ROOT" status --porcelain
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# test_necessity: lock-runは6並行呼出しをflock 1本で同時実行数1へ直列化する(直列化点=1、
# D3の核心)。開始・終了のタイムスタンプ列に重なりが1件もないことで検証する。
@test "lock-run serializes 6 concurrent invocations to exactly 1 concurrent execution" {
    local logf="$FIXTURE_ROOT/serial.log"
    : > "$logf"
    local i
    for i in 1 2 3 4 5 6; do
        ( bash "$PQ" lock-run --bound 5 -- bash -c "echo start \$(date +%s%N) >> '$logf'; sleep 0.2; echo end \$(date +%s%N) >> '$logf'" ) &
    done
    wait

    run bash -c "grep -c '^start' '$logf'"
    [ "$output" -eq 6 ]
    run bash -c "grep -c '^end' '$logf'"
    [ "$output" -eq 6 ]

    # 各行の2列目(ns epoch)を読み、start[i] <= end[i] <= start[i+1] の非重複連鎖であることを検証する
    run python3 - "$logf" <<'PY'
import sys
lines = [l.split() for l in open(sys.argv[1]) if l.strip()]
events = sorted(((int(ts), kind) for kind, ts in lines), key=lambda x: x[0])
depth = 0
for _, kind in events:
    if kind == "start":
        depth += 1
    else:
        depth -= 1
    if depth > 1:
        print("OVERLAP_DETECTED")
        sys.exit(1)
print("OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == "OK" ]]
}

# test_necessity: --boundを超えてTERMを無視する親+検知されにくい短命孫(disownされた
# grandchild)を、GNU timeoutのgroup信号(shimは信号送出コマンドを一切書かない)だけで
# survivor 0まで確実に終わらせることを固定する(H9: 沈黙した再試行を防ぐ安全底線)。
@test "lock-run kills TERM-ignoring parent and detached grandchild via timeout group signal: survivor 0, rc=210, lock released, 0 literal signal-send commands" {
    run grep -cE '\b(kill|pkill|killall)\b' "$SHIM" "$FIXTURE_ROOT/scripts/publisher_queue.sh"
    # grep -c は複数file指定で "file:count" 行を返す。全て0であることを確認する
    [[ "$output" != *":1"* ]] && [[ "$output" != *":2"* ]]

    cat > "$FIXTURE_ROOT/term_ignore_fixture.sh" <<'FIX'
#!/bin/bash
trap '' TERM
sh -c 'sleep 30 &' &
disown
sleep 20
FIX
    chmod +x "$FIXTURE_ROOT/term_ignore_fixture.sh"

    run bash "$PQ" lock-run --bound 3 -- "$FIXTURE_ROOT/term_ignore_fixture.sh"
    [ "$status" -eq 210 ]

    run bash -c "find '$STATE_DIR/publish_queue/run' -name '*.done' -exec cat {} \;"
    [ "$status" -eq 0 ]
    run bash -c "find '$STATE_DIR/publish_queue/run' -name '*.done' -exec jq -r '.rc,.survivor_count,.writer' {} \;"
    [ "$status" -eq 0 ]
    lines=($output)
    [ "${lines[0]}" = "210" ]
    [ "${lines[1]}" = "0" ]
    [ "${lines[2]}" = "lock_run_shim" ]

    # 独立にPIDベースでsleep 30が本当に居残っていないことを確認する(受信証拠の自己申告に依存しない)
    run bash -c "ps -eo pid,cmd | awk '\$2==\"sleep\" && \$3==\"30\"' | wc -l"
    [ "$status" -eq 0 ]
    [ "$output" -eq 0 ]

    # lock解放の確認: 直後に別のlock-runが即座に取得できる(flockが握られたままではない)
    run timeout 5 bash "$PQ" lock-run --bound 2 -- true
    [ "$status" -eq 0 ]
}

# test_necessity: bound到達によるtimeout強制終了(rc=210)と、commandが自発的にexit 124した
# ケース(rc=124のまま)を混同しないことを固定する(spec: 'childが124を返しても固有失敗として区別')。
@test "child self-exiting with 124 maps to rc=124, not confused with bound-timeout rc=210" {
    run bash "$PQ" lock-run --bound 10 -- bash -c 'exit 124'
    [ "$status" -eq 124 ]

    run bash -c "find '$STATE_DIR/publish_queue/run' -name '*.done' -exec jq -r '.reason' {} \;"
    [ "$status" -eq 0 ]
    [[ "$output" == "child_reported_rc" ]]
}

# test_necessity: 直接原因(rc-file書込み前にcommandが予期せず終了)はrc=211へ写像され、
# events.jsonlにkind=rc211が1行、家老inboxに1通が必ず記録される(H9: 沈黙0)。
@test "child abnormal termination before rc-file write maps to rc=211 with events.jsonl kind=rc211 and karo inbox notified" {
    : > "$INBOX_WRITE_STUB_LOG"
    run bash "$PQ" lock-run --bound 10 -- bash -c 'kill -ABRT "$PPID"; sleep 3'
    [ "$status" -eq 211 ]

    run bash -c "jq -r 'select(.kind==\"rc211\") | .kind' '$STATE_DIR/publish_queue/events.jsonl'"
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | grep -c '^rc211$')" -eq 1 ]

    run grep -c 'rc=211' "$INBOX_WRITE_STUB_LOG"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
    run grep -c '^karo ' "$INBOX_WRITE_STUB_LOG"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

# test_necessity: D14(events.jsonlの唯一writer)は6並行writer×100行でもseq重複0・欠番0を
# flock 1本で構造的に保証する。直接echo追記の禁止は本scriptが唯一の入口であることの帰結。
@test "publisher_event.sh append: 6 concurrent writers x 100 lines yields 0 duplicate and 0 missing seq" {
    local w
    for w in 1 2 3 4 5 6; do
        ( local n; for n in $(seq 1 100); do
              bash "$EVLIB" append rc211 "req_${w}_${n}" 211 "loadtest"
          done ) &
    done
    wait

    local ev="$STATE_DIR/publish_queue/events.jsonl"
    run bash -c "wc -l < '$ev'"
    [ "$status" -eq 0 ]
    [ "$output" -eq 600 ]

    run bash -c "jq -r '.seq' '$ev' | sort -n | uniq -d | wc -l"
    [ "$status" -eq 0 ]
    [ "$output" -eq 0 ]

    run bash -c "diff <(seq 1 600) <(jq -r '.seq' '$ev' | sort -n)"
    [ "$status" -eq 0 ]
}

# test_necessity: next_seq()はflock保持下でSEQ_FILEへ書いた直後、request公開(mv)前に
# processが異常終了しうる(§9.1 U1敵対fixture候補2)。そのseqが後続enqueueへ重複払出し
# されないこと、公開されなかった残骸(*.request.tmp.*)がdequeueへ混入しないこと、
# FIFO順序が生き残ったrequest間で崩れないことを固定する。crashは実プロセスkillの
# タイミング依存を避け、next_seq()と同じ操作(SEQ_FILEへseqを書き、対応するrequestを
# 公開しない)をflock外から直接再現して決定的に検証する。
@test "enqueue crash between seq allocation and publish leaves no seq duplicate and no orphan admitted" {
    printf 'task_id: req1\n' > "$FIXTURE_ROOT/req1.yaml"
    run bash "$PQ" enqueue "$FIXTURE_ROOT/req1.yaml"
    [ "$status" -eq 0 ]

    run cat "$STATE_DIR/publish_queue/.seq"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]

    # next_seq()がseq=2を払い出した直後にprocessがcp/mvへ到達せず異常終了した状態を再現する:
    # SEQ_FILEはseq=2まで進むが、対応する*.requestは存在せず、cpが作った0byte残骸だけが残る。
    printf '2' > "$STATE_DIR/publish_queue/.seq"
    touch "$STATE_DIR/publish_queue/9999999999_000000000002_crashed.request.tmp.99999"

    printf 'task_id: req3\n' > "$FIXTURE_ROOT/req3.yaml"
    run bash "$PQ" enqueue "$FIXTURE_ROOT/req3.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"_000000000003_"* ]]

    # 欠番(seq=2)は生じるが重複はしない: 生きているrequestは1と3のみ
    run bash -c "find '$STATE_DIR/publish_queue' -maxdepth 1 -name '*.request' | wc -l"
    [ "$status" -eq 0 ]
    [ "$output" -eq 2 ]

    run bash "$PQ" dequeue
    [ "$status" -eq 0 ]
    [[ "$output" == *"req1.request" ]]

    run bash "$PQ" dequeue
    [ "$status" -eq 0 ]
    [[ "$output" == *"req3.request" ]]

    # 孤児tmpはdequeueの対象に混入しない(空queueへ到達しrc=3)
    run bash "$PQ" dequeue
    [ "$status" -eq 3 ]
    [ -z "$output" ]

    # 孤児tmpは*.request命名規約に一致しないため放置されたまま残る(クリーンアップは本unit対象外)
    run bash -c "find '$STATE_DIR/publish_queue' -maxdepth 1 -name '*.tmp.*' | wc -l"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}
