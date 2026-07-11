#!/usr/bin/env bats

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  TMPROOT=$(mktemp -d)
  mkdir -p "$TMPROOT/queue/gates/cmd_test/review_approvals/reports"
  mkdir -p "$TMPROOT/queue/reports"
  REPORT="$TMPROOT/queue/reports/ninja_report_cmd_test.yaml"
  printf 'parent_cmd: cmd_test\ncommit_hash: abc123\nresult:\n  summary: ok\n' > "$REPORT"
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
  local r="$TMPROOT/queue/reports/ninja_report_cmd_test.yaml"
  approve gunshi LGTM "$r"
  printf 'changed: true\n' >> "$r"
  ! review_two_phase_ready cmd_test "$r"
}

@test "either approval order formalizes once after the second approval" {
  mkdir -p "$TMPROOT/queue/reports" "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  local r="$TMPROOT/queue/reports/ninja_report_cmd_test.yaml"
  approve karo ACCEPT "$r"
  [ ! -e "$TMPROOT/queue/gates/cmd_test/review_gate.done" ]
  approve gunshi LGTM "$r"
  [ -e "$TMPROOT/queue/gates/cmd_test/review_gate.done" ]
  find "$TMPROOT/queue/gates/cmd_test/review_approvals" -maxdepth 1 -name '.gate_triggered.*' | grep -q .
}

@test "changed manifest gets its own single trigger generation" {
  mkdir -p "$TMPROOT/queue/reports" "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  local r="$TMPROOT/queue/reports/ninja_report_cmd_test.yaml"
  approve gunshi LGTM "$r"; approve karo ACCEPT "$r"
  printf 'generation: 2\n' >> "$r"
  approve gunshi LGTM "$r"; approve karo ACCEPT "$r"
  [ "$(find "$TMPROOT/queue/gates/cmd_test/review_approvals" -maxdepth 1 -name '.gate_triggered.*' | wc -l)" -eq 2 ]
}

@test "two reports require approvals for both before formal marker" {
  mkdir -p "$TMPROOT/queue/reports" "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  rm "$REPORT"
  printf 'parent_cmd: cmd_test\ncommit_hash: abc123\n' > "$TMPROOT/queue/reports/a_report_cmd_test.yaml"
  printf 'parent_cmd: cmd_test\ncommit_hash: abc123\n' > "$TMPROOT/queue/reports/b_report_cmd_test.yaml"
  local a="$TMPROOT/queue/reports/a_report_cmd_test.yaml" b="$TMPROOT/queue/reports/b_report_cmd_test.yaml"
  approve gunshi LGTM "$a"; approve karo ACCEPT "$a"
  [ ! -e "$TMPROOT/queue/gates/cmd_test/review_gate.done" ]
  approve gunshi LGTM "$b"; approve karo ACCEPT "$b"
  [ -e "$TMPROOT/queue/gates/cmd_test/review_gate.done" ]
}

@test "RC invalidates report approval and formal marker" {
  mkdir -p "$TMPROOT/queue/reports" "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  local r="$TMPROOT/queue/reports/ninja_report_cmd_test.yaml"
  approve gunshi LGTM "$r"; approve karo ACCEPT "$r"
  [ -e "$TMPROOT/queue/gates/cmd_test/review_gate.done" ]
  approve karo RC "$r"
  [ ! -e "$TMPROOT/queue/gates/cmd_test/review_gate.done" ]
  ! review_two_phase_ready cmd_test "$r"
}

@test "RC permits the same manifest to trigger once again" {
  mkdir -p "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  approve gunshi LGTM "$REPORT"; approve karo ACCEPT "$REPORT"
  manifest=$(review_manifest_fingerprint "$REPORT")
  [ -e "$TMPROOT/queue/gates/cmd_test/review_approvals/.gate_triggered.$manifest" ]
  approve karo RC "$REPORT"
  [ ! -e "$TMPROOT/queue/gates/cmd_test/review_approvals/.gate_triggered.$manifest" ]
  approve gunshi LGTM "$REPORT"; approve karo ACCEPT "$REPORT"
  [ -e "$TMPROOT/queue/gates/cmd_test/review_approvals/.gate_triggered.$manifest" ]
  grep -q "^manifest: $manifest$" "$TMPROOT/queue/gates/cmd_test/review_gate.done"
}

@test "cmd id, report boundary, and parent_cmd mismatch fail closed" {
  mkdir -p "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  run approve gunshi LGTM "$REPORT"; [ "$status" -eq 0 ]
  run env REVIEW_APPROVAL_ROOT="$TMPROOT" bash "$ROOT/scripts/review_approval.sh" bad gunshi LGTM "$REPORT"; [ "$status" -eq 2 ]
  cp "$REPORT" "$TMPROOT/outside.yaml"
  run env REVIEW_APPROVAL_ROOT="$TMPROOT" bash "$ROOT/scripts/review_approval.sh" cmd_test gunshi LGTM "$TMPROOT/outside.yaml"; [ "$status" -eq 2 ]
  sed -i 's/parent_cmd: cmd_test/parent_cmd: cmd_other/' "$REPORT"
  run approve gunshi LGTM "$REPORT"; [ "$status" -eq 2 ]
}

@test "real cmd_complete trigger runs exactly once for a manifest" {
  mkdir -p "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  cat > "$TMPROOT/scripts/cmd_complete_gate.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$REVIEW_TRIGGER_LOG"
SH
  chmod +x "$TMPROOT/scripts/cmd_complete_gate.sh"
  export REVIEW_TRIGGER_LOG="$TMPROOT/trigger.log"
  REVIEW_APPROVAL_ROOT="$TMPROOT" bash "$ROOT/scripts/review_approval.sh" cmd_test gunshi LGTM "$REPORT"
  REVIEW_APPROVAL_ROOT="$TMPROOT" bash "$ROOT/scripts/review_approval.sh" cmd_test karo ACCEPT "$REPORT"
  REVIEW_APPROVAL_ROOT="$TMPROOT" bash "$ROOT/scripts/review_approval.sh" cmd_test karo ACCEPT "$REPORT"
  for _ in {1..20}; do [ -f "$REVIEW_TRIGGER_LOG" ] && break; sleep 0.05; done
  [ "$(wc -l < "$REVIEW_TRIGGER_LOG")" -eq 1 ]
}

@test "canonical and dot report paths share one approval key" {
  mkdir -p "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  approve gunshi LGTM "$TMPROOT/queue/reports/./ninja_report_cmd_test.yaml"
  approve karo ACCEPT "$REPORT"
  [ "$(find "$TMPROOT/queue/gates/cmd_test/review_approvals/reports" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ]
  review_two_phase_ready cmd_test "$REPORT"
}

@test "global lock serializes late approval and RC; RC leaves no formal state" {
  mkdir -p "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  approve gunshi LGTM "$REPORT"
  ready="$TMPROOT/ready" release="$TMPROOT/release"
  REVIEW_APPROVAL_ROOT="$TMPROOT" REVIEW_APPROVAL_NO_TRIGGER=1 REVIEW_APPROVAL_TEST_READY_FILE="$ready" REVIEW_APPROVAL_TEST_RELEASE_FILE="$release" \
    bash "$ROOT/scripts/review_approval.sh" cmd_test karo ACCEPT "$REPORT" >"$TMPROOT/accept.log" 2>&1 & accept_pid=$!
  for _ in {1..100}; do [ -e "$ready" ] && break; sleep 0.01; done
  [ -e "$ready" ]
  REVIEW_APPROVAL_ROOT="$TMPROOT" REVIEW_APPROVAL_NO_TRIGGER=1 \
    bash "$ROOT/scripts/review_approval.sh" cmd_test karo RC "$REPORT" >"$TMPROOT/rc.log" 2>&1 & rc_pid=$!
  : > "$release"
  wait "$accept_pid"; wait "$rc_pid"
  [ ! -e "$TMPROOT/queue/gates/cmd_test/review_gate.done" ]
  ! find "$TMPROOT/queue/gates/cmd_test/review_approvals" -maxdepth 1 -name '.gate_triggered.*' | grep -q .
  ! review_two_phase_ready cmd_test "$REPORT"
}
