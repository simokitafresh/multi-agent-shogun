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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"

REPORT_PATH="$1"
DOT_KEY="$2"
VALUE="$3"

if [ -z "$REPORT_PATH" ] || [ -z "$DOT_KEY" ] || [ -z "$VALUE" ]; then
    echo "Usage: bash scripts/report_field_set.sh <report_path> <dot.notation.key> <value>" >&2
    echo "  value が '-' ならstdinから読む" >&2
    echo "Examples:" >&2
    echo "  bash scripts/report_field_set.sh queue/reports/hanzo_report_cmd_100.yaml results.AC1.status PASS" >&2
    echo "  echo 'long text' | bash scripts/report_field_set.sh queue/reports/hanzo_report_cmd_100.yaml results.AC1.notes -" >&2
    exit 1
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
    if python3 -c "
import yaml, sys
data = yaml.safe_load(sys.stdin.read())
sys.exit(0 if isinstance(data, (list, dict)) else 1)
" <<< "$STDIN_VALUE" 2>/dev/null; then
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
            fi
            ;;
        binary_checks)
            # Full-field write validation (GP-072 binary_checks型バリデーション)
            # BaseLoader使用: yes/noを文字列として保持し true/falseと区別する
            if [[ "$dot_key" == "binary_checks" ]]; then
                python3 -c "
import yaml, sys
err = '''ERROR: binary_checks must be YAML list of dicts with result: yes/no.
  Correct: - {check: 'テスト全PASS', result: yes}
  Wrong:   'AC1: YES, AC2: NO'
  Wrong:   result: true (use 'yes' not true)
  Wrong:   result: PASS (use 'yes' not 'PASS')'''
try:
    data = yaml.load(sys.stdin.read(), Loader=yaml.BaseLoader)
except yaml.YAMLError:
    print(err, file=sys.stderr)
    sys.exit(1)
if isinstance(data, str):
    print(err, file=sys.stderr)
    sys.exit(1)
if not isinstance(data, dict):
    print(err, file=sys.stderr)
    sys.exit(1)
for ac_key, ac_val in data.items():
    if not isinstance(ac_val, list):
        print(err, file=sys.stderr)
        sys.exit(1)
    for j, item in enumerate(ac_val):
        if not isinstance(item, dict):
            continue
        r = str(item.get('result', '')).strip()
        if r and r.lower() not in ('yes', 'no', ''):
            print(err, file=sys.stderr)
            sys.exit(1)
" <<< "$val" || return 1
            # GP-072c2: Per-AC write (e.g., binary_checks.AC1) — only 2-level depth
            elif [[ "$dot_key" == binary_checks.AC* ]] && [[ "$dot_key" != *.*.* ]]; then
                python3 -c "
import yaml, sys
err = '''ERROR: binary_checks must be YAML list of dicts with result: yes/no.
  Correct: - {check: 'テスト全PASS', result: yes}
  Wrong:   'AC1: YES, AC2: NO'
  Wrong:   result: true (use 'yes' not true)
  Wrong:   result: PASS (use 'yes' not 'PASS')'''
try:
    data = yaml.load(sys.stdin.read(), Loader=yaml.BaseLoader)
except yaml.YAMLError:
    print(err, file=sys.stderr)
    sys.exit(1)
if isinstance(data, str):
    print(err, file=sys.stderr)
    sys.exit(1)
if not isinstance(data, list):
    print(err, file=sys.stderr)
    sys.exit(1)
for j, item in enumerate(data):
    if not isinstance(item, dict):
        continue
    r = str(item.get('result', '')).strip()
    if r and r.lower() not in ('yes', 'no', ''):
        print(err, file=sys.stderr)
        sys.exit(1)
" <<< "$val" || return 1
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
        verdict)
            # GP-072c2+c3+c4: verdict書込み時に前提条件チェック
            if [[ "$dot_key" == "verdict" ]] && [[ "$val" == "PASS" || "$val" == "FAIL" ]]; then
                REPORT_PATH="$REPORT_PATH" python3 -c "
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
# GP-072c2: lessons_useful items must have non-empty reason
lu = data.get('lessons_useful', [])
if isinstance(lu, list):
    for i, item in enumerate(lu):
        if isinstance(item, dict):
            r = str(item.get('reason', '')).strip()
            if not r:
                issues.append(f'lessons_useful[{i}].reason が空')
# GP-072c4: binary_checks results must not be all empty
bc = data.get('binary_checks', {})
if isinstance(bc, dict) and bc:
    total_checks = 0
    empty_results = 0
    for ac_key, ac_val in bc.items():
        if isinstance(ac_val, list):
            for item in ac_val:
                if isinstance(item, dict) and 'check' in item:
                    total_checks += 1
                    r = str(item.get('result', '')).strip()
                    if not r or r == '\"\"':
                        empty_results += 1
    if total_checks > 0 and empty_results == total_checks:
        issues.append(f'binary_checks {total_checks}件全てのresultが空。yes/noを記入してからverdictを書け')
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

# Execute pre-write validation
_val_input="$VALUE"
if [ -n "$STDIN_VALUE" ]; then
    _val_input="$STDIN_VALUE"
fi
if ! _validate_field_value "$DOT_KEY" "$_val_input"; then
    echo "[report_field_set] BLOCKED: 値フォーマット不正。上記メッセージに従い修正せよ。" >&2
    exit 1
fi

# Parse dot notation
IFS='.' read -ra KEYS <<< "$DOT_KEY"
NUM_KEYS=${#KEYS[@]}

# Create file if not exists
[ -f "$REPORT_PATH" ] || touch "$REPORT_PATH"

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
        parsed = yaml.safe_load(value)
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
    if keys[0] == 'binary_checks' and len(keys) == 2 and isinstance(value, list):
        existing = current.get(last_key, [])
        if isinstance(existing, list) and existing:
            protected = 0
            for i, ex_item in enumerate(existing):
                if i < len(value) and isinstance(ex_item, dict) and isinstance(value[i], dict):
                    ex_check = ex_item.get('check', '')
                    if ex_check and isinstance(ex_check, str) and len(ex_check.strip()) > 5:
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
    os.replace(tmp_path, report_path)
except Exception:
    os.unlink(tmp_path)
    raise

print(f'[report_field_set] {dot_key} = {value}')
" "$rp" "$dk" "$val" "$sv"
}

# --- Main write logic with flock + retries ---
MAX_RETRIES=3
for attempt in $(seq 1 $MAX_RETRIES); do
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

        tmp_file="$(mktemp "${REPORT_PATH}.tmp.XXXXXX")"
        rc=0

        if [ "$NUM_KEYS" -eq 1 ]; then
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
        else
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

        # Post-write verification using shared library functions
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
        if rs and rs.lower() not in ('yes','no',''):
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
fi
