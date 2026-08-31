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

# test_necessity: an overlapping dirty shared worktree must publish the target
# from an isolated worktree while preserving shared HEAD, index, and dirt.
@test "AC1 fixed: overlapping dirty work uses isolated fallback and reaches remote" {
  fallback_origin_init
  fallback_install_hook 'exit 0'
  printf 'local-a\n' >> "$FIX/a.txt"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"
  before_head="$(git -C "$FIX" rev-parse HEAD)"
  before_index="$(git -C "$FIX" ls-files --stage | sha256sum | awk '{print $1}')"
  before_dirty="$(shared_dirty_fingerprint)"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" --repo "$FIX" "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SAFE_SHARED_MAIN_FF_FALLBACK"* ]]
  [[ "$output" == *"remote_contains_target=yes"* ]]
  [[ "$output" == *"shared_head_unchanged=yes"* ]]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$before_head" ]
  [ "$(git -C "$FIX" ls-files --stage | sha256sum | awk '{print $1}')" = "$before_index" ]
  [ "$(shared_dirty_fingerprint)" = "$before_dirty" ]
  [ "$(grep -c . "$BATS_TEST_TMPDIR/hook.log")" -eq 1 ]
  git --git-dir "$BATS_TEST_TMPDIR/origin.git" merge-base --is-ancestor "$target" refs/heads/main
}

# test_necessity: a remote ref race must rebuild the isolated merge from the
# refreshed remote tip and stop after the configured retry bound.
@test "AC2: remote race retries from latest origin main and converges" {
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
  [[ "$output" == *"retry=1/2"* ]]
  [[ "$output" == *"remote_contains_target=yes"* ]]
  [ "$(grep -c . "$BATS_TEST_TMPDIR/hook.log")" -eq 2 ]
  [[ "$(git --git-dir "$BATS_TEST_TMPDIR/origin.git" log --format=%s refs/heads/main)" == *"remote-race"* ]]
  git --git-dir "$BATS_TEST_TMPDIR/origin.git" merge-base --is-ancestor "$target" refs/heads/main
}

# test_necessity: repeated remote races must exhaust the configured bound and
# return BLOCK rather than retrying forever or claiming publication.
@test "AC2: repeated remote races exhaust finite retry bound" {
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
  [ "$status" -eq 2 ]
  [[ "$output" == *"retry=1/1"* ]]
  [[ "$output" == *"isolated fallback push failed"* ]]
  [ "$(grep -c . "$BATS_TEST_TMPDIR/hook.log")" -eq 2 ]
  ! git --git-dir "$BATS_TEST_TMPDIR/origin.git" merge-base --is-ancestor "$target" refs/heads/main
}

# test_necessity: a true three-way conflict in the isolated worktree must be
# fail-closed and must not mutate the shared checkout.
@test "AC2: true isolated merge conflict BLOCKs without shared mutation" {
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
  before_dirty="$(shared_dirty_fingerprint)"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" --repo "$FIX" "$target"
  [ "$status" -eq 2 ]
  [[ "$output" == *"isolated fallback merge conflict"* ]]
  [ "$(git -C "$FIX" rev-parse HEAD)" = "$before_head" ]
  [ "$(shared_dirty_fingerprint)" = "$before_dirty" ]
  hook_count="$(grep -c . "$BATS_TEST_TMPDIR/hook.log" 2>/dev/null || true)"
  [ "${hook_count:-0}" -eq 0 ]
  ! git --git-dir "$BATS_TEST_TMPDIR/origin.git" merge-base --is-ancestor "$target" refs/heads/main
}

# test_necessity: a normal pre-push hook failure is not mistaken for a remote
# race and cannot trigger a retry or a publication.
@test "AC2: pre-push hook failure BLOCKs without retry" {
  fallback_origin_init
  fallback_install_hook 'echo HOOK_FAIL >&2; exit 17'
  printf 'local-a\n' >> "$FIX/a.txt"
  target="$(git -C "$BATS_TEST_TMPDIR/next" rev-parse HEAD)"

  run bash "$FIX/scripts/safe_shared_main_ff.sh" --repo "$FIX" "$target"
  [ "$status" -eq 2 ]
  [[ "$output" == *"HOOK_FAIL"* ]]
  [[ "$output" == *"isolated fallback push failed"* ]]
  [ "$(grep -c . "$BATS_TEST_TMPDIR/hook.log")" -eq 1 ]
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
