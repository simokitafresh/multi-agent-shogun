#!/usr/bin/env bats

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  TMPROOT=$(mktemp -d)
  mkdir -p "$TMPROOT/queue/gates/cmd_test/review_approvals/reports"
  REPORT="$TMPROOT/report.yaml"
  printf 'commit_hash: abc123\nresult:\n  summary: ok\n' > "$REPORT"
  PROJECT_ROOT="$TMPROOT"
  source "$ROOT/scripts/lib/review_approval.sh"
  KEY=$(review_report_key "${REPORT#"$TMPROOT"/}")
  APPROVALS="$TMPROOT/queue/gates/cmd_test/review_approvals/reports/$KEY"
  mkdir -p "$APPROVALS"
}
teardown() { rm -rf "$TMPROOT"; }

approve() {
  REVIEW_APPROVAL_ROOT="$TMPROOT" REVIEW_APPROVAL_NO_TRIGGER=1 \
    bash "$ROOT/scripts/review_approval.sh" cmd_test "$1" "$2" "$3"
}

@test "gunshi LGTM alone is not CLEAR" {
  fp=$(review_report_fingerprint "$REPORT")
  printf 'result: LGTM\nfingerprint: %s\n' "$fp" > "$APPROVALS/gunshi.yaml"
  ! review_two_phase_ready cmd_test "$REPORT"
}

@test "karo RC blocks and stale approvals cannot be reused" {
  fp=$(review_report_fingerprint "$REPORT")
  printf 'result: LGTM\nfingerprint: %s\n' "$fp" > "$APPROVALS/gunshi.yaml"
  printf 'result: RC\nfingerprint: %s\n' "$fp" > "$APPROVALS/karo.yaml"
  ! review_two_phase_ready cmd_test "$REPORT"
  printf 'changed: true\n' >> "$REPORT"
  printf 'result: ACCEPT\nfingerprint: %s\n' "$fp" > "$APPROVALS/karo.yaml"
  ! review_two_phase_ready cmd_test "$REPORT"
}

@test "matching LGTM and ACCEPT CLEAR exactly one fingerprint" {
  fp=$(review_report_fingerprint "$REPORT")
  printf 'result: LGTM\nfingerprint: %s\n' "$fp" > "$APPROVALS/gunshi.yaml"
  printf 'result: ACCEPT\nfingerprint: %s\n' "$fp" > "$APPROVALS/karo.yaml"
  review_two_phase_ready cmd_test "$REPORT"
}

@test "commit_hash missing is fail-closed" {
  printf 'result:\n  summary: ok\n' > "$REPORT"
  ! review_report_fingerprint "$REPORT"
  ! review_two_phase_ready cmd_test "$REPORT"
}

@test "F1 review followed by F2 update does not bind delayed notification to F2" {
  mkdir -p "$TMPROOT/queue/reports" "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  cp "$REPORT" "$TMPROOT/queue/reports/ninja_report_cmd_test.yaml"
  local r="$TMPROOT/queue/reports/ninja_report_cmd_test.yaml"
  approve gunshi LGTM "$r"
  printf 'changed: true\n' >> "$r"
  ! review_two_phase_ready cmd_test "$r"
}

@test "either approval order formalizes once after the second approval" {
  mkdir -p "$TMPROOT/queue/reports" "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  cp "$REPORT" "$TMPROOT/queue/reports/ninja_report_cmd_test.yaml"
  local r="$TMPROOT/queue/reports/ninja_report_cmd_test.yaml"
  approve karo ACCEPT "$r"
  [ ! -e "$TMPROOT/queue/gates/cmd_test/review_gate.done" ]
  approve gunshi LGTM "$r"
  [ -e "$TMPROOT/queue/gates/cmd_test/review_gate.done" ]
  [ -e "$TMPROOT/queue/gates/cmd_test/review_approvals/.gate_triggered" ]
}

@test "two reports require approvals for both before formal marker" {
  mkdir -p "$TMPROOT/queue/reports" "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  cp "$REPORT" "$TMPROOT/queue/reports/a_report_cmd_test.yaml"
  cp "$REPORT" "$TMPROOT/queue/reports/b_report_cmd_test.yaml"
  local a="$TMPROOT/queue/reports/a_report_cmd_test.yaml" b="$TMPROOT/queue/reports/b_report_cmd_test.yaml"
  approve gunshi LGTM "$a"; approve karo ACCEPT "$a"
  [ ! -e "$TMPROOT/queue/gates/cmd_test/review_gate.done" ]
  approve gunshi LGTM "$b"; approve karo ACCEPT "$b"
  [ -e "$TMPROOT/queue/gates/cmd_test/review_gate.done" ]
}

@test "RC invalidates report approval and formal marker" {
  mkdir -p "$TMPROOT/queue/reports" "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  cp "$REPORT" "$TMPROOT/queue/reports/ninja_report_cmd_test.yaml"
  local r="$TMPROOT/queue/reports/ninja_report_cmd_test.yaml"
  approve gunshi LGTM "$r"; approve karo ACCEPT "$r"
  [ -e "$TMPROOT/queue/gates/cmd_test/review_gate.done" ]
  approve karo RC "$r"
  [ ! -e "$TMPROOT/queue/gates/cmd_test/review_gate.done" ]
  ! review_two_phase_ready cmd_test "$r"
}
