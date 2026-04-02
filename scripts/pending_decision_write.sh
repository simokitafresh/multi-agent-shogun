#!/bin/bash
# pending_decision_write.sh — 殿裁定のYAMLデータ管理（排他ロック付き）
# Usage:
#   bash scripts/pending_decision_write.sh create <summary> <source_cmd> <type> <created_by>
#   bash scripts/pending_decision_write.sh resolve <id> <resolved_content> [resolved_by_cmd] [--no-context-sync]
#   bash scripts/pending_decision_write.sh list [--status pending|resolved|all]
#
# type: lord_decision | skill_candidate | escalation | action_required
# Atomic write with flock + python3 + tempfile + os.replace (same as inbox_write.sh)

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

    local entry="- **${PD_ID}**: ${SUMMARY}（${SOURCE_CMD}）"
    local tmpfile
    tmpfile=$(mktemp "${DASHBOARD_FILE}.XXXXXX.tmp")
    { awk -v pd_id="$PD_ID" -v entry="$entry" '
        /^## 要対応/{in_sec=1; print; next}
        in_sec && /^## /{
            if (!added) {print entry; added=1}
            in_sec=0; print; next
        }
        in_sec && /^（なし）/{next}
        in_sec && $0 ~ ("- \\*\\*" pd_id "\\*\\*:"){next}
        {print}
        END{if(in_sec && !added) print entry}
    ' "$DASHBOARD_FILE" > "$tmpfile" && mv "$tmpfile" "$DASHBOARD_FILE"; } \
    || { rm -f "$tmpfile"; echo "[pending_decision] WARN: dashboard create sync failed for $PD_ID" >&2; }
}

get_pending_decision_count() {
    if [ ! -f "$DATA_FILE" ]; then
        echo 0
        return 0
    fi
    grep -c "^  status: pending" "$DATA_FILE" 2>/dev/null || echo 0
}

dashboard_remove_pending() {
    local PD_ID="$1"
    local PENDING_COUNT="${2:-}"
    local DASHBOARD_FILE="$SCRIPT_DIR/dashboard.md"

    if [ ! -f "$DASHBOARD_FILE" ]; then
        echo "[pending_decision] WARN: dashboard.md not found, skip resolve sync" >&2
        return 0
    fi

    if [ -z "$PENDING_COUNT" ]; then
        PENDING_COUNT=$(get_pending_decision_count 2>/dev/null || echo 0)
    fi

    local tmpfile
    tmpfile=$(mktemp "${DASHBOARD_FILE}.XXXXXX.tmp")
    if ! { awk -v pd_id="$PD_ID" -v pending_count="$PENDING_COUNT" '
        /^## 要対応/{in_sec=1; print; next}
        in_sec && /^## /{
            if ((pending_count + 0) == 0 && !has_entry) print "（なし）"
            in_sec=0; print; next
        }
        in_sec && $0 ~ ("- \\*\\*" pd_id "\\*\\*:"){next}
        in_sec && /^（なし）$/{next}
        in_sec && /^- /{has_entry=1}
        {print}
        END{if(in_sec && (pending_count + 0) == 0 && !has_entry) print "（なし）"}
    ' "$DASHBOARD_FILE" > "$tmpfile" && mv "$tmpfile" "$DASHBOARD_FILE"; }; then
        rm -f "$tmpfile"
        echo "[pending_decision] WARN: dashboard resolve sync failed for $PD_ID" >&2
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
    TIMESTAMP=$(date "+%Y-%m-%dT%H:%M:%S%:z")

    attempt=0
    max_attempts=3

    while [ $attempt -lt $max_attempts ]; do
        if create_output=$(
            (
            flock -w 5 200 || exit 1

            python3 - "$DATA_FILE" "$SUMMARY" "$SOURCE_CMD" "$TYPE" "$CREATED_BY" "$TIMESTAMP" "$SCRIPT_DIR/dashboard.md" <<'PY' || exit 1
import yaml, sys, os, tempfile

data_path = sys.argv[1]
summary = sys.argv[2]
source_cmd = sys.argv[3]
pd_type = sys.argv[4]
created_by = sys.argv[5]
timestamp = sys.argv[6]
dashboard_path = sys.argv[7]

def _atomic_write_text(path, content):
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(path), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            f.write(content)
        os.replace(tmp_path, path)
    except Exception:
        os.unlink(tmp_path)
        raise

def _sync_dashboard_add_pending(path, pd_id, summary_text, source_cmd_text):
    if not os.path.exists(path):
        print('[pending_decision] WARN: dashboard.md not found, skip create sync', file=sys.stderr)
        return

    entry = f'- **{pd_id}**: {summary_text}（{source_cmd_text}）\n'
    with open(path) as f:
        lines = f.readlines()

    out = []
    in_section = False
    added = False
    for line in lines:
        if line.startswith('## 要対応'):
            in_section = True
            out.append(line)
            continue
        if in_section and line.startswith('## '):
            if not added:
                out.append(entry)
                added = True
            in_section = False
            out.append(line)
            continue
        if in_section:
            if line.strip() == '（なし）':
                continue
            if line.startswith(f'- **{pd_id}**:'):
                continue
        out.append(line)

    if in_section and not added:
        out.append(entry)

    _atomic_write_text(path, ''.join(out))

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

    # Update summary (AC2/AC3: auto-generated counts)
    _total = len(data['decisions'])
    _resolved = sum(1 for d in data['decisions'] if isinstance(d, dict) and d.get('status') == 'resolved')
    _pending = _total - _resolved
    ordered_data = {'summary': {'total': _total, 'resolved': _resolved, 'pending': _pending}, 'decisions': data['decisions']}

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(data_path), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(ordered_data, f, default_flow_style=False, allow_unicode=True, indent=2, sort_keys=False)
        os.replace(tmp_path, data_path)
    except:
        os.unlink(tmp_path)
        raise

    _sync_dashboard_add_pending(dashboard_path, new_id, summary, source_cmd)

    print(f'[pending_decision] Created {new_id}: {summary[:60]}')
    print(f'PD_ID={new_id}')

except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
PY

            ) 200>"$LOCKFILE"
        ); then
            echo "$create_output"
            local NEW_PD_ID
            NEW_PD_ID=$(printf "%s\n" "$create_output" | awk -F= '/^PD_ID=/{print $2; exit}')
            if [ -z "$NEW_PD_ID" ]; then
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
    TIMESTAMP=$(date "+%Y-%m-%dT%H:%M:%S%:z")

    attempt=0
    max_attempts=3

    while [ $attempt -lt $max_attempts ]; do
        _exit_code=0
        resolve_output=$(
            (
            flock -w 5 200 || exit 2

            python3 - "$DATA_FILE" "$PD_ID" "$RESOLVED_CONTENT" "$RESOLVED_BY" "$TIMESTAMP" "$NO_CONTEXT_SYNC" "$SCRIPT_DIR/config/projects.yaml" "$SCRIPT_DIR/dashboard.md" <<'PY' || exit 1
import yaml, sys, os, tempfile

data_path = sys.argv[1]
pd_id = sys.argv[2]
resolved_content = sys.argv[3]
resolved_by = sys.argv[4]
timestamp = sys.argv[5]
no_context_sync_str = sys.argv[6]
projects_yaml_path = sys.argv[7]
dashboard_path = sys.argv[8]

def _atomic_write_text(path, content):
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(path), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            f.write(content)
        os.replace(tmp_path, path)
    except Exception:
        os.unlink(tmp_path)
        raise

def _sync_dashboard_remove_pending(path, pd_id_value, pending_count):
    if not os.path.exists(path):
        print('[pending_decision] WARN: dashboard.md not found, skip resolve sync', file=sys.stderr)
        return

    target_prefix = f'- **{pd_id_value}**:'
    with open(path) as f:
        lines = f.readlines()

    out = []
    in_section = False
    has_entry = False
    for line in lines:
        if line.startswith('## 要対応'):
            in_section = True
            out.append(line)
            continue
        if in_section and line.startswith('## '):
            if pending_count == 0 and not has_entry:
                out.append('（なし）\n')
            in_section = False
            out.append(line)
            continue
        if in_section:
            if line.startswith(target_prefix):
                continue
            if line.strip() == '（なし）':
                continue
            if line.startswith('- '):
                has_entry = True
        out.append(line)

    if in_section and pending_count == 0 and not has_entry:
        out.append('（なし）\n')

    _atomic_write_text(path, ''.join(out))

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
            no_context_sync = no_context_sync_str == 'true'
            proj_archived = False
            try:
                with open(projects_yaml_path) as _pf:
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

    # Update summary (AC2/AC3: auto-generated counts)
    _total = len(data['decisions'])
    _resolved = sum(1 for d in data['decisions'] if isinstance(d, dict) and d.get('status') == 'resolved')
    _pending = _total - _resolved
    ordered_data = {'summary': {'total': _total, 'resolved': _resolved, 'pending': _pending}, 'decisions': data['decisions']}

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(data_path), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(ordered_data, f, default_flow_style=False, allow_unicode=True, indent=2, sort_keys=False)
        os.replace(tmp_path, data_path)
    except:
        os.unlink(tmp_path)
        raise

    _sync_dashboard_remove_pending(dashboard_path, pd_id, _pending)

    # Output project field for TODO auto-append
    project = d.get('project', '')
    source_cmd = d.get('source_cmd', '')
    print(f'[pending_decision] Resolved {pd_id}')
    print(f'PD_PROJECT={project}')
    print(f'PD_SOURCE={source_cmd}')

except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
PY

            ) 200>"$LOCKFILE"
        ) || _exit_code=$?

        if [ "$_exit_code" -eq 0 ]; then
            echo "$resolve_output"
            # ── Post-resolve: gate_pd_sync + TODO auto-append (outside flock, per L022) ──
            local GATE_SCRIPT="$SCRIPT_DIR/scripts/gates/gate_pd_sync.sh"
            if [ -f "$GATE_SCRIPT" ]; then
                bash "$GATE_SCRIPT" "$PD_ID" || true
            fi

            # Auto 1: context update TODO auto-append
            local TODO_LOG="$SCRIPT_DIR/queue/alerts/pd_context_todo.log"
            mkdir -p "$(dirname "$TODO_LOG")"

            local _project
            _project=$(printf "%s\n" "$resolve_output" | awk -F= '/^PD_PROJECT=/{print $2; exit}')
            local CONTEXT_FILE
            case "$_project" in
                infra)             CONTEXT_FILE="context/infrastructure.md" ;;
                dm-signal)         CONTEXT_FILE="context/dm-signal.md" ;;
                dm-signal-frontend) CONTEXT_FILE="context/dm-signal-frontend.md" ;;
                "")                CONTEXT_FILE="unknown" ;;
                *)                 CONTEXT_FILE="context/${_project}.md" ;;
            esac

            local TODO_TIMESTAMP
            TODO_TIMESTAMP=$(date "+%Y-%m-%dT%H:%M:%S%:z")
            echo "$TODO_TIMESTAMP  $PD_ID → $CONTEXT_FILE に反映必要" >> "$TODO_LOG"
            echo "[pending_decision] TODO追記: $PD_ID → $CONTEXT_FILE"

            return 0
        elif [ "$_exit_code" -eq 2 ]; then
            # flock timeout — retry
            attempt=$((attempt + 1))
            if [ $attempt -lt $max_attempts ]; then
                echo "[pending_decision] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
                sleep 1
            else
                echo "[pending_decision] Failed to acquire lock after $max_attempts attempts" >&2
                exit 1
            fi
        else
            # python3 error (ID not found, data error) — no retry
            exit 1
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

    python3 - "$DATA_FILE" "$STATUS_FILTER" <<'PY'
import yaml, sys

data_path = sys.argv[1]
status_filter = sys.argv[2]

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
PY
}

# ── main dispatch (source guard) ─────────────────
# Allow `source pending_decision_write.sh` for unit tests without triggering dispatch
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -e
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
fi
