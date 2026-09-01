#!/usr/bin/env bats
# test_necessity: when origin/main holds commits that local HEAD lacks (auto-push
# helper publishes integrate commits), the push lane must integrate origin/main
# by a merge (allowed operation) instead of blocking forever; a conflicting
# merge must abort, while a dirty-overlap merge must succeed in isolation and
# preserve the root worktree; a plain "behind" HEAD must fast-forward.
# regression_justification: 2026-09-01 12:10-12:33 and 12:44-13:19 the lane
# logged BLOCK reason=remote_tip_not_ancestor on every cycle until Karo made
# "runtime: integrate …" merges by hand (23 min + 40 min of no push).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  MON="$ROOT/scripts/ninja_monitor.sh"
  eval "$(sed -n '/^push_lane_integrate_remote()/,/^}/p' "$MON")"
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  LOCAL="$BATS_TEST_TMPDIR/local"
  OTHER="$BATS_TEST_TMPDIR/other"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$LOCAL" 2>/dev/null
  git -C "$LOCAL" config user.email t@example.com; git -C "$LOCAL" config user.name t
  git -C "$LOCAL" checkout -q -b main
  printf 'base\n' > "$LOCAL/a.txt"; git -C "$LOCAL" add a.txt; git -C "$LOCAL" commit -qm base
  git -C "$LOCAL" push -q origin main
  git clone -q "$ORIGIN" "$OTHER" 2>/dev/null
  git -C "$OTHER" config user.email o@example.com; git -C "$OTHER" config user.name o
  git -C "$OTHER" checkout -q main 2>/dev/null || git -C "$OTHER" checkout -q -b main origin/main
}

@test "diverged: origin ahead on another file → auto merge makes remote an ancestor of HEAD" {
  printf 'remote\n' > "$OTHER/b.txt"; git -C "$OTHER" add b.txt; git -C "$OTHER" commit -qm remote; git -C "$OTHER" push -q origin main
  printf 'local\n' > "$LOCAL/c.txt"; git -C "$LOCAL" add c.txt; git -C "$LOCAL" commit -qm local
  git -C "$LOCAL" fetch -q origin
  run bash -c "$(declare -f push_lane_integrate_remote); push_lane_integrate_remote '$LOCAL' origin/main \$(git -C '$LOCAL' rev-parse origin/main)"
  [ "$status" -eq 0 ]
  git -C "$LOCAL" merge-base --is-ancestor origin/main HEAD
  [ "$(git -C "$LOCAL" log -1 --format=%s)" != "local" ]
  [[ "$(git -C "$LOCAL" log -1 --format=%s)" == *"integrate origin/main"* ]]
}

@test "behind only: HEAD is ancestor of origin → fast-forward" {
  printf 'remote\n' > "$OTHER/b.txt"; git -C "$OTHER" add b.txt; git -C "$OTHER" commit -qm remote; git -C "$OTHER" push -q origin main
  git -C "$LOCAL" fetch -q origin
  run bash -c "$(declare -f push_lane_integrate_remote); push_lane_integrate_remote '$LOCAL' origin/main \$(git -C '$LOCAL' rev-parse origin/main)"
  [ "$status" -eq 0 ]
  [ "$(git -C "$LOCAL" rev-parse HEAD)" = "$(git -C "$LOCAL" rev-parse origin/main)" ]
}

@test "conflict on the same file → abort, HEAD unchanged, no merge state left" {
  printf 'remote\n' > "$OTHER/a.txt"; git -C "$OTHER" commit -qam remote; git -C "$OTHER" push -q origin main
  printf 'local\n' > "$LOCAL/a.txt"; git -C "$LOCAL" commit -qam local
  git -C "$LOCAL" fetch -q origin
  before="$(git -C "$LOCAL" rev-parse HEAD)"
  run bash -c "$(declare -f push_lane_integrate_remote); push_lane_integrate_remote '$LOCAL' origin/main \$(git -C '$LOCAL' rev-parse origin/main)"
  [ "$status" -ne 0 ]
  [ "$(git -C "$LOCAL" rev-parse HEAD)" = "$before" ]
  [ ! -f "$LOCAL/.git/MERGE_HEAD" ]
}

@test "dirty overlapping worktree file → isolated merge succeeds, root dirt preserved" {
  printf 'remote\n' > "$OTHER/a.txt"; git -C "$OTHER" commit -qam remote; git -C "$OTHER" push -q origin main
  printf 'local\n' > "$LOCAL/c.txt"; git -C "$LOCAL" add c.txt; git -C "$LOCAL" commit -qm local
  printf 'uncommitted\n' > "$LOCAL/a.txt"
  git -C "$LOCAL" fetch -q origin
  before_head="$(git -C "$LOCAL" rev-parse HEAD)"
  before_index="$(git -C "$LOCAL" ls-files --stage | sha256sum | awk '{print $1}')"
  before_worktree="$(sha256sum "$LOCAL/a.txt" | awk '{print $1}')"
  run bash -c "$(declare -f push_lane_integrate_remote); push_lane_integrate_remote '$LOCAL' origin/main \$(git -C '$LOCAL' rev-parse origin/main)"
  [ "$status" -eq 0 ]
  [ "$(git -C "$LOCAL" rev-parse HEAD)" != "$before_head" ]
  git -C "$LOCAL" merge-base --is-ancestor origin/main HEAD
  [[ "$(git -C "$LOCAL" log -1 --format=%s)" == *"integrate origin/main"* ]]
  [ "$(git -C "$LOCAL" ls-files --stage | sha256sum | awk '{print $1}')" = "$before_index" ]
  [ "$(sha256sum "$LOCAL/a.txt" | awk '{print $1}')" = "$before_worktree" ]
  [ "$(cat "$LOCAL/a.txt")" = "uncommitted" ]
  [ ! -f "$LOCAL/.git/MERGE_HEAD" ]
}

@test "PUSH_LANE_AUTO_INTEGRATE=0 keeps the old fail-closed behaviour" {
  printf 'remote\n' > "$OTHER/b.txt"; git -C "$OTHER" add b.txt; git -C "$OTHER" commit -qm remote; git -C "$OTHER" push -q origin main
  printf 'local\n' > "$LOCAL/c.txt"; git -C "$LOCAL" add c.txt; git -C "$LOCAL" commit -qm local
  git -C "$LOCAL" fetch -q origin
  run bash -c "$(declare -f push_lane_integrate_remote); PUSH_LANE_AUTO_INTEGRATE=0 push_lane_integrate_remote '$LOCAL' origin/main \$(git -C '$LOCAL' rev-parse origin/main)"
  [ "$status" -ne 0 ]
  [ "$(git -C "$LOCAL" log -1 --format=%s)" = "local" ]
}
