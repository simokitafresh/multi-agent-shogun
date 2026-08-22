#!/bin/bash
# deploy_task/delivery.sh — cluster C report, RC, delivery evidence, and fallback.
# Function bodies are extracted verbatim from deploy_task.sh.
deploy_task_continuation_contract_valid() {
    local task_file="$1"
    local report_file="$2"
    local parent_cmd="$3"

    [ -f "$task_file" ] || return 1
    [ -f "$report_file" ] || return 1
    python3 - "$task_file" "$report_file" "$parent_cmd" <<'PY'
import os, sys, yaml
task_path, report_path, parent = sys.argv[1:]
task = (yaml.safe_load(open(task_path, encoding="utf-8")) or {}).get("task") or {}
report = yaml.safe_load(open(report_path, encoding="utf-8")) or {}

raw_many = task.get("continuation_of_reports")
if raw_many is None:
    raw_many = [task.get("continuation_of_report")]
if not isinstance(raw_many, list) or any(not isinstance(item, str) for item in raw_many):
    raise SystemExit(1)
continuations = {item.strip() for item in raw_many if item.strip()}
expected = f"queue/reports/{os.path.basename(report_path)}"
assigned = task.get("assigned_acs")
subtask = str(task.get("subtask_id") or "").strip()
prior_task = str(report.get("task_id") or "").strip()
valid = (
    str(task.get("parent_cmd") or "").strip() == parent
    and bool(continuations.intersection({expected, os.path.basename(report_path)}))
    and isinstance(assigned, list) and bool(assigned)
    and bool(subtask) and subtask != prior_task
    and str(report.get("parent_cmd") or "").strip() == parent
    and str(report.get("status") or "").strip() == "completed"
    and str(report.get("verdict") or "").strip() in {"PASS", "PASS_NO_IMPROVEMENT"}
)
raise SystemExit(0 if valid else 1)
PY
}

deploy_task_has_completed_peer_report() {
    local parent_cmd="$1"
    local ninja_name="$2"
    local task_file="${3:-}"
    local report_file report_base report_ninja report_status report_verdict

    [ -n "$parent_cmd" ] || return 1

    for report_file in "$SCRIPT_DIR/queue/reports/"*"_report_${parent_cmd}.yaml"; do
        # archive_completed keeps a compatibility symlink at the former live
        # path. The report is already terminally archived and must not occupy
        # another worker's deployment slot.
        [ -f "$report_file" ] && [ ! -L "$report_file" ] || continue
        report_base=$(basename "$report_file")
        report_ninja="${report_base%%_report_*}"
        [ "$report_ninja" = "$ninja_name" ] && continue

        report_status=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "status" "" 2>/dev/null || true)
        report_verdict=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "verdict" "" 2>/dev/null || true)
        if [ "$report_status" = "completed" ] || [[ "$report_verdict" =~ ^(PASS|FAIL|PASS_NO_IMPROVEMENT)$ ]]; then
            # Natural-boundary commands legitimately continue after a reviewed
            # reconnaissance/report stage.  Require an explicit, machine-bound
            # continuation contract so ordinary duplicate deployments remain
            # fail-closed: distinct subtask_id, explicit parent AC mapping, and
            # every exact completed peer report being continued.  The plural
            # form is required when a natural-boundary command has more than
            # one completed predecessor; the singular field remains compatible.
            if deploy_task_continuation_contract_valid "$task_file" "$report_file" "$parent_cmd"; then
                log "continuation_deploy: ${parent_cmd} continues ${report_base} with explicit AC mapping — allowing"
                continue
            fi
            # A karo-RC'd FAIL report is a formal instruction to rework the
            # command, not a settled outcome — allow redeploying it to a
            # different idle ninja without disturbing the original report.
            if [ "$report_status" = "revision_requested" ] && [ "$report_verdict" = "FAIL" ] \
                && deploy_task_has_formal_karo_rc_for_peer_report "$parent_cmd" "$report_ninja" "$report_file"; then
                log "formal_karo_rc_peer_redeploy: ${parent_cmd} peer=${report_ninja} report=${report_base} — allowing"
                continue
            fi
            log "BLOCK: ${parent_cmd} already has completed peer report ${report_base} (status=${report_status:-empty}, verdict=${report_verdict:-empty})"
            echo "BLOCK: ${parent_cmd} already has completed report from ${report_ninja}: ${report_base}" >&2
            return 0
        fi
    done

    return 1
}

deploy_task_cmd_complete_processed() {
    local parent_cmd="$1"
    local gate_dir="$SCRIPT_DIR/queue/gates/${parent_cmd}"
    local skill_log="$SCRIPT_DIR/logs/skill_execution.log"

    [ -n "$parent_cmd" ] || return 1

    if [ -f "$gate_dir/archive.done" ]; then
        return 0
    fi

    if [ -f "$skill_log" ] && grep -Fq "|PASS|cmd_complete_gate PASS|cmd_complete_gate|${parent_cmd}|" "$skill_log"; then
        return 0
    fi

    return 1
}

deploy_task_has_formal_karo_rc_for_report() {
    local parent_cmd="$1"
    local ninja_name="$2"
    local report_file="$3"
    local task_file="${4:-}"
    local report_abs task_report_abs approval_file

    [ -n "$parent_cmd" ] || return 1
    [ -n "$ninja_name" ] || return 1
    [ -f "$report_file" ] || return 1
    [ -f "$task_file" ] || return 1

    report_abs=$(realpath "$report_file" 2>/dev/null) || return 1
    task_report_abs=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "report_path" "" 2>/dev/null || true)
    [ -n "$task_report_abs" ] || return 1
    [[ "$task_report_abs" = /* ]] || task_report_abs="$SCRIPT_DIR/$task_report_abs"
    task_report_abs=$(realpath "$task_report_abs" 2>/dev/null) || return 1
    [ "$task_report_abs" = "$report_abs" ] || return 1

    for approval_file in "$SCRIPT_DIR/queue/gates/$parent_cmd/review_approvals/reports/"*/karo.yaml; do
        [ -f "$approval_file" ] || continue
        if python3 - "$approval_file" "$report_abs" "$parent_cmd" "$ninja_name" "$SCRIPT_DIR" <<'PY'
import os
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

approval_path, report_path, parent_cmd, ninja_name, root = sys.argv[1:]
approval = yaml.safe_load(open(approval_path, encoding="utf-8")) or {}
report = yaml.safe_load(open(report_path, encoding="utf-8")) or {}
approved_report = str(approval.get("report") or "").strip()
if approved_report and not os.path.isabs(approved_report):
    approved_report = os.path.join(root, approved_report)
valid = (
    str(approval.get("role") or "").strip() == "karo"
    and str(approval.get("result") or "").strip() == "RC"
    and os.path.realpath(approved_report) == os.path.realpath(report_path)
    and str(report.get("status") or "").strip() == "revision_requested"
    and str(report.get("verdict") or "").strip() in {"PASS", "FAIL"}
    and str(report.get("parent_cmd") or "").strip() == parent_cmd
    and str(report.get("worker_id") or "").strip() == ninja_name
)
raise SystemExit(0 if valid else 1)
PY
        then
            return 0
        fi
    done

    return 1
}

# Peer variant of deploy_task_has_formal_karo_rc_for_report: the redeploy
# target is a different idle ninja, not the report's own worker, so ownership
# is bound to the report's worker_id instead of the deploying ninja's task
# file. Only a FAIL verdict qualifies — a formally RC'd PASS report has no
# rework reason to hand to a peer.
deploy_task_has_formal_karo_rc_for_peer_report() {
    local parent_cmd="$1"
    local peer_ninja="$2"
    local report_file="$3"
    local report_abs approval_file

    [ -n "$parent_cmd" ] || return 1
    [ -n "$peer_ninja" ] || return 1
    [ -f "$report_file" ] || return 1

    report_abs=$(realpath "$report_file" 2>/dev/null) || return 1

    for approval_file in "$SCRIPT_DIR/queue/gates/$parent_cmd/review_approvals/reports/"*/karo.yaml; do
        [ -f "$approval_file" ] || continue
        if python3 - "$approval_file" "$report_abs" "$parent_cmd" "$peer_ninja" "$SCRIPT_DIR" <<'PY'
import os
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

approval_path, report_path, parent_cmd, ninja_name, root = sys.argv[1:]
approval = yaml.safe_load(open(approval_path, encoding="utf-8")) or {}
report = yaml.safe_load(open(report_path, encoding="utf-8")) or {}
approved_report = str(approval.get("report") or "").strip()
if approved_report and not os.path.isabs(approved_report):
    approved_report = os.path.join(root, approved_report)
valid = (
    str(approval.get("role") or "").strip() == "karo"
    and str(approval.get("result") or "").strip() == "RC"
    and os.path.realpath(approved_report) == os.path.realpath(report_path)
    and str(report.get("status") or "").strip() == "revision_requested"
    and str(report.get("verdict") or "").strip() == "FAIL"
    and str(report.get("parent_cmd") or "").strip() == parent_cmd
    and str(report.get("worker_id") or "").strip() == ninja_name
)
raise SystemExit(0 if valid else 1)
PY
        then
            return 0
        fi
    done

    return 1
}

deploy_task_has_pending_own_report() {
    local parent_cmd="$1"
    local ninja_name="$2"
    local task_file="${3:-}"
    local report_file report_base report_status report_verdict

    [ -n "$parent_cmd" ] || return 1
    [ -n "$ninja_name" ] || return 1

    if deploy_task_cmd_complete_processed "$parent_cmd"; then
        return 1
    fi

    for report_file in "$SCRIPT_DIR/queue/reports/${ninja_name}_report_${parent_cmd}"*.yaml; do
        [ -f "$report_file" ] || continue
        report_base=$(basename "$report_file")
        report_status=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "status" "" 2>/dev/null || true)
        report_verdict=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "verdict" "" 2>/dev/null || true)
        if [[ "$report_verdict" =~ ^(PASS|FAIL|PASS_NO_IMPROVEMENT)$ ]]; then
            if [ "$report_status" = "revision_requested" ] \
                && deploy_task_has_formal_karo_rc_for_report "$parent_cmd" "$ninja_name" "$report_file" "$task_file"; then
                log "formal_karo_rc_redeploy: ${parent_cmd} report=${report_base} — allowing"
                continue
            fi
            log "BLOCK: ${parent_cmd} has pending own report ${report_base} (status=${report_status:-empty}, verdict=${report_verdict}, cmd_complete=missing)"
            echo "BLOCK: ${ninja_name} has pending report for ${parent_cmd}: ${report_base}. Run/finish cmd_complete_gate before redeploying this ninja, or select another ninja." >&2
            return 0
        fi
    done

    return 1
}

deploy_task_direct_yaml_is_preinjected() {
    local task_file="$1"
    [ "$DIRECT_MODE" = true ] || return 1
    [ -f "$task_file" ] || return 1

    python3 - "$task_file" <<'PY'
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

path = sys.argv[1]
required = (
    "related_lessons",
    "semantic_concepts",
    "standard_skills",
    "memory_db_context",
    "context_hints",
    "report_filename",
)

try:
    with open(path, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    raise SystemExit(1)

task = data.get("task") if isinstance(data, dict) else {}
if not isinstance(task, dict):
    raise SystemExit(1)

for key in required:
    value = task.get(key)
    if value in (None, "", [], {}):
        raise SystemExit(1)

raise SystemExit(0)
PY
}

log_output_file() {
    local output_file="$1"
    if [ -f "$output_file" ]; then
        while IFS= read -r line; do
            log "$line"
        done < "$output_file"
        rm -f "$output_file"
    fi
}

deploy_task_unread_count() {
    local agent_name="$1"
    local inbox_file="$SCRIPT_DIR/queue/inbox/${agent_name}.yaml"
    local count

    if [ ! -f "$inbox_file" ]; then
        echo 1
        return 0
    fi

    count=$(awk '
        BEGIN { c = 0 }
        /^- / { in_msg = 1; read_state = "false"; next }
        in_msg && /^  read:[[:space:]]*/ {
            line = $0
            sub(/^  read:[[:space:]]*/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            if (tolower(line) != "true") c++
            in_msg = 0
        }
        END {
            if (in_msg) c++
            print c
        }
    ' "$inbox_file" 2>/dev/null || echo 0)
    case "$count" in
        ''|*[!0-9]*) count=0 ;;
    esac
    printf '%s\n' "$count"
}

deploy_task_pane_has_delivery_evidence() {
    local agent_name="$1"
    local pane_snapshot="$2"
    printf '%s\n' "$pane_snapshot" | tr '\n' ' ' \
        | grep -qE "inbox[0-9]+ — .*queue/tasks/${agent_name}\.yaml|[•◦] (Working|Ran |Waiting|Running .*([Hh]ook|UserPromptSubmit|PostToolUse))"
}

deploy_task_inbox_message_count() {
    local agent_name="$1"
    local inbox_file="$SCRIPT_DIR/queue/inbox/${agent_name}.yaml"

    if [ ! -f "$inbox_file" ]; then
        echo 0
        return 0
    fi

    grep -c '^- ' "$inbox_file" 2>/dev/null || echo 0
}

safe_inbox_write() {
    local target="$1"
    local message="$2"
    local msg_type="$3"
    local from="$4"
    local action="${5:-}"  # AC2: action省略によるhookスキップ構造穴修正(cmd_3102)
    local inbox_file="$SCRIPT_DIR/queue/inbox/${target}.yaml"
    local before_count after_count output status

    before_count="$(deploy_task_inbox_message_count "$target")"
    case "$before_count" in
        ''|*[!0-9]*) before_count=0 ;;
    esac

    status=0
    if [ "$msg_type" = "task_assigned" ] && [ "${DEPLOY_TASK_ASYNC_CODEX_DELIVERY_VERIFY:-1}" = "1" ]; then
        output="$(INBOX_CODEX_DELIVERY_VERIFY_ASYNC=1 \
            bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$target" "$message" "$msg_type" "$from" "$action" 2>&1)" || status=$?
    else
        output="$(bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$target" "$message" "$msg_type" "$from" "$action" 2>&1)" || status=$?
    fi
    if [ -n "$output" ]; then
        while IFS= read -r line; do
            log "inbox_write: $line"
        done <<< "$output"
    fi

    if [ "$status" -eq 0 ]; then
        log "${target}: inbox_write success (type=${msg_type})"
        return 0
    fi

    after_count="$(deploy_task_inbox_message_count "$target")"
    case "$after_count" in
        ''|*[!0-9]*) after_count=0 ;;
    esac

    if [ -f "$inbox_file" ] && [ "$after_count" -gt "$before_count" ] 2>/dev/null; then
        log "WARN: ${target}: inbox persisted but post-write delivery/verification failed (status=${status}, type=${msg_type}); continuing"
        return 0
    fi

    log "ERROR: ${target}: inbox_write failed before persistence (status=${status}, type=${msg_type})"
    return "$status"
}

handle_yaml_injection_failure() {
    local injector_name="$1"
    local task_file="$2"
    local ninja_name="${3:-${NINJA_NAME:-unknown}}"
    local message

    message="YAML注入失敗: ${injector_name} task_file=${task_file} ninja=${ninja_name}。deploy_task.logを確認されたし。"
    log "ERROR: ${injector_name} failed for ${task_file} (ninja=${ninja_name})"
    safe_inbox_write "karo" "$message" "deploy_error" "deploy_task" || \
        log "ERROR: ${injector_name} failure notification to karo failed"
    return 0
}

deploy_task_guard_task_yaml_syntax() {
    local stage="$1"
    local task_file="$2"
    local ninja_name="${3:-${NINJA_NAME:-unknown}}"
    local py_output message

    py_output="$(mktemp)" || return 1
    if python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1], encoding='utf-8'))" "$task_file" >"$py_output" 2>&1; then
        rm -f "$py_output"
        log "task_yaml_syntax: PASS (${stage})"
        return 0
    fi

    message="YAML構文検証FAIL: stage=${stage} task_file=${task_file} ninja=${ninja_name}。task_assigned送信・report template生成・draft review送信を停止。deploy_task.logを確認されたし。"
    log "FATAL: task YAML syntax invalid after ${stage}: ${task_file} (ninja=${ninja_name})"
    while IFS= read -r line; do
        [ -n "$line" ] && log "YAML_PARSE: $line"
    done < "$py_output"
    rm -f "$py_output"
    safe_inbox_write "karo" "$message" "deploy_error" "deploy_task" || \
        log "ERROR: task YAML syntax failure notification to karo failed"
    return 1
}

deploy_task_send_direct_renudge() {
    local agent_name="$1"
    local pane_target unread_count capture_tail

    pane_target="$(pane_lookup "$agent_name" 2>/dev/null || true)"
    if [ -z "$pane_target" ]; then
        log "${agent_name}: delayed re-nudge skipped (pane not found)"
        return 0
    fi

    capture_tail=$(tmux capture-pane -t "$pane_target" -p -S -30 2>/dev/null || true)
    if deploy_task_pane_has_delivery_evidence "$agent_name" "$capture_tail"; then
        log "${agent_name}: delayed re-nudge skipped (delivery evidence present; unread observed as processing)"
        return 0
    fi

    unread_count="$(deploy_task_unread_count "$agent_name")"
    case "$unread_count" in
        ''|*[!0-9]*) unread_count=1 ;;
    esac
    if ! [ "$unread_count" -gt 0 ] 2>/dev/null; then
        log "${agent_name}: delayed re-nudge skipped (no unread messages)"
        return 0
    fi

    if safe_send_keys_atomic "$pane_target" "inbox${unread_count}" 0.3; then
        log "${agent_name}: delayed direct re-nudge sent (inbox${unread_count})"
    else
        log "${agent_name}: WARN delayed direct re-nudge failed (inbox${unread_count})"
    fi
}

deploy_task_post_deploy_verify() {
    local ninja_name="$1"
    local pane_target unread_count agent_state capture_tail

    pane_target="$(pane_lookup "$ninja_name" 2>/dev/null || true)"
    if [ -z "$pane_target" ]; then
        log "POST-DEPLOY VERIFY ${ninja_name}: pane not found; retry suggestion: bash scripts/deploy_task.sh ${ninja_name} <cmd_id>"
        return 0
    fi

    agent_state=$(tmux show-options -p -t "$pane_target" -v @agent_state 2>/dev/null || true)
    unread_count="$(deploy_task_unread_count "$ninja_name")"
    case "$unread_count" in
        ''|*[!0-9]*) unread_count=0 ;;
    esac
    capture_tail=$(tmux capture-pane -t "$pane_target" -p -S -30 2>/dev/null || true)
    log "POST-DEPLOY VERIFY ${ninja_name}: pane=${pane_target}, state=${agent_state:-unknown}, unread=${unread_count}"
    while IFS= read -r line; do
        log "POST-DEPLOY VERIFY ${ninja_name} pane: ${line}"
    done <<< "$capture_tail"

    DEPLOY_TASK_DELIVERY_EVIDENCE=0
    if deploy_task_pane_has_delivery_evidence "$ninja_name" "$capture_tail"; then
        DEPLOY_TASK_DELIVERY_EVIDENCE=1
        log "POST-DEPLOY VERIFY ${ninja_name}: delivery evidence present; unread=${unread_count} observed as processing, re-nudge suppressed"
    elif [ "$unread_count" -gt 0 ] 2>/dev/null; then
        log "POST-DEPLOY VERIFY ${ninja_name}: no delivery evidence and unread remains; bounded delayed re-nudge eligible"
    else
        log "POST-DEPLOY VERIFY ${ninja_name}: inbox consumed or no unread messages detected"
    fi
}

deploy_task_exit_nudge() {
    deploy_task_exit_draft_review_fallback

    if [ "${DEPLOY_TASK_EXIT_NUDGE_ARMED:-0}" != "1" ]; then
        return 0
    fi
    if [ "${DEPLOY_TASK_EXIT_NUDGE_SENT:-0}" = "1" ]; then
        return 0
    fi
    if [ -z "${NINJA_NAME:-}" ] || [ -z "${MESSAGE:-}" ] || [ -z "${TYPE:-}" ] || [ -z "${FROM:-}" ]; then
        return 0
    fi

    DEPLOY_TASK_EXIT_NUDGE_SENT=1
    log "${NINJA_NAME}: EXIT trap sending inbox_write (interrupted before main nudge)"
    safe_inbox_write "$NINJA_NAME" "$MESSAGE" "$TYPE" "$FROM" "task_start" || \
        log "${NINJA_NAME}: WARN EXIT trap inbox_write failed"
}

deploy_task_exit_draft_review_fallback() {
    if [ "${DEPLOY_TASK_DRAFT_REVIEW_ARMED:-0}" != "1" ]; then
        return 0
    fi
    if [ "${DEPLOY_TASK_DRAFT_REVIEW_SENT:-0}" = "1" ]; then
        return 0
    fi
    if [ -z "${DEPLOY_TASK_DRAFT_REVIEW_TASK_FILE:-}" ] ||
       [ -z "${DEPLOY_TASK_DRAFT_REVIEW_CMD_ID:-}" ] ||
       [ -z "${DEPLOY_TASK_DRAFT_REVIEW_NINJA:-}" ] ||
       [ -z "${DEPLOY_TASK_DRAFT_REVIEW_TYPE:-}" ]; then
        return 0
    fi

    DEPLOY_TASK_DRAFT_REVIEW_SENT=1
    log "${DEPLOY_TASK_DRAFT_REVIEW_NINJA}: EXIT trap draft_review fallback"
    deploy_task_ensure_fallback_report_metadata \
        "$DEPLOY_TASK_DRAFT_REVIEW_TASK_FILE" \
        "$DEPLOY_TASK_DRAFT_REVIEW_NINJA" \
        "$DEPLOY_TASK_DRAFT_REVIEW_CMD_ID" || \
        log "${DEPLOY_TASK_DRAFT_REVIEW_NINJA}: WARN EXIT trap fallback report metadata repair failed"
    maybe_notify_draft_review \
        "$DEPLOY_TASK_DRAFT_REVIEW_TASK_FILE" \
        "$DEPLOY_TASK_DRAFT_REVIEW_CMD_ID" \
        "$DEPLOY_TASK_DRAFT_REVIEW_NINJA" \
        "$DEPLOY_TASK_DRAFT_REVIEW_TYPE" || \
        log "${DEPLOY_TASK_DRAFT_REVIEW_NINJA}: WARN EXIT trap draft_review fallback failed"
}

deploy_task_ensure_fallback_report_metadata() {
    local task_file="$1"
    local ninja_name="$2"
    local fallback_parent_cmd="$3"

    [ -f "$task_file" ] || return 0
    [ -n "$ninja_name" ] || return 0

    local parent_cmd task_id _ac_task_id project report_path report_filename ac_version
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" \
        parent_cmd task_id _ac_task_id project report_path report_filename ac_version 2>/dev/null)" || true

    parent_cmd="${parent_cmd:-$fallback_parent_cmd}"
    [ -n "$parent_cmd" ] || return 0

    if [ -z "${report_filename:-}" ]; then
        inject_report_filename "$task_file" || log "WARN: fallback_report_metadata inject_report_filename failed"
    fi

    if [ -z "${ac_version:-}" ]; then
        inject_ac_version "$task_file" || log "WARN: fallback_report_metadata inject_ac_version failed"
    fi

    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" \
        task_id _ac_task_id project report_path report_filename ac_version 2>/dev/null)" || true
    task_id="${task_id:-${_ac_task_id:-}}"

    if [ -z "${report_path:-}" ] || [ ! -f "$SCRIPT_DIR/${report_path}" ]; then
        generate_report_template "$ninja_name" "$task_id" "$parent_cmd" "${project:-infra}" || return 1
    else
        ensure_report_template_completeness "$SCRIPT_DIR/${report_path}" "$task_file" || return 1
    fi

    log "fallback_report_metadata: ensured report_path/ac_version for ${ninja_name} ${parent_cmd}"
}

run_python_logged() {
    local output_file="$1"
    shift

    local status=0
    "$@" >"$output_file" 2>&1 || status=$?
    log_output_file "$output_file"
    return "$status"
}

cleanup_none_task_files() {
    local ghost_task="$SCRIPT_DIR/queue/tasks/None.yaml"
    local ghost_lock="$SCRIPT_DIR/queue/tasks/None.yaml.lock"

    for ghost_path in "$ghost_task" "$ghost_lock"; do
        if [ -e "$ghost_path" ]; then
            rm -f "$ghost_path"
            log "Removed ghost task artifact: ${ghost_path#"$SCRIPT_DIR"/}"
        fi
    done
}
