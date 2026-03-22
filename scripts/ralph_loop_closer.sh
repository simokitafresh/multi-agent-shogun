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
if ! echo "$INPUT" | grep -q "^WARN:"; then
    exit 0
fi

# Parse REFLUX_CHECK line
REFLUX_LINE=$(echo "$INPUT" | grep "^REFLUX_CHECK:" || true)
if [ -z "$REFLUX_LINE" ]; then
    exit 0
fi

# Extract statuses
PI_STATUS=$(echo "$REFLUX_LINE" | sed -n 's/.*PI=\([A-Z]*\).*/\1/p')
RUNBOOK_STATUS=$(echo "$REFLUX_LINE" | sed -n 's/.*RUNBOOK=\([A-Z]*\).*/\1/p')
INSTRUCTIONS_STATUS=$(echo "$REFLUX_LINE" | sed -n 's/.*INSTRUCTIONS=\([A-Z]*\).*/\1/p')

# Extract lesson ID from output (e.g., "L123 added to ...")
LESSON_ID=$(echo "$INPUT" | grep -oP '^L\d+' | head -1 || true)

# Generate valid YAML via Python (avoids block scalar indentation issues)
export PROJECT_ID LESSON_TITLE LESSON_DETAIL SOURCE_CMD LESSON_ID PI_STATUS RUNBOOK_STATUS INSTRUCTIONS_STATUS
python3 << 'PYEOF'
import os, yaml, sys

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

print(yaml.dump(task, allow_unicode=True, default_flow_style=False, sort_keys=False).rstrip())
PYEOF
