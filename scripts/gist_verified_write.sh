#!/usr/bin/env bash
set -euo pipefail

# Synchronize a committed document blob to its self-described secret Gist.
# Legacy: gist_verified_write.sh <gist-id> <remote-filename> <local-path>
# Master: gist_verified_write.sh --master <path> [--commit <commit>]

GH_CMD="${GH_CMD:-gh}"
GIST_TIMEOUT_SECONDS="${GIST_TIMEOUT_SECONDS:-20}"
GIST_SYNC_LOG="${GIST_SYNC_LOG:-logs/gist_sync_verified.jsonl}"

die() { printf 'BLOCK: gist verified write: %s\n' "$*" >&2; exit 1; }
json_log() {
    local status="$1" reason="$2"
    mkdir -p "$(dirname "$GIST_SYNC_LOG")"
    jq -cn --arg ts "$(date -u +%FT%TZ)" --arg status "$status" \
      --arg gist_id "$gist_id" --arg filename "$remote_filename" \
      --arg source "$source_path" --arg commit "$commit_id" \
      --arg blob "$blob_id" --arg sha256 "$local_sha" --arg reason "$reason" \
      '{timestamp:$ts,status:$status,gist_id:$gist_id,filename:$filename,source:$source,commit:$commit,blob:$blob,sha256:$sha256,reason:$reason}' \
      >> "$GIST_SYNC_LOG"
}
pending_die() { json_log pending "$*"; die "$*"; }
gh_bounded() { timeout --foreground "${GIST_TIMEOUT_SECONDS}s" "$GH_CMD" "$@"; }

source_path= commit_id= blob_id= gist_id= remote_filename= local_sha= master_mode=false
if [ "${1:-}" = --master ]; then
    master_mode=true
    [ "$#" -eq 2 ] || [ "$#" -eq 4 ] || die "usage: $0 --master <path> [--commit <commit>]"
    source_path="$2"; commit_id=HEAD
    if [ "$#" -eq 4 ]; then [ "$3" = --commit ] || die "expected --commit"; commit_id="$4"; fi
    git cat-file -e "${commit_id}^{commit}" 2>/dev/null || die "invalid commit: $commit_id"
    commit_id="$(git rev-parse "${commit_id}^{commit}")"
    blob_id="$(git rev-parse "${commit_id}:${source_path}" 2>/dev/null)" || die "path absent from commit: $source_path"
    content_file="$(mktemp)"; git show "${commit_id}:${source_path}" > "$content_file"
    meta="$(head -n 1 "$content_file")"
    if [[ "$meta" =~ ^\<\!--[[:space:]]gist-master:[[:space:]]([0-9A-Fa-f]+)([[:space:]]([^[:space:]]+))?[[:space:]]--\>$ ]]; then
        gist_id="${BASH_REMATCH[1]}"; remote_filename="${BASH_REMATCH[3]:-$(basename "$source_path")}" 
    else
        rm -f "$content_file"; die "invalid or missing first-line gist-master metadata: $source_path"
    fi
else
    [ "$#" -eq 3 ] || die "usage: $0 <gist-id> <remote-filename> <local-path>"
    gist_id="$1"; remote_filename="$2"; source_path="$3"; commit_id=working-tree
    [ -f "$source_path" ] || die "local path is not a regular file: $source_path"
    content_file="$source_path"; blob_id="$(git hash-object "$source_path" 2>/dev/null || true)"
fi

[[ "$gist_id" =~ ^[0-9A-Fa-f]+$ ]] || die "invalid gist id"
case "$remote_filename" in '' ) die "remote filename is empty";; */*|.|..) die "remote filename must be a filename, not a path";; esac
command -v "$GH_CMD" >/dev/null 2>&1 || die "gh command not found: $GH_CMD"
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v timeout >/dev/null 2>&1 || die "timeout is required"

payload_file="$(mktemp)"; metadata_file="$(mktemp)"; remote_file="$(mktemp)"
cleanup() { rm -f "$payload_file" "$metadata_file" "$remote_file"; [ "${content_file:-}" != "$source_path" ] && rm -f "${content_file:-}" || true; }
trap cleanup EXIT
local_sha="$(sha256sum "$content_file" | awk '{print $1}')"

lock_key="$(printf %s "$gist_id" | sha256sum | cut -c1-32)"
exec 9>"${TMPDIR:-/tmp}/gist-sync-${lock_key}.lock"
flock -w "$GIST_TIMEOUT_SECONDS" 9 || pending_die "gist lock timeout"

if [ "$commit_id" != working-tree ] && [ -f "$GIST_SYNC_LOG" ]; then
    newer="$(jq -r --arg id "$gist_id" --arg f "$remote_filename" 'select(.status=="verified" and .gist_id==$id and .filename==$f) | .commit' "$GIST_SYNC_LOG" 2>/dev/null | tail -1)"
    if [[ "$newer" =~ ^[0-9a-f]{40}$ ]] && git merge-base --is-ancestor "$commit_id" "$newer" 2>/dev/null && [ "$commit_id" != "$newer" ]; then
        json_log skipped_newer "newer commit already published: $newer"
        printf 'SKIPPED_OLDER gist=%s commit=%s newer=%s\n' "$gist_id" "$commit_id" "$newer"; exit 0
    fi
fi

if $master_mode; then
    gh_bounded api "gists/${gist_id}" > "$metadata_file" || pending_die "metadata request failed or timed out"
    owner="$(jq -er '.owner.login' "$metadata_file")" || pending_die "gist owner missing"
    viewer="$(gh_bounded api user --jq .login)" || pending_die "viewer lookup failed or timed out"
    [ "$owner" = "$viewer" ] || pending_die "owner mismatch owner=$owner viewer=$viewer"
    [ "$(jq -r '.public' "$metadata_file")" = false ] || pending_die "visibility must be secret"
    file_count="$(jq '.files | length' "$metadata_file")"
    if [ "$file_count" -gt 1 ] && [ "$remote_filename" = "$(basename "$source_path")" ] && [[ ! "$meta" =~ [[:space:]]${remote_filename}[[:space:]]--\>$ ]]; then
        pending_die "multiple-file gist requires explicit remote filename"
    fi
fi

jq -n --arg filename "$remote_filename" --rawfile content "$content_file" '{files:{($filename):{content:$content}}}' > "$payload_file"
gh_bounded api --method PATCH "gists/${gist_id}" --input "$payload_file" >/dev/null || pending_die "PATCH request failed or timed out"
gh_bounded api "gists/${gist_id}" > "$metadata_file" || pending_die "readback metadata failed or timed out"
raw_url="$(jq -er --arg f "$remote_filename" '.files[$f].raw_url' "$metadata_file")" || pending_die "remote filename missing after PATCH"
gh_bounded api "$raw_url" > "$remote_file" || pending_die "raw readback failed or timed out"
remote_sha="$(sha256sum "$remote_file" | awk '{print $1}')"
if [ "$local_sha" != "$remote_sha" ]; then
    sleep "${GIST_READBACK_RETRY_DELAY_SECONDS:-1}"
    gh_bounded api "$raw_url" > "$remote_file" || pending_die "raw retry failed or timed out"
    remote_sha="$(sha256sum "$remote_file" | awk '{print $1}')"
    [ "$local_sha" = "$remote_sha" ] || pending_die "readback SHA256 mismatch local=$local_sha remote=$remote_sha"
fi
json_log verified "remote bytes equal commit blob"
if $master_mode; then
    printf 'VERIFIED gist=%s filename=%s commit=%s blob=%s sha256=%s\n' "$gist_id" "$remote_filename" "$commit_id" "$blob_id" "$local_sha"
else
    printf 'VERIFIED gist=%s filename=%s sha256=%s\n' "$gist_id" "$remote_filename" "$local_sha"
fi
