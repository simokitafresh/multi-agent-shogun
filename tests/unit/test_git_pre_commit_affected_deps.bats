#!/usr/bin/env bats
# cmd_karo_impl_precommit_affected_link_20260725
# test_necessity: reproduces CI RED run 30150910971 as a regression fixture —
# a scripts/lib/ change whose own tests pass but breaks a caller's dependent
# test must be caught by pre-commit (AC2 reverse-dependency expansion feeding
# AC1's affected-test run), not discovered later in CI. AC5(a)'s untracked-
# source incident is already covered by test_git_pre_commit_sourced_dep.bats
# (check_staged_sourced_deps existed before this task); not duplicated here.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$ROOT/scripts/hooks/git-pre-commit.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/scripts/lib" "$REPO/.githooks" "$REPO/.claude/hooks" "$REPO/logs"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name test
  printf '# baseline\n' > "$REPO/README.md"
  git -C "$REPO" add README.md
  git -C "$REPO" commit -qm baseline

  # A caller that sources the lib via a subshell-wrapped path, the exact
  # shape that defeats a strict quote-excluding regex (deliberately not the
  # simplest literal "scripts/lib/x.sh" form).
  printf '#!/bin/bash\nsource "$(dirname "$0")/lib/mylib.sh"\n' > "$REPO/scripts/caller.sh"
  printf '#!/bin/bash\n:\n' > "$REPO/scripts/lib/mylib.sh"
  git -C "$REPO" add scripts/caller.sh scripts/lib/mylib.sh
  git -C "$REPO" commit -qm "add caller+lib"

  # Stub run_tests.sh: records the file set it was called with and fails
  # exactly when scripts/caller.sh (the dependent side) is among the
  # targets — this is what "the changed file's own tests pass but the
  # dependent side breaks" looks like from the hook's perspective.
  cat > "$REPO/scripts/run_tests.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "$(dirname "$0")/../logs/run_tests_call.txt"
shift
for a in "$@"; do
    [ "$a" = "scripts/caller.sh" ] && { echo "FAIL: dependent test broke" >&2; exit 1; }
done
exit 0
STUB
  chmod +x "$REPO/scripts/run_tests.sh"
}

extract_funcs() {
  local name
  for name in "$@"; do
    sed -n "/^${name}()/,/^}/p" "$HOOK"
  done
}

run_affected() {
  local env_prefix="$1"
  FUNCS="$(extract_funcs staged_file_could_have_tests resolve_reverse_lib_deps reverse_lib_dep_scan_scope check_precommit_affected_tests)"
  bash -c "
    REPO_ROOT='$REPO'
    $env_prefix
    $FUNCS
    list_staged_files() { git -C '$REPO' diff --cached --name-only; }
    staged_file_exists() { git -C '$REPO' diff --cached --name-only | grep -qxF \"\$1\"; }
    check_precommit_affected_tests
  "
}

@test "resolve_reverse_lib_deps finds a caller that invokes the lib as a subprocess (bash x.sh), not just source" {
  # Real-scale finding (軍師 review, 2026-07-25): the overwhelming majority of
  # scripts/lib/yaml_field_set.sh's 37 repo references are `bash
  # .../yaml_field_set.sh "$file" ...` CLI-style calls, not `source`. A
  # source-only pattern silently misses almost all real callers.
  printf '#!/bin/bash\nbash "$(dirname "$0")/lib/mylib.sh" "$1"\n' > "$REPO/scripts/caller.sh"
  git -C "$REPO" add scripts/caller.sh
  git -C "$REPO" commit -qm "caller invokes lib as subprocess"
  printf '#!/bin/bash\necho changed\n' > "$REPO/scripts/lib/mylib.sh"
  git -C "$REPO" add scripts/lib/mylib.sh

  FUNCS="$(extract_funcs resolve_reverse_lib_deps)"
  run bash -c "
    REPO_ROOT='$REPO'
    $FUNCS
    list_staged_files() { git -C '$REPO' diff --cached --name-only; }
    staged_file_exists() { git -C '$REPO' diff --cached --name-only | grep -qxF \"\$1\"; }
    resolve_reverse_lib_deps
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"scripts/caller.sh"* ]]
}

@test "resolve_reverse_lib_deps finds a caller even through a subshell-wrapped source path" {
  printf '#!/bin/bash\necho changed\n' > "$REPO/scripts/lib/mylib.sh"
  git -C "$REPO" add scripts/lib/mylib.sh

  FUNCS="$(extract_funcs resolve_reverse_lib_deps)"
  run bash -c "
    REPO_ROOT='$REPO'
    $FUNCS
    list_staged_files() { git -C '$REPO' diff --cached --name-only; }
    staged_file_exists() { git -C '$REPO' diff --cached --name-only | grep -qxF \"\$1\"; }
    resolve_reverse_lib_deps
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"scripts/caller.sh"* ]]
}

@test "AC5(b): a scripts/lib change that breaks a caller's dependent test is BLOCKED, not just the lib's own test" {
  printf '#!/bin/bash\necho changed\n' > "$REPO/scripts/lib/mylib.sh"
  git -C "$REPO" add scripts/lib/mylib.sh

  run run_affected ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCK(GA-PRECOMMIT1)"* ]]

  call_args="$(cat "$REPO/logs/run_tests_call.txt")"
  [[ "$call_args" == *"scripts/caller.sh"* ]]
  [[ "$call_args" == *"scripts/lib/mylib.sh"* ]]
}

@test "reports the reverse-dep scan scope size (LG042/LK-A14)" {
  printf '#!/bin/bash\necho changed\n' > "$REPO/scripts/lib/mylib.sh"
  git -C "$REPO" add scripts/lib/mylib.sh

  run run_affected ""
  [[ "$output" == *"AC2 reverse-dep scan: scope="* ]]
  [[ "$output" == *"caller_matches=1"* ]]
}

@test "a change outside scripts/lib/ does not trigger reverse-dep expansion" {
  printf '#!/bin/bash\necho unrelated\n' > "$REPO/scripts/unrelated.sh"
  git -C "$REPO" add scripts/unrelated.sh

  run run_affected ""
  [ "$status" -eq 0 ]
  [[ "$output" != *"AC2 reverse-dep scan"* ]]
  call_args="$(cat "$REPO/logs/run_tests_call.txt")"
  [[ "$call_args" == *"scripts/unrelated.sh"* ]]
  [[ "$call_args" != *"scripts/caller.sh"* ]]
}

@test "AC3: a data-only commit (no code-like staged path) skips affected-test resolution entirely" {
  mkdir -p "$REPO/queue"
  printf 'note: ops update\n' > "$REPO/queue/notes.yaml"
  git -C "$REPO" add queue/notes.yaml

  run run_affected ""
  [ "$status" -eq 0 ]
  [ ! -f "$REPO/logs/run_tests_call.txt" ]
}

@test "AC4 escape hatch bypasses the BLOCK and logs reason+agent to logs/precommit_affected_bypass.jsonl" {
  printf '#!/bin/bash\necho changed\n' > "$REPO/scripts/lib/mylib.sh"
  git -C "$REPO" add scripts/lib/mylib.sh

  run run_affected "SHOGUN_PRECOMMIT_AFFECTED_BYPASS='emergency CI RED fix' TMUX_AGENT_ID=kagemaru; export SHOGUN_PRECOMMIT_AFFECTED_BYPASS TMUX_AGENT_ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN(GA-PRECOMMIT1)"* ]]

  [ -f "$REPO/logs/precommit_affected_bypass.jsonl" ]
  grep -q '"reason": "emergency CI RED fix"' "$REPO/logs/precommit_affected_bypass.jsonl"
  grep -q '"agent": "kagemaru"' "$REPO/logs/precommit_affected_bypass.jsonl"
}
