#!/usr/bin/env bats

# test_necessity: auto_commit_before_clear must never mutate the caller's shared Git index tree.

setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/scripts" "$REPO/context"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name test
  printf 'base\n' > "$REPO/shared.txt"
  printf 'base\n' > "$REPO/scripts/regular.sh"
  printf 'base\n' > "$REPO/context/current.md"
  git -C "$REPO" add .
  git -C "$REPO" commit -qm base

  sed -n '/^auto_commit_with_dedicated_index()/,/^}/p' \
    "$BATS_TEST_DIRNAME/../../scripts/ninja_monitor.sh" > "$REPO/helper.sh"
  cat >> "$REPO/helper.sh" <<'EOF'
log() { printf '%s\n' "$*" >> "$TEST_LOG"; }
EOF
}

index_tree() {
  git -C "$REPO" write-tree
}

run_helper() {
  local branch="$1"
  local paths="$2"
  (
    cd "$REPO"
    export TEST_LOG="$REPO/events.log"
    source ./helper.sh
    auto_commit_with_dedicated_index kotaro "$branch" "test $branch" "$paths"
  )
}

@test "regular success preserves pre-existing shared stage" {
  printf 'staged\n' > "$REPO/shared.txt"
  git -C "$REPO" add shared.txt
  printf 'regular\n' > "$REPO/scripts/regular.sh"
  before=$(index_tree)
  run run_helper regular "scripts/regular.sh"
  [ "$status" -eq 0 ]
  [ "$(index_tree)" = "$before" ]
}

@test "context success preserves shared index" {
  printf 'context\n' > "$REPO/context/current.md"
  before=$(index_tree)
  run run_helper context "context/current.md"
  [ "$status" -eq 0 ]
  [ "$(index_tree)" = "$before" ]
}

@test "regular commit failure logs branch rc reason and preserves shared index" {
  printf 'regular\n' > "$REPO/scripts/regular.sh"
  git -C "$REPO" config commit.gpgsign true
  git -C "$REPO" config gpg.program false
  before=$(index_tree)
  run run_helper regular "scripts/regular.sh"
  [ "$status" -ne 0 ]
  [ "$(index_tree)" = "$before" ]
  grep -Eq 'AUTO-COMMIT-FAIL: agent=kotaro branch=regular rc=[1-9][0-9]* reason=.' "$REPO/events.log"
}

@test "context commit failure logs branch rc reason and preserves shared index" {
  printf 'context\n' > "$REPO/context/current.md"
  git -C "$REPO" config commit.gpgsign true
  git -C "$REPO" config gpg.program false
  before=$(index_tree)
  run run_helper context "context/current.md"
  [ "$status" -ne 0 ]
  [ "$(index_tree)" = "$before" ]
  grep -Eq 'AUTO-COMMIT-FAIL: agent=kotaro branch=context rc=[1-9][0-9]* reason=.' "$REPO/events.log"
}

@test "same-content restage keeps shared tree identical" {
  git -C "$REPO" add shared.txt
  before=$(index_tree)
  run run_helper regular "shared.txt"
  [ "$status" -ne 0 ]
  [ "$(index_tree)" = "$before" ]
}

@test "partial add failure preserves shared tree" {
  printf 'regular\n' > "$REPO/scripts/regular.sh"
  before=$(index_tree)
  run run_helper regular $'scripts/regular.sh\nmissing.txt'
  [ "$status" -ne 0 ]
  [ "$(index_tree)" = "$before" ]
}

@test "hook cannot add paths because dedicated commit skips hooks" {
  mkdir -p "$REPO/.git/hooks"
  printf '#!/bin/sh\ngit add shared.txt\n' > "$REPO/.git/hooks/pre-commit"
  chmod +x "$REPO/.git/hooks/pre-commit"
  printf 'hook-stage\n' > "$REPO/shared.txt"
  printf 'regular\n' > "$REPO/scripts/regular.sh"
  before=$(index_tree)
  run run_helper regular "scripts/regular.sh"
  [ "$status" -eq 0 ]
  [ "$(index_tree)" = "$before" ]
  run git -C "$REPO" show --format= --name-only HEAD
  [[ "$output" = "scripts/regular.sh" ]]
}

@test "quoted path commits through dedicated index and preserves shared tree" {
  printf 'base\n' > "$REPO/scripts/quoted file.sh"
  git -C "$REPO" add "scripts/quoted file.sh"
  git -C "$REPO" commit -qm quoted-base
  printf 'changed\n' > "$REPO/scripts/quoted file.sh"
  before=$(index_tree)
  run run_helper regular "scripts/quoted file.sh"
  [ "$status" -eq 0 ]
  [ "$(index_tree)" = "$before" ]
}

@test "dedicated index initialization failure preserves shared tree" {
  mkdir -p "$REPO/fail-bin"
  cat > "$REPO/fail-bin/git" <<'EOF'
#!/bin/sh
if [ "$1" = "read-tree" ]; then
  echo "injected read-tree failure" >&2
  exit 73
fi
exec /usr/bin/git "$@"
EOF
  chmod +x "$REPO/fail-bin/git"
  printf 'regular\n' > "$REPO/scripts/regular.sh"
  before=$(index_tree)
  PATH="$REPO/fail-bin:$PATH" run run_helper regular "scripts/regular.sh"
  [ "$status" -ne 0 ]
  [ "$(index_tree)" = "$before" ]
  grep -Eq 'AUTO-COMMIT-FAIL: agent=kotaro branch=regular rc=73 reason=injected read-tree failure' "$REPO/events.log"
}
