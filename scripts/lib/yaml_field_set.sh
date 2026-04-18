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

# Inline lock_path helper to avoid sourcing another file on the hot path.
lock_path() {
    local file_path="$1"
    case "$file_path" in
        /mnt/c/*|/mnt/d/*)
            local hash
            hash=$(printf '%s' "$file_path" | md5sum | cut -c1-16)
            printf '/tmp/shogun_lock_%s.lock' "$hash"
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

_yaml_field_set_normalize() {
    local s
    s="$(_yaml_field_set_trim "$1")"
    s="$(_yaml_field_set_unquote "$s")"
    printf '%s' "$(_yaml_field_set_trim "$s")"
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
    if (needs_quote) {
        out = ""
        for (i = 1; i <= length(v); i++) {
            c = substr(v, i, 1)
            if (c == "\"") { out = out "\\" c }
            else { out = out c }
        }
        return "\"" out "\""
    }
    return v
}
BEGIN { replaced = 0; has_fields = 0 }
{
    field_re = "^" regex_escape(field) ":[[:space:]]*"
    if (!replaced && $0 ~ field_re) {
        print field ": " yaml_safe(new_value)
        replaced = 1
        has_fields = 1
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
        next
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
            if (c == "\"") { out = out "\\" c }
            else { out = out c }
        }
        return "\"" out "\""
    }
    return v
}
function flush_block(    i,line,indent_str,field_re,replaced) {
    indent_str = make_indent(field_indent)
    field_re = "^" indent_str regex_escape(field) ":[[:space:]]*"
    replaced = 0

    for (i = 1; i <= block_len; i++) {
        line = block_lines[i]
        if (i > 1 && !replaced && line ~ field_re) {
            print indent_str field ": " yaml_safe(new_value)
            replaced = 1
        } else {
            print line
        }
    }

    if (!replaced) {
        print indent_str field ": " yaml_safe(new_value)
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
    lock_file="$(lock_path "$yaml_file")"
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

        local use_root=0
        local rc=2

        if [ "$block_id" = "root" ]; then
            _yaml_field_set_apply_root "$yaml_file" "$tmp_file" "$field" "$new_value"
            rc=$?
            if [ "$rc" -eq 0 ]; then
                use_root=1
            fi
        else
            _yaml_field_set_apply_map_scalar "$yaml_file" "$tmp_file" "$block_id" "$field" "$new_value"
            rc=$?
            if [ "$rc" -eq 2 ]; then
                _yaml_field_set_apply "$yaml_file" "$tmp_file" "$block_id" "$field" "$new_value"
                rc=$?
            fi
        fi

        if [ "$rc" -eq 2 ]; then
            # Fallback: block_id not found → try root-level field update (flat YAML support)
            _yaml_field_set_apply_root "$yaml_file" "$tmp_file" "$field" "$new_value"
            rc=$?
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

        if ! mv "$tmp_file" "$yaml_file"; then
            rm -f "$tmp_file"
            echo "FATAL: yaml_field_set: atomic replace failed: $yaml_file" >&2
            return 1
        fi

        local actual normalized_actual normalized_expected
        if [ "$use_root" -eq 1 ]; then
            if ! actual="$(_yaml_field_get_root "$yaml_file" "$field")"; then
                echo "FATAL: yaml_field_set: post-write readback failed for root.${field} in $yaml_file" >&2
                return 1
            fi
        elif ! actual="$(_yaml_field_get_in_block "$yaml_file" "$block_id" "$field")"; then
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

    # Build fields/values arrays as pipe-delimited strings for awk
    local _fields="" _values="" _count=0
    local _arg _f _v
    for _arg in "$@"; do
        _f="${_arg%%=*}"
        _v="${_arg#*=}"
        if [ -z "$_f" ]; then continue; fi
        if [ "$_count" -gt 0 ]; then
            _fields="${_fields}|${_f}"
            _values="${_values}|${_v}"
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
            -v fields_str="$_fields" \
            -v values_str="$_values" '
function trim(s) { sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
function unquote(s) {
    if (length(s) >= 2) {
        if (substr(s,1,1) == "\"" && substr(s,length(s),1) == "\"") {
            s = substr(s, 2, length(s)-2); gsub(/\\"/, "\"", s)
        } else if (substr(s,1,1) == "\047" && substr(s,length(s),1) == "\047") {
            s = substr(s, 2, length(s)-2)
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
function yaml_safe(v,    out,i,c,nq) {
    nq = 0
    if (index(v, ":") > 0) nq = 1
    if (index(v, "#") > 0) nq = 1
    if (index(v, "[") > 0) nq = 1
    if (index(v, "]") > 0) nq = 1
    if (index(v, "{") > 0) nq = 1
    if (index(v, "}") > 0) nq = 1
    if (nq) {
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
function begin_target(line,    t,key) {
    t = line
    if (t ~ /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/) {
        sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "", t)
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
        if (line ~ /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/) { indent = leading_spaces(line); if (indent <= block_indent) return 1 }
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
    for (i = 1; i <= block_len; i++) {
        line = block_lines[i]
        if (i > 1) {
            for (j = 1; j <= nf; j++) {
                if (!replaced[j]) {
                    fre = "^" indent_str regex_escape(farr[j]) ":[[:space:]]*"
                    if (line ~ fre) {
                        print indent_str farr[j] ": " yaml_safe(varr[j])
                        replaced[j] = 1
                        replaced_count++
                        line = ""
                        break
                    }
                }
            }
        }
        if (line != "") print line
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
    nf = split(fields_str, farr, "|")
    split(values_str, varr, "|")
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

        if ! mv "$tmp_file" "$yaml_file"; then
            rm -f "$tmp_file"
            echo "FATAL: yaml_field_set_batch: atomic replace failed: $yaml_file" >&2
            return 1
        fi

        # Post-write verification for all fields
        local _vf _va _norm_a _norm_e _idx=0
        for _arg in "$@"; do
            _vf="${_arg%%=*}"
            _va="${_arg#*=}"
            if [ -z "$_vf" ]; then continue; fi
            local actual
            if ! actual="$(_yaml_field_get_in_block "$yaml_file" "$block_id" "$_vf")"; then
                echo "FATAL: yaml_field_set_batch: verify failed for ${block_id}.${_vf}" >&2
                return 1
            fi
            _norm_a="$(_yaml_field_set_normalize "$actual")"
            _norm_e="$(_yaml_field_set_normalize "$_va")"
            if [ "$_norm_a" != "$_norm_e" ]; then
                echo "FATAL: yaml_field_set_batch: mismatch ${block_id}.${_vf} (expected='$_norm_e', actual='$_norm_a')" >&2
                return 1
            fi
        done
    } 200>"$lock_file"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    yaml_field_set "$@"
fi
