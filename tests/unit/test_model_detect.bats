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

@test "detect_real_model: latest Claude banner wins when old Sonnet and new Opus banners coexist" {
    run bash -lc "
        source '$PROJECT_ROOT/scripts/lib/cli_lookup.sh'
        source '$PROJECT_ROOT/scripts/lib/model_detect.sh'
        cli_type() { echo claude; }
        tmux() {
            if [ \"\$1\" = capture-pane ]; then
                printf '%s\n' \
                    ' ▝▜█████▛▘  Sonnet 5 with high effort · /mnt/c/tools/multi-agent-shogun' \
                    'older pane output' \
                    ' ▝▜█████▛▘  Opus 4.8 (1M context) with high effort · /mnt/c/tools/multi-agent-shogun'
                return 0
            fi
            if [ \"\$1\" = set-option ]; then
                return 0
            fi
            return 1
        }
        detect_real_model saizo shogun:agents.6
    "
    [ "$status" -eq 0 ]
    [ "$output" = "Opus 4.8 high" ]
}

@test "detect_real_model: ignores stale Claude banners before latest launch marker" {
    run bash -lc "
        source '$PROJECT_ROOT/scripts/lib/cli_lookup.sh'
        source '$PROJECT_ROOT/scripts/lib/model_detect.sh'
        cli_type() { echo claude; }
        tmux() {
            if [ \"\$1\" = capture-pane ]; then
                printf '%s\n' \
                    'Claude Code' \
                    ' ▝▜█████▛▘  Opus 4.8 (1M context) with high effort · /mnt/c/tools/multi-agent-shogun' \
                    'old pane output after previous launch' \
                    'Claude Code' \
                    'initializing current session' \
                    ' ▝▜█████▛▘  Sonnet 5 with high effort · /mnt/c/tools/multi-agent-shogun'
                return 0
            fi
            if [ \"\$1\" = set-option ]; then
                return 0
            fi
            return 1
        }
        detect_real_model saizo shogun:agents.6
    "
    [ "$status" -eq 0 ]
    [ "$output" = "Sonnet 5 high" ]
}

@test "detect_real_model: truncated Claude effort suffix is normalized before validation" {
    run bash -lc "
        source '$PROJECT_ROOT/scripts/lib/cli_lookup.sh'
        source '$PROJECT_ROOT/scripts/lib/model_detect.sh'
        cli_type() { echo claude; }
        tmux() {
            if [ \"\$1\" = capture-pane ]; then
                printf '%s\n' \
                    ' ▝▜█████▛▘  Sonnet 4.6 with high effort · /mnt/c/tools/multi-agent-shogun' \
                    ' ▐▛███▜▌   Opus 4.8 (1M context) with xhigh eff…'
                return 0
            fi
            if [ \"\$1\" = set-option ]; then
                return 0
            fi
            if [ \"\$1\" = show-options ]; then
                printf '%s\n' 'Sonnet 4.6 high'
                return 0
            fi
            return 1
        }
        detect_real_model saizo shogun:agents.6
    "
    [ "$status" -eq 0 ]
    [ "$output" = "Opus 4.8 xhigh" ]
}

@test "detect_real_model: latest wrapped Claude model line wins in narrow pane" {
    run bash -lc "
        source '$PROJECT_ROOT/scripts/lib/cli_lookup.sh'
        source '$PROJECT_ROOT/scripts/lib/model_detect.sh'
        cli_type() { echo claude; }
        tmux() {
            if [ \"\$1\" = capture-pane ]; then
                printf '%s\n' \
                    ' ▐▛███▜▌' \
                    '           Sonnet 5 (1M context) with high effort' \
                    'old text' \
                    ' ▐▛███▜▌' \
                    '           Opus 4.8 (1M context) with high effort'
                return 0
            fi
            if [ \"\$1\" = set-option ]; then
                return 0
            fi
            return 1
        }
        detect_real_model saizo shogun:agents.6
    "
    [ "$status" -eq 0 ]
    [ "$output" = "Opus 4.8" ]
}
