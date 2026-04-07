#!/usr/bin/env bats
# test_cli_adapter.bats — cli_adapter.sh ユニットテスト
# Multi-CLI統合設計書 §4.1 準拠

# --- セットアップ ---

# =============================================================================
# Pure bash YAML helpers (python3 python3-based functions をオーバーライドして高速化)
# =============================================================================

# cli.agents.<agent>.type を返す（string形式/dict形式両対応）
# cli.defaultも1パスで取得し、フォールバック時の追加forkを排除
_bash_agent_type() {
    local file="$1" agent="$2" default="${3:-claude}"
    [[ -f "$file" ]] || { echo "$default"; return; }
    local in_cli=0 in_agents=0 in_agent=0 result="" cli_default=""
    while IFS= read -r line; do
        if [[ $in_cli -eq 0 ]]; then
            [[ "$line" == "cli:" ]] && { in_cli=1; continue; }
        elif [[ $in_agents -eq 0 ]]; then
            if [[ "$line" == "  default: "* ]]; then
                cli_default="${line#  default: }"
            elif [[ "$line" == "  agents:" ]]; then
                in_agents=1
            elif [[ ! "$line" =~ ^[[:space:]] ]]; then
                in_cli=0
            fi
        elif [[ $in_agent -eq 0 ]]; then
            if [[ "$line" == "    ${agent}: "* ]]; then
                result="${line#*: }"; break          # string形式
            elif [[ "$line" == "    ${agent}:" ]]; then
                in_agent=1                            # dict形式
            elif [[ ! "$line" =~ ^[[:space:]] ]]; then
                break
            fi
        else
            if [[ "$line" == "      type: "* ]]; then
                result="${line#*type: }"; break
            elif [[ "$line" =~ ^"    "[^[:space:]] || ! "$line" =~ ^[[:space:]] ]]; then
                break
            fi
        fi
    done < "$file"
    # cli.defaultフォールバック（追加forkなし）
    [[ -z "$result" ]] && result="$cli_default"
    case "${result}" in
        claude|codex|copilot|kimi) echo "$result" ;;
        *) echo "$default" ;;
    esac
}

# YAML スカラー値を返す
# 対応 key_path: models.<key> / cli.agents.<agent>.<field>
_bash_yaml_val() {
    local file="$1" key_path="$2" default="${3:-}"
    [[ -f "$file" ]] || { echo "$default"; return; }
    local result=""
    case "$key_path" in
        models.*)
            local key="${key_path#models.}"
            local in_models=0
            while IFS= read -r line; do
                if [[ $in_models -eq 0 ]]; then
                    [[ "$line" == "models:" ]] && in_models=1
                elif [[ "$line" == "  ${key}: "* ]]; then
                    result="${line#  ${key}: }"; break
                elif [[ ! "$line" =~ ^[[:space:]] ]]; then
                    break
                fi
            done < "$file"
            ;;
        cli.agents.*.*)
            local rest="${key_path#cli.agents.}"
            local agent="${rest%%.*}" field="${rest#*.}"
            local in_cli=0 in_agents=0 in_agent=0
            while IFS= read -r line; do
                if [[ $in_cli -eq 0 ]]; then
                    [[ "$line" == "cli:" ]] && { in_cli=1; continue; }
                elif [[ $in_agents -eq 0 ]]; then
                    [[ "$line" == "  agents:" ]] && { in_agents=1; continue; }
                    [[ ! "$line" =~ ^[[:space:]] ]] && { in_cli=0; continue; }
                elif [[ $in_agent -eq 0 ]]; then
                    if [[ "$line" == "    ${agent}: "* || "$line" == "    ${agent}:" ]]; then
                        in_agent=1
                    elif [[ ! "$line" =~ ^[[:space:]] ]]; then
                        break
                    fi
                else
                    if [[ "$line" == "      ${field}: "* ]]; then
                        result="${line#*${field}: }"; break
                    elif [[ "$line" =~ ^"    "[^[:space:]] || ! "$line" =~ ^[[:space:]] ]]; then
                        break
                    fi
                fi
            done < "$file"
            ;;
    esac
    echo "${result:-$default}"
}

setup_file() {
    export SETTINGS_DIR
    SETTINGS_DIR="$(mktemp -d)"
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

    # デフォルトsettings（cliセクションなし = 後方互換テスト）
    cat > "${SETTINGS_DIR}/settings_none.yaml" << 'YAML'
language: ja
shell: bash
display_mode: shout
YAML

    # claude only settings
    cat > "${SETTINGS_DIR}/settings_claude_only.yaml" << 'YAML'
cli:
  default: claude
YAML

    # mixed CLI settings (dict形式)
    cat > "${SETTINGS_DIR}/settings_mixed.yaml" << 'YAML'
cli:
  default: claude
  agents:
    shogun:
      type: claude
      model: opus
    karo:
      type: claude
      model: opus
    gunshi:
      type: codex
    sasuke:
      type: codex
    kirimaru:
      type: codex
    hayate:
      type: codex
    kagemaru:
      type: claude
      model: opus
    hanzo:
      type: codex
    saizo:
      type: codex
    kotaro:
      type: copilot
    tobisaru:
      type: copilot
YAML

    # 文字列形式のagent設定
    cat > "${SETTINGS_DIR}/settings_string_agents.yaml" << 'YAML'
cli:
  default: claude
  agents:
    hanzo: codex
    kotaro: copilot
YAML

    # 不正CLI名
    cat > "${SETTINGS_DIR}/settings_invalid_cli.yaml" << 'YAML'
cli:
  default: claudee
  agents:
    sasuke: invalid_cli
YAML

    # codexデフォルト
    cat > "${SETTINGS_DIR}/settings_codex_default.yaml" << 'YAML'
cli:
  default: codex
YAML

    # 空ファイル
    cat > "${SETTINGS_DIR}/settings_empty.yaml" << 'YAML'
YAML

    # YAML構文エラー
    cat > "${SETTINGS_DIR}/settings_broken.yaml" << 'YAML'
cli:
  default: [broken yaml
  agents: {{invalid
YAML

    # モデル指定付き
    cat > "${SETTINGS_DIR}/settings_with_models.yaml" << 'YAML'
cli:
  default: claude
  agents:
    sasuke:
      type: claude
      model: haiku
    hanzo:
      type: codex
      model: gpt-5
models:
  karo: opus
YAML

    # kimi CLI settings
    cat > "${SETTINGS_DIR}/settings_kimi.yaml" << 'YAML'
cli:
  default: claude
  agents:
    hayate:
      type: kimi
      model: k2.5
    kagemaru:
      type: kimi
YAML

    # kimi default settings
    cat > "${SETTINGS_DIR}/settings_kimi_default.yaml" << 'YAML'
cli:
  default: kimi
YAML

    # cli_adapter.sh を1回だけsource（export -fでテスト間共有）
    export CLI_ADAPTER_SETTINGS="${SETTINGS_DIR}/settings_none.yaml"
    source "${PROJECT_ROOT}/lib/cli_adapter.sh"

    # python3-based helpers をpure bash実装でオーバーライド
    _cli_lookup_settings_get() {
        local agent="$1" field="$2" default="$3"
        [[ "$field" == "type" ]] || { echo "$default"; return; }
        _bash_agent_type "$_CLI_LOOKUP_SETTINGS" "$agent" "$default"
    }
    _cli_adapter_read_yaml() {
        local key_path="$1" fallback="${2:-}"
        _bash_yaml_val "$CLI_ADAPTER_SETTINGS" "$key_path" "$fallback"
    }
    _cli_lookup_profile_get() {
        local cli_type="$1" key="$2"
        [[ "$key" != "launch_cmd" ]] && { echo ""; return; }
        case "$cli_type" in
            claude) echo "/home/simokitafresh/bin/claude --dangerously-skip-permissions" ;;
            codex)  echo "codex --dangerously-bypass-approvals-and-sandbox --no-alt-screen" ;;
            *)      echo "" ;;
        esac
    }

    # 全テスト間で関数を共有（export -f により各テストsubprocessへ継承）
    export -f get_cli_type build_cli_command get_instruction_file validate_cli_availability get_agent_model
    export -f cli_type cli_profile_get cli_launch_cmd cli_profile_get_for_type
    export -f _cli_lookup_settings_get _cli_adapter_read_yaml _cli_lookup_profile_get
    export -f _bash_agent_type _bash_yaml_val
}

setup() {
    # TEST_TMPをSETTINGS_DIRに直接指定（mktemp+symlinks不要化）
    TEST_TMP="${SETTINGS_DIR}"
}

teardown() {
    [[ -d "${SETTINGS_DIR}/bin" ]] && rm -rf "${SETTINGS_DIR}/bin" || true
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

# --- 正常系 ---

@test "get_cli_type: cliセクションなし → claude (後方互換)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(get_cli_type "shogun")
    [ "$result" = "claude" ]
}

@test "get_cli_type: claude only設定 → claude" {
    load_adapter_with "${TEST_TMP}/settings_claude_only.yaml"
    result=$(get_cli_type "sasuke")
    [ "$result" = "claude" ]
}

@test "get_cli_type: mixed設定 shogun → claude" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_cli_type "shogun")
    [ "$result" = "claude" ]
}

@test "get_cli_type: mixed設定 hanzo → codex" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_cli_type "hanzo")
    [ "$result" = "codex" ]
}

@test "get_cli_type: mixed設定 kotaro → copilot" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_cli_type "kotaro")
    [ "$result" = "copilot" ]
}

@test "get_cli_type: mixed設定 sasuke → codex (個別設定)" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_cli_type "sasuke")
    [ "$result" = "codex" ]
}

@test "get_cli_type: 文字列形式 hanzo → codex" {
    load_adapter_with "${TEST_TMP}/settings_string_agents.yaml"
    result=$(get_cli_type "hanzo")
    [ "$result" = "codex" ]
}

@test "get_cli_type: 文字列形式 kotaro → copilot" {
    load_adapter_with "${TEST_TMP}/settings_string_agents.yaml"
    result=$(get_cli_type "kotaro")
    [ "$result" = "copilot" ]
}

@test "get_cli_type: kimi設定 hayate → kimi" {
    load_adapter_with "${TEST_TMP}/settings_kimi.yaml"
    result=$(get_cli_type "hayate")
    [ "$result" = "kimi" ]
}

@test "get_cli_type: kimi設定 kagemaru → kimi (モデル指定なし)" {
    load_adapter_with "${TEST_TMP}/settings_kimi.yaml"
    result=$(get_cli_type "kagemaru")
    [ "$result" = "kimi" ]
}

@test "get_cli_type: kimiデフォルト設定 → kimi" {
    load_adapter_with "${TEST_TMP}/settings_kimi_default.yaml"
    result=$(get_cli_type "sasuke")
    [ "$result" = "kimi" ]
}

@test "get_cli_type: 未定義agent → default継承" {
    load_adapter_with "${TEST_TMP}/settings_codex_default.yaml"
    result=$(get_cli_type "hayate")
    [ "$result" = "codex" ]
}

@test "get_cli_type: 空agent_id → claude" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_cli_type "")
    [ "$result" = "claude" ]
}

# --- 全忍者 パターン ---

@test "get_cli_type: mixed設定 全忍者パターン" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    [ "$(get_cli_type sasuke)" = "codex" ]
    [ "$(get_cli_type kirimaru)" = "codex" ]
    [ "$(get_cli_type hayate)" = "codex" ]
    [ "$(get_cli_type kagemaru)" = "claude" ]
    [ "$(get_cli_type hanzo)" = "codex" ]
    [ "$(get_cli_type saizo)" = "codex" ]
    [ "$(get_cli_type kotaro)" = "copilot" ]
    [ "$(get_cli_type tobisaru)" = "copilot" ]
}

# --- エラー系 ---

@test "get_cli_type: 不正CLI名 → claude フォールバック" {
    load_adapter_with "${TEST_TMP}/settings_invalid_cli.yaml"
    result=$(get_cli_type "sasuke")
    [ "$result" = "claude" ]
}

@test "get_cli_type: 不正default → claude フォールバック" {
    load_adapter_with "${TEST_TMP}/settings_invalid_cli.yaml"
    result=$(get_cli_type "karo")
    [ "$result" = "claude" ]
}

@test "get_cli_type: 空YAMLファイル → claude" {
    load_adapter_with "${TEST_TMP}/settings_empty.yaml"
    result=$(get_cli_type "shogun")
    [ "$result" = "claude" ]
}

@test "get_cli_type: YAML構文エラー → claude" {
    load_adapter_with "${TEST_TMP}/settings_broken.yaml"
    result=$(get_cli_type "sasuke")
    [ "$result" = "claude" ]
}

@test "get_cli_type: 存在しないファイル → claude" {
    load_adapter_with "/nonexistent/path/settings.yaml"
    result=$(get_cli_type "shogun")
    [ "$result" = "claude" ]
}

# =============================================================================
# build_cli_command テスト
# =============================================================================

@test "build_cli_command: claude + opus → --modelなし (素claude=1Mコンテキスト)" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(build_cli_command "shogun")
    [[ "$result" != *"--model"* ]]
    [[ "$result" == *"--dangerously-skip-permissions"* ]]
}

@test "build_cli_command: claude + haiku → --model haiku付き" {
    load_adapter_with "${TEST_TMP}/settings_with_models.yaml"
    result=$(build_cli_command "sasuke")
    [[ "$result" == *"--model haiku"* ]]
    [[ "$result" == *"--dangerously-skip-permissions"* ]]
}

@test "build_cli_command: codex → codex --dangerously-bypass-approvals-and-sandbox --no-alt-screen" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(build_cli_command "hanzo")
    [ "$result" = "codex --dangerously-bypass-approvals-and-sandbox --no-alt-screen" ]
}

@test "build_cli_command: cliセクションなし → pinned claude フォールバック" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(build_cli_command "sasuke")
    [[ "$result" == *claude*--dangerously-skip-permissions ]]
}

@test "build_cli_command: settings読取失敗 → pinned claude フォールバック" {
    load_adapter_with "/nonexistent/settings.yaml"
    result=$(build_cli_command "sasuke")
    [[ "$result" == *claude*--dangerously-skip-permissions ]]
}

# =============================================================================
# get_instruction_file テスト
# =============================================================================

@test "get_instruction_file: shogun + claude → instructions/shogun.md" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_instruction_file "shogun")
    [ "$result" = "instructions/shogun.md" ]
}

@test "get_instruction_file: karo + claude → instructions/karo.md" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_instruction_file "karo")
    [ "$result" = "instructions/karo.md" ]
}

@test "get_instruction_file: gunshi + codex → instructions/generated/codex-gunshi.md" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_instruction_file "gunshi")
    [ "$result" = "instructions/generated/codex-gunshi.md" ]
}

@test "get_instruction_file: sasuke + codex → instructions/generated/codex-ashigaru.md" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_instruction_file "sasuke")
    [ "$result" = "instructions/generated/codex-ashigaru.md" ]
}

@test "get_instruction_file: hanzo + codex → instructions/generated/codex-ashigaru.md" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_instruction_file "hanzo")
    [ "$result" = "instructions/generated/codex-ashigaru.md" ]
}

@test "get_instruction_file: kotaro + copilot → .github/copilot-instructions-ashigaru.md" {
    load_adapter_with "${TEST_TMP}/settings_mixed.yaml"
    result=$(get_instruction_file "kotaro")
    [ "$result" = ".github/copilot-instructions-ashigaru.md" ]
}

@test "get_instruction_file: hayate + kimi → instructions/generated/kimi-ashigaru.md" {
    load_adapter_with "${TEST_TMP}/settings_kimi.yaml"
    result=$(get_instruction_file "hayate")
    [ "$result" = "instructions/generated/kimi-ashigaru.md" ]
}

@test "get_instruction_file: shogun + kimi → instructions/generated/kimi-shogun.md" {
    load_adapter_with "${TEST_TMP}/settings_kimi_default.yaml"
    result=$(get_instruction_file "shogun")
    [ "$result" = "instructions/generated/kimi-shogun.md" ]
}

@test "get_instruction_file: cli_type引数で明示指定 (codex)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(get_instruction_file "shogun" "codex")
    [ "$result" = "instructions/generated/codex-shogun.md" ]
}

@test "get_instruction_file: cli_type引数で明示指定 (copilot)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(get_instruction_file "karo" "copilot")
    [ "$result" = ".github/copilot-instructions-karo.md" ]
}

@test "get_instruction_file: 全CLI × 全role組み合わせ" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    # claude
    [ "$(get_instruction_file shogun claude)" = "instructions/shogun.md" ]
    [ "$(get_instruction_file karo claude)" = "instructions/karo.md" ]
    [ "$(get_instruction_file gunshi claude)" = "instructions/gunshi.md" ]
    [ "$(get_instruction_file sasuke claude)" = "instructions/ashigaru.md" ]
    # codex
    [ "$(get_instruction_file shogun codex)" = "instructions/generated/codex-shogun.md" ]
    [ "$(get_instruction_file karo codex)" = "instructions/generated/codex-karo.md" ]
    [ "$(get_instruction_file gunshi codex)" = "instructions/generated/codex-gunshi.md" ]
    [ "$(get_instruction_file hayate codex)" = "instructions/generated/codex-ashigaru.md" ]
    # copilot
    [ "$(get_instruction_file shogun copilot)" = ".github/copilot-instructions-shogun.md" ]
    [ "$(get_instruction_file karo copilot)" = ".github/copilot-instructions-karo.md" ]
    [ "$(get_instruction_file gunshi copilot)" = ".github/copilot-instructions-gunshi.md" ]
    [ "$(get_instruction_file hanzo copilot)" = ".github/copilot-instructions-ashigaru.md" ]
    # kimi
    [ "$(get_instruction_file shogun kimi)" = "instructions/generated/kimi-shogun.md" ]
    [ "$(get_instruction_file karo kimi)" = "instructions/generated/kimi-karo.md" ]
    [ "$(get_instruction_file gunshi kimi)" = "instructions/generated/kimi-gunshi.md" ]
    [ "$(get_instruction_file kotaro kimi)" = "instructions/generated/kimi-ashigaru.md" ]
}

@test "get_instruction_file: 不明なagent_id → 空文字 + return 1" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    run get_instruction_file "unknown_agent"
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_cli_availability テスト
# =============================================================================

@test "validate_cli_availability: claude mock (PATH操作)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    # モックclaudeコマンドを作成
    mkdir -p "${TEST_TMP}/bin"
    echo '#!/bin/bash' > "${TEST_TMP}/bin/claude"
    chmod +x "${TEST_TMP}/bin/claude"
    PATH="${TEST_TMP}/bin:$PATH" run validate_cli_availability "claude"
    [ "$status" -eq 0 ]
}

@test "validate_cli_availability: 不正CLI名 → 1 + エラーメッセージ" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    run validate_cli_availability "invalid_type"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown CLI type"* ]]
}

@test "validate_cli_availability: 空文字 → 1" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    run validate_cli_availability ""
    [ "$status" -eq 1 ]
}

@test "validate_cli_availability: codex mock (PATH操作)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    # モックcodexコマンドを作成
    mkdir -p "${TEST_TMP}/bin"
    echo '#!/bin/bash' > "${TEST_TMP}/bin/codex"
    chmod +x "${TEST_TMP}/bin/codex"
    PATH="${TEST_TMP}/bin:$PATH" run validate_cli_availability "codex"
    [ "$status" -eq 0 ]
}

@test "validate_cli_availability: copilot mock (PATH操作)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/bin"
    echo '#!/bin/bash' > "${TEST_TMP}/bin/copilot"
    chmod +x "${TEST_TMP}/bin/copilot"
    PATH="${TEST_TMP}/bin:$PATH" run validate_cli_availability "copilot"
    [ "$status" -eq 0 ]
}

@test "validate_cli_availability: kimi-cli mock (PATH操作)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/bin"
    echo '#!/bin/bash' > "${TEST_TMP}/bin/kimi-cli"
    chmod +x "${TEST_TMP}/bin/kimi-cli"
    PATH="${TEST_TMP}/bin:$PATH" run validate_cli_availability "kimi"
    [ "$status" -eq 0 ]
}

@test "validate_cli_availability: kimi mock (PATH操作)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    mkdir -p "${TEST_TMP}/bin"
    echo '#!/bin/bash' > "${TEST_TMP}/bin/kimi"
    chmod +x "${TEST_TMP}/bin/kimi"
    PATH="${TEST_TMP}/bin:$PATH" run validate_cli_availability "kimi"
    [ "$status" -eq 0 ]
}

@test "validate_cli_availability: codex未インストール → 1 + エラーメッセージ" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    # PATHからcodexを除外（空PATHは危険なのでminimal PATHを設定）
    PATH="/usr/bin:/bin" run validate_cli_availability "codex"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Codex CLI not found"* ]]
}

@test "validate_cli_availability: kimi未インストール → 1 + エラーメッセージ" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    PATH="/usr/bin:/bin" run validate_cli_availability "kimi"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Kimi CLI not found"* ]]
}

# =============================================================================
# get_agent_model テスト
# =============================================================================

@test "get_agent_model: cliセクションなし shogun → opus (デフォルト)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(get_agent_model "shogun")
    [ "$result" = "opus" ]
}

@test "get_agent_model: cliセクションなし karo → opus (デフォルト)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(get_agent_model "karo")
    [ "$result" = "opus" ]
}

@test "get_agent_model: cliセクションなし sasuke → opus (デフォルト)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(get_agent_model "sasuke")
    [ "$result" = "opus" ]
}

@test "get_agent_model: cliセクションなし hanzo → opus (デフォルト)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(get_agent_model "hanzo")
    [ "$result" = "opus" ]
}

@test "get_agent_model: YAML指定 sasuke → haiku (オーバーライド)" {
    load_adapter_with "${TEST_TMP}/settings_with_models.yaml"
    result=$(get_agent_model "sasuke")
    [ "$result" = "haiku" ]
}

@test "get_agent_model: modelsセクションから取得 karo → opus" {
    load_adapter_with "${TEST_TMP}/settings_with_models.yaml"
    result=$(get_agent_model "karo")
    [ "$result" = "opus" ]
}

@test "get_agent_model: codexエージェントのmodel hanzo → gpt-5" {
    load_adapter_with "${TEST_TMP}/settings_with_models.yaml"
    result=$(get_agent_model "hanzo")
    [ "$result" = "gpt-5" ]
}

@test "get_agent_model: 未知agent → opus (デフォルト)" {
    load_adapter_with "${TEST_TMP}/settings_none.yaml"
    result=$(get_agent_model "unknown_agent")
    [ "$result" = "opus" ]
}

@test "get_agent_model: kimi CLI hayate → k2.5 (YAML指定)" {
    load_adapter_with "${TEST_TMP}/settings_kimi.yaml"
    result=$(get_agent_model "hayate")
    [ "$result" = "k2.5" ]
}

@test "get_agent_model: kimi CLI kagemaru → k2.5 (デフォルト)" {
    load_adapter_with "${TEST_TMP}/settings_kimi.yaml"
    result=$(get_agent_model "kagemaru")
    [ "$result" = "k2.5" ]
}

@test "get_agent_model: kimi CLI shogun → k2.5 (デフォルト)" {
    load_adapter_with "${TEST_TMP}/settings_kimi_default.yaml"
    result=$(get_agent_model "shogun")
    [ "$result" = "k2.5" ]
}

@test "get_agent_model: kimi CLI karo → k2.5 (デフォルト)" {
    load_adapter_with "${TEST_TMP}/settings_kimi_default.yaml"
    result=$(get_agent_model "karo")
    [ "$result" = "k2.5" ]
}
