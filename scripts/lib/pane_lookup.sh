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

_PANE_LOOKUP_SCRIPT_DIR="${_PANE_LOOKUP_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# 静的フォールバックマッピング
declare -A _PANE_LOOKUP_MAP=(
    [karo]="shogun:agents.1"
    [sasuke]="shogun:agents.2"
    [kirimaru]="shogun:agents.3"
    [hayate]="shogun:agents.4"
    [kagemaru]="shogun:agents.5"
    [hanzo]="shogun:agents.6"
    [saizo]="shogun:agents.7"
    [kotaro]="shogun:agents.8"
    [tobisaru]="shogun:agents.9"
)

# エージェント名の順序リスト（表示用。source先で参照）
# shellcheck disable=SC2034
PANE_LOOKUP_AGENT_ORDER=(karo sasuke kirimaru hayate kagemaru hanzo saizo kotaro tobisaru)

pane_lookup() {
    local name="$1"

    if [ -z "$name" ]; then
        echo "" >&2
        return 1
    fi

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
