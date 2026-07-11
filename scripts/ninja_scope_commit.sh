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

# GA-222 final edge RC: scope pathの表現ゆれ(末尾"/."、内部"/./"、先頭"./")を
# lexicalに正規化してからチェック・保存する。これにより`scripts/hooks/.`と
# `scripts/hooks`のようなpathspec同値表現がpostcondition/sync_git_hooks双方で
# 同一視される(片方だけ正規化すると別表現で同種の穴が再発するため)。
normalize_rel_path() {
    local p="$1"
    while [[ "$p" == */./* ]]; do
        p="${p/\/.\//\/}"
    done
    p="${p%/.}"
    p="${p%/}"
    p="${p#./}"
    printf '%s' "$p"
}

paths=()
for path in "$@"; do
    [[ -n "$path" && "$path" != -* ]] \
        || { echo "BLOCK: invalid scope path: ${path:-<empty>}" >&2; exit 2; }
    normalized="$(normalize_rel_path "$path")"
    [[ "$normalized" != /* && "$normalized" != ../* && "$normalized" != */../* ]] \
        || { echo "BLOCK: scope path must stay inside repository: $path" >&2; exit 2; }
    # GA-222 final edge RC: root scope("."等repo全体を指す表現)は他agentの
    # 無関係な変更まで丸ごとgit addしうるため、共有worktreeでは明示的にBLOCKする。
    # このBLOCKはgit add呼出より前(バリデーションループ内)で発生するため、
    # commit scopeにこの表現が含まれる限りindex/working treeは一切変更されない。
    [[ "$normalized" != "." && "$normalized" != "" ]] \
        || { echo "BLOCK: root scope '.' is not allowed — commit scope must stay inside a specific file/subdirectory to avoid staging unrelated shared-worktree changes: $path" >&2; exit 2; }
    [[ -e "$normalized" || -L "$normalized" ]] \
        || { echo "BLOCK: scope path does not exist: $normalized" >&2; exit 2; }
    [[ -n "$(git status --porcelain -- "$normalized")" ]] \
        || { echo "BLOCK: scope path has no changes: $normalized" >&2; exit 2; }
    paths+=("$normalized")
done

# Path限定addは他者の既存stageを変更しない。--onlyは共有indexの他pathをcommitしない。
git add -- "${paths[@]}"

# GA-222: commit前にgitが実際に発火するhookを正本(scripts/hooks/*.sh)と同期する。
# git add後に呼ぶことで、対象正本がこのcommitのscope内ならstaged(index)版、
# scope外(他agentの作業中/未確定分含む)ならHEAD(直近commit済み)版を使い分けられる。
# 正本が存在しないrepo(このrepoの規約非対象)では無害にno-op。
if [[ -f "$repo_root/scripts/sync_git_hooks.sh" ]]; then
    sync_args=()
    for scope_path in "${paths[@]}"; do
        sync_args+=(--scope-path "$scope_path")
    done
    bash "$repo_root/scripts/sync_git_hooks.sh" "${sync_args[@]}" \
        || { echo "BLOCK(GA-222): git hook sync failed — commit aborted" >&2; exit 1; }
fi
if [[ -f "$repo_root/../multi-agent-shogun/scripts/dm_signal_research_reflux_guard.sh" ]]; then
    bash "$repo_root/../multi-agent-shogun/scripts/dm_signal_research_reflux_guard.sh" check --repo "$repo_root"
elif [[ -f "/mnt/c/tools/multi-agent-shogun/scripts/dm_signal_research_reflux_guard.sh" ]]; then
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
