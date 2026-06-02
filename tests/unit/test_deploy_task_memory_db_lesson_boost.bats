#!/usr/bin/env bats
# test_deploy_task_memory_db_lesson_boost.bats — event_concepts経由の教訓boost

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "deploy_memory_db_lesson_boost"
    mkdir -p "$TEST_PROJECT/projects/infra" "$TEST_PROJECT/data"
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

create_memory_db_fixture() {
    python3 - "$TEST_PROJECT/data/multi_agent_shogun_memory.db" <<'PY'
import sqlite3
import sys

db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
conn.executescript("""
CREATE TABLE events (
    id TEXT PRIMARY KEY,
    ts TEXT,
    event_type TEXT,
    agent TEXT,
    target TEXT,
    direction TEXT,
    summary TEXT,
    detail TEXT,
    session_id TEXT,
    cmd_id TEXT,
    concepts TEXT,
    source_file TEXT,
    parent_event_id INTEGER,
    importance TEXT
);
CREATE TABLE event_concepts (
    event_id TEXT NOT NULL,
    concept_name TEXT NOT NULL,
    relevance_score REAL NOT NULL DEFAULT 1.0,
    PRIMARY KEY (event_id, concept_name)
);
CREATE INDEX idx_event_concepts_concept_name ON event_concepts(concept_name);
""")
conn.execute(
    "INSERT INTO events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    (
        "report:cmd_3119_fixture",
        "2026-06-02T13:00:00",
        "report",
        "hayate",
        "karo",
        "outbound",
        "lesson_candidate referenced L777",
        "event_concepts concept should boost L777 for deploy_task injection",
        "",
        "cmd_3119",
        '["memory_db_dynamic"]',
        "queue/reports/hayate_report_cmd_3119.yaml",
        None,
        "high",
    ),
)
conn.execute(
    "INSERT INTO event_concepts VALUES (?, ?, ?)",
    ("report:cmd_3119_fixture", "memory_db_dynamic", 1.0),
)
conn.commit()
conn.close()
PY
}

@test "cmd_3119 AC1: event_concepts一致イベント内lesson_idをboost候補として注入する" {
    create_memory_db_fixture
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L777
    title: unrelated title without task keywords
    summary: memory db selected this lesson from event concepts
    content: no deploy task keyword here
    tags: [process]
    helpful_count: 1
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  project: infra
  task_id: cmd_3119_ac1
  parent_cmd: cmd_3119
  task_type: exact
  title: "dynamic lesson boost"
  purpose: "memory_db_dynamic concept should find prior lesson IDs"
  target_path: scripts/deploy_task.sh
EOF

    MEMORY_DB_LESSON_BOOST=20 run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run related_lesson_ids
    [ "$status" -eq 0 ]
    [[ "$output" == *"L777"* ]]
}

@test "cmd_3119 AC2: static semantic boost and event_concepts boost are deduped by lesson id" {
    create_memory_db_fixture
    mkdir -p "$TEST_PROJECT/docs/semantic-index"
    cat > "$TEST_PROJECT/docs/semantic-index/index.md" <<'EOF'
## memory_db_dynamic — Memory DB Dynamic
| key | value |
| id | memory_db_dynamic |
| label | Memory DB Dynamic |
| aliases | memory_db_dynamic |
| related_lessons | L777 |
EOF
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L777
    title: unrelated title without task keywords
    summary: duplicate boosts must still produce one related_lessons item
    content: no deploy task keyword here
    tags: [process]
    helpful_count: 1
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  project: infra
  task_id: cmd_3119_ac2
  parent_cmd: cmd_3119
  task_type: exact
  title: "dynamic lesson boost"
  purpose: "memory_db_dynamic concept should find prior lesson IDs"
  target_path: scripts/deploy_task.sh
EOF

    MEMORY_DB_LESSON_BOOST=20 run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run related_lesson_ids
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c '^L777$')" -eq 1 ]
}

@test "cmd_3119 AC3: semantic-index aliasで見つけた概念IDからevent_concepts候補を発見する" {
    create_memory_db_fixture
    mkdir -p "$TEST_PROJECT/docs/semantic-index"
    cat > "$TEST_PROJECT/docs/semantic-index/index.md" <<'EOF'
## memory_db_dynamic — Memory DB Dynamic
| key | value |
| id | memory_db_dynamic |
| label | Memory DB Dynamic |
| aliases | 記憶DB |
| related_lessons | L999 |
EOF
    cat > "$TEST_PROJECT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L777
    title: unrelated dynamic lesson
    summary: event_concepts should select this lesson through concept seed
    content: no deploy task keyword here
    tags: [process]
    helpful_count: 1
  - id: L999
    title: static semantic placeholder
    summary: semantic index placeholder lesson
    content: no deploy task keyword here
    tags: [process]
    helpful_count: 1
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  project: infra
  task_id: cmd_3119_ac3_seed
  parent_cmd: cmd_3119
  task_type: exact
  title: "dynamic lesson boost"
  purpose: "記憶DBの概念から過去eventのlesson IDを発見する"
  target_path: scripts/deploy_task.sh
EOF

    MEMORY_DB_LESSON_BOOST=20 run deploy_task_lessons_only sasuke
    [ "$status" -eq 0 ]

    run related_lesson_ids
    [ "$status" -eq 0 ]
    [[ "$output" == *"L777"* ]]
}
