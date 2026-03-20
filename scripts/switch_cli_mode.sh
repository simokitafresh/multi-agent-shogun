#!/usr/bin/env bash
# switch_cli_mode.sh — Shogun/Karo failover switch (Claude <-> Codex)
# Usage:
#   bash scripts/switch_cli_mode.sh codex
#   bash scripts/switch_cli_mode.sh claude --scope core
#   bash scripts/switch_cli_mode.sh codex --scope all
#   bash scripts/switch_cli_mode.sh codex --scope shogun,karo --dry-run

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS_FILE="${SCRIPT_DIR}/config/settings.yaml"

source "${SCRIPT_DIR}/lib/cli_adapter.sh"
source "${SCRIPT_DIR}/scripts/lib/cli_lookup.sh"

TARGET_CLI="${1:-}"
SCOPE="core"
DRY_RUN=false
NO_RELAUNCH=false

usage() {
    cat <<'USAGE'
switch_cli_mode.sh — CLI failover switch

Usage:
  bash scripts/switch_cli_mode.sh <claude|codex> [options]

Options:
  --scope <core|all|csv>  Target agents.
                          core = shogun,karo (default)
                          all  = shogun,karo + 8 ninjas
                          csv  = e.g. shogun,karo,saizo
  --dry-run               Show planned changes only.
  --no-relaunch           Update settings only (do not restart pane CLIs).
  -h, --help              Show this help.
USAGE
}

if [[ -z "$TARGET_CLI" ]] || [[ "$TARGET_CLI" == "-h" ]] || [[ "$TARGET_CLI" == "--help" ]]; then
    usage
    exit 0
fi

shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)
            [[ $# -ge 2 ]] || { echo "ERROR: --scope requires a value" >&2; exit 1; }
            SCOPE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-relaunch)
            NO_RELAUNCH=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

case "$TARGET_CLI" in
    claude|codex) ;;
    *)
        echo "ERROR: target CLI must be claude or codex (got: $TARGET_CLI)" >&2
        exit 1
        ;;
esac

if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo "ERROR: settings file not found: $SETTINGS_FILE" >&2
    exit 1
fi

validate_cli_availability "$TARGET_CLI" >/dev/null

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/scripts/lib/agent_config.sh"
read -ra _cfg_agents <<< "$(get_all_agents)"
ALL_AGENTS=(shogun "${_cfg_agents[@]}")
unset _cfg_agents
CORE_AGENTS=(shogun karo)

declare -a TARGET_AGENTS=()
case "$SCOPE" in
    core)
        TARGET_AGENTS=("${CORE_AGENTS[@]}")
        ;;
    all)
        TARGET_AGENTS=("${ALL_AGENTS[@]}")
        ;;
    *)
        IFS=',' read -r -a raw_agents <<< "$SCOPE"
        for a in "${raw_agents[@]}"; do
            a="$(echo "$a" | tr -d '[:space:]')"
            [[ -n "$a" ]] || continue
            TARGET_AGENTS+=("$a")
        done
        ;;
esac

if [[ ${#TARGET_AGENTS[@]} -eq 0 ]]; then
    echo "ERROR: no target agents resolved from --scope=$SCOPE" >&2
    exit 1
fi

declare -A VALID_AGENT_MAP=()
for a in "${ALL_AGENTS[@]}"; do
    VALID_AGENT_MAP["$a"]=1
done

for a in "${TARGET_AGENTS[@]}"; do
    if [[ -z "${VALID_AGENT_MAP[$a]+x}" ]]; then
        echo "ERROR: unknown agent in scope: $a" >&2
        exit 1
    fi
done

echo "[switch_cli_mode] target_cli=${TARGET_CLI} scope=${SCOPE} dry_run=${DRY_RUN} no_relaunch=${NO_RELAUNCH}"

reload_lookup_cache() {
    source "${SCRIPT_DIR}/scripts/lib/cli_lookup.sh"
    source "${SCRIPT_DIR}/lib/cli_adapter.sh"
}

resolve_window_target() {
    local named_target="$1"
    local indexed_target="$2"
    if tmux list-panes -t "$named_target" >/dev/null 2>&1; then
        echo "$named_target"
    else
        echo "$indexed_target"
    fi
}

find_agent_pane() {
    local agent="$1"
    local agents_window
    agents_window=$(resolve_window_target "shogun:agents" "shogun:2")

    local pane_idx
    pane_idx=$(tmux list-panes -t "$agents_window" -F '#{pane_index} #{@agent_id}' 2>/dev/null \
        | awk -v a="$agent" '$2==a {print $1; exit}')
    if [[ -n "$pane_idx" ]]; then
        echo "${agents_window}.${pane_idx}"
        return 0
    fi

    # 動的フォールバック（settings.yamlから — cmd_1136）
    local pane_base
    pane_base=$(tmux show-options -gv pane-base-index 2>/dev/null || echo "1")
    local _offset=0
    local _found=0
    for _fa in $(get_all_agents); do
        if [[ "$_fa" == "$agent" ]]; then
            echo "${agents_window}.$((pane_base + _offset))"
            _found=1
            break
        fi
        ((_offset++)) || true
    done
    [[ "$_found" -eq 0 ]] && return 1
    return 0
}

agent_pane_target() {
    local agent="$1"
    if [[ "$agent" == "shogun" ]]; then
        resolve_window_target "shogun:main" "shogun:1"
        return 0
    fi
    find_agent_pane "$agent"
}

update_agent_type() {
    local agent="$1"
    local current
    current=$(cli_type "$agent")

    if [[ "$current" == "$TARGET_CLI" ]]; then
        echo "  [settings] ${agent}: already ${TARGET_CLI} (skip)"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [settings] ${agent}: ${current} -> ${TARGET_CLI}"
        return 0
    fi

    if ! bash "${SCRIPT_DIR}/scripts/lib/yaml_field_set.sh" "$SETTINGS_FILE" "$agent" "type" "$TARGET_CLI" >/dev/null 2>&1; then
        # Fallback for scalar form: "agent: codex"
        if grep -Eq "^[[:space:]]*${agent}:[[:space:]]*(claude|codex|copilot|kimi)[[:space:]]*$" "$SETTINGS_FILE"; then
            sed -i -E "s|^([[:space:]]*${agent}:[[:space:]]*).*$|\\1${TARGET_CLI}|" "$SETTINGS_FILE"
        else
            echo "ERROR: failed to update settings for ${agent} (unsupported YAML structure)" >&2
            exit 1
        fi
    fi
    echo "  [settings] ${agent}: ${current} -> ${TARGET_CLI}"
}

restart_agent_cli() {
    local agent="$1"
    local target
    target=$(agent_pane_target "$agent")

    if ! tmux list-panes -t "$target" >/dev/null 2>&1; then
        echo "  [runtime] ${agent}: pane not found (${target}), settings only"
        return 0
    fi

    local launch
    launch=$(build_cli_command "$agent")
    local display_name
    display_name=$(cli_profile_get "$agent" "display_name")
    display_name="${display_name:-$TARGET_CLI}"

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [runtime] ${agent}@${target}: relaunch -> ${launch}"
        return 0
    fi

    tmux set-option -p -t "$target" @agent_cli "$TARGET_CLI" >/dev/null 2>&1 || true
    tmux set-option -p -t "$target" @model_name "$display_name" >/dev/null 2>&1 || true

    tmux send-keys -t "$target" C-c
    sleep 0.4
    tmux send-keys -t "$target" C-c
    sleep 0.4
    tmux send-keys -t "$target" "cd \"${SCRIPT_DIR}\" && clear" Enter
    sleep 0.3
    tmux send-keys -t "$target" "$launch" Enter

    echo "  [runtime] ${agent}@${target}: relaunched (${TARGET_CLI})"
}

for agent in "${TARGET_AGENTS[@]}"; do
    update_agent_type "$agent"
done

if [[ "$DRY_RUN" == true ]]; then
    echo "[switch_cli_mode] dry-run complete (no files changed)"
    exit 0
fi

reload_lookup_cache

if ! tmux has-session -t shogun >/dev/null 2>&1; then
    echo "[switch_cli_mode] tmux session 'shogun' not found. Settings updated only."
    exit 0
fi

if [[ "$NO_RELAUNCH" == true ]]; then
    echo "[switch_cli_mode] --no-relaunch: skipped pane restart."
else
    for agent in "${TARGET_AGENTS[@]}"; do
        restart_agent_cli "$agent"
    done

    bash "${SCRIPT_DIR}/scripts/sync_pane_vars.sh" >/dev/null 2>&1 || true
    bash "${SCRIPT_DIR}/scripts/shutsujin_departure.sh" >/dev/null 2>&1 || true
fi

echo "[switch_cli_mode] completed"
echo "[switch_cli_mode] verify: tmux list-panes -a -F '#{session_name}:#{window_name}.#{pane_index} #{@agent_id} #{@agent_cli} #{@model_name}' | grep -E 'shogun|karo'"
