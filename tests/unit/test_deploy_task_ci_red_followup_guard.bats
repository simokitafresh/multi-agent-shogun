#!/usr/bin/env bats
# test_necessity: CI REDと追加commit数だけでは通常配備を止めず、修正を促す警告とtask固有検証を分離する。

setup() {
    REPO_ROOT="$BATS_TEST_DIRNAME/../.."
    RED='[{"conclusion":"failure","databaseId":1,"headSha":"deadbeefdeadbeef"}]'
    GREEN='[{"conclusion":"success","databaseId":1,"headSha":"deadbeefdeadbeef"}]'
    IN_PROGRESS='[{"status":"in_progress","conclusion":"","databaseId":2,"headSha":"feedfacefeedface"}]'
    printf 'task:\n  task_type: hotfix\n' > "$BATS_TEST_TMPDIR/hotfix.yaml"
    printf 'task:\n  task_type: ci_fix\n' > "$BATS_TEST_TMPDIR/ci_fix.yaml"
}

guard() {
    run env "$@" bash -c '
        SCRIPT_DIR="'"$REPO_ROOT"'"
        source "$SCRIPT_DIR/scripts/lib/field_get.sh"
        log() { :; }
        eval "$(sed -n "/^deploy_task_ci_red_followup_push_guard() {/,/^}$/p" "$SCRIPT_DIR/scripts/deploy_task.sh")"
        deploy_task_ci_red_followup_push_guard "$1"
    ' _ "$SOURCE_YAML"
}

@test "CI GREEN never blocks deployment regardless of push count" {
    SOURCE_YAML="$BATS_TEST_TMPDIR/hotfix.yaml"
    guard DEPLOY_TASK_CI_RED_JSON="$GREEN" DEPLOY_TASK_CI_FOLLOWUP_PUSHES=9
    [ "$status" -eq 0 ]
}

@test "CI RED with follow-up pushes at the limit still allows deployment" {
    SOURCE_YAML="$BATS_TEST_TMPDIR/hotfix.yaml"
    guard DEPLOY_TASK_CI_RED_JSON="$RED" DEPLOY_TASK_CI_FOLLOWUP_PUSHES=2
    [ "$status" -eq 0 ]
}

@test "CI RED beyond the follow-up push limit warns without blocking deployment" {
    SOURCE_YAML="$BATS_TEST_TMPDIR/hotfix.yaml"
    guard DEPLOY_TASK_CI_RED_JSON="$RED" DEPLOY_TASK_CI_FOLLOWUP_PUSHES=3
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: CI RED"* ]]
    [[ "$output" != *"BLOCK"* ]]
}

@test "CI RED does not block a fresh CLI process regardless of model" {
    SOURCE_YAML="$BATS_TEST_TMPDIR/hotfix.yaml"
    for cli in claude codex copilot kimi; do
      for model in fixture_model_a fixture_model_b; do
       for effort in low medium high xhigh max; do
        guard -u TMUX -u TMUX_PANE DEPLOY_TASK_CI_RED_JSON="$RED" DEPLOY_TASK_CI_FOLLOWUP_PUSHES=100 CLI_TYPE="$cli" MODEL="$model" MODEL_REASONING_EFFORT="$effort"
        [ "$status" -eq 0 ]
        [[ "$output" == *"WARN: CI RED"* ]]
       done
      done
    done
}

@test "all generated CLI role instructions preserve the independent work policy" {
    run python3 - "$REPO_ROOT" <<'PY'
import pathlib, sys
root=pathlib.Path(sys.argv[1])
start='<!-- ci-independent-work:start -->'
end='<!-- ci-independent-work:end -->'
paths=[root/'AGENTS.md', root/'CLAUDE.md', root/'instructions/common/task_flow.md']
for prefix in ('', 'codex-', 'copilot-', 'kimi-'):
    paths.extend(root/f'instructions/generated/{prefix}{role}.md' for role in ('shogun','karo','gunshi','ashigaru'))
blocks=[]
for path in paths:
    text=path.read_text()
    assert text.count(start)==text.count(end)==1, str(path)
    blocks.append(text.split(start)[1].split(end)[0])
assert len(set(blocks))==1
assert 'pushのみ保留' not in (root/'AGENTS.md').read_text()
assert 'pushのみ保留' not in (root/'CLAUDE.md').read_text()
print('19/19 policy sources identical')
PY
    [ "$status" -eq 0 ]
}

@test "ci_fix deployment is always allowed so RED can be repaired" {
    SOURCE_YAML="$BATS_TEST_TMPDIR/ci_fix.yaml"
    guard DEPLOY_TASK_CI_RED_JSON="$RED" DEPLOY_TASK_CI_FOLLOWUP_PUSHES=9
    [ "$status" -eq 0 ]
}

@test "newer in-progress CI supersedes an older completed RED" {
    SOURCE_YAML="$BATS_TEST_TMPDIR/hotfix.yaml"
    guard DEPLOY_TASK_CI_RED_JSON="$IN_PROGRESS" DEPLOY_TASK_CI_FOLLOWUP_PUSHES=19
    [ "$status" -eq 0 ]
}
