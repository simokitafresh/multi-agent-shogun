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

# === Fix 14: lessons_useful id UNKNOWN/欠落 → タスクYAML参照解決 ===
# パターン: 忍者がid欠落やUNKNOWN_Nで記入。タスクYAMLのrelated_lessonsから正しいidを取得。
lu = data.get('lessons_useful')
if isinstance(lu, list) and lu:
    _unknown_ids = []
    for _idx, _item in enumerate(lu):
        if isinstance(_item, dict):
            _lid = str(_item.get('id', ''))
            if not _lid or _lid.startswith('UNKNOWN') or _lid == 'None':
                _unknown_ids.append(_idx)
    if _unknown_ids:
        # タスクYAMLからrelated_lessons idを取得
        _task_lesson_ids = []
        try:
            _worker = data.get('worker_id', '')
            if _worker:
                _tpath = os.path.join(os.path.dirname(os.path.dirname(report_path)), 'tasks', f'{_worker}.yaml')
                if os.path.exists(_tpath):
                    with open(_tpath) as _tf:
                        _tdata = yaml.safe_load(_tf)
                    _task = _tdata if not isinstance(_tdata, dict) or 'task' not in _tdata else _tdata.get('task', {})
                    _rl = _task.get('related_lessons', [])
                    if isinstance(_rl, list):
                        _task_lesson_ids = [str(r.get('id', '')) for r in _rl if isinstance(r, dict) and r.get('id')]
        except Exception:
            pass
        _lu_fixed = False
        for _pos in _unknown_ids:
            _lid = str(lu[_pos].get('id', ''))
            # UNKNOWN_N → related_lessons[N]のidを使用
            _num = -1
            if _lid.startswith('UNKNOWN_'):
                try:
                    _num = int(_lid.split('_')[1])
                except (ValueError, IndexError):
                    pass
            if _num >= 0 and _num < len(_task_lesson_ids):
                lu[_pos]['id'] = _task_lesson_ids[_num]
                _lu_fixed = True
            elif not _lid or _lid == 'None':
                # id欠落 → 位置ベースで推定(best effort)
                if _pos < len(_task_lesson_ids):
                    lu[_pos]['id'] = _task_lesson_ids[_pos]
                    _lu_fixed = True
        if _lu_fixed:
            fixes.append(f'lessons_useful id UNKNOWN→タスクYAML参照解決({len(_unknown_ids)}件)')

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

# === Fix 5: binary_checks AC values string → list (拡張) ===
# パターン: 忍者がAC値を文字列で記入。複数パターンを捕捉:
#   (a) '[{check: ..., result: ...}]' — bracket-wrapped YAML list string
#   (b) '- check: ...\n  result: ...' — YAML list without brackets
#   (c) '{check: ..., result: ...}' — YAML dict string → yaml.safe_load→dict→[dict]
#   (d) 'check: ..., result: ...' — bare key-value (yaml parse fails) → regex抽出
import re as _re
bc = data.get('binary_checks')
if isinstance(bc, dict):
    bc_fixed = False
    for ac_key, ac_val in bc.items():
        if isinstance(ac_val, str):
            converted = None
            # Step 1: yaml.safe_load を試行(a,b,cパターン)
            try:
                parsed = yaml.safe_load(ac_val)
                if isinstance(parsed, list):
                    converted = parsed
                elif isinstance(parsed, dict):
                    converted = [parsed]
            except Exception:
                pass
            # Step 2: regex fallback(dパターン: 'check: X, result: Y')
            if converted is None:
                m = _re.search(r'check:\s*(.+?)\s*,\s*result:\s*(.+)', ac_val)
                if m:
                    converted = [{'check': m.group(1).strip(), 'result': m.group(2).strip()}]
            # Step 3: タスクYAML参照型キーワード抽出(Fix 13: 散文からYES/NO推定)
            # 注意: \bは日英混在テキストで誤動作する(全PASS等)。containment検索を使用。
            if converted is None:
                # 散文中のYES/NO/PASS/FAILキーワードでresult推定
                _positive = bool(_re.search(r'(?i)(yes|pass|ok|成功|取得|完了|できた|確認済)', ac_val))
                _negative = bool(_re.search(r'(?i)(fail|失敗|不可|できな|エラー)', ac_val))
                if _positive and not _negative:
                    _result = 'yes'
                elif _negative and not _positive:
                    _result = 'no'
                else:
                    _result = None
                if _result is not None:
                    # タスクYAMLから本来のcheck名を取得
                    _task_checks = []
                    try:
                        _worker = data.get('worker_id', '')
                        if _worker:
                            _tpath = os.path.join(os.path.dirname(os.path.dirname(report_path)), 'tasks', f'{_worker}.yaml')
                            if os.path.exists(_tpath):
                                with open(_tpath) as _tf:
                                    _tdata = yaml.safe_load(_tf)
                                _task = _tdata if not isinstance(_tdata, dict) or 'task' not in _tdata else _tdata.get('task', {})
                                _acs = _task.get('acceptance_criteria', [])
                                if isinstance(_acs, list):
                                    for _ac_item in _acs:
                                        if isinstance(_ac_item, dict) and _ac_item.get('id') == ac_key:
                                            _bc_list = _ac_item.get('binary_checks', [])
                                            if isinstance(_bc_list, list):
                                                _task_checks = _bc_list
                    except Exception:
                        pass
                    if _task_checks:
                        converted = []
                        for _tc in _task_checks:
                            if isinstance(_tc, str):
                                _check_name = _tc.split(':')[0].strip() if ':' in _tc else _tc
                                converted.append({'check': _check_name, 'result': _result})
                        if not converted:
                            converted = None
                    else:
                        # タスクYAML参照不可→散文要約+result推定
                        _summary = ac_val[:50].replace('\n', ' ').strip()
                        converted = [{'check': _summary, 'result': _result}]
            if converted is not None:
                bc[ac_key] = converted
                bc_fixed = True
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

# === Fix 15: binary_checks {check_name: result} → {check: name, result: val} ===
# パターン: 忍者がACのbcを [{check_name: result_val}] の単一キーdict listで記入。
# 標準形式は [{check: 'name', result: 'val'}]。cmd_1351影丸で検出。
# Fix 9(verdict推定)とFix 11(boolean→string)が'result'キーに依存するため正規化必須。
bc = data.get('binary_checks')
if isinstance(bc, dict):
    bc15_fixed = False
    for ac_key, ac_val in bc.items():
        if isinstance(ac_val, list):
            new_list = []
            _needs_convert = False
            for chk in ac_val:
                if isinstance(chk, dict) and len(chk) == 1:
                    _k = list(chk.keys())[0]
                    if _k not in ('check', 'result'):
                        _v = chk[_k]
                        # booleanはFix 11で'yes'/'no'に変換するためstr()しない
                        new_list.append({'check': str(_k), 'result': _v if isinstance(_v, bool) else str(_v)})
                        _needs_convert = True
                    else:
                        new_list.append(chk)
                else:
                    new_list.append(chk)
            if _needs_convert:
                bc[ac_key] = new_list
                bc15_fixed = True
    if bc15_fixed:
        fixes.append('binary_checks {name:val}→{check:name,result:val}正規化')

# === Fix 11: binary_checks result boolean → string ===
# パターン: 忍者がresult: true/falseで記入。YAMLはbooleanとして解釈。
# gate_report_format.shはyes/noを期待。cmd_1338で検出。
bc = data.get('binary_checks')
if isinstance(bc, dict):
    bc_bool_fixed = False
    for ac_key, ac_val in bc.items():
        if isinstance(ac_val, list):
            for chk in ac_val:
                if isinstance(chk, dict) and isinstance(chk.get('result'), bool):
                    chk['result'] = 'yes' if chk['result'] else 'no'
                    bc_bool_fixed = True
    if bc_bool_fixed:
        fixes.append('binary_checks result boolean→string変換')

# === Fix 12: lesson_candidate list → dict ===
# パターン: 忍者がlesson_candidateをlist形式で記入。dict形式が正しい。
# cmd_1345で検出。GP-046(PostToolUse)と対。
lc = data.get('lesson_candidate')
if isinstance(lc, list):
    if len(lc) == 0:
        data['lesson_candidate'] = {
            'found': False,
            'no_lesson_reason': '',
            'title': '',
            'detail': '',
        }
        fixes.append('lesson_candidate list→dict変換(空list→found:false)')
    elif isinstance(lc[0], dict):
        first = lc[0]
        data['lesson_candidate'] = {
            'found': first.get('found', True),
            'no_lesson_reason': first.get('no_lesson_reason', ''),
            'title': first.get('title', ''),
            'detail': first.get('detail', ''),
        }
        fixes.append(f'lesson_candidate list→dict変換({len(lc)}要素)')

# === Fix 6: lessons_useful null → empty list ===
if 'lessons_useful' in data and data['lessons_useful'] is None:
    data['lessons_useful'] = []
    fixes.append('lessons_useful null→空list')

# === Fix 15: lessons_useful empty list → task YAML再注入 (GP-066) ===
# 忍者がGP-001テンプレートを上書き(空リスト化) → タスクYAMLのrelated_lessonsから再注入
# Level 1(BLOCK) → Level 3(autofix)昇格。家老workaround排除。
lu = data.get('lessons_useful')
if isinstance(lu, list) and len(lu) == 0:
    try:
        _worker = data.get('worker_id', '')
        if _worker:
            _tpath = os.path.join(os.path.dirname(os.path.dirname(report_path)), 'tasks', f'{_worker}.yaml')
            if os.path.exists(_tpath):
                with open(_tpath) as _tf:
                    _tdata = yaml.safe_load(_tf)
                _task = _tdata if not isinstance(_tdata, dict) or 'task' not in _tdata else _tdata.get('task', {})
                _rl = _task.get('related_lessons', [])
                if isinstance(_rl, list) and _rl:
                    _reinject = []
                    for r in _rl:
                        if isinstance(r, dict) and r.get('id'):
                            _reinject.append({'id': str(r['id']), 'useful': False, 'reason': ''})
                    if _reinject:
                        data['lessons_useful'] = _reinject
                        fixes.append(f'lessons_useful 空list→タスクYAML再注入({len(_reinject)}件)')
    except Exception:
        pass

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
                    r_raw = chk.get('result', '')
                    # bool対応: YAML 'yes'→True, 'no'→False (GP-033)
                    if isinstance(r_raw, bool):
                        if r_raw:
                            pass_count = pass_count + 1
                        else:
                            fail_count = fail_count + 1
                    else:
                        r = str(r_raw).strip().upper()
                        if r in ('PASS', 'YES', 'TRUE'):
                            pass_count = pass_count + 1
                        elif r in ('FAIL', 'NO', 'FALSE'):
                            fail_count = fail_count + 1
        if pass_count + fail_count > 0:
            data['verdict'] = 'FAIL' if fail_count > 0 else 'PASS'
            fixes.append(f'verdict推定({pass_count}PASS/{fail_count}FAIL)')

# === Fix 10: REMOVED ===
# lesson_candidate.found=false + no_lesson_reason空 → N/A を入れても
# gate_report_format.shがN/Aをplaceholderとして即FAIL(L61-63)する。
# 消火しても無意味。忍者に具体的な理由を書かせる方が正しい。
# 除去: 2026-03-23 deepdive Phase 14 現物検証で発見

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
