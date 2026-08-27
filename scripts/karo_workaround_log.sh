#!/usr/bin/env bash
# semantic-links: [[学習ループ]]
# karo_workaround_log.sh — 家老ワークアラウンド記録スクリプト
# Usage:
#   bash scripts/karo_workaround_log.sh <cmd_id> <ninja_name> "<issue>" "<fix>" [category] [missed_sg]
#   bash scripts/karo_workaround_log.sh --wa <cmd_id> <ninja_name> "<issue>" "<fix>" [category] [missed_sg] [environment_change]
#   bash scripts/karo_workaround_log.sh --resolve <cmd_id> <resolved_by_cmd>
#
# AC1(cmd_1211): カテゴリ別件数カウント。2件目WARN、3件目以上ALERT(ntfy+insight_write)
# AC2(cmd_1211): classify_category改善(report_yaml_format/file_disappearance/uncategorized)
# AC3(cmd_1211): resolved_by_cmdフィールド追加。resolved済みはALERTカウント除外
# AC(cmd_karo_hotfix_wa_root_signature_202607121225): categoryに加えroot_signature(発生段階×破れた
#   不変量)でN>=3を判定。異根WAの混入によるPD誤発火を防止。root_signature欠落の既存entryは
#   「${category}::general」fallbackへ非破壊的に集約する(新規entryの既定bucketと同一。挙動非破壊)

set -euo pipefail

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
SCRIPT_DIR="${_self%/*}"
REPO_ROOT="${SCRIPT_DIR%/*}"
unset _self
LOG_FILE="${KARO_WORKAROUND_LOG_FILE:-$REPO_ROOT/logs/karo_workarounds.yaml}"
# All writers of the shared ledger must derive the same lock from the target
# path.  A fixed legacy lock here raced with cmd_complete_gate's path-derived
# lock, allowing one atomic replace to erase the other's append.
# shellcheck source=scripts/lib/lock_path.sh
source "$REPO_ROOT/scripts/lib/lock_path.sh"
LOCK_FILE="${KARO_WORKAROUND_LOCK_FILE:-$(lock_path "$LOG_FILE")}"
DISABLE_ALERTS="${KARO_WORKAROUND_DISABLE_ALERTS:-false}"
BRAINWASH_CHECK="${KARO_WA_BRAINWASH_CHECK:-}"
# A workaround is the point where a reusable lesson is born.  Record that
# decision in the same locked append as the WA itself so startup-time counting
# cannot be the first place where the missing reflux is noticed.
LESSON_REQUIRED="${KARO_WA_LESSON_REQUIRED:-true}"
LESSON_REFERENCE="${KARO_WA_LESSON_REFERENCE:-}"

# shellcheck source=scripts/lib/known_ninjas.sh
source "$REPO_ROOT/scripts/lib/known_ninjas.sh"

# --- Resolve mode: close one exact workaround entry atomically ---
# The log hook deliberately rejects ad-hoc YAML writers.  Resolution therefore
# belongs to this same canonical, locked write boundary as workaround creation.
if [[ "${1:-}" == "--resolve" ]]; then
    if [[ $# -ne 3 ]]; then
        echo "Usage: bash scripts/karo_workaround_log.sh --resolve <cmd_id> <resolved_by_cmd>" >&2
        exit 1
    fi
    RESOLVE_CMD_ID="$2"
    RESOLVED_BY_CMD="$3"
    if [[ -z "${RESOLVE_CMD_ID//[[:space:]]/}" || -z "${RESOLVED_BY_CMD//[[:space:]]/}" ]]; then
        echo "[resolve] ERROR: cmd_id and resolved_by_cmd must be non-empty" >&2
        exit 1
    fi
    (
        flock -w 10 200 || { echo "[resolve] ERROR: lock timeout" >&2; exit 1; }
        python3 - "$LOG_FILE" "$RESOLVE_CMD_ID" "$RESOLVED_BY_CMD" <<'PY'
import os
import re
import sys
import tempfile

import yaml

path, target_cmd, resolution = sys.argv[1:]
with open(path, encoding="utf-8") as fh:
    lines = fh.read().splitlines(keepends=True)

entry_start = re.compile(r"^-\s+[A-Za-z_][A-Za-z0-9_]*:")
field = re.compile(r"^(\s*)([A-Za-z_][A-Za-z0-9_]*):\s*(.*?)(\r?\n?)$")


def scalar(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        value = value[1:-1]
    return value.strip()


starts = [index for index, line in enumerate(lines) if entry_start.match(line)]
starts.append(len(lines))
matches = []
for pos in range(len(starts) - 1):
    start, end = starts[pos], starts[pos + 1]
    fields = {}
    field_lines = {}
    for index in range(start, end):
        text = re.sub(r"^-\s+", "  ", lines[index], count=1) if index == start else lines[index]
        match = field.match(text)
        if not match:
            continue
        fields[match.group(2)] = scalar(match.group(3))
        field_lines[match.group(2)] = index
    if fields.get("cmd_id") == target_cmd or fields.get("cmd") == target_cmd:
        matches.append((start, end, fields, field_lines))

if len(matches) != 1:
    raise SystemExit(f"[resolve] ERROR: expected exactly one entry for {target_cmd}, found {len(matches)}")

start, end, fields, field_lines = matches[0]
current = fields.get("resolved_by_cmd", "")
if current and current != resolution:
    raise SystemExit(f"[resolve] ERROR: {target_cmd} already resolved by {current}")
if current == resolution:
    print(f"[resolve] unchanged=1 cmd_id={target_cmd} resolved_by_cmd={resolution}")
    raise SystemExit(0)

rendered = "'" + resolution.replace("'", "''") + "'"
if "resolved_by_cmd" in field_lines:
    index = field_lines["resolved_by_cmd"]
    match = field.match(lines[index])
    indent = match.group(1) if match else "  "
    newline = match.group(4) if match else "\n"
    lines[index] = f"{indent}resolved_by_cmd: {rendered}{newline}"
else:
    lines.insert(end, f"  resolved_by_cmd: {rendered}\n")

fd, candidate = tempfile.mkstemp(prefix=".karo_workarounds.resolve.", dir=os.path.dirname(path) or ".")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.writelines(lines)
    with open(candidate, encoding="utf-8") as fh:
        yaml.safe_load(fh)
    os.replace(candidate, path)
finally:
    if os.path.exists(candidate):
        os.unlink(candidate)

print(f"[resolve] updated=1 cmd_id={target_cmd} resolved_by_cmd={resolution}")
PY
    ) 200>"$LOCK_FILE"
    exit $?
fi

# --- Reflux backfill mode: classify every unresolved ledger entry atomically ---
# Usage: --backfill-reflux <resolution_cmd> <root_signature=lesson_id> [...]
# Automatic completion observations are dispositioned as not_applicable and
# resolved by their own cmd.  Every unresolved manual WA must match one of the
# explicit signature mappings; an incomplete inventory fails closed.
if [[ "${1:-}" == "--backfill-reflux" ]]; then
    shift
    [[ $# -ge 2 ]] || {
        echo "Usage: bash scripts/karo_workaround_log.sh --backfill-reflux <resolution_cmd> <root_signature=lesson_id> [...]" >&2
        exit 1
    }
    REFLUX_RESOLUTION_CMD="$1"
    shift
    (
        flock -w 10 200 || { echo "[backfill-reflux] ERROR: lock timeout" >&2; exit 1; }
        python3 - "$LOG_FILE" "$REFLUX_RESOLUTION_CMD" "$@" <<'PY'
import os, re, sys, tempfile, yaml

path, resolution, *mapping_args = sys.argv[1:]
mappings = {}
for item in mapping_args:
    signature, sep, lesson = item.partition("=")
    if not sep or not signature or not lesson:
        raise SystemExit(f"[backfill-reflux] ERROR: invalid mapping {item!r}")
    mappings[signature] = lesson

with open(path, encoding="utf-8") as fh:
    lines = fh.read().splitlines(keepends=True)

entry_re = re.compile(r"^-\s+[A-Za-z_][A-Za-z0-9_]*:")
field_re = re.compile(r"^\s*(?:-\s*)?([A-Za-z_][A-Za-z0-9_]*):\s*(.*?)\r?\n?$")
starts = [i for i, line in enumerate(lines) if entry_re.match(line)] + [len(lines)]
edits = []
counts = {"not_applicable": 0, "integrated_existing": 0}

def scalar(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
        value = value[1:-1]
    return value.strip()

def sq(value):
    return "'" + value.replace("'", "''") + "'"

for pos in range(len(starts) - 1):
    start, end = starts[pos], starts[pos + 1]
    fields, indexes = {}, {}
    for index in range(start, end):
        match = field_re.match(lines[index])
        if match:
            fields[match.group(1)] = scalar(match.group(2))
            indexes[match.group(1)] = index
    is_wa = fields.get("workaround") == "true"
    is_placeholder = (
        is_wa
        and fields.get("lesson_disposition") == "new_lesson_required"
        and not fields.get("lesson_reference")
    )
    if fields.get("resolved_by_cmd") and not is_placeholder:
        continue
    if "resolved_by_cmd" not in indexes:
        raise SystemExit(f"[backfill-reflux] ERROR: entry at line {start + 1} lacks resolved_by_cmd")
    if is_wa:
        signature = fields.get("root_signature") or f"legacy::{fields.get('category', 'uncategorized')}"
        if signature not in mappings:
            raise SystemExit(f"[backfill-reflux] ERROR: no lesson mapping for {signature}")
        disposition, reference, resolved = "integrated_existing", mappings[signature], resolution
    else:
        disposition, reference = "not_applicable", "not_applicable"
        resolved = fields.get("cmd_id") or fields.get("cmd") or resolution
    idx = indexes["resolved_by_cmd"]
    inserts = []
    replacements = {}
    if "lesson_required" not in fields:
        inserts.append("  lesson_required: false\n")
    if "lesson_disposition" in indexes:
        replacements[indexes["lesson_disposition"]] = f"  lesson_disposition: {disposition}\n"
    else:
        inserts.append(f"  lesson_disposition: {disposition}\n")
    if "lesson_reference" in indexes:
        replacements[indexes["lesson_reference"]] = f"  lesson_reference: {sq(reference)}\n"
    else:
        inserts.append(f"  lesson_reference: {sq(reference)}\n")
    replacements[idx] = f"  resolved_by_cmd: {sq(resolved)}\n"
    edits.append((replacements, idx, inserts))
    counts[disposition] += 1

new_lines = list(lines)
for replacements, idx, inserts in reversed(edits):
    for replace_idx, replacement in replacements.items():
        new_lines[replace_idx] = replacement
    if inserts:
        new_lines[idx:idx] = inserts

fd, candidate = tempfile.mkstemp(prefix=".karo_workarounds.reflux.", dir=os.path.dirname(path) or ".")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.writelines(new_lines)
    with open(candidate, encoding="utf-8") as fh:
        yaml.safe_load(fh)
    os.replace(candidate, path)
finally:
    if os.path.exists(candidate):
        os.unlink(candidate)
print(f"[backfill-reflux] updated={len(edits)} not_applicable={counts['not_applicable']} integrated_existing={counts['integrated_existing']}")
PY
    ) 200>"$LOCK_FILE"
    exit $?
fi

# --- Reclassify mode: update category of existing entries ---
if [[ "${1:-}" == "--reclassify" ]]; then
    shift
    if [[ $# -lt 2 ]]; then
        echo "Usage: bash scripts/karo_workaround_log.sh --reclassify <cmd_id_pattern> <new_category> [new_root_signature] [detail_pattern]" >&2
        exit 1
    fi
    PATTERN="$1"
    NEW_CAT="$2"
    NEW_ROOT_SIGNATURE="${3:-}"
    DETAIL_PATTERN="${4:-}"
    (
        flock -w 10 200 || { echo "[reclassify] Error: lock" >&2; exit 1; }
        TMPFILE="/tmp/.kwl_reclassify_$$"
        awk -v pat="$PATTERN" -v newcat="$NEW_CAT" -v newrootsig="$NEW_ROOT_SIGNATURE" -v detailpat="$DETAIL_PATTERN" '
        function trim_scalar(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            if (value ~ /^'\''.*'\''$/ || value ~ /^".*"$/) {
                value = substr(value, 2, length(value) - 2)
            }
            return value
        }
        function reset_entry() {
            delete entry_lines
            entry_len = 0
            entry_cmd = ""
        }
        function flush_entry(    idx, line, matches, replaced, oldcat, value, suffix, entrydetail, hasrootsig) {
            if (entry_len == 0) return
            replaced = 0
            oldcat = ""
            entrydetail = ""
            hasrootsig = 0
            for (idx = 1; idx <= entry_len; idx++) {
                line = entry_lines[idx]
                if (line ~ /^(-|  )category:[[:space:]]*/) {
                    value = line
                    sub(/^(-|  )category:[[:space:]]*/, "", value)
                    oldcat = trim_scalar(value)
                }
                if (line ~ /^  detail:[[:space:]]*/) {
                    value = line
                    sub(/^  detail:[[:space:]]*/, "", value)
                    entrydetail = trim_scalar(value)
                }
                if (line ~ /^  root_signature:[[:space:]]*/) hasrootsig = 1
            }
            matches = (entry_cmd != "" && entry_cmd ~ pat && (detailpat == "" || entrydetail ~ detailpat))
            for (idx = 1; idx <= entry_len; idx++) {
                line = entry_lines[idx]
                if (matches && !replaced && line ~ /^- category:[[:space:]]*/) {
                    print "- category: " newcat
                    replaced = 1
                    continue
                }
                if (matches && !replaced && line ~ /^  category:[[:space:]]*/) {
                    print "  category: " newcat
                    if (newrootsig != "" && !hasrootsig) {
                        print "  root_signature: '\''" newrootsig "'\''"
                    }
                    replaced = 1
                    continue
                }
                # categoryだけを再分類してroot_signatureのfamilyを旧値のまま
                # 残すと、集計単位(category×root_signature)が矛盾する。
                # 旧familyに属する署名だけprefixを原子的に追従させ、suffixは
                # 発生段階×破れた不変量として保持する。
                if (matches && oldcat != "" && line ~ /^  root_signature:[[:space:]]*/) {
                    if (newrootsig != "") {
                        print "  root_signature: '\''" newrootsig "'\''"
                        continue
                    }
                    value = line
                    sub(/^  root_signature:[[:space:]]*/, "", value)
                    value = trim_scalar(value)
                    if (index(value, oldcat "::") == 1) {
                        suffix = substr(value, length(oldcat) + 1)
                        print "  root_signature: '\''" newcat suffix "'\''"
                        continue
                    }
                }
                print line
            }
            reset_entry()
        }
        /^- [A-Za-z0-9_]+:[[:space:]]*/ {
            flush_entry()
        }
        {
            entry_lines[++entry_len] = $0
            if ($0 ~ /^-[[:space:]]+cmd(_id)?:[[:space:]]*/ || $0 ~ /^  cmd(_id)?:[[:space:]]*/) {
                value = $0
                sub(/^-[[:space:]]+cmd(_id)?:[[:space:]]*/, "", value)
                sub(/^  cmd(_id)?:[[:space:]]*/, "", value)
                entry_cmd = trim_scalar(value)
            }
        }
        END { flush_entry() }
        ' "$LOG_FILE" > "$TMPFILE"
        mv "$TMPFILE" "$LOG_FILE"
        echo "[reclassify] Updated entries matching '$PATTERN' → category: $NEW_CAT"
    ) 200>"$LOCK_FILE"
    exit 0
fi

# --- Normalize mode: fix cmd → cmd_id key ---
if [[ "${1:-}" == "--normalize" ]]; then
    (
        flock -w 10 200 || { echo "[normalize] Error: lock" >&2; exit 1; }
        BEFORE=$(awk 'BEGIN { count = 0 } /^- cmd: / { count++ } END { print count + 0 }' "$LOG_FILE" 2>/dev/null)
        if [[ "$BEFORE" -gt 0 ]]; then
            TMPFILE="/tmp/.kwl_normalize_$$"
            sed "s/^- cmd: /- cmd_id: /" "$LOG_FILE" > "$TMPFILE"
            mv "$TMPFILE" "$LOG_FILE"
        fi
        echo "[normalize] Fixed $BEFORE entries: cmd → cmd_id"
    ) 200>"$LOCK_FILE"
    exit 0
fi

# --- Event schema migration (cmd_3862 AC1) ---
# The workaround ledger now stores manual interventions and automatically
# captured rework events together.  Preserve every legacy record and make the
# historical default explicit: it was a manually written ledger entry, never
# an automatically captured completion event.
if [[ "${1:-}" == "--backfill-event-fields" ]]; then
    (
        flock -w 10 200 || { echo "[backfill-event-fields] Error: lock" >&2; exit 1; }
        python3 - "$LOG_FILE" <<'PY'
import os
import re
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    print("entries=0 backfilled=0")
    raise SystemExit(0)

lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
starts = [i for i, line in enumerate(lines) if re.match(r"^-\s+[A-Za-z0-9_]+:\s*", line)]
starts.append(len(lines))
output = []
backfilled = 0
for index in range(len(starts) - 1):
    block = lines[starts[index]:starts[index + 1]]
    fields = {match.group(1) for line in block if (match := re.match(r"^\s+([A-Za-z_][A-Za-z0-9_]*):", line))}
    additions = []
    if "event_kind" not in fields:
        additions.append("  event_kind: manual_wa\n")
    if "auto_captured" not in fields:
        additions.append("  auto_captured: false\n")
    if additions:
        backfilled += 1
        insert_at = next((i for i, line in enumerate(block) if re.match(r"^\s+detail:", line)), len(block))
        block[insert_at:insert_at] = additions
    output.extend(block)

if backfilled:
    fd, temporary = tempfile.mkstemp(dir=str(path.parent), suffix=".tmp")
    os.close(fd)
    try:
        Path(temporary).write_text("".join(output), encoding="utf-8")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
print(f"entries={len(starts) - 1} backfilled={backfilled}")
PY
    ) 200>"$LOCK_FILE"
    exit 0
fi

# --- Argument validation ---
CLEAN_MODE=false
WA_MODE=false
EXPLICIT_CATEGORY=""
MISSED_SG=""
ENVIRONMENT_CHANGE=""
if [[ "${1:-}" = "--clean" ]]; then
    CLEAN_MODE=true
    shift
    if [[ $# -lt 2 ]]; then
        echo "[karo_workaround_log] Usage: bash scripts/karo_workaround_log.sh --clean <cmd_id> <ninja_name>" >&2
        exit 1
    fi
    CMD_ID="$1"
    NINJA_NAME="$2"
    ISSUE=""
    FIX=""
    if [[ -z "$CMD_ID" || -z "$NINJA_NAME" ]]; then
        echo "[karo_workaround_log] Error: cmd_id and ninja_name must be non-empty" >&2
        exit 1
    fi
elif [[ "${1:-}" = "--wa" ]]; then
    WA_MODE=true
    shift
    if [[ $# -lt 4 || $# -gt 7 ]]; then
        echo "[karo_workaround_log] Usage: bash scripts/karo_workaround_log.sh --wa <cmd_id> <ninja_name> \"<issue>\" \"<fix>\" [category] [missed_sg] [environment_change]" >&2
        echo "  structured environment_change: type=gate|lesson|hook; file=path; pattern=grep_pattern" >&2
        exit 1
    fi
    CMD_ID="$1"
    NINJA_NAME="$2"
    ISSUE="$3"
    FIX="$4"
    EXPLICIT_CATEGORY="${5:-}"
    MISSED_SG="${6:-}"
    ENVIRONMENT_CHANGE="${7:-}"
    if [[ -z "$CMD_ID" || -z "$NINJA_NAME" || -z "$ISSUE" ]]; then
        echo "[karo_workaround_log] Error: cmd_id, ninja_name, issue must be non-empty" >&2
        exit 1
    fi
else
    if [[ $# -lt 4 || $# -gt 6 ]]; then
        echo "[karo_workaround_log] Usage: bash scripts/karo_workaround_log.sh <cmd_id> <ninja_name> \"<issue>\" \"<fix>\" [category] [missed_sg]" >&2
        echo "  --wa mode: bash scripts/karo_workaround_log.sh --wa <cmd_id> <ninja_name> \"<issue>\" \"<fix>\" [category] [missed_sg] [environment_change]" >&2
        echo "  --clean mode: bash scripts/karo_workaround_log.sh --clean <cmd_id> <ninja_name>" >&2
        exit 1
    fi
    CMD_ID="$1"
    NINJA_NAME="$2"
    ISSUE="$3"
    FIX="$4"
    EXPLICIT_CATEGORY="${5:-}"  # optional 5th arg for category
    MISSED_SG="${6:-}"          # optional 6th arg for missed SG checklist id
    if [[ -z "$CMD_ID" || -z "$NINJA_NAME" || -z "$ISSUE" ]]; then
        echo "[karo_workaround_log] Error: cmd_id, ninja_name, issue must be non-empty" >&2
        exit 1
    fi
fi

# --- Structured environment_change parsing (cmd_karo_env_change_gate) ---
# Pure-bash implementation: avoids Python3 subprocess fork cost on WSL2 (L511)
parse_structured_environment_change() {
    local env_change="${1:-}"
    [[ -n "$env_change" ]] || return 1

    local _key _val etype="" efile="" epattern=""

    _extract_field() {
        local text="$1" key="$2" val=""
        # Match: (^|;) optional_space key optional_space = optional_space capture_to_semicolon
        if [[ "$text" =~ (^|;)[[:space:]]*${key}[[:space:]]*=[[:space:]]*([^;]+) ]]; then
            val="${BASH_REMATCH[2]}"
            # Trim trailing whitespace
            val="${val%"${val##*[! ]}"}"
            # Trim leading whitespace
            val="${val#"${val%%[! ]*}"}"
            # Remove surrounding single or double quotes
            if [[ ${#val} -ge 2 && "${val:0:1}" == "${val: -1}" && \
                  ( "${val:0:1}" == "'" || "${val:0:1}" == '"' ) ]]; then
                val="${val:1:${#val}-2}"
                val="${val%"${val##*[! ]}"}"
                val="${val#"${val%%[! ]*}"}"
            fi
            printf '%s' "$val"
        fi
    }

    etype="$(_extract_field "$env_change" "type")"
    efile="$(_extract_field "$env_change" "file")"
    epattern="$(_extract_field "$env_change" "pattern")"

    [[ -n "$etype" && -n "$efile" && -n "$epattern" ]] || return 1
    printf '%s\t%s\t%s\n' "$etype" "$efile" "$epattern"
}

verify_environment_change() {
    local env_change="${1:-}"
    local env_structured="" env_type="" env_file="" env_pattern="" env_file_resolved=""

    if [[ -z "$env_change" ]]; then
        echo "[karo_workaround_log] BLOCK: environment_change未記入。--wa時は何を環境に埋め込んだか記録せよ" >&2
        echo '  形式: type=gate|lesson|hook; file=対象ファイルパス; pattern=grepで検証可能な文字列' >&2
        return 1
    fi

    if env_structured="$(parse_structured_environment_change "$env_change" 2>/dev/null)"; then
        IFS=$'\t' read -r env_type env_file env_pattern <<< "$env_structured"
        env_file_resolved="$env_file"
        [[ "$env_file_resolved" == /* ]] || env_file_resolved="$REPO_ROOT/$env_file_resolved"
        if grep -qE -- "$env_pattern" "$env_file_resolved" 2>/dev/null; then
            echo "[karo_workaround_log] INFO: environment_change検証OK: type=${env_type} file=${env_file} pattern=${env_pattern}" >&2
        else
            echo "[karo_workaround_log] BLOCK: environment_change未実装。file=${env_file} に pattern=${env_pattern} が見つからない" >&2
            echo "  実装してからkaro_workaround_log.sh --waを再実行せよ" >&2
            return 1
        fi
    else
        echo "[karo_workaround_log] BLOCK: environment_changeが非構造化。構造化形式で記録せよ" >&2
        echo '  形式: type=gate|lesson|hook; file=対象ファイルパス; pattern=grepで検証可能な文字列' >&2
        echo '  例: type=gate; file=scripts/karo_workaround_log.sh; pattern=verify_environment_change' >&2
        return 1
    fi
}

validate_brainwash_check() {
    local check="${1:-}"

    if [[ -z "$check" ]]; then
        echo "[karo_workaround_log] BLOCK: brainwash_check未記入。KARO_WA_BRAINWASH_CHECK='洗脳#X + 修正前→後の数値'で渡せ: $CMD_ID/$NINJA_NAME" >&2
        echo "  例: KARO_WA_BRAINWASH_CHECK='洗脳#2検証スキップ防止: gate再実行 0→1件 PASS'" >&2
        return 1
    fi
    if [[ ! "$check" =~ [0-9] ]]; then
        echo "[karo_workaround_log] BLOCK: brainwash_checkに数値なし。修正前→後の数値、またはN件中N件確認を記録せよ: $CMD_ID/$NINJA_NAME" >&2
        return 1
    fi
    if [[ ! "$check" =~ (→|->|=>|[0-9]+[[:space:]]*/[[:space:]]*[0-9]+|[0-9]+[[:space:]]*件中[[:space:]]*[0-9]+[[:space:]]*件) ]]; then
        echo "[karo_workaround_log] BLOCK: brainwash_checkに修正前→後の数値差分なし。0→1件、0/1件、N件中N件などを記録せよ: $CMD_ID/$NINJA_NAME" >&2
        return 1
    fi
}

# --- Argument order auto-swap (cmd_id/ninja reversal detection) ---
# 家老がcmd_idとninja_nameを逆順で渡すバグを自動検出+修正(4件データ汚染で発見 2026-04-28)
if [[ ! "$CMD_ID" =~ ^cmd_ && "$NINJA_NAME" =~ ^cmd_ ]]; then
    echo "[karo_workaround_log] WARN: cmd_id='$CMD_ID' がcmd_パターンに不一致、ninja='$NINJA_NAME'がcmd_パターン。引数が逆順。自動スワップ実行" >&2
    SWAP_TMP="$CMD_ID"
    CMD_ID="$NINJA_NAME"
    NINJA_NAME="$SWAP_TMP"
fi

# --- AC1(cmd_1542): ninja_id validation ---
if ! is_known_ninja "$NINJA_NAME"; then
    echo "[karo_workaround_log] Error: ninja_id '$NINJA_NAME' はknown_ninjas($(known_ninjas_display))に含まれない" >&2
    echo "  正しいninja名を指定せよ。unknownに集約する場合は明示的にunknownを渡せ" >&2
    exit 1
fi

# --- YAML single-quote escaping (cmd_cycle_L4_026: injection防止) ---
yaml_escape_sq() {
    # YAML single-quoted strings: ' → '' でエスケープ
    printf '%s' "${1//\'/\'\'}"
}

# --- Category auto-classification (AC2: cmd_1211) ---
classify_category() {
    local issue="$1"
    local pattern_report="lessons_useful|binary_checks|lesson_candidate|report_field_set|verdict|ac_version|variation_checks|variation.*(証跡|未実施|空)|報告証跡|report.*evidence|report.*フォーマット|フォーマット|(dict|list|string).*(→|変換|形式)"
    local pattern_disappear="消失|missing|not found|消失|不在"
    local pattern_report_commit_meta="commit_hash|files_modified|command_files_modified_mismatch|偵察commit不要|commit不要|binary_checks\\.commit|報告YAML.*commit|report.*commit"
    local pattern_commit_missing="commit.*漏れ|commit.*なし|commit.*missing|コミット.*漏れ|コミット.*なし|未commit|未コミット|untracked|modified"
    local pattern_stale="stale|古い|残骸|旧cmd|残存"
    local pattern_double="二重|double|重複配備|二重配備"
    local pattern_redeploy="再配備|redeploy|task_redeploy"
    local pattern_report_missing="報告.*未作成|report.*未作成|報告YAML.*未|report_yaml_missing"
    if [[ "$issue" =~ $pattern_report ]]; then
        echo "report_yaml_format"
    elif [[ "$issue" =~ $pattern_report_commit_meta ]]; then
        echo "report_yaml_format"
    elif [[ "$issue" =~ $pattern_report_missing ]]; then
        echo "report_missing"
    elif [[ "$issue" =~ $pattern_disappear ]]; then
        echo "file_disappearance"
    elif [[ "$issue" =~ $pattern_commit_missing ]]; then
        echo "commit_missing"
    elif [[ "$issue" =~ $pattern_stale ]]; then
        echo "stale_report"
    elif [[ "$issue" =~ $pattern_double ]]; then
        echo "double_deploy"
    elif [[ "$issue" =~ $pattern_redeploy ]]; then
        echo "task_redeploy"
    else
        echo "uncategorized"
    fi
}

# --- Root-signature classification (AC2: cmd_karo_hotfix_wa_root_signature_202607121225) ---
# category familyは維持しつつ、発生段階×破れた不変量で下位分類する。
# 1カテゴリに異根(schema欠落/agent stall/commit provenance/deploy fallback破損)が
# 混入しN>=3を偽発火させる問題(2026-07-08分析: report_yaml_format 3件=deploy fallback1+stall2)への対策。
# 自由文の個別cmd/file allowlistではなく、構造的な文言パターンのみで判定する。
classify_root_signature() {
    local category="$1"
    local issue="$2"
    local pattern_deploy_template='report_path.*欠落|ac_version.*欠落|標準スキル.*欠落|未引用.*コロン|deploy_task.*(fail|失敗)|最小task YAML'
    local pattern_lifecycle_stall='停滞|idle化|verdict_empty|Codex停止|未完了.*(commit未実施|status)'
    local pattern_commit_provenance='command_files_modified_mismatch|verified_existing_dependency|files_modified全件|commit未完了|uncommitted.*(gate|BLOCK)|report_received.*uncommitted|後続(integrator[[:space:]]*)?commit.*確認'
    local pattern_schema_shape='binary_checks|lessons_useful|knowledge_candidate|quote parse|(dict|list|string).*(→|変換|形式)|(commit_hash|status|items).*補正|補正.*(commit_hash|status)|欠落'

    # gate_logic_gap/deploy_contractに共通する破損不変量。個別cmd名ではなく、
    # 「どの実行段階で、何の契約が破れたか」を表す構造語だけで分類する。
    local pattern_error_handling='(exit[[:space:]]*2|異常exit).*(握り潰|許|続行)|握り潰.*(exit|異常)|異常終了.*伝播'
    local pattern_contract_projection='(quality[_ -]?contract|品質契約|QUALITY_CONTRACT).*(投影|射影|評価|action/fp|missing)|(flow-style|辞書型|複数行).*(投影|射影|評価)|(command以外|command第1行).*(評価|投影|射影|BLOCK|detector_fp_rate)'
    local pattern_merge_hook='merge.*(ninja_scope_commit|partial commit|hook)|ninja_scope_commit.*(merge|partial commit)|AUTO_MERGE'
    local pattern_exception_taxonomy='OperationalError|非lock.*(例外|error)|lock deadline|例外.*原義'
    local pattern_safety_boundary='readonly.*(credential|restore|allowlist)|credential.*(allowlist|縮小env)|backup.*dry-run.*restore|trust boundary'
    local pattern_operator_orchestration='completed.*(追記|helper)|helper BLOCK.*(複合shell|続行)|時期尚早.*(レビュー|通知)|再レビュー依頼'
    local pattern_natural_boundary='自然境界|estimated_minutes|長時間契約|split_decision'
    local pattern_verification_evidence='variation_checks|variation.*(証跡|未実施|空)|報告証跡|report.*evidence|test_results.*details'

    if [[ "$issue" =~ $pattern_verification_evidence ]]; then
        echo "${category}::verification_evidence"
    elif [[ "$issue" =~ $pattern_error_handling ]]; then
        echo "${category}::error_handling"
    elif [[ "$issue" =~ $pattern_contract_projection ]]; then
        echo "${category}::contract_projection"
    elif [[ "$issue" =~ $pattern_merge_hook ]]; then
        echo "${category}::merge_hook"
    elif [[ "$issue" =~ $pattern_exception_taxonomy ]]; then
        echo "${category}::exception_taxonomy"
    elif [[ "$issue" =~ $pattern_safety_boundary ]]; then
        echo "${category}::safety_boundary"
    elif [[ "$issue" =~ $pattern_operator_orchestration ]]; then
        echo "${category}::operator_orchestration"
    elif [[ "$issue" =~ $pattern_natural_boundary ]]; then
        echo "${category}::natural_boundary"
    elif [[ "$issue" =~ $pattern_deploy_template ]]; then
        echo "${category}::deploy_template_integrity"
    elif [[ "$issue" =~ $pattern_lifecycle_stall ]]; then
        echo "${category}::report_lifecycle_stall"
    elif [[ "$issue" =~ $pattern_commit_provenance ]]; then
        echo "${category}::commit_provenance"
    elif [[ "$issue" =~ $pattern_schema_shape ]]; then
        echo "${category}::schema_shape"
    else
        echo "${category}::general"
    fi
}

if [[ "$CLEAN_MODE" = true ]]; then
    CATEGORY="clean"
elif [[ -n "$EXPLICIT_CATEGORY" ]]; then
    CATEGORY="$EXPLICIT_CATEGORY"
else
    CATEGORY=$(classify_category "$ISSUE")
fi
TZ=UTC printf -v TIMESTAMP '%(%Y-%m-%dT%H:%M:%SZ)T' -1

# AC1(cmd_1538): WARN when category is uncategorized
if [[ "$CLEAN_MODE" != true && "$CATEGORY" == "uncategorized" ]]; then
    echo "[karo_workaround_log] WARN: categoryが未分類(uncategorized)。5番目の引数で明示的にcategoryを指定せよ: $CMD_ID/$NINJA_NAME" >&2
fi

# GP-220 hardening: category=clean is valid only through --clean.  Reject before
# brainwash validation, lock acquisition, or any ledger write so callers cannot
# persist the contradictory workaround=true/category=clean state.
if [[ "$CLEAN_MODE" != true && "$CATEGORY" == "clean" ]]; then
    echo "[karo_workaround_log] BLOCK: category=cleanは--cleanモード専用。正経路を使え: bash scripts/karo_workaround_log.sh --clean $CMD_ID $NINJA_NAME" >&2
    exit 1
fi

# AC2(cmd_1538+cmd_1542): root_cause validation (empty/null/short)
if [[ "$CLEAN_MODE" != true ]]; then
    if [[ -z "$FIX" || "$FIX" == "null" || "$FIX" == "None" || "$FIX" == "NULL" || "$FIX" == "none" ]]; then
        echo "[karo_workaround_log] WARN: root_causeが無効値('$FIX')。意味のある修正説明を記録せよ: $CMD_ID/$NINJA_NAME" >&2
    elif [[ ${#FIX} -lt 3 ]]; then
        echo "[karo_workaround_log] WARN: root_causeが短すぎる(${#FIX}文字, 最小3文字)。意味のある修正説明を記録せよ: $CMD_ID/$NINJA_NAME" >&2
    fi
fi

if [[ "$WA_MODE" = true ]]; then
    verify_environment_change "$ENVIRONMENT_CHANGE"
fi

# AC2(cmd_3474) + cmd_3752: every workaround:true path must carry numeric brainwash_check.
if [[ "$CLEAN_MODE" != true ]]; then
    validate_brainwash_check "$BRAINWASH_CHECK"
fi

# --- Count root_signature entries excluding resolved (AC3: cmd_karo_hotfix_wa_root_signature_202607121225) ---
# category単独ではなくcategory×root_signatureの対で集計する。root_signature欠落の
# legacy entryは根因不明であり、同根という証拠がないためパターン母数から除外する。
# 「unknown」をcategory::generalへ集約すると、異根を再び同一パターンとして偽発火させる。
count_root_signature_entries() {
    local target_category="$1"
    local target_signature="$2"
    if [[ ! -f "$LOG_FILE" ]]; then
        echo 0
        return
    fi
    awk -v target_cat="$target_category" -v target_sig="$target_signature" '
    function trim_scalar(value) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        if (value ~ /^'\''.*'\''$/ || value ~ /^".*"$/) {
            value = substr(value, 2, length(value) - 2)
        }
        return value
    }
    function flush_entry() {
        if (entry_started && cat == target_cat && is_wa && !resolved && rootsig != "") {
            if (rootsig == target_sig) count++
        }
        cat = ""
        rootsig = ""
        resolved = 0
        is_wa = 0
        entry_started = 0
    }
    function apply_field(key, value) {
        value = trim_scalar(value)
        if (key == "workaround" && value == "true") is_wa = 1
        else if (key == "category") cat = value
        else if (key == "root_signature") rootsig = value
        else if (key == "resolved_by_cmd" && value != "") resolved = 1
    }
    match($0, /^- ([A-Za-z0-9_]+):[[:space:]]*(.*)$/, m) {
        flush_entry()
        entry_started = 1
        apply_field(m[1], m[2])
        next
    }
    match($0, /^  ([A-Za-z0-9_]+):[[:space:]]*(.*)$/, m) {
        if (entry_started) apply_field(m[1], m[2])
        next
    }
    END {
        flush_entry()
        print count+0
    }
    ' "$LOG_FILE"
}

# --- Append entry with flock ---
(
    flock -w 10 200 || { echo "[karo_workaround_log] Error: Failed to acquire lock" >&2; exit 1; }

    # Initialize file if it doesn't exist
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
    fi

    if [[ "$CLEAN_MODE" = true ]]; then
        # --clean mode: workaround: false, category: clean を記録
        cat >> "$LOG_FILE" <<EOF
- cmd_id: $CMD_ID
  timestamp: '$TIMESTAMP'
  ninja: $NINJA_NAME
  workaround: false
  event_kind: manual_wa
  auto_captured: false
  category: clean
  detail: ''
  root_cause: ''
  lesson_required: false
  lesson_disposition: not_applicable
  lesson_reference: 'not_applicable'
  resolved_by_cmd: ''
EOF
        echo "[karo_workaround_log] Clean: $CMD_ID/$NINJA_NAME [clean]"
    else
        ROOT_SIGNATURE=$(classify_root_signature "$CATEGORY" "$ISSUE")
        SIG_COUNT=$(count_root_signature_entries "$CATEGORY" "$ROOT_SIGNATURE")
        OCCURRENCE=$((SIG_COUNT + 1))

        # GP-086: Append entry in standard flat-list format (matches manual karo entries)
        # Old format used nested "entries:" + 2-space indent → YAML structure conflict with manual entries
        SAFE_ISSUE=$(yaml_escape_sq "$ISSUE")
        SAFE_FIX=$(yaml_escape_sq "$FIX")
        SAFE_ROOT_SIGNATURE=$(yaml_escape_sq "$ROOT_SIGNATURE")
        SAFE_MISSED_SG=$(yaml_escape_sq "$MISSED_SG")
        SAFE_ENVIRONMENT_CHANGE=$(yaml_escape_sq "$ENVIRONMENT_CHANGE")
        SAFE_BRAINWASH_CHECK=$(yaml_escape_sq "$BRAINWASH_CHECK")
        {
            cat <<EOF
- cmd_id: $CMD_ID
  timestamp: '$TIMESTAMP'
  ninja: $NINJA_NAME
  workaround: true
  event_kind: manual_wa
  auto_captured: false
  category: $CATEGORY
  root_signature: '$SAFE_ROOT_SIGNATURE'
  detail: '$SAFE_ISSUE'
  root_cause: '$SAFE_FIX'
  lesson_required: $LESSON_REQUIRED
  lesson_disposition: '$([[ -n "$LESSON_REFERENCE" ]] && echo integrated_existing || echo new_lesson_required)'
  lesson_reference: '$(yaml_escape_sq "$LESSON_REFERENCE")'
EOF
            if [[ -n "$MISSED_SG" ]]; then
                echo "  missed_sg: '$SAFE_MISSED_SG'"
            fi
            if [[ "$WA_MODE" = true && -n "$ENVIRONMENT_CHANGE" ]]; then
                echo "  environment_change: '$SAFE_ENVIRONMENT_CHANGE'"
            fi
            echo "  brainwash_check: '$SAFE_BRAINWASH_CHECK'"
            cat <<EOF
  resolved_by_cmd: ''
EOF
        } >> "$LOG_FILE"

        memory_db_live_insert="$SCRIPT_DIR/memory_db_live_insert_async.py"
        if [[ ! -f "$memory_db_live_insert" ]]; then
            memory_db_live_insert="$SCRIPT_DIR/memory_db_live_insert.py"
        fi
        if [[ -f "$memory_db_live_insert" ]]; then
            memory_db_args=(
                workaround
                --cmd-id "$CMD_ID"
                --ts "$TIMESTAMP"
                --ninja "$NINJA_NAME"
                --category "$CATEGORY"
                --issue "$ISSUE"
                --root-cause "$FIX"
                --source-file "$LOG_FILE"
            )
            if [[ -n "${SHOGUN_MEMORY_DB:-}" ]]; then
                python3 "$memory_db_live_insert" "${memory_db_args[@]}" >/dev/null 2>&1 || true
            else
                python3 "$memory_db_live_insert" "${memory_db_args[@]}" >/dev/null 2>&1 &
                disown 2>/dev/null || true
            fi
        fi

        # --- Alert mechanism (AC1: cmd_1211, AC3: cmd_karo_hotfix_wa_root_signature_202607121225) ---
        # N>=3判定はcategory単独ではなくcategory×root_signature(発生段階×破れた不変量)で行う。
        # 異根(root_signatureが異なる)WAが同一categoryに混在してもALERT/PDは発火しない。
        if [[ "$CATEGORY" != "clean" && $OCCURRENCE -ge 3 ]]; then
            echo "[karo_workaround_log] ALERT: カテゴリ「${CATEGORY}」が${OCCURRENCE}件(root_signature=${ROOT_SIGNATURE})。構造対策cmdを起票せよ"
            if [[ "$DISABLE_ALERTS" != "true" ]]; then
                bash "$SCRIPT_DIR/ntfy.sh" "【家老ALERT】workaround同一カテゴリ「${CATEGORY}」根本原因「${ROOT_SIGNATURE}」が${OCCURRENCE}件。構造対策cmd起票を強制" 2>/dev/null || true
                bash "$SCRIPT_DIR/insight_write.sh" "workaround同一カテゴリ「${CATEGORY}」根本原因「${ROOT_SIGNATURE}」が${OCCURRENCE}件蓄積。構造対策cmdの起票が必要" "high" "karo_workaround_log" 2>/dev/null || true
                # なぜなぜ7回到達: ALERTを行動に接続（表示→PD自動起票→将軍startup gate検知）
                # PD_DEDUP_KEY: 同一root_signatureのWAが4件目5件目と増えてもPDは1件へ集約し、
                # occurrence/summaryの件数を更新する。件数増=悪化という情報は保持されるため
                # 「既に記録したから黙る」検知器にはならない(A8 沈黙の検査)。
                PD_DEDUP_KEY="wa_escalation:${CATEGORY}::${ROOT_SIGNATURE}" \
                bash "$SCRIPT_DIR/pending_decision_write.sh" create "workaround同一カテゴリ「${CATEGORY}」根本原因「${ROOT_SIGNATURE}」が${OCCURRENCE}件蓄積。構造対策cmdの起票・裁定が必要" "${CMD_ID}" escalation karo 2>/dev/null || true
            fi
        elif [[ "$CATEGORY" != "clean" && $OCCURRENCE -eq 2 ]]; then
            echo "[karo_workaround_log] WARN: 同一カテゴリ「${CATEGORY}」が2件(root_signature=${ROOT_SIGNATURE})。構造対策cmdの起票を検討せよ"
        else
            echo "[karo_workaround_log] Logged: $CMD_ID/$NINJA_NAME [$CATEGORY/$ROOT_SIGNATURE]"
        fi
    fi

) 200>"$LOCK_FILE"
# karo_workarounds.yaml 専用軽量 archive:
# yaml_auto_archive.sh の Python起動コスト(~45ms)をawk実装で削減。
# keep=100件を超えた場合のみ、古いエントリをarchiveに移動する。
_wa_total=$(awk '/^- cmd_id:/{c++}END{print c+0}' "$LOG_FILE" 2>/dev/null)
if [[ "${_wa_total:-0}" -gt 100 ]]; then
    _to_archive=$(( _wa_total - 100 ))
    _archive_dir="$REPO_ROOT/logs/archive"
    _archive_file="$_archive_dir/karo_workarounds.yaml"
    mkdir -p "$_archive_dir" 2>/dev/null || true
    (
        flock -w 10 300 || { echo "[karo_workaround_log] WARN: archive lock timeout" >&2; exit 0; }
        awk -v n="$_to_archive" -v arch="$_archive_file" '
        /^- cmd_id:/ { entry++ }
        entry <= n { print >> arch; next }
        { print }
        ' "$LOG_FILE" > "${LOG_FILE}.tmp.$$" && mv "${LOG_FILE}.tmp.$$" "$LOG_FILE"
    ) 300>/tmp/karo_workarounds_archive.lock
fi
