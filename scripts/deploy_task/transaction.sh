#!/bin/bash
# deploy_task/transaction.sh — cluster B YAML transaction and cleanup.
# Function bodies are extracted verbatim from deploy_task.sh.

deploy_task_yaml_transaction_begin() {
    local task_file="$1" source_file="$2" ninja_name="$3" parent_cmd="$4"
    local report_filename
    DEPLOY_TASK_YAML_TX_DIR=$(mktemp -d) || return 1
    DEPLOY_TASK_YAML_TX_TASK="$task_file"
    cp -- "$task_file" "$DEPLOY_TASK_YAML_TX_DIR/task.before" || return 1
    report_filename=$(FIELD_GET_NO_LOG=1 field_get "$source_file" report_filename "" 2>/dev/null || true)
    [ -n "$report_filename" ] || report_filename="${ninja_name}_report_${parent_cmd}.yaml"
    DEPLOY_TASK_YAML_TX_REPORT="$SCRIPT_DIR/queue/reports/$report_filename"
    if [ -f "$DEPLOY_TASK_YAML_TX_REPORT" ]; then
        cp -- "$DEPLOY_TASK_YAML_TX_REPORT" "$DEPLOY_TASK_YAML_TX_DIR/report.before" || return 1
        DEPLOY_TASK_YAML_TX_REPORT_EXISTED=1
    else
        DEPLOY_TASK_YAML_TX_REPORT_EXISTED=0
    fi
    DEPLOY_TASK_YAML_TX_ARMED=1
}

deploy_task_yaml_transaction_rollback() {
    [ "${DEPLOY_TASK_YAML_TX_ARMED:-0}" = "1" ] || return 0
    DEPLOY_TASK_EXIT_NUDGE_ARMED=0
    DEPLOY_TASK_DRAFT_REVIEW_ARMED=0
    cp -- "$DEPLOY_TASK_YAML_TX_DIR/task.before" "${DEPLOY_TASK_YAML_TX_TASK}.rollback"
    mv -f -- "${DEPLOY_TASK_YAML_TX_TASK}.rollback" "$DEPLOY_TASK_YAML_TX_TASK"
    if [ "${DEPLOY_TASK_YAML_TX_REPORT_EXISTED:-0}" = "1" ]; then
        cp -- "$DEPLOY_TASK_YAML_TX_DIR/report.before" "${DEPLOY_TASK_YAML_TX_REPORT}.rollback"
        mv -f -- "${DEPLOY_TASK_YAML_TX_REPORT}.rollback" "$DEPLOY_TASK_YAML_TX_REPORT"
    elif [ -f "${DEPLOY_TASK_YAML_TX_REPORT:-}" ]; then
        rm -f -- "$DEPLOY_TASK_YAML_TX_REPORT"
    fi
    log "YAML-TRANSACTION: rollback restored task/report; inbox publication=0"
    DEPLOY_TASK_YAML_TX_ARMED=0
    DEPLOY_TASK_YAML_TX_ISSUED_AT=""
    DEPLOY_TASK_YAML_TX_ISSUED_CMD=""
    rm -f -- "$DEPLOY_TASK_YAML_TX_DIR/task.before" "$DEPLOY_TASK_YAML_TX_DIR/report.before"
    rmdir -- "$DEPLOY_TASK_YAML_TX_DIR" 2>/dev/null || true
}

deploy_task_yaml_transaction_commit() {
    [ "${DEPLOY_TASK_YAML_TX_ARMED:-0}" = "1" ] || return 0
    DEPLOY_TASK_YAML_TX_ARMED=0
    rm -f -- "$DEPLOY_TASK_YAML_TX_DIR/task.before" "$DEPLOY_TASK_YAML_TX_DIR/report.before"
    rmdir -- "$DEPLOY_TASK_YAML_TX_DIR" 2>/dev/null || true
    if [ -n "${DEPLOY_TASK_YAML_TX_ISSUED_AT:-}" ]; then
        log "[ISSUED_AT] Recorded: ${DEPLOY_TASK_YAML_TX_ISSUED_AT} (${DEPLOY_TASK_YAML_TX_ISSUED_CMD})"
    fi
    DEPLOY_TASK_YAML_TX_ISSUED_AT=""
    DEPLOY_TASK_YAML_TX_ISSUED_CMD=""
    log "YAML-TRANSACTION: committed task/report with delivery"
}

deploy_task_exit_cleanup() {
    local exit_status=$?
    local finished_us wall_ms residual_ms residual_pct finalize_ms
    if [ -n "${DEPLOY_TASK_STARTED_US:-}" ]; then
        deploy_task_wall_phase_checkpoint "${DEPLOY_TASK_PHASE:-unknown}"
        finished_us="${EPOCHREALTIME/./}"
        finished_us="${finished_us:0:16}"
        # The final checkpoint writes its own two telemetry rows. Include that
        # bounded writer cost in the sum before freezing the receipt wall;
        # otherwise short isolated runs misleadingly report >10% residual.
        finalize_ms=$(((finished_us - DEPLOY_TASK_WALL_PHASE_LAST_US + 999) / 1000))
        DEPLOY_TASK_WALL_PHASE_SUM_MS=$((DEPLOY_TASK_WALL_PHASE_SUM_MS + finalize_ms))
        wall_ms=$(((finished_us - DEPLOY_TASK_STARTED_US + 999) / 1000))
        residual_ms=$((wall_ms - DEPLOY_TASK_WALL_PHASE_SUM_MS))
        [ "$residual_ms" -ge 0 ] || residual_ms=0
        if [ "$wall_ms" -gt 0 ]; then
            residual_pct=$((residual_ms * 10000 / wall_ms))
        else
            residual_pct=0
        fi
        log "DEPLOY_RECEIPT result=$([ "$exit_status" -eq 0 ] && echo success || echo blocked) rc=${exit_status} wall_ms=${wall_ms} phase=${DEPLOY_TASK_PHASE:-unknown} phase_sum_ms=${DEPLOY_TASK_WALL_PHASE_SUM_MS} residual_ms=${residual_ms} residual_bp=${residual_pct} max_phase=${DEPLOY_TASK_WALL_PHASE_MAX_NAME} max_phase_ms=${DEPLOY_TASK_WALL_PHASE_MAX_MS}"
        defense_overhead_write_async deploy_task deploy_total "$wall_ms" \
            "$([ "$exit_status" -eq 0 ] && echo PASS || echo FAIL)" \
            "deploy:${DEPLOY_TASK_ISSUE_ATTEMPT_ID:-$$}:${DEPLOY_TASK_STARTED_US}" || true
    fi
    if [ -n "${DEPLOY_TASK_ISSUE_ATTEMPT_ID:-}" ] && [ "${DEPLOY_TASK_ISSUE_TERMINAL_RECORDED:-0}" != "1" ]; then
        if [ "${DEPLOY_TASK_DEPLOY_COMPLETED:-0}" = "1" ]; then
            deploy_task_append_issue_event "deployed" "exit_0"
        else
            deploy_task_append_issue_event "blocked" "exit_${exit_status}"
        fi
        DEPLOY_TASK_ISSUE_TERMINAL_RECORDED=1
    fi
    if [ "$exit_status" -ne 0 ]; then
        deploy_task_yaml_transaction_rollback || true
    fi
    deploy_task_postcondition_cleanup
    deploy_task_exit_nudge
    deploy_task_release_ninja_lock
}

