#!/usr/bin/env bats
# test_necessity: the cmd_complete_gate sandbox must mirror every scripts/lib
# entry, so a new lib sourced by the gate never leaves the sandbox missing it.

load '../helpers/cmd_gate_scaffold'

setup_file() {
  cmd_gate_setup_file
}

setup() {
  PROBE_LIB="$PROJECT_ROOT/scripts/lib/zz_scaffold_mirror_probe.sh"
  printf '#!/usr/bin/env bash\n:\n' > "$PROBE_LIB"
  cmd_gate_scaffold "cmd_gate_mirror"
}

teardown() {
  rm -f "$PROBE_LIB"
  cmd_gate_teardown
}

@test "scaffold mirrors a newly added scripts/lib entry" {
  [ -e "$TEST_PROJECT/scripts/lib/zz_scaffold_mirror_probe.sh" ]
}

@test "scaffold mirrors every scripts/lib entry, not an allowlist" {
  local entry missing=""
  for entry in "$PROJECT_ROOT/scripts/lib/"*; do
    [ -e "$entry" ] || continue
    [ -e "$TEST_PROJECT/scripts/lib/$(basename "$entry")" ] || missing+=" $(basename "$entry")"
  done
  [ -z "$missing" ]
}

@test "overriding a mirrored lib in the sandbox never writes into the real repo" {
  cmd_gate_lib_override zz_scaffold_mirror_probe.sh
  printf 'sandbox stub\n' > "$TEST_PROJECT/scripts/lib/zz_scaffold_mirror_probe.sh"
  ! grep -q 'sandbox stub' "$PROBE_LIB"
}
