#!/bin/bash
# semantic-links: [[スコープ鮮度ライフサイクル]], [[タスク修飾子注入]], [[編成管理]]
# shellcheck disable=SC1091
# deploy_task.sh — legacy-compatible task deployment entrypoint.
# Usage: bash scripts/deploy_task.sh [--direct] <ninja_name> [cmd_id] [message] [type] [from]

# A long-lived deployment must never continue parsing the mutable working-tree
# file after delivery. Validate one private /tmp copy, then execute only that
# immutable inode.
if [[ "${BASH_SOURCE[0]}" == "$0" && "${DEPLOY_TASK_LIB_ONLY:-0}" != "1" \
    && "${DEPLOY_TASK_SELF_SNAPSHOT_ACTIVE:-0}" != "1" ]]; then
    _dt_original_self="$0"
    [[ "$_dt_original_self" != /* ]] && _dt_original_self="$PWD/$_dt_original_self"
    _dt_original_root="${_dt_original_self%/scripts/deploy_task.sh}"
    _dt_snapshot="$(mktemp /tmp/deploy_task.self.XXXXXXXX.sh)" || {
        echo "BLOCK: deploy_task self-snapshot allocation failed" >&2
        exit 2
    }
    if ! cp -- "$_dt_original_self" "$_dt_snapshot" || ! bash -n "$_dt_snapshot"; then
        rm -f -- "$_dt_snapshot"
        echo "BLOCK: deploy_task self-snapshot validation failed" >&2
        exit 2
    fi
    export DEPLOY_TASK_SELF_SNAPSHOT_ACTIVE=1
    export DEPLOY_TASK_ROOT_OVERRIDE="${DEPLOY_TASK_ROOT_OVERRIDE:-$_dt_original_root}"
    export DEPLOY_TASK_ORIGINAL_SOURCE="$_dt_original_self"
    exec bash "$_dt_snapshot" "$@"
fi

# The interpreter owns an open descriptor for this unique snapshot; unlinking
# its pathname prevents later writers from finding or changing it.
if [[ "${DEPLOY_TASK_SELF_SNAPSHOT_ACTIVE:-0}" == "1" \
    && "${BASH_SOURCE[0]}" == /tmp/deploy_task.self.*.sh ]]; then
    _dt_live_snapshot="${BASH_SOURCE[0]}"
    rm -f -- "$_dt_live_snapshot"
    unset _dt_live_snapshot
    if [ -n "${DEPLOY_TASK_SELF_SNAPSHOT_TEST_HOLD_DIR:-}" ]; then
        : > "$DEPLOY_TASK_SELF_SNAPSHOT_TEST_HOLD_DIR/ready"
        while [ ! -e "$DEPLOY_TASK_SELF_SNAPSHOT_TEST_HOLD_DIR/release" ]; do
            sleep 0.01
        done
    fi
fi

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    export DEPLOY_TASK_ENTRYPOINT_IS_MAIN=1
    _dt_entrypoint_source="$0"
else
    export DEPLOY_TASK_ENTRYPOINT_IS_MAIN=0
    _dt_entrypoint_source="${BASH_SOURCE[0]}"
fi
[[ "$_dt_entrypoint_source" != /* ]] && _dt_entrypoint_source="$PWD/$_dt_entrypoint_source"
export DEPLOY_TASK_ENTRYPOINT_SOURCE="$_dt_entrypoint_source"
_dt_bootstrap_root="${DEPLOY_TASK_ROOT_OVERRIDE:-${_dt_entrypoint_source%/scripts/deploy_task.sh}}"
_dt_bootstrap_path="$_dt_bootstrap_root/scripts/deploy_task/bootstrap.sh"
# Unit fixtures may copy only deploy_task.sh. Resolve canonical bootstrap from
# the source checkout when the fixture omits modules.
if [ ! -f "$_dt_bootstrap_path" ] && [ -n "${SRC_DEPLOY_SCRIPT:-}" ]; then
    _dt_bootstrap_path="${SRC_DEPLOY_SCRIPT%/deploy_task.sh}/deploy_task/bootstrap.sh"
fi
if [ ! -f "$_dt_bootstrap_path" ] && [ -n "${PROJECT_ROOT:-}" ]; then
    _dt_bootstrap_path="$PROJECT_ROOT/scripts/deploy_task/bootstrap.sh"
fi
source "$_dt_bootstrap_path"
unset _dt_bootstrap_path _dt_bootstrap_root _dt_entrypoint_source

_dt_main_path="$SCRIPT_DIR/scripts/deploy_task/main.sh"
if [ ! -f "$_dt_main_path" ] && [ -n "${SRC_DEPLOY_SCRIPT:-}" ]; then
    _dt_main_path="${SRC_DEPLOY_SCRIPT%/deploy_task.sh}/deploy_task/main.sh"
fi
if [ ! -f "$_dt_main_path" ] && [ -n "${PROJECT_ROOT:-}" ]; then
    _dt_main_path="$PROJECT_ROOT/scripts/deploy_task/main.sh"
fi
source "$_dt_main_path"
unset _dt_main_path

if [[ "${DEPLOY_TASK_SELF_SNAPSHOT_TEST_ONLY:-0}" == "1" ]]; then
    printf 'SELF_SNAPSHOT_OK\\n'
    exit 0
fi

if [[ "${BASH_SOURCE[0]}" == "$0" && "${DEPLOY_TASK_LIB_ONLY:-0}" != "1" ]]; then
    deploy_task_main "$@"

    # cmd_1337: dashboard update remains a post-deployment side effect.
    # Source(lib-only)利用時は起動しない。
    bash "$SCRIPT_DIR/scripts/dashboard_auto_section.sh" &
fi

