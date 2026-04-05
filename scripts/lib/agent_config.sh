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

_agent_config_unquote() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
        value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
        value="${value:1:${#value}-2}"
        value="${value//\'\'/\'}"
    fi
    printf '%s' "$value"
}

_agent_config_load() {
    # Guard: already loaded in this process
    if [[ -n "$_AGENT_CONFIG_RAW" ]]; then
        return 0
    fi

    if [[ ! -f "$_AGENT_CONFIG_SETTINGS" ]]; then
        echo "agent_config: settings.yaml not found: $_AGENT_CONFIG_SETTINGS" >&2
        return 1
    fi

    local _ac_raw="" _ac_line="" _ac_name="" _ac_role="" _ac_jp=""
    local _in_cli=0 _in_agents=0 _seen_agents=0
    local _line_value=""

    _flush_agent_row() {
        if [[ -n "$_ac_name" ]]; then
            _ac_raw+="${_ac_name}"$'\t'"${_ac_role:-ninja}"$'\t'"${_ac_jp:-$_ac_name}"$'\n'
        fi
        _ac_name=""
        _ac_role=""
        _ac_jp=""
    }

    while IFS= read -r _ac_line || [[ -n "$_ac_line" ]]; do
        if [[ $_in_cli -eq 0 ]]; then
            [[ "$_ac_line" == "cli:" ]] && _in_cli=1
            continue
        fi

        if [[ $_in_agents -eq 0 ]]; then
            if [[ "$_ac_line" == "  agents:" ]]; then
                _in_agents=1
                continue
            fi
            [[ ! "$_ac_line" =~ ^[[:space:]] ]] && _in_cli=0
            continue
        fi

        if [[ "$_ac_line" =~ ^[[:space:]]{4}([^:#[:space:]][^:]*):[[:space:]]*(.*)$ ]]; then
            _flush_agent_row
            _ac_name="$(_agent_config_unquote "${BASH_REMATCH[1]}")"
            _line_value="${BASH_REMATCH[2]}"
            _seen_agents=1
            if [[ -n "${_line_value//[[:space:]]/}" ]]; then
                _flush_agent_row
            fi
            continue
        fi

        if [[ -z "$_ac_name" ]]; then
            if [[ ! "$_ac_line" =~ ^[[:space:]] ]]; then
                break
            fi
            continue
        fi

        if [[ "$_ac_line" =~ ^[[:space:]]{6}role:[[:space:]]*(.*)$ ]]; then
            _ac_role="$(_agent_config_unquote "${BASH_REMATCH[1]}")"
            continue
        fi

        if [[ "$_ac_line" =~ ^[[:space:]]{6}japanese_name:[[:space:]]*(.*)$ ]]; then
            _ac_jp="$(_agent_config_unquote "${BASH_REMATCH[1]}")"
            continue
        fi

        if [[ ! "$_ac_line" =~ ^[[:space:]]{6} ]]; then
            _flush_agent_row
            [[ ! "$_ac_line" =~ ^[[:space:]] ]] && break
        fi
    done < "$_AGENT_CONFIG_SETTINGS"

    _flush_agent_row
    unset -f _flush_agent_row

    _AGENT_CONFIG_RAW="${_ac_raw%$'\n'}"

    if [[ $_seen_agents -eq 0 || -z "$_AGENT_CONFIG_RAW" ]]; then
        echo "agent_config: no agent entries parsed from settings.yaml" >&2
        return 1
    fi

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
    _agent_config_load || return 1
    echo "$_AGENT_CONFIG_NINJA_NAMES"
}

get_all_agents() {
    _agent_config_load || return 1
    echo "karo $_AGENT_CONFIG_ALL_NAMES"
}

get_agent_role() {
    local name="$1"
    if [[ "$name" == "karo" ]]; then
        echo "karo"
        return 0
    fi
    _agent_config_load || return 1
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
    _agent_config_load || return 1
    local jp
    jp=$(echo "$_AGENT_CONFIG_RAW" | awk -F'\t' -v n="$name" '$1==n{print $3; exit}')
    echo "${jp:-$name}"
}

get_allowed_targets() {
    _agent_config_load || return 1
    echo "karo $_AGENT_CONFIG_ALL_NAMES shogun"
}

get_layout_col1_width_pct() {
    local val
    val=$(grep -A5 '^layout:' "$_AGENT_CONFIG_SETTINGS" | grep 'col1_width_pct:' | head -1)
    val="${val#*:}"
    val="${val//[[:space:]]/}"
    echo "${val:-38}"
}

get_layout_karo_height() {
    local val
    val=$(grep -A5 '^layout:' "$_AGENT_CONFIG_SETTINGS" | grep 'karo_height:' | head -1)
    val="${val#*:}"
    val="${val//[[:space:]]/}"
    echo "${val:-24}"
}
