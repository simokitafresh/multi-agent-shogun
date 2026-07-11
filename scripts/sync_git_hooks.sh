#!/usr/bin/env bash
# sync_git_hooks.sh — .git/hooks/配下の実行フックが正本(scripts/hooks/*.sh)と
# 常に一致するよう保証する。
#
# GA-222: scripts/hooks/git-pre-commit.sh は正本としてgit管理下にあるが、
# 実際にgitが発火する .git/hooks/pre-commit はgit管理外(直接配置)であり、
# 正本を修正しても自動反映されない。放置すると正本側の修正(例: GA-190の
# BLOCK→AUTO-FIX化)が何日も実際の挙動に反映されず、古い挙動のままBLOCKし
# 続ける(2026-06-20設置のまま2026-07-11まで21日・3コミット分drift)。
#
# 対象repoにこのスクリプトが存在しない(=本リポジトリの規約を使わない別repo/
# テストサンドボックス)場合は何もせずexit 0で抜ける。正本ファイルが存在するのに
# コピーに失敗した場合のみfail-closed(exit 1)し、.git/hooks/側は変更しない。
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "BLOCK: not inside a git repository" >&2; exit 1; }

# "<hook名>:<正本の repo-root 相対path>" のペア。
HOOK_MANIFEST=(
    "pre-commit:scripts/hooks/git-pre-commit.sh"
)

sync_one_hook() {
    local hook_name="$1" source_rel="$2"
    local source_full="$repo_root/$source_rel"
    local installed="$repo_root/.git/hooks/$hook_name"

    # 正本が存在しない = このrepoでは当該hookを本方式で管理していない。対象外としてスキップ。
    [[ -f "$source_full" ]] || return 0

    if [[ -f "$installed" ]] && cmp -s "$source_full" "$installed"; then
        return 0
    fi

    if ! cp "$source_full" "$installed" 2>/dev/null; then
        echo "BLOCK(GA-222): failed to sync .git/hooks/$hook_name from $source_rel" >&2
        return 1
    fi
    chmod +x "$installed" 2>/dev/null || true
    echo "SYNCED(GA-222): .git/hooks/$hook_name <- $source_rel" >&2
    return 0
}

status=0
for entry in "${HOOK_MANIFEST[@]}"; do
    hook_name="${entry%%:*}"
    source_rel="${entry#*:}"
    sync_one_hook "$hook_name" "$source_rel" || status=1
done

exit "$status"
