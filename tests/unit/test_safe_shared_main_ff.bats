#!/usr/bin/env bats
# test_necessity: a shared-main fast-forward must update ref, shared index, and
# changed worktree blobs as one verified boundary while preserving unrelated
# local work; overlapping local work must fail before HEAD moves.

setup() {
  export FIX="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$FIX/scripts"
  cp "$BATS_TEST_DIRNAME/../../scripts/safe_shared_main_ff.sh" "$FIX/scripts/"
  git -C "$FIX" init -q -b main
  git -C "$FIX" config user.email test@example.com
  git -C "$FIX" config user.name test
  printf 'old-a\n' > "$FIX/a.txt"
  printf 'old-b\n' > "$FIX/b.txt"
  git -C "$FIX" add a.txt b.txt scripts/safe_shared_main_ff.sh
  git -C "$FIX" commit -qm base
  git -C "$FIX" worktree add -q -b next "$BATS_TEST_TMPDIR/next"
  printf 'new-a\n' > "$BATS_TEST_TMPDIR/next/a.txt"
  git -C "$BATS_TEST_TMPDIR/next" add a.txt
  git -C "$BATS_TEST_TMPDIR/next" commit -qm next-a
}

@test "fast-forward converges changed path and preserves unrelated dirty path" {
  printf 'local-b\n' >> "$FIX/b.txt"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"
  run bash "$FIX/scripts/safe_shared_main_ff.sh" "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=PASS"* ]]
  [ "$(cat "$FIX/a.txt")" = "new-a" ]
  grep -q '^local-b$' "$FIX/b.txt"
  git -C "$FIX" diff --quiet HEAD -- a.txt
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$target" ]
}

@test "overlap blocks before HEAD moves" {
  printf 'local-a\n' >> "$FIX/a.txt"
  before="$(git -C "$FIX" rev-parse HEAD)"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"
  run bash "$FIX/scripts/safe_shared_main_ff.sh" "$target"
  [ "$status" -eq 2 ]
  [[ "$output" == *"overlap"* ]]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$before" ]
}

@test "explicit repo converges an external shared main with the same checks" {
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"
  run bash "$FIX/scripts/safe_shared_main_ff.sh" --repo "$FIX" "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=PASS"* ]]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$target" ]
  git -C "$FIX" diff --quiet HEAD -- a.txt
}
