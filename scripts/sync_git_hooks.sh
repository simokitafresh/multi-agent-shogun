#!/usr/bin/env bash
# sync_git_hooks.sh — 実際にgitが発火するhook(git rev-parse --git-path hooks/<name>)を
# 常にtracked正本(scripts/hooks/*.sh)のcommit済み内容と一致させる。
#
# GA-222: scripts/hooks/git-pre-commit.sh は正本としてgit管理下にあるが、
# 実際にgitが発火するhookファイルはgit管理外(直接配置)であり、正本を修正しても
# 自動反映されない。放置すると正本側の修正が何日も実際の挙動に反映されない
# (2026-06-20設置のまま2026-07-11まで21日・3コミット分drift、BLOCK15件蓄積)。
#
# GA-222レビュー指摘(2026-07-11 karo REQUEST_CHANGES)への対応:
#  (1) 配備元をworking treeの直接catから「git blob」へ変更。--scope-pathで明示された
#      path(=呼び出し元がまさに今からcommitしようとしているpath)だけindex(staged)の
#      blobを使い、それ以外はHEAD(直近commit済み)のblobを使う。これにより他agentの
#      working-tree-onlyの未commit編集や、未staged/staged問わず「今回のcommit scope外」
#      の変更が絶対にlive hookへ混入しない。
#  (2) 配備先pathをrepo_root/.git/hooks固定でなく `git rev-parse --git-path hooks/<name>`
#      で解決し、git worktree配下でも正しい共有hooksディレクトリを指す。
#  (3) 書込みはtmpファイルへ書く→chmod +x成功を確認→atomic mvの順で行い、
#      途中失敗でlive hookが不完全な状態(truncate)になることを防ぐ。chmod失敗は
#      握りつぶさずfail-closedする。
#  (4) 正本(source_rel)がHEADに存在しない場合、「scripts/hooks/」というtracked
#      ディレクトリ自体がHEADに存在するなら、このrepoは本方式の管理対象であり
#      個別ファイルの消失は異常事態としてfail-closedする。scripts/hooks/自体が
#      HEADに存在しない場合のみ「本方式を使わないrepo」としてno-opする。
#
# GA-222 followupレビュー指摘(2026-07-11 karo 2回目REQUEST_CHANGES)への対応:
#  (5) is_in_scopeが完全一致のみだと、ninja_scope_commit.shがdirectory scope
#      (例: -- scripts/hooks)で呼ばれた場合にscripts/hooks/git-pre-commit.sh
#      自身がgit addされてcommitされるのにsync側はscope外と誤判定しHEAD版を
#      配備してしまい、commit直後に再driftする。scope_pathがdirectoryの場合
#      その配下も含めてin-scope判定するよう修正(末尾slash正規化+"/"境界要求で
#      scripts/hook等の類似prefix誤マッチを回避)。
#
# GA-222 final edge RC(2026-07-11 karo 3回目REQUEST_CHANGES)への対応:
#  (6) scope pathの表現ゆれ(末尾"/."、内部"/./"、先頭"./")を正規化してから
#      比較しないと、`-- scripts/hooks/.`のようにgitのpathspec上は
#      `scripts/hooks`と等価な表現でも文字列比較では別物とみなされ、
#      (5)と同じ再drift問題が別表現で再発する。root scope"."自体は
#      ninja_scope_commit.sh側の入口で明示BLOCKする(sync側の責務ではない)。
#
# GA-222 4回目REQUEST_CHANGES(2026-07-11 karo)への対応:
#  (7) (6)のnormalize_rel_pathはこのファイル固有の実装で、ninja_scope_commit.sh
#      側にも別実装があり重複していた。さらに"subdir/.."や単独".."、
#      "scripts//hooks"(連続slash)等、文字列パターンの積み重ねでは閉じきれない
#      表現が残っていた。正規化・in-scope判定はscripts/lib/scope_path.sh
#      (SSOT、component単位で分解し".."を出現位置問わずfail-close)へ集約し、
#      このファイルは重複実装を持たずSSOTのみを使う。
set -euo pipefail

# このscript自身が置かれているdirectory(=multi-agent-shogunのscripts/)を
# 動的に求める。sync_git_hooks.shはDM-Signal等、別repoを対象に呼ばれる
# ことがあるため($repo_rootはそちらのrepo rootになる)、SSOT(scope_path.sh)
# は「操作対象repo」ではなく「このscript自身の設置場所」基準で解決する。
_sync_git_hooks_self="${BASH_SOURCE[0]:-$0}"
[[ "$_sync_git_hooks_self" = /* ]] || _sync_git_hooks_self="$PWD/$_sync_git_hooks_self"
SYNC_GIT_HOOKS_SCRIPT_DIR="$(cd "$(dirname "$_sync_git_hooks_self")" && pwd)"
unset _sync_git_hooks_self

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "BLOCK: not inside a git repository" >&2; exit 1; }

# shellcheck source=scripts/lib/scope_path.sh
source "$SYNC_GIT_HOOKS_SCRIPT_DIR/lib/scope_path.sh"

# "<hook名>:<正本の repo-root 相対path>" のペア。
HOOK_MANIFEST=(
    "pre-commit:scripts/hooks/git-pre-commit.sh"
    "pre-push:.githooks/pre-push"
)

scope_paths=()
while (($#)); do
    case "$1" in
        --scope-path)
            (($# >= 2)) || { echo "BLOCK: --scope-path requires a value" >&2; exit 1; }
            scope_paths+=("$2")
            shift 2
            ;;
        *)
            echo "BLOCK: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

is_in_scope() {
    # ninja_scope_commit.shはdirectory scope(例: -- scripts/hooks、
    # -- scripts/hooks/.、-- scripts//hooks)を許容し、その配下の全ファイルが
    # commit対象になる。scope_path_is_in_scope(SSOT)がcomponent単位で正規化
    # してから判定するため、pathの表現ゆれ(末尾"/."・内部"/./"・連続slash等)を
    # 気にせず判定できる。
    scope_path_is_in_scope "$1" ${scope_paths[@]+"${scope_paths[@]}"}
}

uses_hook_source_convention() {
    local source_rel="$1"
    case "$source_rel" in
        scripts/hooks/*)
            git -C "$repo_root" cat-file -e "HEAD:scripts/hooks" 2>/dev/null
            ;;
        .githooks/*)
            git -C "$repo_root" cat-file -e "HEAD:.githooks" 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

resolve_installed_path() {
    local hook_name="$1" rel
    rel="$(git -C "$repo_root" rev-parse --git-path "hooks/$hook_name" 2>/dev/null)" || return 1
    [[ "$rel" = /* ]] && printf '%s' "$rel" || printf '%s/%s' "$repo_root" "$rel"
}

sync_one_hook() {
    local hook_name="$1" source_rel="$2"
    local installed ref tmp

    if ! git -C "$repo_root" cat-file -e "HEAD:$source_rel" 2>/dev/null; then
        if uses_hook_source_convention "$source_rel"; then
            echo "BLOCK(GA-222): tracked hook source missing at HEAD: $source_rel (scripts/hooks/ convention is in use — this looks like an anomaly, not an unmanaged repo)" >&2
            return 1
        fi
        return 0   # scripts/hooks/自体が無い = 本方式を使わないrepo。対象外としてno-op。
    fi

    installed="$(resolve_installed_path "$hook_name")" \
        || { echo "BLOCK(GA-222): failed to resolve git hooks path for $hook_name" >&2; return 1; }

    if is_in_scope "$source_rel"; then
        ref=":$source_rel"       # 今回のcommitで確定させる、まさに今stageされた内容
    else
        ref="HEAD:$source_rel"   # 他者のworking tree/staged編集を信用せず、直近commit済みの内容のみ使う
    fi

    mkdir -p "$(dirname "$installed")" 2>/dev/null || true
    tmp="$(mktemp "${installed}.tmp.XXXXXX" 2>/dev/null)" \
        || { echo "BLOCK(GA-222): mktemp failed for $hook_name" >&2; return 1; }

    if ! git -C "$repo_root" show "$ref" > "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        echo "BLOCK(GA-222): failed to read $ref for $hook_name" >&2
        return 1
    fi

    if [[ -f "$installed" ]] && cmp -s "$tmp" "$installed"; then
        rm -f "$tmp"
        return 0
    fi

    if ! chmod +x "$tmp"; then
        rm -f "$tmp"
        echo "BLOCK(GA-222): chmod +x failed for $hook_name — installed hook left untouched" >&2
        return 1
    fi

    if ! mv -f "$tmp" "$installed"; then
        rm -f "$tmp"
        echo "BLOCK(GA-222): atomic install failed for $hook_name — installed hook left untouched" >&2
        return 1
    fi

    echo "SYNCED(GA-222): $installed <- $ref" >&2
    return 0
}

status=0
for entry in "${HOOK_MANIFEST[@]}"; do
    hook_name="${entry%%:*}"
    source_rel="${entry#*:}"
    sync_one_hook "$hook_name" "$source_rel" || status=1
done

exit "$status"
