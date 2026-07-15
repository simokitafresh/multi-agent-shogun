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

    run maybe_notify_draft_review "$task_file" "$cmd_id" sasuke "$deploy_type"
}

run_quality_contract() {
    run deploy_task_quality_contract_result "$1"
}

run_draft_review_skipped() {
    SKIP_DRAFT_REVIEW=1 maybe_notify_draft_review "$1" cmd_normal sasuke task_assigned
}

run_draft_review_with_invalid_count() {
    count_task_acceptance_criteria() { printf 'not-a-number\n'; }
    maybe_notify_draft_review "$1" cmd_normal sasuke task_assigned
}

run_draft_review_with_failed_count() {
    count_task_acceptance_criteria() { return 1; }
    maybe_notify_draft_review "$1" cmd_normal sasuke task_assigned
}

@test "normal deploy sends review_draft to gunshi" {
    run_draft_review "cmd_normal"

    [ "$status" -eq 0 ]
    [[ "$output" == *"draft_review: SENT (gunshi)"* ]]
    run cat "$TEST_PROJECT/logs/inbox_write_calls.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"gunshi draft cmd_normal レビュー依頼。通常cmd。ninja=sasuke。 review_draft karo"* ]]
}

@test "EXIT trap fallback sends draft review on deploy failure" {
    run bash -lc '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "'"$TEST_PROJECT/scripts/deploy_task.sh"'"
        log() { printf "%s\n" "$1"; }
        trap deploy_task_exit_nudge EXIT
        DEPLOY_TASK_DRAFT_REVIEW_ARMED=1
        DEPLOY_TASK_DRAFT_REVIEW_SENT=0
        DEPLOY_TASK_DRAFT_REVIEW_TASK_FILE="'"$TEST_PROJECT/queue/tasks/sasuke.yaml"'"
        DEPLOY_TASK_DRAFT_REVIEW_CMD_ID=cmd_normal
        DEPLOY_TASK_DRAFT_REVIEW_NINJA=sasuke
        DEPLOY_TASK_DRAFT_REVIEW_TYPE=task_assigned
        false
    '

    [ "$status" -eq 1 ]
    [[ "$output" == *"sasuke: EXIT trap draft_review fallback"* ]]
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

@test "description wrapper dict AC count sends draft review" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_normal
  acceptance_criteria:
    description:
      - "dict wrapper first AC"
      - "dict wrapper second AC"
YAML

    run_draft_review "cmd_normal"

    [ "$status" -eq 0 ]
    [[ "$output" == *"draft_review: SENT (gunshi)"* ]]
}

@test "karo_direct task without local ACs counts ACs from malformed archived cmd source" {
    mkdir -p "$TEST_PROJECT/queue/archive/cmds"
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_karo_archive
  task_id: cmd_karo_archive_exact
  task_type: exact
YAML
    cat > "$TEST_PROJECT/queue/archive/cmds/cmd_karo_archive_completed_20260512.yaml" <<'YAML'
commands:
  cmd_karo_archive:
    title: "archive cmd"
    acceptance_criteria:
      - description: "first AC"
      - description: "second AC"
      - description: "third AC"
    quality_gate:
      q11_not_already_done: "grep -n 'MIN_SAMPLES.*inject\|初回.*保証' scripts/deploy_task.sh"
YAML

    run_draft_review "cmd_karo_archive"

    [ "$status" -eq 0 ]
    [[ "$output" == *"draft_review: SENT (gunshi)"* ]]
    run cat "$TEST_PROJECT/logs/inbox_write_calls.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"gunshi draft cmd_karo_archive レビュー依頼。"* ]]
    [[ "$output" == *"ninja=sasuke。 review_draft karo"* ]]
}

@test "invalid AC count output warns and still sends draft review" {
    run run_draft_review_with_invalid_count "$TEST_PROJECT/queue/tasks/sasuke.yaml"

    [ "$status" -eq 0 ]
    [[ "$output" == *"draft_review: WARN (ac_count invalid: not-a-number; sending review)"* ]]
    [[ "$output" == *"draft_review: SENT (gunshi)"* ]]
}

@test "failed AC count command warns and still sends draft review" {
    run run_draft_review_with_failed_count "$TEST_PROJECT/queue/tasks/sasuke.yaml"

    [ "$status" -eq 0 ]
    [[ "$output" == *"draft_review: WARN (ac_count unavailable; sending review)"* ]]
    [[ "$output" == *"draft_review: SENT (gunshi)"* ]]
}

@test "resolve_cmd preserves purpose containing shell pipe operators" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_2548_pipe:
    estimated_minutes: 10
    title: "pipe purpose"
    project: infra
    scope_mode: exact
    purpose: "trim_cmd_chronicle || true を保持し、後続文も切り詰めない"
    acceptance_criteria:
      - description: "purpose is preserved"
      - description: "draft review is sent"
YAML

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'YAML'
task:
  status: idle
YAML

    run deploy_task_template_only sasuke cmd_2548_pipe
    [ "$status" -eq 0 ]

    run python3 - <<EOF
import yaml
from pathlib import Path

data = yaml.safe_load(Path("$TEST_PROJECT/queue/tasks/sasuke.yaml").read_text(encoding="utf-8"))
purpose = data["task"]["purpose"]
assert purpose == "trim_cmd_chronicle || true を保持し、後続文も切り詰めない", purpose
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
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

@test "already reviewed cmd skips draft review without marker" {
    mkdir -p "$TEST_PROJECT/logs"
    cat > "$TEST_PROJECT/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_normal
  review_type: draft
  verdict: APPROVE
  confidence: HIGH
YAML

    run_draft_review "cmd_normal"

    [ "$status" -eq 0 ]
    [[ "$output" == *"draft_review: SKIP (already reviewed: cmd_normal)"* ]]
    [ ! -e "$TEST_PROJECT/queue/draft_review_started/cmd_normal.draft_review.started" ]
    [ ! -f "$TEST_PROJECT/logs/inbox_write_calls.log" ]
}

@test "CI RED title skips draft review" {
    run_draft_review "cmd_ci_red"

    [ "$status" -eq 0 ]
    [[ "$output" == *"draft_review: SKIP (CI RED)"* ]]
    [ ! -f "$TEST_PROJECT/logs/inbox_write_calls.log" ]
}

@test "single AC task sends draft review" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_single_ac
  acceptance_criteria:
    - id: AC1
      description: "軽微修正"
YAML

    run_draft_review "cmd_single_ac"

    [ "$status" -eq 0 ]
    [[ "$output" == *"draft_review: SENT"* ]]
    [ -f "$TEST_PROJECT/logs/inbox_write_calls.log" ]
}

@test "SKIP_DRAFT_REVIEW=1 skips draft review" {
    run run_draft_review_skipped "$TEST_PROJECT/queue/tasks/sasuke.yaml"

    [ "$status" -eq 0 ]
    [[ "$output" == *"draft_review: SKIP (env)"* ]]
    [ ! -f "$TEST_PROJECT/logs/inbox_write_calls.log" ]
}

@test "direct detector deployment fails closed without action conversion and FP measurement" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'YAML'
task:
  project: infra
  command: "新規gateを追加して警告を出す"
YAML

    run deploy_task_direct_quality_contract_precheck "$TEST_PROJECT/queue/tasks/sasuke.yaml"

    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: direct deployment detector quality contract failed"* ]]
}

@test "direct detector deployment accepts action conversion and FP measurement" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'YAML'
task:
  project: infra
  command: "新規gateを追加し、BLOCKしてdetector_fp_rateでFP率計測する"
YAML

    run deploy_task_direct_quality_contract_precheck "$TEST_PROJECT/queue/tasks/sasuke.yaml"

    [ "$status" -eq 0 ]
    [[ "$output" == *"quality_contract: PASS"* ]]
}

@test "structured direct detector quality contract is canonical YAML and not a false positive" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'YAML'
task:
  project: infra
  purpose: "新規gateを追加する: 日本語と引用符 'single' / \"double\""
  acceptance_criteria:
    - id: AC1
      description: action conversionはBLOCKして停止する
    - id: AC2
      description: gate_fire_logとdetector_fp_rateで偽陽性率を計測する
  quality_gate:
    action_conversion: "欠落時はBLOCK"
    fp_measurement: "false_positiveを計測"
YAML

    run_quality_contract "$TEST_PROJECT/queue/tasks/sasuke.yaml"

    [ "$status" -eq 0 ]
    [ "$output" = "PASS" ]
}

@test "structured direct detector quality contract fails closed for each missing requirement" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'YAML'
task:
  project: infra
  purpose: 新規hookを追加する
  acceptance_criteria:
    - description: 実装後に通知する
  quality_gate:
    note: 品質を確認する
YAML

    run_quality_contract "$TEST_PROJECT/queue/tasks/sasuke.yaml"

    [ "$status" -eq 0 ]
    [ "$output" = "WARN(action=missing,fp=missing)" ]

    sed -i 's/実装後に通知する/BLOCKして停止する/' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    run_quality_contract "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$output" = "WARN(action=pass,fp=missing)" ]

    sed -i 's/品質を確認する/detector_fp_rateで計測する/' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    run_quality_contract "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$output" = "PASS" ]
}

@test "non-candidate structured task remains not applicable" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'YAML'
task:
  project: infra
  acceptance_criteria:
    - description: 既存の文書を確認する
  quality_gate:
    action_conversion: BLOCK
    fp_measurement: gate_fire_log
YAML

    run_quality_contract "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "NOT_APPLICABLE" ]
}

@test "block scalar and heredoc-like structured text retain quality contract meaning" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'YAML'
task:
  project: infra
  purpose: |
    新規gateを追加する。
    cat <<'CHECK'
    引用符: "値"
    CHECK
  acceptance_criteria:
    - description: |
        欠落した場合はBLOCKして停止する。
  quality_gate:
    fp_measurement: |
      gate_fire_log と detector_fp_rate で偽陽性を計測する。
YAML

    run_quality_contract "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "PASS" ]
}

@test "linked-worktree task path uses the same read-only projection" {
    mkdir -p "$TEST_PROJECT/.karo_worktrees/feature/queue/tasks"
    cat > "$TEST_PROJECT/.karo_worktrees/feature/queue/tasks/sasuke.yaml" <<'YAML'
task:
  project: infra
  acceptance_criteria:
    - description: 新規hook追加時はBLOCKして停止する
  quality_gate:
    fp_measurement: gate_fire_logでdetector_fp_rateを計測する
YAML
    before="$(sha256sum "$TEST_PROJECT/.karo_worktrees/feature/queue/tasks/sasuke.yaml")"

    run_quality_contract "$TEST_PROJECT/.karo_worktrees/feature/queue/tasks/sasuke.yaml"

    [ "$status" -eq 0 ]
    [ "$output" = "PASS" ]
    [ "$(sha256sum "$TEST_PROJECT/.karo_worktrees/feature/queue/tasks/sasuke.yaml")" = "$before" ]
}
