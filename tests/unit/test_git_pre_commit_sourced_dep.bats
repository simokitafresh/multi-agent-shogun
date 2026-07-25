#!/usr/bin/env bats
# test_necessity: a commit that adds `source <repo path>` to a staged script must
# also track or stage that path, or fresh checkouts and CI abort at source time.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$ROOT/scripts/hooks/git-pre-commit.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/scripts/lib"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name test
  printf '# baseline\n' > "$REPO/README.md"
  git -C "$REPO" add README.md
  git -C "$REPO" commit -qm baseline
}

run_check() {
  REPO_ROOT="$REPO" STAGED_FILE="$1" HOOK="$HOOK" bash -c '
    eval "$(sed -n "/^check_staged_sourced_deps()/,/^}/p" "$HOOK")"
    staged_file_exists() { [ "$1" = "$STAGED_FILE" ]; }
    list_staged_files() { printf "%s\n" "$STAGED_FILE"; }
    cd "$REPO_ROOT"
    check_staged_sourced_deps
  '
}

@test "blocks a staged script sourcing an untracked, unstaged repo lib" {
  printf '#!/bin/bash\nsource "$DIR/scripts/lib/newdep.sh"\n' > "$REPO/scripts/caller.sh"
  printf '#!/bin/bash\n:\n' > "$REPO/scripts/lib/newdep.sh"
  git -C "$REPO" add scripts/caller.sh
  run run_check scripts/caller.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"scripts/lib/newdep.sh"* ]]
}

@test "permits the same source when the dependency is staged in this commit" {
  printf '#!/bin/bash\nsource "$DIR/scripts/lib/newdep.sh"\n' > "$REPO/scripts/caller.sh"
  printf '#!/bin/bash\n:\n' > "$REPO/scripts/lib/newdep.sh"
  git -C "$REPO" add scripts/caller.sh scripts/lib/newdep.sh
  run run_check scripts/caller.sh
  [ "$status" -eq 0 ]
}

@test "permits sourcing a dependency already tracked in HEAD" {
  printf '#!/bin/bash\n:\n' > "$REPO/scripts/lib/olddep.sh"
  git -C "$REPO" add scripts/lib/olddep.sh
  git -C "$REPO" commit -qm dep
  printf '#!/bin/bash\nsource "$DIR/scripts/lib/olddep.sh"\n' > "$REPO/scripts/caller.sh"
  git -C "$REPO" add scripts/caller.sh
  run run_check scripts/caller.sh
  [ "$status" -eq 0 ]
}

@test "does not false-positive on a source path absent from the working tree" {
  printf '#!/bin/bash\nsource "$DIR/scripts/lib/${name}.sh"\nsource "/etc/scripts/absent.sh"\n' \
    > "$REPO/scripts/caller.sh"
  git -C "$REPO" add scripts/caller.sh
  run run_check scripts/caller.sh
  [ "$status" -eq 0 ]
}
