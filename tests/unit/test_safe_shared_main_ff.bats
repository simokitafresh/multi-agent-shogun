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

@test "diverged histories with identical path content converge" {
  printf 'same-a\n' > "$FIX/a.txt"
  git -C "$FIX" add a.txt
  git -C "$FIX" commit -qm local-same-a
  printf 'same-a\n' > "$BATS_TEST_TMPDIR/next/a.txt"
  git -C "$BATS_TEST_TMPDIR/next" add a.txt
  git -C "$BATS_TEST_TMPDIR/next" commit -qm remote-same-a
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode=diverged"* ]]
  [ "$(cat "$FIX/a.txt")" = "same-a" ]
  git -C "$FIX" merge-base --is-ancestor "$target" HEAD
}

@test "diverged non-conflicting histories preserve unrelated dirty work" {
  printf 'local-b-commit\n' > "$FIX/b.txt"
  git -C "$FIX" add b.txt
  git -C "$FIX" commit -qm local-b
  printf 'dirty-local\n' > "$FIX/dirty.txt"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode=diverged"* ]]
  [ "$(cat "$FIX/dirty.txt")" = "dirty-local" ]
  [ "$(cat "$FIX/a.txt")" = "new-a" ]
  [ "$(cat "$FIX/b.txt")" = "local-b-commit" ]
}

@test "diverged conflicting histories block before HEAD moves" {
  printf 'local-conflict\n' > "$FIX/a.txt"
  git -C "$FIX" add a.txt
  git -C "$FIX" commit -qm local-conflict
  before="$(git -C "$FIX" rev-parse HEAD)"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" "$target"
  [ "$status" -eq 2 ]
  [[ "$output" == *"merge conflicts"* ]]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$before" ]
}

# test_necessity: a target-side ours-equivalent merge has a non-empty
# first-parent/second-parent tree diff but an identical merge/first-parent tree;
# safe convergence must block it before ref movement.
@test "target-side ours-equivalent tree regression blocks before ref update" {
  git -C "$FIX" worktree add -q -b side "$BATS_TEST_TMPDIR/side"
  printf 'side-b\n' > "$BATS_TEST_TMPDIR/side/b.txt"
  git -C "$BATS_TEST_TMPDIR/side" add b.txt
  git -C "$BATS_TEST_TMPDIR/side" commit -qm side-b
  git -C "$BATS_TEST_TMPDIR/next" merge -s ours --no-ff side -m "ours regression fixture" >/dev/null
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"
  before="$(git -C "$FIX" rev-parse HEAD)"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" "$target"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ours-equivalent merge"* ]]
  [[ "$output" == *"target_new_merges=1"* ]]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$before" ]
}

@test "concurrent convergence is serialized and both callers succeed" {
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"
  bash "$FIX/scripts/safe_shared_main_ff.sh" "$target" > "$BATS_TEST_TMPDIR/first.out" 2>&1 &
  first_pid=$!
  bash "$FIX/scripts/safe_shared_main_ff.sh" "$target" > "$BATS_TEST_TMPDIR/second.out" 2>&1 &
  second_pid=$!

  wait "$first_pid"
  wait "$second_pid"
  grep -q 'result=PASS' "$BATS_TEST_TMPDIR/first.out"
  grep -q 'result=PASS' "$BATS_TEST_TMPDIR/second.out"
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$target" ]
}

@test "unrelated untracked files are preserved without full-repository enumeration" {
  mkdir -p "$FIX/unrelated"
  for n in $(seq 1 200); do printf 'keep\n' > "$FIX/unrelated/$n.txt"; done
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" "$target"
  [ "$status" -eq 0 ]
  [ "$(find "$FIX/unrelated" -type f | wc -l)" -eq 200 ]
  [[ "$output" == *"dirty_paths=0"* ]]
}
