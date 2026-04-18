#!/usr/bin/env bash
# pane_lookup.sh — エージェント名→tmuxペインターゲット解決
# Usage: source scripts/lib/pane_lookup.sh
#
# API:
#   pane_lookup <agent_name>  → tmuxペインターゲット(例: shogun:agents.7)を標準出力
#
# 解決優先順位:
#   1. ninja_states.yaml(ninja_monitorが定期更新する動的マッピング)
#   2. 静的フォールバック(エージェント名→既知ペイン番号)
#
# deploy_task.sh resolve_pane() / agent_status.sh PANES連想配列 を統合

# SCRIPT_DIR: string ops instead of $(cd dirname pwd) subshells (cmd_2078: pane_lookup.sh最適化)
if [[ -z "${_PANE_LOOKUP_SCRIPT_DIR:-}" ]]; then
    _pl_self="${BASH_SOURCE[0]}"
    [[ "$_pl_self" != /* ]] && _pl_self="$PWD/$_pl_self"
    _PANE_LOOKUP_SCRIPT_DIR="${_pl_self%/scripts/lib/pane_lookup.sh}"
fi

# agent_config.shから動的取得（cmd_1136: ハードコード全廃）
# cmd_2078: includeガード付きagent_config.sh再source(no-op on second call)
# shellcheck source=/dev/null
source "${_PANE_LOOKUP_SCRIPT_DIR}/scripts/lib/agent_config.sh"
unset _pl_self

# cmd_karo_pane_lookup_fix: source時消費側(agent_status.sh / deploy_task.sh)が
# PANE_LOOKUP_AGENT_ORDER と静的マップを即参照するため、初期化をsource時へ戻す。
# pane_lookup() 側も防御的に ensure して、将来の呼出順変更でも空配列のまま落ちないようにする。
_PANE_LOOKUP_INITIALIZED=0
declare -A _PANE_LOOKUP_MAP=()
# shellcheck disable=SC2034
PANE_LOOKUP_AGENT_ORDER=()

_pane_lookup_ensure_init() {
    [[ "${_PANE_LOOKUP_INITIALIZED}" == "1" ]] && return 0
    _agent_config_load  # 親シェルでキャッシュ書込み
    local _pl_all="karo $_AGENT_CONFIG_ALL_NAMES"
    local _pl_idx=1
    local _pl_a
    for _pl_a in $_pl_all; do
        _PANE_LOOKUP_MAP[$_pl_a]="shogun:agents.${_pl_idx}"
        ((_pl_idx++)) || true
    done
    # shellcheck disable=SC2034  # Used externally by agent_status.sh
    read -ra PANE_LOOKUP_AGENT_ORDER <<< "$_pl_all"
    _PANE_LOOKUP_INITIALIZED=1
}

# agent_status.sh等: source後に PANE_LOOKUP_AGENT_ORDER を使う場合はこれを呼べ
pane_lookup_ensure_initialized() {
    _pane_lookup_ensure_init
}

pane_lookup() {
    local name="$1"

    if [ -z "$name" ]; then
        echo "" >&2
        return 1
    fi

    _pane_lookup_ensure_init

    # Source 1: ninja_states.yaml (動的マッピング)
    local states_path="${_PANE_LOOKUP_SCRIPT_DIR}/logs/ninja_states.yaml"
    if [ -f "$states_path" ]; then
        local pane
        pane=$(
            SCRIPT_DIR_ENV="$_PANE_LOOKUP_SCRIPT_DIR" NAME_ENV="$name" python3 - <<'PY' 2>/dev/null
import os
import yaml

try:
    states_path = os.path.join(os.environ['SCRIPT_DIR_ENV'], 'logs', 'ninja_states.yaml')
    with open(states_path) as f:
        data = yaml.safe_load(f)
    ninja = data.get('ninjas', {}).get(os.environ['NAME_ENV'], {})
    print(ninja.get('pane', ''))
except Exception:
    pass
PY
        )
        if [ -n "$pane" ]; then
            echo "$pane"
            return 0
        fi
    fi

    # Source 2: 静的フォールバック
    local static_pane="${_PANE_LOOKUP_MAP[$name]:-}"
    if [ -n "$static_pane" ]; then
        echo "$static_pane"
        return 0
    fi

    echo ""
    return 1
}

# source直後に参照する消費側がいるため、静的マップは定義時点で構築しておく。
_pane_lookup_ensure_init
