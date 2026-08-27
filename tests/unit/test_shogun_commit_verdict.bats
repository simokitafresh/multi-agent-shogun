#!/usr/bin/env bats
# test_necessity: 不変量=「control repo に無く正準 PJ repo にだけ存在する commit は verdict=PRESENT(exit 0)で、
#   正準 repo 行に ancestor_origin/main=yes が出る。全 repo で不在なら verdict=ABSENT(exit 1)」。
#   これが崩れると将軍が再び 1 文脈の fatal を『不在』と断定する(2026-08-28 T108 e3c456584109 誤除去)。

setup() {
    ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TMP="$(mktemp -d)"
    # control repo (empty-ish) と、正準 PJ repo (commit を持つ) を用意
    git -C "$TMP" init -q control
    git -C "$TMP/control" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "control root"
    git -C "$TMP" init -q pj
    git -C "$TMP/pj" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "pj root"
    git -C "$TMP/pj" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "pj feature"
    PJ_COMMIT="$(git -C "$TMP/pj" rev-parse HEAD)"
    # origin/main を持たせる(自分自身を origin として)
    git -C "$TMP/pj" remote add origin "$TMP/pj"
    git -C "$TMP/pj" update-ref refs/remotes/origin/main "$PJ_COMMIT"
    cat >"$TMP/projects.yaml" <<EOF
projects:
  - id: pjx
    path: "$TMP/pj"
EOF
    export SHOGUN_VERDICT_PROJECTS_CONFIG="$TMP/projects.yaml"
}

teardown() { rm -rf "$TMP"; }

@test "commit only in canonical PJ repo → PRESENT with origin ancestor yes" {
    run bash -c "cd '$TMP/control' && bash '$ROOT/scripts/shogun_commit_verdict.sh' '$PJ_COMMIT' --context context/pjx.md --no-fetch"
    [ "$status" -eq 0 ]
    [[ "$output" == *"verdict=PRESENT"* ]]
    [[ "$output" == *"repo=$TMP/pj"*"ancestor_origin/main=yes"* ]]
}

@test "commit in no repo → ABSENT exit 1" {
    run bash "$ROOT/scripts/shogun_commit_verdict.sh" 0123456789abcdef0123456789abcdef01234567 --context context/pjx.md --no-fetch
    [ "$status" -eq 1 ]
    [[ "$output" == *"verdict=ABSENT"* ]]
}
