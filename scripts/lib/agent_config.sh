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

# Include guard: re-source時のキャッシュ破壊を防ぐ (cmd_2078: pane_lookup.sh二重source問題修正)
# pane_lookup.shが source agent_config.sh すると _AGENT_CONFIG_RAW="" がリセットされ
# awk再実行が2回発生していた。ガードにより初回sourceのキャッシュを保持する。
[[ -n "${_AGENT_CONFIG_LOADED:-}" ]] && return 0
_AGENT_CONFIG_LOADED=1

# SCRIPT_DIR: string ops instead of $(cd) subshell (~5ms savings on WSL2)
if [[ -z "${_AGENT_CONFIG_SCRIPT_DIR:-}" ]]; then
    _ac_self="${BASH_SOURCE[0]}"
    [[ "$_ac_self" != /* ]] && _ac_self="$PWD/$_ac_self"
    _AGENT_CONFIG_SCRIPT_DIR="${_ac_self%/scripts/lib/agent_config.sh}"
fi
_AGENT_CONFIG_SETTINGS="${_AGENT_CONFIG_SCRIPT_DIR}/config/settings.yaml"

# Cache: loaded raw data (tab-separated: name\trole\tjapanese_name)
_AGENT_CONFIG_RAW=""
_AGENT_CONFIG_NINJA_NAMES=""
_AGENT_CONFIG_ALL_NAMES=""
# Associative arrays for O(1) per-agent lookups (eliminates echo|awk spawns)
declare -A _AGENT_CONFIG_ROLE_MAP=()
declare -A _AGENT_CONFIG_JP_MAP=()

_agent_config_load() {
    # Guard: already loaded in this process
    if [[ -n "$_AGENT_CONFIG_RAW" ]]; then
        return 0
    fi

    # Parse settings.yaml agents section with awk (python3 eliminates ~36ms subprocess)
    _AGENT_CONFIG_RAW=$(awk '
        /^  agents:[[:space:]]*$/ { in_agents=1; next }
        in_agents && !/^    / {
            if (cur != "") print cur "\t" role "\t" (jp!="" ? jp : cur)
            in_agents=0; next
        }
        in_agents && /^    [a-z][a-z_0-9]*:[[:space:]]*$/ {
            if (cur != "") print cur "\t" role "\t" (jp!="" ? jp : cur)
            cur = $0; sub(/^[ \t]+/, "", cur); sub(/:[[:space:]]*$/, "", cur)
            role = "ninja"; jp = ""; next
        }
        in_agents && cur != "" && /^      role:/ {
            v = $0; sub(/.*role:[[:space:]]*/, "", v); gsub(/[[:space:]\r]/, "", v)
            if (v != "") role = v; next
        }
        in_agents && cur != "" && /^      japanese_name:/ {
            v = $0; sub(/.*japanese_name:[[:space:]]*/, "", v)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
            if (v != "") jp = v; next
        }
        END { if (cur != "" && in_agents) print cur "\t" role "\t" (jp != "" ? jp : cur) }
    ' "$_AGENT_CONFIG_SETTINGS")

    local ninjas=()
    local all_names=()

    while IFS=$'\t' read -r _ac_name _ac_role _ac_jp; do
        [[ -z "$_ac_name" ]] && continue
        all_names+=("$_ac_name")
        _AGENT_CONFIG_ROLE_MAP["$_ac_name"]="$_ac_role"
        _AGENT_CONFIG_JP_MAP["$_ac_name"]="${_ac_jp:-$_ac_name}"
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
    echo "${_AGENT_CONFIG_ROLE_MAP[$name]:-ninja}"
}

get_japanese_name() {
    local name="$1"
    if [[ "$name" == "karo" ]]; then
        echo "家老"
        return 0
    fi
    _agent_config_load
    echo "${_AGENT_CONFIG_JP_MAP[$name]:-$name}"
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
