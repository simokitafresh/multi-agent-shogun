#!/usr/bin/env bats
# test_necessity: Admission waits for live process-group work, ignores terminated zombie members, and fails closed at a finite deadline.
# cmd_karo_hotfix_heavy_job_admission_202607121348
# 同一8コアWSL2ホスト上でbats全量/pytest全量/DM-Signal golden regressionが無調停で
# 並走しCPUオーバーサブスクリプションでwall時間を増幅する構造バグの根治を検証する。

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WRAPPER="$ROOT/scripts/heavy_job_admission.sh"
    HOOK="$ROOT/.claude/hooks/pre-bash-combined.sh"
    TMP="$(mktemp -d "$BATS_TMPDIR/heavy_job_admission.XXXXXX")"
    mkdir -p "$TMP/tmp" "$TMP/singleflight" "$TMP/receipts"
    # Every nested runner in this fixture must use the test's own namespace.
    # The old default /tmp domains let concurrent CI roots contend on lpt,
    # manifests, receipts, and single-flight coordination before #42 reached
    # its orphan-owner assertion.
    export TMPDIR="$TMP/tmp"
    export RUN_TESTS_SINGLEFLIGHT_DIR="$TMP/singleflight"
    export RUN_TESTS_RECEIPT_DIR="$TMP/receipts"
    export SHOGUN_HEAVY_JOB_LOCK_FILE="$TMP/admission.lock"
    export SHOGUN_HEAVY_JOB_WAITER_DIR="$TMP/waiters"
    export SHOGUN_HEAVY_JOB_WAITER_MUTEX="$TMP/waiters.lock"
    # The suite itself may be launched through heavy_job_admission.sh. Its
    # re-entrancy marker must not leak into wrapper unit tests, which exercise
    # independent top-level contenders rather than a nested child job.
    unset SHOGUN_HEAVY_JOB_LOCK_HELD
    # The suite itself may be protected by a run-id guard. Unit contenders use
    # their own explicit IDs and must not inherit the suite's outer identity.
    unset SHOGUN_HEAVY_JOB_RUN_ID
    OUT="$TMP/timeline.log"
    export TEST_TIMING_LEDGER="$TMP/timing.tsv"
    printf 'run_id\trepo\tcommit_sha\tsuite_root\trunner\ttest_file\ttest_id_count\twall_sec\tstatus\tskip_count\tcache_hit\tsource_fingerprint\tmeasured_at\tresource_tags\n' >"$TEST_TIMING_LEDGER"
}

# test_necessity: The E2E CI job must reserve time for network-bound dependency
# installation without dropping or bypassing the E2E test target.
@test "E2E CI job reserves setup time and keeps the full test target" {
    run python3 - "$ROOT/.github/workflows/test.yml" <<'PY'
import sys
import yaml

workflow = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
e2e = workflow["jobs"]["e2e-tests"]
assert e2e["timeout-minutes"] >= 20
assert any(
    step.get("name") == "Run E2E tests"
    and step.get("run") == "bats tests/e2e/ --timing --jobs 1"
    for step in e2e["steps"]
)
PY
    [ "$status" -eq 0 ]
}

_install_empty_ps() {
    mkdir -p "$TMP/no-p9"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$TMP/no-p9/ps"
    chmod +x "$TMP/no-p9/ps"
    export PATH="$TMP/no-p9:$PATH"
}

_wait_for_waiter_count() {
    local expected="$1" attempts=0 actual
    while :; do
        actual="$(find "$SHOGUN_HEAVY_JOB_WAITER_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)"
        [ "$actual" -ge "$expected" ] && return 0
        attempts=$((attempts + 1))
        [ "$attempts" -lt 200 ] || return 1
        sleep 0.01
    done
}

_wait_for_owner_lock() {
    local attempts=0
    while flock -n "$SHOGUN_HEAVY_JOB_LOCK_FILE" true 2>/dev/null; do
        attempts=$((attempts + 1))
        [ "$attempts" -lt 200 ] || return 1
        sleep 0.01
    done
}

@test "CI waiterは先に待つnormal waiterを明示priorityで追い越す" {
    _install_empty_ps
    export SHOGUN_HEAVY_JOB_ADMISSION_HEARTBEAT_SECONDS=1
    release="$TMP/release-owner"
    bash "$WRAPPER" -- bash -c 'while [ ! -e "$1" ]; do sleep 0.01; done' _ "$release" &
    owner=$!
    _wait_for_owner_lock
    SHOGUN_HEAVY_JOB_PRIORITY=normal bash "$WRAPPER" -- bash -c 'echo normal >>"$1"' _ "$OUT" &
    normal=$!
    SHOGUN_HEAVY_JOB_PRIORITY=ci bash "$WRAPPER" -- bash -c 'echo ci >>"$1"' _ "$OUT" &
    ci=$!
    _wait_for_waiter_count 2
    touch "$release"
    wait "$owner" "$normal" "$ci"
    [ "$(sed -n '1p' "$OUT")" = "ci" ]
    [ "$(sed -n '2p' "$OUT")" = "normal" ]
}

@test "同priority waiterはenqueue順でhandoffし同時owner最大1" {
    _install_empty_ps
    export SHOGUN_HEAVY_JOB_ADMISSION_HEARTBEAT_SECONDS=1
    release="$TMP/release-owner"
    bash "$WRAPPER" -- bash -c 'while [ ! -e "$1" ]; do sleep 0.01; done' _ "$release" &
    owner=$!
    _wait_for_owner_lock
    for n in 1 2 3; do
        SHOGUN_HEAVY_JOB_PRIORITY=normal bash "$WRAPPER" -- bash -c \
            'v=$(cat "$1" 2>/dev/null || echo 0); v=$((v+1)); echo "$v" >"$1"; echo "$2:$v" >>"$3"; sleep 0.1; echo 0 >"$1"' \
            _ "$TMP/count" "$n" "$OUT" &
        pids[$n]=$!
        _wait_for_waiter_count "$n"
    done
    touch "$release"
    wait "$owner" "${pids[1]}" "${pids[2]}" "${pids[3]}"
    [ "$(cut -d: -f1 "$OUT" | paste -sd, -)" = "1,2,3" ]
    [ "$(cut -d: -f2 "$OUT" | sort -nr | head -1)" -eq 1 ]
}

@test "stale waiter票は回収され後続ownerを恒久BLOCKしない" {
    _install_empty_ps
    mkdir -p "$SHOGUN_HEAVY_JOB_WAITER_DIR"
    printf '999999 1 0 1\n' >"$SHOGUN_HEAVY_JOB_WAITER_DIR/000-00000000000000000001-0000999999"
    run env SHOGUN_HEAVY_JOB_ADMISSION_HEARTBEAT_SECONDS=1 bash "$WRAPPER" -- true
    [ "$status" -eq 0 ]
    [ ! -e "$SHOGUN_HEAVY_JOB_WAITER_DIR/000-00000000000000000001-0000999999" ]
}

@test "不正priorityはfail-closedでownerを開始しない" {
    run env SHOGUN_HEAVY_JOB_PRIORITY=urgent bash "$WRAPPER" -- sh -c 'echo bad >"$1"' _ "$OUT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"invalid heavy admission priority"* ]]
    [ ! -e "$OUT" ]
}

@test "ci_fix task metadataは明示envなしでもCI priorityへ解決される" {
    _install_empty_ps
    mkdir -p "$TMP/tasks" "$TMP/fake-tmux"
    printf 'task:\n  task_type: ci_fix\n' >"$TMP/tasks/hayate.yaml"
    cat >"$TMP/fake-tmux/tmux" <<'SH'
#!/usr/bin/env bash
printf 'hayate\n'
SH
    chmod +x "$TMP/fake-tmux/tmux"
    PATH="$TMP/fake-tmux:$PATH" TMUX_PANE=%fixture \
        SHOGUN_HEAVY_JOB_TASK_DIR="$TMP/tasks" \
        bash "$WRAPPER" -- sh -c 'echo admitted >"$1"' _ "$OUT"
    [ "$(cat "$OUT")" = admitted ]
    [ ! -e "$SHOGUN_HEAVY_JOB_WAITER_DIR/010-"* ]
}

_timing_row() {
    local file="$1" wall="$2" fingerprint="${3:-}"
    [ -n "$fingerprint" ] || fingerprint="$(sha256sum "$file" | awk '{print $1}')"
    printf 'fixture\trepo\tHEAD\tdirect\tbats\t%s\t1\t%s\tpass\t0\t0\t%s\t%s\tmode=direct;jobs=1\n' \
      "$file" "$wall" "$fingerprint" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$TEST_TIMING_LEDGER"
}

_quick_fixture() {
    local name="$1" file
    file="$TMP/$name"
    printf '@test "quick" { true; }\n' >"$file"
    _timing_row "$file" 1.000
    printf '%s\n' "$file"
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

# GA-231/GA-231c(忍者・指揮官のgit commit直書き禁止)はagent identityで発火する。
# heavy admissionの偽陽性を測る際は、identity由来のBLOCKと混同しないよう
# 鎖の外(agent roleでない)identityで実行する。
_run_hook_as_non_agent() {
    _hook_payload "$1" | TMUX_AGENT_ID=lord-tools bash "$HOOK"
}

_exclusive_fixture_contract() {
    local runner="$1" block fixture
    local -a required=(
        test_gate_shogun_startup.bats
        test_heavy_job_admission.bats
        test_daemon_maintenance_lock.bats
        test_heavy_job_classifier_newline.bats
        test_cmd_complete_insight_consumption.bats
        test_pending_approval.bats
        test_pre_bash_guard1_git_commit_tokenizer.bats
        test_ninja_scope_commit.bats
        test_deploy_task_template_generation.bats
    )
    block="$(awk '
        /These fixture suites exercise process-wide hooks/ { capture=1 }
        capture { print }
        capture && /^[[:space:]]*esac[[:space:]]*$/ { exit }
    ' "$runner")"
    [ -n "$block" ] || return 1
    for fixture in "${required[@]}"; do
        [[ "$block" == *"$fixture"* ]] || return 1
    done
    grep -Eq '^[[:space:]]*file_inner_jobs=1[[:space:]]*$' <<<"$block" || return 1
    grep -Eq '^[[:space:]]*file_weight="\$MAX_TEST_JOBS"[[:space:]]*$' <<<"$block"
}

_malformed_readonly_rg_command() {
    cat <<'CMD'
printf 'wait_n_occurrences\n'; rg -n 'wait -n' scripts tests .githooks --glob '*.sh' --glob '*.bats' || true
printf 'global_tmp_locks\n'; rg -n '(LOCK_FILE|lock_file)=?["'"']?/tmp/|flock[^\n]*/tmp/' scripts .githooks --glob '*.sh' | head -200
CMD
}

@test "leader終了後のprocess group drainは有限deadlineでfail-closed" {
    local started="$TMP/detached.started" child_pid begin end
    begin="$(date +%s)"
    run env SHOGUN_HEAVY_JOB_DRAIN_TIMEOUT=1 \
        bash "$WRAPPER" -- bash -c 'sleep 1.1 & echo $! > "$1"' _ "$started"
    end="$(date +%s)"
    [ "$status" -eq 124 ]
    [[ "$output" == *"did not drain within 1s"* ]]
    [ $((end - begin)) -lt 10 ]
    [ -e "$started" ]
    child_pid="$(cat "$started")"
    sleep 0.3
    [ ! -e "/proc/$child_pid" ]
}

@test "GitHub runner型: 終了済みzombieだけのprocess groupはdrain済みとして扱う" {
    local fakebin="$TMP/fakebin" begin end
    mkdir -p "$fakebin"
    cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
printf '%s Z\n' "$SHOGUN_HEAVY_JOB_DRAIN_PGID"
SH
    chmod +x "$fakebin/ps"

    begin="$(date +%s%N)"
    run env PATH="$fakebin:$PATH" \
        SHOGUN_HEAVY_JOB_DRAIN_TIMEOUT=1 \
        bash "$WRAPPER" -- true
    end="$(date +%s%N)"

    [ "$status" -eq 0 ]
    # Shared CI hosts can deschedule this zero-work zombie probe while other
    # compatibility roots are draining. Keep the bound finite and diagnostic
    # without treating bounded scheduler latency as a process leak.
    [ $((end - begin)) -lt 5000000000 ]
}

@test "drain判定は対象PGIDの非zombieだけを待ち別groupを無視する" {
    local fakebin="$TMP/fakebin"
    mkdir -p "$fakebin"
    cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
printf '999999 S\n'
printf '%s Z\n' "$SHOGUN_HEAVY_JOB_DRAIN_PGID"
SH
    chmod +x "$fakebin/ps"

    run env PATH="$fakebin:$PATH" \
        SHOGUN_HEAVY_JOB_DRAIN_TIMEOUT=1 \
        bash "$WRAPPER" -- true
    [ "$status" -eq 0 ]
}

@test "drain判定は対象PGIDのlive memberをdeadlineまで待ってBLOCKする" {
    local fakebin="$TMP/fakebin"
    mkdir -p "$fakebin"
    cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
printf '%s S\n' "$SHOGUN_HEAVY_JOB_DRAIN_PGID"
SH
    chmod +x "$fakebin/ps"

    run env PATH="$fakebin:$PATH" SHOGUN_HEAVY_JOB_DRAIN_TIMEOUT=1 \
        bash "$WRAPPER" -- true
    [ "$status" -eq 124 ]
    [[ "$output" == *"did not drain within 1s"* ]]
}

@test "process snapshot失敗はdrain済みにせずdeadlineでfail-closed" {
    local fakebin="$TMP/fakebin"
    mkdir -p "$fakebin"
    cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
exit 1
SH
    chmod +x "$fakebin/ps"

    run env PATH="$fakebin:$PATH" SHOGUN_HEAVY_JOB_DRAIN_TIMEOUT=1 \
        bash "$WRAPPER" -- true
    [ "$status" -eq 124 ]
    [[ "$output" == *"did not drain within 1s"* ]]
}

@test "drain timeout診断は対象PGIDのlive memberだけをbounded安全fieldで出す" {
    local fakebin="$TMP/fakebin"
    mkdir -p "$fakebin"
    cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *"pid="* ]]; then
    printf '101 1 999999 S 9 unrelated\n'
    printf '102 1 %s Z 8 zombie\n' "$SHOGUN_HEAVY_JOB_DRAIN_PGID"
    printf '103 1 %s S 7 worker\n' "$SHOGUN_HEAVY_JOB_DRAIN_PGID"
else
    printf '%s S\n' "$SHOGUN_HEAVY_JOB_DRAIN_PGID"
fi
SH
    chmod +x "$fakebin/ps"

    run env PATH="$fakebin:$PATH" SHOGUN_HEAVY_JOB_DRAIN_TIMEOUT=1 \
        bash "$WRAPPER" -- true
    [ "$status" -eq 124 ]
    [[ "$output" == *"DRAIN_MEMBER pid=103 ppid=1 pgid="*" stat=S elapsed=7 comm=worker origin=unknown"* ]]
    [[ "$output" != *"unrelated"* ]]
    [[ "$output" != *"zombie"* ]]
    [[ "$output" != *"argv="* ]]
    [[ "$output" != *"env="* ]]
    [[ "$output" != *"cwd="* ]]
    [ "$(grep -c '^DRAIN_MEMBER ' <<< "$output")" -eq 1 ]
}

# --- 分類器(SSOT) — argv位置ベース、部分文字列誤検出禁止 ---

@test "分類器: 単一.batsファイル1つは軽量" {
    local fixture="$TMP/test_foo.bats"
    printf '@test "quick" { true; }\n' >"$fixture"
    _timing_row "$fixture" 9.999
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    result="$(heavy_job_classify "bats $fixture")"
    [ "$result" = "light" ]
}

@test "分類器: 実測10秒超でも単一.batsは呼出幅が1なので軽量" {
    local fixture="$TMP/test_campaign_lane_shard_item.bats"
    printf '@test "slow" { true; }\n' >"$fixture"
    _timing_row "$fixture" 29.840
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    [ "$(heavy_job_classify "bats $fixture")" = "light" ]
}

@test "分類器: ledger欠損・fingerprint不一致でも単一.batsは軽量" {
    local fixture="$TMP/test_unknown.bats"
    printf '@test "unknown" { true; }\n' >"$fixture"
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    [ "$(heavy_job_classify "bats $fixture")" = "light" ]
    _timing_row "$fixture" 1.000 deadbeef
    [ "$(heavy_job_classify "bats $fixture")" = "light" ]
}

@test "分類器: 単一.bats判定はtiming indexの破損・更新に依存しない" {
    local fixture="$TMP/test-cache-refresh.bats" cache_dir="$TMP/index-cache"
    printf '@test "cache" { true; }\n' >"$fixture"
    _timing_row "$fixture" 1.000
    export HEAVY_JOB_INDEX_CACHE_DIR="$cache_dir"
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    mkdir -p "$cache_dir"
    printf 'corrupt' >"$cache_dir/stale.json"
    [ "$(heavy_job_classify "bats $fixture")" = "light" ]
    _timing_row "$fixture" 29.840
    [ "$(heavy_job_classify "bats $fixture")" = "light" ]
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
    local a="$(_quick_fixture a.bats)" b="$(_quick_fixture b.bats)" c="$(_quick_fixture c.bats)"
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    result="$(heavy_job_classify "bats $a; bats $b; bats $c")"
    [ "$result" = "light" ]
}

@test "分類器: 単一batsのfilter値は第二の対象ファイルに数えない" {
    local fixture="$(_quick_fixture filtered.bats)"
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    result="$(heavy_job_classify "bats $fixture --filter 'specific test name'")"
    [ "$result" = "light" ]
}

@test "分類器: 実行commandだけを分類する表はFP=0 FN=0" {
    local fixture="$(_quick_fixture matrix.bats)" command expected actual
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    local -a cases=(
        "bats $fixture|light"
        "bats '$fixture'|light"
        "bats --filter 'one test' $fixture|light"
        "printf '%s\\n' 'bats tests/unit/a.bats tests/unit/b.bats'|light"
        "python3 - <<'PY'
print('bats tests/unit/a.bats tests/unit/b.bats')
PY|light"
        "echo before && bats $fixture|light"
        "bats tests/unit/a.bats tests/unit/b.bats|heavy"
        "bats tests/unit/|heavy"
    )
    local fp=0 fn=0
    for row in "${cases[@]}"; do
        command="${row%|*}"
        expected="${row##*|}"
        actual="$(heavy_job_classify "$command")"
        if [ "$expected" = light ] && [ "$actual" = heavy ]; then fp=$((fp + 1)); fi
        if [ "$expected" = heavy ] && [ "$actual" = light ]; then fn=$((fn + 1)); fi
    done
    [ "$fp" -eq 0 ]
    [ "$fn" -eq 0 ]
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
    local fixture="$(_quick_fixture redirected.bats)"
    source "$ROOT/scripts/lib/heavy_job_classify.sh"
    result="$(heavy_job_classify "bats $fixture 2>&1")"
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
    # 固定sleepで「Bが待機へ入った」と推測せず、待機票を一次観測してから
    # A解放前には開始できないことを直接確認する。
    _wait_for_waiter_count 1
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

# test_necessity: metrics非同期writerが遅延しても異常exit後にhost-wide admission FDを継承せず、後続ownerが有限時間内に取得できる不変量。
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

@test "wrapper: parent exit後も同じprocess groupの子孫がdrainするまで返らない" {
    marker="$TMP/descendant.done"
    started="$(date +%s%N)"
    bash "$WRAPPER" -- bash -c "(sleep 0.25; printf done > '$marker') &"
    ended="$(date +%s%N)"
    [ -f "$marker" ]
    [ $((ended - started)) -ge 200000000 ]
}

@test "wrapper: 同一run idの重複起動は待機でなくBLOCKする" {
    release="$TMP/run.release"
    holder_started="$TMP/run-holder.started"
    SHOGUN_HEAVY_JOB_RUN_ID=same bash "$WRAPPER" -- bash -c "touch '$holder_started'; while [ ! -e '$release' ]; do sleep 0.02; done" &
    holder=$!
    local waited=0
    while [ ! -f "$holder_started" ]; do
        sleep 0.01
        waited=$((waited + 1))
        [ "$waited" -le 200 ] || break
    done
    [ -f "$holder_started" ]
    run env SHOGUN_HEAVY_JOB_RUN_ID=same bash "$WRAPPER" -- true
    [ "$status" -ne 0 ]
    [[ "$output" == *"duplicate heavy run id"* ]]
    touch "$release"
    wait "$holder"
}

# test_necessity: unit並行2要求でleaderが1件のreceipt・1回の実行に完結し、followerが同一receiptへ相乗りしheartbeatで待機進捗を出力し、snapshot母数(observed_test_count)が両者で一致する不変量。
@test "run_tests single-flight joins one leader receipt with heartbeat and fixed snapshot" {
    local fixture="$TMP/singleflight"
    mkdir -p "$fixture/tests/unit" "$fixture/scripts" "$fixture/receipts" "$fixture/sf"
    cp "$ROOT/scripts/run_tests.sh" "$ROOT/scripts/run_with_receipt.sh" "$ROOT/scripts/heavy_job_admission.sh" "$ROOT/scripts/test_timing_ledger_write.sh" "$ROOT/scripts/test_suite_timing_ledger_write.sh" "$fixture/scripts/"
    printf '@test "slow" { sleep 1.1; [ -f "$BATS_TEST_FILENAME" ]; }\n' > "$fixture/tests/unit/slow.bats"
    git -C "$fixture" init -q
    git -C "$fixture" config user.email test@example.com
    git -C "$fixture" config user.name test
    git -C "$fixture" add .
    git -C "$fixture" commit -qm initial
    env -u RUN_TESTS_ACTIVE -u SHOGUN_HEAVY_JOB_LOCK_HELD -u SHOGUN_HEAVY_JOB_ADMITTED SHOGUN_HEAVY_JOB_LOCK_FILE="$fixture/heavy.lock" REPO_ROOT="$fixture" RUN_TESTS_RECEIPT_DIR="$fixture/receipts" RUN_TESTS_SINGLEFLIGHT_DIR="$fixture/sf" RUN_TESTS_SINGLEFLIGHT_HEARTBEAT_SECONDS=1 BATS_MAX_TEST_JOBS=1 bash "$fixture/scripts/run_tests.sh" unit >"$fixture/a.out" 2>"$fixture/a.err" &
    local a=$!
    local waited=0
    while ! grep -q SINGLE_FLIGHT_LEADER "$fixture/a.err" 2>/dev/null; do sleep 0.02; waited=$((waited+1)); [ "$waited" -lt 200 ] || break; done
    env -u RUN_TESTS_ACTIVE -u SHOGUN_HEAVY_JOB_LOCK_HELD -u SHOGUN_HEAVY_JOB_ADMITTED SHOGUN_HEAVY_JOB_LOCK_FILE="$fixture/heavy.lock" REPO_ROOT="$fixture" RUN_TESTS_RECEIPT_DIR="$fixture/receipts" RUN_TESTS_SINGLEFLIGHT_DIR="$fixture/sf" RUN_TESTS_SINGLEFLIGHT_HEARTBEAT_SECONDS=1 BATS_MAX_TEST_JOBS=1 bash "$fixture/scripts/run_tests.sh" unit >"$fixture/b.out" 2>"$fixture/b.err" &
    local b=$!
    local ra=0 rb=0
    wait "$a" || ra=$?
    wait "$b" || rb=$?
    if [ "$ra" -ne 0 ] || [ "$rb" -ne 0 ]; then
        cat "$fixture/a.err" "$fixture/a.out" "$fixture/b.err" "$fixture/b.out" "$fixture"/receipts/*.output >&3
        return 1
    fi
    # A join also writes a small structured .join_status.json sidecar
    # (cmd_karo_impl_singleflight_tree_identity_20260726 AC4); exclude it here
    # so this count still proves "exactly one real receipt, no re-run".
    [ "$(find "$fixture/receipts" -name '*.json' ! -name '*.join_status.json' | wc -l)" -eq 1 ]
    grep -q 'SINGLE_FLIGHT_JOINED' "$fixture/b.err"
    grep -q 'SINGLE_FLIGHT_HEARTBEAT' "$fixture/b.err"
    grep -q 'joined=1' "$fixture/b.out"
    [ "$(python3 -c 'import json,glob; d=json.load(open(sorted(p for p in glob.glob("'"$fixture"'/receipts/*.json") if not p.endswith(".join_status.json"))[0])); print(d["observed_test_count"])')" -eq 1 ]
}

# test_necessity: terminal receiptを残してleaderが死に子孫だけがlock FDを保持しても、followerが10秒以内に停止せず同一結果へ収束する契約。
@test "run_tests single-flight recovers terminal receipt from dead owner with orphan lock holder" {
    local fixture="$TMP/singleflight-orphan"
    mkdir -p "$fixture/tests/unit" "$fixture/scripts" "$fixture/receipts" "$fixture/sf"
    cp "$ROOT/scripts/run_tests.sh" "$ROOT/scripts/run_with_receipt.sh" "$ROOT/scripts/heavy_job_admission.sh" "$ROOT/scripts/test_timing_ledger_write.sh" "$ROOT/scripts/test_suite_timing_ledger_write.sh" "$fixture/scripts/"
    printf '@test "pass" { true; }\n' > "$fixture/tests/unit/pass.bats"
    git -C "$fixture" init -q
    git -C "$fixture" config user.email test@example.com
    git -C "$fixture" config user.name test
    git -C "$fixture" add .
    git -C "$fixture" commit -qm initial
    local linked="$TMP/singleflight-orphan-linked"
    git -C "$fixture" worktree add -q "$linked" HEAD
    # The outer run_tests.sh exports its own REPO_ROOT into bats fixtures.
    # Without an explicit fixture root here, this seed invocation resolves the
    # real 239-file suite instead of the one-file seed tree, recursively
    # starting the heavy suite and contending with every compatibility run.
    env -u RUN_TESTS_ACTIVE -u SHOGUN_HEAVY_JOB_LOCK_HELD -u SHOGUN_HEAVY_JOB_ADMITTED \
        REPO_ROOT="$fixture" RUN_TESTS_RECEIPT_DIR="$fixture/receipts" RUN_TESTS_SINGLEFLIGHT_DIR="$fixture/seed-sf" BATS_MAX_TEST_JOBS=1 \
        bash "$fixture/scripts/run_tests.sh" unit >/dev/null 2>&1
    local receipt
    receipt="$(find "$fixture/receipts" -name '*.json' -print -quit)"
    (
        exec 9>"$fixture/sf/unit.lock"
        flock 9
        sleep 20
    ) &
    local holder=$!
    local holder_pgid
    holder_pgid="$(ps -o pgid= -p "$holder" | tr -d ' ')"
    # cmd_karo_impl_singleflight_tree_identity_20260726: the follower now
    # cross-checks the dead owner's recorded tree identity (lines 5-6) against
    # its OWN tree before joining. Compute the exact same fingerprint the
    # follower (running from $linked, mode=unit) will independently derive, so
    # this fixture keeps exercising "orphan lock holder recovery" rather than
    # tripping the (unrelated) tree-mismatch guard.
    local _seed_selection _seed_head _seed_dirty
    _seed_selection="$(find "$linked/tests/unit" -maxdepth 1 -name '*.bats' -type f -print | sort -u)"
    _seed_head="$(git -C "$linked" rev-parse HEAD)"
    _seed_dirty="$(
        { printf '%s\n' "$_seed_selection"; git -C "$linked" status --porcelain -- "$linked/tests/unit/pass.bats" 2>/dev/null; } \
        | sha256sum | awk '{print $1}'
    )"
    printf '%s\n99999999\norphan-generation\n%s\n%s\n%s\n' "$receipt" "$holder_pgid" "$_seed_head" "$_seed_dirty" > "$fixture/sf/unit.state"
    local started=$SECONDS
    run timeout 12 env -u RUN_TESTS_ACTIVE -u SHOGUN_HEAVY_JOB_LOCK_HELD -u SHOGUN_HEAVY_JOB_ADMITTED RUN_TESTS_RECEIPT_DIR="$fixture/receipts-follow" RUN_TESTS_SINGLEFLIGHT_DIR="$fixture/sf" RUN_TESTS_SINGLEFLIGHT_HEARTBEAT_SECONDS=1 RUN_TESTS_SINGLEFLIGHT_STALE_SECONDS=1 BATS_MAX_TEST_JOBS=1 \
        REPO_ROOT="$linked" bash "$linked/scripts/run_tests.sh" unit
    local elapsed=$((SECONDS - started))
    kill "$holder" 2>/dev/null || true
    wait "$holder" 2>/dev/null || true
    [ "$status" -eq 0 ]
    [ "$elapsed" -le 10 ]
    [[ "$output" == *"SINGLE_FLIGHT_STALE_OWNER"* ]]
    [[ "$output" == *"owner_pid=99999999"* ]]
    [[ "$output" == *"generation=orphan-generation"* ]]
    [[ "$output" =~ lock_holders=[1-9][0-9]* ]]
    [[ "$output" == *"followers=1"* ]]
    [[ "$output" == *"stale_owner=1"* ]]
}

# test_necessity: SHOGUN_HEAVY_JOB_LOCK_HELD=1を持つ既admitted呼出しはsingle-flightロック取得をスキップしlock inversionによるdeadlockを防ぐ不変量。
@test "already admitted run_tests skips single-flight lock to prevent lock inversion" {
    run env SHOGUN_HEAVY_JOB_LOCK_HELD=1 RUN_TESTS_ACTIVE=1 bash "$ROOT/scripts/run_tests.sh" unit
    [ "$status" -ne 0 ]
    [[ "$output" != *'SINGLE_FLIGHT_'* ]]
}

@test "wrapper: durable背景workerへlock FDを継承せずmarker=0再入もself-deadlockしない" {
    local result="$TMP/background_reentry.result"
    # cmd_complete_gate -> semantic_causal_post_clear の実事故を再現する。外側の
    # admission中にdurable workerを背景起動し、workerは独立ジョブとしてmarkerを
    # 0へ戻して同じadmissionへ再入する。lock FDが継承される旧実装ではworker自身が
    # 保持するlockを待ち、1秒timeoutしてresultを作れない。
    bash "$WRAPPER" -- bash -c \
        "setsid -f env SHOGUN_HEAVY_JOB_LOCK_HELD=0 SHOGUN_HEAVY_JOB_ADMISSION_TIMEOUT=1 bash '$WRAPPER' -- sh -c 'printf inner-ok > \"$result\"' >/dev/null 2>&1"

    local waited=0
    while [ ! -f "$result" ]; do
        sleep 0.05
        waited=$((waited + 1))
        [ "$waited" -le 40 ] || break
    done
    [ -f "$result" ]
    [ "$(cat "$result")" = "inner-ok" ]
}

# test_necessity: metrics非同期writerを含む通常exit後にadmission lock holderが残らず、外部holderを操作せず後続ownerへhandoffする不変量。
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

@test "CI push lane integrates declared tests with serial file internals and TAP artifact" {
    workflow="$ROOT/.github/workflows/test.yml"
    grep -q 'BATS_INNER_JOBS=1' "$workflow"
    grep -q 'BATS_FILE_TIMEOUT_SECONDS=300' "$workflow"
    grep -q 'timeout-minutes: 12' "$workflow"
    grep -Fq 'group: test-${{ github.workflow }}-${{ github.ref }}' "$workflow"
    grep -q 'cancel-in-progress: true' "$workflow"
    ! grep -q 'BATS_INNER_JOBS=8' "$workflow"
    grep -q 'tap="$GITHUB_WORKSPACE/test-results/shard-${{ matrix.shard }}-requested.tap"' "$workflow"
    grep -q 'compatibility: true' "$workflow"
    grep -q 'bash scripts/run_tests.sh push' "$workflow"
    grep -q 'find "$REPO_ROOT/tests/unit" -maxdepth 1' "$ROOT/scripts/run_tests.sh"
    grep -q 'find "$REPO_ROOT/tests" -maxdepth 1' "$ROOT/scripts/run_tests.sh"
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
    _exclusive_fixture_contract "$runner"
}

@test "exclusive fixture contract ignores arm order and additional fixtures" {
    local runner="$TMP/run_tests.sh"
    cp "$ROOT/scripts/run_tests.sh" "$runner"
    sed -i 's/test_gate_shogun_startup\.bats|test_heavy_job_admission\.bats/test_unknown_future_fixture.bats|test_heavy_job_admission.bats|test_gate_shogun_startup.bats/' "$runner"
    _exclusive_fixture_contract "$runner"
}

@test "exclusive fixture contract fails closed when a required fixture or assignment is missing" {
    local runner="$TMP/run_tests.sh"
    cp "$ROOT/scripts/run_tests.sh" "$runner"
    sed -i 's/test_pending_approval\.bats|//' "$runner"
    run _exclusive_fixture_contract "$runner"
    [ "$status" -ne 0 ]

    cp "$ROOT/scripts/run_tests.sh" "$runner"
    sed -i '/These fixture suites exercise process-wide hooks/,/^[[:space:]]*esac[[:space:]]*$/ s/file_weight="\$MAX_TEST_JOBS"/file_weight="\$INNER_JOBS"/' "$runner"
    run _exclusive_fixture_contract "$runner"
    [ "$status" -ne 0 ]
}

@test "hook: 実行batsは単一でもBLOCKし単一pytest::関数はALLOW" {
    local fixture="$(_quick_fixture hook-quick.bats)"
    run _run_hook "bats $fixture"
    [ "$status" -eq 2 ]
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
    # cmd_karo_impl_commander_scope_commit_20260725 で GA-231c(指揮官のgit commit直書き禁止)が
    # 追加されたため、shogun identityでのdirect commitはBLOCKが正となった。
    # 本testの契約は「heavy admission分類器の偽陽性0」であり identity guard の検証ではないので、
    # 鎖の外のidentityで測る。GA-231c自体の発火は
    # tests/unit/test_pre_bash_combined.bats が既に固定しているため重複させない。
    run _run_hook_as_non_agent "git commit -m test"
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

@test "run_tests.sh: 全cache-hit集合は空pidsをwaitせずexit0" {
    local fake_dir="$TMP/fake_bats" marker="$TMP/fake-bats-started"
    mkdir -p "$fake_dir"
    cat > "$fake_dir/bats" <<FAKEEOF
#!/usr/bin/env bash
touch "$marker"
exit 99
FAKEEOF
    chmod +x "$fake_dir/bats"

    run env REPO_ROOT="$ROOT" TEST_TIMING_LEDGER="$TMP/timing-cache.tsv" \
        BATS_CACHE=1 BATS_CACHE_DIR="$TMP/cache" BATS_SOURCE_FINGERPRINT=all-cache \
        PATH="$fake_dir:$PATH" bash -c '
            set -euo pipefail
            source "$1/scripts/run_tests.sh"
            mkdir -p "$BATS_CACHE_DIR"
            for file in /tmp/test_cached_a.bats /tmp/test_cached_b.bats; do
                touch "$BATS_CACHE_DIR/$(bats_cache_key "$file" "$INNER_JOBS" "$BATS_SOURCE_FINGERPRINT").pass"
            done
            run_bats_files_parallel /tmp/test_cached_a.bats /tmp/test_cached_b.bats
        ' _ "$ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: 2 bats file(s) (0 run, 2 cached)"* ]]
    [[ "$output" != *"unbound variable"* ]]
    [ ! -e "$marker" ]
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

# test_necessity: cmd_4175 grounds git_pre_commit's affected_tests dominant term (台帳実測
# mean=113s/max=1303s) by splitting queue-wait from execution. Metrics must stay opt-in so
# direct/unrelated wrapper callers (this suite's own 80 other cases, semantic_causal_post_clear.sh)
# never write into the shared ledger by accident, and both events must land with correct wall_ms.
@test "wrapper: SHOGUN_HEAVY_JOB_ADMISSION_METRICS=1 records queue_wait and execution; unset writes nothing" {
    local ledger="$TMP/defense_overhead.jsonl"

    run env -u SHOGUN_HEAVY_JOB_ADMISSION_METRICS DEFENSE_OVERHEAD_LEDGER="$ledger" bash "$WRAPPER" -- bash -c 'exit 0'
    [ "$status" -eq 0 ]
    [ ! -e "$ledger" ]

    run env SHOGUN_HEAVY_JOB_ADMISSION_METRICS=1 DEFENSE_OVERHEAD_LEDGER="$ledger" \
        bash "$WRAPPER" -- bash -c 'sleep 1; exit 0'
    [ "$status" -eq 0 ]
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ "$(wc -l <"$ledger" 2>/dev/null || echo 0)" -ge 2 ] && break
        sleep 0.05
    done
    [ "$(wc -l <"$ledger")" -eq 2 ]
    run grep -c '"check_id":"queue_wait"' "$ledger"
    [ "$output" -eq 1 ]
    run grep -c '"check_id":"execution"' "$ledger"
    [ "$output" -eq 1 ]
    run python3 -c "
import json
rows = [json.loads(l) for l in open('$ledger')]
exec_row = next(r for r in rows if r['check_id'] == 'execution')
assert exec_row['source'] == 'heavy_job_admission'
assert exec_row['verdict'] == 'PASS'
assert exec_row['wall_ms'] >= 900, exec_row['wall_ms']
"
    [ "$status" -eq 0 ]
}
