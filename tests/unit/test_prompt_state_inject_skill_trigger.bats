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

  run bash "$HOOK" <<< '{"prompt":"CDPで確認してDB確認"}'

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

@test "semantic_search skill recommendations respect SKILL role markers" {
  export PROMPT_STATE_AGENT_ID="hayate"
  export PROMPT_STATE_SEMANTIC_SEARCH_CMD="$TEST_TMPDIR/semantic_search_role_skills.sh"
  mkdir -p "$PROMPT_STATE_SKILLS_DIR/lesson-sort" "$PROMPT_STATE_SKILLS_DIR/report-write" "$PROMPT_STATE_SKILLS_DIR/general-skill"
  cat > "$PROMPT_STATE_SKILLS_DIR/lesson-sort/SKILL.md" <<'EOF'
---
name: lesson-sort
description: |
  【将軍専用】家老・忍者は使用禁止。
  TRIGGER: /lesson-sort、教訓ソート
---
EOF
  cat > "$PROMPT_STATE_SKILLS_DIR/report-write/SKILL.md" <<'EOF'
---
name: report-write
description: |
  【忍者専用】報告YAML作成を標準化する。
  TRIGGER: /report-write、報告作成
---
EOF
  cat > "$PROMPT_STATE_SKILLS_DIR/general-skill/SKILL.md" <<'EOF'
---
name: general-skill
description: |
  Markerless skill.
  TRIGGER: /general-skill、汎用確認
---
EOF
  cat > "$PROMPT_STATE_SEMANTIC_SEARCH_CMD" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
## role_filter_check — role filter
resources:
- skills: lesson-sort, report-write, general-skill
OUT
EOF
  chmod +x "$PROMPT_STATE_SEMANTIC_SEARCH_CMD"

  run bash "$HOOK" <<< '{"prompt":"報告作成と汎用確認"}'

  [ "$status" -eq 0 ]
  [[ "$output" == *"/report-write"* ]]
  [[ "$output" == *"/general-skill"* ]]
  [[ "$output" != *"/lesson-sort"* ]]

  export PROMPT_STATE_AGENT_ID="shogun"
  run bash "$HOOK" <<< '{"prompt":"教訓ソートと汎用確認"}'

  [ "$status" -eq 0 ]
  [[ "$output" == *"/lesson-sort"* ]]
  [[ "$output" == *"/general-skill"* ]]
  [[ "$output" != *"/report-write"* ]]
}

@test "semantic_search without skills rows emits no skill recommendation when no trigger matches" {
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
  [[ "$output" != *"SKILL RECOMMENDATION"* ]]
  [[ "$output" != *"/cdp-browse"* ]]
  [[ "$output" != *"/db-check"* ]]
}

@test "shogun semantic knowledge deduplicates discussion rows by timestamp and summary" {
  export PROMPT_STATE_AGENT_ID="shogun"
  export PROMPT_STATE_SEMANTIC_SEARCH_CMD="$TEST_TMPDIR/semantic_search_discussion_dupes.sh"
  cat > "$PROMPT_STATE_SEMANTIC_SEARCH_CMD" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
## growth_loop — 成長ループ
resources:
| discussion | `queue/lord_conversation.jsonl` 2026-05-27T11:08:00+09:00 [shogun宛て] 今クリアされても強くてニューゲームできるか |
## deepdive_principles — deepdive
resources:
| discussion | `queue/lord_conversation.jsonl` 2026-05-27T11:08:00+09:00 [shogun宛て] 今クリアされても強くてニューゲームできるか |
| discussion | `queue/lord_conversation.jsonl` 2026-05-27T11:09:00+09:00 [shogun宛て] 別の発言 |
OUT
EOF
  chmod +x "$PROMPT_STATE_SEMANTIC_SEARCH_CMD"

  run bash "$HOOK" <<< '{"prompt":"ニューゲーム確認"}'

  [ "$status" -eq 0 ]
  run python3 - "$output" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
ctx = payload["hookSpecificOutput"]["additionalContext"]
assert ctx.count("今クリアされても強くてニューゲームできるか") == 1, ctx
assert ctx.count("| discussion |") == 2, ctx
PY
  [ "$status" -eq 0 ]
}

@test "shogun prompt injects brainwash 8-pattern binary check reminder (cmd_3251 AC3-A)" {
  export PROMPT_STATE_AGENT_ID="shogun"

  run bash "$HOOK" <<< '{"prompt":"次の作業を開始する"}'

  [ "$status" -eq 0 ]
  [[ "$output" == *"brainwash_binary_check"* ]]
  [[ "$output" == *"#1 早期終了"* ]]
  [[ "$output" == *"#2 検証スキップ"* ]]
  [[ "$output" == *"#3 他者依存"* ]]
  [[ "$output" == *"#4 緩い設計"* ]]
  [[ "$output" == *"#5 先送り"* ]]
  [[ "$output" == *"#6 出力=仕事"* ]]
  [[ "$output" == *"#7 簡潔本能"* ]]
  [[ "$output" == *"#8 完了急ぎ"* ]]
}

@test "non-shogun prompt does not inject brainwash reminder (cmd_3251 AC3-A)" {
  export PROMPT_STATE_AGENT_ID="hayate"

  run bash "$HOOK" <<< '{"prompt":"次の作業を開始する"}'

  [ "$status" -eq 0 ]
  [[ "$output" != *"brainwash_binary_check"* ]]
}

@test "same prompt reuses skill recommendation cache without rerunning semantic_search" {
  export PROMPT_STATE_AGENT_ID="hayate_cache_test"
  export PROMPT_STATE_SEMANTIC_SEARCH_CMD="$TEST_TMPDIR/semantic_search_counting.sh"
  mkdir -p "$PROMPT_STATE_SKILLS_DIR/report-write"
  cat > "$PROMPT_STATE_SKILLS_DIR/report-write/SKILL.md" <<'EOF'
---
name: report-write
description: |
  【忍者専用】報告YAML作成を標準化する。
  TRIGGER: /report-write、報告YAML作成、報告記入
---
EOF
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

  run bash "$HOOK" <<< '{"prompt":"報告YAML作成"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"/report-write"* ]]

  run bash "$HOOK" <<< '{"prompt":"報告YAML作成"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"/report-write"* ]]
  # One call is for semantic_search-derived skill recommendation and one is
  # for the normal semantic knowledge layer. The second prompt reuses caches.
  [ "$(wc -l < "$SEMANTIC_CALL_LOG" | tr -d ' ')" -eq 2 ]
  run python3 - "$PROMPT_STATE_SKILL_RECOMMEND_LOG_FILE" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as fh:
    data = yaml.safe_load(fh)
entries = data["recommendations"]
assert len(entries) == 1, entries
PY
  [ "$status" -eq 0 ]
}
