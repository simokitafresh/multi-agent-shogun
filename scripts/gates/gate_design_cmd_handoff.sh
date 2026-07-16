#!/usr/bin/env bash
# LS086: design documents that declare a Phase/step -> command handoff table
# may not close with an unassigned implementation command.
set -euo pipefail

python3 - "$@" <<'PY'
import pathlib, re, sys

EMPTY = {'', '-', '—', '未起票', '未定', 'tbd', 'todo', 'pending'}
failed = []
checked = 0
for raw in sys.argv[1:]:
    path = pathlib.Path(raw)
    if path.suffix.lower() != '.md' or not path.is_file():
        continue
    lines = path.read_text(encoding='utf-8').splitlines()
    for i, line in enumerate(lines):
        if not (line.lstrip().startswith('|') and '起票cmd' in line):
            continue
        headers = [c.strip() for c in line.strip().strip('|').split('|')]
        try:
            col = headers.index('起票cmd')
        except ValueError:
            continue
        if i + 1 >= len(lines) or not re.match(r'^\s*\|(?:\s*:?-{3,}:?\s*\|)+\s*$', lines[i + 1]):
            continue
        checked += 1
        for row_no, row in enumerate(lines[i + 2:], i + 3):
            if not row.lstrip().startswith('|'):
                break
            cells = [c.strip() for c in row.strip().strip('|').split('|')]
            if len(cells) <= col:
                failed.append((path, row_no, '<列欠落>'))
                continue
            value = re.sub(r'[`*_]', '', cells[col]).strip()
            # Explicit deferral is valid only with a reason after ':' or '：'.
            deferred = re.match(r'^(?:保留|deferred|n/a)\s*[:：]\s*\S+', value, re.I)
            if value.lower() in EMPTY or (value.startswith('保留') and not deferred):
                failed.append((path, row_no, cells[col]))

if failed:
    for path, line, value in failed:
        print(f'BLOCK LS086: {path}:{line}: 起票cmd={value or "<empty>"}', file=sys.stderr)
    sys.exit(1)
print(f'PASS LS086: handoff_tables={checked} unresolved=0')
PY
