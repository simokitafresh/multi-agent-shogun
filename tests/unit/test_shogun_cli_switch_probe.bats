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
