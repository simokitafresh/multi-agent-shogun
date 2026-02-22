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

    print(f'[pending_decision] Resolved {pd_id}')

except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" || exit 1

        ) 200>"$LOCKFILE"; then
            # 穴3 auto-apply: context自動追記
            _auto_append_context "$PD_ID" "$RESOLVED_CONTENT" "$TIMESTAMP"
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

# ── auto append context (穴3 auto-apply) ────────
_auto_append_context() {
    local PD_ID="$1"
    local RESOLVED_CONTENT="$2"
    local RESOLVED_AT="$3"

    export SCRIPT_DIR PD_ID DATA_FILE
    python3 << 'PYEOF' || true
import yaml, re, os, sys

script_dir = os.environ["SCRIPT_DIR"]
pd_id = os.environ["PD_ID"]
data_file = os.environ["DATA_FILE"]
projects_config = os.path.join(script_dir, "config/projects.yaml")
shogun_cmd_file = os.path.join(script_dir, "queue/shogun_to_karo.yaml")

# Read PD entry
with open(data_file, encoding='utf-8') as f:
    data = yaml.safe_load(f)

pd = None
for d in data.get('decisions', []):
    if d.get('id') == pd_id:
        pd = d
        break

if not pd:
    sys.exit(0)

# Skip auto-reconciled and test
if pd.get('resolved_by') == 'reconcile':
    print(f'[auto_append_context] Skip: {pd_id} is auto-reconciled')
    sys.exit(0)

source_cmd = pd.get('source_cmd', '')
if source_cmd.startswith('TEST'):
    print(f'[auto_append_context] Skip: {pd_id} is test')
    sys.exit(0)

# Find project from source_cmd via shogun_to_karo.yaml
project = None
try:
    with open(shogun_cmd_file, encoding='utf-8') as f:
        cmd_data = yaml.safe_load(f)
    for cmd in cmd_data.get('commands', []):
        if cmd.get('id') == source_cmd:
            project = cmd.get('project')
            break
except Exception:
    pass

# Check archive if not found
if not project:
    archive_dir = os.path.join(script_dir, "queue/archive/cmds")
    if os.path.isdir(archive_dir):
        for fname in sorted(os.listdir(archive_dir)):
            if not fname.endswith('.yaml'):
                continue
            try:
                with open(os.path.join(archive_dir, fname), encoding='utf-8') as f:
                    arch = yaml.safe_load(f)
                for cmd in (arch.get('commands', []) if isinstance(arch, dict) else []):
                    if cmd.get('id') == source_cmd:
                        project = cmd.get('project')
                        break
            except Exception:
                pass
            if project:
                break

if not project:
    print(f'[auto_append_context] Skip: project not found for {source_cmd}')
    sys.exit(0)

# Find context file from config/projects.yaml
with open(projects_config, encoding='utf-8') as f:
    proj_cfg = yaml.safe_load(f)

context_file = None
for p in proj_cfg.get('projects', []):
    if p.get('id') == project:
        context_file = p.get('context_file', f'context/{project}.md')
        break

if not context_file:
    context_file = f'context/{project}.md'

if not os.path.isabs(context_file):
    context_file = os.path.join(script_dir, context_file)

if not os.path.isfile(context_file):
    print(f'[auto_append_context] Skip: context file not found: {context_file}')
    sys.exit(0)

# Build entry
summary = pd.get('summary', '')
resolved_content = pd.get('resolved_content', '')
resolved_at = pd.get('resolved_at', '')
entry = f'- **{pd_id}**: {summary}\n  - 裁定: {resolved_content}\n  - 日時: {resolved_at}\n'

# Read context file and append to ## 殿裁定履歴 section
with open(context_file, 'r', encoding='utf-8') as f:
    content = f.read()

section_header = '## 殿裁定履歴'
if section_header in content:
    idx = content.index(section_header)
    after_header = content[idx + len(section_header):]
    # Find next ## heading
    m = re.search(r'\n## ', after_header)
    if m:
        insert_pos = idx + len(section_header) + m.start()
        content = content[:insert_pos] + '\n' + entry + content[insert_pos:]
    else:
        content = content.rstrip('\n') + '\n' + entry + '\n'
else:
    content = content.rstrip('\n') + '\n\n' + section_header + '\n' + entry + '\n'

with open(context_file, 'w', encoding='utf-8') as f:
    f.write(content)

print(f'[auto_append_context] Appended {pd_id} to {context_file}')
PYEOF
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
