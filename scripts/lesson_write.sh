#!/bin/bash
# provenance: cmd_karo_hotfix_lesson_write_chmod_eperm_20260725_normal (DrvFs chmod EPERM許容化)
# semantic-links: [[教訓ライフサイクル管理]]
# lesson_write.sh — SSOT (DM-signal/tasks/lessons.md) への教訓追記（排他ロック付き）
# Usage: bash scripts/lesson_write.sh <project_id> "<title>" "<detail>" "<source_cmd>" "<author>" [cmd_id] [--strategic] [--tags "db,api"] [--subdomain fe|be|gs|infra] [--target-files "scripts/foo.sh,tests/foo.bats"] [--source-marker "gate_auto_draft"] [--origin "[[cmd_XXX]]"] [--when "trigger"] [--how "steps"] [--if "condition"] [--then "action"] [--because "reason"]
# Tags: --tags "tag1,tag2" (explicit) or auto-inferred project tag. Fallback: universal
# Example: bash scripts/lesson_write.sh dm-signal "本番DBはPostgreSQL" "SQLiteに書くな" "cmd_079" "karo"
# Example: bash scripts/lesson_write.sh infra "Gate改修" "ゲート検証" "cmd_100" "saizo" "" --tags "gate,process"

set -e

_LESSON_WRITE_SELF="${BASH_SOURCE[0]:-$0}"
[[ "$_LESSON_WRITE_SELF" = /* ]] || _LESSON_WRITE_SELF="$PWD/$_LESSON_WRITE_SELF"
_LESSON_WRITE_ROOT="${_LESSON_WRITE_SELF%/scripts/lesson_write.sh}"
LESSON_WRITE_TOTAL_T0_US="${EPOCHREALTIME/./}"
LESSON_WRITE_TOTAL_T0_US="${LESSON_WRITE_TOTAL_T0_US:0:16}"
DEFENSE_OVERHEAD_REPO_ROOT="${DEFENSE_OVERHEAD_REPO_ROOT:-${LESSON_WRITE_SCRIPT_DIR:-$_LESSON_WRITE_ROOT}}"
if [ -f "$_LESSON_WRITE_ROOT/scripts/lib/defense_overhead_writer.sh" ]; then
    # shellcheck source=scripts/lib/defense_overhead_writer.sh
    source "$_LESSON_WRITE_ROOT/scripts/lib/defense_overhead_writer.sh"
else
    defense_overhead_write_async() { return 0; }
fi
LESSON_WRITE_TOTAL_RECORDED=0
lesson_write_record_total() {
    local rc="${1:-0}" now_us wall_ms verdict
    [ "${LESSON_WRITE_TOTAL_RECORDED:-0}" -eq 0 ] || return 0
    LESSON_WRITE_TOTAL_RECORDED=1
    now_us="${EPOCHREALTIME/./}"
    now_us="${now_us:0:16}"
    wall_ms=$(( (now_us - LESSON_WRITE_TOTAL_T0_US + 999) / 1000 ))
    verdict=PASS
    [ "$rc" -eq 0 ] || verdict=FAIL
    defense_overhead_write_async lesson_write lesson_write_total "$wall_ms" "$verdict" \
        "lesson-write-${BASHPID}-${LESSON_WRITE_TOTAL_T0_US}" || true
}
lesson_write_total_on_exit() { local rc=$?; lesson_write_record_total "$rc"; return "$rc"; }
trap lesson_write_total_on_exit EXIT

if [ -n "${LESSON_WRITE_SCRIPT_DIR:-}" ]; then
    SCRIPT_DIR="$LESSON_WRITE_SCRIPT_DIR"
else
    _self="${BASH_SOURCE[0]}"
    _self_dir="${_self%/*}"
    [[ "$_self_dir" != /* ]] && _self_dir="$(cd "$_self_dir" && pwd)"
    SCRIPT_DIR="${_self_dir%/scripts}"
fi
if [ -f "$SCRIPT_DIR/scripts/lib/lock_path.sh" ]; then
    # Keep all lesson writers on the same lock namespace. On WSL2 /mnt/c,
    # lock_path places flock files on /tmp instead of NTFS/DrvFs.
    source "$SCRIPT_DIR/scripts/lib/lock_path.sh"
else
    lock_path() { printf '%s.lock' "$1"; }
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

# resolve_lesson_context_route()のSSOTはscripts/gates/lesson_context_routes.sh。
# gate_lesson_health.shの未合流判定と同じルーティング表を共有し、
# 「書込み側がsyncしたファイル」と「gateが見るファイル」がドリフトしないようにする(GA-216/GA-217)。
if [ ! -f "$SCRIPT_DIR/scripts/gates/lesson_context_routes.sh" ]; then
    echo "ERROR: scripts/gates/lesson_context_routes.sh not found — context route SSOT missing" >&2
    exit 1
fi
source "$SCRIPT_DIR/scripts/gates/lesson_context_routes.sh"

resolve_cmd_project() {
    local cmd_id="$1"
    [ -z "$cmd_id" ] && return 0

    CMD_ID_ENV="$cmd_id" SCRIPT_DIR_ENV="$SCRIPT_DIR" python3 <<'PY'
# Extract commands[cmd_id].project via a bounded line-scan instead of a full
# yaml.safe_load. Avoids `import yaml` (~182ms) + parsing the 204KB
# shogun_to_karo.yaml on every lesson write (378ms -> 107ms, -71.7%).
# Output verified identical to safe_load across stk(dict) + archive(list) +
# nonexistent cmd_ids (cmd_training_L4 lesson_write.sh speedup).
import glob
import os
import re
import sys

cmd_id = os.environ.get("CMD_ID_ENV", "").strip()
script_dir = os.environ.get("SCRIPT_DIR_ENV", "").strip()

if not cmd_id or not script_dir:
    raise SystemExit(0)

def scan_project(path, cmd_id):
    """Return the top-level `project:` value for cmd_id, or None.
    Handles dict form (`  cmd_id:` mapping key) and list form (`- id: cmd_id`)."""
    try:
        with open(path, encoding='utf-8') as fh:
            lines = fh.readlines()
    except Exception:
        return None
    key_re = re.compile(r'^(\s+)' + re.escape(cmd_id) + r':\s*(?:#.*)?$')
    id_re = re.compile(r'^(\s*)-?\s*id:\s*[\'"]?' + re.escape(cmd_id) + r'[\'"]?\s*$')
    n = len(lines)
    for i, line in enumerate(lines):
        m = key_re.match(line)
        if m:
            base = len(m.group(1))
            for j in range(i + 1, n):
                s = lines[j].strip()
                if not s:
                    continue
                indent = len(lines[j]) - len(lines[j].lstrip())
                if indent <= base:
                    break
                if s.startswith('project:'):
                    v = s[len('project:'):].strip().strip('"\'')
                    return v or None
            return None
        m = id_re.match(line)
        if m:
            id_pos = line.index('id:')
            start = i
            while start - 1 >= 0:
                pl = lines[start - 1]
                if not pl.strip():
                    start -= 1
                    continue
                if len(pl) - len(pl.lstrip()) < id_pos:
                    break
                start -= 1
            for j in range(start, n):
                s = lines[j].strip()
                if not s:
                    continue
                indent = len(lines[j]) - len(lines[j].lstrip())
                if j > i and indent < id_pos:
                    break
                if s.startswith('project:'):
                    v = s[len('project:'):].strip().strip('"\'')
                    return v or None
            return None
    return None

stk = os.path.join(script_dir, 'queue', 'shogun_to_karo.yaml')
project = scan_project(stk, cmd_id)
if project:
    print(project)
    raise SystemExit(0)

archive_dir = os.path.join(script_dir, 'queue', 'archive', 'cmds')
for cpath in sorted(glob.glob(os.path.join(archive_dir, f'{cmd_id}_*.yaml')), reverse=True):
    project = scan_project(cpath, cmd_id)
    if project:
        print(project)
        raise SystemExit(0)
PY
}

infer_subdomain_tag_from_files() {
    local files="${1:-}"
    [ -z "$files" ] && return 0

    local tag=""
    local _isf_f
    local _isf_oldIFS="$IFS"
    IFS=','
    for _isf_f in $files; do
        IFS="$_isf_oldIFS"
        # Trim whitespace
        _isf_f="${_isf_f#"${_isf_f%%[![:space:]]*}"}"
        _isf_f="${_isf_f%"${_isf_f##*[![:space:]]}"}"
        [ -z "$_isf_f" ] && continue

        case "$_isf_f" in
            *scripts/gates/*|*/gates/gate_*) tag="gate" ;;
            *tests/*|*test_*.bats)           tag="testing" ;;
            *scripts/deploy_task*)           tag="deploy-task" ;;
            *scripts/ninja_monitor*)         tag="ninja-monitor" ;;
            *scripts/inbox*|*inbox_write*|*inbox_mark*|*inbox_watcher*|*inbox_archive*) tag="inbox" ;;
            *scripts/lesson*|*lesson_write*|*sync_lessons*) tag="lesson" ;;
            *scripts/cmd_save*|*cmd_design_quality*|*cmd_complete_gate*) tag="cmd-quality" ;;
            *scripts/bulletin*)              tag="bulletin" ;;
            *scripts/semantic*)              tag="semantic" ;;
            *context/*)                      tag="context" ;;
            *instructions/*)                 tag="instructions" ;;
            *skills/*)                       tag="skill" ;;
        esac

        [ -n "$tag" ] && break
    done
    IFS="$_isf_oldIFS"

    printf '%s\n' "$tag"
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

    # Infer subdomain tag from target files (--target-files or auto-resolved)
    local subdomain_tag=""
    local files_to_check="${_LW_TARGET_FILES:-${TARGET_FILES:-}}"
    if [ -n "$files_to_check" ]; then
        subdomain_tag="$(infer_subdomain_tag_from_files "$files_to_check")"
    fi

    # Combine: project_tag[,subdomain_tag]
    local result="$inferred_project"
    if [ -n "$subdomain_tag" ]; then
        if [ -n "$result" ]; then
            result="${result},${subdomain_tag}"
        else
            result="$subdomain_tag"
        fi
    fi

    printf '%s\n' "$result"
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
PROMOTE_ID=""
SUBDOMAIN=""
TARGET_FILES=""
SOURCE_MARKER=""
ORIGIN=""
ENFORCEMENT="未自動化"

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
  --target-files "pattern1,pattern2"
                          教訓の対象ファイルパターンを明示指定
  --source-marker "value" 教訓生成元マーカーを明示指定
  --origin "[[cmd_XXX]]"  因果ネットワーク用originを明示指定
  --enforcement "Level4: gate blocks ..."
                          防御階層/自動化状態を明示指定。省略時は未自動化
  --when "trigger"        発動条件を明示指定
  --how "steps"           実行手順を明示指定
  --if "condition" --then "action" --because "reason"
  --retire <lesson_id>
  --retag <lesson_id> --new-tags "tag1,tag2"
  --promote <lesson_id> --enforcement "Level5: ..."
                          SSOT上の既存IDをexact一致で原子的に昇格しcacheを再同期
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
        --target-files)
            TARGET_FILES="${2:-}"
            shift 2
            ;;
        --source-marker)
            SOURCE_MARKER="${2:-}"
            shift 2
            ;;
        --origin)
            ORIGIN="${2:-}"
            shift 2
            ;;
        --enforcement)
            ENFORCEMENT="${2:-}"
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
        --promote)
            PROMOTE_ID="${2:-}"
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

normalize_target_files_csv() {
    local raw="$1"
    printf '%s\n' "$raw" | tr ',' '\n' | awk '
        {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            gsub(/^["'\''"]|["'\''"]$/, "")
            if ($0 != "" && !seen[$0]++ && count < 5) {
                out = out (out ? "," : "") $0
                count++
            }
        }
        END { print out }
    '
}

if [ -n "$TARGET_FILES" ]; then
    TARGET_FILES="$(normalize_target_files_csv "$TARGET_FILES")"
fi

resolve_origin_value() {
    if [ -n "${ORIGIN:-}" ]; then
        printf '%s\n' "$ORIGIN"
    elif [ -n "${SOURCE_CMD:-}" ]; then
        printf '[[%s]]\n' "$SOURCE_CMD"
    fi
}

require_origin_value() {
    local resolved_origin
    resolved_origin="$(resolve_origin_value)"
    if [ -z "$resolved_origin" ]; then
        echo "ERROR: origin is required. Pass --origin \"[[cmd_XXX]] -> [[原因]] -> [[結果]]\" or provide source_cmd." >&2
        exit 1
    fi
    if [[ "$resolved_origin" != *"[[ "* && "$resolved_origin" != *"[["* ]]; then
        echo "ERROR: origin must contain Obsidian-style [[link]] syntax (got: $resolved_origin)" >&2
        exit 1
    fi
    printf '%s\n' "$resolved_origin"
}

# ─── Promote mode: atomically update one existing SSOT lesson, then sync cache ───
if [ -n "$PROMOTE_ID" ]; then
    if [ -z "$PROJECT_ID" ] || [ -z "$ENFORCEMENT" ] || [ "$ENFORCEMENT" = "未自動化" ]; then
        echo "Usage: lesson_write.sh <project_id> --promote <lesson_id> --enforcement \"Level5: ...\"" >&2
        exit 1
    fi
    if [[ "$PROJECT_ID" == cmd_* ]]; then
        echo "ERROR: 第1引数はproject_id（例: infra, dm-signal）。cmd_idではない。" >&2
        exit 1
    fi
    if [[ ! "$PROMOTE_ID" =~ ^L[0-9]+$ ]]; then
        echo "ERROR: --promote requires an exact lesson ID such as L901" >&2
        exit 1
    fi

    PROJECT_PATH=$(resolve_project_path "$PROJECT_ID")
    [ -n "$PROJECT_PATH" ] || { echo "ERROR: Project '$PROJECT_ID' not found in config/projects.yaml" >&2; exit 1; }
    LESSONS_FILE="$PROJECT_PATH/tasks/lessons.md"
    [ -f "$LESSONS_FILE" ] || { echo "ERROR: $LESSONS_FILE not found." >&2; exit 1; }
    LOCKFILE="$(lock_path "$LESSONS_FILE")"
    CACHE_FILE="$SCRIPT_DIR/projects/${PROJECT_ID}/lessons.yaml"

    # sync_lessons.sh regenerates CACHE_FILE. Never overwrite unrelated work
    # already present there; the caller must reconcile that dirty cache first.
    if [ -e "$CACHE_FILE" ] && git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        _lw_cache_rel="${CACHE_FILE#"$SCRIPT_DIR"/}"
        if git -C "$SCRIPT_DIR" ls-files --error-unmatch -- "$_lw_cache_rel" >/dev/null 2>&1 \
            && ! git -C "$SCRIPT_DIR" diff --quiet -- "$_lw_cache_rel"; then
            echo "ERROR: generated cache has foreign dirty changes: $_lw_cache_rel" >&2
            exit 1
        fi
    fi

    (
        flock -w 10 200 || { echo "ERROR: Could not acquire lock" >&2; exit 1; }
        LESSONS_FILE_ENV="$LESSONS_FILE" PROMOTE_ID_ENV="$PROMOTE_ID" \
        ENFORCEMENT_ENV="$ENFORCEMENT" python3 <<'PROMOTEPY'
import os
import re
import stat
import sys
import tempfile

path = os.environ["LESSONS_FILE_ENV"]
lesson_id = os.environ["PROMOTE_ID_ENV"]
enforcement = os.environ["ENFORCEMENT_ENV"]
with open(path, encoding="utf-8") as fh:
    content = fh.read()

heading = re.compile(rf"^### {re.escape(lesson_id)}\s*[:：].*$", re.MULTILINE)
matches = list(heading.finditer(content))
if len(matches) != 1:
    state = "not found" if not matches else f"duplicate ({len(matches)} matches)"
    raise SystemExit(f"ERROR: exact lesson ID {lesson_id} {state} in {path}")

start = matches[0].start()
next_heading = re.search(r"^### L[0-9]+\s*[:：]", content[matches[0].end():], re.MULTILINE)
end = matches[0].end() + next_heading.start() if next_heading else len(content)
block = content[start:end]
line = f"- **enforcement**: {enforcement}"
metadata = re.compile(r"^- \*\*enforcement\*\*:[^\n]*$", re.MULTILINE)
if len(metadata.findall(block)) > 1:
    raise SystemExit(f"ERROR: duplicate enforcement metadata for {lesson_id}")
if metadata.search(block):
    block = metadata.sub(line, block, count=1)
else:
    heading_end = block.find("\n")
    block = block[:heading_end + 1] + line + "\n" + block[heading_end + 1:]
updated = content[:start] + block + content[end:]

mode = stat.S_IMODE(os.stat(path).st_mode)
directory = os.path.dirname(path) or "."
fd, tmp = tempfile.mkstemp(prefix=".lesson-promote.", dir=directory, text=True)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(updated)
        fh.flush()
        os.fsync(fh.fileno())
    # DrvFs(/mnt/c): 所有者root/mode 777固定。非所有者chmodはEPERM、replace後modeもFS側が固定するため継承は不要
    try:
        os.chmod(tmp, mode)
    except PermissionError as exc:
        print(f"WARN: chmod skipped (mode preservation unsupported on this filesystem): {exc}", file=sys.stderr)
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
print(f"{lesson_id} promoted in {path}")
PROMOTEPY
    ) 200>"$LOCKFILE"

    if [ "${LESSON_WRITE_SKIP_SYNC:-0}" != "1" ]; then
        LESSON_WRITE_SYNC_MODE=sync bash "$SCRIPT_DIR/scripts/sync_lessons.sh" "$PROJECT_ID"
    fi
    echo "[lesson_write] $PROMOTE_ID promoted and cache synchronized"
    exit 0
fi

write_project_yaml_lesson() {
    local lessons_yaml="$SCRIPT_DIR/projects/${PROJECT_ID}/lessons.yaml"
    local lessons_dir="${lessons_yaml%/*}"
    local lockfile
    local timestamp

    # Not every external project owns a tasks/lessons.md SSOT. The Shogun
    # project layer is the canonical fallback for those projects, and must be
    # initializable on first write. Requiring a hand-created empty YAML made
    # every lesson candidate for a newly registered external project fail
    # forever. Project membership was already validated from projects.yaml
    # before this function is called, so the derived directory is bounded.
    mkdir -p "$lessons_dir" || return 1
    lockfile="$(lock_path "$lessons_yaml")"

    timestamp=$(date "+%Y-%m-%d")
    RESOLVED_ORIGIN="$(require_origin_value)"

    (
        flock -w 10 200 || { echo "ERROR: Could not acquire lock" >&2; exit 1; }

        if [ ! -f "$lessons_yaml" ]; then
            local init_tmp
            init_tmp="$(mktemp "${lessons_yaml}.init.XXXXXX")" || exit 1
            {
                # Cache-only projects have no lessons.md.  Store a portable
                # repo-relative cache path instead of the absolute writer
                # checkout, so a later health gate can resolve it after a
                # publish-clone move.
                printf 'ssot_path: projects/%s/lessons.yaml\n' "$PROJECT_ID"
                printf "last_synced: '%s'\n" "$(date -Is)"
                printf 'lesson_count: 0\n'
                printf 'lessons:\n'
            } > "$init_tmp"
            mv -f "$init_tmp" "$lessons_yaml"
        fi

        LESSONS_YAML_ENV="$lessons_yaml" \
        TITLE_ENV="$TITLE" \
        DETAIL_ENV="$DETAIL" \
        SOURCE_CMD_ENV="$SOURCE_CMD" \
        AUTHOR_ENV="${AUTHOR:-karo}" \
        TAGS_ENV="${TAGS:-$PROJECT_ID}" \
        TARGET_FILES_ENV="${TARGET_FILES:-}" \
        ORIGIN_ENV="$RESOLVED_ORIGIN" \
        ENFORCEMENT_ENV="${ENFORCEMENT:-未自動化}" \
        TIMESTAMP_ENV="$timestamp" \
        FORCE_ENV="${FORCE:-0}" \
        python3 <<'PY'
import os
import re
import sys
import tempfile

import yaml

path = os.environ["LESSONS_YAML_ENV"]
title = os.environ["TITLE_ENV"]
detail = os.environ["DETAIL_ENV"]
source_cmd = os.environ.get("SOURCE_CMD_ENV", "")
origin = os.environ.get("ORIGIN_ENV", "")
enforcement = os.environ.get("ENFORCEMENT_ENV", "未自動化") or "未自動化"
timestamp = os.environ["TIMESTAMP_ENV"]
force = os.environ.get("FORCE_ENV", "0") == "1"
tags = [t.strip() for t in os.environ.get("TAGS_ENV", "").split(",") if t.strip()]
target_files = [p.strip() for p in os.environ.get("TARGET_FILES_ENV", "").split(",") if p.strip()]

with open(path, encoding="utf-8") as fh:
    content = fh.read()

if not force:
    for m in re.finditer(r"^[ \t]+title:[ \t]*(.+)$", content, re.MULTILINE):
        existing = m.group(1).strip().strip("'\"")
        if existing == title:
            print(f"ERROR: 類似教訓あり: {existing} (類似度: 100%)", file=sys.stderr)
            print("強制登録: --force フラグを追加", file=sys.stderr)
            sys.exit(1)

max_id = 0
for m in re.finditer(r"^- id:[ \t]*L(\d+)[ \t]*$", content, re.MULTILINE):
    max_id = max(max_id, int(m.group(1)))
new_id = f"L{max_id + 1:03d}"

def sq(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"

def block_scalar(prefix: str, value: str) -> list[str]:
    text = value.rstrip("\n") or "未設定"
    leading = len(prefix) - len(prefix.lstrip(" "))
    content_indent = " " * (leading + 2)
    lines = [f"{prefix}: >-"]
    for line in text.splitlines():
        lines.append(f"{content_indent}{line}")
    return lines

entry = []
if content and not content.endswith("\n"):
    entry.append("")
entry.append(f"- id: {new_id}")
entry.append(f"  title: {sq(title)}")
entry.extend(block_scalar("  summary", detail))
entry.extend(block_scalar("  when", title + " の状況で判断・実装・検証する時"))
entry.extend(block_scalar("  how", detail + " を根拠に、実体確認と再発防止の手順を先に通す"))
entry.append("  category: 未分類")
if source_cmd:
    entry.append(f"  source: {sq(source_cmd)}")
if origin:
    entry.append(f"  origin: {sq(origin)}")
entry.extend(block_scalar("  enforcement", enforcement))
entry.append(f"  automated: {'false' if enforcement == '未自動化' else 'true'}")
entry.append(f"  date: {sq(timestamp)}")
entry.append("  tags:")
for tag in tags or ["universal"]:
    entry.append(f"  - {tag}")
if target_files:
    entry.append("  target_files:")
    for target_file in target_files[:5]:
        entry.append(f"  - {sq(target_file)}")
entry.append("  helpful_count: 0")
entry.append("  harmful_count: 0")
entry.append("  injection_count: 0")
entry.append(f"  last_referenced: {sq(timestamp)}")

try:
    existing = yaml.safe_load(content) or {}
except yaml.YAMLError as exc:
    print(f"ERROR: existing lesson YAML is invalid; preserving {path}: {exc}", file=sys.stderr)
    sys.exit(1)
if (not isinstance(existing, dict) or "lessons" not in existing
        or (existing.get("lessons") is not None and not isinstance(existing.get("lessons"), list))):
    print(f"ERROR: existing lesson YAML has invalid schema; preserving {path}", file=sys.stderr)
    sys.exit(1)

candidate = content
if candidate and not candidate.endswith("\n"):
    candidate += "\n"
candidate += "\n".join(entry) + "\n"
try:
    generated = yaml.safe_load(candidate) or {}
except yaml.YAMLError as exc:
    print(f"ERROR: generated lesson YAML is invalid; preserving {path}: {exc}", file=sys.stderr)
    sys.exit(1)
if not isinstance(generated, dict) or not isinstance(generated.get("lessons"), list):
    print(f"ERROR: generated lesson YAML has invalid schema; preserving {path}", file=sys.stderr)
    sys.exit(1)

directory = os.path.dirname(path) or "."
fd, temporary = tempfile.mkstemp(prefix=".lesson-write.", suffix=".tmp", dir=directory)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(candidate)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(temporary, path)
except BaseException:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
    raise

print(f"{new_id} added to {path}")
PY
    ) 200>"$lockfile" || return 1

    # cmd_108: Write .done flag for cmd_complete_gate
    if [ -n "$CMD_ID" ]; then
        gates_dir="$SCRIPT_DIR/queue/gates/${CMD_ID}"
        mkdir -p "$gates_dir"
        echo "timestamp: $(date +%Y-%m-%dT%H:%M:%S)" > "$gates_dir/lesson.done"
        echo "source: lesson_write" >> "$gates_dir/lesson.done"
    fi

    echo "REFLUX_CHECK: (1)PI=SKIPPED (2)RUNBOOK=SKIPPED (3)INSTRUCTIONS=SKIPPED"
    return 0
}

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
    LOCKFILE="$(lock_path "$LESSONS_FILE")"
    LEDGER_WRITER="$SCRIPT_DIR/scripts/ledger_writer.sh"

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
    # Old-format lesson (no tags line) → insert tags line after heading
    insert_pos = heading_idx + 1
    lines.insert(insert_pos, f'- **tags**: {tags_str}')
    print(f'{retag_id} tags: (none) → {tags_str} [inserted]')

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
    LOCKFILE="$(lock_path "$LESSONS_FILE")"

    if [ ! -f "$LESSONS_FILE" ]; then
        echo "ERROR: $LESSONS_FILE not found." >&2
        exit 1
    fi

    TIMESTAMP=$(date "+%Y-%m-%d")

    # Emit an update operation; the publisher performs the atomic ledger write.
    (
        flock -w 10 200 || { echo "ERROR: Could not acquire lock" >&2; exit 1; }
        if grep -A40 -m1 "^### L\?$(printf '%s' "$RETIRE_ID" | sed 's/^L//'):" "$LESSONS_FILE" | grep -q '\*\*retired\*\*'; then
            echo "$RETIRE_ID is already retired"
            exit 0
        fi
        normalized_id="$(printf '%s' "$RETIRE_ID" | sed 's/^L//' | awk '{printf "L%03d", $1}')"
        if [[ -x "$LEDGER_WRITER" ]]; then
            LEDGER_SOURCE_FILE="$LESSONS_FILE" LEDGER_LESSONS_FILE="$LESSONS_FILE" \
                bash "$LEDGER_WRITER" update lessons "$normalized_id" status=retired retired_at="$TIMESTAMP" --expect status=
        else
            LESSONS_FILE_ENV="$LESSONS_FILE" RETIRE_ID_ENV="$normalized_id" TIMESTAMP_ENV="$TIMESTAMP" python3 - <<'PY'
import os, re
path=os.environ['LESSONS_FILE_ENV']; ident=os.environ['RETIRE_ID_ENV']
lines=open(path,encoding='utf-8').read().splitlines()
start=next((i for i,line in enumerate(lines) if re.match(r'^### '+re.escape(ident)+r'\s*[:：]',line)),None)
if start is None:
    print(f'ERROR: {ident} not found in {path}', file=__import__('sys').stderr)
    raise SystemExit(1)
end=next((i for i in range(start+1,len(lines)) if lines[i].startswith('### L')),len(lines))
if any('**retired**' in line for line in lines[start:end]): raise SystemExit(0)
insert=start+1
while insert<end and (lines[insert].strip()=='' or lines[insert].lstrip().startswith('- **')): insert+=1
lines[insert:insert]=['- **retired**: true','- **retired_at**: '+os.environ['TIMESTAMP_ENV']]
open(path,'w',encoding='utf-8').write('\n'.join(lines)+'\n')
PY
        fi
        echo "$normalized_id retired in $LESSONS_FILE"

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
LOCKFILE="$(lock_path "$LESSONS_FILE")"
LEDGER_WRITER="$SCRIPT_DIR/scripts/ledger_writer.sh"
LEDGER_ENTRY_FILE="$(mktemp)"

# Verify lessons file exists
if [ ! -f "$LESSONS_FILE" ]; then
    if write_project_yaml_lesson; then
        exit 0
    fi
    echo "ERROR: $LESSONS_FILE not found." >&2
    exit 1
fi

TIMESTAMP=$(date "+%Y-%m-%d")
RESOLVED_ORIGIN="$(require_origin_value)"

# 忍者成長速度改善2: source_cmdのtarget_pathを教訓のtarget_filesに自動設定
_LW_TARGET_FILES=""
if [ -n "${TARGET_FILES:-}" ]; then
    _LW_TARGET_FILES="$TARGET_FILES"
elif [ -n "${SOURCE_CMD:-}" ]; then
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
trap 'rc=$?; rm -f "$LESSON_ID_FILE"; lesson_write_record_total "$rc"; exit "$rc"' EXIT

# Atomic append with flock (3 retries)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 10 200 || exit 1

        # Lesson IDs are also materialized in the routed context index. That
        # index can be ahead of lessons.md while reflux/migration work is being
        # reconciled. Allocating from lessons.md alone then reuses an existing
        # context ID and silently skips a different lesson's context append.
        _lw_context_max=0
        resolve_lesson_context_route "$PROJECT_ID" "${SUBDOMAIN:-}"
        _lw_context_path=""
        if [ -n "${CONTEXT_ROUTE_FILE:-}" ]; then
            _lw_context_path="$SCRIPT_DIR/$CONTEXT_ROUTE_FILE"
        fi
        if [ -f "$_lw_context_path" ]; then
            _lw_context_max=$(awk '
                /^-[[:space:]]L[0-9]+:/ {
                    id = $2
                    sub(/^L/, "", id)
                    sub(/:.*/, "", id)
                    n = id + 0
                    if (n > max_id) max_id = n
                }
                /<!--[[:space:]]*last_synced_lesson:[[:space:]]*L[0-9]+[[:space:]]*-->/ {
                    line = $0
                    sub(/.*last_synced_lesson:[[:space:]]*L/, "", line)
                    sub(/[[:space:]]*-->.*/, "", line)
                    n = line + 0
                    if (n > max_id) max_id = n
                }
                END { print max_id + 0 }
            ' "$_lw_context_path")
        fi

        # Find max SSOT ID and exact duplicate in one awk process. Bash
        # line-by-line scans are costly on WSL2/NTFS for the large lessons.md.
        _lw_scan=$(
            awk -v title="$TITLE" -v force="${FORCE:-0}" -v context_max="$_lw_context_max" '
                BEGIN { max_id = context_max + 0 }
                /^##[[:space:]][0-9]+\./ {
                    id = $0
                    sub(/^##[[:space:]]*/, "", id)
                    sub(/\..*$/, "", id)
                    n = id + 0
                    if (n > max_id) max_id = n
                    next
                }
                /^###[[:space:]]L[0-9]+:/ {
                    id = $0
                    sub(/^###[[:space:]]L/, "", id)
                    sub(/:.*/, "", id)
                    n = id + 0
                    if (n > max_id) max_id = n

                    if (force != "1") {
                        lesson_title = $0
                        sub(/^###[[:space:]]L[0-9]+:[[:space:]]*/, "", lesson_title)
                        if (lesson_title == title && duplicate_id == "") {
                            duplicate_id = sprintf("L%03d", n)
                            duplicate_title = lesson_title
                        }
                    }
                }
                END {
                    printf "%d\t%s\t%s\n", max_id, duplicate_id, duplicate_title
                }
            ' "$LESSONS_FILE"
        )
        IFS=$'\t' read -r _lw_max_id _lw_duplicate_id _lw_duplicate_title <<< "$_lw_scan"
        _lw_new_id=$(( _lw_max_id + 1 ))
        printf -v _lw_new_id_str 'L%03d' "$_lw_new_id"

        if [ -n "$_lw_duplicate_id" ]; then
            printf 'ERROR: 類似教訓あり: %s: %s (類似度: 100%%)\n' "$_lw_duplicate_id" "$_lw_duplicate_title" >&2
            printf '強制登録: --force フラグを追加\n' >&2
            echo "duplicate_error" > "${LESSON_ID_FILE}.err" 2>/dev/null || true
            exit 1
        fi

        # ── Combined Python: Jaccard similarity + auto-tag (single spawn) ───────
        # Jaccard: FORCE!=1 and title has ≥3 ASCII tokens
        # Auto-tag: TAGS empty and lesson_tags.yaml exists
        # Both run → 1 Python spawn instead of 2 (saves ~50ms on WSL2 NTFS)
        _lw_do_sim=0
        if [ "${FORCE:-0}" != "1" ]; then
            _lw_tok=0; _lw_rest="$TITLE"
            while [[ "$_lw_rest" =~ [a-zA-Z][a-zA-Z0-9_.]*[a-zA-Z0-9]|[a-zA-Z0-9]{2,} ]]; do
                (( _lw_tok++ ))
                _lw_rest="${_lw_rest#*"${BASH_REMATCH[0]}"}"
                [[ $_lw_tok -ge 3 ]] && break
            done
            (( _lw_tok >= 3 )) && _lw_do_sim=1
        fi

        _lw_do_tags=0
        if [ -z "${TAGS:-}" ] && [ -f "$SCRIPT_DIR/config/lesson_tags.yaml" ]; then
            _lw_do_tags=1
        fi

        _lw_auto_tags=""
        if [ "$_lw_do_sim" = "1" ] || [ "$_lw_do_tags" = "1" ]; then
            _lw_auto_tags=$(
                LESSONS_FILE_ENV="$LESSONS_FILE" \
                TITLE_ENV="$TITLE" \
                LESSON_TEXT_ENV="${TITLE} ${DETAIL}" \
                TAGS_FILE_ENV="$SCRIPT_DIR/config/lesson_tags.yaml" \
                DO_SIM_ENV="$_lw_do_sim" \
                DO_TAGS_ENV="$_lw_do_tags" \
                python3 <<'PYCOMBINED'
import re, yaml, os, sys

do_sim  = os.environ.get('DO_SIM_ENV',  '0') == '1'
do_tags = os.environ.get('DO_TAGS_ENV', '0') == '1'

# ── Auto-tag ──────────────────────────────────────────────────────────────
auto_tags = []
if do_tags:
    text      = os.environ.get('LESSON_TEXT_ENV', '')
    tags_file = os.environ.get('TAGS_FILE_ENV',   '')
    try:
        with open(tags_file) as f:
            rules = yaml.safe_load(f).get('tag_rules', [])
        for r in rules:
            for p in r.get('patterns', []):
                if re.search(p, text):
                    auto_tags.append(r['tag'])
                    break
    except Exception:
        pass

# ── Jaccard similarity ────────────────────────────────────────────────────
if do_sim:
    lessons_file = os.environ.get('LESSONS_FILE_ENV', '')
    new_title    = os.environ.get('TITLE_ENV', '')
    threshold    = 0.6
    min_tokens   = 3

    def tokenize(t):
        tokens = set()
        for tok in re.findall(r'[a-zA-Z][a-zA-Z0-9_.]*[a-zA-Z0-9]|[a-zA-Z0-9]{2,}', t.lower()):
            tokens.add(tok)
        jp = re.sub(r'[\x00-\x7f\s]', '', t)
        for i in range(len(jp) - 1):
            tokens.add(jp[i:i+2])
        return tokens

    def jaccard(a, b):
        u = a | b
        return len(a & b) / len(u) if u else 0.0

    new_tok = tokenize(new_title)
    if len(new_tok) >= min_tokens:
        best = None
        pat = re.compile(r'^### L(\d+): (.+)$', re.MULTILINE)
        try:
            with open(lessons_file, encoding='utf-8') as f:
                content = f.read()
            for m in pat.finditer(content):
                eid  = f'L{int(m.group(1)):03d}'
                etit = m.group(2).strip()
                etok = tokenize(etit)
                if len(etok) < min_tokens:
                    continue
                sc = jaccard(new_tok, etok)
                if sc >= threshold and (best is None or sc > best[0]):
                    best = (sc, eid, etit)
            if best:
                sc, eid, etit = best
                print(f'WARN: 類似教訓候補: {eid}: {etit} (Jaccard: {sc:.2f})', file=sys.stderr)
        except Exception:
            pass

print(','.join(auto_tags[:3]))
PYCOMBINED
            )
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
        _lw_origin="$RESOLVED_ORIGIN"

        # Build and append new entry
        {
            printf '\n### %s: %s\n' "$_lw_new_id_str" "$TITLE"
            printf -- '- **日付**: %s\n' "$TIMESTAMP"
            [ -n "${SOURCE_CMD:-}" ] && printf -- '- **出典**: %s\n' "$SOURCE_CMD"
            printf -- '- **記録者**: %s\n' "${AUTHOR:-karo}"
            [ "${STATUS:-confirmed}" = "draft" ] && printf -- '- **status**: draft\n'
            [ -n "${SOURCE_MARKER:-}" ] && printf -- '- **source**: %s\n' "$SOURCE_MARKER"
            printf -- '- **tags**: %s\n' "$_lw_tags_yaml"
            [ -n "${SUBDOMAIN:-}" ] && printf -- '- **subdomain**: %s\n' "$SUBDOMAIN"
            [ -n "$_LW_TARGET_FILES" ] && printf -- '- **target_files**: [%s]\n' "$_LW_TARGET_FILES"
            [ -n "$_lw_origin" ] && printf -- '- **origin**: %s\n' "$_lw_origin"
            printf -- '- **enforcement**: %s\n' "${ENFORCEMENT:-未自動化}"
            printf -- '- **when**: %s\n' "$_lw_when"
            printf -- '- **how**: %s\n' "$_lw_how"
            [ -n "${IF_COND:-}" ] && printf -- '- **if**: %s\n' "$IF_COND"
            [ -n "${THEN_ACTION:-}" ] && printf -- '- **then**: %s\n' "$THEN_ACTION"
            [ -n "${BECAUSE_REASON:-}" ] && printf -- '- **because**: %s\n' "$BECAUSE_REASON"
            printf -- '- %s\n' "$DETAIL"
        } > "$LEDGER_ENTRY_FILE"

        if [[ -x "$LEDGER_WRITER" ]]; then
            LEDGER_SOURCE_FILE="$LESSONS_FILE" LEDGER_LESSONS_FILE="$LESSONS_FILE" \
                bash "$LEDGER_WRITER" append lessons "$LEDGER_ENTRY_FILE" >/dev/null
        else
            cat "$LEDGER_ENTRY_FILE" >> "$LESSONS_FILE"
        fi

        printf '%s' "$_lw_new_id_str" > "${LESSON_ID_FILE:-/dev/null}"
        echo "$_lw_new_id_str added to $LESSONS_FILE"

    ) 200>"$LOCKFILE"; then
        # AC3: Auto-call sync_lessons.sh after write (non-blocking: 失敗しても後続処理を続行)
        if [ "${LESSON_WRITE_SKIP_SYNC:-0}" != "1" ]; then
            if [ "${LESSON_WRITE_SYNC_MODE:-async}" = "sync" ]; then
                bash "$SCRIPT_DIR/scripts/sync_lessons.sh" "$PROJECT_ID" || echo "WARN: sync_lessons.sh failed (non-blocking — lesson is written)" >&2
            else
                mkdir -p "$SCRIPT_DIR/logs"
                (
                    bash "$SCRIPT_DIR/scripts/sync_lessons.sh" "$PROJECT_ID" \
                        || echo "WARN: sync_lessons.sh failed (non-blocking — lesson is written)" >&2
                ) >> "$SCRIPT_DIR/logs/lesson_write_sync_async.log" 2>&1 &
                disown 2>/dev/null || true
            fi
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
            if _semantic_payload=$(LESSON_ID_ENV="$NEW_LESSON_ID" TITLE_ENV="$TITLE" DETAIL_ENV="$DETAIL" SOURCE_CMD_ENV="$SOURCE_CMD" ORIGIN_ENV="$(resolve_origin_value)" python3 - <<'PY' 2>/dev/null
import json
import os

print(json.dumps({
    "id": os.environ.get("LESSON_ID_ENV", ""),
    "title": os.environ.get("TITLE_ENV", ""),
    "detail": os.environ.get("DETAIL_ENV", ""),
    "source_cmd": os.environ.get("SOURCE_CMD_ENV", ""),
    "origin": os.environ.get("ORIGIN_ENV", ""),
}, ensure_ascii=False))
PY
            ); then
                (bash "$SCRIPT_DIR/scripts/semantic_index_update.sh" lesson "$_semantic_payload" >/dev/null 2>&1 || true) &
            fi
        fi
        if [ -f "$SCRIPT_DIR/scripts/semantic_map_generate.sh" ]; then
            (bash "$SCRIPT_DIR/scripts/semantic_map_generate.sh" >/dev/null 2>&1 || true) &
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
            # A repository without a runbook layer cannot be missing a match
            # inside that layer.  Treat absence of docs/rule/*.md as SKIPPED;
            # otherwise every English-bearing lesson emits a permanent false
            # WARN and operators learn to ignore real reflux gaps.
            REFLUX_RUNBOOK="SKIPPED"
            REFLUX_INSTRUCTIONS="MISSING"

            if [ -n "$REFLUX_KEYWORDS" ]; then
                # (1) PI check: projects/{project}.yaml の production_invariants 関連
                PI_FILE="$SCRIPT_DIR/projects/${PROJECT_ID}.yaml"
                if [ -f "$PI_FILE" ] && grep -qE "$REFLUX_KEYWORDS" "$PI_FILE" 2>/dev/null; then
                    REFLUX_PI="FOUND"
                fi

                # (2) Runbook check: only a lesson whose declared scope is a
                # runbook can be missing from the runbook layer.  The mere
                # existence of an unrelated docs/rule/bash-conventions.md
                # must not turn every infra lesson into a permanent warning.
                REFLUX_RUNBOOK_RELEVANT=false
                if [[ "${TARGET_FILES:-}" == *"docs/rule"* ]] \
                    || [[ ",${TAGS:-}," == *",runbook,"* ]] \
                    || [[ "${TITLE} ${DETAIL}" =~ [Rr][Uu][Nn][Bb][Oo][Oo][Kk]|ランブック ]]; then
                    REFLUX_RUNBOOK_RELEVANT=true
                fi
                if [ "$REFLUX_RUNBOOK_RELEVANT" = true ]; then
                    REFLUX_RUNBOOK="MISSING"
                    if [ -d "$SCRIPT_DIR/docs/rule" ] \
                        && find "$SCRIPT_DIR/docs/rule" -name "*.md" -print0 2>/dev/null | xargs -0 -r grep -lqE "$REFLUX_KEYWORDS" 2>/dev/null; then
                        REFLUX_RUNBOOK="FOUND"
                    fi
                fi

                # (3) Instructions check: instructions/*.md
                if grep -rlE "$REFLUX_KEYWORDS" "$SCRIPT_DIR/instructions/"*.md >/dev/null 2>&1; then
                    REFLUX_INSTRUCTIONS="FOUND"
                fi
            else
                # REFLUX_KEYWORDSが空（日本語のみのテキスト等）— チェック不可のためSKIPPED
                REFLUX_PI="SKIPPED"
                REFLUX_RUNBOOK="SKIPPED"
                REFLUX_INSTRUCTIONS="SKIPPED"
            fi

            echo "REFLUX_CHECK: (1)PI=$REFLUX_PI (2)RUNBOOK=$REFLUX_RUNBOOK (3)INSTRUCTIONS=$REFLUX_INSTRUCTIONS"
            if [ "$REFLUX_PI" = "MISSING" ] || [ "$REFLUX_RUNBOOK" = "MISSING" ] || [ "$REFLUX_INSTRUCTIONS" = "MISSING" ]; then
                echo "WARN: 還流漏れの可能性あり。MISSING箇所にこの教訓の知見を反映すべきか検討せよ"
            fi
        fi
        # DB INSERT: eventsテーブルへ教訓記録（非ブロック）
        if [ -f "$SCRIPT_DIR/scripts/memory_db_live_insert_async.py" ] && [ -n "$NEW_LESSON_ID" ]; then
            python3 "$SCRIPT_DIR/scripts/memory_db_live_insert_async.py" lesson \
                --lesson-id "$NEW_LESSON_ID" \
                --title "$TITLE" \
                --detail "$DETAIL" \
                --source-cmd "${SOURCE_CMD:-}" \
                --agent "${AUTHOR:-karo}" \
                --ts "$(date -Is)" \
                --project "$PROJECT_ID" \
                --source-file "$LESSONS_FILE" >/dev/null 2>&1 &
            disown 2>/dev/null || true
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
