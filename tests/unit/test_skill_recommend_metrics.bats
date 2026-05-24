#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/skill_recommend_metrics.XXXXXX")"
  export SKILL_RECOMMEND_LOG_FILE="$TEST_TMPDIR/skill_recommend_log.yaml"
  export SKILL_EXECUTION_LOG_FILE="$TEST_TMPDIR/skill_execution_log.yaml"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "recall miss is suppressed until recommendation log has enough data" {
  cat > "$SKILL_RECOMMEND_LOG_FILE" <<'EOF'
recommendations:
- ts: "2026-05-24T15:10:27+09:00"
  agent_id: "hayate"
  prompt_hash: "abc"
  recommended_skills:
  - "report-write"
EOF
  cat > "$SKILL_EXECUTION_LOG_FILE" <<'EOF'
executions:
- ts: "2026-05-24T18:00:00+0900"
  skill: "verdict-check"
  used: "true"
- ts: "2026-05-24T18:01:00+0900"
  skill: "cmd-complete"
  used: "true"
EOF

  run bash "$PROJECT_ROOT/scripts/skill_recommend_metrics.sh" 30

  [ "$status" -eq 0 ]
  [[ "$output" == *"recall miss件数: N/A"* ]]
  [[ "$output" == *"計測不足: 推薦ログ1件 < 10件。ALERT抑制"* ]]
  [[ "$output" != *"ALERT: Phase 3"* ]]
}

@test "recall miss is calculated after recommendation log reaches threshold" {
  {
    printf 'recommendations:\n'
    for i in $(seq 1 10); do
      printf -- '- ts: "2026-05-24T15:%02d:00+09:00"\n' "$i"
      printf '  agent_id: "hayate"\n'
      printf '  prompt_hash: "hash_%02d"\n' "$i"
      printf '  recommended_skills:\n'
      printf '  - "report-write"\n'
    done
  } > "$SKILL_RECOMMEND_LOG_FILE"
  cat > "$SKILL_EXECUTION_LOG_FILE" <<'EOF'
executions:
- ts: "2026-05-24T18:00:00+0900"
  skill: "verdict-check"
  used: "true"
EOF

  run bash "$PROJECT_ROOT/scripts/skill_recommend_metrics.sh" 30

  [ "$status" -eq 2 ]
  [[ "$output" == *"recall miss件数: 1"* ]]
  [[ "$output" == *"recall miss top: verdict-check:1"* ]]
  [[ "$output" == *"ALERT: Phase 3"* ]]
}
