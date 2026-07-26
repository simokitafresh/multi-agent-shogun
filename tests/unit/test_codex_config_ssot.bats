#!/usr/bin/env bats

# test_necessity: codex respawn paths must never restore a pre-SSOT config, and applying one agent's settings twice must be idempotent.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

# cmd_karo_impl_codex_ssot_test_fixture_20260726: 実 config/settings.yaml を読ませない。
# 旧版は実settingsの hanzo が codex 型であることに依存しており、殿が /shogun-cli-switch で
# 編成を変えると落ちた(実測: HEAD版 hanzo=codex/gpt-5.6-sol-low、作業ツリー hanzo=claude/opus-5-1m-low)。
# 検査すべき不変量は「codex agent への apply が冪等であること」であって「半蔵が codex であること」ではない。
# cli_lookup.sh:22 の CLI_LOOKUP_SETTINGS override で、fixture が自前定義した agent を読ませる。
_write_settings_fixture() {
    cat > "$1" <<'EOF'
cli:
  default: claude
  agents:
    dummycodex:
      type: codex
      model_name: gpt-5.6-sol-low
      role: ninja
      service_tier: default
    dummyclaude:
      type: claude
      model_name: opus-5-1m-low
      role: ninja
      service_tier: default
EOF
}

_write_config_toml() {
    cat > "$1" <<'EOF'
model = "gpt-5.6-sol"
model_reasoning_effort = "high"
service_tier = "fast"
EOF
}

@test "scripts contain no codex_config_restore definition or call" {
    run bash -c 'if rg -n "codex_config_restore" "$1/scripts"; then exit 1; fi' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
}

@test "codex_config_apply_agent is idempotent for a codex SSOT agent (positive control)" {
    fixture="$(mktemp -d)"
    mkdir -p "$fixture/.codex"
    _write_config_toml "$fixture/.codex/config.toml"
    _write_settings_fixture "$fixture/settings.yaml"
    run env HOME="$fixture" PROJECT_ROOT="$PROJECT_ROOT" \
        CLI_LOOKUP_SETTINGS="$fixture/settings.yaml" bash -c '
        set -e
        source "$PROJECT_ROOT/scripts/lib/cli_lookup.sh"
        codex_config_apply_agent dummycodex
        first=$(sha256sum "$HOME/.codex/config.toml" | awk "{print \$1}")
        codex_config_apply_agent dummycodex
        second=$(sha256sum "$HOME/.codex/config.toml" | awk "{print \$1}")
        test "$first" = "$second"
        grep -q "model = \"gpt-5.6-sol\"" "$HOME/.codex/config.toml"
        grep -q "model_reasoning_effort = \"low\"" "$HOME/.codex/config.toml"
        grep -q "service_tier = \"default\"" "$HOME/.codex/config.toml"
    '
    rm -r "$fixture"
    [ "$status" -eq 0 ]
}

@test "codex_config_apply_agent leaves config.toml untouched for a claude agent (negative control)" {
    fixture="$(mktemp -d)"
    mkdir -p "$fixture/.codex"
    _write_config_toml "$fixture/.codex/config.toml"
    _write_settings_fixture "$fixture/settings.yaml"
    before="$(sha256sum "$fixture/.codex/config.toml" | awk '{print $1}')"
    run env HOME="$fixture" PROJECT_ROOT="$PROJECT_ROOT" \
        CLI_LOOKUP_SETTINGS="$fixture/settings.yaml" bash -c '
        set -e
        source "$PROJECT_ROOT/scripts/lib/cli_lookup.sh"
        codex_config_apply_agent dummyclaude
    '
    after="$(sha256sum "$fixture/.codex/config.toml" | awk '{print $1}')"
    rm -r "$fixture"
    [ "$status" -eq 0 ]
    # claude 型 agent へ codex 設定を書かないことが正しい挙動。書けばこの比較が落ちる。
    [ "$before" = "$after" ]
}

@test "codex apply does not depend on the live config/settings.yaml (formation independence)" {
    fixture="$(mktemp -d)"
    mkdir -p "$fixture/.codex"
    _write_config_toml "$fixture/.codex/config.toml"
    _write_settings_fixture "$fixture/settings.yaml"
    # fixture が定義する agent 名は実 settings.yaml に存在しない。実settingsを読む実装なら
    # lookup は既定値へ落ち、model_reasoning_effort は書き換わらない。
    run bash -c 'grep -Eq "^    (dummycodex|dummyclaude):" "$1/config/settings.yaml"' _ "$PROJECT_ROOT"
    [ "$status" -ne 0 ]
    run env HOME="$fixture" PROJECT_ROOT="$PROJECT_ROOT" \
        CLI_LOOKUP_SETTINGS="$fixture/settings.yaml" bash -c '
        set -e
        source "$PROJECT_ROOT/scripts/lib/cli_lookup.sh"
        codex_config_apply_agent dummycodex
        grep -q "model_reasoning_effort = \"low\"" "$HOME/.codex/config.toml"
    '
    rm -r "$fixture"
    [ "$status" -eq 0 ]
}
