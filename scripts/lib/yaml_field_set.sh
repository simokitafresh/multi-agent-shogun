#!/usr/bin/env bash
# semantic-links: [[YAML安全書込み]]
# yaml_field_set.sh - Safe YAML field update helper with post-write verification.
#
# Usage:
#   bash scripts/lib/yaml_field_set.sh <yaml_file> <block_id> <field> <new_value>
#   bash scripts/lib/yaml_field_set.sh <yaml_file> <block_id> <a.b.c> <new_value>   # nested path
#   bash scripts/lib/yaml_field_set.sh --append <yaml_file> <block_id> <field> <element>  # list append
#   source scripts/lib/yaml_field_set.sh && yaml_field_set <yaml_file> <block_id> <field> <new_value>
#
# Behavior:
# - Locates a target block by either:
#   1) list item id: "- id: <block_id>"
#   2) mapping key:  "<block_id>:"
# - Replaces field value inside the block if present (keeps indent level).
# - Adds field at block end if missing.
# - Uses flock -w 10 for exclusive writes.
# - Verifies written value by re-reading; exits 1 with FATAL on mismatch.
# Cross-file report revision lifecycles are intentionally not composed here;
# review_approval.sh owns that transaction under the worker deploy lock.

# Inline lock_path helper to avoid sourcing another file on the hot path.
# ロジックはscripts/lib/lock_path.sh(正本)と完全一致させること — 独自の派生ロジックは
# 同一ファイルに対し正本経由の書き手と異なるロックパスを生成し排他が破綻する
# (cmd_3874: queue/insights.yaml全損の真因。queue/tasks/*.yamlでも同型不一致を確認済み)
lock_path() {
    local file_path="$1"
    case "$file_path" in
        /mnt/c/*|/mnt/d/*)
            # 純bash DJB2ハッシュ — md5sum subprocessを排除(scripts/lib/lock_path.shと同一導出)
            local hash=5381 i c
            for (( i=0; i<${#file_path}; i++ )); do
                printf -v c '%d' "'${file_path:$i:1}"
                (( hash = hash * 33 + c ))
            done
            printf '/tmp/shogun_lock_%016x.lock' "$hash"
            ;;
        *)
            printf '%s.lock' "$file_path"
            ;;
    esac
}

_yaml_field_set_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

_yaml_field_set_unquote() {
    local s="$1"
    if [ "${#s}" -ge 2 ]; then
        case "$s" in
            \"*\") s="${s#\"}"; s="${s%\"}"; s="${s//\\\"/\"}" ;;
            \'*\') s="${s#\'}"; s="${s%\'}" ;;
        esac
    fi
    printf '%s' "$s"
}

# WSL2最適化: subshell 3回(trim→unquote→trim)をpure bash変数展開に置換(55x高速化)。
# 結果は _YFS_NORM に格納。呼び出し元はサブシェルキャプチャ不要。
_yaml_field_set_normalize_v() {
    local s="$1"
    # trim leading whitespace
    s="${s#"${s%%[![:space:]]*}"}"
    # trim trailing whitespace
    s="${s%"${s##*[![:space:]]}"}"
    # unquote
    if [ "${#s}" -ge 2 ]; then
        case "$s" in
            \"*\") s="${s#\"}"; s="${s%\"}"; s="${s//\\\"/\"}" ;;
            \'*\') s="${s#\'}"; s="${s%\'}" ;;
        esac
    fi
    # trim again after unquote
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    _YFS_NORM="$s"
}

_yaml_field_set_normalize() {
    _yaml_field_set_normalize_v "$1"
    printf '%s' "$_YFS_NORM"
}

# cmd_4162 (忍者利他報告blt_20260724_162804): yaml_field_set/yaml_field_set_batchの
# field引数はawk側で常に単一の完全一致キーとして扱われる。呼び出し側が
# "planned_paths[1]"のようなネストlist添字表記を渡しても、そのフィールド名の
# ブロックは存在しないため root-level fallback が働き、添字表記の文字列そのものが
# 新規のリテラルキーとして黙って書き込まれる(list要素の更新にならない)。
# yaml_field_setのawkエンジンはYAML構造を解釈しない行ベース置換であり、
# list要素単位の更新は安全に実装できない。よって解釈対応ではなく、
# 添字表記を検出した時点でfail-closedし、呼び出し側にリスト全体を書き直すよう促す。
_yaml_field_set_reject_bracket_field() {
    local field="$1"
    case "$field" in
        *'['*']'*)
            echo "FATAL: yaml_field_set: nested list index notation is not supported in field path: '$field'" >&2
            echo "  yaml_field_set only replaces a whole field's scalar value; per-element list writes like '${field}' would silently create a literal key instead of updating the list element." >&2
            echo "  Hint: rewrite the entire list field with its full new value instead (e.g. yaml_field_set <file> <block_id> ${field%%\[*} '[...]')." >&2
            return 1
            ;;
    esac
    return 0
}

# cmd_karo_hotfix_queue_yaml_atomicity_202607110113: 公開前にYAML構文を検証する。
# awk生成物が不正(例: 値に生の改行が混入し裸テキストが行頭に漏れる)でも、
# 検証をパスしない限り旧ファイルへは一切書き戻さない(fail-closed)。
_yaml_field_set_validate_parseable() {
    local candidate_file="$1"
    python3 -c '
import sys
import yaml
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        yaml.safe_load(fh)
except Exception as exc:
    print(f"invalid_yaml: {exc}", file=sys.stderr)
    sys.exit(1)
' "$candidate_file"
}

# cmd_karo_hotfix_yaml_field_set_multiline_verify_202607122228: post-write検証を
# awk単一物理行の生テキスト比較(_yaml_field_get_in_block等)からyaml.safe_load後の
# scalar比較へ統一する。複数行/引用符混在値は書込み時にYAML上1物理行のquoted scalarへ
# 正しくエスケープされるが、旧検証はその物理行を跨いだ継続テキストを誤抽出し
# (先頭引用符だけ残る等)偽FAILを起こしていた(LK-A13.detail実測)。
# expectedは環境変数経由で渡す(改行/引用符を含んでもshell引数展開の再解釈を受けない)。
# actualがbool/int/float/NoneにYAML実装解決された場合はexpected(常にbash文字列)を
# 同じ型規則で比較する(YAML1.1のtrue/false/null表記ゆれの偽FAILを防ぐ)。
_yaml_field_set_verify_parsed() {
    local yaml_file="$1"
    local block_id="$2"
    local field="$3"
    local expected="$4"
    local use_root="$5"

    YFS_EXPECTED="$expected" python3 -c '
import os
import sys

import yaml

yaml_file, block_id, field, use_root_flag = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
use_root = use_root_flag == "1"
expected = os.environ.get("YFS_EXPECTED", "")

try:
    with open(yaml_file, encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
except Exception as exc:
    sys.stderr.write(f"parse_error: {exc}\n")
    sys.exit(1)


def find_blocks(node, target_id, out):
    if isinstance(node, dict):
        val = node.get(target_id)
        if isinstance(val, dict):
            out.append(val)
        for v in node.values():
            find_blocks(v, target_id, out)
    elif isinstance(node, list):
        for item in node:
            if isinstance(item, dict):
                for key in ("id", "cmd_id", "check"):
                    if key in item and str(item[key]) == target_id:
                        out.append(item)
                        break
            find_blocks(item, target_id, out)


if use_root:
    if not isinstance(data, dict) or field not in data:
        sys.stderr.write("field_not_found\n")
        sys.exit(2)
    actual = data[field]
else:
    blocks = []
    find_blocks(data, block_id, blocks)
    if not blocks:
        sys.stderr.write("block_not_found\n")
        sys.exit(2)
    matches = [b[field] for b in blocks if field in b]
    if not matches:
        sys.stderr.write("field_not_found\n")
        sys.exit(3)
    actual = matches[0]

YAML_TRUE = {"y", "Y", "yes", "Yes", "YES", "true", "True", "TRUE", "on", "On", "ON"}
YAML_FALSE = {"n", "N", "no", "No", "NO", "false", "False", "FALSE", "off", "Off", "OFF"}
YAML_NULL = {"null", "Null", "NULL", "~", ""}

if isinstance(actual, bool):
    matched = (expected in YAML_TRUE) if actual else (expected in YAML_FALSE)
elif actual is None:
    matched = expected in YAML_NULL
elif isinstance(actual, int):
    try:
        matched = int(expected, 0) == actual
    except (ValueError, TypeError):
        matched = False
elif isinstance(actual, float):
    try:
        matched = float(expected) == actual
    except (ValueError, TypeError):
        matched = False
else:
    matched = actual == expected

if not matched:
    sys.stderr.write(f"mismatch expected={expected!r} actual={actual!r}\n")
    sys.exit(4)

sys.stdout.write("MATCH\n")
' "$yaml_file" "$block_id" "$field" "$use_root"
}

# cmd_karo_hotfix_deploy_task_atomic_publish_202607111645: awk/python生成のtmp_fileを
# 共有運用YAML(target_file)へ発行する共通口。tmp_fileは呼び出し側がtarget_fileと同一
# ディレクトリ(同一filesystem)でmktempしていることが前提(別filesystemだとmvがEXDEVで失敗する)。
# 検証NGなら target_file は一切変更せず、tmp_fileも残さない(fail-closed + 一時ファイル0件)。
_yaml_field_set_publish_atomic() {
    local tmp_file="$1"
    local target_file="$2"

    if ! _yaml_field_set_validate_parseable "$tmp_file" 2>&1; then
        rm -f "$tmp_file"
        echo "FATAL: publish_atomic: generated content failed YAML validation, original file kept unchanged: $target_file" >&2
        return 1
    fi
    if ! mv "$tmp_file" "$target_file"; then
        rm -f "$tmp_file"
        echo "FATAL: publish_atomic: atomic publish (mv) failed: $target_file" >&2
        return 1
    fi
}

_yaml_field_set_apply_root() {
    local yaml_file="$1"
    local out_file="$2"
    local field="$3"
    local new_value="$4"

    awk \
        -v field="$field" \
        -v new_value="$new_value" '
function regex_escape(str,    out,i,c) {
    out = ""
    for (i = 1; i <= length(str); i++) {
        c = substr(str, i, 1)
        if (c ~ /[][\\.^$*+?(){}|]/) {
            out = out "\\" c
        } else {
            out = out c
        }
    }
    return out
}
function yaml_safe(v,    out,i,c,needs_quote) {
    needs_quote = 0
    if (v ~ /^0[0-9]+$/) needs_quote = 1
    if (index(v, ":") > 0) needs_quote = 1
    if (index(v, "#") > 0) needs_quote = 1
    if (index(v, "[") > 0) needs_quote = 1
    if (index(v, "]") > 0) needs_quote = 1
    if (index(v, "{") > 0) needs_quote = 1
    if (index(v, "}") > 0) needs_quote = 1
    if (index(v, "|") > 0) needs_quote = 1
    if (index(v, ">") > 0) needs_quote = 1
    if (index(v, "\"") > 0) needs_quote = 1
    if (index(v, "\n") > 0) needs_quote = 1
    if (index(v, "\t") > 0) needs_quote = 1
    if (index(v, "\r") > 0) needs_quote = 1
    if (needs_quote) {
        out = ""
        for (i = 1; i <= length(v); i++) {
            c = substr(v, i, 1)
            if (c == "\\") out = out "\\\\"
            else if (c == "\"") out = out "\\\""
            else if (c == "\n") out = out "\\n"
            else if (c == "\t") out = out "\\t"
            else if (c == "\r") out = out "\\r"
            else out = out c
        }
        return "\"" out "\""
    }
    return v
}
BEGIN { replaced = 0; has_fields = 0; skip_children = 0 }
{
    # When replacing a nested mapping header, skip its indented children
    if (skip_children) {
        if ($0 == "" || (($0 ~ /^[[:space:]]/ || $0 ~ /^-[[:space:]]/) && $0 !~ /^[A-Za-z0-9_.-]+:/)) {
            next
        }
        skip_children = 0
    }
    field_re = "^" regex_escape(field) ":[[:space:]]*"
    if (!replaced && $0 ~ field_re) {
        # Detect if the original line is a nested mapping header (value is empty)
        rhs = $0
        sub("^" regex_escape(field) ":[[:space:]]*", "", rhs)
        sub(/[[:space:]]+$/, "", rhs)
        print field ": " yaml_safe(new_value)
        replaced = 1
        has_fields = 1
        # A root block scalar owns the following indented physical lines just
        # like a mapping header owns its children.  Leaving those lines behind
        # after replacing `field: |`/`field: >-` with an inline scalar makes
        # the candidate invalid (compact_state session_summary regression).
        if (rhs == "" || rhs ~ /^#/ || rhs ~ /^[|>][+-]?[0-9]*([[:space:]]+#.*)?$/) {
            skip_children = 1
        }
        next
    }
    if ($0 ~ /^[A-Za-z0-9_.-]+:[[:space:]]/) has_fields = 1
    print
}
END {
    if (!has_fields) exit 2
    if (!replaced) print field ": " yaml_safe(new_value)
}
' "$yaml_file" > "$out_file"
}

_yaml_field_set_apply_map_scalar() {
    local yaml_file="$1"
    local out_file="$2"
    local block_id="$3"
    local field="$4"
    local new_value="$5"

    if [[ "$block_id" == *$'\n'* ]] || [[ "$field" == *$'\n'* ]] || [[ "$new_value" == *$'\n'* ]]; then
        return 2
    fi
    if [[ "$new_value" == '['* ]] || [[ "$new_value" == '{'* ]]; then
        return 2
    fi

    awk \
        -v block_id="$block_id" \
        -v field="$field" \
        -v new_value="$new_value" '
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
function is_inline_scalar_field(line,    rhs) {
    if (line !~ ("^" make_indent(field_indent) "[A-Za-z0-9_.-]+:[[:space:]]*")) return 0
    rhs = line
    sub("^" make_indent(field_indent) "[A-Za-z0-9_.-]+:[[:space:]]*", "", rhs)
    rhs = trim(rhs)
    if (rhs == "") return 0
    if (rhs ~ /^[|>][+-]?[0-9]*$/) return 0
    return 1
}
function is_closed_quoted_inline_scalar(line,    rhs,first,last,prev) {
    if (line !~ ("^" make_indent(field_indent) "[A-Za-z0-9_.-]+:[[:space:]]*")) return 0
    rhs = line
    sub("^" make_indent(field_indent) "[A-Za-z0-9_.-]+:[[:space:]]*", "", rhs)
    rhs = trim(rhs)
    if (length(rhs) < 2) return 0
    first = substr(rhs, 1, 1)
    last = substr(rhs, length(rhs), 1)
    if (first == "\047" && last == "\047") return 1
    if (first == "\"" && last == "\"") {
        prev = substr(rhs, length(rhs) - 1, 1)
        if (prev != "\\") return 1
    }
    return 0
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
    if (v ~ /^0[0-9]+$/) needs_quote = 1
    if (index(v, ":") > 0) needs_quote = 1
    if (index(v, "#") > 0) needs_quote = 1
    if (index(v, "[") > 0) needs_quote = 1
    if (index(v, "]") > 0) needs_quote = 1
    if (index(v, "{") > 0) needs_quote = 1
    if (index(v, "}") > 0) needs_quote = 1
    if (index(v, "|") > 0) needs_quote = 1
    if (index(v, ">") > 0) needs_quote = 1
    if (index(v, "\"") > 0) needs_quote = 1
    if (index(v, "\n") > 0) needs_quote = 1
    if (index(v, "\t") > 0) needs_quote = 1
    if (index(v, "\r") > 0) needs_quote = 1
    if (needs_quote) {
        out = ""
        for (i = 1; i <= length(v); i++) {
            c = substr(v, i, 1)
            if (c == "\\") out = out "\\\\"
            else if (c == "\"") out = out "\\\""
            else if (c == "\n") out = out "\\n"
            else if (c == "\t") out = out "\\t"
            else if (c == "\r") out = out "\\r"
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
    skip_replaced_continuation = 0
    prev_closed_quoted_scalar = 0
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

    if (skip_replaced_continuation) {
        if (trimmed == "") next
        if (indent > field_indent || (indent == field_indent && trimmed ~ /^-[[:space:]]/)) next
        skip_replaced_continuation = 0
    }

    # Historical malformed task YAML may contain a stray indented line after a
    # scalar whose quote already closed on the field line.  Drop only that
    # impossible continuation; preserve valid wrapped plain/open-quoted scalars.
    if (prev_closed_quoted_scalar && indent > field_indent && trimmed != "" && trimmed !~ /^#/ && trimmed !~ /^-/) {
        next
    }

    field_re = "^" make_indent(field_indent) regex_escape(field) ":[[:space:]]*"
    if (!replaced && $0 ~ field_re) {
        print make_indent(field_indent) field ": " yaml_safe(new_value)
        replaced = 1
        skip_replaced_continuation = 1
        next
    }
    if (indent == field_indent) {
        prev_closed_quoted_scalar = is_closed_quoted_inline_scalar($0)
    }
    print
}
END {
    if (!block_found) exit 2
    if (in_block && !replaced) print make_indent(field_indent) field ": " yaml_safe(new_value)
}
' "$yaml_file" > "$out_file"
}

_yaml_field_get_root() {
    local yaml_file="$1"
    local field="$2"

    awk \
        -v field="$field" '
function trim(s) { sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
function unquote(s) {
    if (length(s) >= 2) {
        if (substr(s,1,1) == "\"" && substr(s,length(s),1) == "\"") {
            s = substr(s, 2, length(s)-2)
            gsub(/\\"/, "\"", s)
        } else if (substr(s,1,1) == "'"'"'" && substr(s,length(s),1) == "'"'"'") {
            s = substr(s, 2, length(s)-2)
            gsub(/'"'"''"'"'/, "'"'"'", s)
        }
    }
    return s
}
function regex_escape(str,    out,i,c) {
    out = ""
    for (i = 1; i <= length(str); i++) {
        c = substr(str, i, 1)
        if (c ~ /[][\\.^$*+?(){}|]/) {
            out = out "\\" c
        } else {
            out = out c
        }
    }
    return out
}
BEGIN { found = 0 }
{
    field_re = "^" regex_escape(field) ":[[:space:]]*"
    if (!found && $0 ~ field_re) {
        value = $0
        sub(field_re, "", value)
        value = trim(value)
        if (substr(value, 1, 1) != "\"" && substr(value, 1, 1) != "'"'"'") {
            sub(/[[:space:]]+#.*$/, "", value)
        }
        value = trim(unquote(value))
        print value
        found = 1
        exit 0
    }
}
END {
    if (!found) exit 3
}
' "$yaml_file"
}

# List items generated from mapping data do not guarantee that `id` is the
# first key (for example `- description: ...` followed by `  id: AC1`).
_yaml_field_set_apply_list_id_anywhere() {
    local yaml_file="$1" out_file="$2" block_id="$3" field="$4" new_value="$5"
    YFS_NEW_VALUE="$new_value" python3 - "$yaml_file" "$out_file" "$block_id" "$field" <<'PY'
import os, re, sys
src, dst, block_id, field = sys.argv[1:]
value = os.environ.get("YFS_NEW_VALUE", "")
lines = open(src, encoding="utf-8").readlines()
item_re = re.compile(r"^( *)-\s+")
id_re = re.compile(r"^( *)id:\s*(.*?)\s*(?:#.*)?$")
inline_id_re = re.compile(r"^( *)-\s+id:\s*(.*?)\s*(?:#.*)?$")
def unquote(s):
    s = s.strip()
    return s[1:-1] if len(s) >= 2 and s[0] == s[-1] and s[0] in "\"'" else s
def scalar(s):
    if re.fullmatch(r"0[0-9]+", s) or any(c in s for c in ':#[]{}|>"\n\t\r'):
        s = s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\t', '\\t').replace('\r', '\\r')
        return f'"{s}"'
    return s
starts = [(i, len(m.group(1))) for i, line in enumerate(lines) if (m := item_re.match(line))]
matches = []
for pos, (start, indent) in enumerate(starts):
    end = next((n for n, ni in starts[pos + 1:] if ni <= indent), len(lines))
    for line in lines[start:end]:
        m = id_re.match(line.rstrip('\n'))
        inline = inline_id_re.match(line.rstrip('\n'))
        direct_match = m and len(m.group(1)) == indent + 2 and unquote(m.group(2)) == block_id
        inline_match = inline and len(inline.group(1)) == indent and unquote(inline.group(2)) == block_id
        if direct_match or inline_match:
            matches.append((start, end, indent + 2)); break
if not matches: sys.exit(2)
if len(matches) != 1:
    print(f"duplicate_list_id: {block_id} ({len(matches)} matches)", file=sys.stderr); sys.exit(3)
start, end, direct = matches[0]
field_re = re.compile(rf"^ {{{direct}}}{re.escape(field)}:\s*")
replacement = " " * direct + field + ": " + scalar(value) + "\n"
at = next((i for i in range(start, end) if field_re.match(lines[i])), None)
if at is None:
    lines.insert(end, replacement)
else:
    stop = at + 1
    while stop < end:
        stripped = lines[stop].strip(); indent = len(lines[stop]) - len(lines[stop].lstrip(' '))
        if stripped and indent <= direct: break
        stop += 1
    lines[at:stop] = [replacement]
with open(dst, "w", encoding="utf-8", newline="") as fh: fh.writelines(lines)
PY
}

_yaml_field_set_apply() {
    local yaml_file="$1"
    local out_file="$2"
    local block_id="$3"
    local field="$4"
    local new_value="$5"

    awk \
        -v block_id="$block_id" \
        -v field="$field" \
        -v new_value="$new_value" '
function trim(s) { sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
function unquote(s) {
    if (length(s) >= 2) {
        if (substr(s,1,1) == "\"" && substr(s,length(s),1) == "\"") {
            s = substr(s, 2, length(s)-2)
            gsub(/\\"/, "\"", s)
        } else if (substr(s,1,1) == "'"'"'" && substr(s,length(s),1) == "'"'"'") {
            s = substr(s, 2, length(s)-2)
            gsub(/'"'"''"'"'/, "'"'"'", s)
        }
    }
    return s
}

function leading_spaces(line,    i,cnt,c) {
    cnt = 0
    for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (c == " ") {
            cnt++
        } else {
            break
        }
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
        if (c ~ /[][\\.^$*+?(){}|]/) {
            out = out "\\" c
        } else {
            out = out c
        }
    }
    return out
}
function begin_target(line,    t,key) {
    t = line
    if (t ~ /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/) {
        sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "", t)
        sub(/[[:space:]]+#.*$/, "", t)
        t = trim(unquote(t))
        if (t == block_id) {
            block_kind = "id"
            block_indent = leading_spaces(line)
            field_indent = block_indent + 2
            return 1
        }
    }

    t = line
    if (t ~ /^[[:space:]]*-[[:space:]]*cmd_id:[[:space:]]*/) {
        sub(/^[[:space:]]*-[[:space:]]*cmd_id:[[:space:]]*/, "", t)
        sub(/[[:space:]]+#.*$/, "", t)
        t = trim(unquote(t))
        if (t == block_id) {
            block_kind = "id"
            block_indent = leading_spaces(line)
            field_indent = block_indent + 2
            return 1
        }
    }

    t = line
    if (t ~ /^[[:space:]]*-[[:space:]]*check:[[:space:]]*/) {
        sub(/^[[:space:]]*-[[:space:]]*check:[[:space:]]*/, "", t)
        sub(/[[:space:]]+#.*$/, "", t)
        t = trim(unquote(t))
        if (t == block_id) {
            block_kind = "list"
            block_indent = leading_spaces(line)
            field_indent = block_indent + 2
            return 1
        }
    }

    t = line
    sub(/[[:space:]]+#.*$/, "", t)
    if (t ~ /^[[:space:]]*[A-Za-z0-9_.-]+:[[:space:]]*$/) {
        key = t
        sub(/^[[:space:]]*/, "", key)
        sub(/:[[:space:]]*$/, "", key)
        if (key == block_id) {
            block_kind = "map"
            block_indent = leading_spaces(line)
            field_indent = block_indent + 2
            return 1
        }
    }
    return 0
}
function is_boundary(line,    indent,t) {
    if (block_kind == "list") {
        if (line ~ /^[[:space:]]*-[[:space:]]*/) {
            indent = leading_spaces(line)
            if (indent <= block_indent) return 1
        }
        return 0
    }

    if (block_kind == "id") {
        if (line ~ /^[[:space:]]*-[[:space:]]*(id|cmd_id):[[:space:]]*/) {
            indent = leading_spaces(line)
            if (indent <= block_indent) return 1
        }
        return 0
    }

    t = trim(line)
    if (t == "" || t ~ /^#/) return 0

    indent = leading_spaces(line)
    if (indent <= block_indent) return 1
    return 0
}
function yaml_safe(v,    out,i,c,needs_quote) {
    needs_quote = 0
    if (v ~ /^0[0-9]+$/) needs_quote = 1
    if (index(v, ":") > 0) needs_quote = 1
    if (index(v, "#") > 0) needs_quote = 1
    if (index(v, "[") > 0) needs_quote = 1
    if (index(v, "]") > 0) needs_quote = 1
    if (index(v, "{") > 0) needs_quote = 1
    if (index(v, "}") > 0) needs_quote = 1
    if (index(v, "|") > 0) needs_quote = 1
    if (index(v, ">") > 0) needs_quote = 1
    if (index(v, "\"") > 0) needs_quote = 1
    if (index(v, "\n") > 0) needs_quote = 1
    if (index(v, "\t") > 0) needs_quote = 1
    if (index(v, "\r") > 0) needs_quote = 1
    if (needs_quote) {
        out = ""
        for (i = 1; i <= length(v); i++) {
            c = substr(v, i, 1)
            if (c == "\\") out = out "\\\\"
            else if (c == "\"") out = out "\\\""
            else if (c == "\n") out = out "\\n"
            else if (c == "\t") out = out "\\t"
            else if (c == "\r") out = out "\\r"
            else out = out c
        }
        return "\"" out "\""
    }
    return v
}
function flush_block(    i,line,indent_str,field_re,replaced,skip_replaced_continuation,line_indent,line_trimmed,last_scalar_indent) {
    indent_str = make_indent(field_indent)
    field_re = "^" indent_str regex_escape(field) ":[[:space:]]*"
    replaced = 0
    skip_replaced_continuation = 0
    last_scalar_indent = -1

    last_held = ""
    for (i = 1; i <= block_len; i++) {
        line = block_lines[i]
        if (skip_replaced_continuation) {
            line_indent = leading_spaces(line)
            line_trimmed = trim(line)
            if (line_trimmed == "" || line_indent > field_indent || (line_indent == field_indent && line_trimmed ~ /^-[[:space:]]/)) {
                continue
            }
            skip_replaced_continuation = 0
        }
        if (last_scalar_indent >= 0) {
            line_indent = leading_spaces(line)
            line_trimmed = trim(line)
            if (line_trimmed == "" || line_indent > last_scalar_indent) {
                continue
            }
            last_scalar_indent = -1
        }
        if (i > 1 && !replaced && line ~ field_re) {
            print indent_str field ": " yaml_safe(new_value)
            replaced = 1
            skip_replaced_continuation = 1
        } else {
            # 最終行を保持: 新フィールド追加時に最終行の前に挿入する
            # (2026-06-26: 最終ブロックのEOF追加でEdit挿入時に次cmdへ侵入するバグ根治)
            if (last_held != "") print last_held
            if (i > 1 && i == block_len && !replaced && leading_spaces(line) <= field_indent) {
                last_held = line
            } else {
                last_held = ""
                print line
            }
            if (line ~ "^" indent_str "[A-Za-z0-9_.-]+:[[:space:]]*\".*\"[[:space:]]*$") {
                last_scalar_indent = field_indent
            }
        }
    }

    if (!replaced && last_held != "") {
        print indent_str field ": " yaml_safe(new_value)
        print last_held
    } else if (!replaced) {
        print indent_str field ": " yaml_safe(new_value)
    } else if (last_held != "") {
        print last_held
    }

    delete block_lines
    block_len = 0
}
BEGIN {
    in_block = 0
    block_found = 0
    block_done = 0
    block_len = 0
}
{
    if (!in_block) {
        if (!block_done && begin_target($0)) {
            in_block = 1
            block_found = 1
            block_len = 1
            block_lines[1] = $0
            next
        }
        print
        next
    }

    if (is_boundary($0)) {
        flush_block()
        in_block = 0
        block_done = 1
        print $0
        next
    }

    block_len++
    block_lines[block_len] = $0
}
END {
    if (in_block) {
        flush_block()
        block_done = 1
    }
    if (!block_found) {
        exit 2
    }
}
' "$yaml_file" > "$out_file"
}

_yaml_field_get_in_block() {
    local yaml_file="$1"
    local block_id="$2"
    local field="$3"

    awk \
        -v block_id="$block_id" \
        -v field="$field" '
function trim(s) { sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
function unquote(s) {
    if (length(s) >= 2) {
        if (substr(s,1,1) == "\"" && substr(s,length(s),1) == "\"") {
            s = substr(s, 2, length(s)-2)
            gsub(/\\"/, "\"", s)
        } else if (substr(s,1,1) == "'"'"'" && substr(s,length(s),1) == "'"'"'") {
            s = substr(s, 2, length(s)-2)
            gsub(/'"'"''"'"'/, "'"'"'", s)
        }
    }
    return s
}
function leading_spaces(line,    i,cnt,c) {
    cnt = 0
    for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (c == " ") {
            cnt++
        } else {
            break
        }
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
        if (c ~ /[][\\.^$*+?(){}|]/) {
            out = out "\\" c
        } else {
            out = out c
        }
    }
    return out
}
function begin_target(line,    t,key) {
    t = line
    if (t ~ /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/) {
        sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "", t)
        sub(/[[:space:]]+#.*$/, "", t)
        t = trim(unquote(t))
        if (t == block_id) {
            block_kind = "id"
            block_indent = leading_spaces(line)
            field_indent = block_indent + 2
            return 1
        }
    }

    t = line
    if (t ~ /^[[:space:]]*-[[:space:]]*cmd_id:[[:space:]]*/) {
        sub(/^[[:space:]]*-[[:space:]]*cmd_id:[[:space:]]*/, "", t)
        sub(/[[:space:]]+#.*$/, "", t)
        t = trim(unquote(t))
        if (t == block_id) {
            block_kind = "id"
            block_indent = leading_spaces(line)
            field_indent = block_indent + 2
            return 1
        }
    }

    t = line
    if (t ~ /^[[:space:]]*-[[:space:]]*check:[[:space:]]*/) {
        sub(/^[[:space:]]*-[[:space:]]*check:[[:space:]]*/, "", t)
        sub(/[[:space:]]+#.*$/, "", t)
        t = trim(unquote(t))
        if (t == block_id) {
            block_kind = "list"
            block_indent = leading_spaces(line)
            field_indent = block_indent + 2
            return 1
        }
    }

    t = line
    sub(/[[:space:]]+#.*$/, "", t)
    if (t ~ /^[[:space:]]*[A-Za-z0-9_.-]+:[[:space:]]*$/) {
        key = t
        sub(/^[[:space:]]*/, "", key)
        sub(/:[[:space:]]*$/, "", key)
        if (key == block_id) {
            block_kind = "map"
            block_indent = leading_spaces(line)
            field_indent = block_indent + 2
            return 1
        }
    }
    return 0
}
function is_boundary(line,    indent,t) {
    if (block_kind == "list") {
        if (line ~ /^[[:space:]]*-[[:space:]]*/) {
            indent = leading_spaces(line)
            if (indent <= block_indent) return 1
        }
        return 0
    }

    if (block_kind == "id") {
        if (line ~ /^[[:space:]]*-[[:space:]]*(id|cmd_id):[[:space:]]*/) {
            indent = leading_spaces(line)
            if (indent <= block_indent) return 1
        }
        return 0
    }

    t = trim(line)
    if (t == "" || t ~ /^#/) return 0
    indent = leading_spaces(line)
    if (indent <= block_indent) return 1
    return 0
}
BEGIN {
    in_block = 0
    block_found = 0
    field_found = 0
}
{
    if (!in_block) {
        if (begin_target($0)) {
            in_block = 1
            block_found = 1
            next
        }
        next
    }

    if (is_boundary($0)) {
        in_block = 0
        next
    }

    indent_str = make_indent(field_indent)
    field_re = "^" indent_str regex_escape(field) ":[[:space:]]*"
    if (!field_found && $0 ~ field_re) {
        value = $0
        sub(field_re, "", value)
        value = trim(value)
        if (substr(value, 1, 1) != "\"" && substr(value, 1, 1) != "'"'"'") {
            sub(/[[:space:]]+#.*$/, "", value)
        }
        value = trim(unquote(value))
        print value
        field_found = 1
        exit 0
    }
}
END {
    if (!block_found) exit 2
    if (!field_found) exit 3
}
' "$yaml_file"
}

# cmd_karo_impl_yaml_field_set_list_nested_20260725:
# 構造書込みレーン。dotted path("a.b.c")とlist追記(--append)を扱う。
# 旧実装はdotted fieldをawkの完全一致キーとして扱い、該当キーが無いと
# root fallbackで**トップレベルにリテラルキー'a.b.c'を新規追加しRC=0を返した**
# (半蔵が隔離コピーで実測)。成功を返しながら意図と異なる結果を残すのが最も危険であり、
# 本レーンは書けない場合に必ず非ゼロで失敗する。
# 書込みはyaml.dumpによる全文再生成ではなく、対象keyの行範囲だけを差し替える
# 外科的splice(周辺行はバイト単位で保存)。fragment生成のみyaml_atomic.yaml_textを使う
# (L295/cmd_1399: 全文yaml.dumpはデータ消失を起こす)。
_yaml_field_set_structural() {
    local yaml_file="$1"
    local out_file="$2"
    local block_id="$3"
    local field="$4"
    local value="$5"
    local mode="$6"

    local _self _root
    _self="${BASH_SOURCE[0]:-$0}"
    [[ "$_self" != /* ]] && _self="$PWD/$_self"
    _root="${_self%/scripts/lib/yaml_field_set.sh}"

    YFS_S_FILE="$yaml_file" YFS_S_OUT="$out_file" YFS_S_BLOCK="$block_id" \
    YFS_S_PATH="$field" YFS_S_VALUE="$value" YFS_S_MODE="$mode" \
    YFS_S_LIBDIR="${_self%/yaml_field_set.sh}" YFS_S_ROOT="$_root" python3 - <<'PY'
import os
import re
import sys

import yaml


def _load_yaml_text():
    libdir = os.environ.get("YFS_S_LIBDIR", "")
    local = os.path.join(libdir, "yaml_atomic.py")
    if os.path.isfile(local):
        import importlib.util

        spec = importlib.util.spec_from_file_location("_yfs_yaml_atomic", local)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod.yaml_text
    sys.path.insert(0, os.environ.get("YFS_S_ROOT", ""))
    from scripts.lib.yaml_atomic import yaml_text  # noqa: E402

    return yaml_text


def fail(msg, code=1):
    sys.stderr.write("FATAL: yaml_field_set(structural): %s\n" % msg)
    raise SystemExit(code)


yaml_text = _load_yaml_text()

path_file = os.environ["YFS_S_FILE"]
out_file = os.environ["YFS_S_OUT"]
block_id = os.environ["YFS_S_BLOCK"]
dotted = os.environ["YFS_S_PATH"]
raw_value = os.environ["YFS_S_VALUE"]
mode = os.environ["YFS_S_MODE"]

with open(path_file, encoding="utf-8") as fh:
    text = fh.read()
lines = text.splitlines(True)

try:
    data = yaml.safe_load(text)
except Exception as exc:
    fail("source file is not parseable YAML: %s" % exc)

keys = [k for k in dotted.split(".") if k != ""]
if not keys or len(keys) != len(dotted.split(".")):
    fail("invalid field path: %r" % dotted)

# Structured input is honoured only when it parses to a list/mapping.  Anything
# else stays the caller's literal string, so 'yes'/'123'/'null' cannot be
# silently retyped by YAML resolution.
def coerce(s):
    try:
        parsed = yaml.safe_load(s)
    except Exception:
        return s
    if isinstance(parsed, (list, dict)):
        return parsed
    return s


element = coerce(raw_value)


def indent_of(line):
    return len(line) - len(line.lstrip(" "))


def blankish(line):
    s = line.strip()
    return s == "" or s.startswith("#")


def find_key(start, end, indent, key):
    pat = re.compile(r"^ {%d}%s\s*:" % (indent, re.escape(key)))
    for i in range(start, end):
        if blankish(lines[i]):
            continue
        if indent_of(lines[i]) != indent:
            continue
        if pat.match(lines[i]):
            return i
    return None


def body_of(key_idx, end):
    """Return (body_start, body_end, child_indent) for the mapping key at key_idx."""
    ki = indent_of(lines[key_idx])
    body_start = key_idx + 1
    body_end = body_start
    child_indent = None
    i = body_start
    while i < end:
        if blankish(lines[i]):
            i += 1
            continue
        if indent_of(lines[i]) <= ki:
            break
        if child_indent is None:
            child_indent = indent_of(lines[i])
        body_end = i + 1
        i += 1
    if child_indent is None:
        child_indent = ki + 2
    return body_start, body_end, child_indent


def value_end(key_idx, end):
    """Exclusive end line of the whole value owned by the key at key_idx."""
    ki = indent_of(lines[key_idx])
    last = key_idx + 1
    i = key_idx + 1
    while i < end:
        if blankish(lines[i]):
            i += 1
            continue
        line_indent = indent_of(lines[i])
        if line_indent < ki:
            break
        if line_indent == ki and not lines[i].lstrip().startswith("- "):
            break
        last = i + 1
        i += 1
    return last


# --- resolve the block scope -------------------------------------------------
if block_id == "root":
    scope = (0, len(lines), 0)
else:
    map_idx = None
    map_pat = re.compile(r"^(\s*)%s\s*:\s*(#.*)?$" % re.escape(block_id))
    for i, line in enumerate(lines):
        if map_pat.match(line):
            map_idx = i
            break
    if map_idx is not None:
        scope = body_of(map_idx, len(lines))
    else:
        item_idx = None
        item_pat = re.compile(
            r"^(\s*)-\s*(id|cmd_id|check)\s*:\s*[\"']?%s[\"']?\s*$" % re.escape(block_id)
        )
        for i, line in enumerate(lines):
            if item_pat.match(line):
                item_idx = i
                break
        if item_idx is None:
            fail("block_id not found: %s (%s)" % (block_id, path_file), 2)
        dash_indent = indent_of(lines[item_idx])
        child_indent = dash_indent + 2
        end = item_idx + 1
        i = item_idx + 1
        while i < len(lines):
            if blankish(lines[i]):
                i += 1
                continue
            if indent_of(lines[i]) <= dash_indent:
                break
            end = i + 1
            i += 1
        scope = (item_idx, end, child_indent)

start, end, cur_indent = scope

# --- walk intermediate segments ---------------------------------------------
for depth, key in enumerate(keys[:-1]):
    idx = find_key(start, end, cur_indent, key)
    if idx is None:
        fail(
            "path segment %r not found under %s (path=%s). "
            "Create the parent mapping first; this helper never invents intermediate keys."
            % (key, ".".join([block_id] + keys[:depth]) or block_id, dotted),
            2,
        )
    inline = lines[idx].split(":", 1)[1].strip()
    if inline and not inline.startswith("#"):
        fail(
            "path segment %r holds a scalar value, not a mapping (path=%s)" % (key, dotted),
            2,
        )
    start, end, cur_indent = body_of(idx, end)

leaf = keys[-1]
leaf_idx = find_key(start, end, cur_indent, leaf)

# --- compute the new value ---------------------------------------------------
def navigate(root_obj):
    node = root_obj
    if block_id != "root":
        found = []

        def walk(n):
            if isinstance(n, dict):
                v = n.get(block_id)
                if isinstance(v, dict):
                    found.append(v)
                for vv in n.values():
                    walk(vv)
            elif isinstance(n, list):
                for item in n:
                    if isinstance(item, dict):
                        for k in ("id", "cmd_id", "check"):
                            if k in item and str(item[k]) == block_id:
                                found.append(item)
                                break
                    walk(item)

        walk(root_obj)
        if not found:
            return None, False
        node = found[0]
    for k in keys[:-1]:
        if not isinstance(node, dict) or k not in node:
            return None, False
        node = node[k]
    if not isinstance(node, dict) or leaf not in node:
        return None, False
    return node[leaf], True


if mode == "append":
    existing, present = navigate(data)
    if present and isinstance(existing, list):
        new_value = list(existing)
    elif present and existing is not None and existing != "":
        # scalar → list 化(小太郎事例: planned_paths が scalar 1本で contract test が
        # scope外判定になった)。既存値は先頭要素として保持する。
        new_value = [existing]
    else:
        new_value = []
    if isinstance(element, list):
        additions = element
    else:
        additions = [element]
    for item in additions:
        if item not in new_value:
            new_value.append(item)
else:
    new_value = element

# --- render + splice ---------------------------------------------------------
try:
    fragment = yaml_text({leaf: new_value})
except Exception as exc:
    fail("failed to render value fragment: %s" % exc)

pad = " " * cur_indent
rendered = []
for line in fragment.splitlines():
    rendered.append((pad + line if line.strip() else "") + "\n")

if leaf_idx is None:
    insert_at = end
    new_lines = lines[:insert_at] + rendered + lines[insert_at:]
else:
    new_lines = lines[:leaf_idx] + rendered + lines[value_end(leaf_idx, end):]

new_text = "".join(new_lines)

# --- verify on the candidate before the caller publishes ---------------------
try:
    new_data = yaml.safe_load(new_text)
except Exception as exc:
    fail("generated content is not parseable YAML: %s" % exc)

actual, present = navigate(new_data)
if not present:
    fail("post-write verification could not locate %s.%s" % (block_id, dotted))
if actual != new_value:
    fail("post-write mismatch expected=%r actual=%r" % (new_value, actual))

with open(out_file, "w", encoding="utf-8") as fh:
    fh.write(new_text)
PY
}

yaml_field_set() {
    local _yfs_mode="set"
    if [ "${1:-}" = "--append" ]; then
        _yfs_mode="append"
        shift
    fi

    local yaml_file="$1"
    local block_id="$2"
    local field="$3"
    local new_value="$4"

    if [ "$#" -lt 4 ]; then
        echo "Usage: yaml_field_set [--append] <yaml_file> <block_id> <field|a.b.c> <new_value>" >&2
        return 1
    fi

    # Active task leases have one authority: progress_updated_at.  Lifecycle
    # writes must publish the requested value and the renewed lease together.
    if [[ "$yaml_file" == */queue/tasks/*.yaml || "$yaml_file" == queue/tasks/*.yaml ]] \
        && [ "$block_id" = "task" ] \
        && { [ "$field" = "progress" ] || { [ "$field" = "status" ] && [[ "$new_value" =~ ^(acknowledged|in_progress)$ ]]; }; }; then
        yaml_field_set_batch "$yaml_file" "$block_id" \
            "$field=$new_value" "progress_updated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        return $?
    fi

    if [ ! -f "$yaml_file" ]; then
        echo "FATAL: yaml_field_set: file not found: $yaml_file" >&2
        return 1
    fi

    if ! _yaml_field_set_reject_bracket_field "$field"; then
        return 1
    fi

    # cmd_karo_impl_yaml_field_set_list_nested_20260725: dotted path / list追記は
    # awkレーン(完全一致キー前提)では表現できない。構造書込みレーンへ回す。
    # 判定はstructured typeより先に行う(--append planned_paths のような
    # 「既知の構造化fieldへの追記」もawk/全置換ではなく追記として扱うため)。
    if [ "$_yfs_mode" = "append" ] || [[ "$field" == *.* ]]; then
        local _s_lock _s_tmp
        _s_lock="$(lock_path "$yaml_file")"
        _s_tmp="$(mktemp "${yaml_file}.XXXXXX")" || {
            echo "FATAL: yaml_field_set: failed to create temp file for $yaml_file" >&2
            return 1
        }
        {
            flock -w 10 200 || {
                rm -f "$_s_tmp"
                echo "FATAL: yaml_field_set: flock timeout for $yaml_file" >&2
                return 1
            }
            if ! _yaml_field_set_structural "$yaml_file" "$_s_tmp" "$block_id" "$field" "$new_value" "$_yfs_mode"; then
                rm -f "$_s_tmp"
                echo "FATAL: yaml_field_set: structural write failed for ${block_id}.${field} in $yaml_file; original file kept unchanged" >&2
                return 1
            fi
            _yaml_field_set_publish_atomic "$_s_tmp" "$yaml_file" || return 1
        } 200>"$_s_lock"
        return $?
    fi

    # cmd_karo_hotfix_control_plane_contracts_ga321_20260723:
    # Typed lifecycle fields are never scalars.  The ordinary awk lane
    # The ordinary awk lane deliberately quotes JSON/YAML punctuation to keep
    # scalar writes safe; using it for these fields therefore turns a list into
    # a string and blocks scope/commit checks only after implementation ends.
    # Route known structured task fields through
    # the existing flocked/atomic structural writer.  Invalid scalar input is
    # rejected before any write, so callers cannot silently corrupt the type.
    local _yfs_structured_type=""
    case "$field" in
        split_decision) _yfs_structured_type="mapping" ;;
    esac
    if [ "$block_id" = "task" ]; then
        case "$field" in
            acceptance_criteria) _yfs_structured_type="list" ;;
            test_necessity) _yfs_structured_type="list_or_mapping" ;;
            commit_contract) _yfs_structured_type="mapping" ;;
            investigation_contract) _yfs_structured_type="mapping" ;;
            pre_implementation_review) _yfs_structured_type="mapping" ;;
            planned_paths|target_path) _yfs_structured_type="list" ;;
        esac
    fi
    if [ -n "$_yfs_structured_type" ]; then
        if ! YFS_STRUCTURED_VALUE="$new_value" YFS_STRUCTURED_TYPE="$_yfs_structured_type" YFS_STRUCTURED_FIELD="$field" python3 -c '
import os, sys, yaml
value = yaml.safe_load(os.environ.get("YFS_STRUCTURED_VALUE", ""))
kind = os.environ["YFS_STRUCTURED_TYPE"]
field = os.environ["YFS_STRUCTURED_FIELD"]
valid = (
    isinstance(value, list)
    if kind == "list"
    else isinstance(value, dict)
    if kind == "mapping"
    else isinstance(value, (list, dict))
)
if not valid:
    expected = (
        "a YAML list"
        if kind == "list"
        else "a YAML mapping"
        if kind == "mapping"
        else "a YAML list or mapping"
    )
    print(f"BLOCK: task.{field} must be {expected}", file=sys.stderr)
    raise SystemExit(2)
'; then
            return 2
        fi
        local _yfs_self _yfs_report_setter
        _yfs_self="${BASH_SOURCE[0]:-$0}"
        [[ "$_yfs_self" != /* ]] && _yfs_self="$PWD/$_yfs_self"
        _yfs_report_setter="${_yfs_self%/lib/yaml_field_set.sh}/report_field_set.sh"
        # Invoke the writer explicitly through bash below, so executable mode is
        # not part of its runtime contract.  Git checkouts that preserve the
        # tracked 100644 mode must work exactly like a developer worktree.
        if [ ! -f "$_yfs_report_setter" ]; then
            echo "FATAL: yaml_field_set: structural writer not found: $_yfs_report_setter" >&2
            return 1
        fi
        local _yfs_structured_path="task.${field}"
        if [ "$block_id" != "task" ]; then
            # Command ledgers nest entries below `commands`, while task files
            # expose the reusable `task` block directly. Preserve the caller's
            # block identity instead of silently writing a stray task.* field.
            _yfs_structured_path="commands.${block_id}.${field}"
        fi
        printf '%s\n' "$new_value" | bash "$_yfs_report_setter" "$yaml_file" "$_yfs_structured_path" -
        return $?
    fi

    local lock_file
    lock_file="$(lock_path "$yaml_file")"
    local tmp_file
    # cmd_karo_hotfix_queue_yaml_atomicity_202607110113: 同一ディレクトリ(同一FS)にtemp作成。
    # 旧実装はtmpfs(/tmp)にtemp作成しflock内cat>yaml_fileで公開していたが、
    # cat>は open(O_TRUNC)直後にwriteするため truncate-write間に一瞬 0byte/不完全な状態が生じ、
    # flockを取らない読み手(gate_queue_yaml_parse.sh等)がその瞬間を読むと
    # YAMLError/UnicodeDecodeErrorで破損を観測する(2026-07-11 01:09 kagemaru.yaml破損の実因)。
    # 同一ディレクトリでmktempし最後にmv(rename)することで、公開を単一のatomic操作にする。
    tmp_file="$(mktemp "${yaml_file}.XXXXXX")" || {
        echo "FATAL: yaml_field_set: failed to create temp file for $yaml_file" >&2
        return 1
    }

    # cmd_karo_hotfix_yaml_field_set_multiline_verify_202607122228: awkの-v代入は
    # \n/\t/\\等のバックスラッシュエスケープ列を独自にデコードする(gawk実測確認済み)ため、
    # new_valueに生のバックスラッシュ(正規表現\s、Windowsパス等)が含まれると意図せぬ
    # 制御文字へ化ける。事前に二重化してdecodeを相殺する(yaml_field_set_batchの
    # 既存対策と同一データモデルへ統一)。post-write比較には元のnew_valueを使う。
    local yfs_safe_value="${new_value//\\/\\\\}"

    {
        flock -w 10 200 || {
            rm -f "$tmp_file"
            echo "FATAL: yaml_field_set: flock timeout for $yaml_file" >&2
            return 1
        }

        local use_root=0
        local rc=2

        if [ "$block_id" = "root" ]; then
            rc=0; _yaml_field_set_apply_root "$yaml_file" "$tmp_file" "$field" "$yfs_safe_value" || rc=$?
            if [ "$rc" -eq 0 ]; then
                use_root=1
            fi
        else
            rc=0; _yaml_field_set_apply_list_id_anywhere "$yaml_file" "$tmp_file" "$block_id" "$field" "$new_value" || rc=$?
            if [ "$rc" -eq 2 ]; then
                rc=0; _yaml_field_set_apply_map_scalar "$yaml_file" "$tmp_file" "$block_id" "$field" "$yfs_safe_value" || rc=$?
            fi
            if [ "$rc" -eq 2 ]; then
                rc=0; _yaml_field_set_apply "$yaml_file" "$tmp_file" "$block_id" "$field" "$yfs_safe_value" || rc=$?
            fi
        fi

        if [ "$rc" -eq 2 ]; then
            # Fallback: block_id not found → try root-level field update (flat YAML support)
            rc=0; _yaml_field_set_apply_root "$yaml_file" "$tmp_file" "$field" "$yfs_safe_value" || rc=$?
            if [ "$rc" -eq 0 ]; then
                use_root=1
            fi
        fi
        if [ "$rc" -ne 0 ]; then
            rm -f "$tmp_file"
            if [ "$rc" -eq 2 ]; then
                echo "FATAL: yaml_field_set: block_id not found and no root-level fields: $block_id ($yaml_file)" >&2
                # Hint: suggest available top-level block keys
                local _hint_blocks
                _hint_blocks=$(awk '/^[a-zA-Z_][a-zA-Z0-9_.-]*:[[:space:]]*$/{sub(/:[[:space:]]*$/,"");print}' "$yaml_file" 2>/dev/null | head -5 | tr '\n' ', ' | sed 's/,$//')
                if [ -n "$_hint_blocks" ]; then
                    echo "Hint: available block_id: $_hint_blocks (例: yaml_field_set <file> task <field> <value>)" >&2
                fi
            else
                echo "FATAL: yaml_field_set: failed to rewrite file: $yaml_file" >&2
            fi
            return 1
        fi

        # 候補上でparseと期待値を同時検証する。旧実装はparse→mv→値検証と
        # 同じYAMLをPythonで2回読んでいたうえ、値不一致時には公開済みだった。
        # 先に候補を検証すれば1 processで済み、失敗時も旧ファイルを保持できる。
        local _verify_err
        if ! _verify_err="$(_yaml_field_set_verify_parsed "$tmp_file" "$block_id" "$field" "$new_value" "$use_root" 2>&1 1>/dev/null)"; then
            rm -f "$tmp_file"
            echo "FATAL: yaml_field_set: candidate verification mismatch for ${block_id}.${field} in $yaml_file ($_verify_err); original file kept unchanged" >&2
            return 1
        fi

        # 同一ファイルシステム上のrename(mv)はatomicであり、読み手が
        # truncate-write間の不完全な状態を観測することがない。
        if ! mv "$tmp_file" "$yaml_file"; then
            rm -f "$tmp_file"
            echo "FATAL: yaml_field_set: atomic publish (mv) failed: $yaml_file" >&2
            return 1
        fi

    } 200>"$lock_file"
}

yaml_field_set_batch() {
    # Batch update: 1 flock + 1 awk pass for N fields.
    # Usage: yaml_field_set_batch <yaml_file> <block_id> "field1=value1" "field2=value2" ...
    local yaml_file="$1"
    local block_id="$2"
    shift 2

    if [[ "$yaml_file" == */queue/tasks/*.yaml || "$yaml_file" == queue/tasks/*.yaml ]] && [ "$block_id" = "task" ]; then
        local _lease_refresh=0 _lease_present=0 _lease_arg
        for _lease_arg in "$@"; do
            [[ "$_lease_arg" == progress_updated_at=* ]] && _lease_present=1
            [[ "$_lease_arg" == progress=* || "$_lease_arg" == status=acknowledged || "$_lease_arg" == status=in_progress ]] && _lease_refresh=1
        done
        if [ "$_lease_refresh" -eq 1 ] && [ "$_lease_present" -eq 0 ]; then
            set -- "$@" "progress_updated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        fi
    fi

    if [ "$#" -eq 0 ]; then
        echo "Usage: yaml_field_set_batch <yaml_file> <block_id> field1=val1 [field2=val2 ...]" >&2
        return 1
    fi
    if [ ! -f "$yaml_file" ]; then
        echo "FATAL: yaml_field_set_batch: file not found: $yaml_file" >&2
        return 1
    fi

    # Build fields/values arrays using a non-printable delimiter so field values
    # may contain shell/YAML punctuation such as pipe characters.
    local _sep
    _sep=$'\034'
    local _fields="" _values="" _count=0
    local _arg _f _v
    for _arg in "$@"; do
        _f="${_arg%%=*}"
        _v="${_arg#*=}"
        if [ -z "$_f" ]; then continue; fi
        if ! _yaml_field_set_reject_bracket_field "$_f"; then
            return 1
        fi
        # cmd_karo_impl_yaml_field_set_list_nested_20260725: batchのawkレーンも
        # 完全一致キー前提のため、dotted pathを渡すとトップレベルにリテラルキーを
        # 作って成功を返していた。構造レーン(自前でflock/atomic publishする)へ委譲する。
        if [[ "$_f" == *.* ]]; then
            if ! yaml_field_set "$yaml_file" "$block_id" "$_f" "$_v"; then
                echo "FATAL: yaml_field_set_batch: structural write failed for ${block_id}.${_f}" >&2
                return 1
            fi
            continue
        fi
        _v="${_v//\\/\\\\}"
        if [ "$_count" -gt 0 ]; then
            _fields="${_fields}${_sep}${_f}"
            _values="${_values}${_sep}${_v}"
        else
            _fields="$_f"
            _values="$_v"
        fi
        _count=$((_count + 1))
    done

    if [ "$_count" -eq 0 ]; then return 0; fi

    local lock_file
    lock_file="$(lock_path "$yaml_file")"
    local tmp_file
    tmp_file="$(mktemp "${yaml_file}.tmp.XXXXXX")" || {
        echo "FATAL: yaml_field_set_batch: failed to create temp file" >&2
        return 1
    }

    {
        flock -w 10 200 || {
            rm -f "$tmp_file"
            echo "FATAL: yaml_field_set_batch: flock timeout for $yaml_file" >&2
            return 1
        }

        awk \
            -v block_id="$block_id" \
            -v sep="$_sep" \
            -v fields_str="$_fields" \
            -v values_str="$_values" '
function trim(s) { sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
function unquote(s) {
    if (length(s) >= 2) {
        if (substr(s,1,1) == "\"" && substr(s,length(s),1) == "\"") {
            s = substr(s, 2, length(s)-2); gsub(/\\"/, "\"", s)
        } else if (substr(s,1,1) == "\047" && substr(s,length(s),1) == "\047") {
            s = substr(s, 2, length(s)-2)
            gsub(/\047\047/, "\047", s)
        }
    }
    return s
}

function leading_spaces(line,    i,cnt,c) {
    cnt = 0
    for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (c == " ") cnt++; else break
    }
    return cnt
}
function make_indent(n,    s,i) { s = ""; for (i = 0; i < n; i++) s = s " "; return s }
function regex_escape(str,    out,i,c) {
    out = ""
    for (i = 1; i <= length(str); i++) {
        c = substr(str, i, 1)
        if (c ~ /[][\\.^$*+?(){}|]/) out = out "\\" c
        else out = out c
    }
    return out
}
function is_inline_scalar_field(line,    rhs) {
    if (line !~ ("^" make_indent(field_indent) "[A-Za-z0-9_.-]+:[[:space:]]*")) return 0
    rhs = line
    sub("^" make_indent(field_indent) "[A-Za-z0-9_.-]+:[[:space:]]*", "", rhs)
    rhs = trim(rhs)
    if (rhs == "") return 0
    if (rhs ~ /^[|>][+-]?[0-9]*$/) return 0
    return 1
}
function is_closed_quoted_inline_scalar(line,    rhs,first,last,prev) {
    if (line !~ ("^" make_indent(field_indent) "[A-Za-z0-9_.-]+:[[:space:]]*")) return 0
    rhs = line
    sub("^" make_indent(field_indent) "[A-Za-z0-9_.-]+:[[:space:]]*", "", rhs)
    rhs = trim(rhs)
    if (length(rhs) < 2) return 0
    first = substr(rhs, 1, 1)
    last = substr(rhs, length(rhs), 1)
    if (first == "\047" && last == "\047") return 1
    if (first == "\"" && last == "\"") {
        prev = substr(rhs, length(rhs) - 1, 1)
        if (prev != "\\") return 1
    }
    return 0
}
function yaml_safe(v,    out,i,c,needs_quote) {
    needs_quote = 0
    if (v ~ /^0[0-9]+$/) needs_quote = 1
    if (index(v, ":") > 0) needs_quote = 1
    if (index(v, "#") > 0) needs_quote = 1
    if (index(v, "[") > 0) needs_quote = 1
    if (index(v, "]") > 0) needs_quote = 1
    if (index(v, "{") > 0) needs_quote = 1
    if (index(v, "}") > 0) needs_quote = 1
    if (index(v, "|") > 0) needs_quote = 1
    if (index(v, ">") > 0) needs_quote = 1
    if (index(v, "\"") > 0) needs_quote = 1
    if (index(v, "\n") > 0) needs_quote = 1
    if (index(v, "\t") > 0) needs_quote = 1
    if (index(v, "\r") > 0) needs_quote = 1
    if (needs_quote) {
        out = ""
        for (i = 1; i <= length(v); i++) {
            c = substr(v, i, 1)
            if (c == "\\") out = out "\\\\"
            else if (c == "\"") out = out "\\\""
            else if (c == "\n") out = out "\\n"
            else if (c == "\t") out = out "\\t"
            else if (c == "\r") out = out "\\r"
            else out = out c
        }
        return "\"" out "\""
    }
    return v
}
function begin_target(line,    t,key) {
    t = line
    if (t ~ /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/) {
        sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "", t)
        sub(/[[:space:]]+#.*$/, "", t)
        t = trim(unquote(t))
        if (t == block_id) { block_kind = "id"; block_indent = leading_spaces(line); field_indent = block_indent + 2; return 1 }
    }
    t = line
    if (t ~ /^[[:space:]]*-[[:space:]]*cmd_id:[[:space:]]*/) {
        sub(/^[[:space:]]*-[[:space:]]*cmd_id:[[:space:]]*/, "", t)
        sub(/[[:space:]]+#.*$/, "", t)
        t = trim(unquote(t))
        if (t == block_id) { block_kind = "id"; block_indent = leading_spaces(line); field_indent = block_indent + 2; return 1 }
    }
    t = line; sub(/[[:space:]]+#.*$/, "", t)
    if (t ~ /^[[:space:]]*[A-Za-z0-9_.-]+:[[:space:]]*$/) {
        key = t; sub(/^[[:space:]]*/, "", key); sub(/:[[:space:]]*$/, "", key)
        if (key == block_id) { block_kind = "map"; block_indent = leading_spaces(line); field_indent = block_indent + 2; return 1 }
    }
    return 0
}
function is_boundary(line,    indent,t) {
    if (block_kind == "id") {
        if (line ~ /^[[:space:]]*-[[:space:]]*(id|cmd_id):[[:space:]]*/) { indent = leading_spaces(line); if (indent <= block_indent) return 1 }
        return 0
    }
    t = trim(line)
    if (t == "" || t ~ /^#/) return 0
    indent = leading_spaces(line)
    if (indent <= block_indent) return 1
    return 0
}
function flush_block(    i,line,indent_str,j,fre,replaced_count) {
    indent_str = make_indent(field_indent)
    replaced_count = 0
    skip_replaced_continuation = 0
    prev_closed_quoted_scalar = 0
    for (i = 1; i <= block_len; i++) {
        line = block_lines[i]
        line_indent = leading_spaces(line)
        line_trimmed = trim(line)
        if (skip_replaced_continuation) {
            if (line_trimmed == "") {
                continue
            }
            if (line_indent > field_indent || (line_indent == field_indent && line_trimmed ~ /^-[[:space:]]/)) {
                continue
            }
            skip_replaced_continuation = 0
        }
        if (prev_closed_quoted_scalar && line_indent > field_indent && line_trimmed != "" && line_trimmed !~ /^#/ && line_trimmed !~ /^-/) {
            continue
        }
        if (i > 1) {
            for (j = 1; j <= nf; j++) {
                if (!replaced[j]) {
                    fre = "^" indent_str regex_escape(farr[j]) ":[[:space:]]*"
                    if (line ~ fre) {
                        print indent_str farr[j] ": " yaml_safe(varr[j])
                        replaced[j] = 1
                        replaced_count++
                        skip_replaced_continuation = 1
                        line = ""
                        break
                    }
                }
            }
        }
        if (line != "") {
            print line
            if (line_indent == field_indent) {
                prev_closed_quoted_scalar = is_closed_quoted_inline_scalar(line)
            }
        }
    }
    for (j = 1; j <= nf; j++) {
        if (!replaced[j]) {
            print indent_str farr[j] ": " yaml_safe(varr[j])
        }
    }
    delete block_lines; block_len = 0
}
BEGIN {
    in_block = 0; block_found = 0; block_done = 0; block_len = 0
    nf = split(fields_str, farr, sep)
    split(values_str, varr, sep)
    for (i = 1; i <= nf; i++) replaced[i] = 0
}
{
    if (!in_block) {
        if (!block_done && begin_target($0)) {
            in_block = 1; block_found = 1; block_len = 1; block_lines[1] = $0; next
        }
        print; next
    }
    if (is_boundary($0)) {
        flush_block(); in_block = 0; block_done = 1; print $0; next
    }
    block_len++; block_lines[block_len] = $0
}
END {
    if (in_block) { flush_block(); block_done = 1 }
    if (!block_found) exit 2
}
' "$yaml_file" > "$tmp_file"
        local rc=$?

        if [ "$rc" -ne 0 ]; then
            rm -f "$tmp_file"
            echo "FATAL: yaml_field_set_batch: awk failed (rc=$rc) for $yaml_file" >&2
            return 1
        fi

        # 公開前にYAML構文を検証する。不正なら旧ファイルは一切変更せず失敗する(fail-closed)。
        if ! _yaml_field_set_validate_parseable "$tmp_file" 2>&1; then
            rm -f "$tmp_file"
            echo "FATAL: yaml_field_set_batch: generated content failed YAML validation, original file kept unchanged: $yaml_file" >&2
            return 1
        fi

        if ! mv "$tmp_file" "$yaml_file"; then
            rm -f "$tmp_file"
            echo "FATAL: yaml_field_set_batch: atomic replace failed: $yaml_file" >&2
            return 1
        fi

        # Post-write verification for all fields: YAML表現文字列ではなく
        # yaml.safe_load後のscalar同士で比較する(_yaml_field_set_verify_parsed)。
        local _vf _va _verify_err
        for _arg in "$@"; do
            _vf="${_arg%%=*}"
            _va="${_arg#*=}"
            if [ -z "$_vf" ]; then continue; fi
            # dotted pathは構造レーンが候補上で検証済み(awkレーンには存在しない)。
            if [[ "$_vf" == *.* ]]; then continue; fi
            if ! _verify_err="$(_yaml_field_set_verify_parsed "$yaml_file" "$block_id" "$_vf" "$_va" "0" 2>&1 1>/dev/null)"; then
                echo "FATAL: yaml_field_set_batch: mismatch ${block_id}.${_vf} ($_verify_err)" >&2
                return 1
            fi
        done
    } 200>"$lock_file"
}

# Return success only when exactly one fresh active task owns rel_path and the
# target is a dirty worktree blob different from its deploy-time baseline.
active_context_defer_allowed() {
    local root="$1" rel_path="$2"
    ACTIVE_CONTEXT_ROOT="$root" ACTIVE_CONTEXT_REL_PATH="$rel_path" \
    ACTIVE_CONTEXT_DEFER_LEASE_SECONDS="${ACTIVE_CONTEXT_DEFER_LEASE_SECONDS:-1200}" \
    ACTIVE_CONTEXT_CLOCK_SKEW_SECONDS="${ACTIVE_CONTEXT_CLOCK_SKEW_SECONDS:-5}" python3 - <<'PY'
import datetime as dt, glob, hashlib, os, pathlib, subprocess, sys, yaml
root=pathlib.Path(os.environ['ACTIVE_CONTEXT_ROOT']).resolve(); rel=os.environ['ACTIVE_CONTEXT_REL_PATH']
owners=[]
for name in glob.glob(str(root/'queue/tasks/*.yaml')):
    try: task=(yaml.safe_load(open(name, encoding='utf-8')) or {}).get('task', {})
    except Exception: sys.exit(1)
    if not isinstance(task, dict): sys.exit(1)
    paths=[]
    for value in (task.get('target_path'), task.get('planned_paths'), (task.get('commit_contract') or {}).get('planned_paths')):
        paths += value if isinstance(value,list) else [value] if isinstance(value,str) else []
    if rel in paths and task.get('status') in ('acknowledged','in_progress'): owners.append(task)
if len(owners)!=1: sys.exit(1)
t=owners[0]; baseline=t.get('target_path_worktree_blob_at_deploy','')
if not isinstance(baseline,str) or len(baseline)!=40: sys.exit(1)
target=root/rel
if not target.is_file(): sys.exit(1)
data=target.read_bytes(); current=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
if current==baseline: sys.exit(1)
dirty=subprocess.run(['git','-C',str(root),'status','--porcelain','--',rel],capture_output=True,text=True).stdout.strip()
if not dirty: sys.exit(1)
try:
    stamp=dt.datetime.fromisoformat(str(t['progress_updated_at']).replace('Z','+00:00'))
    if stamp.tzinfo is None: raise ValueError
    now_raw=os.environ.get('ACTIVE_CONTEXT_NOW','')
    now=(dt.datetime.fromisoformat(now_raw.replace('Z','+00:00')) if now_raw else dt.datetime.now(dt.timezone.utc))
    if now.tzinfo is None: raise ValueError
    age=(now.astimezone(dt.timezone.utc)-stamp.astimezone(dt.timezone.utc)).total_seconds()
except Exception: sys.exit(1)
lease=float(os.environ['ACTIVE_CONTEXT_DEFER_LEASE_SECONDS']); skew=float(os.environ['ACTIVE_CONTEXT_CLOCK_SKEW_SECONDS'])
if age < -skew or age > lease: sys.exit(1)
print(t.get('task_id') or t.get('parent_cmd') or 'active-owner')
PY
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    yaml_field_set "$@"
fi
