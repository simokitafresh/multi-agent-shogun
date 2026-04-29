#!/usr/bin/env bats
# test_deploy_task_template_generation.bats
# Consolidated from:
#   test_deploy_task_gitignore_commit_check (2)
#   test_deploy_task_monthly_and_scout_exempt (4)
#   test_deploy_task_recon_template (2)
#   test_deploy_task_handwritten_bc (6)
# Total: 14 tests

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
    export TEMPLATE_FIXTURE_ROOT
    TEMPLATE_FIXTURE_ROOT="$(mktemp -d "$BATS_TMPDIR/deploy_task_template_generation.XXXXXX")"
    export TEMPLATE_FIXTURE_CACHE
    TEMPLATE_FIXTURE_CACHE="$(_fixture_cache_dir)"
    if [ -d "$TEMPLATE_FIXTURE_CACHE" ] && find "$TEMPLATE_FIXTURE_CACHE" -maxdepth 1 -name '*.yaml' | grep -q .; then
        cp "$TEMPLATE_FIXTURE_CACHE"/*.yaml "$TEMPLATE_FIXTURE_ROOT/"
        return 0
    fi
    _generate_report_fixtures
    mkdir -p "$TEMPLATE_FIXTURE_CACHE"
    cp "$TEMPLATE_FIXTURE_ROOT"/*.yaml "$TEMPLATE_FIXTURE_CACHE/"
}

teardown_file() {
    [ -n "${TEMPLATE_FIXTURE_ROOT:-}" ] && [ -d "$TEMPLATE_FIXTURE_ROOT" ] && rm -rf "$TEMPLATE_FIXTURE_ROOT"
    [ -n "$DEPLOY_TASK_TEMPLATE_DIR" ] && [ -d "$DEPLOY_TASK_TEMPLATE_DIR" ] && rm -rf "$DEPLOY_TASK_TEMPLATE_DIR"
}

_fixture_project_start() {
    deploy_task_scaffold "tmpl_gen"
    # shellcheck disable=SC1090
    source "$TEST_PROJECT/scripts/lib/field_get.sh"
}

_fixture_project_end() {
    deploy_task_teardown
    unset TEST_TMPDIR TEST_PROJECT
}

_save_report_fixture() {
    local fixture_name="$1"
    local report_rel
    report_rel=$(FIELD_GET_NO_LOG=1 field_get "$TEST_PROJECT/queue/tasks/sasuke.yaml" "report_path" "" 2>/dev/null)
    cp "$TEST_PROJECT/$report_rel" "$TEMPLATE_FIXTURE_ROOT/${fixture_name}.yaml"
}

_fixture_cache_dir() {
    local key
    key=$(
        {
            cksum tests/unit/test_deploy_task_template_generation.bats
            cksum tests/helpers/deploy_task_scaffold.bash
            cksum scripts/deploy_task.sh
        } | cksum | awk '{print $1}'
    )
    printf '/tmp/deploy_task_template_generation_cache_%s\n' "$key"
}

_build_report_fixture() {
    local fixture_name="$1"
    local task_file="$TEST_PROJECT/queue/tasks/sasuke.yaml"
    (
        # shellcheck disable=SC1090,SC1091
        export DEPLOY_TASK_LIB_ONLY=1
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        log() { :; }
        NINJA_NAME="sasuke"

        local task_id parent_cmd project
        yaml_field_set "$task_file" "task" "report_filename" ""
        yaml_field_set "$task_file" "task" "report_path" ""
        inject_report_filename "$task_file" || true

        task_id=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_id" "")
        parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "")
        project=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "project" "")
        generate_report_template "$NINJA_NAME" "$task_id" "$parent_cmd" "$project"
    )
    _save_report_fixture "$fixture_name"
}

_build_report_fixture_full() {
    local fixture_name="$1"
    deploy_task_template_only sasuke
    _save_report_fixture "$fixture_name"
}

fixture_report_path() {
    printf '%s\n' "$TEMPLATE_FIXTURE_ROOT/$1.yaml"
}

report_block() {
    local report_file="$1"
    local block_name="$2"
    awk -v key="$block_name" '
        $0 ~ ("^  " key ":$") { in_block=1; next }
        in_block && /^  [A-Za-z0-9_]+:/ { exit }
        in_block { print }
    ' "$report_file"
}

_generate_report_fixtures() {
    _fixture_project_start
    _setup_git_project
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "強化 monthly waive scout fixture"
  task_type: impl
  parent_cmd: cmd_fixture_combo
  task_id: cmd_fixture_combo_impl
  project: infra
  scout_exempt: true
  waive_ac: [AC5]
  target_path: "outputs/test_result.csv"
  acceptance_criteria:
    - id: AC1
      description: "monthly returns parityを確認する。差分が0である"
    - id: AC5
      description: "後続レビューで免除する"
    - id: AC6
      description: "月次データの確認"
      binary_checks:
        - check: "月次リターン差分を確認したか"
EOF
    _build_report_fixture combo_impl
    _fixture_project_end

    _fixture_project_start
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "waive_ac field test"
  task_type: impl
  parent_cmd: cmd_fixture_waive
  task_id: cmd_fixture_waive_impl
  project: infra
  waive_ac: [AC5]
  acceptance_criteria:
    - id: AC1
      description: "通常ACは空のまま残す"
    - id: AC5
      description: "後続レビューで免除する"
EOF
    _build_report_fixture_full waive_ac
    _fixture_project_end

    _fixture_project_start
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "recon commit skip test"
  task_type: recon
  parent_cmd: cmd_gp183
  task_id: cmd_gp183_recon
  project: infra
  acceptance_criteria:
    - id: AC1
      description: "既存の挙動を確認する"
EOF
    _build_report_fixture recon_template
    _fixture_project_end

    _fixture_project_start
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "research commit auto waive test"
  task_type: impl
  scope_mode: RESEARCH
  parent_cmd: cmd_1946
  task_id: cmd_1946_research
  project: infra
  target_path:
    - outputs/research.csv
    - docs/research/cmd_1946_notes.md
  acceptance_criteria:
    - id: AC1
      description: "研究成果を保存する"
EOF
    _build_report_fixture research
    _fixture_project_end

    _fixture_project_start
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "monthly annotation test"
  task_type: impl
  parent_cmd: cmd_fixture_monthly
  task_id: cmd_fixture_monthly_impl
  project: infra
  acceptance_criteria:
    - id: AC1
      description: "monthly returns parityを確認する。差分が0である"
EOF
    _build_report_fixture_full monthly_description
    _fixture_project_end

    _fixture_project_start
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "monthly handwritten binary check test"
  task_type: impl
  parent_cmd: cmd_gp184
  task_id: cmd_gp184_impl_handwritten
  project: infra
  acceptance_criteria:
    - id: AC1
      description: "月次データの確認"
      binary_checks:
        - check: "月次リターン差分を確認したか"
EOF
    _build_report_fixture_full monthly_handwritten
    _fixture_project_end

    _fixture_project_start
    _setup_git_project
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "non-gitignore commit check test"
  task_type: impl
  parent_cmd: cmd_1838
  task_id: cmd_1838_impl2
  project: infra
  target_path: "scripts/deploy_task.sh"
  acceptance_criteria:
    - id: AC1
      description: "scripts/deploy_task.shを修正する"
EOF
    _build_report_fixture non_gitignore
    _fixture_project_end
}

# ─── Helper: gitignore テスト用 git 環境セットアップ ───
_setup_git_project() {
    git -C "$TEST_PROJECT" init --quiet
    printf 'outputs/\n' > "$TEST_PROJECT/.gitignore"
}

# ═══════════════════════════════════════════════════════════
# gitignore commit check tests (from test_deploy_task_gitignore_commit_check.bats)
# cmd_1838: gitignore対象ファイルのみ変更するcmdでcommit check=noが自動設定される
# ═══════════════════════════════════════════════════════════

@test "gitignore対象ファイルのみ変更するcmdでcommit check=noが自動設定される" {
    local report_path
    report_path="$(fixture_report_path combo_impl)"

    local commit_block
    commit_block="$(report_block "$report_path" "commit")"
    [[ "$commit_block" == *'check: git commitが完了したか(untracked/modified=0)'* ]]
    [[ "$commit_block" == *"result: 'no'"* ]]
}

@test "gitignore対象外ファイルのcmdではcommit checkは空のまま" {
    local report_path
    report_path="$(fixture_report_path non_gitignore)"

    local commit_block
    commit_block="$(report_block "$report_path" "commit")"
    [[ "$commit_block" == *'check: git commitが完了したか(untracked/modified=0)'* ]]
    [[ "$commit_block" == *"result: ''"* ]]
}

@test "研究cmdではcommit checkにwaive_reason付きresult:noを自動注入する" {
    local report_path
    report_path="$(fixture_report_path research)"

    local commit_block
    commit_block="$(report_block "$report_path" "commit")"
    [[ "$commit_block" == *"result: 'no'"* ]]
    [[ "$commit_block" == *"waive_reason: '研究cmd: commit不要'"* ]]
}

# ═══════════════════════════════════════════════════════════
# monthly and scout_exempt tests (from test_deploy_task_monthly_and_scout_exempt.bats)
# ═══════════════════════════════════════════════════════════

@test "scout_exempt=true + impl taskでcommit checkが注入される (GP-190修正)" {
    local report_path
    report_path="$(fixture_report_path combo_impl)"

    local commit_block
    commit_block="$(report_block "$report_path" "commit")"
    [[ -n "$commit_block" ]]
    [[ "$commit_block" == *'check: git commitが完了したか(untracked/modified=0)'* ]]
}

@test "waive_ac指定のACはwaive_reason付きresult:noで初期化される" {
    local report_path
    report_path="$(fixture_report_path waive_ac)"

    local ac1_block ac5_block
    ac1_block="$(report_block "$report_path" "AC1")"
    ac5_block="$(report_block "$report_path" "AC5")"
    [[ "$ac5_block" == *"result: 'no'"* ]]
    [[ "$ac5_block" == *'waive_reason: waive_ac指定'* ]]
}

@test "recon taskではcommit checkを引き続き注入しない" {
    local report_path
    report_path="$(fixture_report_path recon_template)"

    local commit_block
    commit_block="$(report_block "$report_path" "commit")"
    [ -z "$commit_block" ]
}

@test "AC descriptionにmonthlyを含む場合はdescription由来checkへ進行中月除外を付記する" {
    local report_path
    report_path="$(fixture_report_path monthly_description)"

    local ac1_block
    ac1_block="$(report_block "$report_path" "AC1")"
    [[ "$ac1_block" == *'進行中月除外'* ]]
}

@test "AC descriptionに月次を含む場合は手書きbinary_checksにも進行中月除外を付記する" {
    local report_path
    report_path="$(fixture_report_path monthly_handwritten)"

    local ac1_block
    ac1_block="$(report_block "$report_path" "AC1")"
    [[ "$ac1_block" == *'進行中月除外'* ]]
}

@test "強化cmdの報告テンプレートにbefore/after/regressionを追加する" {
    local report_path
    report_path="$(fixture_report_path combo_impl)"

    grep -Fq 'before_metrics:' "$report_path"
    grep -Fq 'after_metrics:' "$report_path"
    grep -Fq 'regression: ""' "$report_path"
    grep -Fq 'summary: ""  # 実装前の計測値' "$report_path"
    grep -Fq 'summary: ""  # 実装後の計測値' "$report_path"
}

@test "報告テンプレートにsimplicity_checkを追加する" {
    local report_path
    report_path="$(fixture_report_path combo_impl)"

    grep -Fq 'simplicity_check: ""' "$report_path"
}

@test "報告テンプレートにself_gate_check 4項目をPASS初期値で注入する" {
    local report_path
    report_path="$(fixture_report_path combo_impl)"

    grep -Fq 'self_gate_check:' "$report_path"
    grep -Fq 'lesson_ref: PASS' "$report_path"
    grep -Fq 'lesson_candidate: PASS' "$report_path"
    grep -Fq 'status_valid: PASS' "$report_path"
    grep -Fq 'purpose_fit: PASS' "$report_path"
}

# ═══════════════════════════════════════════════════════════
# recon report template tests (from test_deploy_task_recon_template.bats)
# ═══════════════════════════════════════════════════════════

@test "recon report template includes dependency_constraints field" {
    local REPORT_FILE
    REPORT_FILE="$(fixture_report_path recon_template)"

    run grep -Fq "dependency_constraints" "$REPORT_FILE"
    [ "$status" -eq 0 ]
}

@test "recon report template includes all 5 implementation_readiness fields" {
    local REPORT_FILE
    REPORT_FILE="$(fixture_report_path recon_template)"

    run grep -Fq "files_to_modify" "$REPORT_FILE"
    [ "$status" -eq 0 ]
    run grep -Fq "affected_files" "$REPORT_FILE"
    [ "$status" -eq 0 ]
    run grep -Fq "related_tests" "$REPORT_FILE"
    [ "$status" -eq 0 ]
    run grep -Fq "edge_cases" "$REPORT_FILE"
    [ "$status" -eq 0 ]
    run grep -Fq "dependency_constraints" "$REPORT_FILE"
    [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════
# handwritten binary_checks tests (from test_deploy_task_handwritten_bc.bats)
# AC1: hand-written YAML explicit check extraction
# AC2: scout_gate AC id confusion
# ═══════════════════════════════════════════════════════════

@test "explicit check AWK extracts AC ids from hand-written YAML (- id: ACx same line)" {
    # Hand-written format: "  - id: AC1" on same line (NOT yaml.dump "    id: AC1" on separate line)
    local task_yaml
    task_yaml=$(cat <<'YAML'
task:
  acceptance_criteria:
  - id: AC1
    criteria: "first check"
    - check: "check item 1"
  - id: AC2
    criteria: "second check"
    - check: "check item 2"
YAML
)

    local result
    result=$(echo "$task_yaml" | awk '
        /^  acceptance_criteria:/ { in_ac=1; next }
        in_ac && /^  [a-z]/ { exit }
        in_ac && /^  - / {
            if (cur_id != "" && cc > 0) {
                printf "  %s:\n", cur_id
                for (i=1; i<=cc; i++) { printf "  - check: \"%s\"\n    result: \"\"  # yes or no\n", chk[i] }
            }
            cur_id=""; cc=0
            if (/id:/) { s=$0; sub(/.*id:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); cur_id=s }
        }
        in_ac && /    id:/ { sub(/.*id:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); cur_id=$0 }
        in_ac && /    - check:/ { sub(/.*- check:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); cc++; chk[cc]=$0 }
        END {
            if (cur_id != "" && cc > 0) {
                printf "  %s:\n", cur_id
                for (i=1; i<=cc; i++) { printf "  - check: \"%s\"\n    result: \"\"  # yes or no\n", chk[i] }
            }
        }
    ')

    # AC1 and AC2 should both appear
    echo "$result" | grep -q "AC1:" || { echo "AC1 not found in: $result"; false; }
    echo "$result" | grep -q "AC2:" || { echo "AC2 not found in: $result"; false; }
    echo "$result" | grep -q "check item 1" || { echo "check item 1 not found in: $result"; false; }
    echo "$result" | grep -q "check item 2" || { echo "check item 2 not found in: $result"; false; }
}

@test "explicit check AWK still works with yaml.dump format (    id: ACx on separate line)" {
    # yaml.dump format: id on separate indented line
    local task_yaml
    task_yaml=$(cat <<'YAML'
task:
  acceptance_criteria:
  - criteria: "first check"
    id: AC1
    - check: "check item 1"
  - criteria: "second check"
    id: AC2
    - check: "check item 2"
YAML
)

    local result
    result=$(echo "$task_yaml" | awk '
        /^  acceptance_criteria:/ { in_ac=1; next }
        in_ac && /^  [a-z]/ { exit }
        in_ac && /^  - / {
            if (cur_id != "" && cc > 0) {
                printf "  %s:\n", cur_id
                for (i=1; i<=cc; i++) { printf "  - check: \"%s\"\n    result: \"\"  # yes or no\n", chk[i] }
            }
            cur_id=""; cc=0
            if (/id:/) { s=$0; sub(/.*id:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); cur_id=s }
        }
        in_ac && /    id:/ { sub(/.*id:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); cur_id=$0 }
        in_ac && /    - check:/ { sub(/.*- check:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); cc++; chk[cc]=$0 }
        END {
            if (cur_id != "" && cc > 0) {
                printf "  %s:\n", cur_id
                for (i=1; i<=cc; i++) { printf "  - check: \"%s\"\n    result: \"\"  # yes or no\n", chk[i] }
            }
        }
    ')

    echo "$result" | grep -q "AC1:" || { echo "AC1 not found in: $result"; false; }
    echo "$result" | grep -q "AC2:" || { echo "AC2 not found in: $result"; false; }
}

@test "scout_gate AWK does not confuse AC id with cmd id in shogun_to_karo.yaml" {
    # shogun_to_karo.yaml with acceptance_criteria containing "id: AC1" lines
    local stk_yaml
    stk_yaml=$(cat <<'YAML'
commands:
  cmd_1656:
    status: pending
    title: "test cmd"
    acceptance_criteria:
      - id: AC1
        description: "first"
      - id: AC2
        description: "second"
    scout_exempt: true
YAML
)

    local result
    result=$(echo "$stk_yaml" | awk -v cmd="cmd_1656" '
        /^  [a-zA-Z_].*:$/ { sub(/^[[:space:]]*/, ""); sub(/:$/, ""); cur_id=$0 }
        /^[[:space:]]*id:[[:space:]]/ { s=$0; sub(/.*id:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); if (s ~ /^cmd_/) cur_id=s }
        cur_id == cmd && /scout_exempt:[[:space:]]*true/ { print "true"; exit }
    ')

    [ "$result" = "true" ] || { echo "Expected 'true' but got '$result'"; false; }
}

@test "scout_gate AWK detects scout_exempt with yaml.dump style id on separate line" {
    # yaml.dump format where id: cmd_xxx is on its own line
    local stk_yaml
    stk_yaml=$(cat <<'YAML'
commands:
  cmd_1700:
    status: pending
    id: cmd_1700
    title: "test cmd"
    acceptance_criteria:
    - criteria: "first"
      id: AC1
    - criteria: "second"
      id: AC2
    scout_exempt: true
YAML
)

    local result
    result=$(echo "$stk_yaml" | awk -v cmd="cmd_1700" '
        /^  [a-zA-Z_].*:$/ { sub(/^[[:space:]]*/, ""); sub(/:$/, ""); cur_id=$0 }
        /^[[:space:]]*id:[[:space:]]/ { s=$0; sub(/.*id:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); if (s ~ /^cmd_/) cur_id=s }
        cur_id == cmd && /scout_exempt:[[:space:]]*true/ { print "true"; exit }
    ')

    [ "$result" = "true" ] || { echo "Expected 'true' but got '$result'"; false; }
}

@test "scout_gate AWK detects scout_exempt with list format parent cmd id" {
    local stk_yaml
    stk_yaml=$(cat <<'YAML'
commands:
  - id: cmd_1805
    status: pending
    title: "list format cmd"
    acceptance_criteria:
      - id: AC1
        description: "first"
      - id: AC2
        description: "second"
    scout_exempt: true
YAML
)

    local result
    result=$(echo "$stk_yaml" | awk -v cmd="cmd_1805" '
        /^  [a-zA-Z_].*:$/ { sub(/^[[:space:]]*/, ""); sub(/:$/, ""); cur_id=$0 }
        /^[[:space:]]*-?[[:space:]]*id:[[:space:]]/ { s=$0; sub(/.*id:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); if (s ~ /^cmd_/) cur_id=s }
        cur_id == cmd && /scout_exempt:[[:space:]]*true/ { print "true"; exit }
    ')

    [ "$result" = "true" ] || { echo "Expected 'true' but got '$result'"; false; }
}

@test "AC overwrite preserves quoted lesson-injected description" {
    _fixture_project_start

    mkdir -p "$TEST_PROJECT/queue"
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_2404:
    status: delegated
    acceptance_criteria:
      AC1:
        description: "first injected AC"
      AC2:
        description: "second injected AC"
YAML

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'YAML'
task:
  _ac_task_id: null
  _ac_worker_id: null
  ac_version: old
  assigned_to: sasuke
  description: "【注入教訓】 必ず確認してから作業開始せよ\n  - L508: 6723ファイルのrg scan + 153ファイルのyaml.safe_load両方がWSL2\
  に支配される\n  ────────────────────────────────────────\n\n元の説明"
  parent_cmd: cmd_2404
  task_id: cmd_2404_normal
  project: infra
  acceptance_criteria:
  - id: AC1
    checks: []
YAML

    (
        export DEPLOY_TASK_LIB_ONLY=1
        # shellcheck disable=SC1090,SC1091
        source "$TEST_PROJECT/scripts/deploy_task.sh"
        log() { :; }
        inject_ac_version "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    )

    python3 - "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'PY'
import sys
import yaml

data = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
task = data['task']
assert '【注入教訓】' in task['description']
acs = task['acceptance_criteria']
assert len(acs) == 2
assert acs[0]['id'] == 'AC1'
assert acs[0]['checks'][0]['check'] == 'first injected AC'
assert acs[1]['id'] == 'AC2'
PY

    _fixture_project_end
}

@test "scout_gate AWK returns empty when scout_exempt is false" {
    local stk_yaml
    stk_yaml=$(cat <<'YAML'
commands:
  cmd_1656:
    status: pending
    acceptance_criteria:
      - id: AC1
        description: "first"
    scout_exempt: false
YAML
)

    local result
    result=$(echo "$stk_yaml" | awk -v cmd="cmd_1656" '
        /^  [a-zA-Z_].*:$/ { sub(/^[[:space:]]*/, ""); sub(/:$/, ""); cur_id=$0 }
        /^[[:space:]]*id:[[:space:]]/ { s=$0; sub(/.*id:[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); if (s ~ /^cmd_/) cur_id=s }
        cur_id == cmd && /scout_exempt:[[:space:]]*true/ { print "true"; exit }
    ')

    [ -z "$result" ] || { echo "Expected empty but got '$result'"; false; }
}
