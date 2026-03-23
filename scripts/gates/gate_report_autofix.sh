#!/bin/bash
# gate_report_autofix.sh — 報告YAMLの機械的フォーマット自動修正
# 原則: 品質に影響しない純粋な構造変換のみ。内容欠落はBLOCKして家老/軍師に回す。
# 局所免疫: 忍者のペインで走る。家老のCTXを消費しない。
# Usage: bash scripts/gates/gate_report_autofix.sh <report_yaml_path>
# Exit: 0=修正完了(or修正不要), 1=auto-fix不可(要エージェント判断)
# Stdout: AUTO-FIXED: ... / NO-FIX-NEEDED / UNFIXABLE: ...

set -e

REPORT_PATH="$1"

if [ -z "$REPORT_PATH" ] || [ ! -f "$REPORT_PATH" ]; then
    echo "UNFIXABLE: report file not found: ${REPORT_PATH:-<empty>}" >&2
    exit 1
fi

RESULT=$(REPORT_PATH="$REPORT_PATH" python3 -c "
import yaml, os, sys, copy

report_path = os.environ['REPORT_PATH']

try:
    with open(report_path) as f:
        raw = f.read()
    data = yaml.safe_load(raw)
except Exception as e:
    print(f'UNFIXABLE: YAML parse error: {e}')
    sys.exit(1)

if not data or not isinstance(data, dict):
    print('UNFIXABLE: report is empty or not a dict')
    sys.exit(1)

fixes = []

# === Fix 1: report: wrapper → flatten ===
# パターン: 忍者が report: の下に全フィールドをネストする旧形式
if 'report' in data and isinstance(data['report'], dict):
    inner = data.pop('report')
    # 既存のトップレベルキー(cmd_id等)は保持し、inner側で上書き
    data.update(inner)
    fixes.append('report:ラップ→フラット化')

# === Fix 2: lessons_useful dict → list ===
# パターン: 忍者が 0: {}, 1: {} のdict形式で記入(YAML listではなく)
lu = data.get('lessons_useful')
if isinstance(lu, dict):
    # キーが数値的(0,1,2...)ならlist化
    try:
        sorted_keys = sorted(lu.keys(), key=lambda k: int(k) if str(k).isdigit() else k)
    except (ValueError, TypeError):
        sorted_keys = sorted(lu.keys())
    data['lessons_useful'] = [lu[k] for k in sorted_keys]
    fixes.append('lessons_useful dict→list変換')

# === Fix 3: files_modified string list → dict list ===
# パターン: 忍者が ['path/to/file'] のstring listで記入
fm = data.get('files_modified')
if isinstance(fm, list):
    needs_fix = False
    new_fm = []
    for item in fm:
        if isinstance(item, str):
            new_fm.append({'path': item, 'change': 'modified'})
            needs_fix = True
        else:
            new_fm.append(item)
    if needs_fix:
        data['files_modified'] = new_fm
        fixes.append('files_modified string→dict変換')

# === Fix 4: lessons_useful items — id欠落時にindex付番 ===
lu = data.get('lessons_useful')
if isinstance(lu, list):
    for i, item in enumerate(lu):
        if isinstance(item, dict) and 'id' not in item:
            item['id'] = f'UNKNOWN_{i}'
            fixes.append(f'lessons_useful[{i}]: id=UNKNOWN_{i}仮付番')

# === Fix 5: binary_checks AC values string → list ===
# パターン: 忍者がAC値を '[{check: ..., result: ...}]' の文字列で記入
bc = data.get('binary_checks')
if isinstance(bc, dict):
    bc_fixed = False
    for ac_key, ac_val in bc.items():
        if isinstance(ac_val, str) and ac_val.strip().startswith('['):
            try:
                parsed = yaml.safe_load(ac_val)
                if isinstance(parsed, list):
                    bc[ac_key] = parsed
                    bc_fixed = True
            except Exception:
                pass
    if bc_fixed:
        fixes.append('binary_checks string→list変換')

# === Fix 8: binary_checks AC values dict → list wrap ===
# パターン: 忍者がAC値を {check: ..., result: ...} の単一dictで記入(listでない)
bc = data.get('binary_checks')
if isinstance(bc, dict):
    bc_dict_fixed = False
    for ac_key, ac_val in bc.items():
        if isinstance(ac_val, dict):
            bc[ac_key] = [ac_val]
            bc_dict_fixed = True
    if bc_dict_fixed:
        fixes.append('binary_checks dict→list wrap')

# === Fix 6: lessons_useful null → empty list ===
if 'lessons_useful' in data and data['lessons_useful'] is None:
    data['lessons_useful'] = []
    fixes.append('lessons_useful null→空list')

# === Fix 7: acceptance_criteria wrapper → flatten ===
# パターン: 忍者がacceptance_criteriaの下に結果を入れる独自形式
if 'acceptance_criteria' in data and 'binary_checks' not in data:
    ac = data.get('acceptance_criteria')
    if isinstance(ac, dict):
        # acceptance_criteria形式からbinary_checks形式への変換は
        # 構造が不明確なためauto-fixしない（品質に関わる）
        pass

# === Fix 9: verdict空/欠落 → binary_checksから推定 ===
# パターン: 忍者がverdictを空のまま提出するがbinary_checksは記入済み
verdict_val = data.get('verdict')
if not verdict_val or (isinstance(verdict_val, str) and verdict_val.strip() == ''):
    bc = data.get('binary_checks')
    if isinstance(bc, dict) and bc:
        pass_count = 0
        fail_count = 0
        for ac_key, ac_val in bc.items():
            checks = ac_val if isinstance(ac_val, list) else []
            for chk in checks:
                if isinstance(chk, dict):
                    r = str(chk.get('result', '')).strip().upper()
                    if r in ('PASS', 'YES'):
                        pass_count = pass_count + 1
                    elif r in ('FAIL', 'NO'):
                        fail_count = fail_count + 1
        if pass_count + fail_count > 0:
            data['verdict'] = 'FAIL' if fail_count > 0 else 'PASS'
            fixes.append(f'verdict推定({pass_count}PASS/{fail_count}FAIL)')

# === Fix 10: lesson_candidate.found=false + no_lesson_reason空 → N/A ===
# パターン: 忍者がfound=falseにしたがno_lesson_reasonを空のまま提出
lc = data.get('lesson_candidate')
if isinstance(lc, dict):
    found_val = lc.get('found')
    if found_val is False or (isinstance(found_val, str) and found_val.strip().lower() == 'false'):
        nlr = lc.get('no_lesson_reason')
        if not nlr or (isinstance(nlr, str) and nlr.strip() in ('', '""')):
            lc['no_lesson_reason'] = 'N/A'
            fixes.append('no_lesson_reason空→N/A')

# === Write back if changed ===
if fixes:
    with open(report_path, 'w') as f:
        yaml.dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
    print('AUTO-FIXED: ' + '; '.join(fixes))
else:
    print('NO-FIX-NEEDED')
" 2>&1) || true

echo "$RESULT"

# --- Log auto-fix actions ---
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_FILE="$REPO_ROOT/logs/gate_fire_log.yaml"
TS=$(date -Is)

if echo "$RESULT" | grep -q "^AUTO-FIXED"; then
    FIXED_ITEMS=$(echo "$RESULT" | sed 's/^AUTO-FIXED: //' | sed 's/"/\\"/g')
    (
        flock -w 5 200 2>/dev/null
        printf -- '- ts: "%s", file: "%s", result: AUTO-FIXED, fixes: "%s"\n' "$TS" "$REPORT_PATH" "$FIXED_ITEMS" >> "$LOG_FILE"
    ) 200>"$LOG_FILE.lock" 2>/dev/null || true
    exit 0
elif echo "$RESULT" | grep -q "^NO-FIX-NEEDED"; then
    exit 0
else
    # UNFIXABLE — needs agent intervention
    REASON=${RESULT//\"/\\\"}
    (
        flock -w 5 200 2>/dev/null
        printf -- '- ts: "%s", file: "%s", result: UNFIXABLE, reason: "%s"\n' "$TS" "$REPORT_PATH" "$REASON" >> "$LOG_FILE"
    ) 200>"$LOG_FILE.lock" 2>/dev/null || true
    exit 1
fi
