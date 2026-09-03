#!/usr/bin/env bats
# test_necessity: the confirmation-prompt guard must fire only on a real dialog
# structure (question line and/or consecutive numbered choices at line start, on
# the visible screen) and never on prose that merely quotes "❯ 1. Yes".
# regression_justification: 2026-09-01 13:11-13:14 the guard matched a quoted
# "❯ 1. Yes" inside Shogun's own reply (scrollback -S -30, loose regex) and
# suppressed 4 consecutive nudges — lord: "将軍が起きない。デーモン問題では".

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$ROOT/scripts/lib/pane_confirmation_guard.sh"
}

@test "real claude confirmation dialog (question + cursor choices) is a prompt" {
  run _pane_confirmation_screen_has_prompt $'Do you want to proceed?\n ❯ 1. Yes\n   2. No'
  [ "$status" -eq 0 ]
}

@test "codex update dialog (numbered choices at line start, no question) is a prompt" {
  run _pane_confirmation_screen_has_prompt $'Update available! 0.151.0 -> 0.152.0\n› 1. Update now\n  2. Skip until next version\n  3. Never'
  [ "$status" -eq 0 ]
}

@test "prose quoting the choice text inside a sentence is not a prompt" {
  run _pane_confirmation_screen_has_prompt $'   - 確認/更新/上限ダイアログの選択肢行(`❯ 1. Yes`/`› 1. Update now`)を陰性 fixture\n   - crash 後のシェル\n❯ '
  [ "$status" -ne 0 ]
}

@test "prose quoting Do you want to proceed? mid-sentence without choices is not a prompt" {
  run _pane_confirmation_screen_has_prompt $'watcher は "Do you want to proceed?" を検知して nudge を止める。\n❯ '
  [ "$status" -ne 0 ]
}

@test "idle codex prompt is not a confirmation prompt" {
  run _pane_confirmation_screen_has_prompt $'› Ask Codex to do anything\n  gpt-5.6-luna high · Context 0% used'
  [ "$status" -ne 0 ]
}

@test "single numbered list item without a second choice is not a prompt" {
  run _pane_confirmation_screen_has_prompt $'次の手順:\n  1. push する\n  その後に GATE\n❯ '
  [ "$status" -ne 0 ]
}

@test "claude session quality survey is a confirmation prompt" {
  run _pane_confirmation_screen_has_prompt $'How is Claude doing this session? (optional)\n  1 Bad\n  2 Fine\n  3 Good\n  0 Dismiss'
  [ "$status" -eq 0 ]
}

@test "survey prose without the visible choice structure is not a prompt" {
  run _pane_confirmation_screen_has_prompt $'The docs mention "How is Claude doing this session?" and choices 1 Bad, 2 Fine, 3 Good, 0 Dismiss.\n❯ '
  [ "$status" -ne 0 ]
}

@test "claude launch command carries the documented survey opt-out" {
  fixture="$BATS_TEST_TMPDIR/cli-lookup"
  mkdir -p "$fixture/config"
  cat > "$fixture/settings.yaml" <<'YAML'
cli:
  default: claude
  agents:
    dummyclaude:
      type: claude
      model_name: claude-opus-4-6
YAML
  cat > "$fixture/profiles.yaml" <<'YAML'
profiles:
  claude:
    launch_cmd: /bin/true
YAML
  run env CLI_LOOKUP_SETTINGS="$fixture/settings.yaml" CLI_LOOKUP_PROFILES="$fixture/profiles.yaml" \
    bash -c 'source "$1/scripts/lib/cli_lookup.sh"; cli_launch_cmd dummyclaude' _ "$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "env CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1 /bin/true" ]
}
