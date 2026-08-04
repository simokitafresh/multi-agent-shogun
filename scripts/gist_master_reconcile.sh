#!/usr/bin/env bash
set -euo pipefail

root="${1:-docs/research}"
commit_id="${GIST_RECONCILE_COMMIT:-HEAD}"
writer="$(dirname "${BASH_SOURCE[0]}")/gist_verified_write.sh"
mapfile -t masters < <(rg -l '^<!-- gist-master: [0-9A-Fa-f]+( [^[:space:]]+)? -->$' "$root" -g '*.md' | sort)
pass=0; fail=0; skip=0
for path in "${masters[@]}"; do
    if bash "$writer" --master "$path" --commit "$commit_id"; then pass=$((pass+1)); else fail=$((fail+1)); fi
done
pending="$(jq -rs '[group_by([.gist_id,.filename])[] | last | select(.status=="pending")] | length' "${GIST_SYNC_LOG:-logs/gist_sync_verified.jsonl}" 2>/dev/null || printf 0)"
printf 'RECONCILE total=%d pass=%d fail=%d skip=%d pending=%s\n' "${#masters[@]}" "$pass" "$fail" "$skip" "$pending"
[ "$fail" -eq 0 ] && [ "$pending" -eq 0 ]
