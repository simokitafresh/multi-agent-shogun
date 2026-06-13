#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  PROMPT_HOOK="$PROJECT_ROOT/scripts/hooks/prompt_state_inject.sh"
  POST_HOOK="$PROJECT_ROOT/.claude/hooks/post-shogun-inbox-check.sh"
  TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/prompt_state_recovery.XXXXXX")"
  export PROMPT_STATE_RECOVERY_MARKER="$TEST_TMPDIR/recovery_marker"
  export PROMPT_STATE_GROWTH_METRICS_FILE="$TEST_TMPDIR/growth.yaml"
  export PROMPT_STATE_LORD_CONVERSATION_FILE="$TEST_TMPDIR/lord_conversation.jsonl"
  export PROMPT_STATE_PROJECTS_YAML="$TEST_TMPDIR/projects.yaml"
  export PROMPT_STATE_SEMANTIC_SEARCH_CMD="$TEST_TMPDIR/no_semantic_search.sh"
  export PROMPT_STATE_SKILLS_DIR="$TEST_TMPDIR/skills"
  export PROMPT_STATE_SKILL_RECOMMEND_LOG_FILE="$TEST_TMPDIR/skill_recommend_log.yaml"
  export PROMPT_STATE_LORD_RULING_CACHE_PATH="$TEST_TMPDIR/no_lord_cache.db"
  export PROMPT_STATE_MEMORY_DB_PATH="$TEST_TMPDIR/no_memory.db"
  export PROMPT_STATE_AGENT_ID="shogun"
  export SHOGUN_ROOT="$PROJECT_ROOT"
  export SHOGUN_RECOVERY_MARKER="$PROMPT_STATE_RECOVERY_MARKER"
  export SHOGUN_INBOX_PATH="$TEST_TMPDIR/shogun_inbox.yaml"
  export SHOGUN_LORD_CONV_PATH="$TEST_TMPDIR/lord_conversation.jsonl"
  export TMUX_PANE="%recovery_test_$$"
  cat > "$PROMPT_STATE_PROJECTS_YAML" <<'EOF'
projects: []
current_project: infra
EOF
  cat > "$SHOGUN_INBOX_PATH" <<'EOF'
messages: []
EOF
  : > "$SHOGUN_LORD_CONV_PATH"
  mkdir -p "$PROMPT_STATE_SKILLS_DIR"
  rm -f "/tmp/shogun_aid_${TMUX_PANE}" "/tmp/shogun_not_shogun_${TMUX_PANE}"
  printf 'shogun\n' > "/tmp/shogun_aid_${TMUX_PANE}"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
  rm -f "/tmp/shogun_aid_${TMUX_PANE}" "/tmp/shogun_not_shogun_${TMUX_PANE}" \
        "/tmp/shogun_unread_${TMUX_PANE}" "/tmp/shogun_unread_${TMUX_PANE}.meta" \
        "/tmp/shogun_lord_last_${TMUX_PANE}" "/tmp/shogun_lord_last_${TMUX_PANE}.meta" \
        "/tmp/shogun_effect_remind_${TMUX_PANE}" "/tmp/shogun_effect_remind_${TMUX_PANE}.meta"
}

@test "shogun prompt refreshes an existing recovery marker" {
  touch -d '9 hours ago' "$PROMPT_STATE_RECOVERY_MARKER"
  before="$(stat -c %Y "$PROMPT_STATE_RECOVERY_MARKER")"

  run bash "$PROMPT_HOOK" <<< '{"prompt":"通常の作業を続ける"}'

  [ "$status" -eq 0 ]
  after="$(stat -c %Y "$PROMPT_STATE_RECOVERY_MARKER")"
  [ "$after" -gt "$before" ]
}

@test "shogun prompt does not create a missing recovery marker" {
  rm -f "$PROMPT_STATE_RECOVERY_MARKER"

  run bash "$PROMPT_HOOK" <<< '{"prompt":"通常の作業を続ける"}'

  [ "$status" -eq 0 ]
  [ ! -e "$PROMPT_STATE_RECOVERY_MARKER" ]
}

@test "non-shogun prompt does not refresh recovery marker" {
  export PROMPT_STATE_AGENT_ID="hayate"
  touch -d '9 hours ago' "$PROMPT_STATE_RECOVERY_MARKER"
  before="$(stat -c %Y "$PROMPT_STATE_RECOVERY_MARKER")"

  run bash "$PROMPT_HOOK" <<< '{"prompt":"通常の作業を続ける"}'

  [ "$status" -eq 0 ]
  after="$(stat -c %Y "$PROMPT_STATE_RECOVERY_MARKER")"
  [ "$after" -eq "$before" ]
}

@test "refreshed marker prevents RECOVERY INCOMPLETE after 480 minutes" {
  touch -d '9 hours ago' "$PROMPT_STATE_RECOVERY_MARKER"

  run bash "$PROMPT_HOOK" <<< '{"prompt":"活動継続"}'
  [ "$status" -eq 0 ]

  run dash "$POST_HOOK"
  [ "$status" -le 1 ]
  [[ "$output" != *"RECOVERY INCOMPLETE"* ]]
}

@test "missing marker still emits RECOVERY INCOMPLETE warning" {
  rm -f "$PROMPT_STATE_RECOVERY_MARKER"

  run dash "$POST_HOOK"

  [ "$status" -eq 0 ]
  [[ "$output" == *"RECOVERY INCOMPLETE"* ]]
}
