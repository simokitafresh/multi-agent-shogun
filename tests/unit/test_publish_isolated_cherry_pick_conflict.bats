#!/usr/bin/env bats
# test_necessity: publish_isolated_cherry_pick must return non-zero and leave
# origin/main untouched when the cherry-pick conflicts. On 2026-09-06 01:20 a
# conflicting pick printed "error: could not apply" but fell through to push and
# reported "published", because `set -e` is suspended inside `( ... ) || rc=$?`.

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    T="$(mktemp -d)"
    # origin (bare) with one file
    git init -q -b main "$T/seed"
    ( cd "$T/seed" && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init \
      && printf 'base\n' > f.txt && git add f.txt && git -c user.name=t -c user.email=t@t commit -q -m f )
    git clone -q --bare "$T/seed" "$T/origin.git"
    # local root clone that will hold the commit to publish
    git clone -q "$T/origin.git" "$T/root"
    ( cd "$T/root" && printf 'root-change\n' > f.txt && git -c user.name=t -c user.email=t@t commit -qam local )
    # origin moves on with a conflicting change to the same line
    git clone -q "$T/origin.git" "$T/other"
    ( cd "$T/other" && printf 'origin-change\n' > f.txt && git -c user.name=t -c user.email=t@t commit -qam remote && git push -q origin main )
    HELPER="$T/fn.sh"
    sed -n '/^publish_isolated_cherry_pick()/,/^}$/p' "$ROOT/scripts/publish_direct_commit.sh" > "$HELPER"
}

teardown() { rm -rf "$T"; }

@test "conflicting isolated cherry-pick returns non-zero, names the file, and does not move origin/main" {
    local before after
    before="$(git -C "$T/origin.git" rev-parse main)"
    run bash -c "cd '$T/root' && source '$HELPER' && publish_isolated_cherry_pick \$(git rev-parse HEAD)"
    [ "$status" -ne 0 ]
    [[ "$output" == *"cherry-pick conflict"* ]]
    [[ "$output" == *"f.txt"* ]]
    [[ "$output" != *"published via cherry-pick"* ]]
    after="$(git -C "$T/origin.git" rev-parse main)"
    [ "$before" = "$after" ]
}

@test "clean isolated cherry-pick advances origin/main by exactly one commit" {
    ( cd "$T/root" && git fetch -q origin && git reset -q --hard origin/main \
      && printf 'extra\n' > g.txt && git add g.txt && git -c user.name=t -c user.email=t@t commit -qm add-g )
    local before after
    before="$(git -C "$T/origin.git" rev-parse main)"
    run bash -c "cd '$T/root' && source '$HELPER' && publish_isolated_cherry_pick \$(git rev-parse HEAD)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cherry-picked"* ]]
    after="$(git -C "$T/origin.git" rev-parse main)"
    [ "$before" != "$after" ]
    [ "$(git -C "$T/origin.git" rev-list --count "$before..$after")" -eq 1 ]
}
