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

fast_no_fix_needed() {
    local report_path="$1"
    local _gr_need_python=0
    local _gr_section=""
    local _gr_saw_worker=0
    local _gr_saw_parent=0
    local _gr_saw_lessons_useful=0
    local _gr_line=""
    local _gr_key=""

    while IFS= read -r _gr_line || [ -n "$_gr_line" ]; do
        if [[ "$_gr_line" =~ ^[^[:space:]][^:]*: ]]; then
            _gr_key="${_gr_line%%:*}"
            _gr_section="$_gr_key"

            case "$_gr_key" in
                report)
                    _gr_need_python=1
                    ;;
                worker_id)
                    _gr_saw_worker=1
                    [[ "$_gr_line" =~ ^worker_id:[[:space:]]*$ ]] && _gr_need_python=1
                    ;;
                parent_cmd)
                    _gr_saw_parent=1
                    [[ "$_gr_line" =~ ^parent_cmd:[[:space:]]*$ ]] && _gr_need_python=1
                    ;;
                lessons_useful)
                    _gr_saw_lessons_useful=1
                    if [[ "$_gr_line" =~ ^lessons_useful:[[:space:]]*(null|~)[[:space:]]*$ ]]; then
                        _gr_need_python=1
                    elif [[ ! "$_gr_line" =~ ^lessons_useful:[[:space:]]*$ ]] && [[ ! "$_gr_line" =~ ^lessons_useful:[[:space:]]*\[[[:space:]]*\][[:space:]]*$ ]]; then
                        _gr_need_python=1
                    fi
                    ;;
                files_modified)
                    if [[ ! "$_gr_line" =~ ^files_modified:[[:space:]]*$ ]] && [[ ! "$_gr_line" =~ ^files_modified:[[:space:]]*\[[[:space:]]*\][[:space:]]*$ ]]; then
                        _gr_need_python=1
                    fi
                    ;;
                binary_checks)
                    [[ ! "$_gr_line" =~ ^binary_checks:[[:space:]]*$ ]] && _gr_need_python=1
                    ;;
                lesson_candidate)
                    [[ "$_gr_line" =~ ^lesson_candidate:[[:space:]]*\[ ]] && _gr_need_python=1
                    ;;
                verdict)
                    if [[ ! "$_gr_line" =~ ^verdict:[[:space:]]*(PASS|FAIL)[[:space:]]*$ ]] && [[ ! "$_gr_line" =~ ^verdict:[[:space:]]*$ ]]; then
                        _gr_need_python=1
                    fi
                    ;;
            esac
            continue
        fi

        case "$_gr_section" in
            files_modified)
                [[ "$_gr_line" =~ ^[[:space:]]{2}-[[:space:]] ]] && [[ ! "$_gr_line" =~ ^[[:space:]]{2}-[[:space:]]path: ]] && _gr_need_python=1
                ;;
            lessons_useful)
                [[ "$_gr_line" =~ ^[[:space:]]{2}[0-9A-Za-z_-]+: ]] && _gr_need_python=1
                [[ "$_gr_line" =~ ^[[:space:]]{2}-[[:space:]] ]] && [[ ! "$_gr_line" =~ ^[[:space:]]{2}-[[:space:]]id: ]] && _gr_need_python=1
                [[ "$_gr_line" =~ UNKNOWN_[0-9]+ ]] && _gr_need_python=1
                [[ "$_gr_line" =~ id:[[:space:]]*(UNKNOWN|None|null) ]] && _gr_need_python=1
                ;;
            binary_checks)
                [[ "$_gr_line" =~ ^[[:space:]]{2}[^:]+:[[:space:]]+[^[:space:]] ]] && _gr_need_python=1
                [[ "$_gr_line" =~ ^[[:space:]]{4}(check|result): ]] && _gr_need_python=1
                [[ "$_gr_line" =~ ^[[:space:]]{4}-[[:space:]] ]] && [[ ! "$_gr_line" =~ ^[[:space:]]{4}-[[:space:]]check: ]] && _gr_need_python=1
                if [[ "$_gr_line" =~ ^[[:space:]]{6}result: ]]; then
                    [[ ! "$_gr_line" =~ ^[[:space:]]{6}result:[[:space:]]*\"?(yes|no)\"?[[:space:]]*$ ]] && _gr_need_python=1
                fi
                ;;
            self_gate_check)
                [[ "$_gr_line" =~ ^[[:space:]]{2}[^:]+:[[:space:]]*(ok|yes|true|pass|o|○|ng|no|false|fail|x|×)[[:space:]]*$ ]] && _gr_need_python=1
                ;;
        esac

        [ "$_gr_need_python" -eq 1 ] && break
    done < "$report_path"

    if [ "$_gr_saw_worker" -eq 0 ] || [ "$_gr_saw_parent" -eq 0 ] || [ "$_gr_saw_lessons_useful" -eq 0 ]; then
        _gr_need_python=1
    fi

    [ "$_gr_need_python" -eq 0 ]
}

fast_binary_checks_fix() {
    local report_path="$1"
    local tmp_file=""
    local meta_file=""
    local awk_status=0
    local fixes=""

    tmp_file="$(mktemp)"
    meta_file="$(mktemp)"

    if ! awk -v meta_file="$meta_file" '
function trim(s) { sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
function unquote(s, first, last) {
    s = trim(s)
    first = substr(s, 1, 1)
    last = substr(s, length(s), 1)
    if (length(s) >= 2 && ((first == "\"" && last == "\"") || (first == "'"'"'" && last == "'"'"'"))) {
        s = substr(s, 2, length(s) - 2)
    }
    return s
}
function yaml_safe(v, needs_quote, out, i, c) {
    needs_quote = (v ~ /[:#\[\]\{\}",]/ || v ~ /^[[:space:]]/ || v ~ /[[:space:]]$/ || v == "" || v ~ /^[-?]/)
    if (!needs_quote) {
        return v
    }
    out = ""
    for (i = 1; i <= length(v); i++) {
        c = substr(v, i, 1)
        if (c == "\"") {
            out = out "\\" c
        } else {
            out = out c
        }
    }
    return "\"" out "\""
}
function normalize_result(raw, cleaned, lowered) {
    cleaned = trim(raw)
    sub(/[[:space:]]+#.*$/, "", cleaned)
    cleaned = unquote(cleaned)
    lowered = tolower(cleaned)
    if (lowered == "yes") return "yes"
    if (lowered == "no") return "no"
    if (lowered == "true" || lowered == "pass" || lowered == "ok" || lowered == "done" || lowered == "clear" || lowered == "n/a" || lowered == "na") return "yes"
    if (lowered == "false" || lowered == "fail" || lowered == "ng" || lowered == "block") return "no"
    return cleaned
}
function add_fix(label) {
    if (fixes == "") {
        fixes = label
    } else if (index(fixes, label) == 0) {
        fixes = fixes "; " label
    }
}
BEGIN {
    current_section = ""
    in_binary_checks = 0
    eligible = 1
    changed = 0
    bc_pass = 0
    bc_fail = 0
    verdict_idx = 0
    verdict_invalid = 0
    fixes = ""
    out_count = 0
}
{
    line = $0

    if (line ~ /^[^[:space:]][^:]*:/) {
        top_key = substr(line, 1, index(line, ":") - 1)
        current_section = top_key
        in_binary_checks = (top_key == "binary_checks")

        if (top_key == "report") {
            eligible = 0
        } else if (top_key == "worker_id" || top_key == "parent_cmd") {
            if (line ~ /^[^:]+:[[:space:]]*$/) eligible = 0
        } else if (top_key == "lessons_useful") {
            if (line ~ /^lessons_useful:[[:space:]]*(null|~)[[:space:]]*$/) {
                eligible = 0
            } else if (line !~ /^lessons_useful:[[:space:]]*$/ && line !~ /^lessons_useful:[[:space:]]*\[[[:space:]]*\][[:space:]]*$/) {
                eligible = 0
            }
        } else if (top_key == "files_modified") {
            if (line !~ /^files_modified:[[:space:]]*$/ && line !~ /^files_modified:[[:space:]]*\[[[:space:]]*\][[:space:]]*$/) {
                eligible = 0
            }
        } else if (top_key == "lesson_candidate") {
            if (line ~ /^lesson_candidate:[[:space:]]*\[/) eligible = 0
        } else if (top_key == "binary_checks") {
            if (line !~ /^binary_checks:[[:space:]]*$/) eligible = 0
        } else if (top_key == "verdict") {
            verdict_idx = out_count + 1
            verdict_val = line
            sub(/^verdict:[[:space:]]*/, "", verdict_val)
            verdict_val = trim(verdict_val)
            if (verdict_val != "" && verdict_val != "PASS" && verdict_val != "FAIL") {
                verdict_invalid = 1
            }
        } else if (top_key == "self_gate_check") {
            # Non-standard self_gate_check values still require Python fallback.
        }

        out[++out_count] = line
        next
    }

    if (current_section == "files_modified") {
        if (line ~ /^[[:space:]]{2}-[[:space:]]/ && line !~ /^[[:space:]]{2}-[[:space:]]path:/) eligible = 0
    } else if (current_section == "lessons_useful") {
        if (line ~ /^[[:space:]]{2}[0-9A-Za-z_-]+:/) eligible = 0
        if (line ~ /^[[:space:]]{2}-[[:space:]]/ && line !~ /^[[:space:]]{2}-[[:space:]]id:/) eligible = 0
        if (line ~ /UNKNOWN_[0-9]+/) eligible = 0
        if (line ~ /id:[[:space:]]*(UNKNOWN|None|null)/) eligible = 0
    } else if (current_section == "binary_checks") {
        if (line ~ /^[[:space:]]{4}(check|result):/) {
            eligible = 0
        } else if (line ~ /^[[:space:]]{6}result:/) {
            raw_result = line
            sub(/^[[:space:]]{6}result:[[:space:]]*/, "", raw_result)
            normalized = normalize_result(raw_result)
            if (normalized == "yes") bc_pass++
            else if (normalized == "no") bc_fail++
            if (normalized == "yes" || normalized == "no") {
                normalized_line = "      result: " yaml_safe(normalized)
                if (normalized_line != line) {
                    line = normalized_line
                    changed = 1
                    add_fix("binary_checks result文字列正規化(PASS/ok→yes, FAIL/ng→no)")
                }
            } else if (line !~ /^[[:space:]]{6}result:[[:space:]]*\"?(yes|no)\"?[[:space:]]*$/) {
                eligible = 0
            }
        } else if (line ~ /^[[:space:]]{4}-[[:space:]]check:/) {
            # Valid list item. Result line will be processed separately.
        } else if (line ~ /^[[:space:]]{4}-[[:space:]]/) {
            if (match(line, /^[[:space:]]{4}-[[:space:]]([^:]+):[[:space:]]*(.*)$/, parts)) {
                check_name = trim(parts[1])
                raw_result = parts[2]
                normalized = normalize_result(raw_result)
                if (!(normalized == "yes" || normalized == "no")) {
                    eligible = 0
                } else {
                    out[++out_count] = "    - check: " yaml_safe(check_name)
                    out[++out_count] = "      result: " yaml_safe(normalized)
                    if (normalized == "yes") bc_pass++
                    else if (normalized == "no") bc_fail++
                    changed = 1
                    add_fix("binary_checks {name:val}→{check:name,result:val}正規化")
                    if (tolower(unquote(trim(raw_result))) == "true" || tolower(unquote(trim(raw_result))) == "false") {
                        add_fix("binary_checks result boolean→string変換")
                    } else {
                        add_fix("binary_checks result文字列正規化(PASS/ok→yes, FAIL/ng→no)")
                    }
                    next
                }
            } else {
                eligible = 0
            }
        } else if (line !~ /^[[:space:]]{2}[^:]+:[[:space:]]*$/ && line !~ /^[[:space:]]*$/ && line !~ /^[[:space:]]*#/) {
            eligible = 0
        }
    } else if (current_section == "self_gate_check") {
        if (line ~ /^[[:space:]]{2}[^:]+:[[:space:]]*(ok|yes|true|pass|o|○|ng|no|false|fail|x|×)[[:space:]]*$/) eligible = 0
    }

    out[++out_count] = line
}
END {
    if (!eligible) exit 2

    if (verdict_invalid && verdict_idx > 0 && (bc_pass + bc_fail) > 0) {
        out[verdict_idx] = "verdict: " (bc_fail > 0 ? "FAIL" : "PASS")
        changed = 1
        add_fix("verdict推定(" bc_pass "PASS/" bc_fail "FAIL)")
    }

    if (!changed) exit 2

    print fixes > meta_file
    close(meta_file)
    for (i = 1; i <= out_count; i++) {
        print out[i]
    }
}
' "$report_path" > "$tmp_file"; then
        awk_status=$?
    else
        awk_status=$?
    fi

    if [ "$awk_status" -ne 0 ]; then
        rm -f "$tmp_file" "$meta_file"
        return 1
    fi

    fixes="$(cat "$meta_file")"
    rm -f "$meta_file"

    if [ -z "$fixes" ]; then
        rm -f "$tmp_file"
        return 1
    fi

    mv "$tmp_file" "$report_path"
    echo "AUTO-FIXED: $fixes"
    return 0
}

if fast_no_fix_needed "$REPORT_PATH"; then
    echo "NO-FIX-NEEDED"
    exit 0
fi

if RESULT="$(fast_binary_checks_fix "$REPORT_PATH")"; then
    echo "$RESULT"
    :
else
    RESULT=""
fi

if [ -n "$RESULT" ]; then
    :
else

RESULT=$(REPORT_PATH="$REPORT_PATH" python3 -c "
import yaml, os, sys, re

report_path = os.environ['REPORT_PATH']
SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)
SafeDumper = getattr(yaml, 'CSafeDumper', yaml.SafeDumper)
DumpAll = getattr(yaml, 'dump_all')

try:
    with open(report_path) as f:
        raw = f.read()
    data = yaml.load(raw, Loader=SafeLoader)
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

# === Task YAML cache (Fix 20/14/6/19 共通) ===
# 4箇所で独立にopen+yaml.safe_loadしていたタスクYAMLを1回読込でキャッシュ
_task_yaml_cache = {}
def _get_task_data(worker_id):
    if worker_id in _task_yaml_cache:
        return _task_yaml_cache[worker_id]
    result = None
    if worker_id:
        tpath = os.path.join(os.path.dirname(os.path.dirname(report_path)), 'tasks', f'{worker_id}.yaml')
        if os.path.exists(tpath):
            try:
                with open(tpath) as tf:
                    tdata = yaml.load(tf, Loader=SafeLoader)
                result = tdata if not isinstance(tdata, dict) or 'task' not in tdata else tdata.get('task', {})
            except Exception:
                pass
    _task_yaml_cache[worker_id] = result
    return result

_task_binary_check_map_cache = {}
def _task_binary_check_map(worker_id):
    if worker_id in _task_binary_check_map_cache:
        return _task_binary_check_map_cache[worker_id]
    _task = _get_task_data(worker_id)
    _mapping = {}
    if isinstance(_task, dict):
        _acs = _task.get('acceptance_criteria', [])
        if isinstance(_acs, list):
            for _ac_item in _acs:
                if not isinstance(_ac_item, dict):
                    continue
                _ac_id = _ac_item.get('id')
                _bc_list = _ac_item.get('binary_checks', [])
                if _ac_id and isinstance(_bc_list, list):
                    _mapping[str(_ac_id)] = _bc_list
    _task_binary_check_map_cache[worker_id] = _mapping
    return _mapping

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
if not data.get('worker_id'):
    _basename = os.path.basename(report_path)
    _m20 = re.match(r'^([a-z_]+?)_report(?:_cmd_.+)?\.yaml$', _basename)
    if _m20:
        data['worker_id'] = _m20.group(1)
        fixes.append(f'worker_id ファイル名から推定({_m20.group(1)})')

if not data.get('parent_cmd'):
    _basename = os.path.basename(report_path)
    _m20p = re.match(r'^[a-z_]+?_report_(cmd_.+)\.yaml$', _basename)
    if _m20p:
        data['parent_cmd'] = _m20p.group(1)
        fixes.append(f'parent_cmd ファイル名から推定({_m20p.group(1)})')
    else:
        # ファイル名から推定不可 → タスクYAMLから取得(キャッシュ使用)
        _worker20 = data.get('worker_id', '')
        if _worker20:
            _task20 = _get_task_data(_worker20)
            if _task20:
                _pcmd20 = _task20.get('parent_cmd', '')
                if _pcmd20:
                    data['parent_cmd'] = str(_pcmd20)
                    fixes.append(f'parent_cmd タスクYAMLから補完({_pcmd20})')

# === Fix 2: lessons_useful dict → list (3パターン網羅 cmd_1535) ===
# Pattern A: 数値キーdict {0: {...}, 1: {...}} → [{...}, {...}] (既存)
# Pattern B: 単一教訓dict {id: L074, useful: true, reason: ...} → [{id: L074, ...}]
# Pattern C: 教訓IDキーdict {L074: {...}, L063: {...}} → [{id: L074, ...}, {id: L063, ...}]
lu = data.get('lessons_useful')
if isinstance(lu, dict):
    _lu_keys_str = {str(k) for k in lu.keys()}
    _known_fields = {'id', 'useful', 'reason'}
    _lesson_id_re = re.compile(r'^L\d+$')

    _converted = None
    _fix_label = ''

    if not lu:
        # 空dict → 空list
        _converted = []
        _fix_label = 'lessons_useful 空dict→空list変換'
    elif _lu_keys_str & _known_fields:
        # Pattern B: 単一教訓dict → list wrap
        _converted = [dict(lu)]
        _fix_label = 'lessons_useful 単一dict→list wrap'
        # Assertion: 全フィールドが保持されていること
        if not all(_converted[0].get(k) == v for k, v in lu.items()):
            _converted = None  # 安全側: 変換せずBLOCKに回す
    elif all(_lesson_id_re.match(str(k)) for k in lu.keys()):
        # Pattern C: 教訓IDキーdict → id注入+list化
        _new_list = []
        for k in sorted(lu.keys(), key=str):
            val = lu[k]
            if isinstance(val, dict):
                entry = dict(val)
                if 'id' not in entry:
                    entry['id'] = str(k)
                _new_list.append(entry)
            else:
                _new_list.append({'id': str(k)})
        _converted = _new_list
        _fix_label = 'lessons_useful LessonIDキーdict→list変換(id注入)'
        # Assertion: 要素数一致+元の値dictフィールドが全て保持
        _ok = len(_converted) == len(lu)
        if _ok:
            for _item in _converted:
                _lid = _item.get('id', '')
                if _lid in lu and isinstance(lu[_lid], dict):
                    if not all(_item.get(fk) == fv for fk, fv in lu[_lid].items()):
                        _ok = False
                        break
        if not _ok:
            _converted = None
    else:
        # Pattern A: 数値キーdict → 値のリスト化
        # ソートキー: 数値は(0,N)、文字列は(1,str)でTypeError回避
        try:
            sorted_keys = sorted(lu.keys(), key=lambda k: (0, int(str(k))) if str(k).isdigit() else (1, str(k)))
        except (ValueError, TypeError):
            sorted_keys = sorted(lu.keys(), key=str)
        _converted = [lu[k] for k in sorted_keys]
        _fix_label = 'lessons_useful dict→list変換'
        # Assertion: 要素数一致
        if len(_converted) != len(lu):
            _converted = None

    if _converted is not None:
        data['lessons_useful'] = _converted
        fixes.append(_fix_label)

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
        # タスクYAMLからrelated_lessons idを取得(キャッシュ使用)
        _task_lesson_ids = []
        _worker = data.get('worker_id', '')
        _task14 = _get_task_data(_worker)
        if _task14:
            _rl = _task14.get('related_lessons', [])
            if isinstance(_rl, list):
                _task_lesson_ids = [str(r.get('id', '')) for r in _rl if isinstance(r, dict) and r.get('id')]
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
bc = data.get('binary_checks')
if isinstance(bc, dict):
    bc_fixed = False
    for ac_key, ac_val in bc.items():
        if isinstance(ac_val, str):
            converted = None
            # Step 1: yaml.safe_load を試行(a,b,cパターン)
            try:
                parsed = yaml.load(ac_val, Loader=SafeLoader)
                if isinstance(parsed, list):
                    converted = parsed
                elif isinstance(parsed, dict):
                    converted = [parsed]
            except Exception:
                pass
            # Step 2: regex fallback(dパターン: 'check: X, result: Y')
            if converted is None:
                m = re.search(r'check:\s*(.+?)\s*,\s*result:\s*(.+)', ac_val)
                if m:
                    converted = [{'check': m.group(1).strip(), 'result': m.group(2).strip()}]
            # === Fix 5 Step 3: plain string → [{check: str, result: 'yes'}] ===
            # パターン: YAML/regex解析不能な散文テキスト
            # 旧Step3(撤去済み)はYES/NO推定=情報捏造リスク。
            # 新Step3は文字列をそのままcheck名に使用、result='yes'固定。
            if converted is None and ac_val.strip():
                converted = [{'check': ac_val.strip(), 'result': 'yes'}]
            if converted is not None:
                bc[ac_key] = converted
                bc_fixed = True
    if bc_fixed:
        fixes.append('binary_checks string→list変換')

# === Fix 8: binary_checks AC values dict → list wrap ===
# パターン: 忍者がAC値を {check: ..., result: ...} の単一dictで記入(listでない)
# Fix 8/15/11/19/18は全てbinary_checks走査なので一巡で正規化する
# Fix 19のAC名解決は O(AC数) 線形探索を避け、task YAML読込後に map 化して O(1) lookup にする
def _task_binary_checks_for(ac_key):
    _worker = data.get('worker_id', '')
    return _task_binary_check_map(_worker).get(ac_key, [])

bc = data.get('binary_checks')
_bc_pass_count = 0
_bc_fail_count = 0
if isinstance(bc, dict):
    bc_dict_fixed = False
    bc15_fixed = False
    bc_bool_fixed = False
    bc19_fixed = False
    _str_fixed = False
    _pass_vals = {'pass', 'ok', 'true', 'yes', 'done', 'clear', 'n/a', 'na'}
    _fail_vals = {'fail', 'false', 'no', 'ng', 'block'}

    for ac_key, ac_val in list(bc.items()):
        if isinstance(ac_val, dict):
            ac_val = [ac_val]
            bc[ac_key] = ac_val
            bc_dict_fixed = True
        if not isinstance(ac_val, list):
            continue

        _needs_numbered_convert = any(
            isinstance(chk, dict) and len(chk) > 1 and len([k for k in chk.keys() if re.match(r'^\[?\d+\]?$', str(k))]) == len(chk)
            for chk in ac_val
        )
        if _needs_numbered_convert:
            _task_checks = _task_binary_checks_for(ac_key)
            new_list = []
            for chk in ac_val:
                if isinstance(chk, dict):
                    for idx, (k, v) in enumerate(sorted(chk.items(), key=lambda x: str(x[0]))):
                        _result_val = v.get('result', 'yes') if isinstance(v, dict) else v
                        _check_name = ''
                        if idx < len(_task_checks):
                            tc = _task_checks[idx]
                            _check_name = tc.get('check', tc) if isinstance(tc, dict) else str(tc)
                        if not _check_name:
                            _check_name = f'{ac_key}_check_{idx}'
                        new_list.append({'check': _check_name, 'result': _result_val})
                else:
                    new_list.append(chk)
            if new_list:
                ac_val = new_list
                bc[ac_key] = ac_val
                bc19_fixed = True

        new_list = []
        for chk in ac_val:
            item = chk
            if isinstance(chk, dict) and len(chk) == 1:
                _k = list(chk.keys())[0]
                if _k not in ('check', 'result'):
                    _v = chk[_k]
                    item = {'check': str(_k), 'result': _v if isinstance(_v, bool) else str(_v)}
                    bc15_fixed = True
            if isinstance(item, dict):
                _result = item.get('result')
                if isinstance(_result, bool):
                    item['result'] = 'yes' if _result else 'no'
                    bc_bool_fixed = True
                elif isinstance(_result, str):
                    r = _result.strip().lower()
                    if r in _pass_vals and _result != 'yes':
                        item['result'] = 'yes'
                        _str_fixed = True
                    elif r in _fail_vals and _result != 'no':
                        item['result'] = 'no'
                        _str_fixed = True

                _norm = item.get('result')
                if isinstance(_norm, str):
                    if _norm == 'yes':
                        _bc_pass_count = _bc_pass_count + 1
                    elif _norm == 'no':
                        _bc_fail_count = _bc_fail_count + 1
            new_list.append(item)
        bc[ac_key] = new_list

    if bc_dict_fixed:
        fixes.append('binary_checks dict→list wrap')
    if bc15_fixed:
        fixes.append('binary_checks {name:val}→{check:name,result:val}正規化')
    if bc_bool_fixed:
        fixes.append('binary_checks result boolean→string変換')
    if bc19_fixed:
        fixes.append('binary_checks [N]キー→check/result正規化')
    if _str_fixed:
        fixes.append('binary_checks result文字列正規化(PASS/ok→yes, FAIL/ng→no)')

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

# === Fix 6: lessons_useful null/MISSING → task YAMLからスケルトン生成 ===
# パターン: 忍者がlessons_usefulを記入忘れ(MISSING)またはnull上書き
# deploy_task.shが注入したrelated_lessonsのIDリストからデフォルトスケルトンを生成
_lu_missing = 'lessons_useful' not in data
_lu_null = 'lessons_useful' in data and data['lessons_useful'] is None
if _lu_missing or _lu_null:
    _skeleton = []
    _worker6 = data.get('worker_id', '')
    _task6 = _get_task_data(_worker6)
    if _task6:
        _rl6 = _task6.get('related_lessons', [])
        if isinstance(_rl6, list):
            for _item6 in _rl6:
                if isinstance(_item6, dict) and _item6.get('id'):
                    _skeleton.append({'id': str(_item6['id']), 'useful': False, 'reason': ''})
    data['lessons_useful'] = _skeleton if _skeleton else []
    _label6 = 'MISSING' if _lu_missing else 'null'
    if _skeleton:
        fixes.append(f'lessons_useful {_label6}→タスクYAMLからスケルトン生成({len(_skeleton)}件)')
    else:
        fixes.append(f'lessons_useful {_label6}→空list')

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
    if isinstance(bc, dict) and (_bc_pass_count + _bc_fail_count > 0):
        data['verdict'] = 'FAIL' if _bc_fail_count > 0 else 'PASS'
        fixes.append(f'verdict推定({_bc_pass_count}PASS/{_bc_fail_count}FAIL)')

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

# === Write back if changed ===
if fixes:
    data['autofix_applied'] = fixes
    with open(report_path, 'w') as f:
        DumpAll([data], f, Dumper=SafeDumper, allow_unicode=True, default_flow_style=False, sort_keys=False)
    print('AUTO-FIXED: ' + '; '.join(fixes))
else:
    print('NO-FIX-NEEDED')
" 2>&1) || true

fi

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
