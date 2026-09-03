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

[[ -n "$message" && ${#paths[@]} -gt 0 ]] || { usage; exit 2; }

run_locked() {
    local commit_hash
    if ! timeout 120 git fetch origin; then
        echo "publish_direct_commit: git fetch failed (rc=8)" >&2
        return 8
    fi
    if ! git merge --ff-only origin/main; then
        echo "publish_direct_commit: origin/main ff-only merge failed (rc=8)" >&2
        return 8
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
    if timeout 120 git push origin main; then
        return 0
    fi
    # lock 外で origin が進んだ(publisher batch 等)ため non-ff で reject された場合は、
    # 同じ lock 内で isolated clone の 3-way merge(Published-By trailer 付き)を 1 回だけ試み、
    # root を origin へ ff する(将軍 2026-09-03 11:07 hotfix 列)。
    echo "publish_direct_commit: push rejected; retrying via publisher_c2a_merge (nolock)" >&2
    if PUBLISHER_C2A_MERGE_NOLOCK=1 bash "$SCRIPT_DIR/publisher_c2a_merge.sh" "u1b_retry_$(date +%H%M%S)" "$commit_hash" \
        && timeout 120 git fetch origin && git merge --ff-only origin/main; then
        return 0
    fi
    echo "publish_direct_commit: push retry failed (rc=9)" >&2
    return 9
}

# The inner invocation is deliberately the same script so lock-run owns the
# complete fetch→merge→commit→push sequence without a second implementation.
if (( locked )); then
    run_locked
    exit $?
fi

exec bash "$SCRIPT_DIR/publisher_queue.sh" lock-run --bound 300 -- \
    bash "$SCRIPT_DIR/publish_direct_commit.sh" --locked -m "$message" -- "${paths[@]}"
