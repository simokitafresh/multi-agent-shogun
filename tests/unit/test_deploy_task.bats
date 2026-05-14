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

    export TEST_GIT_ROOT
    TEST_GIT_ROOT="$(mktemp -d "$BATS_TMPDIR/test_git_root.XXXXXX")"
    git -C "$TEST_GIT_ROOT" init --quiet
    git -C "$TEST_GIT_ROOT" config user.name "Test User"
    git -C "$TEST_GIT_ROOT" config user.email "test@example.com"
    mkdir -p "$TEST_GIT_ROOT/scripts"
}

teardown() {
    deploy_task_teardown
    [ -n "${TEST_GIT_ROOT:-}" ] && [ -d "$TEST_GIT_ROOT" ] && rm -rf "$TEST_GIT_ROOT"
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

@test "deploy_task --direct cmd_training injects L4 purpose and four ACs" {
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
assert "L4修行" in task["purpose"]
acs = task["acceptance_criteria"]
assert list(acs.keys()) == ["AC1", "AC2", "AC3", "AC4"]
assert "改善点を3つ" in acs["AC1"]["description"]
assert "最高インパクト1件" in acs["AC2"]["description"]
assert "lesson_candidate found=true" in acs["AC3"]["description"]
assert "注入教訓から1件以上" in acs["AC4"]["description"]
assert "lessons_useful" in acs["AC4"]["description"]
for ac_id in ("AC1", "AC2", "AC3", "AC4"):
    assert acs[ac_id]["binary_checks"], ac_id
PY
}

@test "deploy_task --direct cmd_training overwrites pre-existing purpose and ACs with L4 template" {
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
assert list(acs.keys()) == ["AC1", "AC2", "AC3", "AC4"], f"ACs not overwritten to 4-AC template: {list(acs.keys())}"
assert "改善点を3つ" in acs["AC1"]["description"]
assert "最高インパクト1件" in acs["AC2"]["description"]
assert "lesson_candidate found=true" in acs["AC3"]["description"]
assert "注入教訓から1件以上" in acs["AC4"]["description"]
PY
}
