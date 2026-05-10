#!/bin/bash
# lesson_write.sh — SSOT (DM-signal/tasks/lessons.md) への教訓追記（排他ロック付き）
# Usage: bash scripts/lesson_write.sh <project_id> "<title>" "<detail>" "<source_cmd>" "<author>" [cmd_id] [--strategic] [--tags "db,api"] [--subdomain fe|be|gs|infra] [--when "trigger"] [--how "steps"] [--if "condition"] [--then "action"] [--because "reason"]
# Tags: --tags "tag1,tag2" (explicit) or auto-inferred project tag. Fallback: universal
# Example: bash scripts/lesson_write.sh dm-signal "本番DBはPostgreSQL" "SQLiteに書くな" "cmd_079" "karo"
# Example: bash scripts/lesson_write.sh infra "Gate改修" "ゲート検証" "cmd_100" "saizo" "" --tags "gate,process"

set -e

if [ -n "${LESSON_WRITE_SCRIPT_DIR:-}" ]; then
    SCRIPT_DIR="$LESSON_WRITE_SCRIPT_DIR"
else
    _self="${BASH_SOURCE[0]}"
    _self_dir="${_self%/*}"
    [[ "$_self_dir" != /* ]] && _self_dir="$(cd "$_self_dir" && pwd)"
    SCRIPT_DIR="${_self_dir%/scripts}"
fi
PROJECT_ID="${1:-}"
TITLE="${2:-}"
DETAIL="${3:-}"
SOURCE_CMD="${4:-}"
AUTHOR="${5:-karo}"
CMD_ID="${6:-""}"

# Resolve project metadata once and reuse it in this process.
PROJECT_META_ID=""
PROJECT_META_PATH=""
PROJECT_META_CONTEXT_FILE=""

load_project_metadata() {
    local proj_id="$1"
    local config_file="$SCRIPT_DIR/config/projects.yaml"

    if [ "$PROJECT_META_ID" = "$proj_id" ]; then
        return 0
    fi

    local meta
    meta=$(awk -v id="$proj_id" '
        /^[[:space:]]*- id:/ {
            if (seen_target && !first_match_consumed) {
                exit
            }
            val = $NF
            gsub(/"/, "", val)
            found = (val == id)
            if (found) {
                seen_target = 1
            }
            first_match_consumed = 0
            next
        }
        found && /^[[:space:]]*path:/ {
            path = $0
            sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "", path)
            gsub(/"/, "", path)
            first_match_consumed = 1
        }
        found && /^[[:space:]]*context_file:/ {
            context_file = $0
            sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "", context_file)
            gsub(/"/, "", context_file)
            first_match_consumed = 1
        }
        END {
            printf "%s\t%s\n", path, context_file
        }
    ' "$config_file")

    IFS=$'\t' read -r PROJECT_META_PATH PROJECT_META_CONTEXT_FILE <<< "$meta"
    PROJECT_META_ID="$proj_id"
}

# Resolve project_id → field value from config/projects.yaml (pure bash, no python3)
# Usage: resolve_project_field <project_id> [field]  (default field: path)
resolve_project_field() {
    local proj_id="$1"
    local field="${2:-path}"

    load_project_metadata "$proj_id"
    case "$field" in
        path)
            printf '%s\n' "$PROJECT_META_PATH"
            ;;
        context_file)
            printf '%s\n' "$PROJECT_META_CONTEXT_FILE"
            ;;
    esac
}

# Backward-compat wrapper
resolve_project_path() {
    resolve_project_field "$1" "path"
}

resolve_lesson_context_route() {
    local proj_id="$1"
    local subdomain="${2:-}"
    local first_subdomain="${subdomain%%,*}"

    CONTEXT_ROUTE_FILE="$PROJECT_META_CONTEXT_FILE"
    CONTEXT_ROUTE_ANCHOR=""

    case "$proj_id:$first_subdomain" in
        dm-signal:fe)
            CONTEXT_ROUTE_FILE="context/dm-signal-frontend.md"
            CONTEXT_ROUTE_ANCHOR='^## 12\. Frontend関連教訓'
            ;;
        dm-signal:be)
            CONTEXT_ROUTE_FILE="context/dm-signal-ops.md"
            CONTEXT_ROUTE_ANCHOR='^## §6-7 '
            ;;
        dm-signal:gs)
            CONTEXT_ROUTE_FILE="context/dm-signal-ops.md"
            CONTEXT_ROUTE_ANCHOR='^## §33 '
            ;;
        dm-signal:infra|infra:infra)
            CONTEXT_ROUTE_FILE="context/infrastructure.md"
            CONTEXT_ROUTE_ANCHOR='^## Infra教訓索引'
            ;;
        infra:*)
            CONTEXT_ROUTE_FILE="context/infrastructure.md"
            CONTEXT_ROUTE_ANCHOR='^## Infra教訓索引'
            ;;
    esac
}

resolve_cmd_project() {
    local cmd_id="$1"
    [ -z "$cmd_id" ] && return 0

    CMD_ID_ENV="$cmd_id" SCRIPT_DIR_ENV="$SCRIPT_DIR" python3 <<'PY'
import glob
import os
import sys
import yaml

cmd_id = os.environ.get("CMD_ID_ENV", "").strip()
script_dir = os.environ.get("SCRIPT_DIR_ENV", "").strip()

if not cmd_id or not script_dir:
    raise SystemExit(0)

def load_yaml(path):
    try:
        with open(path, encoding='utf-8') as fh:
            return yaml.safe_load(fh) or {}
    except Exception:
        return {}

def print_project(entry):
    if not isinstance(entry, dict):
        return False
    project = str(entry.get('project', '') or '').strip()
    if not project:
        return False
    print(project)
    return True

stk = os.path.join(script_dir, 'queue', 'shogun_to_karo.yaml')
stk_data = load_yaml(stk)
commands = stk_data.get('commands', {})
if isinstance(commands, dict) and print_project(commands.get(cmd_id, {})):
    raise SystemExit(0)

archive_dir = os.path.join(script_dir, 'queue', 'archive', 'cmds')
for cpath in sorted(glob.glob(os.path.join(archive_dir, f'{cmd_id}_*.yaml')), reverse=True):
    data = load_yaml(cpath)
    commands = data.get('commands', {})
    if isinstance(commands, dict) and print_project(commands.get(cmd_id, {})):
        raise SystemExit(0)
    if isinstance(commands, list):
        for cmd in commands:
            if str(cmd.get('id', '') or '').strip() == cmd_id and print_project(cmd):
                raise SystemExit(0)
PY
}

infer_default_project_tag() {
    local inferred_cmd=""
    local inferred_project=""

    if [[ "${CMD_ID:-}" == cmd_* ]]; then
        inferred_cmd="$CMD_ID"
    elif [[ "${SOURCE_CMD:-}" == cmd_* ]]; then
        inferred_cmd="$SOURCE_CMD"
    fi

    if [ -n "$inferred_cmd" ]; then
        inferred_project="$(resolve_cmd_project "$inferred_cmd")"
    fi

    if [ -z "$inferred_project" ] && [ -n "$PROJECT_ID" ]; then
        load_project_metadata "$PROJECT_ID"
        if [ -n "$PROJECT_META_PATH" ]; then
            inferred_project="$PROJECT_ID"
        fi
    fi

    printf '%s\n' "$inferred_project"
}

warn_similar_title() {
    # bash pre-check: count ASCII tokens (mirrors python3 min_tokens=3 logic)
    # Skip python3 startup entirely when title clearly has fewer than 3 tokens
    local _tok_count=0 _rest="$2"
    while [[ "$_rest" =~ [a-zA-Z][a-zA-Z0-9_.]*[a-zA-Z0-9]|[a-zA-Z0-9]{2,} ]]; do
        (( _tok_count++ ))
        _rest="${_rest#*"${BASH_REMATCH[0]}"}"
        [[ $_tok_count -ge 3 ]] && break
    done
    if (( _tok_count < 3 )); then
        return 0
    fi
    LESSONS_FILE_ENV="$1" TITLE_ENV="$2" python3 <<'PY'
import os
import re
import sys

lessons_file = os.environ["LESSONS_FILE_ENV"]
new_title = os.environ["TITLE_ENV"]
threshold = 0.6
min_tokens = 3

def tokenize(text):
    tokens = set()
    for token in re.findall(r'[a-zA-Z][a-zA-Z0-9_.]*[a-zA-Z0-9]|[a-zA-Z0-9]{2,}', text.lower()):
        tokens.add(token)
    jp_chars = re.sub(r'[\x00-\x7f\s]', '', text)
    for i in range(len(jp_chars) - 1):
        tokens.add(jp_chars[i:i+2])
    return tokens

def jaccard(set_a, set_b):
    if not set_a or not set_b:
        return 0.0
    union = set_a | set_b
    return len(set_a & set_b) / len(union) if union else 0.0

new_tokens = tokenize(new_title)
if len(new_tokens) < min_tokens:
    sys.exit(0)

best_match = None
heading_re = re.compile(r'^### L(\d+): (.+)$', re.MULTILINE)
with open(lessons_file, encoding='utf-8') as f:
    content = f.read()

for match in heading_re.finditer(content):
    existing_id = f'L{int(match.group(1)):03d}'
    existing_title = match.group(2).strip()
    existing_tokens = tokenize(existing_title)
    if len(existing_tokens) < min_tokens:
        continue
    score = jaccard(new_tokens, existing_tokens)
    if score >= threshold and (best_match is None or score > best_match[0]):
        best_match = (score, existing_id, existing_title)

if best_match is not None:
    score, existing_id, existing_title = best_match
    print(
        f'WARN: 類似教訓候補: {existing_id}: {existing_title} (Jaccard: {score:.2f})',
        file=sys.stderr,
    )
PY
}

# ── Parse all flags in one pass ──
FORCE=0
STRATEGIC=""
STATUS="confirmed"
TAGS=""
IF_COND=""
THEN_ACTION=""
BECAUSE_REASON=""
WHEN_COND=""
HOW_ACTION=""
RETIRE_ID=""
RETAG_ID=""
RETAG_TAGS=""
SUBDOMAIN=""

show_usage() {
    cat <<'EOF'
Usage: lesson_write.sh <project_id> <title> <detail> [source_cmd] [author] [cmd_id] [options]

Options:
  --force                 重複タイトルチェックをバイパス
  --strategic             pending_decisionにMCP昇格候補を登録
  --status draft|confirmed
  --tags "db,api"         教訓タグを明示指定
  --subdomain fe|be|gs|infra
                          教訓の対象サブドメインを明示指定
  --when "trigger"        発動条件を明示指定
  --how "steps"           実行手順を明示指定
  --if "condition" --then "action" --because "reason"
  --retire <lesson_id>
  --retag <lesson_id> --new-tags "tag1,tag2"
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            show_usage
            exit 0
            ;;
        --force)
            FORCE=1
            shift
            ;;
        --strategic)
            STRATEGIC="--strategic"
            shift
            ;;
        --status)
            STATUS="${2:-}"
            shift 2
            ;;
        --tags)
            TAGS="${2:-}"
            shift 2
            ;;
        --subdomain)
            SUBDOMAIN="${2:-}"
            shift 2
            ;;
        --if)
            IF_COND="${2:-}"
            shift 2
            ;;
        --then)
            THEN_ACTION="${2:-}"
            shift 2
            ;;
        --because)
            BECAUSE_REASON="${2:-}"
            shift 2
            ;;
        --when)
            WHEN_COND="${2:-}"
            shift 2
            ;;
        --how)
            HOW_ACTION="${2:-}"
            shift 2
            ;;
        --retire)
            RETIRE_ID="${2:-}"
            shift 2
            ;;
        --retag)
            RETAG_ID="${2:-}"
            shift 2
            ;;
        --new-tags)
            RETAG_TAGS="${2:-}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [ "$STATUS" != "draft" ] && [ "$STATUS" != "confirmed" ]; then
    echo "ERROR: --status must be 'draft' or 'confirmed' (got: $STATUS)" >&2
    exit 1
fi

if [ -n "$SUBDOMAIN" ]; then
    _lw_subdomain_csv=""
    IFS=',' read -r -a _lw_subdomain_array <<< "$SUBDOMAIN"
    for _lw_sd in "${_lw_subdomain_array[@]}"; do
        _lw_sd="${_lw_sd#"${_lw_sd%%[![:space:]]*}"}"
        _lw_sd="${_lw_sd%"${_lw_sd##*[![:space:]]}"}"
        case "$_lw_sd" in
            frontend|front|ui) _lw_sd="fe" ;;
            backend|back|api) _lw_sd="be" ;;
            grid_search|grid-search|gridsearch) _lw_sd="gs" ;;
            platform) _lw_sd="infra" ;;
        esac
        case "$_lw_sd" in
            fe|be|gs|infra) ;;
            *)
                echo "ERROR: --subdomain must be one of fe,be,gs,infra (got: $SUBDOMAIN)" >&2
                exit 1
                ;;
        esac
        if [ -z "$_lw_subdomain_csv" ]; then
            _lw_subdomain_csv="$_lw_sd"
        elif [[ ",$_lw_subdomain_csv," != *",$_lw_sd,"* ]]; then
            _lw_subdomain_csv="${_lw_subdomain_csv},$_lw_sd"
        fi
    done
    SUBDOMAIN="$_lw_subdomain_csv"
fi

# ─── Retag mode: change tags of existing lesson (both lessons.md + sync) ───
if [ -n "$RETAG_ID" ]; then
    if [ -z "$PROJECT_ID" ] || [ -z "$RETAG_TAGS" ]; then
        echo "Usage: lesson_write.sh <project_id> --retag <lesson_id> --new-tags \"tag1,tag2\"" >&2
        exit 1
    fi

    if [[ "$PROJECT_ID" == cmd_* ]]; then
        echo "ERROR: 第1引数はproject_id（例: infra, dm-signal）。cmd_idではない。" >&2
        exit 1
    fi

    PROJECT_PATH=$(resolve_project_path "$PROJECT_ID")
    if [ -z "$PROJECT_PATH" ]; then
        echo "ERROR: Project '$PROJECT_ID' not found in config/projects.yaml" >&2
        exit 1
    fi

    LESSONS_FILE="$PROJECT_PATH/tasks/lessons.md"
    LOCKFILE="${LESSONS_FILE}.lock"

    if [ ! -f "$LESSONS_FILE" ]; then
        echo "ERROR: $LESSONS_FILE not found." >&2
        exit 1
    fi

    (
        flock -w 10 200 || { echo "ERROR: Could not acquire lock" >&2; exit 1; }

        export LESSONS_FILE RETAG_ID RETAG_TAGS
        python3 << 'RETAGPY'
import re, os, sys

lessons_file = os.environ["LESSONS_FILE"]
retag_id = os.environ["RETAG_ID"]
new_tags = os.environ["RETAG_TAGS"]

with open(lessons_file, encoding='utf-8') as f:
    content = f.read()

# Normalize lesson ID
m_id = re.match(r'^L?(\d+)$', retag_id)
if m_id:
    retag_id = f'L{int(m_id.group(1)):03d}'

# Format tags as [tag1, tag2]
tag_list = [t.strip() for t in new_tags.split(',')]
tags_str = '[' + ', '.join(tag_list) + ']'

lines = content.split('\n')

# Find lesson heading
heading_idx = None
for i, line in enumerate(lines):
    if re.match(rf'^### {re.escape(retag_id)}\s*[:：]', line):
        heading_idx = i
        break

if heading_idx is None:
    print(f'ERROR: {retag_id} not found in {lessons_file}', file=sys.stderr)
    sys.exit(1)

# Find and replace tags line
found = False
for j in range(heading_idx + 1, min(heading_idx + 10, len(lines))):
    if re.match(r'^- \*\*tags\*\*:', lines[j]):
        old_tags = lines[j]
        lines[j] = f'- **tags**: {tags_str}'
        found = True
        print(f'{retag_id} tags: {old_tags.strip()} → {tags_str}')
        break
    if lines[j].startswith('###'):
        break

if not found:
    print(f'ERROR: tags line not found for {retag_id}', file=sys.stderr)
    sys.exit(1)

with open(lessons_file, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))
RETAGPY

    ) 200>"$LOCKFILE"

    # Re-sync YAML cache (both lessons.md → lessons.yaml)
    bash "$SCRIPT_DIR/scripts/sync_lessons.sh" "$PROJECT_ID"

    echo "[lesson_write] $RETAG_ID retag successfully"
    exit 0
fi

# ─── Retire mode: mark existing lesson as retired ───
if [ -n "$RETIRE_ID" ]; then
    if [ -z "$PROJECT_ID" ]; then
        echo "Usage: lesson_write.sh <project_id> --retire <lesson_id>" >&2
        exit 1
    fi

    if [[ "$PROJECT_ID" == cmd_* ]]; then
        echo "ERROR: 第1引数はproject_id（例: infra, dm-signal）。cmd_idではない。" >&2
        exit 1
    fi

    PROJECT_PATH=$(resolve_project_path "$PROJECT_ID")

    if [ -z "$PROJECT_PATH" ]; then
        echo "ERROR: Project '$PROJECT_ID' not found in config/projects.yaml" >&2
        exit 1
    fi

    LESSONS_FILE="$PROJECT_PATH/tasks/lessons.md"
    LOCKFILE="${LESSONS_FILE}.lock"

    if [ ! -f "$LESSONS_FILE" ]; then
        echo "ERROR: $LESSONS_FILE not found." >&2
        exit 1
    fi

    TIMESTAMP=$(date "+%Y-%m-%d")

    # Atomic modify with flock
    (
        flock -w 10 200 || { echo "ERROR: Could not acquire lock" >&2; exit 1; }

        export LESSONS_FILE RETIRE_ID TIMESTAMP
        python3 << 'RETIREPY'
import re, os, sys

lessons_file = os.environ["LESSONS_FILE"]
retire_id = os.environ["RETIRE_ID"]
timestamp = os.environ["TIMESTAMP"]

with open(lessons_file, encoding='utf-8') as f:
    content = f.read()

# Normalize lesson ID to LXXX format
m_id = re.match(r'^L?(\d+)$', retire_id)
if m_id:
    num = int(m_id.group(1))
    retire_id = f'L{num:03d}'

lines = content.split('\n')

# Find the lesson heading: ### LXXX: title
heading_idx = None
for i, line in enumerate(lines):
    if re.match(rf'^### {re.escape(retire_id)}\s*[:：]', line):
        heading_idx = i
        break

if heading_idx is None:
    print(f'ERROR: {retire_id} not found in {lessons_file}', file=sys.stderr)
    sys.exit(1)

# Find the last metadata line after the heading (lines starting with - **)
insert_idx = heading_idx + 1
already_retired = False
for j in range(heading_idx + 1, len(lines)):
    stripped = lines[j].strip()
    if stripped.startswith('- **'):
        insert_idx = j + 1
        if '**retired**' in stripped:
            already_retired = True
    elif stripped == '':
        continue
    else:
        break

if already_retired:
    print(f'{retire_id} is already retired')
    sys.exit(0)

# Insert retired fields after last metadata line
retired_lines = [f'- **retired**: true', f'- **retired_at**: {timestamp}']
new_lines = lines[:insert_idx] + retired_lines + lines[insert_idx:]

with open(lessons_file, 'w', encoding='utf-8') as f:
    f.write('\n'.join(new_lines))

print(f'{retire_id} retired in {lessons_file}')
RETIREPY

    ) 200>"$LOCKFILE"

    # Re-sync YAML cache
    bash "$SCRIPT_DIR/scripts/sync_lessons.sh" "$PROJECT_ID"

    echo "[lesson_write] $RETIRE_ID retired successfully"
    exit 0
fi

# Validate arguments
if [ -z "$PROJECT_ID" ] || [ -z "$TITLE" ] || [ -z "$DETAIL" ]; then
    echo "Usage: lesson_write.sh <project_id> <title> <detail> [source_cmd] [author]" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

if [[ "$PROJECT_ID" == cmd_* ]]; then
    echo "ERROR: 第1引数はproject_id（例: infra, dm-signal）。cmd_idではない。" >&2
    echo "Usage: lesson_write.sh <project_id> <title> <detail> [source_cmd] [author]" >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

# Summary quality gate (cmd_158)
DETAIL_LEN=${#DETAIL}
if [ "$DETAIL_LEN" -lt 10 ]; then
    echo "ERROR: summary(detail)が10文字未満 (${DETAIL_LEN}文字)。具体的な内容を記載せよ" >&2
    exit 1
fi

load_project_metadata "$PROJECT_ID"
PROJECT_PATH="$PROJECT_META_PATH"

if [ -z "$PROJECT_PATH" ]; then
    echo "ERROR: Project '$PROJECT_ID' not found in config/projects.yaml" >&2
    exit 1
fi

LESSONS_FILE="$PROJECT_PATH/tasks/lessons.md"
LOCKFILE="${LESSONS_FILE}.lock"

# Verify lessons file exists
if [ ! -f "$LESSONS_FILE" ]; then
    echo "ERROR: $LESSONS_FILE not found." >&2
    exit 1
fi

TIMESTAMP=$(date "+%Y-%m-%d")

# 忍者成長速度改善2: source_cmdのtarget_pathを教訓のtarget_filesに自動設定
_LW_TARGET_FILES=""
if [ -n "${SOURCE_CMD:-}" ]; then
    # shogun_to_karo.yaml + archive からtarget_pathを取得
    _lw_tp=""
    for _lw_yaml in "$SCRIPT_DIR/queue/shogun_to_karo.yaml" "$SCRIPT_DIR/queue/archive"/shogun_to_karo_*.yaml; do
        [ -f "$_lw_yaml" ] || continue
        _lw_tp=$(awk -v cmd="$SOURCE_CMD" '
            /^[[:space:]]*cmd_[0-9]+:/ || /^[[:space:]]*'"$SOURCE_CMD"':/ {
                found = ($0 ~ cmd":")
            }
            found && /target_path:/ {
                sub(/.*target_path:[[:space:]]*/, "")
                gsub(/["'"'"']/, "")
                gsub(/^[[:space:]]+|[[:space:]]+$/, "")
                if (length($0) > 0) print
                found = 0
                exit
            }
        ' "$_lw_yaml" 2>/dev/null)
        [ -n "$_lw_tp" ] && break
    done
    # 報告YAMLからfiles_modifiedも取得（path フィールド）
    _lw_fm=""
    for _lw_report in "$SCRIPT_DIR/queue/reports"/*_report_"${SOURCE_CMD}".yaml; do
        [ -f "$_lw_report" ] || continue
        _lw_fm=$(awk 'BEGIN{f=0} /^files_modified:/{f=1;next} f && /^[a-z_]/{f=0} f && /path:/{sub(/.*path: */,""); gsub(/"/,""); print}' "$_lw_report" 2>/dev/null | head -5 | tr '\n' ',')
        _lw_fm="${_lw_fm%,}"
        break
    done
    # 結合: target_path + files_modified (重複除去、最大5件)
    _lw_all_files=""
    [ -n "$_lw_tp" ] && _lw_all_files="$_lw_tp"
    if [ -n "$_lw_fm" ]; then
        [ -n "$_lw_all_files" ] && _lw_all_files="${_lw_all_files},${_lw_fm}" || _lw_all_files="$_lw_fm"
    fi
    if [ -n "$_lw_all_files" ]; then
        # 重複除去して最大5件
        _LW_TARGET_FILES=$(echo "$_lw_all_files" | tr ',' '\n' | awk '!seen[$0]++ && NR<=5' | tr '\n' ',' | sed 's/,$//')
    fi
fi

# Temp file for passing lesson ID out of flock subshell
LESSON_ID_FILE=$(mktemp)
trap 'rm -f "$LESSON_ID_FILE"' EXIT

# Atomic append with flock (3 retries)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 10 200 || exit 1

        # Find max ID and append new entry (bash native — no python3)
        _lw_max_id=0
        _lw_duplicate_id=""
        _lw_duplicate_title=""
        while IFS= read -r _lw_line; do
            if [[ "$_lw_line" =~ ^##[[:space:]]([0-9]+)\. ]]; then
                _lw_n=$(( 10#${BASH_REMATCH[1]} ))
                (( _lw_n > _lw_max_id )) && _lw_max_id=$_lw_n
            elif [[ "$_lw_line" =~ ^###[[:space:]]L([0-9]+): ]]; then
                _lw_n=$(( 10#${BASH_REMATCH[1]} ))
                (( _lw_n > _lw_max_id )) && _lw_max_id=$_lw_n
                if [ "${FORCE:-0}" != "1" ] && [[ "$_lw_line" =~ ^###[[:space:]]L([0-9]+):[[:space:]](.+)$ ]]; then
                    _lw_eid="L$(printf '%03d' $(( 10#${BASH_REMATCH[1]} )))"
                    _lw_etitle="${BASH_REMATCH[2]}"
                    if [ "$TITLE" = "$_lw_etitle" ]; then
                        _lw_duplicate_id="$_lw_eid"
                        _lw_duplicate_title="$_lw_etitle"
                    fi
                fi
            fi
        done < "$LESSONS_FILE"
        _lw_new_id=$(( _lw_max_id + 1 ))
        printf -v _lw_new_id_str 'L%03d' "$_lw_new_id"

        if [ -n "$_lw_duplicate_id" ]; then
            printf 'ERROR: 類似教訓あり: %s: %s (類似度: 100%%)\n' "$_lw_duplicate_id" "$_lw_duplicate_title" >&2
            printf '強制登録: --force フラグを追加\n' >&2
            echo "duplicate_error" > "${LESSON_ID_FILE}.err" 2>/dev/null || true
            exit 1
        fi

        if [ "${FORCE:-0}" != "1" ]; then
            warn_similar_title "$LESSONS_FILE" "$TITLE"
        fi

        # Tag processing (bash native)
        if [ -n "${TAGS:-}" ]; then
            _lw_tags_yaml="["
            IFS=',' read -r -a _lw_tags_array <<< "$TAGS"
            for _lw_tag in "${_lw_tags_array[@]}"; do
                _lw_tag="${_lw_tag#"${_lw_tag%%[![:space:]]*}"}"
                _lw_tag="${_lw_tag%"${_lw_tag##*[![:space:]]}"}"
                [ -z "$_lw_tag" ] && continue
                if [ "$_lw_tags_yaml" != "[" ]; then
                    _lw_tags_yaml+=", "
                fi
                _lw_tags_yaml+="${_lw_tag}"
            done
            _lw_tags_yaml+="]"
        else
            _lw_default_tag="$(infer_default_project_tag)"
            # 忍者成長速度改善: lesson_tags.yamlルールで教訓テキストからタグ自動推定
            _lw_auto_tags=""
            _lw_lesson_text="${TITLE} ${DETAIL}"
            if [ -f "$SCRIPT_DIR/config/lesson_tags.yaml" ]; then
                _lw_auto_tags=$(python3 -c "
import re, yaml, sys
text = sys.argv[1]
with open(sys.argv[2]) as f:
    rules = yaml.safe_load(f).get('tag_rules', [])
tags = []
for r in rules:
    for p in r.get('patterns', []):
        if re.search(p, text):
            tags.append(r['tag'])
            break
print(','.join(tags[:3]))
" "$_lw_lesson_text" "$SCRIPT_DIR/config/lesson_tags.yaml" 2>/dev/null || true)
            fi
            _lw_all_tags=""
            [ -n "$_lw_default_tag" ] && _lw_all_tags="$_lw_default_tag"
            if [ -n "$_lw_auto_tags" ]; then
                [ -n "$_lw_all_tags" ] && _lw_all_tags="${_lw_all_tags},${_lw_auto_tags}" || _lw_all_tags="$_lw_auto_tags"
            fi
            if [ -n "$_lw_all_tags" ]; then
                _lw_tags_yaml="[${_lw_all_tags}]"
            else
                _lw_tags_yaml="[universal]"
            fi
        fi

        _lw_when="${WHEN_COND:-${IF_COND:-未設定}}"
        _lw_how="${HOW_ACTION:-${THEN_ACTION:-未設定}}"

        # Build and append new entry
        {
            printf '\n### %s: %s\n' "$_lw_new_id_str" "$TITLE"
            printf -- '- **日付**: %s\n' "$TIMESTAMP"
            [ -n "${SOURCE_CMD:-}" ] && printf -- '- **出典**: %s\n' "$SOURCE_CMD"
            printf -- '- **記録者**: %s\n' "${AUTHOR:-karo}"
            [ "${STATUS:-confirmed}" = "draft" ] && printf -- '- **status**: draft\n'
            printf -- '- **tags**: %s\n' "$_lw_tags_yaml"
            [ -n "${SUBDOMAIN:-}" ] && printf -- '- **subdomain**: %s\n' "$SUBDOMAIN"
            [ -n "$_LW_TARGET_FILES" ] && printf -- '- **target_files**: [%s]\n' "$_LW_TARGET_FILES"
            printf -- '- **when**: %s\n' "$_lw_when"
            printf -- '- **how**: %s\n' "$_lw_how"
            [ -n "${IF_COND:-}" ] && printf -- '- **if**: %s\n' "$IF_COND"
            [ -n "${THEN_ACTION:-}" ] && printf -- '- **then**: %s\n' "$THEN_ACTION"
            [ -n "${BECAUSE_REASON:-}" ] && printf -- '- **because**: %s\n' "$BECAUSE_REASON"
            printf -- '- %s\n' "$DETAIL"
        } >> "$LESSONS_FILE"

        printf '%s' "$_lw_new_id_str" > "${LESSON_ID_FILE:-/dev/null}"
        echo "$_lw_new_id_str added to $LESSONS_FILE"

    ) 200>"$LOCKFILE"; then
        # AC3: Auto-call sync_lessons.sh after write (non-blocking: 失敗しても後続処理を続行)
        if [ "${LESSON_WRITE_SKIP_SYNC:-0}" != "1" ]; then
            bash "$SCRIPT_DIR/scripts/sync_lessons.sh" "$PROJECT_ID" || echo "WARN: sync_lessons.sh failed (non-blocking — lesson is written)" >&2
        fi
        # Read lesson ID once — reuse for context/strategic/reflux (was: 3x cat fork)
        NEW_LESSON_ID=""
        if [ -f "$LESSON_ID_FILE" ]; then
            read -r NEW_LESSON_ID < "$LESSON_ID_FILE" || true
        fi
        # Context索引自動追記 (cmd_300)
        if [ -n "$NEW_LESSON_ID" ]; then
            resolve_lesson_context_route "$PROJECT_ID" "${SUBDOMAIN:-}"
            CONTEXT_FILE="$CONTEXT_ROUTE_FILE"
            if [ -n "$CONTEXT_FILE" ]; then
                CONTEXT_FULL_PATH="$SCRIPT_DIR/$CONTEXT_FILE"
                if [ -f "$CONTEXT_FULL_PATH" ]; then
                    # AC2: dedup — 同一LESSON_IDがあればスキップ (L006教訓)
                    if ! grep -qF -- "- ${NEW_LESSON_ID}:" "$CONTEXT_FULL_PATH"; then
                        (
                            flock -w 10 201 || { echo "WARN: context lock timeout, skipping context update" >&2; exit 1; }
                            export CONTEXT_FULL_PATH NEW_LESSON_ID TITLE SOURCE_CMD CONTEXT_ROUTE_ANCHOR
                            python3 << 'CTXEOF'
import re, os

ctx_path = os.environ["CONTEXT_FULL_PATH"]
lesson_id = os.environ["NEW_LESSON_ID"]
title = os.environ["TITLE"]
source_cmd = os.environ.get("SOURCE_CMD", "")
route_anchor = os.environ.get("CONTEXT_ROUTE_ANCHOR", "")

with open(ctx_path, encoding='utf-8') as f:
    content = f.read()

entry = f"- {lesson_id}: {title}"
if source_cmd:
    entry += f"\uFF08{source_cmd}\uFF09"

def insert_under_heading(text, heading_match, lesson_entry):
    after_section = text[heading_match.end():]
    next_heading = re.search(r'^## ', after_section, re.MULTILINE)
    if next_heading:
        insert_pos = heading_match.end() + next_heading.start()
        return text[:insert_pos].rstrip('\n') + '\n' + lesson_entry + '\n\n' + text[insert_pos:]
    return text.rstrip('\n') + '\n' + lesson_entry + '\n'

# Patterns: "## ...教訓..." or "## ...Lesson..."
section_pattern = re.compile(r'^(##\s+.*(?:教訓|[Ll]esson).*)', re.MULTILINE)
matches = list(section_pattern.finditer(content))

route_match = re.search(route_anchor, content, re.MULTILINE) if route_anchor else None
if route_match:
    new_content = insert_under_heading(content, route_match, entry)
elif matches:
    new_content = insert_under_heading(content, matches[-1], entry)
else:
    new_content = content.rstrip('\n') + '\n\n## 教訓索引（自動追記）\n\n' + entry + '\n'

# Update sync marker: <!-- last_synced_lesson: LXXX -->
marker_pattern = re.compile(r'<!--\s*last_synced_lesson:\s*L\d+\s*-->')
new_marker = f'<!-- last_synced_lesson: {lesson_id} -->'

if marker_pattern.search(new_content):
    # AC2: Marker exists — update the number
    new_content = marker_pattern.sub(new_marker, new_content)
else:
    # AC2: Marker absent — add after last lesson entry in the section
    # Insert before the next heading or at EOF
    route_match_recheck = re.search(route_anchor, new_content, re.MULTILINE) if route_anchor else None
    matches_recheck = list(section_pattern.finditer(new_content))
    if route_match_recheck or matches_recheck:
        last_match_recheck = route_match_recheck or matches_recheck[-1]
        after_recheck = new_content[last_match_recheck.end():]
        next_h = re.search(r'^## ', after_recheck, re.MULTILINE)
        if next_h:
            marker_pos = last_match_recheck.end() + next_h.start()
            new_content = new_content[:marker_pos].rstrip('\n') + '\n' + new_marker + '\n\n' + new_content[marker_pos:].lstrip('\n')
        else:
            new_content = new_content.rstrip('\n') + '\n' + new_marker + '\n'
    else:
        new_content = new_content.rstrip('\n') + '\n' + new_marker + '\n'

with open(ctx_path, 'w', encoding='utf-8') as f:
    f.write(new_content)

print(f"[lesson_write] {lesson_id} appended to {ctx_path}")
print(f"[lesson_write] sync marker updated: {new_marker}")
CTXEOF
                        ) 201>"${CONTEXT_FULL_PATH}.lock"
                    else
                        echo "[lesson_write] ${NEW_LESSON_ID} already in $CONTEXT_FILE, skipping context append"
                    fi
                else
                    echo "WARN: context file not found: $CONTEXT_FULL_PATH" >&2
                fi
            fi
        fi
        # --strategic: Register as pending decision (replaces direct dashboard.md editing)
        if [ "$STRATEGIC" == "--strategic" ]; then
            if [ -n "$NEW_LESSON_ID" ]; then
                if [ -f "$SCRIPT_DIR/scripts/pending_decision_write.sh" ]; then
                    bash "$SCRIPT_DIR/scripts/pending_decision_write.sh" create \
                        "MCP昇格候補: $NEW_LESSON_ID — $TITLE（将軍確認待ち）" \
                        "$SOURCE_CMD" "skill_candidate" "$AUTHOR"
                else
                    echo "WARN: pending_decision_write.sh not found, skipping strategic registration" >&2
                fi
            fi
        fi
        # cmd_108: Write .done flag for cmd_complete_gate
        if [ -n "$CMD_ID" ]; then
            gates_dir="$SCRIPT_DIR/queue/gates/${CMD_ID}"
            mkdir -p "$gates_dir"
            echo "timestamp: $(date +%Y-%m-%dT%H:%M:%S)" > "$gates_dir/lesson.done"
            echo "source: lesson_write" >> "$gates_dir/lesson.done"
        fi
        # セマンティクスインデックス: aliases照合で既存概念へlessonリソースを追記（失敗は非ブロック）
        if [ -n "$NEW_LESSON_ID" ] && [ -f "$SCRIPT_DIR/scripts/semantic_index_update.sh" ]; then
            if _semantic_payload=$(LESSON_ID_ENV="$NEW_LESSON_ID" TITLE_ENV="$TITLE" DETAIL_ENV="$DETAIL" SOURCE_CMD_ENV="$SOURCE_CMD" python3 - <<'PY' 2>/dev/null
import json
import os

print(json.dumps({
    "id": os.environ.get("LESSON_ID_ENV", ""),
    "title": os.environ.get("TITLE_ENV", ""),
    "detail": os.environ.get("DETAIL_ENV", ""),
    "source_cmd": os.environ.get("SOURCE_CMD_ENV", ""),
}, ensure_ascii=False))
PY
            ); then
                bash "$SCRIPT_DIR/scripts/semantic_index_update.sh" lesson "$_semantic_payload" >/dev/null 2>&1 || true
            fi
        fi
        # REFLUX_CHECK: 穴検出3問チェック (cmd_1088)
        # 教訓登録=一回失敗=周辺に穴。キーワードでPI/ランブック/instructionsをgrep、還流漏れを検出
        if [ -n "$NEW_LESSON_ID" ]; then
            REFLUX_KEYWORDS=$(printf '%s\n' "${TITLE} ${DETAIL}" | awk '
                {
                    line = tolower($0)
                    while (match(line, /[a-z_][a-z_0-9]{2,}/)) {
                        token = substr(line, RSTART, RLENGTH)
                        if (!seen[token]++) {
                            out[++count] = token
                            if (count == 3) {
                                break
                            }
                        }
                        line = substr(line, RSTART + RLENGTH)
                    }
                    if (count == 3) {
                        exit
                    }
                }
                END {
                    for (i = 1; i <= count; i++) {
                        printf "%s%s", out[i], (i < count ? "|" : "")
                    }
                }
            ') || true

            REFLUX_PI="MISSING"
            REFLUX_RUNBOOK="MISSING"
            REFLUX_INSTRUCTIONS="MISSING"

            if [ -n "$REFLUX_KEYWORDS" ]; then
                # (1) PI check: projects/{project}.yaml の production_invariants 関連
                PI_FILE="$SCRIPT_DIR/projects/${PROJECT_ID}.yaml"
                if [ -f "$PI_FILE" ] && grep -qE "$REFLUX_KEYWORDS" "$PI_FILE" 2>/dev/null; then
                    REFLUX_PI="FOUND"
                fi

                # (2) Runbook check: docs/rule/*.md
                if [ -d "$SCRIPT_DIR/docs/rule" ]; then
                    if grep -rlE "$REFLUX_KEYWORDS" "$SCRIPT_DIR/docs/rule/"*.md >/dev/null 2>&1; then
                        REFLUX_RUNBOOK="FOUND"
                    fi
                fi

                # (3) Instructions check: instructions/*.md
                if grep -rlE "$REFLUX_KEYWORDS" "$SCRIPT_DIR/instructions/"*.md >/dev/null 2>&1; then
                    REFLUX_INSTRUCTIONS="FOUND"
                fi
            fi

            echo "REFLUX_CHECK: (1)PI=$REFLUX_PI (2)RUNBOOK=$REFLUX_RUNBOOK (3)INSTRUCTIONS=$REFLUX_INSTRUCTIONS"
            if [ "$REFLUX_PI" = "MISSING" ] || [ "$REFLUX_RUNBOOK" = "MISSING" ] || [ "$REFLUX_INSTRUCTIONS" = "MISSING" ]; then
                echo "WARN: 還流漏れの可能性あり。MISSING箇所にこの教訓の知見を反映すべきか検討せよ"
            fi
        fi
        exit 0
    else
        # Check if failure was a validation error (not a lock timeout) — skip retry
        if [ -f "${LESSON_ID_FILE}.err" ]; then
            rm -f "${LESSON_ID_FILE}.err"
            exit 1
        fi
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[lesson_write] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[lesson_write] Failed to acquire lock after $max_attempts attempts" >&2
            exit 1
        fi
    fi
done
