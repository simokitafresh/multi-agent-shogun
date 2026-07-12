#!/usr/bin/env bash
# semantic-links: [[YAML安全書込み]]
# yaml_field_set.sh - Safe YAML field update helper with post-write verification.
#
# Usage:
#   bash scripts/lib/yaml_field_set.sh <yaml_file> <block_id> <field> <new_value>
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

# Inline lock_path helper to avoid sourcing another file on the hot path.
lock_path() {
    local file_path="$1"
    case "$file_path" in
        /mnt/c/*|/mnt/d/*)
            # WSL2最適化: md5sum+cut subprocess(~10ms)を純bashハッシュ(~0ms)に置換
            local sanitized="${file_path//[\/: .#*?!]/_}"
            printf '/tmp/shogun_lock_%s.lock' "${sanitized: -48}"
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
        if (($0 ~ /^[[:space:]]/ || $0 ~ /^-[[:space:]]/) && $0 !~ /^[A-Za-z0-9_.-]+:/) {
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
        if (rhs == "" || rhs ~ /^#/) {
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
    prev_inline_scalar = 0
    block_indent = -1
    field_indent = -1
    flow_cont = 0
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
        if (indent > field_indent) next
        skip_replaced_continuation = 0
    }

    if (prev_inline_scalar && indent > field_indent && trimmed != "" && trimmed !~ /^#/ && trimmed !~ /^-/) {
        if (!flow_cont) { next }
        # YAML double-quoted flow scalar continuation — detect closing quote
        if (trimmed ~ /[^\\]"$/ || trimmed == "\"") flow_cont = 0
    }

    field_re = "^" make_indent(field_indent) regex_escape(field) ":[[:space:]]*"
    if (!replaced && $0 ~ field_re) {
        print make_indent(field_indent) field ": " yaml_safe(new_value)
        replaced = 1
        skip_replaced_continuation = 1
        prev_inline_scalar = 1
        next
    }

    if (indent == field_indent) {
        prev_inline_scalar = is_inline_scalar_field($0)
        if (prev_inline_scalar && $0 ~ /\\$/) {
            flow_cont = 1
        } else {
            flow_cont = 0
        }
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
            if (line_trimmed == "" || line_indent > field_indent) {
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

yaml_field_set() {
    local yaml_file="$1"
    local block_id="$2"
    local field="$3"
    local new_value="$4"

    if [ "$#" -lt 4 ]; then
        echo "Usage: yaml_field_set <yaml_file> <block_id> <field> <new_value>" >&2
        return 1
    fi

    if [ ! -f "$yaml_file" ]; then
        echo "FATAL: yaml_field_set: file not found: $yaml_file" >&2
        return 1
    fi

    local lock_file
    case "$yaml_file" in
        /mnt/c/*|/mnt/d/*)
            local sanitized="${yaml_file//[\/: .#*?!]/_}"
            lock_file="/tmp/shogun_lock_${sanitized: -48}.lock"
            ;;
        *)
            lock_file="${yaml_file}.lock"
            ;;
    esac
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
            rc=0; _yaml_field_set_apply_map_scalar "$yaml_file" "$tmp_file" "$block_id" "$field" "$yfs_safe_value" || rc=$?
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

        # 公開前にYAML構文を検証する。不正なら旧ファイルは一切変更せず失敗する(fail-closed)。
        if ! _yaml_field_set_validate_parseable "$tmp_file" 2>&1; then
            rm -f "$tmp_file"
            echo "FATAL: yaml_field_set: generated content failed YAML validation, original file kept unchanged: $yaml_file" >&2
            return 1
        fi

        # 同一ファイルシステム上のrename(mv)はatomicであり、読み手が
        # truncate-write間の不完全な状態を観測することがない。
        if ! mv "$tmp_file" "$yaml_file"; then
            rm -f "$tmp_file"
            echo "FATAL: yaml_field_set: atomic publish (mv) failed: $yaml_file" >&2
            return 1
        fi

        # post-write比較はYAML表現文字列(awk単一物理行の生テキスト)ではなく
        # yaml.safe_load後のscalar同士で行う(_yaml_field_set_verify_parsed)。
        local _verify_err
        if ! _verify_err="$(_yaml_field_set_verify_parsed "$yaml_file" "$block_id" "$field" "$new_value" "$use_root" 2>&1 1>/dev/null)"; then
            echo "FATAL: yaml_field_set: post-write verification mismatch for ${block_id}.${field} in $yaml_file ($_verify_err)" >&2
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
    case "$yaml_file" in
        /mnt/c/*|/mnt/d/*)
            local sanitized="${yaml_file//[\/: .#*?!]/_}"
            lock_file="/tmp/shogun_lock_${sanitized: -48}.lock"
            ;;
        *)
            lock_file="${yaml_file}.lock"
            ;;
    esac
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
function yaml_safe(v,    out,i,c,needs_quote) {
    needs_quote = 0
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
    prev_inline_scalar = 0
    for (i = 1; i <= block_len; i++) {
        line = block_lines[i]
        line_indent = leading_spaces(line)
        line_trimmed = trim(line)
        if (skip_replaced_continuation) {
            if (line_trimmed == "") {
                continue
            }
            if (line_indent > field_indent) {
                continue
            }
            skip_replaced_continuation = 0
        }
        if (prev_inline_scalar && line_indent > field_indent && line_trimmed != "" && line_trimmed !~ /^#/ && line_trimmed !~ /^-/) {
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
                        prev_inline_scalar = 1
                        line = ""
                        break
                    }
                }
            }
        }
        if (line != "") {
            print line
            if (line_indent == field_indent) {
                prev_inline_scalar = is_inline_scalar_field(line)
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
            if ! _verify_err="$(_yaml_field_set_verify_parsed "$yaml_file" "$block_id" "$_vf" "$_va" "0" 2>&1 1>/dev/null)"; then
                echo "FATAL: yaml_field_set_batch: mismatch ${block_id}.${_vf} ($_verify_err)" >&2
                return 1
            fi
        done
    } 200>"$lock_file"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    yaml_field_set "$@"
fi
