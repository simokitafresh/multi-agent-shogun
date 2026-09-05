#!/usr/bin/env bash
# publish_direct_commit.sh — root checkout専用のU1b直接commit wrapper
#
# Usage:
#   scripts/publish_direct_commit.sh -m "message" -- path ...
#
# 公開へ進む唯一の経路は publisher_queue.sh lock-run であり、fetchから
# pushまでを同一の有界lock critical sectionへ収める。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

usage() {
    echo "Usage: bash scripts/publish_direct_commit.sh -m <message> -- <paths...>" >&2
    echo "       bash scripts/publish_direct_commit.sh --republish <full-sha>   # root 上の既存 commit を isolated cherry-pick で origin へ" >&2
}

# U1bはmain checkoutのroot cwdだけを受け付ける。linked worktreeは.gitが
# directoryではなくfileになるため、rootと同時に明示的に拒否する。
require_main_root() {
    local cwd git_root is_bare
    cwd="$(pwd -P)"
    git_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    is_bare="$(git rev-parse --is-bare-repository 2>/dev/null || true)"
    if [[ "$cwd" != "$REPO_ROOT" || "$git_root" != "$REPO_ROOT" || \
          "$is_bare" != false || ! -d "$REPO_ROOT/.git" ]]; then
        echo "publish_direct_commit: root checkout required (rc=7)" >&2
        return 7
    fi
}

require_main_root || exit $?

message=""
locked=0
republish_sha=""
paths=()
while (($#)); do
    case "$1" in
        -m|--message)
            (($# >= 2)) || { usage; exit 2; }
            message="$2"
            shift 2
            ;;
        --locked)
            locked=1
            shift
            ;;
        --republish)
            (($# >= 2)) || { usage; exit 2; }
            republish_sha="$2"
            shift 2
            ;;
        --)
            shift
            paths=("$@")
            break
            ;;
        -h|--help)
            usage 2>&1
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

if [[ -z "$republish_sha" ]]; then
    [[ -n "$message" && ${#paths[@]} -gt 0 ]] || { usage; exit 2; }
fi

# 2026-09-05 将軍: c2a(3-way merge)は commit の祖先(root 上の他者の未合流 commit)まで巻き込むため、
# 他者 commit が origin と衝突していると自分の 1 commit も出せない(18:30 実証: 軍師 D0 2 commit の
# review_bundle.py 衝突で将軍 6 commit が全滅)。isolated clone で対象 commit だけを origin/main へ
# cherry-pick して push する。shared root には一切触れない(D012 は root 内の merge/rebase/cherry-pick
# を禁じる。isolated clone は c2a と同じ扱い)。root の収束は drain lane の責務。
publish_isolated_cherry_pick() {
    local commit_hash="$1" root url work rc=0
    root="$(git rev-parse --show-toplevel)"
    url="$(git config --get remote.origin.url)"
    [[ -n "$url" ]] || { echo "publish_direct_commit: remote.origin.url missing" >&2; return 1; }
    work="$(mktemp -d "${TMPDIR:-/tmp}/pdc-cherry.XXXXXX")"
    (
        set -euo pipefail
        git clone -q --reference "$root" --branch main "$url" "$work/clone"
        cd "$work/clone"
        git fetch -q "$root" "$commit_hash"
        before="$(git rev-parse HEAD)"
        # `set -e` is suspended inside a `( ... ) || rc=$?` list, so every step
        # must fail explicitly. 2026-09-06 01:20: a conflicting cherry-pick
        # printed "error: could not apply" yet fell through to push+echo and
        # reported a false "published" with origin/main unchanged.
        if ! git -c user.name=shogun -c user.email=shogun@shogun.local cherry-pick -x "$commit_hash" >/dev/null 2>&1; then
            echo "publish_direct_commit: cherry-pick conflict for ${commit_hash:0:9}: $(git diff --name-only --diff-filter=U | tr '\n' ' ')" >&2
            git cherry-pick --abort >/dev/null 2>&1 || true
            exit 9
        fi
        [ "$(git rev-parse HEAD)" != "$before" ] || { echo "publish_direct_commit: cherry-pick produced no commit for ${commit_hash:0:9}" >&2; exit 9; }
        git push -q origin HEAD:main || exit 9
        echo "publish_direct_commit: cherry-picked ${commit_hash:0:9} -> origin/main $(git rev-parse --short HEAD)"
    ) || rc=$?
    rm -rf "$work"
    return "$rc"
}

run_locked() {
    local commit_hash
    if ! timeout 120 git fetch origin; then
        echo "publish_direct_commit: git fetch failed (rc=8)" >&2
        return 8
    fi
    # 2026-09-05 将軍(殿『コミットをまとめるメリットは？』): root が origin と分岐している
    # (忍者 commit を root に置き c2a が別 commit で合流した後の恒常状態)とき、ff 失敗で
    # rc=8 終了すると commit 自体が作れず、publish が root 収束まで滞留=commit のまとめ書きを
    # 強制していた。分岐時は ff を諦め、commit を作って c2a(isolated clone 3-way)で直接 origin へ
    # 出す。root の収束は別 lane(publisher root drain / 家老)の責務で、ここでは待たない。
    local diverged=0
    if ! git merge --ff-only origin/main; then
        if git merge-base --is-ancestor origin/main HEAD; then
            echo "publish_direct_commit: origin/main ff-only merge failed (rc=8)" >&2
            return 8
        fi
        diverged=1
        echo "publish_direct_commit: root diverged from origin/main (ahead=$(git rev-list --count origin/main..HEAD) behind=$(git rev-list --count HEAD..origin/main)); commit locally and publish via c2a" >&2
    fi

    # ninja_scope_commit accepts the exact requested paths; append exactly one
    # wrapper trailer so C1a can identify this U1b publisher.
    if commit_hash="$(bash "$SCRIPT_DIR/ninja_scope_commit.sh" \
        -m "${message}

Published-By: wrapper" -- "${paths[@]}")"; then
        :
    else
        local scope_rc=$?
        return "$scope_rc"
    fi
    [[ "$commit_hash" =~ ^[0-9a-f]{40}$ ]] || {
        echo "publish_direct_commit: scope commit returned invalid hash" >&2
        return 1
    }
    if (( diverged == 0 )) && timeout 120 git push origin main; then
        return 0
    fi
    # lock 外で origin が進んだ(publisher batch 等)ため non-ff で reject された場合は、
    # 同じ lock 内で isolated clone の 3-way merge(Published-By trailer 付き)を 1 回だけ試み、
    # root を origin へ ff する(将軍 2026-09-03 11:07 hotfix 列)。
    echo "publish_direct_commit: push rejected; retrying via publisher_c2a_merge (nolock)" >&2
    if PUBLISHER_C2A_MERGE_NOLOCK=1 bash "$SCRIPT_DIR/publisher_c2a_merge.sh" "u1b_retry_$(date +%H%M%S)" "$commit_hash"; then
        if timeout 120 git fetch origin && git merge --ff-only origin/main 2>/dev/null; then
            return 0
        fi
        # 分岐中の root は ff できないが、内容は c2a で origin に出ている。publish は成功。
        echo "publish_direct_commit: published via c2a; root remains diverged (converge via root drain lane)" >&2
        return 0
    fi
    echo "publish_direct_commit: c2a merge failed (foreign root commits conflict?); retrying via isolated cherry-pick" >&2
    if publish_isolated_cherry_pick "$commit_hash"; then
        timeout 120 git fetch origin >/dev/null 2>&1 || true
        git merge --ff-only origin/main >/dev/null 2>&1 || echo "publish_direct_commit: published via cherry-pick; root remains diverged (converge via root drain lane)" >&2
        return 0
    fi
    echo "publish_direct_commit: push retry failed (rc=9)" >&2
    return 9
}

# --republish <sha>: root 上に既にある自分の commit(以前 rc=9 で origin に出なかったもの)を
# isolated cherry-pick で origin へ出す。新規 commit は作らない。
republish_locked() {
    local sha="$1"
    [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "publish_direct_commit: --republish needs a full sha" >&2; return 2; }
    timeout 120 git fetch origin >/dev/null 2>&1 || { echo "publish_direct_commit: git fetch failed (rc=8)" >&2; return 8; }
    if git merge-base --is-ancestor "$sha" origin/main; then
        echo "publish_direct_commit: ${sha:0:9} already on origin/main" >&2
        return 0
    fi
    # A prior --republish lands the change as a *different* sha (cherry-pick).
    # Recognise that by patch-id so the second call is an explicit no-op
    # success instead of relying on an empty cherry-pick falling through
    # (which the fail-closed pick in publish_isolated_cherry_pick no longer does).
    if git cherry origin/main "$sha" "${sha}^" 2>/dev/null | grep -q "^- "; then
        echo "publish_direct_commit: ${sha:0:9} already applied on origin/main (patch-id match)" >&2
        return 0
    fi
    publish_isolated_cherry_pick "$sha"
}

# The inner invocation is deliberately the same script so lock-run owns the
# complete fetch→merge→commit→push sequence without a second implementation.
if (( locked )) && [[ -n "${republish_sha:-}" ]]; then
    republish_locked "$republish_sha"
    exit $?
fi
if (( locked )); then
    run_locked
    exit $?
fi
if [[ -n "${republish_sha:-}" ]]; then
    exec bash "$SCRIPT_DIR/publisher_queue.sh" lock-run --bound 300 -- \
        bash "$SCRIPT_DIR/publish_direct_commit.sh" --locked --republish "$republish_sha"
fi

exec bash "$SCRIPT_DIR/publisher_queue.sh" lock-run --bound 300 -- \
    bash "$SCRIPT_DIR/publish_direct_commit.sh" --locked -m "$message" -- "${paths[@]}"
