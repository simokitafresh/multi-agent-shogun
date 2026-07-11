#!/usr/bin/env bash
# ninja_scope_commit.sh — shared index上で指定pathだけを安全にcommitする
set -euo pipefail

# GA-222: このscript自身が置かれているdirectory(=multi-agent-shogunの
# scripts/)を動的に求める。ninja_scope_commit.shはDM-Signal等、別repoを
# cwdにして呼ばれることがあるため($repo_rootはそちらのrepo rootになる)、
# 後段でsourceするSSOT(scripts/lib/scope_path.sh)は「操作対象repo」ではなく
# 「このscript自身の設置場所」基準で解決する。cd実行より前に計算すること
# (BASH_SOURCEが相対pathの場合、後のcdでPWD基準の解決が狂うため)。
_ninja_scope_commit_self="${BASH_SOURCE[0]:-$0}"
[[ "$_ninja_scope_commit_self" = /* ]] || _ninja_scope_commit_self="$PWD/$_ninja_scope_commit_self"
NINJA_SCOPE_COMMIT_SCRIPT_DIR="$(cd "$(dirname "$_ninja_scope_commit_self")" && pwd)"
unset _ninja_scope_commit_self

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

# GA-222: scope path正規化はscripts/lib/scope_path.sh(SSOT)に集約する。
# ここ(commit scopeのバリデーション)とsync_git_hooks.sh(is_in_scope判定)で
# 別々に正規化ロジックを持つと、片方だけ直して片方が取り残される形で
# 同じ穴が別のpath表現で繰り返し再発したため、両scriptとも同一helperのみを使う。
# shellcheck source=scripts/lib/scope_path.sh
source "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/lib/scope_path.sh"

paths=()
for path in "$@"; do
    [[ -n "$path" && "$path" != -* ]] \
        || { echo "BLOCK: invalid scope path: ${path:-<empty>}" >&2; exit 2; }
    # scope_path_normalizeは絶対path・".."を含むpath(出現位置を問わず)・
    # root相当に解決されるpath(空/"."/".."単体等)を全てfail-closedし、
    # 理由をstderrへ書く(このtry/exitはその理由をそのまま伝播させる)。
    normalized="$(scope_path_normalize "$path")" || exit 2
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
# scope_path_is_in_scope(SSOT)で判定することで、正規化ロジックの重複を避ける。
mapfile -t committed < <(git diff-tree --no-commit-id --name-only -r HEAD)
for committed_path in "${committed[@]}"; do
    scope_path_is_in_scope "$committed_path" "${paths[@]}" \
        || { echo "FATAL: out-of-scope path entered commit: $committed_path" >&2; exit 1; }
done

git rev-parse HEAD
