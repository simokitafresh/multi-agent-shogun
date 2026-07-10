#!/usr/bin/env bash
# ninja_scope_commit.sh — shared index上で指定pathだけを安全にcommitする
set -euo pipefail

usage() {
    echo "Usage: bash scripts/ninja_scope_commit.sh -m <message> -- <path> [path ...]" >&2
}

message=""
while (($#)); do
    case "$1" in
        -m|--message)
            (($# >= 2)) || { usage; exit 2; }
            message="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "BLOCK: unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

[[ -n "$message" ]] || { echo "BLOCK: commit message is required" >&2; exit 2; }
(($# > 0)) || { echo "BLOCK: commit scope is empty" >&2; exit 2; }

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "BLOCK: not inside a git repository" >&2; exit 2; }
cd "$repo_root"

paths=()
for path in "$@"; do
    [[ -n "$path" && "$path" != -* ]] \
        || { echo "BLOCK: invalid scope path: ${path:-<empty>}" >&2; exit 2; }
    normalized="${path#./}"
    [[ "$normalized" != /* && "$normalized" != ../* && "$normalized" != */../* ]] \
        || { echo "BLOCK: scope path must stay inside repository: $path" >&2; exit 2; }
    [[ -e "$normalized" || -L "$normalized" ]] \
        || { echo "BLOCK: scope path does not exist: $normalized" >&2; exit 2; }
    [[ -n "$(git status --porcelain -- "$normalized")" ]] \
        || { echo "BLOCK: scope path has no changes: $normalized" >&2; exit 2; }
    paths+=("$normalized")
done

# Path限定addは他者の既存stageを変更しない。--onlyは共有indexの他pathをcommitしない。
git add -- "${paths[@]}"
if [[ -x "$repo_root/../multi-agent-shogun/scripts/dm_signal_research_reflux_guard.sh" ]]; then
    bash "$repo_root/../multi-agent-shogun/scripts/dm_signal_research_reflux_guard.sh" check --repo "$repo_root"
elif [[ -x "/mnt/c/tools/multi-agent-shogun/scripts/dm_signal_research_reflux_guard.sh" ]]; then
    bash "/mnt/c/tools/multi-agent-shogun/scripts/dm_signal_research_reflux_guard.sh" check --repo "$repo_root"
fi
git commit --only -m "$message" -- "${paths[@]}"

# 二値postcondition: commit treeは指定scopeのみ、他者stageはそのまま残る。
mapfile -t committed < <(git diff-tree --no-commit-id --name-only -r HEAD)
for committed_path in "${committed[@]}"; do
    allowed=false
    for scope_path in "${paths[@]}"; do
        if [[ "$committed_path" == "$scope_path" || "$committed_path" == "$scope_path"/* ]]; then
            allowed=true
            break
        fi
    done
    [[ "$allowed" == true ]] \
        || { echo "FATAL: out-of-scope path entered commit: $committed_path" >&2; exit 1; }
done

git rev-parse HEAD
