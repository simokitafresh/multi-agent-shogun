#!/usr/bin/env bash
# Atomically merge one completed run's 14-column timing rows into the ledger.
set -euo pipefail

LEDGER="${TEST_TIMING_LEDGER:-$(cd "$(dirname "$0")/.." && pwd)/logs/test_timing_ledger.tsv}"
BATCH="${1:?usage: test_timing_ledger_write.sh BATCH_TSV}"
HEADER=$'run_id\trepo\tcommit_sha\tsuite_root\trunner\ttest_file\ttest_id_count\twall_sec\tstatus\tskip_count\tcache_hit\tsource_fingerprint\tmeasured_at\tresource_tags'

[ -s "$BATCH" ] || exit 0
mkdir -p "$(dirname "$LEDGER")"
exec 9>"${LEDGER}.lock"
flock 9
tmp="$(mktemp "${LEDGER}.tmp.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$HEADER" >"$tmp"
if [ -f "$LEDGER" ] && IFS= read -r current_header <"$LEDGER" && [ "$current_header" = "$HEADER" ]; then
  tail -n +2 "$LEDGER" >>"$tmp"
fi
cat "$BATCH" >>"$tmp"
mv -f "$tmp" "$LEDGER"
trap - EXIT
