#!/bin/bash
# deploy_task/bootstrap.sh — cluster A bootstrap and CLI entrance guards.
# This module is sourced by deploy_task.sh so the legacy shell API remains in
# the caller's process while root, logging, and entrance guards have one home.

set -euo pipefail

# cmd_2078: SCRIPT_DIR string ops — $(cd dirname pwd)サブシェル2個→Bash文字列演算 (~10ms節約)
_dt_self="${DEPLOY_TASK_ENTRYPOINT_SOURCE:-${BASH_SOURCE[0]}}"
[[ "$_dt_self" != /* ]] && _dt_self="$PWD/$_dt_self"
SCRIPT_DIR="${DEPLOY_TASK_ROOT_OVERRIDE:-${_dt_self%/scripts/deploy_task.sh}}"
DEPLOY_TASK_CODE_ROOT="$SCRIPT_DIR"
# shellcheck source=scripts/lib/defense_overhead_writer.sh
source "$SCRIPT_DIR/scripts/lib/defense_overhead_writer.sh"
# Report lifecycle operations share the /tmp-backed lock domain with archive
# and formal review writers (WSL2 /mnt/c flock is not reliable).
if [ -f "$SCRIPT_DIR/scripts/lib/lock_path.sh" ]; then
    source "$SCRIPT_DIR/scripts/lib/lock_path.sh"
else
    # Unit fixtures may copy only deploy_task.sh. Keep the same lock contract
    # available without making the fixture depend on an unrelated helper file.
    lock_path() { printf '%s.lock\n' "$1"; }
fi
unset _dt_self
LOG="$SCRIPT_DIR/logs/deploy_task.log"

# --yaml is an option prefix, never a trailing modifier.  Without this guard,
# `deploy_task.sh ninja --yaml file` is parsed as a legacy message and may
# redeploy the ninja's previous command.  YAML task files use the single
# canonical form `--yaml file ninja`; `--direct` is reserved for cmd IDs.
deploy_task_guard_yaml_arg_order() {
    local index=0 arg
    local first="${1:-}"
    for arg in "$@"; do
        index=$((index + 1))
        if [[ "$arg" == "--yaml" ]]; then
            if [[ "$index" -eq 1 ]] || { [[ "$index" -eq 2 ]] && [[ "$first" == "--direct" ]]; }; then
                return 0
            fi
            echo "BLOCK: --yaml must precede ninja_name (use: deploy_task.sh --yaml <file> <ninja> or --direct --yaml <file> <ninja>)" >&2
            return 2
        fi
    done
    return 0
}

deploy_task_guard_direct_yaml_misuse() {
    [ "${1:-}" = "--direct" ] || return 0
    # canonical form `--direct --yaml <file> <ninja> [cmd_id]` は$3がYAMLパスで正当
    [ "${2:-}" != "--yaml" ] || return 0
    local direct_cmd="${3:-}"
    if [[ "$direct_cmd" == */* || "$direct_cmd" == *.yaml || "$direct_cmd" == *.yml ]]; then
        echo "BLOCK: --direct expects a cmd_id, not a YAML path. Use: deploy_task.sh --yaml <file> <ninja>" >&2
        return 2
    fi
    return 0
}

deploy_task_early_target_from_args() {
    local first="${1:-}"
    shift || true

    if [[ "$first" == "--direct" ]]; then
        first="${1:-}"
        shift || true
    fi

    if [[ "$first" == "--yaml" ]]; then
        shift || true  # yaml file
        first="${1:-}"
    fi

    printf '%s\n' "$first"
}

deploy_task_early_target_known() {
    local target="$1"
    [ -n "$target" ] || return 1
    # cmd_training_speed: awk→grep置換でサブプロセスオーバーヘッド削減(~4ms)
    # エージェント名行は "    name:" のみ(値なし)の形式。フィールド値行("    type: claude"等)はヒットしない
    grep -qE "^    ${target}:[[:space:]]*$" "$SCRIPT_DIR/config/settings.yaml"
}

if [[ "${DEPLOY_TASK_ENTRYPOINT_IS_MAIN:-0}" == "1" \
    && "${DEPLOY_TASK_LIB_ONLY:-0}" != "1" \
    && "${DEPLOY_TASK_SELF_SNAPSHOT_TEST_ONLY:-0}" != "1" ]]; then
    deploy_task_guard_yaml_arg_order "$@" || exit $?
    deploy_task_guard_direct_yaml_misuse "$@" || exit $?
    _dt_early_target="$(deploy_task_early_target_from_args "$@")"
    if [ -z "$_dt_early_target" ] || [ "${_dt_early_target,,}" = "none" ] || [[ "$_dt_early_target" == cmd_* ]]; then
        echo "ERROR: ninja_name is required and must be a configured agent, not '${_dt_early_target:-empty}'." >&2
        exit 1
    fi
    if ! deploy_task_early_target_known "$_dt_early_target"; then
        echo "ERROR: Unknown ninja: $_dt_early_target" >&2
        exit 1
    fi
    unset _dt_early_target
fi

# cli_lookup.sh — CLI Profile SSOT参照（CLI種別判定・パターン取得）
source "$SCRIPT_DIR/scripts/lib/cli_lookup.sh"
source "$SCRIPT_DIR/scripts/lib/model_injection_profile.sh"
source "$SCRIPT_DIR/scripts/lib/agent_config.sh"
source "$SCRIPT_DIR/scripts/lib/project_path.sh"
DEPLOY_NINJA_NAMES="$(get_ninja_names 2>/dev/null || echo 'hayate kagemaru hanzo saizo kotaro tobisaru')"
export DEPLOY_NINJA_NAMES
source "$SCRIPT_DIR/scripts/lib/field_get.sh"
source "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
source "$SCRIPT_DIR/scripts/lib/ctx_utils.sh"
source "$SCRIPT_DIR/scripts/lib/pane_lookup.sh"
source "$SCRIPT_DIR/scripts/lib/tmux_utils.sh"
source "$SCRIPT_DIR/scripts/lib/firefighting_keywords.sh"
source "$SCRIPT_DIR/scripts/lib/gate_hook_quality_contract.sh"
source "$SCRIPT_DIR/lib/agent_state.sh"

# WSL2 NTFS最適化: field_getの依存ログ(flock+stat+write)を抑制。65回×20ms=1.3s削減
export FIELD_GET_NO_LOG=1

DEFAULT_MESSAGE="現task YAMLを正本として読み直して作業開始せよ。inboxはread:falseかつ現task_id一致の補足だけを命令として扱い、read:trueまたは別taskのRC/補足は参照しても適用するな。"
DIRECT_MODE=false
YAML_FILE=""
NINJA_NAME=""
CMD_ID=""
CMD_FORCED=""
MESSAGE="$DEFAULT_MESSAGE"
TYPE="task_assigned"
FROM="karo"
DEPLOY_TASK_MAIN_TIMEOUT_SEC="${DEPLOY_TASK_MAIN_TIMEOUT_SEC:-300}"
DEPLOY_TASK_MAIN_DEADLINE=0
DEPLOY_TASK_DRAFT_REVIEW_ARMED=0
DEPLOY_TASK_DRAFT_REVIEW_SENT=0
DEPLOY_TASK_DRAFT_REVIEW_TASK_FILE=""
DEPLOY_TASK_DRAFT_REVIEW_CMD_ID=""
DEPLOY_TASK_DRAFT_REVIEW_NINJA=""
DEPLOY_TASK_DRAFT_REVIEW_TYPE=""
DEPLOY_TASK_DIRECT_YAML_PREINJECTED=0
DEPLOY_TASK_ISSUE_ATTEMPT_ID=""
DEPLOY_TASK_ISSUE_TERMINAL_RECORDED=0
DEPLOY_TASK_DEPLOY_COMPLETED=0

mkdir -p "$SCRIPT_DIR/logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEPLOY] $1" >> "$LOG"
    echo "[DEPLOY] $1" >&2
}

