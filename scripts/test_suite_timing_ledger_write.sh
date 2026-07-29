#!/usr/bin/env bash
# Append one completed suite measurement with wall and summed-file units explicit.
set -euo pipefail
LEDGER="${TEST_SUITE_TIMING_LEDGER:-$(cd "$(dirname "$0")/.." && pwd)/logs/test_suite_timing_ledger.tsv}"
BATCH="${1:?usage: test_suite_timing_ledger_write.sh BATCH_TSV}"
HEADER=$'run_id\trepo\tcommit_sha\tmode\tsuite_wall_sec\tsum_file_sec\tfile_count\tstatus\tsource_fingerprint\tmeasured_at\toutput_sha256'
if [ "${1:-}" = "--pair" ]; then
  FILE_BATCH="${2:?file batch}"; SUITE_BATCH="${3:?suite batch}"; OUTPUT_SHA="${4:?output sha}"
  FILE_LEDGER="${TEST_TIMING_LEDGER:-$(cd "$(dirname "$0")/.." && pwd)/logs/test_timing_ledger.tsv}"
  FILE_HEADER=$'run_id\trepo\tcommit_sha\tsuite_root\trunner\ttest_file\ttest_id_count\twall_sec\tstatus\tskip_count\tcache_hit\tsource_fingerprint\tmeasured_at\tresource_tags\toutput_sha256'
  [[ "$OUTPUT_SHA" =~ ^[0-9a-f]{64}$ ]] || { echo "BLOCK: invalid output_sha256" >&2; exit 2; }
  [ -s "$FILE_BATCH" ] && [ -s "$SUITE_BATCH" ] \
    || { echo "BLOCK: paired timing batches must both exist" >&2; exit 2; }
  mkdir -p "$(dirname "$FILE_LEDGER")" "$(dirname "$LEDGER")"
  exec 8>"${FILE_LEDGER}.lock"; exec 9>"${LEDGER}.lock"; flock 8; flock 9
  file_tmp="$(mktemp "${FILE_LEDGER}.tmp.XXXXXX")"
  suite_tmp="$(mktemp "${LEDGER}.tmp.XXXXXX")"
  trap 'rm -f "$file_tmp" "$suite_tmp"' EXIT
  printf '%s\n' "$FILE_HEADER" >"$file_tmp"
  if [ -f "$FILE_LEDGER" ] && IFS= read -r current <"$FILE_LEDGER"; then
    if [ "$current" = "$FILE_HEADER" ]; then
      tail -n +2 "$FILE_LEDGER" >>"$file_tmp"
    elif [ "$current" = "${FILE_HEADER%$'\toutput_sha256'}" ]; then
      tail -n +2 "$FILE_LEDGER" | awk 'BEGIN{OFS="\t"} {$15=""; print}' >>"$file_tmp"
    else
      echo "BLOCK: unknown per-file timing ledger schema" >&2; exit 2
    fi
  fi
  awk -v sha="$OUTPUT_SHA" 'BEGIN{OFS="\t"} {$15=sha; print}' "$FILE_BATCH" >>"$file_tmp"
  printf '%s\n' "$HEADER" >"$suite_tmp"
  if [ -f "$LEDGER" ] && IFS= read -r current <"$LEDGER"; then
    if [ "$current" = "$HEADER" ]; then
      tail -n +2 "$LEDGER" >>"$suite_tmp"
    elif [ "$current" = "${HEADER%$'\toutput_sha256'}" ]; then
      tail -n +2 "$LEDGER" | awk 'BEGIN{OFS="\t"} {$11=""; print}' >>"$suite_tmp"
    else
      echo "BLOCK: unknown suite timing ledger schema" >&2; exit 2
    fi
  fi
  awk -v sha="$OUTPUT_SHA" 'BEGIN{OFS="\t"} {$11=sha; print}' "$SUITE_BATCH" >>"$suite_tmp"
  mv -f "$file_tmp" "$FILE_LEDGER"
  mv -f "$suite_tmp" "$LEDGER"
  trap - EXIT
  exit 0
fi
[ -s "$BATCH" ] || exit 0
awk -F '\t' 'NF != 11 || $5 !~ /^[0-9]+([.][0-9]+)?$/ || $6 !~ /^[0-9]+([.][0-9]+)?$/ {exit 2}' "$BATCH" || {
  echo "BLOCK: suite timing row requires distinct numeric suite_wall_sec and sum_file_sec columns" >&2; exit 2;
}
mkdir -p "$(dirname "$LEDGER")"
exec 9>"${LEDGER}.lock"; flock 9
tmp="$(mktemp "${LEDGER}.tmp.XXXXXX")"; trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$HEADER" >"$tmp"
if [ -f "$LEDGER" ] && IFS= read -r current <"$LEDGER" && [ "$current" = "$HEADER" ]; then tail -n +2 "$LEDGER" >>"$tmp"; fi
cat "$BATCH" >>"$tmp"; mv -f "$tmp" "$LEDGER"; trap - EXIT
