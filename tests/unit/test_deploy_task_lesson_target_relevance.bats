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
