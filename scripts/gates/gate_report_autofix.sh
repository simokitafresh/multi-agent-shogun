#!/bin/bash
# gate_report_autofix.sh — 報告YAMLの機械的フォーマット自動修正
# 原則: 品質に影響しない純粋な構造変換のみ。内容欠落はBLOCKして家老/軍師に回す。
# 局所免疫: 忍者のペインで走る。家老のCTXを消費しない。
# Usage: bash scripts/gates/gate_report_autofix.sh <report_yaml_path>
# Exit: 0=修正完了(or修正不要), 1=auto-fix不可(要エージェント判断)
# Stdout: AUTO-FIXED: ... / NO-FIX-NEEDED / UNFIXABLE: ...
#
# === GP-107: 消火検出4問ゲート ===
# 新Fixを追加する前に4問で判定。1つでもNOなら消火構造 → BLOCKに切替えよ。
#   Q1: 内容不変か？ (構造変換: YES / 値の推定・補完: NO)
#   Q2: 忍者の判断を代行していないか？ (機械的変換: YES / 思考の代替: NO)
#   Q3: BLOCKで代替可能か？ (可能ならBLOCKを選べ)
#   Q4: 撤去しても忍者の学習ループは回るか？ (YES: 合法 / NO: 消火)
# 撤去実績: GP-091,093,094,103,104,106 (全て上記Q1-Q4でNO判定→BLOCK化)

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
    # === GP-091: 撤去(2026-03-25 消火→品質向上改修) ===
    # 旧: YAML parse errorを自動修復しダミーコンテンツを捏造(消火構造)
    # 新: YAML parse errorはそのままFAIL → 忍者がYAMLを正しく書き直す
    print(f'UNFIXABLE: YAML parse error: {e}')
    sys.exit(1)

if not data or not isinstance(data, dict):
    print('UNFIXABLE: report is empty or not a dict')
    sys.exit(1)

fixes = []

# === Fix 22-28: 撤去(2026-03-25 消火→品質向上改修) ===
# 旧: MISSINGフィールドにデフォルト値を挿入 → gateがPASS → 家老workaround発生(消火構造)
# 新: MISSINGはautofixしない → gate_report_format.shがBLOCK → 忍者が修正 → 学習ループ回転
# deepdive Phase 5: 消火=免疫応答を妨げる=抗体が生まれない
# 下流Fix(5,8,9等)は.get()で安全にスキップされる

# === Fix 1: report: wrapper → flatten ===
# パターン: 忍者が report: の下に全フィールドをネストする旧形式
if 'report' in data and isinstance(data['report'], dict):
    inner = data.pop('report')
    # 既存のトップレベルキー(cmd_id等)は保持し、inner側で上書き
    data.update(inner)
    fixes.append('report:ラップ→フラット化')

# === Fix 20: worker_id/parent_cmd欠落 → ファイル名から推定 ===
# パターン: 忍者がworker_id/parent_cmdを記入忘れ。ファイル名パターンから推定。
# Fix 14等のworker_id依存Fixより前に配置し、worker_idを先に確定させる。
import re as _re20
if not data.get('worker_id'):
    _basename = os.path.basename(report_path)
    _m20 = _re20.match(r'^([a-z_]+?)_report(?:_cmd_.+)?\.yaml$', _basename)
    if _m20:
        data['worker_id'] = _m20.group(1)
        fixes.append(f'worker_id ファイル名から推定({_m20.group(1)})')

if not data.get('parent_cmd'):
    _basename = os.path.basename(report_path)
    _m20p = _re20.match(r'^[a-z_]+?_report_(cmd_.+)\.yaml$', _basename)
    if _m20p:
        data['parent_cmd'] = _m20p.group(1)
        fixes.append(f'parent_cmd ファイル名から推定({_m20p.group(1)})')
    else:
        # ファイル名から推定不可 → タスクYAMLから取得
        _worker20 = data.get('worker_id', '')
        if _worker20:
            try:
                _tpath20 = os.path.join(os.path.dirname(os.path.dirname(report_path)), 'tasks', f'{_worker20}.yaml')
                if os.path.exists(_tpath20):
                    with open(_tpath20) as _tf20:
                        _tdata20 = yaml.safe_load(_tf20)
                    _task20 = _tdata20 if not isinstance(_tdata20, dict) or 'task' not in _tdata20 else _tdata20.get('task', {})
                    _pcmd20 = _task20.get('parent_cmd', '')
                    if _pcmd20:
                        data['parent_cmd'] = str(_pcmd20)
                        fixes.append(f'parent_cmd タスクYAMLから補完({_pcmd20})')
            except Exception:
                pass

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

# === Fix 3: files_modified string/list → dict list ===
# パターンA: 忍者が 'path/to/file' の単一stringで記入 (GP-065検出)
# パターンB: 忍者が ['path/to/file'] のstring listで記入
fm = data.get('files_modified')
if isinstance(fm, str) and fm.strip():
    data['files_modified'] = [{'path': fm.strip(), 'change': 'modified'}]
    fixes.append('files_modified string→dict変換(単一ファイル)')
elif isinstance(fm, list):
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

# === Fix 21: 撤去(2026-03-25 消火→品質向上改修) ===
# 旧: lessons_useful reason空を自動補完 → 忍者の評価放棄を隠す(消火構造)
# 新: reason空のままgate_report_format.shがBLOCK → 忍者が自分で評価理由を書く

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
            # === Fix 5 Step 3: 撤去(2026-03-25 消火→品質向上改修) ===
            # 旧: 散文テキストからYES/NO/PASS/FAILキーワードを推定して構造化
            # 問題: 忍者のフォーマット不備を自動変換で隠す(消火構造)
            #   - 散文→YES/NO推定は情報を捏造する可能性がある
            #   - 忍者は正しいフォーマットを学ばない（BLOCKされないため）
            # 新: 散文のままgate_report_format.shがBLOCK → 忍者がcheck/result形式で書き直す
            # deepdive Phase 5: 消火=免疫応答を妨げる。BLOCKこそが学習の起点。
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

# === Fix 15: 撤去(2026-03-25 消火→品質向上改修) ===
# 旧: lessons_useful空list→task YAMLから再注入(useful:False,reason:''のデフォルト値)
# 問題: 忍者のlesson評価放棄を体裁だけ復元(消火構造)。reason空で品質ゼロ
# 新: 空listのままgate_report_format.shがBLOCK → 忍者がlesson評価を自分で記入
# 軍師gate hint: テンプレートに注入済みの教訓にuseful/reasonを記入せよ。空リストで上書きするな

# === Fix 7: acceptance_criteria wrapper → flatten ===
# パターン: 忍者がacceptance_criteriaの下に結果を入れる独自形式
if 'acceptance_criteria' in data and 'binary_checks' not in data:
    ac = data.get('acceptance_criteria')
    if isinstance(ac, dict):
        # acceptance_criteria形式からbinary_checks形式への変換は
        # 構造が不明確なためauto-fixしない（品質に関わる）
        pass

# === Fix 9: verdict非標準値 → binary_checksから推定 (GP-092拡張) ===
# パターン: 忍者がverdictを空/None/None文字列/CONDITIONAL_PASS等の非標準値で提出
# PASS/FAIL以外の全値でbinary_checksから機械的に導出を試みる
# NOTE: verdict MISSING(キー不在)の場合は推定しない(消火防止 2026-03-25)
#   → gate_report_format.shがBLOCK → 忍者が自分でverdictを記入
verdict_val = data.get('verdict')
_is_valid_verdict = isinstance(verdict_val, str) and verdict_val in ('PASS', 'FAIL')
if not _is_valid_verdict and 'verdict' in data:
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

# === Fix 10: 撤去(2026-03-25 消火→品質向上改修) ===
# 旧: no_lesson_reasonをタスク種別から自動補完 → 忍者の思考放棄を隠す(消火構造)
# 新: 空理由のままgate_report_format.shがBLOCK → 忍者が自分で理由を考える

# === Fix 16: self_gate_check value normalization (GP-068) ===
sgc = data.get('self_gate_check')
if isinstance(sgc, dict):
    _pass_map = {'ok', 'yes', 'true', 'pass', 'o', '○'}
    _fail_map = {'ng', 'no', 'false', 'fail', 'x', '×'}
    _changed = False
    for k, v in sgc.items():
        if isinstance(v, str):
            low = v.strip().lower()
            if low in _pass_map and v != 'PASS':
                sgc[k] = 'PASS'
                _changed = True
            elif low in _fail_map and v != 'FAIL':
                sgc[k] = 'FAIL'
                _changed = True
    if _changed:
        data['self_gate_check'] = sgc
        fixes.append('self_gate_check値正規化(ok/yes→PASS)')

# === Fix 17: 撤去(2026-03-25 消火→品質向上改修) ===
# 旧: ac_version_read欠落→タスクYAMLから自動補完 → gate PASS(消火構造)
# 問題: ac_version_readの目的は忍者がACを実際に読んだことの証明(attestation)
#   autofixが補完すると忍者はACを読まなくても通る → attestation機能が無意味化
# 新: ac_version_read欠落のままgate_report_format.shがBLOCK → 忍者がACを読んでハッシュをコピー
# deepdive Phase 5: 証明を代行する自動化=免疫応答の無力化

# === Fix 19: binary_checks [N] key pattern → proper check/result (GP-088) ===
# パターン: 忍者がbcを [{[0]: {result: PASS}, [1]: {result: PASS}}] の番号キーdict形式で記入。
# cmd_1387半蔵で検出。Fix 15(len==1)では捕まらない(複数キー)。
# タスクYAMLのbinary_checksから本来のcheck名を取得して再構築。
import re as _re19
bc = data.get('binary_checks')
if isinstance(bc, dict):
    bc19_fixed = False
    for ac_key, ac_val in bc.items():
        if isinstance(ac_val, list):
            _needs_convert = False
            for chk in ac_val:
                if isinstance(chk, dict) and len(chk) > 1:
                    # 全キーが[N]パターンかチェック
                    _numbered_keys = [k for k in chk.keys() if _re19.match(r'^\[?\d+\]?$', str(k))]
                    if len(_numbered_keys) == len(chk):
                        _needs_convert = True
                        break
            if _needs_convert:
                # タスクYAMLからcheck名取得
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
                # 番号キーから結果を抽出し、タスクYAMLのcheck名と結合
                new_list = []
                for chk in ac_val:
                    if isinstance(chk, dict):
                        for idx, (k, v) in enumerate(sorted(chk.items(), key=lambda x: str(x[0]))):
                            _result_val = v.get('result', 'yes') if isinstance(v, dict) else str(v)
                            _check_name = ''
                            if idx < len(_task_checks):
                                tc = _task_checks[idx]
                                _check_name = tc.get('check', tc) if isinstance(tc, dict) else str(tc)
                            if not _check_name:
                                _check_name = f'{ac_key}_check_{idx}'
                            new_list.append({'check': _check_name, 'result': str(_result_val)})
                if new_list:
                    bc[ac_key] = new_list
                    bc19_fixed = True
    if bc19_fixed:
        fixes.append('binary_checks [N]キー→check/result正規化')

# === Fix 18: binary_checks result PASS/FAIL → yes/no (GP-083) ===
# パターン: 忍者がresult: PASS/FAILで記入。gate_report_format.shはyes/noを期待。
# Fix 11(boolean→string)とは別パターン。cmd_1384でhayate/kagemaru両方で検出。
bc = data.get('binary_checks')
if isinstance(bc, dict):
    _str_fixed = False
    _pass_vals = {'pass', 'ok', 'true', 'yes', 'done', 'clear', 'n/a', 'na'}
    _fail_vals = {'fail', 'false', 'no', 'ng', 'block'}
    for ac_key, ac_val in bc.items():
        if isinstance(ac_val, list):
            for chk in ac_val:
                if isinstance(chk, dict) and isinstance(chk.get('result'), str):
                    r = chk['result'].strip().lower()
                    if r in _pass_vals and chk['result'] != 'yes':
                        chk['result'] = 'yes'
                        _str_fixed = True
                    elif r in _fail_vals and chk['result'] != 'no':
                        chk['result'] = 'no'
                        _str_fixed = True
    if _str_fixed:
        fixes.append('binary_checks result文字列正規化(PASS/ok→yes, FAIL/ng→no)')

# === Write back if changed ===
if fixes:
    data['autofix_applied'] = fixes
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
        printf -- '- ts: "%s", file: "%s", gate: "gate_report_autofix", result: AUTO-FIXED, fixes: "%s"\n' "$TS" "$REPORT_PATH" "$FIXED_ITEMS" >> "$LOG_FILE"
    ) 200>"$LOG_FILE.lock" 2>/dev/null || true
    exit 0
elif echo "$RESULT" | grep -q "^NO-FIX-NEEDED"; then
    exit 0
else
    # UNFIXABLE — needs agent intervention
    REASON=${RESULT//\"/\\\"}
    (
        flock -w 5 200 2>/dev/null
        printf -- '- ts: "%s", file: "%s", gate: "gate_report_autofix", result: UNFIXABLE, reason: "%s"\n' "$TS" "$REPORT_PATH" "$REASON" >> "$LOG_FILE"
    ) 200>"$LOG_FILE.lock" 2>/dev/null || true
    exit 1
fi
