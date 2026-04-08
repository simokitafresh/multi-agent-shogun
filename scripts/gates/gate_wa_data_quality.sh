#!/usr/bin/env bash
# gate_wa_data_quality.sh — karo_workarounds.yaml データ品質ゲート
# GP-063: WA計測の汚染検出+自動修復
#
# 検出パターン:
#   1. False WA: workaround=true + detail内にcleanキーワード → clean化
#   2. 重複エントリ: 同一cmd_id+ninja → 後勝ち(cleanがあればclean)
#   3. GP-049バイパス: workaround=true + detail<10文字 → WARN
#   4. ninja名汚染: 既知忍者名以外のninja値 → WARN
#
# Usage:
#   CHECK: bash scripts/gates/gate_wa_data_quality.sh
#   FIX:   bash scripts/gates/gate_wa_data_quality.sh --fix
#
# Exit: 0=CLEAN, 1=ISSUES_FOUND(check) or FIXED(fix mode)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WA_FILE="$REPO_ROOT/logs/karo_workarounds.yaml"
FIX_MODE=false

if [[ "${1:-}" == "--fix" ]]; then
    FIX_MODE=true
fi

if [[ ! -f "$WA_FILE" ]]; then
    echo "PASS: karo_workarounds.yaml not found"
    exit 0
fi

RESULT=$(FIX_MODE="$FIX_MODE" WA_FILE="$WA_FILE" python3 -c "
import yaml, re, os, sys, copy

wa_file = os.environ['WA_FILE']
fix_mode = os.environ['FIX_MODE'] == 'true'

with open(wa_file) as f:
    raw = f.read()

data = yaml.safe_load(raw)

# Support bare list or dict wrapper
if isinstance(data, list):
    entries = data
    is_bare_list = True
elif isinstance(data, dict):
    for key in ('workarounds', 'entries'):
        if key in data:
            entries = data[key]
            is_bare_list = False
            break
    else:
        entries = []
        is_bare_list = True
else:
    entries = []
    is_bare_list = True

if not isinstance(entries, list):
    print('FAIL: entries is not a list')
    sys.exit(1)

issues = []
fixes = []

KNOWN_NINJAS = {'hayate', 'kagemaru', 'hanzo', 'saizo', 'kotaro', 'tobisaru', 'unknown'}
CLEAN_KEYWORDS = ['workaround不要', 'WA不要', '修正なし', '対処不要', '修正不要', '正規フロー完了', '問題なし']

# --- Check 1: False WAs ---
for i, e in enumerate(entries):
    if not isinstance(e, dict):
        continue
    wa = e.get('workaround', False)
    detail = str(e.get('detail', ''))
    cat = e.get('category', '')
    cmd_id = str(e.get('cmd_id', ''))

    if wa and cat != 'clean':
        for kw in CLEAN_KEYWORDS:
            if kw in detail:
                issues.append(f'FALSE_WA[{i}]: {cmd_id} — detail contains \"{kw}\" but workaround=true')
                if fix_mode:
                    e['workaround'] = False
                    e['category'] = 'clean'
                    fixes.append(f'FIX[{i}]: {cmd_id} → workaround=false, category=clean')
                break

# --- Check 2: Duplicate entries (same cmd_id + ninja) ---
seen = {}
dup_indices = []
for i, e in enumerate(entries):
    if not isinstance(e, dict):
        continue
    cmd_id = str(e.get('cmd_id', ''))
    ninja = str(e.get('ninja', ''))
    key = f'{cmd_id}|{ninja}'

    if key in seen:
        prev_i = seen[key]
        prev_e = entries[prev_i]
        # If one is clean and other is WA, keep clean
        prev_wa = prev_e.get('workaround', False)
        curr_wa = e.get('workaround', False)

        if not curr_wa and prev_wa:
            # Current is clean, previous is WA → remove previous
            issues.append(f'DUPLICATE[{prev_i},{i}]: {cmd_id}/{ninja} — keeping clean entry [{i}]')
            dup_indices.append(prev_i)
            seen[key] = i
        elif curr_wa and not prev_wa:
            # Previous is clean, current is WA → remove current
            issues.append(f'DUPLICATE[{prev_i},{i}]: {cmd_id}/{ninja} — keeping clean entry [{prev_i}]')
            dup_indices.append(i)
        else:
            # Both same type → keep latest (higher index)
            issues.append(f'DUPLICATE[{prev_i},{i}]: {cmd_id}/{ninja} — keeping latest [{i}]')
            dup_indices.append(prev_i)
            seen[key] = i
    else:
        seen[key] = i

if fix_mode and dup_indices:
    # Remove duplicates (reverse order to preserve indices)
    for idx in sorted(set(dup_indices), reverse=True):
        removed = entries.pop(idx)
        fixes.append(f'REMOVED[{idx}]: {removed.get(\"cmd_id\",\"?\")}/{removed.get(\"ninja\",\"?\")}')

# --- Check 3: GP-049 bypass (detail too short) ---
for i, e in enumerate(entries):
    if not isinstance(e, dict):
        continue
    wa = e.get('workaround', False)
    detail = str(e.get('detail', ''))
    cmd_id = str(e.get('cmd_id', ''))

    if wa and e.get('category') != 'clean':
        if detail in ('none', 'null', '') or (0 < len(detail) < 10):
            issues.append(f'GP049_BYPASS[{i}]: {cmd_id} — detail=\"{detail}\" (too short/placeholder)')

# --- Check 4: Ninja name corruption ---
for i, e in enumerate(entries):
    if not isinstance(e, dict):
        continue
    ninja = str(e.get('ninja', ''))
    cmd_id = str(e.get('cmd_id', ''))

    if ninja and ninja not in KNOWN_NINJAS:
        issues.append(f'NINJA_CORRUPT[{i}]: {cmd_id} — ninja=\"{ninja}\" not in known list')

# --- Output ---
if not issues:
    print('PASS: no data quality issues')
    sys.exit(0)

print(f'ISSUES: {len(issues)}')
for iss in issues:
    print(f'  {iss}')

if fix_mode and fixes:
    # Write back (yaml.dump禁止: マルチライン消失+pre-commit BLOCK。手書き出力)
    import tempfile
    def _yaml_val(v):
        if isinstance(v, bool):
            return 'true' if v else 'false'
        if isinstance(v, (int, float)):
            return str(v)
        s = str(v)
        if not s or ':' in s or '#' in s or s.startswith('{') or s.startswith('[') or '\\n' in s or s in ('true','false','null','yes','no'):
            return \"'\" + s.replace(\"'\", \"''\") + \"'\"
        return s
    out_entries = entries if is_bare_list else data.get('workarounds', data.get('entries', entries))
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(wa_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
            for entry in out_entries:
                if not isinstance(entry, dict):
                    continue
                first = True
                for k, v in entry.items():
                    prefix = '- ' if first else '  '
                    f.write(f'{prefix}{k}: {_yaml_val(v)}\\n')
                    first = False
        os.replace(tmp_path, wa_file)
    except Exception:
        try: os.unlink(tmp_path)
        except OSError: pass
        raise
    print(f'\\nFIXED: {len(fixes)} changes applied')
    for fix in fixes:
        print(f'  {fix}')

if not fix_mode:
    print(f'\\nRun with --fix to auto-repair')

sys.exit(1)
" 2>&1) || true

echo "$RESULT"

if echo "$RESULT" | grep -q "^PASS"; then
    exit 0
else
    exit 1
fi
