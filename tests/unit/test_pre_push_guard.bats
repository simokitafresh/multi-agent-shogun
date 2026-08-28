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

# --- 基準2: 境界がcmdを分割しないこと(軍師の指摘 2026-07-26) ---
# path基準だけでは、同一cmd_idが2commitに分かれている時に境界がそれを割り、
# 是正前の版だけを公開しうる(実例: cmd_karo_impl_watcher_log_series_kind が
# db3a1e724 と 92bef71db、cmd_karo_impl_approval_log_atomic が 6d8412dfd と
# 2e2dcb0c2。いずれも後者が軍師レビューを受けた是正commit)。
_setup_split_history() {
    cd "$W/wc"
    # X1(cmd_alpha) X2(cmd_beta) X3(阻害path) X4(cmd_alpha 是正)
    printf 'x1\n' > scripts/x1.txt;      git add -A; git commit -q -m "cmd_alpha_20260726: first"
    printf 'x2\n' > scripts/x2.txt;      git add -A; git commit -q -m "cmd_beta_20260726: only one"
    printf 'x3\n' > scripts/split.sh;    git add -A; git commit -q -m "cmd_gamma_20260726: touches blocking path"
    printf 'x4\n' > scripts/x4.txt;      git add -A; git commit -q -m "cmd_alpha_20260726: fix after review"
}

@test "positive control: a boundary that would split one cmd is moved back before that cmd" {
    _setup_split_history
    # 阻害pathを未commitに = path基準の境界は X2(cmd_beta) の位置になる
    printf 'x3-dirty\n' > "$W/wc/scripts/split.sh"

    # path基準だけなら X2 が境界。しかし X1(cmd_alpha) は X4 に続きがあるので割れる。
    run bash "$GUARD" safe-tip "$W/wc" origin/main
    [ "$status" -eq 0 ]
    # cmd_alpha を含まない位置、すなわち X1 の親まで下がる
    [ "$output" = "$(git -C "$W/wc" rev-parse HEAD~4)" ]
    # 下がった境界に cmd_alpha が含まれないこと
    run git -C "$W/wc" log --format=%s "origin/main..$output"
    [[ "$output" != *"cmd_alpha_20260726"* ]]
}

@test "negative control: when no cmd is split, the path-based boundary is kept as is" {
    cd "$W/wc"
    printf 'y1\n' > scripts/y1.txt;   git add -A; git commit -q -m "cmd_delta_20260726: only one"
    printf 'y2\n' > scripts/split.sh; git add -A; git commit -q -m "cmd_eps_20260726: touches blocking path"
    printf 'y2-dirty\n' > "$W/wc/scripts/split.sh"

    run bash "$GUARD" safe-tip "$W/wc" origin/main
    [ "$status" -eq 0 ]
    # 阻害commitの直前(= cmd_delta)がそのまま境界になる
    [ "$output" = "$(git -C "$W/wc" rev-parse HEAD~1)" ]
}

# test_necessity: pre-push may skip affected tests only for a terminal Ninja
# receipt whose source head and scripts/tests tree are proven identical to the
# push target.  A fingerprint-only cache would permit stale or failed reuse.
@test "pre-push reuses only a terminal receipt with matching tree identity" {
    hook="$PROJECT_ROOT/.githooks/pre-push"
    function_body="$(awk '
        /^pre_push_test_tree_fingerprint\(\)/ {capture=1}
        /^pre_push_receipt_source_fingerprint\(\)/ {capture=1}
        /^pre_push_receipt_matches\(\)/ {capture=1}
        capture {print}
        capture && /^}$/ {capture=0}
    ' "$hook")"
    run env FUNCTION_BODY="$function_body" WORK="$W/wc" bash -c '
        set -e
        REPO_ROOT="$WORK"
        eval "$FUNCTION_BODY"
        head="$(git -C "$REPO_ROOT" rev-parse HEAD)"
        old_head="$(git -C "$REPO_ROOT" rev-parse HEAD~1)"
        tree="$(pre_push_test_tree_fingerprint "$head")"
        old_tree="$(pre_push_test_tree_fingerprint "$old_head")"
        source_fp="$(pre_push_receipt_source_fingerprint "$head")"
        artifact="$REPO_ROOT/receipt.output"
        printf "terminal PASS\n" >"$artifact"
        output_sha="$(sha256sum "$artifact" | awk "{print \$1}")"
        receipt="$REPO_ROOT/receipt.json"
        write_receipt() {
            python3 - "$receipt" "$artifact" "$output_sha" "$1" "$2" "$3" "$4" "$5" "$6" "$7" <<"PY"
import json, sys
path, artifact, output_sha, complete, result, rc, skip, source_head, source_fp, tree = sys.argv[1:]
json.dump({
    "version": 3, "complete": complete == "true", "result": result,
    "rc": int(rc), "duration_ms": 1, "output_sha256": output_sha,
    "declared_test_count": 67, "observed_test_count": 67, "skip_count": int(skip),
    "artifact": artifact, "signal": None, "command": ["bats"],
    "source_head": source_head, "test_paths": ["tests/unit/test_pre_push_guard.bats"],
    "source_fingerprint": source_fp, "tree_fingerprint": tree,
}, open(path, "w", encoding="utf-8"))
PY
        }
        pass=0
        reject=0
        write_receipt true PASS 0 0 "$head" "$source_fp" "$tree"
        pre_push_receipt_matches "$receipt" "$head" "$tree" && pass=$((pass + 1))
        write_receipt true PASS 0 0 "$old_head" "$source_fp" "$old_tree"
        pre_push_receipt_matches "$receipt" "$head" "$tree" || reject=$((reject + 1))
        write_receipt true PASS 0 0 "$head" "$source_fp" "$(printf wrong | sha256sum | awk "{print \$1}")"
        pre_push_receipt_matches "$receipt" "$head" "$tree" || reject=$((reject + 1))
        write_receipt true FAIL 1 0 "$head" "$source_fp" "$tree"
        pre_push_receipt_matches "$receipt" "$head" "$tree" || reject=$((reject + 1))
        write_receipt true PASS 0 1 "$head" "$source_fp" "$tree"
        pre_push_receipt_matches "$receipt" "$head" "$tree" || reject=$((reject + 1))
        printf "reuse=%s reject=%s false_reuse=%s\n" "$pass" "$reject" "$((4 - reject))"
        [[ "$pass" -eq 1 && "$reject" -eq 4 ]]
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"reuse=1 reject=4 false_reuse=0"* ]]
}

@test "pre-push no longer trusts the legacy fingerprint-only cache" {
    hook="$PROJECT_ROOT/.githooks/pre-push"
    run rg -n 'PREPUSH_PASS_CACHE|PREPUSH_CACHE_TO_PUBLISH|pre_push_find_reusable_receipt|pre_push_receipt_matches' "$hook"
    [ "$status" -eq 0 ]
    [[ "$output" != *"PREPUSH_PASS_CACHE"* ]]
    [[ "$output" != *"PREPUSH_CACHE_TO_PUBLISH"* ]]
    [ "$(printf '%s\n' "$output" | rg -c 'pre_push_find_reusable_receipt|pre_push_receipt_matches')" -ge 2 ]
}
