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

# --- PASS cache: skip redundant re-checks on unmodified files (GP-073) ---
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS_CACHE="$REPO_ROOT/logs/.gate_pass_cache"
_CANON=$(realpath "$REPORT_PATH" 2>/dev/null || echo "$REPORT_PATH")
_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "")
if [ -n "$_MTIME" ] && [ -f "$PASS_CACHE" ] && grep -qF "${_CANON} ${_MTIME}" "$PASS_CACHE" 2>/dev/null; then
    echo "PASS"
    exit 0
fi

# Python validation — checks all known failure patterns from karo_workarounds
RESULT=$(REPORT_PATH="$REPORT_PATH" python3 -c "
import yaml, os, sys

report_path = os.environ['REPORT_PATH']
errors = []
hints = []

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
required = ['worker_id', 'parent_cmd', 'ac_version_read', 'binary_checks', 'files_modified', 'lesson_candidate', 'lessons_useful']
missing_hints = {
    'worker_id': 'FIX (worker_id): テンプレートに生成済み。上書きで消すな。report_field_set.sh経由で記入:\\n  bash scripts/report_field_set.sh <report> worker_id <your_name>',
    'parent_cmd': 'FIX (parent_cmd): テンプレートに生成済み。上書きで消すな。report_field_set.sh経由で記入:\\n  bash scripts/report_field_set.sh <report> parent_cmd cmd_XXXX',
    'binary_checks': 'FIX (binary_checks): report_field_set.shで記入せよ:\\n  binary_checks:\\n    AC1:\\n      - check: \"確認内容\"\\n        result: \"yes\"',
    'files_modified': 'FIX (files_modified): 変更したファイルパスを記入せよ:\\n  files_modified:\\n    - path/to/file.py',
    'lesson_candidate': 'FIX (lesson_candidate): report_field_set.shで記入せよ:\\n  lesson_candidate:\\n    found: false\\n    no_lesson_reason: \"理由を具体的に書け\"',
    'lessons_useful': 'FIX (lessons_useful): テンプレートに注入済みの教訓にuseful/reasonを記入せよ。空リストで上書きするな',
    'ac_version_read': 'FIX (ac_version_read): task YAMLのac_versionハッシュ値をコピーせよ',
}
for field in required:
    if field not in data:
        errors.append(f'{field}: MISSING')
        if field in missing_hints:
            hints.append(missing_hints[field])

# --- files_modified must be string or list, not null/dict (GP-065) ---
fm = data.get('files_modified')
if fm is None and 'files_modified' in data:
    errors.append('files_modified: null (must be string or list of file paths)')
    hints.append('FIX (files_modified): nullではなく変更ファイルパスを記入せよ:\\n  files_modified:\\n    - path/to/file.py')
elif isinstance(fm, dict):
    errors.append('files_modified: is dict (must be string or list of file paths)')
    hints.append('FIX (files_modified): 文字列またはリスト形式で記入せよ:\\n  files_modified: path/to/file.py\\n  または\\n  files_modified:\\n    - path/to/file1.py\\n    - path/to/file2.py')
elif isinstance(fm, bool):
    errors.append(f'files_modified: is bool ({fm}), must be string or list of file paths')

# --- lesson_candidate must be dict with 'found' (null = FAIL) ---
lc = data.get('lesson_candidate')
if lc is None and 'lesson_candidate' in data:
    errors.append('lesson_candidate: null (must be dict with found/title/detail)')
elif lc is not None:
    if isinstance(lc, str):
        errors.append('lesson_candidate: is string (must be dict with found/title/detail)')
        hints.append('FIX (lesson_candidate): dict形式で再記入せよ:\\n  lesson_candidate:\\n    found: true  # or false\\n    title: \"教訓タイトル\"\\n    detail: \"詳細\"')
    elif isinstance(lc, dict):
        if 'found' not in lc:
            errors.append('lesson_candidate: missing \"found\" field')
        if not lc.get('found') and not lc.get('no_lesson_reason'):
            errors.append('lesson_candidate: found=false but no no_lesson_reason')
            hints.append('FIX (lesson_candidate): found: falseの場合はno_lesson_reasonが必須:\\n  lesson_candidate:\\n    found: false\\n    no_lesson_reason: \"既知のL084と同じパターンで新規教訓なし\"')
        # --- no_lesson_reason quality check (cmd_1299) ---
        if not lc.get('found') and lc.get('no_lesson_reason'):
            reason = str(lc.get('no_lesson_reason', '')).strip()
            if len(reason) <= 3:
                errors.append(f'lesson_candidate: no_lesson_reason too short ({len(reason)} chars, need >3)')
                hints.append('FIX (lesson_candidate): no_lesson_reasonに具体的な理由を記入せよ。例: \"既知のL084と同じパターン\"')
            placeholder_values = ['なし', '特になし', 'N/A', 'n/a', 'none', 'None', 'no', 'No']
            if reason in placeholder_values:
                errors.append(f'lesson_candidate: no_lesson_reason=\"{reason}\" is placeholder (write a real reason)')
                hints.append('FIX (lesson_candidate): プレースホルダ禁止。なぜ教訓がないのか具体的に書け')
        if lc.get('found') and not lc.get('title'):
            errors.append('lesson_candidate: found=true but no title')
        if lc.get('found') and not lc.get('detail') and not lc.get('summary'):
            errors.append('lesson_candidate: found=true but no detail or summary')
    else:
        errors.append(f'lesson_candidate: unexpected type {type(lc).__name__}')

# --- lessons_useful must be list of dicts (null = FAIL) ---
lu = data.get('lessons_useful')
if lu is None and 'lessons_useful' in data:
    errors.append('lessons_useful: null (must be list of dicts, not null)')
    hints.append('FIX (lessons_useful): nullではなくリスト形式で記入せよ。テンプレート注入済み教訓を上書きするな:\\n  lessons_useful:\\n    - id: L074\\n      useful: true\\n      reason: \"具体的な理由\"')
elif lu is not None:
    if isinstance(lu, str):
        errors.append('lessons_useful: is string (must be list of dicts)')
    elif isinstance(lu, list):
        # --- GP-064+GP-088: empty list detection (related_lessons考慮) ---
        if len(lu) == 0:
            # GP-088: related_lessonsがないcmdでは[]が正当。task YAMLを確認。
            _worker = data.get('worker_id', '')
            _task_path = os.path.join(os.path.dirname(os.path.dirname(report_path)), 'tasks', f'{_worker}.yaml')
            _has_related = False
            try:
                if os.path.exists(_task_path):
                    with open(_task_path) as _tf:
                        _tdata = yaml.safe_load(_tf)
                    _task = (_tdata or {}).get('task', _tdata or {})
                    _rel = _task.get('related_lessons', [])
                    _has_related = bool(_rel and isinstance(_rel, list) and len(_rel) > 0)
            except Exception:
                pass
            if _has_related:
                errors.append('lessons_useful: empty list (テンプレートには教訓が注入済み。空リストで上書きするな)')
                hints.append('FIX (lessons_useful): report_field_set.sh経由でuseful/reasonを各教訓に記入せよ')
        for i, item in enumerate(lu):
            if isinstance(item, dict):
                if 'FILL_THIS' in str(item.get('useful', '')) or 'FILL_THIS' in str(item.get('reason', '')):
                    errors.append(f'lessons_useful[{i}]: contains FILL_THIS (must fill actual values)')
                if 'id' not in item:
                    errors.append(f'lessons_useful[{i}]: missing \"id\" field (must have lesson ID like L074)')
                    hints.append(f'FIX (lessons_useful[{i}]): id フィールド必須。テンプレート注入済みの教訓IDを確認せよ:\\n  - id: L074\\n    useful: true\\n    reason: \"理由\"')
                if 'useful' not in item:
                    errors.append(f'lessons_useful[{i}]: missing \"useful\" field')
                    hints.append(f'FIX (lessons_useful[{i}]): useful: true or false を記入せよ')
                elif not isinstance(item['useful'], bool):
                    errors.append(f'lessons_useful[{i}]: useful={item[\"useful\"]} is {type(item[\"useful\"]).__name__} (must be true or false)')
                    hints.append(f'FIX (lessons_useful[{i}]): useful: true または useful: false を指定せよ（文字列やnullは不可）')
                if 'reason' not in item:
                    errors.append(f'lessons_useful[{i}]: missing \"reason\" field')
                    hints.append(f'FIX (lessons_useful[{i}]): reason フィールド必須。教訓が有用/無用な理由を具体的に記入せよ')
                elif isinstance(item.get('reason'), str) and not item['reason'].strip():
                    errors.append(f'lessons_useful[{i}]: reason is empty (教訓が有用/無用な理由を具体的に書け)')
                    hints.append(f'FIX (lessons_useful[{i}]): reason: \"L070のパターンと同一で参考にならなかった\" など具体的に記述')
            else:
                errors.append(f'lessons_useful[{i}]: is {type(item).__name__} (must be dict)')
    elif isinstance(lu, dict):
        errors.append('lessons_useful: is dict (must be list). Use \"- id: L001\" not \"0: {id: L001}\". Numbered keys are not YAML lists')
        hints.append(f'FIX (lessons_useful): Pythonで変換せよ:\\n  python3 -c \"import yaml; d=yaml.safe_load(open(\\'{report_path}\\')); d[\\'lessons_useful\\']=[v for v in d[\\'lessons_useful\\'].values()]; yaml.dump(d,open(\\'{report_path}\\',\\'w\\'),allow_unicode=True)\"')
    else:
        errors.append(f'lessons_useful: unexpected type {type(lu).__name__} (must be list of dicts)')

# --- binary_checks must not be null, empty, or string ---
bc = data.get('binary_checks')
if bc is None and 'binary_checks' in data:
    errors.append('binary_checks: null (must be dict with AC entries)')
    hints.append('FIX (binary_checks): nullではなくdict形式で記入せよ:\\n  binary_checks:\\n    AC1:\\n      - check: \"確認内容\"\\n        result: \"yes\"')
elif isinstance(bc, str):
    errors.append('binary_checks: is string (must be dict with AC entries)')
    hints.append('FIX (binary_checks): dict形式で再記入せよ:\\n  binary_checks:\\n    AC1:\\n      - check: \"確認内容\"\\n        result: \"yes\"')
elif isinstance(bc, dict) and not bc:
    errors.append('binary_checks: empty dict (must have at least one AC entry)')
    hints.append('FIX (binary_checks): AC完了ごとに二値チェックを記入せよ:\\n  binary_checks:\\n    AC1:\\n      - check: \"確認内容を具体的に\"\\n        result: \"yes\"')
elif isinstance(bc, dict):
    for ac_key, ac_val in bc.items():
        if not isinstance(ac_val, list):
            errors.append(f'binary_checks.{ac_key}: is {type(ac_val).__name__} (must be list of check items)')
            hints.append(f'FIX (binary_checks.{ac_key}): list形式で記入せよ:\\n  binary_checks:\\n    {ac_key}:\\n      - check: \"確認内容\"\\n        result: \"yes\"')
        else:
            # --- GP-053: binary_checks semantic quality check ---
            # 形式だけでなく中身の品質を検証。check=verdict値やresult=自由記述を検出。
            # 品質の起点: binary_checksが機能しなければ第一層学習ループが空回りする。
            verdict_words = {'PASS', 'FAIL', 'OK', 'NG', 'yes', 'no', 'YES', 'NO', 'true', 'false', 'True', 'False', 'pass', 'fail', 'ok', 'ng'}
            for j, check_item in enumerate(ac_val):
                if not isinstance(check_item, dict):
                    continue
                # GP-088: check/resultフィールド欠落検出（[N]キー形式等の残骸）
                if 'check' not in check_item:
                    errors.append(f'binary_checks.{ac_key}[{j}]: missing \"check\" field')
                if 'result' not in check_item:
                    errors.append(f'binary_checks.{ac_key}[{j}]: missing \"result\" field')
                ck = check_item.get('check', '')
                rs = check_item.get('result', '')
                # check field: must describe WHAT was verified, not a verdict
                if isinstance(ck, str) and ck.strip() in verdict_words:
                    errors.append(f'binary_checks.{ac_key}[{j}].check: \"{ck}\" は確認項目ではない。PASS/FAILではなく「何を確認したか」を書け')
                    hints.append(f'FIX (binary_checks.{ac_key}[{j}]): check に確認内容を書け。result に yes/no を書け。\\n  例: {{check: \"_pane_offset変数が除去されたか\", result: \"yes\"}}')
                elif isinstance(ck, str) and 0 < len(ck.strip()) < 5:
                    errors.append(f'binary_checks.{ac_key}[{j}].check: \"{ck}\" が短すぎる(確認内容を具体的に書け)')
                # result field: must be yes/no, not free-form text or empty
                if isinstance(rs, str) and not rs.strip():
                    errors.append(f'binary_checks.{ac_key}[{j}].result: 空文字。\"yes\" または \"no\" を記入せよ')
                    hints.append(f'FIX (binary_checks.{ac_key}[{j}].result): 確認結果を \"yes\" or \"no\" で記入せよ')
                elif isinstance(rs, str) and rs.strip().lower() not in ('yes', 'no'):
                    errors.append(f'binary_checks.{ac_key}[{j}].result: \"{rs[:40]}\" は不正。\"yes\" または \"no\" のみ')
                    hints.append(f'FIX (binary_checks.{ac_key}[{j}].result): \"yes\" or \"no\" のみ。自由記述は acceptance_criteria.detail に書け')
elif isinstance(bc, list) and not bc:
    errors.append('binary_checks: empty list (must have at least one entry)')

# --- purpose_validation should exist and not be null ---
if 'purpose_validation' not in data:
    errors.append('purpose_validation: MISSING')
    hints.append('FIX (purpose_validation): cmdの目的との適合を記入せよ:\\n  purpose_validation:\\n    cmd_purpose: \"cmdの目的\"\\n    fit: true\\n    purpose_gap: \"\"')
elif data.get('purpose_validation') is None:
    errors.append('purpose_validation: null (must be dict with fit/reason)')

# --- status must not be pending (template default = unfinished) ---
status_val = data.get('status', '')
if isinstance(status_val, str) and status_val.strip().lower() == 'pending':
    errors.append('status: \"pending\" はテンプレート初期値。完了後に \"completed\" に更新せよ')
    hints.append('FIX (status): bash scripts/report_field_set.sh <report> status completed')

# --- result.summary should exist ---
result = data.get('result', {})
if isinstance(result, dict):
    if not result.get('summary'):
        errors.append('result.summary: MISSING or empty')
else:
    errors.append('result: not a dict')

# --- verdict must be PASS or FAIL (strict binary) ---
verdict = data.get('verdict')
if not isinstance(verdict, str) or verdict not in ('PASS', 'FAIL'):
    errors.append(f'verdict: \"{verdict}\" is not valid (must be \"PASS\" or \"FAIL\")')
    hints.append('verdictはPASS/FAILの二値のみ。binary_checks全yes→PASS、1つでもno→FAIL')

# --- GP-128: verdict ↔ binary_checks consistency (SG7自動化) ---
if isinstance(verdict, str) and verdict in ('PASS', 'FAIL') and isinstance(bc, dict) and bc:
    bc_has_no = False
    bc_results_found = False
    for _ac_key, _ac_val in bc.items():
        if isinstance(_ac_val, list):
            for _item in _ac_val:
                if isinstance(_item, dict) and 'result' in _item:
                    bc_results_found = True
                    r = str(_item['result']).strip().lower()
                    if r in ('no', 'false', 'fail', 'ng'):
                        bc_has_no = True
    if bc_results_found:
        if verdict == 'PASS' and bc_has_no:
            errors.append('verdict: PASS but binary_checks contain \"no\" results (verdict must be FAIL when any check fails)')
            hints.append('FIX (verdict): binary_checksにno/fail/ngがある場合はverdict: FAILにせよ')
        elif verdict == 'FAIL' and not bc_has_no:
            # WARN only — FAIL with all-yes may have valid external reasons
            hints.append('GP-128 WARN: verdict=FAIL but all binary_checks are \"yes\" — 外部制約によるFAILか確認せよ')

# --- assumption_invalidation structure check (cmd_1433) ---
ai = data.get('assumption_invalidation')
if ai is None and 'assumption_invalidation' in data:
    errors.append('assumption_invalidation: null (must be dict with found/affected_cmds/detail)')
elif ai is not None:
    if not isinstance(ai, dict):
        errors.append(f'assumption_invalidation: is {type(ai).__name__} (must be dict)')
    else:
        for ai_field in ['found', 'affected_cmds', 'detail']:
            if ai_field not in ai:
                errors.append(f'assumption_invalidation: missing \"{ai_field}\" field')
        ai_found = ai.get('found')
        ai_cmds = ai.get('affected_cmds')
        if ai_found is True and isinstance(ai_cmds, list) and len(ai_cmds) == 0:
            errors.append('assumption_invalidation: found=true but affected_cmds is empty (影響cmdを列挙せよ)')
            hints.append('FIX (assumption_invalidation): found:trueの場合、affected_cmdsに影響を受けるcmd_IDを列挙せよ')
elif 'assumption_invalidation' not in data:
    errors.append('assumption_invalidation: MISSING')
    hints.append('FIX (assumption_invalidation): テンプレートに生成済み。上書きで消すな:\\n  assumption_invalidation:\\n    found: false\\n    affected_cmds: []\\n    detail: \"\"')

# --- GP-126: knowledge_candidate structure check ---
kc = data.get('knowledge_candidate')
if kc is not None:
    if not isinstance(kc, dict):
        errors.append(f'knowledge_candidate: is {type(kc).__name__} (must be dict)')
    else:
        kc_found = kc.get('found')
        if kc_found is True:
            kc_items = kc.get('items', [])
            if not isinstance(kc_items, list) or len(kc_items) == 0:
                errors.append('knowledge_candidate: found=true but items is empty')
                hints.append('FIX (knowledge_candidate): found:true時はitemsに事実データを列挙せよ:\\n  knowledge_candidate:\\n    found: true\\n    items:\\n      - fact: \"発見した事実\"\\n        source: \"確認元\"')
            elif isinstance(kc_items, list):
                for ki, kitem in enumerate(kc_items):
                    if isinstance(kitem, dict):
                        if not str(kitem.get('fact', '')).strip():
                            errors.append(f'knowledge_candidate.items[{ki}].fact: empty')

# --- self_gate_check value validation (cmd_cycle_001) ---
# reviewタスクのself_gate_check: 各項目のresultはPASS/FAILのみ許容
sgc = data.get('self_gate_check')
if sgc is not None:
    if not isinstance(sgc, dict):
        errors.append(f'self_gate_check: is {type(sgc).__name__} (must be dict)')
        hints.append('FIX (self_gate_check): dict形式で記入せよ:\\n  self_gate_check:\\n    lesson_ref: PASS\\n    format_compliance: PASS\\n  各項目はPASS/FAILの二値')
    else:
        valid_sgc_values = {'PASS', 'FAIL'}
        for sgc_key, sgc_val in sgc.items():
            sgc_str = str(sgc_val).strip() if sgc_val is not None else ''
            if sgc_str == '':
                # 空文字はテンプレート初期値 — 未記入
                errors.append(f'self_gate_check.{sgc_key}: empty (must be PASS or FAIL)')
                hints.append(f'FIX: self_gate_check.{sgc_key} に PASS or FAIL を記入せよ')
            elif sgc_str not in valid_sgc_values:
                errors.append(f'self_gate_check.{sgc_key}: \"{sgc_str}\" is not valid (must be \"PASS\" or \"FAIL\")')
                hints.append(f'FIX: Change self_gate_check.{sgc_key} from \"{sgc_str}\" to \"PASS\" or \"FAIL\"')

# --- stale_report check (GP-036): filename cmd vs parent_cmd field ---
import re
filename = os.path.basename(report_path)
fname_match = re.search(r'cmd_(\d+)', filename)
parent_cmd = data.get('parent_cmd', '')
if fname_match and parent_cmd:
    fname_cmd = f'cmd_{fname_match.group(1)}'
    if fname_cmd != str(parent_cmd):
        errors.append(f'stale_report: filename has {fname_cmd} but parent_cmd={parent_cmd} (cmd_id mismatch)')

# --- GP-062: stale content detection ---
# 報告YAML内にparent_cmd以外のcmd_XXXXが存在→前cmdテンプレート残骸の可能性
import json
report_text = json.dumps(data, ensure_ascii=False, default=str)
other_cmds = set(re.findall(r'cmd_\d+', report_text)) - {str(parent_cmd)}
if other_cmds and parent_cmd:
    # parent_cmdのサブcmd(例: cmd_1311内でcmd_1311_sub)は除外
    stale_cmds = [c for c in other_cmds if not c.startswith(str(parent_cmd))]
    if stale_cmds:
        hints.append(f'GP-062 WARN: 報告内に別cmdの参照あり: {sorted(stale_cmds)} — staleコンテンツの可能性を確認せよ')

# --- PI-012: GS探索でのPE使用検出 ---
# 忍法スクリプト(run_077_*)のGS結果にPEフォールバックが使われた場合をWARN
# 自動消火装置の検出: PEフォールバックは問題を隠す
if result and isinstance(result, dict):
    details_text = str(result.get('details', '')) + ' ' + str(result.get('summary', ''))
    pe_indicators = ['PE経由', 'PE fallback', 'PEフォールバック', 'PE経由でフル実行', 'use_pe_mode']
    for indicator in pe_indicators:
        if indicator in details_text:
            hints.append(f'PI-012 WARN: 報告にPE使用の痕跡あり(\"{indicator}\")。GS探索でPE使用は禁止(cmd_1349)。batch pathの修正が必要')
            break

# --- Output (GP-108: hint dedup) ---
# 同一パターンのヒントが複数回出力されると忍者にとってノイズ。
# インデックス[N]を正規化して重複排除し、1パターンにつき1回だけ表示
seen_bases = set()
deduped = []
for h in hints:
    base = re.sub(r'\[\d+\]', '[*]', h)
    if base not in seen_bases:
        seen_bases.add(base)
        deduped.append(re.sub(r'\[\d+\]', '[N]', h))
hints = deduped

if errors:
    print('FAIL: ' + '; '.join(errors))
    if hints:
        for h in hints:
            print(h)
    sys.exit(1)
else:
    print('PASS')
    if hints:
        for h in hints:
            print(h)
    sys.exit(0)
" 2>&1) || true

echo "$RESULT"

# --- Gate fire logging (cmd_1279) ---
LOG_FILE="$REPO_ROOT/logs/gate_fire_log.yaml"
TS=$(date -Is)

if echo "$RESULT" | grep -q "^PASS"; then
    (
        flock -w 5 200 2>/dev/null
        printf -- '- ts: "%s", file: "%s", result: PASS\n' "$TS" "$REPORT_PATH" >> "$LOG_FILE"
    ) 200>"$LOG_FILE.lock" 2>/dev/null || true
    # Update PASS cache (GP-073)
    if [ -n "$_MTIME" ]; then
        sed -i "\|^${_CANON} |d" "$PASS_CACHE" 2>/dev/null || true
        echo "${_CANON} ${_MTIME}" >> "$PASS_CACHE"
    fi
    exit 0
else
    REASONS=$(echo "$RESULT" | head -1 | sed 's/^FAIL: //' | sed 's/"/\\"/g')
    (
        flock -w 5 200 2>/dev/null
        printf -- '- ts: "%s", file: "%s", result: FAIL, reasons: "%s"\n' "$TS" "$REPORT_PATH" "$REASONS" >> "$LOG_FILE"
    ) 200>"$LOG_FILE.lock" 2>/dev/null || true
    exit 1
fi
