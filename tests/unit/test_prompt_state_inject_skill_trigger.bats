#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$PROJECT_ROOT/scripts/hooks/prompt_state_inject.sh"
  TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/prompt_state_skill.XXXXXX")"
  export PROMPT_STATE_SKILLS_DIR="$TEST_TMPDIR/skills"
  export PROMPT_STATE_GROWTH_METRICS_FILE="$TEST_TMPDIR/growth.yaml"
  export PROMPT_STATE_LORD_CONVERSATION_FILE="$TEST_TMPDIR/lord_conversation.jsonl"
  export PROMPT_STATE_PROJECTS_YAML="$TEST_TMPDIR/projects.yaml"
  export PROMPT_STATE_SEMANTIC_SEARCH_CMD="$TEST_TMPDIR/no_semantic_search.sh"
  export PROMPT_STATE_SKILL_RECOMMEND_LOG_FILE="$TEST_TMPDIR/skill_recommend_log.yaml"
  export PROMPT_STATE_SKILL_TRIGGER_TIMEOUT=1
  export PROMPT_STATE_SKILL_SEMANTIC_TIMEOUT=1
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

@test "non-shogun prompt matching skill trigger injects skill reminder" {
  export PROMPT_STATE_AGENT_ID="hayate"

  run bash "$HOOK" <<< '{"prompt":"CDP未使用のまま進めていないか確認して"}'

  [ "$status" -eq 0 ]
  [[ "$output" == *"SKILL TRIGGER HIT"* ]]
  [[ "$output" == *"/cdp-browse"* ]]
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

@test "codd-fix skill documents phenomenon fix and dag verify chain" {
  skill_file="$PROJECT_ROOT/skills/codd-fix/SKILL.md"

  run rg -n 'codd fix "\$PHENOMENON" --path \. --non-interactive --on-ambiguity abort --no-push' "$skill_file"
  [ "$status" -eq 0 ]

  run rg -n 'codd dag build --path \.' "$skill_file"
  [ "$status" -eq 0 ]

  run rg -n 'codd dag verify --all --path \.' "$skill_file"
  [ "$status" -eq 0 ]

  run rg -n 'codd dag verify --path \.' "$skill_file"
  [ "$status" -eq 0 ]
}

@test "semantic_search skills rows recommend skills for any role" {
  export PROMPT_STATE_AGENT_ID="hayate"
  export PROMPT_STATE_SEMANTIC_SEARCH_CMD="$TEST_TMPDIR/semantic_search_mock.sh"
  cat > "$PROMPT_STATE_SEMANTIC_SEARCH_CMD" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
## cdp_browser_capability — CDP(ブラウザ操作能力)
resources:
- skills: cdp-browse, db-check
OUT
EOF
  chmod +x "$PROMPT_STATE_SEMANTIC_SEARCH_CMD"

  run bash "$HOOK" <<< '{"prompt":"推薦なし入力"}'

  [ "$status" -eq 0 ]
  [[ "$output" == *"SKILL RECOMMENDATION"* ]]
  [[ "$output" == *"/cdp-browse"* ]]
  [[ "$output" == *"/db-check"* ]]
  run python3 - "$PROMPT_STATE_SKILL_RECOMMEND_LOG_FILE" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as fh:
    data = yaml.safe_load(fh)
skills = data["recommendations"][-1]["recommended_skills"]
assert skills == ["cdp-browse", "db-check"], skills
PY
  [ "$status" -eq 0 ]
}

@test "semantic_search without skills rows stays silent when no trigger matches" {
  export PROMPT_STATE_AGENT_ID="hayate"
  export PROMPT_STATE_SEMANTIC_SEARCH_CMD="$TEST_TMPDIR/semantic_search_no_skills.sh"
  cat > "$PROMPT_STATE_SEMANTIC_SEARCH_CMD" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
## semantic_dictionary_design — セマンティック辞書構想
resources:
- file: `docs/research/semantic_index_design.md`
OUT
EOF
  chmod +x "$PROMPT_STATE_SEMANTIC_SEARCH_CMD"

  run bash "$HOOK" <<< '{"prompt":"セマンティック推薦して"}'

  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "same prompt reuses skill recommendation cache without rerunning semantic_search" {
  export PROMPT_STATE_AGENT_ID="hayate_cache_test"
  export PROMPT_STATE_SEMANTIC_SEARCH_CMD="$TEST_TMPDIR/semantic_search_counting.sh"
  rm -f /tmp/skill_recommend_cache_hayate_cache_test
  cat > "$PROMPT_STATE_SEMANTIC_SEARCH_CMD" <<'EOF'
#!/usr/bin/env bash
printf 'call\n' >> "$SEMANTIC_CALL_LOG"
cat <<'OUT'
## report_flow — 報告経路
resources:
- skills: report-write
OUT
EOF
  chmod +x "$PROMPT_STATE_SEMANTIC_SEARCH_CMD"
  export SEMANTIC_CALL_LOG="$TEST_TMPDIR/semantic_calls.log"

  run bash "$HOOK" <<< '{"prompt":"同一プロンプト推薦"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"/report-write"* ]]

  run bash "$HOOK" <<< '{"prompt":"同一プロンプト推薦"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"/report-write"* ]]
  [ "$(wc -l < "$SEMANTIC_CALL_LOG" | tr -d ' ')" -eq 1 ]
}
