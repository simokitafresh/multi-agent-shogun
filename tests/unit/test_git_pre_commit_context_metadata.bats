#!/usr/bin/env bats
# test_necessity: staged operational context documents must carry freshness metadata; excluded generated/stable references remain committable.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$ROOT/scripts/hooks/git-pre-commit.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/context" "$REPO/config"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name test
  printf '# baseline\n' > "$REPO/README.md"
  git -C "$REPO" add README.md
  git -C "$REPO" commit -qm baseline
}

run_check() {
  local staged_file="$1"
  REPO_ROOT="$REPO" STAGED_FILE="$staged_file" HOOK="$HOOK" bash -c '
    eval "$(sed -n "/^context_freshness_excluded()/,/^}/p; /^check_staged_context_last_updated()/,/^}/p" "$HOOK")"
    declare -A _STAGED_FILE_STATUS=(["$STAGED_FILE"]="A")
    list_staged_files() { printf "%s\n" "$STAGED_FILE"; }
    cd "$REPO_ROOT"
    check_staged_context_last_updated
  '
}

@test "GA-318 blocks staged operational context without last_updated" {
  printf '# missing\n' > "$REPO/context/missing.md"
  git -C "$REPO" add context/missing.md
  run run_check context/missing.md
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCK(GA-318)"* ]]
}

@test "GA-318 permits staged context with last_updated" {
  printf '# fresh\n<!-- last_updated: 2026-07-23 cmd_test -->\n' > "$REPO/context/fresh.md"
  git -C "$REPO" add context/fresh.md
  run run_check context/fresh.md
  [ "$status" -eq 0 ]
}

@test "GA-318 permits explicitly excluded generated context" {
  printf 'context/generated.md\n' > "$REPO/config/context_freshness_excludes.txt"
  printf '# generated\n' > "$REPO/context/generated.md"
  git -C "$REPO" add context/generated.md
  run run_check context/generated.md
  [ "$status" -eq 0 ]
}
