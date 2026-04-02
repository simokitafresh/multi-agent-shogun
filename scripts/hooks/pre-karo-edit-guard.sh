#!/usr/bin/env bash
# @source: gunshi_S141 (SKILL.md 0バイト化事故の再発防止)
# PreToolUse hook: 家老が忍者稼働中にEdit/Writeする際のガード
#
# 根本原因: 家老が忍者の仕事を代行（鎖の原理違反）→同一ファイル並列Write→データ消失
# 対策: 忍者稼働中 + 家老の管理領域外 → BLOCK
#
# 家老の管理領域（PASS）: queue/ logs/ dashboard.md CLAUDE.md instructions/ context/ projects/ config/ docs/
# それ以外（忍者稼働中ならBLOCK）: ~/.claude/skills/ scripts/ tests/ 外部プロジェクト等
set -euo pipefail

PROJ_DIR="/mnt/c/tools/multi-agent-shogun"
TASKS_DIR="${PROJ_DIR}/queue/tasks"

emit_deny() {
    local reason="$1"
    jq -cn --arg reason "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
}

# --- Read hook payload ---
payload="$(cat)"
if [ -z "${payload//[[:space:]]/}" ]; then
    exit 0
fi

tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null || true)"
if [[ "$tool_name" != "Write" && "$tool_name" != "Edit" ]]; then
    exit 0
fi

# --- Agent check: only applies to karo ---
agent_id="$(tmux display-message -t "${TMUX_PANE:-}" -p '#{@agent_id}' 2>/dev/null || echo "")"
if [ "$agent_id" != "karo" ]; then
    exit 0
fi

# --- Extract file path ---
file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
if [ -z "$file_path" ]; then
    exit 0
fi

# --- Whitelist: karo's management domain (always PASS) ---
# Normalize path for matching
case "$file_path" in
    */queue/* | */tasks/* | */inbox/*)
        exit 0 ;;
    */logs/*)
        exit 0 ;;
    */dashboard.md)
        exit 0 ;;
    */CLAUDE.md)
        exit 0 ;;
    */instructions/*)
        exit 0 ;;
    */context/*)
        exit 0 ;;
    */projects/*)
        exit 0 ;;
    */config/*)
        exit 0 ;;
    */docs/*)
        exit 0 ;;
esac

# --- Check ninja status ---
active_ninjas=""
for task_yaml in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_yaml" ] || continue
    ninja_name="$(basename "$task_yaml" .yaml)"
    # Skip non-ninja files
    case "$ninja_name" in
        hayate|kagemaru|hanzo|saizo|kotaro|tobisaru) ;;
        *) continue ;;
    esac
    status="$(grep -m1 '^\s*status:' "$task_yaml" 2>/dev/null | sed 's/.*status:\s*//' | tr -d "' \"" || true)"
    if [ "$status" = "acknowledged" ] || [ "$status" = "in_progress" ]; then
        active_ninjas="${active_ninjas}${ninja_name}(${status}) "
    fi
done

if [ -z "$active_ninjas" ]; then
    # No active ninja → safe to edit
    exit 0
fi

# --- BLOCK: ninja active + non-management path ---
emit_deny "BLOCK: 忍者稼働中(${active_ninjas})。家老の直接Edit/Write禁止(管理領域外: ${file_path})。忍者をidle化してから操作するか、cmdで忍者に指示せよ。[pre-karo-edit-guard]"
exit 2
