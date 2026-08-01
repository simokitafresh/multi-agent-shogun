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
