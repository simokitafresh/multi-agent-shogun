#!/usr/bin/env bash
# cli_lookup.sh — CLI Profile SSOT参照ライブラリ
# cmd_143 Phase 1: Profile SSOT基盤
#
# Usage: source scripts/lib/cli_lookup.sh
#
# 提供関数:
#   cli_type <agent_name>          → "claude" / "codex"
#   cli_profile_get <agent_name> <key> → cli_profiles.yamlから任意のキーを取得
#   cli_launch_cmd <agent_name>    → 起動コマンド文字列
#
# 設計:
#   settings.yaml → type取得 → cli_profiles.yaml → 値取得 の2段参照
#   python3 -c でYAMLパース（yqがない環境を想定）
#   同一セッション内の繰り返し呼び出しに変数キャッシュで対応

# パス解決（source元からの相対パス）
_CLI_LOOKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_CLI_LOOKUP_SETTINGS="${CLI_ADAPTER_SETTINGS:-${_CLI_LOOKUP_DIR}/config/settings.yaml}"
_CLI_LOOKUP_PROFILES="${_CLI_LOOKUP_DIR}/config/cli_profiles.yaml"

# キャッシュ（連想配列、bash 4+）
# re-source時にキャッシュをクリアし、declare -gAでグローバルスコープに宣言
# （関数内からsourceされた場合でもグローバルになるよう -g フラグを使用）
unset _CLI_LOOKUP_TYPE_CACHE _CLI_LOOKUP_PROFILE_CACHE 2>/dev/null
declare -gA _CLI_LOOKUP_TYPE_CACHE 2>/dev/null || declare -A _CLI_LOOKUP_TYPE_CACHE 2>/dev/null || true
declare -gA _CLI_LOOKUP_PROFILE_CACHE 2>/dev/null || declare -A _CLI_LOOKUP_PROFILE_CACHE 2>/dev/null || true

# --- 内部ヘルパー ---

# _cli_lookup_settings_get <agent_name> <field> <default>
# settings.yaml の cli.agents.<agent_name>.<field> を取得
_cli_lookup_settings_get() {
    local agent="$1"
    local field="$2"
    local default="$3"
    python3 - "$_CLI_LOOKUP_SETTINGS" "$agent" "$field" "$default" <<'PYEOF' 2>/dev/null
import yaml, sys
settings_path, agent, field, default = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    with open(settings_path) as f:
        cfg = yaml.safe_load(f) or {}
    cli = cfg.get('cli', {})
    agents = cli.get('agents', {}) if isinstance(cli, dict) else {}
    agent_cfg = agents.get(agent, {})
    if isinstance(agent_cfg, str):
        if field == 'type':
            print(agent_cfg)
            sys.exit(0)
        else:
            print(default)
            sys.exit(0)
    elif isinstance(agent_cfg, dict):
        val = agent_cfg.get(field, '')
        if val:
            print(val)
            sys.exit(0)
    default_val = cli.get('default', default) if isinstance(cli, dict) else default
    if field == 'type':
        print(default_val)
    else:
        print(default)
except Exception:
    print(default)
PYEOF
}

# _cli_lookup_profile_get <cli_type> <key>
# cli_profiles.yaml の profiles.<cli_type>.<key> を取得
_cli_lookup_profile_get() {
    local cli_type="$1"
    local key="$2"
    python3 - "$_CLI_LOOKUP_PROFILES" "$cli_type" "$key" <<'PYEOF' 2>/dev/null
import yaml, sys
profiles_path, cli_type, key = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(profiles_path) as f:
        cfg = yaml.safe_load(f) or {}
    profiles = cfg.get('profiles', {})
    profile = profiles.get(cli_type, {})
    val = profile.get(key, '')
    if isinstance(val, list):
        print('|'.join(str(v) for v in val))
    elif isinstance(val, bool):
        print('true' if val else 'false')
    else:
        print(val if val is not None else '')
except Exception:
    print('')
PYEOF
}

# --- 公開API ---

# cli_type <agent_name>
# settings.yaml の cli.agents.<name>.type を返す。未定義なら cli.default → "claude"
cli_type() {
    local agent="$1"
    if [[ -z "$agent" ]]; then
        echo "claude"
        return 0
    fi

    # キャッシュ確認
    if [[ -n "${_CLI_LOOKUP_TYPE_CACHE[$agent]+x}" ]]; then
        echo "${_CLI_LOOKUP_TYPE_CACHE[$agent]}"
        return 0
    fi

    local result
    result=$(_cli_lookup_settings_get "$agent" "type" "claude")
    # 不正なCLI種別はclaude にフォールバック
    case "$result" in
        claude|codex|copilot|kimi) ;;
        *) result="claude" ;;
    esac
    _CLI_LOOKUP_TYPE_CACHE[$agent]="$result"
    echo "$result"
}

# cli_profile_get <agent_name> <key>
# settings.yaml → type特定 → cli_profiles.yaml から任意のキーを取得
cli_profile_get() {
    local agent="$1"
    local key="$2"

    # キャッシュ確認
    local cache_key="${agent}:${key}"
    if [[ -n "${_CLI_LOOKUP_PROFILE_CACHE[$cache_key]+x}" ]]; then
        echo "${_CLI_LOOKUP_PROFILE_CACHE[$cache_key]}"
        return 0
    fi

    local ct
    ct=$(cli_type "$agent")
    local result
    result=$(_cli_lookup_profile_get "$ct" "$key")
    _CLI_LOOKUP_PROFILE_CACHE[$cache_key]="$result"
    echo "$result"
}

# cli_profile_get_for_type <cli_type> <key>
# CLI typeを直接指定してcli_profiles.yamlからプロファイル値を取得
# agent名→settings.yaml→type解決をスキップする（ランタイムオーバーライド用）
cli_profile_get_for_type() {
    local cli_type="$1"
    local key="$2"
    _cli_lookup_profile_get "$cli_type" "$key"
}

# cli_model_display <agent_name>
# settings.yamlのmodel_nameからユーザーフレンドリーな表示名を導出
# claude-opus-4-6 → "Opus 4.6", claude-sonnet-4-6 → "Sonnet 4.6", gpt-5.4 → "gpt-5.4"
cli_model_display() {
    local agent="$1"
    local model_name
    model_name=$(_cli_lookup_settings_get "$agent" "model_name" "")
    if [[ -z "$model_name" ]]; then
        return 1
    fi
    case "$model_name" in
        claude-opus-4-6*)    echo "Opus 4.6" ;;
        claude-opus-4*)      echo "Opus 4" ;;
        claude-sonnet-4-6*)  echo "Sonnet 4.6" ;;
        claude-sonnet-4*)    echo "Sonnet 4" ;;
        claude-haiku-4-5*)   echo "Haiku 4.5" ;;
        claude-haiku-4*)     echo "Haiku 4" ;;
        *)                   echo "$model_name" ;;
    esac
}

# cli_launch_cmd <agent_name>
# 起動コマンド文字列を返す
cli_launch_cmd() {
    cli_profile_get "$1" "launch_cmd"
}
