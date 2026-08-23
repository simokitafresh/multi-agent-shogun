#!/usr/bin/env bash
set -euo pipefail

# Intentional entry point for publishing one committed local master to a secret Gist.

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    printf 'BLOCK: gist share: not inside a git worktree\n' >&2
    exit 1
}
# helper解決: 対象repoに同名helperがあればそれを使い、無ければ本script自身のdir(正本)へfallback。
# 2026-08-23実証: DM-signal repoからの共有でcwd相対解決がhelper不在で2連BLOCKした。
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
default_writer="$repo_root/scripts/gist_verified_write.sh"
[ -x "$default_writer" ] || default_writer="$script_dir/gist_verified_write.sh"
default_indexer="$repo_root/scripts/gist_index_update.sh"
[ -x "$default_indexer" ] || default_indexer="$script_dir/gist_index_update.sh"
writer="${GIST_VERIFIED_WRITE_CMD:-$default_writer}"
indexer="${GIST_INDEX_UPDATE_CMD:-$default_indexer}"
gh_cmd="${GH_CMD:-gh}"
timeout_seconds="${GIST_TIMEOUT_SECONDS:-20}"
metadata_install_cmd="${GIST_SHARE_METADATA_INSTALL_CMD:-mv}"

die() { printf 'BLOCK: gist share: %s\n' "$*" >&2; exit 1; }
gh_bounded() { timeout --foreground "${timeout_seconds}s" "$gh_cmd" "$@"; }

[ "$#" -eq 1 ] || die "usage: $0 <repo-relative-local-master-path>"
source_path="$1"
case "$source_path" in /*|../*|*/../*|*/..|.) die "path must be repo-relative and remain inside the worktree";; esac
[ -f "$repo_root/$source_path" ] || die "local master is not a regular file: $source_path"
git -C "$repo_root" ls-files --error-unmatch -- "$source_path" >/dev/null 2>&1 || die "local master must be tracked: $source_path"
git -C "$repo_root" cat-file -e "HEAD:$source_path" 2>/dev/null || die "local master is absent from HEAD: $source_path"
git -C "$repo_root" diff --quiet -- "$source_path" || die "local master differs from HEAD; commit it first: $source_path"
git -C "$repo_root" diff --cached --quiet -- "$source_path" || die "local master has staged changes; commit it first: $source_path"

first_line="$(head -n 1 "$repo_root/$source_path")"
if [[ "$first_line" =~ ^\<\!--[[:space:]]gist-master:[[:space:]]([0-9A-Fa-f]+)([[:space:]]([^[:space:]]+))?[[:space:]]--\>$ ]]; then
    gist_id="${BASH_REMATCH[1]}"
    remote_filename="${BASH_REMATCH[3]:-$(basename "$source_path")}" 
    writer_output="$(cd "$repo_root" && GH_CMD="$gh_cmd" GIST_TIMEOUT_SECONDS="$timeout_seconds" bash "$writer" --master "$source_path")" || die "verified synchronization failed"
    local_sha="$(git -C "$repo_root" show "HEAD:$source_path" | sha256sum | awk '{print $1}')"
    printf '%s\n' "$writer_output"
    grep -Fq "sha256=$local_sha" <<< "$writer_output" || die "verified writer did not return the local commit-blob hash"
    (cd "$repo_root" && GH_CMD="$gh_cmd" GIST_TIMEOUT_SECONDS="$timeout_seconds" bash "$indexer") || die "gist index update failed after verified synchronization"
    printf 'GIST_SHARED url=https://gist.github.com/%s sha256_local=%s sha256_remote=%s filename=%s\n' \
        "$gist_id" "$local_sha" "$local_sha" "$remote_filename"
    exit 0
fi

command -v "$gh_cmd" >/dev/null 2>&1 || die "gh command not found: $gh_cmd"
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v timeout >/dev/null 2>&1 || die "timeout is required"

title="$(basename "$source_path")"

# --- duplicate detection + auto-repair (2026-08-06): gist-masterコメント欠落時に既存gistを自動検出し修復 ---
# gh gist list失敗時(ネットワーク障害等)は空文字=fallthrough(新規作成)
existing_gist_id="$( { gh_bounded gist list --limit 100 2>/dev/null || true; } | awk -v t="$title" '$2 == t {print $1; exit}' )"
if [ -n "$existing_gist_id" ]; then
    printf '[gist_share] auto-repair: found existing gist %s for %s — inserting gist-master comment\n' "$existing_gist_id" "$title" >&2
    repair_tmp="$(mktemp "$(dirname "$repo_root/$source_path")/.gist-repair.XXXXXX")"
    { printf '<!-- gist-master: %s %s -->\n' "$existing_gist_id" "$title"; cat "$repo_root/$source_path"; } > "$repair_tmp"
    chmod --reference="$repo_root/$source_path" "$repair_tmp"
    mv "$repair_tmp" "$repo_root/$source_path"
    printf 'GIST_REPAIRED_PENDING_COMMIT gist_id=%s title=%s next="commit %s, then rerun gist-share"\n' \
        "$existing_gist_id" "$title" "$source_path" >&2
    exit 2
fi
# 根治(2026-08-07殿指摘): gist-masterなし+既存gist検出失敗時の新規作成を禁止。
# 新規作成は作成日が今日になり永久に取り返しがつかない。
# 明示的に --allow-create フラグが渡された場合のみ新規作成を許可する。
if [ "${GIST_ALLOW_CREATE:-}" != "1" ]; then
    die "BLOCK: gist-masterコメントなし+既存gist未検出。新規作成は作成日が変わり取り返しがつかない。意図的な新規作成なら GIST_ALLOW_CREATE=1 を付けて再実行せよ"
fi
content_sha="$(git -C "$repo_root" show "HEAD:$source_path" | sha256sum | awk '{print $1}')"
payload="$(mktemp)"
response="$(mktemp)"
cleanup() { rm -f "$payload" "$response" "${replacement:-}"; }
trap cleanup EXIT
jq -n --arg filename "$title" --rawfile content <(git -C "$repo_root" show "HEAD:$source_path") \
    --arg description "$title" '{description:$description,public:false,files:{($filename):{content:$content}}}' > "$payload"

if ! gh_bounded api --method POST gists --input "$payload" > "$response"; then
    die "secret gist create failed title=$title content_sha256=$content_sha"
fi
gist_id="$(jq -er '.id | select(type=="string" and test("^[0-9A-Fa-f]+$"))' "$response" 2>/dev/null)" || \
    die "secret gist created but response ID is invalid; orphan_candidate title=$title content_sha256=$content_sha response=$(tr '\n' ' ' < "$response")"
[ "$(jq -r '.public' "$response")" = false ] || die "created gist is not secret; orphan_candidate gist_id=$gist_id title=$title content_sha256=$content_sha"

replacement="$(mktemp "$(dirname "$repo_root/$source_path")/.gist-share.XXXXXX")"
if ! { printf '<!-- gist-master: %s %s -->\n' "$gist_id" "$title"; cat "$repo_root/$source_path"; } > "$replacement"; then
    die "metadata preparation failed; orphan_candidate gist_id=$gist_id title=$title content_sha256=$content_sha"
fi
chmod --reference="$repo_root/$source_path" "$replacement"
if ! "$metadata_install_cmd" "$replacement" "$repo_root/$source_path"; then
    die "metadata atomic install failed; orphan_candidate gist_id=$gist_id title=$title content_sha256=$content_sha"
fi
replacement=""
printf 'GIST_CREATED_PENDING_COMMIT gist_id=%s url=https://gist.github.com/%s title=%s content_sha256=%s next="commit %s, then rerun gist-share"\n' \
    "$gist_id" "$gist_id" "$title" "$content_sha" "$source_path" >&2
exit 2
