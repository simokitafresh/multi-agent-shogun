#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export ENGINE="$PROJECT_ROOT/scripts/gates/gate_gunshi_report_precheck_engine.py"
    [ -f "$ENGINE" ] || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/sg_pre9c_scope.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/tasks"
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

_write_report() {
    local purpose_gap="$1"
    cat > "$TEST_TMPDIR/report.yaml" <<YAML
ninja: hanzo
task_id: cmd_test
status: completed
purpose_validation:
  cmd_purpose: "context freshness修正"
  fit: false
  purpose_gap: "$purpose_gap"
binary_checks:
  ac1:
    - check: "通常gate OK"
      result: yes
YAML
}

@test "SG-PRE9c allows not_in_scope aligned scope外 boundary text" {
    _write_report "対象ファイルは通常gateでOK。scope外修正しない。"

    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
    [[ "$output" == *"BC_YES_CLARITY_TERMS=''"* ]]
}

@test "SG-PRE9c still detects scope外 delegation to karo" {
    _write_report "scope外で家老が実施するため未完了。"

    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
    [[ "$output" == *"scope外で家老"* ]]
}

@test "SG-PRE9c allows unmet wording when explicitly outside scope" {
    _write_report "full 5分目標は未達(スコープ外)。今回ACは補完済み。"

    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
    [[ "$output" == *"BC_YES_CLARITY_TERMS=''"* ]]
}

@test "SG-PRE9c still detects unmet wording when delegated later" {
    _write_report "full 5分目標は未達。後で家老が実施する。"

    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
    [[ "$output" == *"未達"* ]]
}

@test "SG-PRE9c allows investigation-state unresolved wording in recon context" {
    cat > "$TEST_TMPDIR/report.yaml" <<YAML
ninja: hayate
task_id: cmd_recon
status: completed
task_clarity:
  score: 90
  unclear_points: "偵察の調査状態: 本番パスワード未確認。原因切り分けとして401認証差異を分類した。"
  discretion_fills: "detector分類ロジックでは未解決/未確認を状態記述として扱う。"
binary_checks:
  ac1:
    - check: "原因分類済み"
      result: yes
YAML

    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
    [[ "$output" == *"BC_YES_CLARITY_TERMS=''"* ]]
}

@test "SG-PRE9c still detects unresolved wording when delegated later" {
    cat > "$TEST_TMPDIR/report.yaml" <<YAML
ninja: hayate
task_id: cmd_recon
status: completed
task_clarity:
  score: 70
  unclear_points: "AC1は未解決。後で家老が実施する。"
binary_checks:
  ac1:
    - check: "AC1完了"
      result: yes
YAML

    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
    [[ "$output" == *"未解決"* ]]
}

@test "SG-PRE9c allows TODO and FILL_THIS in identifiers and detector descriptions" {
    cat > "$TEST_TMPDIR/report.yaml" <<YAML
ninja: kotaro
task_id: cmd_detector_fix
status: completed
task_clarity:
  score: 100
  unclear_points: "機能名run_todo_fixme_residual_checkとFILL_THIS検出器の説明を検証した。引用 'TODO' もfixture対象。"
binary_checks:
  ac1:
    - check: "検出器fixture完了"
      result: yes
YAML

    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
    [[ "$output" == *"BC_YES_CLARITY_TERMS=''"* ]]
}

@test "SG-PRE9c still detects actionable TODO and FILL_THIS work" {
    cat > "$TEST_TMPDIR/report.yaml" <<YAML
ninja: kotaro
task_id: cmd_incomplete
status: completed
task_clarity:
  score: 70
  unclear_points: "TODO: 後で実施する。FILL_THISは未実施。"
binary_checks:
  ac1:
    - check: "AC1完了"
      result: yes
YAML

    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
    [[ "$output" == *"todo"* ]]
    [[ "$output" == *"fill_this"* ]]
}

@test "SG-PRE9c allows the originating report detector-design wording" {
    # 発端実report(cmd_karo_hotfix_sg_pre9c_todo_context_202607111318, kagemaru)は
    # queue/reports/配下のgitignore対象・cmd完了後archive済みで実行時に存在しない。
    # 運用reportへの実行時依存を断ち、当該reportで矛盾誤検出を起こしていた
    # task_clarity.discretion_fills(「未完了マーカー」)とpurpose_validation.cmd_purpose
    # (「TODO文脈偽陽性」「真の未完了検出」)の文言を自己完結fixtureとして再現する。
    cat > "$TEST_TMPDIR/report.yaml" <<'YAML'
worker_id: kagemaru
task_id: cmd_karo_hotfix_sg_pre9c_todo_context_202607111318_normal
status: completed
task_clarity:
  score: 100
  unclear_points: なし
  discretion_fills: 局所文脈窓を前後32文字とし、既存の委譲・未完了マーカーを優先した
purpose_validation:
  cmd_purpose: SG-PRE9cのTODO文脈偽陽性を根治し真の未完了検出を維持する
  fit: true
  purpose_gap: なし
binary_checks:
  AC1:
    - check: task_clarity内の機能名run_todo_fixme_residual_checkや検出器説明・引用としてのTODOはBC_YES_CLARITY_CONTRADICTION=0になるfixtureを追加する
      result: 'yes'
YAML

    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
    [[ "$output" == *"BC_YES_CLARITY_TERMS=''"* ]]
}

@test "SG-PRE9c still detects explicit AC unfinished wording" {
    _write_report "AC1未完了。"

    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
    [[ "$output" == *"未完了"* ]]
}

@test "SG-PRE9c ignores conditional rollback and historical causes in purpose fields" {
    cat > "$TEST_TMPDIR/report.yaml" <<'YAML'
status: completed
task_clarity:
  score: 100
  unclear_points: なし
  discretion_fills: なし
assumption_check: なし
purpose_validation:
  cmd_purpose: "速度基準未達ならrollbackして台帳へ記録する"
  fit: true
  purpose_gap: なし
not_in_scope:
  - "過去の未達原因の全面修正は対象外"
binary_checks:
  AC1:
    - check: 条件分岐を検証
      result: yes
YAML
    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
}

@test "SG-PRE9c detects unfinished purpose gap task clarity and assumption fields" {
    for field in purpose_gap task_clarity assumption_check; do
        cat > "$TEST_TMPDIR/report.yaml" <<'YAML'
status: completed
task_clarity: {score: 100, unclear_points: なし, discretion_fills: なし}
assumption_check: なし
purpose_validation: {cmd_purpose: 完了目的, fit: true, purpose_gap: なし}
binary_checks: {AC1: [{check: 完了確認, result: yes}]}
YAML
        case "$field" in
            purpose_gap)
                sed -i 's/fit: true/fit: false/' "$TEST_TMPDIR/report.yaml"
                sed -i 's/purpose_gap: なし/purpose_gap: AC2未完了/' "$TEST_TMPDIR/report.yaml"
                ;;
            task_clarity) sed -i 's/unclear_points: なし/unclear_points: 後で家老が実施/' "$TEST_TMPDIR/report.yaml" ;;
            assumption_check) sed -i 's/assumption_check: なし/assumption_check: 前提確認を保留/' "$TEST_TMPDIR/report.yaml" ;;
        esac
        run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
        [ "$status" -eq 0 ]
        [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
    done
}

@test "SG-PRE9c skips empty reports and reports containing binary no" {
    printf 'status: completed\n' > "$TEST_TMPDIR/report.yaml"
    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]

    _write_report "AC2未完了。"
    sed -i 's/result: yes/result: no/' "$TEST_TMPDIR/report.yaml"
    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
}

@test "SG-PRE9c keeps English conditional purpose out but detects English TODO in clarity" {
    cat > "$TEST_TMPDIR/report.yaml" <<'YAML'
status: completed
task_clarity: {score: 100, unclear_points: none, discretion_fills: none}
assumption_check: none
purpose_validation:
  cmd_purpose: "rollback only if the performance threshold is unmet"
  fit: true
  purpose_gap: none
binary_checks: {AC1: [{check: complete, result: yes}]}
YAML
    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]

    sed -i 's/unclear_points: none/unclear_points: "TODO: defer this work"/' "$TEST_TMPDIR/report.yaml"
    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
}

@test "SG-PRE9c real kagemaru report is clear and purpose-gap mutation is blocked" {
    local fixture="$PROJECT_ROOT/tests/fixtures/kagemaru_report_cmd_training_speed_capture_clipboard_image_20260717005701.yaml"
    run python3 "$ENGINE" --report "$fixture" --tasks-dir "$TEST_TMPDIR/tasks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
    [[ "$output" == *"GATE_PREDICTION=CLEAR"* ]]

    cp "$fixture" "$TEST_TMPDIR/report.yaml"
    sed -i 's/^  fit: true/  fit: false/' "$TEST_TMPDIR/report.yaml"
    sed -i "s/^  purpose_gap: ''/  purpose_gap: 'AC2未完了。後で家老が実施する'/" "$TEST_TMPDIR/report.yaml"
    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
    [[ "$output" == *"GATE_PREDICTION=BLOCK"* ]]
}

@test "SG-PRE9c purpose_gap follows purpose_validation fit semantics without weakening clarity checks" {
    local cases=(
        "true|採用基準未達のためrollback済み|なし|なし|yes|0"
        "false|AC2未完了。後で家老が実施する|なし|なし|yes|1"
        "missing|AC2未完了。後で家老が実施する|なし|なし|yes|1"
        "str_true|採用基準未達のためrollback済み|なし|なし|yes|0"
        "str_false|AC2未完了。後で家老が実施する|なし|なし|yes|1"
        "true|なし|後で家老が実施する|なし|yes|1"
        "true|なし|なし|前提確認を保留|yes|1"
        "false|AC2未完了。後で家老が実施する|なし|なし|no|0"
    )
    local row fit gap unclear assumption bc expected
    for row in "${cases[@]}"; do
        IFS='|' read -r fit gap unclear assumption bc expected <<< "$row"
        {
            printf 'status: completed\n'
            printf 'task_clarity: {score: 100, unclear_points: "%s", discretion_fills: なし}\n' "$unclear"
            printf 'assumption_check: "%s"\n' "$assumption"
            printf 'purpose_validation:\n  cmd_purpose: 完了目的\n'
            case "$fit" in
                missing) ;;
                str_true) printf '  fit: "true"\n' ;;
                str_false) printf '  fit: "false"\n' ;;
                *) printf '  fit: %s\n' "$fit" ;;
            esac
            printf '  purpose_gap: "%s"\n' "$gap"
            printf 'binary_checks: {AC1: [{check: 完了確認, result: %s}]}\n' "$bc"
        } > "$TEST_TMPDIR/report.yaml"
        run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
        [ "$status" -eq 0 ]
        [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=$expected"* ]]
    done
}

@test "SG-PRE9 sets BLOCK prediction for waived binary check no" {
    cat > "$TEST_TMPDIR/report.yaml" <<YAML
ninja: hayate
task_id: cmd_recon
status: completed
test_triage: pre_existing
binary_checks:
  commit:
    - check: "git commitが完了したか(untracked/modified=0)"
      result: no
      waive_reason: "偵察cmd: commit不要"
YAML

    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_HAS_NO=1"* ]]
    [[ "$output" == *"BC_NO_WAIVE_ITEMS='commit/git commitが完了したか(untracked/modified=0)'"* ]]
    [[ "$output" == *"GATE_PREDICTION=BLOCK"* ]]
    [[ "$output" == *"bc:no検出(waive_reason有でもBLOCK)"* ]]
}
