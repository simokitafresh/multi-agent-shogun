#!/bin/bash
# pending_decision_write.sh — 殿裁定のYAMLデータ管理（排他ロック付き）
# Usage:
#   bash scripts/pending_decision_write.sh create <summary> <source_cmd> <type> <created_by>
#   bash scripts/pending_decision_write.sh resolve <id> <resolved_content> [resolved_by_cmd]
#   bash scripts/pending_decision_write.sh list [--status pending|resolved|all]
#
# type: lord_decision | skill_candidate | escalation | action_required
# Atomic write with flock + python3 + tempfile + os.replace (same as inbox_write.sh)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_FILE="$SCRIPT_DIR/queue/pending_decisions.yaml"
LOCKFILE="${DATA_FILE}.lock"
SUBCMD="$1"

# Initialize data file if not exists
init_data_file() {
    if [ ! -f "$DATA_FILE" ]; then
        mkdir -p "$(dirname "$DATA_FILE")"
        echo "decisions: []" > "$DATA_FILE"
    fi
}

# ── create ──────────────────────────────────────
cmd_create() {
    local SUMMARY="$1"
    local SOURCE_CMD="$2"
    local TYPE="$3"
    local CREATED_BY="$4"

    if [ -z "$SUMMARY" ] || [ -z "$SOURCE_CMD" ] || [ -z "$TYPE" ] || [ -z "$CREATED_BY" ]; then
        echo "Usage: pending_decision_write.sh create <summary> <source_cmd> <type> <created_by>" >&2
        exit 1
    fi

    # Validate type
    case "$TYPE" in
        lord_decision|skill_candidate|escalation|action_required) ;;
        *)
            echo "ERROR: Invalid type '$TYPE'. Must be: lord_decision|skill_candidate|escalation|action_required" >&2
            exit 1
            ;;
    esac

    init_data_file

    local TIMESTAMP
    TIMESTAMP=$(date "+%Y-%m-%dT%H:%M:%S")

    attempt=0
    max_attempts=3

    while [ $attempt -lt $max_attempts ]; do
        if (
            flock -w 5 200 || exit 1

            python3 -c "
import yaml, sys, os, tempfile

data_path = '$DATA_FILE'
summary = '''$SUMMARY'''
source_cmd = '$SOURCE_CMD'
pd_type = '$TYPE'
created_by = '$CREATED_BY'
timestamp = '$TIMESTAMP'

try:
    with open(data_path) as f:
        data = yaml.safe_load(f)

    if not data:
        data = {}
    if not data.get('decisions'):
        data['decisions'] = []

    # Auto-increment ID: find max existing PD-XXX
    max_id = 0
    for d in data['decisions']:
        did = d.get('id', '')
        if did.startswith('PD-'):
            try:
                num = int(did[3:])
                if num > max_id:
                    max_id = num
            except ValueError:
                pass
    new_id = f'PD-{max_id + 1:03d}'

    new_decision = {
        'id': new_id,
        'type': pd_type,
        'summary': summary,
        'source_cmd': source_cmd,
        'status': 'pending',
        'created_at': timestamp,
        'created_by': created_by,
    }
    data['decisions'].append(new_decision)

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(data_path), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, data_path)
    except:
        os.unlink(tmp_path)
        raise

    print(f'[pending_decision] Created {new_id}: {summary[:60]}')

except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" || exit 1

        ) 200>"$LOCKFILE"; then
            return 0
        else
            attempt=$((attempt + 1))
            if [ $attempt -lt $max_attempts ]; then
                echo "[pending_decision] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
                sleep 1
            else
                echo "[pending_decision] Failed to acquire lock after $max_attempts attempts" >&2
                exit 1
            fi
        fi
    done
}

# ── resolve ─────────────────────────────────────
cmd_resolve() {
    local PD_ID="$1"
    local RESOLVED_CONTENT="$2"
    local RESOLVED_BY="${3:-direct}"

    if [ -z "$PD_ID" ] || [ -z "$RESOLVED_CONTENT" ]; then
        echo "Usage: pending_decision_write.sh resolve <id> <resolved_content> [resolved_by_cmd]" >&2
        exit 1
    fi

    init_data_file

    local TIMESTAMP
    TIMESTAMP=$(date "+%Y-%m-%dT%H:%M:%S")

    attempt=0
    max_attempts=3

    while [ $attempt -lt $max_attempts ]; do
        if (
            flock -w 5 200 || exit 1

            python3 -c "
import yaml, sys, os, tempfile

data_path = '$DATA_FILE'
pd_id = '$PD_ID'
resolved_content = '''$RESOLVED_CONTENT'''
resolved_by = '$RESOLVED_BY'
timestamp = '$TIMESTAMP'

try:
    with open(data_path) as f:
        data = yaml.safe_load(f)

    if not data or not data.get('decisions'):
        print(f'ERROR: No decisions found', file=sys.stderr)
        sys.exit(1)

    found = False
    for d in data['decisions']:
        if d.get('id') == pd_id:
            if d.get('status') == 'resolved':
                print(f'WARN: {pd_id} is already resolved', file=sys.stderr)
                sys.exit(0)
            d['status'] = 'resolved'
            d['resolved_at'] = timestamp
            d['resolved_content'] = resolved_content
            d['resolved_by'] = resolved_by
            # context_synced: false unless auto-reconciled or test
            if resolved_by != 'reconcile' and not d.get('source_cmd', '').startswith('TEST'):
                d['context_synced'] = False
            found = True
            break

    if not found:
        print(f'ERROR: {pd_id} not found', file=sys.stderr)
        sys.exit(1)

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(data_path), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, data_path)
    except:
        os.unlink(tmp_path)
        raise

    # Output project field for TODO auto-append
    project = d.get('project', '')
    source_cmd = d.get('source_cmd', '')
    print(f'[pending_decision] Resolved {pd_id}')
    print(f'PD_PROJECT={project}')
    print(f'PD_SOURCE={source_cmd}')

except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" || exit 1

        ) 200>"$LOCKFILE"; then
            # ── Post-resolve: gate_pd_sync + TODO auto-append (outside flock, per L022) ──
            local GATE_SCRIPT="$SCRIPT_DIR/scripts/gates/gate_pd_sync.sh"
            if [ -f "$GATE_SCRIPT" ]; then
                bash "$GATE_SCRIPT" "$PD_ID" || true
            fi

            # Auto 1: context update TODO auto-append
            local TODO_LOG="$SCRIPT_DIR/queue/alerts/pd_context_todo.log"
            mkdir -p "$(dirname "$TODO_LOG")"

            # Determine context_file from PD's project field
            local CONTEXT_FILE
            CONTEXT_FILE=$(python3 -c "
import yaml, sys

data_path = '$DATA_FILE'
pd_id = '$PD_ID'

PROJECT_MAP = {
    'infra': 'context/infrastructure.md',
    'dm-signal': 'context/dm-signal.md',
    'dm-signal-frontend': 'context/dm-signal-frontend.md',
}

try:
    with open(data_path) as f:
        data = yaml.safe_load(f)
    if not data or not data.get('decisions'):
        print('unknown')
        sys.exit(0)
    for d in data['decisions']:
        if d.get('id') == pd_id:
            project = d.get('project', '')
            if project and project in PROJECT_MAP:
                print(PROJECT_MAP[project])
            elif project:
                print(f'context/{project}.md')
            else:
                print('unknown')
            sys.exit(0)
    print('unknown')
except Exception:
    print('unknown')
" 2>/dev/null || echo "unknown")

            local TODO_TIMESTAMP
            TODO_TIMESTAMP=$(date "+%Y-%m-%dT%H:%M:%S")
            echo "$TODO_TIMESTAMP  $PD_ID → $CONTEXT_FILE に反映必要" >> "$TODO_LOG"
            echo "[pending_decision] TODO追記: $PD_ID → $CONTEXT_FILE"

            return 0
        else
            attempt=$((attempt + 1))
            if [ $attempt -lt $max_attempts ]; then
                echo "[pending_decision] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
                sleep 1
            else
                echo "[pending_decision] Failed to acquire lock after $max_attempts attempts" >&2
                exit 1
            fi
        fi
    done
}

# ── list ────────────────────────────────────────
cmd_list() {
    local STATUS_FILTER="${1:-pending}"

    # Parse --status flag
    if [ "$STATUS_FILTER" = "--status" ]; then
        STATUS_FILTER="${2:-pending}"
    fi

    init_data_file

    python3 -c "
import yaml, sys

data_path = '$DATA_FILE'
status_filter = '$STATUS_FILTER'

try:
    with open(data_path) as f:
        data = yaml.safe_load(f)

    if not data or not data.get('decisions'):
        print('No decisions found.')
        sys.exit(0)

    for d in data['decisions']:
        if status_filter != 'all' and d.get('status') != status_filter:
            continue
        pid = d.get('id', '???')
        summary = d.get('summary', '')
        status = d.get('status', 'unknown')
        source = d.get('source_cmd', '')
        print(f'{pid}  [{status}]  ({source})  {summary}')

except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
"
}

# ── main dispatch ───────────────────────────────
case "$SUBCMD" in
    create)
        shift
        cmd_create "$@"
        ;;
    resolve)
        shift
        cmd_resolve "$@"
        ;;
    list)
        shift
        cmd_list "$@"
        ;;
    *)
        echo "Usage: pending_decision_write.sh <create|resolve|list> [args...]" >&2
        echo "" >&2
        echo "Subcommands:" >&2
        echo "  create  <summary> <source_cmd> <type> <created_by>" >&2
        echo "  resolve <id> <resolved_content> [resolved_by_cmd]" >&2
        echo "  list    [--status pending|resolved|all]" >&2
        exit 1
        ;;
esac
