#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$PROJECT_ROOT/scripts/hooks/prompt_state_inject.sh"
  TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/prompt_state_skill.XXXXXX")"
  export PROMPT_STATE_SKILLS_DIR="$TEST_TMPDIR/skills"
  export PROMPT_STATE_GROWTH_METRICS_FILE="$TEST_TMPDIR/growth.yaml"
  export PROMPT_STATE_LORD_CONVERSATION_FILE="$TEST_TMPDIR/lord_conversation.jsonl"
  export PROMPT_STATE_PROJECTS_YAML="$TEST_TMPDIR/projects.yaml"
  unset PROMPT_STATE_CURRENT_PROJECT
  cat > "$PROMPT_STATE_PROJECTS_YAML" <<'EOF'
projects: []
current_project: dm-signal
EOF
  mkdir -p "$PROMPT_STATE_SKILLS_DIR/cdp-browse"
  cat > "$PROMPT_STATE_SKILLS_DIR/cdp-browse/SKILL.md" <<'EOF'
---
name: cdp-browse
description: |
  Browser operation skill.
  TRIGGER: /cdp-browse、CDPで確認、ブラウザ確認、本番画面をスクショ、rebalancer本番画面確認 project:rebalancer
  DO NOT TRIGGER: DB確認（→/db-check）
---

# cdp-browse
EOF
  mkdir -p "$PROMPT_STATE_SKILLS_DIR/db-check"
  cat > "$PROMPT_STATE_SKILLS_DIR/db-check/SKILL.md" <<'EOF'
---
name: db-check
description: |
  DM-Signal DB skill.
  TRIGGER: /db-check、DB確認 project:dm-signal、本番DB project:dm-signal
  DO NOT TRIGGER: DM-Signal以外の画面確認
allowed_projects: [dm-signal]
---

# db-check
EOF
  mkdir -p "$PROMPT_STATE_SKILLS_DIR/codd-fix"
  cat > "$PROMPT_STATE_SKILLS_DIR/codd-fix/SKILL.md" <<'EOF'
---
name: codd-fix
description: |
  CoDD fix PHENOMENON skill.
  TRIGGER: /codd-fix、codd fix、事象修正、現象修正、PHENOMENON修正
  DO NOT TRIGGER: 設計書の新規生成のみ
---

# codd-fix
EOF
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "shogun prompt matching skill trigger injects mandatory skill reminder" {
  export PROMPT_STATE_AGENT_ID="shogun"

  run bash "$HOOK" <<< '{"prompt":"CDP未使用のまま進めていないか確認して"}'

  [ "$status" -eq 0 ]
  [[ "$output" == *"SKILL TRIGGER HIT"* ]]
  [[ "$output" == *"/cdp-browse"* ]]
  [[ "$output" == *"作業開始前に該当SKILL.mdを読め"* ]]
}

@test "non-shogun prompt does not inject skill reminder" {
  export PROMPT_STATE_AGENT_ID="hayate"

  run bash "$HOOK" <<< '{"prompt":"CDP未使用のまま進めていないか確認して"}'

  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "project constrained skill triggers only for matching current_project" {
  export PROMPT_STATE_AGENT_ID="shogun"
  export PROMPT_STATE_CURRENT_PROJECT="dm-signal"

  run bash "$HOOK" <<< '{"prompt":"本番DBを確認して"}'

  [ "$status" -eq 0 ]
  [[ "$output" == *"/db-check"* ]]

  export PROMPT_STATE_CURRENT_PROJECT="rebalancer"
  run bash "$HOOK" <<< '{"prompt":"本番DBを確認して"}'

  [ "$status" -eq 0 ]
  [[ "$output" != *"/db-check"* ]]
}

@test "project annotated trigger routes screen check without DM-Signal DB false positive" {
  export PROMPT_STATE_AGENT_ID="shogun"
  export PROMPT_STATE_CURRENT_PROJECT="rebalancer"

  run bash "$HOOK" <<< '{"prompt":"rebalancer本番画面をスクショして"}'

  [ "$status" -eq 0 ]
  [[ "$output" == *"/cdp-browse"* ]]
  [[ "$output" != *"/db-check"* ]]
}

@test "codd fix phenomenon prompt injects codd-fix skill reminder" {
  export PROMPT_STATE_AGENT_ID="shogun"

  run bash "$HOOK" <<< '{"prompt":"codd fixで現象修正したい"}'

  [ "$status" -eq 0 ]
  [[ "$output" == *"SKILL TRIGGER HIT"* ]]
  [[ "$output" == *"/codd-fix"* ]]
}
