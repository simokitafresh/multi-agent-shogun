#!/usr/bin/env bats

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  TMPROOT=$(mktemp -d)
  mkdir -p "$TMPROOT/queue/gates/cmd_test/review_approvals"
  REPORT="$TMPROOT/report.yaml"
  printf 'commit_hash: abc123\nresult:\n  summary: ok\n' > "$REPORT"
  PROJECT_ROOT="$TMPROOT"
  source "$ROOT/scripts/lib/review_approval.sh"
}
teardown() { rm -rf "$TMPROOT"; }

@test "gunshi LGTM alone is not CLEAR" {
  fp=$(review_report_fingerprint "$REPORT")
  printf 'result: LGTM\nfingerprint: %s\n' "$fp" > "$TMPROOT/queue/gates/cmd_test/review_approvals/gunshi.yaml"
  ! review_two_phase_ready cmd_test "$REPORT"
}

@test "karo RC blocks and stale approvals cannot be reused" {
  fp=$(review_report_fingerprint "$REPORT")
  printf 'result: LGTM\nfingerprint: %s\n' "$fp" > "$TMPROOT/queue/gates/cmd_test/review_approvals/gunshi.yaml"
  printf 'result: RC\nfingerprint: %s\n' "$fp" > "$TMPROOT/queue/gates/cmd_test/review_approvals/karo.yaml"
  ! review_two_phase_ready cmd_test "$REPORT"
  printf 'changed: true\n' >> "$REPORT"
  printf 'result: ACCEPT\nfingerprint: %s\n' "$fp" > "$TMPROOT/queue/gates/cmd_test/review_approvals/karo.yaml"
  ! review_two_phase_ready cmd_test "$REPORT"
}

@test "matching LGTM and ACCEPT CLEAR exactly one fingerprint" {
  fp=$(review_report_fingerprint "$REPORT")
  printf 'result: LGTM\nfingerprint: %s\n' "$fp" > "$TMPROOT/queue/gates/cmd_test/review_approvals/gunshi.yaml"
  printf 'result: ACCEPT\nfingerprint: %s\n' "$fp" > "$TMPROOT/queue/gates/cmd_test/review_approvals/karo.yaml"
  review_two_phase_ready cmd_test "$REPORT"
}
