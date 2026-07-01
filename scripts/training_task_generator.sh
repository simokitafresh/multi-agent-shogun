#!/usr/bin/env bash
# semantic-links: [[修行サイクル]] [[Skill設計ルール]]
# training_task_generator.sh — FAILパターンから修行課題タスクYAML骨格を自動生成し家老に通知
#
# Usage:
#   bash scripts/training_task_generator.sh --skill <name> --gate <gate> --reason <reason> --streak <N>
#
# Called by skill_auto_improve.sh when escalation is detected.
# Generates a training task YAML skeleton in queue/training/ and notifies karo via inbox.
# Karo reviews and deploys (no auto-deploy: safety valve).

set -euo pipefail

REPO_ROOT="${SHOGUN_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
INBOX_SCRIPT="${REPO_ROOT}/scripts/inbox_write.sh"
TRAINING_DIR="${REPO_ROOT}/queue/training"

skill=""
gate=""
reason=""
streak=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --skill) skill="${2:-}"; shift 2 ;;
        --gate) gate="${2:-}"; shift 2 ;;
        --reason) reason="${2:-}"; shift 2 ;;
        --streak) streak="${2:-}"; shift 2 ;;
        --repo-root) REPO_ROOT="${2:-}"; INBOX_SCRIPT="${REPO_ROOT}/scripts/inbox_write.sh"; TRAINING_DIR="${REPO_ROOT}/queue/training"; shift 2 ;;
        -h|--help) sed -n '1,11p' "$0" >&2; exit 0 ;;
        *) echo "ERROR: Unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$skill" ]; then
    echo "ERROR: --skill is required" >&2
    exit 2
fi

# --- Map FAIL reason to training level ---
# Based on training-cycle.md §2 BLOCKパターン一覧
reason_lower=$(echo "$reason" | tr '[:upper:]' '[:lower:]')
level=1
block_patterns=""

# L3 check first (most specific)
if echo "$reason_lower" | grep -qE 'self_gate_check'; then
    level=3
    block_patterns="#11: self_gate_check非二値"
# L2 checks
elif echo "$reason_lower" | grep -qE 'lessons_useful|draft_lessons'; then
    level=2
    block_patterns="#2: lessons_useful dict形式"
elif echo "$reason_lower" | grep -qE 'lesson_candidate'; then
    level=2
    block_patterns="#5/#6: lesson_candidate構造不備"
# L1 checks (default level)
elif echo "$reason_lower" | grep -qE 'verdict'; then
    block_patterns="#1: verdict非二値"
elif echo "$reason_lower" | grep -qE 'binary_checks|bc:|bc_'; then
    block_patterns="#3: binary_checks string形式"
elif echo "$reason_lower" | grep -qE 'fill_this'; then
    block_patterns="#4: FILL_THIS残存"
elif echo "$reason_lower" | grep -qE 'ac_version'; then
    block_patterns="#7: ac_version_read欠落"
elif echo "$reason_lower" | grep -qE 'files_modified'; then
    block_patterns="#8: files_modified形式不備"
elif echo "$reason_lower" | grep -qE 'purpose_validation'; then
    block_patterns="#9: purpose_validation欠落"
elif echo "$reason_lower" | grep -qE 'result\.summary|summary.*empty'; then
    block_patterns="#10: result.summary空"
else
    block_patterns="general: gate FAIL蓄積(L${level})"
fi

# --- Generate training task YAML skeleton ---
mkdir -p "$TRAINING_DIR"
timestamp=$(date "+%Y%m%d%H%M%S")
skill_slug=$(printf '%s' "$skill" | tr -c '[:alnum:]_-' '_' | sed -E 's/_+/_/g; s/^_//; s/_$//')
[ -n "$skill_slug" ] || skill_slug="skill"
task_file="${TRAINING_DIR}/training_L${level}_${skill_slug}_${timestamp}.yaml"

yaml_dq_escape() {
    local value="${1:-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

# Truncate reason for YAML safety (max 300 chars)
safe_skill=$(yaml_dq_escape "$skill")
safe_gate=$(yaml_dq_escape "${gate:-unknown}")
safe_reason=$(yaml_dq_escape "$(printf '%s' "$reason" | head -c 300)")
safe_block_patterns=$(yaml_dq_escape "$block_patterns")
parent_cmd="cmd_training_L${level}_${skill_slug}_${timestamp}"
target_path="skills/${skill}/SKILL.md"
if [ ! -f "${REPO_ROOT}/${target_path}" ]; then
    target_path="skills/${skill_slug}/SKILL.md"
fi
if [ ! -f "${REPO_ROOT}/${target_path}" ]; then
    target_path="context/training-cycle.md"
fi
safe_target_path=$(yaml_dq_escape "$target_path")
generated_at=$(date "+%Y-%m-%dT%H:%M:%S")

cat > "$task_file" <<YAML
# Auto-generated training task skeleton
# Source: skill_auto_improve.sh escalation (unchanged_streak=${streak})
# Review and deploy: bash scripts/deploy_task.sh --direct --yaml ${task_file} <ninja>
# !! 家老は内容を確認し配備判断せよ。自動配備ではない !!
task:
  parent_cmd: "${parent_cmd}"
  task_id: "${parent_cmd}_training"
  task_type: skill_training
  project: infra
  target_path: "${safe_target_path}"
  scout_exempt: true
  status: assigned
  purpose: "skill=${safe_skill} のgate FAIL(${safe_block_patterns})に対するL${level}修行。BLOCKパターンを実戦前に学習し一発PASS率を向上させる"
  command: "training_proposal.fail_reason を再現し、${safe_skill} の手順で ${safe_gate} をPASSへ戻す。report_field_set.sh/verdict自動導出/binary_checksのどこで同種FAILを防ぐかを報告する。"
  acceptance_criteria:
    AC1:
      description: "gate FAIL原因(${safe_block_patterns})を対象スキル手順と照合し、どの記入・検証手順で防ぐかを説明する"
      binary_checks:
        - "training_proposal.fail_reasonを読み、該当するBLOCKパターンを特定したか: yes/no"
        - "対象スキル手順のどのステップで同種FAILを防ぐかを報告したか: yes/no"
    AC2:
      description: "報告YAMLテンプレートをreport_field_set.sh経由で完成させ、${safe_gate}を実行してPASS/FAILを数値で確認する"
      binary_checks:
        - "report_field_set.sh経由で必須フィールドを記入したか: yes/no"
        - "全binary_checksのresultをyes/noで記入したか: yes/no"
        - "${safe_gate}を実行し結果を報告したか: yes/no"
    AC3:
      description: "同じFAILを次回防ぐlesson_candidateをorigin付きで記録し、verdictとbinary_checksの整合を確認する"
      binary_checks:
        - "lesson_candidateに次回追加すべきチェックをorigin付きで記入したか: yes/no"
        - "verdictがgateまたはbinary_checksと矛盾していないことを確認したか: yes/no"

training_proposal:
  skill: "${safe_skill}"
  gate: "${safe_gate}"
  fail_reason: "${safe_reason}"
  training_level: "L${level}"
  block_patterns: "${safe_block_patterns}"
  suggested_parent_cmd: "${parent_cmd}"
  suggested_purpose: "skill=${safe_skill} のgate FAIL(${safe_block_patterns})に対する修行。BLOCKパターンを実戦前に学習し一発PASS率を向上させる"
  unchanged_streak: ${streak}
  generated_at: "${generated_at}"
  status: pending_karo_review
YAML

echo "TRAINING_TASK_GENERATED: ${task_file} level=L${level} skill=${skill}"

# --- Notify karo via inbox ---
if [ -f "$INBOX_SCRIPT" ]; then
    bash "$INBOX_SCRIPT" karo \
        "修行課題自動生成: skill=${skill} level=L${level} gate=${gate:-unknown} streak=${streak}。YAML: ${task_file} を確認し配備判断せよ" \
        training_task_generated \
        skill_auto_improve
    echo "KARO_NOTIFIED: training task for ${skill}"
else
    echo "WARN: inbox_write.sh not found at ${INBOX_SCRIPT}" >&2
fi
