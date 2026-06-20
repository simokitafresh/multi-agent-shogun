#!/usr/bin/env bash
# repo_root.sh — リポジトリルートパスの一元管理ライブラリ
# git rev-parse --show-toplevel を使い、SSOT としてリポジトリ絶対パスを提供する。
#
# Usage: source scripts/lib/repo_root.sh
#
# API:
#   get_repo_root  → リポジトリのルート絶対パスを返す (失敗時は exit 1 + stderr)
#
# 設計方針:
#   - git サブコマンドで実際のリポジトリ状態から取得する(設定値ハードコード禁止)
#   - Include guard により同一プロセス内で複数 source しても git を 1 回だけ呼ぶ

# Include guard
[[ -n "${_REPO_ROOT_LOADED:-}" ]] && return 0
_REPO_ROOT_LOADED=1

_REPO_ROOT_CACHE=""

get_repo_root() {
    if [[ -n "$_REPO_ROOT_CACHE" ]]; then
        echo "$_REPO_ROOT_CACHE"
        return 0
    fi

    local root
    if ! root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
        echo "get_repo_root: git rev-parse --show-toplevel failed. Not inside a git repository?" >&2
        return 1
    fi

    _REPO_ROOT_CACHE="$root"
    echo "$root"
}
