#!/usr/bin/env bash
# project_path.sh — プロジェクトパスの一元管理ライブラリ
# config/projects.yaml を SSOT として、project id からパスを返す。
#
# Usage: source scripts/lib/project_path.sh
#
# API:
#   get_project_path <project_id>  → config/projects.yaml の projects[].path を返す
#                                    見つからない場合は exit 1 + stderr
#
# 依存: scripts/lib/repo_root.sh (get_repo_root)
# 設計方針:
#   - yq 不要。awk で YAML をパース(yq は環境依存)
#   - Include guard により同一プロセス内で複数 source しても安全

# Include guard
[[ -n "${_PROJECT_PATH_LOADED:-}" ]] && return 0
_PROJECT_PATH_LOADED=1

# repo_root.sh を自動ロード(未ロードの場合)
if [[ -z "${_REPO_ROOT_LOADED:-}" ]]; then
    _pp_self="${BASH_SOURCE[0]}"
    [[ "$_pp_self" != /* ]] && _pp_self="$PWD/$_pp_self"
    _pp_lib_dir="${_pp_self%/project_path.sh}"
    # shellcheck source=scripts/lib/repo_root.sh
    source "${_pp_lib_dir}/repo_root.sh"
fi

get_project_path() {
    local project_id="$1"
    if [[ -z "$project_id" ]]; then
        echo "get_project_path: project_id is required" >&2
        return 1
    fi

    local repo_root
    repo_root="$(get_repo_root)" || return 1

    local projects_yaml="${repo_root}/config/projects.yaml"
    if [[ ! -f "$projects_yaml" ]]; then
        echo "get_project_path: config/projects.yaml not found at ${projects_yaml}" >&2
        return 1
    fi

    # awk で projects リストをパース:
    #   - "- id: <id>" で現在エントリの id を設定
    #   - "  path: <path>" で現在エントリのパスを設定
    #   - id が一致した後に path が見つかれば出力して終了
    local result
    result=$(awk -v target="$project_id" '
        /^[[:space:]]*-[[:space:]]+id:[[:space:]]+/ {
            cur_id = $0
            sub(/.*id:[[:space:]]+/, "", cur_id)
            gsub(/[[:space:]]+$/, "", cur_id)
            cur_path = ""
            next
        }
        cur_id == target && /^[[:space:]]+path:[[:space:]]+/ {
            val = $0
            sub(/.*path:[[:space:]]+/, "", val)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
            gsub(/"/, "", val)
            if (val != "") {
                print val
                exit 0
            }
        }
    ' "$projects_yaml")

    if [[ -z "$result" ]]; then
        echo "get_project_path: project '${project_id}' not found in ${projects_yaml}" >&2
        return 1
    fi

    echo "$result"
}
