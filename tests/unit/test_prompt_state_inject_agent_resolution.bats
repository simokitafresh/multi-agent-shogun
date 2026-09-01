#!/usr/bin/env bats
# test_necessity: prompt_state_inject must resolve the agent only from
# TMUX_PANE. Without TMUX_PANE (child `claude -p`, daemon-spawned CLI) it must
# report agent=unknown and must not write shogun-specific state (growth metrics
# / lord-conversation identity) even when the tmux active pane is shogun.
# Invariant guards 2026-09-01 15:19 (foreign process resolved as shogun via the
# active pane and its CoDD prompt was treated as a lord inbound).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  T="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$T/scripts/hooks" "$T/scripts/lib" "$T/logs" "$T/queue/inbox" "$T/config"
  cp "$ROOT/scripts/hooks/prompt_state_inject.sh" "$T/scripts/hooks/"
  cp -r "$ROOT/scripts/lib/." "$T/scripts/lib/" 2>/dev/null || true
  : > "$T/queue/lord_conversation.jsonl"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/tmux" <<'SH'
#!/usr/bin/env bash
# active pane (no -t) is shogun; the caller's own pane (-t) is gunshi
if [[ " $* " == *" -t "* ]]; then echo "gunshi"; else echo "shogun"; fi
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
  PAYLOAD='{"prompt":"You are UPDATING an existing design document to reflect source code changes."}'
}

run_hook() {
  # $1 = "nopane" | "pane"
  if [ "$1" = nopane ]; then
    env -u TMUX_PANE -u AGENT_ID -u PROMPT_STATE_AGENT_ID TMUX=/tmp/tmux-1000/default,1,0 \
        PROMPT_STATE_LORD_CONVERSATION_FILE="$T/queue/lord_conversation.jsonl" \
        PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
        bash -c 'printf "%s" "$2" | timeout 60 bash "$1/scripts/hooks/prompt_state_inject.sh" 2>/dev/null; true' _ "$T" "$PAYLOAD"
  else
    env -u AGENT_ID -u PROMPT_STATE_AGENT_ID TMUX=/tmp/tmux-1000/default,1,0 TMUX_PANE=%9 \
        PROMPT_STATE_LORD_CONVERSATION_FILE="$T/queue/lord_conversation.jsonl" \
        PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
        bash -c 'printf "%s" "$2" | timeout 60 bash "$1/scripts/hooks/prompt_state_inject.sh" 2>/dev/null; true' _ "$T" "$PAYLOAD"
  fi
}

@test "no TMUX_PANE: agent resolves to unknown even though the active pane is shogun; no shogun state written" {
  run run_hook nopane
  [[ "$output" != *"agent: shogun"* ]]
  [[ "$output" == *"agent: unknown"* ]] || [[ -z "$output" ]]
  # no shogun-specific growth/identity artefacts in the isolated tree
  [ -z "$(find "$T/logs" -type f -name '*shogun*' 2>/dev/null)" ]
  [ ! -s "$T/queue/lord_conversation.jsonl" ]
}

@test "TMUX_PANE set: agent resolves to the pane's own id (gunshi), never the active pane (shogun)" {
  run run_hook pane
  [[ "$output" == *"agent: gunshi"* ]]
  [[ "$output" != *"agent: shogun"* ]]
  [ -z "$(find "$T/logs" -type f -name '*shogun*' 2>/dev/null)" ]
}
