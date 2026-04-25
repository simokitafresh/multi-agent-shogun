#!/usr/bin/env bash
# cdp_canary.sh — repeated CDP benchmark canary with consecutive alert detection.
#
# Usage:
#   bash scripts/cdp_canary.sh --dry-run
#   bash scripts/cdp_canary.sh --target dashboard --runs 3 --interval 60
#
# Exit code: 0=OK, 1=alert threshold reached, 2=usage/config error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BENCHMARK_SCRIPT="${CDP_BENCHMARK_SCRIPT:-${REPO_ROOT}/scripts/cdp/cdp_benchmark.sh}"

DRY_RUN=false
TARGET_FILTER=""
OVERRIDE_RUNS=""
OVERRIDE_INTERVAL=""
OVERRIDE_CONSECUTIVE=""
KEEP_GOING=false

usage() {
    cat <<'USAGE'
Usage: bash scripts/cdp_canary.sh [options]

Options:
  --dry-run                 Print the catalog and planned commands without measuring.
  --target NAME             Run only one catalog target.
  --runs N                  Override catalog run count.
  --interval SECONDS        Override catalog interval.
  --consecutive-alerts N    Override consecutive alert threshold.
  --keep-going              Continue other targets after one target alerts.
  -h, --help                Show this help.

Catalog columns:
  name|interval_seconds|runs|consecutive_alerts|benchmark arguments
USAGE
}

die() {
    echo "ERROR: $*" >&2
    exit 2
}

is_positive_int() {
    [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --target)
            TARGET_FILTER="${2:-}"
            [[ -n "$TARGET_FILTER" ]] || die "--target requires a value"
            shift 2
            ;;
        --runs)
            OVERRIDE_RUNS="${2:-}"
            is_positive_int "$OVERRIDE_RUNS" || die "--runs must be a positive integer"
            shift 2
            ;;
        --interval)
            OVERRIDE_INTERVAL="${2:-}"
            is_positive_int "$OVERRIDE_INTERVAL" || die "--interval must be a positive integer"
            shift 2
            ;;
        --consecutive-alerts)
            OVERRIDE_CONSECUTIVE="${2:-}"
            is_positive_int "$OVERRIDE_CONSECUTIVE" || die "--consecutive-alerts must be a positive integer"
            shift 2
            ;;
        --keep-going)
            KEEP_GOING=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

catalog_entries=(
    "dashboard|60|3|2|--trend -- --profile production --pages dashboard"
    "operations|300|2|2|--trend -- --profile production --pages operations"
)

print_plan() {
    local name="$1"
    local interval="$2"
    local runs="$3"
    local consecutive="$4"
    local args="$5"

    printf 'PLAN target=%s interval=%ss runs=%s consecutive_alerts=%s command=%q' \
        "$name" "$interval" "$runs" "$consecutive" "$BENCHMARK_SCRIPT"
    printf ' %s\n' "$args"
}

status_from_output() {
    local output_file="$1"
    if grep -q 'overall=REGRESSION\|regression=REGRESSION\| status=.*REGRESSION' "$output_file"; then
        echo "REGRESSION"
    elif grep -q 'overall=WARN\|regression=WARN\| status=.*WARN' "$output_file"; then
        echo "WARN"
    else
        echo "PASS"
    fi
}

run_target() {
    local entry="$1"
    local name interval runs consecutive args
    IFS='|' read -r name interval runs consecutive args <<< "$entry"

    if [[ -n "$TARGET_FILTER" && "$TARGET_FILTER" != "$name" ]]; then
        return 0
    fi

    runs="${OVERRIDE_RUNS:-$runs}"
    interval="${OVERRIDE_INTERVAL:-$interval}"
    consecutive="${OVERRIDE_CONSECUTIVE:-$consecutive}"

    print_plan "$name" "$interval" "$runs" "$consecutive" "$args"
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi

    [[ -x "$BENCHMARK_SCRIPT" ]] || die "benchmark script is not executable: $BENCHMARK_SCRIPT"

    local streak=0
    local run_no=1
    local output_file
    while [[ "$run_no" -le "$runs" ]]; do
        output_file="$(mktemp)"
        echo "RUN target=${name} run=${run_no}/${runs}"
        # shellcheck disable=SC2086
        if bash "$BENCHMARK_SCRIPT" $args >"$output_file" 2>&1; then
            cat "$output_file"
            local status
            status="$(status_from_output "$output_file")"
            echo "RESULT target=${name} run=${run_no} status=${status}"
            if [[ "$status" == "REGRESSION" || "$status" == "WARN" ]]; then
                streak=$((streak + 1))
            else
                streak=0
            fi
        else
            cat "$output_file"
            echo "RESULT target=${name} run=${run_no} status=COMMAND_FAILED"
            streak=$((streak + 1))
        fi
        rm -f "$output_file"

        if [[ "$streak" -ge "$consecutive" ]]; then
            echo "ALERT target=${name} consecutive_alerts=${streak} threshold=${consecutive}"
            return 1
        fi

        if [[ "$run_no" -lt "$runs" ]]; then
            sleep "$interval"
        fi
        run_no=$((run_no + 1))
    done

    echo "OK target=${name} max_consecutive_alerts=${streak} threshold=${consecutive}"
    return 0
}

matched=0
alerted=0
for entry in "${catalog_entries[@]}"; do
    entry_name="${entry%%|*}"
    if [[ -n "$TARGET_FILTER" && "$TARGET_FILTER" != "$entry_name" ]]; then
        continue
    fi
    matched=$((matched + 1))
    if ! run_target "$entry"; then
        alerted=1
        [[ "$KEEP_GOING" == true ]] || break
    fi
done

if [[ "$matched" -eq 0 ]]; then
    die "no catalog target matched: ${TARGET_FILTER}"
fi

exit "$alerted"
