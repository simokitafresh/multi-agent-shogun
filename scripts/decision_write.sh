#!/bin/bash
# decision_write.sh — SSOT (DM-signal/tasks/decisions.md) への意思決定記録追記（排他ロック付き）
# Usage: bash scripts/decision_write.sh <project_id> "<cmd_id>" "<title>" "<decision>" "<rationale>" "<alternatives>"
# Example: bash scripts/decision_write.sh dm-signal "cmd_083" "MC廃止" "per-ticker統一" "バグ発見" "案D,E,F"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/lock_path.sh" 2>/dev/null \
    || lock_path() { printf '/tmp/shogun_lock_%s.lock' "$(printf '%s' "$1" | md5sum | cut -c1-16)"; }
PROJECT_ID="$1"
CMD_ID="$2"
TITLE="$3"
DECISION="$4"
RATIONALE="$5"
ALTERNATIVES="$6"

# Validate arguments
if [ -z "$PROJECT_ID" ] || [ -z "$TITLE" ] || [ -z "$DECISION" ]; then
    echo "Usage: decision_write.sh <project_id> <cmd_id> <title> <decision> <rationale> <alternatives>" >&2
    exit 1
fi

# Get project path from config/projects.yaml
export PROJECT_ID SCRIPT_DIR
PROJECT_PATH=$(python3 -c "
import yaml, os
script_dir = os.environ['SCRIPT_DIR']
project_id = os.environ['PROJECT_ID']
with open(os.path.join(script_dir, 'config', 'projects.yaml'), encoding='utf-8') as f:
    cfg = yaml.safe_load(f)
for p in cfg.get('projects', []):
    if p['id'] == project_id:
        print(p['path'])
        break
")

if [ -z "$PROJECT_PATH" ]; then
    echo "ERROR: Project '$PROJECT_ID' not found in config/projects.yaml" >&2
    exit 1
fi

DECISIONS_FILE="$PROJECT_PATH/tasks/decisions.md"
LOCKFILE="$(lock_path "$DECISIONS_FILE")"

# Create decisions.md if it doesn't exist
if [ ! -f "$DECISIONS_FILE" ]; then
    {
        echo "# ADR (Architecture Decision Records)"
        echo ""
        echo "意思決定記録。各エントリは不可逆な設計判断を記録する。"
        echo ""
    } > "$DECISIONS_FILE"
fi

TIMESTAMP=$(date "+%Y-%m-%d")

# Atomic append with flock (3 retries)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 10 200 || exit 1

        # Find max ID and append new entry
        export DECISIONS_FILE TIMESTAMP CMD_ID TITLE DECISION RATIONALE ALTERNATIVES
        python3 << 'PYEOF'
import re, os

decisions_file = os.environ["DECISIONS_FILE"]
timestamp = os.environ["TIMESTAMP"]
cmd_id = os.environ["CMD_ID"]
title = os.environ["TITLE"]
decision = os.environ["DECISION"]
rationale = os.environ["RATIONALE"]
alternatives = os.environ["ALTERNATIVES"]

with open(decisions_file, encoding='utf-8') as f:
    content = f.read()

# Find max numeric ID from ### D{N}: pattern
max_id = 0

for m in re.finditer(r'^### D(\d+):', content, re.MULTILINE):
    num = int(m.group(1))
    if num > max_id:
        max_id = num

new_id = max_id + 1
new_id_str = f'D{new_id:03d}'

# Build new entry
entry = f'\n### {new_id_str}: {title}\n'
entry += f'- **日付**: {timestamp}\n'
if cmd_id:
    entry += f'- **cmd**: {cmd_id}\n'
entry += f'- **決定**: {decision}\n'
if rationale:
    entry += f'- **根拠**: {rationale}\n'
if alternatives:
    entry += f'- **却下案**: {alternatives}\n'

# Append to file
with open(decisions_file, 'a', encoding='utf-8') as f:
    f.write(entry)

print(f'{new_id_str} added to {decisions_file}')
PYEOF

    ) 200>"$LOCKFILE"; then
        exit 0
    else
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[decision_write] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[decision_write] Failed to acquire lock after $max_attempts attempts" >&2
            exit 1
        fi
    fi
done
