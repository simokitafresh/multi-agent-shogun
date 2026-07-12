#!/usr/bin/env bash
# shellcheck disable=SC1091
# insight_resolve.sh — insightをresolvedステータスに変更
# Usage: bash scripts/insight_resolve.sh <insight_id> "<reason>" "<action_artifact>"
# @source: cmd_1502

set -euo pipefail
_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
SCRIPT_DIR="${_self%/*}"
REPO_ROOT="${SCRIPT_DIR%/*}"
unset _self

if [ "$#" -ne 3 ]; then
    echo "Usage: bash scripts/insight_resolve.sh <insight_id> \"<reason>\" \"<action_artifact>\"" >&2
    exit 1
fi

INSIGHT_ID="$1"
REASON="$2"
ACTION_ARTIFACT="$3"
INSIGHTS_FILE="$REPO_ROOT/queue/insights.yaml"

if [ ! -f "$INSIGHTS_FILE" ]; then
    echo "ERROR: insights file not found: $INSIGHTS_FILE" >&2
    exit 1
fi

if ! grep -q "id: ${INSIGHT_ID}" "$INSIGHTS_FILE"; then
    echo "ERROR: insight not found: $INSIGHT_ID" >&2
    exit 1
fi

if [ -z "${REASON//[[:space:]]/}" ] || [ -z "${ACTION_ARTIFACT//[[:space:]]/}" ]; then
    echo "ERROR: resolved_reason and action_artifact must be non-empty" >&2
    exit 1
fi

# shellcheck source=lib/yaml_field_set.sh
source "$SCRIPT_DIR/lib/yaml_field_set.sh"

yaml_field_set "$INSIGHTS_FILE" "$INSIGHT_ID" status resolved
yaml_field_set "$INSIGHTS_FILE" "$INSIGHT_ID" resolved_reason "$REASON"
yaml_field_set "$INSIGHTS_FILE" "$INSIGHT_ID" action_artifact "$ACTION_ARTIFACT"
yaml_field_set "$INSIGHTS_FILE" "$INSIGHT_ID" resolved_at "$(date -Iseconds)"

echo "OK: $INSIGHT_ID → resolved"
