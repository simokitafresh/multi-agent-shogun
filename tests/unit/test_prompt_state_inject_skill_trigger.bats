#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$PROJECT_ROOT/scripts/hooks/prompt_state_inject.sh"
  TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/prompt_state_skill.XXXXXX")"
  export PROMPT_STATE_SKILLS_DIR="$TEST_TMPDIR/skills"
  export PROMPT_STATE_GROWTH_METRICS_FILE="$TEST_TMPDIR/growth.yaml"
  export PROMPT_STATE_LORD_CONVERSATION_FILE="$TEST_TMPDIR/lord_conversation.jsonl"
  mkdir -p "$PROMPT_STATE_SKILLS_DIR/cdp-browse"
  cat > "$PROMPT_STATE_SKILLS_DIR/cdp-browse/SKILL.md" <<'EOF'
---
name: cdp-browse
description: |
  Browser operation skill.
  TRIGGER: /cdp-browse、CDPで確認、ブラウザ確認
  DO NOT TRIGGER: DB確認（→/db-check）
---

# cdp-browse
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
