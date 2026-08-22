# deploy_task/task_contract.sh — cluster E: task YAML normalization and contract injection.
# Function bodies are extracted verbatim from deploy_task.sh.
inject_cmd_time_contract() {
    local task_file="$1"
    local cmd_id="$2"
    local source_path
    source_path=$(resolve_cmd_source_path "$cmd_id") || return 1
    python3 - "$task_file" "$source_path" "$cmd_id" <<'TIME_CONTRACT_INJECT_PY'
import os
import re
import sys
import tempfile
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task_path, source_path, cmd_id = sys.argv[1:]
with open(source_path, encoding="utf-8") as f:
    source = yaml.safe_load(f) or {}
entry = (source.get("commands") or {}).get(cmd_id)
if not isinstance(entry, dict):
    raise SystemExit(f"command not found: {cmd_id}")

field_order = ("estimated_minutes", "timeout_minutes", "split_decision", "execution_env")
projection = {key: entry[key] for key in field_order if key in entry}
if "estimated_minutes" not in projection:
    raise SystemExit("estimated_minutes missing after source contract precheck")

def scalar(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (int, float)):
        return str(value)
    quote = chr(39)
    text = str(value)
    return quote + text.replace(quote, quote + quote) + quote

def emit_field(key, value, indent=2):
    prefix = " " * indent
    if isinstance(value, dict):
        lines = [prefix + key + ":"]
        for nested_key, nested_value in value.items():
            if isinstance(nested_value, list):
                lines.append(prefix + "  " + str(nested_key) + ":")
                lines.extend(prefix + "  - " + scalar(item) for item in nested_value)
            else:
                lines.append(prefix + "  " + str(nested_key) + ": " + scalar(nested_value))
        return lines
    if isinstance(value, list):
        return [prefix + key + ":"] + [prefix + "- " + scalar(item) for item in value]
    return [prefix + key + ": " + scalar(value)]

with open(task_path, encoding="utf-8") as f:
    lines = f.read().splitlines()

# Replace rather than append so same-cmd recovery cannot create duplicate keys.
targets = set(field_order)
cleaned = []
skip_indent = None
for line in lines:
    stripped = line.lstrip(" ")
    indent = len(line) - len(stripped)
    if skip_indent is not None:
        if not stripped or indent > skip_indent or (indent == skip_indent and stripped.startswith("- ")):
            continue
        skip_indent = None
    if indent == 2 and ":" in stripped and stripped.split(":", 1)[0] in targets:
        skip_indent = indent
        continue
    cleaned.append(line)

insert_at = next((i + 1 for i, line in enumerate(cleaned) if line == "task:"), None)
if insert_at is None:
    raise SystemExit("task block missing")
block = []
for key in field_order:
    if key in projection:
        block.extend(emit_field(key, projection[key]))
cleaned[insert_at:insert_at] = block
rendered = "\n".join(cleaned) + "\n"
parsed = yaml.safe_load(rendered) or {}
task = parsed.get("task") or {}
for key, expected in projection.items():
    if task.get(key) != expected:
        raise SystemExit(f"projection mismatch: {key}")

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(task_path), suffix=".tmp")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(rendered)
    os.replace(tmp, task_path)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
TIME_CONTRACT_INJECT_PY
}

# ─── cmd assumptions構造保持注入 ───
inject_cmd_assumptions() {
    local task_file="$1"
    local cmd_id="$2"
    local source_path
    source_path=$(resolve_cmd_source_path "$cmd_id") || return 0
    python3 - "$task_file" "$source_path" "$cmd_id" <<'ASSUMPTIONS_INJECT_PY'
import os
import sys
import tempfile
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task_path, source_path, cmd_id = sys.argv[1:]
with open(source_path, encoding='utf-8') as f:
    source = yaml.safe_load(f) or {}
commands = source.get('commands', {})
entry = commands.get(cmd_id, {}) if isinstance(commands, dict) else {}
assumptions = entry.get('assumptions') if isinstance(entry, dict) else None
if assumptions is None:
    raise SystemExit(0)

def scalar(value):
    if value is None:
        return 'null'
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value)
    quote = chr(39)
    return quote + text.replace(quote, quote + quote) + quote

def emit_value(value, indent):
    prefix = ' ' * indent
    if isinstance(value, dict):
        if not value:
            return [prefix + '{}']
        lines = []
        for key, nested in value.items():
            if isinstance(nested, (dict, list)):
                lines.append(prefix + str(key) + ':')
                lines.extend(emit_value(nested, indent + 2))
            else:
                lines.append(prefix + str(key) + ': ' + scalar(nested))
        return lines
    if isinstance(value, list):
        if not value:
            return [prefix + '[]']
        lines = []
        for item in value:
            if isinstance(item, dict) and item:
                first = True
                for key, nested in item.items():
                    marker = '- ' if first else '  '
                    first = False
                    if isinstance(nested, (dict, list)):
                        lines.append(prefix + marker + str(key) + ':')
                        lines.extend(emit_value(nested, indent + 4))
                    else:
                        lines.append(prefix + marker + str(key) + ': ' + scalar(nested))
            elif isinstance(item, (dict, list)):
                lines.append(prefix + '-')
                lines.extend(emit_value(item, indent + 2))
            else:
                lines.append(prefix + '- ' + scalar(item))
        return lines
    return [prefix + scalar(value)]

with open(task_path, encoding='utf-8') as f:
    raw = f.read()
block = ['  assumptions:'] + emit_value(assumptions, 4)
lines = raw.splitlines()
insert_at = next((i + 1 for i, line in enumerate(lines) if line == 'task:'), None)
if insert_at is None:
    raise SystemExit('task block missing')
lines[insert_at:insert_at] = block
rendered = '\n'.join(lines) + '\n'
yaml.safe_load(rendered)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(task_path), suffix='.tmp')
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        f.write(rendered)
    os.replace(tmp, task_path)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
ASSUMPTIONS_INJECT_PY
}

# ─── cmd_1157: flat→nested YAML正規化 ───
# flat形式(task:ブロックなし)のtask YAMLをnested形式に変換する。
# 変換失敗時はログ出力のみ（配備は継続。yaml_field_setのフォールバック対応あり）
normalize_task_yaml() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        return 1
    fi

    # nested形式判定: 先頭が"task:"で始まる → 変換不要
    if head -1 "$task_file" | grep -qE '^task:'; then
        return 0
    fi

    # flat形式判定: task_id: or status: がルートに存在
    if ! grep -qE '^(task_id|status):' "$task_file"; then
        return 0  # flat形式でもない → 未知の形式、触らない
    fi

    log "normalize_task_yaml: flat→nested conversion for $(basename "$task_file")"

    local tmp_file
    tmp_file="$(mktemp "${task_file}.norm.XXXXXX")" || {
        log "normalize_task_yaml: mktemp failed"
        return 1
    }

    # 全行を2spインデントし、先頭に"task:"を追加
    {
        echo "task:"
        sed 's/^/  /' "$task_file"
    } > "$tmp_file"

    # 変換後のYAMLがyaml_field_setで操作可能か検証
    local verify_tmp
    verify_tmp="$(mktemp "${task_file}.verify.XXXXXX")" || {
        rm -f "$tmp_file"
        log "normalize_task_yaml: verify mktemp failed"
        return 1
    }

    # 検証: task blockが見つかることを確認（_yaml_field_set_applyのdry-run相当）
    if _yaml_field_get_in_block "$tmp_file" "task" "task_id" >/dev/null 2>&1 || \
       _yaml_field_get_in_block "$tmp_file" "task" "status" >/dev/null 2>&1; then
        mv "$tmp_file" "$task_file"
        rm -f "$verify_tmp"
        log "normalize_task_yaml: conversion successful"
        return 0
    else
        rm -f "$tmp_file" "$verify_tmp"
        log "normalize_task_yaml: verification failed, keeping original"
        return 1
    fi
}

# ─── task_id自動注入（cmd_465: STALL検知キー統一） ───
# subtask_idの値をtask_idとして注入。ninja_monitor check_stall()がtask_idを参照するため必須。
inject_task_id() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_task_id: task file not found: $task_file"
        return 1
    fi

    local subtask_id existing_task_id task_id
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" subtask_id task_id 2>/dev/null)" || true
    if [ -z "$subtask_id" ]; then
        log "inject_task_id: no subtask_id found, skipping"
        return 0
    fi

    existing_task_id="${task_id:-}"
    if [ -n "$existing_task_id" ] && [ "$existing_task_id" != "idle" ]; then
        log "inject_task_id: task_id already set ($existing_task_id), skipping"
        return 0
    fi

    yaml_field_set "$task_file" "task" "task_id" "$subtask_id" \
        || { log "FATAL: yaml_field_set failed for task_id (inject_task_id)"; return 1; }
    log "inject_task_id: set task_id=$subtask_id"
}

infer_ac_assigned_from_chunk_task_id() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "infer_ac_assigned: task file not found: $task_file"
        return 0
    fi

    local existing_ac existing_assigned task_id _ac_task_id ac_id ac_value ac_assigned assigned_acs
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" \
        ac_assigned assigned_acs task_id _ac_task_id 2>/dev/null)" || true
    existing_ac="${ac_assigned:-}"
    existing_assigned="${assigned_acs:-}"
    if [ -n "$existing_ac" ] || [ -n "$existing_assigned" ]; then
        log "infer_ac_assigned: existing assignment found, skipping"
        return 0
    fi

    task_id="${task_id:-${_ac_task_id:-}}"

    # cmd_karo_hotfix_chunk_marker_boundary_202607121210: 旧regexはunderscoreを非alnum境界として
    # 任意のac+数字(gate_ac3_hunk等の通常説明語)を拾い誤検知した。明示chunk命名規約
    # (cmd_2483_ac3_chunk2等の acN_chunkM 形式)のみに限定する。
    ac_id=$(printf '%s\n' "$task_id" | sed -nE 's/.*(^|[^[:alnum:]])[aA][cC]([0-9]+)_[cC][hH][uU][nN][kK]([0-9]+)?([^[:alnum:]]|$).*/AC\2/p' | head -n1)
    if [ -z "$ac_id" ]; then
        log "infer_ac_assigned: no AC marker in task_id (${task_id:-empty}), skipping"
        return 0
    fi

    ac_value="$ac_id"
    yaml_field_set_batch "$task_file" "task" \
        "ac_assigned=$ac_value" "assigned_acs=$ac_value" \
        || { log "FATAL: yaml_field_set_batch failed for AC assignment"; return 1; }
    log "infer_ac_assigned: task_id=${task_id} -> ac_assigned=${ac_value}"
}

# ─── inject_ac_assigned_from_stk: STKのcmd定義からac_assignedをtask YAMLに転記（cmd_2790） ───
# infer_ac_assigned_from_chunk_task_idがtask_id命名から推論するのに対し、
# こちらはshogun_to_karo.yamlのcmd定義に明示されたac_assignedをそのまま転記する。
# 分割配備時にcmd定義側でac_assignedを指定→各忍者のtask YAMLに自動転記。
# スカラー(AC1)/インラインリスト([AC1, AC2])両形式対応。
inject_ac_assigned_from_stk() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_ac_assigned_from_stk: task file not found: $task_file"
        return 0
    fi

    # 既にac_assignedが設定済みならスキップ（infer_ac_assigned_from_chunk_task_idと同じガード）
    local existing
    existing=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "ac_assigned" "" 2>/dev/null || true)
    if [ -n "$existing" ]; then
        log "inject_ac_assigned_from_stk: already set (${existing}), skipping"
        return 0
    fi

    # parent_cmdをtask YAMLから取得してSTKを検索
    local cmd_id
    cmd_id=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
    [ -z "$cmd_id" ] && return 0
    local stk
    stk=$(resolve_cmd_source_path "$cmd_id") || return 0

    # STKからcmd定義のac_assignedを読む（inline scalar/list形式対応）
    local ac_val
    ac_val=$(awk -v cmd="$cmd_id" '
        /^  [a-zA-Z]/ {
            key = $0; sub(/^  /, "", key); sub(/:.*/, "", key)
            in_cmd = (key == cmd)
        }
        in_cmd && /^    ac_assigned:[[:space:]]*/ {
            s = $0
            sub(/^    ac_assigned:[[:space:]]*/, "", s)
            sub(/[[:space:]]*$/, "", s)
            if (length(s) >= 2) {
                fc = substr(s,1,1); lc = substr(s,length(s),1)
                if ((fc == "\"" && lc == "\"") || (fc == "'" "'" && lc == "'" "'")) s = substr(s, 2, length(s)-2)
            }
            if (s != "") print s
            exit
        }
    ' "$stk" 2>/dev/null || true)

    [ -z "$ac_val" ] && return 0

    # task YAMLにac_assignedを書込む
    # スカラー値(AC1等): yaml_field_set使用
    # リスト値([AC1, AC2]): yaml_field_setがlist非対応のため直接awk書込み
    if [[ "$ac_val" != '['* ]]; then
        yaml_field_set "$task_file" "task" "ac_assigned" "$ac_val" \
            || { log "WARN: inject_ac_assigned_from_stk: yaml_field_set failed for ${cmd_id}"; return 0; }
    else
        # リスト形式: taskブロックの先頭フィールド前に挿入
        local tmp
        tmp=$(mktemp "${task_file}.tmp.XXXXXX") || return 0
        if awk -v ac_val="$ac_val" '
            BEGIN { done = 0 }
            /^task:[[:space:]]*$/ { print; next }
            !done && /^  [a-zA-Z_][a-zA-Z0-9_]*:/ {
                print "  ac_assigned: " ac_val
                done = 1
            }
            { print }
        ' "$task_file" > "$tmp"; then
            mv "$tmp" "$task_file"
        else
            rm -f "$tmp"
            log "WARN: inject_ac_assigned_from_stk: awk write failed for ${cmd_id}"
            return 0
        fi
    fi

    log "inject_ac_assigned_from_stk: cmd=${cmd_id} -> ac_assigned=${ac_val}"
}

# ─── ac_version自動注入（cmd_530: stale作業検知, cmd_1053: ハッシュ化, cmd_1493: 再配備AC上書き） ───
# acceptance_criteriaの各descriptionをソート→連結→md5先頭8桁をtask.ac_versionとして保持。
# 件数が同じでも内容が変われば異なるハッシュになる。再配備時に再計算される。
# cmd_1493: ac_version同一でもtask_id/worker_id変更時はcmdソースからAC上書き
# cmd_1393: Python→awk+md5sum置換

# ─── _compute_ac_hash: ACハッシュ計算ヘルパー ───
# cmd_2944: description:なし(karo_direct形式)のACでもcheck:フィールドをフォールバックとして使用。
# ac_item_indentを追跡してchecks[]内の"- check:"をitem境界と誤判定しない設計。
# description: 優先、なければchecks[]の全check値を"|"連結してdescs[]に格納。
_compute_ac_hash() {
    local task_file="$1"
    local concat
    # Hash parsed YAML values rather than physical lines. The former awk
    # parser skipped inline "- description:" values and all folded
    # continuation text, collapsing description-form ACs to one empty hash.
    concat=$(python3 - "$task_file" <<'PY'
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
task = data.get("task") if isinstance(data, dict) else None
raw_items = (task or {}).get("acceptance_criteria", []) if isinstance(task, dict) else []
# Support both list form ([{id: AC1, description: ...}]) and mapping form
# ({AC1: {description: ...}}) used by karo_direct drafts.
items = raw_items if isinstance(raw_items, list) else list(raw_items.values()) if isinstance(raw_items, dict) else []
values = []
for item in items:
    if not isinstance(item, dict):
        values.append(str(item))
        continue
    description = str(item.get("description", "")).strip()
    if description:
        values.append(description)
        continue
    checks = item.get("checks", [])
    if isinstance(checks, list):
        values.append("|".join(
            str(check.get("check", "")).strip() if isinstance(check, dict) else str(check).strip()
            for check in checks
        ))
    else:
        values.append(str(item.get("check", "")).strip())
sys.stdout.write("|".join(sorted(values)))
PY
    )
    printf '%s' "$concat" | md5sum | cut -c1-8
}

# ─── _overwrite_ac_from_cmd: cmdソースからAC上書き（cmd_1493） ───
# shogun_to_karo.yaml → archive/cmds/ の順でparent_cmdのACを探し、task YAMLに上書き。
# 教訓マーカー(【注入教訓】)もクリアして再注入を促す。
_overwrite_ac_from_cmd() {
    local task_file="$1"
    local parent_cmd
    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "")
    [ -z "$parent_cmd" ] && return 1

    local py_output
    py_output=$(mktemp) || {
        log "_overwrite_ac_from_cmd: mktemp failed"
        return 1
    }
    if python3 - "$task_file" "$parent_cmd" "$SCRIPT_DIR" <<'OVERWRITE_AC_PY' > "$py_output" 2>&1; then
import glob
import os
import re
import sys
import tempfile

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task_file = sys.argv[1]
parent_cmd = sys.argv[2]
script_dir = sys.argv[3]

def _convert_nested_ac(ac_dict):
    """ac: {AC1: {title, criteria}} → acceptance_criteria: [{id, title, checks}] 変換。
    cmd_1604+のネスト形式を、task YAML+binary_checks awk互換のリスト形式に変換する。"""
    if not isinstance(ac_dict, dict):
        return None
    result = []
    for ac_id, ac_body in ac_dict.items():
        if not isinstance(ac_body, dict):
            continue
        entry = {'id': ac_id}
        if 'title' in ac_body:
            entry['title'] = ac_body['title']
        criteria = ac_body.get('criteria', [])
        if isinstance(criteria, list) and criteria:
            entry['checks'] = [{'check': str(c)} for c in criteria]
        elif isinstance(ac_body.get('description'), str):
            description = ac_body['description']
            entry['description'] = description
            entry['checks'] = [{'check': description}]
        result.append(entry)
    return result if result else None

def _convert_flat_ac_dict(ac_dict):
    """acceptance_criteria: {AC1: "string", AC2: "string"} → [{id, checks}] 変換。
    cmd_1610型のAC-ID→文字列dictを、binary_checks awk互換リスト形式に変換。"""
    if not isinstance(ac_dict, dict):
        return None
    result = []
    for ac_id, ac_text in ac_dict.items():
        if isinstance(ac_text, str):
            result.append({'id': ac_id, 'description': ac_text, 'checks': [{'check': ac_text}]})
        elif isinstance(ac_text, dict):
            # ac: {AC1: {title, criteria}} がacceptance_criteriaキーで書かれたケース
            converted = _convert_nested_ac({ac_id: ac_text})
            if converted:
                result.extend(converted)
    return result if result else None

def _extract_acs_from_cmd(cmd):
    """cmdデータからACを抽出。3形式対応:
    1. acceptance_criteria: ['AC1: ...'] (flat list, ≤cmd_1603)
    2. acceptance_criteria: {AC1: "..."} (flat dict, cmd_1610型)
    3. ac: {AC1: {title, criteria}} (nested dict, cmd_1604+)
    リスト形式はそのまま返す。dict形式はbinary_checks awk互換リストに変換。"""
    acs = cmd.get('acceptance_criteria')
    if acs:
        if isinstance(acs, list):
            return acs  # 旧形式: flat list → そのまま
        if isinstance(acs, dict):
            converted = _convert_flat_ac_dict(acs)
            if converted:
                return converted
            return acs  # 変換失敗時はそのまま返す
    # 新形式: ac (nested dict, cmd_1604+)
    ac_nested = cmd.get('ac')
    if ac_nested and isinstance(ac_nested, dict):
        converted = _convert_nested_ac(ac_nested)
        if converted:
            return converted
    return None

def find_cmd_acs(pcmd, sdir):
    # 1. shogun_to_karo.yaml (dict format: commands.cmd_XXX.acceptance_criteria or .ac)
    stk_path = os.path.join(sdir, 'queue', 'shogun_to_karo.yaml')
    if os.path.exists(stk_path):
        try:
            with open(stk_path, encoding='utf-8') as f:
                stk = yaml.load(f, Loader=yaml.SafeLoader) or {}
            cmds = stk.get('commands', {})
            if isinstance(cmds, dict):
                cmd = cmds.get(pcmd, {})
                if isinstance(cmd, dict):
                    acs = _extract_acs_from_cmd(cmd)
                    if acs:
                        return acs
        except Exception:
            pass
    # 2. Archive fallback
    archive_dir = os.path.join(sdir, 'queue', 'archive', 'cmds')
    if os.path.isdir(archive_dir):
        for cpath in sorted(glob.glob(os.path.join(archive_dir, f'{pcmd}_*.yaml')), reverse=True):
            try:
                with open(cpath, encoding='utf-8') as f:
                    adata = yaml.load(f, Loader=yaml.SafeLoader) or {}
                cmds = adata.get('commands', {})
                if isinstance(cmds, dict):
                    cmd = cmds.get(pcmd, {})
                    if isinstance(cmd, dict):
                        acs = _extract_acs_from_cmd(cmd)
                        if acs:
                            return acs
            except Exception:
                continue
    return None

cmd_acs = find_cmd_acs(parent_cmd, script_dir)
if not cmd_acs:
    print(f'[AC_OVERWRITE] WARN: No ACs found for {parent_cmd} in cmd source', file=sys.stderr)
    sys.exit(1)

with open(task_file, 'r', encoding='utf-8') as f:
    raw = f.read()

# yaml.dump禁止(CLAUDE.md): 手動YAML構築でデータ消失を防止
def _sv(v, multiline_indent=2):
    if v is None: return 'null'
    if isinstance(v, bool): return str(v).lower()
    if isinstance(v, (int, float)): return str(v)
    s = str(v)
    if '\n' in s:
        return '|-\n' + '\n'.join(' ' * multiline_indent + ln for ln in s.split('\n'))
    sq = chr(39)
    return sq + s.replace(sq, sq + sq) + sq
def _yaml_lines(key, val, ind=0):
    p = ' ' * ind
    if not isinstance(val, (dict, list)):
        s = _sv(val, ind + 2)
        if '\n' in s:
            parts = s.split('\n')
            return [p + key + ': ' + parts[0]] + [p + x for x in parts[1:]]
        return [p + key + ': ' + s]
    if not val:
        return [p + key + ': ' + ('[]' if isinstance(val, list) else '{}')]
    r = [p + key + ':']
    if isinstance(val, dict):
        for k, v in val.items():
            r.extend(_yaml_lines(k, v, ind + 2))
    else:
        for item in val:
            r.extend(_list_item(item, ind))
    return r
def _list_item(item, ind):
    p = ' ' * ind
    if not isinstance(item, (dict, list)):
        s = _sv(item, ind + 2)
        if '\n' in s:
            parts = s.split('\n')
            return [p + '- ' + parts[0]] + [p + '  ' + x for x in parts[1:]]
        return [p + '- ' + s]
    if isinstance(item, dict) and item:
        lines = []
        first = True
        for k, v in item.items():
            tag = '- ' if first else '  '
            first = False
            if isinstance(v, (dict, list)) and v:
                lines.append(p + tag + k + ':')
                if isinstance(v, list):
                    for sub in v:
                        lines.extend(_list_item(sub, ind + 2))
                else:
                    for dk, dv in v.items():
                        lines.extend(_yaml_lines(dk, dv, ind + 4))
            else:
                sv = _sv(v, ind + 4) if not isinstance(v, (dict, list)) else ('[]' if isinstance(v, list) else '{}')
                if '\n' in sv:
                    parts = sv.split('\n')
                    lines.append(p + tag + k + ': ' + parts[0])
                    lines.extend(parts[1:])
                else:
                    lines.append(p + tag + k + ': ' + sv)
        return lines
    return [p + '- ' + ('[]' if isinstance(item, list) else '{}')]
frag = '\n'.join(_yaml_lines('acceptance_criteria', cmd_acs))
indented = '\n'.join('  ' + line for line in frag.split('\n'))

# Replace acceptance_criteria section（行ベース置換）
_lines = raw.split('\n')
_result = []
_skip = False
_inserted = False
for _l in _lines:
    _s = _l.lstrip(' ')
    _i = len(_l) - len(_s)
    if _skip:
        if _s == '' or _i > 2 or (_i == 2 and _s.startswith('- ')):
            continue
        _skip = False
    if _i == 2 and _s.startswith('acceptance_criteria:'):
        _skip = True
        _result.append(indented)
        _inserted = True
        continue
    _result.append(_l)
raw = '\n'.join(_result)
if not _inserted:
    task_match = re.search(r'^task:', raw, re.MULTILINE)
    if task_match:
        rest = raw[task_match.end():]
        top_m = re.search(r'^\S', rest, re.MULTILINE)
        if top_m:
            pos = task_match.end() + top_m.start()
            raw = raw[:pos] + indented + '\n' + raw[pos:]
        else:
            raw = raw.rstrip('\n') + '\n' + indented + '\n'

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
        f.write(raw)
    os.replace(tmp_path, task_file)
except Exception:
    try:
        os.unlink(tmp_path)
    except OSError:
        pass
    raise

print(f'[AC_OVERWRITE] Overwrote {len(cmd_acs)} ACs from cmd source ({parent_cmd})', file=sys.stderr)
OVERWRITE_AC_PY
        log "$(cat "$py_output")"
        rm -f "$py_output"
        return 0
    else
        log "WARN: _overwrite_ac_from_cmd failed: $(cat "$py_output")"
        rm -f "$py_output"
        return 1
    fi
}

inject_direct_training_template() {
    local task_file="$1"
    local cmd_id="$2"

    if [[ ! "$cmd_id" =~ ^cmd_training_ ]]; then
        return 0
    fi
    if [ ! -f "$task_file" ]; then
        log "inject_direct_training_template: task file not found: $task_file"
        return 1
    fi
    local task_type
    task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "" 2>/dev/null || true)
    # test_speed_task_generator owns a purpose/AC/quality/multi-round contract.
    # Its task_type is the shared `training` value, so identify it by the
    # speed_campaign marker instead of widening the exemption to all training.
    if grep -Eq '^  speed_campaign:[[:space:]]*' "$task_file"; then
        log "direct_mode: preserve test-speed campaign contract for ${cmd_id}"
        return 0
    fi
    # The fixed five-AC template belongs only to direct L4 implementation
    # tasks.  A task already typed `training` owns its lesson-scoring ACs;
    # overwriting those after mutation suppresses related_lessons injection.
    if [[ "$cmd_id" =~ ^cmd_training_L4_ ]] && [ -n "$task_type" ] && [ "$task_type" != "normal" ]; then
        log "direct_mode: preserve typed training ACs for ${cmd_id} (task_type=${task_type})"
        return 0
    fi
    # L1/L2 custom training keeps its authored ACs, while every L4 task has
    # one canonical five-AC mapping contract regardless of prior task_type.
    # Otherwise a late YAML-normalizing injector can leave a L4 task with a
    # list-shaped acceptance_criteria that passes content-only validation.
    if [[ ! "$cmd_id" =~ ^cmd_training_L4_ ]]; then
        case "$task_type" in
            speed_training|skill_training)
                log "direct_mode: skip non-L4 training template for ${cmd_id} (task_type=${task_type:-unset}, custom training ACs preserved)"
                return 0
                ;;
        esac
    fi

    TASK_FILE_ENV="$task_file" python3 - <<'TRAINING_TEMPLATE_PY'
import os
import re
import tempfile

task_file = os.environ["TASK_FILE_ENV"]

purpose = "L4修行: 指定ファイルの改善点3つを特定し、最高インパクト1件を実装し、[[リンク]]で知識ネットワークを育て、報告YAMLを一発PASS品質で完成させる"

ac_lines = [
    "  acceptance_criteria:",
    "    AC1:",
    "      description: \"指定ファイルの改善点を3つ特定し、根拠付きで報告する\"",
    "      binary_checks:",
    "        - \"改善点を3つ特定したか: yes/no\"",
    "        - \"各改善点に対象ファイル・根拠を添えたか: yes/no\"",
    "    AC2:",
    "      description: \"改善点のうち最高インパクト1件を実装し、対象Markdownへ関連ファイルへの直接[[ファイル名]]リンクを1件以上追加し、リンク先ファイルの特定行引用と必要な検証を報告する\"",
    "      binary_checks:",
    "        - \"最高インパクト1件を実装したか: yes/no\"",
    "        - \"対象Markdownへ関連ファイルへの直接[[ファイル名]]リンクを1件以上追加したか: yes/no\"",
    "        - \"追加した[[ファイル名]]リンクのリンク先ファイルから特定行を引用して報告したか: yes/no\"",
    "        - \"関連テストまたは明示的な検証を実行したか: yes/no\"",
    "    AC3:",
    "      description: \"lesson_candidate found=true、AC1/AC2のbinary_checks全記入、verdict整合を含む報告YAMLを完成させる\"",
    "      binary_checks:",
    "        - \"lesson_candidate found=trueでtitle/detail/projectを記入したか: yes/no\"",
    "        - \"AC1/AC2/AC3/AC4/AC5のbinary_checksを全てyes/noで記入したか: yes/no\"",
    "        - \"verdictがbinary_checksと矛盾していないか: yes/no\"",
    "    AC4:",
    "      description: \"related_lessonsが1件以上なら作業判断に参照してlessons_usefulへ理由を記入し、0件なら空であることと代替知見をlesson_candidateへ記録する\"",
    "      binary_checks:",
    "        - \"task.related_lessonsの件数を確認したか: yes/no\"",
    "        - \"1件以上なら参照ID/useful/reason、0件なら空であることと代替知見を記録したか: yes/no\"",
    "    AC5:",
    "      description: \"対象ファイルの現在のincoming backlink数とファイル間直接[[ファイル名]]リンク数baselineを計測し、変更後に孤立解消または直接リンク数増加を報告する\"",
    "      binary_checks:",
    "        - \"bash scripts/causal_backlink_counts.sh --zero --limit 20でincoming backlink baselineを確認したか: yes/no\"",
    "        - \"bash scripts/markdown_link_counts.sh --top 20でbaselineを確認したか: yes/no\"",
    "        - \"git diffで対象Markdownの孤立解消またはファイル間直接[[ファイル名]]リンク数増加を確認したか: yes/no\"",
]

with open(task_file, encoding="utf-8") as f:
    raw = f.read()

lines = raw.splitlines()
result = []
skip_indent = None
inserted_purpose = False
inserted_ac = False

for line in lines:
    stripped = line.lstrip(" ")
    indent = len(line) - len(stripped)
    if skip_indent is not None:
        # A legacy acceptance_criteria list has its "- id" items at the
        # same indentation as the mapping key.  They remain part of the
        # replaced block, not the next task field.
        if stripped == "" or indent > skip_indent or (indent == skip_indent and stripped.startswith("-")):
            continue
        skip_indent = None

    if indent == 2 and stripped.startswith("purpose:"):
        result.append("  purpose: " + repr(purpose))
        inserted_purpose = True
        if re.match(r"^purpose:\s*$", stripped):
            skip_indent = 2
        continue

    if indent == 2 and stripped.startswith("acceptance_criteria:"):
        result.extend(ac_lines)
        inserted_ac = True
        skip_indent = 2
        continue

    result.append(line)

insert_at = None
for idx, line in enumerate(result):
    if line.startswith("task:"):
        insert_at = idx + 1
        break

if insert_at is not None:
    additions = []
    if not inserted_purpose:
        additions.append("  purpose: " + repr(purpose))
    if not inserted_ac:
        additions.extend(ac_lines)
    if additions:
        result[insert_at:insert_at] = additions
else:
    additions = ["task:"]
    additions.append("  purpose: " + repr(purpose))
    additions.extend(ac_lines)
    result = additions + result

new_raw = "\n".join(result).rstrip("\n") + "\n"
fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix=".tmp")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(new_raw)
    os.replace(tmp_path, task_file)
except Exception:
    try:
        os.unlink(tmp_path)
    except OSError:
        pass
    raise
TRAINING_TEMPLATE_PY
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        log "FATAL: inject_direct_training_template failed for ${cmd_id}"
        return "$rc"
    fi

    TASK_FILE_ENV="$task_file" python3 - <<'TRAINING_TEMPLATE_VALIDATE_PY'
import os
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

def flatten_text(value):
    if isinstance(value, dict):
        return "\n".join(str(k) + "\n" + flatten_text(v) for k, v in value.items())
    if isinstance(value, list):
        return "\n".join(flatten_text(v) for v in value)
    return "" if value is None else str(value)

task_file = os.environ["TASK_FILE_ENV"]
with open(task_file, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}
task = data.get("task") if isinstance(data, dict) else {}
if not isinstance(task, dict):
    print("training_template_validation: task mapping missing", file=sys.stderr)
    sys.exit(1)

acs = task.get("acceptance_criteria")
required = {
    "AC1": "改善点を3つ特定",
    "AC2": "[[ファイル名]]リンク",
    "AC3": "lesson_candidate found=true",
    "AC4": "lessons_useful",
    "AC5": "causal_backlink_counts.sh --zero --limit 20",
}

if not isinstance(acs, dict):
    print("training_template_validation: acceptance_criteria must be a mapping", file=sys.stderr)
    sys.exit(1)

if set(acs) != set(required):
    print(
        "training_template_validation: acceptance_criteria keys must be AC1..AC5 "
        f"(got={sorted(str(key) for key in acs)})",
        file=sys.stderr,
    )
    sys.exit(1)

found = {str(key): value for key, value in acs.items()}

missing = []
for ac_id, needle in required.items():
    block = found.get(ac_id)
    text = flatten_text(block)
    if needle not in text:
        missing.append(f"{ac_id}:{needle}")

if missing:
    print("training_template_validation: missing " + ", ".join(missing), file=sys.stderr)
    sys.exit(1)
TRAINING_TEMPLATE_VALIDATE_PY
    rc=$?
    if [ "$rc" -ne 0 ]; then
        log "FATAL: training L4 template validation failed for ${cmd_id}"
        return "$rc"
    fi

    log "direct_mode: training L4 template injected for ${cmd_id}"
}

deploy_task_is_nullish_value() {
    local value="${1:-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    case "${value,,}" in
        ""|"null"|"none"|"~") return 0 ;;
        *) return 1 ;;
    esac
}

repair_training_parent_cmd_from_cmd_id() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0

    local parent_cmd cmd_id task_id task_type status
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" parent_cmd cmd_id task_id task_type status 2>/dev/null)" || true

    deploy_task_is_nullish_value "$parent_cmd" || return 0
    [[ "${cmd_id:-}" =~ ^cmd_training_ ]] || return 0

    local suffix="normal"
    if [ "${task_type:-}" = "exact" ]; then
        suffix="exact"
    fi

    yaml_field_set "$task_file" "task" "parent_cmd" "$cmd_id" \
        || { log "FATAL: failed to repair training parent_cmd from cmd_id=${cmd_id}"; return 1; }

    if deploy_task_is_nullish_value "$task_id" || [[ "$task_id" != "${cmd_id}_"* ]]; then
        yaml_field_set "$task_file" "task" "task_id" "${cmd_id}_${suffix}" \
            || { log "FATAL: failed to repair training task_id from cmd_id=${cmd_id}"; return 1; }
    fi

    if deploy_task_is_nullish_value "$status" || [ "$status" = "idle" ]; then
        yaml_field_set "$task_file" "task" "status" "assigned" \
            || { log "FATAL: failed to repair training status for cmd_id=${cmd_id}"; return 1; }
    fi

    log "training_parent_cmd_repair: parent_cmd=${cmd_id} task_id=${cmd_id}_${suffix}"
}

inject_training_target_path_from_alias_quality() {
    local task_file="$1"
    local cmd_id="$2"

    if [[ ! "$cmd_id" =~ ^cmd_training_ ]]; then
        return 0
    fi
    if [ ! -f "$task_file" ]; then
        log "inject_training_target_path_from_alias_quality: task file not found: $task_file"
        return 1
    fi

    local current_target
    current_target=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "target_path" "" 2>/dev/null || true)
    if [ -n "$current_target" ]; then
        return 0
    fi

    local selected_target=""
    # The library is sourced once by the Bats scaffold and reused across
    # per-test TEST_PROJECT roots. Resolve all selector inputs from the task
    # fixture, not the cached source root captured at source time.
    local task_root="${task_file%/queue/tasks/*}"
    [ "$task_root" != "$task_file" ] || task_root="$SCRIPT_DIR"
    local backlink_selector="$task_root/scripts/causal_backlink_counts.sh"
    if [ -f "$backlink_selector" ]; then
        selected_target=$(
            CAUSAL_BACKLINK_COUNTS_ROOT="$task_root" bash "$backlink_selector" --zero --limit 1 2>/dev/null \
                | awk -F '\t' 'NF >= 2 { print $2; exit }' \
            || true
        )
    else
        log "WARN: causal_backlink_counts selector missing; falling back to markdown_link_counts"
    fi

    local markdown_selector="$task_root/scripts/markdown_link_counts.sh"
    if [ -z "$selected_target" ] && [ -f "$markdown_selector" ]; then
        selected_target=$(bash "$markdown_selector" --select-file 2>/dev/null | head -1 || true)
    elif [ -z "$selected_target" ]; then
        log "WARN: markdown_link_counts selector missing; falling back to semantic_alias_quality"
    fi

    if [ -z "$selected_target" ]; then
        local selector="$task_root/scripts/semantic_alias_quality.sh"
        if [ ! -f "$selector" ]; then
            log "WARN: semantic_alias_quality selector missing; training target_path left empty"
            return 0
        fi
        selected_target=$(bash "$selector" --select-file 2>/dev/null | head -1 || true)
    fi
    if [ -z "$selected_target" ]; then
        log "WARN: training target selector produced no target; training target_path left empty"
        return 0
    fi

    # target_path is a typed list; preserve the one selected path as a
    # one-element YAML sequence rather than passing a scalar to the setter.
    yaml_field_set "$task_file" "task" "target_path" "[\"$selected_target\"]" \
        || { log "FATAL: failed to set training target_path=${selected_target}"; return 1; }
    log "training_target_path: selected target_path=${selected_target}"
}

inject_ac_version() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        log "inject_ac_version: task file not found: $task_file"
        return 0
    fi

    local ac_version
    ac_version=$(_compute_ac_hash "$task_file")

    local prev
    prev=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "ac_version" "")

    # R2: field_get 6-7回→field_get_multi 1回(CoDD batch_read_flow準拠)
    local curr_task_id curr_worker_id prev_ac_task_id prev_ac_worker_id
    local task_id="" _ac_task_id="" worker_id="" _ac_worker_id=""
    eval "$(FIELD_GET_NO_LOG=1 field_get_multi "$task_file" task_id _ac_task_id worker_id _ac_worker_id)"
    # AC3修正: task_id/ac_task_id両方空=karo_direct手動YAML等でtask_idが未設定のケース。
    # parent_cmd+task_typeからtask_idを導出してYAMLに書込み、二重配備防止を確実に発火させる(cmd_3102)
    if [ -z "$task_id" ] && [ -z "$_ac_task_id" ]; then
        local _pcmd="" _ttype=""
        _pcmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "")
        _ttype=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "normal")
        if [ -n "$_pcmd" ]; then
            task_id="${_pcmd}_${_ttype:-normal}"
            yaml_field_set "$task_file" "task" "task_id" "$task_id" 2>/dev/null || true
            log "[AC_VERSION] derived task_id from parent_cmd: $task_id (AC3: 二重配備防止発火保証)"
        fi
    fi
    # task_idが空なら_ac_task_idをfallback(家老が_ac_task_idを直接設定するケース)
    if [ -z "$task_id" ]; then
        curr_task_id="$_ac_task_id"
    else
        curr_task_id="$task_id"
    fi
    if [ -z "$worker_id" ]; then
        curr_worker_id="$_ac_worker_id"
    else
        curr_worker_id="$worker_id"
    fi
    prev_ac_task_id="$_ac_task_id"
    prev_ac_worker_id="$_ac_worker_id"

    if [ "$curr_task_id" != "$prev_ac_task_id" ] || [ "$curr_worker_id" != "${prev_ac_worker_id:-}" ]; then
        if [ "${DIRECT_MODE:-false}" = true ] && [ -n "${YAML_FILE:-}" ]; then
            log "[AC_VERSION] direct --yaml deploy detected; keeping source YAML ACs without cmd-source overwrite"
        else
            log "[AC_VERSION] deploy detected (task_id: ${prev_ac_task_id:-empty}→${curr_task_id}, worker: ${prev_ac_worker_id:-empty}→${curr_worker_id}). Overwriting ACs from cmd source."
            if _overwrite_ac_from_cmd "$task_file"; then
                ac_version=$(_compute_ac_hash "$task_file")
                log "[AC_VERSION] recomputed after AC overwrite: $ac_version"
            else
                log "[AC_VERSION] WARN: AC overwrite failed, keeping existing ACs"
            fi
        fi
    fi

    # R2: yaml_field_set 3回→batch 1回(CoDD batch_write_flow準拠)
    yaml_field_set_batch "$task_file" "task" \
        "ac_version=$ac_version" \
        "_ac_task_id=$curr_task_id" \
        "_ac_worker_id=$curr_worker_id" \
        || { log "FATAL: yaml_field_set_batch failed for inject_ac_version"; return 1; }

    if [ "$prev" = "$ac_version" ]; then
        log "[AC_VERSION] unchanged: $ac_version"
    else
        log "[AC_VERSION] set: $prev -> $ac_version"
    fi
}

# Bind a numbered parent command's immutable AC contract at deployment time.
# assigned_acs is authoritative for split deployments; otherwise the task ACs
# must be a subset of the parent AC namespace.  Direct hotfixes are exempt.
inject_parent_contract() {
    local task_file="$1" report_file="${2:-}" worker_id="${3:-}"
    local contract coverage fingerprint cmd_bound tool_root
    tool_root="$SCRIPT_DIR"
    contract=$(python3 - "$task_file" "$SCRIPT_DIR" <<'PARENT_CONTRACT_PY'
import hashlib, json, os, sys, yaml
task_path, root = sys.argv[1:]
task_doc = yaml.safe_load(open(task_path, encoding="utf-8")) or {}
task = task_doc.get("task") or {}
cmd = str(task.get("parent_cmd") or "")
if not (cmd.startswith("cmd_") and cmd[4:].isdigit()): raise SystemExit(0)
def command_from(path):
    if not os.path.isfile(path): return None
    source = yaml.safe_load(open(path, encoding="utf-8")) or {}
    commands = source.get("commands", source)
    return commands.get(cmd) if isinstance(commands, dict) else next((x for x in commands if isinstance(x,dict) and x.get("id")==cmd), None)

# Keep the producer's resolution order identical to parent_cmd_contract.py:
# active queue first, then the authoritative reopened state.  Archive is not
# deployable until cmd_reopen has explicitly restored it.
parent = command_from(os.path.join(root, "queue", "shogun_to_karo.yaml"))
if not isinstance(parent, dict):
    parent = command_from(os.path.join(root, "queue", "reopened_cmds", cmd + ".yaml"))
if not isinstance(parent, dict): raise SystemExit("BLOCK: parent SSOT missing during deployment")
def ids(items):
    if isinstance(items, dict):
        return [str(key) for key in items]
    return [str(x.get("id") or f"AC{i}") for i,x in enumerate(items or [],1) if isinstance(x,dict)]
parent_ids = ids(parent.get("acceptance_criteria")); purpose = str(parent.get("purpose") or parent.get("title") or "").strip()
assigned = task.get("assigned_acs")
coverage = [str(x) for x in assigned] if isinstance(assigned,list) and assigned else ids(task.get("acceptance_criteria"))
if not purpose or not parent_ids or not coverage or not set(coverage) <= set(parent_ids): raise SystemExit("BLOCK: invalid parent AC mapping during deployment")
raw=json.dumps({"cmd":cmd,"purpose":purpose,"acs":sorted(parent_ids)},ensure_ascii=False,sort_keys=True)
fp=hashlib.sha256(raw.encode()).hexdigest()[:16]
print("["+", ".join(coverage)+"]\t"+fp+"\t"+cmd)
PARENT_CONTRACT_PY
    ) || return 1
    [ -z "$contract" ] && return 0
    IFS=$'\t' read -r coverage fingerprint cmd_bound <<< "$contract"
    printf '%s\n' "$coverage" | bash "$tool_root/scripts/report_field_set.sh" "$task_file" task.parent_ac_coverage - || return 1
    bash "$tool_root/scripts/report_field_set.sh" "$task_file" task.parent_contract_fingerprint "$fingerprint" || return 1
    if [ -n "$report_file" ] && [ -f "$report_file" ]; then
        printf '%s\n' "$coverage" | bash "$tool_root/scripts/report_field_set.sh" "$report_file" parent_ac_coverage - || return 1
        bash "$tool_root/scripts/report_field_set.sh" "$report_file" parent_contract_fingerprint "$fingerprint" || return 1
    fi
    # Durable per-(worker, cmd) evidence: a later redeployment overwrites
    # task_file with an unrelated parent_cmd, but this archive stays keyed
    # to the cmd bound *right now* and survives that overwrite (root cause
    # of parent_ac_uncovered false-BLOCK after worker reassignment).
    if [ -n "$coverage" ] && [ -n "$fingerprint" ] && [[ "$cmd_bound" =~ ^cmd_[0-9]+$ ]]; then
        local archive_worker="${worker_id:-$(basename "$task_file" .yaml)}"
        local archive_dir="$SCRIPT_DIR/queue/archive/parent_contracts"
        mkdir -p "$archive_dir"
        local archive_tmp
        archive_tmp=$(mktemp "$archive_dir/.tmp.XXXXXX")
        {
            printf 'worker_id: %s\n' "$archive_worker"
            printf 'parent_cmd: %s\n' "$cmd_bound"
            printf 'parent_ac_coverage: %s\n' "$coverage"
            printf 'parent_contract_fingerprint: %s\n' "$fingerprint"
            printf 'bound_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        } > "$archive_tmp"
        mv -f "$archive_tmp" "$archive_dir/${archive_worker}__${cmd_bound}.yaml"
    fi
    log "[PARENT_CONTRACT] coverage=${coverage} fingerprint=${fingerprint}"
}

# ─── verify_ac_consistency: task YAML vs cmdソースのAC件数・ID突合（cmd_1619） ───
# inject_ac_version後に実行。不一致時はWARNING。BLOCKではない（配備続行）。
verify_ac_consistency() {
    local task_file="$1"
    if [ ! -f "$task_file" ]; then
        return 0
    fi

    local parent_cmd
    parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "")
    [ -z "$parent_cmd" ] && return 0

    local py_output
    py_output=$(mktemp) || {
        log "verify_ac_consistency: mktemp failed"
        return 1
    }
    if python3 - "$task_file" "$parent_cmd" "$SCRIPT_DIR" <<'VERIFY_AC_PY' > "$py_output" 2>&1; then
import glob
import os
import sys

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

task_file = sys.argv[1]
parent_cmd = sys.argv[2]
script_dir = sys.argv[3]

def extract_ac_id(entry):
    """AC entryからIDを抽出。'AC1: desc' → 'AC1', {id: 'AC1'} → 'AC1'"""
    if isinstance(entry, str):
        colon_idx = entry.find(':')
        if colon_idx > 0:
            return entry[:colon_idx].strip()
        return entry.strip()
    if isinstance(entry, dict):
        if 'id' in entry:
            return str(entry['id'])
        for k in entry:
            return str(k)
    return str(entry)

def _extract_acs_from_cmd(cmd):
    acs = cmd.get('acceptance_criteria')
    if acs:
        if isinstance(acs, (list, dict)):
            return acs
    ac_nested = cmd.get('ac')
    if ac_nested and isinstance(ac_nested, dict):
        return list(ac_nested.keys())
    return None

def find_cmd_acs(pcmd, sdir):
    stk_path = os.path.join(sdir, 'queue', 'shogun_to_karo.yaml')
    if os.path.exists(stk_path):
        try:
            with open(stk_path, encoding='utf-8') as f:
                stk = yaml.load(f, Loader=yaml.SafeLoader) or {}
            cmds = stk.get('commands', {})
            if isinstance(cmds, dict):
                cmd = cmds.get(pcmd, {})
                if isinstance(cmd, dict):
                    acs = _extract_acs_from_cmd(cmd)
                    if acs:
                        return acs
        except Exception:
            pass
    archive_dir = os.path.join(sdir, 'queue', 'archive', 'cmds')
    if os.path.isdir(archive_dir):
        for cpath in sorted(glob.glob(os.path.join(archive_dir, f'{pcmd}_*.yaml')), reverse=True):
            try:
                with open(cpath, encoding='utf-8') as f:
                    adata = yaml.load(f, Loader=yaml.SafeLoader) or {}
                cmds = adata.get('commands', {})
                if isinstance(cmds, dict):
                    cmd = cmds.get(pcmd, {})
                    if isinstance(cmd, dict):
                        acs = _extract_acs_from_cmd(cmd)
                        if acs:
                            return acs
            except Exception:
                continue
    return None

def to_list(acs):
    if isinstance(acs, dict):
        return [{'id': k, 'value': v} for k, v in acs.items()]
    if isinstance(acs, list):
        return acs
    return []

# Load task YAML
with open(task_file, encoding='utf-8') as f:
    task_data = yaml.load(f, Loader=yaml.SafeLoader) or {}
task = task_data.get('task', task_data)
task_acs = to_list(task.get('acceptance_criteria', []))

# Load cmd source ACs
cmd_acs_raw = find_cmd_acs(parent_cmd, script_dir)
if cmd_acs_raw is None:
    print(f'[AC_VERIFY] SKIP: No cmd source found for {parent_cmd}', file=sys.stderr)
    sys.exit(0)
cmd_acs = to_list(cmd_acs_raw)

task_count = len(task_acs)
cmd_count = len(cmd_acs)

# AC1: Count comparison
if task_count != cmd_count:
    print(f'[AC_VERIFY] WARNING: AC count mismatch — task={task_count} cmd_source={cmd_count} (parent_cmd={parent_cmd})', file=sys.stderr)

# AC2: ID comparison
task_ids = [extract_ac_id(a) for a in task_acs]
cmd_ids = [extract_ac_id(a) for a in cmd_acs]

if task_count == cmd_count:
    mismatched = []
    for i, (tid, cid) in enumerate(zip(task_ids, cmd_ids)):
        if tid != cid:
            mismatched.append(f'{i}: task={tid} cmd={cid}')
    if mismatched:
        print(f'[AC_VERIFY] WARNING: AC id mismatch — {"; ".join(mismatched)} (parent_cmd={parent_cmd})', file=sys.stderr)
    elif task_count > 0:
        print(f'[AC_VERIFY] OK: AC count={task_count} ids match (parent_cmd={parent_cmd})', file=sys.stderr)
else:
    print(f'[AC_VERIFY] WARNING: AC ids — task={task_ids} cmd_source={cmd_ids} (parent_cmd={parent_cmd})', file=sys.stderr)
VERIFY_AC_PY
        log "$(cat "$py_output")"
        rm -f "$py_output"
        return 0
    else
        log "verify_ac_consistency: python3 failed: $(cat "$py_output")"
        rm -f "$py_output"
        return 1
    fi
}

# ─── 報告YAML雛形生成（cmd_138: lesson_candidate欠落防止） ───
is_before_after_required_task() {
    local task_file="$1"
    local parent_cmd="$2"
    local task_title task_type

    # cmd_1983: 第3・第4引数が渡された場合はpre-read値を使用（field_get subprocess削減）
    if [[ ${3+x} ]] && [[ ${4+x} ]]; then
        task_title="$3"
        task_type="$4"
    else
        task_title=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "title" "" 2>/dev/null)
        task_type=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_type" "" 2>/dev/null)
    fi

    case "$parent_cmd" in
        cmd_karo_gp*) return 0 ;;
    esac

    case "${task_type,,}" in
        gp|improvement) return 0 ;;
    esac

    case "$task_title" in
        GP*|強化*|改善*|*"GP/"*|*" GP "*|*"改善"*|*"強化"*) return 0 ;;
    esac

    return 1
}

_apply_binary_check_waivers() {
    local task_file="$1"
    local bc_full="$2"

    if [[ "${DEPLOY_TASK_SKIP_BINARY_CHECK_WAIVERS:-0}" == "1" ]]; then
        printf '%s\n' "$bc_full"
        return 0
    fi
    if ! grep -qE '^[[:space:]]+(waive_ac|scope_mode|task_type|type|target_path):' "$task_file" 2>/dev/null; then
        printf '%s\n' "$bc_full"
        return 0
    fi
    if ! grep -qE 'waive_ac:|RESEARCH|research|docs/research|outputs' "$task_file" 2>/dev/null; then
        printf '%s\n' "$bc_full"
        return 0
    fi

    PYTHONPATH="$SCRIPT_DIR" TASK_FILE_ENV="$task_file" BC_FULL_ENV="$bc_full" python3 - <<'PY_BC_WAIVE'
import os
import sys

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)
from scripts.lib.yaml_atomic import yaml_text


def to_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return [str(v).strip() for v in value if str(v).strip()]
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return []
        if text.startswith('[') and text.endswith(']'):
            text = text[1:-1]
        return [part.strip().strip('"\'') for part in text.replace(',', ' ').split() if part.strip()]
    return [str(value).strip()] if str(value).strip() else []


def is_research_target(path):
    raw = str(path or '').strip().strip('"\'')
    if not raw:
        return False
    normalized = raw.replace('\\', '/')
    stripped = normalized
    while stripped.startswith('./'):
        stripped = stripped[2:]
    prefixes = ('outputs', 'docs/research')
    if any(stripped == prefix or stripped.startswith(prefix + '/') for prefix in prefixes):
        return True
    if '/outputs/' in normalized or normalized.endswith('/outputs'):
        return True
    if '/docs/research/' in normalized or normalized.endswith('/docs/research'):
        return True
    return False


task_path = os.environ['TASK_FILE_ENV']
bc_full = os.environ['BC_FULL_ENV']

try:
    with open(task_path, encoding='utf-8') as f:
        task_raw = yaml.safe_load(f) or {}
except Exception:
    print(bc_full.rstrip())
    raise SystemExit(0)

task = task_raw.get('task', task_raw)

try:
    parsed = yaml.safe_load(bc_full) or {}
except Exception:
    print(bc_full.rstrip())
    raise SystemExit(0)

bc = parsed.get('binary_checks')
if not isinstance(bc, dict):
    print(bc_full.rstrip())
    raise SystemExit(0)

waive_ac = set(to_list(task.get('waive_ac')))

scope_mode = str(task.get('scope_mode') or task.get('task_type') or task.get('type') or '')
targets = to_list(task.get('target_path'))
is_research = ('RESEARCH' in scope_mode.upper()) or (bool(targets) and all(is_research_target(p) for p in targets))

for ac_id in waive_ac:
    items = bc.get(ac_id)
    if not isinstance(items, list):
        continue
    for item in items:
        if not isinstance(item, dict):
            continue
        item['result'] = 'no'
        item['waive_reason'] = 'waive_ac指定'

if is_research:
    items = bc.get('commit')
    if isinstance(items, list):
        for item in items:
            if not isinstance(item, dict):
                continue
            item['result'] = 'no'
            if not str(item.get('waive_reason') or '').strip():
                item['waive_reason'] = '研究cmd: commit不要'

print(yaml_text({'binary_checks': bc}, sort_keys=False).rstrip())
PY_BC_WAIVE
}

deploy_task_needs_causal_verification() {
    local task_file="$1"
    [ -f "$task_file" ] || return 1

    local task_text
    task_text="$(awk '
        /^  (purpose|title|command|target_path|scope|context|semantic_concepts|task_type|type|scope_mode):/ { print; in_block=1; next }
        in_block && /^  [A-Za-z_][A-Za-z0-9_]*:/ { in_block=0 }
        in_block && /^    / { print }
    ' "$task_file" 2>/dev/null)"
    printf '%s\n' "$task_text" | grep -qiE 'hook|gate|daemon|semantic|search|memory[ _-]?db|記憶DB|deploy_task|配備フロー|report[_ -]?format|cmd_save|inbox_watcher|ninja_monitor'
}

# enforcement層の変更だけに、実運用の変形検査を報告契約として要求する。
# docs/教訓/fixture/索引のみの仕事へ広げると、実装のない報告に無意味な検査を
# 強いるため、明示的なコード変更と enforcement 語の両方を必須にする。
is_enforcement_variation_contract_task() {
    local task_file="$1"
    [ -f "$task_file" ] || return 1

    TASK_FILE_ENV="$task_file" python3 - <<'PY_ENFORCEMENT_VARIATION'
import os
import re
from pathlib import Path

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (8x faster parse, same safe schema)

try:
    raw = yaml.safe_load(Path(os.environ['TASK_FILE_ENV']).read_text(encoding='utf-8')) or {}
except Exception:
    raise SystemExit(1)

task = raw.get('task', raw) if isinstance(raw, dict) else {}

# Runtime variation checks are an infra enforcement contract.  Product tasks
# may legitimately mention gate/hook behavior in acceptance criteria, but that
# text must not reclassify them as platform enforcement implementations.
project = str(task.get('project', '')).strip().lower()
if project != 'infra':
    raise SystemExit(1)

# Reconnaissance is structurally no-code.  Injected lessons and context may
# contain words such as scripts/ and gate; those must never reclassify a recon
# task as an enforcement implementation that requires runtime variation tests.
task_type = str(
    task.get('task_type', task.get('type', task.get('scope_mode', '')))
).strip().lower()
if task_type in {'scout', 'recon', 'recon2'}:
    raise SystemExit(1)

def flatten(value):
    if isinstance(value, dict):
        return ' '.join(flatten(item) for item in value.values())
    if isinstance(value, (list, tuple, set)):
        return ' '.join(flatten(item) for item in value)
    return str(value or '')

text = flatten({
    key: task.get(key)
    for key in (
        'title', 'purpose', 'command', 'description', 'target_path',
        'files_to_modify', 'files_modified', 'acceptance_criteria',
    )
}).lower()

enforcement = bool(re.search(
    r'(?:enforcement|gate|hook|detector|guard|watcher|state[ _-]?machine|ゲート|フック|検知器|ガード|監視)',
    text,
))
code_change = bool(re.search(
    r'(?:scripts/|\.sh\b|\.py\b|コード変更|コード修正|実装|修正|implement|fix\b)',
    text,
))
non_code_only = bool(re.search(
    r'(?:docs?[ _-]?only|documentation[ _-]?only|教訓のみ|fixtureのみ|索引のみ|docsのみ)',
    text,
))

raise SystemExit(0 if enforcement and code_change and not non_code_only else 1)
PY_ENFORCEMENT_VARIATION
}

inject_causal_verification_template() {
    local task_file="$1"
    [ -f "$task_file" ] || return 0
    deploy_task_needs_causal_verification "$task_file" || return 0

    local inject_block
    inject_block='  causal_verification:
    cause_checked: ""  # 変更前にgit log/blame・教訓・設計書・semantic/causalを確認し3行以上で記録
    design_intent_checked: ""  # 導入理由/守るべき既存防御/今回壊れている因果を記録
    evidence: ""  # bounded確認: scope限定、timeout、既存cache利用。全走査を避ける
    origin: ""  # [[発端]] -> [[原因]] -> [[結果]]'

    local tmp_file insert_file
    tmp_file=$(mktemp "${task_file}.XXXXXX")
    awk '
        /^  causal_verification:/ { skip=1; next }
        skip && /^    / { next }
        skip && /^  [A-Za-z_][A-Za-z0-9_]*:/ { skip=0 }
        skip && /^[^ ]/ { skip=0 }
        !skip { print }
    ' "$task_file" > "$tmp_file"

    insert_file=$(mktemp)
    printf '%s\n' "$inject_block" > "$insert_file"
    if grep -q "^  description:" "$tmp_file"; then
        awk -v insert_file="$insert_file" '
            /^  description:/ && !inserted {
                while ((getline line < insert_file) > 0) print line
                close(insert_file)
                inserted=1
            }
            { print }
        ' "$tmp_file" > "${tmp_file}.inserted"
        mv "${tmp_file}.inserted" "$tmp_file"
    else
        printf '%s\n' "$inject_block" >> "$tmp_file"
    fi
    rm -f "$insert_file"
    _yaml_field_set_publish_atomic "$tmp_file" "$task_file" || return 1
    log "inject_causal_verification_template: causal_verification injected"
}

# Report feedback must use the task's explicit evaluation set when one exists.
# Falling back to auto-injected related_lessons for a lesson-reflux task polluted
# lessons_useful with unrelated context lessons (assigned=10 but report=14), so
# the binary set check could say extra=0 while the report artifact contradicted it.
report_lesson_ids_for_task() {
    local task_file="$1"
    awk '
        function clean(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            gsub(/^[\047\"]|[\047\"]$/, "", value)
            return value
        }
        /^  assigned_lesson_ids:/ {
            in_assigned=1
            in_related=0
            value=$0
            sub(/^  assigned_lesson_ids:[[:space:]]*/, "", value)
            if (value ~ /^\[/) {
                gsub(/^\[|\]$/, "", value)
                count=split(value, inline_ids, /[[:space:]]*,[[:space:]]*/)
                for (i=1; i<=count; i++) {
                    item=clean(inline_ids[i])
                    if (item != "") assigned[++assigned_count]=item
                }
                in_assigned=0
            }
            next
        }
        in_assigned && /^  [A-Za-z_][A-Za-z0-9_]*:/ { in_assigned=0 }
        in_assigned && /^[[:space:]]*-[[:space:]]*/ {
            item=$0
            sub(/^[[:space:]]*-[[:space:]]*/, "", item)
            item=clean(item)
            if (item != "") assigned[++assigned_count]=item
            next
        }
        /^  related_lessons:/ { in_related=1; in_assigned=0; next }
        in_related && /^  [A-Za-z_][A-Za-z0-9_]*:/ { in_related=0 }
        in_related && /^[[:space:]]+(- )?id:/ {
            item=$0
            sub(/.*id:[[:space:]]*/, "", item)
            item=clean(item)
            if (item != "") related[++related_count]=item
        }
        END {
            if (assigned_count > 0) {
                for (i=1; i<=assigned_count; i++) print assigned[i]
            } else {
                for (i=1; i<=related_count; i++) print related[i]
            }
        }
    ' "$task_file" 2>/dev/null
}
