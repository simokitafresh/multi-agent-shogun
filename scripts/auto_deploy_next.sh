#!/usr/bin/env bash
# auto_deploy_next.sh — サブタスク完了時の次サブタスク自動配備
# Usage: bash scripts/auto_deploy_next.sh <cmd_id> <completed_subtask_id>
#
# Exit codes:
#   0 — AUTO_DEPLOY_OK: 配備成功 / AUTO_DEPLOY_DONE: 全サブタスク完了
#   1 — 入力エラー or 検証失敗
#   2 — AUTO_DEPLOY_SKIP: auto_deploy=false, 家老の手動判断を待つ
#   3 — AUTO_DEPLOY_BLOCKED: blocked_by未解消 or 全忍者busy or 二重配備ロック

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$SCRIPT_DIR/logs/auto_deploy.log"
TASKS_DIR="$SCRIPT_DIR/queue/tasks"
REPORTS_DIR="$SCRIPT_DIR/queue/reports"

CMD_ID="${1:-}"
COMPLETED_SUBTASK_ID="${2:-}"

mkdir -p "$SCRIPT_DIR/logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [AUTO_DEPLOY] $1" >> "$LOG"
    echo "[AUTO_DEPLOY] $1" >&2
}

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

ANALYSIS_EXIT=0
ANALYSIS=$(CMD_ID="$CMD_ID" COMPLETED_ID="$COMPLETED_SUBTASK_ID" \
    TASKS_DIR="$TASKS_DIR" REPORTS_DIR="$REPORTS_DIR" \
    python3 -c "
import yaml, sys, os, glob

cmd_id = os.environ['CMD_ID']
completed_id = os.environ['COMPLETED_ID']
tasks_dir = os.environ['TASKS_DIR']
reports_dir = os.environ['REPORTS_DIR']

# ─── Scan all task YAMLs for parent_cmd match ───
raw_subtasks = []
for fpath in sorted(glob.glob(os.path.join(tasks_dir, '*.yaml'))):
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
            'task_id': t.get('task_id', ''),
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
    rpath = os.path.join(reports_dir, f'{completed_ninja}_report.yaml')
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
undone = [st for st in all_subtasks if st['status'] != 'done']

if not undone:
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
    DETAIL=$(echo "$ANALYSIS" | sed 's/^ERROR\t//')
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

# CTX% helper (tmux @context_pct → ハードコードペインマッピング)
get_ctx_pct() {
    local name="$1"
    local pane
    case "$name" in
        karo)     pane="shogun:agents.1" ;;
        sasuke)   pane="shogun:agents.2" ;;
        kirimaru) pane="shogun:agents.3" ;;
        hayate)   pane="shogun:agents.4" ;;
        kagemaru) pane="shogun:agents.5" ;;
        hanzo)    pane="shogun:agents.6" ;;
        saizo)    pane="shogun:agents.7" ;;
        kotaro)   pane="shogun:agents.8" ;;
        tobisaru) pane="shogun:agents.9" ;;
        *) echo "100"; return ;;
    esac
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

    # Priority 2: ninja_states.yamlからidle忍者
    if [ -z "$SELECTED_NINJA" ]; then
        STATES_FILE="$SCRIPT_DIR/logs/ninja_states.yaml"
        if [ -f "$STATES_FILE" ]; then
            IDLE_NINJA=$(python3 -c "
import yaml, sys
try:
    with open('$STATES_FILE') as f:
        data = yaml.safe_load(f)
    for name, info in data.get('ninjas', {}).items():
        if name == 'karo':
            continue
        state = str(info.get('state', '')).lower()
        ctx = int(info.get('ctx_pct', 100))
        if state == 'idle' and ctx < 50:
            print(name)
            sys.exit(0)
except:
    pass
" 2>/dev/null || true)

            if [ -n "$IDLE_NINJA" ]; then
                SELECTED_NINJA="$IDLE_NINJA"
                log "Ninja selected: ${SELECTED_NINJA} (idle from ninja_states.yaml)"
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
TARGET_LOCK="${TARGET_YAML}.lock"

WRITE_EXIT=0
(
    flock -w 10 201 || { log "ERROR: flock failed for ${TARGET_YAML}"; exit 1; }

    TASK_FILE_PATH="$TASK_FILE" TARGET_PATH="$TARGET_YAML" \
    NINJA_NAME="$SELECTED_NINJA" \
    python3 -c "
import yaml, sys, os, tempfile

task_file = os.environ['TASK_FILE_PATH']
target_path = os.environ['TARGET_PATH']
ninja = os.environ['NINJA_NAME']

with open(task_file) as f:
    data = yaml.safe_load(f)

task = data['task']

# assigned_toが事前指定されていればそちらを優先
if not task.get('assigned_to'):
    task['assigned_to'] = ninja
task['status'] = 'assigned'

# Atomic write to target ninja YAML
tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(target_path), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
    os.replace(tmp_path, target_path)
except:
    os.unlink(tmp_path)
    raise

print(f'Written: {target_path}', file=sys.stderr)

# If source file differs from target, update source too (prevent stale duplicates)
if os.path.abspath(task_file) != os.path.abspath(target_path):
    tmp_fd2, tmp_path2 = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd2, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path2, task_file)
        print(f'Source updated: {task_file}', file=sys.stderr)
    except:
        try: os.unlink(tmp_path2)
        except: pass
        # Non-fatal: target is the authority
        print(f'WARN: source update failed (non-fatal)', file=sys.stderr)
" 2>> "$LOG"

) 201>"$TARGET_LOCK" || WRITE_EXIT=$?

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
