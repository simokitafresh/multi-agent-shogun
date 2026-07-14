#!/bin/bash
# inbox_archive.sh — read:trueメッセージをアーカイブに退避
# Usage: bash scripts/inbox_archive.sh <agent_id>
# Example: bash scripts/inbox_archive.sh karo

set -e

_ia_self="${BASH_SOURCE[0]}"
[[ "$_ia_self" != /* ]] && _ia_self="$PWD/$_ia_self"
SCRIPT_DIR="${_ia_self%/scripts/inbox_archive.sh}"
unset _ia_self
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/lock_path.sh" 2>/dev/null \
    || lock_path() { printf '/tmp/shogun_lock_%s.lock' "$(printf '%s' "$1" | md5sum | cut -c1-16)"; }
AGENT="$1"

if [ -z "$AGENT" ]; then
    echo "Usage: inbox_archive.sh <agent_id>" >&2
    exit 1
fi

INBOX="$SCRIPT_DIR/queue/inbox/${AGENT}.yaml"
LOCKFILE="$(lock_path "$INBOX")"

if [ ! -f "$INBOX" ]; then
    echo "[inbox_archive] No inbox file for $AGENT" >&2
    exit 0
fi

ARCHIVE_DIR="$SCRIPT_DIR/archive/inbox"
mkdir -p "$ARCHIVE_DIR"

printf -v DATE_STAMP '%(%Y%m%d)T' -1
ARCHIVE_FILE="$ARCHIVE_DIR/${AGENT}_${DATE_STAMP}.yaml"

inbox_archive_fast_path() {
    local inbox_path="$1"
    local archive_path="$2"
    local agent_id="$3"

    # Complex YAML remains on the existing PyYAML path. The hot inbox shape is a
    # flat list of single-line scalar message fields.
    # Complex YAML detection is integrated into awk (exit 2) to avoid a separate
    # grep subprocess reading the file a second time.

    local inbox_dir archive_dir _ia_tmpdir read_tmp unread_tmp stats_tmp inbox_tmp archive_tmp
    inbox_dir="${inbox_path%/*}"
    archive_dir="${archive_path%/*}"
    # One mktemp -d replaces three separate mktemp subprocesses
    _ia_tmpdir=$(mktemp -d /tmp/.ia_XXXXXX)
    read_tmp="$_ia_tmpdir/r"
    unread_tmp="$_ia_tmpdir/u"
    stats_tmp="$_ia_tmpdir/s"

    if ! awk -v read_out="$read_tmp" -v unread_out="$unread_tmp" -v stats_out="$stats_tmp" '
# Detect complex YAML in a single pass — replaces grep -Eq pre-scan
/^[[:space:]][[:space:]][[:space:]][[:space:]][^[:space:]]/ {
    if (block_key != "") {
        line = $0
        sub(/^[[:space:]][[:space:]][[:space:]][[:space:]]/, "", line)
        values[block_key] = values[block_key] (block_lines++ ? "\n" : "") line
        next
    }
    exit 2
}
function trim(v) {
    gsub(/^[ \t\r\n]+/, "", v)
    gsub(/[ \t\r\n]+$/, "", v)
    return v
}
function unquote(v,    q) {
    v = trim(v)
    if (length(v) >= 2) {
        q = substr(v, 1, 1)
        if (q == "'"'"'" && substr(v, length(v), 1) == "'"'"'") {
            v = substr(v, 2, length(v) - 2)
            gsub(/'"'"''"'"'/, "'"'"'", v)
        } else if (q == "\"" && substr(v, length(v), 1) == "\"") {
            v = substr(v, 2, length(v) - 2)
            gsub(/\\"/, "\"", v)
            gsub(/\\\\/, "\\", v)
        }
    }
    return v
}
function sv(v,    out,i,c,sq) {
    v = unquote(v)
    if (v == "true" || v == "false") return v
    sq = sprintf("%c", 39)
    out = sq
    for (i = 1; i <= length(v); i++) {
        c = substr(v, i, 1)
        if (c == sq) out = out sq sq
        else out = out c
    }
    return out sq
}
function reset_msg(    i) {
    delete values
    delete seen
    delete extra_keys
    extra_count = 0
    in_msg = 0
    read_value = "false"
    block_key = ""
    block_lines = 0
}
function set_field(k, v,    known) {
    if (k == "") return
    values[k] = v
    if (v ~ /^[|>][+-]?[0-9]*$/) {
        if (v !~ /^\|-/) exit 2
        values[k] = ""
        block_key = k
        block_lines = 0
    } else {
        block_key = ""
    }
    seen[k] = 1
    if (k == "read") read_value = unquote(v)
    known = (k == "content" || k == "from" || k == "id" || k == "read" || k == "timestamp" || k == "type")
    if (!known) extra_keys[++extra_count] = k
}
function emit_field(out, prefix, k,    lines,n,i) {
    if (index(values[k], "\n")) {
        print prefix k ": |-" >> out
        n = split(values[k], lines, "\n")
        for (i = 1; i <= n; i++) print "    " lines[i] >> out
    } else {
        print prefix k ": " sv(values[k]) >> out
    }
}
function emit_msg(out,    keys,nkeys,i,prefix,k) {
    if (!in_msg) return
    split("content from id read timestamp type", keys, " ")
    nkeys = 6
    prefix = "- "
    for (i = 1; i <= nkeys; i++) {
        k = keys[i]
        if (seen[k]) {
            emit_field(out, prefix, k)
            prefix = "  "
        }
    }
    for (i = 1; i <= extra_count; i++) {
        k = extra_keys[i]
        if (seen[k]) {
            emit_field(out, prefix, k)
            prefix = "  "
        }
    }
}
function flush_msg() {
    if (!in_msg) return
    total_count++
    if (read_value == "true") {
        read_count++
        emit_msg(read_out)
    } else {
        unread_count++
        emit_msg(unread_out)
    }
}
BEGIN {
    total_count = read_count = unread_count = 0
    reset_msg()
}
/^[[:space:]]*messages:[[:space:]]*\[\][[:space:]]*$/ { empty_seen = 1; next }
/^[[:space:]]*messages:[[:space:]]*$/ { next }
/^[[:space:]]*-[[:space:]]*/ {
    flush_msg()
    reset_msg()
    in_msg = 1
    line = $0
    sub(/^[[:space:]]*-[[:space:]]*/, "", line)
    key = line
    sub(/:.*/, "", key)
    val = line
    sub(/^[^:]*:[[:space:]]*/, "", val)
    set_field(trim(key), trim(val))
    next
}
/^[[:space:]]+[A-Za-z0-9_.-]+:[[:space:]]*/ {
    if (!in_msg) next
    line = $0
    sub(/^[[:space:]]+/, "", line)
    key = line
    sub(/:.*/, "", key)
    val = line
    sub(/^[^:]*:[[:space:]]*/, "", val)
    set_field(trim(key), trim(val))
    next
}
END {
    flush_msg()
    print total_count, read_count, unread_count > stats_out
}
' "$inbox_path"; then
        rm -rf "$_ia_tmpdir"
        return 1
    fi

    local total_count read_count unread_count
    read -r total_count read_count unread_count < "$stats_tmp" || {
        rm -rf "$_ia_tmpdir"
        return 1
    }

    echo "[inbox_archive] ${agent_id}: total=${total_count}, read=${read_count}, unread=${unread_count}"

    if [ "${total_count:-0}" -eq 0 ]; then
        rm -rf "$_ia_tmpdir"
        echo "[inbox_archive] No messages in inbox"
        return 0
    fi
    if [ "${read_count:-0}" -eq 0 ]; then
        rm -rf "$_ia_tmpdir"
        echo "[inbox_archive] No read messages to archive"
        return 0
    fi
    if [ "${unread_count:-0}" -gt 0 ]; then
        echo "[inbox_archive] NOTE: ${unread_count} unread messages will be preserved"
    fi

    if [ -f "$archive_path" ]; then
        cat "$read_tmp" >> "$archive_path"
    else
        archive_tmp=$(mktemp "$archive_dir/.ia_archive_XXXXXX.tmp")
        {
            printf 'messages:\n'
            cat "$read_tmp"
        } > "$archive_tmp"
        mv "$archive_tmp" "$archive_path"
    fi

    inbox_tmp=$(mktemp "$inbox_dir/.ia_inbox_XXXXXX.tmp")
    if [ "${unread_count:-0}" -eq 0 ]; then
        printf 'messages: []\n' > "$inbox_tmp"
    else
        {
            printf 'messages:\n'
            cat "$unread_tmp"
        } > "$inbox_tmp"
    fi
    mv "$inbox_tmp" "$inbox_path"

    rm -rf "$_ia_tmpdir"
    echo "[inbox_archive] Archived ${read_count} messages to ${archive_path}"
    return 0
}

# Atomic archive with flock (same lock as inbox_write.sh)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 5 200 || exit 1

        if inbox_archive_fast_path "$INBOX" "$ARCHIVE_FILE" "$AGENT"; then
            exit 0
        fi

        INBOX_PATH="$INBOX" ARCHIVE_PATH="$ARCHIVE_FILE" AGENT_ID="$AGENT" python3 -c "
import yaml, sys, os, tempfile

inbox_path = os.environ['INBOX_PATH']
archive_path = os.environ['ARCHIVE_PATH']
agent_id = os.environ['AGENT_ID']

# Load inbox
with open(inbox_path, encoding='utf-8') as f:
    data = yaml.safe_load(f)

if not data or not data.get('messages'):
    print('[inbox_archive] No messages in inbox')
    sys.exit(0)

msgs = data['messages']
unread = [m for m in msgs if not m.get('read', False)]
read_msgs = [m for m in msgs if m.get('read', False)]

print(f'[inbox_archive] {agent_id}: total={len(msgs)}, read={len(read_msgs)}, unread={len(unread)}')

if not read_msgs:
    print('[inbox_archive] No read messages to archive')
    sys.exit(0)

if unread:
    print(f'[inbox_archive] NOTE: {len(unread)} unread messages will be preserved')

# yaml.dump禁止(CLAUDE.md): 手動YAML構築でデータ消失を防止
def _sv(v):
    if isinstance(v, bool): return str(v).lower()
    s = str(v)
    if '\n' in s:
        return '|-\n' + '\n'.join('    ' + ln for ln in s.split('\n'))
    sq = chr(39)
    return sq + s.replace(sq, sq+sq) + sq

def _write_msg_entries(f, messages):
    for m in messages:
        keys = ['content', 'from', 'id', 'read', 'timestamp', 'type']
        extra = sorted(k for k in m if k not in keys)
        first = True
        for k in keys + extra:
            if k not in m: continue
            p = '- ' if first else '  '
            first = False
            f.write(f'{p}{k}: {_sv(m[k])}\n')

def _write_messages(f, messages):
    if not messages:
        f.write('messages: []\n')
    else:
        f.write('messages:\n')
        _write_msg_entries(f, messages)

# Write archive (append-only: avoid loading existing archive for O(k) performance)
if os.path.exists(archive_path):
    # Existing archive: append entries directly (O(k), no full reload)
    with open(archive_path, 'a', encoding='utf-8') as f:
        _write_msg_entries(f, read_msgs)
else:
    # New archive file: create atomically with header
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(archive_path), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
            f.write('messages:\n')
            _write_msg_entries(f, read_msgs)
        os.replace(tmp_path, archive_path)
    except Exception:
        os.unlink(tmp_path)
        raise

# Rewrite inbox with unread only (atomic)
new_data = {'messages': unread} if unread else {'messages': []}
tmp_fd2, tmp_path2 = tempfile.mkstemp(dir=os.path.dirname(inbox_path), suffix='.tmp')
try:
    with os.fdopen(tmp_fd2, 'w', encoding='utf-8') as f:
        _write_messages(f, new_data['messages'])
    os.replace(tmp_path2, inbox_path)
except Exception:
    os.unlink(tmp_path2)
    raise

print(f'[inbox_archive] Archived {len(read_msgs)} messages to {archive_path}')
" || exit 1

    ) 200>"$LOCKFILE"; then
        exit 0
    else
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[inbox_archive] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[inbox_archive] Failed to acquire lock after $max_attempts attempts" >&2
            exit 1
        fi
    fi
done
