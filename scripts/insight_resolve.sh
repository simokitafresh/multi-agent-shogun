#!/usr/bin/env bash
# shellcheck disable=SC1091
# insight_resolve.sh — insightをresolvedステータスに変更
# Usage: bash scripts/insight_resolve.sh <insight_id> "<reason>"
# @source: cmd_1502

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ "$#" -lt 2 ]; then
    echo "Usage: bash scripts/insight_resolve.sh <insight_id> \"<reason>\"" >&2
    exit 1
fi

INSIGHT_ID="$1"
REASON="$2"
INSIGHTS_FILE="$REPO_ROOT/queue/insights.yaml"

if [ ! -f "$INSIGHTS_FILE" ]; then
    echo "ERROR: insights file not found: $INSIGHTS_FILE" >&2
    exit 1
fi

if ! grep -q "id: ${INSIGHT_ID}" "$INSIGHTS_FILE"; then
    echo "ERROR: insight not found: $INSIGHT_ID" >&2
    exit 1
fi

# shellcheck source=lib/yaml_field_set.sh
source "$SCRIPT_DIR/lib/yaml_field_set.sh"

yaml_field_set "$INSIGHTS_FILE" "$INSIGHT_ID" status resolved
yaml_field_set "$INSIGHTS_FILE" "$INSIGHT_ID" resolved_reason "$REASON"

echo "OK: $INSIGHT_ID → resolved"
