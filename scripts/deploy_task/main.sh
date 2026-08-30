#!/bin/bash
# deploy_task/main.sh — cluster J orchestration and delivery phase order.
# The canonical entrypoint sources this module after bootstrap; all modules
# remain in one shell process so the legacy function API stays compatible.

_dt_lifecycle_path="$SCRIPT_DIR/scripts/lib/task_lifecycle.sh"
[ -f "$_dt_lifecycle_path" ] || [ -z "${SRC_DEPLOY_SCRIPT:-}" ] || _dt_lifecycle_path="${SRC_DEPLOY_SCRIPT%/deploy_task.sh}/lib/task_lifecycle.sh"
[ -f "$_dt_lifecycle_path" ] || [ -z "${PROJECT_ROOT:-}" ] || _dt_lifecycle_path="$PROJECT_ROOT/scripts/lib/task_lifecycle.sh"
source "$_dt_lifecycle_path"
unset _dt_lifecycle_path

_dt_module_root="$SCRIPT_DIR/scripts/deploy_task"
if [ ! -f "$_dt_module_root/bootstrap.sh" ] && [ -n "${SRC_DEPLOY_SCRIPT:-}" ]; then
    _dt_module_root="${SRC_DEPLOY_SCRIPT%/deploy_task.sh}/deploy_task"
fi
if [ ! -f "$_dt_module_root/bootstrap.sh" ] && [ -n "${PROJECT_ROOT:-}" ]; then
    _dt_module_root="$PROJECT_ROOT/scripts/deploy_task"
fi

# Cluster order is the dependency contract from deploy_task_split_design:
# bootstrap -> state/transaction -> resolve -> task_contract ->
# context/modifiers -> report -> preflight/gates -> delivery -> orchestration.
source "$_dt_module_root/state.sh"
source "$_dt_module_root/transaction.sh"
source "$_dt_module_root/resolve.sh"
source "$_dt_module_root/task_contract.sh"
source "$_dt_module_root/context_injection.sh"
source "$_dt_module_root/modifiers.sh"
source "$_dt_module_root/report.sh"
source "$_dt_module_root/preflight.sh"
source "$_dt_module_root/gates.sh"
source "$_dt_module_root/delivery.sh"
unset _dt_module_root

deploy_task_main() {
    DEPLOY_TASK_STARTED_US="${EPOCHREALTIME/./}"
    DEPLOY_TASK_STARTED_US="${DEPLOY_TASK_STARTED_US:0:16}"
    DEPLOY_TASK_PHASE=parse_args
    DEPLOY_TASK_WALL_PHASE_LAST_US="$DEPLOY_TASK_STARTED_US"
    deploy_task_start_deadline
    parse_deploy_task_args "$@"
    export DEPLOY_TASK_DIRECT_MODE="$DIRECT_MODE"
    deploy_task_wall_phase_checkpoint parse_args
    DEPLOY_TASK_PHASE=preflight
    deploy_task_check_deadline "after_parse_args" || return $?
    cleanup_none_task_files
    deploy_task_validate_cli_target "$NINJA_NAME" "$@" || return 1
    DEPLOY_TASK_EXIT_NUDGE_ARMED=0
    DEPLOY_TASK_EXIT_NUDGE_SENT=0
    DEPLOY_TASK_DRAFT_REVIEW_ARMED=0
    DEPLOY_TASK_DRAFT_REVIEW_SENT=0
    DEPLOY_TASK_DRAFT_REVIEW_TASK_FILE=""
    DEPLOY_TASK_DRAFT_REVIEW_CMD_ID=""
    DEPLOY_TASK_DRAFT_REVIEW_NINJA=""
    DEPLOY_TASK_DRAFT_REVIEW_TYPE=""
    DEPLOY_TASK_YAML_TX_ARMED=0
    DEPLOY_TASK_YAML_TX_ISSUED_AT=""
    DEPLOY_TASK_YAML_TX_ISSUED_CMD=""
    DEPLOY_TASK_POSTCOND_FILE=""
    DEPLOY_TASK_POSTCOND_TASK_FILE=""
    trap deploy_task_exit_cleanup EXIT

    local pane_target ctx_pct
    local is_idle=false
    pane_target=$(resolve_pane "$NINJA_NAME" || true)
    deploy_task_check_deadline "after_resolve_pane" || return $?
    if [ -z "$pane_target" ]; then
        log "ERROR: Unknown ninja: $NINJA_NAME"
        return 1
    fi

    ctx_pct=$(get_ctx_pct "$pane_target" "$NINJA_NAME")
    # Runtime idleness is independent of how the incoming task is sourced.
    # In particular, --yaml is the canonical karo-direct path; suppressing the
    # observation there makes every terminal worker with a retained immutable
    # report permanently unavailable.  Source validation still runs before any
    # task/report publication, and a busy/unknown pane remains fail-closed.
    check_idle "$pane_target" && is_idle=true

    local task_yaml pre_resolve_status pre_resolve_cmd task_status verify_status current_cmd
    local deploy_parent_cmd deploy_task_id deploy_scope_mode dd_task dd_ninja dd_pcmd dd_tid dd_status
    local deploy_lock_fd="" deploy_lock_file=""
    local deploy_task_resolved_mutated=0
    task_yaml="$SCRIPT_DIR/queue/tasks/${NINJA_NAME}.yaml"
    if [ -n "$CMD_ID" ]; then
        DEPLOY_TASK_ISSUE_ATTEMPT_ID="${CMD_ID}:${NINJA_NAME}:$(date '+%Y%m%dT%H%M%S'):${BASHPID}"
        deploy_task_append_issue_event "issued" "entry"
    fi

    # A per-command lock cannot protect one ninja from two different commands
    # arriving concurrently.  Hold the worker lock across every task/report
    # mutation and the durable task_start notification (GA-257).
    deploy_task_acquire_ninja_lock "$NINJA_NAME" || return 1
    if ! deploy_task_guard_retro_answer_hold "$NINJA_NAME"; then
        deploy_task_release_ninja_lock
        return 2
    fi
    if ! deploy_task_guard_checkpoint_review_hold "$NINJA_NAME"; then
        deploy_task_release_ninja_lock
        return 2
    fi

    # Legacy lifecycle control is status-only, not a deployment.  Handle it
    # before normalization, stale-field repair, collision checks, or context
    # injection so an old failed task cannot be republished accidentally.
    if [ "$MESSAGE" = "status" ] && [[ "$TYPE" =~ ^(idle|done|in_progress)$ ]]; then
        task_status=$(field_get "$task_yaml" "status" "unknown")
        if [ "$TYPE" = "in_progress" ] && [ "$task_status" = "in_progress" ]; then
            current_cmd=$(field_get "$task_yaml" "parent_cmd" "")
            log "BLOCK: ${NINJA_NAME} is in_progress on ${current_cmd:-unknown}. 前タスク完了を待て。"
            echo "BLOCK: ${NINJA_NAME} は ${current_cmd:-unknown} を実行中。二重配備禁止(GP-069)。" >&2
            deploy_task_release_ninja_lock
            return 1
        fi
        yaml_field_set "$task_yaml" "task" "status" "$TYPE"
        log "status_update: ${task_status} → ${TYPE}"
        verify_status=$(field_get "$task_yaml" "status" "")
        if [ "$verify_status" != "$TYPE" ]; then
            log "WARN: status更新検証失敗: 期待=${TYPE}, 実際=${verify_status}"
        fi
        bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$NINJA_NAME" "$MESSAGE" "$TYPE" "$FROM" "status_update"
        log "${NINJA_NAME}: status control complete (type=${TYPE})"
        deploy_task_release_ninja_lock
        return 0
    fi

    normalize_task_yaml "$task_yaml" || true
    if [ "$DIRECT_MODE" != true ]; then
        repair_training_parent_cmd_from_cmd_id "$task_yaml" || return $?
    fi

    if [ -n "$CMD_ID" ]; then
        deploy_lock_file="$(deploy_task_lock_path "$CMD_ID")"
        exec {deploy_lock_fd}>"$deploy_lock_file"
        if ! flock -w 10 "$deploy_lock_fd"; then
            log "BLOCK: could not acquire deploy lock for ${CMD_ID}: ${deploy_lock_file}"
            echo "BLOCK: ${CMD_ID} deploy lock busy. Retry after current deployment finishes." >&2
            return 1
        fi
        log "deploy_lock: acquired ${deploy_lock_file}"
        deploy_task_check_deadline "after_deploy_lock" || return $?
    fi

    if [ -n "$CMD_ID" ] && deploy_task_cleanup_canceled_cmd "$NINJA_NAME" "$CMD_ID"; then
        deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
        deploy_task_release_ninja_lock
        return 0
    fi

    if [ -n "$CMD_ID" ] && deploy_task_cmd_status_is_canceled "$CMD_ID"; then
        log "BLOCK: ${CMD_ID} is canceled in shogun_to_karo.yaml. Deployment aborted."
        echo "BLOCK: ${CMD_ID} は canceled。再起票cmdを待て。" >&2
        deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
        return 1
    fi

    if [ "$DIRECT_MODE" != true ] && [ -z "$CMD_FORCED" ] && [ -n "$CMD_ID" ] && deploy_task_cmd_status_is_draft "$CMD_ID"; then
        log "BLOCK: ${CMD_ID} status=draft; skip deployment until cmd_save promotes it to pending."
        echo "BLOCK: ${CMD_ID} は status=draft。cmd_save PASSでpendingへ昇格するまで配備をスキップ。" >&2
        deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
        return 1
    fi

    local status="" parent_cmd=""
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_yaml" status parent_cmd 2>/dev/null)" || true
    pre_resolve_status="${status:-unknown}"
    pre_resolve_cmd="${parent_cmd:-}"
    # cmd_karo_impl_related_lessons_snapshot_20260727 (related_lessons再配備drift是正):
    # resolve_cmd_to_task/reset_stale_fieldsが走る前のparent_cmd/related_lessons在否を
    # 記録する。同一cmdの再配備でinject_related_lessonsが既存集合を上書きするのを防ぐため、
    # 「再解決前からこのCMD_ID向けにrelated_lessonsが既に存在していたか」をここで確定する。
    _DEPLOY_PRE_RESOLVE_PARENT_CMD="$pre_resolve_cmd"
    _DEPLOY_PRE_RESOLVE_RELATED_LESSONS_PRESENT=$(python3 -c "
import sys, yaml
try:
    with open(sys.argv[1], encoding='utf-8') as f:
        d = (yaml.safe_load(f) or {}).get('task', {})
    rl = d.get('related_lessons')
    print('1' if isinstance(rl, list) and len(rl) > 0 else '0')
except Exception:
    print('0')
" "$task_yaml" 2>/dev/null || echo 0)
    export _DEPLOY_PRE_RESOLVE_PARENT_CMD _DEPLOY_PRE_RESOLVE_RELATED_LESSONS_PRESENT
    # B26 escape hatch入力: 配備しようとしているtaskのtask_typeをガードへ渡す。
    # source YAMLがあるときのみ読む(なければ空=従来通り拒否側に倒れるfail-closed)。
    DEPLOY_INCOMING_TASK_TYPE=""
    if [ -n "$YAML_FILE" ] && [ -f "$YAML_FILE" ]; then
        DEPLOY_INCOMING_TASK_TYPE=$(FIELD_GET_NO_LOG=1 field_get "$YAML_FILE" "task_type" "" 2>/dev/null || true)
    fi
    if [ -n "$CMD_ID" ] && ! deploy_task_guard_worker_assignment "$task_yaml" "$CMD_ID"; then
        deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
        return 1
    fi
    # Normal cmd deployments resolve the incoming command into the worker task
    # before the target-overlap guard can inspect the complete reservation.
    # Snapshot task/report now so any later collision BLOCK restores the exact
    # pre-deploy bytes; otherwise resolve_cmd_to_task can leak status=assigned
    # into an idle worker slot (cmd_4424 ghost assignment).
    if [ -n "$CMD_ID" ] && [ "$DIRECT_MODE" != true ] &&
       [ "${DEPLOY_TASK_YAML_TX_ARMED:-0}" != "1" ]; then
        local normal_cmd_source
        normal_cmd_source=$(resolve_cmd_source_path "$CMD_ID") || {
            deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
            return 2
        }
        deploy_task_yaml_transaction_begin "$task_yaml" "$normal_cmd_source" "$NINJA_NAME" "$CMD_ID" || {
            deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
            return 1
        }
    fi
    if [ -n "$CMD_ID" ] && { [ "$DIRECT_MODE" != true ] || [ -z "$YAML_FILE" ]; }; then
        # --direct without --yaml mutates the worker task while deriving the
        # training template below.  Arm the same task/report transaction used
        # by --yaml before issued_at or template injection so a later
        # preflight BLOCK restores the exact pre-deploy bytes and cannot leak
        # an EXIT fallback publication.
        if [ "$DIRECT_MODE" = true ] && [ -z "$YAML_FILE" ] &&
           [ "${DEPLOY_TASK_YAML_TX_ARMED:-0}" != "1" ]; then
            deploy_task_yaml_transaction_begin "$task_yaml" "$task_yaml" "$NINJA_NAME" "$CMD_ID" || {
                deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
                return 1
            }
        fi
        record_issued_at_once "$task_yaml" "$CMD_ID" "$(date '+%Y-%m-%dT%H:%M:%S')" || return 1
    fi

    if [ -n "$CMD_ID" ] && deploy_task_has_pending_own_report "$CMD_ID" "$NINJA_NAME" "$task_yaml"; then
        deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
        return 1
    fi

    if [ -n "$CMD_ID" ]; then
        capture_done_redeploy_context "$task_yaml" "$CMD_ID"
        # GP-198: session_stateをstale reset前に保存（再配備時のhint注入用）
        # cmd_2078 B3: awk fast-path — session_stateフィールドが存在しなければpython3をスキップ (~53ms節約)
        _DEPLOY_PREV_SESSION_STATE=""
        _DEPLOY_PREV_PARENT_CMD=$(FIELD_GET_NO_LOG=1 field_get "$task_yaml" "parent_cmd" "" 2>/dev/null || true)
        if grep -qE '^[[:space:]]+session_state:' "$task_yaml" 2>/dev/null; then
            _DEPLOY_PREV_SESSION_STATE=$(python3 -c "
import yaml, json, sys
try:
    with open('$task_yaml') as f:
        d = yaml.safe_load(f) or {}
    ss = (d.get('task') or d).get('session_state')
    if ss and isinstance(ss, dict):
        print(json.dumps(ss))
except Exception:
    pass
" 2>/dev/null || true)
        fi
        export _DEPLOY_PREV_SESSION_STATE
        export _DEPLOY_PREV_PARENT_CMD
        _DEPLOY_FORMAL_RC_REFRESH_REPORT=""
        if [ "$DIRECT_MODE" = true ] && [ -n "$YAML_FILE" ]; then
            _DEPLOY_FORMAL_RC_REFRESH_REPORT=$(deploy_task_direct_formal_rc_refresh_report \
                "$task_yaml" "$CMD_ID" "$NINJA_NAME" "$YAML_FILE" 2>/dev/null || true)
        fi
        _DEPLOY_SKIP_SAME_CMD_RESOLVE=0
        if [ -z "$_DEPLOY_FORMAL_RC_REFRESH_REPORT" ]; then
            if should_skip_same_cmd_resolve "$task_yaml" "$CMD_ID" "$NINJA_NAME"; then
                _DEPLOY_SKIP_SAME_CMD_RESOLVE=1
            fi
        fi
        if [ "$_DEPLOY_SKIP_SAME_CMD_RESOLVE" = "1" ]; then
            _DEPLOY_PREV_PARENT_CMD="$CMD_ID"
            _DEPLOY_SAME_CMD_REDEPLOY=1
            # The reused task already passed reset_stale_fields during the first
            # publication. Mark that contract satisfied so retry preflight does
            # not contradict the intentional same-command reuse path.
            _STALE_RESET_DONE=1
            log "same_cmd_redeploy: skipped reset_stale_fields and resolve_cmd_to_task for ${CMD_ID}"
        else
            if ! deploy_task_guard_direct_yaml_prewrite_collision "$YAML_FILE" "$NINJA_NAME"; then
                deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
                return 1
            fi
            if ! deploy_task_ci_red_followup_push_guard "$YAML_FILE"; then
                deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
                return 1
            fi
            # Validation-before-mutation: syntax, natural-boundary and required
            # source contracts must all pass while the current task is untouched.
            if [ "$DIRECT_MODE" = true ] && [ -n "$YAML_FILE" ]; then
                deploy_task_yaml_transaction_begin "$task_yaml" "$YAML_FILE" "$NINJA_NAME" "$CMD_ID" || {
                    deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
                    return 1
                }
                [ "${DEPLOY_TASK_LIB_ONLY:-0}" = "1" ] || deploy_task_source_contract_precheck "$YAML_FILE" || {
                    deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
                    return 2
                }
                deploy_task_ci_fix_run_id_precheck "$YAML_FILE" || {
                    deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
                    return 1
                }
                deploy_task_destructive_signal_precheck "$YAML_FILE" || {
                    deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
                    return 2
                }
                deploy_task_direct_quality_contract_precheck "$YAML_FILE" || {
                    deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
                    return 1
                }
            elif [ "$DIRECT_MODE" != true ]; then
                local cmd_source_file
                cmd_source_file=$(resolve_cmd_source_path "$CMD_ID") || {
                    deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
                    return 2
                }
                [ "${DEPLOY_TASK_LIB_ONLY:-0}" = "1" ] || deploy_task_source_contract_precheck "$cmd_source_file" "$CMD_ID" || {
                    deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
                    return 2
                }
                deploy_task_destructive_signal_precheck "$cmd_source_file" "$CMD_ID" || {
                    deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
                    return 2
                }
            fi
            # --yaml source replaces the full task atomically; mutating the old
            # destination first breaks validation-before-publication on failure.
            if [ "$DIRECT_MODE" != true ] || [ -z "$YAML_FILE" ]; then
                reset_stale_fields "$NINJA_NAME"
            fi
            if [ "$DIRECT_MODE" = true ]; then
            if [ -n "$YAML_FILE" ]; then
                deploy_task_direct_yaml_publish "$task_yaml" "$YAML_FILE" || {
                    deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
                    return 1
                }
                _STALE_RESET_DONE=1
                record_issued_at_once "$task_yaml" "$CMD_ID" "$(date '+%Y-%m-%dT%H:%M:%S')" || return 1
                if deploy_task_direct_yaml_is_preinjected "$task_yaml"; then
                    DEPLOY_TASK_DIRECT_YAML_PREINJECTED=1
                else
                    DEPLOY_TASK_DIRECT_YAML_PREINJECTED=0
                fi
                check_yaml_freshness "$YAML_FILE" "$SCRIPT_DIR"
            fi
            deploy_task_direct_quality_contract_precheck "$task_yaml" || {
                deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
                return 1
            }
            log "direct_mode: skipping resolve_cmd_to_task for ${CMD_ID} (shogun_to_karo.yaml not required)"
            # cmd_2481事故修正: --directでもparent_cmd/task_id/statusを更新する
            # resolve_cmd_to_taskスキップ時に旧cmd文脈で後続inject処理が動作するバグを防止
            local direct_task_type direct_task_id_suffix
            direct_task_type=$(field_get "$task_yaml" "task_type" "normal")
            if [ "$direct_task_type" = "exact" ]; then
                direct_task_id_suffix="exact"
            else
                direct_task_id_suffix="normal"
            fi
            yaml_field_set_batch "$task_yaml" "task" \
                "parent_cmd=$CMD_ID" \
                "status=assigned" \
                "task_id=${CMD_ID}_${direct_task_id_suffix}" 2>/dev/null || true
            inject_training_target_path_from_alias_quality "$task_yaml" "$CMD_ID" || true
            inject_direct_training_template "$task_yaml" "$CMD_ID" || {
                deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
                return 1
            }
            deploy_task_resolved_mutated=1
            log "direct_mode: parent_cmd=${CMD_ID}, task_id=${CMD_ID}_${direct_task_id_suffix}, status=assigned set"
            elif [ -n "$CMD_FORCED" ]; then
            # --cmd mode: shogun_to_karo.yaml不在cmdを強制展開（修行cmd等に対応）
            # parent_cmd/task_idを直接設定。解決失敗でもabortしない。
            yaml_field_set "$task_yaml" "task" "parent_cmd" "$CMD_FORCED" \
                || { log "FATAL: yaml_field_set failed for parent_cmd (cmd_forced)"; return 1; }
            local force_task_type
            force_task_type=$(field_get "$task_yaml" "task_type" "impl")
            if [ -z "$force_task_type" ] || [ "$force_task_type" = "unknown" ]; then
                force_task_type="impl"
            fi
            yaml_field_set "$task_yaml" "task" "task_id" "${CMD_FORCED}_${force_task_type}" \
                || { log "FATAL: yaml_field_set failed for task_id (cmd_forced)"; return 1; }
            yaml_field_set "$task_yaml" "task" "status" "assigned" \
                || { log "FATAL: yaml_field_set failed for status (cmd_forced)"; return 1; }
            yaml_field_set "$task_yaml" "task" "_ac_task_id" "" \
                || { log "FATAL: yaml_field_set failed for _ac_task_id (cmd_forced)"; return 1; }
            yaml_field_set "$task_yaml" "task" "_ac_worker_id" "" \
                || { log "FATAL: yaml_field_set failed for _ac_worker_id (cmd_forced)"; return 1; }
            _overwrite_ac_from_cmd "$task_yaml" || true
            inject_training_target_path_from_alias_quality "$task_yaml" "$CMD_FORCED" || true
            inject_direct_training_template "$task_yaml" "$CMD_FORCED" || return 1
            deploy_task_resolved_mutated=1
            log "cmd_forced: ${CMD_FORCED} → parent_cmd/task_id set directly (shogun_to_karo.yaml not required)"
            elif resolve_cmd_to_task "$CMD_ID" "$NINJA_NAME"; then
                deploy_task_resolved_mutated=1
                log "cmd_resolve: ${CMD_ID} → task YAML updated for ${NINJA_NAME}"
            else
                log "ERROR: cmd_resolve failed for ${CMD_ID}. Aborting deployment."
                echo "ERROR: ${CMD_ID} の解決に失敗。shogun_to_karo.yamlにcmd_idが存在するか確認せよ。" >&2
                deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
                return 1
            fi
        fi
        deploy_task_check_deadline "after_cmd_resolution" || return $?
    fi

    if ! deploy_task_guard_target_path_collision "$task_yaml" "$NINJA_NAME"; then
        deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
        return 1
    fi

    if ! deploy_task_guard_preserved_path "$task_yaml"; then
        deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
        return 1
    fi

    task_status=$(field_get "$task_yaml" "status" "unknown")
    log "${NINJA_NAME}: CTX=${ctx_pct}%, idle=${is_idle}, task_status=${task_status}, pane=${pane_target}"

    if [ "$task_status" = "in_progress" ] && [ "$TYPE" != "in_progress" ]; then
        current_cmd=$(field_get "$task_yaml" "parent_cmd" "")
        log "BLOCK: ${NINJA_NAME} is in_progress on ${current_cmd:-unknown}. 前タスク完了を待て。"
        echo "BLOCK: ${NINJA_NAME} は ${current_cmd:-unknown} を実行中。二重配備禁止(GP-069)。" >&2
        deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
        return 1
    fi

    local task_type="" scope_mode="" type="" task_id="" subtask_id=""
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_yaml" parent_cmd _ac_task_id task_id subtask_id task_type scope_mode type 2>/dev/null)" || true
    deploy_parent_cmd="${parent_cmd:-}"
    deploy_task_id="${_ac_task_id:-}"
    # split_deploy fix (cmd_3280): resolve_cmd_to_taskが_ac_task_idを常に空リセットするため
    # 分割配備許可パス(L7713)に到達不能だった。_ac_task_idが空(inject_ac_version実行前)の場合は
    # subtask_id(karo_direct分割配備の固有ID)またはtask_id(resolve直後の値)をfallbackとして使う。
    if [ -z "$deploy_task_id" ]; then
        deploy_task_id="${subtask_id:-${task_id:-}}"
    fi
    deploy_scope_mode="${task_type:-}"
    [ -z "$deploy_scope_mode" ] && deploy_scope_mode="${scope_mode:-}"
    [ -z "$deploy_scope_mode" ] && deploy_scope_mode="${type:-}"
    deploy_scope_mode="${deploy_scope_mode,,}"

    if ! deploy_task_enforce_gpt_priority "$NINJA_NAME" "$deploy_scope_mode"; then
        if [ "$deploy_task_resolved_mutated" = "1" ]; then
            task_lifecycle_set_idle "$task_yaml" "gpt_priority_block" >/dev/null 2>&1 || true
            log "ROLLBACK: ${NINJA_NAME} task YAML reset to idle after GPT priority BLOCK"
        else
            log "ROLLBACK: skipped after GPT priority BLOCK because task YAML was not rewritten in this deploy attempt"
        fi
        deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
        return 1
    fi

    if [ -n "$deploy_parent_cmd" ]; then
        warn_same_ninja_redeploy "$task_yaml" "$NINJA_NAME" "$deploy_parent_cmd"
    fi

    DEPLOY_TASK_DRAFT_REVIEW_TASK_FILE="$task_yaml"
    DEPLOY_TASK_DRAFT_REVIEW_CMD_ID="$deploy_parent_cmd"
    DEPLOY_TASK_DRAFT_REVIEW_NINJA="$NINJA_NAME"
    DEPLOY_TASK_DRAFT_REVIEW_TYPE="$TYPE"
    DEPLOY_TASK_DRAFT_REVIEW_SENT=0

    # _ac_task_id必須チェック: 分割配備の判定に必要。scope_mode=exactはAC分割しないため対象外。
    if [ -z "$deploy_task_id" ] && [ "$deploy_scope_mode" != "exact" ]; then
        log "WARN: _ac_task_id is empty — split deploy detection may misfire"
        echo "WARN: _ac_task_id が未設定。分割配備時に二重配備と誤判定する可能性あり。task YAMLに _ac_task_id を設定せよ。" >&2
    fi

    if [ -n "$deploy_parent_cmd" ]; then
        if deploy_task_has_completed_peer_report "$deploy_parent_cmd" "$NINJA_NAME" "$task_yaml"; then
            task_lifecycle_set_idle "$task_yaml" "completed_peer_report" >/dev/null 2>&1 || true
            log "ROLLBACK: ${NINJA_NAME} task YAML reset to idle after completed peer report BLOCK"
            deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
            return 1
        fi

        for dd_task in "$SCRIPT_DIR/queue/tasks/"*.yaml; do
            [ -f "$dd_task" ] || continue
            dd_ninja=$(basename "$dd_task" .yaml)
            [ "$dd_ninja" = "$NINJA_NAME" ] && continue
            dd_pcmd=$(FIELD_GET_NO_LOG=1 field_get "$dd_task" "parent_cmd" "")
            [ "$dd_pcmd" != "$deploy_parent_cmd" ] && continue
            dd_tid=$(FIELD_GET_NO_LOG=1 field_get "$dd_task" "_ac_task_id" "")
            # split_deploy fix (cmd_3280): peer側も_ac_task_idが空の場合はsubtask_id/task_idをfallback
            if [ -z "$dd_tid" ]; then
                local _dd_subtask_id _dd_task_id
                _dd_subtask_id="$(FIELD_GET_NO_LOG=1 field_get "$dd_task" "subtask_id" "" 2>/dev/null || true)"
                _dd_task_id="$(FIELD_GET_NO_LOG=1 field_get "$dd_task" "task_id" "" 2>/dev/null || true)"
                dd_tid="${_dd_subtask_id:-${_dd_task_id:-}}"
            fi
            # 二重配備判定: deploy_task_idが空(reset_stale_fields後)の場合は
            # parent_cmd一致+相手がactive=二重配備とみなす。
            # deploy_task_idが存在する場合は task_id同一チェックで分割配備を許可。
            if [[ "$deploy_scope_mode" =~ ^(recon|scout)$ ]] && [ -n "$dd_tid" ] && [ "$deploy_task_id" != "$dd_tid" ]; then
                log "parallel_recon: ${deploy_parent_cmd} peer ${dd_ninja} (task_id: ${dd_tid:-empty}) — allowing"
                continue
            fi
            if [ -n "$deploy_task_id" ] && [ "$deploy_scope_mode" != "exact" ]; then
                # 両方にtask_idがある場合: 同一task_idのみBLOCK(分割配備はtask_id異なるため許可)
                if [ -z "$dd_tid" ] || [ "$deploy_task_id" != "$dd_tid" ]; then
                    log "split_deploy: ${deploy_parent_cmd} peer ${dd_ninja} (task_id: ${dd_tid:-empty}) — allowing"
                    continue
                fi
            else
                # deploy_task_id空(reset後): parent_cmd一致だけで二重配備と判定
                # ただし相手もidle/completedならスキップ(前回の残骸)
                :
            fi
            dd_status=$(FIELD_GET_NO_LOG=1 field_get "$dd_task" "status" "")
            case "$dd_status" in
                assigned|acknowledged|in_progress)
                    log "BLOCK: ${deploy_parent_cmd} is already assigned to ${dd_ninja} (status: ${dd_status}, task_id: ${dd_tid})"
                    task_lifecycle_set_idle "$task_yaml" "duplicate_deploy_block" >/dev/null 2>&1 || true
                    log "ROLLBACK: ${NINJA_NAME} task YAML reset to idle after duplicate deploy BLOCK"
                    echo "BLOCK: ${deploy_parent_cmd} is already assigned to ${dd_ninja} (status: ${dd_status})" >&2
                    echo "Clear the existing task first through scripts/lib/task_lifecycle.sh: queue/tasks/${dd_ninja}.yaml" >&2
                    deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
                    return 1
                    ;;
            esac
        done
    fi

    # 消火キーワードtitle検知（cmd_1807）
    if [ -n "$deploy_parent_cmd" ]; then
        check_firefighting_title "$deploy_parent_cmd" "$task_yaml"
    fi

    warn_task_clarity "$task_yaml"

    # GP-110修正版: target_pathの直近コミットが非cmd self-driveならWARN
    warn_recent_noncmd_commit_targets "$task_yaml"

    # cmd_3019: q11_not_already_doneを配備時に再実行し、既実装レースをWARNで可視化
    warn_q11_not_already_done_drift "$task_yaml"

    # cmd_3181: 三層記憶candidate蓄積を配備時にWARNで可視化。WARN止まりで配備は継続。
    warn_three_layer_candidate_backlog || true

    # AC3: _STALE_RESET_DONE確認ゲート — CMD_ID配備時にreset_stale_fieldsが実行済みか検証
    if [ -n "$CMD_ID" ] && [ "${_STALE_RESET_DONE:-0}" != "1" ]; then
        log "BLOCK(AC3): _STALE_RESET_DONE not set — reset_stale_fields が未実行。配備を中止。"
        echo "BLOCK: stale field reset (reset_stale_fields) が未実行。配備を中止。deploy_task.shのreset_stale_fields呼出し経路を確認せよ。" >&2
        deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
        return 1
    fi

    [ "${DEPLOY_TASK_LIB_ONLY:-0}" = "1" ] || deploy_task_ten_min_contract_precheck "$task_yaml" || {
        deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
        return 2
    }

    # Do not let a preflight failure publish a report or task_assigned nudge.
    # Both EXIT fallbacks are armed only after the final contract gate passes.
    DEPLOY_TASK_DRAFT_REVIEW_ARMED=1
    DEPLOY_TASK_EXIT_NUDGE_ARMED=1
    if [ "$DIRECT_MODE" = true ] && [ -z "$YAML_FILE" ]; then
        # The direct no-YAML transaction protects preflight only.  Once the
        # final contract gate passes, preserve the established post-mutation
        # EXIT fallback contract instead of rolling back after a later
        # deadline/interruption.
        deploy_task_yaml_transaction_commit
    fi

    DEPLOY_TASK_PHASE=task_mutations
    deploy_task_wall_phase_checkpoint preflight
    deploy_task_apply_task_mutations "$NINJA_NAME" || {
        DEPLOY_TASK_EXIT_NUDGE_ARMED=0
        DEPLOY_TASK_DRAFT_REVIEW_ARMED=0
        deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
        return 1
    }
    deploy_task_prepare_remote_tip_worktree "$task_yaml" "$NINJA_NAME" || {
        DEPLOY_TASK_EXIT_NUDGE_ARMED=0
        DEPLOY_TASK_DRAFT_REVIEW_ARMED=0
        deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
        return 1
    }
    # Deployment and Gunshi draft review now run in parallel; deployment does
    # not wait for an APPROVE/LGTM receipt (殿裁定2026-08-09 14:05). Review
    # still happens via maybe_notify_draft_review below, and REQUEST_CHANGES
    # reaches the running ninja through the existing task_supplement inbox path.
    # Publication identity (active status + deployed_at) must become visible
    # under the same per-ninja/deploy lock.  Previously deployed_at was written
    # after lock release and inbox delivery, allowing revision/respawn to see an
    # active task with the prior generation and allowing an interrupted deploy
    # to emit a task nudge before its generation existed.
    record_deployed_at "$task_yaml" "$(date '+%Y-%m-%dT%H:%M:%S')" || {
        deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
        return 1
    }
    record_target_worktree_blob_at_deploy "$task_yaml" || return 1
    deploy_task_wall_phase_checkpoint task_mutations
    deploy_task_check_deadline "after_task_mutations" || return $?

    if [ -n "$deploy_lock_fd" ]; then
        deploy_task_release_lock "$deploy_lock_fd" "$deploy_lock_file"
        deploy_lock_fd=""
    fi

    DEPLOY_TASK_PHASE=delivery
    if [ "${_DEPLOY_SAME_CMD_REDEPLOY:-0}" = "1" ]; then
        # The original task_assigned message is already durable.  Reusing the
        # same task must not append an identical persistent message; the
        # watcher/post-verify path can re-nudge the existing unread set.
        log "${NINJA_NAME}: same-cmd redeploy; persistent task_assigned write skipped"
    elif [ "$ctx_pct" -le 0 ] 2>/dev/null; then
        log "${NINJA_NAME}: CTX=0% detected (clear済み). Sending inbox_write (watcher handles timing)"
        safe_inbox_write "$NINJA_NAME" "$MESSAGE" "$TYPE" "$FROM" "task_start"
    elif [ "$is_idle" = "true" ]; then
        log "${NINJA_NAME}: CTX=${ctx_pct}%, idle. Sending inbox_write (normal nudge)"
        safe_inbox_write "$NINJA_NAME" "$MESSAGE" "$TYPE" "$FROM" "task_start"
    else
        log "${NINJA_NAME}: CTX=${ctx_pct}%, busy. Sending inbox_write (queued, watcher will nudge later)"
        safe_inbox_write "$NINJA_NAME" "$MESSAGE" "$TYPE" "$FROM" "task_start"
    fi
    deploy_task_check_deadline "after_inbox_write" || return $?
    DEPLOY_TASK_EXIT_NUDGE_SENT=1
    DEPLOY_TASK_EXIT_NUDGE_ARMED=0
    deploy_task_yaml_transaction_commit
    deploy_task_wall_phase_checkpoint delivery

    # Canonical receipt order is delivery -> post_verify -> post_delivery.
    # Keep the verifier ahead of notification/deferred work so EXIT records
    # post_delivery exactly once instead of appending a duplicate terminal
    # phase after an already-recorded post_delivery interval.
    DEPLOY_TASK_PHASE=post_verify
    deploy_task_post_deploy_verify "$NINJA_NAME"
    deploy_task_wall_phase_checkpoint post_verify

    DEPLOY_TASK_PHASE=post_delivery
    notify_initial_deploy_ntfy_once "$task_yaml" "$NINJA_NAME" || true
    preflight_gate_artifacts "$task_yaml" || true

    local rr_pointer_file rr_lock_file
    rr_pointer_file="$SCRIPT_DIR/queue/rr_pointer.txt"
    rr_lock_file="/tmp/rr_pointer.lock"
    (
        flock -w 5 201
        echo "$NINJA_NAME" > "$rr_pointer_file"
    ) 201>"$rr_lock_file" 2>/dev/null || log "WARN: rr_pointer update failed (non-fatal)"

    maybe_notify_draft_review "$task_yaml" "$deploy_parent_cmd" "$NINJA_NAME" "$TYPE"
    DEPLOY_TASK_DRAFT_REVIEW_ARMED=0
    DEPLOY_TASK_DRAFT_REVIEW_SENT=1
    log "${NINJA_NAME}: deployment complete (type=${TYPE})"
    DEPLOY_TASK_DEPLOY_COMPLETED=1
    deploy_task_wall_phase_checkpoint post_delivery
    deploy_task_release_ninja_lock
    deploy_task_start_deferred_drain

    # Codex忍者向け遅延re-nudge + 配備確認ログ (cmd_karo_codex_renudge / cmd_3102 AC1修正)
    # 根因: CLI再起動直後、Codex CLIが初期画面表示中にinbox_watcherのnudgeが空振りする
    # AC1修正: CTX=0%条件を撤去。Codexエージェントは常に遅延re-nudge対象
    #          + 配備確認ログをlogs/codex_delivery_log.yamlに記録し到達確認可能に
    if [ "$(cli_type "$NINJA_NAME")" = "codex" ] && [ "${DEPLOY_TASK_DELIVERY_EVIDENCE:-0}" != "1" ]; then
        log "${NINJA_NAME}: Codex detected. Scheduling delayed re-nudge in 5s (background, ctx=${ctx_pct}%)"
        # 到達確認ログ: ninja/cmd/ctx/timestamp を記録
        printf '- ninja: %s\n  cmd: %s\n  ctx_pct: %s\n  timestamp: %s\n  renudge: scheduled\n' \
            "$NINJA_NAME" "${deploy_parent_cmd:-unknown}" "${ctx_pct:-unknown}" \
            "$(date '+%Y-%m-%dT%H:%M:%S')" \
            >> "$SCRIPT_DIR/logs/codex_delivery_log.yaml" 2>/dev/null || true
        local _renudge_name="$NINJA_NAME"
        (
            sleep 5
            deploy_task_send_direct_renudge "$_renudge_name"
        ) &
        log "${NINJA_NAME}: re-nudge scheduled (pid=$!)"
    elif [ "$(cli_type "$NINJA_NAME")" = "codex" ]; then
        log "${NINJA_NAME}: delayed re-nudge not scheduled (delivery evidence already present)"
    fi
}

