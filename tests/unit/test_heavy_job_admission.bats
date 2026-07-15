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
    # The suite itself may be launched through heavy_job_admission.sh. Its
    # re-entrancy marker must not leak into wrapper unit tests, which exercise
    # independent top-level contenders rather than a nested child job.
    unset SHOGUN_HEAVY_JOB_LOCK_HELD
    OUT="$TMP/timeline.log"
}

teardown() {
    rm -rf "$TMP"
}

_hook_payload() {
    python3 -c "import json,sys; print(json.dumps({'tool_name':'Bash','tool_input':{'command':sys.argv[1]}}))" "$1"
}

_run_hook() {
    _hook_payload "$1" | TMUX_AGENT_ID=shogun bash "$HOOK"
}

_malformed_readonly_rg_command() {
    cat <<'CMD'
printf 'wait_n_occurrences\n'; rg -n 'wait -n' scripts tests .githooks --glob '*.sh' --glob '*.bats' || true
printf 'global_tmp_locks\n'; rg -n '(LOCK_FILE|lock_file)=?["'"']?/tmp/|flock[^\n]*/tmp/' scripts .githooks --glob '*.sh' | head -200
CMD
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

@test "分類器: bats/pytestのversion・help照会はテストを実行せず軽量" {
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    [ "$(heavy_job_classify "bats --version")" = "light" ]
    [ "$(heavy_job_classify "bats --help")" = "light" ]
    [ "$(heavy_job_classify "pytest --version")" = "light" ]
    [ "$(heavy_job_classify "python3 -m pytest --help")" = "light" ]
}

@test "分類器: bats --countは複数ファイルでもテストを実行せず軽量" {
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    [ "$(heavy_job_classify "bats --count tests/unit/test_a.bats tests/unit/test_b.bats")" = "light" ]
    [ "$(heavy_job_classify "bats -c tests/unit/")" = "light" ]
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

@test "分類器: quote不整合のread-only rgは重量jobでなくmalformed" {
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    result="$(heavy_job_classify "$(_malformed_readonly_rg_command)")"
    [ "$result" = "malformed" ]
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

@test "分類器: semicolonで順次実行する単一bats群は各segmentを独立判定する" {
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    result="$(heavy_job_classify "bats tests/unit/test_a.bats; bats tests/unit/test_b.bats; bats tests/unit/test_c.bats")"
    [ "$result" = "light" ]
}

@test "分類器: 単一batsのfilter値は第二の対象ファイルに数えない" {
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    result="$(heavy_job_classify "bats tests/unit/test_a.bats --filter 'specific test name'")"
    [ "$result" = "light" ]
}

@test "分類器: chained read commandのpython heredoc本文に重量語があっても軽量" {
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    cmd="git log --oneline; python3 - <<'PY'
print('bats pytest full regression')
PY"
    result="$(heavy_job_classify "$cmd")"
    [ "$result" = "light" ]
}

# cmd_karo_ci_red_remaining_unit_202607151950: Claude Codeが自動付加する"2>&1"が
# shlexで"2>"+"&"+"1"にトークン化され、"2>"が単一ファイル指定segmentへ残存し
# 第二の対象ファイルとして誤カウントされていた(shell_command_segments.py root cause)。
@test "分類器: 単一.batsファイル1つに末尾2>&1が付いても軽量" {
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    result="$(heavy_job_classify "bats tests/unit/test_foo.bats 2>&1")"
    [ "$result" = "light" ]
}

# 家老レビュー指摘(2026-07-15 20:24): segment_tokensの出力自体が孤立segment ['1']
# を残していないことを直接検証する(heavy/light判定の副産物ではなく契約そのもの)。
@test "segment_tokens: 末尾2>&1は孤立segmentを残さず元コマンド1segmentのみ" {
    run python3 -S -c "
import sys
sys.path.insert(0, '$ROOT/scripts/lib')
from shell_command_segments import segment_tokens
result = segment_tokens('bats tests/unit/test_foo.bats 2>&1')
expected = [['bats', 'tests/unit/test_foo.bats']]
assert result == expected, f'expected {expected!r}, got {result!r}'
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == "ok" ]]
}

# 家老2次レビュー指摘(2026-07-15 20:27): 旧実装は">out"/"2>/tmp/x"のような
# attached-target token(operatorと対象が同一token、空白なし)にもbare operatorと
# 同じ扱いで次tokenを追加消費し、後続の正当な引数を食い違って消してしまうバグを
# 作っていた。attached-targetは1tokenで完結させ、後続tokenは消費してはならない。
@test "segment_tokens: attached-target redirect(>out/2>/tmp/x)は後続の正当な引数を消さない" {
    run python3 -S -c "
import sys
sys.path.insert(0, '$ROOT/scripts/lib')
from shell_command_segments import segment_tokens
cases = [
    ('cmd >out arg', [['cmd', 'arg']]),
    ('cmd 2>/tmp/x arg', [['cmd', 'arg']]),
    ('cmd > out arg', [['cmd', 'arg']]),
]
for cmd, expected in cases:
    result = segment_tokens(cmd)
    assert result == expected, f'{cmd!r}: expected {expected!r}, got {result!r}'
print('ok')
"
    [ "$status" -eq 0 ]
    [[ "$output" == "ok" ]]
}

@test "分類器: bats全量ディレクトリに末尾2>&1が付いても重量のまま" {
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    result="$(heavy_job_classify "bats tests/unit/ 2>&1")"
    [ "$result" = "heavy" ]
}

@test "分類器: bats複数ファイルに末尾2>&1が付いても重量のまま" {
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    result="$(heavy_job_classify "bats tests/unit/test_a.bats tests/unit/test_b.bats 2>&1")"
    [ "$result" = "heavy" ]
}

# --- admission wrapper (flock host-wide semaphore) ---

@test "wrapper: 単純コマンドを正常に実行できる" {
    run bash "$WRAPPER" -- echo "hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello"* ]]
}

@test "wrapper: 2重量ジョブ同時要求で実行中最大1、第2はevent-driven待機(busy pollingでない)" {
    local started_marker="$TMP/a_started"
    local release_marker="$TMP/release_a"
    (
        bash "$WRAPPER" -- bash -c "echo A-start \$(date +%s.%N) >> '$OUT'; touch '$started_marker'; while [ ! -f '$release_marker' ]; do sleep 0.01; done; echo A-end \$(date +%s.%N) >> '$OUT'"
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
        bash "$WRAPPER" -- bash -c "echo B-start \$(date +%s.%N) >> '$OUT'; touch '$TMP/b_started'"
    ) &
    pid_b=$!
    # Bがlock待機へ入る猶予を与え、A解放前には開始できないことを直接確認する。
    sleep 0.05
    [ ! -f "$TMP/b_started" ]
    touch "$release_marker"
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

@test "wrapper: durable背景workerへlock FDを継承せずmarker=0再入もself-deadlockしない" {
    local result="$TMP/background_reentry.result"
    # cmd_complete_gate -> semantic_causal_post_clear の実事故を再現する。外側の
    # admission中にdurable workerを背景起動し、workerは独立ジョブとしてmarkerを
    # 0へ戻して同じadmissionへ再入する。lock FDが継承される旧実装ではworker自身が
    # 保持するlockを待ち、1秒timeoutしてresultを作れない。
    bash "$WRAPPER" -- bash -c \
        "SHOGUN_HEAVY_JOB_LOCK_HELD=0 SHOGUN_HEAVY_JOB_ADMISSION_TIMEOUT=1 bash '$WRAPPER' -- sh -c 'printf inner-ok > \"$result\"' >/dev/null 2>&1 &"

    local waited=0
    while [ ! -f "$result" ]; do
        sleep 0.05
        waited=$((waited + 1))
        [ "$waited" -le 40 ] || break
    done
    [ -f "$result" ]
    [ "$(cat "$result")" = "inner-ok" ]
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
    local started_marker="$TMP/direct_a_started"
    local release_marker="$TMP/direct_release_a"
    (
        bash -c "echo A-start \$(date +%s.%N) >> '$OUT'; touch '$started_marker'; while [ ! -f '$release_marker' ]; do sleep 0.01; done; echo A-end \$(date +%s.%N) >> '$OUT'"
    ) &
    pid_a=$!
    local waited=0
    while [ ! -f "$started_marker" ]; do
        sleep 0.01
        waited=$((waited + 1))
        [ "$waited" -le 200 ] || break
    done
    (
        bash -c "echo B-start \$(date +%s.%N) >> '$OUT'; echo B-end \$(date +%s.%N) >> '$OUT'"
    ) &
    pid_b=$!
    wait "$pid_b"
    touch "$release_marker"
    wait "$pid_a"

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

@test "CI unit lane keeps file internals serial under aggregate jobs 8 and writes TAP artifact" {
    workflow="$ROOT/.github/workflows/test.yml"
    grep -q 'BATS_INNER_JOBS=1' "$workflow"
    grep -q 'BATS_FILE_TIMEOUT_SECONDS=900' "$workflow"
    grep -q 'timeout-minutes: 45' "$workflow"
    grep -Fq 'group: test-${{ github.workflow }}-${{ github.ref }}' "$workflow"
    grep -q 'cancel-in-progress: true' "$workflow"
    ! grep -q 'BATS_INNER_JOBS=8' "$workflow"
    grep -q 'BATS_TAP_OUTPUT=test-results/unit.tap' "$workflow"
    grep -q 'bash scripts/run_tests.sh unit' "$workflow"
    ! grep -q 'bats tests/unit/ .*--jobs 8' "$workflow"
}

@test "file-level overrides cannot exceed the aggregate test job budget" {
    runner="$ROOT/scripts/run_tests.sh"
    grep -q 'MAX_TEST_JOBS="${BATS_MAX_TEST_JOBS:-$_detected_test_cpus}"' "$runner"
    grep -q 'if \[ "\$_detected_test_cpus" -gt 8 \]' "$runner"
    grep -q 'file_inner_jobs="\$MAX_TEST_JOBS"' "$runner"
}

@test "shared hook git daemon and startup fixtures are exclusive file roots" {
    runner="$ROOT/scripts/run_tests.sh"
    fixture_contract='test_gate_shogun_startup.bats|test_heavy_job_admission.bats|test_daemon_maintenance_lock.bats|test_heavy_job_classifier_newline.bats|test_cmd_complete_insight_consumption.bats|test_pending_approval.bats|test_pre_bash_guard1_git_commit_tokenizer.bats|test_ninja_scope_commit.bats|test_deploy_task_template_generation.bats'
    grep -Fq "$fixture_contract" "$runner"
    grep -F -A3 "${fixture_contract})" "$runner" \
        | grep -q 'file_inner_jobs=1'
    grep -F -A3 "${fixture_contract})" "$runner" \
        | grep -q 'file_weight="\$MAX_TEST_JOBS"'
}

@test "hook: 単一.batsファイル/単一pytest::関数は軽量でBLOCKされない" {
    run _run_hook "bats tests/unit/test_foo.bats"
    [ "$status" -eq 0 ]
    run _run_hook "python3 -m pytest backend/tests/test_foo.py::test_bar"
    [ "$status" -eq 0 ]
}

@test "hook: bats/pytestのversion照会はheavy admissionを要求しない" {
    run _run_hook "bats --version"
    [ "$status" -eq 0 ]
    run _run_hook "python3 -m pytest --version"
    [ "$status" -eq 0 ]
}

@test "hook: bats --count複数ファイルはheavy admissionを要求しない" {
    run _run_hook "bats --count tests/unit/test_a.bats tests/unit/test_b.bats"
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

# cmd_karo_ci_red_remaining_unit_202607151950 (旧Guard 5): "bats tests/unit"を
# 実行対象のargvではなく$payload/$command全文への部分文字列/regexで検出していたため、
# 引用符内の説明文がたまたま一致しただけでも誤BLOCKしていた(家老一次証跡:
# 現象説明をinbox_write本文に含めただけで同じBLOCKが発生)。argv位置ベースの
# Guard17だけに一本化し、非実行本文(quoted prose)は誤検出しないことを固定する。
@test "hook: inbox_writeの説明文がbats全量glob文言を含んでも偽陽性0" {
    run _run_hook "bash scripts/inbox_write.sh saizo \"説明: bats tests/unit/*.bats のglob問題\" task_addendum karo cmd_test"
    [ "$status" -eq 0 ]
    run _run_hook "bash scripts/inbox_write.sh saizo \"説明: bats tests/unit/ 全量問題\" task_addendum karo cmd_test"
    [ "$status" -eq 0 ]
}

@test "hook: unit配下のbatsグロブを引数にした読み取り専用検索は偽陽性0" {
    run _run_hook "grep -l 'heavy_job' tests/unit/*.bats"
    [ "$status" -eq 0 ]
}

@test "hook: quote不整合のread-only rgはwrapperを誤案内せず構文BLOCK" {
    run _run_hook "$(_malformed_readonly_rg_command)"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(shell-syntax)"* ]]
    [[ "$output" != *"BLOCK(heavy-job-admission)"* ]]
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
if [ -n "${BATS_TAP_OUTPUT:-}" ]; then
    echo "not ok 1 inherited shared BATS_TAP_OUTPUT" >&2
    exit 1
fi
echo "ok 1 fake pass"
exit 0
FAKEEOF
    chmod +x "$dir/bats"
}

@test "run_tests.sh: FAILファイルを含む集合はrun_bats_files_parallel経由で最終exit非0" {
    local fake_dir="$TMP/fake_bats"
    _make_fake_bats "$fake_dir"
    run env REPO_ROOT="$ROOT" TEST_TIMING_LEDGER="$TMP/timing-fail.tsv" BATS_CACHE=0 BATS_SOURCE_FINGERPRINT=fake-fail PATH="$fake_dir:$PATH" \
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
    run env REPO_ROOT="$ROOT" TEST_TIMING_LEDGER="$TMP/timing-pass.tsv" BATS_CACHE=0 BATS_SOURCE_FINGERPRINT=fake-pass PATH="$fake_dir:$PATH" \
        bash -c '
            set -euo pipefail
            source "$1/scripts/run_tests.sh"
            run_bats_files_parallel "/tmp/test_pass_a.bats" "/tmp/test_pass_b.bats"
        ' _ "$ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS:"* ]]
}

# --- Guard 18: git stash mutation block (共有worktree保護) ---
# cmd_karo_ci_red_remaining_unit_202607151950: 2026-07-15 20:27実例 — bareの
# `git stash`が共有main working treeのtracked 23 files(複数忍者+運用差分)を一括退避した事故。
# argv位置ベースで実際に"git"+読み取り専用でない"stash"サブコマンドのときだけ
# BLOCKし、text上の"stash"言及(commit message/inbox本文等)は誤検出しないことを
# Guard 5→17の教訓に沿って直接検証する。

@test "分類器: git stash無引数/push/save/pop/apply/drop/clear/branchはblock" {
    source "$ROOT/scripts/lib/git_stash_guard_classify.sh"
    for cmd in "git stash" "git stash push" "git stash push -m msg" "git stash save msg" \
               "git stash pop" "git stash apply" "git stash drop" "git stash clear" \
               "git stash branch foo"; do
        result="$(git_stash_guard_classify "$cmd")"
        [ "$result" = "block" ]
    done
}

@test "分類器: git stash list/showはallow(読み取り専用)" {
    source "$ROOT/scripts/lib/git_stash_guard_classify.sh"
    r1="$(git_stash_guard_classify "git stash list")"
    r2="$(git_stash_guard_classify "git stash show")"
    r3="$(git_stash_guard_classify "git stash show -p stash@{0}")"
    [ "$r1" = "allow" ]
    [ "$r2" = "allow" ]
    [ "$r3" = "allow" ]
}

@test "分類器: git -C <root> stash形もblock、read-onlyはallow" {
    source "$ROOT/scripts/lib/git_stash_guard_classify.sh"
    r1="$(git_stash_guard_classify "git -C /some/repo stash")"
    r2="$(git_stash_guard_classify "git -C /some/repo stash pop")"
    r3="$(git_stash_guard_classify "git -C /some/repo stash list")"
    [ "$r1" = "block" ]
    [ "$r2" = "block" ]
    [ "$r3" = "allow" ]
}

@test "分類器: git status/commitや文面上のstash言及は偽陽性0" {
    source "$ROOT/scripts/lib/git_stash_guard_classify.sh"
    r1="$(git_stash_guard_classify "git status")"
    r2="$(git_stash_guard_classify "git commit -m 'stash cleanup message'")"
    r3="$(git_stash_guard_classify "bash scripts/inbox_write.sh saizo 'explaining git stash push behavior' task_addendum karo cmd_test")"
    [ "$r1" = "allow" ]
    [ "$r2" = "allow" ]
    [ "$r3" = "allow" ]
}

# 家老追加RC(2026-07-15 20:40): env/command/先頭代入prefix/bash -cで包むと
# "seg[0]が文字通りgit"チェックをすり抜けmutationがallowされていた(4/4実測)。
# env・command・VAR=value代入・bash -c '<nested>'を再帰的に展開してから判定する。
@test "分類器: env/command/代入prefix/bash -cで包んだgit stashもblockする" {
    source "$ROOT/scripts/lib/git_stash_guard_classify.sh"
    for cmd in "env git stash" "command git stash" "bash -c 'git stash'" "FOO=bar git stash" \
               "command env git stash" "FOO=bar env git stash pop" "bash -c 'env git stash pop'" \
               "env FOO=bar git stash"; do
        result="$(git_stash_guard_classify "$cmd")"
        [ "$result" = "block" ]
    done
}

@test "分類器: env/command/bash -cで包んだgit stash list/showはallowのまま" {
    source "$ROOT/scripts/lib/git_stash_guard_classify.sh"
    r1="$(git_stash_guard_classify "env git stash list")"
    r2="$(git_stash_guard_classify "command git stash show")"
    r3="$(git_stash_guard_classify "bash -c 'git stash list'")"
    [ "$r1" = "allow" ]
    [ "$r2" = "allow" ]
    [ "$r3" = "allow" ]
}

@test "分類器: quoted単一引数の説明文(report/commit -m等)は文面上のstash言及でも偽陽性0" {
    source "$ROOT/scripts/lib/git_stash_guard_classify.sh"
    r1="$(git_stash_guard_classify "git commit -m \"discussing git stash safety\"")"
    r2="$(git_stash_guard_classify "bash scripts/report_field_set.sh queue/reports/foo.yaml result.summary 'ran git stash safely'")"
    [ "$r1" = "allow" ]
    [ "$r2" = "allow" ]
}

# 家老RC4(2026-07-15 21:30): RC3の「segment内全suffix再帰評価」一般fallbackは
# 未知wrapper検出には有効だったが、echo/printf/rg/python3/bash script.sh/
# inbox_write.shへの非実行引数を実コマンドと誤認する偽陽性6/6を独立実測で
# 引き起こした。「後方にargvがある」だけではwrapper実行対象と一般コマンド引数を
# 区別不能(原理的に両立不能)と判明したため、全suffix fallbackを撤回し、
# 既知実行wrapperの明示SSOT(_EXEC_WRAPPERS、単一ファイル)+未知wrapperは
# fail-open(=誤検知させない)という安全側の設計へ回帰した。bash -cのnested
# 文字列内の裸文字列prose(echo等)は元のRC1同様allowへ戻る。
@test "分類器: bash -c nested文字列内のecho裸文字列prose(実コマンド不成立)は偽陽性0" {
    source "$ROOT/scripts/lib/git_stash_guard_classify.sh"
    result="$(git_stash_guard_classify "bash -c 'echo mentioning git stash push in text'")"
    [ "$result" = "allow" ]
}

@test "分類器: 既知wrapperテーブル外の一般コマンドへのgit stash引数は偽陽性0(karo RC4反例)" {
    source "$ROOT/scripts/lib/git_stash_guard_classify.sh"
    for cmd in "echo git stash" "printf %s git stash" "rg -n git stash scripts" \
               "python3 tool.py git stash" "bash script.sh git stash" \
               "bash scripts/inbox_write.sh karo git stash report"; do
        result="$(git_stash_guard_classify "$cmd")"
        [ "$result" = "allow" ]
    done
}

@test "hook: env/command/bash -cで包んだgit stashもBLOCKする" {
    run _run_hook "env git stash"
    [ "$status" -eq 2 ]
    run _run_hook "command git stash pop"
    [ "$status" -eq 2 ]
    run _run_hook "bash -c 'git stash'"
    [ "$status" -eq 2 ]
    run _run_hook "FOO=bar git stash"
    [ "$status" -eq 2 ]
}

# 家老追加RC2(2026-07-15 20:47): commit 8a0680570後もnohup/nice/timeout/setsid/
# `command --`の実行wrapper経由が5/5 allowだった。table駆動のexec-wrapper展開
# (_EXEC_WRAPPERS)で汎化し、個別enumerate競争を止める。
@test "分類器: nohup/nice/timeout/setsid/command --で包んだgit stashもblockする" {
    source "$ROOT/scripts/lib/git_stash_guard_classify.sh"
    for cmd in "command -- git stash" "nohup git stash" "nice git stash" \
               "timeout 5 git stash" "setsid git stash" "nice -n 10 git stash pop" \
               "timeout -k 5 30 git stash" "command env timeout 5 git stash"; do
        result="$(git_stash_guard_classify "$cmd")"
        [ "$result" = "block" ]
    done
}

@test "分類器: nohup/timeoutで包んだgit stash list/showと文面上のstashは偽陽性0" {
    source "$ROOT/scripts/lib/git_stash_guard_classify.sh"
    r1="$(git_stash_guard_classify "nohup git stash list")"
    r2="$(git_stash_guard_classify "timeout 5 git stash list")"
    r3="$(git_stash_guard_classify "nohup echo 'git stash'")"
    [ "$r1" = "allow" ]
    [ "$r2" = "allow" ]
    [ "$r3" = "allow" ]
}

@test "hook: nohup/nice/timeout/setsidで包んだgit stashもBLOCKする" {
    run _run_hook "nohup git stash"
    [ "$status" -eq 2 ]
    run _run_hook "nice git stash pop"
    [ "$status" -eq 2 ]
    run _run_hook "timeout 5 git stash"
    [ "$status" -eq 2 ]
    run _run_hook "setsid git stash"
    [ "$status" -eq 2 ]
}

# 家老RC3(2026-07-15 21:17): time/ionice/taskset/chrt/xargs経由と
# git -c alias.NAME=stash NAME(git自体のalias機構)が独立実測で7/7 allowだった。
# 既知wrapper列挙を止め、segment内の全suffixを再帰評価する一般fallback
# (未知の起動ラッパーにも対応)+ git -c alias解析(-c alias.NAME=stash NAME /
# -calias.NAME=stash NAME 双方の形)で根治した。
@test "分類器: 拡張SSOT(time/ionice/taskset/chrt/xargs)経由のgit stashもblockする" {
    source "$ROOT/scripts/lib/git_stash_guard_classify.sh"
    for cmd in "time git stash" "/usr/bin/time git stash" "ionice git stash" \
               "taskset -c 0 git stash" "chrt 1 git stash" "xargs git stash"; do
        result="$(git_stash_guard_classify "$cmd")"
        [ "$result" = "block" ]
    done
}

@test "分類器: 拡張SSOT wrapperでもgit stash list/showはallowのまま" {
    source "$ROOT/scripts/lib/git_stash_guard_classify.sh"
    r1="$(git_stash_guard_classify "time git stash list")"
    r2="$(git_stash_guard_classify "taskset -c 0 git stash show")"
    [ "$r1" = "allow" ]
    [ "$r2" = "allow" ]
}

@test "分類器: git -c alias.NAME=stash NAME(git自体のaliasによるstash迂回)もblockする" {
    source "$ROOT/scripts/lib/git_stash_guard_classify.sh"
    r1="$(git_stash_guard_classify "git -c alias.x=stash x")"
    r2="$(git_stash_guard_classify "git -calias.x=stash x")"
    r3="$(git_stash_guard_classify 'git -c alias.x="stash pop" x')"
    [ "$r1" = "block" ]
    [ "$r2" = "block" ]
    [ "$r3" = "block" ]
}

@test "分類器: git aliasがstash list/showへ展開する場合はallowのまま" {
    source "$ROOT/scripts/lib/git_stash_guard_classify.sh"
    r1="$(git_stash_guard_classify "git -c alias.x=stash x list")"
    r2="$(git_stash_guard_classify 'git -c alias.x="stash list" x')"
    [ "$r1" = "allow" ]
    [ "$r2" = "allow" ]
}

@test "hook: 拡張SSOT wrapper(time/taskset)とgit alias迂回もBLOCKする" {
    run _run_hook "time git stash"
    [ "$status" -eq 2 ]
    run _run_hook "taskset -c 0 git stash"
    [ "$status" -eq 2 ]
    run _run_hook "git -c alias.x=stash x"
    [ "$status" -eq 2 ]
}

@test "hook: git stash破壊的形はBLOCKし、list/showは通過する" {
    run _run_hook "git stash"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK"* ]]
    run _run_hook "git stash pop"
    [ "$status" -eq 2 ]
    run _run_hook "git stash list"
    [ "$status" -eq 0 ]
    run _run_hook "git stash show"
    [ "$status" -eq 0 ]
}
