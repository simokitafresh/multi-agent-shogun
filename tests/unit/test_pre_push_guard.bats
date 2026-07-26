#!/usr/bin/env bats
# test_pre_push_guard.bats — 部分push境界計算の対照fixture
# (cmd_karo_impl_partial_push_safety_20260726)
#
# test_necessity: 守る不変量は1つ —
#   「作業ツリーの未commit pathと重なるcommitがある時だけ safe_tip を返し、
#    重ならない時は空を返す(=全量pushへ落とす)」。
#   これが片方向に倒れると、常に部分pushとなって台帳への到達が恒常的に遅れるか、
#   逆に重複commitまで送ってGA-PUSH1が守っている不変量を破る。
#
# ★このtestは実際のremoteへpushしない。BATS_TEST_TMPDIR内のbare repoだけを使う。

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    GUARD="$PROJECT_ROOT/scripts/lib/pre_push_guard.sh"
    W="$BATS_TEST_TMPDIR/pp"
    mkdir -p "$W"
    export GIT_CONFIG_GLOBAL="$W/gitconfig"
    git config --global user.email test@example.com
    git config --global user.name test
    git config --global init.defaultBranch main

    git init --bare -q "$W/remote.git"
    git init -q "$W/wc"
    cd "$W/wc"
    mkdir -p scripts
    printf 'base\n' > scripts/base.txt
    git add -A && git commit -q -m "C0 base"
    git remote add origin "$W/remote.git"
    git push -q origin main

    # 未push: A(無関係) B(無関係) P(阻害path) D(無関係)
    printf 'a\n' > scripts/a.txt;        git add -A; git commit -q -m "A unrelated"
    printf 'b\n' > scripts/b.txt;        git add -A; git commit -q -m "B unrelated"
    printf 'p\n' > scripts/blocking.sh;  git add -A; git commit -q -m "P touches blocking path"
    printf 'd\n' > scripts/d.txt;        git add -A; git commit -q -m "D unrelated"
}

@test "positive control: with an overlapping path, safe_tip stops before the blocking commit" {
    # 阻害pathを未commitで編集 = GA-PUSH1が止める条件
    printf 'p-dirty\n' > "$W/wc/scripts/blocking.sh"

    run bash "$GUARD" first-blocking "$W/wc" origin/main
    [ "$status" -eq 0 ]
    [ "$output" = "$(git -C "$W/wc" rev-parse HEAD~1)" ]   # P

    run bash "$GUARD" safe-tip "$W/wc" origin/main
    [ "$status" -eq 0 ]
    [ "$output" = "$(git -C "$W/wc" rev-parse HEAD~2)" ]   # B

    # safe_tip までを隔離remoteへ送ると、P以降は送られない
    git -C "$W/wc" push -q origin "$output:main"
    [ "$(git -C "$W/remote.git" rev-parse main)" = "$(git -C "$W/wc" rev-parse HEAD~2)" ]
    run git -C "$W/remote.git" merge-base --is-ancestor "$(git -C "$W/wc" rev-parse HEAD~1)" main
    [ "$status" -ne 0 ]
}

@test "negative control: with no overlapping path, no safe_tip is produced (full push stays)" {
    # 作業ツリーは clean = 重複なし
    run bash "$GUARD" first-blocking "$W/wc" origin/main
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    run bash "$GUARD" safe-tip "$W/wc" origin/main
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    run bash "$GUARD" report "$W/wc" origin/main
    [ "$status" -eq 0 ]
    [[ "$output" == *"blocking=none"* ]]
    [[ "$output" == *"action=full-push"* ]]
}

@test "negative control: an unrelated dirty path does not trigger a partial push" {
    # 未pushcommitが触っていないpathだけがdirty
    printf 'unrelated\n' > "$W/wc/scripts/base.txt"

    run bash "$GUARD" first-blocking "$W/wc" origin/main
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "boundary: when the oldest pending commit is the blocking one, no advance is offered" {
    # A を阻害commitにする(最古の未pushcommitが重複を含む)
    printf 'a-dirty\n' > "$W/wc/scripts/a.txt"

    run bash "$GUARD" first-blocking "$W/wc" origin/main
    [ "$status" -eq 0 ]
    [ "$output" = "$(git -C "$W/wc" rev-parse HEAD~3)" ]   # A

    run bash "$GUARD" safe-tip "$W/wc" origin/main
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    run bash "$GUARD" report "$W/wc" origin/main
    [ "$status" -eq 0 ]
    [[ "$output" == *"action=none"* ]]
}
