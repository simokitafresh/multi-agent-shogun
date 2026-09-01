#!/usr/bin/env bats
# test_necessity: log_terminal_input.sh must record a prompt as a lord inbound
# only when the invoking process has its own TMUX_PANE. With TMUX_PANE empty
# or unset, `tmux display-message -t ""` resolves the active pane (the pane the
# lord is looking at), so a foreign process's prompt would be recorded as the
# lord speaking to that agent. Invariant guards 2026-09-01 15:19:06
# (CoDD "You are UPDATING an existing design document" logged as lord→shogun).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  T="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$T/scripts" "$T/lib" "$T/queue" "$T/logs"
  cp "$ROOT/scripts/log_terminal_input.sh" "$T/scripts/"
  # the script sources "$SCRIPT_DIR/lib/lord_conversation.sh" (repo-root lib/)
  cp -r "$ROOT/lib/." "$T/lib/"
  : > "$T/queue/lord_conversation.jsonl"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/tmux" <<'SH'
#!/usr/bin/env bash
# `-t ""` (empty target) behaves like the real tmux: falls back to the active pane = shogun
args=("$@"); target=""
for ((i=0;i<${#args[@]};i++)); do [[ "${args[$i]}" == -t ]] && target="${args[$((i+1))]}"; done
if [[ -n "$target" ]]; then echo "gunshi"; else echo "shogun"; fi
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
  PAYLOAD='{"prompt":"You are UPDATING an existing design document to reflect source code changes."}'
}

@test "empty TMUX_PANE: nothing is recorded (active pane must not be borrowed)" {
  run env TMUX_PANE= TMUX=/tmp/tmux-1000/default,1,0 PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
      bash -c 'printf "%s" "$2" | bash "$1/scripts/log_terminal_input.sh"; echo rc=$?' _ "$T" "$PAYLOAD"
  [[ "$output" == *"rc=0"* ]]
  [ ! -s "$T/queue/lord_conversation.jsonl" ]
}

@test "unset TMUX_PANE: nothing is recorded" {
  run env -u TMUX_PANE TMUX=/tmp/tmux-1000/default,1,0 PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
      bash -c 'printf "%s" "$2" | bash "$1/scripts/log_terminal_input.sh"; echo rc=$?' _ "$T" "$PAYLOAD"
  [[ "$output" == *"rc=0"* ]]
  [ ! -s "$T/queue/lord_conversation.jsonl" ]
}

@test "own TMUX_PANE: the prompt is recorded as lord inbound targeting the pane's own agent" {
  run env TMUX_PANE=%9 TMUX=/tmp/tmux-1000/default,1,0 PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
      bash -c 'printf "%s" "$2" | bash "$1/scripts/log_terminal_input.sh"; echo rc=$?' _ "$T" "$PAYLOAD"
  [[ "$output" == *"rc=0"* ]]
  [ -s "$T/queue/lord_conversation.jsonl" ]
  grep -q '"direction": *"inbound"' "$T/queue/lord_conversation.jsonl"
  grep -q '"target": *"gunshi"' "$T/queue/lord_conversation.jsonl"
  ! grep -q '"target": *"shogun"' "$T/queue/lord_conversation.jsonl"
}
