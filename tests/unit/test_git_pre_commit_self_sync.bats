#!/usr/bin/env bats
# test_necessity: pre-commit self-sync must skip its full synchronizer only when
# the installed hook equals HEAD and no hook-related path is staged; stale,
# staged, and unreadable identities must remain fail-closed sync decisions.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  REPO="$(mktemp -d)"
  mkdir -p "$REPO/scripts/hooks" "$REPO/.git/hooks"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name tester
  printf '#!/bin/sh\nexit 0\n' >"$REPO/scripts/hooks/git-pre-commit.sh"
  git -C "$REPO" add scripts/hooks/git-pre-commit.sh
  git -C "$REPO" commit -qm base
  cp "$REPO/scripts/hooks/git-pre-commit.sh" "$REPO/.git/hooks/pre-commit"
}

teardown() { rm -rf "$REPO"; }

decision() {
  local staged="${1:-}" installed="${2:-$REPO/.git/hooks/pre-commit}"
  local measure="${3:-0}"
  REPO_ROOT="$REPO" STAGED="$staged" INSTALLED="$installed" MEASURE="$measure" HOOK="$ROOT/scripts/hooks/git-pre-commit.sh" bash -c '
    eval "$(sed -n "/^staged_hook_related_exists()/,/^}/p; /^precommit_self_sync_required()/,/^}/p" "$HOOK")"
    load_staged_file_cache(){ _STAGED_FILES=(); [ -z "$STAGED" ] || _STAGED_FILES+=("$STAGED"); }
    start_ns="$(date +%s%N)"
    if precommit_self_sync_required "$INSTALLED"; then result=sync; else result=skip; fi
    elapsed_ms=$(( ($(date +%s%N)-start_ns)/1000000 ))
    if [ "$MEASURE" = 1 ]; then echo "$result $elapsed_ms"; else echo "$result"; fi
  '
}

@test "matching installed and HEAD hook with no staged hook skips sync under 0.2s" {
  run decision '' "$REPO/.git/hooks/pre-commit" 1
  [ "$status" -eq 0 ]
  [ "${output%% *}" = skip ]
  [ "${output##* }" -lt 200 ]
}

@test "stale installed hook requires sync" {
  printf stale >"$REPO/.git/hooks/pre-commit"
  run decision
  [ "$status" -eq 0 ]
  [ "$output" = sync ]
}

@test "any staged hook-related path requires sync" {
  run decision .githooks/pre-push
  [ "$status" -eq 0 ]
  [ "$output" = sync ]
}

@test "unreadable or missing installed identity requires sync" {
  run decision '' "$REPO/.git/hooks/missing"
  [ "$status" -eq 0 ]
  [ "$output" = sync ]
}

@test "self-sync failure path remains a blocking exit" {
  run python3 - "$ROOT/scripts/hooks/git-pre-commit.sh" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
assert 'bash "$REPO_ROOT/scripts/sync_git_hooks.sh" "${_sync_args[@]}" || {' in s
assert 'BLOCK(GA-222): live pre-commit hook self-sync failed' in s
assert 'exit 1' in s
PY
  [ "$status" -eq 0 ]
}
