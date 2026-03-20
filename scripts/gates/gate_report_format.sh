#!/bin/bash
# gate_report_format.sh — 忍者報告YAMLのフォーマット検証
# 目的: 家老の手動フォーマット修正作業を根絶（karo_workarounds 5件連続同一問題）
# 知性の外部化原則: 正しいフォーマットを忍者の記憶に依存させず、自動検証で強制
# Usage: bash scripts/gates/gate_report_format.sh <report_yaml_path>
# Exit: 0=PASS, 1=FAIL(修正必要)

set -e

REPORT_PATH="$1"

if [ -z "$REPORT_PATH" ] || [ ! -f "$REPORT_PATH" ]; then
    echo "FAIL: report file not found: ${REPORT_PATH:-<empty>}" >&2
    exit 1
fi

# Python validation — checks all known failure patterns from karo_workarounds
RESULT=$(REPORT_PATH="$REPORT_PATH" python3 -c "
import yaml, os, sys

report_path = os.environ['REPORT_PATH']
errors = []

try:
    with open(report_path) as f:
        data = yaml.safe_load(f)
except Exception as e:
    print(f'FAIL: YAML parse error: {e}')
    sys.exit(1)

if not data or not isinstance(data, dict):
    print('FAIL: report is empty or not a dict')
    sys.exit(1)

# --- Required top-level fields ---
required = ['ac_version_read', 'binary_checks', 'files_modified', 'lesson_candidate', 'lessons_useful']
for field in required:
    if field not in data:
        errors.append(f'{field}: MISSING')

# --- lesson_candidate must be dict with 'found' ---
lc = data.get('lesson_candidate')
if lc is not None:
    if isinstance(lc, str):
        errors.append('lesson_candidate: is string (must be dict with found/title/detail)')
    elif isinstance(lc, dict):
        if 'found' not in lc:
            errors.append('lesson_candidate: missing \"found\" field')
        if not lc.get('found') and not lc.get('no_lesson_reason'):
            errors.append('lesson_candidate: found=false but no no_lesson_reason')
        if lc.get('found') and not lc.get('title'):
            errors.append('lesson_candidate: found=true but no title')
    else:
        errors.append(f'lesson_candidate: unexpected type {type(lc).__name__}')

# --- lessons_useful must be list of dicts ---
lu = data.get('lessons_useful')
if lu is not None:
    if isinstance(lu, str):
        errors.append('lessons_useful: is string (must be list of dicts)')
    elif isinstance(lu, list):
        for i, item in enumerate(lu):
            if isinstance(item, dict):
                if 'FILL_THIS' in str(item.get('useful', '')) or 'FILL_THIS' in str(item.get('reason', '')):
                    errors.append(f'lessons_useful[{i}]: contains FILL_THIS (must fill actual values)')
                if 'useful' not in item:
                    errors.append(f'lessons_useful[{i}]: missing \"useful\" field')
                if 'reason' not in item:
                    errors.append(f'lessons_useful[{i}]: missing \"reason\" field')
            else:
                errors.append(f'lessons_useful[{i}]: is {type(item).__name__} (must be dict)')
    else:
        errors.append(f'lessons_useful: unexpected type {type(lu).__name__}')

# --- purpose_validation should exist ---
if 'purpose_validation' not in data:
    errors.append('purpose_validation: MISSING')

# --- result.summary should exist ---
result = data.get('result', {})
if isinstance(result, dict):
    if not result.get('summary'):
        errors.append('result.summary: MISSING or empty')
else:
    errors.append('result: not a dict')

# --- Output ---
if errors:
    print('FAIL: ' + '; '.join(errors))
    sys.exit(1)
else:
    print('PASS')
    sys.exit(0)
" 2>&1) || true

echo "$RESULT"
if echo "$RESULT" | grep -q "^PASS"; then
    exit 0
else
    exit 1
fi
