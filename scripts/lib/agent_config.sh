#!/usr/bin/env bash
# agent_config.sh — エージェント名の一元管理ライブラリ
# settings.yamlからエージェント情報を読み取り、関数として提供する。
#
# Usage: source scripts/lib/agent_config.sh
#
# API:
#   get_ninja_names       → role=ninjaのエージェント名をスペース区切りで返す
#   get_all_agents        → karo + 全エージェント名をスペース区切りで返す
#   get_agent_role <name> → ninja / gunshi / karo
#   get_japanese_name <name> → 日本語名
#   get_allowed_targets   → inbox_writeの送信先一覧（karo + 全agents + shogun）
#
# キャッシュ: 初回呼び出し時にsettings.yamlを読み込み、同一プロセス内はキャッシュ

_AGENT_CONFIG_SCRIPT_DIR="${_AGENT_CONFIG_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
_AGENT_CONFIG_SETTINGS="${_AGENT_CONFIG_SCRIPT_DIR}/config/settings.yaml"

# Cache: loaded raw data (tab-separated: name\trole\tjapanese_name)
_AGENT_CONFIG_RAW=""
_AGENT_CONFIG_NINJA_NAMES=""
_AGENT_CONFIG_ALL_NAMES=""

_agent_config_load() {
    # Guard: already loaded in this process
    if [[ -n "$_AGENT_CONFIG_RAW" ]]; then
        return 0
    fi

    _AGENT_CONFIG_RAW=$(SETTINGS_PATH="$_AGENT_CONFIG_SETTINGS" python3 -c "
import yaml, os, sys
try:
    with open(os.environ['SETTINGS_PATH']) as f:
        data = yaml.safe_load(f)
    agents = data.get('cli', {}).get('agents', {})
    for name, conf in agents.items():
        if not isinstance(conf, dict):
            continue
        role = conf.get('role', 'ninja')
        jp = conf.get('japanese_name', name)
        print(f'{name}\t{role}\t{jp}')
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null)

    local ninjas=()
    local all_names=()

    while IFS=$'\t' read -r _ac_name _ac_role _ac_jp; do
        [[ -z "$_ac_name" ]] && continue
        all_names+=("$_ac_name")
        if [[ "$_ac_role" == "ninja" ]]; then
            ninjas+=("$_ac_name")
        fi
    done <<< "$_AGENT_CONFIG_RAW"

    _AGENT_CONFIG_NINJA_NAMES="${ninjas[*]}"
    _AGENT_CONFIG_ALL_NAMES="${all_names[*]}"
}

get_ninja_names() {
    _agent_config_load
    echo "$_AGENT_CONFIG_NINJA_NAMES"
}

get_all_agents() {
    _agent_config_load
    echo "karo $_AGENT_CONFIG_ALL_NAMES"
}

get_agent_role() {
    local name="$1"
    if [[ "$name" == "karo" ]]; then
        echo "karo"
        return 0
    fi
    _agent_config_load
    local role
    role=$(echo "$_AGENT_CONFIG_RAW" | awk -F'\t' -v n="$name" '$1==n{print $2; exit}')
    echo "${role:-ninja}"
}

get_japanese_name() {
    local name="$1"
    if [[ "$name" == "karo" ]]; then
        echo "家老"
        return 0
    fi
    _agent_config_load
    local jp
    jp=$(echo "$_AGENT_CONFIG_RAW" | awk -F'\t' -v n="$name" '$1==n{print $3; exit}')
    echo "${jp:-$name}"
}

get_allowed_targets() {
    _agent_config_load
    echo "karo $_AGENT_CONFIG_ALL_NAMES shogun"
}

get_layout_col1_width_pct() {
    local val
    val=$(grep -A1 '^layout:' "$_AGENT_CONFIG_SETTINGS" | grep 'col1_width_pct:' | sed 's/.*col1_width_pct:[[:space:]]*//')
    echo "${val:-38}"
}

get_layout_karo_height() {
    local val
    val=$(grep -A2 '^layout:' "$_AGENT_CONFIG_SETTINGS" | grep 'karo_height:' | sed 's/.*karo_height:[[:space:]]*//')
    echo "${val:-24}"
}
