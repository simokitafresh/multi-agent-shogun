#!/usr/bin/env bash
set -u

usage() {
    echo "Usage: code_locate.sh [--include-untracked --reason TEXT] QUERY [PATHSPEC ...]" >&2
}

include_untracked=0
reason=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --include-untracked) include_untracked=1; shift ;;
        --reason)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            reason=$2; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        --) shift; break ;;
        -*) echo "code_locate: unknown option: $1" >&2; usage; exit 2 ;;
        *) break ;;
    esac
done

[ "$#" -ge 1 ] || { usage; exit 2; }
query=$1
shift
[ -n "$query" ] || { echo "code_locate: QUERY must not be empty" >&2; exit 2; }

if [ "$include_untracked" -eq 0 ]; then
    [ -z "$reason" ] || { echo "code_locate: --reason requires --include-untracked" >&2; exit 2; }
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
        echo "code_locate: tracked search requires a git worktree" >&2
        exit 2
    }
    if [ "$#" -gt 0 ]; then
        git grep -n --full-name -e "$query" -- "$@"
    else
        git grep -n --full-name -e "$query" --
    fi
    exit $?
fi

[ -n "${reason//[[:space:]]/}" ] || {
    echo "code_locate: --include-untracked requires a non-empty --reason" >&2
    exit 2
}
command -v rg >/dev/null 2>&1 || { echo "code_locate: rg is required for untracked search" >&2; exit 2; }

paths=("$@")
[ "${#paths[@]}" -gt 0 ] || paths=(.)
rg -n --hidden \
    --glob '!node_modules/**' \
    --glob '!.git/**' \
    --glob '!.*_worktrees/**' \
    -- "$query" "${paths[@]}"
exit $?
