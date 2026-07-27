#!/usr/bin/env bats
# test_necessity: decision-candidate duplicate severity is a process contract:
# partial overlap must remain non-blocking while exact duplicate must block.

bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CASE_ROOT="$(mktemp -d)"
  mkdir -p "$CASE_ROOT/scripts/gates" "$CASE_ROOT/queue"
  cp "$ROOT/scripts/gates/gate_dc_duplicate.sh" "$CASE_ROOT/scripts/gates/"
  cat >"$CASE_ROOT/queue/pending_decisions.yaml" <<'YAML'
decisions:
  - id: PD-EXACT
    status: resolved
    summary: "exact resolved title"
    resolution: "alpha beta gamma delta"
YAML
}

teardown() { rm -rf "$CASE_ROOT"; }

write_report() {
  cat >"$CASE_ROOT/report.yaml" <<YAML
decision_candidate:
  found: true
  title: "$1"
  detail: "$2"
YAML
}

@test "partial overlap warns and exits zero" {
  write_report "different title" "alpha beta gamma"
  run /bin/bash -c 'result=$(/bin/bash "$1" "$2" 2>/dev/null || echo "BLOCK: gate script error"); printf "%s\n" "$result"' _ \
    "$CASE_ROOT/scripts/gates/gate_dc_duplicate.sh" "$CASE_ROOT/report.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == WARN:* ]]
  [[ "$output" != *"BLOCK:"* ]]
}

@test "exact duplicate blocks and exits one" {
  write_report "exact resolved title" "unrelated"
  run bash "$CASE_ROOT/scripts/gates/gate_dc_duplicate.sh" "$CASE_ROOT/report.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == BLOCK:* ]]
}

@test "true gate execution error remains nonzero for caller fail-close" {
  write_report "different title" "alpha beta gamma"
  run -127 env PATH=/nonexistent /bin/bash "$CASE_ROOT/scripts/gates/gate_dc_duplicate.sh" "$CASE_ROOT/report.yaml"
  [[ "$output" == *"command not found"* ]]
}
