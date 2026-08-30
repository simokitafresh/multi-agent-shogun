#!/bin/bash
# semantic-links: [[YAML安全書込み]], [[インフラ設計意図カタログ]]
# inbox_write.sh — メールボックスへのメッセージ書き込み（排他ロック付き）
# Usage: bash scripts/inbox_write.sh <target_agent> <content> [type] [from] [action]
# Example: bash scripts/inbox_write.sh karo "半蔵、任務完了" report_received hanzo notify_karo
#
# Supported types:
#   wake_up              — デフォルト。汎用起動通知
#   task_assigned        — タスク配備通知（家老→忍者）
#   task_new             — タスク作業指示（家老→忍者/家老内部）
#   task_supplement      — タスク補足通知（家老/軍師→忍者）
#   task_cancel          — タスク取消通知（家老→忍者）
#   cmd_new              — 新cmd通知（将軍→家老）
#   report_received/report_submitted/task_done/report_completed/report_done/report_ready/task_failed
#                        — 忍者報告完了通知（忍者→家老）※報告YAML検証+auto-done hookあり
#   uncommitted_block    — 未commitブロック通知
#   review_draft         — draft cmdレビュー依頼（家老→軍師）
#   review_result        — レビュー結果（軍師→家老）
#   review_feedback      — GATEフィードバック（家老→軍師）
#   report_review        — 忍者報告一次レビュー依頼（家老→軍師）
#   review_report        — review-pending状態Aの構造化起床（monitor→軍師）
#   accept_report        — review-pending状態Bの構造化起床（monitor→家老）
#   run_cmd_complete     — review-pending状態Cの構造化起床（monitor→家老）
#   report_review_result — 忍者報告レビュー結果（軍師→家老）
#   report_revision      — 正式RC後の忍者への修正通知
#   workaround_feedback  — workaround原因共有（家老→軍師）
#   review_hint          — レビューヒント（家老→軍師）
#   analysis_result      — idle時データ分析結果（軍師→家老）
#   investigation_result — hook/gate調査結果（忍者→家老、返答必須の専用lane）
#   gunshi_lesson_candidate — 軍師教訓候補（軍師→家老）
#   decomposition_feedback  — 分解フィードバック（軍師→家老）
#   verify_request       — RC修正再検証依頼（家老→軍師）
#   verify_result        — RC修正再検証結果（軍師→家老）
#   clear_command        — /clear送信（特殊: inbox_watcherがCLI直接操作）
#   model_switch         — /model切替（特殊: inbox_watcherがCLI直接操作）
#   recovery             — 復帰通知

set -e

# SCRIPT_DIR/SELF_SCRIPT_PATH: string ops instead of dirname/basename/cd subshells (~5ms savings on WSL2)
_iw_self="${BASH_SOURCE[0]:-$0}"
[[ "$_iw_self" != /* ]] && _iw_self="$PWD/$_iw_self"
INBOX_WRITE_INSTALL_ROOT="${_iw_self%/scripts/inbox_write.sh}"
SCRIPT_DIR="${INBOX_WRITE_ROOT_OVERRIDE:-${_iw_self%/scripts/inbox_write.sh}}"
SELF_SCRIPT_PATH="$_iw_self"
NINJA_NAMES=""
AGENT_CONFIG_LOADED=0

# B5 timing contract: only inbox_write_total is additive.  The three child
# intervals are diagnostic slices of that same wall clock and must never be
# summed with the parent by ledger consumers.
DEFENSE_OVERHEAD_REPO_ROOT="${DEFENSE_OVERHEAD_REPO_ROOT:-$SCRIPT_DIR}"
# shellcheck source=scripts/lib/defense_overhead_writer.sh
if [ -f "$INBOX_WRITE_INSTALL_ROOT/scripts/lib/defense_overhead_writer.sh" ]; then
    source "$INBOX_WRITE_INSTALL_ROOT/scripts/lib/defense_overhead_writer.sh"
else
    # Some isolated contract fixtures intentionally copy only inbox_write.sh.
    # Telemetry must never turn a valid durable delivery into a failure.
    defense_overhead_write_async() { return 0; }
    defense_overhead_drain_async() { return 0; }
fi
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/escalation_evidence.sh"
IW_TOTAL_STARTED_US="${EPOCHREALTIME/./}"
IW_ROOT_BASHPID="${BASHPID:-$$}"

iw_record_timing() {
    local check_id="$1" started_us="$2" verdict="${3:-PASS}"
    local finished_us="${EPOCHREALTIME/./}" wall_ms caller metadata_json
    wall_ms=$(( (finished_us - started_us + 999) / 1000 ))
    if [ "$check_id" = "inbox_write_total" ]; then
        # `FROM` is the stable caller label already supplied by every normal
        # inbox_write callsite. An explicit override keeps wrapper/fixture
        # callers observable without adding a process or filesystem lookup to
        # this hot path. The field is metadata-only: existing six-key ledger
        # consumers continue to select source/check_id/wall_ms/verdict/event_id.
        caller="${INBOX_WRITE_RUNTIME_CALLER:-${INBOX_WRITE_CALLER:-${FROM:-unknown}}}"
        case "$caller" in
            ''|unknown|UNKNOWN|*[!A-Za-z0-9_.:-]*) caller=unknown ;;
        esac
        metadata_json=$(printf '{"caller":"%s"}' "$caller")
        defense_overhead_write_async inbox_write "$check_id" "$wall_ms" "$verdict" \
            "inbox_write-${check_id}-${IW_ROOT_BASHPID}-${finished_us}" "$metadata_json" || true
    else
        defense_overhead_write_async inbox_write "$check_id" "$wall_ms" "$verdict" \
            "inbox_write-${check_id}-${IW_ROOT_BASHPID}-${finished_us}" || true
    fi
}

iw_record_total_on_exit() {
    local rc=$?
    [ "${BASHPID:-$$}" = "$IW_ROOT_BASHPID" ] || return "$rc"
    iw_record_timing inbox_write_total "$IW_TOTAL_STARTED_US" \
        "$([ "$rc" -eq 0 ] && printf PASS || printf BLOCK)"
    defense_overhead_drain_async
    return "$rc"
}
trap iw_record_total_on_exit EXIT

FIELD_GET_LOADED=0
CLI_LOOKUP_LOADED=0

usage() {
    cat <<'EOF'
Usage: inbox_write.sh <target_agent> <content> [type] [from] [action]
EOF
}

is_core_agent() {
    # AGENT_CONFIG_LOADED gate: agent_config.sh未ロード時に type コマンドを呼ばない。
    # WSL2 DrvFs上で type は PATH全走査に ~300ms かかり、2回で ~600ms の主要ボトルネック。
    # is_commander_role は agent_config.sh 内で定義されるため、未ロード時は存在し得ない。
    if [ "$AGENT_CONFIG_LOADED" = "1" ] && type is_commander_role >/dev/null 2>&1; then
        is_commander_role "$1"
        return $?
    fi

    # Keep filesystem fast-path side-effect free; full SSOT is used once agent_config is loaded.
    case " shogun karo gunshi " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

known_agent_from_fs() {
    local agent="$1"

    is_core_agent "$agent" && return 0
    [ -f "$SCRIPT_DIR/queue/tasks/${agent}.yaml" ] && return 0
    [ -f "$SCRIPT_DIR/queue/inbox/${agent}.yaml" ] && return 0
    return 1
}

sender_is_ninja_from_fs() {
    local agent="$1"

    [ "$agent" = "ninja_monitor" ] && return 1
    is_core_agent "$agent" && return 1
    [ -f "$SCRIPT_DIR/queue/tasks/${agent}.yaml" ]
}

target_is_ninja() {
    local agent="$1"
    local ninja=""

    is_core_agent "$agent" && return 1
    ensure_agent_config_loaded
    for ninja in $NINJA_NAMES; do
        if [ "$ninja" = "$agent" ]; then
            return 0
        fi
    done
    [ -f "$SCRIPT_DIR/queue/tasks/${agent}.yaml" ]
}

deploy_nudge_target_is_ninja() {
    local agent="$1"
    local config_root="${INBOX_WRITE_INSTALL_ROOT:-$SCRIPT_DIR}"
    local ninja=""
    target_is_ninja "$agent" && return 0

    # inbox_write may execute from the small installed runtime root used by
    # the watcher.  That root owns inbox files but intentionally has neither
    # queue/tasks nor agent_config.sh.  Preserve the role SSOT by resolving it
    # from the immutable installation root rather than the runtime override.
    if [ -f "$config_root/scripts/lib/agent_config.sh" ]; then
        # shellcheck source=/dev/null
        source "$config_root/scripts/lib/agent_config.sh"
        for ninja in $(get_ninja_names); do
            [ "$ninja" = "$agent" ] && return 0
        done
    fi
    return 1
}

ensure_agent_config_loaded() {
    if [ "${AGENT_CONFIG_LOADED:-0}" = "1" ]; then
        return 0
    fi

    if [ "${INBOX_WRITE_TEST:-}" != "1" ] && [ -f "$SCRIPT_DIR/scripts/lib/agent_config.sh" ]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/scripts/lib/agent_config.sh"
        NINJA_NAMES=$(get_ninja_names)
    else
        NINJA_NAMES=""
    fi

    AGENT_CONFIG_LOADED=1
}

ensure_field_get_loaded() {
    if [ "${FIELD_GET_LOADED:-0}" = "1" ]; then
        return 0
    fi
    if [ -f "$SCRIPT_DIR/scripts/lib/field_get.sh" ]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/scripts/lib/field_get.sh" 2>/dev/null || true
    fi
    FIELD_GET_LOADED=1
}

ensure_cli_lookup_loaded() {
    if [ "${CLI_LOOKUP_LOADED:-0}" = "1" ]; then
        return 0
    fi
    if [ -f "$SCRIPT_DIR/scripts/lib/cli_lookup.sh" ]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/scripts/lib/cli_lookup.sh" 2>/dev/null || true
    fi
    CLI_LOOKUP_LOADED=1
}

DIRTY_HUNK_FILTER_LOADED=0
ensure_dirty_hunk_filter_loaded() {
    if [ "${DIRTY_HUNK_FILTER_LOADED:-0}" = "1" ]; then
        return 0
    fi
    if [ -f "$SCRIPT_DIR/scripts/lib/report_commit_nonoverlap_filter.sh" ]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/scripts/lib/report_commit_nonoverlap_filter.sh" 2>/dev/null || true
    fi
    DIRTY_HUNK_FILTER_LOADED=1
}

# Report completion must observe HEAD vs working tree, never the process-wide
# shared index (or a caller-inherited private GIT_INDEX_FILE).  In a multi-agent
# checkout that index can intentionally lag HEAD or contain another ninja's
# stage, which used to turn an already committed report into a false BLOCK.
inbox_status_against_head() {
    local repo="$1" temp_index rc
    shift
    temp_index="$(mktemp "${TMPDIR:-/tmp}/inbox-head-index.XXXXXX")"
    rm -f "$temp_index"
    rc=0
    (
        export GIT_INDEX_FILE="$temp_index"
        unset GIT_DIR GIT_WORK_TREE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
        git -C "$repo" read-tree HEAD
        git -C "$repo" status --porcelain --untracked-files=all -- "$@"
    ) || rc=$?
    rm -f "$temp_index" "$temp_index.lock"
    return "$rc"
}

lock_path() {
    case "$1" in
        /mnt/c/*|/mnt/d/*)
            local sanitized="${1//[^[:alnum:]._-]/_}"
            if ((${#sanitized} > 180)); then
                sanitized="${sanitized:0:120}_${sanitized: -40}_${#1}"
            fi
            printf '/tmp/shogun_lock_%s.lock' "$sanitized"
            ;;
        *)
            printf '%s.lock' "$1"
            ;;
    esac
}

resolve_inbox_file_path() {
    local inbox_file="$1"
    local resolved=""
    local inbox_dir=""

    inbox_dir="${inbox_file%/*}"
    if [[ ! -L "$inbox_file" && ! -L "$inbox_dir" ]]; then
        printf '%s\n' "$inbox_file"
        return 0
    fi

    resolved=$(readlink -f "$inbox_file" 2>/dev/null || true)
    if [ -n "$resolved" ]; then
        printf '%s\n' "$resolved"
        return 0
    fi

    # File may not exist yet. Resolve the parent directory so queue/inbox
    # symlinks still write to the real mailbox location on first delivery.
    local inbox_base resolved_dir
    inbox_base="${inbox_file##*/}"
    resolved_dir=$(readlink -f "$inbox_dir" 2>/dev/null || true)
    if [ -n "$resolved_dir" ]; then
        printf '%s/%s\n' "$resolved_dir" "$inbox_base"
    else
        printf '%s\n' "$inbox_file"
    fi
}

inbox_yaml_field_get() {
    local yaml_file="$1"
    local field_name="$2"
    local default_value="${3:-}"

    ensure_field_get_loaded
    if type field_get &>/dev/null; then
        FIELD_GET_NO_LOG=1 field_get "$yaml_file" "$field_name" "$default_value" 2>/dev/null || true
        return 0
    fi

    grep -m1 -E "^[[:space:]]*${field_name}:" "$yaml_file" 2>/dev/null \
        | sed 's/^[^:]*:[[:space:]]*//' \
        | sed "s/^['\"]//;s/['\"]$//"
}

# task_assigned notifications carry the destination task generation so the
# receiver can reject stale or cross-task mail without inferring identity from
# prose.  This is deliberately separate from report identity: report fields
# must continue to come from the referenced report YAML, while assignment
# fields come only from queue/tasks/{agent}.yaml at send time.
inbox_task_assignment_identity_fields() {
    local target="$1"
    local task_yaml="$SCRIPT_DIR/queue/tasks/${target}.yaml"
    local task_id="" parent_cmd=""

    if [ -f "$task_yaml" ]; then
        task_id=$(inbox_yaml_field_get "$task_yaml" "task_id" "")
        parent_cmd=$(inbox_yaml_field_get "$task_yaml" "parent_cmd" "")
    fi

    # Explicit empty fields are the no-task contract.  The receiver must not
    # treat an unbound assignment as belonging to its current task.
    # Commander targets (karo/gunshi/shogun) have no ninja task binding; an
    # unbound task_assigned to them is a directive, never "not my task".
    # Bind it to the fixed token so the receiver's task_id filter cannot
    # drop it (2026-08-28 T159/型十一弾-2, 8th recurrence 2026-08-29 14:09).
    case "$target" in
        karo|gunshi|shogun)
            [ -n "$task_id" ] || task_id="commander_directive"
            ;;
    esac
    printf '%s\n' "$task_id" "$parent_cmd"
}

# task_supplement notifications are consumed by the ninja's current-task
# filter. Bind the explicit identity from the message into dedicated fields
# and reject stale, malformed, or taskless supplements before persistence.
# Unlike task_assigned, this lane must not silently borrow the destination
# task identity: a supplement can arrive after a re-deployment and must prove
# which task it belongs to.
inbox_task_supplement_identity() {
    local target="$1"
    local content="$2"
    local task_yaml="$SCRIPT_DIR/queue/tasks/${target}.yaml"
    local current_task_id="" current_parent_cmd=""
    local supplied_task_id="" supplied_parent_cmd=""
    local token value
    local task_id_count=0 parent_cmd_count=0

    if [ ! -f "$task_yaml" ]; then
        echo "BLOCK: task_supplement requires current destination task identity (missing task YAML: ${task_yaml})" >&2
        return 2
    fi

    current_task_id=$(inbox_yaml_field_get "$task_yaml" "task_id" "")
    current_parent_cmd=$(inbox_yaml_field_get "$task_yaml" "parent_cmd" "")
    if [ -z "$current_task_id" ] || [ -z "$current_parent_cmd" ]; then
        echo "BLOCK: task_supplement requires non-empty current task_id and parent_cmd" >&2
        return 2
    fi

    for token in $content; do
        case "$token" in
            task_id=*)
                value="${token#task_id=}"
                task_id_count=$((task_id_count + 1))
                supplied_task_id="$value"
                ;;
            parent_cmd=*)
                value="${token#parent_cmd=}"
                parent_cmd_count=$((parent_cmd_count + 1))
                supplied_parent_cmd="$value"
                ;;
        esac
    done

    if [ "$task_id_count" -ne 1 ] || [ "$parent_cmd_count" -ne 1 ] \
        || [[ ! "$supplied_task_id" =~ ^[A-Za-z0-9_.:-]+$ ]] \
        || [[ ! "$supplied_parent_cmd" =~ ^cmd_[A-Za-z0-9_.:-]+$ ]]; then
        echo "BLOCK: task_supplement requires exactly one valid task_id=<id> and parent_cmd=<cmd>" >&2
        return 2
    fi

    if [ "$supplied_task_id" != "$current_task_id" ] || [ "$supplied_parent_cmd" != "$current_parent_cmd" ]; then
        echo "BLOCK: task_supplement identity mismatch: supplied=${supplied_task_id}/${supplied_parent_cmd} current=${current_task_id}/${current_parent_cmd}" >&2
        return 2
    fi

    printf '%s\n' "$supplied_task_id" "$supplied_parent_cmd"
}

report_yaml_is_template() {
    local report_path="$1"
    local verdict=""

    verdict=$(inbox_yaml_field_get "$report_path" "verdict" "")
    if [ -z "${verdict//[[:space:]]/}" ]; then
        echo "yes"
        return 0
    fi

    if grep -Eq '^[[:space:]]*result:[[:space:]]*.*FILL_THIS' "$report_path" 2>/dev/null; then
        echo "yes"
        return 0
    fi

    echo "no"
}

guard_report_revision_delivery() {
    local target="$1"
    local type="$2"
    local task_yaml report_path task_status report_status parent_cmd

    # Delivery is only the final durable edge.  The formal RC entry point must
    # atomically reopen report/task state before this notification is accepted.
    [ "$type" = "report_revision" ] || return 0
    target_is_ninja "$target" || return 0

    task_yaml="$SCRIPT_DIR/queue/tasks/${target}.yaml"
    [ -f "$task_yaml" ] || return 0
    task_status=$(inbox_yaml_field_get "$task_yaml" "status" "")
    parent_cmd=$(inbox_yaml_field_get "$task_yaml" "parent_cmd" "")
    report_path=$(inbox_yaml_field_get "$task_yaml" "report_path" "")
    if [ -z "$report_path" ]; then
        report_path=$(inbox_yaml_field_get "$task_yaml" "report_filename" "")
        [ -z "$report_path" ] || report_path="queue/reports/$report_path"
    fi
    case "$report_path" in
        /*) ;;
        ?*) report_path="$SCRIPT_DIR/$report_path" ;;
    esac
    report_status=""
    [ -n "$report_path" ] && [ -f "$report_path" ] \
        && report_status=$(inbox_yaml_field_get "$report_path" "status" "")

    case "$task_status:$report_status" in
        assigned:revision_requested|acknowledged:revision_requested|in_progress:revision_requested)
            return 0
            ;;
    esac
    case "$task_status" in
        done|failed|blocked) ;;
        *)
            [ "$report_status" = "completed" ] || return 0
            ;;
    esac

    echo "BLOCK: report_revision requires formal RC reopen before delivery (task status=${task_status:-missing}, report status=${report_status:-missing})." >&2
    echo "Run: bash scripts/review_approval.sh ${parent_cmd:-<cmd>} karo RC ${report_path:-<report>}" >&2
    exit 2
}

report_yaml_fail_details() {
    local report_path="$1"

    python3 - "$report_path" <<'PY'
import sys
import yaml

report_path = sys.argv[1]

try:
    with open(report_path, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception as exc:
    print(f"report YAML parse failed: {exc}")
    sys.exit(1)

if str(data.get("verdict", "") or "").strip() != "FAIL":
    sys.exit(1)

details = []
binary_checks = data.get("binary_checks") or {}
if isinstance(binary_checks, dict):
    for ac_key, checks in binary_checks.items():
        if not isinstance(checks, list):
            continue
        for index, item in enumerate(checks, 1):
            if not isinstance(item, dict):
                continue
            result = str(item.get("result", "") or "").strip().lower()
            waive_reason = str(item.get("waive_reason", "") or "").strip()
            if result in ("no", "false", "fail", "ng") and not waive_reason:
                check = str(item.get("check", "") or "").strip()
                details.append(f"{ac_key}[{index}]: {check or '(check未記入)'}")

if details:
    for detail in details:
        print(detail)
else:
    print("verdict: FAIL (binary_checksのno項目は検出できず。result.summary/lesson_candidate等を確認せよ)")

sys.exit(0)
PY
}

find_active_peer_deployments() {
    local target="$1"
    local tasks_dir="$SCRIPT_DIR/queue/tasks"

    [ -d "$tasks_dir" ] || return 0

    python3 - "$tasks_dir" "$target" <<'PY' 2>/dev/null || true
import glob
import os
import sys

import yaml

tasks_dir = sys.argv[1]
target = sys.argv[2]
active_statuses = {"assigned", "acknowledged", "in_progress"}


def task_payload(path):
    with open(path, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    task = data.get("task")
    if isinstance(task, dict):
        return task
    return data if isinstance(data, dict) else {}


target_path = os.path.join(tasks_dir, f"{target}.yaml")
if not os.path.exists(target_path):
    raise SystemExit(0)

try:
    target_task = task_payload(target_path)
except Exception:
    raise SystemExit(0)

parent_cmd = str(target_task.get("parent_cmd") or "").strip()
if not parent_cmd:
    raise SystemExit(0)
target_task_id = str(
    target_task.get("_ac_task_id")
    or target_task.get("subtask_id")
    or target_task.get("task_id")
    or ""
).strip()

for path in sorted(glob.glob(os.path.join(tasks_dir, "*.yaml"))):
    ninja = os.path.splitext(os.path.basename(path))[0]
    if ninja == target:
        continue
    try:
        task = task_payload(path)
    except Exception:
        continue
    if str(task.get("parent_cmd") or "").strip() != parent_cmd:
        continue
    status = str(task.get("status") or "").strip()
    peer_task_id = str(
        task.get("_ac_task_id")
        or task.get("subtask_id")
        or task.get("task_id")
        or ""
    ).strip()
    if target_task_id and peer_task_id and target_task_id != peer_task_id:
        continue
    if status in active_statuses:
        print(f"{ninja}\t{status}")
PY
}

notify_karo_duplicate_deploy_block() {
    local target="$1"
    local parent_cmd="$2"
    local duplicates="$3"
    local duplicate_summary=""

    [ "${INBOX_WRITE_DUP_BLOCK_NOTIFY:-1}" = "1" ] || return 0

    duplicate_summary=$(printf '%s\n' "$duplicates" | awk -F '\t' 'NF >= 2 { printf "%s(status=%s) ", $1, $2 }')
    duplicate_summary="${duplicate_summary%" "}"
    [ -n "$duplicate_summary" ] || duplicate_summary="$duplicates"

    INBOX_WRITE_DUP_BLOCK_NOTIFY=0 \
        bash "$SELF_SCRIPT_PATH" \
            karo \
            "task_id=commander_directive subject_task_id=${target} parent_cmd=${parent_cmd} [duplicate_deploy_gate] BLOCKED: parent_cmd=${parent_cmd} target=${target} duplicates=${duplicate_summary}" \
            deploy_blocked \
            inbox_write >/dev/null 2>&1 || true
}

inbox_yaml_strip_quotes() {
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

inbox_yaml_emit_field() {
    local first="$1"
    local key="$2"
    local value="$3"
    local prefix="  "
    [[ "$first" == "1" ]] && prefix="- "

    if [[ "$value" == "true" || "$value" == "false" ]]; then
        printf '%s%s: %s\n' "$prefix" "$key" "$value"
        return 0
    fi

    if [[ "$value" == *$'\n'* ]]; then
        printf '%s%s: |-\n' "$prefix" "$key"
        while IFS= read -r _line || [[ -n "$_line" ]]; do
            printf '    %s\n' "$_line"
        done <<< "$value"
        return 0
    fi

    value="${value//\'/\'\'}"
    printf "%s%s: '%s'\n" "$prefix" "$key" "$value"
}

inbox_build_message_block() {
    # cmd_inbox_write_speed: inbox_yaml_emit_field呼出しをインライン化(6コマンド置換→0)
    local output="" first=1 key value prefix
    while [[ $# -ge 2 ]]; do
        key="$1"; value="$2"
        prefix="  "
        [[ "$first" == "1" ]] && prefix="- "
        if [[ "$value" == "true" || "$value" == "false" ]]; then
            output+="${prefix}${key}: ${value}"$'\n'
        elif [[ "$value" == *$'\n'* ]]; then
            output+="${prefix}${key}: |-"$'\n'
            while IFS= read -r _iw_emit_line || [[ -n "$_iw_emit_line" ]]; do
                output+="    ${_iw_emit_line}"$'\n'
            done <<< "$value"
        else
            value="${value//\'/\'\'}"
            output+="${prefix}${key}: '${value}'"$'\n'
        fi
        first=0
        shift 2
    done
    printf '%s' "$output"
}

inbox_collect_records() {
    local inbox_file="$1"
    INBOX_RECORDS=()
    INBOX_RECORD_READS=()
    [[ -f "$inbox_file" ]] || return 0

    while IFS= read -r -d '' _record_item; do
        INBOX_RECORD_READS+=("${_record_item%%$'\034'*}")
        INBOX_RECORDS+=("${_record_item#*$'\034'}")
    done < <(
        awk '
            BEGIN { started = 0; rec = ""; read_state = "false"; }
            /^messages:[[:space:]]*\[\][[:space:]]*$/ { next }
            /^messages:[[:space:]]*$/ { next }
            /^- / {
                if (started) {
                    printf "%s\034%s\0", read_state, rec
                }
                rec = $0 "\n"
                read_state = "false"
                started = 1
                next
            }
            started {
                rec = rec $0 "\n"
                if ($0 ~ /^  read:[[:space:]]*/) {
                    read_state = $0
                    sub(/^  read:[[:space:]]*/, "", read_state)
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", read_state)
                }
            }
            END {
                if (started) {
                    printf "%s\034%s\0", read_state, rec
                }
            }
        ' "$inbox_file"
    )
}

inbox_write_records() {
    local inbox_file="$1"
    shift
    local tmp_file
    tmp_file=$(mktemp "${inbox_file}.XXXXXX.tmp")
    if [[ $# -eq 0 ]]; then
        printf 'messages: []\n' > "$tmp_file"
    else
        printf 'messages:\n' > "$tmp_file"
        local _record
        for _record in "$@"; do
            printf '%s' "$_record" >> "$tmp_file"
        done
    fi
    inbox_replace_file_with_retry "$tmp_file" "$inbox_file"
}

inbox_replace_file_with_retry() {
    local tmp_file="$1"
    local inbox_file="$2"
    local max_attempts="${INBOX_WRITE_MV_RETRIES:-3}"
    local sleep_sec="${INBOX_WRITE_MV_RETRY_SLEEP:-0.1}"
    local attempt=1

    while [ "$attempt" -le "$max_attempts" ]; do
        if mv "$tmp_file" "$inbox_file"; then
            return 0
        fi

        if [ "$attempt" -lt "$max_attempts" ]; then
            echo "[inbox_write] WARN: mv failed for ${inbox_file} (attempt ${attempt}/${max_attempts}), retrying; tmp=${tmp_file}" >&2
            sleep "$sleep_sec"
        else
            echo "[inbox_write] ERROR: mv failed for ${inbox_file} after ${max_attempts} attempts; tmp preserved at ${tmp_file}" >&2
            return 1
        fi

        attempt=$((attempt + 1))
    done
}

inbox_is_empty_file() {
    local inbox_file="$1"
    [[ -f "$inbox_file" ]] || {
        return 0
    }

    local first_line=""
    IFS= read -r first_line < "$inbox_file" || first_line=""
    [[ "$first_line" == "messages: []" ]]
}

inbox_message_count() {
    local inbox_file="$1"
    if inbox_is_empty_file "$inbox_file"; then
        echo 0
        return 0
    fi
    local count
    count=$(grep -c '^- ' "$inbox_file" 2>/dev/null || true)
    printf '%s\n' "${count:-0}"
}

inbox_unread_count() {
    local inbox_file="$1"
    [[ -f "$inbox_file" ]] || {
        echo 0
        return 0
    }

    awk '
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
    ' "$inbox_file"
}

inbox_gate_metrics_has_clear() {
    local cmd_id="$1"
    local gate_log="$SCRIPT_DIR/logs/gate_metrics.log"

    [ -n "$cmd_id" ] || return 1
    [ -f "$gate_log" ] || return 1

    awk -F '\t' -v cmd="$cmd_id" '$2 == cmd && $3 == "CLEAR" { found = 1; exit } END { exit(found ? 0 : 1) }' "$gate_log"
}

inbox_extract_report_path_from_content() {
    local content="$1"
    local candidate=""

    candidate=$(printf '%s' "$content" \
        | grep -oE 'queue/(archive/)?reports/[A-Za-z0-9_.-]+\.yaml|[A-Za-z0-9_-]+_report_[A-Za-z0-9_-]+\.yaml' \
        | head -1 || true)
    [ -n "$candidate" ] || return 0

    case "$candidate" in
        queue/*) printf '%s/%s\n' "$SCRIPT_DIR" "$candidate" ;;
        *)       printf '%s/queue/reports/%s\n' "$SCRIPT_DIR" "$candidate" ;;
    esac
}

inbox_extract_parent_cmd_from_report() {
    local report_path="$1"
    [ -f "$report_path" ] || return 0

    inbox_yaml_field_get "$report_path" "parent_cmd" ""
}

inbox_resolve_report_identity() {
    local report_path="$1" task_path="${2:-}"
    local helper="$SCRIPT_DIR/scripts/lib/report_unique_identity.py"
    [ -f "$report_path" ] || return 1
    if [ -n "$task_path" ] && [ -f "$task_path" ]; then
        python3 "$helper" verify --path "$report_path" --task "$task_path" --root "$SCRIPT_DIR"
    else
        python3 "$helper" resolve --path "$report_path" --root "$SCRIPT_DIR"
    fi
}

inbox_resolve_archived_report_for_task() {
    local active_report="$1" task_path="$2"
    local archive_dir="$SCRIPT_DIR/queue/archive/reports"
    local report_base="${active_report##*/}"
    report_base="${report_base%.yaml}"
    [ -d "$archive_dir" ] || return 1

    python3 - "$task_path" "$archive_dir" "$report_base" <<'PY'
import glob
import os
import sys

import yaml

task_path, archive_dir, report_base = sys.argv[1:]
with open(task_path, encoding="utf-8") as stream:
    task_doc = yaml.safe_load(stream) or {}
task = task_doc.get("task") or task_doc
candidates = sorted(glob.glob(os.path.join(archive_dir, report_base + "*.yaml")))

def text(mapping, key):
    return str(mapping.get(key) or "").strip()

task_version = int(task.get("report_identity_version") or 1)
matches = []
for path in candidates:
    try:
        with open(path, encoding="utf-8") as stream:
            report = yaml.safe_load(stream) or {}
        if not isinstance(report, dict):
            continue
        report_version = int(report.get("report_identity_version") or 1)
    except (OSError, ValueError, yaml.YAMLError):
        continue

    if task_version >= 2 or report_version >= 2:
        fields = (
            "report_id",
            "task_id",
            "parent_cmd",
            "parent_contract_fingerprint",
        )
        if task_version != 2 or report_version != 2:
            continue
        if not text(task, "report_id"):
            continue
        if all(text(task, field) == text(report, field) for field in fields):
            matches.append(path)
    else:
        # Legacy reports have no immutable identity. Preserve the historical
        # fallback only when the basename identifies exactly one generation.
        matches.append(path)

if len(matches) != 1:
    print(
        f"[report_format_gate] BLOCKED: archive identity candidates="
        f"{len(matches)} scanned={len(candidates)} base={report_base}",
        file=sys.stderr,
    )
    raise SystemExit(2)
print(matches[0])
PY
}

inbox_report_fingerprint() {
    local report_path="$1" fallback_identity="${2:-}"
    if [ -f "$report_path" ]; then
        sha256sum "$report_path" | awk '{print $1}'
        return 0
    fi
    # Compatibility for already-archived/missing legacy notifications: they
    # have no formal revision payload, so identity itself is the sole stable
    # generation. A present report always uses its content fingerprint.
    [ -n "$fallback_identity" ] || return 1
    printf '%s' "$fallback_identity" | sha256sum | awk '{print $1}'
}

inbox_report_revision_fingerprint() {
    local event_type="$1" action="$2" content="$3"
    [ "$event_type" = "report_revision" ] || { printf '%s' ''; return 0; }
    printf '%s\0%s' "$action" "$content" | sha256sum | awk '{print $1}'
}

# Reconcile the task side of an already durable terminal report event.
# This closes the crash window where the inbox row was appended but the task
# status update did not run. Exact retries repair that consequence instead of
# waiting for ninja_monitor's polling cycle. Deployment identity stays intact.
# cmd_karo_hotfix_completion_event_dedupe_20260723: reconcile durable terminal events.
inbox_reconcile_terminal_task_generation() {
    local ninja="$1" report_path="$2"
    local task_file="$SCRIPT_DIR/queue/tasks/${ninja}.yaml"
    [ -f "$task_file" ] && [ -f "$report_path" ] || return 0

    local report_status report_task_id report_parent task_id task_parent current_status now
    report_status=$(inbox_yaml_field_get "$report_path" "status" "")
    case "$report_status" in completed|done|success) ;; *) return 0 ;; esac
    report_task_id=$(inbox_yaml_field_get "$report_path" "task_id" "")
    report_parent=$(inbox_yaml_field_get "$report_path" "parent_cmd" "")
    task_id=$(inbox_yaml_field_get "$task_file" "task_id" "")
    task_parent=$(inbox_yaml_field_get "$task_file" "parent_cmd" "")
    [ -n "$report_task_id" ] && [ -n "$task_id" ] && [ "$report_task_id" != "$task_id" ] && return 0
    [ -n "$report_parent" ] && [ -n "$task_parent" ] && [ "$report_parent" != "$task_parent" ] && return 0

    current_status=$(inbox_yaml_field_get "$task_file" "status" "")
    case "$current_status" in done|failed|blocked) return 0 ;; esac
    now=$(date '+%Y-%m-%dT%H:%M:%S')
    (
        # shellcheck source=scripts/lib/yaml_field_set.sh
        source "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
        local -a updates=("status=done")
        [ -n "$(inbox_yaml_field_get "$task_file" "done_at" "")" ] || updates+=("done_at=$now")
        [ -n "$(inbox_yaml_field_get "$task_file" "completed_at" "")" ] || updates+=("completed_at=$now")
        yaml_field_set_batch "$task_file" task "${updates[@]}"
    ) 2>/dev/null
}

inbox_deliver_report_review_generation() {
    local ninja="$1" report_path="$2" parent_cmd="$3" fingerprint="$4"
    local report_base="${report_path##*/}"
    # fingerprint DEDUPE: marker+durable record(inbox or approval)で判定(atomic flock)
    # marker単独では抑止しない。inbox消失+approval不在ならre-send(修復)
    if [ -n "$fingerprint" ] && [ -n "$parent_cmd" ]; then
        local _root="${INBOX_WRITE_ROOT_OVERRIDE:-${SELF_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}}"
        local dedupe_dir="${_root}/queue/gates/${parent_cmd}"
        local dedupe_file="${dedupe_dir}/gunshi_review_notify_${fingerprint}.done"
        local dedupe_lock="${dedupe_dir}/gunshi_review_notify.lock"
        mkdir -p "$dedupe_dir" 2>/dev/null || true
        local _drf_fd
        if exec {_drf_fd}>"$dedupe_lock" && flock -w 3 "$_drf_fd"; then
            if [ -f "$dedupe_file" ]; then
                # marker exists: check durable record (inbox content or formal approval)
                local _inbox_has=false _approval_has=false
                local _gunshi_inbox="${_root}/queue/inbox/gunshi.yaml"
                if [ -f "$_gunshi_inbox" ] && grep -q "report_fingerprint=${fingerprint}" "$_gunshi_inbox" 2>/dev/null; then
                    _inbox_has=true
                fi
                local _approval_base="${dedupe_dir}/review_approvals/reports"
                if [ -d "$_approval_base" ]; then
                    local _ap_file
                    for _ap_file in "${_approval_base}"/*/gunshi.yaml; do
                        [ -f "$_ap_file" ] || continue
                        if grep -q "fingerprint: ${fingerprint}" "$_ap_file" 2>/dev/null && grep -q "result: LGTM" "$_ap_file" 2>/dev/null; then
                            _approval_has=true
                            break
                        fi
                    done
                fi
                if [ "$_inbox_has" = true ] || [ "$_approval_has" = true ]; then
                    flock -u "$_drf_fd"; eval "exec ${_drf_fd}>&-"
                    return 0
                fi
                # marker exists but inbox lost + no approval → re-send (repair)
            fi
        else
            [ -n "${_drf_fd:-}" ] && eval "exec ${_drf_fd}>&-"
        fi
    fi
    local _content="${ninja}報告完了。レビュー依頼: ${parent_cmd} report=${report_base}"
    [ -n "$fingerprint" ] && _content="${_content}
report_fingerprint=${fingerprint}"
    bash "$SELF_SCRIPT_PATH" gunshi \
        "$_content" \
        report_review karo notify_gunshi >/dev/null 2>&1
    # 送信成功後にDEDUPEフラグ記録(flock保持中)
    if [ -n "${dedupe_file:-}" ]; then
        printf '%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" > "$dedupe_file" 2>/dev/null || true
    fi
    [ -n "${_drf_fd:-}" ] && { flock -u "$_drf_fd" 2>/dev/null; eval "exec ${_drf_fd}>&-"; } || true
}

inbox_cmd_id_from_report_filename() {
    # <ninja>_report_<cmd_id>.yaml -> <cmd_id>.  The path is a reference the
    # sender supplied explicitly, so the cmd_id it encodes is structural; a
    # cmd_id merely written in prose is not and must never reach here.
    local path="$1" base=""
    [ -n "$path" ] || return 0
    base="${path##*/}"
    base="${base%.yaml}"
    case "$base" in
        *_report_cmd_*) printf '%s\n' "${base#*_report_}" ;;
    esac
}

# inbox_extract_cmd_id_for_completion_guard() was removed on 2026-07-26
# (cmd_karo_impl_autoread_structural_field_20260726).  It took the FIRST
# cmd_[A-Za-z0-9_]+ appearing anywhere in the message body, so a report that
# merely mentioned an earlier cmd was auto-read as that cmd's completion
# notification.  The auto-read decision now uses the report YAML's parent_cmd
# only; prose must never decide delivery.

inbox_review_log_has_lgtm() {
    local cmd_id="$1"
    local ninja="$2"
    local review_log="$SCRIPT_DIR/logs/gunshi_review_log.yaml"

    [ -n "$cmd_id" ] || return 1
    [ -n "$ninja" ] || return 1
    [ -f "$review_log" ] || return 1

    awk -v cmd="$cmd_id" -v ninja="$ninja" '
        function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); gsub(/^'\''|'\''$/, "", s); gsub(/^"|"$/, "", s); return s }
        function flush() {
            if (cur_cmd == cmd && review_type == "report" && report_ninja == ninja && verdict == "LGTM") {
                found = 1
            }
        }
        /^- cmd_id:[[:space:]]*/ {
            if (in_entry) flush()
            in_entry = 1
            cur_cmd = $0; sub(/^- cmd_id:[[:space:]]*/, "", cur_cmd); cur_cmd = trim(cur_cmd)
            review_type = report_ninja = verdict = ""
            next
        }
        !in_entry { next }
        /^  review_type:[[:space:]]*/ {
            review_type = $0; sub(/^  review_type:[[:space:]]*/, "", review_type); review_type = trim(review_type); next
        }
        /^  report_ninja:[[:space:]]*/ {
            report_ninja = $0; sub(/^  report_ninja:[[:space:]]*/, "", report_ninja); report_ninja = trim(report_ninja); next
        }
        /^  verdict:[[:space:]]*/ {
            verdict = $0; sub(/^  verdict:[[:space:]]*/, "", verdict); verdict = trim(verdict); next
        }
        END { if (in_entry) flush(); exit(found ? 0 : 1) }
    ' "$review_log"
}

# shellcheck source=scripts/lib/report_completion_events.sh
source "$SCRIPT_DIR/scripts/lib/report_completion_events.sh"

inbox_type_triggers_report_completion() {
    report_completion_event_type "$1" && return 0
    [ "$1" = "task_failed" ]
}

inbox_type_is_ninja_report_notification() {
    inbox_type_triggers_report_completion "$1" && return 0
    [ "$1" = "report_notification_missing" ]
}

inbox_type_is_report_lifecycle() {
    inbox_type_triggers_report_completion "$1" && return 0
    case "$1" in
        report_review|report_review_result|report_revision) return 0 ;;
    esac
    return 1
}

inbox_type_is_review_pending_nudge() {
    case "$1" in
        review_report|accept_report|run_cmd_complete) return 0 ;;
    esac
    return 1
}

# Review-pending monitor events must carry identity in dedicated fields.  The
# receiver must never recover task/cmd identity from free-form prose.
inbox_review_pending_identity() {
    local content="$1"
    INBOX_NUDGE_CONTENT="$content" python3 - <<'PY'
import os, re, sys
content = os.environ.get("INBOX_NUDGE_CONTENT", "")
values = {}
for token in content.split():
    if "=" not in token:
        continue
    key, value = token.split("=", 1)
    if key in {"task_id", "subject_task_id", "parent_cmd", "report_fingerprint", "report", "review_pending_state"}:
        values[key] = value
required = ("task_id", "subject_task_id", "parent_cmd", "report_fingerprint", "report", "review_pending_state")
if any(not values.get(key) for key in required):
    raise SystemExit(1)
if values["task_id"] != "commander_directive":
    raise SystemExit(1)
if not re.fullmatch(r"[A-Za-z0-9_.:-]+", values["subject_task_id"]):
    raise SystemExit(1)
if not re.fullmatch(r"cmd_[A-Za-z0-9_.:-]+", values["parent_cmd"]):
    raise SystemExit(1)
if not re.fullmatch(r"[0-9a-f]{64}", values["report_fingerprint"]):
    raise SystemExit(1)
if values["review_pending_state"] not in {"A", "B", "C"}:
    raise SystemExit(1)
if not re.fullmatch(r"(?:queue/)?(?:archive/)?reports/[A-Za-z0-9_.-]+\.yaml|[A-Za-z0-9_.-]+_report_[A-Za-z0-9_.-]+\.yaml", values["report"]):
    raise SystemExit(1)
print("\n".join(values[key] for key in required))
PY
}

# Karo-directed control-plane messages have three deliberately separate
# contracts.  Keep the information set synchronized with
# inbox_mark_read.sh's auto-info SSOT; only these six types may omit a
# commander envelope.  The second set is not information: these are the
# existing cases below that derive identity from a trusted task/report/event
# source.  Every other type, including future/unknown types, is an action
# request and must carry an explicit envelope.  Never recover a cmd_id from
# free-form prose.
inbox_karo_message_is_information_type() {
    case "$1" in
        low|info|gate_clear|heartbeat|status_update|retro_answer) return 0 ;;
        *) return 1 ;;
    esac
}

inbox_karo_message_has_dedicated_identity() {
    case "$1" in
        task_assigned|report_received|report_submitted|task_done|report_completed|report_done|report_ready|task_failed|review_report|accept_report|run_cmd_complete|report_review|report_review_result|report_revision)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

inbox_karo_message_has_separate_identity_lane() {
    # These lanes validate their own identity below (retro event_id or the
    # evidence-bound investigation fields).  They are not generic commander
    # exemptions and must not be added to the dedicated-generation set above.
    case "$1" in
        retro_result|infra_bug_suspected|infra_bug_report|infra_bug|investigation_result|bulletin_notify)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

inbox_karo_message_requires_identity() {
    inbox_karo_message_is_information_type "$1" && return 1
    inbox_karo_message_has_dedicated_identity "$1" && return 1
    inbox_karo_message_has_separate_identity_lane "$1" && return 1
    return 0
}

inbox_commander_directive_identity() {
    local content="$1"
    INBOX_DIRECTIVE_CONTENT="$content" python3 - <<'PY'
import os, re

content = os.environ.get("INBOX_DIRECTIVE_CONTENT", "")
values = {}
for token in content.split():
    if "=" not in token:
        continue
    key, value = token.split("=", 1)
    if key in {"task_id", "subject_task_id", "parent_cmd"}:
        values[key] = value

if values.get("task_id") != "commander_directive":
    raise SystemExit(1)
if not re.fullmatch(r"[A-Za-z0-9_.:-]+", values.get("subject_task_id", "")):
    raise SystemExit(1)
if not re.fullmatch(r"cmd_[A-Za-z0-9_.:-]+", values.get("parent_cmd", "")):
    raise SystemExit(1)
print("\n".join(values[key] for key in ("task_id", "subject_task_id", "parent_cmd")))
PY
}

inbox_validate_investigation_result() {
    local target="$1" from_agent="$2" content="$3"
    local field value

    [ "$TYPE" = "investigation_result" ] || return 0
    [ "$target" = "karo" ] && sender_is_ninja_from_fs "$from_agent" || {
        echo "BLOCK: investigation_result is ninja -> karo only" >&2
        exit 2
    }
    for field in task_id check_id occurred_at evidence impact; do
        value=$(printf '%s\n' "$content" | sed -n "s/.*${field}=\([^[:space:]]\+\).*/\1/p" | head -1)
        if [ -z "$value" ] || [ "$value" = "-" ]; then
            echo "BLOCK: investigation_result requires ${field}=<non-empty>; required: task_id/check_id/occurred_at/evidence/impact" >&2
            exit 2
        fi
    done
}

inbox_should_auto_read_completed_notification() {
    local target="$1"
    local type="$2"
    local cmd_id="$3"
    local from_agent="$4"

    [ "$target" = "karo" ] || return 1

    # cmd_id is the report YAML's own parent_cmd, resolved structurally by the
    # caller.  It is NOT grepped out of the message body: a report that merely
    # *mentions* an earlier cmd used to be read as that cmd's completion
    # notification and silently delivered read:true (2026-07-26, kotaro's
    # report mentioning cmd_4173).  Structure decides; prose never does.
    [ -n "$cmd_id" ] || return 1

    if [ "$type" = "report_review_result" ]; then
        inbox_gate_metrics_has_clear "$cmd_id" || return 1
    elif inbox_type_is_ninja_report_notification "$type"; then
        if ! inbox_gate_metrics_has_clear "$cmd_id" && ! inbox_review_log_has_lgtm "$cmd_id" "$from_agent"; then
            return 1
        fi
    else
        return 1
    fi

    INBOX_AUTO_READ_COMPLETED_CMD="$cmd_id"
    return 0
}

inbox_message_marked_read() {
    local inbox_file="$1"
    local msg_id="$2"
    [[ -f "$inbox_file" ]] || return 1

    awk -v msg_id="$msg_id" '
        BEGIN { in_msg = 0; found = 0; read_state = "false" }
        /^- / {
            if (found) exit(tolower(read_state) == "true" ? 0 : 1)
            in_msg = 1
            read_state = "false"
            next
        }
        in_msg && /^  id:[[:space:]]*/ {
            line = $0
            sub(/^  id:[[:space:]]*/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            gsub(/^["'\'']|["'\'']$/, "", line)
            if (line == msg_id) found = 1
            next
        }
        in_msg && found && /^  read:[[:space:]]*/ {
            read_state = $0
            sub(/^  read:[[:space:]]*/, "", read_state)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", read_state)
            exit(tolower(read_state) == "true" ? 0 : 1)
        }
        END {
            if (found) exit(tolower(read_state) == "true" ? 0 : 1)
            exit 1
        }
    ' "$inbox_file"
}

resolve_agent_pane_target() {
    local agent="$1"
    command -v tmux >/dev/null 2>&1 || return 1

    tmux list-panes -a -F '#{session_name}:#{window_name}.#{pane_index} #{@agent_id}' 2>/dev/null \
        | awk -v agent="$agent" '$2 == agent { print $1; exit }'
}

run_tmux_with_timeout() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 5 tmux "$@"
    else
        tmux "$@"
    fi
}

send_codex_task_nudge() {
    local target="$1"
    local pane_target="$2"
    local unread_count="$3"
    local msg_id="${4:-}"
    local task_file="$SCRIPT_DIR/queue/tasks/${target}.yaml"
    local task_id=""
    if [ -f "$task_file" ]; then
        task_id=$(inbox_yaml_field_get "$task_file" "task_id" "")
    fi
    local nudge="inbox${unread_count} — task_id=${task_id} タスクYAML: ${SCRIPT_DIR}/queue/tasks/${target}.yaml を読んで作業開始せよ"
    [ -n "$msg_id" ] && nudge+=" delivery_msg=${msg_id}"
    local started_us="${EPOCHREALTIME/./}" rc=0

    tmux set-buffer -b "nudge_${target}" "$nudge" 2>/dev/null || rc=1
    if [ "$rc" -eq 0 ]; then
        run_tmux_with_timeout paste-buffer -t "$pane_target" -b "nudge_${target}" -d >/dev/null 2>&1 || rc=1
    fi
    if [ "$rc" -eq 0 ]; then
        sleep 0.02
        run_tmux_with_timeout send-keys -t "$pane_target" Enter >/dev/null 2>&1 || rc=1
    fi
    iw_record_timing inbox_write_nudge "$started_us" \
        "$([ "$rc" -eq 0 ] && printf PASS || printf BLOCK)"
    return "$rc"
}

inbox_watcher_active_for_target() {
    local target="$1"
    command -v pgrep >/dev/null 2>&1 || return 1
    pgrep -af "[i]nbox_watcher\\.sh ${target} " >/dev/null 2>&1
}

rearm_codex_watcher_delivery() {
    local target="$1"
    local msg_id="$2"
    local pane_target="$3"
    local inbox_file="$SCRIPT_DIR/queue/inbox/${target}.yaml"
    local state_dir="${SHOGUN_STATE_DIR:-${IDLE_FLAG_DIR:-/tmp}}"
    local state_lock="$state_dir/inbox_watcher_state_${target}.lock"
    local pane_key="${pane_target//[:.]/_}"
    local send_lock="$state_dir/tmux_sendkeys_${pane_key}.lock"
    local token rc=0

    [ -n "$pane_target" ] || return 1
    mkdir -p "$state_dir"
    (
        flock -w 5 201 || exit 1
        flock -w 5 200 || exit 1
        inbox_message_marked_read "$inbox_file" "$msg_id" && exit 3
        rm -f "$state_dir/inbox_watcher_fingerprint_${target}" \
              "$state_dir/inbox_watcher_last_nudge_${target}"
        for token in "$state_dir"/inbox_watcher_sent_"${target}"_*; do
            [ -e "$token" ] || continue
            rm -f -- "$token"
        done
        # Content is unchanged.  The mtime transition wakes the watcher's
        # bounded fallback path after its sent-fingerprint lease is removed.
        touch "$inbox_file"
    ) 201>"$state_lock" 200>"$send_lock" || rc=$?
    return "$rc"
}

capture_codex_delivery_snapshot() {
    local target="$1"
    local pane_target="$2"
    local snapshot=""

    [ -n "$pane_target" ] || return 0
    echo "[inbox_write] post-nudge capture ${target} (-S -30):" >&2
    snapshot=$(tmux capture-pane -t "$pane_target" -p -S -30 2>/dev/null || true)
    if [ -n "$snapshot" ]; then
        printf '%s\n' "$snapshot" >&2
    else
        echo "[inbox_write] post-nudge capture empty for ${target}; fallback tail -30:" >&2
        tmux capture-pane -t "$pane_target" -p 2>/dev/null | tail -30 >&2 || echo "[inbox_write] post-nudge capture unavailable for ${target}" >&2
    fi
}

verify_codex_task_delivery() {
    local target="$1"
    local msg_id="$2"
    local inbox_file="$SCRIPT_DIR/queue/inbox/${target}.yaml"

    if inbox_message_marked_read "$inbox_file" "$msg_id"; then
        return 0
    fi

    # Task status is not delivery evidence: it may predate this message.
    # Only the unique message row becoming read proves post-send processing.
    target_is_ninja "$target" || return 1
    return 1
}

maybe_verify_codex_delivery() {
    local target="$1"
    local msg_id="$2"
    local type="$3"

    [ "$type" = "task_assigned" ] || return 2

    ensure_cli_lookup_loaded
    type cli_type >/dev/null 2>&1 || return 2
    [ "$(cli_type "$target")" = "codex" ] || return 2

    local inbox_file="$SCRIPT_DIR/queue/inbox/${target}.yaml"
    [ -f "$inbox_file" ] || return 2

    local retries="${INBOX_CODEX_NUDGE_RETRIES:-${INBOX_RENUDGE_MAX_ATTEMPTS:-5}}"
    local wait_sec="${INBOX_CODEX_VERIFY_WAIT_SEC:-1}"
    local attempt=0

    local pane_target
    pane_target=$(resolve_agent_pane_target "$target" || true)

    while [ "$attempt" -le "$retries" ]; do
        if verify_codex_task_delivery "$target" "$msg_id"; then
            echo "[inbox_write] codex delivery verified by inbox read transition for ${target} (msg_id=${msg_id})" >&2
            capture_codex_delivery_snapshot "$target" "$pane_target"
            return 0
        fi

        if [ "$attempt" -gt 0 ]; then
            local unread_count
            unread_count=$(inbox_unread_count "$inbox_file")
            if inbox_watcher_active_for_target "$target"; then
                local rearm_rc=0
                rearm_codex_watcher_delivery "$target" "$msg_id" "$pane_target" || rearm_rc=$?
                case "$rearm_rc" in
                    0) echo "[inbox_write] codex watcher dedup rearmed ${attempt}/${retries} for ${target} (msg_id=${msg_id})" >&2 ;;
                    3) echo "[inbox_write] codex watcher rearm skipped: target message already read for ${target} (msg_id=${msg_id})" >&2 ;;
                    *) echo "[inbox_write] codex watcher dedup rearm failed ${attempt}/${retries} for ${target} (msg_id=${msg_id})" >&2 ;;
                esac
            elif [ -n "$pane_target" ] && [ "$unread_count" -gt 0 ] 2>/dev/null; then
                if send_codex_task_nudge "$target" "$pane_target" "$unread_count" "$msg_id"; then
                    echo "[inbox_write] codex nudge retry ${attempt}/${retries} sent to ${target}" >&2
                    capture_codex_delivery_snapshot "$target" "$pane_target"
                else
                    echo "[inbox_write] codex nudge retry ${attempt}/${retries} failed for ${target}" >&2
                fi
            else
                echo "[inbox_write] codex nudge retry ${attempt}/${retries} skipped for ${target} (pane/unread unavailable)" >&2
            fi
        fi

        # Preserve the one-second retry deadline, but finish early only when
        # the exact durable message row becomes read.  Pane/task observations
        # are diagnostics and cannot satisfy delivery identity.
        local delivered=0 wait_tick
        if [ "$wait_sec" = "0" ]; then
            verify_codex_task_delivery "$target" "$msg_id" && delivered=1
        else
            for wait_tick in 1 2 3 4 5; do
                sleep 0.2
                if verify_codex_task_delivery "$target" "$msg_id"; then
                    delivered=1
                    break
                fi
            done
        fi

        if [ "$delivered" -eq 1 ]; then
            if [ "$attempt" -eq 0 ]; then
                echo "[inbox_write] codex delivery verified for ${target}" >&2
            else
                echo "[inbox_write] codex delivery verified after retry ${attempt}/${retries} for ${target}" >&2
            fi
            capture_codex_delivery_snapshot "$target" "$pane_target"
            return 0
        fi

        attempt=$((attempt + 1))
    done

    echo "[inbox_write] WARN: codex delivery remained unverified for ${target} after ${retries} retries" >&2
    return 1
}

close_async_verifier_inherited_fds() {
    local fd_path fd

    # A background child launched inside $(...) keeps the substitution pipe
    # open if any inherited descriptor still references it.  After routing the
    # worker's standard streams to its evidence log, close every other inherited
    # descriptor visible through procfs (including Bats/tmux caller internals).
    for fd_path in "/proc/${BASHPID:-$$}/fd/"*; do
        fd="${fd_path##*/}"
        case "$fd" in
            0|1|2|*[!0-9]*) continue ;;
        esac
        eval "exec ${fd}>&-" 2>/dev/null || true
    done
}

dispatch_codex_delivery_verification() {
    local target="$1"
    local msg_id="$2"
    local type="$3"
    local verify_status=0

    # Persistence above remains synchronous and flock-protected.  When the
    # event-driven watcher is active it owns pane wake-up, so keep delivery
    # verification but detach its bounded observation/retry wait from the
    # writer's command-substitution critical path.  Explicit opt-in preserves
    # the same fast path for deploy fixtures where no real watcher exists.
    if [ "$type" = "task_assigned" ] \
        && { [ "${INBOX_CODEX_DELIVERY_VERIFY_ASYNC:-0}" = "1" ] \
             || inbox_watcher_active_for_target "$target"; }; then
        local verify_log_dir="${INBOX_CODEX_VERIFY_LOG_DIR:-$SCRIPT_DIR/logs/inbox_codex_delivery_verify}"
        local verify_log="$verify_log_dir/${msg_id}.log"
        mkdir -p "$verify_log_dir"

        (
            close_async_verifier_inherited_fds
            local verify_started_us="${EPOCHREALTIME/./}"
            printf '[%s] ASYNC_VERIFY START target=%s msg_id=%s type=%s\n' \
                "$(date '+%Y-%m-%dT%H:%M:%S')" "$target" "$msg_id" "$type"
            if maybe_verify_codex_delivery "$target" "$msg_id" "$type"; then
                verify_status=0
            else
                verify_status=$?
            fi
            iw_record_timing inbox_write_delivery_verify "$verify_started_us" \
                "$([ "$verify_status" -eq 0 ] && printf PASS || printf BLOCK)"
            case "$verify_status" in
                0) printf '[%s] ASYNC_VERIFY SUCCESS target=%s msg_id=%s\n' \
                       "$(date '+%Y-%m-%dT%H:%M:%S')" "$target" "$msg_id" ;;
                2) printf '[%s] ASYNC_VERIFY SKIP target=%s msg_id=%s reason=not_codex\n' \
                       "$(date '+%Y-%m-%dT%H:%M:%S')" "$target" "$msg_id" ;;
                *) printf '[%s] ASYNC_VERIFY FAILURE target=%s msg_id=%s status=%s\n' \
                       "$(date '+%Y-%m-%dT%H:%M:%S')" "$target" "$msg_id" "$verify_status" ;;
            esac
        ) </dev/null >> "$verify_log" 2>&1 &

        echo "[inbox_write] codex delivery verification queued asynchronously for ${target} (msg_id=${msg_id}, log=${verify_log})" >&2
        return 0
    fi

    # Preserve synchronous behavior for every non-opted-in caller/message.
    local verify_started_us="${EPOCHREALTIME/./}"
    if maybe_verify_codex_delivery "$target" "$msg_id" "$type"; then
        iw_record_timing inbox_write_delivery_verify "$verify_started_us" PASS
        return 0
    fi
    verify_status=$?
    iw_record_timing inbox_write_delivery_verify "$verify_started_us" \
        "$([ "$verify_status" -eq 2 ] && printf PASS || printf BLOCK)"
    [ "$verify_status" -eq 2 ] && return 0
    # Delivery verification remains non-fatal after durable inbox persistence.
    return 0
}

list_active_ninjas() {
    local ninja=""
    local task_file=""
    local task_status=""

    ensure_agent_config_loaded
    for ninja in $NINJA_NAMES; do
        task_file="$SCRIPT_DIR/queue/tasks/${ninja}.yaml"
        [ -f "$task_file" ] || continue

        task_status=$(inbox_yaml_field_get "$task_file" "status" "")
        case "$task_status" in
            assigned|acknowledged|in_progress)
                printf '%s\n' "$ninja"
                ;;
        esac
    done
}

forward_gunshi_review_result_to_active_ninjas() {
    local review_content="$1"
    local ninja=""
    local forward_message=""

    # review_contentからcmd_idを抽出(先頭のcmd_XXXX or cmd_karo_XXX)
    local review_cmd_id=""
    review_cmd_id=$(printf '%s' "$review_content" | grep -oP '^cmd_[a-zA-Z0-9_]+' | head -1)

    # A review without a leading canonical cmd id cannot be attributed safely.
    # Fan-out in that state contaminates every active ninja with unrelated scope.
    [ -n "$review_cmd_id" ] || return 0

    while IFS= read -r ninja; do
        [ -n "$ninja" ] || continue

        # cmd_idフィルタ: 忍者のtask YAMLのparent_cmdと一致する場合のみ転送
        local ninja_parent_cmd=""
        local ninja_task_id=""
        local review_body=""
        local task_file="$SCRIPT_DIR/queue/tasks/${ninja}.yaml"
        ninja_parent_cmd=$(inbox_yaml_field_get "$task_file" "parent_cmd" "")
        if [ "$ninja_parent_cmd" != "$review_cmd_id" ]; then
            continue  # この忍者の担当cmdではない→スキップ
        fi

        ninja_task_id=$(inbox_yaml_field_get "$task_file" "task_id" "")
        # The review_result body carries Karo's commander envelope for its
        # own mailbox. Remove those two tokens before replacing them with the
        # recipient ninja's identity; task_supplement requires one unambiguous
        # pair and must not reject its own generated fan-out.
        review_body=$(printf '%s' "$review_content" | sed -E 's/(^|[[:space:]])task_id=[^[:space:]]+/\1/g; s/(^|[[:space:]])parent_cmd=[^[:space:]]+/\1/g')
        forward_message="task_id=${ninja_task_id} parent_cmd=${ninja_parent_cmd} 軍師レビュー補足: ${review_body}"
        if ! INBOX_WRITE_ROOT_OVERRIDE="$SCRIPT_DIR" \
            INBOX_WRITE_TEST="${INBOX_WRITE_TEST:-}" \
            bash "$SELF_SCRIPT_PATH" \
                "$ninja" "$forward_message" task_supplement gunshi; then
            echo "[inbox_write] WARN: gunshi review forward failed for ${ninja}" >&2
        fi
    done < <(list_active_ninjas)
}

record_inbox_event_to_memory_db() {
    local live_insert_script="$SCRIPT_DIR/scripts/memory_db_live_insert_async.py"
    local memory_event_agent="$FROM"
    local memory_event_content="$CONTENT"
    if [ ! -f "$live_insert_script" ]; then
        live_insert_script="$SCRIPT_DIR/scripts/memory_db_live_insert.py"
    fi

    [ -f "$live_insert_script" ] || return 0

    # A Codex deploy nudge contains a receiver-only task-safety rule.  It is
    # not a karo-authored piece of knowledge: storing it with agent=karo
    # makes the sender recall its own instruction on a later preflight and
    # re-injects the rule (T122).  Keep the durable inbox row's `from` field
    # untouched; only the memory event actor is rebound to the ninja that
    # received the rule.  Ordinary communication retains its sender identity.
    if [ "$TYPE" = "task_assigned" ] && deploy_nudge_target_is_ninja "$TARGET" \
        && printf '%s' "$CONTENT" | grep -qF 'inboxはread:falseかつ現task_id一致'; then
        memory_event_agent="$TARGET"
        # Preserve the sender in detail while rebinding only the event actor.
        memory_event_content="$CONTENT
from: $FROM"
    fi

    python3 "$live_insert_script" inbox \
        --message-id "$MSG_ID" \
        --ts "$TIMESTAMP" \
        --target-agent "$TARGET" \
        --from-agent "$memory_event_agent" \
        --content "$memory_event_content" \
        --message-type "$TYPE" \
        --action "$ACTION" \
        --source-file "$INBOX" \
        >/dev/null
}

inbox_append_message_fast_locked() {
    local inbox_file="$1"
    local message_block="$2"

    if inbox_is_empty_file "$inbox_file"; then
        printf 'messages:\n%s' "$message_block" > "$inbox_file"
        return 0
    fi

    printf '%s' "$message_block" >> "$inbox_file"
}

inbox_compact_records_locked() {
    local inbox_file="$1"
    local tmp_file
    # The caller already holds the per-inbox exclusive flock, so a
    # process-local name is collision-free for this mailbox. Avoid spawning
    # mktemp on the overflow hot path while retaining same-directory atomic mv.
    printf -v tmp_file '%s.%s.%04x%04x.tmp' "$inbox_file" "$$" "$RANDOM" "$RANDOM"

    # Keep every unread record and only the newest 30 read records.  Perform
    # selection and emission in one awk process: the former awk -> bash arrays
    # -> per-record printf path amplified DrvFs I/O on every overflow write.
    if ! awk '
        function save_record() {
            if (!started) return
            records[++count] = record
            reads[count] = read_state
        }
        BEGIN { started = 0; record = ""; read_state = "false" }
        /^messages:[[:space:]]*(\[\])?[[:space:]]*$/ { next }
        /^- / {
            save_record()
            record = $0 "\n"
            read_state = "false"
            started = 1
            next
        }
        started {
            record = record $0 "\n"
            if ($0 ~ /^  read:[[:space:]]*/) {
                read_state = $0
                sub(/^  read:[[:space:]]*/, "", read_state)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", read_state)
            }
        }
        END {
            save_record()
            read_count = 0
            for (i = 1; i <= count; i++) {
                if (tolower(reads[i]) == "true") read_count++
            }
            first_read_to_keep = read_count > 30 ? read_count - 29 : 1
            print "messages:"
            for (i = 1; i <= count; i++) {
                if (tolower(reads[i]) != "true") printf "%s", records[i]
            }
            seen_read = 0
            for (i = 1; i <= count; i++) {
                if (tolower(reads[i]) == "true") {
                    seen_read++
                    if (seen_read >= first_read_to_keep) printf "%s", records[i]
                }
            }
        }
    ' "$inbox_file" > "$tmp_file"; then
        rm -f "$tmp_file"
        return 1
    fi

    inbox_replace_file_with_retry "$tmp_file" "$inbox_file"
}

inbox_append_message_locked() {
    local inbox_file="$1"
    local message_block="$2"
    local existing_count=0

    if inbox_is_empty_file "$inbox_file"; then
        printf 'messages:\n%s' "$message_block" > "$inbox_file"
        return 0
    fi

    # cmd_inbox_write_speed: bash while readループ→grep -c(C実装, WSL2高速)
    existing_count=$(grep -c '^- ' "$inbox_file" 2>/dev/null || echo 0)
    if (( existing_count < 50 )); then
        printf '%s' "$message_block" >> "$inbox_file"
        return 0
    fi

    printf '%s' "$message_block" >> "$inbox_file"
    inbox_compact_records_locked "$inbox_file"
}

# Return success when the same sender/content pair is already pending.  This is
# deliberately evaluated while holding the inbox flock: concurrent writers must
# converge on one durable entry instead of both passing a pre-lock check.
inbox_pending_duplicate_locked() {
    local inbox_file="$1"
    local sender="$2"
    local content="$3"
    [ -s "$inbox_file" ] || return 1
    INBOX_DEDUPE_FILE="$inbox_file" INBOX_DEDUPE_FROM="$sender" \
        INBOX_DEDUPE_CONTENT="$content" python3 - <<'PY'
import os, sys, yaml
try:
    data = yaml.safe_load(open(os.environ["INBOX_DEDUPE_FILE"], encoding="utf-8")) or {}
except (OSError, yaml.YAMLError):
    sys.exit(1)
for message in data.get("messages") or []:
    if not isinstance(message, dict) or message.get("read") is not False:
        continue
    if str(message.get("from", "")) == os.environ["INBOX_DEDUPE_FROM"] and str(message.get("content", "")) == os.environ["INBOX_DEDUPE_CONTENT"]:
        sys.exit(0)
sys.exit(1)
PY
}

# Review-pending nudges are actionable work.  An unread matching event is an
# in-flight delivery and is suppressed; a read matching event was consumed and
# must be eligible for a lost-wakeup retry.
inbox_review_pending_duplicate_locked() {
    local inbox_file="$1" sender="$2" task_id="$3" subject_task_id="$4" parent_cmd="$5" fingerprint="$6" state="$7"
    [ -s "$inbox_file" ] || return 1
    INBOX_NUDGE_FILE="$inbox_file" INBOX_NUDGE_FROM="$sender" \
    INBOX_NUDGE_TASK_ID="$task_id" INBOX_NUDGE_SUBJECT_TASK_ID="$subject_task_id" \
    INBOX_NUDGE_PARENT_CMD="$parent_cmd" INBOX_NUDGE_FINGERPRINT="$fingerprint" \
    INBOX_NUDGE_STATE="$state" python3 - <<'PY'
import os, sys, yaml
try:
    data = yaml.safe_load(open(os.environ["INBOX_NUDGE_FILE"], encoding="utf-8")) or {}
except (OSError, yaml.YAMLError):
    sys.exit(1)
wanted = (
    os.environ["INBOX_NUDGE_FROM"], os.environ["INBOX_NUDGE_TASK_ID"],
    os.environ["INBOX_NUDGE_SUBJECT_TASK_ID"],
    os.environ["INBOX_NUDGE_PARENT_CMD"], os.environ["INBOX_NUDGE_FINGERPRINT"],
    os.environ["INBOX_NUDGE_STATE"],
)
for message in data.get("messages") or []:
    if not isinstance(message, dict) or message.get("read") is not False:
        continue
    actual = (
        str(message.get("from") or ""), str(message.get("task_id") or ""),
        str(message.get("subject_task_id") or ""),
        str(message.get("parent_cmd") or ""), str(message.get("report_fingerprint") or ""),
        str(message.get("review_pending_state") or ""),
    )
    if actual == wanted:
        sys.exit(0)
sys.exit(1)
PY
}

# Print the existing message id when a canonical report lifecycle event was
# already persisted. Unlike the legacy pending content dedupe this spans read
# state and ignores retry text/timestamps. Caller holds the inbox flock, making
# check+append one transaction for concurrent writers.
inbox_report_event_duplicate_locked() {
    local inbox_file="$1" target="$2" event_type="$3" sender="$4" report_id="$5" identity_version="$6" report_fingerprint="$7" revision_fingerprint="${8:-}"
    [ -s "$inbox_file" ] || return 1
    INBOX_EVENT_FILE="$inbox_file" INBOX_EVENT_TARGET="$target" \
    INBOX_EVENT_TYPE="$event_type" INBOX_EVENT_FROM="$sender" \
    INBOX_EVENT_REPORT_ID="$report_id" INBOX_EVENT_VERSION="$identity_version" \
    INBOX_EVENT_FINGERPRINT="$report_fingerprint" INBOX_EVENT_REVISION_FINGERPRINT="$revision_fingerprint" python3 - <<'PY'
import os, sys, yaml
try:
    data = yaml.safe_load(open(os.environ["INBOX_EVENT_FILE"], encoding="utf-8")) or {}
except (OSError, yaml.YAMLError):
    sys.exit(1)
wanted = (
    os.environ["INBOX_EVENT_TYPE"], os.environ["INBOX_EVENT_FROM"],
    os.environ["INBOX_EVENT_REPORT_ID"], os.environ["INBOX_EVENT_VERSION"],
    os.environ["INBOX_EVENT_FINGERPRINT"],
    os.environ["INBOX_EVENT_REVISION_FINGERPRINT"],
)
for message in data.get("messages") or []:
    if not isinstance(message, dict):
        continue
    # Review requests are actionable work, not immutable completion facts.
    # Once a matching request was consumed, an explicit retry must wake the
    # reviewer again; suppress only while the matching request is still unread.
    # Terminal report events keep their existing read-state-spanning exactly-once
    # contract below.
    if wanted[0] in {"report_review", "report_revision"} and message.get("read") is True:
        continue
    actual = (
        str(message.get("type", "")), str(message.get("from", "")),
        str(message.get("report_id", "")), str(message.get("report_identity_version", "")),
        str(message.get("report_fingerprint", "")),
        str(message.get("revision_request_fingerprint", "")),
    )
    if actual == wanted:
        print(str(message.get("id", "")))
        sys.exit(0)
sys.exit(1)
PY
}

inbox_extract_report_paths() {
    local report_path="$1"
    [[ -f "$report_path" ]] || return 0

    awk '
        BEGIN { in_files = 0 }
        /^files_modified:[[:space:]]*$/ { in_files = 1; next }
        in_files {
            if ($0 ~ /^[[:space:]]*- path:[[:space:]]*/) {
                line = $0
                sub(/^[[:space:]]*- path:[[:space:]]*/, "", line)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
                print line
                next
            }
            if ($0 ~ /^[[:space:]]*path:[[:space:]]*/) {
                line = $0
                sub(/^[[:space:]]*path:[[:space:]]*/, "", line)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
                print line
                next
            }
            if ($0 ~ /^[[:space:]]*- [^[:space:]][^:]*$/) {
                line = $0
                sub(/^[[:space:]]*- /, "", line)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
                print line
                next
            }
            if ($0 ~ /^[^[:space:]-][^:]*:/) {
                exit
            }
        }
    ' "$report_path" | while IFS= read -r _path; do
        inbox_yaml_strip_quotes "$_path"
        printf '\n'
    done
}

inbox_extract_task_paths() {
    local task_path="$1"
    local raw_values="" raw_entry=""
    [[ -f "$task_path" ]] || return 0

    for _field_name in target_path files; do
        raw_values=$(inbox_yaml_field_get "$task_path" "$_field_name" "")
        [[ -z "${raw_values//[[:space:]]/}" ]] && continue
        IFS=',' read -ra _value_list <<< "$raw_values"
        for raw_entry in "${_value_list[@]}"; do
            raw_entry="$(inbox_yaml_strip_quotes "$raw_entry")"
            [[ -n "${raw_entry//[[:space:]]/}" ]] && printf '%s\n' "$raw_entry"
        done
    done
}

task_has_related_lessons() {
    local task_path="$1"
    awk '
        BEGIN { in_block = 0 }
        /^  related_lessons:[[:space:]]*(\[\])?[[:space:]]*$/ { in_block = 1; next }
        in_block {
            if ($0 ~ /^  - id:[[:space:]]*/) {
                found = 1
                exit
            }
            if ($0 ~ /^  [^[:space:]-][^:]*:/ || $0 !~ /^  /) {
                exit
            }
        }
        END { exit(found ? 0 : 1) }
    ' "$task_path"
}

extract_universal_lessons() {
    local lessons_file="$1"
    [[ -f "$lessons_file" ]] || return 0

    awk '
        function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
        function unquote(s) {
            s = trim(s)
            if (s ~ /^'\''.*'\''$/) {
                sub(/^'\''/, "", s)
                sub(/'\''$/, "", s)
                gsub(/'\'''\''/, "'\''", s)
            } else if (s ~ /^".*"$/) {
                sub(/^"/, "", s)
                sub(/"$/, "", s)
            }
            return s
        }
        function flush() {
            if (lesson_id != "" && universal == 1 && retired == 0 && status != "deprecated") {
                out_summary = summary
                out_detail = detail
                if (out_summary == "") out_summary = title
                if (out_detail == "") out_detail = content
                if (out_detail == "") out_detail = out_summary
                print lesson_id "\t" out_summary "\t" out_detail
            }
            lesson_id = title = summary = detail = content = status = ""
            universal = retired = in_tags = 0
        }
        /^lessons:[[:space:]]*$/ { in_lessons = 1; next }
        !in_lessons { next }
        /^- id:[[:space:]]*/ {
            flush()
            line = $0
            sub(/^- id:[[:space:]]*/, "", line)
            lesson_id = unquote(line)
            next
        }
        lesson_id == "" { next }
        /^  title:[[:space:]]*/ {
            line = $0
            sub(/^  title:[[:space:]]*/, "", line)
            title = unquote(line)
            next
        }
        /^  summary:[[:space:]]*/ {
            line = $0
            sub(/^  summary:[[:space:]]*/, "", line)
            summary = unquote(line)
            next
        }
        /^  detail:[[:space:]]*/ {
            line = $0
            sub(/^  detail:[[:space:]]*/, "", line)
            detail = unquote(line)
            next
        }
        /^  content:[[:space:]]*/ {
            line = $0
            sub(/^  content:[[:space:]]*/, "", line)
            content = unquote(line)
            next
        }
        /^  status:[[:space:]]*/ {
            line = $0
            sub(/^  status:[[:space:]]*/, "", line)
            status = tolower(unquote(line))
            next
        }
        /^  retired:[[:space:]]*true([[:space:]]|$)/ {
            retired = 1
            next
        }
        /^  tags:[[:space:]]*$/ {
            in_tags = 1
            next
        }
        in_tags && /^  - / {
            line = $0
            sub(/^  - /, "", line)
            if (tolower(unquote(line)) == "universal") {
                universal = 1
            }
            next
        }
        in_tags && !/^  - / { in_tags = 0 }
        !/^  / {
            flush()
            in_lessons = 0
        }
        END { flush() }
    ' "$lessons_file"
}

inject_universal_lessons_if_missing() {
    local task_path="$1"
    local project_id="$2"
    local stripped_file="" tmp_file="" lessons_file=""
    local -a lesson_sources=() selected_lessons=()
    local -A seen_lessons=()
    local lesson_id="" lesson_summary="" lesson_detail=""

    task_has_related_lessons "$task_path" && {
        echo "OK: related_lessons already injected"
        return 0
    }

    lesson_sources+=("$SCRIPT_DIR/projects/${project_id}/lessons_archive.yaml")
    lesson_sources+=("$SCRIPT_DIR/projects/${project_id}/lessons.yaml")
    if [[ "$project_id" != "infra" ]]; then
        lesson_sources+=("$SCRIPT_DIR/projects/infra/lessons_archive.yaml")
        lesson_sources+=("$SCRIPT_DIR/projects/infra/lessons.yaml")
    fi

    for lessons_file in "${lesson_sources[@]}"; do
        [[ -f "$lessons_file" ]] || continue
        while IFS=$'\t' read -r lesson_id lesson_summary lesson_detail; do
            [[ -z "$lesson_id" || -n "${seen_lessons[$lesson_id]:-}" ]] && continue
            seen_lessons["$lesson_id"]=1
            selected_lessons+=("$lesson_id"$'\t'"$lesson_summary"$'\t'"$lesson_detail")
            (( ${#selected_lessons[@]} >= 10 )) && break 2
        done < <(extract_universal_lessons "$lessons_file")
    done

    if (( ${#selected_lessons[@]} == 0 )); then
        echo "WARN: no universal lessons found"
        return 0
    fi

    stripped_file=$(mktemp "${task_path}.strip.XXXXXX")
    awk '
        BEGIN { skip = 0 }
        /^  related_lessons:[[:space:]]*$/ {
            skip = 1
            next
        }
        skip {
            if ($0 ~ /^  [^[:space:]-][^:]*:/ || $0 !~ /^  /) {
                skip = 0
            } else {
                next
            }
        }
        { print }
    ' "$task_path" > "$stripped_file"

    tmp_file=$(mktemp "${task_path}.XXXXXX.tmp")
    cat "$stripped_file" > "$tmp_file"
    rm -f "$stripped_file"
    printf '  related_lessons:\n' >> "$tmp_file"
    local lesson_entry
    for lesson_entry in "${selected_lessons[@]}"; do
        IFS=$'\t' read -r lesson_id lesson_summary lesson_detail <<< "$lesson_entry"
        {
            printf "  - id: '%s'\n" "${lesson_id//\'/\'\'}"
            printf "    summary: '%s'\n" "${lesson_summary//\'/\'\'}"
            printf "    detail: '%s'\n" "${lesson_detail//\'/\'\'}"
        } >> "$tmp_file"
    done
    mv "$tmp_file" "$task_path"
    echo "INJECTED: ${#selected_lessons[@]} universal lessons (safety net)"
}

inbox_is_review_request_type() {
    case "$1" in
        review_draft|report_review|verify_request)
            return 0
            ;;
    esac
    return 1
}

inbox_truncate_lines() {
    local max_lines="${1:-5}"
    local max_chars="${2:-1200}"
    awk -v max_lines="$max_lines" -v max_chars="$max_chars" '
        BEGIN { chars = 0 }
        NF {
            line = $0
            if (length(line) > 220) line = substr(line, 1, 217) "..."
            next_chars = chars + length(line) + 1
            if (NR > max_lines || next_chars > max_chars) exit
            print line
            chars = next_chars
        }
    '
}

inbox_utf8_truncate() {
    local max_chars="${1:-900}"
    python3 -c 'import sys; limit=int(sys.argv[1]); raw=sys.stdin.buffer.read(); text=raw.decode("utf-8", "replace"); sys.stdout.write(text[:limit])' "$max_chars" 2>/dev/null || true
}

inbox_extract_report_summary_for_review_context() {
    local report_path="$1"
    [ -f "$report_path" ] || return 0

    python3 - "$report_path" <<'PY' 2>/dev/null || true
import sys
import yaml

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

parts = []
parent = str(data.get("parent_cmd") or "").strip()
if parent:
    parts.append(parent)
result = data.get("result") if isinstance(data.get("result"), dict) else {}
summary = str(result.get("summary") or "").strip()
details = str(result.get("details") or "").strip()
if summary:
    parts.append(summary)
elif details:
    parts.append(details[:240])
for item in data.get("files_modified") or []:
    if isinstance(item, dict) and item.get("path"):
        parts.append(str(item["path"]))
if parts:
    print(" ".join(parts)[:600])
PY
}

inbox_extract_cmd_summary_for_review_context() {
    local cmd_id="$1"
    local cmd_file="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
    [ -n "$cmd_id" ] || return 0
    [ -f "$cmd_file" ] || return 0

    python3 - "$cmd_file" "$cmd_id" <<'PY' 2>/dev/null || true
import sys
import yaml

path, cmd_id = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}
cmd = (data.get("commands") or {}).get(cmd_id) or {}
if not isinstance(cmd, dict):
    raise SystemExit(0)
parts = [cmd_id]
for key in ("purpose", "title", "command", "project"):
    value = cmd.get(key)
    if value:
        parts.append(str(value))
acs = cmd.get("acceptance_criteria") or []
if isinstance(acs, list):
    for ac in acs[:3]:
        parts.append(str(ac))
print(" ".join(parts)[:700])
PY
}

inbox_build_review_context_query() {
    local content="$1"
    local cmd_id="" report_path="" report_query="" cmd_query=""

    cmd_id=$(printf '%s' "$content" | grep -oE 'cmd_[A-Za-z0-9_]+' | head -1 || true)
    report_path=$(inbox_extract_report_path_from_content "$content")
    if [ -n "$report_path" ]; then
        report_query=$(inbox_extract_report_summary_for_review_context "$report_path")
        if [ -z "$cmd_id" ] && [ -f "$report_path" ]; then
            cmd_id=$(inbox_extract_parent_cmd_from_report "$report_path")
        fi
    fi
    cmd_query=$(inbox_extract_cmd_summary_for_review_context "$cmd_id")

    printf '%s\n%s\n%s\n' "$cmd_query" "$report_query" "$content" \
        | tr '\n' ' ' \
        | sed 's/[[:space:]][[:space:]]*/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//' \
        | inbox_utf8_truncate 900
}

inbox_collect_review_memory_context() {
    local query="$1"
    local timeout_sec="${INBOX_REVIEW_CONTEXT_TIMEOUT_SEC:-5}"
    local memory_output="" semantic_output=""
    local context_tmp_dir="" memory_tmp="" semantic_tmp=""
    local memory_pid="" semantic_pid=""

    [ -n "${query//[[:space:]]/}" ] || return 0
    if [ ! -x "$SCRIPT_DIR/scripts/memory_db_query.sh" ] \
        && [ ! -x "$SCRIPT_DIR/scripts/semantic_search.sh" ]; then
        return 0
    fi

    context_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/inbox_review_context.XXXXXX")
    memory_tmp="$context_tmp_dir/memory"
    semantic_tmp="$context_tmp_dir/semantic"

    if [ -x "$SCRIPT_DIR/scripts/memory_db_query.sh" ]; then
        (
            MEMORY_DB_QUERY_LIMIT="${INBOX_REVIEW_CONTEXT_MEMORY_LIMIT:-3}" \
                timeout "$timeout_sec" bash "$SCRIPT_DIR/scripts/memory_db_query.sh" --search "$query" 2>/dev/null \
                | inbox_truncate_lines 4 1000
        ) > "$memory_tmp" || true &
        memory_pid=$!
    fi

    if [ -x "$SCRIPT_DIR/scripts/semantic_search.sh" ]; then
        (
            # memory_db_query.sh above already owns the complete Memory layer.
            # Let semantic_search inspect only the semantic index here; its
            # fallback would otherwise repeat the same large SQLite FTS/cache
            # freshness work in parallel without adding a distinct result.
            SEMANTIC_DISABLE_LLM=1 \
            SEMANTIC_DISABLE_CAUSAL=1 \
            SEMANTIC_DISABLE_MEMORY_DB=1 \
                timeout "$timeout_sec" bash "$SCRIPT_DIR/scripts/semantic_search.sh" "$query" 2>/dev/null \
                | inbox_truncate_lines 5 1200
        ) > "$semantic_tmp" || true &
        semantic_pid=$!
    fi

    [ -z "$memory_pid" ] || wait "$memory_pid" || true
    [ -z "$semantic_pid" ] || wait "$semantic_pid" || true
    [ ! -f "$memory_tmp" ] || IFS= read -r -d '' memory_output < "$memory_tmp" || true
    [ ! -f "$semantic_tmp" ] || IFS= read -r -d '' semantic_output < "$semantic_tmp" || true
    rm -f "$memory_tmp" "$semantic_tmp"
    rmdir "$context_tmp_dir" 2>/dev/null || true

    if [ -z "$memory_output" ] && [ -z "$semantic_output" ]; then
        return 0
    fi

    {
        printf '\n\n[review_context_push]\n'
        printf 'query: %s\n' "$query"
        if [ -n "$memory_output" ]; then
            printf 'memory_db:\n%s\n' "$memory_output"
        fi
        if [ -n "$semantic_output" ]; then
            printf 'semantic_search:\n%s\n' "$semantic_output"
        fi
        printf '[/review_context_push]'
    }
}

inbox_maybe_attach_review_context() {
    local query="" context_block=""

    inbox_is_review_request_type "$TYPE" || return 0
    [ "${INBOX_REVIEW_CONTEXT_DISABLE:-0}" = "1" ] && return 0
    [[ "$CONTENT" == *"[review_context_push]"* ]] && return 0

    query=$(inbox_build_review_context_query "$CONTENT")
    context_block=$(inbox_collect_review_memory_context "$query")
    [ -n "$context_block" ] || return 0

    CONTENT="${CONTENT}${context_block}"
}

# A checkpoint review request is not deliverable until its artifact exists.
# Persist the intent first; ninja_monitor promotes it to ready and replays the
# exact request with CHECKPOINT_MANIFEST_READY_DELIVERY=1.
checkpoint_manifest_defer_unready_review() {
    [ "$TYPE" = "verify_request" ] || return 1
    [ "${CHECKPOINT_MANIFEST_READY_DELIVERY:-0}" != "1" ] || return 1

    local artifact_rel artifact_abs task_id worker reviewer manifest_dir key manifest tmp now content_b64
    artifact_rel=$(printf '%s\n' "$CONTENT" | grep -oE '(docs|queue/reports)/[A-Za-z0-9_./-]+' | head -1 || true)
    [ -n "$artifact_rel" ] || return 1
    artifact_abs="$SCRIPT_DIR/$artifact_rel"
    [ ! -f "$artifact_abs" ] || return 1

    task_id=$(printf '%s\n' "$CONTENT" | grep -oE 'cmd_[A-Za-z0-9_]+' | head -1 || true)
    [ -n "$task_id" ] || task_id="unknown"
    worker=$(printf '%s\n' "$CONTENT" | grep -oE 'worker=[A-Za-z0-9_-]+' | head -1 | cut -d= -f2- || true)
    if [ -z "$worker" ] && [[ "$artifact_rel" == queue/reports/*_report_* ]]; then
        worker="${artifact_rel##*/}"; worker="${worker%%_report_*}"
    fi
    [ -n "$worker" ] || worker="$FROM"
    reviewer="$TARGET"
    manifest_dir="$SCRIPT_DIR/queue/checkpoint_manifests"
    mkdir -p "$manifest_dir"
    key=$(printf '%s\0%s\0%s\0%s' "$task_id" "$worker" "$reviewer" "$artifact_rel" | sha256sum | cut -d' ' -f1)
    manifest="$manifest_dir/$key.manifest"
    [ -f "$manifest" ] && { printf 'CHECKPOINT_DEFERRED existing=%s\n' "$manifest"; return 0; }
    tmp="$manifest.tmp.$$"; now=$EPOCHSECONDS
    content_b64=$(printf '%s' "$CONTENT" | base64 -w0)
    {
        printf 'state=requested\n'
        printf 'task_id=%s\nworker=%s\nreviewer=%s\n' "$task_id" "$worker" "$reviewer"
        printf 'artifact_path=%s\nartifact_hash=-\n' "$artifact_rel"
        printf 'requested_at_epoch=%s\nready_at_epoch=0\nreviewed_at_epoch=0\n' "$now"
        printf 'delivery_count=0\nlast_wake_epoch=0\n'
        printf 'request_type=%s\nrequest_from=%s\nrequest_action=%s\n' "$TYPE" "$FROM" "$ACTION"
        printf 'content_b64=%s\n' "$content_b64"
        printf 'fingerprint=%s\n' "$key"
    } > "$tmp"
    printf 'state=awaiting_artifact\n' > "$tmp.state"
    tail -n +2 "$tmp" >> "$tmp.state"
    mv -n "$tmp.state" "$manifest" 2>/dev/null || true
    rm -f "$tmp" "$tmp.state"
    printf 'CHECKPOINT_DEFERRED manifest=%s state=awaiting_artifact\n' "$manifest"
    return 0
}

TARGET="$1"
CONTENT="$2"
TYPE="${3:-wake_up}"
FROM="${4:-unknown}"

# 委任初回検分marker(殿裁定2026-07-28 02:28「意思依存は洗脳だ」):
# 将軍→家老の委任系送信を記録し、post-shogun-inbox-check.shが家老paneを
# 自動captureして将軍ターンへ注入する(将軍の意志に依存しない初回検分)
if [ "$FROM" = "shogun" ] && [ "$TARGET" = "karo" ] && [ "$TYPE" = "task_assigned" ]; then
    date +%s > /tmp/shogun_delegation_pending 2>/dev/null || true
fi

# 下知本文の path 実在 WARN(型4弾-1「書いたら grep」を下知本文へ拡張。2026-08-28 T109: 将軍が
# scripts/first_setup.sh と書いたが実物は ./first_setup.sh で才蔵が前提差異停止=1往復の損失)。
# 将軍発の指示系のみ、repo 相対の path 風トークン(scripts/… tests/… context/… docs/… config/… skills/…)を
# 抽出し、存在しないものを stderr に列挙する。BLOCK しない(表示型 gate を積まない 07-21 裁定)。
if [ "$FROM" = "shogun" ] && [ "$TYPE" = "task_assigned" ]; then
    _missing_paths="$(printf '%s' "$CONTENT" | grep -oE '(scripts|tests|context|docs|config|skills|instructions|queue)/[A-Za-z0-9_./-]+' \
        | sed 's/[.,、。)]*$//' | sort -u | while IFS= read -r _p; do
            [ -e "$_p" ] || printf '%s ' "$_p"
        done)"
    if [ -n "$_missing_paths" ]; then
        printf 'WARN: 下知本文に実在しない path: %s (型4弾-1: 書いたら grep。送信は続行)\n' "$_missing_paths" >&2
    fi
fi

# 高速回転ガード(殿下知2026-08-15 18:58-19:00「冗長なテストは高速回転への重大なルール違反。
# 最小限にシンプルで最高速度のtry&errorを強制しろ」「将軍が真因だった。将軍にもルールを強制せよ」):
# 将軍→家老の委任本文(および本文中で参照する将軍scratchpadの詳細ファイル)に、途中laneへ
# 儀式(1体×1層の直列配備・層ごとのGATE/報告YAML/レビュー・新規テスト/contract test/fixture作成)を
# 課す文言、または「一括実装」(小さく一歩ずつ=殿裁定2026-08-14 16:53 に反する)があればBLOCK。
# 小さく1層ずつ配備するのは正しい(1体×1層はBLOCK対象ではない)。削るのは儀式だけ。
# さらに将軍→家老のtask_assignedには三層記憶の引用[MEM: ...]を必須とする(殿下知2026-08-15 19:05
# 「すべての作業の前に三層記憶を確認する。人間が無意識に0秒でやることをやるだけだ」)。
# 発端: 2026-08-15 L1分割で将軍が『1体×1層で順に』を設計書に書き、層ごとの配備→報告→レビュー→
# GATEで1h38mかけて2/6しか進まなかった(殿見込み=20分+full)。
if [ "$FROM" = "shogun" ] && [ "$TARGET" = "karo" ] && [ "${INBOX_WRITE_SKIP_SPEED_GUARD:-0}" != "1" ]; then
    _speed_text="$CONTENT"
    while IFS= read -r _ref; do
        [ -f "$_ref" ] && _speed_text="$_speed_text
$(cat "$_ref" 2>/dev/null)"
    done < <(printf '%s
' "$CONTENT" | grep -oE '/tmp/claude-1000/[^ ]*scratchpad/[^ ]+' | tr -d '"' )
    _speed_hit=$(printf '%s\n' "$_speed_text" | python3 -c '
import re,sys
pat=re.compile(r"(一括(実装|で実装|配備)(させ|せよ|する|しろ)|まとめて実装|層ごと(の|に)(GATE|報告YAML|レビュー)(を|必須|せよ)|contract test(を|必須|作成)|新規テスト(を|作成)|fixture(を|作成)|pytest全量|テストを作成)")
neg=re.compile(r"禁止|廃止|不要|課すな|するな|使うな|なし|撤回|違反|削")
hits=[]
for n,l in enumerate(sys.stdin,1):
    for sent in re.split(r"[。\n]",l):
        s2=re.sub(r"[（(][^）)]*[）)]","",sent)
        if pat.search(s2) and not neg.search(s2):
            hits.append(f"{n}: {sent.strip()[:160]}"); break
print("\n".join(hits[:3]))
')
    if [ -n "$_speed_hit" ]; then
        echo "BLOCK(speed_guard): 将軍→家老の委任に『一括実装』または途中laneの儀式(層ごとGATE・報告YAML・レビュー/新規テスト・contract test・fixture)が含まれる。殿裁定: 小さく1層ずつ→push→full→parity→次(2026-08-14 16:53)、儀式は削る(2026-08-15 18:59)。該当行:" >&2
        printf '%s
' "$_speed_hit" | cut -c1-200 | sed 's/^/    /' >&2
        exit 1
    fi
    if [ "$TYPE" = "task_assigned" ] && ! printf '%s' "$_speed_text" | grep -q '\[MEM:'; then
        echo "BLOCK(three_layer_guard): 将軍→家老のtask_assignedに三層記憶の引用[MEM: ...]がない。殿下知2026-08-15 19:05『すべての作業の前に三層記憶を確認する』。memory_db_query.sh --search / semantic_search.sh で裁定を引いて本文へ[MEM: source ts \"原文\"]を添えよ。" >&2
        exit 1
    fi
    unset _speed_text _speed_hit _ref
fi

# A final report review cannot simultaneously approve the report and predict
# that its gate will block.  Reject the structured contradiction before any
# approval lookup or mailbox persistence.  Free-form mentions of "BLOCK" do
# not match this guard.
if [ "$TYPE" = "report_review_result" ] && [ "$FROM" = "gunshi" ]; then
    if printf '%s\n' "$CONTENT" | grep -qiE '(^|[[:space:];,。])verdict[[:space:]]*[:=][[:space:]]*LGTM([[:space:];,。]|$)' \
        && printf '%s\n' "$CONTENT" | grep -qiE '(^|[[:space:];,。])gate_prediction[[:space:]]*[:=][[:space:]]*BLOCK([[:space:];,。、/(\[（]|$)'; then
        echo "BLOCK: contradictory report_review_result: verdict LGTM with gate_prediction BLOCK" >&2
        exit 2
    fi
fi

# A LGTM notification may only describe an approval already bound at review
# time. The report path must be explicit; delayed delivery never hashes anew.
if [ "$TYPE" = "report_review_result" ] && [ "$FROM" = "gunshi" ] && printf '%s' "$CONTENT" | grep -q 'verdict: LGTM'; then
    _guard_report=$(printf '%s' "$CONTENT" | grep -oE 'queue/reports/[A-Za-z0-9_.-]+\.yaml' | head -1 || true)
    _guard_cmd=$(printf '%s' "$CONTENT" | grep -oE 'cmd_[A-Za-z0-9_]+' | head -1 || true)
    [ -n "$_guard_report" ] && [ -n "$_guard_cmd" ] || { echo "BLOCK: LGTM notification requires explicit queue/reports path and cmd_id" >&2; exit 2; }
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/scripts/lib/review_approval.sh"
    PROJECT_ROOT="$SCRIPT_DIR" review_two_phase_ready_gunshi "$_guard_cmd" "$SCRIPT_DIR/$_guard_report" || { echo "BLOCK: LGTM approval marker missing, stale, or mismatched for $_guard_report" >&2; exit 2; }
fi
ACTION="${5:-}"

COMMANDER_DIRECTIVE_TASK_ID=""
COMMANDER_DIRECTIVE_SUBJECT_TASK_ID=""
COMMANDER_DIRECTIVE_PARENT_CMD=""
# Keep the dedicated shogun task_new policy gate as the first rejection for
# that forbidden route; every other task_new-to-karo send still requires the
# commander envelope through the generic boundary below.
if [ "$TARGET" = "karo" ] && inbox_karo_message_requires_identity "$TYPE" \
    && ! { [ "$FROM" = "shogun" ] && [ "$TYPE" = "task_new" ]; }; then
    _commander_directive_identity=$(inbox_commander_directive_identity "$CONTENT" 2>/dev/null || true)
    if [ -z "$_commander_directive_identity" ]; then
        echo "BLOCK: ${TYPE} to karo requires explicit task_id=commander_directive subject_task_id=<task> parent_cmd=<cmd> identity envelope" >&2
        exit 2
    fi
    mapfile -t _commander_directive_values <<< "$_commander_directive_identity"
    COMMANDER_DIRECTIVE_TASK_ID="${_commander_directive_values[0]:-}"
    COMMANDER_DIRECTIVE_SUBJECT_TASK_ID="${_commander_directive_values[1]:-}"
    COMMANDER_DIRECTIVE_PARENT_CMD="${_commander_directive_values[2]:-}"
fi

REVIEW_PENDING_NUDGE_TASK_ID=""
REVIEW_PENDING_NUDGE_SUBJECT_TASK_ID=""
REVIEW_PENDING_NUDGE_PARENT_CMD=""
REVIEW_PENDING_NUDGE_FINGERPRINT=""
REVIEW_PENDING_NUDGE_REPORT=""
REVIEW_PENDING_NUDGE_STATE=""
if inbox_type_is_review_pending_nudge "$TYPE"; then
    case "$TYPE:$TARGET:$ACTION" in
        review_report:gunshi:review_report|accept_report:karo:accept_report|run_cmd_complete:karo:run_cmd_complete) ;;
        *)
            echo "BLOCK: review-pending nudge target/action mismatch: type=$TYPE target=$TARGET action=${ACTION:-missing}" >&2
            exit 2
            ;;
    esac
    _review_pending_identity=$(inbox_review_pending_identity "$CONTENT" 2>/dev/null || true)
    if [ -z "$_review_pending_identity" ]; then
        echo "BLOCK: review-pending nudge requires task_id/subject_task_id/parent_cmd/report_fingerprint/report/review_pending_state" >&2
        exit 2
    fi
    mapfile -t _review_pending_values <<< "$_review_pending_identity"
    REVIEW_PENDING_NUDGE_TASK_ID="${_review_pending_values[0]:-}"
    REVIEW_PENDING_NUDGE_SUBJECT_TASK_ID="${_review_pending_values[1]:-}"
    REVIEW_PENDING_NUDGE_PARENT_CMD="${_review_pending_values[2]:-}"
    REVIEW_PENDING_NUDGE_FINGERPRINT="${_review_pending_values[3]:-}"
    REVIEW_PENDING_NUDGE_REPORT="${_review_pending_values[4]:-}"
    REVIEW_PENDING_NUDGE_STATE="${_review_pending_values[5]:-}"
fi

# Escalation messages must carry the self-trial receipt before any durable
# mailbox write.  The shared helper intentionally scopes the check to
# type=escalation; ordinary BLOCK/FAIL notifications use their existing lanes.
if ! escalation_evidence_validate_or_block inbox_write "$TYPE" "$CONTENT"; then
    exit 2
fi

# A ninja process becoming idle does not close a failed task.  The monitor
# deliberately excludes failed tasks from stall/idle handling, so the durable
# inbox boundary must turn an attempted ordinary idle notice into an explicit
# review request until a formal FAIL report has been closed (active or
# archived).  This keeps the state-machine hole visible without changing the
# sender's task YAML.
if [ "$TARGET" = "karo" ] && [ "$TYPE" = "idle_notice" ] && sender_is_ninja_from_fs "$FROM"; then
    _idle_task_file="$SCRIPT_DIR/queue/tasks/${FROM}.yaml"
    _idle_task_status=$(inbox_yaml_field_get "$_idle_task_file" "status" "")
    if [ "$_idle_task_status" = "failed" ]; then
        _idle_task_id=$(inbox_yaml_field_get "$_idle_task_file" "task_id" "")
        _idle_report_rel=$(inbox_yaml_field_get "$_idle_task_file" "report_path" "")
        _idle_report_state="MISSING"
        _idle_report_file=""
        if [ -n "$_idle_report_rel" ] && [ -f "$SCRIPT_DIR/$_idle_report_rel" ]; then
            _idle_report_file="$SCRIPT_DIR/$_idle_report_rel"
        elif [ -n "$_idle_report_rel" ]; then
            _idle_report_base="${_idle_report_rel##*/}"
            _idle_report_file=$(find "$SCRIPT_DIR/queue/archive/reports" -maxdepth 1 \
                -name "${_idle_report_base%.yaml}*.yaml" -print 2>/dev/null | head -1 || true)
        fi
        if [ -n "$_idle_report_file" ]; then
            # shellcheck source=/dev/null
            source "$SCRIPT_DIR/scripts/lib/report_terminal_state.sh"
            _idle_report_state=$(report_terminal_state "$_idle_report_file")
        fi
        if [ "$_idle_report_state" != "CLOSED_BLOCKED" ]; then
            TYPE="failed_unclosed"
            ACTION="review_failed_task"
            CONTENT="failed task requires formal close: worker=${FROM} task_id=${_idle_task_id:-unknown} report_state=${_idle_report_state} report_path=${_idle_report_rel:-missing}"
        fi
    fi
fi

# Fast path: profiling/usage queries should not pay the agent-config cost.
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

# Validate arguments
if [ -z "$TARGET" ] || [ -z "$CONTENT" ]; then
    usage >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

# Retro results use a dedicated append-only transport.  Normal results never
# enter karo's inbox one-by-one; retro_write emits one batch-ready event at the
# six-result boundary (or an explicit final checkpoint). Safety severities are
# the only immediate exception.
if [ "$TYPE" = "retro_result" ] && [ "$TARGET" = "karo" ]; then
    _retro_parent=$(printf '%s' "$CONTENT" | grep -oE 'parent_report_id=[^[:space:]]+' | head -1 | cut -d= -f2- || true)
    _retro_deployed=$(printf '%s' "$CONTENT" | grep -oE 'deployed_at=[^[:space:]]+' | head -1 | cut -d= -f2- || true)
    _retro_done=$(printf '%s' "$CONTENT" | grep -oE 'done_at=[^[:space:]]+' | head -1 | cut -d= -f2- || true)
    _retro_report=$(printf '%s' "$CONTENT" | grep -oE 'report_at=[^[:space:]]+' | head -1 | cut -d= -f2- || true)
    _retro_commit=$(printf '%s' "$CONTENT" | grep -oE 'commit_at=[^[:space:]]+' | head -1 | cut -d= -f2- || true)
    _retro_severity=$(printf '%s' "$CONTENT" | grep -oE 'severity=[^[:space:]]+' | head -1 | cut -d= -f2- || true)
    [ -n "$_retro_parent" ] && [ -n "$_retro_deployed" ] || { echo "BLOCK: malformed retro_result" >&2; exit 2; }
    bash "$SCRIPT_DIR/scripts/retro_write.sh" submit "$FROM" "$_retro_parent" "$_retro_deployed" \
        "${_retro_done:--}" "${_retro_report:--}" "${_retro_commit:--}" "${_retro_severity:-normal}" "$CONTENT"
    exit 0
fi

if [[ "$TARGET" == cmd_* ]]; then
    echo "ERROR: 第1引数はtarget_agent（例: karo, hanzo）。cmd_idではない。" >&2
    usage >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

if [ -z "$ACTION" ]; then
    echo "[inbox_write] WARN: action omitted; writing message without action field for backward compatibility" >&2
fi

if checkpoint_manifest_defer_unready_review; then
    exit 0
fi

# HIGH-2: パストラバーサル防止 + sender/target制約
# Common path: 静的役職 + queue/tasks|inbox の実在確認だけで判定できる場合は
# agent_config.sh を読まない。fallback時のみロードする。
if [ "${INBOX_WRITE_TEST:-}" != "1" ]; then
    valid_target=0
    if known_agent_from_fs "$TARGET"; then
        valid_target=1
        ALLOWED_TARGETS="shogun karo gunshi + known queue agents"
    else
        ensure_agent_config_loaded
        if type get_allowed_targets &>/dev/null; then
            ALLOWED_TARGETS=$(get_allowed_targets)
            for allowed in $ALLOWED_TARGETS; do
                if [ "$TARGET" = "$allowed" ]; then
                    valid_target=1
                    break
                fi
            done
        fi
    fi
    if [ "$valid_target" -eq 0 ]; then
        echo "ERROR: Invalid target agent: '$TARGET'. Allowed: ${ALLOWED_TARGETS:-none}" >&2
        exit 1
    fi

    is_ninja_sender=0
    if sender_is_ninja_from_fs "$FROM"; then
        is_ninja_sender=1
    elif [ "$TARGET" = "shogun" ]; then
        ensure_agent_config_loaded
        for ninja in $NINJA_NAMES; do
            if [ "$FROM" = "$ninja" ]; then
                is_ninja_sender=1
                break
            fi
        done
    fi

    if [ "$is_ninja_sender" -eq 1 ] && [ "$TARGET" = "shogun" ]; then
        echo "ERROR: Ninja cannot send inbox to shogun directly. Use karo as relay." >&2
        exit 1
    fi

    # cmd_4357 の自動レビュー依頼(ninja_monitor→gunshi, type=review_draft)は正規経路。
    # 2026-08-27 00:15 実証: この制限が自動依頼を毎回BLOCKし(stderrは捨てられ)、報告10本がUN-GATEDで滞留した。
    if [ "$FROM" = "ninja_monitor" ] && [ "$TARGET" != "karo" ] && [ "$TARGET" != "shogun" ] \
        && ! { [ "$TARGET" = "gunshi" ] && { [ "$TYPE" = "review_draft" ] || [ "$TYPE" = "review_report" ]; }; }; then
        echo "ERROR: ninja_monitor can send only to karo or shogun (except review_draft to gunshi)." >&2
        exit 1
    fi
fi

# This is the public lane contract, so fixtures exercise it in test mode too.
inbox_validate_investigation_result "$TARGET" "$FROM" "$CONTENT"

# A bare revision notification must never race ahead of formal RC.  The RC
# helper atomically reopens task/report state; persistence before that point can
# be consumed and then erased by monitor auto-clear.
guard_report_revision_delivery "$TARGET" "$TYPE"

# task_new gate: 将軍からの直接作業指示はcmd品質ゲートを迂回するため禁止
if [ "$FROM" = "shogun" ] && [ "$TYPE" = "task_new" ]; then
    echo "" >&2
    echo "==============================" >&2
    echo "[task_new_gate] BLOCKED: shogun cannot send type=task_new directly" >&2
    echo "[task_new_gate] Use cmd_save.sh→cmd_delegate.sh→karo deployment flow." >&2
    echo "==============================" >&2
    exit 1
fi

INBOX_LINK_PATH="$SCRIPT_DIR/queue/inbox/${TARGET}.yaml"
INBOX="$(resolve_inbox_file_path "$INBOX_LINK_PATH")"
LOCKFILE="$(lock_path "$INBOX")"
INBOX_DIR="${INBOX%/*}"
[ -d "$INBOX_DIR" ] || mkdir -p "$INBOX_DIR"

# Generate message ID and timestamp using bash builtins to avoid subprocess overhead.
# S1 fast-delivery callers may preallocate the idempotency key so the durable
# receipt and the authoritative inbox row share one identity across restarts.
# The default remains unchanged for every existing caller.
if [ -n "${INBOX_MESSAGE_ID:-}" ]; then
    if [[ ! "$INBOX_MESSAGE_ID" =~ ^msg_[A-Za-z0-9_.:-]+$ ]]; then
        echo "ERROR: Invalid INBOX_MESSAGE_ID: '$INBOX_MESSAGE_ID'" >&2
        exit 1
    fi
    MSG_ID="$INBOX_MESSAGE_ID"
else
    printf -v _msg_stamp '%(%Y%m%d_%H%M%S)T' -1
    printf -v _msg_rand '%04x%04x' "$RANDOM" "$RANDOM"
    MSG_ID="msg_${_msg_stamp}_$$_${_msg_rand}"
fi
printf -v TIMESTAMP '%(%Y-%m-%dT%H:%M:%S)T' -1

# Review context push: 軍師レビュー依頼は送信経路で三層記憶を添付する。
# 検索失敗・timeoutはfail-soft。依頼送信自体は止めない。
inbox_maybe_attach_review_context

# Duplicate deploy gate: every task_assigned delivery path must converge here.
# If another ninja already owns the same parent_cmd in an active state, block
# before persisting the new assignment notification.
if [ "$TYPE" = "task_assigned" ]; then
    NINJA_TASK="$SCRIPT_DIR/queue/tasks/${TARGET}.yaml"
    if [ -f "$NINJA_TASK" ]; then
        _target_parent_cmd=$(inbox_yaml_field_get "$NINJA_TASK" "parent_cmd" "")
        _active_duplicates=$(find_active_peer_deployments "$TARGET")
        if [ -n "$_target_parent_cmd" ] && [ -n "$_active_duplicates" ]; then
            echo "" >&2
            echo "==============================" >&2
            echo "[duplicate_deploy_gate] BLOCKED: same parent_cmd already active" >&2
            echo "[duplicate_deploy_gate] parent_cmd=${_target_parent_cmd} target=${TARGET}" >&2
            while IFS=$'\t' read -r _dup_ninja _dup_status; do
                [ -n "$_dup_ninja" ] || continue
                echo "[duplicate_deploy_gate] duplicate=${_dup_ninja} status=${_dup_status}" >&2
            done <<< "$_active_duplicates"
            echo "[duplicate_deploy_gate] Resolve/complete the active deployment before assigning another ninja to the same parent_cmd." >&2
            echo "==============================" >&2
            notify_karo_duplicate_deploy_block "$TARGET" "$_target_parent_cmd" "$_active_duplicates"
            exit 1
        fi
    fi
fi

# Pre-action auto-capture: 将軍→エージェント送信時、送信先ペインの現在状態を送信前に自動表示+ログ
# 目的: 「観察なき行動」を構造的に防止（知性の外部化原則 2026-03-21）
if [ "${INBOX_WRITE_TEST:-}" != "1" ] && { [ "$FROM" = "shogun" ] || [ "$FROM" = "karo" ]; }; then
    _pre_send_capture_started_us="${EPOCHREALTIME/./}"
    _pane_target=""
    # Use the resolver already loaded in this script.  Sourcing pane_lookup.sh
    # here repeated agent-config initialization and a second tmux scan for every
    # commander send.  The in-script resolver only accepts a live @agent_id
    # mapping, so the pre-send safety observation is retained without a static
    # fallback that could point at a stale pane after respawn.
    _pane_target="$(resolve_agent_pane_target "$TARGET" || true)"

    if [ -n "$_pane_target" ]; then
        _capture=$(tmux capture-pane -t "$_pane_target" -p 2>/dev/null | tail -8 || true)
        echo "[pre-send capture] ${TARGET} pane state BEFORE message:"
        echo "$_capture"
        echo "★10回問い: このアクションを10回繰り返したら正の複利か負の複利か？"
        echo "★前提問い: この指示に含まれる数値・条件は自分で確認したか？出典は？中継元の主張を鵜呑みにしていないか？"
        # CTX:0%検知 — task_assigned送信先がCTX:0%なら反応しない可能性を警告
        if [ "$TYPE" = "task_assigned" ]; then
            _ctx_val=$(echo "$_capture" | grep -oP 'CTX:\K[0-9]+' | tail -1)
            if [ "${_ctx_val:-99}" = "0" ]; then
                echo "⚠⚠⚠ WARNING: ${TARGET} CTX:0% — STALL高リスク。30秒後にペイン確認せよ ⚠⚠⚠"
            fi
        fi
        echo "---"
        # Persistent log (survives /clear, enables post-mortem)
        _logdir="$SCRIPT_DIR/logs"
        mkdir -p "$_logdir"
        printf '%s [%s→%s type=%s] pane:\n%s\n---\n' \
            "$TIMESTAMP" "$FROM" "$TARGET" "$TYPE" "$_capture" \
            >> "$_logdir/shogun_action_log.txt" 2>/dev/null || true
    fi
    iw_record_timing inbox_write_pre_send_capture "$_pre_send_capture_started_us" PASS
fi

# Lesson injection safety net: type=task_assigned → 教訓注入チェック
# 目的: deploy_task.sh未使用時でも教訓が忍者に届くことを保証（ラルフループ断絶防止）
if [ "$TYPE" = "task_assigned" ]; then
    NINJA_TASK="$SCRIPT_DIR/queue/tasks/${TARGET}.yaml"
    if [ -f "$NINJA_TASK" ]; then
        TASK_LOCKFILE="$(lock_path "$NINJA_TASK")"
        LESSON_CHECK=$(
            (
                flock -w 5 200 || { echo "[lesson_safety_net] WARN: flock timeout on ${TARGET} task YAML, skipping lesson injection" >&2; exit 1; }
                project_id=$(inbox_yaml_field_get "$NINJA_TASK" "project" "infra")
                inject_universal_lessons_if_missing "$NINJA_TASK" "${project_id:-infra}"
            ) 200>"$TASK_LOCKFILE" 2>&1 || true)
        if [ -n "$LESSON_CHECK" ]; then
            echo "[lesson_safety_net] $LESSON_CHECK" >&2
        fi
    fi
fi

# cmd_new gate: type=cmd_new → cmd_save.sh gate照合
# 目的: gate BLOCK中のcmd委任を防止（将軍がcmd_delegate.shを迂回してinbox_write直送信する経路を封鎖）
# 原因事故: cmd_2004でcmd_save.sh BLOCK中に手動inbox_writeで家老に送信→gate未通過cmdが配備された
if [ "$TYPE" = "cmd_new" ]; then
    # contentからcmd_idを抽出（"cmd_XXXX"パターン）
    _CMD_NEW_ID=$(echo "$CONTENT" | grep -oP 'cmd_\d+' | head -1 || true)
    if [ "$FROM" = "shogun" ] && [ -z "$_CMD_NEW_ID" ]; then
        echo "" >&2
        echo "==============================" >&2
        echo "[cmd_new_gate] BLOCKED: shogun cmd_new にcmd_idが含まれていない" >&2
        echo "[cmd_new_gate] LS-A07: gate迂回禁止。cmd_idなしのcmd_newはcmd_save/cmd_new_gate/軍師レビュー/教訓サイクルを全て迂回する" >&2
        echo "[cmd_new_gate] 正規テンプレート: bash scripts/cmd_publish.sh cmd_XXXX \"cmd_XXXXを書いた。配備せよ。\"" >&2
        echo "[cmd_new_gate] 既存cmd委任のみなら: bash scripts/cmd_delegate.sh cmd_XXXX" >&2
        echo "==============================" >&2
        exit 1
    fi
    if [ -n "$_CMD_NEW_ID" ]; then
        # statusを確認。pendingならgate未通過(cmd_delegate.shはinbox_write前にstatus=delegatedに変更済み)
        _CMD_STATUS=$(awk -v id="$_CMD_NEW_ID" '
            $0 ~ "^  " id ":" { found=1; next }
            found && /^    status:/ { gsub(/.*status:[[:space:]]*/, ""); gsub(/"/, ""); print; exit }
            found && /^  [a-zA-Z]/ { exit }
        ' "$SCRIPT_DIR/queue/shogun_to_karo.yaml" 2>/dev/null)
        if [ -z "$_CMD_STATUS" ]; then
            echo "[cmd_new_gate] BLOCKED: ${_CMD_NEW_ID} がshogun_to_karo.yamlに存在しない" >&2
            exit 1
        fi
        if [ "$_CMD_STATUS" = "pending" ]; then
            echo "" >&2
            echo "==============================" >&2
            echo "[cmd_new_gate] BLOCKED: ${_CMD_NEW_ID} はstatus=pending(gate未通過)" >&2
            echo "[cmd_new_gate] cmd_save.sh→cmd_delegate.shの正規フローでgateを通せ" >&2
            echo "==============================" >&2
            exit 1
        fi
    fi
fi

# Report format gate: 忍者の報告完了type → 報告YAMLのフォーマット検証
# 目的: 家老の手動修正作業を根絶（karo_workarounds 5件連続同一問題を自動化×強制で解消）
# LK013: Codex忍者がtask_done typeで報告→gunshi_notify不発を防止
if inbox_type_triggers_report_completion "$TYPE"; then
    VERIFIED_FAILURE_REPORT=0
    # Find report YAML path from task YAML
    ensure_agent_config_loaded
    is_ninja_reporter=0
    for ninja in $NINJA_NAMES; do
        if [ "$FROM" = "$ninja" ]; then
            is_ninja_reporter=1
            break
        fi
    done

    if [ "$is_ninja_reporter" -eq 1 ]; then
        TASK_YAML="$SCRIPT_DIR/queue/tasks/${FROM}.yaml"
        if [ -f "$TASK_YAML" ]; then
            REPORT_PATH=$(inbox_yaml_field_get "$TASK_YAML" "report_path" "")

            FULL_REPORT=""
            if [ -n "$REPORT_PATH" ]; then
                FULL_REPORT="$SCRIPT_DIR/$REPORT_PATH"
                if [ ! -f "$FULL_REPORT" ]; then
                    FULL_REPORT=$(inbox_resolve_archived_report_for_task "$FULL_REPORT" "$TASK_YAML") || exit 1
                    echo "[report_format_gate] archive fallback: identity一致 $(basename "$FULL_REPORT") を検出" >&2
                fi
            else
                # Fallback: report_path未設定 → queue/reports/{from}_report_{cmd_id}*.yaml を検索
                CMD_ID=$(inbox_yaml_field_get "$TASK_YAML" "parent_cmd" "")
                if [ -n "$CMD_ID" ]; then
                    FALLBACK=$(find "$SCRIPT_DIR/queue/reports" -maxdepth 1 -name "${FROM}_report_${CMD_ID}*.yaml" -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2- || true)
                    if [ -z "$FALLBACK" ]; then
                        # archive fallback: queue/reports/に不在→queue/archive/reports/を検索
                        FALLBACK=$(find "$SCRIPT_DIR/queue/archive/reports" -maxdepth 1 -name "${FROM}_report_${CMD_ID}*.yaml" -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2- || true)
                    fi
                    if [ -n "$FALLBACK" ]; then
                        FULL_REPORT="$FALLBACK"
                        echo "[report_format_gate] fallback: report_path未設定 → $(basename "$FALLBACK") を検出" >&2
                    else
                        echo "[report_format_gate] BLOCKED: 報告YAMLが見つからない: queue/reports/${FROM}_report_${CMD_ID}*.yaml" >&2
                        exit 1
                    fi
                else
                    echo "[report_format_gate] BLOCKED: 報告YAMLが見つからない: report_path未設定 + parent_cmd未設定 (ninja: ${FROM})" >&2
                    exit 1
                fi
            fi

            if [ -n "${FULL_REPORT:-}" ] && [ -f "$FULL_REPORT" ]; then
                _REPORT_IDENTITY=$(inbox_resolve_report_identity "$FULL_REPORT" "$TASK_YAML") || exit 1
                IFS=$'\t' read -r STRUCTURED_REPORT_ID STRUCTURED_REPORT_VERSION STRUCTURED_REPORT_PATH <<< "$_REPORT_IDENTITY"
                STRUCTURED_TASK_ID=$(inbox_yaml_field_get "$TASK_YAML" "task_id" "")
                # cmd_4163: 報告YAML自身のparent_cmdを一次として帰属を解決する。
                # task YAMLは配備間隔中に次cmdへ差し替わり得るため、その現在値を
                # 一次にすると「旧cmd向け報告が新cmdへ誤帰属する」raceが起きる
                # (LS078)。報告YAML自身のparent_cmdは発行時点で固定され、以後
                # 変化しないので、こちらを一次・task YAMLはレガシー報告
                # (parent_cmd未記載)向けのfallbackに限定する。
                STRUCTURED_PARENT_CMD=$(inbox_yaml_field_get "$FULL_REPORT" "parent_cmd" "")
                [ -n "$STRUCTURED_TASK_ID" ] || STRUCTURED_TASK_ID=$(inbox_yaml_field_get "$FULL_REPORT" "task_id" "")
                [ -n "$STRUCTURED_PARENT_CMD" ] || STRUCTURED_PARENT_CMD=$(inbox_yaml_field_get "$TASK_YAML" "parent_cmd" "")
                STRUCTURED_REPORT_FINGERPRINT=$(inbox_report_fingerprint "$FULL_REPORT" "$STRUCTURED_REPORT_ID:$STRUCTURED_REPORT_VERSION") || exit 1
                STRUCTURED_REVISION_FINGERPRINT=$(inbox_report_revision_fingerprint "$TYPE" "$ACTION" "$CONTENT")

                # Retry fast path: once an event is durable, do not rerun the
                # expensive report gate or downstream notification chain.
                # Concurrent first writers still converge at the authoritative
                # check+append transaction below.
                _early_event_id=$(
                    {
                        flock -w 5 201 || exit 1
                        inbox_report_event_duplicate_locked "$INBOX" "$TARGET" "$TYPE" "$FROM" "$STRUCTURED_REPORT_ID" "$STRUCTURED_REPORT_VERSION" "$STRUCTURED_REPORT_FINGERPRINT" "$STRUCTURED_REVISION_FINGERPRINT"
                    } 201>"$LOCKFILE" || true
                )
                if [ -n "$_early_event_id" ]; then
                    if inbox_type_triggers_report_completion "$TYPE" && [ -n "${FULL_REPORT:-}" ] && [ -n "${STRUCTURED_PARENT_CMD:-}" ]; then
                        inbox_deliver_report_review_generation "$FROM" "$FULL_REPORT" "$STRUCTURED_PARENT_CMD" "$STRUCTURED_REPORT_FINGERPRINT" || true
                        inbox_reconcile_terminal_task_generation "$FROM" "$FULL_REPORT" || {
                            echo "[inbox_write] WARN: duplicate terminal event task reconciliation failed: id=$_early_event_id" >&2
                            exit 1
                        }
                    fi
                    printf 'DUPLICATE_MSG_ID=%s\n' "$_early_event_id"
                    exit 0
                fi
            fi

            if [ -n "$FULL_REPORT" ]; then
                if [ -f "$FULL_REPORT" ]; then
                    # Phase 1: 機械的フォーマット自動修正（忍者ペインで局所免疫）
                    AUTOFIX_RESULT=$("$SCRIPT_DIR/scripts/gates/gate_report_autofix.sh" "$FULL_REPORT" 2>&1 || true)
                    if echo "$AUTOFIX_RESULT" | grep -q "^AUTO-FIXED"; then
                        echo "[report_autofix] $AUTOFIX_RESULT" >&2
                    fi
                    # Phase 2: フォーマット検証（auto-fix後に実行）
                    # Reuse only a caller validation bound to this exact
                    # lifecycle generation.  A missing or stale value is
                    # cleared so gate_report_format performs a full check.
                    _GATE_REUSE_FINGERPRINT=""
                    if [ -n "${GATE_VALIDATED_FINGERPRINT:-}" ] &&
                       [ "$GATE_VALIDATED_FINGERPRINT" = "${STRUCTURED_REPORT_FINGERPRINT:-}" ]; then
                        _GATE_REUSE_FINGERPRINT="$GATE_VALIDATED_FINGERPRINT"
                    fi
                    # Lazily sourced: this path only runs once a FULL_REPORT is being
                    # validated, so the filesystem fast-path (wake_up etc., which never
                    # reaches here) keeps its zero-extra-dependency contract.
                    # shellcheck source=scripts/lib/gate_report_format_classify.sh
                    source "$SCRIPT_DIR/scripts/lib/gate_report_format_classify.sh"
                    GATE_EXIT=0
                    GATE_RESULT=$(GATE_VALIDATED_FINGERPRINT="$_GATE_REUSE_FINGERPRINT" \
                        bash "$SCRIPT_DIR/scripts/gates/gate_report_format.sh" "$FULL_REPORT" 2>&1) || GATE_EXIT=$?
                    GATE_STATUS=$(gate_report_format_classify "$GATE_EXIT")

                    # cmd_karo_hotfix_singleflight_fail_misattribution_20260725 (AC1/AC2):
                    # インフラ由来のsingle-flightロック競合(exit code 2)は、忍者の品質FAIL
                    # とは機械的に区別する(文字列prefixに依存しない)。忍者へ修正を要求せず、
                    # 報告も破棄しない。1回だけ再試行し、なお解消しなければ軍師ではなく
                    # 家老へインフラ異常として明示通知する(品質監視通知は出さない)。
                    # provenance: 本変更の実体はdf3421336で導入済み。
                    if [ "$GATE_STATUS" = "INFRA_TIMEOUT" ]; then
                        echo "[report_format_gate] INFO: single-flightタイムアウト(インフラ由来)を検出。1回再試行する" >&2
                        GATE_EXIT=0
                        GATE_RESULT=$(GATE_VALIDATED_FINGERPRINT="$_GATE_REUSE_FINGERPRINT" \
                            bash "$SCRIPT_DIR/scripts/gates/gate_report_format.sh" "$FULL_REPORT" 2>&1) || GATE_EXIT=$?
                        GATE_STATUS=$(gate_report_format_classify "$GATE_EXIT")
                    fi

                    if [ "$GATE_STATUS" = "INFRA_TIMEOUT" ]; then
                        ensure_agent_config_loaded
                        KARO_INBOX="$(get_commander_inbox_path karo)"
                        ROUTE_TS=$(date -Is)
                        ROUTE_ID="msg_$(date +%s%N | head -c 16)"
                        (
                            flock -w 5 202 || { echo "[report_quality_route] WARN: flock timeout for karo inbox, skipping infra notification" >&2; exit 1; }
                            if [ ! -f "$KARO_INBOX" ]; then
                                mkdir -p "$(dirname "$KARO_INBOX")"
                                printf 'messages: []\n' > "$KARO_INBOX"
                            fi
                            _karo_msg="$(inbox_build_message_block \
                                content "【インフラ異常】報告gateのsingle-flightロック競合により忍者${FROM}の報告フォーマット検証が2回連続timeout。忍者の品質問題ではない。report_path=${FULL_REPORT}" \
                                from "system" \
                                id "$ROUTE_ID" \
                                read "false" \
                                timestamp "$ROUTE_TS" \
                                type "infra_anomaly" \
                                original_ninja "$FROM" \
                                report_path "$FULL_REPORT")"$'\n'
                            inbox_append_message_locked "$KARO_INBOX" "$_karo_msg"
                        ) 202>"$(lock_path "$KARO_INBOX")" \
                            && echo "[report_quality_route] インフラ異常を家老に通知済み(忍者への修正要求は行わない)" >&2 \
                            || echo "[report_quality_route] WARN: karo infra notification skipped (flock timeout)" >&2
                        echo "" >&2
                        echo "==============================" >&2
                        echo "[report_format_gate] インフラ異常(ロック競合)により報告フォーマット検証が完了できなかった (ninja: ${FROM})" >&2
                        echo "[report_format_gate] 報告YAMLの問題ではない。修正不要。家老の復旧対応を待て" >&2
                        echo "==============================" >&2
                        exit 1
                    fi

                    if [ "$GATE_STATUS" = "QUALITY_FAIL" ]; then
                        # GP-071: テンプレート状態検出 — 忍者がまだ記入中ならquality_fix_requestスキップ
                        # FILL_THIS残存 or verdict未記入 → テンプレート状態（忍者が書いている途中）
                        # verdict記入済み + FAIL → 本物の品質問題 → 軍師に転送
                        IS_TEMPLATE=$(report_yaml_is_template "$FULL_REPORT")

                        if [ "$IS_TEMPLATE" = "yes" ]; then
                            # GP-071改: テンプレート状態でreport_received = 報告未完了のまま完了報告 = BLOCK
                            # 旧: exit 0でバイパス → 不完全報告がkaroに届く → workaround（消火構造）
                            # 新: exit 1でBLOCK → 忍者がフィールドを埋めてから再送信（品質向上）
                            echo "" >&2
                            echo "==============================" >&2
                            echo "[report_format_gate] BLOCKED: 報告が未完了 (ninja: ${FROM})" >&2
                            echo "[report_format_gate] verdict未記入 or FILL_THIS残存。フィールドを全て埋めてから再送信せよ" >&2
                            echo "[report_format_gate] FAIL理由:" >&2
                            while IFS= read -r _gate_line; do
                                echo "  $_gate_line" >&2
                            done <<< "$GATE_RESULT"
                            echo "" >&2
                            echo "[report_format_gate] 修正後に再送信せよ: bash scripts/inbox_write.sh karo \"報告完了\" report_received ${FROM}" >&2
                            echo "[report_format_gate] 調査返信なら完了通知ではない。次を使え: bash scripts/inbox_write.sh karo \"task_id=<id> check_id=<id> occurred_at=<ISO8601> evidence=<path> impact=<summary>\" investigation_result ${FROM} reply_required" >&2
                            echo "==============================" >&2
                            exit 1
                        fi

                        # Phase 3: 品質問題→軍師に監視通知（第二層分離）
                        # GP-102: 修正指示→監視通知に変更(消火→品質向上)
                        # 旧: 軍師に修正を指示 → 軍師が代行修正 = 消火の移転(忍者が学ばない)
                        # 新: 軍師に監視通知のみ → 忍者がBLOCKエラーを見て自分で修正 → 学習ループ回転
                        ensure_agent_config_loaded
                        GUNSHI_INBOX="$(get_commander_inbox_path gunshi)"
                        ROUTE_TS=$(date -Is)
                        ROUTE_ID="msg_$(date +%s%N | head -c 16)"
                        (
                            flock -w 5 200 || { echo "[report_quality_route] WARN: flock timeout for gunshi inbox, skipping quality notification" >&2; exit 1; }
                            if [ ! -f "$GUNSHI_INBOX" ]; then
                                mkdir -p "$(dirname "$GUNSHI_INBOX")"
                                printf 'messages: []\n' > "$GUNSHI_INBOX"
                            fi
                            _gunshi_msg="$(inbox_build_message_block \
                                content "【監視通知】忍者${FROM}の報告YAMLにgate FAIL。忍者にBLOCK済み。忍者が自分で修正して再送信する。軍師は直接修正するな(消火行為)。パターン分析用の記録。" \
                                from "system" \
                                id "$ROUTE_ID" \
                                read "false" \
                                timestamp "$ROUTE_TS" \
                                type "quality_monitor" \
                                gate_errors "$GATE_RESULT" \
                                original_ninja "$FROM" \
                                report_path "$FULL_REPORT")"$'\n'
                            inbox_append_message_locked "$GUNSHI_INBOX" "$_gunshi_msg"
                        ) 200>"$(lock_path "$GUNSHI_INBOX")" \
                            && echo "[report_quality_route] 品質問題を軍師に監視通知済み(修正は忍者が行う)" >&2 \
                            || echo "[report_quality_route] WARN: gunshi notification skipped (flock timeout)" >&2
                        # BLOCK: verdict記入済み+gate FAIL → 忍者が修正して再送信するまでkaroに届けない
                        echo "" >&2
                        echo "==============================" >&2
                        echo "[report_format_gate] BLOCKED: 報告YAML品質問題 (ninja: ${FROM})" >&2
                        echo "[report_format_gate] FAIL理由:" >&2
                        while IFS= read -r _gate_line; do
                            echo "  $_gate_line" >&2
                        done <<< "$GATE_RESULT"
                        echo "" >&2
                        echo "[report_format_gate] 修正方法: bash scripts/report_field_set.sh <report_path> <key> <value>" >&2
                        echo "[report_format_gate] 修正例:" >&2
                        echo "  echo '[{check: \"AC完了確認\", result: \"yes\"}]' | bash scripts/report_field_set.sh $REPORT_PATH binary_checks.AC1 -" >&2
                        echo "  bash scripts/report_field_set.sh $REPORT_PATH lesson_candidate.found false" >&2
                        echo "  bash scripts/report_field_set.sh $REPORT_PATH lesson_candidate.no_lesson_reason '既知のL084と同じパターン'" >&2
                        echo "  bash scripts/report_field_set.sh $REPORT_PATH result.summary '実装完了'" >&2
                        echo "  # verdict は gate_report_format.sh が binary_checks から自動導出" >&2
                        echo "==============================" >&2
                        echo "[report_format_gate] 修正後に再送信せよ: bash scripts/inbox_write.sh karo \"報告完了\" report_received ${FROM}" >&2
                        exit 1
                    fi

                    # Phase 2.5: フォーマットPASSでもverdict=FAILなら成功完了通知を通さない。
                    # gate_report_format.shはbinary_checksからverdictを自動導出するため、
                    # 正直な失敗報告は task_failed だけを正規入口とし、task側もfailedであることを要求する。
                    FAIL_DETAILS="$(report_yaml_fail_details "$FULL_REPORT" 2>/dev/null || true)"
                    if [ -n "$FAIL_DETAILS" ]; then
                        if [ "$TYPE" = "task_failed" ]; then
                            TASK_STATUS=$(inbox_yaml_field_get "$TASK_YAML" "status" "")
                            if [ "$TASK_STATUS" != "failed" ] && [ "$TASK_STATUS" != "blocked" ]; then
                                echo "[report_format_gate] BLOCKED: task_failed requires task status=failed|blocked (actual: ${TASK_STATUS:-missing})" >&2
                                exit 1
                            fi
                            echo "[report_format_gate] verified failure report: verdict=FAIL, task status=failed (ninja: ${FROM})" >&2
                            VERIFIED_FAILURE_REPORT=1
                        else
                        echo "" >&2
                        echo "==============================" >&2
                        echo "[report_format_gate] BLOCKED: binary_checksにnoがあるため報告完了を差戻し (ninja: ${FROM})" >&2
                        echo "[report_format_gate] no判定のAC:" >&2
                        while IFS= read -r _fail_line; do
                            [ -n "$_fail_line" ] && echo "  $_fail_line" >&2
                        done <<< "$FAIL_DETAILS"
                        echo "" >&2
                        echo "[report_format_gate] no項目を修正してbinary_checksをyesにするか、未達ならtaskをfailedとしてtask_failedで家老へ報告せよ" >&2
                        echo "[report_format_gate] 修正例: bash scripts/report_field_set.sh $REPORT_PATH binary_checks.AC1.0.result yes" >&2
                        echo "[report_format_gate] 修正後に再送信せよ: bash scripts/inbox_write.sh karo \"報告完了\" report_received ${FROM}" >&2
                        echo "==============================" >&2
                        exit 1
                        fi
                    elif [ "$TYPE" = "task_failed" ]; then
                        echo "[report_format_gate] BLOCKED: task_failed requires report verdict=FAIL with binary_checks result=no" >&2
                        exit 1
                    fi
                else
                    echo "[report_format_gate] BLOCKED: 報告YAMLが見つからない: $FULL_REPORT" >&2
                    exit 1
                fi
            fi

            # Git uncommitted check: 報告YAMLのfiles_modified + task YAMLのtarget_pathを確認
            # cmd_1296教訓: 全repoではなく忍者が申告したファイルのみチェック（運用ファイル誤検知防止）
            # サイクル2: WARNING→BLOCK昇格。commit漏れは忍者ペインで止める（局所免疫）
            # cmd_2704: scout_exempt=true の偵察免除タスクはコード変更なし前提のため、このgateをスキップする。
            TASK_SCOUT_EXEMPT=""
            if [ -n "$TASK_YAML" ] && [ -f "$TASK_YAML" ]; then
                TASK_SCOUT_EXEMPT=$(inbox_yaml_field_get "$TASK_YAML" "scout_exempt" "" 2>/dev/null || true)
            fi

            if [ "$VERIFIED_FAILURE_REPORT" = "1" ]; then
                # A canonical task_failed report must remain deliverable when the
                # failed attempt intentionally leaves task-owned WIP uncommitted.
                # Requiring a commit here creates a deadlock: the failure report
                # cannot reach karo until the failed implementation is committed.
                # Success completion types still use the strict uncommitted gate.
                echo "[git_uncommitted_gate] SKIP: verified task_failed preserves failure evidence (ninja: ${FROM})" >&2
            elif [ "$TASK_SCOUT_EXEMPT" = "true" ]; then
                echo "[git_uncommitted_gate] SKIP: scout_exempt=true (ninja: ${FROM})" >&2
            else
                REPORT_CHECK_PATHS="$(inbox_extract_report_paths "$FULL_REPORT" | awk 'NF && $0 != "偵察のみ"')"
                if [ -n "$REPORT_CHECK_PATHS" ]; then
                    # Report YAMLのfiles_modifiedは忍者の実変更申告。これがある時は
                    # task.target_pathの広いディレクトリ指定を混ぜない。混ぜると
                    # 家老/他忍者の同時インフラ変更で完了報告が誤BLOCKされる。
                    GIT_CHECK_PATHS="$(printf '%s\n' "$REPORT_CHECK_PATHS" | awk '!seen[$0]++')"
                else
                    GIT_CHECK_PATHS="$(inbox_extract_task_paths "$TASK_YAML" | awk '!seen[$0]++')"
                fi
            fi

            if [ "$VERIFIED_FAILURE_REPORT" != "1" ] && [ "$TASK_SCOUT_EXEMPT" != "true" ] && [ -n "$GIT_CHECK_PATHS" ]; then
                # プロジェクトリポジトリの解決: task YAMLのproject:からprojects/{project}.yamlのpath:を参照
                # cmd_1412教訓: SCRIPT_DIR(multi-agent-shogun)でDM-signalファイルをチェックしても検出不能
                GIT_REPO_DIR="$SCRIPT_DIR"
                if [ -n "$TASK_YAML" ] && [ -f "$TASK_YAML" ]; then
                    _proj=$(grep -m1 '^\s*project:' "$TASK_YAML" 2>/dev/null | sed 's/.*project:[[:space:]]*//' | sed "s/['\"]//g" | tr -d '[:space:]' || true)
                    if [ -n "$_proj" ] && [ -f "$SCRIPT_DIR/projects/${_proj}.yaml" ]; then
                        _proj_path=$(grep -m1 '^\s*path:' "$SCRIPT_DIR/projects/${_proj}.yaml" 2>/dev/null | sed 's/.*path:[[:space:]]*//' | sed "s/['\"]//g" | sed 's/[[:space:]]*$//' || true)
                        if [ -n "$_proj_path" ] && [ -d "$_proj_path/.git" ]; then
                            GIT_REPO_DIR="$_proj_path"
                        fi
                    fi
                fi
                # A linked-worktree reporter must opt in explicitly.  Accept
                # only a real worktree of the canonical repo and only when the
                # report commit is the worktree HEAD; arbitrary paths and stale
                # or foreign commits remain fail-closed.
                if [ -n "${INBOX_REPORT_WORKTREE_ROOT:-}" ]; then
                    _requested_root=$(git -C "$INBOX_REPORT_WORKTREE_ROOT" rev-parse --show-toplevel 2>/dev/null || true)
                    _canonical_root=$(git -C "$GIT_REPO_DIR" rev-parse --show-toplevel 2>/dev/null || true)
                    _requested_common=$(git -C "$INBOX_REPORT_WORKTREE_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
                    _canonical_common=$(git -C "$GIT_REPO_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
                    _report_commit=$(inbox_yaml_field_get "$FULL_REPORT" "commit_hash" "" 2>/dev/null || true)
                    _requested_head=$(git -C "$INBOX_REPORT_WORKTREE_ROOT" rev-parse HEAD 2>/dev/null || true)
                    if [ -z "$_requested_root" ] || [ "$_requested_root" != "$INBOX_REPORT_WORKTREE_ROOT" ] \
                        || [ -z "$_canonical_root" ] || [ "$_requested_common" != "$_canonical_common" ] \
                        || ! [[ "$_report_commit" =~ ^[0-9a-fA-F]{40}$ ]] || [ "$_report_commit" != "$_requested_head" ]; then
                        echo "[git_uncommitted_gate] BLOCKED: invalid linked worktree root or report commit mismatch (ninja: ${FROM})" >&2
                        exit 1
                    fi
                    GIT_REPO_DIR="$_requested_root"
                    echo "[git_uncommitted_gate] verified linked worktree root: $GIT_REPO_DIR" >&2
                fi
                _filtered_check_paths=()
                while IFS= read -r _candidate_path; do
                    [ -n "$_candidate_path" ] || continue
                    # Directory target_path (e.g. scripts/, projects/) is too broad for
                    # report completion gating. It can include unrelated concurrent work.
                    # Concrete files from files_modified remain checked above.
                    if [ -d "$GIT_REPO_DIR/$_candidate_path" ]; then
                        echo "[git_uncommitted_gate] SKIP directory target_path: $_candidate_path" >&2
                        continue
                    fi
                    _filtered_check_paths+=("$_candidate_path")
                done <<< "$GIT_CHECK_PATHS"
                if [ "${#_filtered_check_paths[@]}" -eq 0 ]; then
                    UNCOMMITTED=""
                else
                    UNCOMMITTED=$(inbox_status_against_head "$GIT_REPO_DIR" "${_filtered_check_paths[@]}" 2>/dev/null || true)
                fi
                # cmd_karo_hotfix_shared_dirty_commit_gate_202607101643 (AC1/AC2):
                # 報告者自身の変更が commit_hash として commit 済みなら、同一ファイル内に残る
                # 他忍者の非重複(non-overlapping)WIP hunkだけで誤BLOCKしない。
                # 報告者自身の未commit hunkが commit 済み範囲と重なる場合は従来通りBLOCKする。
                if [ -n "$UNCOMMITTED" ] && [ -n "$FULL_REPORT" ] && [ -f "$FULL_REPORT" ]; then
                    ensure_dirty_hunk_filter_loaded
                    if type filter_report_commit_nonoverlap_uncommitted >/dev/null 2>&1; then
                        _dirty_plain_paths=$(printf '%s\n' "$UNCOMMITTED" | cut -c4-)
                        _dirty_kept_paths=$(filter_report_commit_nonoverlap_uncommitted "$GIT_REPO_DIR" "$FULL_REPORT" "$_dirty_plain_paths")
                        if [ -z "$_dirty_kept_paths" ]; then
                            UNCOMMITTED=""
                        else
                            UNCOMMITTED=$(printf '%s\n' "$UNCOMMITTED" | awk -v kept="$_dirty_kept_paths" '
                                BEGIN {
                                    n = split(kept, arr, "\n")
                                    for (i = 1; i <= n; i++) keep[arr[i]] = 1
                                }
                                { path = substr($0, 4); if (path in keep) print }
                            ')
                        fi
                    fi
                fi
                if [ -n "$UNCOMMITTED" ]; then
                    echo "[git_uncommitted_gate] BLOCKED: 未commitファイルあり (ninja: ${FROM})" >&2
                    while IFS= read -r _uline; do
                        echo "  $_uline" >&2
                    done <<< "$UNCOMMITTED"
                    echo "[git_uncommitted_gate] git add + git commitを実行してから報告せよ" >&2
                    exit 1
                fi
            fi
        fi
    fi
fi

# Atomic write with flock (3 retries)
attempt=0
max_attempts=3

# cmd_inbox_write_speed: メッセージブロック構築をflockサブシェル外に移動(ネストサブシェル削減)
# MSG_ID/TIMESTAMPはflockループ前に確定済み。リトライ時も同一メッセージを再送するため安全。
MESSAGE_READ_STATE="false"
INBOX_COMPLETED_DUPLICATE=0
INBOX_AUTO_READ_COMPLETED_CMD=""
# The auto-read decision is deliberately deferred until after the structured
# identity block below: it must key off the report's own parent_cmd, which is
# only known once the report YAML has been resolved.
STRUCTURED_PARENT_CMD_FROM_YAML=""

_identity_fields=()
STRUCTURED_REPORT_FINGERPRINT=""
STRUCTURED_REVISION_FINGERPRINT=""
case "$TYPE" in
    task_assigned)
        if [ "$TARGET" = "karo" ] && inbox_karo_message_requires_identity "$TYPE"; then
            _identity_fields=(task_id "$COMMANDER_DIRECTIVE_TASK_ID" subject_task_id "$COMMANDER_DIRECTIVE_SUBJECT_TASK_ID" parent_cmd "$COMMANDER_DIRECTIVE_PARENT_CMD")
        else
            # Bind assignment identity from the destination task only.  In
            # particular, never copy report_id/task_id from sender prose or a
            # report notification into this deployment event.
            mapfile -t _assignment_values < <(inbox_task_assignment_identity_fields "$TARGET")
            _identity_fields=(task_id "${_assignment_values[0]:-}" parent_cmd "${_assignment_values[1]:-}")
        fi
        ;;
    report_received|report_submitted|task_done|report_completed|report_done|report_ready|task_failed)
        if [ -z "${STRUCTURED_REPORT_ID:-}" ]; then
            _structured_candidate=$(inbox_extract_report_path_from_content "$CONTENT")
            if [ -z "$_structured_candidate" ] && [ -n "${FULL_REPORT:-}" ] && [ -f "$FULL_REPORT" ]; then
                _structured_candidate="$FULL_REPORT"
                _REPORT_IDENTITY=$(inbox_resolve_report_identity "$_structured_candidate" "${TASK_YAML:-}") || exit 1
                IFS=$'\t' read -r STRUCTURED_REPORT_ID STRUCTURED_REPORT_VERSION STRUCTURED_REPORT_PATH <<< "$_REPORT_IDENTITY"
                STRUCTURED_TASK_ID=$(inbox_yaml_field_get "$_structured_candidate" "task_id" "")
                STRUCTURED_PARENT_CMD=$(inbox_yaml_field_get "$_structured_candidate" "parent_cmd" "")
                STRUCTURED_PARENT_CMD_FROM_YAML="$STRUCTURED_PARENT_CMD"
            fi
            [ -n "$_structured_candidate" ] || { echo "BLOCK: report notification missing structured report identity" >&2; exit 1; }
            if [ -z "${STRUCTURED_REPORT_ID:-}" ]; then
                _REPORT_IDENTITY=$(python3 "$SCRIPT_DIR/scripts/lib/report_unique_identity.py" fallback --path "$_structured_candidate" --root "$SCRIPT_DIR") || exit 1
                IFS=$'\t' read -r STRUCTURED_REPORT_ID STRUCTURED_REPORT_VERSION STRUCTURED_REPORT_PATH <<< "$_REPORT_IDENTITY"
                # The report file is in hand here, so its own task_id/parent_cmd
                # are the identity.  This used to grep the first cmd_id out of
                # the message body, which stamped a *mentioned* cmd onto the
                # delivered message and onto the review child spawned from it.
                STRUCTURED_TASK_ID=$(inbox_yaml_field_get "$_structured_candidate" "task_id" "")
                STRUCTURED_PARENT_CMD=$(inbox_yaml_field_get "$_structured_candidate" "parent_cmd" "")
                STRUCTURED_PARENT_CMD_FROM_YAML="$STRUCTURED_PARENT_CMD"
            fi
        fi
        if [ -z "${_structured_candidate:-}" ]; then
            _structured_candidate="$STRUCTURED_REPORT_PATH"
            [[ "$_structured_candidate" = /* ]] || _structured_candidate="$SCRIPT_DIR/$_structured_candidate"
        fi
        STRUCTURED_REPORT_FINGERPRINT=$(inbox_report_fingerprint "$_structured_candidate" "$STRUCTURED_REPORT_ID:$STRUCTURED_REPORT_VERSION") || exit 1
        _identity_fields=(report_id "$STRUCTURED_REPORT_ID" report_identity_version "$STRUCTURED_REPORT_VERSION" report_fingerprint "$STRUCTURED_REPORT_FINGERPRINT" report_path "$STRUCTURED_REPORT_PATH" task_id "$STRUCTURED_TASK_ID" parent_cmd "$STRUCTURED_PARENT_CMD")
        ;;
    review_report|accept_report|run_cmd_complete)
        _identity_fields=(task_id "$REVIEW_PENDING_NUDGE_TASK_ID" subject_task_id "$REVIEW_PENDING_NUDGE_SUBJECT_TASK_ID" parent_cmd "$REVIEW_PENDING_NUDGE_PARENT_CMD" report_fingerprint "$REVIEW_PENDING_NUDGE_FINGERPRINT" report "$REVIEW_PENDING_NUDGE_REPORT" review_pending_state "$REVIEW_PENDING_NUDGE_STATE")
        ;;
    task_supplement)
        # Only ninja destinations have a current task binding. Karo-directed
        # task_supplement messages use the commander identity gate above and
        # retain that established control-plane contract.
        if target_is_ninja "$TARGET"; then
            _supplement_identity=$(inbox_task_supplement_identity "$TARGET" "$CONTENT") || exit 2
            mapfile -t _supplement_values <<< "$_supplement_identity"
            _identity_fields=(task_id "${_supplement_values[0]:-}" parent_cmd "${_supplement_values[1]:-}")
        fi
        ;;
    report_review|report_review_result|report_revision)
        _structured_candidate=$(inbox_extract_report_path_from_content "$CONTENT")
        if [ -z "$_structured_candidate" ] && [ "$TYPE" = "report_revision" ] && [ -f "$SCRIPT_DIR/queue/tasks/${TARGET}.yaml" ]; then
            _revision_rel=$(inbox_yaml_field_get "$SCRIPT_DIR/queue/tasks/${TARGET}.yaml" "report_path" "")
            [ -n "$_revision_rel" ] && _structured_candidate="$SCRIPT_DIR/$_revision_rel"
        fi
        if [ -n "$_structured_candidate" ] && [ -f "$_structured_candidate" ]; then
            _REPORT_IDENTITY=$(inbox_resolve_report_identity "$_structured_candidate") || exit 1
            IFS=$'\t' read -r STRUCTURED_REPORT_ID STRUCTURED_REPORT_VERSION STRUCTURED_REPORT_PATH <<< "$_REPORT_IDENTITY"
            STRUCTURED_TASK_ID=$(inbox_yaml_field_get "$_structured_candidate" "task_id" "")
            STRUCTURED_PARENT_CMD=$(inbox_yaml_field_get "$_structured_candidate" "parent_cmd" "")
            STRUCTURED_PARENT_CMD_FROM_YAML="$STRUCTURED_PARENT_CMD"
            STRUCTURED_REPORT_FINGERPRINT=$(inbox_report_fingerprint "$_structured_candidate" "$STRUCTURED_REPORT_ID:$STRUCTURED_REPORT_VERSION") || exit 1
            STRUCTURED_REVISION_FINGERPRINT=$(inbox_report_revision_fingerprint "$TYPE" "$ACTION" "$CONTENT")
            _identity_fields=(report_id "$STRUCTURED_REPORT_ID" report_identity_version "$STRUCTURED_REPORT_VERSION" report_fingerprint "$STRUCTURED_REPORT_FINGERPRINT" revision_request_fingerprint "$STRUCTURED_REVISION_FINGERPRINT" report_path "$STRUCTURED_REPORT_PATH" task_id "$STRUCTURED_TASK_ID" parent_cmd "$STRUCTURED_PARENT_CMD")
        else
            # A review message without a resolvable report may still carry an
            # explicit commander envelope. Keep that identity structured;
            # otherwise the post-case validator below rejects the taskless
            # message before it can enter the mailbox.
            _fallback_identity=$(inbox_commander_directive_identity "$CONTENT" 2>/dev/null || true)
            if [ -n "$_fallback_identity" ]; then
                mapfile -t _fallback_values <<< "$_fallback_identity"
                _identity_fields=(task_id "${_fallback_values[0]:-}" subject_task_id "${_fallback_values[1]:-}" parent_cmd "${_fallback_values[2]:-}")
            fi
        fi
        ;;
    investigation_result)
        # This lane has its own evidence contract rather than a commander
        # envelope. Preserve every validated identity field structurally so
        # consumers never need to parse the free-form content again.
        for _investigation_field in task_id check_id occurred_at evidence impact; do
            _investigation_value=$(printf '%s\n' "$CONTENT" | sed -n "s/.*${_investigation_field}=\\([^[:space:]]\\+\\).*/\\1/p" | head -1)
            _identity_fields+=("$_investigation_field" "$_investigation_value")
        done
        ;;
    *)
        if [ "$TARGET" = "karo" ] && inbox_karo_message_requires_identity "$TYPE"; then
            _identity_fields=(task_id "$COMMANDER_DIRECTIVE_TASK_ID" subject_task_id "$COMMANDER_DIRECTIVE_SUBJECT_TASK_ID" parent_cmd "$COMMANDER_DIRECTIVE_PARENT_CMD")
        fi
        ;;
esac

# Dedicated generators must not silently fall back to a taskless durable row
# when their case branch could not resolve a report/task identity. Validate
# the constructed structure after all case handling and before persistence.
if [ "$TARGET" = "karo" ]; then
    case "$TYPE" in
        review_report|accept_report|run_cmd_complete|report_review|report_review_result|report_revision)
            _dedicated_task_id=""
            for ((_identity_i=0; _identity_i<${#_identity_fields[@]}; _identity_i+=2)); do
                if [ "${_identity_fields[_identity_i]}" = "task_id" ]; then
                    _dedicated_task_id="${_identity_fields[_identity_i+1]:-}"
                    break
                fi
            done
            if [ -z "$_dedicated_task_id" ]; then
                echo "BLOCK: ${TYPE} dedicated identity resolved no non-empty task_id; report/task identity is required before persistence" >&2
                exit 2
            fi
            ;;
    esac
fi

# Duplicate-notification suppression, decided on structure alone.
# Order of structural sources, strongest first:
#   1. parent_cmd read out of the referenced report YAML
#   2. the cmd_id encoded in the explicitly supplied report *path*
#      (<ninja>_report_<cmd_id>.yaml) when that file is not readable
# Neither is a prose match: both come from the report reference the sender
# supplied, never from a cmd_id merely mentioned in the message text.  If
# neither yields a cmd_id the message fails closed and is delivered unread.
_autoread_cmd="$STRUCTURED_PARENT_CMD_FROM_YAML"
if [ -z "$_autoread_cmd" ] && [ -n "${STRUCTURED_REPORT_PATH:-}" ]; then
    _autoread_cmd=$(inbox_cmd_id_from_report_filename "$STRUCTURED_REPORT_PATH")
fi
if inbox_should_auto_read_completed_notification \
        "$TARGET" "$TYPE" "$_autoread_cmd" "$FROM"; then
    MESSAGE_READ_STATE="true"
    INBOX_COMPLETED_DUPLICATE=1
    echo "[inbox_write] auto-read completed notification: target=${TARGET} type=${TYPE} cmd=${INBOX_AUTO_READ_COMPLETED_CMD}" >&2
fi

# Infrastructure-bug findings are answers to an exact retrospective prompt.
# Persist the identity structurally; ambiguous/no-hold cases fail closed.
# 忍者が同じretro回答をinfra_bug_suspected/infra_bug_report/infra_bug/retro_answerの
# どれで送るかは実データ上ばらついており(実測: 各48/43/29/78件)、送信側がtypeを1つに
# 決め打ちしていたためinfra_bug_report・infra_bugの72件は一度もevent_idを持てず、
# 判定側(retro_write.sh final-checkpoint)の突合に乗らなかった。回答族を1つの集合として
# 扱う。★この集合は scripts/retro_write.sh の受理集合と同一でなければならない
# (tests/unit/test_retro_answer_type_parity.bats が両者の一致を強制する)。
inbox_is_retro_answer_type() {
    case "$1" in
        infra_bug_suspected|infra_bug_report|infra_bug|retro_answer) return 0 ;;
        *) return 1 ;;
    esac
}
if inbox_is_retro_answer_type "$TYPE"; then
    _retro_event_id="${RETRO_EVENT_ID:-}"
    # 回答本文が event_id=<id> を名乗っている場合、それは送信者が明示した識別子であり
    # 保留イベントが複数でも曖昧ではない。既存のretro_answer運用(本文にevent_idを書き、
    # 判定側が本文突合で拾う形)を壊さないため、本文由来IDは fail-closed の対象にせず
    # 構造化フィールドへ写すだけにする。厳密照合を課すのは明示のRETRO_EVENT_IDのみ。
    _retro_content_event_id=""
    if [ -z "$_retro_event_id" ]; then
        _retro_content_event_id=$(printf '%s' "$CONTENT" | grep -oE 'event_id=[^[:space:]]+' | head -1 | cut -d= -f2- || true)
    fi
    _retro_matches=()
    for _retro_hold in "$SCRIPT_DIR"/queue/retro/verbatim_awaiting_answer/*.event; do
        [ -f "$_retro_hold" ] || continue
        if [ "$(sed -n '1p' "$_retro_hold")" = "$FROM" ]; then
            _retro_matches+=("$(sed -n '2p' "$_retro_hold")")
        fi
    done
    if [ -n "$_retro_event_id" ]; then
        _retro_exact=0
        for _retro_candidate in "${_retro_matches[@]}"; do
            [ "$_retro_candidate" = "$_retro_event_id" ] && _retro_exact=$((_retro_exact + 1))
        done
        if [ "$_retro_exact" -ne 1 ]; then
            echo "[retro_answer_identity] BLOCKED: RETRO_EVENT_ID does not identify exactly one awaiting event for ${FROM}" >&2
            exit 2
        fi
    elif [ -n "$_retro_content_event_id" ]; then
        _retro_event_id="$_retro_content_event_id"
    elif [ "${#_retro_matches[@]}" -eq 1 ]; then
        _retro_event_id="${_retro_matches[0]}"
    elif [ "${#_retro_matches[@]}" -gt 1 ]; then
        echo "[retro_answer_identity] BLOCKED: ambiguous awaiting events for ${FROM}: ${#_retro_matches[@]}" >&2
        exit 2
    fi
    [ -z "$_retro_event_id" ] || _identity_fields+=(event_id "$_retro_event_id")
fi

if [ -n "$ACTION" ]; then
    _msg_block="$(inbox_build_message_block \
        action "$ACTION" \
        content "$CONTENT" \
        from "$FROM" \
        id "$MSG_ID" \
        read "$MESSAGE_READ_STATE" \
        timestamp "$TIMESTAMP" \
        type "$TYPE" "${_identity_fields[@]}")"$'\n'
else
    _msg_block="$(inbox_build_message_block \
        content "$CONTENT" \
        from "$FROM" \
        id "$MSG_ID" \
        read "$MESSAGE_READ_STATE" \
        timestamp "$TIMESTAMP" \
        type "$TYPE" "${_identity_fields[@]}")"$'\n'
fi

while [ $attempt -lt $max_attempts ]; do
    _persist_rc=0
    _persist_started_us="${EPOCHREALTIME/./}"
    (
        flock -w 5 200 || exit 1

        # Report/retro prechecks above can be slow enough for a prompt to become
        # visible after the first identity scan.  Resolve again at the durable
        # append checkpoint so a 0 -> 1 live transition cannot persist an
        # unbound answer (the 12:57 prompt / 12:59 answer incident).
        if inbox_is_retro_answer_type "$TYPE"; then
            _retro_event_id="${RETRO_EVENT_ID:-}"
            _retro_content_event_id=""
            if [ -z "$_retro_event_id" ]; then
                _retro_content_event_id=$(printf '%s' "$CONTENT" | grep -oE 'event_id=[^[:space:]]+' | head -1 | cut -d= -f2- || true)
            fi
            _retro_matches=()
            for _retro_hold in "$SCRIPT_DIR"/queue/retro/verbatim_awaiting_answer/*.event; do
                [ -f "$_retro_hold" ] || continue
                if [ "$(sed -n '1p' "$_retro_hold")" = "$FROM" ]; then
                    _retro_matches+=("$(sed -n '2p' "$_retro_hold")")
                fi
            done
            if [ -n "$_retro_event_id" ]; then
                _retro_exact=0
                for _retro_candidate in "${_retro_matches[@]}"; do
                    [ "$_retro_candidate" = "$_retro_event_id" ] && _retro_exact=$((_retro_exact + 1))
                done
                if [ "$_retro_exact" -ne 1 ]; then
                    echo "[retro_answer_identity] BLOCKED: RETRO_EVENT_ID does not identify exactly one awaiting event for ${FROM}" >&2
                    exit 2
                fi
            elif [ -n "$_retro_content_event_id" ]; then
                _retro_event_id="$_retro_content_event_id"
            elif [ "${#_retro_matches[@]}" -eq 1 ]; then
                _retro_event_id="${_retro_matches[0]}"
            elif [ "${#_retro_matches[@]}" -gt 1 ]; then
                echo "[retro_answer_identity] BLOCKED: ambiguous awaiting events for ${FROM}: ${#_retro_matches[@]}" >&2
                exit 2
            fi
            _locked_identity_fields=("${_identity_fields[@]}")
            if [ -n "$_retro_event_id" ]; then
                # Drop a stale pre-lock identity before appending the live one.
                _locked_identity_fields=()
                for ((_i=0; _i<${#_identity_fields[@]}; _i+=2)); do
                    [ "${_identity_fields[_i]}" = "event_id" ] || _locked_identity_fields+=("${_identity_fields[_i]}" "${_identity_fields[_i+1]}")
                done
                _locked_identity_fields+=(event_id "$_retro_event_id")
            fi
            if [ -n "$ACTION" ]; then
                _msg_block="$(inbox_build_message_block action "$ACTION" content "$CONTENT" from "$FROM" id "$MSG_ID" read "$MESSAGE_READ_STATE" timestamp "$TIMESTAMP" type "$TYPE" "${_locked_identity_fields[@]}")"$'\n'
            else
                _msg_block="$(inbox_build_message_block content "$CONTENT" from "$FROM" id "$MSG_ID" read "$MESSAGE_READ_STATE" timestamp "$TIMESTAMP" type "$TYPE" "${_locked_identity_fields[@]}")"$'\n'
            fi
        fi

        # Initialize inbox under the same flock that protects message append.
        if [ ! -f "$INBOX" ]; then
            printf 'messages: []\n' > "$INBOX"
        fi

        if inbox_type_is_review_pending_nudge "$TYPE"; then
            if inbox_review_pending_duplicate_locked "$INBOX" "$FROM" \
                "$REVIEW_PENDING_NUDGE_TASK_ID" "$REVIEW_PENDING_NUDGE_SUBJECT_TASK_ID" \
                "$REVIEW_PENDING_NUDGE_PARENT_CMD" "$REVIEW_PENDING_NUDGE_FINGERPRINT" \
                "$REVIEW_PENDING_NUDGE_STATE"; then
                exit 20
            fi
        elif inbox_type_is_report_lifecycle "$TYPE" && [ -n "${STRUCTURED_REPORT_ID:-}" ]; then
            _existing_event_id=$(inbox_report_event_duplicate_locked "$INBOX" "$TARGET" "$TYPE" "$FROM" "$STRUCTURED_REPORT_ID" "$STRUCTURED_REPORT_VERSION" "$STRUCTURED_REPORT_FINGERPRINT" "$STRUCTURED_REVISION_FINGERPRINT") || _existing_event_id=""
            if [ -n "$_existing_event_id" ]; then
                printf 'DUPLICATE_MSG_ID=%s\n' "$_existing_event_id"
                exit 20
            fi
        elif inbox_pending_duplicate_locked "$INBOX" "$FROM" "$CONTENT"; then
            exit 20
        fi
        inbox_append_message_locked "$INBOX" "$_msg_block" || exit 1

    ) 200>"$LOCKFILE" || _persist_rc=$?
    iw_record_timing inbox_write_persist "$_persist_started_us" \
        "$([ "$_persist_rc" -eq 0 ] || [ "$_persist_rc" -eq 20 ] && printf PASS || printf BLOCK)"
    if [ "$_persist_rc" -eq 20 ]; then
        echo "[inbox_write] pending duplicate suppressed: target=${TARGET} from=${FROM}" >&2
        exit 0
    elif [ "$_persist_rc" -eq 0 ]; then
        # Success — inbox message persisted
        if [ "${INBOX_WRITE_SYNC_MEMORY_DB:-0}" = "1" ] || [[ "$SCRIPT_DIR" != /mnt/c/* && "$SCRIPT_DIR" != /mnt/d/* ]]; then
            if ! record_inbox_event_to_memory_db 2>/dev/null; then
                echo "[inbox_write] WARN: memory DB inbox insert failed (non-fatal; inbox persisted)" >&2
            fi
        else
            record_inbox_event_to_memory_db >/dev/null 2>&1 &
        fi

        # A ninja completion and its Gunshi review are separate actionable
        # events. Keep the durable parent unread so Karo sees the report arrival
        # immediately and can prepare in parallel with review. The former
        # auto-ack hid the parent until the review result arrived (92s observed).
        # If child persistence fails the parent also remains visible/retryable.
        INBOX_REVIEW_CHILD_DELIVERED=0
        if [ "$TARGET" = "karo" ] && inbox_type_triggers_report_completion "$TYPE" \
           && [ -n "${_structured_candidate:-}" ] && [ -f "$_structured_candidate" ] \
           && [ -n "${STRUCTURED_PARENT_CMD:-}" ]; then
            if inbox_deliver_report_review_generation "$FROM" "$_structured_candidate" \
                "$STRUCTURED_PARENT_CMD" "$STRUCTURED_REPORT_FINGERPRINT"; then
                INBOX_REVIEW_CHILD_DELIVERED=1
            else
                echo "[inbox_write] WARN: review child persistence failed; parent remains unread: id=$MSG_ID" >&2
            fi
        fi

        # Review delivery is a child event of the durable report event, not an
        # auto-done side effect. Completed/auto-read parents must still create
        # (or repair) the fingerprint-specific child review exactly once.
        if [ "$INBOX_REVIEW_CHILD_DELIVERED" -eq 0 ] && [ "$TYPE" = "report_received" ] && [ -n "${_structured_candidate:-}" ] \
           && [ -f "$_structured_candidate" ] && [ -n "${STRUCTURED_PARENT_CMD:-}" ]; then
            ( inbox_deliver_report_review_generation "$FROM" "$_structured_candidate" "$STRUCTURED_PARENT_CMD" "$STRUCTURED_REPORT_FINGERPRINT" ) \
                </dev/null >/dev/null 2>&1 &
        fi

        # Hook: canonical report-completion types from ninja → auto-update task YAML to done
        if [ "$INBOX_COMPLETED_DUPLICATE" -eq 0 ] && inbox_type_triggers_report_completion "$TYPE"; then
            ensure_agent_config_loaded
            is_ninja=0
            for ninja in $NINJA_NAMES; do
                if [ "$FROM" = "$ninja" ]; then
                    is_ninja=1
                    break
                fi
            done

            if [ "$is_ninja" -eq 1 ]; then
                TASK_YAML="$SCRIPT_DIR/queue/tasks/${FROM}.yaml"
                if [ -f "$TASK_YAML" ]; then
                    # Report YAML existence verification before done transition (cmd_813)
                    REPORT_FILENAME=$(inbox_yaml_field_get "$TASK_YAML" "report_filename" "")
                    if [ -z "$REPORT_FILENAME" ]; then
                        _parent_cmd=$(inbox_yaml_field_get "$TASK_YAML" "parent_cmd" "")
                        if [ -n "$_parent_cmd" ]; then
                            REPORT_FILENAME="${FROM}_report_${_parent_cmd}.yaml"
                        fi
                    fi

                    report_found=0
                    REPORT_FULL_PATH=""
                    if [ -n "$REPORT_FILENAME" ]; then
                        if [ -f "$SCRIPT_DIR/queue/reports/$REPORT_FILENAME" ]; then
                            report_found=1
                            REPORT_FULL_PATH="$SCRIPT_DIR/queue/reports/$REPORT_FILENAME"
                        elif [ -f "$SCRIPT_DIR/queue/archive/reports/$REPORT_FILENAME" ]; then
                            report_found=1
                            REPORT_FULL_PATH="$SCRIPT_DIR/queue/archive/reports/$REPORT_FILENAME"
                        else
                            # Archive files may have date suffix
                            base="${REPORT_FILENAME%.yaml}"
                            shopt -s nullglob
                            archived=("$SCRIPT_DIR/queue/archive/reports/${base}"_*.yaml)
                            shopt -u nullglob
                            if [ "${#archived[@]}" -gt 0 ]; then
                                report_found=1
                                REPORT_FULL_PATH="${archived[0]}"
                            fi
                        fi
                    fi

                    if [ "$report_found" -eq 0 ]; then
                        echo "[inbox_write] auto-done BLOCKED: report YAML not found: ${REPORT_FILENAME:-unknown} (ninja: $FROM)" >&2
                    else
                        # cmd_4163: 報告YAML自身のparent_cmdを一次とする(LS078)。
                        # task YAMLは配備差替え後の再送/リトライ経路のfallbackのみ
                        _parent_cmd=$(inbox_yaml_field_get "$REPORT_FULL_PATH" "parent_cmd" "")
                        [ -n "$_parent_cmd" ] || _parent_cmd=$(inbox_yaml_field_get "$TASK_YAML" "parent_cmd" "")
                        if [ "${INBOX_REVIEW_CHILD_DELIVERED:-0}" -eq 0 ] && [ -n "$_parent_cmd" ] && [ -n "$REPORT_FULL_PATH" ] && [ -f "$REPORT_FULL_PATH" ] && [ -f "$SCRIPT_DIR/scripts/lib/gunshi_notify.sh" ]; then
                            # shellcheck disable=SC2034  # PROJECT_ROOT is used by sourced gunshi_notify.sh
                            PROJECT_ROOT="$SCRIPT_DIR"
                            # shellcheck source=/dev/null
                            # Persistence is already durable. Child review uses
                            # the same report fingerprint key, so retries repair
                            # a missing child and suppress an existing child.
                            ( inbox_deliver_report_review_generation "$FROM" "$REPORT_FULL_PATH" "$_parent_cmd" "$STRUCTURED_REPORT_FINGERPRINT" ) \
                                </dev/null >/dev/null 2>&1 &
                        fi

                        # Check current status — don't overwrite terminal states
                        CURRENT_STATUS=$(inbox_yaml_field_get "$TASK_YAML" "status" "")
                        case "$CURRENT_STATUS" in
                            done|failed|blocked) ;;
                            *)
                                # yaml_field_set.sh has its own flock on ${yaml_file}.lock.
                                # Outer flock on same lockfile via different fd = self-deadlock
                                # on WSL2/DrvFs (POSIX flock treats different open file descriptions
                                # independently; same-process exclusive vs exclusive = blocked).
                                # statusだけを先にdoneへ変えると、ninja_monitorは
                                # done taskを早期returnし、done_at/completed_atを永久に
                                # 記録できない。3フィールドを同一flock・同一atomic publishで
                                # 更新し、E2E throughputのterminal境界を欠損させない。
                                _auto_done_ts=$(date '+%Y-%m-%dT%H:%M:%S')
                                _auto_done_done_at=$(inbox_yaml_field_get "$TASK_YAML" "done_at" "")
                                _auto_done_completed_at=$(inbox_yaml_field_get "$TASK_YAML" "completed_at" "")
                                _auto_done_updates=("status=done")
                                [ -n "$_auto_done_done_at" ] || _auto_done_updates+=("done_at=$_auto_done_ts")
                                [ -n "$_auto_done_completed_at" ] || _auto_done_updates+=("completed_at=$_auto_done_ts")
                                if ! (
                                    # shellcheck source=/dev/null
                                    source "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
                                    yaml_field_set_batch "$TASK_YAML" task "${_auto_done_updates[@]}"
                                ) 2>/dev/null; then
                                    echo "[inbox_write] auto-done: task status/timestamp更新失敗（非致命的。メッセージ送信は成功済み）" >&2
                                fi
                                ;;
                        esac
                    fi
                fi
            fi
        fi

        # Review notifications are persistence-only. Fingerprints are bound at
        # review time by scripts/review_approval.sh, never on delayed delivery.

        # 重複report_review防止: type=report_review to=gunshi 時にgunshi_notify.shと同じフラグを書く
        # gunshi_notify.sh(cmd_complete_gate.sh経由)が後から発火しても重複送信しない
        if [ "$TYPE" = "report_review" ] && [ "$TARGET" = "gunshi" ]; then
            _dr_cmd_id=$(echo "$CONTENT" | grep -oP 'cmd_\w+' | head -1 || true)
            _dr_ninja_pattern="$(get_ninja_names 2>/dev/null | sed 's/ /|/g')"
            if [ -n "$_dr_ninja_pattern" ]; then
                _dr_ninja=$(echo "$CONTENT" | grep -oP "\b(${_dr_ninja_pattern})\b" | head -1 || true)
            else
                _dr_ninja=""
            fi
            if [ -n "$_dr_cmd_id" ] && [ -n "$_dr_ninja" ]; then
                _dr_gates_dir="$SCRIPT_DIR/queue/gates/${_dr_cmd_id}"
                mkdir -p "$_dr_gates_dir"
                _dr_flag="${_dr_gates_dir}/gunshi_report_review_notify_${_dr_ninja}.done"
                if [ ! -f "$_dr_flag" ]; then
                    echo "timestamp: $(date +%Y-%m-%dT%H:%M:%S)" > "$_dr_flag"
                    echo "ninja: ${_dr_ninja}" >> "$_dr_flag"
                    echo "source: inbox_write_dedup" >> "$_dr_flag"
                fi
            fi
        fi

        # 軍師review_resultのみ、配備中忍者へ補足として自動forwardする
        # task_supplement/review_feedback 等の二次通知はforwardしない（再帰ループ防止）
        if [ "$TYPE" = "review_result" ] && [ "$FROM" = "gunshi" ] && [ "$TARGET" = "karo" ]; then
            forward_gunshi_review_result_to_active_ninjas "$CONTENT"
        fi

        # 忍者report_received後の振り返り自動トリガー(殿裁定2026-07-18: 分離原則)
        if [ "$TYPE" = "report_received" ] && [ "$TARGET" = "karo" ]; then
            _ninja_names_retro=$(get_ninja_names 2>/dev/null || true)
            for _rn in $_ninja_names_retro; do
                if [ "$FROM" = "$_rn" ]; then
                    _retro_dir="$SCRIPT_DIR/queue/retro"
                    mkdir -p "$_retro_dir"
                    if [ -f "$SCRIPT_DIR/scripts/retro_write.sh" ]; then
                        bash "$SCRIPT_DIR/scripts/retro_write.sh" enqueue-trigger \
                            "$FROM" "$MSG_ID" "$(date -Iseconds)" normal
                    elif [ "${INBOX_WRITE_TEST:-}" != "1" ]; then
                        echo "BLOCK: retro_write.sh missing; refusing unmanaged retro trigger" >&2
                        exit 2
                    fi
                    break
                fi
            done
            # Queue the exact prompt. ninja_monitor delivers only after proving
            # pane idle while holding the same per-ninja lock as deployment.
            source "$SCRIPT_DIR/scripts/lib/retro_verbatim_prompt.sh"
            retro_verbatim_prompt_enqueue "$SCRIPT_DIR" "$FROM" "report_received:$MSG_ID" inbox_write
        fi

        # Failure/BLOCK terminals enqueue only. Delivery waits for the monitor
        # to prove pane-idle and no next task, avoiding prompt/task overlap.
        if [ "$TYPE" = "task_failed" ] && [ "$TARGET" = "karo" ]; then
            source "$SCRIPT_DIR/scripts/lib/retro_verbatim_prompt.sh"
            _failed_retro_event="task_failed:${STRUCTURED_REPORT_ID}:${STRUCTURED_REPORT_VERSION}:${STRUCTURED_REPORT_FINGERPRINT}"
            retro_verbatim_prompt_enqueue "$SCRIPT_DIR" "$FROM" "$_failed_retro_event" inbox_write
        fi

        # Machine-readable persistence receipt.  Emit only after the inbox row
        # is durably published; watcher verification is a separate consequence.
        printf 'INBOX_MESSAGE_ID=%s\n' "$MSG_ID"
        dispatch_codex_delivery_verification "$TARGET" "$MSG_ID" "$TYPE"
        exit 0
    else
        # Lock timeout or error
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[inbox_write] Lock timeout for $INBOX (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[inbox_write] Failed to acquire lock after $max_attempts attempts for $INBOX (target=$TARGET, from=$FROM)" >&2
            bash "$SCRIPT_DIR/scripts/ntfy.sh" "[inbox_write] FAIL: lock取得失敗 target=$TARGET from=$FROM" 2>/dev/null || true
            exit 1
        fi
    fi
done
# hanzo_test
