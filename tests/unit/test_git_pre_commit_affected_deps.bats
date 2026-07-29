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

# test_necessity: shell syntax validation must keep inspecting staged index
# content while the multi-file fast path avoids one git-show process per
# unchanged worktree file.
@test "shell syntax fast path preserves staged-content fail-close" {
  printf '#!/bin/bash\n:\n' >"$REPO/scripts/valid.sh"
  printf '#!/bin/bash\n:\n' >"$REPO/scripts/dirty.sh"
  git -C "$REPO" add scripts/valid.sh scripts/dirty.sh
  printf '#!/bin/bash\nif true; then\n' >"$REPO/scripts/dirty.sh"

  FUNCS="$(extract_funcs check_staged_shell_syntax)"
  run bash -c "
    REPO_ROOT='$REPO'
    $FUNCS
    list_staged_files() { git -C '$REPO' diff --cached --name-only; }
    staged_file_exists() { git -C '$REPO' diff --cached --name-only | grep -qxF \"\$1\"; }
    git() { command git -C '$REPO' \"\$@\"; }
    check_staged_shell_syntax
  "
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  printf '#!/bin/bash\nif true; then\n' >"$REPO/scripts/valid.sh"
  git -C "$REPO" add scripts/valid.sh
  printf '#!/bin/bash\n:\n' >"$REPO/scripts/valid.sh"

  run bash -c "
    REPO_ROOT='$REPO'
    $FUNCS
    list_staged_files() { git -C '$REPO' diff --cached --name-only; }
    staged_file_exists() { git -C '$REPO' diff --cached --name-only | grep -qxF \"\$1\"; }
    git() { command git -C '$REPO' \"\$@\"; }
    check_staged_shell_syntax
  "
  [ "$status" -eq 0 ]
  [ "$output" = "scripts/valid.sh" ]
}

run_affected() {
  local env_prefix="$1"
  FUNCS="$(extract_funcs staged_file_could_have_tests resolve_reverse_lib_deps reverse_lib_dep_scan_scope is_doc_only_fastpath_path all_staged_files_are_doc_only_fastpath resolve_precommit_task_file check_precommit_affected_tests)"
  bash -c "
    REPO_ROOT='$REPO'
    _PRECOMMIT_COMMAND_ID='test-precommit'
    unset NINJA_SCOPE_TASK_FILE
    $env_prefix
    $FUNCS
    list_staged_files() { git -C '$REPO' diff --cached --name-only; }
    staged_file_exists() { git -C '$REPO' diff --cached --name-only | grep -qxF \"\$1\"; }
    defense_overhead_write_async() { printf 'DOH_CALL:%s\n' \"\$*\" >> '$REPO/logs/doh_calls.txt'; }
    check_precommit_affected_tests
  "
}

# test_necessity: ninja_scope_commit's reviewed two-path task contract must
# remain the pre-commit selection boundary rather than expanding transitively.
@test "ninja scope task uses task mode while manual commit keeps affected mode" {
  mkdir -p "$REPO/queue/tasks"
  cat >"$REPO/queue/tasks/kotaro.yaml" <<'YAML'
task:
  planned_paths: [scripts/lib/mylib.sh, tests/unit/owned.bats]
YAML
  printf '#!/bin/bash\necho changed\n' >"$REPO/scripts/lib/mylib.sh"
  git -C "$REPO" add scripts/lib/mylib.sh

  run run_affected "NINJA_SCOPE_TASK_FILE='$REPO/queue/tasks/kotaro.yaml'; export NINJA_SCOPE_TASK_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"affected-test mode=task"* ]]
  [ "$(cat "$REPO/logs/run_tests_call.txt")" = $'task\n'"$REPO"$'/queue/tasks/kotaro.yaml' ]

  rm -f "$REPO/logs/run_tests_call.txt"
  run run_affected ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"affected-test mode=affected"* ]]
  [[ "$(cat "$REPO/logs/run_tests_call.txt")" == affected$'\n'* ]]
}

# test_necessity: a supplied selector is an asserted scope contract; missing
# and outside-repository paths must not silently degrade to affected mode.
@test "ninja scope task path fails closed when missing or outside repo" {
  printf '#!/bin/bash\necho changed\n' >"$REPO/scripts/lib/mylib.sh"
  git -C "$REPO" add scripts/lib/mylib.sh

  run run_affected "NINJA_SCOPE_TASK_FILE='$REPO/queue/tasks/missing.yaml'; export NINJA_SCOPE_TASK_FILE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
  [ ! -e "$REPO/logs/run_tests_call.txt" ]

  outside="$BATS_TEST_TMPDIR/outside.yaml"
  printf 'task: {}\n' >"$outside"
  run run_affected "NINJA_SCOPE_TASK_FILE='$outside'; export NINJA_SCOPE_TASK_FILE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must resolve inside"* ]]
  [ ! -e "$REPO/logs/run_tests_call.txt" ]
}

# test_necessity: linked worktrees have a separate worktree root while sharing
# git metadata; task containment must follow the active root, not the main one.
@test "ninja scope task resolves against the active linked worktree root" {
  linked="$BATS_TEST_TMPDIR/linked"
  git -C "$REPO" worktree add -q -b linked-fixture "$linked"
  mkdir -p "$linked/queue/tasks"
  printf 'task: {}\n' >"$linked/queue/tasks/kotaro.yaml"

  FUNCS="$(extract_funcs resolve_precommit_task_file)"
  run env REPO_ROOT="$linked" NINJA_SCOPE_TASK_FILE="$linked/queue/tasks/kotaro.yaml" \
    bash -c "$FUNCS; resolve_precommit_task_file"
  [ "$status" -eq 0 ]
  [ "$output" = "$linked/queue/tasks/kotaro.yaml" ]
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

# cmd_4182 AC1: doc-only fast-path.
# test_necessity: a docs/research/*.md single-line annotation commit measured
# 41.2-83.9s here (real repo, 61/43 real bats cases via the context/*.md and
# docs/research/*.md mappings in test_select.sh) and, worse, still had to
# queue for the host-wide heavy_job_admission.sh semaphore behind it — 11m12s
# holding the shared ninja-scope-commit lock and failing another ninja's
# commit twice on its 120s timeout (blt_20260727_201344, PID 3923473). This
# invariant — an all-docs/context/memory/archive staged diff never enters
# affected_tests (and therefore never enters heavy_job_admission, which only
# fires from inside scripts/run_tests.sh below this function) — must hold
# permanently or the incident reproduces on the next design-doc commit.

@test "is_doc_only_fastpath_path: classifies docs/context/memory/archive paths as fast-path-eligible" {
  FUNCS="$(extract_funcs is_doc_only_fastpath_path)"
  run bash -c "
    $FUNCS
    for f in docs/research/foo.md context/bar.md memory/baz.md archive/frozen/qux.yaml docs/dashboard/x.html; do
      is_doc_only_fastpath_path \"\$f\" && echo \"YES:\$f\" || echo \"NO:\$f\"
    done
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"YES:docs/research/foo.md"* ]]
  [[ "$output" == *"YES:context/bar.md"* ]]
  [[ "$output" == *"YES:memory/baz.md"* ]]
  [[ "$output" == *"YES:archive/frozen/qux.yaml"* ]]
  [[ "$output" == *"YES:docs/dashboard/x.html"* ]]
}

@test "is_doc_only_fastpath_path: rejects executable files even nested under a doc directory (defense-in-depth)" {
  FUNCS="$(extract_funcs is_doc_only_fastpath_path)"
  run bash -c "
    $FUNCS
    for f in docs/research/tool.sh context/scripts/helper.py scripts/lib/mylib.sh queue/tasks/x.yaml; do
      is_doc_only_fastpath_path \"\$f\" && echo \"YES:\$f\" || echo \"NO:\$f\"
    done
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"NO:docs/research/tool.sh"* ]]
  [[ "$output" == *"NO:context/scripts/helper.py"* ]]
  [[ "$output" == *"NO:scripts/lib/mylib.sh"* ]]
  [[ "$output" == *"NO:queue/tasks/x.yaml"* ]]
}

@test "AC1: a doc-only staged diff (context/*.md) skips affected_tests entirely via the fast-path" {
  mkdir -p "$REPO/context"
  printf '# note\n' > "$REPO/context/growth-loop.md"
  git -C "$REPO" add context/growth-loop.md

  run run_affected ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"AC1(cmd_4182) doc-only fast-path"* ]]
  [ ! -f "$REPO/logs/run_tests_call.txt" ]
}

@test "AC1: a doc-only staged diff spanning docs+context+memory+archive together still takes the fast-path" {
  mkdir -p "$REPO/docs/research" "$REPO/context" "$REPO/memory" "$REPO/archive"
  printf 'design note\n' > "$REPO/docs/research/design.md"
  printf '# ctx\n' > "$REPO/context/growth-loop.md"
  printf 'memo\n' > "$REPO/memory/deepdive.md"
  printf 'old\n' > "$REPO/archive/log.md"
  git -C "$REPO" add docs/research/design.md context/growth-loop.md memory/deepdive.md archive/log.md

  run run_affected ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"AC1(cmd_4182) doc-only fast-path"* ]]
  [ ! -f "$REPO/logs/run_tests_call.txt" ]
}

@test "AC2 negative control: a mixed doc+script diff does NOT take the fast-path and still runs affected tests" {
  mkdir -p "$REPO/context"
  printf '# note\n' > "$REPO/context/growth-loop.md"
  printf '#!/bin/bash\necho unrelated\n' > "$REPO/scripts/unrelated.sh"
  git -C "$REPO" add context/growth-loop.md scripts/unrelated.sh

  run run_affected ""
  [ "$status" -eq 0 ]
  [[ "$output" != *"AC1(cmd_4182) doc-only fast-path"* ]]
  call_args="$(cat "$REPO/logs/run_tests_call.txt")"
  [[ "$call_args" == *"scripts/unrelated.sh"* ]]
}

@test "AC2 negative control: a script-only diff does NOT take the fast-path (unchanged from before AC1)" {
  printf '#!/bin/bash\necho unrelated\n' > "$REPO/scripts/unrelated.sh"
  git -C "$REPO" add scripts/unrelated.sh

  run run_affected ""
  [ "$status" -eq 0 ]
  [[ "$output" != *"AC1(cmd_4182) doc-only fast-path"* ]]
  [ -f "$REPO/logs/run_tests_call.txt" ]
}

@test "AC3: the doc-only fast-path emits one defense_overhead instrumentation call with a distinguishable check_id" {
  mkdir -p "$REPO/context"
  printf '# note\n' > "$REPO/context/growth-loop.md"
  git -C "$REPO" add context/growth-loop.md

  run run_affected ""
  [ "$status" -eq 0 ]
  [ -f "$REPO/logs/doh_calls.txt" ]
  grep -q 'affected_tests_docs_fastpath' "$REPO/logs/doh_calls.txt"
  grep -q 'git_pre_commit affected_tests_docs_fastpath 0 PASS' "$REPO/logs/doh_calls.txt"
}
