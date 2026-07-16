#!/usr/bin/env bats

setup() { TMPD="$(mktemp -d)"; }
teardown() { rm -r "$TMPD"; }

@test "blocks an empty implementation command" {
  printf '%s\n' '| Phase | 起票cmd |' '|---|---|' '| P1 | 未起票 |' > "$TMPD/design.md"
  run bash scripts/gates/gate_design_cmd_handoff.sh "$TMPD/design.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOCK LS086"* ]]
}

@test "accepts a command or reasoned deferral" {
  printf '%s\n' '| Phase | 起票cmd |' '|---|---|' '| P1 | cmd_123 |' '| P2 | 保留: 外部API待ち |' > "$TMPD/design.md"
  run bash scripts/gates/gate_design_cmd_handoff.sh "$TMPD/design.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unresolved=0"* ]]
}
