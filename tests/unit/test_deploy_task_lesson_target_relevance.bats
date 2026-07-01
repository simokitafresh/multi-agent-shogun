#!/usr/bin/env bats
# test_deploy_task_lesson_target_relevance.bats — universal lessons must still be file-relevant.

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "deploy_lesson_target_relevance"
    mkdir -p "$TEST_PROJECT/projects/infra"
}

teardown() {
    deploy_task_teardown
}

related_lesson_ids() {
    python3 - "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding='utf-8') as f:
    task = (yaml.safe_load(f) or {}).get('task', {})
for lesson in task.get('related_lessons') or []:
    print(lesson.get('id', ''))
PY
}

first_related_lesson_id() {
    python3 - "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding='utf-8') as f:
    task = (yaml.safe_load(f) or {}).get('task', {})
lessons = task.get('related_lessons') or []
if lessons:
    print(lessons[0].get('id', ''))
PY
}

@test "cmd_3020 AC1: target_filesなしuniversal教訓はtarget_path無関連なら注入されない" {
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L_UNRELATED_UNIVERSAL
    title: Android UI keyboard padding
    summary: Compose imePadding regression must be checked for mobile layouts
    content: Android screen layout keyboard resize behavior.
    tags: [universal]
    helpful_count: 100
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  project: infra
  task_id: cmd_3020_ac1
  parent_cmd: cmd_3020
  task_type: exact
  title: "deploy task lesson target relevance"
  description: "Fix lesson injection for deploy_task filtering"
  target_path: scripts/deploy_task.sh
EOF

    run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run related_lesson_ids
    [ "$status" -eq 0 ]
    [[ "$output" != *"L_UNRELATED_UNIVERSAL"* ]]
}

@test "cmd_3020 AC2: target_files設定済み教訓はtarget_path一致時に注入される" {
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L_DEPLOY_TARGET
    title: deploy_task target file matching
    summary: deploy_task target_files matching must be preserved
    content: scripts deploy_task target_files filter behavior.
    tags: [universal]
    target_files: [scripts/deploy_task.sh]
    helpful_count: 100
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  project: infra
  task_id: cmd_3020_ac2
  parent_cmd: cmd_3020
  task_type: exact
  title: "deploy task lesson target relevance"
  description: "Fix lesson injection for deploy_task filtering"
  target_path: scripts/deploy_task.sh
EOF

    run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run related_lesson_ids
    [ "$status" -eq 0 ]
    [[ "$output" == *"L_DEPLOY_TARGET"* ]]
}

@test "cmd_3020: target_filesなしuniversal教訓はtarget_path関連語があれば注入される" {
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L_RELATED_UNIVERSAL
    title: deploy_task lesson injection filter
    summary: deploy_task universal lessons need target_path relevance checks
    content: scripts deploy_task related_lessons filtering behavior.
    tags: [universal]
    helpful_count: 100
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  project: infra
  task_id: cmd_3020_related
  parent_cmd: cmd_3020
  task_type: exact
  title: "deploy task lesson target relevance"
  description: "Fix lesson injection for deploy_task filtering"
  target_path: scripts/deploy_task.sh
EOF

    run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run related_lesson_ids
    [ "$status" -eq 0 ]
    [[ "$output" == *"L_RELATED_UNIVERSAL"* ]]
}

@test "cmd_3062 AC2: target_path一致教訓はinfra汎用教訓より上位に注入される" {
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L_INFRA_GENERIC
    title: task status report deploy yaml gate lesson context
    summary: generic infra task deploy report yaml gate lesson context status
    content: generic infra task deploy report yaml gate lesson context status
    tags: [process]
    helpful_count: 999
  - id: L_SEMANTIC_INDEX_TARGET
    title: semantic index maintenance
    summary: semantic index aliases must preserve related_lessons links
    content: docs semantic index related lessons aliases concept map
    tags: [process]
    target_files: [docs/semantic-index/index.md]
    helpful_count: 1
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  project: infra
  task_id: cmd_3062_ac2
  parent_cmd: cmd_3062
  task_type: exact
  title: "update infra lesson injection"
  description: "Fix deploy_task lesson injection scoring for process tasks"
  purpose: "target_path matching lessons should rank above generic infra lessons"
  target_path: docs/semantic-index/index.md
EOF

    run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run first_related_lesson_id
    [ "$status" -eq 0 ]
    [ "$output" = "L_SEMANTIC_INDEX_TARGET" ]
}

@test "cmd_3466: target_files一致だけでキーワード0点教訓を注入しない" {
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L_PATH_ONLY_LOW_USEFUL
    title: unrelated report formatting
    summary: binary_checks and verdict report fields
    content: report yaml gate validation
    tags: [deploy]
    target_files: [scripts/deploy_task.sh]
    helpful_count: 999
  - id: L_KEYWORD_RELEVANT
    title: deploy task lesson scoring
    summary: deploy_task related_lessons scoring must use keyword relevance
    content: lesson injection scoring target path behavior
    when: deploy_task related_lessons keyword scoring
    tags: [deploy]
    helpful_count: 1
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  project: infra
  task_id: cmd_3466_path_only
  parent_cmd: cmd_3466
  task_type: impl
  title: "deploy matching score"
  description: "Improve deploy_task related_lessons keyword scoring"
  target_path: scripts/deploy_task.sh
EOF

    run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run related_lesson_ids
    [ "$status" -eq 0 ]
    [[ "$output" != *"L_PATH_ONLY_LOW_USEFUL"* ]]
    [[ "$output" == *"L_KEYWORD_RELEVANT"* ]]
}

@test "cmd_karo_hotfix_l828: queue/reports target_files match does not receive target boost" {
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L828_LIKE
    title: SKILL script reference evidence
    summary: record report counts
    content: skill script refs
    when: gate_skill_script_refs.shのWARNを解消する時
    tags: [reporting]
    target_files:
      - skills/*/SKILL.md
      - scripts/gates/gate_skill_script_refs.sh
      - queue/reports/*
    helpful_count: 999
  - id: L_REPORT_RELEVANT
    title: model comparison banner report
    summary: model comparison banner report evidence for runtime verification
    content: model comparison banner report evidence
    when: model comparison banner reportを作成する時
    tags: [reporting]
    helpful_count: 1
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  project: infra
  task_id: cmd_l828_report_artifact
  parent_cmd: cmd_l828
  task_type: impl
  tags: [reporting]
  title: "model comparison report"
  description: "Write model comparison banner report evidence"
  target_path: queue/reports/sasuke_report_cmd_l828.yaml
EOF

    run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run related_lesson_ids
    [ "$status" -eq 0 ]
    [[ "$output" != *"L828_LIKE"* ]]
    [[ "$output" == *"L_REPORT_RELEVANT"* ]]
}

@test "cmd_3466: tag fallback excludes tag-only helpful_count lessons without target_path match" {
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L_TAG_ONLY_GENERIC
    title: unrelated workflow procedure
    summary: generic process lesson unrelated to the target file
    content: process status report yaml
    tags: [deploy]
    helpful_count: 999
  - id: L_TARGET_FALLBACK
    title: unrelated fallback title
    summary: fallback only because target file matches
    content: no task query words here
    tags: [deploy]
    target_files: [scripts/deploy_task.sh]
    helpful_count: 1
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  project: infra
  task_id: cmd_3466_tag_fallback
  parent_cmd: cmd_3466
  task_type: exact
  title: "deploy zzzz qqqq"
  description: "zzzz qqqq"
  target_path: scripts/deploy_task.sh
EOF

    run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run related_lesson_ids
    [ "$status" -eq 0 ]
    [[ "$output" != *"L_TAG_ONLY_GENERIC"* ]]
    [[ "$output" == *"L_TARGET_FALLBACK"* ]]
}
