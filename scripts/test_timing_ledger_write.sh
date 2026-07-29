#!/usr/bin/env bash
# Atomically merge one completed run's 15-column timing rows into the ledger.
set -euo pipefail

LEDGER="${TEST_TIMING_LEDGER:-$(cd "$(dirname "$0")/.." && pwd)/logs/test_timing_ledger.tsv}"
BATCH="${1:?usage: test_timing_ledger_write.sh BATCH_TSV}"
HEADER=$'run_id\trepo\tcommit_sha\tsuite_root\trunner\ttest_file\ttest_id_count\twall_sec\tstatus\tskip_count\tcache_hit\tsource_fingerprint\tmeasured_at\tresource_tags\toutput_sha256'
LEGACY_HEADER="${HEADER%$'\toutput_sha256'}"

snapshot_legacy_ledger() {
  local ledger="$1" old_hash snapshot snapshot_tmp restore_tmp
  local old_rows snapshot_rows snapshot_hash
  old_hash="$(sha256sum "$ledger" | awk '{print $1}')"
  snapshot="${ledger}.pre-schema-${old_hash}.snapshot"
  snapshot_tmp="$(mktemp "${ledger}.snapshot.tmp.XXXXXX")"
  restore_tmp="$(mktemp "${ledger}.restore-dry-run.tmp.XXXXXX")"
  if [ "${TIMING_LEDGER_SNAPSHOT_FAULT:-}" = snapshot_create ]; then
    rm -f "$snapshot_tmp" "$restore_tmp"
    echo "BLOCK: timing ledger snapshot creation failed" >&2
    return 2
  fi
  cp -- "$ledger" "$snapshot_tmp"
  [ "${TIMING_LEDGER_SNAPSHOT_FAULT:-}" != hash_mismatch ] || printf x >>"$snapshot_tmp"
  old_rows="$(tail -n +2 "$ledger" | wc -l)"
  snapshot_rows="$(tail -n +2 "$snapshot_tmp" | wc -l)"
  [ "${TIMING_LEDGER_SNAPSHOT_FAULT:-}" != row_count_mismatch ] || snapshot_rows=$((snapshot_rows + 1))
  snapshot_hash="$(sha256sum "$snapshot_tmp" | awk '{print $1}')"
  if [ "$old_rows" -ne "$snapshot_rows" ] || [ "$old_hash" != "$snapshot_hash" ]; then
    rm -f "$snapshot_tmp" "$restore_tmp"
    echo "BLOCK: timing ledger snapshot verification failed" >&2
    return 2
  fi
  cp -- "$snapshot_tmp" "$restore_tmp"
  cmp -s "$ledger" "$restore_tmp" || {
    rm -f "$snapshot_tmp" "$restore_tmp"
    echo "BLOCK: timing ledger restore dry-run failed" >&2
    return 2
  }
  mv -f "$snapshot_tmp" "$snapshot"
  rm -f "$restore_tmp"
}

[ -s "$BATCH" ] || exit 0
mkdir -p "$(dirname "$LEDGER")"
exec 9>"${LEDGER}.lock"
flock 9
tmp="$(mktemp "${LEDGER}.tmp.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$HEADER" >"$tmp"
if [ -f "$LEDGER" ] && IFS= read -r current_header <"$LEDGER"; then
  if [ "$current_header" = "$HEADER" ]; then
    tail -n +2 "$LEDGER" >>"$tmp"
  elif [ "$current_header" = "$LEGACY_HEADER" ]; then
    snapshot_legacy_ledger "$LEDGER"
    tail -n +2 "$LEDGER" | awk 'BEGIN{OFS="\t"} {$15=""; print}' >>"$tmp"
  else
    echo "BLOCK: unknown per-file timing ledger schema" >&2
    exit 2
  fi
fi
cat "$BATCH" >>"$tmp"
mv -f "$tmp" "$LEDGER"
trap - EXIT
