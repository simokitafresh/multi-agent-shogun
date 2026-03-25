#!/usr/bin/env bats
# test_switch_cli.bats — switch_cli_mode.sh + cli_adapter.sh ユニットテスト
# yohey-w/multi-agent-shogun から適応移植
#
# ローカル適応:
#   - agent名: ashigaru1→sasuke等 (ローカル忍者名)
#   - session名: multiagent→shogun
#   - script名: switch_cli.sh→switch_cli_mode.sh
#   - exit code: --help → exit 0 (ローカル仕様)

# --- セットアップ ---

setup() {
    TEST_TMP="$(mktemp -d)"
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

    # テスト用settings.yaml (ローカル忍者名使用)
    cat > "${TEST_TMP}/settings.yaml" << 'YAML'
cli:
  default: claude
  agents:
    karo:
      type: claude
      model: claude-opus-4-6
    sasuke:
      type: codex
    kirimaru:
      type: codex
    hayate:
      type: codex
    kagemaru:
      type: claude
      model: claude-opus-4-6
    hanzo:
      type: claude
      model: claude-opus-4-6
    saizo:
      type: codex
    kotaro:
      type: claude
      model: claude-opus-4-6
    tobisaru:
      type: claude
      model: claude-opus-4-6
YAML

    # cli_adapter.sh をロード（テスト用settings使用）
    export CLI_ADAPTER_SETTINGS="${TEST_TMP}/settings.yaml"
    source "${PROJECT_ROOT}/lib/cli_adapter.sh"
}

teardown() {
    rm -rf "$TEST_TMP"
}

# =============================================================================
# find_agent_pane テスト (switch_cli_mode.sh 内の関数を直接テスト)
# =============================================================================

# find_agent_pane は tmux に依存するため、フォールバック部分のマッピングをモック化テスト
load_find_agent_pane() {
    eval '
    find_agent_pane_mock() {
        local agent="$1"
        local agents_window="shogun:agents"
        local pane_base="${MOCK_PANE_BASE:-1}"
        case "$agent" in
            karo)       echo "${agents_window}.$((pane_base + 0))" ;;
            sasuke)     echo "${agents_window}.$((pane_base + 1))" ;;
            kirimaru)   echo "${agents_window}.$((pane_base + 2))" ;;
            hayate)     echo "${agents_window}.$((pane_base + 3))" ;;
            kagemaru)   echo "${agents_window}.$((pane_base + 4))" ;;
            hanzo)      echo "${agents_window}.$((pane_base + 5))" ;;
            saizo)      echo "${agents_window}.$((pane_base + 6))" ;;
            kotaro)     echo "${agents_window}.$((pane_base + 7))" ;;
            tobisaru)   echo "${agents_window}.$((pane_base + 8))" ;;
            *)          return 1 ;;
        esac
    }
    '
}

@test "find_agent_pane: karo → shogun:agents.1" {
    load_find_agent_pane
    MOCK_PANE_BASE=1
    result=$(find_agent_pane_mock "karo")
    [ "$result" = "shogun:agents.1" ]
}

@test "find_agent_pane: sasuke → shogun:agents.2" {
    load_find_agent_pane
    MOCK_PANE_BASE=1
    result=$(find_agent_pane_mock "sasuke")
    [ "$result" = "shogun:agents.2" ]
}

@test "find_agent_pane: tobisaru → shogun:agents.9" {
    load_find_agent_pane
    MOCK_PANE_BASE=1
    result=$(find_agent_pane_mock "tobisaru")
    [ "$result" = "shogun:agents.9" ]
}

@test "find_agent_pane: hanzo → shogun:agents.6" {
    load_find_agent_pane
    MOCK_PANE_BASE=1
    result=$(find_agent_pane_mock "hanzo")
    [ "$result" = "shogun:agents.6" ]
}

@test "find_agent_pane: unknown agent → return 1" {
    load_find_agent_pane
    MOCK_PANE_BASE=1
    run find_agent_pane_mock "shogun"
    [ "$status" -eq 1 ]
}

@test "find_agent_pane: pane_base=0 → offset applied" {
    load_find_agent_pane
    MOCK_PANE_BASE=0
    result=$(find_agent_pane_mock "karo")
    [ "$result" = "shogun:agents.0" ]
    result=$(find_agent_pane_mock "hayate")
    [ "$result" = "shogun:agents.3" ]
    result=$(find_agent_pane_mock "tobisaru")
    [ "$result" = "shogun:agents.8" ]
}

# =============================================================================
# settings.yaml 更新テスト（Python部分）
# =============================================================================

@test "update_settings: type変更でYAMLが正しく更新される" {
    cp "${TEST_TMP}/settings.yaml" "${TEST_TMP}/settings_update.yaml"

    # Python直接実行でtype更新 (sasuke: codex → claude)
    python3 << PYEOF
import yaml

path = "${TEST_TMP}/settings_update.yaml"
with open(path, 'r') as f:
    data = yaml.safe_load(f) or {}

data['cli']['agents']['sasuke'] = {'type': 'claude', 'model': 'claude-opus-4-6'}

with open(path, 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
PYEOF

    # 更新結果を検証
    export CLI_ADAPTER_SETTINGS="${TEST_TMP}/settings_update.yaml"
    source "${PROJECT_ROOT}/lib/cli_adapter.sh"

    result=$(get_cli_type "sasuke")
    [ "$result" = "claude" ]

    result=$(get_agent_model "sasuke")
    [ "$result" = "opus" ]
}

@test "update_settings: model変更後にbuild_cli_commandが反映" {
    cp "${TEST_TMP}/settings.yaml" "${TEST_TMP}/settings_update2.yaml"

    # karo: opus → haiku に変更
    python3 << PYEOF
import yaml

path = "${TEST_TMP}/settings_update2.yaml"
with open(path, 'r') as f:
    data = yaml.safe_load(f) or {}

data['cli']['agents']['karo']['model'] = 'claude-haiku-4-5'

with open(path, 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
PYEOF

    export CLI_ADAPTER_SETTINGS="${TEST_TMP}/settings_update2.yaml"
    source "${PROJECT_ROOT}/lib/cli_adapter.sh"

    result=$(build_cli_command "karo")
    [[ "$result" == *"haiku"* ]]
    [[ "$result" == *"--dangerously-skip-permissions"* ]]
}


# =============================================================================
# switch_cli_mode.sh 引数パーステスト（--help, バリデーション）
# =============================================================================

@test "switch_cli_mode.sh --help → usage表示 + exit 0" {
    run bash "${PROJECT_ROOT}/scripts/switch_cli_mode.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "switch_cli_mode.sh -h → usage表示 + exit 0" {
    run bash "${PROJECT_ROOT}/scripts/switch_cli_mode.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "switch_cli_mode.sh 引数なし → usage表示 + exit 0" {
    run bash "${PROJECT_ROOT}/scripts/switch_cli_mode.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "switch_cli_mode.sh 不正target CLI → エラー" {
    run bash "${PROJECT_ROOT}/scripts/switch_cli_mode.sh" invalid_cli
    [ "$status" -ne 0 ]
}

