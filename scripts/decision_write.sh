#!/bin/bash
# decision_write.sh — SSOT (DM-signal/tasks/decisions.md) への意思決定記録追記（排他ロック付き）
# Usage: bash scripts/decision_write.sh <project_id> "<cmd_id>" "<title>" "<decision>" "<rationale>" "<alternatives>"
# Example: bash scripts/decision_write.sh dm-signal "cmd_083" "MC廃止" "per-ticker統一" "バグ発見" "案D,E,F"

set -e

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        ""|-h|--help)
            echo "Usage: decision_write.sh <project_id> <cmd_id> <title> <decision> <rationale> <alternatives>" >&2
            exit 1
            ;;
    esac
fi

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

# Get project path from config/projects.yaml using awk (no Python startup)
PROJECT_PATH=$(awk -v pid="$PROJECT_ID" '
  /^  - id:/ {
    val = $0
    sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*["'"'"']?/, "", val)
    sub(/["'"'"']?[[:space:]]*$/, "", val)
    in_proj = (val == pid)
  }
  /^  - / && !/id:/ { in_proj = 0 }
  in_proj && /^[[:space:]]*path:/ {
    val = $0
    sub(/^[[:space:]]*path:[[:space:]]*["'"'"']?/, "", val)
    sub(/["'"'"']?[[:space:]]*$/, "", val)
    print val; exit
  }
' "$SCRIPT_DIR/config/projects.yaml")

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

        # Find max numeric ID from ### D{N}: pattern using awk
        max_id=$(awk 'BEGIN{max=0} /^### D[0-9]+:/{n=$2; sub(/^D/,"",n); sub(/:$/,"",n); if (n+0>max) max=n+0} END{print max}' "$DECISIONS_FILE")
        new_id=$((max_id + 1))
        new_id_str=$(printf 'D%03d' "$new_id")

        # Build and append entry
        {
            printf '\n### %s: %s\n' "$new_id_str" "$TITLE"
            printf -- '- **日付**: %s\n' "$TIMESTAMP"
            [ -n "$CMD_ID" ] && printf -- '- **cmd**: %s\n' "$CMD_ID"
            printf -- '- **決定**: %s\n' "$DECISION"
            [ -n "$RATIONALE" ] && printf -- '- **根拠**: %s\n' "$RATIONALE"
            [ -n "$ALTERNATIVES" ] && printf -- '- **却下案**: %s\n' "$ALTERNATIVES"
        } >> "$DECISIONS_FILE"

        printf '%s added to %s\n' "$new_id_str" "$DECISIONS_FILE"

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
