#!/usr/bin/env bash
# skill_freshness_adapter.sh — campaign-lane adapter for SKILL.md freshness
# Reads gate_skill_script_refs.sh WARN output to select stale SKILL.md targets.
# Interface: next / status / auto-deploy <ninja> / record <skill_path> <result>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE_SCRIPT="$SCRIPT_DIR/gates/gate_skill_script_refs.sh"
MEASUREMENT_LOG="$PROJECT_DIR/logs/skill_freshness_measurements.jsonl"

usage() {
    cat <<'EOF'
Usage:
  bash scripts/skill_freshness_adapter.sh next
  bash scripts/skill_freshness_adapter.sh status
  bash scripts/skill_freshness_adapter.sh auto-deploy <ninja>
  bash scripts/skill_freshness_adapter.sh record <skill_path> <pass|fail>
EOF
}

# Parse WARN lines from gate_skill_script_refs.sh
_get_stale_skills() {
    bash "$GATE_SCRIPT" 2>&1 | grep '^  WARN:' | \
        sed 's/.*WARN: \(skills\/[^ ]*\) <- \(scripts\/[^ ]*\).*/\1|\2/' || true
}

cmd_next() {
    local stale
    stale=$(_get_stale_skills)
    if [ -z "$stale" ]; then
        echo '{"status":"no_target","reason":"all SKILL.md fresh"}'
        return 0
    fi
    local first
    first=$(echo "$stale" | head -1)
    local skill_path script_path
    skill_path="${first%%|*}"
    script_path="${first##*|}"
    local count
    count=$(echo "$stale" | wc -l)
    echo "{\"status\":\"target_found\",\"target\":\"$skill_path\",\"script\":\"$script_path\",\"remaining\":$count}"
}

cmd_status() {
    local stale
    stale=$(_get_stale_skills)
    local count=0
    [ -n "$stale" ] && count=$(echo "$stale" | wc -l)
    echo "stale_count: $count"
    if [ "$count" -gt 0 ]; then
        echo "targets:"
        echo "$stale" | while IFS='|' read -r skill script; do
            echo "  - skill: $skill"
            echo "    script: $script"
        done
    fi
}

cmd_auto_deploy() {
    local ninja="${1:?ninja name required}"
    local stale
    stale=$(_get_stale_skills)
    if [ -z "$stale" ]; then
        echo "NO_TARGET: all SKILL.md fresh" >&2
        return 1
    fi
    local first
    first=$(echo "$stale" | head -1)
    local skill_path script_path
    skill_path="${first%%|*}"
    script_path="${first##*|}"

    local task_file="$PROJECT_DIR/queue/tasks/${ninja}.yaml"
    if [ ! -f "$task_file" ]; then
        echo "ERROR: task file not found: $task_file" >&2
        return 1
    fi

    # Generate task content via deploy_task.sh karo_direct pattern
    local task_id="cmd_campaign_skill_freshness_$(date +%Y%m%d%H%M%S)"
    local title="SKILL.md鮮度更新: $skill_path <- $script_path"

    echo "DEPLOY: $ninja -> $title"
    echo "  skill_path: $skill_path"
    echo "  script_path: $script_path"
    echo "  task_id: $task_id"

    # Use karo_direct for actual deployment
    echo "HANDOFF: bash scripts/deploy_task.sh karo_direct \"$task_id\" \"$title\" \"$ninja\" infra"
}

cmd_record() {
    local skill_path="${1:?skill_path required}"
    local result="${2:?pass|fail required}"
    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S%z')
    mkdir -p "$(dirname "$MEASUREMENT_LOG")"
    (
        flock -w 5 9 || exit 1
        printf '{"target":"%s","status":"%s","value":%d,"measured_at":"%s"}\n' \
            "$skill_path" "$result" "$([ "$result" = "pass" ] && echo 0 || echo 1)" "$ts" \
            >> "$MEASUREMENT_LOG"
    ) 9>"${MEASUREMENT_LOG}.lock"
    echo "RECORDED: $skill_path $result at $ts"
}

case "${1:-}" in
    next)       cmd_next ;;
    status)     cmd_status ;;
    auto-deploy) cmd_auto_deploy "${2:-}" ;;
    record)     cmd_record "${2:-}" "${3:-}" ;;
    *)          usage; exit 1 ;;
esac
