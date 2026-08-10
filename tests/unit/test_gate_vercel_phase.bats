#!/usr/bin/env bats

setup() { fixture_dir="$(mktemp -d)"; }
make_lines() { awk -v n="$1" 'BEGIN { for (i=1; i<=n; i++) print "line " i }' > "$2"; }

@test "500 line context passes" {
  make_lines 500 "$fixture_dir/new-context.md"
  run bash scripts/gates/gate_vercel_phase.sh "$fixture_dir/new-context.md"
  [ "$status" -eq 0 ]
}

@test "501 line context blocks" {
  make_lines 501 "$fixture_dir/new-context.md"
  run bash scripts/gates/gate_vercel_phase.sh "$fixture_dir/new-context.md"
  [ "$status" -ne 0 ]
}

@test "existing debt increase blocks" {
  make_lines 1490 "$fixture_dir/senkyoku-log.md"
  run bash scripts/gates/gate_vercel_phase.sh "$fixture_dir/senkyoku-log.md"
  [ "$status" -ne 0 ]
}

@test "new 501 line context blocks" {
  make_lines 501 "$fixture_dir/brand-new.md"
  run bash scripts/gates/gate_vercel_phase.sh "$fixture_dir/brand-new.md"
  [ "$status" -ne 0 ]
}

@test "line limit failure reports a distinct machine-readable reason" {
  make_lines 501 "$fixture_dir/line-limit.md"
  run bash scripts/gates/gate_vercel_phase.sh "$fixture_dir/line-limit.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"GATE_REASON=vercel_phase:line_limit_exceeded"* ]]
  [[ "$output" != *"GATE_REASON=vercel_phase:broken_references"* ]]
}

@test "broken reference failure reports a distinct machine-readable reason" {
  printf '# fixture\nSee docs/research/does-not-exist-vercel-phase.md\n' > "$fixture_dir/broken-ref.md"
  run env VERCEL_PHASE_SKIP_CANDIDATE_SUGGESTIONS=1 \
      bash scripts/gates/gate_vercel_phase.sh "$fixture_dir/broken-ref.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"GATE_REASON=vercel_phase:broken_references"* ]]
  [[ "$output" != *"GATE_REASON=vercel_phase:line_limit_exceeded"* ]]
}

@test "completion gate maps machine-readable Vercel reasons without ambiguity" {
  run env CMD_COMPLETE_GATE_VERCEL_REASON_ONLY=1 \
      CMD_COMPLETE_GATE_VERCEL_OUTPUT='[ALERT] line limit exceeded
GATE_REASON=vercel_phase:line_limit_exceeded' \
      bash scripts/cmd_complete_gate.sh cmd_test
  [ "$status" -eq 0 ]
  [ "$output" = "vercel_phase:line_limit_exceeded" ]

  run env CMD_COMPLETE_GATE_VERCEL_REASON_ONLY=1 \
      CMD_COMPLETE_GATE_VERCEL_OUTPUT='[ALERT] broken refs found
GATE_REASON=vercel_phase:broken_references' \
      bash scripts/cmd_complete_gate.sh cmd_test
  [ "$status" -eq 0 ]
  [ "$output" = "vercel_phase:broken_references" ]
}

@test "research context index preserves the exact detail payload before compression" {
  context="context/dm-signal-research.md"
  detail="docs/research/cmd_karo_hotfix_vercel_debt_reason_202608100949_dm_signal_research_full.md"
  [ "$(wc -l < "$context")" -le 500 ]
  expected_lines="$(sed -n 's/.*original_line_count: \([0-9][0-9]*\).*/\1/p' "$detail")"
  expected_sha="$(sed -n 's/.*original_sha256: \([0-9a-f][0-9a-f]*\).*/\1/p' "$detail")"
  actual_lines="$(tail -n +3 "$detail" | wc -l)"
  actual_sha="$(tail -n +3 "$detail" | sha256sum | awk '{print $1}')"
  [ "$actual_lines" -eq "$expected_lines" ]
  [ "$actual_sha" = "$expected_sha" ]
  run bash scripts/gates/gate_vercel_phase.sh "$context"
  [ "$status" -eq 0 ]
}
