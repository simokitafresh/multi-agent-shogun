#!/usr/bin/env bash
set -euo pipefail

root="${1:-docs/research}"
commit_id="${GIST_RECONCILE_COMMIT:-HEAD}"
writer="$(dirname "${BASH_SOURCE[0]}")/gist_verified_write.sh"
log_path="${GIST_SYNC_LOG:-logs/gist_sync_verified.jsonl}"
die() { printf 'BLOCK: gist master reconcile: %s\n' "$*" >&2; exit 1; }
[ -d "$root" ] || die "root is not a readable directory: $root"
[ -r "$log_path" ] || die "sync log is missing or unreadable: $log_path"
jq -e -s 'all(.[]; type == "object")' "$log_path" >/dev/null 2>&1 || die "sync log is invalid JSONL: $log_path"

masters_file="$(mktemp)"
trap 'rm -f "$masters_file"' EXIT
rg_rc=0
rg -l '^<!-- gist-master: [0-9A-Fa-f]+( [^[:space:]]+)? -->$' "$root" -g '*.md' > "$masters_file" || rg_rc=$?
[ "$rg_rc" -le 1 ] || die "master scan failed with rc=$rg_rc: $root"
mapfile -t masters < <(sort "$masters_file")
pass=0; fail=0; skip=0
for path in "${masters[@]}"; do
    if bash "$writer" --master "$path" --commit "$commit_id"; then pass=$((pass+1)); else fail=$((fail+1)); fi
done
pending="$(jq -rs 'sort_by([.gist_id,.filename,.timestamp]) | [group_by([.gist_id,.filename])[] | last | select(.status=="pending")] | length' "$log_path")" \
    || die "sync log pending calculation failed: $log_path"
printf 'RECONCILE total=%d pass=%d fail=%d skip=%d pending=%s\n' "${#masters[@]}" "$pass" "$fail" "$skip" "$pending"
[ "$fail" -eq 0 ] && [ "$pending" -eq 0 ]
