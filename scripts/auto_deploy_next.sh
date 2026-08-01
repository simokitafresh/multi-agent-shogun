#!/usr/bin/env bash
# semantic-links: [[インフラ運用基盤]]
# auto_deploy_next.sh — サブタスク完了時の次サブタスク自動配備
# Usage: bash scripts/auto_deploy_next.sh <cmd_id> <completed_subtask_id>
#
# Exit codes:
#   0 — AUTO_DEPLOY_OK: 配備成功 / AUTO_DEPLOY_DONE: 全サブタスク完了
#   1 — 入力エラー or 検証失敗
#   2 — AUTO_DEPLOY_SKIP: auto_deploy=false, 家老の手動判断を待つ
#   3 — AUTO_DEPLOY_BLOCKED: blocked_by未解消 or 全忍者busy or 二重配備ロック

set -euo pipefail

_adn_self="${BASH_SOURCE[0]:-$0}"
[[ "$_adn_self" != /* ]] && _adn_self="$PWD/$_adn_self"
SCRIPT_DIR="${_adn_self%/scripts/auto_deploy_next.sh}"
LOG="$SCRIPT_DIR/logs/auto_deploy.log"
TASKS_DIR="$SCRIPT_DIR/queue/tasks"
REPORTS_DIR="$SCRIPT_DIR/queue/reports"
OWNER_STATE_ROOT="${AUTO_DEPLOY_OWNER_STATE_ROOT:-$SCRIPT_DIR/logs/durable_state/auto_deploy_owner}"
OWNER_SUBJECT_TYPE="task_owner"

CMD_ID="${1:-}"
COMPLETED_SUBTASK_ID="${2:-}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [AUTO_DEPLOY] $1" >> "$LOG"
    echo "[AUTO_DEPLOY] $1" >&2
}

owner_state_field() {
    local json="$1" field="$2"
    python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get(sys.argv[2], ""))' "$json" "$field"
}

owner_failpoint() {
    [ "${AUTO_DEPLOY_FAILPOINT:-}" != "$1" ] || { echo "AUTO_DEPLOY_FAILPOINT: $1" >&2; return 97; }
}

owner_transaction_assert_current() {
    local subject_id="$1" target="$2" fence="$3" payload_hash="$4" expected_phase="$5"
    local record pointer
    record=$(bash "$SCRIPT_DIR/scripts/lib/durable_state.sh" read "$OWNER_STATE_ROOT" "$OWNER_SUBJECT_TYPE" "$subject_id") || return 4
    python3 - "$record" "$subject_id" "$fence" "$payload_hash" "$expected_phase" "$target" <<'PY'
import json, os, sys
r=json.loads(sys.argv[1]); subject,fence,payload,phase,target=sys.argv[2:]
pointer=next((x.split(':',1)[1] for x in r.get('side_effect_ledger',[]) if x.startswith('owner_pointer:')), '')
ok=(r.get('subject_id')==subject and str(r.get('fence_token'))==fence and
    r.get('phase')==phase and r.get('payload_hash')==payload and
    pointer and os.path.realpath(pointer)==os.path.realpath(target))
raise SystemExit(0 if ok else 4)
PY
}

owner_transaction_finish() {
    local subject_id="$1" source="$2" target="$3" fence="$4" payload_hash="$5"
    local yfs="$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
    local lease_owner="owner-finish-${BASHPID}-${fence}"
    bash "$SCRIPT_DIR/scripts/lib/durable_state.sh" lease-acquire "$OWNER_STATE_ROOT" \
        "$OWNER_SUBJECT_TYPE" "$subject_id" "$lease_owner" "${AUTO_DEPLOY_OWNER_LEASE_TTL:-30}" >/dev/null || return $?
    owner_transaction_assert_current "$subject_id" "$target" "$fence" "$payload_hash" prepared || return 4
    [ "${AUTO_DEPLOY_BARRIER_AFTER_ASSERT:-}" = "" ] || {
        printf 'ready\n' > "$AUTO_DEPLOY_BARRIER_AFTER_ASSERT"
        while [ ! -f "${AUTO_DEPLOY_BARRIER_AFTER_ASSERT}.release" ]; do sleep 0.01; done
    }
    owner_failpoint after_pointer_before_tombstone || return $?
    if [ "$(realpath "$source")" != "$(realpath "$target")" ]; then
        bash "$SCRIPT_DIR/scripts/lib/durable_state.sh" guarded-yaml-set "$OWNER_STATE_ROOT" \
            "$OWNER_SUBJECT_TYPE" "$subject_id" "$fence" prepared "$payload_hash" "$target" \
            "$yfs" "$source" task status transferred >/dev/null || return $?
        bash "$SCRIPT_DIR/scripts/lib/durable_state.sh" guarded-yaml-set "$OWNER_STATE_ROOT" \
            "$OWNER_SUBJECT_TYPE" "$subject_id" "$fence" prepared "$payload_hash" "$target" \
            "$yfs" "$source" task owner_transaction_status tombstoned >/dev/null || return $?
    fi
    owner_failpoint after_tombstone_before_activation || return $?
    owner_transaction_assert_current "$subject_id" "$target" "$fence" "$payload_hash" prepared || return 4
    bash "$SCRIPT_DIR/scripts/lib/durable_state.sh" guarded-yaml-set "$OWNER_STATE_ROOT" \
        "$OWNER_SUBJECT_TYPE" "$subject_id" "$fence" prepared "$payload_hash" "$target" \
        "$yfs" "$target" task status assigned >/dev/null || return $?
    bash "$SCRIPT_DIR/scripts/lib/durable_state.sh" guarded-yaml-set "$OWNER_STATE_ROOT" \
        "$OWNER_SUBJECT_TYPE" "$subject_id" "$fence" prepared "$payload_hash" "$target" \
        "$yfs" "$target" task owner_transaction_status active >/dev/null || return $?
    owner_failpoint after_activation_before_published || return $?
    local ledger
    ledger="[\"owner_pointer:$target\",\"source_tombstone:$source\",\"payload:$payload_hash\"]"
    bash "$SCRIPT_DIR/scripts/lib/durable_state.sh" mutate "$OWNER_STATE_ROOT" \
        "$OWNER_SUBJECT_TYPE" "$subject_id" "$fence" published "" "$ledger" >/dev/null
    owner_failpoint after_published_before_terminal || return $?
    bash "$SCRIPT_DIR/scripts/lib/durable_state.sh" reconcile "$OWNER_STATE_ROOT" \
        "$OWNER_SUBJECT_TYPE" "$subject_id" "$lease_owner" "$payload_hash" "$ledger" >/dev/null
}

owner_transaction_reconcile_startup() {
    OWNER_RECONCILED_COUNT=0
    local active_root="$OWNER_STATE_ROOT/active/$OWNER_SUBJECT_TYPE"
    [ -d "$active_root" ] || return 0
    local state record phase subject_id fence payload_hash source target attempt ledger
    while IFS= read -r state; do
        record=$(cat "$state") || continue
        phase=$(owner_state_field "$record" phase)
        case "$phase" in intended|prepared|published) ;; *) continue ;; esac
        subject_id=$(owner_state_field "$record" subject_id)
        fence=$(owner_state_field "$record" fence_token)
        payload_hash=$(owner_state_field "$record" payload_hash)
        attempt=$(owner_state_field "$record" attempt_id)
        source=${attempt%%|*}; target=${attempt#*|}
        [ "$source" != "$target" ] || continue
        if [ "$phase" = intended ]; then
            [ -f "$target" ] || { bash "$SCRIPT_DIR/scripts/lib/durable_state.sh" mutate "$OWNER_STATE_ROOT" "$OWNER_SUBJECT_TYPE" "$subject_id" "$fence" rolled_back >/dev/null; continue; }
            ledger="[\"owner_pointer:$target\",\"source_pending:$source\",\"payload:$payload_hash\"]"
            bash "$SCRIPT_DIR/scripts/lib/durable_state.sh" mutate "$OWNER_STATE_ROOT" "$OWNER_SUBJECT_TYPE" "$subject_id" "$fence" prepared "" "$ledger" >/dev/null
            phase=prepared
        fi
        [ -f "$source" ] && [ -f "$target" ] || continue
        if [ "$phase" = published ]; then
            ledger="[\"owner_pointer:$target\",\"source_tombstone:$source\",\"payload:$payload_hash\"]"
            bash "$SCRIPT_DIR/scripts/lib/durable_state.sh" reconcile "$OWNER_STATE_ROOT" "$OWNER_SUBJECT_TYPE" "$subject_id" "startup-reconciler-$$" "$payload_hash" "$ledger" >/dev/null || return $?
        else
            owner_transaction_finish "$subject_id" "$source" "$target" "$fence" "$payload_hash" || return $?
        fi
        OWNER_RECONCILED_COUNT=$((OWNER_RECONCILED_COUNT + 1))
        log "OWNER_RECONCILED: $subject_id"
    done < <(find "$active_root" -mindepth 2 -maxdepth 2 -name state.json -type f 2>/dev/null)
}

if [ "${1:-}" = --reconcile-owner-transactions ]; then
    mkdir -p "$SCRIPT_DIR/logs"
    owner_transaction_reconcile_startup
    echo "OWNER_RECONCILE_OK: ${OWNER_RECONCILED_COUNT:-0}"
    exit 0
fi

if [ "${1:-}" = --finish-owner-transaction ]; then
    shift
    owner_transaction_finish "$@"
    exit $?
fi

# ═══════════════════════════════════════
# Step 1: Input validation
# ═══════════════════════════════════════

if [ -z "$CMD_ID" ] || [ -z "$COMPLETED_SUBTASK_ID" ]; then
    echo "Usage: auto_deploy_next.sh <cmd_id> <completed_subtask_id>" >&2
    echo "  cmd_id:               cmd_XXX形式の親コマンドID" >&2
    echo "  completed_subtask_id: 完了したサブタスクID" >&2
    exit 1
fi

if [[ "$CMD_ID" != cmd_* ]]; then
    echo "ERROR: cmd_idはcmd_*形式でなければならない (received: $CMD_ID)" >&2
    exit 1
fi

mkdir -p "$SCRIPT_DIR/logs"
owner_transaction_reconcile_startup
if [ "${OWNER_RECONCILED_COUNT:-0}" -gt 0 ]; then
    echo "AUTO_DEPLOY_OK: startup reconciler recovered ${OWNER_RECONCILED_COUNT} owner transaction(s)"
    exit 0
fi

# ═══════════════════════════════════════
# flock: 二重配備防止
# ═══════════════════════════════════════

LOCK_FILE="/tmp/auto_deploy_${CMD_ID}.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    log "LOCK: ${CMD_ID}は別プロセスで処理中"
    echo "AUTO_DEPLOY_BLOCKED: ${CMD_ID}は別プロセスで処理中"
    exit 3
fi

log "Start: cmd=${CMD_ID} completed=${COMPLETED_SUBTASK_ID}"

# ═══════════════════════════════════════
# Step 2-4: Analysis (python3 YAML parsing)
# ═══════════════════════════════════════
# stdout: TAB区切り結果行
# stderr: ログ → $LOG に追記

# ─── grep fast-path: find matching task files before starting Python3 ───
# Avoids Python3 startup + yaml.safe_load for all files when no match exists
MATCHING_FILES=$(grep -l "parent_cmd: ${CMD_ID}" "$TASKS_DIR"/*.yaml 2>/dev/null || true)
if [ -z "$MATCHING_FILES" ]; then
    log "ERROR: no subtasks found for ${CMD_ID} (fast-path)"
    echo "ERROR: no subtasks found for ${CMD_ID}" >&2
    exit 1
fi

ANALYSIS_EXIT=0
ANALYSIS=$(CMD_ID="$CMD_ID" COMPLETED_ID="$COMPLETED_SUBTASK_ID" \
    TASKS_DIR="$TASKS_DIR" REPORTS_DIR="$REPORTS_DIR" \
    MATCHING_FILES="$MATCHING_FILES" \
    python3 -c "
import yaml, sys, os, glob

cmd_id = os.environ['CMD_ID']
completed_id = os.environ['COMPLETED_ID']
tasks_dir = os.environ['TASKS_DIR']
reports_dir = os.environ['REPORTS_DIR']

# ─── Use pre-filtered files from grep fast-path ───
matching_str = os.environ.get('MATCHING_FILES', '')
if matching_str:
    yaml_files = sorted(f for f in matching_str.split('\n') if f and not f.endswith('.lock'))
else:
    yaml_files = sorted(glob.glob(os.path.join(tasks_dir, '*.yaml')))

# ─── Scan matching task YAMLs for parent_cmd ───
raw_subtasks = []
for fpath in yaml_files:
    if fpath.endswith('.lock'):
        continue
    try:
        with open(fpath) as f:
            data = yaml.safe_load(f)
        if not data or 'task' not in data:
            continue
        t = data['task']
        if t.get('parent_cmd') != cmd_id:
            continue
        raw_subtasks.append({
            'task_id': t.get('task_id') or t.get('_ac_task_id') or '',
            'status': str(t.get('status', '')).lower(),
            'blocked_by': t.get('blocked_by', []) or [],
            'auto_deploy': bool(t.get('auto_deploy', False)),
            'assigned_to': t.get('assigned_to', ''),
            'file': fpath,
        })
    except Exception as e:
        print(f'WARN: {os.path.basename(fpath)}: {e}', file=sys.stderr)

if not raw_subtasks:
    print(f'ERROR\tno subtasks found for {cmd_id}')
    sys.exit(1)

# ─── Dedup by task_id (higher status wins) ───
STATUS_RANK = {'done': 4, 'in_progress': 3, 'acknowledged': 2, 'assigned': 1}
seen = {}
for st in raw_subtasks:
    tid = st['task_id']
    if tid in seen:
        if STATUS_RANK.get(st['status'], 0) > STATUS_RANK.get(seen[tid]['status'], 0):
            seen[tid] = st
    else:
        seen[tid] = st
all_subtasks = list(seen.values())

# ─── Validate completed subtask ───
completed_task = seen.get(completed_id)
if not completed_task:
    print(f'ERROR\t{completed_id} not found with parent_cmd={cmd_id}')
    sys.exit(1)

if completed_task['status'] != 'done':
    print(f'ERROR\t{completed_id} status={completed_task[\"status\"]} (expected done)')
    sys.exit(1)

# ─── Report verification (non-blocking) ───
completed_ninja = completed_task['assigned_to']
if completed_ninja:
    rpath = os.path.join(reports_dir, f'{completed_ninja}_report_{cmd_id}.yaml')
    if not os.path.exists(rpath):
        # Fallback: glob for variant naming patterns
        _matches = sorted(glob.glob(os.path.join(reports_dir, f'{completed_ninja}_report*{cmd_id}*.yaml')))
        rpath = _matches[-1] if _matches else rpath
    if os.path.exists(rpath):
        try:
            with open(rpath) as f:
                rdata = yaml.safe_load(f)
            if rdata:
                # L044: 扁平/ネスト混在対応
                r_status = str(rdata.get('status', '')).lower()
                r_pcmd = str(rdata.get('parent_cmd', ''))
                if r_pcmd == cmd_id and r_status in ('done', 'completed', 'success'):
                    print(f'Report verified: {completed_ninja} status={r_status}', file=sys.stderr)
                else:
                    print(f'WARN: report status={r_status} pcmd={r_pcmd}', file=sys.stderr)
        except Exception as e:
            print(f'WARN: report parse: {e}', file=sys.stderr)

# ─── Find next subtask ───
done_ids = set(st['task_id'] for st in all_subtasks if st['status'] == 'done')
SELECTABLE_STATUSES = {'pending', 'idle'}
undone = [st for st in all_subtasks if st['status'] in SELECTABLE_STATUSES]
rejected = [st for st in all_subtasks
            if st['status'] != 'done' and st['status'] not in SELECTABLE_STATUSES]

if not undone:
    if rejected:
        rejected_detail = ','.join(
            '{}:{}'.format(st['task_id'], st['status'] or 'MISSING_STATUS') for st in rejected)
        print(f'REJECTED\t{rejected_detail}')
        sys.exit(0)
    print(f'ALL_DONE\t{cmd_id}\t{len(all_subtasks)}')
    sys.exit(0)

# Find first eligible: blocked_by all resolved
next_st = None
blocked_st = None
for st in undone:
    if all(bid in done_ids for bid in st['blocked_by']):
        next_st = st
        break
    elif blocked_st is None:
        blocked_st = st

if next_st is None:
    if blocked_st:
        unresolved = ','.join(bid for bid in blocked_st['blocked_by'] if bid not in done_ids)
        print(f'BLOCKED\t{blocked_st[\"task_id\"]}\t{unresolved}')
    else:
        print(f'BLOCKED\tunknown\t')
    sys.exit(0)

# ─── auto_deploy flag check ───
if not next_st['auto_deploy']:
    print(f'SKIP\t{next_st[\"task_id\"]}')
    sys.exit(0)

# Ready to deploy
print(f'DEPLOY\t{next_st[\"task_id\"]}\t{next_st[\"assigned_to\"]}\t{next_st[\"file\"]}\t{completed_ninja}')
" 2>> "$LOG") || ANALYSIS_EXIT=$?

if [ "$ANALYSIS_EXIT" -ne 0 ]; then
    DETAIL="${ANALYSIS#ERROR$'\t'}"
    log "ERROR: $DETAIL"
    echo "ERROR: $DETAIL" >&2
    exit 1
fi

ACTION=$(echo "$ANALYSIS" | cut -f1)
log "Analysis result: $ANALYSIS"

case "$ACTION" in
    ALL_DONE)
        echo "AUTO_DEPLOY_DONE: ${CMD_ID}の全サブタスク完了"
        log "AUTO_DEPLOY_DONE: ${CMD_ID}"
        exit 0
        ;;
    BLOCKED)
        NEXT_ID=$(echo "$ANALYSIS" | cut -f2)
        UNRESOLVED=$(echo "$ANALYSIS" | cut -f3)
        echo "AUTO_DEPLOY_BLOCKED: ${NEXT_ID}はblocked_by未解消 (${UNRESOLVED})"
        log "AUTO_DEPLOY_BLOCKED: ${NEXT_ID} unresolved=${UNRESOLVED}"
        exit 3
        ;;
    REJECTED)
        REJECTED_DETAIL=$(echo "$ANALYSIS" | cut -f2)
        echo "AUTO_DEPLOY_BLOCKED: selector rejected non-pending/idle task(s): ${REJECTED_DETAIL}"
        log "AUTO_DEPLOY_BLOCKED: selector rejected ${REJECTED_DETAIL}"
        exit 3
        ;;
    SKIP)
        NEXT_ID=$(echo "$ANALYSIS" | cut -f2)
        echo "AUTO_DEPLOY_SKIP: auto_deploy=false, 家老の手動判断を待つ (${NEXT_ID})"
        log "AUTO_DEPLOY_SKIP: ${NEXT_ID}"
        exit 2
        ;;
    DEPLOY)
        NEXT_ID=$(echo "$ANALYSIS" | cut -f2)
        PRE_ASSIGNED=$(echo "$ANALYSIS" | cut -f3)
        TASK_FILE=$(echo "$ANALYSIS" | cut -f4)
        COMPLETED_NINJA=$(echo "$ANALYSIS" | cut -f5)
        ;;
    *)
        log "ERROR: unexpected analysis output: $ANALYSIS"
        echo "ERROR: analysis failed" >&2
        exit 1
        ;;
esac

# ═══════════════════════════════════════
# Step 5: Ninja selection
# ═══════════════════════════════════════

# CTX% helper (pane_lookup経由で動的解決 — cmd_1136)
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/agent_config.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/pane_lookup.sh"
get_ctx_pct() {
    local name="$1"
    local pane
    pane=$(pane_lookup "$name" 2>/dev/null) || true
    if [[ -z "$pane" ]]; then
        echo "100"
        return
    fi
    local ctx
    ctx=$(tmux show-options -p -t "$pane" -v @context_pct 2>/dev/null | grep -oE '[0-9]+' | tail -1 || true)
    echo "${ctx:-0}"
}

SELECTED_NINJA=""

if [ -n "$PRE_ASSIGNED" ]; then
    # 家老が事前指定済み
    SELECTED_NINJA="$PRE_ASSIGNED"
    log "Ninja selected: ${SELECTED_NINJA} (pre-assigned)"
else
    # Priority 1: 完了忍者に連続配備 (CTX < 50%)
    if [ -n "$COMPLETED_NINJA" ]; then
        CTX=$(get_ctx_pct "$COMPLETED_NINJA")
        if [ "$CTX" -lt 50 ] 2>/dev/null; then
            SELECTED_NINJA="$COMPLETED_NINJA"
            log "Ninja selected: ${SELECTED_NINJA} (completed ninja, CTX=${CTX}%)"
        else
            log "Completed ninja ${COMPLETED_NINJA} CTX=${CTX}% >= 50%, searching idle"
        fi
    fi

    # Priority 2: ninja_states.yamlからidle忍者（cmd_519: round-robin回転順）
    if [ -z "$SELECTED_NINJA" ]; then
        STATES_FILE="$SCRIPT_DIR/logs/ninja_states.yaml"
        RR_POINTER_FILE="$SCRIPT_DIR/queue/rr_pointer.txt"
        if [ -f "$STATES_FILE" ]; then
            IDLE_NINJA=$(STATES_FILE="$STATES_FILE" SCRIPT_DIR="$SCRIPT_DIR" \
                RR_FILE="$RR_POINTER_FILE" python3 -c "
import yaml, sys, os

states_file = os.environ['STATES_FILE']
script_dir = os.environ['SCRIPT_DIR']

# Read ninja names from settings.yaml (cmd_1136)
settings_path = os.path.join(script_dir, 'config', 'settings.yaml')
with open(settings_path) as _sf:
    _sdata = yaml.safe_load(_sf)
NINJA_NAMES = [n for n, c in (_sdata or {}).get('cli', {}).get('agents', {}).items()
               if isinstance(c, dict) and c.get('role') == 'ninja']

rr_file = os.environ.get('RR_FILE', '')
rr_last = ''
if rr_file and os.path.exists(rr_file):
    with open(rr_file) as f:
        rr_last = f.read().strip()

# Build rotated order
rotated = list(NINJA_NAMES)
if rr_last in NINJA_NAMES:
    idx = NINJA_NAMES.index(rr_last)
    rotated = NINJA_NAMES[idx+1:] + NINJA_NAMES[:idx+1]

try:
    with open(states_file) as f:
        data = yaml.safe_load(f)
    ninjas = data.get('ninjas', {})
    for name in rotated:
        info = ninjas.get(name, {})
        state = str(info.get('state', '')).lower()
        ctx = int(info.get('ctx_pct', 100))
        if state == 'idle' and ctx < 50:
            print(name)
            sys.exit(0)
except Exception:
    pass
" 2>/dev/null || true)

            if [ -n "$IDLE_NINJA" ]; then
                SELECTED_NINJA="$IDLE_NINJA"
                log "Ninja selected: ${SELECTED_NINJA} (idle from ninja_states.yaml, rr-rotated)"
            fi
        else
            log "WARN: ninja_states.yaml not found"
        fi
    fi

    # All busy → notify karo and exit
    if [ -z "$SELECTED_NINJA" ]; then
        log "WARN: 全忍者busy — auto_deploy不可"
        bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo \
            "auto_deploy: 全忍者busy。${NEXT_ID}の手動配備を要す (cmd=${CMD_ID})" \
            auto_deploy auto_deploy_next || true
        echo "AUTO_DEPLOY_BLOCKED: 全忍者busy、家老の手動判断を待つ"
        exit 3
    fi
fi

# ═══════════════════════════════════════
# Step 6: Task YAML write
# ═══════════════════════════════════════

TARGET_YAML="$TASKS_DIR/${SELECTED_NINJA}.yaml"
WRITE_EXIT=0
(
    # Durable owner transaction: target is published non-executable first.
    # A crash before source tombstone leaves the source as the sole executable
    # owner; startup reconciliation resumes using the generation/fence record.
    source_hash=$(sha256sum "$TASK_FILE" | awk '{print $1}')
    owner_subject=$(printf '%s' "${CMD_ID}:${NEXT_ID}" | sha256sum | cut -c1-32)
    owner_record=$(bash "$SCRIPT_DIR/scripts/lib/durable_state.sh" begin "$OWNER_STATE_ROOT" \
        "$OWNER_SUBJECT_TYPE" "$owner_subject" "$TASK_FILE|$TARGET_YAML" "$source_hash" "$source_hash")
    owner_fence=$(owner_state_field "$owner_record" fence_token)
    owner_failpoint after_intended_before_target || exit $?
    cp "$TASK_FILE" "$TARGET_YAML"

    # Update fields via yaml_field_set.sh (flock-safe, format-preserving)
    local_yfs="$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"

    # Set assigned_to if not already set
    # awk fast-path replaces Python3 yaml.safe_load (~87ms) for this single field read
    existing_assigned=$(awk '/^  assigned_to: [^'"'"'"]/{gsub(/^  assigned_to: /, ""); print; exit}' \
        "${TARGET_YAML}" 2>/dev/null || true)

    if [ -z "$existing_assigned" ]; then
        bash "$local_yfs" "$TARGET_YAML" "task" "assigned_to" "$SELECTED_NINJA" 2>> "$LOG"
    fi

    bash "$local_yfs" "$TARGET_YAML" "task" "status" "owner_prepared" 2>> "$LOG"
    bash "$local_yfs" "$TARGET_YAML" "task" "owner_generation" "$owner_fence" 2>> "$LOG"
    bash "$local_yfs" "$TARGET_YAML" "task" "owner_fence" "$owner_fence" 2>> "$LOG"
    bash "$local_yfs" "$TARGET_YAML" "task" "owner_subject_id" "$owner_subject" 2>> "$LOG"
    bash "$local_yfs" "$TARGET_YAML" "task" "owner_state_root" "$OWNER_STATE_ROOT" 2>> "$LOG"
    bash "$local_yfs" "$TARGET_YAML" "task" "owner_transaction_status" "prepared" 2>> "$LOG"
    owner_failpoint after_target_before_pointer || exit $?
    owner_ledger="[\"owner_pointer:$TARGET_YAML\",\"source_pending:$TASK_FILE\",\"payload:$source_hash\"]"
    bash "$SCRIPT_DIR/scripts/lib/durable_state.sh" mutate "$OWNER_STATE_ROOT" \
        "$OWNER_SUBJECT_TYPE" "$owner_subject" "$owner_fence" prepared "" "$owner_ledger" >/dev/null

    echo "Written: ${TARGET_YAML}" >&2

    owner_failpoint after_target_before_tombstone || exit $?

    owner_transaction_finish "$owner_subject" "$TASK_FILE" "$TARGET_YAML" \
        "$owner_fence" "$source_hash"

) || WRITE_EXIT=$?

if [ "$WRITE_EXIT" -ne 0 ]; then
    log "ERROR: Task YAML write failed for ${SELECTED_NINJA}"
    echo "ERROR: Task YAML write failed" >&2
    exit 1
fi

log "Task YAML: ${NEXT_ID} → ${SELECTED_NINJA} (${TARGET_YAML})"

# ═══════════════════════════════════════
# Step 7: deploy_task.sh call
# ═══════════════════════════════════════

log "Calling: deploy_task.sh ${SELECTED_NINJA}"
if ! bash "$SCRIPT_DIR/scripts/deploy_task.sh" "$SELECTED_NINJA"; then
    log "ERROR: deploy_task.sh failed for ${SELECTED_NINJA}"
    bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo \
        "auto_deploy: deploy_task.sh失敗。${NEXT_ID}→${SELECTED_NINJA} (cmd=${CMD_ID})" \
        auto_deploy auto_deploy_next || true
    echo "ERROR: deploy_task.sh failed" >&2
    exit 1
fi

# ═══════════════════════════════════════
# Step 8: Karo notification (事後通知)
# ═══════════════════════════════════════

bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo \
    "auto_deploy: ${SELECTED_NINJA}に${NEXT_ID}を自動配備。cmd=${CMD_ID}" \
    auto_deploy auto_deploy_next || true

echo "AUTO_DEPLOY_OK: ${SELECTED_NINJA}に${NEXT_ID}を配備完了"
log "AUTO_DEPLOY_OK: ${SELECTED_NINJA} ← ${NEXT_ID} (cmd=${CMD_ID})"
exit 0
