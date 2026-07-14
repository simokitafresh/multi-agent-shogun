#!/usr/bin/env bash
# Run one bats file directly and atomically publish its timing to the ledger.
set -euo pipefail

ROOT="${SHOGUN_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TEST_FILE="${1:?usage: run_timed_bats.sh TEST_FILE [bats args...]}"
shift
LEDGER="${TEST_TIMING_LEDGER:-$ROOT/logs/test_timing_ledger.tsv}"
batch="$(mktemp "${TMPDIR:-/tmp}/shogun-direct-bats.XXXXXX")"
output="$(mktemp "${TMPDIR:-/tmp}/shogun-direct-bats-output.XXXXXX")"
trap 'rm -f "$batch" "$output"' EXIT

started_ns="$(date +%s%N)"
set +e
bats "$@" "$TEST_FILE" >"$output" 2>&1
rc=$?
set -e
ended_ns="$(date +%s%N)"
cat "$output"

wall_sec="$(awk -v ns="$((ended_ns - started_ns))" 'BEGIN {printf "%.3f", ns/1000000000}')"
test_count="$(grep -c '^@test ' "$TEST_FILE" 2>/dev/null || true)"
skip_count="$(grep -Ec '^ok [0-9]+ .*# skip([[:space:]]|$)' "$output" 2>/dev/null || true)"
status=pass
(( rc == 0 )) || status=fail
run_id="$(date -u +%Y%m%dT%H%M%S).$$"
commit_sha="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf unknown)"
source_fingerprint="$(sha256sum "$TEST_FILE" | awk '{print $1}')"
measured_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s\t%s\t%s\tdirect\tbats\t%s\t%s\t%s\t%s\t%s\t0\t%s\t%s\tmode=direct;jobs=1\n' \
  "$run_id" "$(basename "$ROOT")" "$commit_sha" "$TEST_FILE" "$test_count" \
  "$wall_sec" "$status" "$skip_count" "$source_fingerprint" "$measured_at" >"$batch"
TEST_TIMING_LEDGER="$LEDGER" bash "$ROOT/scripts/test_timing_ledger_write.sh" "$batch"
exit "$rc"
