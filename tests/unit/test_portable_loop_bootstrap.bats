#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TEST_TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "portable loop bootstrap installs core and runs smoke path" {
  run bash "$REPO_ROOT/scripts/portable_loop_bootstrap.sh" "$TEST_TMP/project"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: installed portable learning-loop core"* ]]

  cd "$TEST_TMP/project"
  [ -x scripts/learning-loop/lesson_write.sh ]
  [ -x scripts/learning-loop/insight_write.sh ]
  [ -x scripts/learning-loop/memory_write.sh ]
  [ -x scripts/learning-loop/inbox_write.sh ]
  [ -x scripts/learning-loop/semantic_search.sh ]
  [ -x scripts/learning-loop/recall_inject.sh ]
  [ -x scripts/learning-loop/report_gate.py ]

  run bash scripts/learning-loop/lesson_write.sh "Portable lesson" "Reusable rule" "test" "bats"
  [ "$status" -eq 0 ]
  [[ "$output" == OK:* ]]
  grep -q "Portable lesson" .learning-loop/lessons.yaml

  run bash scripts/learning-loop/insight_write.sh "Portable insight" medium test
  [ "$status" -eq 0 ]
  [[ "$output" == OK:* ]]
  grep -q "Portable insight" .learning-loop/insights.yaml

  run bash scripts/learning-loop/memory_write.sh "portable memory" test
  [ "$status" -eq 0 ]
  [[ "$output" == OK:* ]]
  grep -q "portable memory" .learning-loop/memory/events.jsonl

  cat > report.yaml <<'EOF'
worker_id: local
parent_cmd: smoke
status: completed
result:
  summary: "smoke passed"
purpose_validation:
  fit: true
files_modified:
- path: scripts/learning-loop/report_gate.py
lesson_candidate:
  found: false
  no_lesson_reason: "smoke"
lessons_useful:
- id: L1
  useful: true
  reason: "smoke"
binary_checks:
  AC1:
  - check: "smoke"
    result: "yes"
EOF
  run python3 scripts/learning-loop/report_gate.py report.yaml
  [ "$status" -eq 0 ]
  [ "$output" = "PASS" ]
}

@test "portable loop recall injection emits semantic and memory matches" {
  run bash "$REPO_ROOT/scripts/portable_loop_bootstrap.sh" "$TEST_TMP/project"
  [ "$status" -eq 0 ]

  cd "$TEST_TMP/project"
  cat >> .learning-loop/semantic-map.md <<'EOF'
| portable recall | recall, portable recall, learning-loop | docs/learning-loop-portable-core.md |
EOF
  run bash scripts/learning-loop/memory_write.sh "portable recall keeps event context available" test
  [ "$status" -eq 0 ]

  run bash scripts/learning-loop/recall_inject.sh "Please use portable recall during report writing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"learning_loop_recall:"* ]]
  [[ "$output" == *"[semantic] query=portable recall"* ]]
  [[ "$output" == *"[memory] query=portable recall"* ]]
}

@test "portable loop recall injection returns empty success for no match" {
  run bash "$REPO_ROOT/scripts/portable_loop_bootstrap.sh" "$TEST_TMP/project"
  [ "$status" -eq 0 ]

  cd "$TEST_TMP/project"
  run bash scripts/learning-loop/recall_inject.sh "zzznomatchtoken"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "portable loop installed files do not contain project-specific dependencies" {
  run bash "$REPO_ROOT/scripts/portable_loop_bootstrap.sh" "$TEST_TMP/project"
  [ "$status" -eq 0 ]

  cd "$TEST_TMP/project"
  run grep -RInE 'tmux|/mnt/c|multi-agent-shogun|queue/tasks|queue/reports|shogun_to_karo' \
    scripts/learning-loop .learning-loop docs/learning-loop-portable-core.md
  [ "$status" -eq 1 ]
}
