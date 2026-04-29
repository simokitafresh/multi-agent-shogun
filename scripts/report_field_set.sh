#!/usr/bin/env bash
# report_field_set.sh — 報告YAMLのフィールドをflock排他制御で安全に更新
# 共通ライブラリ(lib/yaml_field_set.sh)の関数を使用
#
# Usage: bash scripts/report_field_set.sh <report_path> <dot.notation.key> <value>
#        echo "multi-line value" | bash scripts/report_field_set.sh <report_path> <dot.notation.key> -
#
# - flock付き排他制御（inbox_write.sh同等パターン）
# - ドット記法でネストフィールドに対応（例: results.AC1.status）
# - 値が "-" ならstdinから読む
# - 存在しないキーは自動作成（中間dictも — Pythonフォールバック経由）
# - 平文フィールド: yaml_field_set.sh (awk) で高速処理
# - 構造体/複数行/新規ブロック: Pythonフォールバック

set -e

# SCRIPT_DIR: string ops instead of $(cd) subshells (~1.2ms savings on WSL2)
_rfs_self="${BASH_SOURCE[0]:-$0}"
[[ "$_rfs_self" != /* ]] && _rfs_self="$PWD/$_rfs_self"
SCRIPT_DIR="${_rfs_self%/scripts/report_field_set.sh}"
YAML_FIELD_SET_LOADED=0

ensure_yaml_field_set_loaded() {
    if [ "$YAML_FIELD_SET_LOADED" -eq 1 ]; then
        return 0
    fi
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
    YAML_FIELD_SET_LOADED=1
}

REPORT_PATH="$1"
DOT_KEY="$2"
VALUE="$3"

if [ -z "$REPORT_PATH" ] || [ -z "$DOT_KEY" ]; then
    echo "Usage: bash scripts/report_field_set.sh <report_path> <dot.notation.key> <value>" >&2
    echo "  value が '-' ならstdinから読む。空文字列は ''(YAML空文字)として書込み。" >&2
    echo "Examples:" >&2
    echo "  bash scripts/report_field_set.sh queue/reports/hanzo_report_cmd_100.yaml results.AC1.status PASS" >&2
    echo "  echo 'long text' | bash scripts/report_field_set.sh queue/reports/hanzo_report_cmd_100.yaml results.AC1.notes -" >&2
    exit 1
fi
# Pattern1 fix: 空文字値を許可。$3未指定/空→YAML空文字列('')として書込み
if [ -z "$VALUE" ]; then
    VALUE="''"
fi

# Resolve to absolute path if relative
if [[ "$REPORT_PATH" != /* ]]; then
    REPORT_PATH="$SCRIPT_DIR/$REPORT_PATH"
fi

LOCKFILE="${REPORT_PATH}.lock"

# Read stdin if value is "-"
STDIN_VALUE=""
USE_PYTHON=0
if [ "$VALUE" = "-" ]; then
    STDIN_VALUE="$(cat)"
    # Detect YAML structure (list/dict) → Python fallback for faithful preservation
    # bash fast-path: first non-whitespace char is [ { or - → list/dict
    _sv_fc=$(printf '%s' "$STDIN_VALUE" | tr -d ' \t\n' | cut -c1)
    if [[ "$_sv_fc" == "[" || "$_sv_fc" == "{" || "$_sv_fc" == "-" ]]; then
        VALUE="$STDIN_VALUE"
        USE_PYTHON=1
    elif [[ "$STDIN_VALUE" == *$'\n'* ]]; then
        # Multi-line text: awk cannot handle, use Python
        VALUE="$STDIN_VALUE"
        USE_PYTHON=1
    else
        VALUE="$STDIN_VALUE"
    fi
fi

# Direct argument multiline detection (non-stdin path)
if [[ "$VALUE" == *$'\n'* ]] && [ "$USE_PYTHON" -eq 0 ]; then
    USE_PYTHON=1
    STDIN_VALUE="$VALUE"
fi

# --- binary_checks共通バリデーション (DRY: full/per-AC統合) ---
# mode="full": binary_checks全体(dict of lists) / mode="per_ac": 単一AC(list of dicts)
_validate_binary_checks() {
    local mode="$1"
    local val="$2"
    python3 -c "
import yaml, sys
err = '''ERROR: binary_checks must be YAML list of dicts with result: yes/no.
  Correct: - {check: 'テスト全PASS', result: yes}
  Wrong:   'AC1: YES, AC2: NO'
  Wrong:   result: true (use 'yes' not true)
  Wrong:   result: PASS (use 'yes' not 'PASS')'''
mode = sys.argv[1]
try:
    data = yaml.load(sys.stdin.read(), Loader=yaml.BaseLoader)
except yaml.YAMLError:
    print(err, file=sys.stderr)
    sys.exit(1)
if isinstance(data, str):
    print(err, file=sys.stderr)
    sys.exit(1)
def check_items(items):
    if not isinstance(items, list):
        print(err, file=sys.stderr)
        sys.exit(1)
    for j, item in enumerate(items):
        if not isinstance(item, dict):
            continue
        r = str(item.get('result', '')).strip()
        if r and r.lower() not in ('yes', 'no', ''):
            print(err, file=sys.stderr)
            sys.exit(1)
if mode == 'full':
    if not isinstance(data, dict):
        print(err, file=sys.stderr)
        sys.exit(1)
    for ac_key, ac_val in data.items():
        check_items(ac_val)
else:
    check_items(data)
" "$mode" <<< "$val" || return 1
}

# --- GP-072: Pre-write field value validation (Level 4 BLOCK) ---
# 書込み前にフィールド値の妥当性を検証。不正値はBLOCKして忍者に即フィードバック。
# GP-072c2: per-item writes, dict→list conversion, verdict pre-conditions
# GP-072c3: lessons_useful id UNKNOWN/null BLOCK, template mandatory fields
# GP-072c4: binary_checks all-result-empty verdict BLOCK
_validate_field_value() {
    local dot_key="$1"
    local val="$2"
    local field="${dot_key%%.*}"

    case "$field" in
        lessons_useful)
            # Full field write: must be YAML list, not dict/string/empty
            if [[ "$dot_key" == "lessons_useful" ]]; then
                python3 -c "
import yaml, sys
data = yaml.safe_load(sys.stdin.read())
if not isinstance(data, list):
    print('ERROR: lessons_useful must be YAML list format.', file=sys.stderr)
    print(\"  Correct: - {id: L001, useful: true, reason: '理由'}\", file=sys.stderr)
    print(\"  Wrong:   {0: {id: L001}, 1: {id: L002}}\", file=sys.stderr)
    print(\"  Wrong:   'L001をreviewで使用した'\", file=sys.stderr)
    sys.exit(1)
for i, item in enumerate(data):
    if not isinstance(item, dict):
        print(f'BLOCK: lessons_useful[{i}] はdict必須。受信: {type(item).__name__}', file=sys.stderr)
        sys.exit(1)
    if 'id' not in item or not str(item['id']).strip():
        print(f'BLOCK: lessons_useful[{i}].id が空。テンプレート注入済みIDを使え', file=sys.stderr)
        sys.exit(1)
    id_val = str(item['id']).strip()
    if id_val in ('UNKNOWN', 'unknown', 'null', 'FILL_THIS'):
        print(f'BLOCK: lessons_useful[{i}].id=\"{id_val}\" は不正。L074等の実IDを使え', file=sys.stderr)
        sys.exit(1)
    if 'useful' in item and not isinstance(item['useful'], bool):
        print(f'BLOCK: lessons_useful[{i}].useful はbool必須。受信: {item[\"useful\"]}', file=sys.stderr)
        sys.exit(1)
" <<< "$val" || return 1
            # GP-072c3: Per-item id write (e.g., lessons_useful.0.id)
            elif [[ "$dot_key" =~ ^lessons_useful\.[0-9]+\.id$ ]]; then
                local id_val
                id_val=$(echo "$val" | xargs)
                id_val="${id_val//\"/}"
                if [[ -z "$id_val" ]] || [[ "$id_val" == "UNKNOWN" ]] || [[ "$id_val" == "unknown" ]] || [[ "$id_val" == "null" ]]; then
                    echo "BLOCK: lessons_useful id=\"$val\" は不正。テンプレートに注入済みのID(L074等)を使え。UNKNOWNは禁止。" >&2
                    return 1
                fi
            # P5 fix: lessons_useful.{non-numeric}.field → IDベースアクセスをBLOCK+正しい方法を案内
            elif [[ "$dot_key" =~ ^lessons_useful\.[^0-9] ]]; then
                local bad_key="${dot_key#lessons_useful.}"
                echo "BLOCK: lessons_useful.${bad_key} は不正。lessons_usefulはYAML listのためindex指定が必要。" >&2
                echo "  正: lessons_useful.0.reason / lessons_useful.1.useful" >&2
                echo "  誤: lessons_useful.L636.reason (IDベースアクセスは不可)" >&2
                return 1
            fi
            ;;
        binary_checks)
            # Full-field write validation (GP-072 binary_checks型バリデーション)
            # BaseLoader使用: yes/noを文字列として保持し true/falseと区別する
            if [[ "$dot_key" == "binary_checks" ]]; then
                _validate_binary_checks "full" "$val" || return 1
            # GP-072c2: Per-AC write (e.g., binary_checks.AC1) — only 2-level depth
            elif [[ "$dot_key" == binary_checks.AC* ]] && [[ "$dot_key" != *.*.* ]]; then
                _validate_binary_checks "per_ac" "$val" || return 1
            fi
            ;;
        self_gate_check)
            if [[ "$val" != "PASS" ]] && [[ "$val" != "FAIL" ]]; then
                echo "BLOCK: self_gate_check は PASS/FAIL のみ。受信: $val" >&2
                return 1
            fi
            ;;
        lesson_candidate)
            if [[ "$dot_key" == "lesson_candidate" ]]; then
                python3 -c "
import yaml, sys
data = yaml.safe_load(sys.stdin.read())
if not isinstance(data, dict):
    print(f'BLOCK: lesson_candidate はdict形式必須。受信: {type(data).__name__}', file=sys.stderr)
    sys.exit(1)
" <<< "$val" || return 1
            fi
            ;;
        knowledge_candidate)
            # GP-126: knowledge_candidate validation (事実データ循環)
            if [[ "$dot_key" == "knowledge_candidate" ]]; then
                python3 -c "
import yaml, sys
data = yaml.safe_load(sys.stdin.read())
if not isinstance(data, dict):
    print(f'BLOCK: knowledge_candidate はdict形式必須。受信: {type(data).__name__}', file=sys.stderr)
    sys.exit(1)
found = data.get('found', False)
if found is True:
    items = data.get('items', [])
    if not isinstance(items, list) or len(items) == 0:
        print('BLOCK: knowledge_candidate.found=true だがitemsが空。発見した事実を記入せよ', file=sys.stderr)
        print('  items:', file=sys.stderr)
        print(\"    - fact: '発見した事実を1文で'\", file=sys.stderr)
        print(\"      source: '確認元ファイル/行'\", file=sys.stderr)
        sys.exit(1)
    for i, item in enumerate(items):
        if not isinstance(item, dict):
            print(f'BLOCK: knowledge_candidate.items[{i}] はdict必須', file=sys.stderr)
            sys.exit(1)
        if not str(item.get('fact', '')).strip():
            print(f'BLOCK: knowledge_candidate.items[{i}].fact が空', file=sys.stderr)
            sys.exit(1)
" <<< "$val" || return 1
            fi
            ;;
        verdict)
            # GP-072c2+c3+c4: verdict書込み時に前提条件チェック
            if [[ "$dot_key" == "verdict" ]] && [[ "$val" == "PASS" || "$val" == "FAIL" || "$val" == "PASS_NO_IMPROVEMENT" ]]; then
                REPORT_PATH="$REPORT_PATH" FIELD_VAL="$val" python3 -c "
import yaml, sys, os
rp = os.environ.get('REPORT_PATH', '')
if not rp or not os.path.exists(rp):
    sys.exit(0)
with open(rp) as f:
    data = yaml.safe_load(f) or {}
issues = []
# GP-072c3: Template mandatory fields
for mf in ('worker_id', 'parent_cmd', 'ac_version_read'):
    v = data.get(mf)
    if not v or str(v).strip() in ('', 'null', 'None'):
        issues.append(f'{mf} が空。テンプレートの値を保持せよ')
# P8 fix: report filename と parent_cmd の整合性チェック
_pcmd = str(data.get('parent_cmd', '')).strip()
if _pcmd and rp:
    import os as _os
    _basename = _os.path.basename(rp)  # e.g. hayate_report_cmd_2073.yaml
    if _pcmd and _pcmd not in _basename:
        issues.append(f'parent_cmd={_pcmd} がreportファイル名 {_basename} に含まれない。テンプレート再利用時のparent_cmd更新漏れの可能性')
# GP-072c2: result.summary not empty
result = data.get('result', {})
if isinstance(result, dict):
    s = str(result.get('summary', '')).strip()
    if not s:
        issues.append('result.summary が空。作業内容を記述せよ')
# GP-072c2: lesson_candidate.found=false requires no_lesson_reason
lc = data.get('lesson_candidate', {})
if isinstance(lc, dict) and str(lc.get('found', '')).lower() == 'false':
    nlr = str(lc.get('no_lesson_reason', '')).strip()
    if not nlr:
        issues.append('lesson_candidate.found=false だが no_lesson_reason が空')
# P7 fix: assumption_invalidation必須フィールドガード
ai = data.get('assumption_invalidation', {})
if isinstance(ai, dict):
    ai_found = str(ai.get('found', '')).lower()
    if ai_found == 'true':
        ai_detail = str(ai.get('detail', '')).strip()
        ai_cmds = ai.get('affected_cmds', [])
        if not ai_detail:
            issues.append('assumption_invalidation.found=true だが detail が空')
        if not ai_cmds or (isinstance(ai_cmds, list) and len(ai_cmds) == 0):
            issues.append('assumption_invalidation.found=true だが affected_cmds が空')
# GP-072c2: lessons_useful items must have non-empty reason
lu = data.get('lessons_useful', [])
if isinstance(lu, list):
    for i, item in enumerate(lu):
        if isinstance(item, dict):
            r = str(item.get('reason', '')).strip()
            if not r:
                issues.append(f'lessons_useful[{i}].reason が空')
# GP-072c5: binary_checks に 'no' があるのに verdict=PASS は矛盾 → 自動FAIL化
# 真因: フィールド間整合性制約がなく矛盾状態を作れた(なぜなぜ7回 2026-04-21)
# 原理: 間違える余地がない構造。gateで止めるのではなく書込み時に矛盾を不可能にする
bc = data.get('binary_checks', {})
verdict_val = os.environ.get('FIELD_VAL', '')
if isinstance(bc, dict) and bc and verdict_val == 'PASS':
    has_no = False
    for ac_key, ac_val in bc.items():
        if isinstance(ac_val, list):
            for item in ac_val:
                if isinstance(item, dict) and str(item.get('result', '')).strip().lower() == 'no':
                    has_no = True
                    break
        if has_no:
            break
    if has_no:
        issues.append('binary_checks に result:no があるのに verdict=PASS は矛盾。verdict=FAIL に変更せよ')
# GP-072c4: binary_checks results must not be all empty
# P4 fix: assigned_acs がある場合、担当外ACの空resultは除外
import glob
_assigned_acs = set()
_task_files = glob.glob(os.path.join(os.path.dirname(rp), '..', 'tasks', '*.yaml'))
for _tf in _task_files:
    try:
        with open(_tf) as _tfh:
            _td = yaml.safe_load(_tfh) or {}
        _task = _td.get('task', _td)
        _aa = str(_task.get('assigned_acs', '') or '').strip()
        _pcmd = str(_task.get('parent_cmd', '') or '').strip()
        _rpcmd = str(data.get('parent_cmd', '') or '').strip()
        if _aa and _pcmd == _rpcmd:
            _assigned_acs = {a.strip() for a in _aa.replace(',', ' ').split()}
            break
    except Exception:
        pass
if isinstance(bc, dict) and bc:
    total_checks = 0
    empty_results = 0
    for ac_key, ac_val in bc.items():
        if _assigned_acs and ac_key != 'commit' and ac_key not in _assigned_acs:
            continue  # P4: 担当外ACはスキップ
        if isinstance(ac_val, list):
            for item in ac_val:
                if isinstance(item, dict) and 'check' in item:
                    total_checks += 1
                    r = str(item.get('result', '')).strip()
                    if not r or r == '\"\"':
                        empty_results += 1
    if total_checks > 0 and empty_results == total_checks:
        issues.append(f'binary_checks {total_checks}件全てのresultが空。yes/noを記入してからverdictを書け')
    elif total_checks > 0 and empty_results > 0:
        issues.append(f'binary_checks {empty_results}/{total_checks}件のresultが未記入。全件yes/noを記入してからverdictを書け')
if issues:
    for iss in issues:
        print(f'BLOCK: {iss}', file=sys.stderr)
    sys.exit(1)
" || return 1
            fi
            ;;
    esac
    return 0
}

# --- Pre-validation autofix: 機械的フォーマットエラーを自動正規化 ---
# Phase 4原理: 忍者は/clearで記憶を失う。BLOCKでCTX浪費するより構文正規化で通す。
# 意味的エラー(空フィールド等)はBLOCK維持。構文エラー(true→yes, list→dict)のみautofix。
_autofix_field_value() {
    local dot_key="$1"
    local val="$2"
    local field="${dot_key%%.*}"

    case "$field" in
        binary_checks)
            # result: true/True/PASS/Pass/pass → yes, false/False/FAIL/Fail/fail → no
            if [[ "$dot_key" == "binary_checks" ]] || [[ "$dot_key" == binary_checks.AC* ]]; then
                local fixed
                fixed=$(python3 -c "
import yaml, sys, json
raw = sys.stdin.read()
try:
    data = yaml.load(raw, Loader=yaml.BaseLoader)
except yaml.YAMLError:
    print(raw, end='')
    sys.exit(0)
changed = False
true_aliases = {'true','True','TRUE','PASS','Pass','pass','OK','ok','Ok','YES'}
false_aliases = {'false','False','FALSE','FAIL','Fail','fail','NG','ng','Ng','NO'}
def fix_items(items):
    global changed
    if not isinstance(items, list):
        return items
    for item in items:
        if not isinstance(item, dict):
            continue
        r = str(item.get('result','')).strip()
        if r in true_aliases:
            item['result'] = 'yes'
            changed = True
        elif r in false_aliases:
            item['result'] = 'no'
            changed = True
    return items
if isinstance(data, dict):
    for k, v in data.items():
        data[k] = fix_items(v)
elif isinstance(data, list):
    data = fix_items(data)
if changed:
    print('[autofix] binary_checks result正規化(true/PASS→yes, false/FAIL→no)', file=sys.stderr)
import re
out = yaml.dump(data, default_flow_style=False, allow_unicode=True)
out = re.sub(r'(result: )[' + chr(39) + chr(34) + r']?(yes|no)[' + chr(39) + chr(34) + r']?', r'\1\2', out)
print(out, end='')
" <<< "$val")
                echo "$fixed"
                return 0
            fi
            ;;
        files_modified)
            # string/string-list → dict-list (忍者がパス文字列だけを書く頻出パターン)
            if [[ "$dot_key" == "files_modified" ]]; then
                local fixed
                fixed=$(python3 -c "
import yaml, sys
raw = sys.stdin.read()
try:
    data = yaml.safe_load(raw)
except yaml.YAMLError:
    print(raw, end='')
    sys.exit(0)
if isinstance(data, str) and data.strip():
    print('[autofix] files_modified string→dict変換(単一ファイル)', file=sys.stderr)
    print(yaml.dump([{'path': data.strip(), 'change': 'modified'}], default_flow_style=False, allow_unicode=True), end='')
elif isinstance(data, list) and all(isinstance(x, str) for x in data):
    items = [{'path': x.strip(), 'change': 'modified'} for x in data if x.strip()]
    if items:
        print('[autofix] files_modified string list→dict list変換', file=sys.stderr)
        print(yaml.dump(items, default_flow_style=False, allow_unicode=True), end='')
    else:
        print(raw, end='')
else:
    print(raw, end='')
" <<< "$val")
                echo "$fixed"
                return 0
            fi
            ;;
        lessons_useful)
            # dict → list of 1 dict (忍者がlistでなくdictで書く頻出パターン)
            if [[ "$dot_key" == "lessons_useful" ]]; then
                local fixed
                fixed=$(python3 -c "
import yaml, sys
raw = sys.stdin.read()
try:
    data = yaml.safe_load(raw)
except yaml.YAMLError:
    print(raw, end='')
    sys.exit(0)
if isinstance(data, dict) and ('id' in data or 'useful' in data or 'reason' in data):
    print('[autofix] lessons_useful dict→list変換(単体dictをlistに包む)', file=sys.stderr)
    print(yaml.dump([data], default_flow_style=False, allow_unicode=True), end='')
elif isinstance(data, dict) and all(isinstance(v, dict) for v in data.values()):
    # {0: {id:..}, 1: {id:..}} 形式 → list化
    items = [v for k, v in sorted(data.items(), key=lambda x: str(x[0]))]
    print('[autofix] lessons_useful 数値キーdict→list変換', file=sys.stderr)
    print(yaml.dump(items, default_flow_style=False, allow_unicode=True), end='')
else:
    print(raw, end='')
" <<< "$val")
                echo "$fixed"
                return 0
            fi
            ;;
        lesson_candidate)
            # list of 1 dict → dict (忍者がdictをlistで包む頻出パターン)
            if [[ "$dot_key" == "lesson_candidate" ]]; then
                local fixed
                fixed=$(python3 -c "
import yaml, sys
raw = sys.stdin.read()
try:
    data = yaml.safe_load(raw)
except yaml.YAMLError:
    print(raw, end='')
    sys.exit(0)
if isinstance(data, list) and len(data) == 1 and isinstance(data[0], dict):
    print('[autofix] lesson_candidate list→dict変換(要素1のlistからdict抽出)', file=sys.stderr)
    print(yaml.dump(data[0], default_flow_style=False, allow_unicode=True), end='')
elif isinstance(data, list) and len(data) >= 1:
    # 複数要素listの場合: 全要素をキー統合してdictに
    merged = {}
    for item in data:
        if isinstance(item, dict):
            merged.update(item)
    if merged:
        print('[autofix] lesson_candidate list→dict変換(複数要素を統合)', file=sys.stderr)
        print(yaml.dump(merged, default_flow_style=False, allow_unicode=True), end='')
    else:
        print(raw, end='')
else:
    print(raw, end='')
" <<< "$val")
                echo "$fixed"
                return 0
            fi
            ;;
    esac
    echo "$val"
    return 0
}

# Execute pre-write autofix + validation
_val_input="$VALUE"
if [ -n "$STDIN_VALUE" ]; then
    _val_input="$STDIN_VALUE"
fi
# Autofix: 機械的正規化
_fixed_input=$(_autofix_field_value "$DOT_KEY" "$_val_input")
if [ "$_fixed_input" != "$_val_input" ]; then
    # Autofixed — update the value for downstream processing
    if [ -n "$STDIN_VALUE" ]; then
        STDIN_VALUE="$_fixed_input"
    fi
    VALUE="$_fixed_input"
    _val_input="$_fixed_input"
    # Autofix may have converted scalar→structure (e.g., string→YAML list)
    # Re-check if Python fallback is needed
    if [ "$USE_PYTHON" -eq 0 ]; then
        if [[ "$VALUE" == *$'\n'* ]] || [[ "$VALUE" == '['* ]] || [[ "$VALUE" == '{'* ]]; then
            USE_PYTHON=1
            STDIN_VALUE="$VALUE"
        fi
    fi
fi
# ★構造的矛盾排除: verdict書込み時にbc:noがあればFAIL強制(間違える余地を潰す)
if [[ "$DOT_KEY" == "verdict" ]] && [[ "$_val_input" == "PASS" || "$_val_input" == "PASS_NO_IMPROVEMENT" ]]; then
    _bc_has_no=$(REPORT_PATH="$REPORT_PATH" python3 -c "
import yaml, sys, os
rp = os.environ.get('REPORT_PATH', '')
if not rp or not os.path.exists(rp):
    sys.exit(0)
with open(rp) as f:
    data = yaml.safe_load(f) or {}
bc = data.get('binary_checks', {})
if isinstance(bc, dict):
    for ac_val in bc.values():
        if isinstance(ac_val, list):
            for item in ac_val:
                if isinstance(item, dict) and str(item.get('result', '')).strip().lower() == 'no':
                    print('yes', end='')
                    sys.exit(0)
" 2>/dev/null) || true
    if [[ "$_bc_has_no" == "yes" ]]; then
        echo "★ verdict自動修正: PASS→FAIL(bc:noあり。矛盾状態を作れない構造)" >&2
        _val_input="FAIL"
        VALUE="FAIL"
        if [ -n "$STDIN_VALUE" ]; then STDIN_VALUE="FAIL"; fi
    fi
fi
# Validate: 意味的エラーはBLOCK
if ! _validate_field_value "$DOT_KEY" "$_val_input"; then
    echo "[report_field_set] BLOCKED: 値フォーマット不正。上記メッセージに従い修正せよ。" >&2
    exit 1
fi

# Parse dot notation
IFS='.' read -ra KEYS <<< "$DOT_KEY"
NUM_KEYS=${#KEYS[@]}

# Create file if not exists
[ -f "$REPORT_PATH" ] || touch "$REPORT_PATH"

# --- Fast path: scalar root / 2-level nested writes without sourcing yaml_field_set.sh ---
# Common report updates (status/result.summary/etc.) dominate call volume. Keep the
# Python/list paths unchanged, and only short-circuit the simple scalar mapping case.
_report_field_set_fast_scalar() {
    local report_path="$1"
    local tmp_file="$2"
    local dot_key="$3"
    local value="$4"
    local num_keys="$5"
    shift 5
    local keys=("$@")

    if [ "$num_keys" -gt 2 ]; then
        return 2
    fi
    if [[ "$dot_key" == *'['* ]] || [[ "$value" == '['* ]] || [[ "$value" == '{'* ]] || [[ "$value" == *$'\n'* ]]; then
        return 2
    fi

    if [ "$num_keys" -eq 1 ]; then
        awk \
            -v field="${keys[0]}" \
            -v new_value="$value" '
function regex_escape(str,    out,i,c) {
    out = ""
    for (i = 1; i <= length(str); i++) {
        c = substr(str, i, 1)
        if (c ~ /[][\\.^$*+?(){}|]/) out = out "\\" c
        else out = out c
    }
    return out
}
function yaml_safe(v,    out,i,c,needs_quote) {
    needs_quote = 0
    if (index(v, ":") > 0) needs_quote = 1
    if (index(v, "#") > 0) needs_quote = 1
    if (index(v, "[") > 0) needs_quote = 1
    if (index(v, "]") > 0) needs_quote = 1
    if (index(v, "{") > 0) needs_quote = 1
    if (index(v, "}") > 0) needs_quote = 1
    if (needs_quote) {
        out = ""
        for (i = 1; i <= length(v); i++) {
            c = substr(v, i, 1)
            if (c == "\"") out = out "\\" c
            else out = out c
        }
        return "\"" out "\""
    }
    return v
}
BEGIN { replaced = 0; has_fields = 0; skip_continuation = 0 }
{
    field_re = "^" regex_escape(field) ":[[:space:]]*"
    if (!replaced && $0 ~ field_re) {
        print field ": " yaml_safe(new_value)
        replaced = 1
        has_fields = 1
        skip_continuation = 1
        next
    }
    # GP-234: block scalar continuation行スキップ
    if (skip_continuation) {
        if ($0 ~ /^[[:space:]]/ || $0 ~ /^$/) { next }
        skip_continuation = 0
    }
    if ($0 ~ /^[A-Za-z0-9_.-]+:[[:space:]]/) has_fields = 1
    print
}
END {
    if (!has_fields) exit 2
    if (!replaced) print field ": " yaml_safe(new_value)
}
' "$report_path" > "$tmp_file"
        return $?
    fi

    awk \
        -v block_id="${keys[0]}" \
        -v field="${keys[1]}" \
        -v new_value="$value" '
function trim(s) { sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
function leading_spaces(line,    i,cnt,c) {
    cnt = 0
    for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (c == " ") cnt++
        else break
    }
    return cnt
}
function make_indent(n,    s,i) {
    s = ""
    for (i = 0; i < n; i++) s = s " "
    return s
}
function regex_escape(str,    out,i,c) {
    out = ""
    for (i = 1; i <= length(str); i++) {
        c = substr(str, i, 1)
        if (c ~ /[][\\.^$*+?(){}|]/) out = out "\\" c
        else out = out c
    }
    return out
}
function yaml_safe(v,    out,i,c,needs_quote) {
    needs_quote = 0
    if (index(v, ":") > 0) needs_quote = 1
    if (index(v, "#") > 0) needs_quote = 1
    if (index(v, "[") > 0) needs_quote = 1
    if (index(v, "]") > 0) needs_quote = 1
    if (index(v, "{") > 0) needs_quote = 1
    if (index(v, "}") > 0) needs_quote = 1
    if (needs_quote) {
        out = ""
        for (i = 1; i <= length(v); i++) {
            c = substr(v, i, 1)
            if (c == "\"") out = out "\\" c
            else out = out c
        }
        return "\"" out "\""
    }
    return v
}
BEGIN {
    block_found = 0
    in_block = 0
    replaced = 0
    block_indent = -1
    field_indent = -1
}
{
    if (!in_block) {
        block_re = "^" regex_escape(block_id) ":[[:space:]]*$"
        if ($0 ~ block_re) {
            in_block = 1
            block_found = 1
            block_indent = leading_spaces($0)
            field_indent = block_indent + 2
        }
        print
        next
    }

    trimmed = trim($0)
    indent = leading_spaces($0)
    if (trimmed != "" && trimmed !~ /^#/ && indent <= block_indent) {
        if (!replaced) {
            print make_indent(field_indent) field ": " yaml_safe(new_value)
            replaced = 1
        }
        in_block = 0
        print
        next
    }

    field_re = "^" make_indent(field_indent) regex_escape(field) ":[[:space:]]*"
    if (!replaced && $0 ~ field_re) {
        print make_indent(field_indent) field ": " yaml_safe(new_value)
        replaced = 1
        skip_continuation = 1
        next
    }

    # GP-234: block scalar continuation行スキップ（旧マルチライン値の残骸除去）
    if (skip_continuation) {
        if (trimmed == "" || indent > field_indent) {
            next  # continuation行をスキップ
        }
        skip_continuation = 0  # 同レベル以上のフィールドに到達→スキップ終了
    }

    print
}
END {
    if (!block_found) exit 2
    if (in_block && !replaced) print make_indent(field_indent) field ": " yaml_safe(new_value)
}
' "$report_path" > "$tmp_file"
}

# --- Python fallback (multi-line text, new block creation) ---
_report_field_set_python() {
    local rp="$1" dk="$2" val="$3" sv="$4"
    python3 -c "
import sys, os, yaml, tempfile, re

report_path = sys.argv[1]
dot_key = sys.argv[2]
value = sys.argv[3]
stdin_value = sys.argv[4] if len(sys.argv) > 4 else ''

if value == '-' and stdin_value:
    value = stdin_value
    try:
        # binary_checks: BaseLoaderでyes/noを文字列として保持(safe_loadはboolに変換してしまう)
        loader = yaml.BaseLoader if dot_key.startswith('binary_checks') else yaml.SafeLoader
        parsed = yaml.load(value, Loader=loader)
        if isinstance(parsed, (list, dict)):
            value = parsed
    except yaml.YAMLError:
        pass

if isinstance(value, str):
    if value.lower() == 'true':
        value = True
    elif value.lower() == 'false':
        value = False
    elif value.lower() in ('null', 'none'):
        value = None
    else:
        try:
            value = int(value)
        except (ValueError, TypeError):
            try:
                value = float(value)
            except (ValueError, TypeError):
                pass

if os.path.exists(report_path) and os.path.getsize(report_path) > 0:
    with open(report_path, 'r') as f:
        data = yaml.safe_load(f) or {}
else:
    data = {}

keys = dot_key.split('.')
current = data
for key in keys[:-1]:
    m = re.match(r'^(.+)\[(\d+)\]$', key)
    if m:
        arr_key, idx = m.group(1), int(m.group(2))
        if arr_key not in current or not isinstance(current.get(arr_key), list):
            current[arr_key] = []
        arr = current[arr_key]
        while len(arr) <= idx:
            arr.append(None)
        if arr[idx] is None or not isinstance(arr[idx], dict):
            arr[idx] = {}
        current = arr[idx]
    else:
        # GP-072c2: If current is a list and key is numeric, use list index
        if isinstance(current, list) and key.isdigit():
            idx = int(key)
            while len(current) <= idx:
                current.append({})
            if not isinstance(current[idx], dict):
                current[idx] = {}
            current = current[idx]
        elif isinstance(current, dict):
            existing = current.get(key)
            if isinstance(existing, (dict, list)):
                # GP-072c2: preserve list for next iteration's numeric index handling
                current = existing
            else:
                current[key] = {}
                current = current[key]
        else:
            current = {}

last_key = keys[-1]
m_last = re.match(r'^(.+)\[(\d+)\]$', last_key)
if m_last:
    arr_key, idx = m_last.group(1), int(m_last.group(2))
    if arr_key not in current or not isinstance(current.get(arr_key), list):
        current[arr_key] = []
    arr = current[arr_key]
    while len(arr) <= idx:
        arr.append(None)
    arr[idx] = value
else:
    # --- GP-053 cycle 3: binary_checks check項目保護 ---
    # テンプレートで事前展開されたcheck項目を忍者の上書きから保護。
    # 忍者はresultのみ更新可能。check項目はテンプレートのまま維持。
    # ★ただしFILLプレースホルダは保護対象外（忍者の具体的check文で上書き可能）
    if keys[0] == 'binary_checks' and len(keys) == 2 and isinstance(value, list):
        existing = current.get(last_key, [])
        if isinstance(existing, list) and existing:
            protected = 0
            for i, ex_item in enumerate(existing):
                if i < len(value) and isinstance(ex_item, dict) and isinstance(value[i], dict):
                    ex_check = ex_item.get('check', '')
                    if ex_check and isinstance(ex_check, str) and len(ex_check.strip()) > 5:
                        # FILLプレースホルダは保護しない（忍者が具体的check文で上書きすべき）
                        if ex_check.strip().startswith('FILL'):
                            continue
                        value[i]['check'] = ex_check
                        protected += 1
            if protected > 0:
                print(f'[report_field_set] binary_checks保護: {protected}個のcheck項目をテンプレートから維持', file=sys.stderr)
    current[last_key] = value

dir_name = os.path.dirname(report_path) or '.'
fd, tmp_path = tempfile.mkstemp(dir=dir_name, suffix='.tmp')
try:
    with os.fdopen(fd, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    # Fix yaml.dump quoting yes/no in binary_checks result fields
    import re as _re
    with open(tmp_path, 'r') as f:
        _content = f.read()
    _fixed = _re.sub(r'(    result: )[\\x27\\x22]?(yes|no)[\\x27\\x22]?', r'\\1\\2', _content)
    if _fixed != _content:
        with open(tmp_path, 'w') as f:
            f.write(_fixed)
    # Round-trip validation: reload and verify key fields survive yaml.dump
    with open(tmp_path, 'r') as f:
        reloaded = yaml.safe_load(f)
    if not isinstance(reloaded, dict):
        raise ValueError('yaml.dump produced non-dict output')
    # Verify critical fields survived round-trip
    for ck in ['worker_id', 'parent_cmd', 'verdict', 'status', 'ac_version_read']:
        orig = data.get(ck)
        reload_val = reloaded.get(ck)
        if orig is not None and reload_val is None:
            raise ValueError(f'yaml.dump lost field: {ck}')
    os.replace(tmp_path, report_path)
except Exception as e:
    try:
        os.unlink(tmp_path)
    except OSError:
        pass
    print(f'[report_field_set] YAML_DUMP_CORRUPTION: {e}. Original file preserved.', file=sys.stderr)
    sys.exit(1)

print(f'[report_field_set] {dot_key} = {value}')
" "$rp" "$dk" "$val" "$sv"
}

# --- Main write logic with flock + retries ---
MAX_RETRIES=3
for ((attempt = 1; attempt <= MAX_RETRIES; attempt++)); do
    (
        flock -w 5 200 || { echo "[report_field_set] flock failed (attempt $attempt)" >&2; exit 1; }

        # Multi-line stdin text → Python fallback
        if [ "$USE_PYTHON" -eq 1 ]; then
            _report_field_set_python "$REPORT_PATH" "$DOT_KEY" "-" "$STDIN_VALUE"
            exit $?
        fi

        # Array index key (e.g., files_modified[0]) → Python fallback
        # awk経路はリテラルキーとして扱うため配列インデックスを正しく処理できない
        if [[ "$DOT_KEY" == *'['* ]]; then
            _report_field_set_python "$REPORT_PATH" "$DOT_KEY" "$VALUE" "$STDIN_VALUE"
            exit $?
        fi

        # JSON/YAML structure value (starts with [ or {) → Python fallback (GP-038)
        # awk経路は構造体をリテラル文字列として書くためYAML破壊の原因になる
        if [[ "$VALUE" == '['* ]] || [[ "$VALUE" == '{'* ]]; then
            _report_field_set_python "$REPORT_PATH" "$DOT_KEY" "-" "$VALUE"
            exit $?
        fi

        tmp_file="${REPORT_PATH}.tmp.$$.$attempt"
        rm -f "$tmp_file"
        rc=0

        _report_field_set_fast_scalar "$REPORT_PATH" "$tmp_file" "$DOT_KEY" "$VALUE" "$NUM_KEYS" "${KEYS[@]}" || rc=$?
        if [ "$rc" -eq 0 ]; then
            :
        else
            ensure_yaml_field_set_loaded
        fi

        if [ "$rc" -eq 0 ]; then
            :
        elif [ "$NUM_KEYS" -eq 1 ]; then
            # Root-level field (e.g., "status")
            _yaml_field_set_apply_root "$REPORT_PATH" "$tmp_file" "${KEYS[0]}" "$VALUE" || rc=$?
            if [ "$rc" -eq 2 ]; then
                # No root-level fields found: append to file content
                if [ -s "$REPORT_PATH" ]; then
                    cat "$REPORT_PATH" > "$tmp_file"
                    if [[ "$VALUE" == *:* ]]; then
                        _escaped_val="${VALUE//\"/\\\"}"
                        echo "${KEYS[0]}: \"${_escaped_val}\"" >> "$tmp_file"
                    else
                        echo "${KEYS[0]}: $VALUE" >> "$tmp_file"
                    fi
                else
                    if [[ "$VALUE" == *:* ]]; then
                        _escaped_val="${VALUE//\"/\\\"}"
                        echo "${KEYS[0]}: \"${_escaped_val}\"" > "$tmp_file"
                    else
                        echo "${KEYS[0]}: $VALUE" > "$tmp_file"
                    fi
                fi
                rc=0
            fi
        elif [ "$rc" -eq 2 ]; then
            # Nested field: block_id = second-to-last segment, field = last segment
            BLOCK_ID="${KEYS[$((NUM_KEYS-2))]}"
            FIELD="${KEYS[$((NUM_KEYS-1))]}"
            _yaml_field_set_apply "$REPORT_PATH" "$tmp_file" "$BLOCK_ID" "$FIELD" "$VALUE" || rc=$?
            if [ "$rc" -eq 2 ]; then
                # Block not found → Python fallback for new structure creation
                rm -f "$tmp_file"
                _report_field_set_python "$REPORT_PATH" "$DOT_KEY" "$VALUE" ""
                exit $?
            fi
        fi

        if [ "$rc" -ne 0 ]; then
            rm -f "$tmp_file"
            echo "FATAL: report_field_set: failed to write $DOT_KEY in $REPORT_PATH" >&2
            exit 1
        fi

        if ! mv "$tmp_file" "$REPORT_PATH"; then
            rm -f "$tmp_file"
            echo "FATAL: report_field_set: atomic replace failed" >&2
            exit 1
        fi

        if [ "$rc" -ne 0 ]; then
            ensure_yaml_field_set_loaded
            actual=""
            if [ "$NUM_KEYS" -eq 1 ]; then
                actual="$(_yaml_field_get_root "$REPORT_PATH" "${KEYS[0]}")" || true
            else
                actual="$(_yaml_field_get_in_block "$REPORT_PATH" "$BLOCK_ID" "$FIELD")" || true
            fi

            normalized_actual="$(_yaml_field_set_normalize "$actual")"
            normalized_expected="$(_yaml_field_set_normalize "$VALUE")"
            if [ "$normalized_actual" != "$normalized_expected" ]; then
                echo "FATAL: report_field_set: post-write verification mismatch for $DOT_KEY (expected='$normalized_expected', actual='$normalized_actual')" >&2
                exit 1
            fi
        fi

        echo "[report_field_set] $DOT_KEY = ${VALUE:0:80}"

    ) 200>"$LOCKFILE" && break

    if [ "$attempt" -eq "$MAX_RETRIES" ]; then
        echo "[report_field_set] All $MAX_RETRIES attempts failed" >&2
        exit 1
    fi
    sleep 0.5
done

# --- GP-072c2: Post-write dict→list auto-conversion ---
# per-item書込み(lessons_useful.0.id等)後に数値キーdictをリストに変換
if [[ "$DOT_KEY" == lessons_useful.* ]] || [[ "$DOT_KEY" == binary_checks.*.* ]]; then
    python3 -c "
import yaml, sys, os, tempfile
rp = sys.argv[1]
dk = sys.argv[2]
if not os.path.exists(rp):
    sys.exit(0)
with open(rp) as f:
    data = yaml.safe_load(f) or {}
if not isinstance(data, dict):
    sys.exit(0)
changed = False
# Convert numeric-keyed dicts to lists
for field in ('lessons_useful',):
    val = data.get(field)
    if isinstance(val, dict) and all(str(k).isdigit() for k in val.keys()):
        max_idx = max(int(k) for k in val.keys())
        new_list = [val.get(i, val.get(str(i))) for i in range(max_idx + 1)]
        data[field] = new_list
        changed = True
# binary_checks per-AC: convert numeric-keyed dicts within each AC
bc = data.get('binary_checks')
if isinstance(bc, dict):
    for ac_key, ac_val in bc.items():
        if isinstance(ac_val, dict) and all(str(k).isdigit() for k in ac_val.keys()):
            max_idx = max(int(k) for k in ac_val.keys())
            new_list = [ac_val.get(i, ac_val.get(str(i))) for i in range(max_idx + 1)]
            bc[ac_key] = new_list
            changed = True
if changed:
    dir_name = os.path.dirname(rp) or '.'
    fd, tmp = tempfile.mkstemp(dir=dir_name, suffix='.tmp')
    with os.fdopen(fd, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    os.replace(tmp, rp)
    print(f'[report_field_set] dict→list auto-conversion applied for {dk}', file=sys.stderr)
" "$REPORT_PATH" "$DOT_KEY" 2>&1 || true
fi

# --- GP-053: binary_checks書込み直後のsemantic check ---
# 忍者がcheck="PASS"やresult=自由記述を書いた瞬間にフィードバック。
# gateは事後(cmd完了時)。ここは即時検出。品質の起点を早くする。
if [[ "$DOT_KEY" == binary_checks* ]]; then
    _bc_check=$(REPORT_PATH="$REPORT_PATH" python3 -c "
import yaml, os, sys
rp = os.environ['REPORT_PATH']
try:
    with open(rp) as f:
        data = yaml.safe_load(f)
except Exception:
    sys.exit(0)
if not isinstance(data, dict):
    sys.exit(0)
bc = data.get('binary_checks')
if not isinstance(bc, dict):
    sys.exit(0)
verdict_words = {'PASS','FAIL','OK','NG','yes','no','YES','NO','true','false','True','False','pass','fail','ok','ng'}
issues = []
for ac_key, ac_val in bc.items():
    if not isinstance(ac_val, list):
        continue
    for j, ci in enumerate(ac_val):
        if not isinstance(ci, dict):
            continue
        ck = str(ci.get('check','')).strip()
        rs = str(ci.get('result','')).strip()
        if ck in verdict_words:
            issues.append(f'{ac_key}[{j}].check=\"{ck}\" — 確認項目ではなく判定値。何を確認したかを書け')
        if rs and rs.lower() not in ('yes','no','true','false',''):
            issues.append(f'{ac_key}[{j}].result=\"{rs[:30]}\" — yes/noのみ。自由記述はdetailに書け')
if issues:
    print('\\n'.join(issues))
" 2>/dev/null) || true
    if [ -n "$_bc_check" ]; then
        echo "" >&2
        echo "⚠ binary_checks品質問題検出 ⚠" >&2
        echo "$_bc_check" >&2
        echo "FIX: check=「確認した内容」 result=\"yes\" or \"no\"" >&2
        echo "例: bash scripts/report_field_set.sh $REPORT_PATH binary_checks.AC1 '[{check: \"変数が除去されたか\", result: \"yes\"}]'" >&2
    fi
    # ★穴B/C対策: bc書込み後にverdictを自動再導出(矛���状態を時間軸でも作れない)
    _cur_verdict=$(REPORT_PATH="$REPORT_PATH" python3 -c "
import yaml, os, sys
rp = os.environ.get('REPORT_PATH', '')
if not rp or not os.path.exists(rp):
    sys.exit(0)
with open(rp) as f:
    data = yaml.safe_load(f) or {}
verdict = str(data.get('verdict', '')).strip()
if verdict not in ('PASS', 'PASS_NO_IMPROVEMENT'):
    sys.exit(0)  # FAILや未設定なら何もしない
bc = data.get('binary_checks', {})
if not isinstance(bc, dict):
    sys.exit(0)
for ac_val in bc.values():
    if isinstance(ac_val, list):
        for item in ac_val:
            if isinstance(item, dict) and str(item.get('result', '')).strip().lower() == 'no':
                print('INCONSISTENT', end='')
                sys.exit(0)
" 2>/dev/null) || true
    if [[ "$_cur_verdict" == "INCONSISTENT" ]]; then
        # verdict:PASSだがbc:noあり → FAILに自動修正
        bash "$0" "$REPORT_PATH" verdict FAIL 2>/dev/null
        echo "★ verdict自動再導出: bc:no追加によりPASS→FAIL強制(時間軸矛盾排除)" >&2
    fi
fi
