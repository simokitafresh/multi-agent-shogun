#!/usr/bin/env bash
# git_stash_guard_classify.sh — git stash破壊的操作判定の唯一の入口(SSOT)。
# cmd_karo_ci_red_remaining_unit_202607151950
#
# heavy_job_classify.shと同じ2段構成:
#   1. git_stash_guard_maybe_relevant() — bash-nativeの保守的negative filter。
#      "stash"を含まないcommandはpython側も必ず"allow"を返すと保証されるため、
#      python3プロセスを起動せず"allow"を直接返す。
#   2. 一致した場合のみ python3 git_stash_guard_classify.py を起動し、
#      argv位置ベースの構造判定に委譲する。

git_stash_guard_maybe_relevant() {
    local cmd="$1"
    [[ "$cmd" == *stash* ]] && return 0
    return 1
}

git_stash_guard_classify() {
    local command="$1"
    if git_stash_guard_maybe_relevant "$command"; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        GIT_STASH_GUARD_COMMAND="$command" python3 -S "${script_dir}/lib/git_stash_guard_classify.py" 2>/dev/null || echo "block"
    else
        echo "allow"
    fi
}
