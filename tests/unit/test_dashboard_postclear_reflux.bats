#!/usr/bin/env bats

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "CLEAR and current two-phase fingerprint narrowly enable commit skip" {
    grep -Fq 'latest_status" = "CLEAR" ] && review_two_phase_ready' "$ROOT/scripts/dashboard_update.sh"
    grep -Fq 'GATE_SKIP_COMMIT_MISSING_CHECK="$skip_commit"' "$ROOT/scripts/dashboard_update.sh"
}

@test "commit skip does not bypass combined schema validation" {
    grep -Fq 'gate_report_format_combined.py' "$ROOT/scripts/gates/gate_report_format.sh"
    grep -Fq 'GATE_SKIP_COMMIT_MISSING_CHECK:-0}" != "1"' "$ROOT/scripts/gates/gate_report_format.sh"
}
