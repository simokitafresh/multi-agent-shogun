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
#      (5)と同じ再drift問題が別表現で再発する。normalize_rel_pathで
#      lexicalに正規化してからis_in_scope判定する。root scope"."自体は
#      ninja_scope_commit.sh側の入口で明示BLOCKする(sync側の責務ではない)。
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "BLOCK: not inside a git repository" >&2; exit 1; }

# "<hook名>:<正本の repo-root 相対path>" のペア。
HOOK_MANIFEST=(
    "pre-commit:scripts/hooks/git-pre-commit.sh"
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

normalize_rel_path() {
    # repo相対pathのlexical正規化: 内部"/./"を収束するまで畳み込み、
    # 末尾"/."と末尾"/"を除去し、先頭"./"を除去する。".."は正規化せず
    # そのまま残す(traversalはninja_scope_commit.sh側で既にBLOCK対象)。
    local p="$1"
    while [[ "$p" == */./* ]]; do
        p="${p/\/.\//\/}"
    done
    p="${p%/.}"
    p="${p%/}"
    p="${p#./}"
    printf '%s' "$p"
}

is_in_scope() {
    # ninja_scope_commit.shはdirectory scope(例: -- scripts/hooks、
    # -- scripts/hooks/.)を許容し、その配下の全ファイルがcommit対象になる。
    # scope_pathがdirectoryの場合、その配下のtarget(例:
    # scripts/hooks/git-pre-commit.sh)もin-scope扱いする。両者をlexical正規化
    # してから比較し、"scripts/hook"のような類似prefixを誤マッチしないよう
    # 境界に"/"を要求する(scripts/hooks/*でscripts/hooks2/*等は非マッチ)。
    local target="$1" p norm target_norm
    target_norm="$(normalize_rel_path "$target")"
    for p in ${scope_paths[@]+"${scope_paths[@]}"}; do
        norm="$(normalize_rel_path "$p")"
        [[ "$norm" == "$target_norm" || "$target_norm" == "$norm"/* ]] && return 0
    done
    return 1
}

uses_hook_source_convention() {
    git -C "$repo_root" cat-file -e "HEAD:scripts/hooks" 2>/dev/null
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
        if uses_hook_source_convention; then
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
