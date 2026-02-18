#!/usr/bin/env bash
# cli_lookup.sh — CLI Profile SSOT参照ライブラリ
# cmd_143 Phase 1: Profile SSOT基盤
#
# Usage: source scripts/lib/cli_lookup.sh
#
# 提供関数:
#   cli_type <agent_name>          → "claude" / "codex"
#   cli_tier <agent_name>          → "jonin" / "genin"
#   cli_profile_get <agent_name> <key> → cli_profiles.yamlから任意のキーを取得
#   cli_launch_cmd <agent_name>    → 起動コマンド文字列
#   is_genin <agent_name>          → true(0) / false(1)
#   is_jonin <agent_name>          → true(0) / false(1)
#
# 設計:
#   settings.yaml → type取得 → cli_profiles.yaml → 値取得 の2段参照
#   python3 -c でYAMLパース（yqがない環境を想定）
#   同一セッション内の繰り返し呼び出しに変数キャッシュで対応

# パス解決（source元からの相対パス）
_CLI_LOOKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_CLI_LOOKUP_SETTINGS="${_CLI_LOOKUP_DIR}/config/settings.yaml"
_CLI_LOOKUP_PROFILES="${_CLI_LOOKUP_DIR}/config/cli_profiles.yaml"

# キャッシュ（連想配列、bash 4+）
declare -A _CLI_LOOKUP_TYPE_CACHE 2>/dev/null || true
declare -A _CLI_LOOKUP_TIER_CACHE 2>/dev/null || true
declare -A _CLI_LOOKUP_PROFILE_CACHE 2>/dev/null || true

# --- 内部ヘルパー ---

# _cli_lookup_settings_get <agent_name> <field> <default>
# settings.yaml の cli.agents.<agent_name>.<field> を取得
_cli_lookup_settings_get() {
    local agent="$1"
    local field="$2"
    local default="$3"
    python3 -c "
import yaml, sys
try:
    with open('${_CLI_LOOKUP_SETTINGS}') as f:
        cfg = yaml.safe_load(f) or {}
    cli = cfg.get('cli', {})
    agents = cli.get('agents', {}) if isinstance(cli, dict) else {}
    agent_cfg = agents.get('${agent}', {})
    if isinstance(agent_cfg, dict):
        val = agent_cfg.get('${field}', '')
        if val:
            print(val)
            sys.exit(0)
    default_val = cli.get('default', '${default}') if isinstance(cli, dict) else '${default}'
    if '${field}' == 'type':
        print(default_val)
    else:
        print('${default}')
except Exception:
    print('${default}')
" 2>/dev/null
}

# _cli_lookup_profile_get <cli_type> <key>
# cli_profiles.yaml の profiles.<cli_type>.<key> を取得
_cli_lookup_profile_get() {
    local cli_type="$1"
    local key="$2"
    python3 -c "
import yaml, sys
try:
    with open('${_CLI_LOOKUP_PROFILES}') as f:
        cfg = yaml.safe_load(f) or {}
    profiles = cfg.get('profiles', {})
    profile = profiles.get('${cli_type}', {})
    val = profile.get('${key}', '')
    if isinstance(val, list):
        print('|'.join(str(v) for v in val))
    elif isinstance(val, bool):
        print('true' if val else 'false')
    else:
        print(val if val is not None else '')
except Exception:
    print('')
" 2>/dev/null
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
    _CLI_LOOKUP_TYPE_CACHE[$agent]="$result"
    echo "$result"
}

# cli_tier <agent_name>
# settings.yaml の cli.agents.<name>.tier を返す。未定義なら "jonin"
cli_tier() {
    local agent="$1"
    if [[ -z "$agent" ]]; then
        echo "jonin"
        return 0
    fi

    # キャッシュ確認
    if [[ -n "${_CLI_LOOKUP_TIER_CACHE[$agent]+x}" ]]; then
        echo "${_CLI_LOOKUP_TIER_CACHE[$agent]}"
        return 0
    fi

    local result
    result=$(_cli_lookup_settings_get "$agent" "tier" "jonin")
    _CLI_LOOKUP_TIER_CACHE[$agent]="$result"
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

# cli_launch_cmd <agent_name>
# 起動コマンド文字列を返す
cli_launch_cmd() {
    cli_profile_get "$1" "launch_cmd"
}

# is_genin <agent_name>
# 下忍ならtrue(0)、それ以外ならfalse(1)
is_genin() {
    local tier
    tier=$(cli_tier "$1")
    [[ "$tier" == "genin" ]]
}

# is_jonin <agent_name>
# 上忍ならtrue(0)、それ以外ならfalse(1)
is_jonin() {
    local tier
    tier=$(cli_tier "$1")
    [[ "$tier" == "jonin" ]]
}
