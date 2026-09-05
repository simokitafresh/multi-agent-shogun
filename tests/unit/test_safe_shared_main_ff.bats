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

fallback_origin_init() {
  git init --bare -q "$BATS_TEST_TMPDIR/origin.git"
  git -C "$FIX" remote add origin "$BATS_TEST_TMPDIR/origin.git"
  git -C "$FIX" push -q -u origin main
  mkdir -p "$FIX/hooks"
  git -C "$FIX" config core.hooksPath "$FIX/hooks"
}

fallback_install_hook() {
  local body="${1:-success}"
  cat > "$FIX/hooks/pre-push" <<EOF
#!/usr/bin/env bash
echo invoked >> "$BATS_TEST_TMPDIR/hook.log"
$body
EOF
  chmod +x "$FIX/hooks/pre-push"
}

shared_dirty_fingerprint() {
  {
    git -C "$FIX" diff --no-ext-diff --binary
    git -C "$FIX" diff --cached --no-ext-diff --binary
    git -C "$FIX" status --porcelain=v1 --untracked-files=all
  } | sha256sum | awk '{print $1}'
}

# test_necessity: the old shared push boundary must expose the real overlap
# failure, preserve dirty work, and leave the remote untouched before the
# isolated fallback is exercised.
@test "AC1 baseline: three direct overlap pushes BLOCK with remote and dirty state unchanged" {
  fallback_origin_init
  fallback_install_hook 'echo BLOCK: fixture pre-push overlap >&2; exit 1'
  printf 'local-a\n' >> "$FIX/a.txt"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"
  before_remote="$(git --git-dir "$BATS_TEST_TMPDIR/origin.git" rev-parse refs/heads/main)"
  before_dirty="$(shared_dirty_fingerprint)"
  block_count=0
  remote_unreached_count=0
  dirty_preserved_count=0
  for _ in 1 2 3; do
    if git -C "$FIX" push origin "$target:refs/heads/main" >/dev/null 2>&1; then
      continue
    fi
    block_count=$((block_count + 1))
    [ "$(git --git-dir "$BATS_TEST_TMPDIR/origin.git" rev-parse refs/heads/main)" = "$before_remote" ] && remote_unreached_count=$((remote_unreached_count + 1))
    [ "$(shared_dirty_fingerprint)" = "$before_dirty" ] && dirty_preserved_count=$((dirty_preserved_count + 1))
  done
  [ "$block_count" -eq 3 ]
  [ "$remote_unreached_count" -eq 3 ]
  [ "$dirty_preserved_count" -eq 3 ]
  echo "AC1_BASELINE block_count=$block_count remote_unreached_count=$remote_unreached_count shared_dirty_preserved_count=$dirty_preserved_count"
}

# test_necessity: an overlapping dirty shared worktree must targetize the
# shared checkout while preserving the exact dirty worktree and index.
@test "AC1 fixed: overlapping dirty work is restored after non-merge sync" {
  fallback_origin_init
  fallback_install_hook 'exit 0'
  printf 'local-a\n' >> "$FIX/a.txt"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"
  before_head="$(git -C "$FIX" rev-parse HEAD)"
  before_index="$(git -C "$FIX" ls-files --stage -- b.txt | sha256sum | awk '{print $1}')"
  before_dirty="$(git -C "$FIX" hash-object --no-filters -- a.txt)"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" --repo "$FIX" "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SAFE_SHARED_MAIN_FF_SYNC"* ]]
  [[ "$output" == *"dirty_overlap_restored=yes"* ]]
  [[ "$output" == *"index_preserved=yes"* ]]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$target" ]
  [ "$(git -C "$FIX" ls-files --stage -- b.txt | sha256sum | awk '{print $1}')" = "$before_index" ]
  [ "$(git -C "$FIX" hash-object --no-filters -- a.txt)" = "$before_dirty" ]
  [ ! -e "$BATS_TEST_TMPDIR/hook.log" ] || [ "$(wc -l < "$BATS_TEST_TMPDIR/hook.log")" -eq 0 ]
}

# test_necessity: shared synchronization must not invoke a remote push hook or
# depend on the mutable remote while restoring an overlapping dirty path.
@test "AC2: dirty sync ignores remote push race and converges" {
  fallback_origin_init
  git clone -q -b main "$BATS_TEST_TMPDIR/origin.git" "$BATS_TEST_TMPDIR/race-remote"
  git -C "$BATS_TEST_TMPDIR/race-remote" config user.email test@example.com
  git -C "$BATS_TEST_TMPDIR/race-remote" config user.name test
fallback_install_hook "count=\$(wc -l < \"$BATS_TEST_TMPDIR/hook.log\")
if [ \"\$count\" -eq 1 ]; then
  printf 'remote-race\\n' > \"$BATS_TEST_TMPDIR/race-remote/race.txt\"
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C \"$BATS_TEST_TMPDIR/race-remote\" add race.txt
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C \"$BATS_TEST_TMPDIR/race-remote\" commit -qm remote-race
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C \"$BATS_TEST_TMPDIR/race-remote\" push -q origin main
fi
exit 0"
  printf 'local-a\n' >> "$FIX/a.txt"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" --repo "$FIX" "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SAFE_SHARED_MAIN_FF_SYNC"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/hook.log" ] || [ "$(wc -l < "$BATS_TEST_TMPDIR/hook.log")" -eq 0 ]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$target" ]
  ! git --git-dir "$BATS_TEST_TMPDIR/origin.git" merge-base --is-ancestor "$target" refs/heads/main
}

# test_necessity: retry configuration must not reintroduce a remote-push path
# into shared synchronization.
@test "AC2: retry configuration does not change non-merge sync" {
  fallback_origin_init
  git clone -q -b main "$BATS_TEST_TMPDIR/origin.git" "$BATS_TEST_TMPDIR/bound-remote"
  git -C "$BATS_TEST_TMPDIR/bound-remote" config user.email test@example.com
  git -C "$BATS_TEST_TMPDIR/bound-remote" config user.name test
  fallback_install_hook "count=\$(wc -l < \"$BATS_TEST_TMPDIR/hook.log\")
printf 'remote-race-\$count\\n' > \"$BATS_TEST_TMPDIR/bound-remote/race-\$count.txt\"
env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C \"$BATS_TEST_TMPDIR/bound-remote\" add race-\$count.txt
env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C \"$BATS_TEST_TMPDIR/bound-remote\" commit -qm remote-race-\$count
env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C \"$BATS_TEST_TMPDIR/bound-remote\" push -q origin main
exit 0"
  printf 'local-a\n' >> "$FIX/a.txt"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"

  run env SAFE_SHARED_MAIN_FF_MAX_RETRIES=1 \
    bash "$FIX/scripts/safe_shared_main_ff.sh" --repo "$FIX" "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SAFE_SHARED_MAIN_FF_SYNC"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/hook.log" ] || [ "$(wc -l < "$BATS_TEST_TMPDIR/hook.log")" -eq 0 ]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$target" ]
  ! git --git-dir "$BATS_TEST_TMPDIR/origin.git" merge-base --is-ancestor "$target" refs/heads/main
}

# test_necessity: a remote conflict must not cause an isolated merge or push;
# dirty overlap is still restored by the shared non-merge transaction.
@test "AC2: remote conflict does not invoke isolated merge" {
  fallback_origin_init
  git clone -q -b main "$BATS_TEST_TMPDIR/origin.git" "$BATS_TEST_TMPDIR/conflict-remote"
  git -C "$BATS_TEST_TMPDIR/conflict-remote" config user.email test@example.com
  git -C "$BATS_TEST_TMPDIR/conflict-remote" config user.name test
  printf 'remote-a\n' > "$BATS_TEST_TMPDIR/conflict-remote/a.txt"
  git -C "$BATS_TEST_TMPDIR/conflict-remote" add a.txt
  git -C "$BATS_TEST_TMPDIR/conflict-remote" commit -qm remote-conflict
  git -C "$BATS_TEST_TMPDIR/conflict-remote" push -q origin main
  fallback_install_hook 'exit 0'
  printf 'local-a\n' >> "$FIX/a.txt"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"
  before_head="$(git -C "$FIX" rev-parse HEAD)"
  before_dirty="$(git -C "$FIX" hash-object --no-filters -- a.txt)"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" --repo "$FIX" "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SAFE_SHARED_MAIN_FF_SYNC"* ]]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$target" ]
  [ "$(git -C "$FIX" hash-object --no-filters -- a.txt)" = "$before_dirty" ]
  hook_count="$(grep -c . "$BATS_TEST_TMPDIR/hook.log" 2>/dev/null || true)"
  [ "${hook_count:-0}" -eq 0 ]
  ! git --git-dir "$BATS_TEST_TMPDIR/origin.git" merge-base --is-ancestor "$target" refs/heads/main
}

# test_necessity: a normal pre-push hook failure cannot affect the local
# non-merge synchronization path.
@test "AC2: pre-push hook is not invoked by non-merge sync" {
  fallback_origin_init
  fallback_install_hook 'echo HOOK_FAIL >&2; exit 17'
  printf 'local-a\n' >> "$FIX/a.txt"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" --repo "$FIX" "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SAFE_SHARED_MAIN_FF_SYNC"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/hook.log" ] || [ "$(wc -l < "$BATS_TEST_TMPDIR/hook.log")" -eq 0 ]
  ! git --git-dir "$BATS_TEST_TMPDIR/origin.git" merge-base --is-ancestor "$target" refs/heads/main
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

@test "overlap is restored while HEAD moves atomically" {
  printf 'local-a\n' >> "$FIX/a.txt"
  before="$(git -C "$FIX" rev-parse HEAD)"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"
  run bash "$FIX/scripts/safe_shared_main_ff.sh" "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dirty_overlap_restored=yes"* ]]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$target" ]
}

# test_necessity: staged overlap cannot be overwritten by the targetization
# transaction and must fail before the shared ref moves.
@test "staged overlap fails closed before ref movement" {
  printf 'staged-local\n' >> "$FIX/a.txt"
  git -C "$FIX" add a.txt
  before_head="$(git -C "$FIX" rev-parse HEAD)"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" --repo "$FIX" "$target"
  [ "$status" -eq 2 ]
  [[ "$output" == *"staged changes overlap"* ]]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$before_head" ]
  ! git -C "$FIX" diff --cached --quiet HEAD -- a.txt
}

# test_necessity: an untracked path at a target-created path must not be
# overwritten by read-tree.
@test "untracked target path fails closed before ref movement" {
  printf 'target-c\n' > "$BATS_TEST_TMPDIR/next/c.txt"
  git -C "$BATS_TEST_TMPDIR/next" add c.txt
  git -C "$BATS_TEST_TMPDIR/next" commit -qm next-c
  printf 'untracked-c\n' > "$FIX/c.txt"
  before_head="$(git -C "$FIX" rev-parse HEAD)"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" --repo "$FIX" "$target"
  [ "$status" -eq 2 ]
  [[ "$output" == *"untracked path would be overwritten"* ]]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$before_head" ]
  [ "$(cat "$FIX/c.txt")" = "untracked-c" ]
}

# test_necessity: multiple regular overlap files, including an executable
# mode, must retain both exact hashes and modes after synchronization.
@test "multiple overlap blobs and modes are restored exactly" {
  printf 'target-b\n' > "$BATS_TEST_TMPDIR/next/b.txt"
  git -C "$BATS_TEST_TMPDIR/next" add b.txt
  git -C "$BATS_TEST_TMPDIR/next" commit -qm next-b
  printf 'local-a\n' >> "$FIX/a.txt"
  printf 'local-b\n' >> "$FIX/b.txt"
  chmod 755 "$FIX/a.txt"
  before_a="$(git -C "$FIX" hash-object --no-filters -- a.txt)"
  before_b="$(git -C "$FIX" hash-object --no-filters -- b.txt)"
  before_mode="$(stat -c '%a' "$FIX/a.txt")"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" --repo "$FIX" "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dirty_overlap_restored=yes"* ]]
  [ "$(git -C "$FIX" hash-object --no-filters -- a.txt)" = "$before_a" ]
  [ "$(git -C "$FIX" hash-object --no-filters -- b.txt)" = "$before_b" ]
  [ "$(stat -c '%a' "$FIX/a.txt")" = "$before_mode" ]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$target" ]
}

# test_necessity: a symlink overlap is not eligible for blind copy/restore.
@test "symlink overlap fails closed" {
  rm "$FIX/a.txt"
  ln -s b.txt "$FIX/a.txt"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"
  before="$(git -C "$FIX" rev-parse HEAD)"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" --repo "$FIX" "$target"
  [ "$status" -eq 2 ]
  [[ "$output" == *"must be a regular non-symlink file"* ]]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$before" ]
}

# test_necessity: c2a publication must immediately invoke the same shared-root
# non-merge reconciliation before the next validator cycle observes stale HEAD.
@test "c2a publication wires immediate shared sync" {
  c2a="$BATS_TEST_DIRNAME/../../scripts/publisher_c2a_merge.sh"
  run rg -n 'safe_shared_main_ff\.sh.*--repo|c2a_target=' "$c2a"
  [ "$status" -eq 0 ]
  [[ "$output" == *"c2a_target="* ]]
  [[ "$output" == *"safe_shared_main_ff.sh"* ]]
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

# test_necessity: an origin-side reviewed replacement may retain a local
# commit's effect while adding later safety changes to the same file.  Exact
# blob equality would deadlock that legitimate superset forever; the explicit
# source marker must advance the verified local prefix without weakening the
# next unaccounted commit.
@test "reviewed equivalent-source marker permits target superset convergence" {
  printf 'local-feature\n' >> "$FIX/a.txt"
  git -C "$FIX" add a.txt
  git -C "$FIX" commit -qm local-feature
  local_source="$(git -C "$FIX" rev-parse HEAD)"

  printf 'local-feature\ntarget-hardening\n' > "$BATS_TEST_TMPDIR/next/a.txt"
  git -C "$BATS_TEST_TMPDIR/next" add a.txt
  git -C "$BATS_TEST_TMPDIR/next" commit -qm "canonical replacement

Safe-Shared-Main-Equivalent-Source: $local_source"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"accounted=1"* ]]
  [[ "$output" == *"effect_paths=0"* ]]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$target" ]
  [ "$(cat "$FIX/a.txt")" = $'local-feature\ntarget-hardening' ]
}

# test_necessity: a marker cannot skip an unknown object or jump over an
# unaccounted local commit; otherwise arbitrary target text could discard work.
@test "invalid or noncontiguous equivalent-source marker remains fail-closed" {
  printf 'first-local\n' > "$FIX/b.txt"
  git -C "$FIX" add b.txt
  git -C "$FIX" commit -qm first-local
  first_source="$(git -C "$FIX" rev-parse HEAD)"
  printf 'second-local\n' > "$FIX/a.txt"
  git -C "$FIX" add a.txt
  git -C "$FIX" commit -qm second-local
  second_source="$(git -C "$FIX" rev-parse HEAD)"
  before="$(git -C "$FIX" rev-parse HEAD)"

  git -C "$BATS_TEST_TMPDIR/next" commit --allow-empty -qm "invalid markers

Safe-Shared-Main-Equivalent-Source: 0000000000000000000000000000000000000000
Safe-Shared-Main-Equivalent-Source: $second_source"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" "$target"
  [ "$status" -eq 2 ]
  [[ "$output" == *"effect_base="* ]]
  [[ "$output" == *"local-only tree effect is absent from target"* ]]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$before" ]
  [ -n "$first_source" ]
}

@test "diverged local-only effect absent from target blocks before ref move" {
  printf 'local-b-commit\n' > "$FIX/b.txt"
  git -C "$FIX" add b.txt
  git -C "$FIX" commit -qm local-b
  printf 'dirty-local\n' > "$FIX/dirty.txt"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" "$target"
  [ "$status" -eq 2 ]
  [[ "$output" == *"local-only tree effect is absent from target"* ]]
  [ "$(git -C "$FIX" rev-parse HEAD)" != "$target" ]
  [ "$(cat "$FIX/dirty.txt")" = "dirty-local" ]
  [ "$(cat "$FIX/a.txt")" = "old-a" ]
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
  [[ "$output" == *"local-only tree effect is absent from target"* ]]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$before" ]
}

# test_necessity: a target-side ours-equivalent merge has a non-empty
# first-parent/second-parent tree diff but an identical merge/first-parent tree;
# safe convergence must block it before ref movement.
@test "target-side ours-equivalent tree regression blocks before ref update" {
  fallback_origin_init
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

# test_necessity: the live push-lane candidate had first-parent-only changes;
# its tree already preserves every second-parent change relative to the merge
# base and must not be classified as an ancestry content-loss regression.
@test "live candidate with first-parent-only changes passes merge guard" {
  local project_root repo base_sha side_sha main_sha merge_sha main_tree candidate_tree
  project_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # Self-contained reconstruction of the live push-lane scenario: the target
  # contains an ours-equivalent merge (tree == first parent) whose candidate
  # tree still preserves every second-parent change relative to the merge
  # base. No live-repository SHAs: a fresh CI clone must reproduce this.
  repo="$BATS_TEST_TMPDIR/fp-candidate"
  git init -q -b main "$repo"
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  printf 'a0\n' > "$repo/a.txt"; printf 'b0\n' > "$repo/b.txt"
  git -C "$repo" add a.txt b.txt
  git -C "$repo" commit -qm base
  base_sha="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" checkout -qb side
  printf 'b1\n' > "$repo/b.txt"
  git -C "$repo" commit -aqm side-change
  side_sha="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" checkout -q main
  printf 'a1\n' > "$repo/a.txt"
  git -C "$repo" commit -aqm first-parent-change
  main_sha="$(git -C "$repo" rev-parse HEAD)"
  main_tree="$(git -C "$repo" rev-parse 'HEAD^{tree}')"
  merge_sha="$(git -C "$repo" commit-tree "$main_tree" -p "$main_sha" -p "$side_sha" -m ours-equivalent)"
  git -C "$repo" update-ref refs/heads/main "$merge_sha"
  candidate_tree="$(git -C "$repo" merge-tree --write-tree "$main_sha" "$side_sha")"

  run bash "$project_root/scripts/safe_shared_main_ff.sh" --verify-merge-tree \
    "$repo" "$base_sha" "$merge_sha" "$candidate_tree"
  [ "$status" -eq 0 ]
  [[ "$output" == *"target_new_merges=1"* ]]
  [[ "$output" == *"ours_equivalent=0"* ]]
  [[ "$output" == *"result=PASS"* ]]
}

# test_necessity: the real eaabc7d93 content-loss merge must be diagnosed at
# the incident remote boundary (392fbbf59), even when the tracking ref has not
# crossed the publication boundary; a normal linear update remains allowed.
@test "AC2: real eaabc ancestry boundary reports unique paths and normal merge passes" {
  local project_root source_git_common_dir incident_sha remote_sha incident_tree path_line path_count unique_count
  local normal_parent normal_target normal_tree
  project_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  incident_sha="eaabc7d9323bba3de2cb23635cf2d444cc91cc6c"
  remote_sha="392fbbf5957e65c300caf48eaf5bed4298c9599c"
  source_git_common_dir="$(git -C "$project_root" rev-parse --path-format=absolute --git-common-dir)"
  printf '%s/objects\n' "$source_git_common_dir" > "$FIX/.git/objects/info/alternates"
  git -C "$FIX" update-ref refs/remotes/origin/main "$remote_sha"
  incident_tree="$(git -C "$FIX" rev-parse "$incident_sha^{tree}")"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" --verify-merge-tree \
    "$FIX" "$remote_sha" "$incident_sha" "$incident_tree"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ours-equivalent merge"* ]]
  [[ "$output" == *"changed_paths=7"* ]]
  path_count="$(printf '%s\n' "$output" | awk '/^ANCESTRY-MERGE-REGRESSION paths=/{n++; split($0, parts, "paths="); count=split(parts[2], paths, ",")} END {print count + 0}')"
  unique_count="$(printf '%s\n' "$output" | awk '/^ANCESTRY-MERGE-REGRESSION paths=/{split($0, parts, "paths="); split(parts[2], paths, ","); for (i in paths) seen[paths[i]]=1} END {for (path in seen) n++; print n + 0}')"
  [ "$path_count" -ge 1 ]
  [ "$path_count" -eq "$unique_count" ]
  [ "$(printf '%s\n' "$output" | awk '/^ANCESTRY-MERGE-REGRESSION paths=/{n++} END {print n + 0}')" -eq 1 ]
  path_line="$(printf '%s\n' "$output" | awk '/^ANCESTRY-MERGE-REGRESSION paths=/{print}')"
  [ -n "$path_line" ]

  normal_parent="$(git -C "$FIX" rev-parse HEAD)"
  printf 'normal\n' > "$FIX/normal.txt"
  git -C "$FIX" add normal.txt
  git -C "$FIX" commit -qm "normal linear fixture"
  normal_target="$(git -C "$FIX" rev-parse HEAD)"
  normal_tree="$(git -C "$FIX" rev-parse "$normal_target^{tree}")"
  run bash "$FIX/scripts/safe_shared_main_ff.sh" --verify-merge-tree \
    "$FIX" "$normal_parent" "$normal_target" "$normal_tree"
  [ "$status" -eq 0 ]
  [[ "$output" == *"target_new_merges=0"* ]]
  [[ "$output" == *"result=PASS"* ]]
}

# test_necessity: an ours-equivalent merge already published in origin/main is
# historical state, not a new unsafe merge introduced by this convergence.
@test "published ours-equivalent merge is exempt from the guard" {
  fallback_origin_init
  git -C "$FIX" worktree add -q -b side "$BATS_TEST_TMPDIR/published-side"
  printf 'published-side-b\n' > "$BATS_TEST_TMPDIR/published-side/b.txt"
  git -C "$BATS_TEST_TMPDIR/published-side" add b.txt
  git -C "$BATS_TEST_TMPDIR/published-side" commit -qm published-side-b
  published_side="$(git -C "$BATS_TEST_TMPDIR/published-side" rev-parse HEAD)"
  git -C "$BATS_TEST_TMPDIR/next" merge -s ours --no-ff "$published_side" -m "published ours fixture" >/dev/null
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"
  git -C "$FIX" push -q origin "$target:refs/heads/main"
  git -C "$FIX" fetch -q origin main

  run bash "$FIX/scripts/safe_shared_main_ff.sh" "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"target_new_merges=1"* ]]
  [[ "$output" == *"published_merges=1"* ]]
  [[ "$output" == *"ours_equivalent=0"* ]]
  [[ "$output" == *"result=PASS"* ]]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$target" ]
}

# test_necessity: a published ours-equivalent merge can still regress a
# newer second-parent worktree when a later ancestry merge adopts its first
# parent tree; the pre-push check must report the exact affected paths.
@test "published ancestry merge regression blocks with path evidence" {
  fallback_origin_init
  git -C "$FIX" worktree add -q -b side "$BATS_TEST_TMPDIR/ancestry-side"
  printf 'side-b\n' > "$BATS_TEST_TMPDIR/ancestry-side/b.txt"
  git -C "$BATS_TEST_TMPDIR/ancestry-side" add b.txt
  git -C "$BATS_TEST_TMPDIR/ancestry-side" commit -qm ancestry-side
  second_parent="$(git -C "$BATS_TEST_TMPDIR/ancestry-side" rev-parse HEAD)"
  git -C "$BATS_TEST_TMPDIR/next" merge -s ours --no-ff "$second_parent" -m "published ancestry fixture" >/dev/null
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"
  first_parent="$(git -C "$BATS_TEST_TMPDIR/next" show -s --format='%P' "$target" | awk '{print $1}')"
  git -C "$FIX" push -q origin "$target:refs/heads/main"
  git -C "$FIX" fetch -q origin main
  prospective_tree="$(git -C "$FIX" rev-parse "$first_parent^{tree}")"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" --verify-merge-tree \
    "$FIX" "$second_parent" "$target" "$prospective_tree"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ANCESTRY-MERGE-REGRESSION paths=a.txt"* ]]
}

# test_necessity: a normal fast-forward without merge commits remains a PASS
# while the published-history exemption is active.
@test "normal fast-forward remains allowed after merge guard" {
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"
  run bash "$FIX/scripts/safe_shared_main_ff.sh" "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"target_new_merges=0"* ]]
  [[ "$output" == *"ours_equivalent=0"* ]]
  [[ "$output" == *"result=PASS"* ]]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$target" ]
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

# test_necessity: a runtime writer may update an unrelated tracked-dirty path
# after targetization.  Convergence must neither roll back HEAD nor restore an
# older snapshot over that newer value.
@test "concurrent non-target dirty writer is preserved instead of rolled back" {
  local real_git wrapper target
  real_git="$(command -v git)"
  mkdir -p "$BATS_TEST_TMPDIR/git-wrapper"
  wrapper="$BATS_TEST_TMPDIR/git-wrapper/git"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'real_git=%q\n' "$real_git"
    printf 'repo=%q\n' "$FIX"
    printf '"$real_git" "$@"\n'
    printf 'rc=$?\n'
    printf 'if [[ "$*" == *"read-tree --reset"* ]]; then printf "writer-update\\n" > "$repo/dirty.txt"; fi\n'
    printf 'exit "$rc"\n'
  } > "$wrapper"
  chmod +x "$wrapper"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"

  run env PATH="$BATS_TEST_TMPDIR/git-wrapper:$PATH" \
    bash "$FIX/scripts/safe_shared_main_ff.sh" "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=PASS"* ]]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$target" ]
  [ "$(cat "$FIX/dirty.txt")" = "writer-update" ]
}

# test_necessity: the ancestry-WAIT recovery lane may publish only an
# exact-descendant local main with an exact GREEN remote-tip proof, while the
# shared worktree remains byte-for-byte unchanged.
@test "auto-push publishes GREEN ahead main from an isolated worktree" {
  fallback_origin_init
  fallback_install_hook 'exit 0'
  printf 'ahead\n' >> "$FIX/b.txt"
  git -C "$FIX" add b.txt
  git -C "$FIX" commit -qm "cmd_auto_push fixture"
  before_head="$(git -C "$FIX" rev-parse HEAD)"
  before_dirty="$(shared_dirty_fingerprint)"

  run env SAFE_SHARED_MAIN_FF_AUTO_PUSH_THRESHOLD=1 \
    bash "$FIX/scripts/safe_shared_main_ff.sh" --auto-push-if-ready "$FIX" GREEN
  [ "$status" -eq 0 ]
  [[ "$output" == *"push=1"* ]]
  [[ "$output" == *"shared_head_unchanged=yes"* ]]
  [[ "$output" == *"shared_index_unchanged=yes"* ]]
  [[ "$output" == *"shared_dirty_unchanged=yes"* ]]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$before_head" ]
  [ "$(shared_dirty_fingerprint)" = "$before_dirty" ]
  [ "$(git --git-dir "$BATS_TEST_TMPDIR/origin.git" rev-parse refs/heads/main)" = "$before_head" ]
  [ "$(grep -c . "$BATS_TEST_TMPDIR/hook.log")" -eq 1 ]
}

# test_necessity: CI is post-publication telemetry, not a circular admission
# condition; each supported state must publish one eligible descendant.
@test "auto-push publishes once for GREEN UNKNOWN and RED telemetry" {
  fallback_origin_init
  fallback_install_hook 'exit 0'
  for ci_state in GREEN UNKNOWN RED; do
    printf '%s\n' "$ci_state" >> "$FIX/b.txt"
    git -C "$FIX" add b.txt
    git -C "$FIX" commit -qm "cmd_auto_push $ci_state fixture"
    before_head="$(git -C "$FIX" rev-parse HEAD)"
    before_dirty="$(shared_dirty_fingerprint)"

    run bash "$FIX/scripts/safe_shared_main_ff.sh" --auto-push-if-ready "$FIX" "$ci_state"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ci=$ci_state"*"push=1"*"result=PASS"* ]]
    [ "$(git -C "$FIX" rev-parse HEAD)" = "$before_head" ]
    [ "$(shared_dirty_fingerprint)" = "$before_dirty" ]
  done
  [ "$(grep -c . "$BATS_TEST_TMPDIR/hook.log")" -eq 3 ]
}

# test_necessity: a remote move must be classified as behind/diverged and
# never be force-repaired by the auto-push path.
@test "auto-push skips behind or diverged local main" {
  fallback_origin_init
  fallback_install_hook 'exit 0'
  git clone -q -b main "$BATS_TEST_TMPDIR/origin.git" "$BATS_TEST_TMPDIR/remote"
  git -C "$BATS_TEST_TMPDIR/remote" config user.email test@example.com
  git -C "$BATS_TEST_TMPDIR/remote" config user.name test
  printf 'remote\n' > "$BATS_TEST_TMPDIR/remote/remote.txt"
  git -C "$BATS_TEST_TMPDIR/remote" add remote.txt
  git -C "$BATS_TEST_TMPDIR/remote" commit -qm remote
  git -C "$BATS_TEST_TMPDIR/remote" push -q origin main
  printf 'local\n' >> "$FIX/b.txt"
  git -C "$FIX" add b.txt
  git -C "$FIX" commit -qm local
  before_remote="$(git --git-dir "$BATS_TEST_TMPDIR/origin.git" rev-parse refs/heads/main)"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" --auto-push-if-ready "$FIX" GREEN
  [ "$status" -eq 0 ]
  [[ "$output" == *"reason=behind_or_diverged"* ]]
  [[ "$output" == *"push=0"* ]]
  [ "$(git --git-dir "$BATS_TEST_TMPDIR/origin.git" rev-parse refs/heads/main)" = "$before_remote" ]
  [ ! -f "$BATS_TEST_TMPDIR/hook.log" ]
}

# test_necessity: an ours-equivalent merge whose first-parent tree already
# contains every line the second parent added (ID-merge superset, e.g. the
# insights ledger) loses nothing and must pass; blob inequality alone is not
# content loss (2026-09-02 pre-push false BLOCK on merge 60d87b68d).
@test "ours-equivalent merge with second-parent lines preserved as superset passes" {
  local project_root repo base_sha side_sha main_sha merge_sha main_tree
  project_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  repo="$BATS_TEST_TMPDIR/superset"
  git init -q -b main "$repo"
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  printf -- '- id: A\n' > "$repo/ledger.yaml"
  git -C "$repo" add ledger.yaml; git -C "$repo" commit -qm base
  base_sha="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" checkout -qb side
  printf -- '- id: A\n- id: B\n' > "$repo/ledger.yaml"
  git -C "$repo" commit -aqm side-adds-B
  side_sha="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" checkout -q main
  printf -- '- id: A\n- id: B\n- id: C\n' > "$repo/ledger.yaml"
  git -C "$repo" commit -aqm main-adds-B-and-C
  main_sha="$(git -C "$repo" rev-parse HEAD)"
  main_tree="$(git -C "$repo" rev-parse 'HEAD^{tree}')"
  merge_sha="$(git -C "$repo" commit-tree "$main_tree" -p "$main_sha" -p "$side_sha" -m superset-merge)"
  git -C "$repo" update-ref refs/heads/main "$merge_sha"

  run bash "$project_root/scripts/safe_shared_main_ff.sh" --verify-merge-tree \
    "$repo" "$base_sha" "$merge_sha" "$main_tree"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ours_equivalent=0"* ]]
  [[ "$output" == *"result=PASS"* ]]
}

# test_necessity: the superset relaxation must not hide real loss; when the
# first-parent tree lacks a line the second parent added, the merge still blocks.
@test "ours-equivalent merge that drops a second-parent line still blocks" {
  local project_root repo base_sha side_sha main_sha merge_sha main_tree
  project_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  repo="$BATS_TEST_TMPDIR/dropped"
  git init -q -b main "$repo"
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  printf -- '- id: A\n' > "$repo/ledger.yaml"
  git -C "$repo" add ledger.yaml; git -C "$repo" commit -qm base
  base_sha="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" checkout -qb side
  printf -- '- id: A\n- id: B\n' > "$repo/ledger.yaml"
  git -C "$repo" commit -aqm side-adds-B
  side_sha="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" checkout -q main
  printf -- '- id: A\n- id: C\n' > "$repo/ledger.yaml"
  git -C "$repo" commit -aqm main-adds-C-only
  main_sha="$(git -C "$repo" rev-parse HEAD)"
  main_tree="$(git -C "$repo" rev-parse 'HEAD^{tree}')"
  merge_sha="$(git -C "$repo" commit-tree "$main_tree" -p "$main_sha" -p "$side_sha" -m dropped-merge)"
  git -C "$repo" update-ref refs/heads/main "$merge_sha"

  run bash "$project_root/scripts/safe_shared_main_ff.sh" --verify-merge-tree \
    "$repo" "$base_sha" "$merge_sha" "$main_tree"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ours-equivalent merge"* ]]
  [[ "$output" == *"ANCESTRY-MERGE-REGRESSION paths=ledger.yaml"* ]]
}

# test_necessity: a path that exists only on the first-parent side (absent in
# both the merge base and the second parent) is local-only content, not a
# second-parent regression; `git rev-parse <tree>:<path>` echoes the argument
# for a missing path, so absence must be resolved with --verify -q or two
# distinct echo strings compare unequal and fabricate a regression
# (2026-09-02 16:38 push-lane false BLOCK on SHA256SUMS / gunshi_review_log).
@test "ours-equivalent merge with first-parent-only new file passes merge guard" {
  local project_root repo base_sha side_sha main_sha merge_sha main_tree
  project_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  repo="$BATS_TEST_TMPDIR/localonly"
  git init -q -b main "$repo"
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  printf -- '- id: A\n' > "$repo/ledger.yaml"
  git -C "$repo" add ledger.yaml; git -C "$repo" commit -qm base
  base_sha="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" checkout -qb side
  printf -- '- id: A\n- id: B\n' > "$repo/ledger.yaml"
  git -C "$repo" commit -aqm side-adds-B
  side_sha="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" checkout -q main
  printf -- '- id: A\n- id: B\n' > "$repo/ledger.yaml"
  printf 'local only\n' > "$repo/newfile.txt"
  git -C "$repo" add newfile.txt
  git -C "$repo" commit -aqm main-adds-B-and-newfile
  main_sha="$(git -C "$repo" rev-parse HEAD)"
  main_tree="$(git -C "$repo" rev-parse 'HEAD^{tree}')"
  merge_sha="$(git -C "$repo" commit-tree "$main_tree" -p "$main_sha" -p "$side_sha" -m local-only-merge)"
  git -C "$repo" update-ref refs/heads/main "$merge_sha"

  run bash "$project_root/scripts/safe_shared_main_ff.sh" --verify-merge-tree \
    "$repo" "$base_sha" "$merge_sha" "$main_tree"
  [ "$status" -eq 0 ]
  [[ "$output" == *"result=PASS"* ]]
}
