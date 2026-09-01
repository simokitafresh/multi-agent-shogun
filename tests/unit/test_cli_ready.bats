#!/usr/bin/env bats
# test_necessity: the launch-time "CLI ready" predicate must match only an idle
# input prompt (claude ❯ / codex ›) on the visible screen, and must not match the
# bypass footer alone, confirmation/update/usage dialogs, or a crashed shell.
# regression_justification: 2026-09-01 11:23 six Ninja died at launch and the
# launcher still reported success; the first fix's regex matched the footer alone
# and could report a half-started pane as ready (karo review 13:05).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$ROOT/scripts/lib/cli_ready.sh"
}

@test "claude idle prompt (empty ❯ line) is ready" {
  run cli_visible_is_ready $'  CTX:38%\n❯ \n  ⏵⏵ bypass permissions on (shift+tab to cycle)'
  [ "$status" -eq 0 ]
}

@test "codex idle prompt (› Ask Codex to do anything) is ready" {
  run cli_visible_is_ready $'› Ask Codex to do anything\n  gpt-5.6-luna high · Context 0% used'
  [ "$status" -eq 0 ]
}

@test "bypass footer alone (no prompt line) is not ready" {
  run cli_visible_is_ready $'Loading…\n  ⏵⏵ bypass permissions on (shift+tab to cycle)'
  [ "$status" -ne 0 ]
}

@test "claude trust/confirmation dialog with ❯ cursor on an option is not ready" {
  run cli_visible_is_ready $'Do you want to proceed?\n ❯ 1. Yes\n   2. No'
  [ "$status" -ne 0 ]
}

@test "codex update prompt with › cursor on an option is not ready" {
  run cli_visible_is_ready $'Update available! 0.151.0 -> 0.152.0\n› 1. Update now\n  2. Skip until next version'
  [ "$status" -ne 0 ]
}

@test "codex usage limit screen is not ready" {
  run cli_visible_is_ready $'You have hit your weekly limit. Resets in 3 days.\n  1. Redeem  2. Full reset'
  [ "$status" -ne 0 ]
}

@test "crashed shell after database is locked is not ready" {
  run cli_visible_is_ready $'sqlite3: database is locked\n(疾風) ~/multi-agent-shogun$ '
  [ "$status" -ne 0 ]
}

@test "codex process count is a single integer even when zero" {
  pgrep() { printf '0\n'; return 1; }
  export -f pgrep
  run cli_codex_process_count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}
