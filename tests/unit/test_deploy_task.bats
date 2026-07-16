#!/usr/bin/env bats
# test_deploy_task.bats — deploy_task.sh --yaml モード鮮度チェックのユニットテスト
# AC1: スクリプトがYAML作成後にcommit → WARN表示
# AC2: スクリプトがYAML作成前にcommit → WARN非表示

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "deploy_yaml_freshness"
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
        project="$1"
        export DEPLOY_TASK_LIB_ONLY=1
        source "$project/scripts/deploy_task.sh"
        log() { printf "%s\n" "$1" >> "$project/logs/exit_after_mutation.log"; }
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
            printf "mutated\n" >> "$project/logs/exit_after_mutation.log"
        }
        deploy_task_check_deadline() {
            if [ "${1:-}" = "after_task_mutations" ]; then
                return 1
            fi
            return 0
        }
        safe_inbox_write() {
            printf "%s|%s|%s|%s\n" "$1" "$2" "$3" "$4" >> "$project/logs/exit_after_mutation_send.log"
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
        grep -Fq "if [ \"\$DIRECT_MODE\" != true ]; then" "$script"
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
    title: "deploy_task old training lesson"
    summary: "deploy_task training obsolete"
    detail: "obsolete deploy_task training"
    status: confirmed
    superseded_by: L_NEW
  - id: L_NEW
    title: "deploy_task new training lesson"
    summary: "deploy_task training active"
    detail: "active deploy_task training"
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
    mkdir -p "$TEST_PROJECT/context" "$TEST_PROJECT/docs/research"
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
assert task.get("target_path") == "context/orphan-incoming.md", task.get("target_path")
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

assert task["target_path"] == "docs/isolated.md", task.get("target_path")
PY
}
