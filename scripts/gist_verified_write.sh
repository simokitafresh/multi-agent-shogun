#!/usr/bin/env bash
set -euo pipefail

# Update one Gist file and prove that the remote raw bytes match the local file.
# Usage: gist_verified_write.sh <gist-id> <remote-filename> <local-path>

GH_CMD="${GH_CMD:-gh}"

die() {
    printf 'BLOCK: gist verified write: %s\n' "$*" >&2
    exit 1
}

[ "$#" -eq 3 ] || die "usage: $0 <gist-id> <remote-filename> <local-path>"
gist_id="$1"
remote_filename="$2"
local_path="$3"

[[ "$gist_id" =~ ^[0-9A-Fa-f]+$ ]] || die "invalid gist id"
[ -n "$remote_filename" ] || die "remote filename is empty"
case "$remote_filename" in
    */*|.|..) die "remote filename must be a filename, not a path" ;;
esac
[ -f "$local_path" ] || die "local path is not a regular file: $local_path"
command -v "$GH_CMD" >/dev/null 2>&1 || die "gh command not found: $GH_CMD"
command -v jq >/dev/null 2>&1 || die "jq is required"

payload_file="$(mktemp)"
metadata_file="$(mktemp)"
remote_file="$(mktemp)"
trap 'rm -f "$payload_file" "$metadata_file" "$remote_file"' EXIT

jq -n --arg filename "$remote_filename" --rawfile content "$local_path" \
    '{files:{($filename):{content:$content}}}' > "$payload_file" \
    || die "failed to build PATCH payload"

"$GH_CMD" api --method PATCH "gists/${gist_id}" --input "$payload_file" >/dev/null \
    || die "PATCH request failed"

"$GH_CMD" api "gists/${gist_id}" > "$metadata_file" \
    || die "remote metadata readback failed"
raw_url="$(jq -er --arg filename "$remote_filename" \
    '.files[$filename].raw_url | select(type == "string" and length > 0)' \
    "$metadata_file")" || die "remote filename missing after PATCH: $remote_filename"

"$GH_CMD" api "$raw_url" > "$remote_file" \
    || die "remote raw readback failed"

local_sha="$(sha256sum "$local_path" | awk '{print $1}')"
remote_sha="$(sha256sum "$remote_file" | awk '{print $1}')"
if [ "$local_sha" != "$remote_sha" ]; then
    sleep "${GIST_READBACK_RETRY_DELAY_SECONDS:-1}"
    "$GH_CMD" api "$raw_url" > "$remote_file" || die "remote raw retry failed"
    remote_sha="$(sha256sum "$remote_file" | awk '{print $1}')"
    [ "$local_sha" = "$remote_sha" ] || die "readback SHA256 mismatch after retry local=$local_sha remote=$remote_sha"
fi

printf 'VERIFIED gist=%s filename=%s sha256=%s\n' \
    "$gist_id" "$remote_filename" "$local_sha"
