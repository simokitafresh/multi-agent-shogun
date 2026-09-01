#!/usr/bin/env bats
# test_necessity: a staged deletion whose basename is still referenced from
# tests/ or scripts/ (staged index view) must be reported by
# check_staged_deleted_refs, and a deletion whose references are removed in the
# same commit must produce no output. Invariant guards 2026-09-01 559c02538
# (scripts/shutsujin_departure.sh dropped as "no callers" while
# tests/unit/test_reset_layout.bats:60 still grep'd it -> CI shard 1 RED).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$ROOT/scripts/hooks/git-pre-commit.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/scripts" "$REPO/tests/unit" "$REPO/docs"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name test
  printf '#!/usr/bin/env bash\necho legacy\n' > "$REPO/scripts/legacy_departure.sh"
  printf '@test "x" {\n  grep -q select-layout "$PROJECT_ROOT/scripts/legacy_departure.sh"\n}\n' > "$REPO/tests/unit/test_legacy.bats"
  printf 'see scripts/legacy_departure.sh\n' > "$REPO/docs/note.md"
  git -C "$REPO" add .
  git -C "$REPO" commit -qm baseline
}

extract_funcs() {
  local name
  for name in "$@"; do
    sed -n "/^${name}()/,/^}/p" "$HOOK"
  done
}

run_deleted_ref_check() {
  local funcs
  funcs="$(extract_funcs check_staged_deleted_refs)"
  REPO="$REPO" FUNCS="$funcs" bash -c '
    REPO_ROOT="$REPO"
    eval "$FUNCS"
    declare -A _STAGED_FILE_STATUS=()
    load_staged_file_cache() {
      local status path
      while IFS=$'"'"'\t'"'"' read -r status path; do
        [[ -n "$path" ]] && _STAGED_FILE_STATUS["$path"]="$status"
      done < <(command git -C "$REPO" diff --cached --name-status)
    }
    git() { command git -C "$REPO" "$@"; }
    check_staged_deleted_refs
  '
}

@test "staged deletion still referenced from tests/ is reported with the referencing file" {
  git -C "$REPO" rm -q scripts/legacy_departure.sh
  run run_deleted_ref_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"scripts/legacy_departure.sh <- "* ]]
  [[ "$output" == *"tests/unit/test_legacy.bats"* ]]
  # docs/ is outside the caller census; it must not be listed.
  [[ "$output" != *"docs/note.md"* ]]
}

@test "deletion whose references are removed in the same commit produces no output" {
  git -C "$REPO" rm -q scripts/legacy_departure.sh
  printf '@test "x" {\n  true\n}\n' > "$REPO/tests/unit/test_legacy.bats"
  git -C "$REPO" add tests/unit/test_legacy.bats
  run run_deleted_ref_check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no staged deletion produces no output" {
  printf 'echo more\n' >> "$REPO/scripts/legacy_departure.sh"
  git -C "$REPO" add scripts/legacy_departure.sh
  run run_deleted_ref_check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
