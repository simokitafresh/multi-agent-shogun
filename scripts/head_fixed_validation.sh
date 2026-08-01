#!/usr/bin/env bash
# Run task-selected validation at one immutable commit, independent of shared HEAD.
set -euo pipefail

TASK_YAML=${1:?usage: head_fixed_validation.sh TASK_YAML [REPO]}
REPO=${2:-$(git rev-parse --show-toplevel)}
TASK_YAML=$(realpath "$TASK_YAML")
FIXED_SHA=$(git -C "$REPO" rev-parse HEAD)
WORKTREE_PARENT=$(mktemp -d "${TMPDIR:-/tmp}/head-fixed-validation.XXXXXX")
WORKTREE="$WORKTREE_PARENT/worktree"

cleanup() {
    local rc=$?
    git -C "$REPO" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
    if git -C "$REPO" worktree list --porcelain | grep -Fqx "worktree $WORKTREE" || [ -e "$WORKTREE" ]; then
        echo "FAIL: head-fixed validation worktree residue: $WORKTREE" >&2
        rc=1
    fi
    rmdir "$WORKTREE_PARENT" >/dev/null 2>&1 || true
    exit "$rc"
}
trap cleanup EXIT INT TERM

git -C "$REPO" worktree add --quiet --detach "$WORKTREE" "$FIXED_SHA"
if [ -n "${HEAD_FIXED_VALIDATION_AFTER_CAPTURE_COMMAND:-}" ]; then
    bash -lc "$HEAD_FIXED_VALIDATION_AFTER_CAPTURE_COMMAND"
fi

echo "HEAD_FIXED_VALIDATION fixed_sha=$FIXED_SHA worktree=$WORKTREE"
if [ -n "${HEAD_FIXED_VALIDATION_COMMAND:-}" ]; then
    (cd "$WORKTREE" && bash -lc "$HEAD_FIXED_VALIDATION_COMMAND")
else
    (cd "$WORKTREE" && bash scripts/run_tests.sh task "$TASK_YAML")
fi
