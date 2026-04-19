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
}

setup() {
    deploy_task_scaffold "tmpl_gen"
    # shellcheck disable=SC1090
    source "$TEST_PROJECT/scripts/lib/field_get.sh"
}

teardown() {
    deploy_task_teardown
}

task_file() {
    printf '%s\n' "$TEST_PROJECT/queue/tasks/sasuke.yaml"
}

read_task_report_path() {
    FIELD_GET_NO_LOG=1 field_get "$(task_file)" "report_path" "" 2>/dev/null
}

# ─── Helper: gitignore テスト用 git 環境セットアップ ───
_setup_git_project() {
    git -C "$TEST_PROJECT" init --quiet
    printf 'outputs/\n' > "$TEST_PROJECT/.gitignore"
}

# ─── Helper: recon テンプレート fixture 作成 ───
# 結果は _RECON_REPORT_FILE にセットされる
_setup_recon_report_fixture() {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "recon template test"
  task_type: recon
  acceptance_criteria:
    - ac1: investigate target
EOF

    # CMD_ID regex拡張(cmd_[a-zA-Z0-9_]+)によりcmd_testがCMD_IDとして検出される
    # → resolve_cmd_to_taskがSTK必須。STKにcmd_testエントリを追加
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_test:
    id: cmd_test
    title: 'recon template test'
    project: infra
    type: recon
    purpose: 'test purpose'
    status: delegated
EOF

    deploy_task_template_only sasuke cmd_test

    _RECON_REPORT_FILE=$(find "$TEST_PROJECT/queue/reports" -maxdepth 1 -name 'sasuke_report*.yaml' | head -1)
    [ -n "$_RECON_REPORT_FILE" ]
}

# ═══════════════════════════════════════════════════════════
# gitignore commit check tests (from test_deploy_task_gitignore_commit_check.bats)
# cmd_1838: gitignore対象ファイルのみ変更するcmdでcommit check=noが自動設定される
# ═══════════════════════════════════════════════════════════

@test "gitignore対象ファイルのみ変更するcmdでcommit check=noが自動設定される" {
    _setup_git_project

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "gitignore commit check test"
  task_type: impl
  parent_cmd: cmd_1838
  task_id: cmd_1838_impl
  project: infra
  target_path: "outputs/test_result.csv"
  acceptance_criteria:
    - id: AC1
      description: "outputs/にCSVを出力する"
EOF

    deploy_task_template_only sasuke
    local report_path="$TEST_PROJECT/$(read_task_report_path)"

    run python3 - <<PYEOF
import yaml
from pathlib import Path
report = Path("$report_path")
data = yaml.safe_load(report.read_text(encoding="utf-8"))
bc = data["binary_checks"]
commit_items = bc.get("commit", [])
assert len(commit_items) >= 1, f"commit checkが存在しない: {bc}"
commit_result = commit_items[0].get("result", "")
assert commit_result == "no", f"commit checkのresultが'no'でない: {commit_result!r}"
print("OK")
PYEOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "gitignore対象外ファイルのcmdではcommit checkは空のまま" {
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

    deploy_task_template_only sasuke
    local report_path="$TEST_PROJECT/$(read_task_report_path)"

    run python3 - <<PYEOF
import yaml
from pathlib import Path
report = Path("$report_path")
data = yaml.safe_load(report.read_text(encoding="utf-8"))
bc = data["binary_checks"]
commit_items = bc.get("commit", [])
assert len(commit_items) >= 1, f"commit checkが存在しない: {bc}"
commit_result = commit_items[0].get("result", "")
assert commit_result == "", f"commit checkのresultが空でない: {commit_result!r}"
print("OK")
PYEOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "研究cmdではcommit checkにwaive_reason付きresult:noを自動注入する" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "research commit auto waive test"
  task_type: impl
  scope_mode: RESEARCH
  parent_cmd: cmd_1946
  task_id: cmd_1946_research_scope
  project: infra
  acceptance_criteria:
    - id: AC1
      description: "研究ログを更新する"
EOF

    deploy_task_template_only sasuke
    local scope_report_path="$TEST_PROJECT/$(read_task_report_path)"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "research output auto waive test"
  task_type: impl
  parent_cmd: cmd_1946
  task_id: cmd_1946_research_target
  project: infra
  target_path:
    - outputs/research.csv
    - docs/research/cmd_1946_notes.md
  acceptance_criteria:
    - id: AC1
      description: "研究成果を保存する"
EOF

    deploy_task_template_only sasuke
    local target_report_path="$TEST_PROJECT/$(read_task_report_path)"

    run python3 - <<PYEOF
import yaml
from pathlib import Path

def assert_commit_waived(path_str):
    data = yaml.safe_load(Path(path_str).read_text(encoding="utf-8"))
    commit_items = data["binary_checks"].get("commit", [])
    assert len(commit_items) >= 1, f"commit checkが存在しない: {data['binary_checks']}"
    item = commit_items[0]
    assert item.get("result") == "no", f"commit resultが'no'でない: {item!r}"
    assert item.get("waive_reason"), f"waive_reasonが空: {item!r}"

assert_commit_waived("$scope_report_path")
assert_commit_waived("$target_report_path")
print("OK")
PYEOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# ═══════════════════════════════════════════════════════════
# monthly and scout_exempt tests (from test_deploy_task_monthly_and_scout_exempt.bats)
# ═══════════════════════════════════════════════════════════

@test "scout_exempt=true + impl taskでcommit checkが注入される (GP-190修正)" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "scout exempt commit check test"
  task_type: impl
  parent_cmd: cmd_gp183
  task_id: cmd_gp183_impl
  project: infra
  scout_exempt: true
  acceptance_criteria:
    - id: AC1
      description: "report templateのみ更新する"
EOF

    deploy_task_template_only sasuke
    local report_path="$TEST_PROJECT/$(read_task_report_path)"

    run python3 - <<PYEOF
import yaml
from pathlib import Path
report = Path("$report_path")
data = yaml.safe_load(report.read_text(encoding="utf-8"))
assert "commit" in data["binary_checks"], f"commit checkが注入されていない(impl taskは必須): {data['binary_checks']}"
commit_items = data["binary_checks"]["commit"]
assert len(commit_items) >= 1, f"commit checkが空: {commit_items}"
print("OK")
PYEOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "waive_ac指定のACはwaive_reason付きresult:noで初期化される" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "waive_ac field test"
  task_type: impl
  parent_cmd: cmd_1946
  task_id: cmd_1946_waive_ac
  project: infra
  waive_ac: [AC5]
  acceptance_criteria:
    - id: AC1
      description: "通常ACは空のまま残す"
    - id: AC5
      description: "後続レビューで免除する"
EOF

    deploy_task_template_only sasuke
    local report_path="$TEST_PROJECT/$(read_task_report_path)"

    run python3 - <<PYEOF
import yaml
from pathlib import Path
data = yaml.safe_load(Path("$report_path").read_text(encoding="utf-8"))
ac1_items = data["binary_checks"]["AC1"]
ac5_items = data["binary_checks"]["AC5"]
assert all(item.get("result", "") == "" for item in ac1_items), ac1_items
assert len(ac5_items) >= 1, ac5_items
assert all(item.get("result") == "no" for item in ac5_items), ac5_items
assert all(item.get("waive_reason") == "waive_ac指定" for item in ac5_items), ac5_items
print("OK")
PYEOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "recon taskではcommit checkを引き続き注入しない" {
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

    deploy_task_template_only sasuke
    local report_path="$TEST_PROJECT/$(read_task_report_path)"

    run python3 - <<PYEOF
import yaml
from pathlib import Path
report = Path("$report_path")
data = yaml.safe_load(report.read_text(encoding="utf-8"))
assert "commit" not in data["binary_checks"], data["binary_checks"]
print("OK")
PYEOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AC descriptionにmonthlyを含む場合はdescription由来checkへ進行中月除外を付記する" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "monthly annotation test"
  task_type: impl
  parent_cmd: cmd_gp184
  task_id: cmd_gp184_impl
  project: infra
  acceptance_criteria:
    - id: AC1
      description: "monthly returns parityを確認する。差分が0である"
EOF

    deploy_task_template_only sasuke
    local report_path="$TEST_PROJECT/$(read_task_report_path)"

    run python3 - <<PYEOF
import yaml
from pathlib import Path
report = Path("$report_path")
data = yaml.safe_load(report.read_text(encoding="utf-8"))
checks = data["binary_checks"]["AC1"]
texts = [item["check"] for item in checks]
assert any("進行中月除外" in text for text in texts), texts
print("OK")
PYEOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AC descriptionに月次を含む場合は手書きbinary_checksにも進行中月除外を付記する" {
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

    deploy_task_template_only sasuke
    local report_path="$TEST_PROJECT/$(read_task_report_path)"

    run python3 - <<PYEOF
import yaml
from pathlib import Path
report = Path("$report_path")
data = yaml.safe_load(report.read_text(encoding="utf-8"))
checks = data["binary_checks"]["AC1"]
assert "進行中月除外" in checks[0]["check"], checks
print("OK")
PYEOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "強化cmdの報告テンプレートにbefore/after/regressionを追加する" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "強化 — GP/改善にbefore/after退化計測を義務化"
  task_type: impl
  parent_cmd: cmd_1941
  task_id: cmd_1941_impl
  project: infra
  acceptance_criteria:
    - id: AC1
      description: "報告テンプレートを更新する"
EOF

    deploy_task_template_only sasuke
    local report_path="$TEST_PROJECT/$(read_task_report_path)"

    run python3 - <<PYEOF
import yaml
from pathlib import Path
report = Path("$report_path")
data = yaml.safe_load(report.read_text(encoding="utf-8"))
assert data["before_metrics"]["summary"] == "", data
assert data["after_metrics"]["summary"] == "", data
assert data["regression"] == "", data
print("OK")
PYEOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "報告テンプレートにsimplicity_checkを追加する" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  title: "simplicity field test"
  task_type: impl
  parent_cmd: cmd_2019
  task_id: cmd_2019_impl
  project: infra
  acceptance_criteria:
    - id: AC1
      description: "報告テンプレートにsimplicity_check行を追加する"
EOF

    deploy_task_template_only sasuke
    local report_path="$TEST_PROJECT/$(read_task_report_path)"

    run python3 - <<PYEOF
import yaml
from pathlib import Path
report = Path("$report_path")
data = yaml.safe_load(report.read_text(encoding="utf-8"))
assert "simplicity_check" in data, data
assert data["simplicity_check"] == "", data["simplicity_check"]
print("OK")
PYEOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# ═══════════════════════════════════════════════════════════
# recon report template tests (from test_deploy_task_recon_template.bats)
# ═══════════════════════════════════════════════════════════

@test "recon report template includes dependency_constraints field" {
    _setup_recon_report_fixture
    local REPORT_FILE="$_RECON_REPORT_FILE"

    run grep -Fq "dependency_constraints" "$REPORT_FILE"
    [ "$status" -eq 0 ]
}

@test "recon report template includes all 5 implementation_readiness fields" {
    _setup_recon_report_fixture
    local REPORT_FILE="$_RECON_REPORT_FILE"

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
