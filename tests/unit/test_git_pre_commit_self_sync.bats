#!/usr/bin/env bats
# test_necessity: pre-commit self-sync must skip its full synchronizer only when
# the installed hook equals the repo SSOT and no manifest-backed Git hook path is
# staged; stale, manifest-staged, and unreadable identities remain fail-closed.
# Production acceptance additionally reads PRECOMMIT_RECEIPT self_sync_ms on DrvFS.

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
    eval "$(sed -n "/^staged_hook_related_exists()/,/^}/p; /^staged_hook_sync_required()/,/^}/p; /^precommit_self_sync_required()/,/^}/p" "$HOOK")"
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

@test "manifest post-commit path requires sync" {
  run decision .githooks/post-commit
  [ "$status" -eq 0 ]
  [ "$output" = sync ]
}

@test "non-manifest scripts hook does not trigger git hook sync" {
  run decision scripts/hooks/three_layer_preflight.sh
  [ "$status" -eq 0 ]
  [ "$output" = skip ]
}

@test "staged pre-commit SSOT already equal to installed hook skips full sync" {
  run decision scripts/hooks/git-pre-commit.sh
  [ "$status" -eq 0 ]
  [ "$output" = skip ]
}

@test "staged pre-commit SSOT differing from installed hook requires sync" {
  printf stale >"$REPO/.git/hooks/pre-commit"
  run decision scripts/hooks/git-pre-commit.sh
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

@test "self_sync ledger row carries all five branch observations" {
  ledger="$REPO/defense_overhead.jsonl"
  python3 - "$ROOT/scripts/hooks/git-pre-commit.sh" >"$REPO/self_sync_writer.sh" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
start = text.index("precommit_self_sync_write_async() {")
end = text.index("\n}\n\nprecommit_terminal_receipt()", start) + 2
print(text[start:end])
PY
  FUNCS="$(cat "$REPO/self_sync_writer.sh")"
  run env REPO_ROOT="$REPO" DEFENSE_OVERHEAD_LEDGER="$ledger" bash -c "
    $FUNCS
    _PRECOMMIT_SELF_SYNC_RUNNING_IS_LIVE_HOOK=true
    _PRECOMMIT_SELF_SYNC_STAGED_HOOK_RELATED=false
    _PRECOMMIT_SELF_SYNC_CMP_EQUAL=true
    _PRECOMMIT_SELF_SYNC_SYNC_CALLED=false
    _PRECOMMIT_SELF_SYNC_REEXEC=false
    precommit_self_sync_write_async 17 PASS fixture-self-sync
    wait
  "
  [ "$status" -eq 0 ]
  run python3 - "$ledger" <<'PY'
import json
import sys
row = json.loads(open(sys.argv[1], encoding="utf-8").read())
expected = {
    "running_is_live_hook": True,
    "staged_hook_related": False,
    "cmp_equal": True,
    "sync_called": False,
    "reexec": False,
}
assert all(key in row for key in expected)
assert {key: row[key] for key in expected} == expected
PY
  [ "$status" -eq 0 ]
}

@test "reexec carries the original self_sync start and all branch flags" {
  run python3 - "$ROOT/scripts/hooks/git-pre-commit.sh" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
for contract in (
    'PRECOMMIT_SELF_SYNC_STARTED_US="$_PRECOMMIT_SELF_SYNC_STARTED_US"',
    'PRECOMMIT_SELF_SYNC_RUNNING_IS_LIVE_HOOK="$_PRECOMMIT_SELF_SYNC_RUNNING_IS_LIVE_HOOK"',
    'PRECOMMIT_SELF_SYNC_STAGED_HOOK_RELATED="$_PRECOMMIT_SELF_SYNC_STAGED_HOOK_RELATED"',
    'PRECOMMIT_SELF_SYNC_CMP_EQUAL="$_PRECOMMIT_SELF_SYNC_CMP_EQUAL"',
    'PRECOMMIT_SELF_SYNC_SYNC_CALLED="$_PRECOMMIT_SELF_SYNC_SYNC_CALLED"',
    'PRECOMMIT_SELF_SYNC_REEXEC="$_PRECOMMIT_SELF_SYNC_REEXEC"',
):
    assert contract in text
assert '_PRECOMMIT_STEP_STARTED_US="$_PRECOMMIT_SELF_SYNC_STARTED_US"' in text
PY
  [ "$status" -eq 0 ]
}
