#!/usr/bin/env bash
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
            \"*\") s="${s#\"}"; s="${s%\"}" ;;
            \'*\') s="${s#\'}"; s="${s%\'}" ;;
        esac
    fi
    printf '%s' "$s"
}

_yaml_field_set_normalize() {
    local s
    s="$(_yaml_field_set_trim "$1")"
    s="$(_yaml_field_set_unquote "$s")"
    printf '%s' "$(_yaml_field_set_trim "$s")"
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
        if ((substr(s,1,1) == "\"" && substr(s,length(s),1) == "\"") ||
            (substr(s,1,1) == "'"'"'" && substr(s,length(s),1) == "'"'"'")) {
            s = substr(s, 2, length(s)-2)
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
    if (block_kind == "id") {
        if (line ~ /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/) {
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
function flush_block(    i,line,indent_str,field_re,replaced) {
    indent_str = make_indent(field_indent)
    field_re = "^" indent_str regex_escape(field) ":[[:space:]]*"
    replaced = 0

    for (i = 1; i <= block_len; i++) {
        line = block_lines[i]
        if (i > 1 && !replaced && line ~ field_re) {
            print indent_str field ": " new_value
            replaced = 1
        } else {
            print line
        }
    }

    if (!replaced) {
        print indent_str field ": " new_value
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
        if ((substr(s,1,1) == "\"" && substr(s,length(s),1) == "\"") ||
            (substr(s,1,1) == "'"'"'" && substr(s,length(s),1) == "'"'"'")) {
            s = substr(s, 2, length(s)-2)
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
    if (block_kind == "id") {
        if (line ~ /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/) {
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
        sub(/[[:space:]]+#.*$/, "", value)
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

    local lock_file="${yaml_file}.lock"
    local tmp_file
    tmp_file="$(mktemp "${yaml_file}.tmp.XXXXXX")" || {
        echo "FATAL: yaml_field_set: failed to create temp file for $yaml_file" >&2
        return 1
    }

    {
        flock -w 10 200 || {
            rm -f "$tmp_file"
            echo "FATAL: yaml_field_set: flock timeout for $yaml_file" >&2
            return 1
        }

        _yaml_field_set_apply "$yaml_file" "$tmp_file" "$block_id" "$field" "$new_value"
        local rc=$?
        if [ "$rc" -ne 0 ]; then
            rm -f "$tmp_file"
            if [ "$rc" -eq 2 ]; then
                echo "FATAL: yaml_field_set: block_id not found: $block_id ($yaml_file)" >&2
            else
                echo "FATAL: yaml_field_set: failed to rewrite file: $yaml_file" >&2
            fi
            return 1
        fi

        if ! mv "$tmp_file" "$yaml_file"; then
            rm -f "$tmp_file"
            echo "FATAL: yaml_field_set: atomic replace failed: $yaml_file" >&2
            return 1
        fi

        local actual normalized_actual normalized_expected
        if ! actual="$(_yaml_field_get_in_block "$yaml_file" "$block_id" "$field")"; then
            echo "FATAL: yaml_field_set: post-write readback failed for ${block_id}.${field} in $yaml_file" >&2
            return 1
        fi

        normalized_actual="$(_yaml_field_set_normalize "$actual")"
        normalized_expected="$(_yaml_field_set_normalize "$new_value")"
        if [ "$normalized_actual" != "$normalized_expected" ]; then
            echo "FATAL: yaml_field_set: post-write verification mismatch for ${block_id}.${field} in $yaml_file (expected='$normalized_expected', actual='$normalized_actual')" >&2
            return 1
        fi
    } 200>"$lock_file"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    yaml_field_set "$@"
fi
