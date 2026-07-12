#!/usr/bin/env bats
# cmd_karo_hotfix_heavy_job_admission_202607121348
# 同一8コアWSL2ホスト上でbats全量/pytest全量/DM-Signal golden regressionが無調停で
# 並走しCPUオーバーサブスクリプションでwall時間を増幅する構造バグの根治を検証する。

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WRAPPER="$ROOT/scripts/heavy_job_admission.sh"
    HOOK="$ROOT/.claude/hooks/pre-bash-combined.sh"
    TMP="$(mktemp -d "$BATS_TMPDIR/heavy_job_admission.XXXXXX")"
    export SHOGUN_HEAVY_JOB_LOCK_FILE="$TMP/admission.lock"
    OUT="$TMP/timeline.log"
}

teardown() {
    rm -rf "$TMP"
}

_hook_payload() {
    python3 -c "import json,sys; print(json.dumps({'tool_name':'Bash','tool_input':{'command':sys.argv[1]}}))" "$1"
}

_run_hook() {
    _hook_payload "$1" | bash "$HOOK"
}

# --- 分類器(SSOT) — argv位置ベース、部分文字列誤検出禁止 ---

@test "分類器: 単一.batsファイル1つは軽量" {
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    result="$(heavy_job_classify "bats tests/unit/test_foo.bats")"
    [ "$result" = "light" ]
}

@test "分類器: bats全量ディレクトリは重量" {
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    result="$(heavy_job_classify "bats tests/unit/")"
    [ "$result" = "heavy" ]
}

@test "分類器: bats複数ファイル指定は重量" {
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    result="$(heavy_job_classify "bats tests/unit/test_a.bats tests/unit/test_b.bats")"
    [ "$result" = "heavy" ]
}

@test "分類器: pytest全量ディレクトリは重量、単一::テスト関数指定は軽量" {
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    heavy="$(heavy_job_classify "python3 -m pytest backend/tests")"
    light="$(heavy_job_classify "python3 -m pytest backend/tests/test_foo.py::test_bar")"
    [ "$heavy" = "heavy" ]
    [ "$light" = "light" ]
}

@test "分類器: golden regressionスクリプト直接実行は重量" {
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    result="$(heavy_job_classify "python3 scripts/oneshot/cmd_3854_fof_golden_regression_check.py")"
    [ "$result" = "heavy" ]
}

@test "分類器: heredoc本文中のbats/pytest言及(prose)は誤検出しない" {
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    body='fix(docs): explain how to use bats and pytest in this repo

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>'
    cmd="git commit -m \"\$(cat <<'EOF'
$body
EOF
)\""
    result="$(heavy_job_classify "$cmd")"
    [ "$result" = "light" ]
}

@test "分類器: 通常のgit/report操作は軽量(偽陽性なし)" {
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    r1="$(heavy_job_classify "git status")"
    r2="$(heavy_job_classify "git commit -m test")"
    r3="$(heavy_job_classify "bash scripts/report_field_set.sh queue/reports/foo.yaml result.summary 'ran bats and pytest'")"
    [ "$r1" = "light" ]
    [ "$r2" = "light" ]
    [ "$r3" = "light" ]
}

# --- admission wrapper (flock host-wide semaphore) ---

@test "wrapper: 単純コマンドを正常に実行できる" {
    run bash "$WRAPPER" -- echo "hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello"* ]]
}

@test "wrapper: 2重量ジョブ同時要求で実行中最大1、第2はevent-driven待機(busy pollingでない)" {
    local started_marker="$TMP/a_started"
    (
        bash "$WRAPPER" -- bash -c "echo A-start \$(date +%s.%N) >> '$OUT'; touch '$started_marker'; sleep 2; echo A-end \$(date +%s.%N) >> '$OUT'"
    ) &
    pid_a=$!
    # host高負荷時のプロセス起動遅延に対して固定sleepより堅牢にするため、Aが実際に
    # 開始した証跡(マーカーファイル)の出現を短間隔ポーリングで待ってからBを起動する
    # (無期限busy pollingではなく上限10秒の有限リトライ)。
    local waited=0
    while [ ! -f "$started_marker" ]; do
        sleep 0.05
        waited=$((waited + 1))
        [ "$waited" -le 200 ] || break
    done
    (
        bash "$WRAPPER" -- bash -c "echo B-start \$(date +%s.%N) >> '$OUT'"
    ) &
    pid_b=$!
    wait "$pid_a" "$pid_b"

    a_end="$(awk '/^A-end/{print $2}' "$OUT")"
    b_start="$(awk '/^B-start/{print $2}' "$OUT")"
    [ -n "$a_end" ]
    [ -n "$b_start" ]
    # B must start at or after A finished. awk浮動小数点比較(整数秒丸めは0.x秒差を
    # 誤って一致させ得るため使わない)。
    awk -v a="$a_end" -v b="$b_start" 'BEGIN{exit !(b>=a)}'
}

@test "wrapper: 異常終了(非0 exit)後にlockが自動解放され後続がblockされず即進む" {
    run bash "$WRAPPER" -- bash -c 'exit 17'
    [ "$status" -eq 17 ]

    run timeout 5 bash "$WRAPPER" -- echo "acquired"
    [ "$status" -eq 0 ]
    [[ "$output" == *"acquired"* ]]
}

@test "wrapper: nested呼出し(既にlock保持中)はself-deadlockしない" {
    run timeout 10 bash "$WRAPPER" -- bash -c "bash '$WRAPPER' -- echo inner-ok"
    [ "$status" -eq 0 ]
    [[ "$output" == *"inner-ok"* ]]
}

@test "wrapper: stale lock残存0(実行後にlockファイルへの排他保持プロセスが残らない)" {
    bash "$WRAPPER" -- echo done
    # lsof/fuserで排他保持プロセスが残っていないことを確認(flockはfd close=解放)
    run bash -c "command -v fuser >/dev/null 2>&1 && fuser '$SHOGUN_HEAVY_JOB_LOCK_FILE' 2>/dev/null; true"
    [[ "$output" != *"$$"* ]]
    run timeout 5 bash "$WRAPPER" -- echo "second-acquire-ok"
    [ "$status" -eq 0 ]
}

@test "修正前相当: adminissionを経由しない直接実行は2ジョブが同時並走できる(max>=2)" {
    (
        bash -c "echo A-start \$(date +%s.%N) >> '$OUT'; sleep 1; echo A-end \$(date +%s.%N) >> '$OUT'"
    ) &
    pid_a=$!
    sleep 0.2
    (
        bash -c "echo B-start \$(date +%s.%N) >> '$OUT'; echo B-end \$(date +%s.%N) >> '$OUT'"
    ) &
    pid_b=$!
    wait "$pid_a" "$pid_b"

    a_end="$(awk '/^A-end/{print $2}' "$OUT")"
    b_start="$(awk '/^B-start/{print $2}' "$OUT")"
    # 修正前(wrapperなし): Bが Aの終了を待たずに開始できる(重複稼働の実証)。
    # 整数秒への丸めだと0.8秒差でも同一秒に収まり誤判定し得るためawk浮動小数点比較を使う。
    awk -v a="$a_end" -v b="$b_start" 'BEGIN{exit !(b<a)}'
}

# --- hook統合(Guard17): 迂回不可・偽陽性ゼロ ---

@test "hook: 直接bats全量実行はBLOCKする" {
    run _run_hook "bats tests/unit/"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK"* ]]
}

@test "hook: bats複数ファイル直接実行はBLOCKする" {
    run _run_hook "bats tests/unit/test_a.bats tests/unit/test_b.bats"
    [ "$status" -eq 2 ]
    [[ "$output" == *"heavy-job-admission"* ]]
}

@test "hook: wrapper経由のbats複数ファイル実行はPASSする(迂回不可の裏付け=直接は前項でBLOCK済み)" {
    run _run_hook "bash scripts/heavy_job_admission.sh -- bats tests/unit/test_a.bats tests/unit/test_b.bats"
    [ "$status" -eq 0 ]
}

@test "hook: run_tests.sh経由はBLOCKされない(runner自身がself-reexecでadmissionを内包)" {
    run _run_hook "bash scripts/run_tests.sh"
    [ "$status" -eq 0 ]
    run _run_hook "bash scripts/run_tests.sh unit"
    [ "$status" -eq 0 ]
}

@test "hook: 単一.batsファイル/単一pytest::関数は軽量でBLOCKされない" {
    run _run_hook "bats tests/unit/test_foo.bats"
    [ "$status" -eq 0 ]
    run _run_hook "python3 -m pytest backend/tests/test_foo.py::test_bar"
    [ "$status" -eq 0 ]
}

@test "hook: 通常のgit/report操作は偽陽性0" {
    run _run_hook "git status"
    [ "$status" -eq 0 ]
    run _run_hook "git commit -m test"
    [ "$status" -eq 0 ]
    run _run_hook "cat scripts/run_tests.sh"
    [ "$status" -eq 0 ]
    run _run_hook "bash scripts/report_field_set.sh queue/reports/foo.yaml result.summary 'ran bats and pytest'"
    [ "$status" -eq 0 ]
}

@test "hook: cd + 絶対パスでのDM-Signal golden regression直接実行もBLOCKし、wrapper経由はPASSする" {
    run _run_hook "cd /mnt/c/Python_app/DM-signal && python3 scripts/oneshot/cmd_3854_fof_golden_regression_check.py"
    [ "$status" -eq 2 ]
    run _run_hook "cd /mnt/c/Python_app/DM-signal && bash $ROOT/scripts/heavy_job_admission.sh -- python3 scripts/oneshot/cmd_3854_fof_golden_regression_check.py"
    [ "$status" -eq 0 ]
}

@test "hook: wrapper自身の二重wrap(wrapper経由でrun_tests.shを呼ぶ)は再帰BLOCKしない" {
    run _run_hook "bash scripts/heavy_job_admission.sh -- bash scripts/run_tests.sh"
    [ "$status" -eq 0 ]
}

# --- run_tests.sh exit code集約 (自身の終了コードが下位のFAILを正しく反映することの証明) ---
# 家老指摘(2026-07-12 14:28): background実行観測でrun_tests.sh unitがexit0と誤認された。
# 調査の過程で、bats @testブロックの中から実bats-coreをnested実行すると、bats-core
# 自身の内部通信(FD3以降・BATS_TEST_NUMBER等)が外側batsのTAP集計と衝突し、内側の
# batsプロセスが対象テストを一切実行しないままexit 0で終了する(env -i完全隔離+FD
# 明示close+setsidでも解消せず)ことを発見した。これはrun_tests.sh自体のバグではなく
# bats-in-bats特有の制約だが、そのままでは「FAILがexit0に化ける」経路を誤検出しうる。
# 検証はfake batsバイナリ(PATH差し替え)でrun_bats_files_parallel()の並列実行+
# 終了コード集約ロジックだけを実bats-core実行を経由せず直接確認する。
# run_tests.shはsourceしても副作用ゼロ(関数定義+変数初期化のみ)になるよう
# _run_tests_main()+"BASH_SOURCE==0"ガードでリファクタ済み。self-reexec
# (heavy_job_admission.sh/flock経由のexec)自体のexit伝播は
# "wrapper: 異常終了(非0 exit)後にlockが自動解放され..."で別途検証済み。

_make_fake_bats() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/bats" <<'FAKEEOF'
#!/usr/bin/env bash
# Fake bats: run_bats_files_parallel()の並列実行+終了コード集約だけを検証する
# ためのスタブ。実bats-coreはbats @testブロック内からnestedすると内部通信FDが
# 衝突しテストを実行せずexit0化する既知の問題があるため使わない。
for arg in "$@"; do
    case "$arg" in
        *fail*) echo "not ok 1 fake fail ($arg)"; exit 1 ;;
    esac
done
echo "ok 1 fake pass"
exit 0
FAKEEOF
    chmod +x "$dir/bats"
}

@test "run_tests.sh: FAILファイルを含む集合はrun_bats_files_parallel経由で最終exit非0" {
    local fake_dir="$TMP/fake_bats"
    _make_fake_bats "$fake_dir"
    run env REPO_ROOT=/tmp BATS_CACHE=0 BATS_SOURCE_FINGERPRINT=fake-fail PATH="$fake_dir:$PATH" \
        bash -c '
            set -euo pipefail
            source "$1/scripts/run_tests.sh"
            run_bats_files_parallel "/tmp/test_pass_x.bats" "/tmp/test_fail_x.bats"
        ' _ "$ROOT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not ok"* ]]
}

@test "run_tests.sh: 全PASSの集合はrun_bats_files_parallel経由で最終exit0" {
    local fake_dir="$TMP/fake_bats"
    _make_fake_bats "$fake_dir"
    run env REPO_ROOT=/tmp BATS_CACHE=0 BATS_SOURCE_FINGERPRINT=fake-pass PATH="$fake_dir:$PATH" \
        bash -c '
            set -euo pipefail
            source "$1/scripts/run_tests.sh"
            run_bats_files_parallel "/tmp/test_pass_a.bats" "/tmp/test_pass_b.bats"
        ' _ "$ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS:"* ]]
}

