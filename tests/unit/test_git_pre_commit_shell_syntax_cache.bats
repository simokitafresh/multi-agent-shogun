#!/usr/bin/env bats
# test_necessity: pre-commit may reuse shell syntax validation only for an
# exact staged blob OID + content SHA-256 + Bash-version PASS; changed or
# unreadable blobs must run/fail closed, failed parses must never be cached,
# and sourced-dependency validation must remain an independent later gate.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$ROOT/scripts/hooks/git-pre-commit.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/scripts"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name test
  printf 'baseline\n' > "$REPO/README.md"
  git -C "$REPO" add README.md
  git -C "$REPO" commit -qm baseline
}

extract_funcs() {
  local name
  for name in "$@"; do
    sed -n "/^${name}()/,/^}/p" "$HOOK"
  done
}

run_syntax_check() {
  local cache_dir="$1" force_unknown="${2:-false}"
  local funcs
  funcs="$(extract_funcs precommit_shell_syntax_cache_hit precommit_shell_syntax_cache_publish check_staged_shell_syntax)"
  REPO="$REPO" CACHE_DIR="$cache_dir" FORCE_UNKNOWN="$force_unknown" FUNCS="$funcs" bash -c '
    REPO_ROOT="$REPO"
    PRECOMMIT_SHELL_SYNTAX_CACHE_DIR="$CACHE_DIR"
    eval "$FUNCS"
    list_staged_files() { command git -C "$REPO" diff --cached --name-only; }
    staged_file_exists() { command git -C "$REPO" diff --cached --name-only | grep -qxF "$1"; }
    git() {
      if [[ "$FORCE_UNKNOWN" == true && "$1" == rev-parse && "$2" == :scripts/huge.sh ]]; then
        return 1
      fi
      command git -C "$REPO" "$@"
    }
    check_staged_shell_syntax
  '
}

@test "same huge staged shell reuses exact PASS while changed and failing blobs never reuse it" {
  awk 'BEGIN { print "#!/usr/bin/env bash"; for (i=0; i<180000; i++) print ": # syntax-padding-" i }' \
    > "$REPO/scripts/huge.sh"
  git -C "$REPO" add scripts/huge.sh

  local -a before_ms=() after_ms=()
  local trial started ended cache_dir
  for trial in 1 2 3; do
    cache_dir="$BATS_TEST_TMPDIR/cache-before-$trial"
    started="$(date +%s%N)"
    run run_syntax_check "$cache_dir"
    ended="$(date +%s%N)"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    before_ms+=("$(( (ended - started) / 1000000 ))")
  done

  cache_dir="$BATS_TEST_TMPDIR/cache-before-3"
  local marker_before
  marker_before="$(sha256sum "$cache_dir"/*.pass)"
  for trial in 1 2 3; do
    started="$(date +%s%N)"
    run run_syntax_check "$cache_dir"
    ended="$(date +%s%N)"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    after_ms+=("$(( (ended - started) / 1000000 ))")
  done

  local before_median after_median
  before_median="$(printf '%s\n' "${before_ms[@]}" | sort -n | sed -n '2p')"
  after_median="$(printf '%s\n' "${after_ms[@]}" | sort -n | sed -n '2p')"
  printf 'SHELL_CACHE before_ms=%s,%s,%s median=%s after_ms=%s,%s,%s median=%s\n' \
    "${before_ms[0]}" "${before_ms[1]}" "${before_ms[2]}" "$before_median" \
    "${after_ms[0]}" "${after_ms[1]}" "${after_ms[2]}" "$after_median" >&3
  [ "$(find "$cache_dir" -maxdepth 1 -type f -name '*.pass' | wc -l)" -eq 1 ]
  [ "$(sha256sum "$cache_dir"/*.pass)" = "$marker_before" ]

  printf 'echo changed-blob\n' >> "$REPO/scripts/huge.sh"
  git -C "$REPO" add scripts/huge.sh
  run run_syntax_check "$cache_dir"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(find "$cache_dir" -maxdepth 1 -type f -name '*.pass' | wc -l)" -eq 2 ]

  printf 'if true; then\n' >> "$REPO/scripts/huge.sh"
  git -C "$REPO" add scripts/huge.sh
  run run_syntax_check "$cache_dir"
  [ "$status" -eq 0 ]
  [ "$output" = "scripts/huge.sh" ]
  [ "$(find "$cache_dir" -maxdepth 1 -type f -name '*.pass' | wc -l)" -eq 2 ]
  run run_syntax_check "$cache_dir"
  [ "$status" -eq 0 ]
  [ "$output" = "scripts/huge.sh" ]
  [ "$(find "$cache_dir" -maxdepth 1 -type f -name '*.pass' | wc -l)" -eq 2 ]
}

@test "unknown index blob identity fails closed" {
  printf '#!/usr/bin/env bash\n:\n' > "$REPO/scripts/huge.sh"
  git -C "$REPO" add scripts/huge.sh
  run run_syntax_check "$BATS_TEST_TMPDIR/cache" true
  [ "$status" -eq 0 ]
  [ "$output" = "scripts/huge.sh" ]
  [ ! -d "$BATS_TEST_TMPDIR/cache" ]
}

# test_necessity: a staged deletion of a .sh file has no index blob and must be
# skipped, not reported as a syntax failure (fail-closed only applies to blobs
# that exist in the index).
# regression_justification: 2026-09-01 `git rm scripts/shutsujin_departure.sh`
# was BLOCKed by pre-commit as "bash -n failed on staged shell script(s)".
@test "staged shell deletion is not a syntax failure" {
  printf '#!/usr/bin/env bash\n:\n' > "$REPO/scripts/old.sh"
  git -C "$REPO" add scripts/old.sh
  git -C "$REPO" commit -qm "add old.sh"
  git -C "$REPO" rm -q scripts/old.sh
  run run_syntax_check "$BATS_TEST_TMPDIR/cache-del"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "syntax cache hit does not bypass sourced dependency validation" {
  printf '#!/usr/bin/env bash\nsource scripts/untracked_dep.sh\n' > "$REPO/scripts/huge.sh"
  printf ':\n' > "$REPO/scripts/untracked_dep.sh"
  git -C "$REPO" add scripts/huge.sh
  local cache_dir="$BATS_TEST_TMPDIR/cache"
  run run_syntax_check "$cache_dir"
  [ "$status" -eq 0 ]

  local funcs
  funcs="$(extract_funcs precommit_shell_syntax_cache_hit precommit_shell_syntax_cache_publish check_staged_shell_syntax check_staged_sourced_deps)"
  run env REPO="$REPO" CACHE_DIR="$cache_dir" FUNCS="$funcs" bash -c '
    REPO_ROOT="$REPO"
    PRECOMMIT_SHELL_SYNTAX_CACHE_DIR="$CACHE_DIR"
    eval "$FUNCS"
    list_staged_files() { command git -C "$REPO" diff --cached --name-only; }
    staged_file_exists() { command git -C "$REPO" diff --cached --name-only | grep -qxF "$1"; }
    git() { command git -C "$REPO" "$@"; }
    check_staged_shell_syntax
    check_staged_sourced_deps
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCKED: staged script sources a repo file"* ]]
  [[ "$output" == *"scripts/huge.sh -> scripts/untracked_dep.sh"* ]]
}

@test "many large staged shell blobs remove repeated bash parse as the phase wall-time driver" {
  local file index
  for index in $(seq 1 12); do
    file="$REPO/scripts/large_${index}.sh"
    awk -v prefix="$index" 'BEGIN {
      print "#!/usr/bin/env bash"
      for (i=0; i<45000; i++)
        print "syntax_" prefix "_" i "() { if true; then :; fi; }"
    }' > "$file"
  done
  git -C "$REPO" add scripts/large_*.sh

  local -a before_ms=() after_ms=()
  local trial started ended cache_dir
  for trial in 1 2 3; do
    cache_dir="$BATS_TEST_TMPDIR/many-cold-$trial"
    started="$(date +%s%N)"
    run run_syntax_check "$cache_dir"
    ended="$(date +%s%N)"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    before_ms+=("$(( (ended - started) / 1000000 ))")
  done

  cache_dir="$BATS_TEST_TMPDIR/many-cold-3"
  [ "$(find "$cache_dir" -maxdepth 1 -type f -name '*.pass' | wc -l)" -eq 12 ]
  for trial in 1 2 3; do
    started="$(date +%s%N)"
    run run_syntax_check "$cache_dir"
    ended="$(date +%s%N)"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    after_ms+=("$(( (ended - started) / 1000000 ))")
  done

  local before_median after_median
  before_median="$(printf '%s\n' "${before_ms[@]}" | sort -n | sed -n '2p')"
  after_median="$(printf '%s\n' "${after_ms[@]}" | sort -n | sed -n '2p')"
  printf 'MANY_SHELL_PHASE blobs=12 lines_each=45001 before_ms=%s,%s,%s median=%s after_ms=%s,%s,%s median=%s\n' \
    "${before_ms[0]}" "${before_ms[1]}" "${before_ms[2]}" "$before_median" \
    "${after_ms[0]}" "${after_ms[1]}" "${after_ms[2]}" "$after_median" >&3
  [ "$after_median" -lt "$before_median" ]
}
