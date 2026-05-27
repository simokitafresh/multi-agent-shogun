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
  executor: "hayate"
  skill: "verdict-check"
  used: "true"
- ts: "2026-05-24T18:01:00+0900"
  executor: "hayate"
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
  executor: "hayate"
  skill: "gate-sync"
  used: "true"
EOF

  run bash "$PROJECT_ROOT/scripts/skill_recommend_metrics.sh" 30

  [ "$status" -eq 2 ]
  [[ "$output" == *"recall miss件数: 1"* ]]
  [[ "$output" == *"recall miss top: hayate/gate-sync:1"* ]]
  [[ "$output" == *"ALERT: Phase 3"* ]]
}

@test "unobserved recommended skills remain in precision denominator" {
  cat > "$SKILL_RECOMMEND_LOG_FILE" <<'EOF'
recommendations:
EOF
  for i in $(seq 1 10); do
    cat >> "$SKILL_RECOMMEND_LOG_FILE" <<EOF
- ts: "2026-05-24T15:${i}:00+09:00"
  agent_id: "karo"
  prompt_hash: "hash_${i}"
  recommended_skills:
  - "report-write"
  - "hensei"
EOF
  done
  cat > "$SKILL_EXECUTION_LOG_FILE" <<'EOF'
executions:
- ts: "2026-05-24T18:00:00+0900"
  executor: "karo"
  skill: "report-write"
  used: "true"
EOF

  run bash "$PROJECT_ROOT/scripts/skill_recommend_metrics.sh" 30

  [ "$status" -eq 2 ]
  [[ "$output" == *"precision率: 5% (1/20)"* ]]
  [[ "$output" == *"偽陽性率: 95% (19/20)"* ]]
  [[ "$output" != *"precision評価対象外"* ]]
  [[ "$output" == *"ALERT: Phase 3"* ]]
}

@test "precision matches recommendations and executions by agent_id" {
  cat > "$SKILL_RECOMMEND_LOG_FILE" <<'EOF'
recommendations:
EOF
  for i in $(seq 1 10); do
    cat >> "$SKILL_RECOMMEND_LOG_FILE" <<EOF
- ts: "2026-05-24T15:${i}:00+09:00"
  agent_id: "karo"
  prompt_hash: "hash_${i}"
  recommended_skills:
  - "report-write"
EOF
  done
  cat > "$SKILL_EXECUTION_LOG_FILE" <<'EOF'
executions:
- ts: "2026-05-24T17:50:00+0900"
  executor: "karo"
  skill: "dashboard-update"
  used: "true"
- ts: "2026-05-24T18:00:00+0900"
  executor: "saizo"
  skill: "report-write"
  used: "true"
EOF

  run bash "$PROJECT_ROOT/scripts/skill_recommend_metrics.sh" 30

  [ "$status" -eq 2 ]
  [[ "$output" == *"precision率: 0% (0/10)"* ]]
  [[ "$output" == *"偽陽性率: 100% (10/10)"* ]]
  [[ "$output" == *"recall miss件数: 0"* ]]
  [[ "$output" == *"ALERT: Phase 3"* ]]
}

@test "post-completion automatic skills are not counted as recall miss" {
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
  {
    printf 'executions:\n'
    for i in $(seq 1 10); do
      printf -- '- ts: "2026-05-24T18:%02d:00+0900"\n' "$i"
      printf '  executor: "hayate"\n'
      printf '  skill: "report-write"\n'
      printf '  used: "true"\n'
    done
    cat <<'EOF'
- ts: "2026-05-24T18:20:00+0900"
  skill: "cmd-complete"
  gate: "cmd_complete_gate"
  used: "true"
- ts: "2026-05-24T18:21:00+0900"
  skill: "dashboard-update"
  gate: "dashboard_update"
  used: "true"
EOF
  } > "$SKILL_EXECUTION_LOG_FILE"

  run bash "$PROJECT_ROOT/scripts/skill_recommend_metrics.sh" 30

  [ "$status" -eq 0 ]
  [[ "$output" == *"recall miss件数: 0"* ]]
  [[ "$output" != *"ALERT: Phase 3"* ]]
}
