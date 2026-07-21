#!/usr/bin/env bats
# test_necessity: 三層記憶のMEM引用scaffoldとQ6検出が将軍以外の全ロールでも発火し、証拠なしでは非発火となる不変量を守る。

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$ROOT/scripts/hooks/prompt_state_inject.sh"
}

load_role_functions() {
  eval "$(sed -n '/^_prompt_state_memory_citation_scaffold()/,/^}/p; /^prompt_state_brainwash_flag_file()/,/^}/p; /^prompt_state_q6_brainwash_detected()/,/^}/p' "$SCRIPT")"
}

@test "gunshi receives MEM citation scaffold from its own evidence" {
  load_role_functions
  export agent_id=gunshi prompt_is_inbox_nudge=0 TMUX_PANE='%2'
  export THREE_LAYER_PREACTION_EVIDENCE_DIR="$BATS_TEST_TMPDIR/evidence"
  mkdir -p "$THREE_LAYER_PREACTION_EVIDENCE_DIR"
  local evidence="$THREE_LAYER_PREACTION_EVIDENCE_DIR/evidence_gunshi__2.json"
  printf '%s\n' '{"nonce":"n1","status":"success","memory_db":"0","semantic":"0","obsidian":"0","memory_count":1,"memory_source":"db","memory_query":"q","memory_timestamp":"t","semantic_count":1,"semantic_source":"index","semantic_query":"q","semantic_timestamp":"t","obsidian_count":1,"obsidian_source":"graph","obsidian_query":"q","obsidian_timestamp":"t"}' > "$evidence"
  printf 'n1\n' > "$evidence.current"

  run _prompt_state_memory_citation_scaffold
  [ "$status" -eq 0 ]
  [[ "$output" == *'[MEM: memory_db source="db" query="q" ts="t"]'* ]]
}

@test "karo Q6 detector fires with flag and does not fire without flag" {
  load_role_functions
  export agent_id=karo SCRIPT_DIR="$BATS_TEST_TMPDIR/root"
  export PROMPT_STATE_Q6_BRAINWASH_FLAG_FILE="$BATS_TEST_TMPDIR/karo-q6.flag"

  run prompt_state_q6_brainwash_detected
  [ "$status" -eq 1 ]

  printf '2026-07-21T00:00:00+09:00\t洗脳#5\n' > "$PROMPT_STATE_Q6_BRAINWASH_FLAG_FILE"
  run prompt_state_q6_brainwash_detected
  [ "$status" -eq 0 ]
}
