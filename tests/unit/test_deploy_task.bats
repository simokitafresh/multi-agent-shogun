#!/usr/bin/env bats
# test_necessity: deploy_taskはtask identity・scope・AC契約を欠く配備をBLOCKし、他忍者taskや既存任務を上書きしない。
# test_deploy_task.bats — deploy_task.sh --yaml モード鮮度チェックのユニットテスト
# AC1: スクリプトがYAML作成後にcommit → WARN表示
# AC2: スクリプトがYAML作成前にcommit → WARN非表示

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

# The suite setup already sources deploy_task.sh once per Bats process. Keep
# each cached-library call isolated while avoiding a second parse of the
# 10k-line shell library in every small contract test.
run_cached_deploy_task() {
    (
        export DEPLOY_TASK_LIB_ONLY=1
        export DEPLOY_TASK_SKIP_REPORT_NORMALIZE=1
        export DEPLOY_TASK_SKIP_BINARY_CHECK_WAIVERS=1
        SCRIPT_DIR="$TEST_PROJECT"
        "$@"
    )
}

run_cached_experiment_first_principle() {
    run_cached_deploy_task inject_experiment_first_principle "$1"
    run_cached_deploy_task inject_experiment_first_principle "$1"
}

run_cached_model_profile() {
    local task="$1" ninja="$2" model="$3"
    (
        export DEPLOY_TASK_LIB_ONLY=1
        export DEPLOY_TASK_SKIP_REPORT_NORMALIZE=1
        export DEPLOY_TASK_SKIP_BINARY_CHECK_WAIVERS=1
        SCRIPT_DIR="$TEST_PROJECT"
        cli_model_display() { echo "$model"; }
        inject_model_injection_profile "$task" "$ninja"
    )
}

run_cached_report_template() {
    run_cached_deploy_task generate_report_template "$@"
}

run_post_deploy_ac_warning() {
    run bash -c '
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        deploy_task_warn_post_deploy_ac "$2" "${3:-}"
    ' _ "$TEST_PROJECT" "$1" "${2:-}"
}

# test_necessity: 配備入口が本番観測ACを家老post_deploy_checkへ戻し、ローカル検証ACを誤警告しない不変量を守る。
@test "production observation AC warns with Karo post-deploy routing" {
    local task="$BATS_TEST_TMPDIR/production-ac-task.yaml"
    cat > "$task" <<'EOF'
task:
  acceptance_criteria:
  - id: AC1
    description: "実装後にRenderのdeploy後live endpointをCDPで確認する"
EOF

    run_post_deploy_ac_warning "$task"
    [ "$status" -eq 0 ]
    [ "$(grep -c 'WARNING: post_deploy_ac' <<< "$output")" -eq 1 ]
    [[ "$output" == *"post_deploy_check Karo lane"* ]]
}

# test_necessity: pytest/TestClient/next build+start/local curl/diff0だけのworker検証をproduction proofへ誤分類しない不変量を守る。
@test "local verification AC does not warn as post-deploy proof" {
    local task="$BATS_TEST_TMPDIR/local-ac-task.yaml"
    cat > "$task" <<'EOF'
task:
  acceptance_criteria:
  - id: AC1
    description: "pytestとTestClientを実行し、next build && next startへlocal curlしてdiff0を確認する"
EOF

    run_post_deploy_ac_warning "$task"
    [ "$status" -eq 0 ]
    [ "$(grep -c 'WARNING: post_deploy_ac' <<< "$output")" -eq 0 ]
}

# test_necessity: 全taskが殿の実験ファースト原文と一次確認の適用形をLevel5で受け取る不変量を守る。
@test "all tasks receive experiment-first principle exactly once" {
    local task="$BATS_TEST_TMPDIR/experiment-first-task.yaml"
    printf 'task:\n  parent_cmd: cmd_test\n  status: assigned\n' > "$task"
    run run_cached_experiment_first_principle "$task"
    [ "$status" -eq 0 ]
    run env TASK_FILE="$task" python3 - <<'PY'
import os
import yaml
with open(os.environ['TASK_FILE'], encoding='utf-8') as f:
    values = (yaml.safe_load(f) or {})['task'].get('experiment_first_principle', [])
original = '殿の原文: 『LLMは人間ではない。考えることは向いてない。膨大な量の実験を超速で回し続ける総当たりが構造的に有効だ』'
assert values.count(original) == 1, values
assert len(values) == 2, values
for required in ('仮説を頭で絞らず', '並列に全て試せ', '想像で結論せず', '一次結果を確認'):
    assert required in values[1], values
PY
    [ "$status" -eq 0 ]
}

# test_necessity: 全忍者taskが共有worktreeの無関係diff/FAILを任務判定へ混入させない所有scope検証契約を自動受領する不変量を守る。
@test "model profile injects task-owned validation contract" {
    local task="$BATS_TEST_TMPDIR/two-stage-task.yaml"
    printf 'task:\n  parent_cmd: cmd_test\n  status: assigned\n' > "$task"
    run run_cached_model_profile "$task" saizo GPT
    [ "$status" -eq 0 ]
    run grep -F '任務帰属検証契約:' "$task"
    [ "$status" -eq 0 ]
    run grep -F 'scope外FAILを当該任務のFAILへ混入させない' "$task"
    [ "$status" -eq 0 ]
}

# test_necessity: 全モデルの個別taskが所有scopeだけを検証し、unit全量をwave共有checkpointへ一回だけ集約する不変量を守る。
@test "model profile injects task-owned validation and shared unit checkpoint for every model" {
    local task="$BATS_TEST_TMPDIR/two-stage-regression-task.yaml"
    for model in GPT Sonnet Opus; do
        printf 'task:\n  parent_cmd: cmd_test\n  status: assigned\n' > "$task"
        run run_cached_model_profile "$task" kotaro "$model"
        [ "$status" -eq 0 ]
        [ "$(grep -Fc 'run_tests.sh task queue/tasks/kotaro.yaml' "$task")" -eq 1 ]
        [ "$(grep -Fc 'run_tests.sh unit全量' "$task")" -eq 1 ]
        [ "$(grep -Fc 'wave最終checkpointで共有1回' "$task")" -eq 1 ]
        [ "$(grep -Fc '報告直前=bash scripts/run_tests.sh unit' "$task")" -eq 0 ]
    done
}

# test_necessity: LG083(GPT忍者のhook_failures.details文字列形式FAIL頻発)の防御として、
# GPT系(intensity=max)忍者taskへhook_failures.detailsのmapping6キー(review_bundle.pyの実fail-closed契約)の明示指示がextra_scaffold経由で注入される不変量を守る。
@test "model profile injects hook_failures.details mapping guidance for max intensity" {
    local task="$BATS_TEST_TMPDIR/hook-failures-mapping-task.yaml"
    printf 'task:\n  parent_cmd: cmd_test\n  status: assigned\n' > "$task"
    run run_cached_model_profile "$task" saizo GPT
    [ "$status" -eq 0 ]
    run grep -F 'extra_scaffold:' "$task"
    [ "$status" -eq 0 ]
    for key in cause independent_verification bypass_record post_verification post_verification_result post_verification_head; do
        run grep -F "$key" "$task"
        [ "$status" -eq 0 ]
    done
    run grep -F '7-40' "$task"
    [ "$status" -eq 0 ]
    run grep -F 'LG083' "$task"
    [ "$status" -eq 0 ]
}

# test_necessity: Opus等(intensity!=max)の忍者にはextra_scaffold自体が不要のため、
# hook_failures mapping guidanceも注入されない不変量を守る(過剰注入を防ぐ)。
@test "model profile omits hook_failures.details mapping guidance for non-max intensity" {
    local task="$BATS_TEST_TMPDIR/hook-failures-mapping-opus-task.yaml"
    printf 'task:\n  parent_cmd: cmd_test\n  status: assigned\n' > "$task"
    run run_cached_model_profile "$task" saizo Opus
    [ "$status" -eq 0 ]
    run grep -F 'extra_scaffold:' "$task"
    [ "$status" -eq 1 ]
    run grep -F 'LG083' "$task"
    [ "$status" -eq 1 ]
}

# test_necessity: 配備前CTX判定はキャッシュ(@context_pct)でなく直前pane captureを正本にする不変量を守る。
@test "ctx guard derives before value from pane capture" {
    run bash -c '
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        tmux() {
            case "$1" in
                show-options) printf "99\n" ;;
                capture-pane) printf "OpenAI Codex Context 12%% used\n" ;;
            esac
        }
        deploy_task_capture_ctx_pct pane sasuke
    ' _ "$TEST_PROJECT"
    [ "$status" -eq 0 ]
    [ "$output" = "12" ]
}

# test_necessity: 閾値以下の配備はrespawnせず、receipt identity付きの二値telemetryを1行残す不変量を守る。
@test "ctx guard records threshold-below without respawn" {
    run bash -c '
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        CTX_LOG="$2/ctx.log"
        log() { printf "%s\n" "$1" >> "$CTX_LOG"; }
        tmux() { [ "$1" = capture-pane ] && printf "Claude Code CTX:12%%\n"; }
        deploy_task_respawn_agent() { printf "unexpected\n" >> "$CTX_LOG"; return 1; }
        DEPLOY_TASK_CTX_RECEIPT_ID=receipt-below
        deploy_task_guard_ctx_before_deploy pane sasuke
        grep -q "CTX_GUARD receipt_id=receipt-below.*ctx_before=12.*ctx_after=12.*result=threshold_below" "$CTX_LOG"
    ' _ "$TEST_PROJECT" "$TEST_PROJECT"
    [ "$status" -eq 0 ]
}

# test_necessity: task_mutationsの全体wallと計装済みsub-phaseを同一receiptへ
# 突合し、未帰属時間と最大sub-phaseを次の高速化判断へ渡す不変量を守る。
@test "mutation accounting emits one receipt with residual and max subphase" {
    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        LOG="$2/mutation-accounting.log"
        now=${EPOCHREALTIME/./}
        now=${now:0:16}
        DEPLOY_TASK_STARTED_US="$now"
        DEPLOY_TASK_WALL_PHASE_LAST_US="$now"
        DEPLOY_TASK_PHASE=task_mutations
        deploy_task_mutation_phase probe bash -c ":"
        deploy_task_wall_phase_checkpoint task_mutations
        log "DEPLOY_RECEIPT result=success"
        [ "$(grep -c "DEPLOY_RECEIPT " "$LOG")" -eq 1 ]
        receipt=$(grep "DEPLOY_RECEIPT " "$LOG")
        [[ "$receipt" == *"unaccounted_ms="* ]]
        [[ "$receipt" == *"max_sub_phase=probe"* ]]
        [[ "$receipt" == *"max_sub_phase_ms="* ]]
    ' _ "$PROJECT_ROOT" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

# test_necessity: heredocを含むworktree準備処理もtask_mutationsの最上位phaseとして
# DEPLOY_RECEIPTの帰属時間・最大phaseへ必ず反映する不変量を守る。
@test "heredoc worktree preparation is an accounted mutation phase" {
    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        LOG="$2/worktree-accounting.log"
        deploy_task_original_log() { printf "%s\\n" "$1" >> "$LOG"; }
        deploy_task_original_prepare_remote_tip_worktree() { sleep 0.01; }
        now=${EPOCHREALTIME/./}
        now=${now:0:16}
        DEPLOY_TASK_STARTED_US="$now"
        DEPLOY_TASK_WALL_PHASE_LAST_US="$now"
        DEPLOY_TASK_PHASE=task_mutations
        deploy_task_prepare_remote_tip_worktree ignored ignored
        deploy_task_wall_phase_checkpoint task_mutations
        log "DEPLOY_RECEIPT result=success"
        [ "$(grep -c "DEPLOY_RECEIPT " "$LOG")" -eq 1 ]
        receipt=$(grep "DEPLOY_RECEIPT " "$LOG")
        [[ "$receipt" == *"unaccounted_ms="* ]]
        [[ "$receipt" == *"max_sub_phase=deploy_task_prepare_remote_tip_worktree"* ]]
        [[ "$receipt" == *"max_sub_phase_ms="* ]]
        unaccounted_ms=${receipt##*unaccounted_ms=}
        unaccounted_ms=${unaccounted_ms%% *}
        [ "$unaccounted_ms" -lt 1000 ]
        phase_ms=$(sed -n "s/.*phase=deploy_task_prepare_remote_tip_worktree wall_ms=\\([0-9][0-9]*\\).*/\\1/p" "$LOG")
        receipt_ms=${receipt##*max_sub_phase_ms=}
        [ "$phase_ms" -eq "$receipt_ms" ]
    ' _ "$PROJECT_ROOT" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
}

# test_necessity: 同一taskの未publish active worktreeを再利用し、remote lookup/fetchと
# checkoutを再実行せず、既存の安全なidentity境界を満たした場合だけ高速経路へ進む不変量を守る。
@test "active unpublished task worktree is reused after identity validation" {
    local repo_root="$BATS_TEST_TMPDIR/reuse-repo"
    local task="$BATS_TEST_TMPDIR/reuse-task.yaml"
    local marker="$BATS_TEST_TMPDIR/reuse-marker.json"
    mkdir -p "$repo_root"
    git init -q "$repo_root"
    git -C "$repo_root" config user.email test@example.invalid
    git -C "$repo_root" config user.name test
    printf 'base\n' > "$repo_root/README"
    git -C "$repo_root" add README
    git -C "$repo_root" -c user.email=test@example.invalid -c user.name=test commit -qm base
    local base
    base=$(git -C "$repo_root" rev-parse HEAD)
    git -C "$repo_root" worktree add -q --detach "$BATS_TEST_TMPDIR/reuse-wt" "$base"
    mkdir -p "$(dirname "$marker")"
    python3 - "$marker" "$repo_root" "$BATS_TEST_TMPDIR/reuse-wt" "$base" <<'PY'
import json
import sys

path, repo, worktree, base = sys.argv[1:]
json.dump({
    "version": 1,
    "state": "active",
    "task_id": "task_reuse",
    "parent_cmd": "cmd_reuse",
    "repo": repo,
    "worktree": worktree,
    "remote_tip": base,
    "published_commit": "",
}, open(path, "w", encoding="utf-8"))
PY
    printf 'task:\n  task_id: task_reuse\n  parent_cmd: cmd_reuse\n  task_worktree_required: true\n  task_worktree_status: active\n  task_worktree_path: %s\n  task_worktree_repo: %s\n  task_worktree_marker: %s\n  task_worktree_base: %s\n' \
        "$BATS_TEST_TMPDIR/reuse-wt" "$repo_root" "$marker" "$base" > "$task"

    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        log() { printf "%s\n" "$1"; }
        deploy_task_original_prepare_remote_tip_worktree() {
            printf "unexpected-original-path\n"
            return 99
        }
        DEPLOY_TASK_PHASE=task_mutations
        deploy_task_prepare_remote_tip_worktree "$2" hayate
    ' _ "$PROJECT_ROOT" "$task"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TASK_WORKTREE_REUSED: ninja=hayate task=task_reuse"* ]]
    [[ "$output" == *"TASK_MUTATION_PHASE phase=deploy_task_prepare_remote_tip_worktree"* ]]
    [[ "$output" != *"unexpected-original-path"* ]]
}

# test_necessity: 高CTX配備は正規respawnとready確認を経てからのみ成功し、ctx_before/afterを同一receiptへ記録する不変量を守る。
@test "ctx guard respawns high-ctx idle worker and confirms ready" {
    run bash -c '
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        CTX_LOG="$2/ctx.log"
        log() { printf "%s\n" "$1" >> "$CTX_LOG"; }
        CTX_CAPTURE="OpenAI Codex Context 35% used"
        tmux() { [ "$1" = capture-pane ] && printf "%s\n" "$CTX_CAPTURE"; }
        deploy_task_respawn_agent() {
            printf "respawn:%s:%s\n" "$1" "$2" >> "$CTX_LOG"
            CTX_CAPTURE="OpenAI Codex Context 0% used"
        }
        deploy_task_wait_respawn_ready() { return 0; }
        DEPLOY_TASK_CTX_RECEIPT_ID=receipt-success
        deploy_task_guard_ctx_before_deploy pane sasuke
        grep -q "respawn:sasuke:deploy_ctx_guard_35pct" "$CTX_LOG"
        grep -q "CTX_GUARD receipt_id=receipt-success.*ctx_before=35.*ctx_after=0.*result=respawn_success" "$CTX_LOG"
    ' _ "$TEST_PROJECT" "$TEST_PROJECT"
    [ "$status" -eq 0 ]
}

# test_necessity: respawn失敗/ready timeoutはtask/report/inbox公開前にBLOCKし、原因別telemetryを残す不変量を守る。
@test "ctx guard blocks respawn failure and ready timeout" {
    run bash -c '
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        CTX_LOG="$2/ctx.log"
        log() { printf "%s\n" "$1" >> "$CTX_LOG"; }
        CTX_CAPTURE="Claude Code CTX:40%"
        tmux() { [ "$1" = capture-pane ] && printf "%s\n" "$CTX_CAPTURE"; }
        DEPLOY_TASK_CTX_RECEIPT_ID=receipt-failure
        deploy_task_respawn_agent() { return 1; }
        ! deploy_task_guard_ctx_before_deploy pane sasuke
        grep -q "CTX_GUARD receipt_id=receipt-failure.*result=respawn_failed" "$CTX_LOG"
        deploy_task_respawn_agent() { return 0; }
        deploy_task_wait_respawn_ready() { return 1; }
        DEPLOY_TASK_CTX_RECEIPT_ID=receipt-timeout
        ! deploy_task_guard_ctx_before_deploy pane sasuke
        grep -q "CTX_GUARD receipt_id=receipt-timeout.*result=ready_timeout" "$CTX_LOG"
    ' _ "$TEST_PROJECT" "$TEST_PROJECT"
    [ "$status" -eq 0 ]
}

# test_necessity: report template(hook_failures block)にmapping6キー(review_bundle.pyの実fail-closed契約。
# post_verification_head込み)の記入例がコメントとして常設され、count>0発生時にGPT忍者以外(非max注入対象)も
# 正しい形式を確認できる不変量を守る。
@test "report template hook_failures block carries mapping example with 6 keys" {
    local task="$TEST_PROJECT/queue/tasks/sasuke.yaml"
    cat > "$task" <<'YAML'
task:
  parent_cmd: cmd_hook_failures_template
  task_id: cmd_hook_failures_template_normal
  task_type: normal
  project: infra
  report_filename: sasuke_report_cmd_hook_failures_template.yaml
  acceptance_criteria:
  - id: AC1
    description: check
YAML
    run run_cached_report_template sasuke cmd_hook_failures_template_normal cmd_hook_failures_template infra "$task"
    [ "$status" -eq 0 ]
    local report="$TEST_PROJECT/queue/reports/sasuke_report_cmd_hook_failures_template.yaml"
    run grep -F 'hook_failures:' "$report"
    [ "$status" -eq 0 ]
    for key in cause independent_verification bypass_record post_verification post_verification_result post_verification_head; do
        run grep -F "$key" "$report"
        [ "$status" -eq 0 ]
    done
    run grep -F '7-40' "$report"
    [ "$status" -eq 0 ]
    run grep -F 'LG083' "$report"
    [ "$status" -eq 0 ]
}

setup() {
    deploy_task_scaffold "deploy_yaml_freshness"
}

# test_necessity: 再利用taskの世代境界で前taskのci_run_id/final_checkpointを
# 新taskへ漏らさず、明示された新taskの値だけを2/2保持する不変量を守る。
@test "reset_stale_fields clears predecessor terminal fields and preserves explicit replacement values" {
    local file="$TEST_PROJECT/queue/tasks/sasuke.yaml"
    cat > "$file" <<'YAML'
task:
  parent_cmd: cmd_previous
  task_id: cmd_previous_normal
  ci_run_id: 4354
  final_checkpoint:
    result: PASS
    head: abc1234
YAML

    SCRIPT_DIR="$TEST_PROJECT"
    DIRECT_MODE=false
    CMD_ID="cmd_current"
    run reset_stale_fields sasuke
    [ "$status" -eq 0 ]
    run python3 - "$file" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]
assert sum(key in task for key in ("ci_run_id", "final_checkpoint")) == 0, task
PY
    [ "$status" -eq 0 ]

    # The replacement source is explicit; after stale reset, both values must
    # survive source publication exactly as supplied.
    printf '\n' >> "$file"
    cat >> "$file" <<'YAML'
  ci_run_id: 9001
  final_checkpoint:
    result: PASS
    head: fedcba9
YAML
    run python3 - "$file" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]
assert task["ci_run_id"] == 9001, task
assert task["final_checkpoint"] == {"result": "PASS", "head": "fedcba9"}, task
print("explicit_terminal_fields=2/2")
PY
    [ "$status" -eq 0 ]
}

# Reuse the library parsed by deploy_task_scaffold in Bats' isolated `run`
# subshell. Re-sourcing the ~10k-line script for every table row dominated
# these contract tests without adding an independent oracle.
generate_report_template_fast() {
    SCRIPT_DIR="$TEST_PROJECT"
    generate_report_template "$@"
}

# test_necessity: reportのcommit要否はtask明示契約をSSOTとし、欠落時だけ既存type/path推論へfallbackする不変量を守る。
@test "report commit contract inherits explicit task value and falls back only when absent" {
    use_private_scripts_fixture
    local -a pids=() cases=()

    check_case() {
        local name="$1" required_line="$2" task_type="$3" target_path="$4" expected="$5"
        local task="$TEST_PROJECT/queue/tasks/sasuke_${name}.yaml"
        {
            printf 'task:\n  parent_cmd: %s\n  task_id: %s_normal\n  task_type: %s\n  project: infra\n  report_filename: sasuke_report_%s.yaml\n' "$name" "$name" "$task_type" "$name"
            [ -z "$required_line" ] || printf '  commit_contract:\n    required: %s\n    push_allowed: false\n' "$required_line"
            printf '  target_path: %s\n  acceptance_criteria:\n  - id: AC1\n    description: check\n' "$target_path"
        } > "$task"
        generate_report_template_fast sasuke "${name}_normal" "$name" infra "$task" \
            >"$TEST_TMPDIR/${name}.out" 2>&1 &
        pids+=("$!")
        cases+=("$task:$expected")
    }

    check_case explicit_false false recon2 scripts/tool.sh false
    check_case explicit_true true normal docs/design.md true
    check_case missing_code "" normal scripts/tool.sh true
    check_case missing_readonly "" recon2 docs/evidence.md false
    check_case quoted_false "'false'" recon2 scripts/tool.sh false

    local pid case_entry task expected
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    for case_entry in "${cases[@]}"; do
        task="${case_entry%:*}"
        expected="${case_entry##*:}"
        env TASK="$task" ROOT="$TEST_PROJECT" EXPECTED="$expected" python3 - <<'PY'
import os, yaml
task = yaml.safe_load(open(os.environ["TASK"], encoding="utf-8"))["task"]
report = yaml.safe_load(open(os.path.join(os.environ["ROOT"], task["report_path"]), encoding="utf-8"))
assert report["commit_contract"]["required"] is (os.environ["EXPECTED"] == "true"), report
PY
    done
}

# test_necessity: variation_checks_requiredはinfra enforcement変更だけに付与し、非infra本文のgate/hook言及を偽陽性にしない不変量を守る。
@test "variation contract requires infra project and enforcement code change" {
    use_private_scripts_fixture
    local -a pids=() cases=()

    check_variation_case() {
        local name="$1" project="$2" purpose="$3" expected="$4"
        local task="$TEST_PROJECT/queue/tasks/sasuke_${name}.yaml"
        cat > "$task" <<YAML
task:
  parent_cmd: cmd_${name}
  task_id: cmd_${name}_normal
  task_type: normal
  project: ${project}
  purpose: "${purpose}"
  report_filename: sasuke_report_cmd_${name}.yaml
  acceptance_criteria:
  - id: AC1
    description: boundary contract
YAML
        generate_report_template_fast sasuke "cmd_${name}_normal" "cmd_${name}" "$project" "$task" \
            >"$TEST_TMPDIR/${name}.out" 2>&1 &
        pids+=("$!")
        cases+=("$task:$expected")
    }

    check_variation_case product_gate dm-signal \
        "metrics UIを修正しgate/hook変更ではないことを確認する" false
    check_variation_case infra_gate infra \
        "scripts/gates/example.shのenforcement hookを修正する" true
    check_variation_case infra_normal infra \
        "通常のREADME説明文を更新する" false

    local pid case_entry task expected
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    for case_entry in "${cases[@]}"; do
        task="${case_entry%:*}"
        expected="${case_entry##*:}"
        env TASK="$task" EXPECTED="$expected" python3 - <<'PY'
import os
import yaml

task = yaml.safe_load(open(os.environ["TASK"], encoding="utf-8"))["task"]
assert task["variation_checks_required"] is (os.environ["EXPECTED"] == "true"), task
PY
    done
}

teardown() {
    deploy_task_teardown
    if [ -n "${TEST_GIT_ROOT:-}" ] && [ -d "$TEST_GIT_ROOT" ]; then
        rm -rf "$TEST_GIT_ROOT"
    fi
}

run_yaml_freshness_check() {
    local yaml_file="$1"
    local git_root="$2"
    (
        export DEPLOY_TASK_LIB_ONLY=1
        # shellcheck disable=SC1090,SC1091
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        check_yaml_freshness "$yaml_file" "$git_root"
    ) 2>&1
}

setup_git_fixture() {
    export TEST_GIT_ROOT
    TEST_GIT_ROOT="$(mktemp -d "$BATS_TMPDIR/test_git_root.XXXXXX")"
    git -C "$TEST_GIT_ROOT" init --quiet
    git -C "$TEST_GIT_ROOT" config user.name "Test User"
    git -C "$TEST_GIT_ROOT" config user.email "test@example.com"
    mkdir -p "$TEST_GIT_ROOT/scripts"
}

make_script_commit() {
    local rel_path="$1"
    local commit_date="$2"

    mkdir -p "$TEST_GIT_ROOT/$(dirname "$rel_path")"
    printf '#!/usr/bin/env bash\n# test script\n' > "$TEST_GIT_ROOT/$rel_path"
    git -C "$TEST_GIT_ROOT" add "$rel_path"
    GIT_AUTHOR_DATE="$commit_date" GIT_COMMITTER_DATE="$commit_date" \
        git -C "$TEST_GIT_ROOT" commit --quiet -m "cmd_test update script"
}

use_private_scripts_fixture() {
    local shared_scripts

    if [ -L "$TEST_PROJECT/scripts" ]; then
        shared_scripts="$(readlink -f "$TEST_PROJECT/scripts")"
        rm "$TEST_PROJECT/scripts"
        cp -R "$shared_scripts" "$TEST_PROJECT/scripts"
    fi
}

@test "スクリプトがYAML作成後にcommitされていた場合WARNが出力される" {
    setup_git_fixture
    local recent_date
    recent_date="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    make_script_commit "scripts/my_tool.sh" "$recent_date"

    local yaml_file="$TEST_GIT_ROOT/test_task.yaml"
    cat > "$yaml_file" <<'EOF'
task:
  command: "bash scripts/my_tool.sh を実行せよ"
  task_id: cmd_test_impl
EOF
    touch -d "2 hours ago" "$yaml_file"

    run run_yaml_freshness_check "$yaml_file" "$TEST_GIT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DEPLOY] WARN:"* ]]
    [[ "$output" == *"scripts/my_tool.sh"* ]]
    [[ "$output" == *"task YAMLを再作成せよ"* ]]
}

@test "スクリプトがYAML作成前にcommitされていた場合WARNは出力されない" {
    setup_git_fixture
    local old_date
    old_date="$(date -u -d '2 hours ago' '+%Y-%m-%dT%H:%M:%SZ')"
    make_script_commit "scripts/my_tool.sh" "$old_date"

    local yaml_file="$TEST_GIT_ROOT/test_task.yaml"
    cat > "$yaml_file" <<'EOF'
task:
  command: "bash scripts/my_tool.sh を実行せよ"
  task_id: cmd_test_impl
EOF

    run run_yaml_freshness_check "$yaml_file" "$TEST_GIT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" != *"[DEPLOY] WARN:"* ]]
}

@test "HEADに存在しない新規targetはhistory walkせず5秒未満でskipする" {
    setup_git_fixture
    make_script_commit "scripts/existing.sh" "$(date -u -d '2 hours ago' '+%Y-%m-%dT%H:%M:%SZ')"
    local yaml_file="$TEST_GIT_ROOT/new_target_task.yaml"
    cat > "$yaml_file" <<'EOF'
task:
  command: "bash scripts/throughput_growth_loop.sh を新規作成せよ"
EOF
    local started ended
    started="$(date +%s%N)"
    run run_yaml_freshness_check "$yaml_file" "$TEST_GIT_ROOT"
    ended="$(date +%s%N)"
    [ "$status" -eq 0 ]
    [ $(((ended-started)/1000000)) -lt 5000 ]
    [[ "$output" != *"WARN:"* ]]
}

run_path_collision_guard() {
    local task_file="$1" ninja_name="$2"
    run bash -c 'export DEPLOY_TASK_LIB_ONLY=1; source "$1/scripts/deploy_task.sh"; deploy_task_guard_target_path_collision "$2" "$3"' _ "$TEST_PROJECT" "$task_file" "$ninja_name"
}

write_collision_task() {
    local ninja="$1" status="$2" target="$3" planned="$4"
    mkdir -p "$TEST_PROJECT/queue/tasks"
    cat > "$TEST_PROJECT/queue/tasks/${ninja}.yaml" <<EOF
task:
  parent_cmd: cmd_${ninja}
  status: ${status}
  target_path: ${target}
  planned_paths:
  - ${planned}
EOF
}

@test "active tasks with different target_path BLOCK on normalized planned_paths overlap" {
    write_collision_task sasuke in_progress scripts/a.sh tests/unit/shared.bats
    write_collision_task hanzo assigned scripts/b.sh ./tests/unit/../unit/shared.bats

    run_path_collision_guard "$TEST_PROJECT/queue/tasks/hanzo.yaml" hanzo
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: reserved path collision with sasuke"* ]]
    [[ "$output" == *"tests/unit/shared.bats"* ]]
}

@test "terminal planned_paths release reservation and disjoint active paths pass" {
    local state
    for state in done failed idle; do
        write_collision_task sasuke "$state" scripts/a.sh tests/unit/shared.bats
        write_collision_task hanzo assigned scripts/b.sh tests/unit/shared.bats
        run_path_collision_guard "$TEST_PROJECT/queue/tasks/hanzo.yaml" hanzo
        [ "$status" -eq 0 ]
    done

    write_collision_task sasuke in_progress scripts/a.sh tests/unit/other.bats
    write_collision_task hanzo assigned scripts/b.sh tests/unit/shared.bats
    run_path_collision_guard "$TEST_PROJECT/queue/tasks/hanzo.yaml" hanzo
    [ "$status" -eq 0 ]
}

# test_necessity: GATE CLEAR後にarchive済みのterminal generationは共有pathの
# reservationを解放し、後続writerのdirtyを旧担当へ誤帰属させない。
# regression_justification: 15:59-16:01のreflux配備3試行がarchive済み旧taskの
# queue/insights.yaml予約として全件BLOCKした。
@test "archived terminal owner releases dirty shared path while unarchived owner blocks" {
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_sasuke"
    git -C "$TEST_PROJECT" init -q
    git -C "$TEST_PROJECT" config user.email test@example.invalid
    git -C "$TEST_PROJECT" config user.name test
    printf 'baseline\n' > "$TEST_PROJECT/queue/insights.yaml"
    git -C "$TEST_PROJECT" add queue/insights.yaml
    git -C "$TEST_PROJECT" commit -q -m baseline
    printf 'later writer\n' >> "$TEST_PROJECT/queue/insights.yaml"

    write_collision_task sasuke done scripts/a.sh queue/insights.yaml
    write_collision_task hanzo assigned scripts/b.sh queue/insights.yaml

    run_path_collision_guard "$TEST_PROJECT/queue/tasks/hanzo.yaml" hanzo
    [ "$status" -eq 1 ]
    [[ "$output" == *"status=done/uncommitted"* ]]

    : > "$TEST_PROJECT/queue/gates/cmd_sasuke/archive.done"
    run_path_collision_guard "$TEST_PROJECT/queue/tasks/hanzo.yaml" hanzo
    [ "$status" -eq 0 ]
    [[ "$output" != *"reserved path collision"* ]]
}

# test_necessity: archive解放はterminal generationだけに限定し、active ownerの
# 同一path予約はarchive markerが存在しても解放しない。
@test "archive marker never releases an active owner" {
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_sasuke"
    : > "$TEST_PROJECT/queue/gates/cmd_sasuke/archive.done"
    write_collision_task sasuke in_progress scripts/a.sh queue/insights.yaml
    write_collision_task hanzo assigned scripts/b.sh queue/insights.yaml

    run_path_collision_guard "$TEST_PROJECT/queue/tasks/hanzo.yaml" hanzo
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: reserved path collision with sasuke"* ]]
}

@test "direct prewrite guard BLOCK leaves existing task YAML byte-identical" {
    write_collision_task sasuke in_progress scripts/a.sh tests/unit/shared.bats
    write_collision_task hanzo idle scripts/existing.sh tests/unit/existing.bats
    local before candidate
    before="$(sha256sum "$TEST_PROJECT/queue/tasks/hanzo.yaml" | awk '{print $1}')"
    candidate="$BATS_TEST_TMPDIR/direct-candidate.yaml"
    cat > "$candidate" <<'EOF'
task:
  target_path: scripts/b.sh
  planned_paths:
  - tests/unit/shared.bats
EOF

    run bash -c 'export DEPLOY_TASK_LIB_ONLY=1; source "$1/scripts/deploy_task.sh"; DIRECT_MODE=true; deploy_task_guard_direct_yaml_prewrite_collision "$2" hanzo' _ "$TEST_PROJECT" "$candidate"
    [ "$status" -eq 1 ]
    [ "$(sha256sum "$TEST_PROJECT/queue/tasks/hanzo.yaml" | awk '{print $1}')" = "$before" ]
}

@test "Codex delayed re-nudge sends inboxN directly without inbox_write" {
    mkdir -p "$TEST_PROJECT/queue/inbox"
    cat > "$TEST_PROJECT/queue/inbox/sasuke.yaml" <<'EOF'
messages:
- id: msg_1
  read: false
- id: msg_2
  read: true
- id: msg_3
  read: false
EOF

    (
        export DEPLOY_TASK_LIB_ONLY=1
        # shellcheck disable=SC1090,SC1091
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        pane_lookup() { echo "shogun:agents.2"; }
        # test_necessity: pane evidenceなしのdirect re-nudge契約を実tmux表示から隔離する。
        tmux() { return 1; }
        safe_send_keys_atomic() {
            printf '%s|%s|%s\n' "$1" "$2" "$3" > "$TEST_PROJECT/logs/direct_renudge.log"
        }
        deploy_task_send_direct_renudge sasuke
    )

    run cat "$TEST_PROJECT/logs/direct_renudge.log"
    [ "$status" -eq 0 ]
    [ "$output" = "shogun:agents.2|inbox2|0.3" ]
}

@test "Codex delayed re-nudge ignores read false text inside message content" {
    mkdir -p "$TEST_PROJECT/queue/inbox"
    cat > "$TEST_PROJECT/queue/inbox/sasuke.yaml" <<'EOF'
messages:
- id: msg_1
  content: |
    literal payload:
    read: false
  read: true
- id: msg_2
  content: normal unread
  read: false
EOF

    (
        export DEPLOY_TASK_LIB_ONLY=1
        # shellcheck disable=SC1090,SC1091
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        pane_lookup() { echo "shogun:agents.2"; }
        # test_necessity: message本文中の文字列ではなくYAML read値だけを数える不変量を隔離検証する。
        tmux() { return 1; }
        safe_send_keys_atomic() {
            printf '%s|%s|%s\n' "$1" "$2" "$3" > "$TEST_PROJECT/logs/direct_renudge_literal.log"
        }
        deploy_task_send_direct_renudge sasuke
    )

    run cat "$TEST_PROJECT/logs/direct_renudge_literal.log"
    [ "$status" -eq 0 ]
    [ "$output" = "shogun:agents.2|inbox1|0.3" ]
}

@test "safe_inbox_write continues when message persisted before delivery failure" {
    mkdir -p "$TEST_PROJECT/queue/inbox" "$TEST_PROJECT/logs"
    use_private_scripts_fixture
    cat > "$TEST_PROJECT/queue/inbox/sasuke.yaml" <<'EOF'
messages: []
EOF
cat > "$TEST_PROJECT/scripts/inbox_write.sh" <<'EOF'
#!/usr/bin/env bash
script_dir="${BASH_SOURCE[0]%/scripts/inbox_write.sh}"
inbox="$script_dir/queue/inbox/$1.yaml"
{
  printf 'messages:\n'
  printf -- "- content: '%s'\n" "$2"
  printf "  read: false\n"
} > "$inbox"
echo "[inbox_write] WARN: codex delivery remained unverified" >&2
exit 9
EOF
    chmod +x "$TEST_PROJECT/scripts/inbox_write.sh"

    run bash -c '
        export DEPLOY_TASK_LIB_ONLY=1
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        log() { printf "%s\n" "$1" >> "$TEST_PROJECT/logs/safe_inbox_write.log"; }
        safe_inbox_write sasuke "task assigned" task_assigned karo
    '

    [ "$status" -eq 0 ]
    grep -q "post-write delivery/verification failed" "$TEST_PROJECT/logs/safe_inbox_write.log"
}

@test "safe_inbox_write blocks when message was not persisted" {
    mkdir -p "$TEST_PROJECT/queue/inbox" "$TEST_PROJECT/logs"
    use_private_scripts_fixture
    cat > "$TEST_PROJECT/queue/inbox/sasuke.yaml" <<'EOF'
messages: []
EOF
    cat > "$TEST_PROJECT/scripts/inbox_write.sh" <<'EOF'
#!/usr/bin/env bash
echo "[inbox_write] Failed to acquire lock" >&2
exit 9
EOF
    chmod +x "$TEST_PROJECT/scripts/inbox_write.sh"

    run bash -c '
        export DEPLOY_TASK_LIB_ONLY=1
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        log() { printf "%s\n" "$1" >> "$TEST_PROJECT/logs/safe_inbox_write.log"; }
        safe_inbox_write sasuke "task assigned" task_assigned karo
    '

    [ "$status" -eq 9 ]
    grep -q "failed before persistence" "$TEST_PROJECT/logs/safe_inbox_write.log"
}

@test "deploy_task registers EXIT trap for interrupted nudge delivery" {
    run grep -F "trap deploy_task_exit_cleanup EXIT" "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]
}

@test "resolve_cmd_to_task overwrites stale task cmd_id when assigning new cmd" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_old
  cmd_id: cmd_old
  task_id: cmd_old_full
  status: failed
EOF

    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_new:
    estimated_minutes: 10
    title: "new task"
    project: dm-signal
    scope_mode: FULL
    purpose: "new purpose"
    target_path: /tmp/project
    acceptance_criteria:
      - id: AC1
        description: "new task acceptance criterion"
EOF

    run bash -c '
        export DEPLOY_TASK_LIB_ONLY=1
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        resolve_cmd_to_task cmd_new sasuke
    '
    [ "$status" -eq 0 ]

    run python3 - "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1]))["task"]
print(task.get("parent_cmd"), task.get("cmd_id"), task.get("task_id"), task.get("status"))
PY
    [ "$status" -eq 0 ]
    [ "$output" = "cmd_new cmd_new cmd_new_full assigned" ]
}

@test "cmd_2832: deploy_task_main arms internal cooperative timeout" {
    run grep -F "deploy_task_start_deadline" "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]

    run grep -F "deploy_task_check_deadline \"after_inbox_write\"" "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]

    run grep -F "TIMEOUT: deploy_task_main exceeded" "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]
}

@test "deploy mutation final reads batch canonical and report metadata fields" {
    run python3 - "$PROJECT_ROOT/scripts/deploy_task.sh" <<'PY'
import re
import sys

script = open(sys.argv[1], encoding="utf-8").read()
start = script.index("deploy_task_apply_task_mutations() {")
end = script.index("\n# ═══════════════════════════════════════\n# メイン処理", start)
body = script[start:end]

assert re.search(
    r'field_get_multi "\$task_file" parent_cmd task_type', body
), "canonical training fields must use one YAML scan"
assert re.search(
    r'field_get_multi "\$task_file" task_id _ac_task_id parent_cmd project report_filename',
    body,
), "report metadata must be included in the existing final YAML scan"
assert 'field_get "$task_file" report_filename' not in body
PY
    [ "$status" -eq 0 ]
}

@test "post-deploy verification suppresses duplicate re-nudge for wrapped prompt delivery evidence" {
    mkdir -p "$TEST_PROJECT/queue/inbox" "$TEST_PROJECT/logs"
    cat > "$TEST_PROJECT/queue/inbox/sasuke.yaml" <<'EOF'
messages:
- id: msg_1
  read: false
EOF

    run bash -c '
        export DEPLOY_TASK_LIB_ONLY=1
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        log() { printf "%s\n" "$1" >> "$TEST_PROJECT/logs/post_deploy_verify.log"; }
        tmux() {
            case "$1" in
                list-panes) printf "shogun:agents.2\n" ;;
                show-options) printf "idle\n" ;;
                capture-pane)
                    printf "%s\n" "$@" > "$TEST_PROJECT/logs/post_deploy_capture_args.log"
                    printf "› inbox1 — task: queue/tasks/\nsasuke.yaml\n"
                    for i in $(seq 1 20); do printf "output line %s\n" "$i"; done
                    printf "◦ Running UserPromptSubmit hook\n"
                    ;;
            esac
        }
        deploy_task_send_direct_renudge() {
            printf "%s\n" "$1" > "$TEST_PROJECT/logs/post_deploy_renudge.log"
        }
        deploy_task_post_deploy_verify sasuke
    '

    [ "$status" -eq 0 ]
    [ ! -f "$TEST_PROJECT/logs/post_deploy_renudge.log" ]
    grep -q "delivery evidence present" "$TEST_PROJECT/logs/post_deploy_verify.log"
    grep -q "re-nudge suppressed" "$TEST_PROJECT/logs/post_deploy_verify.log"
    grep -qx -- "-S" "$TEST_PROJECT/logs/post_deploy_capture_args.log"
    grep -qx -- "-30" "$TEST_PROJECT/logs/post_deploy_capture_args.log"
}

@test "post-deploy verification leaves true non-delivery eligible for bounded delayed re-nudge" {
    mkdir -p "$TEST_PROJECT/queue/inbox" "$TEST_PROJECT/logs"
    printf 'messages:\n- id: msg_1\n  read: false\n' > "$TEST_PROJECT/queue/inbox/sasuke.yaml"
    run bash -c '
        export DEPLOY_TASK_LIB_ONLY=1
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        log() { printf "%s\n" "$1" >> "$TEST_PROJECT/logs/post_deploy_missing.log"; }
        pane_lookup() { echo "shogun:agents.2"; }
        tmux() { case "$1" in show-options) printf "idle\n" ;; capture-pane) printf "Codex initial screen\n" ;; esac; }
        deploy_task_send_direct_renudge() { printf "unexpected\n" > "$TEST_PROJECT/logs/unexpected.log"; }
        deploy_task_post_deploy_verify sasuke
    '
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_PROJECT/logs/unexpected.log" ]
    grep -q "bounded delayed re-nudge eligible" "$TEST_PROJECT/logs/post_deploy_missing.log"
}

@test "delayed re-nudge rechecks pane evidence immediately before send" {
    mkdir -p "$TEST_PROJECT/queue/inbox" "$TEST_PROJECT/logs"
    printf 'messages:\n- id: msg_1\n  read: false\n' > "$TEST_PROJECT/queue/inbox/sasuke.yaml"
    run bash -c '
        export DEPLOY_TASK_LIB_ONLY=1
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        log() { printf "%s\n" "$1" >> "$TEST_PROJECT/logs/delayed.log"; }
        pane_lookup() { echo "shogun:agents.2"; }
        tmux() {
            printf "%s\n" "$@" > "$TEST_PROJECT/logs/delayed_capture_args.log"
            printf "• Working\n"
            for i in $(seq 1 20); do printf "output line %s\n" "$i"; done
        }
        safe_send_keys_atomic() { printf "sent\n" > "$TEST_PROJECT/logs/sent.log"; }
        deploy_task_send_direct_renudge sasuke
    '
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_PROJECT/logs/sent.log" ]
    grep -q "delivery evidence present" "$TEST_PROJECT/logs/delayed.log"
    grep -qx -- "-S" "$TEST_PROJECT/logs/delayed_capture_args.log"
    grep -qx -- "-30" "$TEST_PROJECT/logs/delayed_capture_args.log"
}

@test "delayed re-nudge skips when unread was consumed before send" {
    mkdir -p "$TEST_PROJECT/queue/inbox" "$TEST_PROJECT/logs"
    printf 'messages:\n- id: msg_1\n  read: true\n' > "$TEST_PROJECT/queue/inbox/sasuke.yaml"
    run bash -c '
        export DEPLOY_TASK_LIB_ONLY=1
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        log() { printf "%s\n" "$1" >> "$TEST_PROJECT/logs/delayed_read.log"; }
        pane_lookup() { echo "shogun:agents.2"; }
        tmux() { printf "initial screen\n"; }
        safe_send_keys_atomic() { printf "sent\n" > "$TEST_PROJECT/logs/sent.log"; }
        deploy_task_send_direct_renudge sasuke
    '
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_PROJECT/logs/sent.log" ]
    grep -q "no unread messages" "$TEST_PROJECT/logs/delayed_read.log"
}

@test "cmd_2832: report gawk scan avoids global all-ninja glob" {
    run grep -F '"$SCRIPT_DIR/queue/reports/"*_report_*.yaml' "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -ne 0 ]

    run grep -F '"$SCRIPT_DIR/queue/reports/${ninja_name}_report_"*.yaml' "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]

    run grep -F '"$SCRIPT_DIR/queue/reports/"*"_report_${_p_parent_cmd}.yaml"' "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]
}

@test "deploy_task EXIT trap sends pending nudge once when armed" {
    mkdir -p "$TEST_PROJECT/logs"

    run bash -c '
        export DEPLOY_TASK_LIB_ONLY=1
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        log() { printf "%s\n" "$1" >> "$TEST_PROJECT/logs/exit_nudge.log"; }
        safe_inbox_write() {
            printf "%s|%s|%s|%s\n" "$1" "$2" "$3" "$4" >> "$TEST_PROJECT/logs/exit_nudge_send.log"
        }
        NINJA_NAME=sasuke
        MESSAGE="task assigned"
        TYPE=task_assigned
        FROM=karo
        DEPLOY_TASK_EXIT_NUDGE_ARMED=1
        DEPLOY_TASK_EXIT_NUDGE_SENT=0
        deploy_task_exit_nudge
        deploy_task_exit_nudge
    '

    [ "$status" -eq 0 ]
    run wc -l "$TEST_PROJECT/logs/exit_nudge_send.log"
    [ "$status" -eq 0 ]
    [ "${output##* }" = "$TEST_PROJECT/logs/exit_nudge_send.log" ]
    [[ "$output" == "1 "* ]]
    run cat "$TEST_PROJECT/logs/exit_nudge_send.log"
    [ "$output" = "sasuke|task assigned|task_assigned|karo" ]
}

@test "deploy_task EXIT trap skips after main nudge marked sent" {
    mkdir -p "$TEST_PROJECT/logs"

    run bash -c '
        export DEPLOY_TASK_LIB_ONLY=1
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        log() { :; }
        safe_inbox_write() {
            printf "%s|%s|%s|%s\n" "$1" "$2" "$3" "$4" >> "$TEST_PROJECT/logs/exit_nudge_send.log"
        }
        NINJA_NAME=sasuke
        MESSAGE="task assigned"
        TYPE=task_assigned
        FROM=karo
        DEPLOY_TASK_EXIT_NUDGE_ARMED=1
        DEPLOY_TASK_EXIT_NUDGE_SENT=1
        deploy_task_exit_nudge
    '

    [ "$status" -eq 0 ]
    [ ! -f "$TEST_PROJECT/logs/exit_nudge_send.log" ]
}

@test "cmd_2974: deploy_task arms EXIT nudge before post-mutation deadline check" {
    mkdir -p "$TEST_PROJECT/logs"
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_type: exact
  status: idle
EOF

    run bash -c '
        set -euo pipefail
        fixture_root="$1"
        export DEPLOY_TASK_LIB_ONLY=1
        source "$fixture_root/scripts/deploy_task.sh"
        log() { printf "%s\n" "$1" >> "$fixture_root/logs/exit_after_mutation.log"; }
        resolve_pane() { echo "test-pane"; }
        get_ctx_pct() { echo 0; }
        check_idle() { return 0; }
        deploy_task_validate_cli_target() { return 0; }
        normalize_task_yaml() { :; }
        repair_training_parent_cmd_from_cmd_id() { :; }
        deploy_task_has_pending_own_report() { return 1; }
        capture_done_redeploy_context() { :; }
        reset_stale_fields() { _STALE_RESET_DONE=1; }
        inject_training_target_path_from_alias_quality() { :; }
        inject_direct_training_template() { :; }
        warn_same_ninja_redeploy() { :; }
        deploy_task_has_completed_peer_report() { return 1; }
        check_firefighting_title() { :; }
        warn_task_clarity() { :; }
        warn_recent_noncmd_commit_targets() { :; }
        deploy_task_apply_task_mutations() {
            printf "mutated\n" >> "$fixture_root/logs/exit_after_mutation.log"
            deploy_task_ensure_fallback_report_metadata "$task_yaml" "$NINJA_NAME" "$CMD_ID"
        }
        deploy_task_check_deadline() {
            if [ "${1:-}" = "after_task_mutations" ]; then
                return 1
            fi
            return 0
        }
        safe_inbox_write() {
            printf "%s|%s|%s|%s\n" "$1" "$2" "$3" "$4" >> "$fixture_root/logs/exit_after_mutation_send.log"
        }
        deploy_task_main --direct sasuke cmd_2974
    ' _ "$TEST_PROJECT"

    [ "$status" -eq 1 ]
    grep -q "mutated" "$TEST_PROJECT/logs/exit_after_mutation.log"
    grep -q "EXIT trap sending inbox_write" "$TEST_PROJECT/logs/exit_after_mutation.log"
    run cat "$TEST_PROJECT/logs/exit_after_mutation_send.log"
    [ "$status" -eq 0 ]
    [[ "$output" == sasuke\|*queue/tasks/sasuke.yaml* ]]
    [[ "$output" == *"|task_assigned|karo" ]]

    TASK_FILE="$TEST_PROJECT/queue/tasks/sasuke.yaml" python3 - <<'PY'
import os
from pathlib import Path

import yaml

task_path = Path(os.environ["TASK_FILE"])
task = yaml.safe_load(task_path.read_text(encoding="utf-8"))["task"]

assert task.get("report_filename") == "sasuke_report_cmd_2974.yaml", task
assert task.get("report_path") == "queue/reports/sasuke_report_cmd_2974.yaml", task
assert task.get("ac_version"), task

report_path = task_path.parents[2] / task["report_path"]
assert report_path.exists(), report_path
report = yaml.safe_load(report_path.read_text(encoding="utf-8"))
assert report["parent_cmd"] == "cmd_2974", report
assert report["ac_version_read"] == task["ac_version"], report
print("fallback metadata OK")
PY
}

@test "--yaml direct deploy skips stale training parent repair before YAML overwrite" {
    run bash -c '
        set -euo pipefail
        script="$1"
        # test_necessity: karo-direct (--yaml) must observe runtime idle so a
        # terminal worker with an immutable retained report remains reusable.
        grep -Fq "check_idle \"\$pane_target\" && is_idle=true" "$script"
        ! sed -n "/Runtime idleness is independent/,/local task_yaml/p" "$script" | grep -Fq "DIRECT_MODE"
        grep -Fq "repair_training_parent_cmd_from_cmd_id \"\$task_yaml\" || return \$?" "$script"
    ' _ "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]
}

@test "cmd_3091: quoted AC ids do not abort report template binary check injection under set -e" {
    use_private_scripts_fixture

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_3091
  task_id: cmd_3091_normal
  task_type: normal
  project: infra
  report_filename: sasuke_report_cmd_3091.yaml
  related_lessons:
  - id: 'L502'
  acceptance_criteria:
  - id: 'AC1'
    checks:
    - check: 'deployment complete reaches main flow'
  - id: 'AC2'
    checks:
    - check: 'quality monitors run'
  - id: 'AC3'
    checks:
    - check: 'EXIT trap remains fallback only'
  - id: 'AC4'
    checks:
    - check: 'deploy_task tests pass'
EOF

    run bash -c '
        set -euo pipefail
        project="$1"
        export DEPLOY_TASK_LIB_ONLY=1
        source "$project/scripts/deploy_task.sh"
        log() { printf "%s\n" "$1"; }
        generate_report_template sasuke cmd_3091_normal cmd_3091 infra
    ' _ "$TEST_PROJECT"

    [ "$status" -eq 0 ]
    [[ "$output" == *"binary_checks template: 4 ACs + commit check injected"* ]]
    [[ "$output" == *"report_template: generated"* ]]
    grep -Eq "^  '?AC1'?:$" "$TEST_PROJECT/queue/reports/sasuke_report_cmd_3091.yaml"
    grep -q "report_path: queue/reports/sasuke_report_cmd_3091.yaml" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
}

# test_necessity: binary_checksテンプレート注入(awk -v repl)はAC description中のリテラル\t
# (バックスラッシュ+t、2文字)を実タブ(1バイト)へ化けさせず、報告YAMLがyaml.safe_loadで
# 読める不変量を守る。cmd_karo_hotfix_post_clear_fail_open_20260725 AC3:
# awk -v はPOSIX仕様でCエスケープを解釈するため、AC descriptionにリテラル\tを含む
# 忍者task(才蔵自身の受領taskがまさにこれで実際に壊れた実例)が報告YAML破損→
# auto_resolve_cmd_related_insightsのyaml.safe_load失敗→GATE CLEAR後処理の連鎖BLOCKを招いた。
@test "cmd_karo_hotfix_post_clear_fail_open_20260725 AC3: literal backslash-t in AC description survives report template injection without corrupting YAML" {
    use_private_scripts_fixture

    cat > "$TEST_PROJECT/queue/tasks/kotaro.yaml" <<'EOF'
task:
  parent_cmd: cmd_ac3_literal_tab
  task_id: cmd_ac3_literal_tab_normal
  task_type: normal
  project: infra
  report_filename: kotaro_report_cmd_ac3_literal_tab.yaml
  acceptance_criteria:
  - id: 'AC1'
    checks:
    - check: 'リテラル\tを含むAC descriptionが実タブへ化けず報告YAMLがyaml.safe_loadで読めることを確認する'
EOF

    run bash -c '
        set -euo pipefail
        project="$1"
        export DEPLOY_TASK_LIB_ONLY=1
        source "$project/scripts/deploy_task.sh"
        log() { printf "%s\n" "$1"; }
        generate_report_template kotaro cmd_ac3_literal_tab_normal cmd_ac3_literal_tab infra
    ' _ "$TEST_PROJECT"
    [ "$status" -eq 0 ]

    local report_file="$TEST_PROJECT/queue/reports/kotaro_report_cmd_ac3_literal_tab.yaml"

    # 実タブ(0x09)が注入されていないこと(化けていれば失敗)
    run grep -cP '\t' "$report_file"
    [ "$status" -ne 0 ]

    # バックスラッシュ+tの2文字は元のまま残っていること
    grep -F 'リテラル\tを含む' "$report_file"

    # yaml.safe_loadで読めること(実タブ混入時のScannerErrorが再発していないこと)
    run python3 -c "import yaml; yaml.safe_load(open('$report_file', encoding='utf-8'))"
    [ "$status" -eq 0 ]
}

@test "cmd_3091: deploy_task_main reaches quality monitors before deployment complete" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_3091
  task_id: cmd_3091_normal
  task_type: normal
  status: idle
  project: infra
  _ac_task_id: cmd_3091_normal
  report_filename: sasuke_report_cmd_3091.yaml
EOF

    run bash -c '
        set -euo pipefail
        project="$1"
        export DEPLOY_TASK_LIB_ONLY=1
        source "$project/scripts/deploy_task.sh"
        log() { printf "log:%s\n" "$1"; }
        resolve_pane() { echo "test-pane"; }
        get_ctx_pct() { echo 0; }
        cli_type() { echo codex; }
        sleep() { :; }
        check_idle() { return 0; }
        deploy_task_validate_cli_target() { return 0; }
        normalize_task_yaml() { :; }
        repair_training_parent_cmd_from_cmd_id() { :; }
        deploy_task_has_pending_own_report() { return 1; }
        capture_done_redeploy_context() { :; }
        reset_stale_fields() { _STALE_RESET_DONE=1; }
        inject_training_target_path_from_alias_quality() { :; }
        inject_direct_training_template() { :; }
        warn_same_ninja_redeploy() { :; }
        deploy_task_has_completed_peer_report() { return 1; }
        check_firefighting_title() { :; }
        warn_task_clarity() { :; }
        warn_recent_noncmd_commit_targets() { :; }
        warn_q11_not_already_done_drift() { :; }
        deploy_task_apply_task_mutations() { :; }
        safe_inbox_write() { printf "safe_inbox_write\n"; }
        notify_initial_deploy_ntfy_once() { printf "notify_initial_deploy_ntfy_once\n"; }
        record_deployed_at() { printf "record_deployed_at\n"; }
        preflight_gate_artifacts() { printf "preflight_gate_artifacts\n"; }
        maybe_notify_draft_review() { printf "maybe_notify_draft_review\n"; }
        deploy_task_post_deploy_verify() { printf "deploy_task_post_deploy_verify\n"; }
        deploy_task_send_direct_renudge() { printf "deploy_task_send_direct_renudge\n"; }
        tmux() { return 0; }
        deploy_task_main --direct sasuke cmd_3091
    ' _ "$TEST_PROJECT"

    [ "$status" -eq 0 ]
    [[ "$output" == *"safe_inbox_write"* ]]
    [[ "$output" == *"notify_initial_deploy_ntfy_once"* ]]
    [[ "$output" == *"record_deployed_at"* ]]
    [[ "$output" == *"preflight_gate_artifacts"* ]]
    [[ "$output" == *"maybe_notify_draft_review"* ]]
    [[ "$output" == *"log:sasuke: deployment complete (type=task_assigned)"* ]]
    [[ "$output" == *"deploy_task_post_deploy_verify"* ]]
}

@test "inject_semantic_concepts injects recommended_skills from semantic search skills rows" {
    use_private_scripts_fixture
    cat > "$TEST_PROJECT/scripts/semantic_search.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
## cdp_browser_capability — CDP(ブラウザ操作能力)
matched: CDP
aliases: CDP
resources:
- skills: cdp-browse, db-check
- file: `context/cdp-philosophy.md`

## semantic_dictionary_design — セマンティック辞書構想
matched: セマンティック辞書
aliases: セマンティック辞書
resources:
- skills: なし
- file: `docs/research/semantic_index_design.md`
OUT
EOF
    chmod +x "$TEST_PROJECT/scripts/semantic_search.sh"
    mkdir -p "$TEST_PROJECT/docs/semantic-index"
    touch "$TEST_PROJECT/docs/semantic-index/index.md"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  purpose: "CDPで本番画面を確認する"
  description: "末尾説明"
EOF

    run bash -c '
        export DEPLOY_TASK_LIB_ONLY=1
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        log() { :; }
        inject_semantic_concepts "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    '
    [ "$status" -eq 0 ]

    TASK_FILE="$TEST_PROJECT/queue/tasks/sasuke.yaml" python3 - <<'PY'
import os
import yaml

with open(os.environ["TASK_FILE"], encoding="utf-8") as f:
    task = (yaml.safe_load(f) or {}).get("task") or {}

assert task["semantic_concepts"] == [
    "cdp_browser_capability — CDP(ブラウザ操作能力):  context/cdp-philosophy.md",
    "semantic_dictionary_design — セマンティック辞書構想:  docs/research/semantic_index_design.md",
]
assert task["recommended_skills"] == ["cdp-browse", "db-check"]
PY
}

@test "inject_standard_skills injects default always-on skill list" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  purpose: "報告とcommitまで完了する"
  description: "末尾説明"
EOF

    run bash -c '
        export DEPLOY_TASK_LIB_ONLY=1
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        log() { :; }
        inject_standard_skills "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    '
    [ "$status" -eq 0 ]

    TASK_FILE="$TEST_PROJECT/queue/tasks/sasuke.yaml" python3 - <<'PY'
import os
import yaml

with open(os.environ["TASK_FILE"], encoding="utf-8") as f:
    task = (yaml.safe_load(f) or {}).get("task") or {}

assert task["standard_skills"] == ["report-write", "verdict-check", "ninja-commit"]
assert task["description"] == "末尾説明"
PY
}

@test "deploy_task --direct cmd_training injects L4 purpose and five ACs" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_type: normal
  project: infra
EOF

    run deploy_task_fast --direct sasuke cmd_training_L4_test
    [ "$status" -eq 0 ]

    TASK_FILE="$TEST_PROJECT/queue/tasks/sasuke.yaml" python3 - <<'PY'
import os
import yaml

with open(os.environ["TASK_FILE"], encoding="utf-8") as f:
    task = (yaml.safe_load(f) or {}).get("task") or {}

assert task["parent_cmd"] == "cmd_training_L4_test"
assert task["task_id"] == "cmd_training_L4_test_normal"
assert task["status"] == "assigned"
assert task["standard_skills"] == ["report-write", "verdict-check", "ninja-commit"]
assert "L4修行" in task["purpose"]
acs = task["acceptance_criteria"]
assert list(acs.keys()) == ["AC1", "AC2", "AC3", "AC4", "AC5"]
assert "指定ファイル" in acs["AC1"]["description"]
assert "改善点を3つ" in acs["AC1"]["description"]
assert "最高インパクト1件" in acs["AC2"]["description"]
assert "直接[[ファイル名]]リンク" in acs["AC2"]["description"]
assert "既存概念" not in acs["AC2"]["description"]
ac2_checks = "\n".join(acs["AC2"]["binary_checks"])
assert "直接[[ファイル名]]リンク" in ac2_checks
assert "リンク先ファイルから特定行を引用" in ac2_checks
assert "lesson_candidate found=true" in acs["AC3"]["description"]
assert "related_lessonsが1件以上なら" in acs["AC4"]["description"]
assert "0件なら" in acs["AC4"]["description"]
assert "task.related_lessonsの件数を確認" in "\n".join(acs["AC4"]["binary_checks"])
assert "lessons_useful" in acs["AC4"]["description"]
assert "incoming backlink数" in acs["AC5"]["description"]
assert "孤立解消" in acs["AC5"]["description"]
assert "causal_backlink_counts.sh --zero --limit 20" in "\n".join(acs["AC5"]["binary_checks"])
assert "孤立解消またはファイル間直接[[ファイル名]]リンク数増加" in "\n".join(acs["AC5"]["binary_checks"])
for ac_id in ("AC1", "AC2", "AC3", "AC4", "AC5"):
    assert acs[ac_id]["binary_checks"], ac_id
PY
}

@test "deploy_task --direct cmd_training excludes superseded lessons from related_lessons" {
    mkdir -p "$TEST_PROJECT/projects/infra"
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L_OLD
    tags: [deploy]
    title: "deploy_task old training lesson"
    summary: "deploy_task training obsolete"
    detail: "obsolete deploy_task training"
    when: "deploy_task training lesson"
    target_files: ["scripts/deploy_task.sh"]
    status: confirmed
    superseded_by: L_NEW
  - id: L_NEW
    tags: [deploy]
    title: "deploy_task new training lesson"
    summary: "deploy_task training active"
    detail: "active deploy_task training"
    when: "deploy_task training lesson"
    target_files: ["scripts/deploy_task.sh"]
    status: confirmed
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_type: training
  project: infra
  target_path: scripts/deploy_task.sh
  command: "deploy_task training lesson"
EOF

    MIN_KEYWORD_SCORE=1 run deploy_task_fast --direct sasuke cmd_training_L4_superseded_lessons
    [ "$status" -eq 0 ]

    TASK_FILE="$TEST_PROJECT/queue/tasks/sasuke.yaml" python3 - <<'PY'
import os
import yaml

with open(os.environ["TASK_FILE"], encoding="utf-8") as f:
    task = (yaml.safe_load(f) or {}).get("task") or {}

ids = [entry.get("id") for entry in task.get("related_lessons") or []]
assert "L_OLD" not in ids, ids
assert "L_NEW" in ids, ids
PY
}

@test "deploy_task --direct cmd_training overwrites pre-existing purpose and ACs with L4+AC5 template" {
    # karo_direct手動YAML作成方式では目的/AC未注入が発生する（cmd_training_L4_r16事故）
    # deploy_task.sh --directを使えば既存purpose/ACを上書きして修行テンプレートを注入する
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_type: normal
  project: infra
  purpose: "既存の目的 — 上書きされるべき"
  acceptance_criteria:
    AC1:
      description: "既存AC — 上書きされるべき"
EOF

    run deploy_task_fast --direct sasuke cmd_training_L4_overwrite_test
    [ "$status" -eq 0 ]

    TASK_FILE="$TEST_PROJECT/queue/tasks/sasuke.yaml" python3 - <<'PY'
import os
import yaml

with open(os.environ["TASK_FILE"], encoding="utf-8") as f:
    task = (yaml.safe_load(f) or {}).get("task") or {}

assert "L4修行" in task["purpose"], f"purpose not overwritten to L4 template: {task.get('purpose')}"
acs = task["acceptance_criteria"]
assert list(acs.keys()) == ["AC1", "AC2", "AC3", "AC4", "AC5"], f"ACs not overwritten to 5-AC template: {list(acs.keys())}"
assert "改善点を3つ" in acs["AC1"]["description"]
assert "最高インパクト1件" in acs["AC2"]["description"]
assert "直接[[ファイル名]]リンク" in acs["AC2"]["description"]
assert "既存概念" not in acs["AC2"]["description"]
assert "リンク先ファイルから特定行を引用" in "\n".join(acs["AC2"]["binary_checks"])
assert "lesson_candidate found=true" in acs["AC3"]["description"]
assert "related_lessonsが1件以上なら" in acs["AC4"]["description"]
assert "0件なら" in acs["AC4"]["description"]
assert "task.related_lessonsの件数を確認" in "\n".join(acs["AC4"]["binary_checks"])
assert "incoming backlink数" in acs["AC5"]["description"]
assert "causal_backlink_counts.sh --zero --limit 20" in "\n".join(acs["AC5"]["binary_checks"])
PY
}

@test "deploy_task --direct cmd_training preserves skill_training custom ACs" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_type: skill_training
  project: infra
  purpose: "L1 report-write 修行: verdict missingを防ぐ"
  acceptance_criteria:
    AC1:
      description: "verdict missingの原因を説明する"
      binary_checks:
        - "verdict自動導出を確認したか: yes/no"
EOF

    (
        export DEPLOY_TASK_LIB_ONLY=1
        # shellcheck disable=SC1090,SC1091
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        log() { :; }
        inject_direct_training_template "$TEST_PROJECT/queue/tasks/sasuke.yaml" "cmd_training_L1_report-write_20260701194745"
    )

    TASK_FILE="$TEST_PROJECT/queue/tasks/sasuke.yaml" python3 - <<'PY'
import os
import yaml

with open(os.environ["TASK_FILE"], encoding="utf-8") as f:
    task = (yaml.safe_load(f) or {}).get("task") or {}

assert task["task_type"] == "skill_training"
assert "L1 report-write" in task["purpose"], task["purpose"]
acs = task["acceptance_criteria"]
assert list(acs.keys()) == ["AC1"], acs
assert "verdict missing" in acs["AC1"]["description"]
assert "改善点を3つ" not in acs["AC1"]["description"]
PY
}

@test "markdown_link_counts ranks tracked Markdown files by ascending wiki links" {
    mkdir -p "$TEST_PROJECT/docs"
    (
        cd "$TEST_PROJECT"
        git init -q
        git config user.email test@example.com
        git config user.name test
        cat > docs/isolated.md <<'EOF'
# Isolated
EOF
        cat > docs/linked.md <<'EOF'
# Linked
[[alpha]]
[[beta]]
EOF
        git add docs/isolated.md docs/linked.md
    )

    run bash "$TEST_PROJECT/scripts/markdown_link_counts.sh" --top 2
    [ "$status" -eq 0 ]
    [[ "$output" == *$'1\t0\tdocs/isolated.md'* ]]
    [[ "$output" == *$'2\t2\tdocs/linked.md'* ]]

    run bash "$TEST_PROJECT/scripts/markdown_link_counts.sh" --select-file
    [ "$status" -eq 0 ]
    [ "$output" = "docs/isolated.md" ]
}

@test "cmd_training target_path prefers backlink-zero file over outgoing link count" {
    use_private_scripts_fixture
    mkdir -p \
        "$TEST_PROJECT/context" \
        "$TEST_PROJECT/docs/research" \
        "$TEST_PROJECT/docs/semantic-index" \
        "$TEST_PROJECT/instructions" \
        "$TEST_PROJECT/memory" \
        "$TEST_PROJECT/skills"
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_type: training
  project: infra
EOF
    (
        cd "$TEST_PROJECT"
        git init -q
        git config user.email test@example.com
        git config user.name test
        cat > context/orphan-incoming.md <<'EOF'
# Orphan Incoming
[[has_outgoing]]
EOF
        cat > docs/research/outgoing-zero.md <<'EOF'
# Outgoing Zero
EOF
        cat > context/source.md <<'EOF'
# Source
docs/research/outgoing-zero.md
EOF
        git add context/orphan-incoming.md docs/research/outgoing-zero.md context/source.md
    )

    run deploy_task_fast --direct sasuke cmd_training_L4_backlink_zero_target
    [ "$status" -eq 0 ]

    python3 - "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as fh:
    task = (yaml.safe_load(fh) or {}).get("task") or {}
assert task.get("target_path") == ["context/orphan-incoming.md"], task.get("target_path")
PY
}

@test "semantic_alias_quality lists aliases thin Top10 and selects existing script target" {
    mkdir -p "$TEST_PROJECT/docs/semantic-index" "$TEST_PROJECT/scripts/tools"
    touch "$TEST_PROJECT/scripts/tools/thin.sh" "$TEST_PROJECT/scripts/tools/rich.sh"
    cat > "$TEST_PROJECT/docs/semantic-index/index.md" <<'EOF'
# Test semantic index

## thin_concept — 薄い概念

| 属性 | 値 |
|------|---|
| id | thin_concept |
| label | 薄い概念 |
| aliases | thin |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/tools/thin.sh` |

## rich_concept — 濃い概念

| 属性 | 値 |
|------|---|
| id | rich_concept |
| label | 濃い概念 |
| aliases | rich, dense, many |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/tools/rich.sh` |
EOF

    run bash "$TEST_PROJECT/scripts/semantic_alias_quality.sh" --top 10
    [ "$status" -eq 0 ]
    [[ "$output" == *"aliases薄概念Top10"* ]]
    [[ "$output" == *$'thin_concept\t1\t100.0%\tscripts/tools/thin.sh'* ]]

    run bash "$TEST_PROJECT/scripts/semantic_alias_quality.sh" --select-file
    [ "$status" -eq 0 ]
    [ "$output" = "scripts/tools/thin.sh" ]
}

@test "deploy_task --direct cmd_training sets target_path from isolated Markdown before aliases thin concept" {
    mkdir -p "$TEST_PROJECT/docs/semantic-index" "$TEST_PROJECT/docs" "$TEST_PROJECT/scripts/tools"
    touch "$TEST_PROJECT/scripts/tools/thin.sh" "$TEST_PROJECT/scripts/tools/rich.sh"
    (
        cd "$TEST_PROJECT"
        git init -q
        git config user.email test@example.com
        git config user.name test
        cat > docs/isolated.md <<'EOF'
# Isolated
EOF
        cat > docs/linked.md <<'EOF'
# Linked
[[alpha]]
EOF
        git add docs/isolated.md docs/linked.md
    )
    cat > "$TEST_PROJECT/docs/semantic-index/index.md" <<'EOF'
# Test semantic index

## thin_concept — 薄い概念

| 属性 | 値 |
|------|---|
| id | thin_concept |
| label | 薄い概念 |
| aliases | thin |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/tools/thin.sh` |

## rich_concept — 濃い概念

| 属性 | 値 |
|------|---|
| id | rich_concept |
| label | 濃い概念 |
| aliases | rich, dense, many |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/tools/rich.sh` |
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_type: normal
  project: infra
EOF

    run deploy_task_fast --direct sasuke cmd_training_L4_alias_target
    [ "$status" -eq 0 ]

    TASK_FILE="$TEST_PROJECT/queue/tasks/sasuke.yaml" python3 - <<'PY'
import os
import yaml

with open(os.environ["TASK_FILE"], encoding="utf-8") as f:
    task = (yaml.safe_load(f) or {}).get("task") or {}

assert task["target_path"] == ["docs/isolated.md"], task.get("target_path")
PY
}
@test "inject_target_path_check records git HEAD and last commit evidence" {
  local tracked
  tracked=$(realpath "$BATS_TEST_DIRNAME/../../scripts/deploy_task.sh")
  local untracked="$BATS_TEST_TMPDIR/untracked-target.txt"
  printf 'untracked\n' > "$untracked"

  local task="$BATS_TEST_TMPDIR/task.yaml"
  cat > "$task" <<YAML
task:
  project: ''
  target_path:
  - $tracked
  - $untracked
YAML

  run bash -c '
    export DEPLOY_TASK_LIB_ONLY=1
    source "$1/scripts/deploy_task.sh"
    inject_target_path_check "$2"
  ' _ "$TEST_PROJECT" "$task"
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&3
  fi
  [ "$status" -eq 0 ]
  run grep -F 'deploy_task.sh:worktree=yes,head=yes,last_commit=pending@' "$task"
  [ "$status" -eq 0 ]
  run grep -F 'untracked-target.txt:worktree=yes,head=no,last_commit=none' "$task"
  [ "$status" -eq 0 ]
  run grep -F 'target_path_head_warning:' "$task"
  [ "$status" -eq 0 ]
}

@test "target history cold miss is deferred while HEAD safety remains synchronous" {
  local tracked task
  tracked=$(realpath "$BATS_TEST_DIRNAME/../../scripts/deploy_task.sh")
  task="$BATS_TEST_TMPDIR/task-history.yaml"
  cat > "$task" <<YAML
task:
  project: ''
  target_path: $tracked
YAML
  run bash -c 'export DEPLOY_TASK_LIB_ONLY=1; source "$1/scripts/deploy_task.sh"; inject_target_path_check "$2"' _ "$TEST_PROJECT" "$task"
  [ "$status" -eq 0 ]
  grep -Fq 'last_commit=pending@' "$task"
  grep -Fq 'path=scripts/deploy_task.sh' "$TEST_PROJECT/queue/deferred/git_history.tsv"
}

@test "stale report cleanup queue preserves source until revalidation" {
  local report="$TEST_PROJECT/queue/reports/sasuke_report_cmd_old.yaml"
  mkdir -p "$(dirname "$report")"
  printf 'parent_cmd: cmd_old\nstatus: pending\nverdict: ""\n' > "$report"
  run bash -c 'export DEPLOY_TASK_LIB_ONLY=1; source "$1/scripts/deploy_task.sh"; deploy_task_queue_stale_report "$2" cmd_old ""' _ "$TEST_PROJECT" "$report"
  [ "$status" -eq 0 ]
  [ -f "$report" ]
  grep -Fq "path=$report" "$TEST_PROJECT/queue/deferred/stale_reports.tsv"
}

@test "history cache accepts only exact HEAD and path generation" {
  local repo head rel key cache
  repo=$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel)
  head=$(git -C "$repo" rev-parse HEAD)
  rel=scripts/deploy_task.sh
  key=$(printf '%s\0%s\0%s' "$repo" "$head" "$rel" | sha256sum | awk '{print $1}')
  cache="$TEST_PROJECT/.cache/deploy-history/$key"
  mkdir -p "$(dirname "$cache")"
  printf '%s\t%s\t%s\n' "$head" "$rel" 0123456789012345678901234567890123456789 > "$cache"
  run bash -c 'export DEPLOY_TASK_LIB_ONLY=1; source "$1/scripts/deploy_task.sh"; deploy_task_history_cache_get "$2" "$3" "$4"' _ "$TEST_PROJECT" "$repo" "$head" "$rel"
  [ "$status" -eq 0 ]
  [ "$output" = 0123456789012345678901234567890123456789 ]
  run bash -c 'export DEPLOY_TASK_LIB_ONLY=1; source "$1/scripts/deploy_task.sh"; deploy_task_history_cache_get "$2" "$3" "$4"' _ "$TEST_PROJECT" "$repo" 0000000000000000000000000000000000000000 "$rel"
  [ "$status" -ne 0 ]
}

@test "deferred consumer revalidates generation then drains history and stale report" {
  local repo head rel report task key cache
  repo="$BATS_TEST_TMPDIR/drain-repo"
  git init -q "$repo"
  git -C "$repo" config user.name test
  git -C "$repo" config user.email test@example.com
  printf 'x\n' > "$repo/tracked.txt"
  git -C "$repo" add tracked.txt
  git -C "$repo" commit -qm init
  head=$(git -C "$repo" rev-parse HEAD)
  rel=tracked.txt
  report="$TEST_PROJECT/queue/reports/sasuke_report_cmd_old.yaml"
  task="$TEST_PROJECT/queue/tasks/sasuke.yaml"
  mkdir -p "$(dirname "$report")" "$(dirname "$task")"
  printf 'parent_cmd: cmd_old\nstatus: pending\nverdict: ""\n' > "$report"
  printf 'task:\n  parent_cmd: cmd_new\n  status: idle\n' > "$task"
  run bash -c 'export DEPLOY_TASK_LIB_ONLY=1; source "$1/scripts/deploy_task.sh"; deploy_task_queue_history_lookup "$2" "$3" "$4"; deploy_task_queue_stale_report "$5" cmd_old ""; deploy_task_drain_deferred' _ "$TEST_PROJECT" "$repo" "$head" "$rel" "$report"
  [ "$status" -eq 0 ]
  key=$(printf '%s\0%s\0%s' "$repo" "$head" "$rel" | sha256sum | awk '{print $1}')
  cache="$TEST_PROJECT/.cache/deploy-history/$key"
  [ -s "$cache" ]
  [ ! -f "$report" ]
  [ -f "$TEST_PROJECT/archive/reports/stale/$(basename "$report")" ]
}

@test "deferred consumer preserves active and completed reports" {
  local active completed
  active="$TEST_PROJECT/queue/reports/sasuke_report_cmd_active.yaml"
  completed="$TEST_PROJECT/queue/reports/sasuke_report_cmd_done.yaml"
  mkdir -p "$TEST_PROJECT/queue/reports" "$TEST_PROJECT/queue/tasks"
  printf 'parent_cmd: cmd_active\nstatus: pending\nverdict: ""\n' > "$active"
  printf 'parent_cmd: cmd_done\nstatus: completed\nverdict: PASS\n' > "$completed"
  printf 'task:\n  parent_cmd: cmd_active\n  status: in_progress\n' > "$TEST_PROJECT/queue/tasks/sasuke.yaml"
  run bash -c 'export DEPLOY_TASK_LIB_ONLY=1; source "$1/scripts/deploy_task.sh"; deploy_task_queue_stale_report "$2" cmd_active ""; deploy_task_queue_stale_report "$3" cmd_done PASS; deploy_task_drain_deferred' _ "$TEST_PROJECT" "$active" "$completed"
  [ "$status" -eq 0 ]
  [ -f "$active" ]
  [ -f "$completed" ]
}

# test_necessity: lesson injection_countは同一attempt/task generationを一度だけ数え、
# project単位の一括drainでも各lessonの既存値を正確に1増分する不変量を守る。
@test "deferred lesson scores deduplicate generation and batch one project" {
  local archive task
  archive="$TEST_PROJECT/projects/infra/lessons_archive.yaml"
  task="$TEST_PROJECT/queue/tasks/sasuke.yaml"
  mkdir -p "$(dirname "$archive")"
  cat > "$archive" <<'YAML'
- id: L001
  injection_count: 2
  last_referenced: 'old'
- id: L002
  detail: second
YAML
  cat > "$task" <<'YAML'
task:
  parent_cmd: cmd_deferred_score
  task_id: cmd_deferred_score_normal
  ac_version: abc123
YAML

  run bash -c '
    export DEPLOY_TASK_LIB_ONLY=1 DEPLOY_TASK_ISSUE_ATTEMPT_ID=attempt-1
    source "$1/scripts/deploy_task.sh"
    deploy_task_queue_lesson_scores "$2" infra "L001 L002"
    deploy_task_queue_lesson_scores "$2" infra "L001 L002"
    DEPLOY_TASK_ISSUE_ATTEMPT_ID=attempt-2
    deploy_task_queue_lesson_scores "$2" infra "L001 L002"
    deploy_task_drain_deferred
  ' _ "$TEST_PROJECT" "$task"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^  injection_count: 4$' "$archive")" -eq 1 ]
  [ "$(grep -c '^  injection_count: 2$' "$archive")" -eq 1 ]
  [ "$(find "$TEST_PROJECT/.cache/deploy-lesson-scores" -name '*.done' | wc -l)" -eq 2 ]
  [ ! -s "$TEST_PROJECT/queue/deferred/lesson_scores.tsv" ]
}

# test_necessity: lesson archiveの一括更新が失敗した場合、counterを部分更新せず、
# 元のevent rowを失わず次回drainへ残すfail-closed不変量を守る。
@test "deferred lesson score failure retains row without partial archive update" {
  local archive task before after
  archive="$TEST_PROJECT/projects/infra/lessons_archive.yaml"
  task="$TEST_PROJECT/queue/tasks/sasuke.yaml"
  mkdir -p "$(dirname "$archive")"
  printf '%s\n' '- id: L001' '  injection_count: 4' > "$archive"
  printf '%s\n' 'task:' '  parent_cmd: cmd_deferred_score_fail' '  task_id: normal' '  ac_version: def456' > "$task"
  before=$(sha256sum "$archive" | awk '{print $1}')

  run bash -c '
    export DEPLOY_TASK_LIB_ONLY=1 DEPLOY_TASK_ISSUE_ATTEMPT_ID=attempt-fail
    source "$1/scripts/deploy_task.sh"
    deploy_task_queue_lesson_scores "$2" infra "L001 L404"
    deploy_task_drain_deferred
  ' _ "$TEST_PROJECT" "$task"
  [ "$status" -eq 0 ]
  after=$(sha256sum "$archive" | awk '{print $1}')
  [ "$after" = "$before" ]
  [ "$(wc -l < "$TEST_PROJECT/queue/deferred/lesson_scores.tsv")" -eq 1 ]
  [ "$(find "$TEST_PROJECT/.cache/deploy-lesson-scores" -name '*.done' | wc -l)" -eq 0 ]
}

@test "parallel append and drain rotation loses zero deferred items" {
  run bash -c '
    export DEPLOY_TASK_LIB_ONLY=1
    source "$1/scripts/deploy_task.sh"
    total=40
    for i in $(seq 1 "$total"); do
      deploy_task_queue_stale_report "$TEST_PROJECT/queue/reports/missing_${i}.yaml" "cmd_${i}" "" &
    done
    deploy_task_drain_deferred &
    wait
    deploy_task_drain_deferred
    skipped=$(sed -n "s/.*DEFERRED_DRAIN processed=[0-9]* skipped=\([0-9]*\) failed=[0-9]* backlog=[0-9]*/\1/p" "$TEST_PROJECT/logs/deploy_task.log" | awk "{s+=\$1} END{print s+0}")
    backlog=$(find "$TEST_PROJECT/queue/deferred" -maxdepth 1 -name "*.tsv" -type f -exec awk "END{print NR}" {} \; | awk "{s+=\$1} END{print s+0}")
    printf "enqueued=%s skipped=%s backlog=%s lost=%s\n" "$total" "$skipped" "$backlog" "$((total-skipped-backlog))"
  ' _ "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"enqueued=40 skipped=40 backlog=0 lost=0"* ]]
}

# test_necessity: active-report pointer publicationは同一ninjaへの並列配備でもwriter固有tmpを使い、
# stale tmpと再入に干渉されず、完了した最後のwriterを指す不変量を守る。
@test "active report pointer publication is atomic across parallel reentry and stale tmp" {
  local pointer="$TEST_PROJECT/queue/reports/.deploy_active_hanzo"
  mkdir -p "$(dirname "$pointer")"
  printf 'stale\n' > "${pointer}.tmp.999999"

  run bash -c '
    export DEPLOY_TASK_LIB_ONLY=1
    source "$1/scripts/deploy_task.sh"
    pointer="$2"
    deploy_task_publish_active_report_pointer "$pointer" "queue/reports/reentry.yaml"
    deploy_task_publish_active_report_pointer "$pointer" "queue/reports/reentry.yaml"
    for report in parallel_a parallel_b parallel_c; do
      (
        deploy_task_publish_active_report_pointer \
          "$pointer" "queue/reports/${report}.yaml"
      ) &
    done
    wait
    deploy_task_publish_active_report_pointer "$pointer" "queue/reports/last_writer.yaml"
    printf "pointer=%s stale=%s live_tmp=%s\n" \
      "$(cat "$pointer")" \
      "$(cat "${pointer}.tmp.999999")" \
      "$(find "$(dirname "$pointer")" -maxdepth 1 -name "$(basename "$pointer").tmp.*" ! -name "$(basename "$pointer").tmp.999999" -type f | wc -l)"
  ' _ "$TEST_PROJECT" "$pointer"
  [ "$status" -eq 0 ]
  [ "$output" = "pointer=queue/reports/last_writer.yaml stale=stale live_tmp=0" ]

  run grep -Fc 'deploy_task_publish_active_report_pointer "$_active_report_index" "$report_rel_path" || return 1' "$PROJECT_ROOT/scripts/deploy_task.sh"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
  run grep -F '${_active_report_index}.tmp' "$PROJECT_ROOT/scripts/deploy_task.sh"
  [ "$status" -eq 1 ]
}

# test_necessity: per-ninja lock取得後のcheckpoint hold再検証により、review前の同時次task配備を防ぐ不変量を守る。
@test "checkpoint review hold blocks deploy under ninja lock and reviewed releases it" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        source "$PROJECT_ROOT/scripts/deploy_task.sh"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; mkdir -p "$SCRIPT_DIR/queue/checkpoint_manifests" "$SCRIPT_DIR/queue/locks"
        printf "%s\n" state=ready worker=alpha reviewer=gunshi >"$SCRIPT_DIR/queue/checkpoint_manifests/f1.manifest"
        deploy_task_acquire_ninja_lock alpha
        rc=0; deploy_task_guard_checkpoint_review_hold alpha || rc=$?
        [ "$rc" -eq 2 ]
        sed -i "s/^state=ready/state=reviewed/" "$SCRIPT_DIR/queue/checkpoint_manifests/f1.manifest"
        deploy_task_guard_checkpoint_review_hold alpha
        deploy_task_release_ninja_lock
    '
    [ "$status" -eq 0 ]
}

# test_necessity: blocked-parent owner validation follows the configured ninja roster, so roster additions propagate without code edits while unknown owners remain blocked.
@test "blocked parent continuation validates owner through agent roster SSOT" {
    mkdir -p "$TEST_PROJECT/queue/tasks"
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'EOF'
task:
  task_id: cmd_parent_normal
  status: failed
EOF
    cat > "$TEST_PROJECT/queue/tasks/roster_added.yaml" <<'EOF'
task:
  task_id: cmd_parent_normal
  status: failed
EOF
    cat > "$TEST_PROJECT/hotfix.yaml" <<'EOF'
task:
  task_type: hotfix
  parent_cmd: cmd_hotfix
  fixes: cmd_parent
  blocked_parent_ninja: hayate
  blocked_parent_task_id: cmd_parent_normal
EOF

    # A currently configured ninja remains valid.
    run bash -c '
      export DEPLOY_TASK_LIB_ONLY=1
      source "$1/scripts/deploy_task.sh"
      SCRIPT_DIR="$1"
      get_ninja_names() { printf "%s\n" "hayate roster_added"; }
      register_blocked_parent_continuation "$1/hotfix.yaml" kagemaru
    ' _ "$TEST_PROJECT"
    [ "$status" -eq 0 ]

    # A newly configured ninja becomes valid without editing deploy_task.sh.
    sed -i 's/blocked_parent_ninja: hayate/blocked_parent_ninja: roster_added/' "$TEST_PROJECT/hotfix.yaml"
    run bash -c '
      export DEPLOY_TASK_LIB_ONLY=1
      source "$1/scripts/deploy_task.sh"
      SCRIPT_DIR="$1"
      get_ninja_names() { printf "%s\n" "hayate roster_added"; }
      register_blocked_parent_continuation "$1/hotfix.yaml" kagemaru
    ' _ "$TEST_PROJECT"
    [ "$status" -eq 0 ]

    sed -i 's/blocked_parent_ninja: roster_added/blocked_parent_ninja: unknown_ninja/' "$TEST_PROJECT/hotfix.yaml"
    run bash -c '
      export DEPLOY_TASK_LIB_ONLY=1
      source "$1/scripts/deploy_task.sh"
      SCRIPT_DIR="$1"
      get_ninja_names() { printf "%s\n" "hayate roster_added"; }
      register_blocked_parent_continuation "$1/hotfix.yaml" kagemaru
    ' _ "$TEST_PROJECT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK: invalid blocked_parent_ninja"* ]]
}

# test_necessity: deploy preflight must expose the linked-worktree metadata
# count immediately before worktree creation so metadata pressure is measurable.
@test "worktree preflight logs metadata entry count before add" {
    local repo="$BATS_TEST_TMPDIR/worktree-metadata-repo"
    mkdir -p "$repo"
    git init -q "$repo"
    git -C "$repo" config user.email test@example.invalid
    git -C "$repo" config user.name test
    printf 'base\n' > "$repo/README"
    git -C "$repo" add README
    git -C "$repo" commit -q -m base
    git -C "$repo" worktree add -q "$BATS_TEST_TMPDIR/worktree-metadata-live" HEAD

    run bash -c '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        SCRIPT_DIR="$1"
        log() { printf "%s\n" "$1"; }
        deploy_task_log_worktree_metadata_before_add "$2"
    ' _ "$PROJECT_ROOT" "$repo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WORKTREE-METADATA-BEFORE-ADD repo=$repo entries=1"* ]]

    local log_line add_line
    log_line=$(rg -n 'deploy_task_log_worktree_metadata_before_add "\$repo"' \
        "$PROJECT_ROOT/scripts/deploy_task/preflight.sh" | cut -d: -f1)
    add_line=$(rg -n 'git -C "\$repo".*worktree add' \
        "$PROJECT_ROOT/scripts/deploy_task/preflight.sh" | cut -d: -f1)
    test "$log_line" -lt "$add_line"
}
