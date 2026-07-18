#!/usr/bin/env bats
# test_necessity: While-body short-circuit under set -e is blocked to prevent silent loop termination; violation is BLOCK.

setup() {
    FIXTURE="$BATS_TEST_TMPDIR/sample.sh"
    GATE="scripts/gates/gate_set_e_short_circuit.sh"
}

@test "blocks while-body single bracket short-circuit under set -e" {
    printf '%s\n' '#!/bin/bash' 'set -euo pipefail' 'while read -r value; do [ -n "$value" ] && echo "$value"; done' > "$FIXTURE"
    run bash "$GATE" "$FIXTURE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK(LG041)"* ]]
}

@test "blocks while-body double bracket short-circuit under set -e" {
    printf '%s\n' '#!/bin/bash' 'set -e' 'while read -r value; do [[ -n "$value" ]] && echo "$value"; done' > "$FIXTURE"
    run bash "$GATE" "$FIXTURE"
    [ "$status" -eq 1 ]
}

@test "allows explicit if under set -e" {
    printf '%s\n' '#!/bin/bash' 'set -euo pipefail' 'if [ -n "$value" ]; then' '  echo "$value"' 'fi' > "$FIXTURE"
    run bash "$GATE" "$FIXTURE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0件"* ]]
}

@test "does not classify an intentional standalone short-circuit" {
    printf '%s\n' '#!/bin/bash' 'set -euo pipefail' '[ -z "$value" ] && return 0' > "$FIXTURE"
    run bash "$GATE" "$FIXTURE"
    [ "$status" -eq 0 ]
}

@test "allows an explicitly guarded one-line loop" {
    printf '%s\n' '#!/bin/bash' 'set -e' 'for value in one; do [ -n "$value" ] && echo "$value"; done || true' > "$FIXTURE"
    run bash "$GATE" "$FIXTURE"
    [ "$status" -eq 0 ]
}

@test "does not govern scripts without errexit" {
    printf '%s\n' '#!/bin/bash' '[ -n "$value" ] && echo "$value"' > "$FIXTURE"
    run bash "$GATE" "$FIXTURE"
    [ "$status" -eq 0 ]
}
