#!/usr/bin/env bats
# test_necessity: A report generation already validated by the active leader must bypass the same report lock without a false timeout.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TEST_DIR="$(mktemp -d "$REPO_ROOT/.cache/gate-singleflight.XXXXXX")"
    REPORT="$TEST_DIR/report.yaml"
    printf 'worker_id: test\n' >"$REPORT"
    FP="$(sha256sum "$REPORT" | awk '{print $1}')"
    printf '%s\n' "$FP" >"${REPORT}.validated_fingerprints"
}

teardown() {
    find "$TEST_DIR" -type f -delete
    rmdir "$TEST_DIR"
}

@test "validated fingerprint reuse happens before the report singleflight lock" {
    flock "${REPORT}.gate.lock" sleep 3 &
    lock_pid=$!
    sleep 0.1

    run env \
        GATE_SINGLEFLIGHT_TIMEOUT=1 \
        GATE_VALIDATED_FINGERPRINT="$FP" \
        bash "$REPO_ROOT/scripts/gates/gate_report_format.sh" "$REPORT"

    wait "$lock_pid"
    [ "$status" -eq 0 ]
    [ "$output" = "PASS (fingerprint reuse)" ]
}

# cmd_karo_hotfix_singleflight_fail_misattribution_20260725 (provenance: 118dc5ff8)
# test_necessity: a single-flight lock timeout is infrastructure contention, not a report
# quality problem, and must be distinguishable by callers via exit code alone (not string
# prefix matching, which collides with the ordinary quality-FAIL "FAIL:" prefix).
@test "single-flight lock timeout reports a dedicated exit code and marker, not FAIL:" {
    flock "${REPORT}.gate.lock" sleep 3 &
    lock_pid=$!
    sleep 0.1

    run env GATE_SINGLEFLIGHT_TIMEOUT=1 bash "$REPO_ROOT/scripts/gates/gate_report_format.sh" "$REPORT"

    wait "$lock_pid"
    [ "$status" -eq 2 ]
    [[ "$output" == "INFRA_TIMEOUT: report gate single-flight timeout: $REPORT" ]]
    [[ "$output" != FAIL:* ]]
}

@test "one byte report mutation cannot reuse a stale validated fingerprint" {
    printf 'x' >>"$REPORT"

    run env \
        GATE_VALIDATED_FINGERPRINT="$FP" \
        GATE_FAST_EXIT=1 \
        GATE_NO_LOG=1 \
        bash "$REPO_ROOT/scripts/gates/gate_report_format.sh" "$REPORT"

    [ "$status" -ne 0 ]
    [[ "$output" != *"fingerprint reuse"* ]]
}

# cmd_karo_hotfix_control_plane_contracts_ga321_20260723
# test_necessity: SKILL_LOG_SYNCの同期loggerが起動するtransitive background子へreport lock FDを継承させず、親gate直後の後続gateが取得できる不変量。
@test "sync skill logger closes report lock FD before transitive background spawn" {
    run python3 - "$REPO_ROOT/scripts/gates/gate_report_format.sh" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
start = text.index('if [ "${SKILL_LOG_SYNC:-0}" = "1" ]; then')
end = text.index("else", start)
branch = text[start:end]
assert "exec 199>&-" in branch
assert branch.index("exec 199>&-") < branch.index('bash "$_SKILL_LOG"')
PY
    [ "$status" -eq 0 ]

    lock="$TEST_DIR/transitive.gate.lock"
    (
        exec 199>"$lock"
        flock 199
        (
            exec 199>&-
            sleep 2 &
        )
    )
    run flock -w 1 "$lock" true
    [ "$status" -eq 0 ]
}

# cmd_karo_impl_singleflight_hold_instrumentation_20260725
# test_necessity: ロック保持区間(flock取得→解放)のwall_msが既存台帳へ
# check_id=singleflight_hold/source=gate_report_format として1件記録される不変量。
# これが消えるとGATE_SINGLEFLIGHT_TIMEOUTの妥当性が再び実測ではなく外挿になる。
@test "lock-holding run records one singleflight_hold row into the shared overhead ledger" {
    ledger="$TEST_DIR/overhead.jsonl"

    run env \
        DEFENSE_OVERHEAD_LEDGER="$ledger" \
        GATE_FIRE_LOG_FILE="$TEST_DIR/fire.yaml" \
        GATE_FAST_EXIT=1 \
        bash "$REPO_ROOT/scripts/gates/gate_report_format.sh" "$REPORT"

    # 非同期writerの着地を待つ(最大10秒)。判定はgateのPASS/FAILに依存しない。
    for _ in $(seq 1 100); do
        grep -q '"check_id":"singleflight_hold"' "$ledger" 2>/dev/null && break
        sleep 0.1
    done

    run grep -c '"check_id":"singleflight_hold"' "$ledger"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]

    run grep '"check_id":"singleflight_hold"' "$ledger"
    [[ "$output" == *'"source":"gate_report_format"'* ]]
    [[ "$output" =~ \"wall_ms\":[0-9]+ ]]
}

# cmd_karo_impl_singleflight_hold_instrumentation_20260725
# test_necessity: ロックを取得しなかった経路(fingerprint reuse)ではhold行を出さない不変量。
# 保持していない区間を保持時間として記録すると上限判定の母数が汚染される。
@test "fingerprint reuse path records no singleflight_hold row" {
    ledger="$TEST_DIR/overhead_reuse.jsonl"

    run env \
        DEFENSE_OVERHEAD_LEDGER="$ledger" \
        GATE_VALIDATED_FINGERPRINT="$FP" \
        bash "$REPO_ROOT/scripts/gates/gate_report_format.sh" "$REPORT"
    [ "$status" -eq 0 ]
    [ "$output" = "PASS (fingerprint reuse)" ]

    sleep 0.5
    # 台帳が生成されない場合も「hold行なし」として扱う(writerは行が無ければ触らない)
    count=0
    if [ -f "$ledger" ]; then
        count="$(grep -c '"check_id":"singleflight_hold"' "$ledger" || true)"
    fi
    [ "$count" -eq 0 ]
}

# cmd_karo_round8_spare_b_singleflight_io_20260804 AC3
# test_necessity: 品質FAILでもsingle-flight lockを解放し、FAIL verdictのhold計測を
# 1件だけ記録する不変量。異常経路で次のreport検証が詰まる回帰を防ぐ。
@test "quality failure releases the lock and records one FAIL hold row" {
    ledger="$TEST_DIR/overhead_failure.jsonl"

    run env \
        DEFENSE_OVERHEAD_LEDGER="$ledger" \
        GATE_FAST_EXIT=1 \
        bash "$REPO_ROOT/scripts/gates/gate_report_format.sh" "$REPORT"

    [ "$status" -eq 1 ]
    run flock -n "${REPORT}.gate.lock" true
    [ "$status" -eq 0 ]

    for _ in $(seq 1 100); do
        grep -q '"check_id":"singleflight_hold"' "$ledger" 2>/dev/null && break
        sleep 0.1
    done
    run grep -c '"check_id":"singleflight_hold"' "$ledger"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
    run grep '"check_id":"singleflight_hold"' "$ledger"
    [[ "$output" == *'"verdict":"FAIL"'* ]]
}

# cmd_karo_impl_singleflight_hold_instrumentation_20260725 (軍師レビュー指摘の是正)
# test_necessity: 計装のためにforkする非同期writerがgate.lock(fd 199)を継承してはならない。
# 継承するとledger.lock待ちと低速FS書込みの間ロックが保持され、計装自体が
# single-flight timeoutを増やす(本cmdの目的に反する)。gate復帰直後にflock -nで
# 即時取得できることを直接assertし、実装の内部構造に依存せず解放を検証する。
@test "async overhead writer does not inherit the report lock (flock -n succeeds right after the gate returns)" {
    ledger="$TEST_DIR/overhead_fd.jsonl"

    # ledger lockを先に保持し、writer子プロセスを確実にブロックさせる
    : >"${ledger}.lock"
    flock "${ledger}.lock" sleep 3 &
    ledger_holder=$!
    sleep 0.2

    run env \
        DEFENSE_OVERHEAD_LEDGER="$ledger" \
        GATE_FIRE_LOG_FILE="$TEST_DIR/fire_fd.yaml" \
        GATE_FAST_EXIT=1 \
        bash "$REPO_ROOT/scripts/gates/gate_report_format.sh" "$REPORT"

    # gate復帰直後: writerはまだledger lock待ちだが、gate.lockは解放済みでなければならない
    run flock -n "${REPORT}.gate.lock" true
    lock_status="$status"

    wait "$ledger_holder"
    [ "$lock_status" -eq 0 ]
}

# cmd_karo_round8_spare_b_singleflight_io_20260804 AC1/AC3
# test_necessity: 後段の同期skill loggerより前にsingle-flight lockを解放する
# 実装順序を固定し、遅いloggingがlock保持区間へ戻る回帰を防ぐ契約。
@test "post-validation logging is structurally after single-flight release" {
    run python3 - "$REPO_ROOT/scripts/gates/gate_report_format.sh" <<'PY'
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
release = text.index("_gate_record_singleflight_hold 0")
logging = text.index("# --- Gate fire logging")
assert release < logging
assert text.index("_GATE_HOLD_FINALIZED=1") < release
assert "trap '_gate_record_singleflight_hold_on_exit' EXIT" in text
PY
    [ "$status" -eq 0 ]
}
