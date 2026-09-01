#!/usr/bin/env bats
# test_necessity: check_staged_deleted_refs must classify a staged deletion by
# how tests/ and scripts/ (staged index view) still reference it — EXACT when
# the repo-relative path is referenced (the committer must fix or justify),
# BASENAME when only the file name matches (candidate, may be a same-named
# file) — and stay silent when references are removed in the same commit or
# nothing is deleted. Invariant guards 2026-09-01 559c02538
# (scripts/shutsujin_departure.sh dropped as "no callers" while
# tests/unit/test_reset_layout.bats:60 still grep'd it -> CI shard 1 RED) and
# Karo review 14:54 (basename-only census mis-hits same-named files).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$ROOT/scripts/hooks/git-pre-commit.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/scripts/lib" "$REPO/tests/unit" "$REPO/docs"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name test
  printf '#!/usr/bin/env bash\necho legacy\n' > "$REPO/scripts/legacy_departure.sh"
  printf '#!/usr/bin/env bash\necho other\n' > "$REPO/scripts/lib/legacy_departure.sh"
  printf '@test "x" {\n  grep -q select-layout "$PROJECT_ROOT/scripts/legacy_departure.sh"\n}\n' > "$REPO/tests/unit/test_legacy.bats"
  printf '@test "y" {\n  bash "$PROJECT_ROOT/scripts/lib/legacy_departure.sh"\n}\n' > "$REPO/tests/unit/test_lib.bats"
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

@test "exact repo path reference from tests/ is reported as EXACT; same-named file elsewhere is only a BASENAME candidate" {
  git -C "$REPO" rm -q scripts/legacy_departure.sh
  run run_deleted_ref_check
  [ "$status" -eq 0 ]
  exact_line="$(printf '%s\n' "$output" | grep '^EXACT' || true)"
  base_line="$(printf '%s\n' "$output" | grep '^BASENAME' || true)"
  [[ "$exact_line" == "EXACT	scripts/legacy_departure.sh	"* ]]
  [[ "$exact_line" == *"tests/unit/test_legacy.bats"* ]]
  # test_lib.bats references scripts/lib/legacy_departure.sh: never EXACT, only a basename candidate.
  [[ "$exact_line" != *"test_lib.bats"* ]]
  [[ "$base_line" == "BASENAME	scripts/legacy_departure.sh	"* ]]
  [[ "$base_line" == *"tests/unit/test_lib.bats"* ]]
  # a file already listed as EXACT is not repeated as a BASENAME candidate
  [[ "$base_line" != *"test_legacy.bats"* ]]
  # docs/ is outside the caller census
  [[ "$output" != *"docs/note.md"* ]]
}

@test "deletion whose exact references are removed in the same commit yields no EXACT line" {
  git -C "$REPO" rm -q scripts/legacy_departure.sh
  printf '@test "x" {\n  true\n}\n' > "$REPO/tests/unit/test_legacy.bats"
  git -C "$REPO" add tests/unit/test_legacy.bats
  run run_deleted_ref_check
  [ "$status" -eq 0 ]
  [[ "$output" != *"EXACT"* ]]
  # the same-named lib file still makes it a BASENAME candidate only
  [[ "$output" == *"BASENAME	scripts/legacy_departure.sh	"* ]]
}

@test "deletion with no remaining references produces no output" {
  git -C "$REPO" rm -q scripts/legacy_departure.sh
  printf '@test "x" {\n  true\n}\n' > "$REPO/tests/unit/test_legacy.bats"
  git -C "$REPO" rm -q scripts/lib/legacy_departure.sh tests/unit/test_lib.bats
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
