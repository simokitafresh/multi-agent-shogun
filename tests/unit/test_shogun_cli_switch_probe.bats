#!/usr/bin/env bats

# test_necessity: モデル組合せprobeがactive workerをrespawnせず、共有Codex configも変更しない不変量を守る。
@test "codex model probe dry-run leaves worker pane PIDs and shared config unchanged" {
    root="${BATS_TEST_DIRNAME}/../.."
    script="$root/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh"
    cfg="$HOME/.codex/config.toml"
    before_cfg="missing"
    [ ! -f "$cfg" ] || before_cfg="$(sha256sum "$cfg" | awk '{print $1}')"
    before_panes="$(tmux list-panes -a -F '#{pane_id}:#{pane_pid}' | sort)"

    run bash "$script" probe-codex --repo "$root" --model gpt-5.6-sol --effort low --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" == *"isolated probe"* ]]
    after_cfg="missing"
    [ ! -f "$cfg" ] || after_cfg="$(sha256sum "$cfg" | awk '{print $1}')"
    [ "$before_cfg" = "$after_cfg" ]
    [ "$before_panes" = "$(tmux list-panes -a -F '#{pane_id}:#{pane_pid}' | sort)" ]
}

# test_necessity: ピン留めOpus 4.6 1Mのdry-runが正本・worker PIDを変更せず、確定手順を一意に提示する不変量を守る。
@test "pinned Opus 4.6 1M dry-run is deterministic and non-mutating" {
    root="${BATS_TEST_DIRNAME}/../.."
    script="$root/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh"
    before_settings="$(sha256sum "$root/config/settings.yaml" | awk '{print $1}')"
    before_panes="$(tmux list-panes -a -F '#{pane_id}:#{pane_pid}' | sort)"

    run bash "$script" pin-opus-4.6-1m --repo "$root" --agent gunshi --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" == *"model_name=claude-opus-4-6"* ]]
    [[ "$output" == *"send /model default"* ]]
    [[ "$output" == *"require two 1M confirmations"* ]]
    [ "$before_settings" = "$(sha256sum "$root/config/settings.yaml" | awk '{print $1}')" ]
    [ "$before_panes" = "$(tmux list-panes -a -F '#{pane_id}:#{pane_pid}' | sort)" ]
}

# test_necessity: pin-opus専用actionがruntime検証を省くsettings-only経路を必ず拒否する不変量を守る。
@test "pinned Opus 4.6 1M rejects settings-only" {
    root="${BATS_TEST_DIRNAME}/../.."
    script="$root/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh"

    run bash "$script" pin-opus-4.6-1m --repo "$root" --agent gunshi --settings-only

    [ "$status" -ne 0 ]
    [[ "$output" == *"cannot use --settings-only"* ]]
}

make_pin_fixture() {
    fixture="$BATS_TEST_TMPDIR/pin-fixture"
    mkdir -p "$fixture/config" "$fixture/lib" "$fixture/scripts/lib" "$fixture/skills/shogun-cli-switch/scripts" "$fixture/bin"
    printf '#!/usr/bin/env bash\nif [ "${1:-}" = "--version" ]; then echo "2.1.87 (Claude Code)"; else exit 0; fi\n' > "$fixture/bin/claude"
    chmod +x "$fixture/bin/claude"
    cp "${BATS_TEST_DIRNAME}/../../skills/shogun-cli-switch/scripts/shogun_cli_switch.sh" \
        "$fixture/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh"
    printf 'profiles:\n  claude:\n    launch_cmd: pinned\n' >"$fixture/config/cli_profiles.yaml"
    printf 'cli:\n  default: claude\n  agents:\n    gunshi:\n      type: claude\n      model_name: claude-opus-4-6\n' >"$fixture/config/settings.yaml"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$fixture/scripts/switch_cli_mode.sh"
    printf 'check_agent_busy() { return 1; }\n' >"$fixture/lib/agent_state.sh"
    chmod +x "$fixture/scripts/switch_cli_mode.sh"
}

# test_necessity: active workerは設定変更・respawnより前に拒否される不変量を守る。
@test "pinned Opus 4.6 1M refuses a busy worker" {
    make_pin_fixture
    cat >"$fixture/bin/tmux" <<'SH'
#!/usr/bin/env bash
case "$1" in
  list-panes) printf '2 gunshi\n' ;;
  display-message)
    case "$*" in *pane_pid*) printf '4242\n' ;; *) printf 'active\n' ;; esac ;;
  capture-pane) printf 'busy worker output\n' ;;
esac
SH
    cat >"$fixture/bin/ps" <<'SH'
#!/usr/bin/env bash
printf 'codex worker\n'
SH
    chmod +x "$fixture/bin/tmux" "$fixture/bin/ps"
    before="$(sha256sum "$fixture/config/settings.yaml" | awk '{print $1}')"

    run env PATH="$fixture/bin:$PATH" bash "$fixture/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh" \
        pin-opus-4.6-1m --repo "$fixture" --agent gunshi

    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing Opus 4.6 1M pin"* ]]
    [ "$before" = "$(sha256sum "$fixture/config/settings.yaml" | awk '{print $1}')" ]
}

# test_necessity: live processが既に正しければ設定・respawn・コマンド送信なしでfast path成功する不変量を守る。
@test "pinned Opus 4.6 1M already-correct state takes the fast path" {
    make_pin_fixture
    cat >"$fixture/bin/tmux" <<'SH'
#!/usr/bin/env bash
case "$1" in
  list-panes) printf '2 gunshi\n' ;;
  display-message) printf '4242\n' ;;
  capture-pane) printf 'Claude Code v2.1.87\nOpus 4.6 (1M context) with high effort\n' ;;
  set-option|respawn-pane|send-keys) exit 91 ;;
esac
SH
    cat >"$fixture/bin/ps" <<'SH'
#!/usr/bin/env bash
printf "%s --dangerously-skip-permissions --model 'claude-opus-4-6[1m]' --effort high\n" "${PINNED_BIN:-$HOME/bin/claude}"
SH
    chmod +x "$fixture/bin/tmux" "$fixture/bin/ps"
    before="$(sha256sum "$fixture/config/settings.yaml" | awk '{print $1}')"

    run env PATH="$fixture/bin:$PATH" PINNED_BIN="$fixture/bin/claude" bash "$fixture/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh" \
        pin-opus-4.6-1m --repo "$fixture" --agent gunshi

    [ "$status" -eq 0 ]
    [[ "$output" == *"fast_path=already_correct"* ]]
    [ "$before" = "$(sha256sum "$fixture/config/settings.yaml" | awk '{print $1}')" ]
}
