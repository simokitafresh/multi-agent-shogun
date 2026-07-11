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
    echo "Usage: bash scripts/ninja_scope_commit.sh -m <message> [--patch <file> --base-blob <hash>] -- <path> [path ...]" >&2
}

message=""
patch_file=""
base_blob=""
while (($#)); do
    case "$1" in
        -m|--message)
            (($# >= 2)) || { usage; exit 2; }
            message="$2"
            shift 2
            ;;
        --patch)
            (($# >= 2)) || { usage; exit 2; }
            patch_file="$2"
            shift 2
            ;;
        --base-blob)
            (($# >= 2)) || { usage; exit 2; }
            base_blob="$2"
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
if [[ -n "$patch_file" || -n "$base_blob" ]]; then
    [[ -n "$patch_file" && -n "$base_blob" ]] \
        || { echo "BLOCK: --patch and --base-blob must be used together" >&2; exit 2; }
    (($# == 1)) \
        || { echo "BLOCK: patch mode requires exactly one scope path" >&2; exit 2; }
    [[ "$base_blob" =~ ^[0-9a-f]{40}$ ]] \
        || { echo "BLOCK: --base-blob must be a full 40-hex object id" >&2; exit 2; }
fi

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
    if [[ -z "$patch_file" ]]; then
        [[ -e "$normalized" || -L "$normalized" ]] \
            || { echo "BLOCK: scope path does not exist: $normalized" >&2; exit 2; }
        [[ -n "$(git status --porcelain -- "$normalized")" ]] \
            || { echo "BLOCK: scope path has no changes: $normalized" >&2; exit 2; }
    fi
    paths+=("$normalized")
done

# 同一pathに複数agentのhunkが混在する場合の非対話入口。共有index/working treeを
# sourceにせず、HEADから作った専用indexへ明示patchだけを適用してcommitする。
# --base-blobはpatch作成時の基準を固定し、古いpatchの誤適用を事前BLOCKする。
if [[ -n "$patch_file" ]]; then
    [[ -f "$patch_file" && -s "$patch_file" ]] \
        || { echo "BLOCK: patch is missing or empty: $patch_file" >&2; exit 2; }
    patch_file="$(cd "$(dirname "$patch_file")" && pwd)/$(basename "$patch_file")"
    scope_path="${paths[0]}"
    if git cat-file -e "HEAD:$scope_path" 2>/dev/null; then
        head_blob="$(git rev-parse "HEAD:$scope_path")"
    else
        head_blob="0000000000000000000000000000000000000000"
    fi
    [[ "$head_blob" == "$base_blob" ]] \
        || { echo "BLOCK: base blob mismatch for $scope_path (expected $base_blob, HEAD has $head_blob)" >&2; exit 2; }
    shared_index_blob="$(git ls-files -s -- "$scope_path" | awk 'NR==1 {print $2}')"
    [[ "${shared_index_blob:-0000000000000000000000000000000000000000}" == "$head_blob" ]] \
        || { echo "BLOCK: scope path already has staged content in shared index: $scope_path" >&2; exit 2; }

    mapfile -t patch_paths < <(git apply --numstat -- "$patch_file" 2>/dev/null | awk '{print $3}')
    ((${#patch_paths[@]} > 0)) \
        || { echo "BLOCK: patch has no applicable file changes" >&2; exit 2; }
    for patch_path in "${patch_paths[@]}"; do
        [[ "$patch_path" == "$scope_path" ]] \
            || { echo "BLOCK: patch contains out-of-scope path: $patch_path" >&2; exit 2; }
    done

    temp_index="$(mktemp "${TMPDIR:-/tmp}/ninja-scope-index.XXXXXX")"
    rm -f "$temp_index"
    cleanup_patch_index() { rm -f "$temp_index" "$temp_index.lock"; }
    trap cleanup_patch_index EXIT
    export GIT_INDEX_FILE="$temp_index"
    git read-tree HEAD
    git apply --cached --check -- "$patch_file" \
        || { echo "BLOCK: patch does not apply cleanly to the declared base" >&2; exit 2; }
    git apply --cached -- "$patch_file"
    [[ -n "$(git diff --cached --name-only)" ]] \
        || { echo "BLOCK: patch produced an empty index diff" >&2; exit 2; }
    [[ "$(git diff --cached --name-only)" == "$scope_path" ]] \
        || { echo "BLOCK: patch polluted temporary index scope" >&2; exit 2; }
    git commit -m "$message"
    # HEAD更新後、共有indexの対象pathだけを新HEADへ追随させる。他pathのstageは
    # 一切変更せず、対象pathが旧HEAD由来の逆差分として残るindex汚染を防ぐ。
    unset GIT_INDEX_FILE
    if git cat-file -e "HEAD:$scope_path" 2>/dev/null; then
        new_blob="$(git rev-parse "HEAD:$scope_path")"
        new_mode="$(git ls-tree HEAD -- "$scope_path" | awk 'NR==1 {print $1}')"
        git update-index --add --cacheinfo "$new_mode,$new_blob,$scope_path"
    else
        git update-index --force-remove -- "$scope_path"
    fi
    git rev-parse HEAD
    exit 0
fi

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
# GA-222と同じ理由(script冒頭コメント参照): 呼び出し時のcwdは対象repo
# ($repo_root、DM-Signal等)になり得るため、"$repo_root/../multi-agent-shogun"の
# 相対推測や"/mnt/c/tools/multi-agent-shogun"のWSL2固定パスはCI runner等の
# 別環境で解決に失敗しguardが無言でno-opになる。このscript自身の設置場所
# (NINJA_SCOPE_COMMIT_SCRIPT_DIR)は常にmulti-agent-shogun/scripts/を指すため
# それを基準にguardを解決する。
if [[ -f "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/dm_signal_research_reflux_guard.sh" ]]; then
    bash "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/dm_signal_research_reflux_guard.sh" check --repo "$repo_root"
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
