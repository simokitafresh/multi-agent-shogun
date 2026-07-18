#!/usr/bin/env bash
set -u

usage() {
    cat <<'EOF'
Usage: benchmark_full_deploy_e2e.sh --project DIR --runner CMD --output FILE [--runs 6] [--cold-runs 3]

RUNNER is invoked as: CMD <cold|warm> <run-number> <telemetry-file>.
It must append exactly one inbox message, create exactly one report, create no
stale archive, and append telemetry containing phase=, cache=, subprocess=.
The harness writes one durable TSV row per run and a SUMMARY row. Example:
  bash scripts/benchmark_full_deploy_e2e.sh --project "$TEST_PROJECT" \
    --runner "$BATS_TEST_DIRNAME/fixtures/fake_full_deploy.sh" --output "$BATS_TEST_TMPDIR/n6.tsv"
EOF
}

project="" runner="" output="" runs=6 cold_runs=3
while (($#)); do
    case "$1" in
        --project) project=$2; shift 2 ;;
        --runner) runner=$2; shift 2 ;;
        --output) output=$2; shift 2 ;;
        --runs) runs=$2; shift 2 ;;
        --cold-runs) cold_runs=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "BLOCK: unknown argument: $1" >&2; exit 2 ;;
    esac
done

for path in "$project/queue/tasks" "$project/queue/inbox" "$project/queue/reports" \
    "$project/archive/reports" "$project/logs/gates.log"; do
    [ -e "$path" ] || { echo "BLOCK: missing fixture: $path" >&2; exit 2; }
done
[ -n "$runner" ] && [ -x "$runner" ] || { echo "BLOCK: runner missing or not executable" >&2; exit 2; }
[[ "$runs" =~ ^[1-9][0-9]*$ && "$cold_runs" =~ ^[0-9]+$ && "$cold_runs" -le "$runs" ]] || exit 2
mkdir -p "$(dirname "$output")"
printf 'run\tmode\twall_ms\tphase\tcache\tsubprocess\trc\tinbox_delta\treport_delta\tstale_archive\tresult\n' > "$output"

count_files() { find "$1" -maxdepth 1 -type f -printf . 2>/dev/null | wc -c; }
count_messages() { awk '/^[[:space:]]*-?[[:space:]]*id:/{n++} END{print n+0}' "$project/queue/inbox/"*.yaml 2>/dev/null; }
walls=() failures=0 lost=0 duplicate=0
for ((i=1; i<=runs; i++)); do
    mode=warm; ((i <= cold_runs)) && mode=cold
    telemetry="$output.run${i}.telemetry"
    : > "$telemetry"
    inbox_before=$(count_messages); reports_before=$(count_files "$project/queue/reports")
    archive_before=$(count_files "$project/archive/reports")
    start=$(date +%s%N)
    PROJECT_ROOT="$project" "$runner" "$mode" "$i" "$telemetry"; rc=$?
    end=$(date +%s%N); wall_ms=$(((end-start)/1000000)); walls+=("$wall_ms")
    inbox_after=$(count_messages); reports_after=$(count_files "$project/queue/reports")
    archive_after=$(count_files "$project/archive/reports")
    inbox_delta=$((inbox_after-inbox_before)); report_delta=$((reports_after-reports_before))
    stale=$((archive_after-archive_before)); phase=0 cache=0 subprocess=0
    grep -q 'phase=' "$telemetry" && phase=1
    grep -q 'cache=' "$telemetry" && cache=1
    grep -q 'subprocess=' "$telemetry" && subprocess=1
    result=PASS
    if ((rc != 0 || inbox_delta != 1 || report_delta != 1 || stale != 0 || phase != 1 || cache != 1 || subprocess != 1)); then
        result=FAIL; ((failures++)); ((inbox_delta < 1 || report_delta < 1)) && ((lost++));
        ((inbox_delta > 1 || report_delta > 1)) && ((duplicate++))
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$i" "$mode" "$wall_ms" "$phase" "$cache" "$subprocess" "$rc" \
        "$inbox_delta" "$report_delta" "$stale" "$result" >> "$output"
done

sorted=$(printf '%s\n' "${walls[@]}" | sort -n)
percentile() { local n=$1 pct=$2 rank; rank=$(((n*pct+99)/100)); ((rank < 1)) && rank=1; sed -n "${rank}p" <<< "$sorted"; }
p50=$(percentile "$runs" 50); p95=$(percentile "$runs" 95)
summary=PASS
((p50 < 30000 && p95 < 60000 && failures == 0 && lost == 0 && duplicate == 0)) || summary=FAIL
printf 'SUMMARY\tN%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$runs" "$p50" "$p95" 0 0 0 "$failures" "$lost" "$duplicate" "$summary" >> "$output"
[[ "$summary" == PASS ]]
