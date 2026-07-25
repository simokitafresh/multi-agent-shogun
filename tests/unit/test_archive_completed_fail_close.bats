#!/usr/bin/env bats
# contract test: FAIL verdict close path
# test_necessity: verdict=FAILのcmdは定義上CLEARへ到達しないため、家老の正式レビュー証跡が
#                 あっても報告が永久に滞留し忍者が解放されなかった。家老レビュー証跡ありの
#                 FAIL報告のみ退避を許し、証跡なし/PASS報告は従来どおり退避しない不変量を守る。
# origin: [[cmd_karo_impl_fail_close_path_20260725]] -> [[FAIL verdictを閉じる正規経路の不在]] -> [[忍者の拘束継続]]

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    FIX="$BATS_TEST_TMPDIR/proj"
    CMD="cmd_karo_failclose_fixture"
    mkdir -p "$FIX/queue/gates/$CMD" "$FIX/queue/tasks" "$FIX/queue/reports" \
             "$FIX/logs" "$FIX/archive/reports" "$FIX/context" "$FIX/config"
    : > "$FIX/queue/shogun_to_karo.yaml"
    REPORT="$FIX/queue/reports/saizo_report_${CMD}.yaml"
    write_report FAIL
}

write_report() {
    printf 'worker_id: saizo\nparent_cmd: %s\nstatus: completed\nverdict: %s\n' \
        "$CMD" "$1" > "$REPORT"
}

record_karo_review() {
    mkdir -p "$FIX/queue/gates/$CMD/review_approvals/reports/abc123"
    printf 'role: karo\nresult: RC\n' \
        > "$FIX/queue/gates/$CMD/review_approvals/reports/abc123/karo.yaml"
}

run_archive() {
    ARCHIVE_COMPLETED_PROJECT_DIR="$FIX" \
        timeout 200 bash "$REPO_ROOT/scripts/archive_completed.sh" 3 "$CMD" 2>&1
}

# 是正前の実害の再現: 家老レビュー証跡がなければ従来どおり退避しない(安全性維持)
@test "FAIL verdict report without a Karo review record stays kept" {
    run run_archive
    echo "$output"
    [[ "$output" == *"SKIP: review_gate.done not found"* ]]
    [ -f "$REPORT" ]
}

# 是正後: 正規経路で閉じられ、報告が退避されて忍者が解放される
@test "FAIL verdict report with a Karo review record is archived without fabricating CLEAR" {
    record_karo_review

    run run_archive
    echo "$output"
    [[ "$output" == *"FAIL_CLOSE"* ]]
    # 退避済み: 実体はqueue/archive/reports配下へ移り、queue/reportsには参照用symlinkだけが残る。
    # これが忍者を解放する状態(pending reportが消え再配備が通る)である。
    archived=("$FIX/queue/archive/reports/saizo_report_${CMD}_"*.yaml)
    [ -f "${archived[0]}" ]
    [ -L "$REPORT" ]
    [ ! -e "$FIX/queue/reports/saizo_report_${CMD}.yaml.pending" ]
    # AC2-1: CLEARを捏造していない(review_gate.done不在、gate_metricsにもCLEAR行なし)
    [ ! -f "$FIX/queue/gates/$CMD/review_gate.done" ]
    run grep -l "CLEAR" "$FIX/logs/gate_metrics.log"
    [ "$status" -ne 0 ]
    # AC2-2: 品質記録にはFAILのまま残る
    run grep -c '^verdict: FAIL' "${archived[0]}"
    [ "$output" -eq 1 ]
}

# 安全性: PASS verdictはCLEAR経路を通るべきで、本分岐で素通りさせない
@test "PASS verdict report without CLEAR is still blocked even with a Karo review record" {
    write_report PASS
    record_karo_review

    run run_archive
    echo "$output"
    [[ "$output" != *"FAIL_CLOSE"* ]]
    [ -f "$REPORT" ]
}
