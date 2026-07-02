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

@test "detect_real_model: Claude Fable 5 banner is detected" {
    run bash -lc "
        source '$PROJECT_ROOT/scripts/lib/cli_lookup.sh'
        source '$PROJECT_ROOT/scripts/lib/model_detect.sh'
        cli_type() { echo claude; }
        tmux() {
            if [ \"\$1\" = capture-pane ]; then
                printf '%s\n' ' ▝▜█████▛▘  Fable 5 with high effort · /mnt/c/tools/multi-agent-shogun'
                return 0
            fi
            if [ \"\$1\" = set-option ]; then
                return 0
            fi
            return 1
        }
        detect_real_model shogun shogun:main
    "
    [ "$status" -eq 0 ]
    [ "$output" = "Fable 5 high" ]
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

@test "detect_real_model: Claude process args beat stale real_model cache when banner has no model" {
    run bash -lc "
        source '$PROJECT_ROOT/scripts/lib/cli_lookup.sh'
        source '$PROJECT_ROOT/scripts/lib/model_detect.sh'
        cli_type() { echo claude; }
        _cli_lookup_settings_get() {
            if [ \"\$2\" = model_name ]; then
                echo claude-sonnet-5-xhigh
                return 0
            fi
            return 1
        }
        tmux() {
            if [ \"\$1\" = capture-pane ]; then
                printf '%s\n' 'Claude Code' 'current session has no model banner yet'
                return 0
            fi
            if [ \"\$1\" = display-message ]; then
                printf '%s\n' '100'
                return 0
            fi
            if [ \"\$1\" = show-options ]; then
                printf '%s\n' 'Opus 4.8 high'
                return 0
            fi
            if [ \"\$1\" = set-option ]; then
                return 0
            fi
            return 1
        }
        ps() {
            printf '%s\n' \
                '100 1 bash' \
                '201 999 /home/simokitafresh/.local/bin/claude --model opus --effort high' \
                '200 100 /home/simokitafresh/.local/bin/claude --dangerously-skip-permissions --model sonnet --effort xhigh'
        }
        detect_real_model saizo shogun:agents.6
    "
    [ "$status" -eq 0 ]
    [ "$output" = "Sonnet 5 xhigh" ]
}

@test "resolve_model_display: stale real_model cache is cleared and settings model is fallback" {
    run bash -lc "
        source '$PROJECT_ROOT/scripts/lib/cli_lookup.sh'
        source '$PROJECT_ROOT/scripts/lib/model_detect.sh'
        source '$PROJECT_ROOT/scripts/lib/model_resolve.sh'
        cli_type() { echo claude; }
        _cli_lookup_settings_get() {
            if [ \"\$2\" = model_name ]; then
                echo claude-sonnet-5-xhigh
                return 0
            fi
            return 1
        }
        cli_profile_get() { return 1; }
        tmux() {
            if [ \"\$1\" = capture-pane ]; then
                printf '%s\n' 'Claude Code' 'current session has no model banner yet'
                return 0
            fi
            if [ \"\$1\" = display-message ]; then
                printf '%s\n' '100'
                return 0
            fi
            if [ \"\$1\" = show-options ]; then
                printf '%s\n' 'Opus 4.8 high'
                return 0
            fi
            if [ \"\$1\" = set-option ]; then
                return 0
            fi
            return 1
        }
        ps() {
            printf '%s\n' '100 1 bash'
        }
        resolve_model_display saizo shogun:agents.6
    "
    [ "$status" -eq 0 ]
    [ "$output" = "Sonnet 5 xhigh" ]
}

@test "detect_real_model: Claude process args resolve Fable family when banner has no model" {
    run bash -lc "
        source '$PROJECT_ROOT/scripts/lib/cli_lookup.sh'
        source '$PROJECT_ROOT/scripts/lib/model_detect.sh'
        cli_type() { echo claude; }
        _cli_lookup_settings_get() {
            if [ \"\$2\" = model_name ]; then
                echo claude-fable-5-high
                return 0
            fi
            return 1
        }
        tmux() {
            if [ \"\$1\" = capture-pane ]; then
                printf '%s\n' 'Claude Code' 'current session has no model banner yet'
                return 0
            fi
            if [ \"\$1\" = display-message ]; then
                printf '%s\n' '100'
                return 0
            fi
            if [ \"\$1\" = set-option ]; then
                return 0
            fi
            return 1
        }
        ps() {
            printf '%s\n' \
                '100 1 bash' \
                '200 100 /home/simokitafresh/.local/bin/claude --dangerously-skip-permissions --model fable --effort high'
        }
        detect_real_model shogun shogun:main
    "
    [ "$status" -eq 0 ]
    [ "$output" = "Fable high" ]
}

@test "detect_real_model: Claude process args without --model fall back to settings model_name" {
    run bash -lc "
        source '$PROJECT_ROOT/scripts/lib/cli_lookup.sh'
        source '$PROJECT_ROOT/scripts/lib/model_detect.sh'
        cli_type() { echo claude; }
        _cli_lookup_settings_get() {
            if [ \"\$2\" = model_name ]; then
                echo fable-5-high
                return 0
            fi
            return 1
        }
        tmux() {
            if [ \"\$1\" = capture-pane ]; then
                printf '%s\n' 'Claude Code' 'current session has no model banner yet'
                return 0
            fi
            if [ \"\$1\" = display-message ]; then
                printf '%s\n' '100'
                return 0
            fi
            if [ \"\$1\" = set-option ]; then
                return 0
            fi
            return 1
        }
        ps() {
            printf '%s\n' \
                '100 1 bash' \
                '200 100 /home/simokitafresh/.local/bin/claude --dangerously-skip-permissions --effort high'
        }
        detect_real_model shogun shogun:main
    "
    [ "$status" -eq 0 ]
    [ "$output" = "fable-5-high" ]
}

@test "resolve_model_display: Fable settings model_name is the fallback when banner detection fails" {
    run bash -lc "
        source '$PROJECT_ROOT/scripts/lib/cli_lookup.sh'
        source '$PROJECT_ROOT/scripts/lib/model_detect.sh'
        source '$PROJECT_ROOT/scripts/lib/model_resolve.sh'
        cli_type() { echo claude; }
        _cli_lookup_settings_get() {
            if [ \"\$2\" = model_name ]; then
                echo fable-5-high
                return 0
            fi
            return 1
        }
        cli_profile_get() { return 1; }
        tmux() {
            if [ \"\$1\" = capture-pane ]; then
                printf '%s\n' 'Claude Code' 'current session has no model banner yet'
                return 0
            fi
            if [ \"\$1\" = display-message ]; then
                printf '%s\n' '100'
                return 0
            fi
            if [ \"\$1\" = set-option ]; then
                return 0
            fi
            return 1
        }
        ps() {
            printf '%s\n' '100 1 bash'
        }
        resolve_model_display shogun shogun:main
    "
    [ "$status" -eq 0 ]
    [ "$output" = "fable-5-high" ]
}

@test "detect_real_model: Claude process args can be read from pane tty" {
    run bash -lc "
        source '$PROJECT_ROOT/scripts/lib/cli_lookup.sh'
        source '$PROJECT_ROOT/scripts/lib/model_detect.sh'
        cli_type() { echo claude; }
        _cli_lookup_settings_get() {
            if [ \"\$2\" = model_name ]; then
                echo sonnet-5-xhigh
                return 0
            fi
            return 1
        }
        tmux() {
            if [ \"\$1\" = capture-pane ]; then
                printf '%s\n' 'Claude Code' 'current session has no model banner yet'
                return 0
            fi
            if [ \"\$1\" = display-message ] && [ \"\$5\" = '#{pane_pid}' ]; then
                printf '%s\n' '100'
                return 0
            fi
            if [ \"\$1\" = display-message ] && [ \"\$5\" = '#{pane_tty}' ]; then
                printf '%s\n' '/dev/pts/9'
                return 0
            fi
            if [ \"\$1\" = set-option ]; then
                return 0
            fi
            return 1
        }
        ps() {
            if [ \"\$1\" = -eo ]; then
                printf '%s\n' '100 1 bash'
                return 0
            fi
            if [ \"\$1\" = -t ]; then
                printf '%s\n' \
                    '/home/simokitafresh/.local/bin/claude --dangerously-skip-permissions --model sonnet --effort xhigh' \
                    'npm exec @modelcontextprotocol/server-memory'
                return 0
            fi
            return 1
        }
        detect_real_model saizo shogun:agents.6
    "
    [ "$status" -eq 0 ]
    [ "$output" = "Sonnet 5 xhigh" ]
}
