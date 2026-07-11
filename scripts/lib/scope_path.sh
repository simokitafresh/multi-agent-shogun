#!/usr/bin/env bash
# scope_path.sh — SSOT for repo-relative commit-scope path normalization
#
# GA-222: ninja_scope_commit.sh と sync_git_hooks.sh は「このpathはcommit
# scope内か」を判定するために同じ正規化ロジックを独自に持っていたが、
# duplicateしたまま何度も個別修正した結果、片方だけ直して片方が取り残される
# (=同じ穴が別の場所/別のpath表現で再発する)ことが3回連続で発生した
# (directory scope未対応→末尾"/."未対応→root scope"."迂回→"subdir/.."や
# ".."やdouble slash等の残存)。正規化はこのファイル1箇所のみで行い、
# 両scriptはこのhelperだけを呼ぶ。
#
# 正規化はcomponent単位で行う(文字列パターンの積み重ねではない):
#   - "/"でsplitし、空component(連続slash "//"、先頭/末尾slash)と
#     "."component(カレントディレクトリ、"./"や"/./"や末尾"/.") を除去
#   - ".."componentは出現位置を問わずfail-closed(例: "subdir/.."も
#     単独の".."もrepository外/rootへ抜ける経路として一律BLOCK)
#   - componentが1つも残らない(=repository root相当)場合もfail-closed
#   - 絶対path("/"始まり)は最初からfail-closed
#
# Usage:
#   source scripts/lib/scope_path.sh
#   normalized="$(scope_path_normalize "$path")" || exit <code>
#   # 成功時: 正規化されたrepo相対path(先頭/末尾slashなし、"."/".."component無し)を
#   #         stdoutへ出力しreturn 0。
#   # 失敗時: 何も出力せずreasonをstderrへ書きreturn 1。呼び出し側で
#   #         reasonをそのままBLOCKメッセージに含めてよい。

scope_path_normalize() {
    local input="$1" remaining part
    local -a components=()

    [[ -n "$input" ]] || { echo "scope path is empty" >&2; return 1; }
    [[ "$input" != /* ]] || { echo "scope path must be repo-relative, not absolute: $input" >&2; return 1; }

    remaining="$input"
    while [[ -n "$remaining" ]]; do
        if [[ "$remaining" == */* ]]; then
            part="${remaining%%/*}"
            remaining="${remaining#*/}"
        else
            part="$remaining"
            remaining=""
        fi
        [[ -z "$part" || "$part" == "." ]] && continue
        if [[ "$part" == ".." ]]; then
            echo "scope path must stay inside repository (contains '..' component): $input" >&2
            return 1
        fi
        components+=("$part")
    done

    ((${#components[@]} > 0)) \
        || { echo "scope path resolves to repository root, which is not allowed: $input" >&2; return 1; }

    local joined="" c
    for c in "${components[@]}"; do
        if [[ -z "$joined" ]]; then joined="$c"; else joined="$joined/$c"; fi
    done
    printf '%s' "$joined"
}

# scope_path_is_in_scope <target> <scope_path...>
# targetがscope_path群のいずれかと完全一致、またはいずれかのdirectory配下に
# あるかを判定する。呼び出し側はtarget/scope_path双方を事前にnormalize済みで
# 渡す必要がある想定だが、堅牢性のためここでも正規化してから比較する
# (正規化に失敗するscope_pathは単に「一致しない」として扱う=fail-closed)。
scope_path_is_in_scope() {
    local target="$1"
    shift
    local target_norm p norm

    target_norm="$(scope_path_normalize "$target" 2>/dev/null)" || return 1

    for p in "$@"; do
        norm="$(scope_path_normalize "$p" 2>/dev/null)" || continue
        [[ "$norm" == "$target_norm" || "$target_norm" == "$norm"/* ]] && return 0
    done
    return 1
}
