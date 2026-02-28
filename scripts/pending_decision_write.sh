#!/bin/bash
# pending_decision_write.sh — 殿裁定のYAMLデータ管理（排他ロック付き）
# Usage:
#   bash scripts/pending_decision_write.sh create <summary> <source_cmd> <type> <created_by>
#   bash scripts/pending_decision_write.sh resolve <id> <resolved_content> [resolved_by_cmd] [--no-context-sync]
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

# ── dashboard sync helpers ─────────────────────
dashboard_add_pending() {
    local PD_ID="$1"
    local SUMMARY="$2"
    local SOURCE_CMD="$3"
    local DASHBOARD_FILE="$SCRIPT_DIR/dashboard.md"

    if [ ! -f "$DASHBOARD_FILE" ]; then
        echo "[pending_decision] WARN: dashboard.md not found, skip create sync" >&2
        return 0
    fi

    if ! python3 - "$DASHBOARD_FILE" "$PD_ID" "$SUMMARY" "$SOURCE_CMD" <<'PY'
import sys

dashboard_path = sys.argv[1]
pd_id = sys.argv[2]
summary = sys.argv[3]
source_cmd = sys.argv[4]
entry = f"- **{pd_id}**: {summary}（{source_cmd}）"

with open(dashboard_path, encoding="utf-8") as f:
    lines = f.read().splitlines()

start = next((i for i, line in enumerate(lines) if line.startswith("## 要対応")), -1)
if start < 0:
    print("WARN: 要対応 section not found", file=sys.stderr)
    sys.exit(1)

end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
section = lines[start + 1:end]

section = [line for line in section if line.strip() and line.strip() != "（なし）"]
section = [line for line in section if f"- **{pd_id}**:" not in line]
section.append(entry)

new_lines = lines[:start + 1] + section + lines[end:]
with open(dashboard_path, "w", encoding="utf-8") as f:
    f.write("\n".join(new_lines) + "\n")
PY
    then
        echo "[pending_decision] WARN: dashboard create sync failed for $PD_ID" >&2
    fi
}

get_pending_decision_count() {
    python3 - "$DATA_FILE" <<'PY'
import sys, yaml

data_path = sys.argv[1]
try:
    with open(data_path, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    decisions = data.get("decisions") or []
    pending = sum(1 for d in decisions if isinstance(d, dict) and d.get("status") == "pending")
    print(pending)
except Exception:
    print(0)
PY
}

dashboard_remove_pending() {
    local PD_ID="$1"
    local DASHBOARD_FILE="$SCRIPT_DIR/dashboard.md"

    if [ ! -f "$DASHBOARD_FILE" ]; then
        echo "[pending_decision] WARN: dashboard.md not found, skip resolve sync" >&2
        return 0
    fi

    if ! sed -i "/- \\*\\*${PD_ID}\\*\\*/d" "$DASHBOARD_FILE" 2>/dev/null; then
        echo "[pending_decision] WARN: sed delete failed for $PD_ID" >&2
    fi

    local PENDING_COUNT
    PENDING_COUNT=$(get_pending_decision_count 2>/dev/null || echo 0)
    if [ "$PENDING_COUNT" = "0" ]; then
        if ! python3 - "$DASHBOARD_FILE" <<'PY'
import sys

dashboard_path = sys.argv[1]
with open(dashboard_path, encoding="utf-8") as f:
    lines = f.read().splitlines()

start = next((i for i, line in enumerate(lines) if line.startswith("## 要対応")), -1)
if start < 0:
    print("WARN: 要対応 section not found", file=sys.stderr)
    sys.exit(1)

end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
section = [line for line in lines[start + 1:end] if line.strip()]

if not section:
    section = ["（なし）"]

new_lines = lines[:start + 1] + section + lines[end:]
with open(dashboard_path, "w", encoding="utf-8") as f:
    f.write("\n".join(new_lines) + "\n")
PY
        then
            echo "[pending_decision] WARN: dashboard none-placeholder sync failed" >&2
        fi
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
        if create_output=$(
            (
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
    print(f'PD_ID={new_id}')

except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" || exit 1

            ) 200>"$LOCKFILE"
        ); then
            echo "$create_output"
            local NEW_PD_ID
            NEW_PD_ID=$(printf "%s\n" "$create_output" | awk -F= '/^PD_ID=/{print $2; exit}')
            if [ -n "$NEW_PD_ID" ]; then
                dashboard_add_pending "$NEW_PD_ID" "$SUMMARY" "$SOURCE_CMD" || true
            else
                echo "[pending_decision] WARN: created PD id parse failed, skip dashboard sync" >&2
            fi
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
    local NO_CONTEXT_SYNC="false"

    # Parse optional flags from remaining args
    for _arg in "${@:4}"; do
        case "$_arg" in
            --no-context-sync) NO_CONTEXT_SYNC="true" ;;
        esac
    done

    if [ -z "$PD_ID" ] || [ -z "$RESOLVED_CONTENT" ]; then
        echo "Usage: pending_decision_write.sh resolve <id> <resolved_content> [resolved_by_cmd] [--no-context-sync]" >&2
        exit 1
    fi

    init_data_file

    local TIMESTAMP
    TIMESTAMP=$(date "+%Y-%m-%dT%H:%M:%S")

    attempt=0
    max_attempts=3

    while [ $attempt -lt $max_attempts ]; do
        if resolve_output=$(
            (
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
            # context_synced: False unless exempted
            # Exempt: (1)reconcile (2)source_cmd/resolved_by contains 'test' (3)direct+archived PJ (4)--no-context-sync
            no_context_sync = '$NO_CONTEXT_SYNC' == 'true'
            proj_archived = False
            try:
                with open('$SCRIPT_DIR/config/projects.yaml') as _pf:
                    proj_data = yaml.safe_load(_pf) or {}
                for _p in (proj_data.get('projects') or []):
                    if isinstance(_p, dict) and _p.get('id') == d.get('project', '') and _p.get('status') == 'archived':
                        proj_archived = True
                        break
            except Exception:
                pass
            if (resolved_by != 'reconcile'
                    and 'test' not in d.get('source_cmd', '').lower()
                    and 'test' not in resolved_by.lower()
                    and not (resolved_by == 'direct' and proj_archived)
                    and not no_context_sync):
                d['context_synced'] = False
            else:
                d['context_synced'] = True
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

            ) 200>"$LOCKFILE"
        ); then
            echo "$resolve_output"
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

            dashboard_remove_pending "$PD_ID" || true

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
        echo "  resolve <id> <resolved_content> [resolved_by_cmd] [--no-context-sync]" >&2
        echo "  list    [--status pending|resolved|all]" >&2
        exit 1
        ;;
esac
