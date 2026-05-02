#!/usr/bin/env bats
# test_cli_adapter.bats — cli_adapter.sh ユニットテスト
# Multi-CLI統合設計書 §4.1 準拠

# --- セットアップ ---

# =============================================================================
# Pure bash fixture helpers
# setup_fileで多数の一時YAMLを書かず、fixture名ベースで必要値だけ返す
# =============================================================================

_fixture_name() {
    local file="$1"
    printf '%s\n' "${file##*/}"
}

_fixture_agent_type() {
    local file="$1" agent="$2" default="${3:-claude}"
    local fixture
    fixture=$(_fixture_name "$file")

    case "$fixture:$agent" in
        settings_mixed.yaml:shogun|settings_mixed.yaml:karo|settings_mixed.yaml:kagemaru) echo "claude" ;;
        settings_mixed.yaml:gunshi|settings_mixed.yaml:sasuke|settings_mixed.yaml:kirimaru|settings_mixed.yaml:hayate|settings_mixed.yaml:hanzo|settings_mixed.yaml:saizo) echo "codex" ;;
        settings_mixed.yaml:kotaro|settings_mixed.yaml:tobisaru) echo "copilot" ;;
        settings_string_agents.yaml:hanzo) echo "codex" ;;
        settings_string_agents.yaml:kotaro) echo "copilot" ;;
        settings_invalid_cli.yaml:sasuke) echo "invalid_cli" ;;
        settings_with_models.yaml:sasuke) echo "claude" ;;
        settings_with_models.yaml:hanzo) echo "codex" ;;
        settings_kimi.yaml:hayate|settings_kimi.yaml:kagemaru) echo "kimi" ;;
        *)
            case "$fixture" in
                settings_none.yaml|settings_claude_only.yaml) echo "claude" ;;
                settings_mixed.yaml|settings_string_agents.yaml|settings_with_models.yaml|settings_kimi.yaml) echo "claude" ;;
                settings_invalid_cli.yaml) echo "claudee" ;;
                settings_codex_default.yaml) echo "codex" ;;
                settings_kimi_default.yaml) echo "kimi" ;;
                settings_empty.yaml|settings_broken.yaml) echo "$default" ;;
                *) echo "$default" ;;
            esac
            ;;
    esac
}

_fixture_yaml_val() {
    local file="$1" key_path="$2" default="${3:-}"
    local fixture
    fixture=$(_fixture_name "$file")

    case "$fixture:$key_path" in
        settings_with_models.yaml:cli.agents.sasuke.model) echo "haiku" ;;
        settings_with_models.yaml:cli.agents.hanzo.model) echo "gpt-5" ;;
        settings_with_models.yaml:cli.agents.shogun.model_name) echo "claude-opus-4-6" ;;
        settings_with_models.yaml:cli.agents.kagemaru.model_name) echo "gpt-5.5-low" ;;
        settings_with_models.yaml:cli.agents.kotaro.model_name) echo "claude-sonnet-4-6" ;;
        settings_with_models.yaml:models.karo) echo "opus" ;;
        settings_kimi.yaml:cli.agents.hayate.model) echo "k2.5" ;;
        settings_kimi.yaml:cli.agents.kagemaru.model) echo "" ;;
        *)
            echo "$default"
            ;;
    esac
}

setup_file() {
    export SETTINGS_DIR
    SETTINGS_DIR="$(mktemp -d)"
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

    # cli_adapter.sh を1回だけsource（export -fでテスト間共有）
    export CLI_ADAPTER_SETTINGS="${SETTINGS_DIR}/settings_none.yaml"
    source "${PROJECT_ROOT}/lib/cli_adapter.sh"

    # python3-based helpers をfixture lookupでオーバーライド
    _cli_lookup_settings_get() {
        local agent="$1" field="$2" default="$3"
        [[ "$field" == "type" ]] || { echo "$default"; return; }
        _fixture_agent_type "$_CLI_LOOKUP_SETTINGS" "$agent" "$default"
    }
    _cli_adapter_read_yaml() {
        local key_path="$1" fallback="${2:-}"
        _fixture_yaml_val "$CLI_ADAPTER_SETTINGS" "$key_path" "$fallback"
    }
    _cli_lookup_profile_get() {
        local cli_type="$1" key="$2"
        [[ "$key" != "launch_cmd" ]] && { echo ""; return; }
        case "$cli_type" in
            claude) echo "/home/simokitafresh/bin/claude --dangerously-skip-permissions" ;;
            codex)  echo "codex --dangerously-bypass-approvals-and-sandbox --no-alt-screen" ;;
            kimi)   echo "kimi" ;;
            copilot) echo "copilot" ;;
            *)      echo "" ;;
        esac
    }

    # 全テスト間で関数を共有（export -f により各テストsubprocessへ継承）
    export -f get_cli_type get_model_display_name build_cli_command get_instruction_file get_startup_prompt validate_cli_availability get_agent_model
    export -f cli_type cli_profile_get cli_launch_cmd cli_profile_get_for_type
    export -f _cli_lookup_settings_get _cli_adapter_read_yaml _cli_lookup_profile_get
    export -f _fixture_name _fixture_agent_type _fixture_yaml_val
}

setup() {
    # TEST_TMPはSETTINGS_DIR（read-only設定ファイル参照用）
    TEST_TMP="${SETTINGS_DIR}"
    # モックbin用にテストごとの独立ディレクトリを使用（--jobs並列実行の分離保証）
    TEST_BIN="${BATS_TEST_TMPDIR}/bin"
}

teardown() {
    true  # BATS_TEST_TMPDIRはbatsが自動クリーンアップ
}

teardown_file() {
    rm -rf "$SETTINGS_DIR"
}

# ヘルパー: 特定のsettings.yamlでcli_adapterをロード
# 最適化: source不要。settingsパス更新+cacheクリアのみ（export -fで関数は継承済）
load_adapter_with() {
    local settings_file="$1"
    export CLI_ADAPTER_SETTINGS="$settings_file"
    _CLI_LOOKUP_SETTINGS="$settings_file"
    unset _CLI_LOOKUP_TYPE_CACHE _CLI_LOOKUP_PROFILE_CACHE 2>/dev/null
    declare -gA _CLI_LOOKUP_TYPE_CACHE 2>/dev/null || true
    declare -gA _CLI_LOOKUP_PROFILE_CACHE 2>/dev/null || true
}

# =============================================================================
# get_cli_type テスト
# =============================================================================

@test "get_cli_type: settings variants and ninja matrix" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    [ "$(get_cli_type shogun)" = "claude" ]

    load_adapter_with "${TEST_TMP}/settings_claude_only.yaml"
    [ "$(get_cli_type sasuke)" = "claude" ]

    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    [ "$(get_cli_type "")" = "claude" ]
    [ "$(get_cli_type shogun)" = "claude" ]
    [ "$(get_cli_type sasuke)" = "codex" ]
    [ "$(get_cli_type kirimaru)" = "codex" ]
    [ "$(get_cli_type hayate)" = "codex" ]
    [ "$(get_cli_type kagemaru)" = "claude" ]
    [ "$(get_cli_type hanzo)" = "codex" ]
    [ "$(get_cli_type saizo)" = "codex" ]
    [ "$(get_cli_type kotaro)" = "copilot" ]
    [ "$(get_cli_type tobisaru)" = "copilot" ]

    load_adapter_with "${TEST_TMP}/settings_string_agents.yaml"
    [ "$(get_cli_type hanzo)" = "codex" ]
    [ "$(get_cli_type kotaro)" = "copilot" ]

    load_adapter_with "${TEST_TMP}/settings_kimi.yaml"
    [ "$(get_cli_type hayate)" = "kimi" ]
    [ "$(get_cli_type kagemaru)" = "kimi" ]

    load_adapter_with "${TEST_TMP}/settings_kimi_default.yaml"
    [ "$(get_cli_type sasuke)" = "kimi" ]

    load_adapter_with "${TEST_TMP}/settings_codex_default.yaml"
    [ "$(get_cli_type hayate)" = "codex" ]
}

@test "get_cli_type: fallback cases" {
    load_adapter_with "${TEST_TMP}/settings_invalid_cli.yaml"
    [ "$(get_cli_type sasuke)" = "claude" ]
    [ "$(get_cli_type karo)" = "claude" ]

    load_adapter_with "${TEST_TMP}/settings_empty.yaml"
    [ "$(get_cli_type shogun)" = "claude" ]

    load_adapter_with "${TEST_TMP}/settings_broken.yaml"
    [ "$(get_cli_type sasuke)" = "claude" ]

    load_adapter_with "/nonexistent/path/settings.yaml"
    [ "$(get_cli_type shogun)" = "claude" ]
}

# =============================================================================
# build_cli_command テスト
# =============================================================================

@test "get_model_display_name: model_name variants" {
    load_adapter_with "${TEST_TMP}/settings_with_models.yaml"
    [ "$(get_model_display_name shogun)" = "Opus 4.6" ]
    [ "$(get_model_display_name kagemaru)" = "gpt-5.5-low" ]
    [ "$(get_model_display_name kotaro)" = "Sonnet 4.6" ]
}

@test "build_cli_command: command variants" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(build_cli_command "shogun")
    [[ "$result" != *"--model"* ]]
    [[ "$result" == *"--dangerously-skip-permissions"* ]]

    load_adapter_with "${TEST_TMP}/settings_with_models.yaml"
    result=$(build_cli_command "sasuke")
    [[ "$result" == *"--model haiku"* ]]
    [[ "$result" == *"--dangerously-skip-permissions"* ]]

    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    [ "$(build_cli_command hanzo)" = "codex --dangerously-bypass-approvals-and-sandbox --no-alt-screen" ]

    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(build_cli_command "sasuke")
    [[ "$result" == *claude*--dangerously-skip-permissions ]]

    load_adapter_with "/nonexistent/settings.yaml"
    result=$(build_cli_command "sasuke")
    [[ "$result" == *claude*--dangerously-skip-permissions ]]
}

# =============================================================================
# get_instruction_file テスト
# =============================================================================

@test "get_instruction_file: settings-derived variants" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    [ "$(get_instruction_file shogun)" = "instructions/shogun.md" ]
    [ "$(get_instruction_file karo)" = "instructions/karo.md" ]
    [ "$(get_instruction_file gunshi)" = "instructions/generated/codex-gunshi.md" ]
    [ "$(get_instruction_file sasuke)" = "instructions/generated/codex-ashigaru.md" ]
    [ "$(get_instruction_file hanzo)" = "instructions/generated/codex-ashigaru.md" ]
    [ "$(get_instruction_file kotaro)" = ".github/copilot-instructions-ashigaru.md" ]

    load_adapter_with "${TEST_TMP}/settings_kimi.yaml"
    [ "$(get_instruction_file hayate)" = "instructions/generated/kimi-ashigaru.md" ]

    load_adapter_with "${TEST_TMP}/settings_kimi_default.yaml"
    [ "$(get_instruction_file shogun)" = "instructions/generated/kimi-shogun.md" ]
}

@test "get_instruction_file: explicit CLI matrix and unknown agent" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    [ "$(get_instruction_file shogun claude)" = "instructions/shogun.md" ]
    [ "$(get_instruction_file karo claude)" = "instructions/karo.md" ]
    [ "$(get_instruction_file gunshi claude)" = "instructions/gunshi.md" ]
    [ "$(get_instruction_file sasuke claude)" = "instructions/ashigaru.md" ]
    [ "$(get_instruction_file shogun codex)" = "instructions/generated/codex-shogun.md" ]
    [ "$(get_instruction_file karo codex)" = "instructions/generated/codex-karo.md" ]
    [ "$(get_instruction_file gunshi codex)" = "instructions/generated/codex-gunshi.md" ]
    [ "$(get_instruction_file hayate codex)" = "instructions/generated/codex-ashigaru.md" ]
    [ "$(get_instruction_file shogun copilot)" = ".github/copilot-instructions-shogun.md" ]
    [ "$(get_instruction_file karo copilot)" = ".github/copilot-instructions-karo.md" ]
    [ "$(get_instruction_file gunshi copilot)" = ".github/copilot-instructions-gunshi.md" ]
    [ "$(get_instruction_file hanzo copilot)" = ".github/copilot-instructions-ashigaru.md" ]
    [ "$(get_instruction_file shogun kimi)" = "instructions/generated/kimi-shogun.md" ]
    [ "$(get_instruction_file karo kimi)" = "instructions/generated/kimi-karo.md" ]
    [ "$(get_instruction_file gunshi kimi)" = "instructions/generated/kimi-gunshi.md" ]
    [ "$(get_instruction_file kotaro kimi)" = "instructions/generated/kimi-ashigaru.md" ]

    run get_instruction_file "unknown_agent"
    [ "$status" -eq 1 ]
}

# =============================================================================
# get_startup_prompt テスト
# =============================================================================

@test "get_startup_prompt: codex role prompts and claude empty prompt" {
    result=$(get_startup_prompt "codex" "karo")
    [[ "$result" == *"AGENTS.md"* ]]
    [[ "$result" == *"/new Recovery (karo)"* ]]
    [[ "$result" == *"queue/karo_snapshot.txt"* ]]

    result=$(get_startup_prompt "codex" "hayate")
    [[ "$result" == *"/new Recovery (ninja)"* ]]
    [[ "$result" == *"queue/tasks/{your_ninja_name}.yaml"* ]]

    result=$(get_startup_prompt "claude" "karo")
    [ "$result" = "" ]
}

# =============================================================================
# validate_cli_availability テスト
# =============================================================================

@test "validate_cli_availability: mock commands pass" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_BIN}"
    printf '#!/bin/bash\n' > "${TEST_BIN}/claude"
    printf '#!/bin/bash\n' > "${TEST_BIN}/codex"
    printf '#!/bin/bash\n' > "${TEST_BIN}/copilot"
    printf '#!/bin/bash\n' > "${TEST_BIN}/kimi-cli"
    printf '#!/bin/bash\n' > "${TEST_BIN}/kimi"
    chmod +x "${TEST_BIN}/claude" "${TEST_BIN}/codex" "${TEST_BIN}/copilot" "${TEST_BIN}/kimi-cli" "${TEST_BIN}/kimi"

    PATH="${TEST_BIN}:$PATH" run validate_cli_availability "claude"
    [ "$status" -eq 0 ]
    PATH="${TEST_BIN}:$PATH" run validate_cli_availability "codex"
    [ "$status" -eq 0 ]
    PATH="${TEST_BIN}:$PATH" run validate_cli_availability "copilot"
    [ "$status" -eq 0 ]
    PATH="${TEST_BIN}:$PATH" run validate_cli_availability "kimi"
    [ "$status" -eq 0 ]
    rm -f "${TEST_BIN}/kimi-cli"
    PATH="${TEST_BIN}:$PATH" run validate_cli_availability "kimi"
    [ "$status" -eq 0 ]
}

@test "validate_cli_availability: invalid and missing CLI failures" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    run validate_cli_availability "invalid_type"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown CLI type"* ]]

    run validate_cli_availability ""
    [ "$status" -eq 1 ]

    PATH="/usr/bin:/bin" run validate_cli_availability "codex"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Codex CLI not found"* ]]

    PATH="/usr/bin:/bin" run validate_cli_availability "kimi"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Kimi CLI not found"* ]]
}

# =============================================================================
# get_agent_model テスト
# =============================================================================

@test "get_agent_model: default, override, models, unknown and kimi variants" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    [ "$(get_agent_model shogun)" = "opus" ]
    [ "$(get_agent_model karo)" = "opus" ]
    [ "$(get_agent_model sasuke)" = "opus" ]
    [ "$(get_agent_model hanzo)" = "opus" ]
    [ "$(get_agent_model unknown_agent)" = "opus" ]

    load_adapter_with "${TEST_TMP}/settings_with_models.yaml"
    [ "$(get_agent_model sasuke)" = "haiku" ]
    [ "$(get_agent_model karo)" = "opus" ]
    [ "$(get_agent_model hanzo)" = "gpt-5" ]

    load_adapter_with "${TEST_TMP}/settings_kimi.yaml"
    [ "$(get_agent_model hayate)" = "k2.5" ]
    [ "$(get_agent_model kagemaru)" = "k2.5" ]

    load_adapter_with "${TEST_TMP}/settings_kimi_default.yaml"
    [ "$(get_agent_model shogun)" = "k2.5" ]
    [ "$(get_agent_model karo)" = "k2.5" ]
}
