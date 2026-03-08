#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "print_padded pads ASCII text to requested width" {
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
source "$PROJECT_ROOT/scripts/lib/text_utils.sh"
print_padded "agent" 8
'
    [ "$status" -eq 0 ]
    [ "$output" = "agent   " ]
}

@test "print_padded pads Japanese text using display width" {
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
source "$PROJECT_ROOT/scripts/lib/text_utils.sh"
print_padded "忍者" 5
'
    [ "$status" -eq 0 ]
    [ "$output" = "忍者 " ]
}

@test "print_padded pads mixed ASCII and Japanese text" {
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
source "$PROJECT_ROOT/scripts/lib/text_utils.sh"
print_padded "A忍B" 6
'
    [ "$status" -eq 0 ]
    [ "$output" = "A忍B  " ]
}
