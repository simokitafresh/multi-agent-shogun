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
