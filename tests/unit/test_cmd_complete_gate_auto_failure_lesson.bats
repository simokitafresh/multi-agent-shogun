#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

@test "GATE FAIL section invokes auto_failure_lesson.sh for resolved reports" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")

decision_idx = text.index('if [ "$ALL_CLEAR" = true ]; then')
fail_text = text[decision_idx:]
section_idx = fail_text.index('Auto-failure lessons for GATE FAIL')
section = fail_text[section_idx:section_idx + 1600]

required = [
    'auto_failure_lesson.sh',
    'for task_file in "${MATCHING_TASK_FILES[@]}"',
    'report_file=$(resolve_report_file "$ninja_name")',
    'bash "$SCRIPT_DIR/scripts/auto_failure_lesson.sh" "$report_file"',
    'non-blocking',
]
missing = [marker for marker in required if marker not in section]
if missing:
    raise SystemExit(f"missing markers: {missing}")

print("OK: FAIL section calls auto_failure_lesson.sh for each resolved report")
PY
    [ "$status" -eq 0 ]
}

@test "PASS path auto_draft_lesson.sh call remains before GATE CLEAR/BLOCK decision" {
    run python3 - "$SRC_GATE_SCRIPT" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")

auto_draft_idx = text.index('bash "$SCRIPT_DIR/scripts/auto_draft_lesson.sh" "$report_file"')
decision_idx = text.index('if [ "$ALL_CLEAR" = true ]; then')
auto_failure_idx = text.index('Auto-failure lessons for GATE FAIL')

if not auto_draft_idx < decision_idx < auto_failure_idx:
    raise SystemExit("auto_draft_lesson.sh PASS path order changed")

print("OK: PASS auto_draft_lesson.sh path remains before final GATE decision")
PY
    [ "$status" -eq 0 ]
}
