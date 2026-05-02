#!/usr/bin/env bash
# cli_adapter.sh — CLI抽象化レイヤー
# Multi-CLI統合設計書 (reports/design_multi_cli_support.md) §2.2 準拠
#
# 提供関数:
#   get_cli_type(agent_id)                  → "claude" | "codex" | "copilot" | "kimi"
#   build_cli_command(agent_id)             → 完全なコマンド文字列
#   get_instruction_file(agent_id [,cli_type]) → 指示書パス
#   get_startup_prompt(cli_type, role)       → 起動時に注入する短い補助prompt
#   validate_cli_availability(cli_type)     → 0=OK, 1=NG
#   get_agent_model(agent_id)               → "opus" | "sonnet" | "codex" | "k2.5"
#   get_model_display_name(agent_id)        → "Opus 4.6" | "gpt-5.5-low" | ...

# プロジェクトルートを基準にsettings.yamlのパスを解決
CLI_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_ADAPTER_PROJECT_ROOT="$(cd "${CLI_ADAPTER_DIR}/.." && pwd)"
CLI_ADAPTER_SETTINGS="${CLI_ADAPTER_SETTINGS:-${CLI_ADAPTER_PROJECT_ROOT}/config/settings.yaml}"

# cli_lookup.sh — CLI Profile SSOT参照（type/profile取得を委譲）
source "${CLI_ADAPTER_PROJECT_ROOT}/scripts/lib/cli_lookup.sh" 2>/dev/null || true

# --- 内部ヘルパー ---

# _cli_adapter_read_yaml key [fallback]
# python3でsettings.yamlから値を読み取る
_cli_adapter_read_yaml() {
    local key_path="$1"
    local fallback="${2:-}"
    local result
    result=$(python3 -c "
import yaml, sys
try:
    with open('${CLI_ADAPTER_SETTINGS}') as f:
        cfg = yaml.safe_load(f) or {}
    keys = '${key_path}'.split('.')
    val = cfg
    for k in keys:
        if isinstance(val, dict):
            val = val.get(k)
        else:
            val = None
            break
    if val is not None:
        print(val)
    else:
        print('${fallback}')
except Exception:
    print('${fallback}')
" 2>/dev/null)
    if [[ -z "$result" ]]; then
        echo "$fallback"
    else
        echo "$result"
    fi
}

# --- 公開API ---

# get_cli_type(agent_id)
# cli_lookup.sh の cli_type() に委譲（SSOTはsettings.yaml）
get_cli_type() {
    local agent_id="$1"
    cli_type "${agent_id:-}"
}

# get_model_display_name(agent_id)
# settings.yamlのcli.agents.{id}.model_nameを表示用名に変換する
get_model_display_name() {
    local agent_id="$1"
    local model_name
    model_name=$(_cli_adapter_read_yaml "cli.agents.${agent_id}.model_name" "")

    if [[ -n "$model_name" ]]; then
        case "$model_name" in
            claude-opus-4-6*)    echo "Opus 4.6" ;;
            claude-opus-4*)      echo "Opus 4" ;;
            claude-sonnet-4-6*)  echo "Sonnet 4.6" ;;
            claude-sonnet-4*)    echo "Sonnet 4" ;;
            claude-haiku-4-5*)   echo "Haiku 4.5" ;;
            claude-haiku-4*)     echo "Haiku 4" ;;
            *)                   echo "$model_name" ;;
        esac
        return 0
    fi

    local display_name
    display_name=$(cli_profile_get "$agent_id" "display_name" 2>/dev/null) || display_name=""
    if [[ -n "$display_name" ]]; then
        echo "$display_name"
        return 0
    fi

    local cli_type
    cli_type=$(get_cli_type "$agent_id" 2>/dev/null) || cli_type="claude"
    case "$cli_type" in
        codex)   echo "Codex" ;;
        copilot) echo "Copilot" ;;
        kimi)    echo "Kimi" ;;
        *)       echo "Claude" ;;
    esac
}

# build_cli_command(agent_id)
# cli_launch_cmd()でベースコマンドを取得し、モデル指定を追加
build_cli_command() {
    local agent_id="$1"
    local ct
    ct=$(cli_type "$agent_id")
    local base_cmd
    base_cmd=$(cli_launch_cmd "$agent_id")
    local model
    model=$(get_agent_model "$agent_id")

    # cli_launch_cmdが空の場合のフォールバック
    if [[ -z "$base_cmd" ]]; then
        base_cmd="$HOME/bin/claude --dangerously-skip-permissions"
    fi

    # launch_cmdからバイナリパスを抽出（最初のトークン）
    local claude_bin="${base_cmd%% *}"
    local base_flags="${base_cmd#* }"
    [[ "$base_flags" == "$base_cmd" ]] && base_flags=""

    # cli_profiles.yamlのlaunch_cmdをベースに、モデル指定を追加
    case "$ct" in
        claude)
            if [[ -n "$model" && "$model" != "opus" ]]; then
                echo "$claude_bin --model $model --effort high $base_flags"
            else
                echo "$claude_bin --effort high $base_flags"
            fi
            ;;
        kimi)
            if [[ -n "$model" ]]; then
                echo "$base_cmd --model $model"
            else
                echo "$base_cmd"
            fi
            ;;
        *)
            echo "$base_cmd"
            ;;
    esac
}

# get_instruction_file(agent_id [,cli_type])
# CLIが自動読込すべき指示書ファイルのパスを返す
get_instruction_file() {
    local agent_id="$1"
    local cli_type="${2:-$(get_cli_type "$agent_id")}"
    local role

    case "$agent_id" in
        shogun)    role="shogun" ;;
        karo)      role="karo" ;;
        gunshi)    role="gunshi" ;;
        sasuke|kirimaru|hayate|kagemaru|hanzo|saizo|kotaro|tobisaru) role="ashigaru" ;;
        *)
            echo "" >&2
            return 1
            ;;
    esac

    case "$cli_type" in
        claude)  echo "instructions/${role}.md" ;;
        codex)   echo "instructions/generated/codex-${role}.md" ;;
        copilot) echo ".github/copilot-instructions-${role}.md" ;;
        kimi)    echo "instructions/generated/kimi-${role}.md" ;;
        *)       echo "instructions/${role}.md" ;;
    esac
}

# get_startup_prompt(cli_type, role)
# CLI起動直後に注入する短い補助promptを返す。
get_startup_prompt() {
    local cli_type="$1"
    local role="$2"

    case "$role" in
        shogun|karo|gunshi|ashigaru|ninja) ;;
        sasuke|kirimaru|hayate|kagemaru|hanzo|saizo|kotaro|tobisaru)
            role="ninja"
            ;;
        *)
            role="ninja"
            ;;
    esac

    case "$cli_type" in
        codex)
            case "$role" in
                shogun)
                    echo "AGENTS.mdを正として/new Recovery (shogun)を実行し、未読inboxを処理せよ。"
                    ;;
                karo)
                    echo "AGENTS.mdを正として/new Recovery (karo)を実行し、queue/karo_snapshot.txtと未読inboxを確認せよ。"
                    ;;
                gunshi)
                    echo "AGENTS.mdを正として/new Recovery (gunshi)を実行し、未読inboxを確認せよ。"
                    ;;
                *)
                    echo "AGENTS.mdを正として/new Recovery (ninja)を実行し、queue/tasks/{your_ninja_name}.yamlを読み直せ。"
                    ;;
            esac
            ;;
        *)
            echo ""
            ;;
    esac
}

# validate_cli_availability(cli_type)
# 指定CLIがシステムにインストールされているか確認
# 0=利用可能, 1=利用不可
validate_cli_availability() {
    local cli_type="$1"
    case "$cli_type" in
        claude)
            command -v claude &>/dev/null || {
                echo "[ERROR] Claude Code CLI not found. Install from https://claude.ai/download" >&2
                return 1
            }
            ;;
        codex)
            command -v codex &>/dev/null || {
                echo "[ERROR] OpenAI Codex CLI not found. Install with: npm install -g @openai/codex" >&2
                return 1
            }
            ;;
        copilot)
            command -v copilot &>/dev/null || {
                echo "[ERROR] GitHub Copilot CLI not found. Install with: brew install copilot-cli" >&2
                return 1
            }
            ;;
        kimi)
            if ! command -v kimi-cli &>/dev/null && ! command -v kimi &>/dev/null; then
                echo "[ERROR] Kimi CLI not found. Install from https://platform.moonshot.cn/" >&2
                return 1
            fi
            ;;
        *)
            echo "[ERROR] Unknown CLI type: '$cli_type'. Allowed: $CLI_ADAPTER_ALLOWED_CLIS" >&2
            return 1
            ;;
    esac
    return 0
}

# get_agent_model(agent_id)
# エージェントが使用すべきモデル名を返す
get_agent_model() {
    local agent_id="$1"

    # まずsettings.yamlのcli.agents.{id}.modelを確認
    local model_from_yaml
    model_from_yaml=$(_cli_adapter_read_yaml "cli.agents.${agent_id}.model" "")

    # model キーがなければ model_name キーをフォールバック参照
    if [[ -z "$model_from_yaml" ]]; then
        model_from_yaml=$(_cli_adapter_read_yaml "cli.agents.${agent_id}.model_name" "")
    fi

    if [[ -n "$model_from_yaml" ]]; then
        # フルモデル名→ショート名変換
        case "$model_from_yaml" in
            claude-opus*|*opus*)       model_from_yaml="opus" ;;
            claude-sonnet*|*sonnet*)   model_from_yaml="sonnet" ;;
            claude-haiku*|*haiku*)     model_from_yaml="haiku" ;;
            claude-*)                  model_from_yaml="opus" ;;
        esac
        echo "$model_from_yaml"
        return 0
    fi

    # 既存のmodelsセクションを確認
    local model_from_models
    model_from_models=$(_cli_adapter_read_yaml "models.${agent_id}" "")

    if [[ -n "$model_from_models" ]]; then
        echo "$model_from_models"
        return 0
    fi

    # デフォルトロジック（CLI種別に応じた初期値）
    local cli_type
    cli_type=$(get_cli_type "$agent_id")

    case "$cli_type" in
        kimi)
            # Kimi CLI用デフォルトモデル
            case "$agent_id" in
                shogun|karo)    echo "k2.5" ;;
                sasuke|kirimaru|hayate|kagemaru|hanzo|saizo|kotaro|tobisaru) echo "k2.5" ;;
                *)              echo "k2.5" ;;
            esac
            ;;
        *)
            # フォールバック: settings.yamlにmodel指定がない場合のデフォルト
            # 現行編成(2026-02-27改革以降)は Opus+Codex を前提
            echo "opus"
            ;;
    esac
}
