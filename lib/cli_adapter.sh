#!/usr/bin/env bash
# cli_adapter.sh — CLI抽象化レイヤー
# Multi-CLI統合設計書 (reports/design_multi_cli_support.md) §2.2 準拠
#
# 提供関数:
#   get_cli_type(agent_id)                  → "claude" | "codex" | "copilot" | "kimi"
#   build_cli_command(agent_id)             → 完全なコマンド文字列
#   get_instruction_file(agent_id [,cli_type]) → 指示書パス
#   validate_cli_availability(cli_type)     → 0=OK, 1=NG
#   get_agent_model(agent_id)               → "opus" | "sonnet" | "haiku" | "k2.5"

# プロジェクトルートを基準にsettings.yamlのパスを解決
CLI_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_ADAPTER_PROJECT_ROOT="$(cd "${CLI_ADAPTER_DIR}/.." && pwd)"
CLI_ADAPTER_SETTINGS="${CLI_ADAPTER_SETTINGS:-${CLI_ADAPTER_PROJECT_ROOT}/config/settings.yaml}"

# cli_lookup.sh — CLI Profile SSOT参照（type/tier/profile取得を委譲）
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
        base_cmd="claude --dangerously-skip-permissions"
    fi

    # cli_profiles.yamlのlaunch_cmdをベースに、モデル指定を追加
    case "$ct" in
        claude)
            if [[ -n "$model" ]]; then
                # "claude --flags..." → "claude --model X --flags..."
                echo "claude --model $model ${base_cmd#claude }"
            else
                echo "$base_cmd"
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
        sasuke|kirimaru|hayate|kagemaru|hanzo|saizo|kotaro|tobisaru) role="ashigaru" ;;
        *)
            echo "" >&2
            return 1
            ;;
    esac

    case "$cli_type" in
        claude)  echo "instructions/${role}.md" ;;
        codex)   echo "instructions/codex-${role}.md" ;;
        copilot) echo ".github/copilot-instructions-${role}.md" ;;
        kimi)    echo "instructions/generated/kimi-${role}.md" ;;
        *)       echo "instructions/${role}.md" ;;
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
            # フォールバック: settings.yamlにmodel_nameがない場合、tierベースで判定
            # (エージェント名のハードコード禁止 — settings.yamlがSSOT)
            local tier
            tier=$(_cli_adapter_read_yaml "cli.agents.${agent_id}.tier" "jonin")
            case "$tier" in
                genin)  echo "sonnet" ;;
                jonin)  echo "opus" ;;
                *)      echo "sonnet" ;;
            esac
            ;;
    esac
}
