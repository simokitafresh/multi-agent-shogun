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

# ── cmd_karo_impl_b28_failed_report_close_20260726 (B28) ──
# 上のFAIL_CLOSE分岐が要求する karo.yaml 証跡は review_approval.sh だけが作るが、
# verdict=FAIL の報告は status=failed へ落ちるため、その入口が status=completed 必須で
# 閉じていた(=証跡到達不能)。証跡生成側の入口も両方向で固定する。
_b28_root() {
    B28="$BATS_TEST_TMPDIR/b28"
    mkdir -p "$B28/queue/reports" "$B28/queue/gates" "$B28/queue/tasks" "$B28/queue/locks"
    ln -sfn "$REPO_ROOT/scripts" "$B28/scripts"
    B28_CMD="cmd_karo_b28_fixture"
    B28_REPORT="$B28/queue/reports/saizo_report_${B28_CMD}.yaml"
    printf 'worker_id: saizo\nparent_cmd: %s\ntask_id: %s_normal\nstatus: failed\nverdict: %s\nfiles_modified:\n  - path: ""\n' \
        "$B28_CMD" "$B28_CMD" "$1" > "$B28_REPORT"
}

_b28_review() {
    REVIEW_APPROVAL_ROOT="$B28" REVIEW_APPROVAL_NO_NOTIFY=1 REVIEW_APPROVAL_NO_TRIGGER=1 \
        bash "$REPO_ROOT/scripts/review_approval.sh" "$B28_CMD" karo ACCEPT \
        "queue/reports/saizo_report_${B28_CMD}.yaml" 2>&1
}

@test "B28: failed report with verdict FAIL can record the Karo evidence without a CLEAR marker" {
    _b28_root FAIL

    run _b28_review
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"fail-close review recorded"* ]]
    # FAIL_CLOSE分岐が要求する証跡が実在する = 経路が到達可能になった
    run bash -c 'ls "$1"/queue/gates/"$2"/review_approvals/reports/*/karo.yaml' _ "$B28" "$B28_CMD"
    [ "$status" -eq 0 ]
    # CLEARは捏造しない
    [ ! -f "$B28/queue/gates/$B28_CMD/review_gate.done" ]
}

@test "B28: failed report whose verdict is not FAIL stays blocked at the submission guard" {
    _b28_root PASS

    run _b28_review
    echo "$output"
    [ "$status" -ne 0 ]
    [[ "$output" == *"formal review requires status=completed"* ]]
    run bash -c 'ls "$1"/queue/gates/"$2"/review_approvals/reports/*/karo.yaml' _ "$B28" "$B28_CMD"
    [ "$status" -ne 0 ]
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
