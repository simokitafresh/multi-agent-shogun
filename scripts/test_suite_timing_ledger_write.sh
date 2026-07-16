#!/usr/bin/env bash
# Append one completed suite measurement with wall and summed-file units explicit.
set -euo pipefail
LEDGER="${TEST_SUITE_TIMING_LEDGER:-$(cd "$(dirname "$0")/.." && pwd)/logs/test_suite_timing_ledger.tsv}"
BATCH="${1:?usage: test_suite_timing_ledger_write.sh BATCH_TSV}"
HEADER=$'run_id\trepo\tcommit_sha\tmode\tsuite_wall_sec\tsum_file_sec\tfile_count\tstatus\tsource_fingerprint\tmeasured_at'
[ -s "$BATCH" ] || exit 0
awk -F '\t' 'NF != 10 || $5 !~ /^[0-9]+([.][0-9]+)?$/ || $6 !~ /^[0-9]+([.][0-9]+)?$/ {exit 2}' "$BATCH" || {
  echo "BLOCK: suite timing row requires distinct numeric suite_wall_sec and sum_file_sec columns" >&2; exit 2;
}
mkdir -p "$(dirname "$LEDGER")"
exec 9>"${LEDGER}.lock"; flock 9
tmp="$(mktemp "${LEDGER}.tmp.XXXXXX")"; trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$HEADER" >"$tmp"
if [ -f "$LEDGER" ] && IFS= read -r current <"$LEDGER" && [ "$current" = "$HEADER" ]; then tail -n +2 "$LEDGER" >>"$tmp"; fi
cat "$BATCH" >>"$tmp"; mv -f "$tmp" "$LEDGER"; trap - EXIT
