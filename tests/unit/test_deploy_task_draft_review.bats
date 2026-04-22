#!/usr/bin/env bats

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

materialize_scripts_dir() {
    local scripts_target

    if [ ! -L "$TEST_PROJECT/scripts" ]; then
        return 0
    fi

    scripts_target="$(readlink "$TEST_PROJECT/scripts")"
    rm "$TEST_PROJECT/scripts"
    cp -r "$scripts_target" "$TEST_PROJECT/scripts"
}

setup() {
    deploy_task_scaffold "deploy_draft_review"
    materialize_scripts_dir

    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_normal:
    title: "通常cmd"
  cmd_ci_red:
    title: "CI RED修正 cmd"
  cmd_single_ac:
    title: "軽微修正cmd"
YAML

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_normal
  acceptance_criteria:
    - id: AC1
      description: "通常配備"
    - id: AC2
      description: "draft review送信"
YAML

    cat > "$TEST_PROJECT/scripts/inbox_write.sh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TEST_PROJECT/logs/inbox_write_calls.log"
exit 0
EOF
    chmod +x "$TEST_PROJECT/scripts/inbox_write.sh"
}

teardown() {
    deploy_task_teardown
}

run_draft_review() {
    local cmd_id="$1"
    local task_file="${2:-$TEST_PROJECT/queue/tasks/sasuke.yaml}"
    local deploy_type="${3:-task_assigned}"

    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "'"$TEST_PROJECT/scripts/deploy_task.sh"'"
        log() { printf "%s\n" "$1"; }
        maybe_notify_draft_review "'"$task_file"'" "'"$cmd_id"'" sasuke "'"$deploy_type"'"
    '
}

@test "normal deploy sends review_draft to gunshi" {
    run_draft_review "cmd_normal"

    [ "$status" -eq 0 ]
    [[ "$output" == *"draft_review: SENT (gunshi)"* ]]
    run cat "$TEST_PROJECT/logs/inbox_write_calls.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"gunshi draft cmd_normal レビュー依頼。通常cmd。ninja=sasuke。 review_draft karo"* ]]
}

@test "malformed task YAML falls back to cmd source AC count and still sends draft review" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_normal
  acceptance_criteria:
  _deploy_notice: "broken"
    dangling continuation
YAML
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_normal:
    title: "通常cmd"
    acceptance_criteria:
      - id: AC1
        description: "通常配備"
      - id: AC2
        description: "draft review送信"
YAML

    run_draft_review "cmd_normal"

    [ "$status" -eq 0 ]
    [[ "$output" == *"draft_review: SENT (gunshi)"* ]]
}

@test "draft review is sent only once per cmd" {
    run_draft_review "cmd_normal"
    [ "$status" -eq 0 ]
    run_draft_review "cmd_normal"
    [ "$status" -eq 0 ]
    [[ "$output" == *"draft_review: SKIP (already sent)"* ]]
    run grep -c "review_draft karo" "$TEST_PROJECT/logs/inbox_write_calls.log"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "CI RED title skips draft review" {
    run_draft_review "cmd_ci_red"

    [ "$status" -eq 0 ]
    [[ "$output" == *"draft_review: SKIP (CI RED)"* ]]
    [ ! -f "$TEST_PROJECT/logs/inbox_write_calls.log" ]
}

@test "single AC task skips draft review" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_single_ac
  acceptance_criteria:
    - id: AC1
      description: "軽微修正"
YAML

    run_draft_review "cmd_single_ac"

    [ "$status" -eq 0 ]
    [[ "$output" == *"draft_review: SKIP (ac_count<=1: 1)"* ]]
    [ ! -f "$TEST_PROJECT/logs/inbox_write_calls.log" ]
}

@test "SKIP_DRAFT_REVIEW=1 skips draft review" {
    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        export SKIP_DRAFT_REVIEW=1
        source "'"$TEST_PROJECT/scripts/deploy_task.sh"'"
        log() { printf "%s\n" "$1"; }
        maybe_notify_draft_review "'"$TEST_PROJECT/queue/tasks/sasuke.yaml"'" cmd_normal sasuke task_assigned
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"draft_review: SKIP (env)"* ]]
    [ ! -f "$TEST_PROJECT/logs/inbox_write_calls.log" ]
}
