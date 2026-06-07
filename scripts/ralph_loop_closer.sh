#!/bin/bash
# ralph_loop_closer.sh — REFLUX_CHECK WARN → 修復タスク雛形自動生成
# ラルフループStep4断裂を修復: WARN検出→修復タスク雛形→家老が即配備
#
# Usage: bash scripts/lesson_write.sh ... 2>&1 | bash scripts/ralph_loop_closer.sh <project_id> "<lesson_title>" "<lesson_detail>" [source_cmd]
#
# 入力(stdin): lesson_write.shの全stdout
# 引数: project_id, lesson_title, lesson_detail, source_cmd(任意)
# 出力(stdout): 修復タスクYAML（WARN検出時のみ。WARNなし→出力なし・exit 0）
#
# 家老ワークフロー:
#   OUTPUT=$(bash scripts/lesson_write.sh ... 2>&1); echo "$OUTPUT"
#   TASK=$(echo "$OUTPUT" | bash scripts/ralph_loop_closer.sh <pj> "<title>" "<detail>" [src_cmd])
#   if [ -n "$TASK" ]; then echo "$TASK" > queue/tasks/{ninja}.yaml; deploy_task.sh {ninja}; fi

set -euo pipefail

PROJECT_ID="${1:-}"
LESSON_TITLE="${2:-}"
LESSON_DETAIL="${3:-}"
SOURCE_CMD="${4:-}"

if [ -z "$PROJECT_ID" ] || [ -z "$LESSON_TITLE" ] || [ -z "$LESSON_DETAIL" ]; then
    echo "Usage: ... | ralph_loop_closer.sh <project_id> \"<lesson_title>\" \"<lesson_detail>\" [source_cmd]" >&2
    exit 1
fi

# Read stdin
INPUT=$(cat)

# Check for WARN line — if absent, nothing to do
if [[ ! $INPUT =~ (^|$'\n')WARN: ]]; then
    exit 0
fi

# Parse REFLUX_CHECK line
REFLUX_LINE=""
while IFS= read -r line; do
    if [[ $line == REFLUX_CHECK:* ]]; then
        REFLUX_LINE="$line"
        break
    fi
done <<< "$INPUT"
if [ -z "$REFLUX_LINE" ]; then
    exit 0
fi

# Extract statuses
PI_STATUS=""
RUNBOOK_STATUS=""
INSTRUCTIONS_STATUS=""
[[ $REFLUX_LINE =~ PI=([A-Z]+) ]] && PI_STATUS="${BASH_REMATCH[1]}"
[[ $REFLUX_LINE =~ RUNBOOK=([A-Z]+) ]] && RUNBOOK_STATUS="${BASH_REMATCH[1]}"
[[ $REFLUX_LINE =~ INSTRUCTIONS=([A-Z]+) ]] && INSTRUCTIONS_STATUS="${BASH_REMATCH[1]}"

# Validate — empty status means parse failure (silent failure prevention)
if [ -z "$PI_STATUS" ] || [ -z "$RUNBOOK_STATUS" ] || [ -z "$INSTRUCTIONS_STATUS" ]; then
    echo "ERROR: ralph_loop_closer.sh: status extraction failed from REFLUX_LINE" >&2
    echo "  REFLUX_LINE: $REFLUX_LINE" >&2
    echo "  PI=${PI_STATUS:-<empty>} RUNBOOK=${RUNBOOK_STATUS:-<empty>} INSTRUCTIONS=${INSTRUCTIONS_STATUS:-<empty>}" >&2
    exit 1
fi

# Extract lesson ID from output (e.g., "L123 added to ...")
LESSON_ID=""
while IFS= read -r line; do
    if [[ $line =~ ^(L[0-9]+) ]]; then
        LESSON_ID="${BASH_REMATCH[1]}"
        break
    fi
done <<< "$INPUT"

# If every target is already present, no repair task is needed.
if [ "$PI_STATUS" != "MISSING" ] && [ "$RUNBOOK_STATUS" != "MISSING" ] && [ "$INSTRUCTIONS_STATUS" != "MISSING" ]; then
    exit 0
fi

# Generate YAML-compatible JSON without importing PyYAML on the hot path.
export PROJECT_ID LESSON_TITLE LESSON_DETAIL SOURCE_CMD LESSON_ID PI_STATUS RUNBOOK_STATUS INSTRUCTIONS_STATUS
python3 << 'PYEOF'
import json
import os
import sys

project_id = os.environ["PROJECT_ID"]
lesson_title = os.environ["LESSON_TITLE"]
lesson_detail = os.environ["LESSON_DETAIL"]
source_cmd = os.environ.get("SOURCE_CMD", "")
lesson_id = os.environ.get("LESSON_ID", "") or "unknown"
pi = os.environ.get("PI_STATUS", "FOUND")
runbook = os.environ.get("RUNBOOK_STATUS", "FOUND")
instructions = os.environ.get("INSTRUCTIONS_STATUS", "FOUND")

missing = []
if pi == "MISSING":
    missing.append("PI")
if runbook == "MISSING":
    missing.append("RUNBOOK")
if instructions == "MISSING":
    missing.append("INSTRUCTIONS")

if not missing:
    sys.exit(0)

# Build command text
lines = [
    f"ラルフループ穴修復: {lesson_id} ({lesson_title})",
    "",
    "教訓の知見を以下のMISSING箇所に反映せよ。",
    "",
    f"■ 教訓内容: {lesson_detail}",
    "",
    "■ 修復対象:",
]
if pi == "MISSING":
    lines.append(f"- [PI] projects/{project_id}.yaml の production_invariants に不変量を追加")
if runbook == "MISSING":
    lines.append(f"- [RUNBOOK] docs/rule/ の該当ランブックに知見を追記")
if instructions == "MISSING":
    lines.append(f"- [INSTRUCTIONS] instructions/ の該当ファイルに知見を追記")

command_text = "\n".join(lines)

# Build acceptance criteria
acs = []
ac_num = 0
if pi == "MISSING":
    ac_num += 1
    acs.append({
        "id": f"AC{ac_num}",
        "description": f"projects/{project_id}.yaml production_invariantsにこの教訓の不変量を追加",
        "binary_checks": [
            "production_invariants欄に不変量が追加されたか？",
            "不変量の内容が教訓の知見を正確に反映しているか？",
        ],
    })
if runbook == "MISSING":
    ac_num += 1
    acs.append({
        "id": f"AC{ac_num}",
        "description": f"docs/rule/ の該当ランブックにこの教訓の知見を追記",
        "binary_checks": [
            "該当ランブックに知見が追記されたか？",
            "追記内容が既存ルールと整合しているか？",
        ],
    })
if instructions == "MISSING":
    ac_num += 1
    acs.append({
        "id": f"AC{ac_num}",
        "description": f"instructions/ の該当ファイルにこの教訓の知見を追記",
        "binary_checks": [
            "該当instructionsファイルに知見が追記されたか？",
            "追記内容が既存ルールと整合しているか？",
        ],
    })

task = {
    "status": "idle",
    "task_type": "implement",
    "project": project_id,
    "ralph_loop_repair": True,
    "pi_missing": pi == "MISSING",
    "source_lesson": lesson_id,
    "source_cmd": source_cmd,
    "command": command_text,
    "acceptance_criteria": acs,
    "context_files": [f"projects/{project_id}.yaml"],
    "stop_for": [],
    "never_stop_for": [],
}

print(json.dumps(task, ensure_ascii=False, indent=2))
PYEOF
