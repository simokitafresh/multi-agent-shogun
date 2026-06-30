#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
}

@test "detect_real_model: Claude Sonnet 5 integer version banner is detected" {
    run bash -lc "
        source '$PROJECT_ROOT/scripts/lib/cli_lookup.sh'
        source '$PROJECT_ROOT/scripts/lib/model_detect.sh'
        cli_type() { echo claude; }
        tmux() {
            if [ \"\$1\" = capture-pane ]; then
                printf '%s\n' ' ▐▛███▜▌   Sonnet 5 with xhigh effort'
                return 0
            fi
            if [ \"\$1\" = set-option ]; then
                return 0
            fi
            return 1
        }
        detect_real_model tobisaru shogun:agents.8
    "
    [ "$status" -eq 0 ]
    [ "$output" = "Sonnet 5 xhigh" ]
}
