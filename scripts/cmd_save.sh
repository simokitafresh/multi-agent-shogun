#!/usr/bin/env bash
# semantic-links: [[ゲート品質統合フレームワーク]]
# ============================================================
# cmd_save.sh
# 将軍がEdit toolでshogun_to_karo.yamlに書いたcmdブロックの保存前安全チェック
#
# Usage: bash scripts/cmd_save.sh [--preflight] <cmd_id>
#   cmd_id: 数字のみ（例: 1148）またはcmd_付き（例: cmd_1148）
#   --preflight: 同一検査を実行するが、ログ/履歴/通知/YAML補完を書き込まない
#
# チェック内容:
#   1. cmdブロックがshogun_to_karo.yamlに存在するか
#   2. archive/cmds/配下の完了済みcmd_idとの重複チェック
#   3. quality_gateフィールド検査（q1_firefighting, q2_learning, q3_next_quality, q4_depth[WARNING]）
#   4. flock競合検出（家老との同時書き込み防止）
#   11.10. cmd-chronicle.md強制検索（title/purposeから類似過去cmdをINFO表示）
#   12. 内容重複チェック（キュー直近20件+archive直近20ファイルのtitle+purposeとの類似度比較）
# ============================================================
set -euo pipefail
trap '' PIPE  # SIGPIPE無視: 大量INFO出力(semantic_search等)のパイプ破損でスクリプト死亡を防止(2026-06-26)

# --- Usage ---
if [[ $# -lt 1 ]]; then
    echo "Usage: bash scripts/cmd_save.sh [--preflight] <cmd_id>" >&2
    echo "  cmd_id: 数字のみ（例: 1148）またはcmd_付き（例: cmd_1148）" >&2
    echo "  --preflight: 保存前の事前検証。判定は保存時と同一、累計記録/履歴/通知/自動補完の書込みなし" >&2
    exit 1
fi

CMD_SAVE_PREFLIGHT_ONLY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --preflight|--check-only)
            CMD_SAVE_PREFLIGHT_ONLY=1
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Usage: bash scripts/cmd_save.sh [--preflight] <cmd_id>" >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -lt 1 ]]; then
    echo "Usage: bash scripts/cmd_save.sh [--preflight] <cmd_id>" >&2
    echo "  cmd_id: 数字のみ（例: 1148）またはcmd_付き（例: cmd_1148）" >&2
    exit 1
fi

SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
case "$SCRIPT_PATH" in
    */*) SCRIPT_DIR="${SCRIPT_PATH%/*}" ;;
    *) SCRIPT_DIR="." ;;
esac
if [[ "$SCRIPT_DIR" != /* ]]; then
    SCRIPT_DIR="$PWD/$SCRIPT_DIR"
fi
PROJECT_DIR="${SCRIPT_DIR%/*}"

QUEUE_FILE="${CMD_SAVE_QUEUE_FILE:-$PROJECT_DIR/queue/shogun_to_karo.yaml}"
ARCHIVE_CMD_DIR="${CMD_SAVE_ARCHIVE_CMD_DIR:-$PROJECT_DIR/queue/archive/cmds}"
QUALITY_LOG_FILE="${CMD_QUALITY_LOG_FILE:-$PROJECT_DIR/logs/cmd_design_quality.yaml}"
QUALITY_LOG_SCAN_LINES="${CMD_QUALITY_LOG_SCAN_LINES:-5000}"
GATE_FIRE_LOG_FILE="${GATE_FIRE_LOG_FILE:-$PROJECT_DIR/logs/gate_fire_log.yaml}"
LOCK_FILE="${CMD_SAVE_LOCK_FILE:-/tmp/shogun_to_karo.lock}"
CMD_SAVE_LAST_CMD_FILE="${CMD_SAVE_LAST_CMD_FILE:-$PROJECT_DIR/logs/cmd_save_last_cmd.txt}"
CMD_SAVE_SHOGUN_LESSONS_FILE="${CMD_SAVE_SHOGUN_LESSONS_FILE:-$PROJECT_DIR/projects/infra/lessons_shogun.yaml}"
CMD_SAVE_SHOGUN_LESSON_ACK_FILE="${CMD_SAVE_SHOGUN_LESSON_ACK_FILE:-$PROJECT_DIR/queue/shogun_lesson_ack.yaml}"
# CMD_SAVE_SHOGUN_LESSON_LIMIT="${CMD_SAVE_SHOGUN_LESSON_LIMIT:-35}"  # 撤去済(殿裁定2026-07-23 提案A)。未使用変数として残さない
PREFLIGHT_AUTOLEARN_FILE="${CMD_SAVE_PREFLIGHT_AUTOLEARN_FILE:-$PROJECT_DIR/logs/preflight_autolearn.txt}"
LORD_CONVERSATION_FILE="${CMD_SAVE_LORD_CONVERSATION_FILE:-$PROJECT_DIR/queue/lord_conversation.jsonl}"
CMD_CHRONICLE_FILE="${CMD_SAVE_CMD_CHRONICLE_FILE:-$PROJECT_DIR/context/cmd-chronicle.md}"
CMD_SAVE_LORD_CONVERSATION_MAX_LINES="${CMD_SAVE_LORD_CONVERSATION_MAX_LINES:-200}"
CMD_SAVE_LORD_CONVERSATION_MAX_BYTES="${CMD_SAVE_LORD_CONVERSATION_MAX_BYTES:-2097152}"
CMD_SAVE_CHRONICLE_MAX_LINES="${CMD_SAVE_CHRONICLE_MAX_LINES:-1200}"
CMD_SAVE_CHRONICLE_MAX_BYTES="${CMD_SAVE_CHRONICLE_MAX_BYTES:-2097152}"
MEMORY_DB_LIVE_INSERT="${MEMORY_DB_LIVE_INSERT:-$PROJECT_DIR/scripts/memory_db_live_insert_async.py}"
if [[ ! -f "$MEMORY_DB_LIVE_INSERT" ]]; then
    MEMORY_DB_LIVE_INSERT="$PROJECT_DIR/scripts/memory_db_live_insert.py"
fi

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/firefighting_keywords.sh"
# shellcheck source=scripts/lib/gate_hook_quality_contract.sh
source "$SCRIPT_DIR/lib/gate_hook_quality_contract.sh"
# shellcheck source=scripts/lib/cmd_shared_preflight.sh
source "$SCRIPT_DIR/lib/cmd_shared_preflight.sh"
# shellcheck source=scripts/lib/defense_overhead_writer.sh
source "$SCRIPT_DIR/lib/defense_overhead_writer.sh"

EXTRACT_COMMAND_FILES_SCRIPT="${CMD_SAVE_EXTRACT_COMMAND_FILES_SCRIPT:-$SCRIPT_DIR/lib/extract_command_files.sh}"

CMD_DIAGNOSIS=""
PRIOR_ATTEMPT_COUNT=0
CMD_SAVE_STDERR_LOG="/dev/null"
CMD_SAVE_PERSISTENT_STDERR_LOG="${CMD_SAVE_PERSISTENT_STDERR_LOG:-$PROJECT_DIR/logs/cmd_save_stderr.log}"
# スキャンファイルキャッシュ: PID固定パスを使いサブシェル経由でも確実にキャッシュが効く
# .tmp=YAML版(awk処理用) .json=JSON版(Python高速パース用, yaml.safe_load→json.loadで7x高速化)
CMD_SAVE_SCAN_FILE_CACHE="/tmp/cmd_save_scan_$$.tmp"
CMD_SAVE_SCAN_JSON_CACHE="/tmp/cmd_save_scan_$$.json"
# semantic_search セッション内キャッシュ: TMUX_PANEベース(安定)でpreflight→save間でも共有
# TMUX_PANEはpane固有でセッション内で不変。PPIDはBashサブプロセスごとに変わるため不適。
# クエリのsha256ハッシュをファイル名にし、同一クエリの2回目呼び出しをスキップする
_SEMANTIC_SESSION_CACHE_KEY="${TMUX_PANE:-${PPID}}"
_SEMANTIC_SESSION_CACHE_KEY="${_SEMANTIC_SESSION_CACHE_KEY//%/pane}"  # %8 → pane8
_SEMANTIC_SESSION_CACHE_DIR="${TMPDIR:-/tmp}/cmd_save_semantic_${_SEMANTIC_SESSION_CACHE_KEY}"
_CMD_SAVE_METADATA_CACHE_DIR="${TMPDIR:-/tmp}/cmd_save_metadata_${_SEMANTIC_SESSION_CACHE_KEY}"
CMD_SAVE_SEMANTIC_CACHE_READY=0
CMD_SAVE_ACCUMULATE_BLOCKS="${CMD_SAVE_ACCUMULATE_BLOCKS:-1}"
CMD_SAVE_AC_BLOCK_CACHE_READY=0
CMD_SAVE_AC_BLOCK_CACHE=""
CMD_SAVE_COMMAND_BLOCK_CACHE_READY=0
CMD_SAVE_COMMAND_BLOCK_CACHE=""
BLOCK_DURATION_MINUTES=0
BLOCK_RETRY_NUDGE="止まるな、修正して再実行せよ"
BLOCK_RETRY_NUDGE_EMITTED=0
BLOCK_COUNT=0
CMD_BLOCK_LOADED=0
CMD_BLOCK_FOUND=0
CMD_BLOCK_CACHE_LOADED=0
CMD_BLOCK_PROJECT=""
declare -a BLOCK_REASONS=()
declare -a WARN_REASONS=()
declare -a BLOCK_CHECKS=()
declare -A CMD_BLOCK_CACHE=()

# 内部フェーズ計装(cmd_4169): defense_overhead_writer.sh経由でsource:cmd_saveへwall_ms記録。
# 判定ロジック(BLOCK_COUNT/WARN_COUNT)には一切関与しない。setに-uがあるため空でも常に宣言する。
declare -a CMD_SAVE_PHASE_EVENTS=()
CMD_SAVE_PHASE_LAST_US=""
CMD_SAVE_RUN_ID=""
CMD_SAVE_CHECKS_MAIN_LAST_US=""
# 全体wall計測(2026-08-04 殿指示『計測可能にせよ』): フェーズ計装済み区間(合計≈12s/回)と
# 実wall(実測≈150s/回)の差分≈9割が台帳の外にあった計測盲点を塞ぐ。save_total=script開始→EXITの全区間。
CMD_SAVE_TOTAL_T0_US="${EPOCHREALTIME/./}"
CMD_SAVE_TOTAL_T0_US="${CMD_SAVE_TOTAL_T0_US:0:16}"

cmd_save_phase_mark() {
    local name="$1" now_us wall_ms
    now_us="${EPOCHREALTIME/./}"
    now_us="${now_us:0:16}"
    if [[ -n "${CMD_SAVE_PHASE_LAST_US:-}" ]]; then
        wall_ms=$(( (now_us - CMD_SAVE_PHASE_LAST_US + 999) / 1000 ))
        CMD_SAVE_PHASE_EVENTS+=("$name" "$wall_ms")
    fi
    CMD_SAVE_PHASE_LAST_US="$now_us"
}

# checks_mainの親totalを維持したまま、残余ボトルネックを恒久観測する非加算子区間。
# 子区間は命名規約 checks_main.* で台帳へ出すため、集計時に親へ加算してはならない。
cmd_save_checks_main_mark() {
    local name="$1" now_us wall_ms
    now_us="${EPOCHREALTIME/./}"
    now_us="${now_us:0:16}"
    if [[ -n "${CMD_SAVE_CHECKS_MAIN_LAST_US:-}" ]]; then
        wall_ms=$(( (now_us - CMD_SAVE_CHECKS_MAIN_LAST_US + 999) / 1000 ))
        CMD_SAVE_PHASE_EVENTS+=("checks_main.${name}" "$wall_ms")
    fi
    CMD_SAVE_CHECKS_MAIN_LAST_US="$now_us"
}

# 非同期INFO表示(semantic_search/memory_db照会)は`&`で親フローをブロックしないため、
# cmd_save_phase_markの区間計測に乗らない。関数自身の総実行時間を自己計測しPASS固定で記録する
# (これらはgate判定に無関係なINFO専用処理のため、verdictはmemory_db_token_search_overheadの
# 既存手動記録に倣いPASS固定)。
cmd_save_timed_bg() {
    local check_id="$1" _t_start _t_end _t_ms _rc
    shift
    _t_start="${EPOCHREALTIME/./}"
    _t_start="${_t_start:0:16}"
    set +e
    "$@"
    _rc=$?
    set -e
    _t_end="${EPOCHREALTIME/./}"
    _t_end="${_t_end:0:16}"
    _t_ms=$(( (_t_end - _t_start + 999) / 1000 ))
    defense_overhead_write_async cmd_save "$check_id" "$_t_ms" PASS "${CMD_ID:-cmd_unknown}-${check_id}-$$-${_t_end}" || true
    return "$_rc"
}

# Normal output is a decision surface, not a trace dump.  Buffer one invocation
# so the final verdict can be printed first, followed by every distinct
# BLOCK/WARN result in one line.  Full INFO, trigger-location, and semantic alias
# traces remain available with CMD_SAVE_DEBUG=1.
cmd_save_output_filter() {
    if [[ "${CMD_SAVE_DEBUG:-0}" == "1" ]]; then
        cat
        return 0
    fi

    awk '
        { lines[NR] = $0 }
        /^保存確認NG:/ { failed = 1; summary = $0 }
        END {
            if (!failed) {
                for (i = 1; i <= NR; i++) print lines[i]
                exit
            }

            print "判定サマリ: " summary
            for (i = 1; i <= NR; i++) {
                line = lines[i]
                keep = (line ~ /^止まるな、修正して再実行せよ$/ ||
                        line ~ /^BLOCK:/ ||
                        line ~ /^  未記入:/ ||
                        line ~ /unique_cmds=/ ||
                        line ~ /^★ BLOCK SUMMARY:/ ||
                        line ~ /^WARN(ING)?:/ ||
                        line ~ /^ERROR:/ ||
                        line ~ /^診断:/ ||
                        line ~ /^★ (診断せよ|修正前に):/)
                if (keep && !seen[line]++) print line
            }
            print "詳細: CMD_SAVE_DEBUG=1 で判定位置・semantic alias・解消例を表示"
        }
    '
}

exec 9>&1
exec > >(cmd_save_output_filter >&9) 2>&1

cmd_save_hash_text() {
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha256sum | cut -d' ' -f1
    else
        printf '%s' "$1" | cksum | cut -d' ' -f1
    fi
}

cmd_save_metadata_cache_file() {
    local label="${1:-metadata}"
    local payload="${2:-${CMD_BLOCK_NC:-}}"
    local cmd_id_part="${CMD_ID:-unknown}"
    local hash
    hash="$(cmd_save_hash_text "$payload")"
    # q11の出力はcmd IDではなく抽出済みqueryだけで決まる。同一sessionで
    # 同じqueryを別cmd IDから検索した場合も再利用し、外部semantic検索を重ねない。
    # 他labelはcmd本文・時系列へ依存し得るため、従来どおりcmd IDで分離する。
    [[ "$label" == "q11_semantic" ]] && cmd_id_part="query"
    mkdir -p "$_CMD_SAVE_METADATA_CACHE_DIR" 2>/dev/null || true
    printf '%s/%s_%s_%s.cache' "$_CMD_SAVE_METADATA_CACHE_DIR" "$cmd_id_part" "$label" "$hash"
}

cmd_save_metadata_cache_replay() {
    local label="$1"
    local payload="$2"
    local cache_file
    cache_file="$(cmd_save_metadata_cache_file "$label" "$payload")"
    if [[ -f "$cache_file" ]]; then
        echo "INFO: [CMD_SAVE_CACHE] ${label}: 同一cmd本文hashのpreflight結果を再利用" >&2
        cat "$cache_file" >&2 2>/dev/null || true
        return 0
    fi
    return 1
}

cmd_save_metadata_cache_store() {
    local label="$1"
    local payload="$2"
    local source_file="$3"
    local cache_file
    [[ -f "$source_file" ]] || return 0
    cache_file="$(cmd_save_metadata_cache_file "$label" "$payload")"
    mkdir -p "${cache_file%/*}" 2>/dev/null || true
    cp "$source_file" "$cache_file" 2>/dev/null || true
}

extract_cmd_diagnosis() {
    local block_text="${1:-}"
    awk '
        /quality_gate:/ { in_qg=1; next }
        in_qg && /^[[:space:]]{6,}diagnosis:[[:space:]]*/ {
            sub(/^[[:space:]]*diagnosis:[[:space:]]*/, "")
            gsub(/^["'\'']|["'\'']$/, "")
            print
            exit
        }
        in_qg && /^[[:space:]]{4}[a-zA-Z_][a-zA-Z0-9_]*:/ { exit }
    ' <<< "$block_text"
}

extract_nazenaze_root_cause() {
    [[ -n "${CMD_BLOCK_NC:-}" ]] || return 0
    awk '
        /nazenaze_root_cause:/ {
            sub(/.*nazenaze_root_cause:[[:space:]]*/, "")
            gsub(/^["'"'"']|["'"'"']$/, "")
            if ($0 != "" && $0 != "null") print
            exit
        }
    ' <<< "$CMD_BLOCK_NC"
}

build_unique_block_checks_str() {
    [[ ${#BLOCK_CHECKS[@]} -gt 0 ]] || return 0
    printf '%s\n' "${BLOCK_CHECKS[@]}" | sort -u | paste -sd'|'
}

trim_inline_yaml_scalar() {
    local value="${1:-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [[ "$value" == \"*\" && "$value" == *\" && ${#value} -ge 2 ]]; then
        value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' && ${#value} -ge 2 ]]; then
        value="${value:1:${#value}-2}"
        value="${value//\'\'/\'}"
    fi

    printf '%s' "$value"
}

path_exists_for_cmd_source() {
    local project_wd="${1:-}"
    local fpath="${2:-}"
    [[ -n "$fpath" ]] || return 1

    if [[ "$fpath" = /* ]]; then
        [[ -e "$fpath" ]]
        return $?
    fi

    [[ -n "$project_wd" && -e "$project_wd/$fpath" ]] || [[ -e "$PROJECT_DIR/$fpath" ]]
}

parent_exists_for_cmd_source() {
    local project_wd="${1:-}"
    local fpath="${2:-}"
    [[ -n "$fpath" ]] || return 1

    local parent_dir
    parent_dir=$(dirname "$fpath")
    if [[ "$fpath" = /* ]]; then
        [[ -d "$parent_dir" ]]
        return $?
    fi

    [[ -n "$project_wd" && -d "$project_wd/$parent_dir" ]] || [[ -d "$PROJECT_DIR/$parent_dir" ]]
}

display_parent_for_cmd_source() {
    local project_wd="${1:-}"
    local fpath="${2:-}"

    if [[ "$fpath" = /* ]]; then
        dirname "$fpath"
    else
        printf '%s/%s' "$project_wd" "$(dirname "$fpath")"
    fi
}

update_bulletin_actioned_by_for_cmd() {
    local bulletin_file="${CMD_SAVE_BULLETIN_FILE:-$PROJECT_DIR/queue/bulletin_board.yaml}"
    [[ -f "$bulletin_file" ]] || return 0
    [[ -n "${CMD_ID:-}" ]] || return 0

    local lock_file="${bulletin_file}.lock"
    (
        flock -x 200
        CMD_BLOCK_TEXT="${CMD_BLOCK_NC:-${CMD_BLOCK:-}}" python3 - "$bulletin_file" "$CMD_ID" <<'PY'
import os
import re
import sys
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

_CSAFE = getattr(yaml, "CSafeLoader", yaml.SafeLoader)

bulletin_file, cmd_id = sys.argv[1:3]
block_text = os.environ.get("CMD_BLOCK_TEXT", "")
referenced_ids = set(re.findall(r"\bblt_[0-9A-Za-z_]+\b", block_text))

if not referenced_ids:
    raise SystemExit(0)

with open(bulletin_file, encoding="utf-8") as fh:
    data = yaml.load(fh, Loader=_CSAFE) or {}

entries = data.get("entries")
if not isinstance(entries, list):
    raise SystemExit(0)

updated = []
for entry in entries:
    if not isinstance(entry, dict):
        continue
    if str(entry.get("id", "")) not in referenced_ids:
        continue
    if str(entry.get("action_type", "info")) != "action_required":
        continue
    if str(entry.get("actioned_by", "")).strip():
        continue
    entry["actioned_by"] = cmd_id
    updated.append(str(entry.get("id", "")))

if not updated:
    raise SystemExit(0)

def sq(value):
    return str(value).replace("'", "''")

tmp_file = f"{bulletin_file}.tmp"
with open(tmp_file, "w", encoding="utf-8") as fh:
    fh.write("entries:\n")
    for entry in entries:
        fh.write(f"- id: '{sq(entry.get('id', ''))}'\n")
        fh.write("  content: |-\n")
        text = str(entry.get("content", ""))
        lines = text.splitlines() or [""]
        for line in lines:
            fh.write(f"    {line}\n")
        fh.write(f"  posted_by: '{sq(entry.get('posted_by', ''))}'\n")
        fh.write(f"  posted_at: '{sq(entry.get('posted_at', ''))}'\n")
        rc = entry.get("requires_confirmation")
        if isinstance(rc, list):
            fh.write("  requires_confirmation:\n")
            for agent_name in rc:
                fh.write(f"    - '{sq(agent_name)}'\n")
        elif rc:
            fh.write("  requires_confirmation: true\n")
        else:
            fh.write("  requires_confirmation: false\n")
        at = entry.get("action_type", "info")
        if at not in {"info", "action_required"}:
            at = "info"
        fh.write(f"  action_type: '{sq(at)}'\n")
        fh.write(f"  actioned_by: '{sq(entry.get('actioned_by', ''))}'\n")
        confirmed = entry.get("confirmed_by") or []
        if confirmed:
            fh.write("  confirmed_by:\n")
            for agent in confirmed:
                fh.write(f"    - '{sq(agent)}'\n")
        else:
            fh.write("  confirmed_by: []\n")
        fh.write(f"  status: '{sq(entry.get('status', 'open'))}'\n")

os.replace(tmp_file, bulletin_file)
print(",".join(updated))
PY
    ) 200>"$lock_file"
}

parse_structured_environment_change() {
    local env_change="${1:-}"
    [[ -n "$env_change" ]] || return 1
    local stderr_tmp parsed rc line
    stderr_tmp="$(mktemp)"

    if parsed=$(ENV_CHANGE_TEXT="$env_change" python3 - <<'PY' 2>"$stderr_tmp"
import os
import re
import sys

text = os.environ.get("ENV_CHANGE_TEXT", "")
if not text:
    raise SystemExit(1)

def extract(key: str) -> str:
    pattern = rf'(?:^|;)\s*{key}\s*=\s*([^;]+)'
    match = re.search(pattern, text)
    if not match:
        return ""
    value = match.group(1).strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1]
    return value.strip()

etype = extract("type")
efile = extract("file")
epattern = extract("pattern")

if not (etype and efile and epattern):
    raise SystemExit(1)

print(f"{etype}\t{efile}\t{epattern}")
PY
    ); then
        printf '%s\n' "$parsed"
        rm -f "$stderr_tmp"
        return 0
    else
        rc=$?
    fi
    if [[ -s "$stderr_tmp" ]]; then
        mkdir -p "$(dirname "$CMD_SAVE_PERSISTENT_STDERR_LOG")" 2>/dev/null || true
        while IFS= read -r line; do
            printf '%s parse_structured_environment_change: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$line" >> "$CMD_SAVE_PERSISTENT_STDERR_LOG"
        done < "$stderr_tmp"
    fi
    rm -f "$stderr_tmp"
    return "$rc"
}

cmd_text_matches_pattern() {
    local text="${1:-}"
    local pattern="${2:-}"
    [[ -n "$text" && -n "$pattern" ]] || return 1
    grep -qiE "$pattern" <<< "$text"
}

# cmd_3801: 1回のcmd_save.sh実行内でblock_textは不変(CMD_BLOCK_NC固定)のため、
# 4箇所の呼出元が同一入力を毎回再計算していた(awk+grep数個 x再計算回数のfork重複)。
# 呼出元互換のためpublic関数名は維持し、実処理を_uncachedへ委譲してメモ化する。
is_gate_or_hook_addition_cmd() {
    local block_text="${1:-${CMD_BLOCK_NC:-}}"
    if [[ -n "${_GATE_HOOK_ADDITION_CACHE_SET:-}" && "${_GATE_HOOK_ADDITION_CACHE_KEY-}" == "$block_text" ]]; then
        return "$_GATE_HOOK_ADDITION_CACHE_RESULT"
    fi
    _is_gate_or_hook_addition_cmd_uncached "$block_text"
    _GATE_HOOK_ADDITION_CACHE_RESULT=$?
    _GATE_HOOK_ADDITION_CACHE_SET=1
    _GATE_HOOK_ADDITION_CACHE_KEY="$block_text"
    return "$_GATE_HOOK_ADDITION_CACHE_RESULT"
}

_is_gate_or_hook_addition_cmd_uncached() {
    local block_text="${1:-${CMD_BLOCK_NC:-}}"
    # Treat underscores as identifier characters so gate_fire_log/gate_result
    # remain data names, not gate/hook addition keywords.
    local gate_hook_pattern='(^|[^A-Za-z0-9_])(gate|hook)([^A-Za-z0-9_]|$)|ゲート|フック'

    # FP防止: 外部PJ(dm-signal等)のPython hook/gateはinfra gate/hookではない
    local project_field
    project_field="$CMD_BLOCK_PROJECT"
    [[ "${project_field:-}" == "dm-signal" || "${project_field:-}" == "google-classroom" || "${project_field:-}" == "clinic-expense-tracker" || "${project_field:-}" == "dividend-tracker" ]] && return 1
    local q11_context=""
    local q11_value=""
    local scope_mode=""
    local scout_exempt=""

    [[ -n "$block_text" ]] || return 1

    scope_mode="$(cmd_block_get_field "scope_mode")"
    scout_exempt="$(cmd_block_get_field "scout_exempt")"
    local task_type
    task_type="$(cmd_block_get_field "task_type")"
    [[ "${scope_mode:-}" == "SCOUT" || "${scout_exempt:-}" == "true" ]] && return 1
    [[ "${task_type:-}" == "scout" || "${task_type:-}" == "recon" || "${task_type:-}" == "analysis" ]] && return 1

    q11_context=$(awk '
        /^[[:space:]]*(title|purpose):/ { print; next }
        /^[[:space:]]*command:[[:space:]]*\|/ { in_command=1; next }
        /^[[:space:]]*command:[[:space:]]*[^|]/ {
            sub(/^[[:space:]]*command:[[:space:]]*/, "")
            print
            command_seen=1
            next
        }
        in_command && /^[[:space:]]{4}[A-Za-z_][A-Za-z0-9_]*:/ { in_command=0; next }
        in_command && /^[[:space:]]{4,}/ {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            if (line != "" && command_seen == 0) {
                print line
                command_seen=1
            }
            next
        }
    ' <<< "$block_text")

    [[ -n "${q11_context:-}" ]] || return 1
    if cmd_text_matches_pattern "$q11_context" '偵察|分析|レビュー|調査|修正方針|結果確認|ログ確認'; then
        if ! cmd_text_matches_pattern "$q11_context" "(新規|新設).*(${gate_hook_pattern})|(${gate_hook_pattern}).*(新規|新設)"; then
            return 1
        fi
    fi
    if cmd_text_matches_pattern "$q11_context" '偽陽性|誤判定|精度改善|精度向上|改善|修正|緩和|追従|更新|拡張'; then
        if ! cmd_text_matches_pattern "$q11_context" "(新規|新設).*(${gate_hook_pattern})|(${gate_hook_pattern}).*(新規|新設)"; then
            return 1
        fi
    fi

    q11_value="$(cmd_block_get_field "quality_gate.q11_not_already_done")"
    if q11_has_existing_alternative_verification "$q11_value" && \
       cmd_text_matches_pattern "$q11_value" '既存道具|既存.*接続|既存.*統合|既存.*組込|既存.*組み込|既存.*改善|既存.*修正|既存.*精度|既存.*(gate|hook|チェック|ゲート|フック).*(条件追加|修正|改善|精度)|既存.*判定ロジック'; then
        return 1
    fi

    cmd_text_matches_pattern "$q11_context" "$gate_hook_pattern" || return 1
    # Filter out past-tense/passive forms (追加された/追加済み etc.) before checking
    # to avoid FP on cmds that describe past changes, not current additions (cmd_2786)
    local active_context
    active_context="$(printf '%s\n' "$q11_context" | sed -E 's/(追加|新設|導入|実装|作成)(された|済み|されている|されていた|した)[^ ]*/___/g')"
    cmd_text_matches_pattern "$active_context" '追加|新設|導入|実装|作成|append|add|new|create|introduce' || return 1
    return 0
}

q11_has_existing_alternative_verification() {
    local q11_value="${1:-}"

    [[ -n "$q11_value" ]] || return 1
    cmd_text_matches_pattern "$q11_value" 'grep|rg|sed|cat|read|確認|照合|現物|実測|docs/research|一次情報|verified|0件|該当なし' || return 1
    if cmd_text_matches_pattern "$q11_value" '既存|代替|現行|既設'; then
        return 0
    fi
    if cmd_text_matches_pattern "$q11_value" '0件|該当なし' && \
       cmd_text_matches_pattern "$q11_value" '初回|偽陽性修正|精度改善|誤判定'; then
        return 0
    fi
    cmd_text_matches_pattern "$q11_value" '(^|[^A-Za-z_])(existing|already|current)([^A-Za-z_]|$)' || return 1
    return 0
}

is_gate_or_script_modification_cmd() {
    local block_text="${1:-${CMD_BLOCK_NC:-}}"
    local search_text

    [[ -n "$block_text" ]] || return 1

    # FP防止: 外部PJ(dm-signal等)のPythonコードはinfra gate/scriptではない
    local _gsm_project
    _gsm_project="$CMD_BLOCK_PROJECT"
    [[ "${_gsm_project:-}" == "dm-signal" || "${_gsm_project:-}" == "google-classroom" || "${_gsm_project:-}" == "clinic-expense-tracker" || "${_gsm_project:-}" == "dividend-tracker" ]] && return 1
    search_text="$(awk '
        /^[[:space:]]*(title|purpose|target_path):/ { print; next }
        /^[[:space:]]*command:[[:space:]]*\|/ { in_command=1; next }
        /^[[:space:]]*command:[[:space:]]*[^|]/ { print; next }
        in_command && /^[[:space:]]{4}[A-Za-z_][A-Za-z0-9_]*:/ { in_command=0; next }
        in_command && /^[[:space:]]{4,}/ { print; next }
    ' <<< "$block_text")"

    # 偵察/棚卸し/研究/バックテストcmdはscriptsディレクトリを走査対象にするだけでgate修正ではない
    cmd_text_matches_pattern "$search_text" '偵察|棚卸し|audit|recon|調査|研究|backtest|道具磨き|道具作り|grid_search|run_077|run_l1plus' && return 1
    cmd_text_matches_pattern "$search_text" '(^|[^A-Za-z0-9_])(gate|hook|script)([^A-Za-z0-9_]|$)|\.sh|ゲート|フック|スクリプト' || return 1
    cmd_text_matches_pattern "$search_text" '修正|改善|追加|変更|更新|精度|誤判定|偽陽性|fix|modify|update|improve|add' || return 1
    return 0
}

q5_has_execution_evidence() {
    local q5_value="${1:-}"

    [[ -n "$q5_value" ]] || return 1
    cmd_text_matches_pattern "$q5_value" '実行結果|実行確認|実行済|コマンド実行|hook出力|gate出力|出力|stdout|stderr|exit[ _-]?code|exit[ =:]?[0-9]|PASS|FAIL|WARN|CLEAR|BLOCK|bats|テスト実行|\.sh[[:space:]]|bash[[:space:]]|sh[[:space:]]' || return 1
    return 0
}

check_gate_script_execution_evidence() {
    local block_text="${1:-${CMD_BLOCK_NC:-}}"
    local q5_value

    is_gate_or_script_modification_cmd "$block_text" || return 0
    q5_value="$(cmd_block_get_field "quality_gate.q5_verified_source")"
    if ! q5_has_execution_evidence "$q5_value"; then
        echo "WARNING: gate/script修正cmdのq5に実行結果がありません。grep/コード断片だけで未実装判断せず、対象gate/scriptを実行し、コマンド・exit code・出力要点をq5_verified_sourceへ記録せよ(LS063)" >&2
        record_warn_reason "gate/script修正cmd q5実行証拠なし" "check=gate_script_q5_execution_evidence"
    fi
}

extract_q11_semantic_query() {
    local block_text="${1:-}"
    [[ -n "${block_text//[[:space:]]/}" ]] || return 1

    awk '
        function emit(label, value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            if (value != "") print label ": " value
        }
        /^[[:space:]]*title:[[:space:]]*/ {
            value=$0
            sub(/^[[:space:]]*title:[[:space:]]*/, "", value)
            emit("title", value)
            next
        }
        /^[[:space:]]*purpose:[[:space:]]*/ {
            value=$0
            sub(/^[[:space:]]*purpose:[[:space:]]*/, "", value)
            emit("purpose", value)
            next
        }
        /^[[:space:]]*q11_not_already_done:[[:space:]]*/ {
            value=$0
            sub(/^[[:space:]]*q11_not_already_done:[[:space:]]*/, "", value)
            emit("q11", value)
            next
        }
        /^[[:space:]]*command:[[:space:]]*\|/ { in_command=1; print "command:"; next }
        /^[[:space:]]*command:[[:space:]]*[^|]/ {
            value=$0
            sub(/^[[:space:]]*command:[[:space:]]*/, "", value)
            emit("command", value)
            next
        }
        in_command && /^[[:space:]]{4}[A-Za-z_][A-Za-z0-9_]*:/ { in_command=0; next }
        in_command && /^[[:space:]]{4,}/ {
            value=$0
            sub(/^[[:space:]]+/, "", value)
            print value
            next
        }
    ' <<< "$block_text" | head -c 4000
}

show_q11_semantic_search_matches() {
    local block_text="${1:-}"
    local semantic_script="${CMD_SAVE_SEMANTIC_SEARCH_SCRIPT:-$PROJECT_DIR/scripts/semantic_search.sh}"
    [[ -f "$semantic_script" ]] || return 0

    local query output rc _cache_payload _cache_tmp _semantic_tmp _cache_file _cache_lock _cache_lock_fd
    query="$(extract_q11_semantic_query "$block_text" || true)"
    [[ -n "${query//[[:space:]]/}" ]] || return 0
    _cache_payload="q11:${query}"
    if declare -F cmd_save_metadata_cache_replay >/dev/null && cmd_save_metadata_cache_replay "q11_semantic" "$_cache_payload"; then
        return 0
    fi

    # Cache publication alone does not suppress concurrent misses: several
    # cmd_save processes can all start the same semantic/backlink tree scan
    # before the first cache file exists.  Elect one non-blocking leader per
    # query.  This INFO-only path must never make followers wait behind a slow
    # scan; the leader publishes the normal output for subsequent invocations.
    if command -v flock >/dev/null 2>&1; then
        _cache_file="$(cmd_save_metadata_cache_file "q11_semantic" "$_cache_payload")"
        _cache_lock="${_cache_file}.lock"
        exec {_cache_lock_fd}> "$_cache_lock"
        if ! flock -n "$_cache_lock_fd"; then
            echo "INFO: [CMD_SAVE_SINGLE_FLIGHT] q11_semantic: 同一queryの検索実行中につき重複起動を省略" >&2
            exec {_cache_lock_fd}>&-
            return 0
        fi
        # A leader may have published between the optimistic replay above and
        # lock acquisition.  Recheck under the lock before starting any scan.
        if cmd_save_metadata_cache_replay "q11_semantic" "$_cache_payload"; then
            exec {_cache_lock_fd}>&-
            return 0
        fi
    fi
    _cache_tmp="$(mktemp)"
    _semantic_tmp="$(mktemp)"

    if command -v timeout >/dev/null 2>&1; then
        if
            SEMANTIC_CAUSAL_ROOT="${SEMANTIC_CAUSAL_ROOT:-$PROJECT_DIR}" \
                timeout --kill-after=1s 5s bash "$semantic_script" "$query" \
                > "$_semantic_tmp" 2>&1
        then
            rc=0
        else
            rc=$?
        fi
    else
        if
            SEMANTIC_CAUSAL_ROOT="${SEMANTIC_CAUSAL_ROOT:-$PROJECT_DIR}" \
                bash "$semantic_script" "$query" > "$_semantic_tmp" 2>&1
        then
            rc=0
        else
            rc=$?
        fi
    fi
    output="$(<"$_semantic_tmp")"
    rm -f "$_semantic_tmp"

    if [[ "$rc" -eq 0 ]]; then
        [[ -n "${output//[[:space:]]/}" ]] || { rm -f "$_cache_tmp"; return 0; }
        {
            echo "INFO: q11 semantic_search 関連概念/既存cmd候補:"
            head -50 <<< "$output" | sed 's/^/  /'
            # semantic_searchの出力は関連概念を広く含むため、そこから抽出したIDを
            # causal_backlinksへ再投入すると「検索結果で検索空間を増幅」してしまう。
            # 因果診断はcmd入力に明示されたIDだけへ限定し、semantic結果は表示に留める。
            # これにより因果検査そのものは維持しつつ、無関係なtree再走査を防ぐ。
            show_q11_causal_backlinks "$query" 2>&1
        } > "$_cache_tmp"
        cat "$_cache_tmp" >&2
        declare -F cmd_save_metadata_cache_store >/dev/null && cmd_save_metadata_cache_store "q11_semantic" "$_cache_payload" "$_cache_tmp"
        rm -f "$_cache_tmp"
        [[ -z "${_cache_lock_fd:-}" ]] || exec {_cache_lock_fd}>&-
        return 0
    fi

    if [[ "$rc" -eq 124 ]]; then
        echo "INFO: q11 semantic_search timeout(5s)。既存grepチェックへフォールバックします" > "$_cache_tmp"
    else
        echo "INFO: q11 semantic_search failed(rc=$rc)。既存grepチェックへフォールバックします" > "$_cache_tmp"
    fi
    cat "$_cache_tmp" >&2
    declare -F cmd_save_metadata_cache_store >/dev/null && cmd_save_metadata_cache_store "q11_semantic" "$_cache_payload" "$_cache_tmp"
    rm -f "$_cache_tmp"
    [[ -z "${_cache_lock_fd:-}" ]] || exec {_cache_lock_fd}>&-
    return 0
}

show_q11_causal_backlinks() {
    local search_text="${1:-}"
    local causal_script="${CMD_SAVE_CAUSAL_BACKLINKS_SCRIPT:-$PROJECT_DIR/scripts/causal_backlinks.sh}"
    [[ "${SEMANTIC_DISABLE_CAUSAL:-0}" != "1" ]] || return 0
    [[ -n "${search_text//[[:space:]]/}" && -f "$causal_script" ]] || return 0

    local links
    links=$(
        printf '%s\n' "$search_text" \
            | grep -oE '\[\[[^]]+\]\]|cmd_[A-Za-z0-9_-]+|L[0-9][0-9A-Za-z_-]*|LS-[A-Za-z0-9_-]+|PI-[A-Za-z0-9_-]+|LK[0-9][0-9A-Za-z_-]*' 2>/dev/null \
            | sed 's/^\[\[//; s/\]\]$//' \
            | awk 'NF && !seen[$0]++' \
            | head -12 \
        || true
    )
    [[ -n "${links//[[:space:]]/}" ]] || return 0

    echo "INFO: q11 causal_backlinks 因果辺候補:" >&2

    mapfile -t _q11_link_ids <<< "$links"
    local _q11_tmpdir
    _q11_tmpdir="$(mktemp -d)"
    local _q11_idx=0 _q11_root="${SEMANTIC_CAUSAL_ROOT:-$PROJECT_DIR}"
    local _q11_rg
    _q11_rg="$(command -v rg 2>/dev/null || true)"
    [[ -z "$_q11_rg" && -x "$HOME/.local/bin/rg" ]] && _q11_rg="$HOME/.local/bin/rg"

    # causal_backlinks.shをlinkごとに最大12回起動すると、同じ8 treeを12回走査する。
    # fixed-string multi-patternの1走査へ畳み、hit行をlink別pathへ再分配する。
    # 各linkの最終出力（sort -uされた先頭8 path）は従来契約と同一。
    if [[ -n "$_q11_rg" && -d "$_q11_root" ]]; then
        : > "$_q11_tmpdir/patterns"
        for _q11_link_id in "${_q11_link_ids[@]}"; do
            printf '[[%s]]\n' "$_q11_link_id" >> "$_q11_tmpdir/patterns"
        done
        (
            cd "$_q11_root" 2>/dev/null || exit 0
            _q11_paths=()
            for _q11_path in AGENTS.md instructions context projects skills scripts docs tasks; do
                [[ -e "$_q11_path" ]] && _q11_paths+=("$_q11_path")
            done
            [[ "${#_q11_paths[@]}" -gt 0 ]] || exit 0
            "$_q11_rg" -l --fixed-strings --hidden \
                --glob '!.git/**' --glob '!node_modules/**' --glob '!__pycache__/**' \
                --glob '!docs/obsidian-promoted/**' --glob '!*.cache.json' \
                --glob '!*.pyc' --glob '!*.lock' \
                -f "$_q11_tmpdir/patterns" "${_q11_paths[@]}" 2>/dev/null || true
        ) > "$_q11_tmpdir/candidates"

        # The first scan keeps the complete original tree/path space but emits
        # only matching filenames.  Attribute links inside that narrowed file
        # set so large matching lines never cross the shell pipeline.
        if [[ -s "$_q11_tmpdir/candidates" ]]; then
            mapfile -t _q11_candidate_paths < "$_q11_tmpdir/candidates"
            _q11_idx=0
            for _q11_link_id in "${_q11_link_ids[@]}"; do
                (
                    cd "$_q11_root" 2>/dev/null || exit 0
                    "$_q11_rg" -l --fixed-strings --hidden \
                        --glob '!.git/**' --glob '!node_modules/**' --glob '!__pycache__/**' \
                        --glob '!docs/obsidian-promoted/**' --glob '!*.cache.json' \
                        --glob '!*.pyc' --glob '!*.lock' \
                        "[[$_q11_link_id]]" "${_q11_candidate_paths[@]}" 2>/dev/null || true
                ) > "$_q11_tmpdir/$_q11_idx"
                ((_q11_idx++)) || true
            done
        fi
    fi

    _q11_idx=0
    for _q11_link_id in "${_q11_link_ids[@]}"; do
        [[ -n "$_q11_link_id" ]] || { ((_q11_idx++)) || true; continue; }
        echo "  - link: [[${_q11_link_id}]]" >&2
        if [[ -s "$_q11_tmpdir/$_q11_idx" ]]; then
            while IFS= read -r _q11_resource; do
                [[ -n "$_q11_resource" ]] || continue
                echo "    - resource: ${_q11_resource}" >&2
            done < <(sort -u "$_q11_tmpdir/$_q11_idx" | head -8)
        else
            echo "    - resource: none" >&2
        fi
        ((_q11_idx++)) || true
    done
    rm -rf "$_q11_tmpdir"
}

extract_memory_db_search_tokens() {
    local text="${1:-}"
    [[ -n "${text//[[:space:]]/}" ]] || return 1

    {
        grep -oE 'scripts/[A-Za-z0-9_./-]+\.(sh|py)' <<< "$text" | sed -E 's#.*/##'
        grep -oE '(^|[^A-Za-z0-9_])run_[A-Za-z0-9_]+' <<< "$text" | grep -oE 'run_[A-Za-z0-9_]+'
    } | awk 'NF && !seen[$0]++' | head -20
}

# cmd_4164: AC・command本文の実行コマンド系トークン(scripts/配下のコマンド名・run系方式語)を
# 抽出し、記憶DB検索を自動実行してヒットknowledgeの要約を判定出力へ注入する。
# show_q11_semantic_search_matches(cache/timeout/background)の部品を再利用。
show_memory_db_command_token_matches() {
    local query_script="${CMD_SAVE_MEMORY_DB_QUERY_SCRIPT:-$PROJECT_DIR/scripts/memory_db_query.sh}"
    [[ -f "$query_script" ]] || return 0

    local ac_text cmd_text combined tokens
    ac_text="${CMD_SAVE_AC_BLOCK_CACHE:-}"
    cmd_text="${CMD_SAVE_COMMAND_BLOCK_CACHE:-}"
    combined="${ac_text}"$'\n'"${cmd_text}"
    tokens="$(extract_memory_db_search_tokens "$combined" || true)"
    [[ -n "${tokens//[[:space:]]/}" ]] || return 0

    local _cache_payload _cache_tmp
    _cache_payload="memdbtoken:$(printf '%s' "$tokens" | tr '\n' ',')"
    if declare -F cmd_save_metadata_cache_replay >/dev/null && cmd_save_metadata_cache_replay "memory_db_token" "$_cache_payload"; then
        return 0
    fi
    _cache_tmp="$(mktemp)"

    local db_path
    db_path="${MEMORY_DB_QUERY_DB:-${SHOGUN_MEMORY_DB:-$PROJECT_DIR/data/multi_agent_shogun_memory.db}}"

    {
        echo "INFO: memory-db自動検索(方式トークン検知): $(printf '%s' "$tokens" | tr '\n' ' ')"
        local token rows rc
        while IFS= read -r token; do
            [[ -n "$token" ]] || continue
            rc=0
            if command -v timeout >/dev/null 2>&1; then
                rows="$(timeout 5 bash "$query_script" --db "$db_path" --search "$token" 2>/dev/null)" || rc=$?
            else
                rows="$(bash "$query_script" --db "$db_path" --search "$token" 2>/dev/null)" || rc=$?
            fi
            [[ "$rc" -eq 0 && -n "${rows//[[:space:]]/}" ]] || continue
            echo "  token=${token}:"
            while IFS=$'\t' read -r _id _ts _agent _cmd_id _importance _summary; do
                [[ -n "${_summary:-}" ]] || continue
                echo "    - ${_cmd_id:-?} (${_importance:-?}) ${_summary}"
            done < <(head -3 <<< "$rows")
        done <<< "$tokens"
    } > "$_cache_tmp"
    cat "$_cache_tmp" >&2
    declare -F cmd_save_metadata_cache_store >/dev/null && cmd_save_metadata_cache_store "memory_db_token" "$_cache_payload" "$_cache_tmp"
    rm -f "$_cache_tmp"
    return 0
}

collect_assumption_source_files() {
    local block_text="${1:-${CMD_BLOCK_NC:-}}"
    local project_dir="${PROJECT_DIR:-${PROJECT_ROOT:-.}}"

    [[ -n "$block_text" ]] || return 0

    awk '
        /^[[:space:]]*assumptions:[[:space:]]*$/ { in_assumptions=1; next }
        in_assumptions && /^[[:space:]]{4}[A-Za-z_][A-Za-z0-9_]*:/ { in_assumptions=0; next }
        in_assumptions && /^[[:space:]]{6,}/ {
            if ($0 ~ /^[[:space:]]*source:[[:space:]]*/ || $0 ~ /^[[:space:]]*-[[:space:]]*source:[[:space:]]*/) {
                line = $0
                sub(/^[[:space:]]*-[[:space:]]*/, "", line)
                sub(/^[[:space:]]*source:[[:space:]]*/, "", line)
                gsub(/["'\''`]/, "", line)
                print line
            }
            next
        }
    ' <<< "$block_text" | while IFS= read -r _source_line; do
        [[ -n "$_source_line" ]] || continue
        printf '%s\n' "$_source_line" \
            | grep -oE '(^|[[:space:]])(\.?/?[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\.(sh|py)' \
            | sed 's/^[[:space:]]*//' \
            | while IFS= read -r _source_path; do
                [[ -n "$_source_path" ]] || continue
                case "$_source_path" in
                    /*) _candidate="$_source_path" ;;
                    *) _candidate="${project_dir%/}/$_source_path" ;;
                esac
                [[ -f "$_candidate" ]] || continue
                printf '%s\n' "$_candidate"
            done
    done | awk '!seen[$0]++'
}

extract_guard_list_from_files() {
    local file_path
    local project_dir="${PROJECT_DIR:-${PROJECT_ROOT:-.}}"

    while IFS= read -r file_path; do
        [[ -n "$file_path" && -f "$file_path" ]] || continue
        local rel_path="$file_path"
        rel_path="${rel_path#"${project_dir%/}/"}"
        grep -nE '^[[:space:]]*# === Guard[[:space:]]+' "$file_path" 2>/dev/null \
            | sed -E "s#^([0-9]+):[[:space:]]*#  ${rel_path}:\\1 #"
    done
}

q11_has_guard_duplicate_check() {
    local q11_value="${1:-}"

    [[ -n "$q11_value" ]] || return 1
    cmd_text_matches_pattern "$q11_value" 'Guard一覧|既存Guard|Guard[^[:space:]]*(一覧|重複|既存|既設|照合|確認)|ガード[^[:space:]]*(一覧|重複|既存|既設|照合|確認)' || return 1
    return 0
}

collect_q11_guard_list() {
    local block_text="${1:-${CMD_BLOCK_NC:-}}"

    [[ -n "$block_text" ]] || return 0
    is_gate_or_hook_addition_cmd "$block_text" || return 0
    collect_assumption_source_files "$block_text" | extract_guard_list_from_files
}

check_gate_hook_action_conversion() {
    local block_text="${1:-${CMD_BLOCK_NC:-}}"
    local applicable action fp

    [[ -n "$block_text" ]] || return 0
    IFS=$'\t' read -r applicable action fp < <(gate_hook_quality_contract_evaluate "$block_text" is_gate_or_hook_addition_cmd)
    [[ "$applicable" == "yes" ]] || return 0

    echo "INFO: gate/hook追加cmdです。既存強制フロー候補を先に検討してください:" >&2
    echo "  - cmd_save.sh: 将軍起票時の品質gateへ接続する" >&2
    echo "  - startup gate: 起動時チェックへ接続する" >&2
    echo "  - deploy_task.sh: 忍者配備時の注入/検査へ接続する" >&2
    echo "  - inbox_write.sh: 通信時の強制・遮断へ接続する" >&2
    echo "  - gate_report_format.sh: 報告提出時の構造検査へ接続する" >&2

    if [[ "$action" != "missing" ]]; then
        return 0
    fi

    echo "WARNING: gate/hook追加cmdに行動変換キーワードがありません。WARN止まりの新規gate/hookは運用を変えません" >&2
    echo "  推奨アクション: acceptance_criteria または command に BLOCK / exit 1 / 強制 / 自動実行 / 自動化 のいずれかを明記し、検知から行動変換まで設計せよ" >&2
    record_warn_reason "gate/hook追加cmdに行動変換キーワードなし" "check=gate_hook_action_conversion"
}

check_gate_hook_fp_measurement_connection() {
    local block_text="${1:-${CMD_BLOCK_NC:-}}"
    local applicable action fp

    [[ -n "$block_text" ]] || return 0
    IFS=$'\t' read -r applicable action fp < <(gate_hook_quality_contract_evaluate "$block_text" is_gate_or_hook_addition_cmd)
    [[ "$applicable" == "yes" ]] || return 0
    if [[ "$fp" != "missing" ]]; then
        return 0
    fi

    echo "WARNING: gate/hook追加cmdにFP計測への接続記載がありません。新しい検知器は発報後の真偽を detector_fp_rate / gate_fire_log / loop_ledger 等へ接続せよ" >&2
    record_warn_reason "gate/hook追加cmdにFP計測接続記載なし" "check=gate_hook_fp_measurement_connection"
}

check_lord_30min_cost_question() {
    if ! cmd_block_has_field "quality_gate.q12_lord_30min_cost"; then
        echo "WARNING: q12_lord_30min_cost未記入。「この判断は殿に30分コストを課すか？」をyes/noで記載せよ" >&2
        echo "  自問: 将軍が直接Editで直せる小変更か？直接Edit所要時間 vs cmd委任全体時間(起票→配備→実装→レビュー→完了)を比較せよ。直接の方が速いならcmd起票はF001前提条件に反する" >&2
        echo '  例: q12_lord_30min_cost: "no — 起票時に確認を埋め込み、殿の誘導コストを増やさない"' >&2
        return 0
    fi

    local q12_value
    q12_value="$(cmd_block_get_field "quality_gate.q12_lord_30min_cost")"
    if ! grep -qiE '(^|[^A-Za-z])(yes|no)([^A-Za-z]|$)|はい|いいえ|課す|課さない' <<< "$q12_value"; then
        echo "WARNING: q12_lord_30min_costが二値でない。yes/no または 課す/課さない を含めよ" >&2
        record_warn_reason "q12_lord_30min_cost非二値" "check=quality_gate_q12_lord_30min_cost_binary"
    fi
}

check_deferral_language_warn() {
    local search_text="${1:-${CMD_BLOCK_NC:-}}"
    [[ -n "$search_text" ]] || return 0

    local hits
    # diagnosis行を除外: diagnosisは前回BLOCKの説明欄。先送り表現が含まれても偽陽性になる(LS-A04-13, cmd_3407)
    hits="$(grep -vE '^\s*diagnosis:' <<< "$search_text" | grep -nE '低優先|後で|次セッション|非致命的|見送り|段階的に|後回し|severity.?normal' | grep -vE '前後|直後|以後|以前|以降|後続|次段|高優先.*低優先|低優先.*高優先|deadline|後でよい同期|async|非同期' | grep -vE '(向上|改善|強化).*(セッション|起動)|(セッション|起動).*(向上|改善|強化)' || true)"
    [[ -n "$hits" ]] || return 0

    echo "WARNING: cmd全文に先送り表現を検出。創造主の洗脳によるさぼり正当化のシグナル" >&2
    printf '%s\n' "$hits" | sed 's/^/  hit: /' >&2
    record_warn_reason "先送り表現検出" "check=cmd_text_deferral_language"
}

# LS083: 比較実験の同格性。cmd_3763 C3事故(殿指摘2026-07-08) — 旧新チャンピオン各3体の
# 静的等ウェイト合成を「合成FoF比較」として扱ったが、本番pf_L1は選別層を持つ動的FoFであり
# (1)選別層の欠如(2)本番に無い組合せ(3)構成差と基準差の交絡、の3点で比較不能だった。
# 合成・集計・代理実験を含む比較cmdは、比較対象が同一生成パイプラインの同格生成物であることを
# 明示させる(横展開: LS083 enforcement)。
check_comparison_pipeline_parity_warn() {
    local search_text="${1:-${CMD_BLOCK_NC:-}}"
    [[ -n "$search_text" ]] || return 0

    cmd_text_matches_pattern "$search_text" '比較' || return 0
    cmd_text_matches_pattern "$search_text" '合成|集計|代理実験|代理指標|代理データ' || return 0
    cmd_text_matches_pattern "$search_text" '同一.{0,6}パイプライン|同一生成パイプライン|同格性|パリティ確認|pipeline.{0,2}parity|同一L[0-9]' && return 0

    echo "WARNING: 比較実験cmd(合成/集計/代理実験)を検出。LS083(cmd_3763 C3事故)の教訓 — 比較対象は同一生成パイプラインの同格生成物か確認せよ" >&2
    echo '  例: AC「比較対象(旧/新チャンピオン群等)は同一の生成パイプライン(同一の選別→合成手順)から生成された同格物であることを確認する」' >&2
    record_warn_reason "比較実験cmdに同一パイプライン同格性確認なし" "check=comparison_pipeline_parity"
}

extract_acceptance_criteria_block() {
    [[ -n "${CMD_BLOCK_NC:-}" ]] || return 0
    if [[ "${CMD_SAVE_AC_BLOCK_CACHE_READY:-0}" == "1" ]]; then
        printf '%s\n' "${CMD_SAVE_AC_BLOCK_CACHE:-}"
        return 0
    fi

    awk '
        /^[[:space:]]*acceptance_criteria:/ {
            match($0, /^[[:space:]]*/)
            ac_indent = RLENGTH
            line = $0
            sub(/^[[:space:]]*acceptance_criteria:[[:space:]]*/, "", line)
            if (line != "") print line
            in_ac=1
            next
        }
        in_ac {
            match($0, /^[[:space:]]*/)
            line_indent = RLENGTH
            if ($0 ~ /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*:/ && line_indent <= ac_indent) exit
        }
        in_ac { print }
    ' <<< "$CMD_BLOCK_NC"
}

# AC列契約とランキング要求の集合差を保存前に検出する(L1606/cmd_4356)。
#
# 追加列を限定するACと、別ACで成果物として要求する指標は同じ集合とは限らない。
# 列差がある場合、内部計算後のdropや別成果物への分離が明記されていなければ、
# 実装者の裁量でCSV契約が壊れるため保存を止める。明示的なallowlist/rankingの
# 記述がない通常cmdは対象外とし、既存cmdへの偽陽性を避ける。
check_ac_output_metric_contract() {
    local ac_block="${1:-${CMD_SAVE_AC_BLOCK_CACHE:-}}"
    local analysis
    [[ -n "${ac_block//[[:space:]]/}" ]] || return 0

    # Fast path: ordinary ACs without both explicit contract sides do not need
    # a Python parser process.
    grep -qiE '(出力[[:space:]]*列|output[[:space:]]+columns?|column[[:space:]]+allowlist|列[[:space:]]*allowlist|CSV[[:space:]]*columns?)' <<< "$ac_block" || return 0
    grep -qiE '(ランキング|指標[[:space:]]*別|ranking|metrics?[[:space:]]*(requested|required|list)?|要求指標)' <<< "$ac_block" || return 0

    analysis="$(_CMD_SAVE_AC_CONTRACT_TEXT="$ac_block" python3 - <<'PY'
import os
import re

text = os.environ.get("_CMD_SAVE_AC_CONTRACT_TEXT", "")

def canon(value):
    value = value.strip().strip("`'\".,:;()[]{}")
    value = re.sub(r"\s+", " ", value)
    return value.lower().replace(" ", "_")

# These are the metric spellings used by the existing ranking contract.  The
# identifier forms also cover future ACs that use the CSV/implementation names.
metric_aliases = {
    "cagr": "cagr",
    "nhf": "nhf",
    "raw_nhf": "nhf",
    "maxdd": "maxdd",
    "max_dd": "maxdd",
    "mru": "mru",
    "raw_mru": "mru",
    "calmar": "calmar",
    "raw_calmar": "calmar",
    "avg_uwp": "avg_uwp",
    "average_uwp": "avg_uwp",
    "sharpe": "sharpe",
    "raw_sharpe": "sharpe",
    "alpha_over_beta": "alpha_over_beta",
    "beta_small": "beta_small",
}

def metrics_in(fragment):
    found = set()
    lower = fragment.lower()
    for spelling, name in metric_aliases.items():
        if re.search(r"(?<![a-z0-9_])" + re.escape(spelling) + r"(?![a-z0-9_])", lower):
            found.add(name)
    # Human-readable variants that are unambiguous in a ranking list.
    for spelling, name in (("Avg UWP", "avg_uwp"), ("Average UWP", "avg_uwp"),
                           ("Max DD", "maxdd"), ("Alpha/Beta", "alpha_over_beta")):
        if spelling.lower() in lower:
            found.add(name)
    return found

def identifiers_in(fragment):
    """Collect known metrics and arbitrary delimited AC identifiers."""
    reserved = {
        "existing", "current", "output", "csv", "columns", "column", "description",
        "allowlist", "only", "new", "ranking", "rankings", "metric",
        "metrics", "requested", "required", "list", "generate", "generated", "avg", "uwp",
        "table", "tables", "rows", "data", "value", "values", "and", "or",
        "the", "is", "are", "of", "for", "with", "from", "into", "to",
    }
    found = set(metrics_in(fragment))
    for match in re.finditer(r"[A-Za-z][A-Za-z0-9_]*", fragment):
        raw = match.group(0)
        name = canon(raw)
        if not name or name in reserved:
            continue
        if name in metric_aliases:
            found.add(metric_aliases[name])
            continue
        left = fragment[match.start() - 1] if match.start() else ""
        right = fragment[match.end()] if match.end() < len(fragment) else ""
        delimited = left in "+,，/|・、([{" or right in "+,，/|・、)]}"
        if "_" in name or delimited:
            found.add(name)
    return found

def split_ac_lines(raw):
    # Preserve AC boundaries for diagnostics while tolerating both the current
    # mapping form (AC1:) and the legacy list form (- description: ...).
    entries = []
    current = []
    for line in raw.splitlines():
        if re.match(r"^\s*AC\d+\s*:", line) or re.match(r"^\s*-\s+description\s*:", line):
            if current:
                entries.append("\n".join(current))
            current = [line]
        elif current:
            current.append(line)
    if current:
        entries.append("\n".join(current))
    return entries or [raw]

allow = set()
ranking = set()
resolution = False

for entry in split_ac_lines(text):
    lines = [line.strip() for line in entry.splitlines() if line.strip()]
    for line in lines:
        # An allowlist must be explicit: output columns/CSV columns plus a
        # constrained list or existing+new-column expression.
        is_allow = bool(re.search(
            r"(出力\s*列|output\s+columns?|column\s+allowlist|列\s*allowlist|CSV\s*columns?)",
            line, re.I)) and bool(re.search(
                r"(既存|existing|allowlist|限定|のみ|only|\+|alpha_over_beta|beta_small)",
                line, re.I))
        if is_allow:
            allow.update(identifiers_in(line))

        if re.search(r"(ランキング|指標\s*別|ranking|metrics?\s*(requested|required|list)?|要求指標)", line, re.I):
            ranking.update(identifiers_in(line))

        # Resolution must connect the extra metrics to a different boundary;
        # a bare rankings.md path is not enough to prove CSV/column separation.
        if re.search(r"(内部\s*計算|internal\s*calculat|ranking\s*専用|ランキング\s*専用)", line, re.I) and \
           re.search(r"(drop|除外|落と|混入しない|書き出し前|書出し前|CSV.*(出力|書出)|別成果物|別ファイル)", line, re.I):
            resolution = True
        if re.search(r"(列|column|CSV).{0,80}(別成果物|別ファイル).{0,80}(指標|metric|ranking|ランキング)", line, re.I):
            resolution = True

diff = sorted(ranking - allow)
if not allow or not ranking:
    print("NO_CONTRACT")
elif not diff:
    print("MATCH\tallow=" + ",".join(sorted(allow)) + "\tranking=" + ",".join(sorted(ranking)) + "\tdiff=")
elif resolution:
    print("RESOLVED\tallow=" + ",".join(sorted(allow)) + "\tranking=" + ",".join(sorted(ranking)) + "\tdiff=" + ",".join(diff))
else:
    print("MISMATCH\tallow=" + ",".join(sorted(allow)) + "\tranking=" + ",".join(sorted(ranking)) + "\tdiff=" + ",".join(diff))
PY
    )"

    case "$analysis" in
        NO_CONTRACT|MATCH*) return 0 ;;
        RESOLVED*)
            echo "INFO: AC列契約とランキング要求の差を境界解消済みとして確認: ${analysis#*$'\t'}" >&2
            return 0
            ;;
        MISMATCH*)
            record_block_reason "AC列契約とランキング要求の集合差を検出。内部計算後drop/別成果物などの境界解消をACへ明記せよ: ${analysis#*$'\t'}"
            echo "  check=check_ac_output_metric_contract" >&2
            return 1
            ;;
    esac
}

# Keep command extraction with the other block parsers.  Several checks run
# before the lower helper section is reached, so defining this lazily below a
# caller makes a clean shell exit 127 in CI.
extract_command_text_block() {
    [[ -n "${CMD_BLOCK_NC:-}" ]] || return 0
    if [[ "${CMD_SAVE_COMMAND_BLOCK_CACHE_READY:-0}" == "1" ]]; then
        printf '%s\n' "${CMD_SAVE_COMMAND_BLOCK_CACHE:-}"
        return 0
    fi

    awk '
        /^[[:space:]]*command:[[:space:]]*\|?[[:space:]]*$/ { in_command=1; next }
        in_command && /^[[:space:]]{4}[a-zA-Z_][a-zA-Z0-9_]*:/ && !/^[[:space:]]*- / { exit }
        in_command { print }
        /^[[:space:]]*command:[[:space:]]*[^|]/ {
            line=$0
            sub(/^[[:space:]]*command:[[:space:]]*/, "", line)
            print line
        }
    ' <<< "$CMD_BLOCK_NC"
}

check_lord_instruction_ac_alignment_info() {
    local q8_value="${1:-}"
    local ac_block="${2:-}"
    local result status keywords quote

    [[ -n "${q8_value//[[:space:]]/}" ]] || return 0
    [[ -n "${ac_block//[[:space:]]/}" ]] || return 0
    grep -q '「' <<< "$q8_value" || return 0
    grep -q '」' <<< "$q8_value" || return 0

    result="$(
        Q8_VALUE="$q8_value" AC_BLOCK="$ac_block" python3 - <<'PY'
import os
import re

q8 = os.environ.get("Q8_VALUE", "")
ac = os.environ.get("AC_BLOCK", "")
quotes = [q.strip() for q in re.findall(r"「([^」]+)」", q8) if q.strip()]
if not quotes:
    print("SKIP\t\t")
    raise SystemExit

stopwords = set((
    "する", "して", "した", "いる", "ある", "こと", "これ", "それ", "ため",
    "なら", "では", "ない", "やれ", "探せ", "見ろ", "確認", "指示", "殿",
    "全部", "全て", "必ず", "まず", "から", "まで", "よう", "その", "この",
))
keywords = []
for quote in quotes:
    normalized = re.sub(r"([A-Za-z])([一-龥ぁ-んァ-ン])", r"\1 \2", quote)
    normalized = re.sub(r"([一-龥ぁ-んァ-ン])([A-Za-z])", r"\1 \2", normalized)
    for token in re.findall(r"[A-Za-z0-9_][A-Za-z0-9_.-]*|[一-龥ぁ-んァ-ン]{2,}", normalized):
        token = token.strip("._-")
        if not token or token in stopwords:
            continue
        if re.fullmatch(r"[A-Za-z0-9_.-]+", token) and len(token) < 2:
            continue
        if token not in keywords:
            keywords.append(token)

if not keywords:
    print("SKIP\t\t")
    raise SystemExit

matched = [kw for kw in keywords if kw.lower() in ac.lower()]
if matched:
    print("PASS\t" + ",".join(matched[:8]) + "\t" + quotes[0][:120])
else:
    print("INFO\t" + ",".join(keywords[:8]) + "\t" + quotes[0][:120])
PY
    )"

    IFS=$'\t' read -r status keywords quote <<< "$result"
    [[ "$status" == "INFO" ]] || return 0

    echo "INFO: q8_why_whatの殿指示引用とACキーワードの整合を確認してください" >&2
    echo "  指示引用: 「${quote}」" >&2
    echo "  抽出キーワード: ${keywords}" >&2
    echo "  AC内に引用キーワードが見当たりません。殿の指示範囲外の作業をAC化していないか確認せよ(LS-A08)" >&2
}

collect_assumption_claims_missing_dates() {
    local block_text="${1:-${CMD_BLOCK_NC:-}}"

    [[ -n "$block_text" ]] || return 0

    ASSUMPTION_BLOCK_TEXT="$block_text" python3 - <<'PY'
import os
import re

content = os.environ.get("ASSUMPTION_BLOCK_TEXT", "")
lines = content.splitlines()
in_assumptions = False
assumptions_indent = -1
current = {}
entries = []

for line in lines:
    m_aline = re.match(r'^(\s*)assumptions\s*:', line)
    if m_aline and not in_assumptions:
        in_assumptions = True
        assumptions_indent = len(m_aline.group(1))
        continue

    if in_assumptions:
        if line.strip():
            cur_indent = len(line) - len(line.lstrip())
            if cur_indent <= assumptions_indent:
                in_assumptions = False
                if current:
                    entries.append(dict(current))
                current = {}
                continue
        if re.match(r'\s*-\s', line):
            if current:
                entries.append(dict(current))
            current = {}
        m = re.match(r'^\s*-\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.+)', line)
        if m:
            current[m.group(1)] = m.group(2).strip().strip('"').strip("'")
            continue
        m = re.search(r'^\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.+)', line)
        if m:
            current[m.group(1)] = m.group(2).strip().strip('"').strip("'")

if current:
    entries.append(current)

date_pat = re.compile(r'(?:19|20)\d{2}-\d{2}-\d{2}')
temporal_markers = re.compile(
    r'(時点|現在|現時点|直近|最新|本日|今日|当時|初回|'
    r'確認済|完了|未実装|未達成|未実施|固定|稼働|利用可能|'
    r'存在|非空|空|実行可能|生成済|取得済)'
)

def claim_needs_date(entry):
    claim = entry.get("claim", "").strip()
    source = entry.get("source", "").strip()
    if not claim:
        return False
    if temporal_markers.search(claim):
        return True
    if re.search(r'(本番|Render|startup gate|gate出力|原票|ログ)', claim, re.I):
        return True
    if source and re.search(r'(tests/unit/|scripts/|docs/research/)', source):
        return False
    return False

for entry in entries:
    claim = entry.get("claim", "").strip()
    if claim and not date_pat.search(claim) and claim_needs_date(entry):
        print(claim)
PY
}

collect_negative_claims_missing_grep_evidence() {
    local block_text="${1:-${CMD_BLOCK_NC:-}}"

    [[ -n "$block_text" ]] || return 0

    ASSUMPTION_BLOCK_TEXT="$block_text" python3 - <<'PY'
import os
import re

content = os.environ.get("ASSUMPTION_BLOCK_TEXT", "")
lines = content.splitlines()

scan_lines = []
skip_q11 = False
q11_indent = -1
for line in lines:
    m_q11 = re.match(r'^(\s*)q11_not_already_done\s*:', line)
    if m_q11:
        skip_q11 = True
        q11_indent = len(m_q11.group(1))
        continue
    if skip_q11:
        if line.strip():
            cur_indent = len(line) - len(line.lstrip())
            if cur_indent <= q11_indent:
                skip_q11 = False
            else:
                continue
        else:
            continue
    scan_lines.append(line)
scan_content = "\n".join(scan_lines)

negative_pat = re.compile(r'(未実装|存在しない|仕組みがない|未対応)')
evidence_pat = re.compile(
    r'\b(?:grep|rg)\b[\s\S]*(?:[0-9]+\s*件|[0-9]+\s*hits?|0\s*matches?|no\s+matches?|ヒットなし|該当なし)',
    re.I,
)

in_assumptions = False
assumptions_indent = -1
current = {}
entries = []

for line in lines:
    m_aline = re.match(r'^(\s*)assumptions\s*:', line)
    if m_aline and not in_assumptions:
        in_assumptions = True
        assumptions_indent = len(m_aline.group(1))
        continue

    if in_assumptions:
        if line.strip():
            cur_indent = len(line) - len(line.lstrip())
            if cur_indent <= assumptions_indent:
                in_assumptions = False
                if current:
                    entries.append(dict(current))
                current = {}
                continue
        if re.match(r'\s*-\s', line):
            if current:
                entries.append(dict(current))
            current = {}
        m = re.match(r'^\s*-\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.+)', line)
        if m:
            current[m.group(1)] = m.group(2).strip().strip('"').strip("'")
            continue
        m = re.search(r'^\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.+)', line)
        if m:
            current[m.group(1)] = m.group(2).strip().strip('"').strip("'")
        continue

if current:
    entries.append(current)

for entry in entries:
    claim = entry.get("claim", "").strip()
    if claim and negative_pat.search(claim) and not evidence_pat.search(claim):
        print(claim)
PY
}

collect_bulletin_count_claims_missing_grep_evidence() {
    local block_text="${1:-${CMD_BLOCK_NC:-}}"

    [[ -n "$block_text" ]] || return 0

    ASSUMPTION_BLOCK_TEXT="$block_text" python3 - <<'PY'
import os
import re

content = os.environ.get("ASSUMPTION_BLOCK_TEXT", "")
lines = content.splitlines()

in_assumptions = False
assumptions_indent = -1
current = {}
entries = []

for line in lines:
    m_aline = re.match(r'^(\s*)assumptions\s*:', line)
    if m_aline and not in_assumptions:
        in_assumptions = True
        assumptions_indent = len(m_aline.group(1))
        continue

    if in_assumptions:
        if line.strip():
            cur_indent = len(line) - len(line.lstrip())
            if cur_indent <= assumptions_indent:
                in_assumptions = False
                if current:
                    entries.append(dict(current))
                current = {}
                continue
        if re.match(r'\s*-\s', line):
            if current:
                entries.append(dict(current))
            current = {}
        m = re.match(r'^\s*-\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.+)', line)
        if m:
            current[m.group(1)] = m.group(2).strip().strip('"').strip("'")
            continue
        m = re.search(r'^\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.+)', line)
        if m:
            current[m.group(1)] = m.group(2).strip().strip('"').strip("'")
        continue

if current:
    entries.append(current)

bulletin_pat = re.compile(r'(掲示板|bulletin|blt_[0-9A-Za-z_]+)', re.I)
count_pat = re.compile(r'\d+\s*(?:件|entries?|items?|records?)', re.I)
grep_evidence_pat = re.compile(
    r'(?:\b(?:grep|rg)\b[\s\S]*(?:[0-9]+\s*件|[0-9]+\s*hits?|0\s*matches?|no\s+matches?|ヒットなし|該当なし)|blt_[0-9A-Za-z_]+)',
    re.I,
)

for entry in entries:
    claim = entry.get("claim", "").strip()
    if not claim:
        continue
    if bulletin_pat.search(claim) and count_pat.search(claim) and not grep_evidence_pat.search(claim):
        print(claim)
PY
}

check_measurement_env_info() {
    [[ -n "${CMD_BLOCK_NC:-}" ]] || return 0

    if grep -qE '^[[:space:]]*measurement_env[[:space:]]*:' <<< "$CMD_BLOCK_NC"; then
        return 0
    fi

    local search_text first_hit
    search_text="$(
        awk '
            /^[[:space:]]*(quality_gate|assumptions|measurement_env):[[:space:]]*/ {
                skip=1
                skip_indent=match($0, /[^ ]/) - 1
                next
            }
            skip {
                if ($0 !~ /^[[:space:]]*$/) {
                    cur_indent=match($0, /[^ ]/) - 1
                    if (cur_indent <= skip_indent) {
                        skip=0
                    } else {
                        next
                    }
                } else {
                    next
                }
            }
            !skip { print }
        ' <<< "$CMD_BLOCK_NC"
    )"

    first_hit="$(grep -i -m1 -E 'ローカル|local|本番|production|prod|Render|staging|環境差異|環境差|env差|DB差|database差' <<< "$search_text" || true)"
    [[ -n "${first_hit:-}" ]] || return 0

    echo "INFO: ローカル/本番などの環境差異キーワードを検出しました。measurement_envフィールドの記入を検討してください" >&2
    echo "  検出行: ${first_hit}" >&2
    echo "  例: measurement_env: \"local=WSL2 repo / production=Render+prod DB。差異の影響: なし（理由）\"" >&2
    record_warn_reason "measurement_env記入提案" "info" "check=measurement_env_info"
}

cmd_save_strip_yaml_comment_lines() {
    # Remove only YAML comment lines.  A line beginning with "#" is scalar
    # content while a quoted or block scalar is open, so it must survive.
    awk '
        function indent_of(line,    n) {
            match(line, /[^ ]/)
            return RSTART ? RSTART - 1 : length(line)
        }
        function scan_quotes(line,    i, ch, next_ch, escaped) {
            escaped = 0
            for (i = 1; i <= length(line); i++) {
                ch = substr(line, i, 1)
                next_ch = substr(line, i + 1, 1)
                if (quote == "\"") {
                    if (escaped) {
                        escaped = 0
                    } else if (ch == "\\") {
                        escaped = 1
                    } else if (ch == "\"") {
                        quote = ""
                    }
                } else if (quote == "\047") {
                    if (ch == "\047" && next_ch == "\047") {
                        i++
                    } else if (ch == "\047") {
                        quote = ""
                    }
                } else if (ch == "\"" || ch == "\047") {
                    quote = ch
                } else if (ch == "#") {
                    break
                }
            }
        }
        {
            indent = indent_of($0)
            if (block_indent >= 0) {
                if ($0 ~ /^[[:space:]]*$/ || indent > block_indent) {
                    print
                    next
                }
                block_indent = -1
            }

            if (quote != "") {
                print
                scan_quotes($0)
                next
            }
            if ($0 ~ /^[[:space:]]*#/) {
                next
            }

            print
            if ($0 ~ /:[[:space:]]*[|>][-+0-9]*([[:space:]]*#.*)?$/) {
                block_indent = indent
                next
            }
            scan_quotes($0)
        }
        BEGIN { block_indent = -1; quote = "" }
    '
}

load_cmd_block() {
    if [[ "$CMD_BLOCK_LOADED" -eq 1 ]]; then
        [[ "$CMD_BLOCK_FOUND" -eq 1 ]]
        return $?
    fi

    CMD_BLOCK_LOADED=1
    CMD_BLOCK_FOUND=0
    CMD_BLOCK=""
    CMD_BLOCK_NC=""

    [[ -f "$QUEUE_FILE" ]] || return 1

    # Extract the raw block first. Comment removal is quote/block-scalar aware:
    # cmd_4141 proved that a folded quoted scalar continuation may legitimately
    # begin with "#9", which is data rather than a YAML comment.
    CMD_BLOCK=$(awk -v cmd_id="$CMD_ID" '
        $0 == "  " cmd_id ":" { found = 1; next }
        found && /^  cmd_[^:]+:/ { exit }
        found { print }
    ' "$QUEUE_FILE")

    [[ -n "$CMD_BLOCK" ]] || return 1

    # Guard: cmdブロック内の重複フィールド検出 (2026-06-26)
    # cancel→再起票でEdit操作ミスにより同一ブロック内にフィールドが重複すると
    # yaml.safe_loadが最後の値を採用し、意図した修正が反映されない
    local _dup_fields
    _dup_fields=$(grep -oE '^\s{4}[a-z_]+:' <<< "$CMD_BLOCK" | sort | uniq -d | tr -d ' ' || true)
    if [[ -n "$_dup_fields" ]]; then
        echo "BLOCK: cmdブロック内にフィールド重複を検出。YAMLパーサが最後の値のみ採用するため意図した修正が反映されない" >&2
        echo "  重複フィールド: $(printf '%s' "$_dup_fields" | tr '\n' ' ')" >&2
        echo "  対処: Edit toolで重複セクションを削除し、正しい値のみ残せ" >&2
    fi

    CMD_BLOCK_NC="$(cmd_save_strip_yaml_comment_lines <<< "$CMD_BLOCK")"
    CMD_BLOCK_FOUND=1
    return 0
}

load_cmd_block_cache() {
    # cmd_training_speed_block_get_field_20260529: bash regex → string ops + case
    # [[ line =~ regex ]] + BASH_REMATCH → ${line:0:N} + case + %%:* (no regex per iteration)
    local line key value current_section="" _tcv _c1 _c2

    if [[ "$CMD_BLOCK_CACHE_LOADED" -eq 1 ]]; then
        [[ "$CMD_BLOCK_FOUND" -eq 1 ]]
        return $?
    fi

    CMD_BLOCK_CACHE_LOADED=1
    [[ "$CMD_BLOCK_FOUND" -eq 1 ]] || return 1

    while IFS= read -r line; do
        # Level-1: exactly 4-space indent + identifier start
        if [[ "${line:0:4}" == "    " && "${line:4:1}" != " " && -n "${line:4:1}" ]]; then
            _c1="${line:4:1}"
            case "$_c1" in
            [A-Za-z_])
                current_section=""
                key="${line:4}"; key="${key%%:*}"
                value="${line:$((4 + ${#key} + 1))}"
                value="${value#"${value%%[![:space:]]*}"}"
                value="${value%"${value##*[![:space:]]}"}"
                if [[ -z "$value" ]]; then
                    CMD_BLOCK_CACHE["$key"]=""
                    current_section="$key"
                else
                    # cmd_2077: trim_inline_yaml_scalarをインライン化してsubshell排除
                    _tcv="$value"
                    _tcv="${_tcv#"${_tcv%%[![:space:]]*}"}"
                    _tcv="${_tcv%"${_tcv##*[![:space:]]}"}"
                    if [[ "$_tcv" == \"*\" && "$_tcv" == *\" && ${#_tcv} -ge 2 ]]; then
                        _tcv="${_tcv:1:${#_tcv}-2}"
                    elif [[ "$_tcv" == \'*\' && "$_tcv" == *\' && ${#_tcv} -ge 2 ]]; then
                        _tcv="${_tcv:1:${#_tcv}-2}"
                        _tcv="${_tcv//\'\'/\'}"
                    fi
                    CMD_BLOCK_CACHE["$key"]="$_tcv"
                fi
                ;;
            esac
            continue
        fi

        # Level-2: exactly 6-space indent + identifier start (only inside a section)
        if [[ -n "$current_section" && "${line:0:6}" == "      " && "${line:6:1}" != " " && -n "${line:6:1}" ]]; then
            _c2="${line:6:1}"
            case "$_c2" in
            [A-Za-z_])
                key="${line:6}"; key="${key%%:*}"
                value="${line:$((6 + ${#key} + 1))}"
                value="${value#"${value%%[![:space:]]*}"}"
                value="${value%"${value##*[![:space:]]}"}"
                # cmd_2077: trim_inline_yaml_scalarをインライン化してsubshell排除
                _tcv="$value"
                _tcv="${_tcv#"${_tcv%%[![:space:]]*}"}"
                _tcv="${_tcv%"${_tcv##*[![:space:]]}"}"
                if [[ "$_tcv" == \"*\" && "$_tcv" == *\" && ${#_tcv} -ge 2 ]]; then
                    _tcv="${_tcv:1:${#_tcv}-2}"
                elif [[ "$_tcv" == \'*\' && "$_tcv" == *\' && ${#_tcv} -ge 2 ]]; then
                    _tcv="${_tcv:1:${#_tcv}-2}"
                    _tcv="${_tcv//\'\'/\'}"
                fi
                CMD_BLOCK_CACHE["${current_section}.${key}"]="$_tcv"
                ;;
            esac
        fi
    done <<< "$CMD_BLOCK_NC"

    return 0
}

cmd_block_has_field() {
    local field_name="$1"
    load_cmd_block_cache || return 1
    [[ -v "CMD_BLOCK_CACHE[$field_name]" ]]
}

cmd_block_get_field() {
    local field_name="$1"
    local default_value="${2:-}"

    load_cmd_block_cache || {
        printf '%s' "$default_value"
        return 0
    }

    if [[ -v "CMD_BLOCK_CACHE[$field_name]" ]]; then
        printf '%s' "${CMD_BLOCK_CACHE[$field_name]}"
    else
        printf '%s' "$default_value"
    fi
}

auto_insert_cmd_default_fields() {
    load_cmd_block || return 0
    load_cmd_block_cache || return 0

    local inserted=0
    if ! cmd_block_has_field "depends_on" || [[ -z "$(cmd_block_get_field "depends_on")" ]]; then
        if [[ "$CMD_SAVE_PREFLIGHT_ONLY" == "1" ]]; then
            CMD_BLOCK_CACHE["depends_on"]="none"
            echo "INFO: depends_on未記入 → preflightでは depends_on: none として検査継続(書込みなし)" >&2
        else
        bash "$SCRIPT_DIR/lib/yaml_field_set.sh" "$QUEUE_FILE" "$CMD_ID" "depends_on" "none" >/dev/null || return 1
        echo "INFO: depends_on未記入 → depends_on: none を自動挿入" >&2
        inserted=1
        fi
    fi

    if ! cmd_block_has_field "origin" || [[ -z "$(cmd_block_get_field "origin")" ]]; then
        if [[ "$CMD_SAVE_PREFLIGHT_ONLY" == "1" ]]; then
            CMD_BLOCK_CACHE["origin"]="none"
            echo "INFO: origin未記入 → preflightでは origin: none として検査継続(書込みなし)" >&2
        else
        bash "$SCRIPT_DIR/lib/yaml_field_set.sh" "$QUEUE_FILE" "$CMD_ID" "origin" "none" >/dev/null || return 1
        echo "INFO: origin未記入 → origin: none を自動挿入" >&2
        inserted=1
        fi
    fi

    if [[ "$inserted" -eq 1 ]]; then
        CMD_BLOCK_LOADED=0
        CMD_BLOCK_FOUND=0
        CMD_BLOCK_CACHE_LOADED=0
        declare -gA CMD_BLOCK_CACHE=()
        load_cmd_block || return 0
        load_cmd_block_cache || return 0
    fi
}

check_depends_on_field() {
    load_cmd_block || return 0
    load_cmd_block_cache || return 0

    local depends_on_value
    depends_on_value="$(cmd_block_get_field "depends_on")"

    if [[ -z "${depends_on_value:-}" ]]; then
        echo "WARNING: depends_on未記入。依存cmdがある場合は depends_on: cmd_XXXX、依存なしなら depends_on: none を記入せよ" >&2
        record_warn_reason "depends_on未記入" "check=depends_on_field"
        return 0
    fi

    if [[ "$depends_on_value" != "none" && ! "$depends_on_value" =~ ^cmd_[0-9]+$ ]]; then
        echo "WARNING: depends_on形式不正。depends_on: cmd_XXXX または depends_on: none のどちらかで記入せよ" >&2
        echo "  現在値: ${depends_on_value}" >&2
        record_warn_reason "depends_on形式不正" "check=depends_on_field"
    fi
}

check_origin_field() {
    load_cmd_block || return 0
    load_cmd_block_cache || return 0

    local origin_value
    origin_value="$(cmd_block_get_field "origin")"

    if [[ -z "${origin_value:-}" ]]; then
        record_block_reason "origin未記入。cmdの根拠を origin: \"[[発端]] -> [[原因]] -> [[結果]]\" 形式で記入せよ。因果NW成長の源泉"
        return 0
    fi

    if [[ "$origin_value" == "none" ]]; then
        record_block_reason "origin=none。因果辺なしではセマンティックインデックスに還流されない。最低1つの[[リンク]]を含めよ"
        return 0
    fi

    if ! grep -qE '\[\[[^]]+\]\]' <<< "$origin_value"; then
        record_block_reason "origin形式不正。Obsidian [[リンク]] を1つ以上含めよ (例: [[cmd_XXXX]] [[LGXXX]] [[殿裁定YYYY-MM-DD]])"
        echo "  現在値: ${origin_value}" >&2
    fi
}

collect_primary_cmd_targets() {
    [[ -n "${CMD_BLOCK_NC:-}" ]] || return 0

    # cmd_3801: 呼出元2箇所(show_target_path_git_history / check_bundle_red_flag)が
    # 同一CMD_BLOCK_NCに対し毎回8段のawk/sed/grep/sortパイプラインを再実行していた。
    # 結果をメモ化し2回目以降はforkなしで返す。
    if [[ -n "${_PRIMARY_CMD_TARGETS_CACHE_SET:-}" && "${_PRIMARY_CMD_TARGETS_CACHE_KEY-}" == "$CMD_BLOCK_NC" ]]; then
        printf '%s\n' "$_PRIMARY_CMD_TARGETS_CACHE"
        return 0
    fi

    normalize_bundle_path() {
        local path="${1:-}"
        local repo_root="${PROJECT_DIR:-${PROJECT_ROOT:-}}"
        path="${path%/}"

        if [[ -n "$repo_root" ]]; then
            path="${path#"$repo_root"/}"
            [[ "$path" == "$repo_root" ]] && path=""
        fi

        printf '%s\n' "$path"
    }

    detect_target_scope() {
        local raw_path="${1:-}"
        local repo_root="${PROJECT_DIR:-${PROJECT_ROOT:-}}"
        local normalized_path basename
        [[ -n "$raw_path" ]] || return 1

        normalized_path="$(normalize_bundle_path "$raw_path")"
        normalized_path="${normalized_path%/}"
        [[ -n "$normalized_path" ]] || return 1

        basename="${normalized_path##*/}"
        if [[ "$raw_path" == */ ]]; then
            printf '%s\n' "$normalized_path"
            return 0
        fi
        if [[ -n "$repo_root" && -d "$repo_root/$normalized_path" ]]; then
            printf '%s\n' "$normalized_path"
            return 0
        fi
        if [[ "$raw_path" = /* && -d "$raw_path" ]]; then
            printf '%s\n' "$normalized_path"
            return 0
        fi
        [[ "$basename" == *.* ]] && return 1
        return 1
    }

    local target_path_raw target_scope
    target_path_raw="$(
        printf '%s\n' "$CMD_BLOCK_NC" \
            | awk '
                /^[[:space:]]{4}target_path:[[:space:]]*/ {
                    sub(/^[[:space:]]{4}target_path:[[:space:]]*/, "")
                    if ($0 !~ /^[|>][-+]?$/) {
                        print
                    }
                    exit
                }
            '
    )"
    target_scope="$(detect_target_scope "$target_path_raw" || true)"

    _PRIMARY_CMD_TARGETS_CACHE="$(
    printf '%s\n' "$CMD_BLOCK_NC" \
        | awk '
            function emit_inline(value) {
                if (value != "" && value !~ /^[|>][-+]?$/) {
                    print value
                }
            }

            /^[[:space:]]{4}[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*/ {
                if (in_block && $0 !~ /^[[:space:]]{6,}/) {
                    in_block=0
                }

                match($0, /^[[:space:]]{4}([A-Za-z_][A-Za-z0-9_]*):[[:space:]]*(.*)$/, m)
                key=m[1]
                value=m[2]

                if (key == "target_path") {
                    if (value ~ /^[|>][-+]?$/) {
                        in_block=1
                    } else {
                        in_block=0
                        emit_inline(value)
                    }
                } else {
                    in_block=0
                }
                next
            }

            in_block && /^[[:space:]]{6,}/ { print }
        ' \
        | sed 's/--[A-Za-z_-]*[[:space:]]*[^[:space:]]*//g' \
        | grep -oE '((scripts|docs|context|config|projects|queue|lib|memory|logs|instructions|tests)/[^[:space:]`"'\''(),]+|/mnt/[^[:space:]`"'\''(),]+)' 2>/dev/null \
        | sed 's/[.,:;]$//' \
        | while IFS= read -r path; do
            local normalized_path
            normalized_path="$(normalize_bundle_path "$path")"
            [[ -n "$normalized_path" ]] || continue
            if [[ -n "$target_scope" && ( "$normalized_path" == "$target_scope" || "$normalized_path" == "$target_scope/"* ) ]]; then
                printf '%s\n' "$target_scope"
            else
                printf '%s\n' "$normalized_path"
            fi
        done \
        | awk '
            !/^tests(\/|$)/ &&
            !/^docs\/research(\/|$)/ &&
            !/^queue\/reports(\/|$)/ &&
            !/^queue\/archive(\/|$)/ &&
            !/^outputs(\/|$)/ &&
            !/^context(\/|$)/ {
                print
            }
        ' \
        | sort -u
    )"
    _PRIMARY_CMD_TARGETS_CACHE_SET=1
    _PRIMARY_CMD_TARGETS_CACHE_KEY="$CMD_BLOCK_NC"
    printf '%s\n' "$_PRIMARY_CMD_TARGETS_CACHE"
}

_cmd_save_git_target_info() {
    local target_path="${1:-}"
    local abs_path repo_root rel_path base_dir
    [[ -n "$target_path" ]] || return 1

    if [[ "$target_path" = /* ]]; then
        abs_path="$target_path"
    else
        abs_path="$PROJECT_DIR/$target_path"
    fi

    [[ -e "$abs_path" ]] || return 1

    if [[ -d "$abs_path" ]]; then
        base_dir="$abs_path"
    else
        base_dir="$(dirname "$abs_path")"
    fi

    repo_root="$(git -C "$base_dir" rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "$repo_root" ]] || return 1

    rel_path="$(realpath --relative-to="$repo_root" "$abs_path" 2>/dev/null || true)"
    [[ -n "$rel_path" ]] || return 1

    printf '%s\t%s\n' "$repo_root" "$rel_path"
}

_cmd_save_target_keyword() {
    local target_path="${1:-}"
    local base stem
    base="${target_path%/}"
    base="${base##*/}"
    [[ -n "$base" ]] || return 1
    stem="${base%.*}"
    if [[ -n "$stem" && "$stem" != "$base" ]]; then
        printf '%s\n' "$stem"
    else
        printf '%s\n' "$base"
    fi
}

show_target_path_git_history() {
    [[ -n "${CMD_BLOCK_NC:-}" ]] || return 0

    local targets target_path git_info repo_root rel_path keyword history keyword_history
    targets="$(collect_primary_cmd_targets || true)"
    [[ -n "${targets//[[:space:]]/}" ]] || return 0

    while IFS= read -r target_path; do
        [[ -n "${target_path//[[:space:]]/}" ]] || continue

        git_info="$(_cmd_save_git_target_info "$target_path" || true)"
        if [[ -z "$git_info" ]]; then
            echo "INFO: [TARGET_PATH_GIT] target_path git log: ${target_path} は存在しない、またはgit管理外のためスキップ" >&2
            continue
        fi

        IFS=$'\t' read -r repo_root rel_path <<< "$git_info"
        echo "INFO: [TARGET_PATH_GIT] target_path git log直近5件: ${rel_path}" >&2
        history="$(git -C "$repo_root" log --oneline -5 -- "$rel_path" 2>/dev/null || true)"
        if [[ -n "$history" ]]; then
            printf '%s\n' "$history" | sed 's/^/  - /' >&2
        else
            echo "  - 履歴なし" >&2
        fi

        keyword="$(_cmd_save_target_keyword "$rel_path" || true)"
        [[ -n "$keyword" ]] || continue
        echo "INFO: [TARGET_PATH_GIT] keyword git log --all --grep直近5件: ${keyword}" >&2
        keyword_history="$(git -C "$repo_root" log --all --oneline -5 --grep="$keyword" 2>/dev/null || true)"
        if [[ -n "$keyword_history" ]]; then
            printf '%s\n' "$keyword_history" | sed 's/^/  - /' >&2
        else
            echo "  - 履歴なし" >&2
        fi

        # L7e: 因果辺照合 — target_pathの設計意図を表示(因果衝突検知)
        local _causal_script="${CMD_SAVE_CAUSAL_BACKLINKS_SCRIPT:-$PROJECT_DIR/scripts/causal_backlinks.sh}"
        if [[ -f "$_causal_script" ]]; then
            local _causal_links
            _causal_links="$(bash "$_causal_script" "$keyword" 2>/dev/null | head -5 || true)"
            if [[ -n "$_causal_links" ]]; then
                echo "INFO: [TARGET_PATH_CAUSAL] 因果辺(設計意図照合): ${keyword}" >&2
                printf '%s\n' "$_causal_links" | sed 's/^/  → /' >&2
            fi
        fi
    done <<< "$targets"
}

cmd_save_is_causal_verification_scope() {
    [[ -n "${CMD_BLOCK_NC:-}" ]] || return 1
    local search_text
    search_text="$(awk '
        /^[[:space:]]*(title|purpose|command|target_path|scope|project):[[:space:]]*/ { print; next }
        /^[[:space:]]*acceptance_criteria:[[:space:]]*/ { in_ac=1; print; next }
        in_ac && /^[[:space:]]{4}[A-Za-z_][A-Za-z0-9_]*:/ { in_ac=0 }
        in_ac { print }
    ' <<< "$CMD_BLOCK_NC")"
    grep -qiE '(^|[^A-Za-z0-9_])(hook|gate|search)([^A-Za-z0-9_]|$)|daemon|semantic|memory[ _-]?db|記憶DB|deploy_task|配備フロー|report_field_set|gate_report_format|cmd_save|inbox_watcher|ninja_monitor' <<< "$search_text"
}

show_causal_verification_q5_template() {
    echo "  q5テンプレート: q5_verified_source: \"structure_verified — git log確認: <対象path/keywordと結果>; git blame確認: <file:line/理由>; semantic/causal確認: <concept/link>; 関連教訓: <Lxxx/none>\"" >&2
}

check_causal_verification_requirement() {
    cmd_save_is_causal_verification_scope || return 0

    echo "INFO: [CAUSAL_VERIFICATION] infra hook/gate/daemon/semantic/search/memory DB/配備フロー対象cmdです" >&2
    echo "  参照: docs/research/causal-verification-l0-l7-design_20260602.md" >&2
    echo "  必須: git log/blame・関連教訓・設計書・semantic/causal確認をq5/q8/origin/ACへ記録" >&2
    show_causal_verification_q5_template

    local origin_value q5_value q8_value combined structured_evidence_count
    origin_value="$(cmd_block_get_field "origin")"
    q5_value="$(cmd_block_get_field "quality_gate.q5_verified_source")"
    q8_value="$(cmd_block_get_field "quality_gate.q8_why_what")"
    combined="${origin_value}
${q5_value}
${q8_value}
$(extract_acceptance_criteria_block)"
    if [[ "${CMD_SAVE_DEBUG:-0}" == "1" ]]; then
        echo "DEBUG: [CAUSAL_VERIFICATION] q5_value=${q5_value}" >&2
    fi

    structured_evidence_count=0
    grep -qiE 'scripts/|context/|docs/|projects/|queue/|tests/|[A-Za-z0-9_./-]+\.(sh|py|md|yaml|bats)' <<< "$combined" && structured_evidence_count=$((structured_evidence_count + 1))
    grep -qiE 'commit|[0-9a-f]{7,40}|cmd_[0-9]+|L[0-9]+|lesson' <<< "$combined" && structured_evidence_count=$((structured_evidence_count + 1))
    grep -qiE '設計書|設計意図|design doc|docs/research/|教訓|lesson' <<< "$combined" && structured_evidence_count=$((structured_evidence_count + 1))

    if ! grep -qiE 'git log|git blame|blame|履歴|導入理由|設計意図|因果|causal|semantic|教訓|docs/research/causal-verification-l0-l7-design_20260602' <<< "$combined" && (( structured_evidence_count < 2 )); then
        echo "WARNING: 因果確認不足。対象scopeでは origin/q5/q8/AC に git log/blame・教訓・設計意図・semantic/causal確認を明記せよ" >&2
        record_warn_reason "causal_verification_missing" "check=check_causal_verification_requirement"
    fi
}

extract_cmd_target_path_text() {
    [[ -n "${CMD_BLOCK_NC:-}" ]] || return 0

    awk '
        /^[[:space:]]*target_path:[[:space:]]*/ {
            line = $0
            sub(/^[[:space:]]*target_path:[[:space:]]*/, "", line)
            if (line ~ /^[|>][-+]?([[:space:]]*#.*)?$/) {
                in_target = 1
            } else {
                print line
                in_target = 0
            }
            next
        }
        in_target && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*/ {
            in_target = 0
            next
        }
        in_target && /^[[:space:]]{2,}/ { print }
    ' <<< "$CMD_BLOCK_NC"
}

check_three_layer_penetration() {
    [[ -n "${CMD_BLOCK_NC:-}" ]] || return 0

    local target_text
    target_text="$(extract_cmd_target_path_text)"
    [[ -n "${target_text//[[:space:]]/}" ]] || return 0

    if ! grep -qiE 'memory_db|memory[_-]recall|obsidian[_-]promote|memory[_-]candidate|semantic-index|memory-db-schema' <<< "$target_text"; then
        return 0
    fi

    local ac_block command_block q8_value combined missing=()
    ac_block="$(extract_acceptance_criteria_block)"
    command_block="$(awk '
        /^[[:space:]]*command:[[:space:]]*\|/ { found=1; next }
        /^[[:space:]]*command:[[:space:]]*[^|]/ {
            found=1
            sub(/^[[:space:]]*command:[[:space:]]*/, "")
            print
            next
        }
        found && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*/ { exit }
        found { print }
    ' <<< "$CMD_BLOCK_NC")"
    q8_value="$(cmd_block_get_field "quality_gate.q8_why_what")"
    combined="${ac_block}
${command_block}
${q8_value}"

    if grep -qiE 'L0-L7.*(除外|対象外|不要|not applicable|n/a)|coverage.*(除外|対象外|不要|not applicable|n/a)|貫通.*(除外|対象外|不要)' <<< "$combined"; then
        return 0
    fi

    grep -qiE 'infrastructure\.md|context/infrastructure|infrastructure' <<< "$combined" || missing+=("infrastructure.md")
    grep -qiE 'startup[ _-]?gate|gate_(shogun|karo|gunshi)_startup|起動時|起動gate|起動ゲート' <<< "$combined" || missing+=("startup gate")
    grep -qiE 'deploy_task(\.sh)?|配備|task YAML|タスクYAML' <<< "$combined" || missing+=("deploy_task")
    grep -qiE 'prompt_state_inject|prompt[ _-]?state|state injection|プロンプト.*注入|状態注入' <<< "$combined" || missing+=("prompt_state_inject")
    grep -qiE 'ninja_monitor(\.sh)?|idle自動|自動トリガー|定期実行' <<< "$combined" || missing+=("ninja_monitor")

    if (( ${#missing[@]} > 0 )); then
        echo "WARNING: 三層記憶L0-L7 coverage map不足。記憶DB関連target_pathでは5接続先への言及または明示除外理由が必要です" >&2
        echo "  対象target_path: $(printf '%s' "$target_text" | tr '\n' ' ' | cut -c1-160)" >&2
        echo "  不足: ${missing[*]}" >&2
        echo "  必須接続先: infrastructure.md / startup gate / deploy_task / prompt_state_inject / ninja_monitor" >&2
        record_warn_reason "three_layer_penetration_missing" "check=check_three_layer_penetration"
    fi
}

check_self_reread_red_flag() {
    local combined

    combined=$(printf '%s\n%s\n%s\n' \
        "$(cmd_block_get_field "title")" \
        "$(cmd_block_get_field "purpose")" \
        "$CMD_BLOCK_NC")

    if grep -qiE '(自己(再読|申告)|自分で(読み直|読み返)|読み直[しせす]|読み返[しせす]|目視確認.*(品質|判定)|セルフレビュー)' <<< "$combined"; then
        if grep -qiE '(曖昧|不明瞭|ambiguous|clarity|明瞭)' <<< "$combined"; then
            echo "WARNING: 自己再読パターンを検出。書き手自身の目視確認/自己申告は mizchi Red flag『自分で読み直せば同じ効果』になりうる。別役割の評価者へ分離せよ" >&2
            record_warn_reason "自己再読パターン" "check=check_self_reread_red_flag"
        fi
    fi
}

check_bundle_red_flag() {
    local targets target_count bundle_signal targets_inline

    targets="$(collect_primary_cmd_targets || true)"
    target_count=$(awk 'NF{c++} END{print c+0}' <<< "$targets")
    bundle_signal=0

    # diagnosis行を除外: diagnosisは前回BLOCKの説明欄。バンドル表現が含まれても偽陽性になる(LS-A04-13, cmd_3407)
    local bundle_text
    bundle_text="$(grep -vE '^\s*diagnosis:' <<< "$CMD_BLOCK_NC" || true)"
    if grep -qiE '(^|[^A-Za-z])(bundle|バンドル)([^A-Za-z]|$)|\+|一気に|まとめて|同時に|複数|[0-9]+点|[0-9]+件|[0-9]+パターン|統合' <<< "$bundle_text"; then
        bundle_signal=1
    fi

    if (( target_count >= 3 )) || { (( target_count >= 2 )) && (( bundle_signal == 1 )); }; then
        targets_inline=$(awk 'NF{printf "%s%s", sep, $0; sep=", "} END{print ""}' <<< "$targets")
        echo "WARNING: バンドルパターンを検出。1cmdで複数対象(${target_count}): ${targets_inline}。無関係な修正を一気に束ねていないか確認せよ" >&2
        record_warn_reason "バンドルパターン" "check=check_bundle_red_flag"
    fi
}

record_block_reason() {
    local reason="${1:-}"
    [[ -n "$reason" ]] || return 0

    if [[ "${BLOCK_RETRY_NUDGE_EMITTED:-0}" -eq 0 ]]; then
        echo "${BLOCK_RETRY_NUDGE:-止まるな、修正して再実行せよ}" >&2
        BLOCK_RETRY_NUDGE_EMITTED=1
    fi

    echo "BLOCK: $reason" >&2
    BLOCK_REASONS+=("$reason")
    BLOCK_CHECKS+=("$(cmd_save_caller_check_name record_block_reason)")
    BLOCK_COUNT=$((BLOCK_COUNT + 1))
}

cmd_save_caller_check_name() {
    local skip_fn="${1:-}"
    local stack_fn
    for stack_fn in "${FUNCNAME[@]:1}"; do
        case "$stack_fn" in
            ""|cmd_save_caller_check_name|record_block_reason|record_warn_reason|main|source|"$skip_fn")
                continue
                ;;
        esac
        printf '%s' "$stack_fn"
        return 0
    done
    printf 'cmd_save_main'
}

emit_cmd_trigger_locations() {
    local check_name="${1:-unknown}"
    local reason="${2:-}"

    # cmd_2898: show the exact command YAML location that triggered each BLOCK/WARN.
    [[ -n "${QUEUE_FILE:-}" && -f "$QUEUE_FILE" && -n "${CMD_ID:-}" ]] || {
        printf '      - check=%s line=? keyword=? reason=%s\n' "$check_name" "$reason"
        return 0
    }

    CMD_SAVE_TRIGGER_CHECK="$check_name" \
    CMD_SAVE_TRIGGER_REASON="$reason" \
    CMD_SAVE_TRIGGER_CMD_ID="$CMD_ID" \
    python3 - "$QUEUE_FILE" <<'PY'
import os
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
cmd_id = os.environ.get("CMD_SAVE_TRIGGER_CMD_ID", "")
check = os.environ.get("CMD_SAVE_TRIGGER_CHECK", "unknown")
reason = os.environ.get("CMD_SAVE_TRIGGER_REASON", "")

try:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
except Exception:
    print(f"      - check={check} line=? keyword=? reason={reason}")
    raise SystemExit(0)

block = []
in_block = False
cmd_re = re.compile(r"^  cmd_[A-Za-z0-9_-]+:\s*$")
for lineno, line in enumerate(lines, 1):
    if not in_block:
        if re.match(rf"^  {re.escape(cmd_id)}:\s*$", line):
            in_block = True
            block.append((lineno, line))
        continue
    if cmd_re.match(line) and not re.match(rf"^  {re.escape(cmd_id)}:\s*$", line):
        break
    block.append((lineno, line))

stop = {
    "BLOCK", "WARN", "WARNING", "check", "cmd_save", "cmd", "reason",
    "未記入", "形式不正", "検出", "記載", "実行", "確認", "追加",
    "されて", "してください", "する", "せよ", "あり", "なし",
}
keywords = []

def add(token: str) -> None:
    token = token.strip().strip('"\':,，。「」（）()[]{}')
    if not token or token in stop or len(token) < 2:
        return
    if token not in keywords:
        keywords.append(token)

for token in re.findall(r"[A-Za-z_][A-Za-z0-9_.-]*|cmd_[0-9A-Za-z_-]+|q[0-9][A-Za-z0-9_.-]*", check):
    add(token)
for token in re.findall(r"[A-Za-z_][A-Za-z0-9_.-]*|cmd_[0-9A-Za-z_-]+|q[0-9][A-Za-z0-9_.-]*", reason):
    add(token)
for token in re.findall(r"[一-龥ぁ-んァ-ンー]{3,}", reason):
    add(token)
for quoted in re.findall(r"[「『'\"]([^」』'\"]{2,80})[」』'\"]", reason):
    for token in re.findall(r"[A-Za-z_][A-Za-z0-9_.-]*|q[0-9][A-Za-z0-9_.-]*|[一-龥ぁ-んァ-ンー]{2,}", quoted):
        add(token)

hits = []
seen = set()
for lineno, line in block:
    stripped = line.strip()
    if not stripped:
        continue
    for kw in keywords:
        if kw and kw in line:
            key = (lineno, kw)
            if key in seen:
                continue
            seen.add(key)
            hits.append((lineno, kw, stripped[:140]))
            if len(hits) >= 12:
                break
    if len(hits) >= 12:
        break

if hits:
    for lineno, kw, _text in hits:
        print(f"      - check={check} line={lineno} keyword={kw}")
else:
    print(f"      - check={check} line=? keyword=? reason={reason}")
PY
}

emit_block_warn_trigger_summary() {
    local i reason check_name warn_note

    if [[ ${#BLOCK_REASONS[@]} -gt 0 ]]; then
        echo "━━━ BLOCKトリガーマップ ━━━" >&2
        for i in "${!BLOCK_REASONS[@]}"; do
            reason="${BLOCK_REASONS[$i]}"
            check_name="${BLOCK_CHECKS[$i]:-cmd_save_main}"
            echo "  $((i+1)). ${reason}" >&2
            emit_cmd_trigger_locations "$check_name" "$reason" >&2
        done
        echo "━━━━━━━━━━━━━━━━" >&2
    fi

    if [[ ${#WARN_REASONS[@]} -gt 0 ]]; then
        echo "━━━ WARNトリガーマップ ━━━" >&2
        for i in "${!WARN_REASONS[@]}"; do
            warn_note="${WARN_REASONS[$i]}"
            reason="$(warn_note_message "$warn_note")"
            check_name="$(warn_note_check_name "$warn_note")"
            echo "  $((i+1)). ${reason}" >&2
            emit_cmd_trigger_locations "$check_name" "$reason" >&2
        done
        echo "━━━━━━━━━━━━━━━━" >&2
    fi
}

build_warn_note() {
    local reason="${1:-}"
    shift || true

    local warn_type=""
    if [[ $# -gt 0 && "$1" != *=* ]]; then
        warn_type="$1"
        shift || true
    fi

    [[ -n "$warn_type" ]] || warn_type="${reason:-warn_unknown}"

    local note="$warn_type"
    local metadata
    for metadata in "$@"; do
        [[ -n "$metadata" ]] || continue
        note="${note}|${metadata}"
    done

    if [[ -n "$reason" && "$reason" != "$warn_type" ]]; then
        note="${note}|${reason}"
    fi

    printf '%s' "$note"
}

warn_note_key() {
    local note="${1:-}"
    printf '%s' "${note%%|*}"
}

warn_note_message() {
    local note="${1:-}"
    [[ -n "$note" ]] || return 0

    local segment display=""
    IFS='|' read -r -a _warn_segments <<< "$note"
    if [[ ${#_warn_segments[@]} -le 1 ]]; then
        printf '%s' "$note"
        return 0
    fi

    for segment in "${_warn_segments[@]:1}"; do
        [[ -n "$segment" && "$segment" != *=* ]] || continue
        display="$segment"
    done

    printf '%s' "${display:-${_warn_segments[0]}}"
}

record_warn_reason() {
    local reason="${1:-}"
    shift || true

    local warn_args=("$@")
    local has_check_metadata=0
    local warn_arg
    for warn_arg in "${warn_args[@]}"; do
        if [[ "$warn_arg" == check=* ]]; then
            has_check_metadata=1
            break
        fi
    done

    if [[ "$has_check_metadata" -eq 0 ]]; then
        local caller_fn=""
        local stack_fn
        for stack_fn in "${FUNCNAME[@]:1}"; do
            case "$stack_fn" in
                ""|record_warn_reason|main|source)
                    continue
                    ;;
            esac
            caller_fn="$stack_fn"
            break
        done
        [[ -n "$caller_fn" ]] && warn_args+=("check=${caller_fn}")
    fi

    local warn_note warn_key display_reason
    warn_note="$(build_warn_note "$reason" "${warn_args[@]}")"
    warn_key="$(warn_note_key "$warn_note")"
    display_reason="$(warn_note_message "$warn_note")"

    WARN_REASONS+=("$warn_note")
    WARN_COUNT=$((WARN_COUNT + 1))
    # 遡及学習: 過去の同一WARN件数を即表示（殿裁定2026-04-21）
    # 1回目で「過去N回出ている」と気づけば根本修正のROIが分かる
    local _prior_count
    _prior_count=$(count_same_warn_pattern "$warn_key" 2>/dev/null || echo 0)
    [[ "$_prior_count" =~ ^[0-9]+$ ]] || _prior_count=0
    if (( _prior_count > 0 )); then
        echo "  ★ このWARN(${display_reason})は過去${_prior_count}回出現。消火ではなく根本修正を検討せよ。" >&2

        local _note_segment _check_name="" _src_file _grep_output=""
        IFS='|' read -r -a _warn_segments <<< "$warn_note"
        for _note_segment in "${_warn_segments[@]:1}"; do
            [[ "$_note_segment" == check=* ]] || continue
            _check_name="${_note_segment#check=}"
            break
        done

        _src_file="${SRC_SAVE_SCRIPT:-${BASH_SOURCE[0]:-$0}}"
        if [[ ! -f "$_src_file" && -n "${SAVE_SCRIPT:-}" && -f "$SAVE_SCRIPT" ]]; then
            _src_file="$SAVE_SCRIPT"
        fi

        if [[ -f "$_src_file" ]]; then
            if [[ -n "$_check_name" ]]; then
                _grep_output="$(grep -nF -- "$_check_name" "$_src_file" | head -n 2 || true)"
            fi
            if [[ -z "$_grep_output" && -n "$warn_key" ]]; then
                _grep_output="$(grep -nF -- "$warn_key" "$_src_file" | head -n 2 || true)"
            fi
        fi

        if [[ -n "$_grep_output" ]]; then
            echo "  ★ Session State: 検出ロジック該当行" >&2
            while IFS= read -r _grep_line; do
                [[ -n "$_grep_line" ]] || continue
                echo "    ${_grep_line}" >&2
            done <<< "$_grep_output"
        fi
    fi
}

warn_q5_pair_missing_session_state() {
    [[ -n "${CMD_BLOCK_NC:-}" ]] || return 0
    cmd_block_has_field "quality_gate.q5" || return 0
    cmd_block_has_field "quality_gate.q5_verified_source" && return 0

    echo "WARNING: q5_verified_source必須フィールド対。quality_gate.q5 が記入済みだが q5_verified_source が空/未記入です" >&2
    record_warn_reason "q5_verified_source必須フィールド対" "check=warn_q5_pair_missing_session_state"
}

warn_note_check_name() {
    local note="${1:-}"
    local segment
    IFS='|' read -r -a _warn_check_segments <<< "$note"
    for segment in "${_warn_check_segments[@]:1}"; do
        [[ "$segment" == check=* ]] || continue
        printf '%s' "${segment#check=}"
        return 0
    done
    printf '%s' "$(warn_note_key "$note")"
}

log_preflight_autolearn() {
    local warn_note="${1:-}"
    local prior_count="${2:-}"
    [[ -n "$warn_note" && -n "$prior_count" ]] || return 0

    local check_name warn_key timestamp tmp_dir
    check_name="$(warn_note_check_name "$warn_note")"
    warn_key="$(warn_note_key "$warn_note")"
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    tmp_dir="$(dirname "$PREFLIGHT_AUTOLEARN_FILE")"
    mkdir -p "$tmp_dir" 2>/dev/null || return 0

    {
        flock -w 5 201 || exit 0
        printf '%s check=%s count=%s warn=%s cmd=%s\n' \
            "$timestamp" "$check_name" "$prior_count" "$warn_key" "$CMD_ID" >> "$PREFLIGHT_AUTOLEARN_FILE"
    } 201>"${PREFLIGHT_AUTOLEARN_FILE}.lock" || true
}

abort_if_block_immediate() {
    [[ "$CMD_SAVE_ACCUMULATE_BLOCKS" == "1" ]] && return 0
    return 1
}

make_quality_log_scan_file() {
    [[ -f "$QUALITY_LOG_FILE" ]] || return 1
    # セッション内キャッシュ: PID固定パスにスキャンファイルを作成し再利用する。
    # サブシェル経由呼び出し( scan_file="$(make_quality_log_scan_file)" )でも
    # ファイル存在チェックで確実にキャッシュが効く。tail+awk+mktemp を N回→1回に削減。
    # .tmp=YAML版(show_quality_summary等のawk処理用)
    # .json=JSON版(Python関数でjson.loadを使用しyaml.safe_load比7x高速化)
    if [[ -f "$CMD_SAVE_SCAN_FILE_CACHE" ]]; then
        printf '%s\n' "$CMD_SAVE_SCAN_FILE_CACHE"
        return 0
    fi
    printf 'entries:\n' > "$CMD_SAVE_SCAN_FILE_CACHE"
    tail -n "$QUALITY_LOG_SCAN_LINES" "$QUALITY_LOG_FILE" \
        | awk 'BEGIN{in_entry=0} /^entries:[[:space:]]*$/{next} /^[[:space:]]*-[[:space:]]+cmd_id:/{in_entry=1} in_entry{print}' \
        >> "$CMD_SAVE_SCAN_FILE_CACHE"
    # JSON版生成: Python関数がjson.loadを使えるよう変換（yaml.safe_load 175ms→json.load 24ms）
    # perf: CSafeLoader(libyaml)使用でこの変換自体もPure Python比で高速化(実測0.25s級→大幅短縮)
    python3 -c "
import yaml, json, sys
_loader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)
with open(sys.argv[1], encoding='utf-8') as f:
    data = yaml.load(f, Loader=_loader) or {}
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    json.dump(data, f)
" "$CMD_SAVE_SCAN_FILE_CACHE" "$CMD_SAVE_SCAN_JSON_CACHE" 2>/dev/null || true
    printf '%s\n' "$CMD_SAVE_SCAN_FILE_CACHE"
}

show_prior_attempts() {
    [[ -f "$QUALITY_LOG_FILE" ]] || return 0
    # perf: grep fast-path — CMD_ID not in quality log → definitely 0 prior attempts
    # grep は python3 起動コスト(~0.25s×2)を回避。同一入力に対する出力は同一。
    if ! grep -qF "cmd_id: \"$CMD_ID\"" "$QUALITY_LOG_FILE" 2>/dev/null; then
        PRIOR_ATTEMPT_COUNT=0
        return 0
    fi

    local prior_output cache_file cache_tmp cache_sig cached_sig scan_file cache_key
    cache_key="$(printf '%s' "$QUALITY_LOG_FILE" | cksum | awk '{print $1}')"
    cache_file="/tmp/cmd_save_prior_attempts_${CMD_ID}_${cache_key}.cache"
    cache_sig="$(stat -c '%n:%y:%s' "$QUALITY_LOG_FILE" 2>/dev/null || echo "")"

    if [[ -n "$cache_sig" && -f "$cache_file" ]]; then
        IFS= read -r cached_sig < "$cache_file" || cached_sig=""
        if [[ "$cached_sig" == "$cache_sig" ]]; then
            prior_output="$(tail -n +2 "$cache_file")"
        fi
    fi

    if [[ -z "${prior_output:-}" ]]; then
        scan_file="$(make_quality_log_scan_file)" || return 0
        prior_output=$(CMD_SAVE_CMD_ID="$CMD_ID" CMD_SAVE_QUALITY_LOG="$scan_file" python3 - <<'PY'
import os
import json
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

_CSAFE = getattr(yaml, "CSafeLoader", yaml.SafeLoader)

cmd_id = os.environ.get("CMD_SAVE_CMD_ID", "")
log_path = os.environ.get("CMD_SAVE_QUALITY_LOG", "")

if not cmd_id or not log_path or not os.path.exists(log_path):
    print(0)
    raise SystemExit(0)

_json_path = log_path[:-4] + ".json" if log_path.endswith(".tmp") else ""
if _json_path and os.path.exists(_json_path):
    with open(_json_path) as fh:
        data = json.load(fh) or {}
else:
    with open(log_path, encoding="utf-8") as fh:
        data = yaml.load(fh, Loader=_CSAFE) or {}

entries = (data.get("entries") or []) if isinstance(data, dict) else []
filtered = []
for entry in entries:
    if not isinstance(entry, dict):
        continue
    if entry.get("cmd_id") != cmd_id:
        continue
    if entry.get("gate_result") != "BLOCK":
        continue
    if entry.get("source") != "cmd_save":
        continue
    filtered.append(entry)

print(len(filtered))
for idx, entry in enumerate(filtered, start=1):
    reason = str(entry.get("notes", "") or "").split("|")[0].strip() or "unknown"
    diagnosis = str(entry.get("diagnosis", "") or "").strip()
    if diagnosis:
        print(f"Attempt {idx}: {reason} diagnosis: {diagnosis}")
    else:
        print(f"Attempt {idx}: {reason}")
PY
)
        # scan_fileはCMD_SAVE_SCAN_FILE_CACHEの固定パスを指すため削除しない
        # (handle_cmd_save_exitでクリーンアップする)
        if [[ -n "$cache_sig" ]]; then
            cache_tmp="$(mktemp)"
            {
                printf '%s\n' "$cache_sig"
                printf '%s\n' "$prior_output"
            } > "$cache_tmp"
            mv "$cache_tmp" "$cache_file"
        fi
    fi

    IFS= read -r PRIOR_ATTEMPT_COUNT <<< "$prior_output"
    PRIOR_ATTEMPT_COUNT="${PRIOR_ATTEMPT_COUNT//[[:space:]]/}"
    [[ "${PRIOR_ATTEMPT_COUNT:-0}" =~ ^[0-9]+$ ]] || PRIOR_ATTEMPT_COUNT=0
    (( PRIOR_ATTEMPT_COUNT > 0 )) || return 0

    echo "★ Prior attempts (同じcmd):" >&2
    echo "$prior_output" | tail -n +2 | while IFS= read -r line; do
        [[ -n "$line" ]] && echo "  $line" >&2
    done
    echo "  DO NOT repeat these — 別のアプローチを取れ" >&2
}

count_same_reason_prior_blocks() {
    local current_reason="${1:-}"
    [[ -n "$current_reason" && -f "$QUALITY_LOG_FILE" ]] || {
        echo 0
        return 0
    }

    local scan_file
    scan_file="$(make_quality_log_scan_file)" || {
        echo 0
        return 0
    }
    CMD_SAVE_CMD_ID="$CMD_ID" \
    CMD_SAVE_QUALITY_LOG="$scan_file" \
    CMD_SAVE_BLOCK_REASON="$current_reason" \
    python3 - <<'PY'
import os
import json
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

_CSAFE = getattr(yaml, "CSafeLoader", yaml.SafeLoader)

cmd_id = os.environ.get("CMD_SAVE_CMD_ID", "")
log_path = os.environ.get("CMD_SAVE_QUALITY_LOG", "")
current_reason = os.environ.get("CMD_SAVE_BLOCK_REASON", "").strip()

if not cmd_id or not current_reason or not log_path or not os.path.exists(log_path):
    print(0)
    raise SystemExit(0)

_json_path = log_path[:-4] + ".json" if log_path.endswith(".tmp") else ""
if _json_path and os.path.exists(_json_path):
    with open(_json_path) as fh:
        data = json.load(fh) or {}
else:
    with open(log_path, encoding="utf-8") as fh:
        data = yaml.load(fh, Loader=_CSAFE) or {}

entries = (data.get("entries") or []) if isinstance(data, dict) else []
filtered = [
    entry for entry in entries
    if isinstance(entry, dict)
    and entry.get("cmd_id") == cmd_id
    and entry.get("gate_result") == "BLOCK"
    and entry.get("source") == "cmd_save"
]

count = 0
for entry in reversed(filtered[-5:]):
    reason = str(entry.get("notes", "") or "").split("|")[0].strip()
    if reason == current_reason:
        count += 1
    else:
        break

print(count)
PY
}

print_recent_block_pattern_summary() {
    [[ -f "$QUALITY_LOG_FILE" ]] || return 0

    local scan_file
    scan_file="$(make_quality_log_scan_file)" || return 0

    CMD_SAVE_QUALITY_LOG="$scan_file" \
    CMD_SAVE_ACK_LEDGER="$CMD_SAVE_SHOGUN_LESSON_ACK_FILE" python3 - <<'PY'
import json
import os
import re
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)
from collections import OrderedDict

_CSAFE = getattr(yaml, "CSafeLoader", yaml.SafeLoader)

log_path = os.environ.get("CMD_SAVE_QUALITY_LOG", "")
if not log_path or not os.path.exists(log_path):
    raise SystemExit(0)

json_path = log_path[:-4] + ".json" if log_path.endswith(".tmp") else ""
try:
    if json_path and os.path.exists(json_path):
        with open(json_path, encoding="utf-8") as fh:
            data = json.load(fh) or {}
    else:
        with open(log_path, encoding="utf-8") as fh:
            data = yaml.load(fh, Loader=_CSAFE) or {}
except Exception:
    raise SystemExit(0)

entries = (data.get("entries") or []) if isinstance(data, dict) else []
blocks = [
    entry for entry in entries
    if isinstance(entry, dict) and str(entry.get("gate_result", "")).strip() == "BLOCK"
]

# 2026-08-15 殿下知: 解決済みcmdがBLOCK SUMMARYへ永久に居座る不具合の修正。
# 原因=ack台帳(shogun_lesson_ack.yaml)に解決記録があってもこの表示側が一切参照していなかった。
# 実例=cmd_4302(ack 2026-08-14T06:45:18Z)とcmd_4303(同06:50:54Z)が翌日も毎回表示され続けた。
# 窓が件数基準(直近10件)であるため、品質が上がりBLOCKが減るほど古い項目が長く残る逆転も併発する。
# ∴解決済みcmdを除外する。除外後に残らなければ未解決ゼロとして何も表示しない。
_ack_path = os.environ.get("CMD_SAVE_ACK_LEDGER", "")
_acked = set()
if _ack_path and os.path.exists(_ack_path):
    try:
        with open(_ack_path, encoding="utf-8") as fh:
            _ack_data = yaml.load(fh, Loader=_CSAFE) or {}
        for _row in (_ack_data.get("acks") or []):
            if isinstance(_row, dict):
                _cmd = str(_row.get("cmd_id", "") or "").strip()
                if _cmd:
                    _acked.add(_cmd)
    except Exception:
        _acked = set()

_unresolved = [
    entry for entry in blocks
    if str(entry.get("cmd_id", "") or "").strip() not in _acked
]

# 窓が件数基準だけだと、ack手段を持たない家老側cmd等が無期限に居座る。
# entryはtimestampを持つため日数でも切る。両方を満たしたものだけを「直近の未解決」とする。
_max_age_days = 7
try:
    _max_age_days = int(os.environ.get("CMD_SAVE_BLOCK_SUMMARY_MAX_AGE_DAYS", "7"))
except ValueError:
    _max_age_days = 7
if _max_age_days > 0:
    import datetime as _dt
    _now = _dt.datetime.now(_dt.timezone.utc)
    _fresh = []
    for _entry in _unresolved:
        _raw_ts = str(_entry.get("timestamp", "") or "").strip()
        if not _raw_ts:
            _fresh.append(_entry)  # 時刻不明は落とさない(判断材料を黙って捨てない)
            continue
        try:
            _parsed = _dt.datetime.fromisoformat(_raw_ts.replace("Z", "+00:00"))
        except ValueError:
            _fresh.append(_entry)
            continue
        if _parsed.tzinfo is None:
            _parsed = _parsed.replace(tzinfo=_dt.timezone.utc)
        if (_now - _parsed).days < _max_age_days:
            _fresh.append(_entry)
    _unresolved = _fresh

recent = _unresolved[-10:]
if not recent:
    raise SystemExit(0)

patterns = OrderedDict()
for entry in recent:
    note = str(entry.get("notes", "") or "").strip()
    pattern = note.split("|", 1)[0].strip() or "unknown"
    pattern = re.sub(r"\s+", " ", pattern)
    cmd = str(entry.get("cmd_id", "") or "").strip() or "unknown"
    bucket = patterns.setdefault(pattern, set())
    bucket.add(cmd)

print("★ BLOCK SUMMARY: recent 10 pattern unique cmd counts")
for pattern, cmd_ids in patterns.items():
    shown = ",".join(sorted(cmd_ids)[:5])
    suffix = "" if len(cmd_ids) <= 5 else ",..."
    print(f"  - {pattern}: unique_cmds={len(cmd_ids)} cmd_ids={shown}{suffix}")
PY
}

count_same_check_prior_blocks() {
    local check_name="${1:-}"
    [[ -n "$check_name" && -f "$QUALITY_LOG_FILE" ]] || {
        echo 0
        return 0
    }
    if ! grep -qF "cmd_id: \"$CMD_ID\"" "$QUALITY_LOG_FILE" 2>/dev/null; then
        echo 0
        return 0
    fi
    local scan_file
    scan_file="$(make_quality_log_scan_file)" || {
        echo 0
        return 0
    }
    CMD_SAVE_CMD_ID="$CMD_ID" \
    CMD_SAVE_QUALITY_LOG="$scan_file" \
    CMD_SAVE_CHECK_NAME="$check_name" \
    python3 - <<'PY'
import os
import json
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

_CSAFE = getattr(yaml, "CSafeLoader", yaml.SafeLoader)

cmd_id = os.environ.get("CMD_SAVE_CMD_ID", "")
log_path = os.environ.get("CMD_SAVE_QUALITY_LOG", "")
target_check = os.environ.get("CMD_SAVE_CHECK_NAME", "").strip()

if not cmd_id or not target_check or not log_path or not os.path.exists(log_path):
    print(0)
    raise SystemExit(0)

_json_path = log_path[:-4] + ".json" if log_path.endswith(".tmp") else ""
if _json_path and os.path.exists(_json_path):
    with open(_json_path) as fh:
        data = json.load(fh) or {}
else:
    with open(log_path, encoding="utf-8") as fh:
        data = yaml.load(fh, Loader=_CSAFE) or {}

entries = (data.get("entries") or []) if isinstance(data, dict) else []
count = 0
for entry in entries:
    if not isinstance(entry, dict):
        continue
    if entry.get("cmd_id") != cmd_id:
        continue
    if entry.get("gate_result") != "BLOCK":
        continue
    if entry.get("source") != "cmd_save":
        continue
    checks_str = str(entry.get("checks", "") or "")
    if target_check in checks_str.split("|"):
        count += 1

print(count)
PY
}

extract_last_block_reason() {
    python3 - "$CMD_SAVE_STDERR_LOG" <<'PY'
import re
import sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()
except FileNotFoundError:
    print("")
    raise SystemExit(0)

for line in reversed(lines):
    match = re.match(r"BLOCK:\s*(.+)", line.strip())
    if match:
        print(match.group(1).strip())
        break
else:
    print("")
PY
}

cleanup_cmd_save_stderr_log() {
    [[ -n "${CMD_SAVE_STDERR_LOG:-}" && "$CMD_SAVE_STDERR_LOG" != "/dev/null" ]] || return 0
    rm -f "$CMD_SAVE_STDERR_LOG"
}

log_cmd_save_block() {
    local block_reason="${1:-}"
    local check_names="${2:-}"
    [[ "${CMD_SAVE_PREFLIGHT_ONLY:-0}" != "1" ]] || return 0
    [[ "${CMD_SAVE_DISABLE_QUALITY_LOG:-0}" != "1" ]] || return 0
    [[ -n "$block_reason" && -f "$SCRIPT_DIR/cmd_quality_log.sh" ]] || return 0
    log_cmd_save_fire_event "BLOCK" "$block_reason" "$check_names"
    if [[ "${CMD_SAVE_SYNC_QUALITY_LOG:-0}" == "1" ]]; then
        CMD_QUALITY_LOG_FILE="$QUALITY_LOG_FILE" \
        CMD_QUALITY_SOURCE="cmd_save" \
        CMD_QUALITY_DIAGNOSIS="$CMD_DIAGNOSIS" \
        CMD_QUALITY_PROJECT="$CMD_BLOCK_PROJECT" \
        CMD_QUALITY_CHECK_NAMES="$check_names" \
        CMD_QUALITY_FAST_METADATA=1 \
        bash "$SCRIPT_DIR/cmd_quality_log.sh" "$CMD_ID" "BLOCK" "no" "0" "$block_reason" >/dev/null 2>&1
    else
        # perf: 非同期化 — logging は fire-and-forget。flock で並列書き込み安全。
        CMD_QUALITY_LOG_FILE="$QUALITY_LOG_FILE" \
        CMD_QUALITY_SOURCE="cmd_save" \
        CMD_QUALITY_DIAGNOSIS="$CMD_DIAGNOSIS" \
        CMD_QUALITY_PROJECT="$CMD_BLOCK_PROJECT" \
        CMD_QUALITY_CHECK_NAMES="$check_names" \
        CMD_QUALITY_FAST_METADATA=1 \
        bash "$SCRIPT_DIR/cmd_quality_log.sh" "$CMD_ID" "BLOCK" "no" "0" "$block_reason" >/dev/null 2>&1 &
    fi
}

log_cmd_save_fire_event() {
    local result="${1:-}"
    local reason="${2:-}"
    local check_names="${3:-}"
    [[ "${CMD_SAVE_PREFLIGHT_ONLY:-0}" != "1" ]] || return 0
    [[ "${CMD_SAVE_DISABLE_FIRE_LOG:-0}" != "1" ]] || return 0
    [[ -n "$result" && -n "$CMD_ID" ]] || return 0

    local ts log_dir escaped_reason escaped_checks
    ts="$(date '+%Y-%m-%dT%H:%M:%S')"
    log_dir="$(dirname "$GATE_FIRE_LOG_FILE")"
    mkdir -p "$log_dir" 2>/dev/null || return 0
    escaped_reason="${reason//\\/\\\\}"
    escaped_reason="${escaped_reason//\"/\\\"}"
    escaped_checks="${check_names//\\/\\\\}"
    escaped_checks="${escaped_checks//\"/\\\"}"
    (
        flock -w 5 200 2>/dev/null || exit 0
        printf -- '- ts: "%s", file: "%s", gate: "cmd_save", result: %s, checks: "%s", reasons: "%s"\n' \
            "$ts" "$CMD_ID" "$result" "$escaped_checks" "$escaped_reason" >> "$GATE_FIRE_LOG_FILE"
    ) 200>"$GATE_FIRE_LOG_FILE.lock" 2>/dev/null || true
}

log_cmd_save_warns() {
    [[ "${CMD_SAVE_PREFLIGHT_ONLY:-0}" != "1" ]] || return 0
    [[ "${CMD_SAVE_DISABLE_QUALITY_LOG:-0}" != "1" ]] || return 0
    [[ ${#WARN_REASONS[@]} -gt 0 && -f "$SCRIPT_DIR/cmd_quality_log.sh" ]] || return 0
    local warn_note
    local warn_check_name
    local _project
    _project="$CMD_BLOCK_PROJECT"
    for warn_note in "${WARN_REASONS[@]}"; do
        warn_check_name="$(warn_note_check_name "$warn_note")"
        if [[ "${CMD_SAVE_SYNC_QUALITY_LOG:-0}" == "1" ]]; then
            CMD_QUALITY_LOG_FILE="$QUALITY_LOG_FILE" \
            CMD_QUALITY_SOURCE="cmd_save_warn" \
            CMD_QUALITY_DIAGNOSIS="" \
            CMD_QUALITY_PROJECT="$_project" \
            CMD_QUALITY_CHECK_NAMES="$warn_check_name" \
            CMD_QUALITY_FAST_METADATA=1 \
            bash "$SCRIPT_DIR/cmd_quality_log.sh" "$CMD_ID" "WARN" "no" "0" "$warn_note" >/dev/null 2>&1
        else
            # perf: 非同期化 — logging は fire-and-forget。flock で並列書き込み安全。
            CMD_QUALITY_LOG_FILE="$QUALITY_LOG_FILE" \
            CMD_QUALITY_SOURCE="cmd_save_warn" \
            CMD_QUALITY_DIAGNOSIS="" \
            CMD_QUALITY_PROJECT="$_project" \
            CMD_QUALITY_CHECK_NAMES="$warn_check_name" \
            CMD_QUALITY_FAST_METADATA=1 \
            bash "$SCRIPT_DIR/cmd_quality_log.sh" "$CMD_ID" "WARN" "no" "0" "$warn_note" >/dev/null 2>&1 &
        fi
        log_cmd_save_fire_event "WARN" "$warn_note" "$warn_check_name"
    done
}

log_cmd_save_pass() {
    [[ "${CMD_SAVE_PREFLIGHT_ONLY:-0}" != "1" ]] || return 0
    [[ "${CMD_SAVE_DISABLE_QUALITY_LOG:-0}" != "1" ]] || return 0
    [[ -n "$CMD_ID" ]] || return 0
    [[ -f "$SCRIPT_DIR/cmd_quality_log.sh" ]] || return 0
    if [[ "${CMD_SAVE_SYNC_QUALITY_LOG:-0}" == "1" ]]; then
        CMD_QUALITY_LOG_FILE="$QUALITY_LOG_FILE" \
        CMD_QUALITY_SOURCE="cmd_save" \
        CMD_QUALITY_DIAGNOSIS="" \
        CMD_QUALITY_PROJECT="$CMD_BLOCK_PROJECT" \
        CMD_QUALITY_BLOCK_DURATION="$BLOCK_DURATION_MINUTES" \
        CMD_QUALITY_FAST_METADATA=1 \
        bash "$SCRIPT_DIR/cmd_quality_log.sh" "$CMD_ID" "PASS" "no" "0" >/dev/null 2>&1
    else
        # perf: 非同期化 — logging は fire-and-forget。flock で並列書き込み安全。
        CMD_QUALITY_LOG_FILE="$QUALITY_LOG_FILE" \
        CMD_QUALITY_SOURCE="cmd_save" \
        CMD_QUALITY_DIAGNOSIS="" \
        CMD_QUALITY_PROJECT="$CMD_BLOCK_PROJECT" \
        CMD_QUALITY_BLOCK_DURATION="$BLOCK_DURATION_MINUTES" \
        CMD_QUALITY_FAST_METADATA=1 \
        bash "$SCRIPT_DIR/cmd_quality_log.sh" "$CMD_ID" "PASS" "no" "0" >/dev/null 2>&1 &
        # perf: 非同期化 — yaml_auto_archive.sh は結果に影響しない後処理。
        # A custom quality log is an isolated test/tool target.  Rotating the
        # repository default in that case leaks across the override boundary
        # and makes a clean unit run mutate tracked operational logs.
        if [[ "$QUALITY_LOG_FILE" == "$PROJECT_DIR/logs/cmd_design_quality.yaml" ]]; then
            bash "$SCRIPT_DIR/yaml_auto_archive.sh" >/dev/null 2>&1 &
        fi
    fi
}

count_same_warn_pattern() {
    local warn_pattern="${1:-}"
    local output_mode="${2:-count}"
    [[ -n "$warn_pattern" && -f "$QUALITY_LOG_FILE" ]] || {
        [[ "$output_mode" == "cmd_ids" ]] && echo "" || echo 0
        return 0
    }
    local current_project
    local scan_file
    current_project="$CMD_BLOCK_PROJECT"
    scan_file="$(make_quality_log_scan_file)" || {
        echo 0
        return 0
    }
    CMD_SAVE_CMD_ID="$CMD_ID" \
    CMD_SAVE_QUALITY_LOG="$scan_file" \
    CMD_SAVE_WARN_PATTERN="$warn_pattern" \
    CMD_SAVE_WARN_OUTPUT_MODE="$output_mode" \
    CMD_SAVE_CURRENT_PROJECT="$current_project" \
    CMD_SAVE_QUEUE_FILE="$QUEUE_FILE" \
    CMD_SAVE_ARCHIVE_CMD_DIR="$ARCHIVE_CMD_DIR" \
    CMD_SAVE_SHOGUN_LESSONS_FILE="$CMD_SAVE_SHOGUN_LESSONS_FILE" \
    python3 - <<'PY'
import os
import glob
import json
import re
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

_CSAFE = getattr(yaml, "CSafeLoader", yaml.SafeLoader)

cmd_id = os.environ.get("CMD_SAVE_CMD_ID", "")
log_path = os.environ.get("CMD_SAVE_QUALITY_LOG", "")
warn_pattern = os.environ.get("CMD_SAVE_WARN_PATTERN", "").strip()
output_mode = os.environ.get("CMD_SAVE_WARN_OUTPUT_MODE", "count").strip()
current_project = os.environ.get("CMD_SAVE_CURRENT_PROJECT", "").strip()
queue_path = os.environ.get("CMD_SAVE_QUEUE_FILE", "")
archive_dir = os.environ.get("CMD_SAVE_ARCHIVE_CMD_DIR", "")
lessons_path = os.environ.get("CMD_SAVE_SHOGUN_LESSONS_FILE", "")

if not cmd_id or not warn_pattern or not log_path or not os.path.exists(log_path):
    print("" if output_mode == "cmd_ids" else 0)
    raise SystemExit(0)

resolved_source_cmds = set()
if lessons_path and os.path.exists(lessons_path):
    with open(lessons_path, encoding="utf-8") as fh:
        for line in fh:
            match = re.match(r'^\s*source_cmd:\s*["\']?([^"\']+)["\']?\s*$', line)
            if match:
                resolved_source_cmds.add(match.group(1).strip())

_json_path = log_path[:-4] + ".json" if log_path.endswith(".tmp") else ""
if _json_path and os.path.exists(_json_path):
    with open(_json_path) as fh:
        data = json.load(fh) or {}
else:
    with open(log_path, encoding="utf-8") as fh:
        data = yaml.load(fh, Loader=_CSAFE) or {}

project_cache = {}

def extract_project(payload, target_cmd):
    if not isinstance(payload, dict):
        return ""
    commands = payload.get("commands")
    if isinstance(commands, dict):
        cmd_data = commands.get(target_cmd)
        if isinstance(cmd_data, dict):
            return str(cmd_data.get("project", "") or "").strip()
    cmd_data = payload.get(target_cmd)
    if isinstance(cmd_data, dict):
        return str(cmd_data.get("project", "") or "").strip()
    if str(payload.get("id", "") or "").strip() == target_cmd:
        return str(payload.get("project", "") or "").strip()
    return str(payload.get("project", "") or "").strip()

def read_project_from_yaml(path, target_cmd):
    try:
        with open(path, encoding="utf-8") as fh:
            return extract_project(yaml.load(fh, Loader=_CSAFE) or {}, target_cmd)
    except Exception:
        return ""

canceled_cache = {}

def is_cmd_canceled(target_cmd):
    """Check if cmd has status=canceled in queue or archive YAML."""
    if not target_cmd:
        return False
    if target_cmd in canceled_cache:
        return canceled_cache[target_cmd]
    result = False
    for path in ([queue_path] if queue_path and os.path.exists(queue_path) else []):
        try:
            with open(path, encoding="utf-8") as fh:
                payload = yaml.load(fh, Loader=_CSAFE) or {}
            commands = payload.get("commands", payload)
            if isinstance(commands, dict):
                cmd_data = commands.get(target_cmd)
                if isinstance(cmd_data, dict) and str(cmd_data.get("status", "")).strip() == "canceled":
                    result = True
        except Exception:
            pass
    canceled_cache[target_cmd] = result
    return result

def resolve_cmd_project(target_cmd, entry):
    if not target_cmd:
        return ""
    if isinstance(entry, dict):
        explicit = str(entry.get("project", "") or "").strip()
        if explicit:
            return explicit
    if target_cmd == cmd_id and current_project:
        return current_project
    if target_cmd in project_cache:
        return project_cache[target_cmd]

    project = ""
    if queue_path and os.path.exists(queue_path):
        project = read_project_from_yaml(queue_path, target_cmd)
    if not project and archive_dir and os.path.isdir(archive_dir):
        for path in sorted(glob.glob(os.path.join(archive_dir, f"{target_cmd}*.yaml"))):
            project = read_project_from_yaml(path, target_cmd)
            if project:
                break

    project_cache[target_cmd] = project
    return project

def project_matches(entry):
    if not current_project:
        return True
    entry_cmd = str(entry.get("cmd_id", "") or "").strip()
    entry_project = resolve_cmd_project(entry_cmd, entry)
    if entry_project:
        return entry_project == current_project
    # Legacy cmd_save_warn rows predate project logging. They came from the infra
    # command queue; keep infra continuity without contaminating external projects.
    return current_project == "infra"

entries = (data.get("entries") or []) if isinstance(data, dict) else []
matching_cmd_ids_set = set()
matching_cmd_ids_ordered = []
for entry in entries:
    if not isinstance(entry, dict):
        continue
    note = str(entry.get("notes", "") or "").strip()
    if not (
        project_matches(entry)
        and entry.get("source") == "cmd_save_warn"
        and entry.get("gate_result") == "WARN"
        and (note.split("|", 1)[0].strip() == warn_pattern or warn_pattern in note)
        and "[resolved:" not in note
        and not entry.get("resolved_by")
        and not (
            note.split("|", 1)[0].strip() == "missing_prev_cmd_lesson"
            and any(
                part.startswith("source_cmd=")
                and part.split("=", 1)[1].strip() in resolved_source_cmds
                for part in note.split("|")[1:]
            )
        )
    ):
        continue
    entry_cmd = str(entry.get("cmd_id", "") or "").strip()
    # cmd_3801/737350613: 同一cmd_id内の繰り返しのみ累計昇格対象(殿裁定2026-07-09 22:50)。
    # cmd_ids モードの呼出元(WARN累計昇格)は自身のcmd_idの再発回数を数えるため、
    # 下のFP fix(他cmdのunique化)とは別に、self-repeatは重複除外せず1件ずつ数える。
    if output_mode == "cmd_ids" and entry_cmd and entry_cmd == cmd_id:
        matching_cmd_ids_ordered.append(entry_cmd)
        continue
    # FP fix: count unique cmd_ids only (same cmd retry creates duplicate WARN entries)
    # FP fix (2026-06-26): skip canceled cmds — their WARNs are invalid (cmd_3537 canceled but counted)
    if entry_cmd and entry_cmd != cmd_id and entry_cmd not in matching_cmd_ids_set and not is_cmd_canceled(entry_cmd):
        matching_cmd_ids_set.add(entry_cmd)
        matching_cmd_ids_ordered.append(entry_cmd)

if output_mode == "cmd_ids":
    print(",".join(matching_cmd_ids_ordered[-10:]))
else:
    print(len(matching_cmd_ids_set))
PY
}

count_cmd_save_blocks_for_cmd() {
    local target_cmd_id="${1:-}"
    [[ -n "$target_cmd_id" && -f "$QUALITY_LOG_FILE" ]] || {
        echo 0
        return 0
    }
    # perf: grep fast-path — cmd not in quality log → definitely 0 blocks
    # grep は python3 起動コスト(~0.25s)を回避。同一入力に対する出力は同一。
    if ! grep -qF "cmd_id: \"$target_cmd_id\"" "$QUALITY_LOG_FILE" 2>/dev/null; then
        echo 0
        return 0
    fi

    local scan_file
    scan_file="$(make_quality_log_scan_file)" || {
        echo 0
        return 0
    }
    CMD_SAVE_TARGET_CMD_ID="$target_cmd_id" \
    CMD_SAVE_QUALITY_LOG="$scan_file" \
    python3 - <<'PY'
import os
import json
import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

_CSAFE = getattr(yaml, "CSafeLoader", yaml.SafeLoader)

cmd_id = os.environ.get("CMD_SAVE_TARGET_CMD_ID", "")
log_path = os.environ.get("CMD_SAVE_QUALITY_LOG", "")

if not cmd_id or not log_path or not os.path.exists(log_path):
    print(0)
    raise SystemExit(0)

_json_path = log_path[:-4] + ".json" if log_path.endswith(".tmp") else ""
if _json_path and os.path.exists(_json_path):
    with open(_json_path) as fh:
        data = json.load(fh) or {}
else:
    with open(log_path, encoding="utf-8") as fh:
        data = yaml.load(fh, Loader=_CSAFE) or {}

entries = (data.get("entries") or []) if isinstance(data, dict) else []
count = sum(
    1
    for entry in entries
    if isinstance(entry, dict)
    and entry.get("cmd_id") == cmd_id
    and entry.get("gate_result") == "BLOCK"
    and entry.get("source") == "cmd_save"
)
print(count)
PY
}

cmd_save_shogun_lesson_exists_for_cmd() {
    local source_cmd_id="${1:-}"
    [[ -n "$source_cmd_id" ]] || return 1

    if [[ -f "$CMD_SAVE_SHOGUN_LESSON_ACK_FILE" ]] && grep -qE "^[[:space:]]*-[[:space:]]+cmd_id:[[:space:]]*['\"]?${source_cmd_id}['\"]?" "$CMD_SAVE_SHOGUN_LESSON_ACK_FILE" 2>/dev/null; then
        return 0
    fi

    [[ -f "$CMD_SAVE_SHOGUN_LESSONS_FILE" ]] || return 1

    # v1形式: source_cmd: cmd_XXXX
    if grep -qE "^[[:space:]]+source_cmd:[[:space:]]*['\"]?${source_cmd_id}['\"]?" "$CMD_SAVE_SHOGUN_LESSONS_FILE" 2>/dev/null; then
        return 0
    fi
    # v2形式: source_cmdがなくても、detail/enforcement等でcmd_idに言及されていれば記録済みとみなす
    if grep -qF "${source_cmd_id}" "$CMD_SAVE_SHOGUN_LESSONS_FILE" 2>/dev/null; then
        return 0
    fi

    return 1
}

cmd_save_default_ack_lesson_id() {
    local resolved=""

    [[ -f "$CMD_SAVE_SHOGUN_LESSONS_FILE" ]] || return 0

    # Never propose a dead identifier. Choose the newest active canonical
    # lesson directly from the guarded SSOT.
    resolved="$(awk '
        /^[[:space:]]*-[[:space:]]+id:/ {
            if (id != "" && !superseded) latest = id
            id = $0
            sub(/^[[:space:]]*-[[:space:]]+id:[[:space:]]*/, "", id)
            gsub(/["'\''[:space:]]/, "", id)
            superseded = 0
            next
        }
        /^[[:space:]]+superseded_by:/ { superseded = 1 }
        END {
            if (id != "" && !superseded) latest = id
            print latest
        }
    ' "$CMD_SAVE_SHOGUN_LESSONS_FILE" 2>/dev/null)"
    [[ -n "$resolved" ]] && printf '%s\n' "$resolved"
}

warn_missing_prev_cmd_lesson() {
    [[ -f "$CMD_SAVE_LAST_CMD_FILE" ]] || return 0

    local prev_cmd_id prev_block_count warn_msg ack_lesson_id
    prev_cmd_id="$(tr -d '[:space:]' < "$CMD_SAVE_LAST_CMD_FILE" 2>/dev/null || true)"
    [[ -n "$prev_cmd_id" && "$prev_cmd_id" != "$CMD_ID" ]] || return 0

    prev_block_count="$(count_cmd_save_blocks_for_cmd "$prev_cmd_id")"
    [[ "$prev_block_count" =~ ^[0-9]+$ ]] || prev_block_count=0
    (( prev_block_count > 0 )) || return 0

    cmd_save_shogun_lesson_exists_for_cmd "$prev_cmd_id" && return 0

    ack_lesson_id="$(cmd_save_default_ack_lesson_id)"
    warn_msg="前${prev_cmd_id}で${prev_block_count}回BLOCKされたが教訓未記録。lesson_write_shogun.shで記録せよ。"
    if [[ -n "$ack_lesson_id" ]]; then
        warn_msg+="既知パターンなら: bash scripts/shogun_lesson_ack.sh ${prev_cmd_id} ${ack_lesson_id}"
    fi
    record_block_reason "$warn_msg"
}

remind_missing_current_cmd_lesson_after_clear() {
    local current_block_count remind_msg ack_lesson_id
    current_block_count="$(count_cmd_save_blocks_for_cmd "$CMD_ID")"
    [[ "$current_block_count" =~ ^[0-9]+$ ]] || current_block_count=0
    (( current_block_count > 0 )) || return 0

    cmd_save_shogun_lesson_exists_for_cmd "$CMD_ID" && return 0

    ack_lesson_id="$(cmd_save_default_ack_lesson_id)"
    remind_msg="${CMD_ID}で${current_block_count}回BLOCKされたが教訓未記録。lesson_write_shogun.shで記録せよ。"
    if [[ -n "$ack_lesson_id" ]]; then
        remind_msg+="既知パターンなら: bash scripts/shogun_lesson_ack.sh ${CMD_ID} ${ack_lesson_id}"
    fi
    echo "REMIND: ${remind_msg}" >&2
    echo "REMIND: 環境埋込み判定: 同じBLOCKを既存hookテンプレート注入で防止可能か、gate修正が必要かを判定せよ。" >&2
}

handle_cmd_save_exit() {
    local status=$?
    trap - EXIT

    # 内部フェーズ計装(cmd_4169): 区間計測済みのCMD_SAVE_PHASE_EVENTSをsource:cmd_saveで台帳へ一括記録。
    # 判定(BLOCK_COUNT/WARN_COUNT)そのものは変更しない。verdictは既存の確定ロジック
    # (BLOCK_COUNT>0=BLOCK, WARN_COUNT>0=WARN, それ以外=PASS)をそのまま踏襲する。
    if [[ "${#CMD_SAVE_PHASE_EVENTS[@]}" -gt 0 ]]; then
        local _cs_verdict _cs_i _cs_phase _cs_ms
        local -a _cs_batch=()
        if [[ "${BLOCK_COUNT:-0}" -gt 0 ]]; then
            _cs_verdict=BLOCK
        elif [[ "${WARN_COUNT:-0}" -gt 0 ]]; then
            _cs_verdict=WARN
        else
            _cs_verdict=PASS
        fi
        for (( _cs_i=0; _cs_i<${#CMD_SAVE_PHASE_EVENTS[@]}; _cs_i+=2 )); do
            _cs_phase="${CMD_SAVE_PHASE_EVENTS[$_cs_i]}"
            _cs_ms="${CMD_SAVE_PHASE_EVENTS[$((_cs_i+1))]}"
            _cs_batch+=(cmd_save "$_cs_phase" "$_cs_ms" "$_cs_verdict" "${CMD_SAVE_RUN_ID:-cmd_unknown-$$}-${_cs_phase}")
        done
        defense_overhead_write_batch_async "${_cs_batch[@]}" || true
    fi

    # save_total: script開始からEXITまでの全wall(未計装区間込み)。計測盲点根絶(殿指示2026-08-04)。
    if [[ -n "${CMD_SAVE_TOTAL_T0_US:-}" ]]; then
        local _cs_total_now_us _cs_total_ms _cs_total_verdict
        _cs_total_now_us="${EPOCHREALTIME/./}"
        _cs_total_now_us="${_cs_total_now_us:0:16}"
        _cs_total_ms=$(( (_cs_total_now_us - CMD_SAVE_TOTAL_T0_US + 999) / 1000 ))
        if [[ "${BLOCK_COUNT:-0}" -gt 0 ]]; then
            _cs_total_verdict=BLOCK
        elif [[ "${WARN_COUNT:-0}" -gt 0 ]]; then
            _cs_total_verdict=WARN
        else
            _cs_total_verdict=PASS
        fi
        defense_overhead_write_async cmd_save save_total "$_cs_total_ms" "$_cs_total_verdict" "${CMD_SAVE_RUN_ID:-cmd_unknown-$$}-save_total" || true
    fi

    if [[ "$status" -ne 0 ]]; then
        local block_reason same_reason_count
        if [[ ${#BLOCK_REASONS[@]} -gt 0 ]]; then
            block_reason="${BLOCK_REASONS[-1]}"
        else
            block_reason="$(extract_last_block_reason)"
        fi

        if [[ -n "$block_reason" ]]; then
            if [[ -n "$CMD_DIAGNOSIS" ]]; then
                echo "診断: $CMD_DIAGNOSIS" >&2
            fi

            echo "★ 診断せよ: なぜこのBLOCKが起きたか？根本原因を1行で書け。" >&2
            echo '★ 修正前に: quality_gateに diagnosis: "根本原因の1行記述" を追加してから再実行せよ。' >&2

            # --- resolution_hint: BLOCK理由に対応する解消手順を自動表示 ---
            # 軍師提案(A): 行動コストを下げて同じBLOCKの繰り返しを防ぐ
            case "$block_reason" in
                *"ファイルパスが存在しません"*|*"親ディレクトリも不在"*)
                    echo "★ 解消: ls でパスを確認。見つからなければ grep -rn 'ファイル名' で検索せよ。" >&2 ;;
                *"必須項目"*"未記入"*)
                    echo "★ 解消: quality_gate: に q1_firefighting/q2_learning/q3_next_quality を追加。各1行で理由を書け。" >&2 ;;
                *"q9_firefighting_root_cause"*)
                    echo "★ 解消: q9_firefighting_root_cause: \"真因: ... 再発防止: ...\" を追加せよ。" >&2 ;;
                *"q5="*"code_reading"*)
                    echo "★ 解消: q5を isolated_test/structure_verified/production_verified に昇格。確認した証拠を1行追記。" >&2 ;;
                *"未検証前提"*|*"trust:unverified"*)
                    echo "★ 解消: assumptions内のtrust:unverifiedをtrust:verifiedに変更。確認手段(コマンド/ファイル)を明記。" >&2 ;;
                *"既に委任済み"*)
                    echo "★ 解消: cmd_idが重複。新しいcmd_idで起票し直せ。" >&2 ;;
                *"WARN累計昇格"*)
                    echo "★ 解消: 繰り返しWARNの根因を修正せよ。偽陽性ならgateのチェック条件を修正。" >&2 ;;
            esac

            same_reason_count="$(count_same_reason_prior_blocks "$block_reason" | tr -d '[:space:]')"
            [[ "$same_reason_count" =~ ^[0-9]+$ ]] || same_reason_count=0
            if (( same_reason_count >= 1 )); then
                echo "★ DIVERGENT: 同じチェック($block_reason)で2回連続BLOCK。" >&2
                echo "  根本的に異なるアプローチを検討せよ。" >&2
            fi
            print_recent_block_pattern_summary >&2 || true

            local _exit_checks_str
            _exit_checks_str="$(build_unique_block_checks_str 2>/dev/null || true)"
            log_cmd_save_block "$block_reason" "$_exit_checks_str"
        fi
    fi

    cleanup_cmd_save_stderr_log
    rm -f "${CMD_SAVE_SCAN_FILE_CACHE:-}"
    rm -f "${CMD_SAVE_SCAN_JSON_CACHE:-}"
    exit "$status"
}

check_ac_structure_quality() {
    _CHECK19_ISSUES=()

    if [[ -n "${AC_TEXT:-}" ]]; then
        # 同じAC_TEXTへのgrep多段起動を単一awk走査へ統合する。
        # 5カウンタは後段Check17/20も再利用し、恒常PASS経路のforkを削る。
        IFS=$'\t' read -r _FILL_COUNT _DESC_EMPTY_COUNT _AC_ENTRY_COUNT _BC_TOTAL _BC_EMPTY < <(
            awk '
                /FILL_THIS/ { fill++ }
                /^[[:space:]]*description:[[:space:]]*(""|'\'''\''|)[[:space:]]*$/ { desc_empty++ }
                /^[[:space:]]+AC[0-9]+:[[:space:]]*$/ { ac_entry++ }
                /^[[:space:]]*binary_check:/ {
                    bc_total++
                    if ($0 ~ /^[[:space:]]*binary_check:[[:space:]]*(""|'\'''\''|)[[:space:]]*$/) bc_empty++
                }
                END {
                    printf "%d\t%d\t%d\t%d\t%d\n",
                        fill + 0, desc_empty + 0, ac_entry + 0, bc_total + 0, bc_empty + 0
                }
            ' <<< "$AC_TEXT"
        )

        if [[ "${_FILL_COUNT:-0}" -gt 0 ]]; then
            _CHECK19_ISSUES+=("FILL_THISマーカー残存: ${_FILL_COUNT}件")
            awk '/FILL_THIS/{print NR ":" $0; if (++hits == 3) exit}' <<< "$AC_TEXT" >&2
        fi

        if [[ "${_DESC_EMPTY_COUNT:-0}" -gt 0 ]]; then
            _CHECK19_ISSUES+=("description空値: ${_DESC_EMPTY_COUNT}件")
        fi

        if [[ "${_AC_ENTRY_COUNT:-0}" -gt 0 && "${_BC_TOTAL:-0}" -eq 0 ]]; then
            _CHECK19_ISSUES+=("binary_checkフィールド不在(AC${_AC_ENTRY_COUNT}件全て)")
        elif [[ "${_BC_EMPTY:-0}" -gt 0 ]]; then
            _CHECK19_ISSUES+=("binary_check空値: ${_BC_EMPTY}件")
        fi
    fi

    if [[ ${#_CHECK19_ISSUES[@]} -gt 0 ]]; then
        echo "WARNING: AC YAML構造判定(Check19)で不備を検出" >&2
        for _issue in "${_CHECK19_ISSUES[@]}"; do
            echo "  ✗ $_issue" >&2
        done
        printf '  修正: 各ACにdescription+binary_checkを記入し、FILL_THISを実内容で埋めよ\n' >&2
        printf '  例:\n  acceptance_criteria:\n    AC1:\n      description: "具体的な達成条件"\n      binary_check: "確認方法を1行で"\n' >&2
        record_warn_reason "ac_structure_incomplete" "check=check_ac_structure_quality"
    fi
}

check_unverified_assumptions_block() {
    local assumption_block
    assumption_block="$(grep -A5 "assumptions:" <<< "$CMD_BLOCK_NC" || true)"
    if grep -q "trust:.*unverified\|trust: unverified" <<< "$assumption_block"; then
        record_block_reason "未検証前提あり。現物確認してtrust:verifiedに変更せよ"
        abort_if_block_immediate || exit 1
    fi
}

check_assumption_source_paths_block() {
    _ASSUMP_PROJECT_ID="$CMD_BLOCK_PROJECT"
    [[ -z "${_ASSUMP_PROJECT_ID:-}" ]] && _ASSUMP_PROJECT_ID=$(awk '/^current_project:/{print $2}' "$PROJECT_DIR/config/projects.yaml" 2>/dev/null || true)
    if [[ -n "${_ASSUMP_PROJECT_ID:-}" ]]; then
        _ASSUMP_PROJECT_WD=$(awk -v id="$_ASSUMP_PROJECT_ID" '
            /^  - id:/ { current_id = $3; gsub(/"/, "", current_id) }
            /^    path:/ && current_id == id { gsub(/.*path: *"?/, ""); gsub(/"$/, ""); print; exit }
        ' "$PROJECT_DIR/config/projects.yaml" 2>/dev/null || true)
    fi
    if [[ -z "${_ASSUMP_PROJECT_WD:-}" ]]; then
        return 0
    fi

    _ASSUMP_VERIFIED_PATHS=$(echo "$CMD_BLOCK_NC" | python3 -c "
import sys, re
content = sys.stdin.buffer.read().decode('utf-8', errors='replace')
lines = content.split('\n')
in_assumptions = False
assumptions_indent = -1
current = {}
entries = []
for line in lines:
    m_aline = re.match(r'^(\s*)assumptions\s*:', line)
    if m_aline and not in_assumptions:
        in_assumptions = True
        assumptions_indent = len(m_aline.group(1))
        continue
    if in_assumptions:
        if line.strip():
            cur_indent = len(line) - len(line.lstrip())
            if cur_indent <= assumptions_indent:
                in_assumptions = False
                if current: entries.append(dict(current))
                current = {}
                continue
        if re.match(r'\s*-\s', line):
            if current:
                entries.append(dict(current))
            current = {}
        m = re.search(r'^\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.+)', line)
        if m:
            current[m.group(1)] = m.group(2).strip().strip('\"').strip(\"'\")
if current: entries.append(current)
pat = re.compile(r'/?[A-Za-z0-9_.-]+(/[A-Za-z0-9_.+-]+)+\.(py|tsx|ts|jsx|js|sh|bash|yaml|yml|json|sql|html|css|toml|cfg|env)(?![a-zA-Z])')
for e in entries:
    trust = e.get('trust', '')
    if 'verified' in trust and 'unverified' not in trust:
        skip_keys = {'trust', 'claim', 'assumption'}
        for key, val in e.items():
            if key in skip_keys:
                continue
            for m in pat.finditer(val):
                print(m.group(0))
" 2>/dev/null || true)
    if [[ -z "${_ASSUMP_VERIFIED_PATHS:-}" ]]; then
        return 0
    fi

    _ASSUMP_HAS_MISSING=false
    while IFS= read -r fpath; do
        [[ -z "$fpath" ]] && continue
        if ! path_exists_for_cmd_source "$_ASSUMP_PROJECT_WD" "$fpath"; then
            if [[ "$_ASSUMP_HAS_MISSING" == false ]]; then
                record_block_reason "assumptions sourceのファイルパスが存在しません:"
                _ASSUMP_HAS_MISSING=true
            fi
            if [[ "$fpath" = /* ]]; then
                echo "  ✗ $fpath" >&2
            else
                echo "  ✗ $fpath (in $_ASSUMP_PROJECT_WD)" >&2
            fi
        fi
    done <<< "$_ASSUMP_VERIFIED_PATHS"
    if [[ "$_ASSUMP_HAS_MISSING" == true ]]; then
        echo "  現物確認してからcmd_save.shを再実行せよ" >&2
        abort_if_block_immediate || exit 1
    fi
}

check_assumption_claim_dates_warn() {
    _ASSUMP_CLAIMS_MISSING_DATES="$(collect_assumption_claims_missing_dates "$CMD_BLOCK_NC")"
    if [[ -z "${_ASSUMP_CLAIMS_MISSING_DATES//[[:space:]]/}" ]]; then
        return 0
    fi
    echo "WARNING: assumptions claimに日付がありません。claimへ YYYY-MM-DD を含めて時系列を固定してください" >&2
    while IFS= read -r _assump_claim; do
        [[ -z "$_assump_claim" ]] && continue
        echo "  - $_assump_claim" >&2
    done <<< "$_ASSUMP_CLAIMS_MISSING_DATES"
    record_warn_reason "assumptions claimに日付なし" "check=assumptions_claim_date"
}

check_negative_claim_grep_evidence_warn() {
    _ASSUMP_NEGATIVE_CLAIMS_MISSING_GREP="$(collect_negative_claims_missing_grep_evidence "$CMD_BLOCK_NC")"
    if [[ -z "${_ASSUMP_NEGATIVE_CLAIMS_MISSING_GREP//[[:space:]]/}" ]]; then
        return 0
    fi
    echo "BLOCK: 否定的前提キーワードを検出しました。assumptions claimに全探索範囲と各範囲のgrep/rg反証結果を記載してください" >&2
    echo "  対象キーワード: 未実装 / 存在しない / 仕組みがない / 未対応" >&2
    echo "  例: claim: \"2026-05-10時点で探索範囲=scripts/,tests/。rg 'pattern' scripts/ → 0件、rg 'pattern' tests/ → 0件\"" >&2
    while IFS= read -r _assump_claim; do
        [[ -z "$_assump_claim" ]] && continue
        echo "  - $_assump_claim" >&2
    done <<< "$_ASSUMP_NEGATIVE_CLAIMS_MISSING_GREP"
    record_block_reason "否定的前提claimに全探索範囲のgrep反証結果なし"
    abort_if_block_immediate || return 1
}

check_bulletin_count_grep_evidence_warn() {
    _ASSUMP_BULLETIN_COUNT_CLAIMS_MISSING_GREP="$(collect_bulletin_count_claims_missing_grep_evidence "$CMD_BLOCK_NC")"
    if [[ -z "${_ASSUMP_BULLETIN_COUNT_CLAIMS_MISSING_GREP//[[:space:]]/}" ]]; then
        return 0
    fi
    echo "WARNING: bulletin由来の件数claimを検出しました。assumptions claimにgrep/rg検証結果を記載してください" >&2
    echo "  例: claim: \"2026-05-15時点で grep -n 'blt_...' queue/bulletin_board.yaml → 1件\"" >&2
    while IFS= read -r _assump_claim; do
        [[ -z "$_assump_claim" ]] && continue
        echo "  - $_assump_claim" >&2
    done <<< "$_ASSUMP_BULLETIN_COUNT_CLAIMS_MISSING_GREP"
    record_warn_reason "bulletin由来件数claimにgrep検証結果なし" "check=assumptions_bulletin_count_grep_evidence"
}

check_q4_depth_warn() {
    if ! cmd_block_has_field "quality_gate.q4_depth"; then
        echo "WARNING: q4_depth未記入。深堀り度を記入せよ: q4_depth: \"shallow/medium/deep — 理由\"" >&2
        record_warn_reason "q4_depth未記入" "check=quality_gate_q4_depth"
        return 0
    fi

    _Q4_VAL="$(cmd_block_get_field "quality_gate.q4_depth")"
    if grep -qiE '\b(deep|medium)\b' <<< "$_Q4_VAL"; then
        if grep -qiE '\bdeep\b' <<< "$_Q4_VAL"; then
            echo "WARNING: q4_depth=deep/medium — 時間コスト概算: 30-60分(全忍者投入)。時間は最も高価な資源。分割・並列化を検討せよ" >&2
        else
            echo "WARNING: q4_depth=deep/medium — 時間コスト概算: 15-30分(2-3忍者)。分割で時間短縮を検討せよ" >&2
        fi
    fi
}

check_research_baseline_warn() {
    _LG022_TYPE="$(cmd_block_get_field "type")"
    if grep -qiE 'research|analysis|investigation' <<< "$_LG022_TYPE"; then
        _LG022_TEXT="$(cmd_block_raw)"
        if ! grep -qiE 'baseline|比較対象|before.*after|対照' <<< "$_LG022_TEXT"; then
            echo "WARNING(LG022): type=research系cmdにbaseline/比較対象がありません。改善主張には比較対象が必須" >&2
            record_warn_reason "研究cmdにbaseline無し(LG022)" "check=research_baseline"
        fi
    fi
}

# T25: a fixed historical target is a reporting hint, not a stop condition.
# Once a command starts declaring the measurement contract explicitly, all
# three self-measurement fields become mandatory; an incomplete contract is a
# real input defect and therefore BLOCKs. Legacy commands with fixed figures
# but no contract remain WARN-only so cmd_save can be adopted incrementally.
check_dynamic_measurement_contract() {
    local search_text="${1:-${CMD_BLOCK_NC:-}}"
    [[ -n "$search_text" ]] || return 0

    if ! grep -Eqi '正本[^[:cntrl:]]{0,40}秒|件数厳密一致|±[0-9]+%|[0-9]+秒([[:space:]]*(以内|未満|固定))' <<< "$search_text"; then
        return 0
    fi

    local explicit=0 missing=()
    local field
    for field in measurement_environment before after measurement_command; do
        if grep -qE "^[[:space:]]*${field}:[[:space:]]*" <<< "$search_text"; then
            explicit=1
        fi
    done

    if [ "$explicit" -eq 0 ]; then
        echo "WARNING(T25): 固定基準値だけのACは停止条件にしない。before/after/measurement_commandを同一環境で自己計測し、差異は報告して継続せよ" >&2
        record_warn_reason "固定基準値のみのACはWARN。同一環境before/after自己計測へ変換せよ" "check=dynamic_measurement_fixed_baseline"
        return 0
    fi

    for field in before after measurement_command; do
        if ! grep -qE "^[[:space:]]*${field}:[[:space:]]*[^[:space:]]" <<< "$search_text"; then
            missing+=("$field")
        fi
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        local missing_text
        missing_text=$(printf '%s, ' "${missing[@]}")
        missing_text="${missing_text%, }"
        echo "BLOCK(T25): 自己計測欄が欠落しています: ${missing_text}。before/after/measurement_commandを埋めよ" >&2
        record_block_reason "T25 self-measurement fields missing: ${missing_text}" "check=dynamic_measurement_fields"
    fi
}

check_q6_not_hiding_warn() {
    if ! cmd_block_has_field "quality_gate.q6_not_hiding"; then
        echo "WARNING: q6_not_hiding未記入。「この変更は根源的問題を隠さないか？表面的対処で改革動機を殺さないか？」" >&2
        echo '  例: q6_not_hiding: "no — Vercel化は構造改革であり表面的対処ではない"' >&2
        record_warn_reason "q6_not_hiding未記入" "check=quality_gate_q6_not_hiding"
    fi
}

check_q7_definition_verified_warn() {
    _Q7_PROJECT="$CMD_BLOCK_PROJECT"
    _Q7_TASK_TYPE="$(cmd_block_get_field "task_type")"
    if ! cmd_block_has_field "quality_gate.q7_definition_verified"; then
        if [[ "${_Q7_PROJECT:-}" != "dm-signal" || "${_Q7_TASK_TYPE:-}" != "impl" ]]; then
            echo "WARNING: q7_definition_verified未記入。High/Lowなどcmd固有定義を一次情報へ照合したか記載推奨" >&2
            echo '  例: q7_definition_verified: "yes — High=rolling max。trade-rule/テスト期待値に定義を固定"' >&2
            record_warn_reason "q7_definition_verified未記入" "check=quality_gate_q7_definition_verified"
        fi
    fi
}

check_q10_knowledge_boundary_warn() {
    if ! cmd_block_has_field "quality_gate.q10_knowledge_boundary"; then
        echo "WARNING: q10_knowledge_boundary未記入。cmdの前提は検証済み空間内か？前Phase/前cmdの到達点を使っているか？" >&2
        echo '  形式例: q10_knowledge_boundary: "空間内。根拠: Phase30 β調整確立 + cmd_1896結果確認済み"' >&2
        record_warn_reason "q10_knowledge_boundary未記入" "check=quality_gate_q10_knowledge_boundary"
    fi
}

check_q5_code_reading_only_block() {
    _q5_scope_mode="$(cmd_block_get_field "scope_mode")"
    _q5_scout_exempt="$(cmd_block_get_field "scout_exempt")"
    _q5_project="$CMD_BLOCK_PROJECT"
    _q5_depth="$(cmd_block_get_field "quality_gate.q4_depth")"
    q5_val="$(cmd_block_get_field "quality_gate.q5_verified_source")"
    if [[ -n "$q5_val" ]] && grep -qiE "code_reading|コード読み|読んだだけ" <<< "$q5_val"; then
        if [[ "${_q5_scope_mode:-}" == "SCOUT" || "${_q5_scout_exempt:-}" == "true" ]]; then
            echo "INFO: q5=code_reading。scope_mode=SCOUTまたはscout_exempt=trueのため除外。OK" >&2
        elif [[ "${_q5_project:-}" == "infra" && "${_q5_depth:-}" == "shallow" ]]; then
            echo "INFO: q5=code_reading。project=infra かつ q4_depth=shallow のためINFO扱い。OK" >&2
        elif ! grep -qiE "isolated_test|structure_verified|production_verified|pipeline_test|実行|execute|本番|production|API応答|DB確認|テスト実行" <<< "$q5_val"; then
            record_block_reason "q5=code_readingのみ。コード読みだけでは前提未検証。isolated_test/structure_verified/production_verifiedのいずれかで実確認せよ"
            echo '  例: q5_verified_source: "engine.py L107 code_reading + isolated_test(スクリプト実行確認)"' >&2
            abort_if_block_immediate || exit 1
        else
            echo "INFO: q5にcode_readingを含むが追加検証あり。OK" >&2
        fi
    elif [[ -n "$q5_val" ]] && ! grep -qiE "実行|execute|pipeline|本番|production|API応答|DB確認|テスト実行|structure_verified|isolated_test|production_verified|pipeline_test" <<< "$q5_val"; then
        echo "WARNING: q5に検証方法が不明確。レベル明記推奨: code_reading(コード読み) / isolated_test(単体実行) / pipeline_test(結合実行) / production_verified(本番確認)" >&2
    fi
}

check_q8_scope_expression_warn() {
    [[ -n "${_Q8_WHAT_PART:-}" ]] || return 0
    _Q8_SCOPE_MODE="$(cmd_block_get_field "scope_mode")"
    _Q8_SCOPE_EXEMPT=false
    if [[ "${_Q8_SCOPE_MODE,,}" == "focused" || "${_Q8_SCOPE_MODE,,}" == "exact" ]]; then
        _Q8_SCOPE_EXEMPT=true
    fi
    if grep -qE '偵察のみ|分析のみ|調査のみ|確認のみ|コード変更なし|非破壊|対象外|not[- ]in[- ]scope|スコープ限定|範囲限定' <<< "$_Q8_WHAT_PART"; then
        _Q8_SCOPE_EXEMPT=true
    fi
    if grep -qE '(のみ|だけ|一部|代表).{0,24}(対象|範囲|探索|パラメータ|件数|サンプル)|(対象|範囲|探索|パラメータ|件数|サンプル).{0,24}(のみ|だけ|一部|代表)' <<< "$_Q8_WHAT_PART" && [[ "$_Q8_SCOPE_EXEMPT" != true ]]; then
        echo "WARN: q8_why_whatのWHATに縮小表現を検出。全量やることを確認せよ" >&2
        echo "  → のみ/だけ/一部/代表 は範囲縮小のシグナル(殿厳命 2026-04-04)" >&2
        record_warn_reason "q8_縮小表現" "check=quality_gate_q8_scope_expression"
    fi
}

check_q8_compound_question_warn() {
    if ! grep -qE '複利|compound' <<< "$_Q8_WW_VAL"; then
        echo "WARN: q8に複利の問いがありません。「この実装選択を10回繰り返したら正の複利か負の複利か」を追記せよ" >&2
        echo '  例: q8_why_what: "WHY: 殿指摘「浅い」 WHAT: lessons_shogun.yaml作成=正の複利(毎セッション具体化)"' >&2
        record_warn_reason "q8_複利の問い" "check=quality_gate_q8_compound_question"
    fi
}

check_q8_when_how_warn() {
    if ! grep -qiE '(^|[^A-Za-z])WHEN[[:space:]]*[：:]' <<< "$_Q8_WW_VAL" || ! grep -qiE '(^|[^A-Za-z])HOW[[:space:]]*[：:]' <<< "$_Q8_WW_VAL"; then
        echo "WARN: q8_why_whatにWHEN/HOWが不足しています。WHY/WHAT/WHEN/HOWを最低限そろえよ" >&2
        echo '  例: q8_why_what: "WHY: 殿原則「...」 → WHAT: ... → WHEN: ... → HOW: ...。複利: 正の複利"' >&2
        record_warn_reason "q8_WHEN/HOW不足" "check=quality_gate_q8_when_how"
    fi
}

check_q8_where_who_warn() {
    if ! grep -qiE '(^|[^A-Za-z])WHERE[[:space:]]*[：:]' <<< "$_Q8_WW_VAL" || ! grep -qiE '(^|[^A-Za-z])WHO[[:space:]]*[：:]' <<< "$_Q8_WW_VAL"; then
        echo "WARN: q8_why_whatにWHERE/WHOが不足しています。5W1H(WHY/WHAT/WHEN/WHERE/WHO/HOW)をそろえよ" >&2
        echo '  例: q8_why_what: "WHY: ... WHAT: ... WHEN: ... WHERE: scripts/cmd_save.sh WHO: 将軍 HOW: ..."' >&2
        record_warn_reason "q8_WHERE/WHO不足" "check=quality_gate_q8_where_who"
    fi
}

check_q9_firefighting_root_cause_block() {
    _Q9_SIGNAL_TEXT=$(awk '
        /^[[:space:]]*title:/ {
            sub(/^[[:space:]]*title:[[:space:]]*/, "")
            print
            next
        }
    ' <<< "$CMD_BLOCK_NC")
    _Q1_VAL="$(cmd_block_get_field "quality_gate.q1_firefighting")"
    if grep -qiE "$FIREFIGHTING_PATTERN" <<< "$_Q9_SIGNAL_TEXT" && ! grep -q "品質向上" <<< "$_Q1_VAL"; then
        if ! cmd_block_has_field "quality_gate.q9_firefighting_root_cause"; then
            record_block_reason "消火cmdなのにq9_firefighting_root_cause未記入。真因と再発防止を記載してからcmd_save.shを実行せよ"
            echo '  形式: q9_firefighting_root_cause: "root_cause: 真因1行 | prevention: 二度と起きない仕組み1行"' >&2
            abort_if_block_immediate || exit 1
        fi
        _Q9_VAL="$(cmd_block_get_field "quality_gate.q9_firefighting_root_cause")"
        check_q9_root_cause_label_block
        check_q9_prevention_label_block
        check_q9_root_cause_length_block
        check_q9_prevention_length_block
        if grep -qiE '気をつけ|注意し|徹底|意識し|漏れないよう|覚えておく|次は.*ようにする' <<< "$_Q9_PREVENTION"; then
            echo "WARNING: q9のpreventionが意志依存です。『気をつける/徹底する』ではなく、gate追加・自動化・チェック強制など仕組みに置き換えてください" >&2
        fi
    fi
}

check_q9_root_cause_label_block() {
    if [[ -n "$_Q9_VAL" ]] && ! grep -q "root_cause:" <<< "$_Q9_VAL"; then
        record_block_reason "q9にroot_cause:が含まれていない。真因を具体的に記載せよ"
        echo '  形式: q9_firefighting_root_cause: "root_cause: 真因1行 | prevention: 二度と起きない仕組み1行"' >&2
        abort_if_block_immediate || exit 1
    fi
}

check_q9_prevention_label_block() {
    if [[ -n "$_Q9_VAL" ]] && ! grep -q "prevention:" <<< "$_Q9_VAL"; then
        record_block_reason "q9にprevention:が含まれていない。二度と起きない仕組みを記載せよ"
        echo '  形式: q9_firefighting_root_cause: "root_cause: 真因1行 | prevention: 二度と起きない仕組み1行"' >&2
        abort_if_block_immediate || exit 1
    fi
}

check_q9_root_cause_length_block() {
    _Q9_ROOT=$(echo "$_Q9_VAL" | sed -E 's/.*root_cause:[[:space:]]*([^|]*).*/\1/' | sed 's/[[:space:]]*$//')
    if [[ -n "$_Q9_VAL" && ${#_Q9_ROOT} -lt 10 ]]; then
        record_block_reason "q9のroot_causeが短すぎる。10文字以上で具体的に記載せよ"
        echo '  形式: q9_firefighting_root_cause: "root_cause: 真因1行 | prevention: 二度と起きない仕組み1行"' >&2
        abort_if_block_immediate || exit 1
    fi
}

check_q9_prevention_length_block() {
    _Q9_PREVENTION=$(echo "$_Q9_VAL" | sed -E 's/.*prevention:[[:space:]]*(.*)/\1/' | sed 's/[[:space:]]*$//')
    if [[ -n "$_Q9_VAL" && ${#_Q9_PREVENTION} -lt 10 ]]; then
        record_block_reason "q9のpreventionが短すぎる。10文字以上で具体的に記載せよ"
        echo '  形式: q9_firefighting_root_cause: "root_cause: 真因1行 | prevention: 二度と起きない仕組み1行"' >&2
        abort_if_block_immediate || exit 1
    fi
}

check_cmd_block_presence_warn() {
    if [[ ! -f "$QUEUE_FILE" ]]; then
        echo "BLOCK: $QUEUE_FILE が存在しません。先にEdit toolでcmdブロックを書け" >&2
        record_block_reason "$QUEUE_FILE が存在しません" "check=session_state_queue_file_presence"
    elif ! load_cmd_block; then
        if [[ -d "$ARCHIVE_CMD_DIR" ]] && ls "$ARCHIVE_CMD_DIR"/"${CMD_ID}"_* 1>/dev/null 2>&1; then
            return 0
        fi
        echo "BLOCK: ${CMD_ID} のブロックが $QUEUE_FILE に見つかりません。先にEdit toolでcmdブロックを書け" >&2
        record_block_reason "${CMD_ID} のブロックが $QUEUE_FILE に見つかりません" "check=session_state_cmd_block_presence"
    fi
}

check_fill_this_placeholder_block() {
    if load_cmd_block && grep -q 'FILL_THIS' <<< "$CMD_BLOCK_NC"; then
        record_block_reason "雛形のFILL_THISが残存。全プレースホルダを実内容で埋めよ"
        awk '/FILL_THIS/{print NR ":" $0; if (++hits == 5) exit}' <<< "$CMD_BLOCK_NC" >&2
    fi
}

check_delegated_duplicate_block() {
    [[ "$CMD_SAVE_PREFLIGHT_ONLY" != "1" ]] || return 0
    load_cmd_block || return 0

    _DELEGATED_AT="$(cmd_block_get_field "delegated_at")"
    if [[ -n "$_DELEGATED_AT" ]]; then
        record_block_reason "${CMD_ID} は既に委任済みです。"
        echo "  delegated_at: $_DELEGATED_AT" >&2
        echo "  途中修正の二択: (1)別CMD_IDで発令 (2)忍者を神速停止→回復後に新CMD" >&2
        echo "  同一cmd_idの上書きは忍者のフリーズ・成果物無効化を引き起こします(cmd_1688実証済み)" >&2
        abort_if_block_immediate || exit 1
    fi
}

check_previous_pass_pending_block() {
    [[ -f "$CMD_SAVE_LAST_CMD_FILE" ]] || return 0

    _PREV_CMD_ID=$(cat "$CMD_SAVE_LAST_CMD_FILE" 2>/dev/null || true)
    if [[ -z "$_PREV_CMD_ID" || "$_PREV_CMD_ID" == "$CMD_ID" ]]; then
        return 0
    fi

    _PREV_STATUS=$(awk -v cmd_id="$_PREV_CMD_ID" '
        $0 == "  " cmd_id ":" { found=1; next }
        found && /^  cmd_[^:]+:/ { exit }
        found && /^[[:space:]]+status:[[:space:]]/ {
            gsub(/^[[:space:]]+status:[[:space:]]*/, "")
            gsub(/"/, "")
            print; exit
        }
    ' "$QUEUE_FILE" 2>/dev/null || true)
    if [[ "$_PREV_STATUS" == "pending" ]]; then
        _PREV_DELEGATED_AT="$(awk -v cmd_id="$_PREV_CMD_ID" '
            $0 == "  " cmd_id ":" { found=1; next }
            found && /^  cmd_[^:]+:/ { exit }
            found && /^[[:space:]]+delegated_at:[[:space:]]/ {
                gsub(/^[[:space:]]+delegated_at:[[:space:]]*/, "")
                gsub(/"/, "")
                print; exit
            }
        ' "$QUEUE_FILE" 2>/dev/null || true)"
        [[ -n "$_PREV_DELEGATED_AT" ]] && return 0
        record_block_reason "前回PASS済み ${_PREV_CMD_ID} がまだ pending のまま。家老に委任(delegated昇格)されてから次のcmdを保存せよ"
        abort_if_block_immediate || exit 1
    fi
}

check_archive_duplicate_warn() {
    [[ -d "$ARCHIVE_CMD_DIR" ]] || return 0

    if ls "$ARCHIVE_CMD_DIR"/"${CMD_ID}"_completed_*.yaml 1>/dev/null 2>&1; then
        echo "WARN: ${CMD_ID} は既にアーカイブ済みです（重複の可能性）" >&2
        echo "  INFO: 完了済みcmdの再確認では品質FP率へ計上しません" >&2
    fi
}

check_other_draft_exists_block() {
    OTHER_DRAFTS=$(awk -v current="$CMD_ID" '
        /^  cmd_[^:]+:/ { id = $1; sub(/:$/, "", id); sub(/^  /, "", id); next }
        id && id != current && /^[[:space:]]+status:[[:space:]]*["'\''"]?draft["'\''"]?([[:space:]]*(#.*)?)?$/ { print id }
    ' "$QUEUE_FILE" 2>/dev/null)
    [[ -n "$OTHER_DRAFTS" ]] || return 0

    _independent_drafts=""
    while IFS= read -r _other_id; do
        [[ -z "$_other_id" ]] && continue
        _dep="$(awk -v id="$_other_id" '
            $0 ~ "^  "id":" { found=1; next }
            found && /^  cmd_/ { exit }
            found && /depends_on:/ { sub(/.*depends_on:[[:space:]]*/, ""); gsub(/["'"'"']/, ""); print; exit }
        ' "$QUEUE_FILE" 2>/dev/null)"
        if [[ -z "$_dep" || "$_dep" == "none" ]]; then
            _independent_drafts+="$_other_id"$'\n'
        fi
    done <<< "$OTHER_DRAFTS"
    if [[ -n "${_independent_drafts//[[:space:]]/}" ]]; then
        printf 'BLOCK\tother_draft_exists: %s もdraft状態でdepends_onなし。1本ずつゲートを通せ(LS088)\n' "$(echo "$_independent_drafts" | tr '\n' ',')" >&2
        record_block_reason "other_draft_exists"
    fi
}

check_diagnosis_format_block() {
    [[ -n "${CMD_DIAGNOSIS:-}" ]] || return 0

    _DIAG_HAS_BLOCK_REASON=0
    _DIAG_HAS_TAISAKU=0
    if grep -q "BLOCK理由:" <<< "$CMD_DIAGNOSIS"; then _DIAG_HAS_BLOCK_REASON=1; fi
    if grep -q "対策:" <<< "$CMD_DIAGNOSIS"; then _DIAG_HAS_TAISAKU=1; fi
    if [[ "$_DIAG_HAS_BLOCK_REASON" -eq 0 || "$_DIAG_HAS_TAISAKU" -eq 0 ]]; then
        record_block_reason "diagnosisの形式不正。「BLOCK理由: ... 対策: ...」の2部構成で記載せよ"
        echo '  例: diagnosis: "BLOCK理由: q8にWHYが未記入 対策: q8に殿の指示引用を追加"' >&2
        abort_if_block_immediate || exit 1
    fi
}

check_environment_change_after_prior_block() {
    (( PRIOR_ATTEMPT_COUNT > 0 )) || return 0

    _ENV_STRUCTURED=""
    _ENV_TYPE=""
    _ENV_FILE=""
    _ENV_PATTERN=""
    _ENV_FILE_RESOLVED=""
    _ENV_CHANGE="$(awk '/environment_change:/{found=1; sub(/.*environment_change:[[:space:]]*["\x27]?/,""); sub(/["\x27]?[[:space:]]*$/,""); print; exit} END{if(!found) print ""}' <<< "$CMD_BLOCK_NC")"
    if [[ -z "$_ENV_CHANGE" ]]; then
        record_block_reason "environment_change未記入。BLOCKから何を環境に埋め込んだかを記載せよ(gate/lesson/hook/PI等)"
        echo '  例: environment_change: "gate_X追加(scripts/cmd_save.sh L576)+lesson_Y追加(lessons_karo.yaml)"' >&2
        abort_if_block_immediate || exit 1
    fi
    _ENV_VAGUE_PATTERN="^(修正した|対策済み|対応済み|対策した|直した|変更した|更新した|改善した|実施した|対処した|完了|なし|none|N/A|初回起票|初回|該当なし|なし.*初回|対策:.*初回)$"
    if grep -qE "$_ENV_VAGUE_PATTERN" <<< "$_ENV_CHANGE"; then
        record_block_reason "environment_changeが低品質。環境変化の具体的diffを記載せよ(gate追加/lesson登録/hook変更等)"
        echo '  禁止値: 修正した/対策済み/対策した/直した/変更した/更新した/改善した/実施した/対処した/完了/なし' >&2
        abort_if_block_immediate || exit 1
    fi

    if _ENV_STRUCTURED="$(parse_structured_environment_change "$_ENV_CHANGE" 2>/dev/null)"; then
        IFS=$'\t' read -r _ENV_TYPE _ENV_FILE _ENV_PATTERN <<< "$_ENV_STRUCTURED"
        _ENV_FILE_RESOLVED="$_ENV_FILE"
        if [[ "$_ENV_FILE_RESOLVED" != /* ]]; then
            _ENV_FILE_RESOLVED="$PROJECT_DIR/$_ENV_FILE_RESOLVED"
        fi

        if ! grep -qE -- "$_ENV_PATTERN" "$_ENV_FILE_RESOLVED"; then
            record_block_reason "environment_change未実装。file=${_ENV_FILE} に pattern=${_ENV_PATTERN} が見つからない"
            echo "  structured environment_change: type=${_ENV_TYPE} file=${_ENV_FILE} pattern=${_ENV_PATTERN}" >&2
            echo "  実装してからcmd_save.shを再実行せよ" >&2
            abort_if_block_immediate || exit 1
        fi
    else
        record_block_reason "environment_changeが非構造化。構造化形式で記載せよ: type=gate|lesson|hook; file=対象ファイルパス; pattern=grepで検証可能な文字列"
        echo '  例: environment_change: "type=gate; file=scripts/cmd_save.sh; pattern=WARN_COUNT"' >&2
        echo '  注意: YAML list形式(- type: ...)は非対応。必ず1行テキストで書け' >&2
        echo '  理由: 自由テキストは実装を検証できない。構造化形式なら自動grepで実在を証明する' >&2
        abort_if_block_immediate || exit 1
    fi
}


# --- Check 3.6a: environment_change鎖の原理照合（LS091, D006趣旨解釈事故 2026-07-17） ---
# 目的: environment_changeが将軍スコープファイルに家老スコープ情報を追加しようとするとき
#        LS-A11(鎖の原理: CI検知は家老の責務)との矛盾をWARN。
# 起源: LS091 — 将軍がclear_prep_check.shへCI GREEN確認追加を提案→殿即却下。
#        LS-A11を20分前に通読していたのに照合せず。causal_tracing Phase3再現。
check_environment_change_chain_of_command_warn() {
    [[ -n "$_ENV_FILE" ]] || return 0

    local shogun_scope_pattern='(clear_prep|gate_shogun|stop_check_inbox|shogun_startup|prompt_state_inject|post-shogun)'
    local karo_scope_keywords='(CI[_ ]?(RED|GREEN|status|check|結果)|gh[_ ]run|test[_ ]?(result|fail|pass|結果)|忍者[_ ]?(状態|status))'

    if grep -qiE "$shogun_scope_pattern" <<< "$_ENV_FILE" && \
       grep -qiE "$karo_scope_keywords" <<< "$_ENV_CHANGE"; then
        echo "WARN: LS091 environment_change鎖の原理照合" >&2
        echo "  将軍スコープファイル(${_ENV_FILE})に家老スコープ情報を追加しようとしている" >&2
        echo "  LS-A11: CI検知は家老の責務。将軍にCI情報を見せる仕組み=鎖の迂回誘発" >&2
        echo "  因果確認: この情報は本当に将軍に必要か？家老経由で届くべきではないか？" >&2
        record_warn_reason "environment_change_chain_bypass" "check=check_environment_change_chain_of_command LS091"
    fi
}

check_required_quality_gate_keys_block() {
    MISSING_KEYS=()
    MISSING_HINTS=()

    warn_q5_pair_missing_session_state

    for _QG_KEY in q1_firefighting q2_learning q3_next_quality; do
        if ! cmd_block_has_field "quality_gate.${_QG_KEY}"; then
            MISSING_KEYS+=("$_QG_KEY")
            case "$_QG_KEY" in
                q1_firefighting)  MISSING_HINTS+=('  q1_firefighting: "no/yes — 理由"') ;;
                q2_learning)      MISSING_HINTS+=('  q2_learning: "奪わない/奪う — 学習機会への影響"') ;;
                q3_next_quality)  MISSING_HINTS+=('  q3_next_quality: "上がる/下がる — 品質への影響"') ;;
            esac
        fi
    done

    if ! cmd_block_has_field "quality_gate.q5_verified_source"; then
        MISSING_KEYS+=("q5_verified_source")
        MISSING_HINTS+=('  q5_verified_source: "structure_verified — 確認方法と対象を記載"')
    fi

    if ! cmd_block_has_field "quality_gate.q8_why_what"; then
        MISSING_KEYS+=("q8_why_what")
        MISSING_HINTS+=('  q8_why_what: "WHY: 殿指示「...」 → WHAT: ...=正の複利(...)"')
    fi

    if ! cmd_block_has_field "quality_gate.q11_not_already_done"; then
        MISSING_KEYS+=("q11_not_already_done")
        MISSING_HINTS+=('  q11_not_already_done: "未達成。確認方法と結果を記載"')
    fi

    _PF_PROJECT="$CMD_BLOCK_PROJECT"
    _PF_TASK_TYPE="$(cmd_block_get_field "task_type")"
    if [[ "${_PF_PROJECT:-}" == "dm-signal" && "${_PF_TASK_TYPE:-}" == "impl" ]]; then
        if ! cmd_block_has_field "quality_gate.q7_definition_verified"; then
            MISSING_KEYS+=("q7_definition_verified")
            MISSING_HINTS+=('  q7_definition_verified: "yes — 定義を一次情報で照合した事実"')
        fi
    fi

    if ! cmd_block_has_field "assumptions" && ! cmd_block_has_field "quality_gate.assumptions"; then
        MISSING_KEYS+=("assumptions")
        MISSING_HINTS+=('  assumptions: [{claim: "...", source: "...", trust: "verified"}]')
    fi

    if [[ ${#MISSING_KEYS[@]} -gt 0 ]]; then
        record_block_reason "必須項目 ${#MISSING_KEYS[@]}件 未記入。全て記入してからcmd_save.shを再実行せよ"
        echo "  未記入: ${MISSING_KEYS[*]}" >&2
        echo "  ---" >&2
        for _hint in "${MISSING_HINTS[@]}"; do
            echo "$_hint" >&2
        done
        echo "  ---" >&2
        abort_if_block_immediate || exit 1
    fi
}

check_q11_guard_duplicate_block() {
    _Q11_VAL="$(cmd_block_get_field "quality_gate.q11_not_already_done")"
    _Q11_GUARD_LIST="$(collect_q11_guard_list "$CMD_BLOCK_NC" || true)"
    if [[ -n "${_Q11_GUARD_LIST//[[:space:]]/}" ]]; then
        echo "INFO: assumptions source Guard一覧(# === Guard):" >&2
        printf '%s\n' "$_Q11_GUARD_LIST" >&2
        if ! q11_has_guard_duplicate_check "$_Q11_VAL"; then
            echo "BLOCK: q11_guard_duplicate_verification — Guard一覧が検出されました。q11_not_already_done に既存Guard一覧との重複確認を記載してください" >&2
            echo "  推奨アクション: 表示された Guard 一覧を確認し、重複有無と差分理由を q11_not_already_done に書け" >&2
            record_block_reason "q11にGuard一覧との重複確認なし"
        fi
    fi
}

check_q11_existing_alternative_block() {
    _Q11_VAL="$(cmd_block_get_field "quality_gate.q11_not_already_done")"
    _Q11_SUPPLEMENTAL_CONTEXT="$(
        printf '%s\n' "$(cmd_block_get_field "quality_gate.q5_verified_source")"
        awk '
            /^[[:space:]]*assumptions:[[:space:]]*$/ { in_assumptions=1; next }
            in_assumptions && /^[[:space:]]{4}[A-Za-z_][A-Za-z0-9_]*:/ { in_assumptions=0; next }
            in_assumptions && /^[[:space:]]{6,}/ { print; next }
            /^[[:space:]]*command:[[:space:]]*\|/ { in_command=1; next }
            /^[[:space:]]*command:[[:space:]]*[^|]/ { sub(/^[[:space:]]*command:[[:space:]]*/, ""); print; next }
            in_command && /^[[:space:]]{4}[A-Za-z_][A-Za-z0-9_]*:/ { in_command=0; next }
            in_command && /^[[:space:]]{4,}/ { print; next }
        ' <<< "$CMD_BLOCK_NC"
    )"
    if is_gate_or_hook_addition_cmd "$CMD_BLOCK_NC" && ! q11_has_existing_alternative_verification "${_Q11_VAL}
${_Q11_SUPPLEMENTAL_CONTEXT}"; then
        echo "BLOCK: q11_existing_alternative_verification — gate/hook追加cmdです。q11_not_already_done に既存代替の現物確認を記載してください" >&2
        echo "  推奨アクション: 既存/代替の仕組みを grep/rg 等で確認し、その確認方法と差分理由を q11_not_already_done に書け" >&2
        record_block_reason "q11に既存代替の現物確認なし"
    fi
}

check_lock_contention_warn() {
    if ! (flock -n 200) 200>"$LOCK_FILE" 2>/dev/null; then
        echo "WARN: $LOCK_FILE がロック中です（家老が書き込み中の可能性）" >&2
        record_warn_reason "flock_lock_contention" "check=check_lock_contention"
    fi
}

validate_queue_yaml_syntax() {
    [[ -f "$QUEUE_FILE" ]] || return 0

    # checks_pre_session is paid on every cmd_save invocation, while the queue
    # commonly remains byte-identical across repeated preflight/save attempts.
    # yaml_field_set replaces the queue atomically, so device/inode/size plus
    # nanosecond mtime/ctime is a fail-closed content-generation key: any write
    # forces a real parse, but an unchanged generation can reuse the prior PASS.
    local _syntax_cache_dir _syntax_cache_file _queue_generation _cached_generation=""
    _syntax_cache_dir="${_CMD_SAVE_METADATA_CACHE_DIR}/queue_yaml"
    _syntax_cache_file="${_syntax_cache_dir}/validated_generation"
    _queue_generation="$(stat -c '%d:%i:%s:%y:%z' "$QUEUE_FILE" 2>/dev/null || true)"

    if [[ -n "$_queue_generation" && -f "$_syntax_cache_file" ]]; then
        IFS= read -r _cached_generation < "$_syntax_cache_file" || true
        [[ "$_cached_generation" == "$_queue_generation" ]] && return 0
    fi

    python3 -c "import yaml,sys; yaml.load(open(sys.argv[1]), Loader=getattr(yaml, 'CSafeLoader', yaml.SafeLoader))" "$QUEUE_FILE" 2>/dev/null || return 1

    if [[ -n "$_queue_generation" ]]; then
        mkdir -p "$_syntax_cache_dir" 2>/dev/null || true
        printf '%s\n' "$_queue_generation" > "${_syntax_cache_file}.$$" 2>/dev/null &&
            mv -f "${_syntax_cache_file}.$$" "$_syntax_cache_file" 2>/dev/null || true
    fi
    return 0
}

trap 'handle_cmd_save_exit' EXIT

# --- cmd_id正規化（cmd_プレフィックスを付与） ---
RAW_ID="$1"
if [[ "$RAW_ID" =~ ^cmd_ ]]; then
    CMD_ID="$RAW_ID"
else
    CMD_ID="cmd_${RAW_ID}"
fi

# 教訓件数capを撤去(殿裁定2026-07-23 提案A採用)。startup gateの件数WARN撤去と同一裁定であり、
# 撤去は両方に適用される。将軍が当初startup gate側のみを直しcmd_save側を残したため、
# 殿裁定済みのcapがcmd_4125の保存をBLOCKし、教訓統合を強要する空転が再発した(実測)。
# 理由: 閾値は原理由来ではなく当時の実数からの逆算であり、教訓の件数は品質の代理変数として不正。
# 品質実測はgate_lesson_health.sh(origin充足率/useful率/enforcement phantom検出)が担う。
# LS106参照(閾値の根拠をgit log -Sでたどれ=逆算値なら従うのではなく撤去を提案せよ)。

BLOCK_START_FILE="${CMD_SAVE_BLOCK_DIR:-/tmp}/cmd_save_block_start_${CMD_ID}.ts"
WARN_COUNT=0
CMD_BLOCK=""
CMD_BLOCK_NC=""

if [[ "${CMD_SAVE_PREV_LESSON_FAST:-0}" = "1" ]]; then
    if [[ ! -f "$QUEUE_FILE" ]]; then
        echo "BLOCK: $QUEUE_FILE が存在しません。先にEdit toolでcmdブロックを書け" >&2
        record_block_reason "$QUEUE_FILE が存在しません" "check=session_state_queue_file_presence"
    elif load_cmd_block; then
        CMD_DIAGNOSIS="$(extract_cmd_diagnosis "$CMD_BLOCK_NC")"
        warn_missing_prev_cmd_lesson
    else
        echo "BLOCK: ${CMD_ID} のブロックが $QUEUE_FILE に見つかりません。先にEdit toolでcmdブロックを書け" >&2
        record_block_reason "${CMD_ID} のブロックが $QUEUE_FILE に見つかりません" "check=session_state_cmd_block_presence"
    fi

    if [[ "$BLOCK_COUNT" -eq 0 && "$WARN_COUNT" -eq 0 ]]; then
        if [[ "$CMD_SAVE_PREFLIGHT_ONLY" == "1" ]]; then
            echo "事前検証OK: ${CMD_ID}"
            echo "  書込みなし: 累計記録/履歴/通知/自動補完は更新していません"
            echo "  保存時は: bash scripts/cmd_save.sh ${CMD_ID}"
        else
            echo "保存確認OK: ${CMD_ID}"
            echo "  次: bash scripts/cmd_delegate.sh ${CMD_ID} \"<家老への配備メッセージ>\" で委任せよ（inbox_write直接のcmd_new送信はcmd_new_gateがBLOCKする）"
            echo "$CMD_ID" > "$CMD_SAVE_LAST_CMD_FILE"
            remind_missing_current_cmd_lesson_after_clear
        fi
        cleanup_cmd_save_stderr_log
        trap - EXIT
        exit 0
    fi

    if [[ "$BLOCK_COUNT" -gt 0 && ${#BLOCK_REASONS[@]} -gt 0 ]]; then
        _fast_checks_str=""
        _fast_checks_str="$(build_unique_block_checks_str 2>/dev/null || true)"
        log_cmd_save_block "${BLOCK_REASONS[-1]}" "$_fast_checks_str"
    fi
    echo "保存確認NG: ${CMD_ID} (${BLOCK_COUNT}件のBLOCK, ${WARN_COUNT}件のWARN)" >&2
    emit_block_warn_trigger_summary
    cleanup_cmd_save_stderr_log
    trap - EXIT
    exit 1
fi

# 内部フェーズ計装(cmd_4169)の開始点: ここから主要check群のwall_msを区間計測する。
CMD_SAVE_PHASE_LAST_US="${EPOCHREALTIME/./}"
CMD_SAVE_PHASE_LAST_US="${CMD_SAVE_PHASE_LAST_US:0:16}"
CMD_SAVE_RUN_ID="${CMD_ID}-$$-${CMD_SAVE_PHASE_LAST_US}"

# --- Check 0.9: YAML構文検証 ---
# perf: CSafeLoader(libyaml)がPure Python SafeLoader比で約8倍速い(実測0.28s→0.03s級)。
# 構文検証のみで結果は使わないため、Loaderの違いによる出力差は発生しない。
if ! validate_queue_yaml_syntax; then
    echo "BLOCK: $QUEUE_FILE にYAML構文エラーがあります。ダブルクォート内の特殊文字(|等)をエスケープするか、ブロックスカラー(|)を使用してください" >&2
    BLOCK_REASONS+=("yaml_syntax_error")
fi

# --- Check 0.95: typed creator generation receipt 3/3 consistency ---
# cmd_4205 RC3 production parity: before/current/mutant=82/82/82;
# receipt: logs/test_receipts/run_tests_20260801T044447_2247416.json
# Legacy commands without schema_version remain governed by the frozen 82 checks.
# Typed entries are accepted only when queue payload, embedded receipt and the
# committed ledger record agree byte-for-byte on the cryptographic identity.
if ! python3 - "$QUEUE_FILE" "${CMD_GENERATION_LEDGER_FILE:-$PROJECT_DIR/queue/cmd_generation_receipts.jsonl}" "$CMD_ID" <<'PY'
import hashlib,json,sys,yaml
from pathlib import Path
q,l,cmd=Path(sys.argv[1]),Path(sys.argv[2]),sys.argv[3]
d=yaml.safe_load(q.read_text()) or {}; entry=(d.get('commands') or {}).get(cmd)
if not isinstance(entry,dict) or 'schema_version' not in entry: raise SystemExit(0)
r=entry.get('generation_receipt')
if not isinstance(r,dict): print('BLOCK: generation_receipt missing',file=sys.stderr); raise SystemExit(1)
latest={}
if l.exists():
  for line in l.read_text().splitlines():
    if line.strip():
      x=json.loads(line); latest[x['identity']]=x
lr=latest.get(r.get('identity'))
payload={k:v for k,v in entry.items() if k not in ('status','schema_version','generation_receipt')}
ps=hashlib.sha256(json.dumps(payload,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
raw=json.dumps([r.get('schema_version'),r.get('reserved_cmd_id'),ps,r.get('baseline_sha'),r.get('writer_version')],separators=(',',':'))
ident=hashlib.sha256(raw.encode()).hexdigest()
ok=(r.get('state')=='committed' and lr and lr.get('state')=='committed' and
    r.get('reserved_cmd_id')==cmd and r.get('canonical_payload_sha256')==ps and
    ident==r.get('identity') and all(lr.get(k)==r.get(k) for k in
    ('schema_version','reserved_cmd_id','canonical_payload_sha256','baseline_sha','writer_version','identity')))
if not ok: print('BLOCK: generation_receipt queue/embedded/ledger consistency is not 3/3',file=sys.stderr)
raise SystemExit(0 if ok else 1)
PY
then
    BLOCK_REASONS+=("generation_receipt_inconsistent")
fi
if [[ "${CMD_SAVE_RECEIPT_ONLY:-0}" == "1" ]]; then
    if (( ${#BLOCK_REASONS[@]} > 0 )); then exit 1; fi
    echo "PASS: generation_receipt queue/embedded/ledger consistency 3/3"
    exit 0
fi

# --- Check 1: cmdブロック存在確認 ---
check_cmd_block_presence_warn

# The command block is immutable for one cmd_save invocation. Project was the
# hottest repeated lookup (20 callers); cache it before any project-aware check
# so those callers avoid Bash command-substitution while preserving check order.
if load_cmd_block; then
    load_cmd_block_cache || true
    CMD_BLOCK_PROJECT="${CMD_BLOCK_CACHE[project]-}"
fi

# cmd本文は1 invocation中不変。後段check群はcommand substitution経由で同じ
# acceptance_criteria/command抽出を繰り返すため、親shellで各1回だけprimeする。
# 関数内lazy cacheではsubshell終了時に代入が失われるので、ここで明示的に保持する。
CMD_SAVE_AC_BLOCK_CACHE="$(extract_acceptance_criteria_block)"
CMD_SAVE_AC_BLOCK_CACHE_READY=1
CMD_SAVE_COMMAND_BLOCK_CACHE="$(extract_command_text_block)"
CMD_SAVE_COMMAND_BLOCK_CACHE_READY=1

# --- Check 1.06: AC列契約とランキング要求の集合差(BLOCK, L1606) ---
if ! check_ac_output_metric_contract "$CMD_SAVE_AC_BLOCK_CACHE"; then
    [[ "$CMD_SAVE_ACCUMULATE_BLOCKS" == "1" ]] || exit 1
fi

# --- Check 1.05: 雛形FILL_THIS残存BLOCK ---
# 起源: cmd_skeleton.sh導入(2026-06-10殿指示「劣化LLMでもスムーズ起票」)。
# 雛形の穴埋め漏れを構造的に防ぐ。FILL_THIS残存=未記入フィールド。
check_fill_this_placeholder_block

# --- Check 1.1: 定型フィールド自動補完 ---
# cmd_publish/pre-bash経路に依存せず、cmd_save単体実行でも暗黙の空欄を潰す。
auto_insert_cmd_default_fields

# --- Check 1.5: 委任済みcmd再保存BLOCK ---
# cmd_1688事故: 将軍が委任済みcmdを3回上書き→忍者フリーズ→殿指摘
# delegated_at存在 = 既に家老に委任済み。再保存は設計変更を意味する。
# CLAUDE.mdルール: 途中修正の二択(別CMD or 神速停止→再CMD)。inbox_writeで途中修正するな
check_delegated_duplicate_block

# --- Check 1.6: 前回PASS済みcmd pending昇格チェック ---
# 原理: 将軍が一括起票すると前回cmdが家老に委任されないまま次のcmdを保存できてしまう
# 1cmd毎ゲート強制=呼出し方100億パターンに対応する原理的解決(cmd_2158)
check_previous_pass_pending_block

# --- Check 2: 重複チェック（アーカイブ済みcmd_idとの衝突） ---
check_archive_duplicate_warn

# --- Check 2.5: 同時draft複数BLOCK（LS088: 1CMD1ゲート） ---
# depends_onで直列依存が明示されているdraft群は共存可能（先に書いておくパターン）
check_other_draft_exists_block

cmd_save_phase_mark "checks_pre_session"

# --- Session State: 同一cmdの過去BLOCK履歴を表示 ---
if load_cmd_block; then
    CMD_DIAGNOSIS="$(extract_cmd_diagnosis "$CMD_BLOCK_NC")"
    show_prior_attempts
    warn_missing_prev_cmd_lesson
fi

cmd_save_phase_mark "session_state"
cmd_save_checks_main_mark "start"

# --- Check 3.5: diagnosis質検査（cmd_2159） ---
# 目的: diagnosisが記入されている場合、「BLOCK理由:」「対策:」の2部構成を強制
# 低品質diagnosisを再BLOCKすることで診断内容の質を担保する
check_diagnosis_format_block

# --- Check 3.6: environment_change強制（cmd_2160, 殿指摘2026-04-20拡張） ---
# 目的: BLOCK/WARN後に「環境に何を埋め込んだか」を強制。免疫系の抗体生成フェーズ。
# 軍師原理(blt_20260420_021639): 「BLOCKの度に環境が1つ強くなるまで、次を許すな。」
# 殿指摘: WARNもスルーするな。WARNされたら次のCMDでBLOCKされないように成長せよ。
# 条件: PRIOR_ATTEMPT_COUNT > 0 = 過去にBLOCKされた実績がある
# ★ WARN_COUNT > 0 のケースは全チェック完了後(L2594付近)で処理(WARNは後段で蓄積されるため)
_ENV_FILE=""
check_environment_change_after_prior_block
check_environment_change_chain_of_command_warn

# --- Check 3: quality_gateフィールド検査 ---
# cmdブロック内にquality_gate（q1_firefighting, q2_learning, q3_next_quality）があるか検査
if load_cmd_block; then
    load_cmd_block_cache || true

    if ! cmd_block_has_field "quality_gate"; then
        record_block_reason "quality_gate未記入。3問に答えてからcmd_save.shを実行せよ"
        cat >&2 <<'QG_TEMPLATE'
---
quality_gate:
  q1_firefighting: "no/yes — 理由"
  q2_learning: "奪わない/奪う — 学習機会への影響"
  q3_next_quality: "上がる/下がる — 品質への影響"
---
QG_TEMPLATE
        abort_if_block_immediate || exit 1
    fi

    # --- Field name validation: 不正フィールド名の即時検出 ---
    # 起源: cmd_3244で7回BLOCK。q5_assumptionsのような不正名が素通りし値チェックまで発見が遅延
    # 修正: quality_gate配下の全フィールド名をテンプレートの正規名リストと照合し、不一致を即BLOCK
    VALID_QG_FIELDS="q1_firefighting q2_learning q3_next_quality q4_depth q5 q5_verified_source q6_not_hiding q7_definition_verified q8_why_what q9_firefighting_root_cause q10_knowledge_boundary q11_not_already_done q12_lord_30min_cost q_ambiguity assumptions diagnosis environment_change nazenaze_root_cause"
    INVALID_QG_FIELDS=()
    for _cache_key in "${!CMD_BLOCK_CACHE[@]}"; do
        if [[ "$_cache_key" == quality_gate.* ]]; then
            _qg_subfield="${_cache_key#quality_gate.}"
            _qg_valid=0
            for _valid_name in $VALID_QG_FIELDS; do
                if [[ "$_qg_subfield" == "$_valid_name" ]]; then
                    _qg_valid=1
                    break
                fi
            done
            if [[ "$_qg_valid" -eq 0 ]]; then
                INVALID_QG_FIELDS+=("$_qg_subfield")
            fi
        fi
    done
    if [[ ${#INVALID_QG_FIELDS[@]} -gt 0 ]]; then
        record_block_reason "quality_gate: 不正フィールド名 ${#INVALID_QG_FIELDS[@]}件検出。正しいフィールド名に修正せよ"
        echo "  不正フィールド名: ${INVALID_QG_FIELDS[*]}" >&2
        echo "  正しいフィールド名: $VALID_QG_FIELDS" >&2
        abort_if_block_immediate || exit 1
    fi

    # --- Preflight: 全必須項目の存在を一括チェック（逐次BLOCK防止） ---
    # 起源: cmd_1951で7回連続BLOCK。1項目ずつexit 1するため全項目埋めるのに7往復
    # 修正: 全必須項目を一括チェックし、全ての不足を1回で表示してexit 1
    check_required_quality_gate_keys_block

    # depends_on: cmd間依存の暗黙化を入口で可視化（WARN導入 cmd_2627）
    check_depends_on_field

    # origin: cmdの根拠ルール/殿裁定を因果ネットワーク入口として必須可視化（WARN導入 cmd_2819）
    check_origin_field

    # q4_depth: WARN_COUNTに加算（段階的導入→本格化 2026-04-21殿裁定）
    check_q4_depth_warn

    # LG022 gate: 研究cmdにbaseline無し→WARN
    check_research_baseline_warn
    # T25: fixed values warn; explicit but incomplete self-measurement blocks.
    check_dynamic_measurement_contract "$CMD_BLOCK_NC"

    # q5_verified_source: 存在チェックはpreflight済み。以下は内容検証のみ
    # q5検証レベル分類（cmd_1692: code_readingのみはBLOCK）
    # cmd_1481教訓: code_readingをproduction_verifiedに見せかけた。忍者に信頼度を正直に伝える(利他)
    # cmd_1692: code_readingのみでは前提未検証のためBLOCK。追加検証(isolated_test等)があれば通過
    # 除外条件: scope_mode=SCOUT OR scout_exempt=true（偵察cmdは実行前確認が目的のためcode_readingでも可）
    # infraの道具磨き(cmd_1891): q4_depth=shallow は軽微変更のためINFOに留める
    check_q5_code_reading_only_block
    check_gate_script_execution_evidence "$CMD_BLOCK_NC"

    # q6_not_hiding: SG8自動消火チェック（WARN_COUNTに加算 2026-04-21殿裁定）
    # 目的: 表面的対処で根源的問題を隠し改革動機を殺すcmdを防止
    # 起源: cmd_1278事件 — lessons.yaml読込削除が7,552行の構造問題を隠蔽
    check_q6_not_hiding_warn

    # q7_definition_verified: cmd内定義の一次情報照合明示
    # 起源: L542 — High/Low等の研究用語は実装とテストに同じ意味を固定しないと結論がずれる
    # 目的: cmd固有定義を一次情報に照合した事実をquality_gateに明示させる
    # dm-signal impl cmd → BLOCK昇格（cmd_1903）。infra/他PJ・scout/reconはWARNING維持
    # q7: dm-signal impl BLOCKはpreflight済み。それ以外はWARNING
    check_q7_definition_verified_warn

    # q8_why_what: 存在チェックはpreflight済み。以下は内容検証のみ
    if cmd_block_has_field "quality_gate.q8_why_what"; then
        # WHAT部分の縮小表現検出（WARN — AC2）
        _Q8_WW_VAL="$(cmd_block_get_field "quality_gate.q8_why_what")"
        _Q8_WHAT_PART="${_Q8_WW_VAL#*WHAT:}"
        _Q8_WHAT_PART="${_Q8_WHAT_PART%%WHEN:*}"
        _Q8_WHAT_PART="${_Q8_WHAT_PART%%WHERE:*}"
        _Q8_WHAT_PART="${_Q8_WHAT_PART%%WHO:*}"
        _Q8_WHAT_PART="${_Q8_WHAT_PART%%HOW:*}"
        check_q8_scope_expression_warn
        # COMPOUND(複利の問い)検査（WARN — 2026-04-15 殿指摘「将軍に因果をたどる仕組みを」）
        # 起源: 軍師のcausal_chain+複利の問いが因果思考を強制。将軍にはなかった
        # 方法: q8に「正の複利」or「負の複利」or「複利」が含まれるか検査
        check_q8_compound_question_warn
        # WHY/WHATだけではループが回らない。WHEN(いつ発動)とHOW(どう機能)も明示させる。
        check_q8_when_how_warn
        # 5W1H: WHERE(どこで)とWHO(誰が/誰に)も明示させる（殿指摘2026-05-10）
        check_q8_where_who_warn
        # 親shellでprime済みの不変AC本文を直接渡し、command substitution用subshellを省く。
        check_lord_instruction_ac_alignment_info "$_Q8_WW_VAL" "$CMD_SAVE_AC_BLOCK_CACHE"
        # q8 WHY引用検査はcmd_2248で廃止。
        # 理由: WHYが明示されていても引用記号や特定語彙を持たないだけでWARNになる偽陽性が多かった。
    fi

    # q9_firefighting_root_cause: 消火cmdでは真因+再発防止を必須化（BLOCK — cmd_1801）
    # 起源: 消火禁止原則が理解止まりで、症状修正cmdが真因未記載のまま繰り返された
    # 対象: titleに消火キーワードが含まれるcmd（command本文は対象外 — cmd_1803）
    check_q9_firefighting_root_cause_block

    # (causal_chain各論パッチは削除。q5_verified_sourceに複利の問いを統合 — 2026-04-05)

    # (q8_tool_readiness各論パッチは削除。q5の複利の問いで十分 — cmd_1742 cancel 2026-04-05)

    # q10_knowledge_boundary: 検証済み空間の明示（WARN_COUNTに加算 2026-04-21殿裁定）
    # 起源: cmd_1903 — Phase 31-32の11過ちが全てgateを通過。「無知の知」がcmd起票に強制されていない
    # 目的: cmdの前提が「前Phase/前cmdの到達点(検証済み事実)」に基づいているかを明示させる
    check_q10_knowledge_boundary_warn

    # q_ambiguity: 不明瞭自覚の自己申告（段階的導入 — WARNING）
    # 起源: cmd_2121 — 将軍がcmd設計時の曖昧な点を自己申告させることで定義確認を促す
    # 目的: cmdに曖昧な指示・未定義の前提がある場合、将軍に自覚と記録を促す
    if ! cmd_block_has_field "quality_gate.q_ambiguity"; then
        echo "WARNING: q_ambiguity未記入。このcmdに曖昧な指示・未定義の前提はないか？あれば明記し、なければ\"none\"と記入せよ" >&2
        echo '  形式例: q_ambiguity: "none — 全前提定義済み" or "あり: TOP-N の N が未定義 → 将軍が3と定義"' >&2
    fi

    # q12_lord_30min_cost: 創造主の洗脳防御。先送り/低優先化が殿の誘導コストを増やすか二値で問う。
    check_lord_30min_cost_question

    # cmd全文の先送り表現検出。低優先/後で/次セッション/非致命的をWARNで露出する。
    check_deferral_language_warn "$CMD_BLOCK_NC"

    # LS083: 比較実験cmd(合成/集計/代理実験)は同一生成パイプラインの同格性確認をWARNで促す
    # 起源: cmd_3763 C3事故 — 静的等ウェイト合成比較を本番動的FoFと同格に扱い殿指摘で訂正
    check_comparison_pipeline_parity_warn "$CMD_BLOCK_NC"

    # mizchi Red flag (1): 「自分で読み直せば同じ効果」
    # 自己申告/目視確認/自問で曖昧さや品質を担保しようとしていないかをWARNINGで可視化
    check_self_reread_red_flag

    # mizchi Red flag (4): 「複数の不明瞭点を一気に潰そう」
    # 1cmdに複数の主要対象を束ねた設計をWARNINGで可視化
    check_bundle_red_flag

    # q11_not_already_done: 存在チェックはpreflight済み。以下は自動検索のみ

    # q11自動検索: command内スクリプト名とdocs/researchの既存成果物を照合（INFO）
    # 起源: cmd_1916 — q11手動記入は嘘が書ける。自動露出で車輪の再発明を補助的に防ぐ
    _Q11_PROJECT_DIR="${PROJECT_DIR:-${PROJECT_ROOT:-.}}"
    _Q11_RESEARCH_DIR="${CMD_SAVE_Q11_RESEARCH_DIR:-${_Q11_PROJECT_DIR}/docs/research}"
    if [[ -d "$_Q11_RESEARCH_DIR" ]]; then
        _Q11_COMMAND_SECTION=$(awk '
            /^\s*command:\s*\|/ { found=1; next }
            /^\s*command:\s*[^|]/ { found=1; sub(/^\s*command:\s*/, ""); print; next }
            found && /^\s{4,}/ { print; next }
            found && /^\s*[a-zA-Z_][a-zA-Z0-9_]*:/ { exit }
        ' <<< "${CMD_BLOCK_NC:-$CMD_BLOCK}")
        if [[ -n "${_Q11_COMMAND_SECTION:-}" ]]; then
            if [[ "${CMD_QUALITY_FAST_METADATA:-0}" != "1" ]]; then
                # q11 cold-cache leader must finish publishing before the
                # output filter exits; otherwise the orphaned INFO worker is
                # terminated and every later invocation misses again.
                # Query-level non-blocking single-flight keeps concurrent
                # followers fast while this one bounded leader completes.
                cmd_save_timed_bg q11_semantic_search_overhead show_q11_semantic_search_matches "$CMD_BLOCK_NC"
                # Avoid launching a background shell, reparsing AC/command, and
                # touching the DB cache for the common token-absent branch.
                # The worker remains the normalization/dedup SSOT; this cheap
                # predicate uses already-primed sections, so the absent branch
                # pays no process launch. Exact extraction stays in the worker.
                _MEMORY_DB_TOKEN_TEXT="${CMD_SAVE_AC_BLOCK_CACHE:-}"$'\n'"${CMD_SAVE_COMMAND_BLOCK_CACHE:-}"
                if [[ "$_MEMORY_DB_TOKEN_TEXT" =~ scripts/[A-Za-z0-9_./-]+\.(sh|py) \
                    || "$_MEMORY_DB_TOKEN_TEXT" =~ (^|[^A-Za-z0-9_])run_[A-Za-z0-9_]+ ]]; then
                    cmd_save_timed_bg memory_db_token_search_overhead show_memory_db_command_token_matches &
                fi
            fi

            # WSL2最適化: docs/research/全件grep(50+NTFSファイル)はunitテストで10-20秒かかる。
            # FAST_METADATAモードでは本番docs走査を避けるが、テストで明示された小さいresearch dirは走査する。
            _Q11_ALLOW_RESEARCH_SCAN=0
            if [[ "${CMD_QUALITY_FAST_METADATA:-0}" != "1" || -n "${CMD_SAVE_Q11_RESEARCH_DIR:-}" || "${_Q11_PROJECT_DIR}" != "${PROJECT_ROOT:-$PROJECT_DIR}" ]]; then
                _Q11_ALLOW_RESEARCH_SCAN=1
            fi
            if [[ "$_Q11_ALLOW_RESEARCH_SCAN" == "1" ]]; then
            if [[ -f "$EXTRACT_COMMAND_FILES_SCRIPT" ]]; then
                _Q11_TARGETS="$(bash "$EXTRACT_COMMAND_FILES_SCRIPT" --command-text "$_Q11_COMMAND_SECTION" --repo "$PROJECT_DIR" 2>/dev/null | grep -E '\.(sh|py)$' || true)"
            else
                _Q11_TARGETS=$(
                    printf '%s\n' "$_Q11_COMMAND_SECTION" \
                        | grep -oE 'scripts/[A-Za-z0-9_./-]+\.(sh|py)|[A-Za-z0-9_./-]+\.(sh|py)' \
                        | awk '
                        function basename_of(path, parts, n) {
                            n = split(path, parts, "/")
                            return parts[n]
                        }
                        {
                            item = $0
                            base = basename_of(item)
                            items[++count] = item
                            if (item ~ /\//) {
                                has_path[base] = 1
                            }
                        }
                        END {
                            for (i = 1; i <= count; i++) {
                                item = items[i]
                                base = basename_of(item)
                                if (item !~ /\// && has_path[base]) {
                                    continue
                                }
                                if (!seen[item]++) {
                                    print item
                                }
                            }
                        }
                        ' \
                        || true
                )
            fi
            if [[ -n "${_Q11_TARGETS:-}" ]]; then
                read -r _Q11_CACHE_KEY _ < <(printf '%s\n%s\n' "$_Q11_RESEARCH_DIR" "$_Q11_TARGETS" | cksum)
                _Q11_CACHE_FILE="/tmp/cmd_save_q11_${_Q11_CACHE_KEY}.cache"
                _Q11_CACHE_SIG=""
                _Q11_CACHE_BODY=""
                _Q11_CACHE_HIT=false
                if [[ -f "$_Q11_CACHE_FILE" && "$_Q11_CACHE_FILE" -nt "$_Q11_RESEARCH_DIR" ]]; then
                    _Q11_CACHE_HIT=true
                    _Q11_SKIP_CACHE_SIG=true
                    while IFS= read -r _q11_cache_line; do
                        if [[ "$_Q11_SKIP_CACHE_SIG" == true ]]; then
                            _Q11_CACHE_SIG="$_q11_cache_line"
                            _Q11_SKIP_CACHE_SIG=false
                            continue
                        fi
                        _Q11_CACHE_BODY+="${_q11_cache_line}"$'\n'
                    done < "$_Q11_CACHE_FILE"
                fi

                if [[ "$_Q11_CACHE_HIT" == true ]]; then
                    [[ -n "${_Q11_CACHE_BODY//[[:space:]]/}" ]] && {
                        echo "INFO: 関連する既存成果物を検出:" >&2
                        printf '%s\n' "$_Q11_CACHE_BODY" >&2
                    }
                else
                    _Q11_ANY_MATCH=false
                    _Q11_CACHE_BODY=""
                    _Q11_USE_RG=false
                    command -v rg >/dev/null 2>&1 && _Q11_USE_RG=true
                    while IFS= read -r _q11_target; do
                        [[ -z "$_q11_target" ]] && continue
                        _q11_base="${_q11_target##*/}"
                        _Q11_PATTERN_ARGS=(-e "$_q11_target")
                        if [[ "$_q11_base" != "$_q11_target" ]]; then
                            _Q11_PATTERN_ARGS+=(-e "$_q11_base")
                        fi
                        if [[ "$_Q11_USE_RG" == true ]]; then
                            _Q11_MATCHES=$(rg -l -F "${_Q11_PATTERN_ARGS[@]}" "$_Q11_RESEARCH_DIR" 2>/dev/null || true)
                        else
                            _Q11_MATCHES=$(grep -rl -F "${_Q11_PATTERN_ARGS[@]}" "$_Q11_RESEARCH_DIR" 2>/dev/null || true)
                        fi
                        [[ -z "${_Q11_MATCHES:-}" ]] && continue
                        if [[ "$_Q11_ANY_MATCH" == false ]]; then
                            echo "INFO: 関連する既存成果物を検出:" >&2
                            _Q11_ANY_MATCH=true
                        fi
                        while IFS= read -r _q11_doc; do
                            [[ -z "$_q11_doc" ]] && continue
                            _q11_rel="${_q11_doc#"${_Q11_PROJECT_DIR}"/}"
                            echo "  ${_q11_target} → ${_q11_rel}" >&2
                            _Q11_CACHE_BODY+="  ${_q11_target} → ${_q11_rel}"$'\n'
                        done <<< "$_Q11_MATCHES"
                    done <<< "$_Q11_TARGETS"

                    {
                        printf '%s\n' "v2"
                        printf '%s' "$_Q11_CACHE_BODY"
                    } > "$_Q11_CACHE_FILE"
                fi
            fi
            fi  # end FAST_METADATA guard for Q11 research dir scan
        fi
    fi

    check_q11_guard_duplicate_block
    check_q11_existing_alternative_block
    check_gate_hook_action_conversion "$CMD_BLOCK_NC"
    check_gate_hook_fp_measurement_connection "$CMD_BLOCK_NC"

    # q8_branch_coverage: 条件分岐変更cmdの本番データ分岐確認AC提案（段階的導入 — WARNING）
    # 起源: cmd_1443事例 — 本番未使用コードパスへの無駄修正
    # 目的: type=impl + 条件分岐キーワード検出時に、本番での分岐実行頻度確認ACの追加を提案
    _Q8_TASK_TYPE="$(cmd_block_get_field "task_type")"
    if [[ "${_Q8_TASK_TYPE:-}" == "impl" ]]; then
        _Q8_FIELDS=$(grep -E '^\s*(purpose|title):' <<< "$CMD_BLOCK_NC" || true)
        if grep -qiE '\bif\b|\bcase\b|条件|分岐|フラグ|\bflag\b|\belif\b|\bswitch\b' <<< "$_Q8_FIELDS"; then
            echo "WARNING: q8_branch_coverage — 条件分岐変更を含むimpl cmdです。本番データでの分岐実行頻度確認ACの追加を検討してください" >&2
            echo "  推奨アクション: 本番DBで該当条件がtrue/falseになるレコード数を確認せよ" >&2
            echo "  (cmd_1443教訓: 本番未使用コードパスへの修正は無駄コスト+リスク)" >&2
        fi
    fi

    # --- Check 3.7: チェックリスト制約転写確認（WARNING） ---
    # cmd_1397事故: チェックリストStep7(再計算禁止)がcmdに転写されず忍者が再計算実行
    # cmdにチェックリスト参照がある場合、隣接Step制約の転写を促す
    if grep -qiE 'チェックリスト|checklist-' <<< "$CMD_BLOCK_NC"; then
        echo "WARNING: チェックリスト参照cmdです。隣接Stepの🛑制約(禁止事項)をACまたは制約欄に転写しましたか？" >&2
        echo "  (cmd_1397教訓: Step7再計算禁止がcmd未記載→忍者が再計算実行)" >&2
    fi
fi

cmd_save_checks_main_mark "quality_gate"
# --- Check 4: flock競合検出 ---
# flock -n: ノンブロッキング。取得成功=競合なし、取得失敗=家老が書き込み中
check_lock_contention_warn

show_recent_completed_ninjas() {
    local snapshot_file="$PROJECT_DIR/queue/karo_snapshot.txt"
    [[ -f "$snapshot_file" ]] || return 0

    local completed_ninjas
    completed_ninjas=$(
        awk -F'|' '
            NR == FNR {
                if ($1 == "report" && ($4 == "completed" || $4 == "done")) {
                    report_done[$2] = 1
                    if (!seen[$2]++) {
                        names[++count] = $2
                    }
                }
                next
            }
            $1 == "ninja" && ($4 == "completed" || $4 == "done") {
                if (!report_done[$2] && !seen[$2]++) {
                    names[++count] = $2
                }
            }
            END {
                for (i = 1; i <= count; i++) {
                    printf "%s%s", names[i], (i < count ? ", " : "")
                }
            }
        ' "$snapshot_file" "$snapshot_file" 2>/dev/null || true
    )

    [[ -n "$completed_ninjas" ]] || return 0
    echo "  直近完了忍者一覧: $completed_ninjas" >&2
}

show_uncommitted_changes_warning() {
    local uncommitted="${1:-}"
    [[ -n "$uncommitted" ]] || return 0

    echo "WARN: 未コミット変更を検出（コミット忘れ注意）:" >&2
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        echo "  $line" >&2
    done <<< "$uncommitted"

    show_recent_completed_ninjas
}

# --- Check 5: uncommitted changes検出 ---
# WSL2 NTFS最適化: git status --porcelain=v2 --no-optional-locks はgit自身のmtime cacheを活用し
# diff-files(全tracked filesをstat()比較)より高速。cmd_2077で最適化
UNCOMMITTED=$(git -C "$PROJECT_DIR" status --porcelain=v2 --no-optional-locks \
    -- scripts/ CLAUDE.md instructions/ config/ 2>/dev/null \
    | awk '!/^[?!#]/{sub(/.*[[:space:]]/,""); print}' || true)
show_uncommitted_changes_warning "$UNCOMMITTED"

# --- Check 6: パイプラインGP重複チェック（非BLOCK — WARN_COUNTに加算しない） ---
# 新cmdのcommandフィールドからGP-XXXパターンを抽出し、
# 直近20件のdelegated/in_progress cmdと照合。一致時WARN（非BLOCK）
if [[ -f "$QUEUE_FILE" ]] && grep -q "  ${CMD_ID}:" "$QUEUE_FILE"; then
    NEW_CMD_LINE=$(awk "/^  ${CMD_ID}:/{found=1; next} found && /^  cmd_/{exit} found && /command:/{print; exit}" "$QUEUE_FILE")
    NEW_GP=$(grep -oE 'GP-[0-9]+' <<< "$NEW_CMD_LINE" | sort -u || true)

    if [[ -n "$NEW_GP" ]]; then
        RECENT_CMDS=$(grep -oE "^  cmd_[^:]+:" "$QUEUE_FILE" | sed 's/: *$//; s/^ *//' | tail -20 | grep -v "^${CMD_ID}$" || true)

        if [[ -n "$RECENT_CMDS" ]]; then
            while IFS= read -r OTHER_CMD; do
                [[ -z "$OTHER_CMD" ]] && continue
                OTHER_BLOCK=$(awk "/^  ${OTHER_CMD}:/{found=1; next} found && /^  cmd_/{exit} found{print}" "$QUEUE_FILE")
                OTHER_STATUS=$(awk '/status:/{gsub(/.*status: */, ""); gsub(/"/, ""); print; exit}' <<< "$OTHER_BLOCK")

                if [[ "$OTHER_STATUS" == "delegated" || "$OTHER_STATUS" == "in_progress" ]]; then
                    OTHER_CMD_LINE=$(grep -m1 "command:" <<< "$OTHER_BLOCK" || true)
                    while IFS= read -r gp; do
                        [[ -z "$gp" ]] && continue
                        if grep -qF "$gp" <<< "$OTHER_CMD_LINE"; then
                            echo "WARN: ${CMD_ID} のGP番号 ${gp} が ${OTHER_CMD}(status:${OTHER_STATUS}) と重複" >&2
                        fi
                    done <<< "$NEW_GP"
                fi
            done <<< "$RECENT_CMDS"
        fi
    fi
fi

# --- Check 7: 軍師既存分析チェック（偵察cmd重複防止） ---
# 起源: cmd_1451事件 — 軍師OPT-6分析完了済みなのに偵察cmd重複起票
# 目的: recon/scout cmdの起票前に軍師の関連分析有無を確認させる
check_gunshi_analysis_overlap() {
    [[ ! -f "$QUEUE_FILE" ]] && return 0
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # task_typeがrecon/scoutの場合のみチェック（impl等は対象外）
    local TASK_TYPE
    TASK_TYPE="$(cmd_block_get_field "task_type")"
    if [[ "$TASK_TYPE" != "recon" && "$TASK_TYPE" != "scout" ]]; then
        return 0
    fi

    # context/gunshi-*.md の存在チェック
    local GUNSHI_FILES
    GUNSHI_FILES=$(find "$PROJECT_DIR/context" -name "gunshi-*.md" -type f 2>/dev/null)
    [[ -z "$GUNSHI_FILES" ]] && return 0

    # 軍師分析ファイルの見出しを表示
    local HIT=false
    while IFS= read -r gfile; do
        [[ -z "$gfile" || ! -f "$gfile" ]] && continue
        local title mtime_hr
        title=$(head -5 "$gfile" | grep -m1 '^#' | sed 's/^# *//')
        mtime_hr=$(date -r "$gfile" '+%m-%d %H:%M' 2>/dev/null || echo "unknown")
        if [[ "$HIT" == false ]]; then
            echo "WARNING: 偵察cmd起票前に軍師の既存分析を確認したか？" >&2
            HIT=true
        fi
        echo "  $(basename "$gfile") [$mtime_hr] — $title" >&2
    done <<< "$GUNSHI_FILES"

    if [[ "$HIT" == true ]]; then
        echo "  → 重複起票防止(cmd_1451教訓): 軍師が先行分析済みの可能性あり" >&2
    fi
}

check_gunshi_analysis_overlap

# --- Check 8: PI番号衝突チェック（Production Invariant重複防止） ---
# 起源: cmd_1453事件 — PI-015を起票したが既存PI-015と衝突。hayateがPI-016に修正
# 目的: cmdにPI-0XXが含まれる場合、既存PIと衝突しないか自動チェック
check_pi_number_collision() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # cmdブロックからPI-0XX番号を抽出
    local PI_NUMS
    PI_NUMS=$(grep -oE 'PI-[0-9]{3}' <<< "$CMD_BLOCK_NC" | sort -u || true)
    [[ -z "$PI_NUMS" ]] && return 0

    # 全projects/*.yamlから既存PI番号を収集
    local EXISTING_PIS
    EXISTING_PIS=$(grep -ohE 'PI-[0-9]{3}' "$PROJECT_DIR"/projects/*.yaml 2>/dev/null | sort -u || true)
    [[ -z "$EXISTING_PIS" ]] && return 0

    # 衝突検出
    local HIT=false
    while IFS= read -r pi; do
        [[ -z "$pi" ]] && continue
        if grep -qx "$pi" <<< "$EXISTING_PIS"; then
            if [[ "$HIT" == false ]]; then
                echo "WARNING: PI番号衝突検出（cmd_1453教訓）" >&2
                HIT=true
            fi
            echo "  $pi は既に projects/*.yaml に登録済み" >&2
        fi
    done <<< "$PI_NUMS"

    if [[ "$HIT" == true ]]; then
        # 次の空き番号を表示
        local MAX_PI
        MAX_PI=$(grep -oE '[0-9]+' <<< "$EXISTING_PIS" | sort -n | tail -1)
        local NEXT_PI
        NEXT_PI=$(printf "PI-%03d" $((10#$MAX_PI + 1)))
        echo "  → 次の空き番号: $NEXT_PI" >&2
    fi
}

check_pi_number_collision

# --- Check 9: 未消化insightsサーフェス（知識循環デッドエンド防止） ---
# 起源: insights 18件死蔵発見(2026-03-28) — 書込み専用で消費者不在
# 目的: cmd起票時にpending insightsを表示し、将軍がinsightsを消費する動線を作る
show_pending_insights() {
    local INSIGHTS_FILE="${CMD_SAVE_INSIGHTS_FILE:-$PROJECT_DIR/queue/insights.yaml}"
    [[ ! -f "$INSIGHTS_FILE" ]] && return 0

    local insight_summary PENDING_COUNT
    insight_summary=$(awk '
        /^- / {
            if (in_item && status == "pending") {
                pending++
                if (shown < 3 && insight != "") {
                    text = insight
                    gsub(/\r/, "", text)
                    gsub(/\n/, " ", text)
                    if (length(text) > 70) {
                        text = substr(text, 1, 70)
                    }
                    shown++
                    lines = lines "  → " text "\n"
                }
            }
            in_item = 1
            status = ""
            insight = ""
            next
        }
        in_item && /^[[:space:]]*status:[[:space:]]*/ {
            status = $0
            sub(/^[[:space:]]*status:[[:space:]]*/, "", status)
            gsub(/["'"'"']/, "", status)
            next
        }
        in_item && /^[[:space:]]*insight:[[:space:]]*/ {
            insight = $0
            sub(/^[[:space:]]*insight:[[:space:]]*/, "", insight)
            gsub(/^["'"'"']|["'"'"']$/, "", insight)
            next
        }
        END {
            if (in_item && status == "pending") {
                pending++
                if (shown < 3 && insight != "") {
                    text = insight
                    gsub(/\r/, "", text)
                    gsub(/\n/, " ", text)
                    if (length(text) > 70) {
                        text = substr(text, 1, 70)
                    }
                    lines = lines "  → " text "\n"
                }
            }
            printf "%d\n%s", pending + 0, lines
        }
    ' "$INSIGHTS_FILE" 2>/dev/null)
    IFS= read -r PENDING_COUNT <<< "$insight_summary"
    PENDING_COUNT=$(( ${PENDING_COUNT:-0} + 0 ))
    [[ "$PENDING_COUNT" -eq 0 ]] && return 0

    echo "INFO: 未消化insights ${PENDING_COUNT}件 — 起票前に確認推奨:" >&2
    printf '%s\n' "$insight_summary" | tail -n +2 >&2
    if [[ "$PENDING_COUNT" -gt 3 ]]; then
        echo "  ... 他 $((PENDING_COUNT - 3))件 (queue/insights.yaml)" >&2
    fi
}

show_pending_insights
cmd_save_checks_main_mark "workspace_state"

# --- Check 9.9: explicit reference existence guard ---
# Only structurally declared references in target_path / assumptions /
# acceptance_criteria are checked. Prose, URLs, globs, placeholders and shell
# fragments are deliberately ignored to keep the detector fail-open on
# ambiguous text.
check_explicit_reference_existence() {
    [[ -z "${CMD_BLOCK_NC:-}" ]] && return 0

    local project_id project_wd violations
    project_id="${CMD_BLOCK_PROJECT:-}"
    [[ -z "$project_id" ]] && project_id=$(awk '/^current_project:/{print $2}' "$PROJECT_DIR/config/projects.yaml" 2>/dev/null || true)
    [[ -z "$project_id" ]] && return 0
    project_wd="${CMD_REFERENCE_PROJECT_WD_OVERRIDE:-}"
    if [[ -z "$project_wd" ]]; then
        project_wd=$(awk -v id="$project_id" '
            /^  - id:/ { current_id = $3; gsub(/"/, "", current_id) }
            /^    path:/ && current_id == id { gsub(/.*path: *"?/, ""); gsub(/"$/, ""); print; exit }
        ' "$PROJECT_DIR/config/projects.yaml" 2>/dev/null || true)
    fi
    [[ -d "$project_wd" ]] || return 0

    violations=$(CMD_REFERENCE_PROJECT_WD="$project_wd" CMD_REFERENCE_BLOCK="$CMD_BLOCK_NC" python3 - <<'PY'
import os
import re
import sqlite3
import sys

import yaml
yaml.SafeLoader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)  # cmd-lord-20260803: libyaml C loader (same safe schema)

root = os.path.realpath(os.environ["CMD_REFERENCE_PROJECT_WD"])
try:
    doc = yaml.safe_load(os.environ["CMD_REFERENCE_BLOCK"]) or {}
except yaml.YAMLError:
    raise SystemExit(0)
if not isinstance(doc, dict):
    raise SystemExit(0)

scope = {key: doc[key] for key in ("target_path", "assumptions", "acceptance_criteria") if key in doc}
path_re = re.compile(
    r"^(?:\./)?[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.+-]+)+"
    r"\.(?:py|tsx?|jsx?|sh|bash|ya?ml|json|sql|html|css|toml|cfg|env|md|txt|csv|db|sqlite)$"
)
ambiguous_re = re.compile(r"(?:https?://|[*?\[\]{}<>$`]|\|\||&&|;\s|\s(?:>|>>|<)\s)")


def strings(value):
    if isinstance(value, str):
        yield value.strip().strip("\"'")
    elif isinstance(value, list):
        for item in value:
            yield from strings(item)
    elif isinstance(value, dict):
        for item in value.values():
            yield from strings(item)


def explicit_path(value):
    if not value or any(ch.isspace() for ch in value) or ambiguous_re.search(value):
        return None
    if os.path.isabs(value):
        return value if re.search(r"\.[A-Za-z0-9]+$", value) else None
    return value if path_re.fullmatch(value) else None


violations = set()
for raw in strings(scope):
    candidate = explicit_path(raw)
    if not candidate:
        continue
    resolved = os.path.realpath(candidate if os.path.isabs(candidate) else os.path.join(root, candidate))
    if not os.path.exists(resolved):
        violations.add(candidate)


def mappings(value):
    if isinstance(value, dict):
        yield value
        for item in value.values():
            yield from mappings(item)
    elif isinstance(value, list):
        for item in value:
            yield from mappings(item)


for mapping in mappings(scope):
    db_value = next((mapping.get(key) for key in ("db_path", "database_path", "sqlite_path")
                     if isinstance(mapping.get(key), str)), None)
    table = mapping.get("table")
    if not db_value or not isinstance(table, str):
        continue
    db_candidate = explicit_path(db_value.strip().strip("\"'"))
    table = table.strip()
    if not db_candidate or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", table):
        continue
    db_path = db_candidate if os.path.isabs(db_candidate) else os.path.join(root, db_candidate)
    if not os.path.isfile(db_path):
        continue
    try:
        with sqlite3.connect(f"file:{os.path.realpath(db_path)}?mode=ro", uri=True) as conn:
            exists = conn.execute(
                "SELECT 1 FROM sqlite_master WHERE type IN ('table','view') AND name=?",
                (table,),
            ).fetchone()
    except sqlite3.Error:
        continue
    if not exists:
        violations.add(table)

for item in sorted(violations):
    print(item)
PY
    ) || true

    [[ -z "${violations//[[:space:]]/}" ]] && return 0
    while IFS= read -r reference; do
        [[ -z "$reference" ]] && continue
        record_block_reason "参照先が非実在: ${reference}。falsifyしてから起票せよ"
    done <<< "$violations"
    abort_if_block_immediate || return 1
}

check_explicit_reference_existence

# --- Check 10: AC内ファイルパス存在チェック（親ディレクトリありはINFO、親も不在はBLOCK） ---
# 起源: cmd_1464事故 + cmd_1896/1899で3回連続パス誤り(2026-04-14なぜなぜ7回)
# 目的: AC内のファイルパス参照が実在するか検証。未作成でも親ディレクトリがあれば作成対象として許容する
# 真因: WARNを無視する習慣が定着し、パス誤りcmdが家老・忍者に到達する
check_ac_file_paths() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # AC内からファイルパス(拡張子付き)を抽出（ACセクションのみ。command/quality_gate内の説明文は対象外）
    # awkでacceptance_criteria:ブロックを抽出。終了条件: ACブロック後の同レベルキー(quality_gate/command等)
    local AC_BLOCK PATHS
    AC_BLOCK=$(awk '
        /^[[:space:]]*acceptance_criteria:/ { in_ac=1; print; next }
        in_ac && /^[[:space:]]*[a-z_]+:/ && !/^[[:space:]]*- / && !/^[[:space:]]*description:/ && !/^[[:space:]]*id:/ { exit }
        in_ac { print }
    ' <<< "$CMD_BLOCK_NC" || true)
    # cmd_reflux_insight_202607081318: 区切り文字"/"の絶対パス誤吸収防止(INS-20260708-130637223-380c)
    # 日本語文中で"A(注記)/B(注記)"のように"/"を列挙区切りに使うと、直前の"/"が
    # 次のパスの先頭に誤結合し「/scripts/foo.sh」のような偽の絶対パスを生成していた
    # (path_exists_for_cmd_sourceがOS root直下を探索し実在ファイルを「不在」と誤判定)。
    # 先頭"/"は空白/行頭直後にのみ許可し、区切り文字直後の吸収を止める
    PATHS=$(grep -oP '(?<![^\s("'\''\[])/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.+-]+)+\.(py|tsx|ts|jsx|js|sh|bash|yaml|yml|json|sql|html|css|toml|cfg|env)|[A-Za-z0-9_.-]+(/[A-Za-z0-9_.+-]+)+\.(py|tsx|ts|jsx|js|sh|bash|yaml|yml|json|sql|html|css|toml|cfg|env)' <<< "$AC_BLOCK" | sort -u || true)
    [[ -z "$PATHS" ]] && return 0

    # プロジェクトWDを取得: cmdブロックのproject → current_project → fallback
    # 単体抽出テストでも動くよう、helper未ロード時はブロック本文から直接拾う。
    local PROJECT_ID PROJECT_WD
    if declare -F cmd_block_get_field >/dev/null 2>&1; then
        PROJECT_ID="$CMD_BLOCK_PROJECT"
    else
        PROJECT_ID=$(awk '
            /^[[:space:]]*project:[[:space:]]*/ {
                sub(/^[[:space:]]*project:[[:space:]]*/, "")
                gsub(/^["'\''"]|["'\''"]$/, "")
                print
                exit
            }
        ' <<< "${CMD_BLOCK_NC:-$CMD_BLOCK}")
    fi
    [[ -z "$PROJECT_ID" ]] && PROJECT_ID=$(awk '/^current_project:/{print $2}' "$PROJECT_DIR/config/projects.yaml" 2>/dev/null)

    if [[ -n "${PROJECT_ID:-}" ]]; then
        PROJECT_WD=$(awk -v id="$PROJECT_ID" '
            /^  - id:/ { current_id = $3; gsub(/"/, "", current_id) }
            /^    path:/ && current_id == id { gsub(/.*path: *"?/, ""); gsub(/"$/, ""); print; exit }
        ' "$PROJECT_DIR/config/projects.yaml" 2>/dev/null)
    fi

    [[ -z "${PROJECT_WD:-}" ]] && return 0

    # 各パスの存在チェック
    local HAS_MISSING=false
    local HAS_CREATABLE=false
    while IFS= read -r fpath; do
        [[ -z "$fpath" ]] && continue
        if ! path_exists_for_cmd_source "$PROJECT_WD" "$fpath"; then
            local display_parent
            display_parent=$(display_parent_for_cmd_source "$PROJECT_WD" "$fpath")

            if parent_exists_for_cmd_source "$PROJECT_WD" "$fpath"; then
                if [[ "$HAS_CREATABLE" == false ]]; then
                    echo "INFO: AC内の未作成ファイルは親ディレクトリが存在するため作成対象として扱います:" >&2
                    HAS_CREATABLE=true
                fi
                echo "  • $fpath (parent: $display_parent)" >&2
            else
                if [[ "$HAS_MISSING" == false ]]; then
                    echo "WARNING: AC内のファイルパスが存在せず、親ディレクトリも不在です（cmd_1464教訓）:" >&2
                    HAS_MISSING=true
                fi
                echo "  ✗ $fpath (missing parent: $display_parent)" >&2
            fi
        fi
    done <<< "$PATHS"

    if [[ "$HAS_MISSING" == true ]]; then
        echo "  BLOCK: 親ディレクトリも不在のパスはcmd品質低下の根因。現物確認してからcmd_save.shを再実行せよ" >&2
        record_warn_reason "ac_missing_parent_path" "check=check_ac_file_paths"
    fi
}

check_ac_file_paths

# --- Check 10.5: cmd text pipe danger warning ---
# Purpose: shell/YAML-special pipe characters in command/purpose can be lost or
# interpreted by downstream task deployment if a batch write path regresses.
check_cmd_text_pipe_danger() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    local CMD_TEXT
    CMD_TEXT=$(awk '
        /^[[:space:]]*purpose:[[:space:]]*/ {
            line = $0
            sub(/^[[:space:]]*purpose:[[:space:]]*/, "", line)
            print line
            next
        }
        /^[[:space:]]*command:[[:space:]]*[|>][+-]?([[:space:]]*#.*)?$/ {
            in_command = 1
            next
        }
        /^[[:space:]]*command:[[:space:]]*/ {
            line = $0
            sub(/^[[:space:]]*command:[[:space:]]*/, "", line)
            print line
            next
        }
        in_command && /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]*/ {
            in_command = 0
            next
        }
        in_command { print }
    ' <<< "$CMD_BLOCK_NC" || true)

    [[ -n "${CMD_TEXT:-}" ]] || return 0
    if [[ "$CMD_TEXT" == *"|"* ]]; then
        echo "WARNING: cmdテキスト内にパイプ文字(|)を検出。deploy_task.sh/yaml_field_set_batch経路で切り詰め・シェル解釈されないよう、必要なら引用または別表現へ修正せよ" >&2
        record_warn_reason "cmd_text_pipe_danger" "check=check_cmd_text_pipe_danger"
    fi
}

check_cmd_text_pipe_danger

# --- Check 11: impl cmd post-deploy verification AC検出（informational — WARN_COUNTに加算しない） ---
# 目的: project=dm-signal + type=impl のcmdのacceptance_criteria内にデプロイ後検証ACがない場合に警告
# 起源: cmd_1491でpush漏れ→cmd_1492で後追い発生
check_impl_push_ac() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # project取得
    local PROJECT_ID
    PROJECT_ID="$CMD_BLOCK_PROJECT"
    [[ "$PROJECT_ID" != "dm-signal" ]] && return 0

    # task_type取得
    local TASK_TYPE
    TASK_TYPE="$(cmd_block_get_field "task_type")"
    [[ "$TASK_TYPE" != "impl" ]] && return 0

    # acceptance_criteria セクションを抽出
    local AC_SECTION
    AC_SECTION=$(awk '
        /^[[:space:]]*acceptance_criteria:/ { found=1; next }
        # binary_check: はAC配下の常設キー。exit条件に含めるとAC1のdescription
        # 1行しか検査されず、AC2以降の記述が検出されないFPを生む
        # (2026-07-10 cmd_3836/3837で4回BLOCK往復実証。4関数同型を一括修正)
        found && /^[[:space:]]*[a-z_]+:/ && !/^[[:space:]]*- / && !/^[[:space:]]*description:/ && !/^[[:space:]]*binary_check:/ && !/^[[:space:]]*id:/ { exit }
        found { print }
    ' <<< "$CMD_BLOCK_NC")

    # acceptance_criteriaがない場合はCMD_BLOCK_NC全体にフォールバック
    if [[ -z "$AC_SECTION" ]]; then
        AC_SECTION="$CMD_BLOCK_NC"
    fi

    # AC内にpush/deploy/verify/本番確認関連キーワードがあるか
    if ! grep -qiE 'push|deploy|デプロイ|verify|本番確認|本番反映|本番動作|Render' <<< "$AC_SECTION"; then
        echo "WARNING: project=dm-signal + type=impl のACにデプロイ後の本番動作確認が含まれていません" >&2
        echo "  デプロイ後の本番動作確認ACを追加せよ。例:" >&2
        echo '  - "ACN: git push後、Render自動デプロイ完了を確認。本番エンドポイントで変更反映を目視確認"' >&2
        echo "  (cmd_1491教訓: push漏れ→cmd_1492で後追い発生)" >&2
    fi
}

check_impl_push_ac

cmd_save_checks_main_mark "reference_guards"
# --- Check 11.0: 三層記憶L0-L7 coverage map要求（WARN） ---
# 目的: 記憶DB関連cmdで、部品だけ作られて導線なしで放置されることを起票時に検出する
check_three_layer_penetration

# --- Check 11.1: dm-signal raw layer notation warning ---
# 目的: dm-signal cmdで文脈なし生L0-L4を使うと、PF階層と計算階層が混線するためcanonical名を促す
check_dm_signal_bare_layer_reference() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    local PROJECT_ID
    if declare -F cmd_block_get_field >/dev/null 2>&1; then
        PROJECT_ID="$CMD_BLOCK_PROJECT"
    else
        PROJECT_ID=$(awk '
            /^[[:space:]]*project:[[:space:]]*/ {
                sub(/^[[:space:]]*project:[[:space:]]*/, "")
                gsub(/^["'\''"]|["'\''"]$/, "")
                print
                exit
            }
        ' <<< "${CMD_BLOCK_NC:-$CMD_BLOCK}")
    fi
    [[ "$PROJECT_ID" != "dm-signal" ]] && return 0

    local raw_hits=""
    local line trimmed
    while IFS= read -r line; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$trimmed" ]] && continue

        # Exclusions: code spans, file paths, canonical names, and mathematical contexts.
        [[ "$trimmed" == *'`'* ]] && continue
        [[ "$trimmed" =~ (/|[[:alnum:]_-]+\.(md|py|sh|yaml|yml|csv|json|txt|db|sqlite)) ]] && continue
        [[ "$trimmed" =~ (pf_L[0-4]|calc_L[0-4]|ctx_L[0-4]|doc_L[0-4]|sg_L[0-4]) ]] && continue
        [[ "$trimmed" =~ (正則化|ノルム|norm|regularization|regression|loss|lambda|λ|距離|行列|ベクトル|vector|matrix) ]] && continue
        # DM-Signal固有名詞と同一行のL表記は正当(例: "L2 GS実績", "L3用universe", "秘奥義GS")
        [[ "$trimmed" =~ (GS|奥義|秘奥義|忍法|四神|universe|smoke|RSS|チャンピオン|構成PF|cmd_[0-9]) ]] && continue
        # ETL層名称(Layer0-5, LayerLock, sync-fof等)はinfra用語でありDM-Signal PF層と無関係
        [[ "$trimmed" =~ (Layer[0-5]|LayerLock|LAYER_DEPENDENCIES|sync-fof|sync-standard|precompute|ETL|cron|endpoint|admin) ]] && continue

        if [[ "$trimmed" =~ (^|[^A-Za-z0-9_])L[0-4]([^A-Za-z0-9_]|$) ]]; then
            raw_hits+="${trimmed}"$'\n'
        fi
    done <<< "${CMD_BLOCK_NC:-$CMD_BLOCK}"

    [[ -z "$raw_hits" ]] && return 0

    echo "WARNING: dm-signal cmdに文脈なし生L0-L4表記を検出。pf_L0/pf_L1/pf_L2 または calc_L1/calc_L2/calc_L3 などcanonical名で曖昧性を潰せ" >&2
    echo "  該当行: $(sed -n '1,3p' <<< "$raw_hits" | tr '\n' ' ')" >&2
    echo "  除外: バッククォート/ファイルパス/canonical名接頭辞/数学キーワード同一行" >&2
    record_warn_reason "dm-signal文脈なし生L0-L4表記" "check=check_dm_signal_bare_layer_reference"
}

check_dm_signal_bare_layer_reference

# --- Check 11.3: AC推奨/必須混在検出（informational — WARN_COUNTに加算しない） ---
# 起源: GP-173。verdict_override 2件(cmd_karo_fix_flock_silent)。ACに推奨事項混入→忍者正FAIL→家老override
# 目的: ACテキストに推奨キーワードが含まれる場合にWARNし、notesへの分離を促す
check_ac_must_should_mix() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    local AC_SECTION
    AC_SECTION=$(awk '
        /^[[:space:]]*acceptance_criteria:/ { found=1; next }
        # binary_check: はAC配下の常設キー。exit条件に含めるとAC1のdescription
        # 1行しか検査されず、AC2以降の記述が検出されないFPを生む
        # (2026-07-10 cmd_3836/3837で4回BLOCK往復実証。4関数同型を一括修正)
        found && /^[[:space:]]*[a-z_]+:/ && !/^[[:space:]]*- / && !/^[[:space:]]*description:/ && !/^[[:space:]]*binary_check:/ && !/^[[:space:]]*id:/ { exit }
        found { print }
    ' <<< "$CMD_BLOCK_NC")
    [[ -z "$AC_SECTION" ]] && return 0

    local RECOMMEND_LINES
    RECOMMEND_LINES=$(grep -inE '推奨|optional|nice.to.have|できれば|望ましい' <<< "$AC_SECTION" || true)
    if [[ -n "$RECOMMEND_LINES" ]]; then
        record_block_reason "ACに推奨事項が混在しています。推奨はnotesに分離し、ACは必須(MUST)のみにせよ"
        echo "  AC定義: 忍者が二値(yes/no)で判定する必須完了基準。推奨/optional/nice-to-haveはnotes欄に" >&2
        echo "  該当行: $(sed -n '1,3p' <<< "$RECOMMEND_LINES" | tr '\n' ' ')" >&2
        echo "  根拠: verdict_override WA 2件(cmd_karo_fix_flock_silent)。推奨にno→FAIL→家老override。WARN→BLOCK昇格(GP-175)" >&2
        abort_if_block_immediate || return 1
    fi
}

check_ac_must_should_mix

# --- Check 11.5: 研究cmdの道具成長AC検出（informational — WARN_COUNTに加算しない） ---
# 起源: 軍師SG10 — 研究cmdで新規関数を増やしてもresearch_engine.py統合ACがないと意志依存で分岐する
# 目的: research系キーワードを含むimpl cmdで、ACにengine統合/追加/移設の明示がない場合にWARNING
check_research_tool_growth_ac() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    local PROJECT_ID TASK_TYPE
    if declare -F cmd_block_get_field >/dev/null 2>&1; then
        PROJECT_ID="$CMD_BLOCK_PROJECT"
        TASK_TYPE="$(cmd_block_get_field "task_type")"
    else
        PROJECT_ID=$(awk '
            /^[[:space:]]*project:[[:space:]]*/ {
                sub(/^[[:space:]]*project:[[:space:]]*/, "")
                gsub(/^["'\''"]|["'\''"]$/, "")
                print
                exit
            }
        ' <<< "${CMD_BLOCK_NC:-$CMD_BLOCK}")
        TASK_TYPE=$(awk '
            /^[[:space:]]*task_type:[[:space:]]*/ {
                sub(/^[[:space:]]*task_type:[[:space:]]*/, "")
                gsub(/^["'\''"]|["'\''"]$/, "")
                print
                exit
            }
        ' <<< "${CMD_BLOCK_NC:-$CMD_BLOCK}")
    fi

    [[ "$PROJECT_ID" != "dm-signal" ]] && return 0
    [[ "$TASK_TYPE" != "impl" ]] && return 0

    local COMMAND_SECTION
    COMMAND_SECTION=$(awk '
        /command:/ { found=1; print; next }
        found && /^    [a-zA-Z_][a-zA-Z0-9_]*:/ { exit }
        found { print }
    ' <<< "$CMD_BLOCK_NC")
    [[ -z "$COMMAND_SECTION" ]] && return 0

    if ! grep -qiE 'research_engine|simulate|analysis|研究' <<< "$COMMAND_SECTION"; then
        return 0
    fi

    local AC_SECTION
    AC_SECTION=$(awk '
        /^[[:space:]]*acceptance_criteria:/ { found=1; next }
        # binary_check: はAC配下の常設キー。exit条件に含めるとAC1のdescription
        # 1行しか検査されず、AC2以降の記述が検出されないFPを生む
        # (2026-07-10 cmd_3836/3837で4回BLOCK往復実証。4関数同型を一括修正)
        found && /^[[:space:]]*[a-z_]+:/ && !/^[[:space:]]*- / && !/^[[:space:]]*description:/ && !/^[[:space:]]*binary_check:/ && !/^[[:space:]]*id:/ { exit }
        found { print }
    ' <<< "$CMD_BLOCK_NC")
    [[ -z "$AC_SECTION" ]] && AC_SECTION="$CMD_BLOCK_NC"

    if grep -qiE 'research_engine(\.py)?|engine[^[:cntrl:]]*(統合|追加|移設)|(統合|追加|移設)[^[:cntrl:]]*(research_engine|engine)' <<< "$AC_SECTION"; then
        return 0
    fi

    echo "WARNING: 研究cmdで新規関数を定義する場合、research_engine.pyへの統合ACを検討せよ" >&2
    echo '  例: "ACN: 新規関数をresearch_engine.pyへ統合し、呼び出し側を移設"' >&2
    echo "  (軍師SG10: engine未統合の研究ロジックは再利用が意志依存になる)" >&2
}

check_research_tool_growth_ac

# --- Check 11.9: 殿発言強制検索（informational — WARN_COUNTに加算しない） ---
# 目的: cmdのtitle/purposeから過去の殿裁定・方針・指摘を自動検索し、
#       起票時に関連発言を見落とさない入口を作る。
show_lord_conversation_matches() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0
    [[ ! -f "$LORD_CONVERSATION_FILE" ]] && {
        echo "INFO: [LORD] 殿発言検索: lord_conversation.jsonl不在のため0件" >&2
        return 0
    }

    local _cache_payload _cache_tmp _conversation_sig
    _conversation_sig="$(stat -c '%n:%Y:%s' "$LORD_CONVERSATION_FILE" 2>/dev/null || printf '%s' "$LORD_CONVERSATION_FILE")"
    _cache_payload="lord:${_conversation_sig}:${CMD_BLOCK_NC}"
    if declare -F cmd_save_metadata_cache_replay >/dev/null && cmd_save_metadata_cache_replay "lord_conversation" "$_cache_payload"; then
        return 0
    fi
    _cache_tmp="$(mktemp)"

    CMD_BLOCK_FOR_LORD="$CMD_BLOCK_NC" \
    CMD_SAVE_LORD_CONVERSATION_MAX_LINES="$CMD_SAVE_LORD_CONVERSATION_MAX_LINES" \
    CMD_SAVE_LORD_CONVERSATION_MAX_BYTES="$CMD_SAVE_LORD_CONVERSATION_MAX_BYTES" \
    python3 - "$LORD_CONVERSATION_FILE" > "$_cache_tmp" <<'PY'
import json
import os
import re
import sys

conversation_path = sys.argv[1]
max_lines = int(os.environ.get("CMD_SAVE_LORD_CONVERSATION_MAX_LINES", "1000") or "1000")
max_bytes = int(os.environ.get("CMD_SAVE_LORD_CONVERSATION_MAX_BYTES", "2097152") or "2097152")

def tokenize(text):
    if not text:
        return set()
    tokens = set()
    for token in re.findall(r'[a-zA-Z][a-zA-Z0-9_.-]*[a-zA-Z0-9]|[a-zA-Z0-9]{2,}', text.lower()):
        tokens.add(token)
    jp_chars = re.sub(r'[\x00-\x7f\s]', '', text)
    for i in range(len(jp_chars) - 1):
        tokens.add(jp_chars[i:i + 2])
    return tokens

def similarity(left, right):
    if not left or not right:
        return 0.0
    union = left | right
    return len(left & right) / len(union) * 100 if union else 0.0

def strip_scalar(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1]
    return value

cmd_text = os.environ.get("CMD_BLOCK_FOR_LORD", "")
fields = {"title": "", "purpose": ""}
current = None
block_indent = 0
for raw_line in cmd_text.splitlines():
    line = raw_line.rstrip("\n")
    if current is not None:
        indent = len(line) - len(line.lstrip(" "))
        if not line.strip():
            fields[current] += "\n"
            continue
        if indent > block_indent:
            fields[current] += line[block_indent:].rstrip() + "\n"
            continue
        current = None

    match = re.match(r'^\s*(title|purpose):\s*(.*)$', line)
    if not match:
        continue
    key, value = match.group(1), match.group(2)
    if value in {"|", ">"} or value == "":
        fields[key] = ""
        current = key
        block_indent = 6
    else:
        fields[key] = strip_scalar(value)

query = " ".join(value.strip() for value in fields.values() if value.strip())
query_words = tokenize(query)
if not query_words:
    print("INFO: [LORD] 殿発言検索: title/purpose空のため0件")
    raise SystemExit(0)

entries = []
total_inbound = 0
try:
    with open(conversation_path, "rb") as fh:
        if max_bytes > 0:
            fh.seek(0, os.SEEK_END)
            file_size = fh.tell()
            fh.seek(max(0, file_size - max_bytes), os.SEEK_SET)
            if file_size > max_bytes:
                fh.readline()
            raw = fh.read()
        else:
            raw = fh.read()
        lines = raw.decode("utf-8", errors="ignore").splitlines()
        if max_lines > 0:
            lines = lines[-max_lines:]
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if entry.get("direction") != "inbound":
                continue
            target = str(entry.get("target", "") or "").strip().lower()
            if target not in {"", "shogun"}:
                continue
            total_inbound += 1
            text = " ".join(
                str(entry.get(key, "") or "")
                for key in ("summary", "detail")
            )
            words = tokenize(text)
            score = similarity(query_words, words)
            if score <= 0:
                continue
            overlap = sorted(query_words & words)
            entries.append((score, entry.get("ts", ""), str(entry.get("summary", "") or "")[:120], overlap[:5]))
except OSError:
    print("INFO: [LORD] 殿発言検索: lord_conversation.jsonl読込失敗のため0件")
    raise SystemExit(0)

entries.sort(key=lambda item: (-item[0], item[1]))
hits = entries[:3]
print(f"INFO: [LORD] 殿発言検索: inbound {total_inbound}件から関連{len(entries)}件")
for score, ts, summary, overlap in hits:
    terms = ",".join(overlap)
    print(f"  - {ts} 類似度{score:.0f}% terms={terms}: {summary}")
PY
    cat "$_cache_tmp" >&2
    declare -F cmd_save_metadata_cache_store >/dev/null && cmd_save_metadata_cache_store "lord_conversation" "$_cache_payload" "$_cache_tmp"
    rm -f "$_cache_tmp"
}

# WSL2最適化: lord_conversation検索を非同期化（全出力>&2、判定に影響しない）
# Unit tests pass CMD_QUALITY_FAST_METADATA=1 and assert gate decisions, not
# best-effort metadata. Avoid spawning slow background scans in that mode.
if [[ "${CMD_SAVE_FORCE_LORD_CONVERSATION:-0}" == "1" ]]; then
    show_lord_conversation_matches
elif [[ "${CMD_QUALITY_FAST_METADATA:-0}" != "1" ]]; then
    show_lord_conversation_matches &
fi

# --- Check 11.10: cmd-chronicle.md強制検索（informational — WARN_COUNTに加算しない） ---
# 目的: cmdのtitle/purposeから完了済みcmd履歴を自動検索し、
#       類似過去cmdの見落としを起票時に減らす。
show_cmd_chronicle_matches() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0
    [[ ! -f "$CMD_CHRONICLE_FILE" ]] && {
        echo "INFO: [CHRONICLE] cmd履歴検索: cmd-chronicle.md不在のため0件" >&2
        return 0
    }

    local _cache_payload _cache_tmp
    _cache_payload="chronicle:${CMD_BLOCK_NC}"
    if declare -F cmd_save_metadata_cache_replay >/dev/null && cmd_save_metadata_cache_replay "cmd_chronicle" "$_cache_payload"; then
        return 0
    fi
    _cache_tmp="$(mktemp)"

    CMD_BLOCK_FOR_CHRONICLE="$CMD_BLOCK_NC" \
    CMD_SAVE_CHRONICLE_MAX_LINES="$CMD_SAVE_CHRONICLE_MAX_LINES" \
    CMD_SAVE_CHRONICLE_MAX_BYTES="$CMD_SAVE_CHRONICLE_MAX_BYTES" \
    python3 - "$CMD_CHRONICLE_FILE" > "$_cache_tmp" <<'PY'
import os
import re
import sys

chronicle_path = sys.argv[1]
max_lines = int(os.environ.get("CMD_SAVE_CHRONICLE_MAX_LINES", "1200") or "1200")
max_bytes = int(os.environ.get("CMD_SAVE_CHRONICLE_MAX_BYTES", "2097152") or "2097152")

def tokenize(text):
    if not text:
        return set()
    tokens = set()
    for token in re.findall(r'[a-zA-Z][a-zA-Z0-9_.-]*[a-zA-Z0-9]|[a-zA-Z0-9]{2,}', text.lower()):
        tokens.add(token)
    jp_chars = re.sub(r'[\x00-\x7f\s]', '', text)
    for i in range(len(jp_chars) - 1):
        tokens.add(jp_chars[i:i + 2])
    return tokens

def similarity(left, right):
    if not left or not right:
        return 0.0
    union = left | right
    return len(left & right) / len(union) * 100 if union else 0.0

def strip_scalar(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1]
    return value

def extract_title_purpose(cmd_text):
    fields = {"title": "", "purpose": ""}
    current = None
    block_indent = 0
    for raw_line in cmd_text.splitlines():
        line = raw_line.rstrip("\n")
        if current is not None:
            indent = len(line) - len(line.lstrip(" "))
            if not line.strip():
                fields[current] += "\n"
                continue
            if indent > block_indent:
                fields[current] += line[block_indent:].rstrip() + "\n"
                continue
            current = None

        match = re.match(r'^\s*(title|purpose):\s*(.*)$', line)
        if not match:
            continue
        key, value = match.group(1), match.group(2)
        if value in {"|", ">"} or value == "":
            fields[key] = ""
            current = key
            block_indent = 6
        else:
            fields[key] = strip_scalar(value)
    return " ".join(value.strip() for value in fields.values() if value.strip())

# chronicle検索精度向上: titleのみをクエリに使用(purpose全文はトークン過多で全件マッチを引き起こす)
_block_text_chr = os.environ.get("CMD_BLOCK_FOR_CHRONICLE", "")
_title_match = re.search(r'^\s*title:\s*(.+)$', _block_text_chr, re.MULTILINE)
query = _title_match.group(1).strip().strip("'\"") if _title_match else extract_title_purpose(_block_text_chr)
query_words = tokenize(query)
if not query_words:
    print("INFO: [CHRONICLE] cmd履歴検索: title空のため0件")
    raise SystemExit(0)

entries = []
total_cmds = 0
try:
    with open(chronicle_path, "rb") as fh:
        if max_bytes > 0:
            fh.seek(0, os.SEEK_END)
            file_size = fh.tell()
            fh.seek(max(0, file_size - max_bytes), os.SEEK_SET)
            if file_size > max_bytes:
                fh.readline()
            raw = fh.read()
        else:
            raw = fh.read()
        lines = raw.decode("utf-8", errors="ignore").splitlines()
        if max_lines > 0:
            lines = lines[-max_lines:]
        for raw_line in lines:
            line = raw_line.strip()
            if not line.startswith("| cmd_"):
                continue
            parts = [part.strip() for part in line.strip("|").split("|")]
            if len(parts) < 2:
                continue
            cmd_id = parts[0]
            title = parts[1]
            rest = " ".join(parts[2:])
            total_cmds += 1
            words = tokenize(f"{title} {rest}")
            overlap_set = query_words & words
            if len(overlap_set) < 2:
                continue
            score = similarity(query_words, words)
            overlap = sorted(overlap_set)
            entries.append((score, cmd_id, title[:100], overlap[:5]))
except OSError:
    print("INFO: [CHRONICLE] cmd履歴検索: cmd-chronicle.md読込失敗のため0件")
    raise SystemExit(0)

entries.sort(key=lambda item: (-item[0], item[1]))
hits = entries[:5]
print(f"INFO: [CHRONICLE] cmd履歴検索: completed {total_cmds}件から関連{len(entries)}件")
for score, cmd_id, title, overlap in hits:
    terms = ",".join(overlap)
    print(f"  - {cmd_id} 類似度{score:.0f}% terms={terms}: {title}")
PY
    cat "$_cache_tmp" >&2
    declare -F cmd_save_metadata_cache_store >/dev/null && cmd_save_metadata_cache_store "cmd_chronicle" "$_cache_payload" "$_cache_tmp"
    rm -f "$_cache_tmp"
}

# WSL2最適化: cmd-chronicle検索を非同期化（全出力>&2、判定に影響しない）
# Unit tests pass CMD_QUALITY_FAST_METADATA=1 and assert gate decisions, not
# best-effort metadata. Avoid spawning slow background scans in that mode.
if [[ "${CMD_QUALITY_FAST_METADATA:-0}" != "1" ]]; then
    show_cmd_chronicle_matches &
fi

# --- Check 11.11: target_path git履歴表示（informational — WARN_COUNTに加算しない） ---
# 目的: target_pathの変更経緯を起票時に自動表示し、現物履歴未確認のままcmdを書く余地を減らす。
# WSL2最適化: 全出力が >&2 のみ（判定に影響しない）のでバックグラウンド化。
if [[ "${CMD_QUALITY_FAST_METADATA:-0}" != "1" ]]; then
    show_target_path_git_history &
fi
check_causal_verification_requirement

# --- Check 11.12: 三層記憶・殿裁定自動INFO表示（informational — WARN_COUNTに加算しない） ---
# 目的: cmdのtitle+purposeで三層記憶(semantic_search.sh)を自動検索し、関連する殿裁定・概念定義をINFO表示する。
# 起源: 殿指摘(2026-06-14) — 教訓を記録しても使わないのは仕組みがないから。全cmd起票前に三層記憶を自動検索せよ。
# 設計: BLOCKなし。INFOのみ。LLMフォールバックは使わない(SEMANTIC_DISABLE_LLM=1)。
show_three_layer_memory_ruling_info() {
    local block_text="${1:-${CMD_BLOCK_NC:-}}"
    [[ -z "$block_text" ]] && return 0

    local semantic_script="${CMD_SAVE_SEMANTIC_SEARCH_SCRIPT:-$PROJECT_DIR/scripts/semantic_search.sh}"
    [[ -f "$semantic_script" ]] || return 0

    # title+purposeのみ抽出してクエリを組み立てる
    local query
    query="$(awk '
        /^[[:space:]]*(title|purpose):[[:space:]]*/ {
            sub(/^[[:space:]]*(title|purpose):[[:space:]]*/, "")
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            if (NF > 0) print
        }
    ' <<< "$block_text" | head -10 | tr '\n' ' ' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' || true)"
    # 表示上だけ異なる空白を同じ検索意図として扱う。検索へ渡す文字列自体も
    # 正規化することで、cache keyと実行結果の対応を一意に保つ。
    query="$(tr '[:space:]' ' ' <<< "$query" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
    [[ -n "${query//[[:space:]]/}" ]] || return 0

    # セッション内キャッシュ確認。pane単位なのでcmd保存間でも共有される。
    # 同一queryの並行cold missはmkdirによる非待機single-flightで1 leaderに絞る。
    local cache_key cache_file claim_dir output rc
    if [[ "${CMD_SAVE_SEMANTIC_CACHE_READY:-0}" != "1" ]]; then
        mkdir -p "$_SEMANTIC_SESSION_CACHE_DIR" 2>/dev/null || true
        CMD_SAVE_SEMANTIC_CACHE_READY=1
    fi
    cache_key="$(printf '%s' "1_1_${query}" | sha256sum 2>/dev/null | cut -d' ' -f1 || printf '%s' "1_1_${query}" | cksum | cut -d' ' -f1)"
    cache_file="${_SEMANTIC_SESSION_CACHE_DIR}/${cache_key}.cache"
    if [[ -f "$cache_file" ]]; then
        echo "INFO: [MEMORY_RULING] 三層記憶検索: セッション内キャッシュヒット(key=${cache_key:0:8}...)。スキップ" >&2
        output="$(cat "$cache_file")"
        [[ -n "${output//[[:space:]]/}" ]] && {
            echo "INFO: [MEMORY_RULING] 三層記憶検索(title+purpose基準) [cached]:" >&2
            head -50 <<< "$output" | sed 's/^/  /' >&2
        }
        return 0
    fi
    claim_dir="${cache_file}.claim"
    if ! mkdir "$claim_dir" 2>/dev/null; then
        # 外側timeoutの上限を越えたclaimは、leader異常終了の残骸として回収する。
        local claim_mtime now_epoch
        claim_mtime="$(stat -c %Y "$claim_dir" 2>/dev/null || printf '0')"
        now_epoch="$(date +%s)"
        if [[ "$claim_mtime" =~ ^[0-9]+$ ]] && (( now_epoch - claim_mtime > 10 )); then
            rmdir "$claim_dir" 2>/dev/null || true
            mkdir "$claim_dir" 2>/dev/null || {
                echo "INFO: [MEMORY_RULING] 三層記憶検索: 同一queryを別jobが検索中(key=${cache_key:0:8}...)。重複起動をスキップ" >&2
                return 0
            }
        else
            echo "INFO: [MEMORY_RULING] 三層記憶検索: 同一queryを別jobが検索中(key=${cache_key:0:8}...)。重複起動をスキップ" >&2
            return 0
        fi
    fi

    # cmd_karo_impl_cmd_save_three_layer_speed_20260725 (AC2): n=5直接計測で
    # memory_db_search段(227,441件のFTS問合せ)が支配相と判明した(直接計測:
    # デフォルトSEMANTIC_MEMORY_DB_TIMEOUT=5で5/5回が5000-6249msの自身のtimeout上限へ到達=
    # 早期成功でなく毎回timeout枯渇)。この関数はgate判定に無関係なINFO専用処理であり
    # (呼出元コメント参照、verdict常にPASS固定)、判定条件は一切変更せず支配相のtimeout
    # 予算のみを縮小する。外側timeoutにも-k(kill-after)を付け、SIGTERM未応答時の
    # 追加滞留を打ち切る(是正前は外側8sの想定上限を大きく超える実測あり=32.2s)。
    if command -v timeout >/dev/null 2>&1; then
        if output="$(
            SEMANTIC_DISABLE_LLM=1 \
            SEMANTIC_DISABLE_CAUSAL=1 \
            SEMANTIC_CAUSAL_ROOT="${SEMANTIC_CAUSAL_ROOT:-$PROJECT_DIR}" \
            SEMANTIC_MEMORY_DB_TIMEOUT="${SEMANTIC_MEMORY_DB_TIMEOUT:-2}" \
                timeout -k 1 4 bash "$semantic_script" "$query" 2>/dev/null
        )"; then
            rc=0
        else
            rc=$?
        fi
    else
        if output="$(
            SEMANTIC_DISABLE_LLM=1 \
            SEMANTIC_DISABLE_CAUSAL=1 \
            SEMANTIC_CAUSAL_ROOT="${SEMANTIC_CAUSAL_ROOT:-$PROJECT_DIR}" \
            SEMANTIC_MEMORY_DB_TIMEOUT="${SEMANTIC_MEMORY_DB_TIMEOUT:-2}" \
                bash "$semantic_script" "$query" 2>/dev/null
        )"; then
            rc=0
        else
            rc=$?
        fi
    fi

    # 成功・タイムアウトのいずれもキャッシュに保存（2回目以降をスキップ可能にする）
    # タイムアウト(rc=124)時は空キャッシュを作成 → 次回実行でキャッシュヒット→即スキップ
    if [[ "$rc" -eq 0 || "$rc" -eq 124 ]]; then
        printf '%s\n' "${output}" > "$cache_file" 2>/dev/null || true
    fi
    rmdir "$claim_dir" 2>/dev/null || true

    [[ "$rc" -eq 0 && -n "${output//[[:space:]]/}" ]] || return 0

    echo "INFO: [MEMORY_RULING] 三層記憶検索(title+purpose基準):" >&2
    head -50 <<< "$output" | sed 's/^/  /' >&2
}

# WSL2最適化: 非同期化（全出力>&2、判定に影響しない）
if [[ "${CMD_QUALITY_FAST_METADATA:-0}" != "1" ]]; then
    cmd_save_timed_bg three_layer_memory_ruling_overhead show_three_layer_memory_ruling_info &
fi

# --- Check 11.13: projects yaml forbidden_topics矛盾検出（WARNING — WARN_COUNTに加算しない） ---
# 目的: projects/{project}.yaml + infra.yaml の forbidden_topics を自動参照し、
#       cmd内容(title+purpose+command)に矛盾する記述があればWARNINGを表示する。
# 設計: BLOCKなし。WARNINGのみ。record_warn_reasonは使わない(gate判定に影響させない)。
check_projects_yaml_forbidden_topics() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    local project_id
    project_id="$CMD_BLOCK_PROJECT"

    # cmd テキスト: title + purpose + command の先頭50行
    local cmd_text
    cmd_text="$(awk '
        /^[[:space:]]*(title|purpose):[[:space:]]*/ { print; next }
        /^[[:space:]]*command:[[:space:]]/ { found=1; print; next }
        found && /^[[:space:]]{4,}/ { print; next }
        found && /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]/ { found=0 }
    ' <<< "$CMD_BLOCK_NC" | head -50 || true)"
    [[ -n "${cmd_text//[[:space:]]/}" ]] || return 0

    # 検索対象yaml: infra.yaml + project固有yaml
    local yaml_files=()
    local _pdir="$PROJECT_DIR/projects"
    [[ -f "$_pdir/infra.yaml" ]] && yaml_files+=("$_pdir/infra.yaml")
    if [[ -n "$project_id" && "$project_id" != "infra" && -f "$_pdir/${project_id}.yaml" ]]; then
        yaml_files+=("$_pdir/${project_id}.yaml")
    fi
    [[ ${#yaml_files[@]} -eq 0 ]] && return 0

    CMD_SAVE_PROJECT_YAMLS="$(printf '%s\n' "${yaml_files[@]}")" \
    CMD_SAVE_CMD_TEXT="$cmd_text" \
    python3 - >&2 <<'PY'
import os
import re

yaml_paths_raw = os.environ.get("CMD_SAVE_PROJECT_YAMLS", "")
yaml_paths = [p.strip() for p in yaml_paths_raw.splitlines() if p.strip()]
cmd_text = os.environ.get("CMD_SAVE_CMD_TEXT", "")

def keyword_match(text, keyword):
    if not text or not keyword:
        return False
    kw = re.escape(keyword.strip())
    return bool(re.search(kw, text, re.IGNORECASE))

for yaml_path in yaml_paths:
    if not os.path.isfile(yaml_path):
        continue
    try:
        content = open(yaml_path, encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    # forbidden_topics セクションのtopic+rule ペアを抽出
    topic_matches = re.findall(
        r'- topic:\s*["\']?([^"\'\n#]+?)["\']?\s*\n\s*rule:\s*["\']?([^"\'\n#]+?)["\']?\s*$',
        content, re.MULTILINE
    )
    for topic, rule in topic_matches:
        topic = topic.strip()
        rule = rule.strip()
        if not topic:
            continue
        if keyword_match(cmd_text, topic):
            print(f"WARNING: [MEMORY_RULING] forbidden_topic検出: '{topic}' がcmd内に含まれています")
            print(f"  殿裁定: {rule}")
            print(f"  source: {yaml_path}")
            print("  → このcmdはforbidden topicに言及しています。再確認してください（BLOCKなし）")
PY
}

check_projects_yaml_forbidden_topics

cmd_save_checks_main_mark "memory_context"
# --- Check 12: 内容重複チェック（informational — WARN_COUNTに加算しない） ---
# 起源: 重複cmd起票の構造的防止
# 目的: 新cmdのtitle+purposeと直近20件(キュー+archive)の類似度を比較しWARN（50%以上）
check_content_duplicate() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0
    [[ ! -f "$QUEUE_FILE" ]] && return 0

    python3 - "$QUEUE_FILE" "$CMD_ID" "${ARCHIVE_CMD_DIR:-}" >&2 <<'PY'
import sys, re, os, json

def tokenize(text):
    """title+purposeをトークン集合に変換。ASCII単語+日本語2gramで混合テキスト対応"""
    if not text:
        return set()
    tokens = set()
    for t in re.findall(r'[a-zA-Z][a-zA-Z0-9_.]*[a-zA-Z0-9]|[a-zA-Z0-9]{2,}', text.lower()):
        tokens.add(t)
    jp_chars = re.sub(r'[\x00-\x7f\s]', '', text)
    for i in range(len(jp_chars) - 1):
        tokens.add(jp_chars[i:i+2])
    return tokens

def similarity(s1, s2):
    """共通単語数/全単語数(Jaccard)"""
    if not s1 or not s2:
        return 0.0
    union = s1 | s2
    return len(s1 & s2) / len(union) * 100 if union else 0.0

def strip_scalar(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1]
    return value

def parse_title_purpose(path):
    commands = {}
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.readlines()
    except Exception:
        return commands

    current_cmd = None
    current_field = None
    block_indent = None

    def ensure_entry(cmd_id):
        return commands.setdefault(cmd_id, {"title": "", "purpose": ""})

    def finalize_block():
        nonlocal current_field, block_indent
        current_field = None
        block_indent = None

    for raw_line in lines:
        line = raw_line.rstrip("\n")

        cmd_match = re.match(r"^  (cmd_\d+):\s*$", line)
        if cmd_match:
            current_cmd = cmd_match.group(1)
            ensure_entry(current_cmd)
            finalize_block()
            continue

        if current_cmd is None:
            continue

        next_cmd_match = re.match(r"^  cmd_\d+:\s*$", line)
        if next_cmd_match:
            current_cmd = None
            finalize_block()
            continue

        if current_field is not None:
            indent = len(line) - len(line.lstrip(" "))
            if not line.strip():
                commands[current_cmd][current_field] += "\n"
                continue
            if indent <= block_indent:
                finalize_block()
            else:
                commands[current_cmd][current_field] += line[block_indent:].rstrip() + "\n"
                continue

        field_match = re.match(r"^    (title|purpose):\s*(.*)$", line)
        if not field_match:
            continue

        field = field_match.group(1)
        value = field_match.group(2)
        if value in {"|", ">"} or value == "":
            commands[current_cmd][field] = ""
            current_field = field
            block_indent = 6
        else:
            commands[current_cmd][field] = strip_scalar(value)
            finalize_block()

    for entry in commands.values():
        for key in ("title", "purpose"):
            entry[key] = entry[key].strip()
    return commands

queue_file, current_cmd_id, archive_dir = sys.argv[1], sys.argv[2], sys.argv[3]
cmds = parse_title_purpose(queue_file)
current = cmds.get(current_cmd_id)
if not isinstance(current, dict):
    sys.exit(0)

new_title = str(current.get("title", "") or "")
new_purpose = str(current.get("purpose", "") or "")
new_words = tokenize(new_title) | tokenize(new_purpose)
if not new_words:
    sys.exit(0)

# Phase 1: キュー内の直近20件と比較
cmd_ids = sorted(cmds.keys())
cmd_ids = [c for c in cmd_ids if c != current_cmd_id][-20:]

hits = []
for cid in cmd_ids:
    entry = cmds[cid]
    if not isinstance(entry, dict):
        continue
    t = str(entry.get("title", "") or "")
    p = str(entry.get("purpose", "") or "")
    other_words = tokenize(t) | tokenize(p)
    sim = similarity(new_words, other_words)
    if sim >= 50:
        hits.append((cid, t[:50], sim))

if hits:
    hits.sort(key=lambda x: -x[2])
    print("WARNING: 内容重複の可能性を検出（類似度50%以上）", file=sys.stderr)
    for cid, title, sim in hits:
        print(f"  {cid}: {title} — 類似度{sim:.0f}%", file=sys.stderr)
    print("  → 重複起票でないか確認してください（BLOCKではありません）", file=sys.stderr)

# Phase 2: archive/cmds/の直近20ファイルと比較
# os.scandir()でstat情報を一括取得（glob+getmtimeのsyscall×n削減）
if os.path.isdir(archive_dir):
    cache_path = "/tmp/cmd_save_content_dup_cache.json"
    try:
        with open(cache_path, encoding="utf-8") as fh:
            cache = json.load(fh)
        if not isinstance(cache, dict):
            cache = {}
    except Exception:
        cache = {}

    cache_dirty = False
    try:
        archive_dir_stat = os.stat(archive_dir)
    except OSError:
        archive_dir_stat = None

    recent_index = cache.get("_archive_recent_files", {})
    if (
        archive_dir_stat is not None
        and isinstance(recent_index, dict)
        and recent_index.get("archive_dir") == os.path.abspath(archive_dir)
        and recent_index.get("dir_mtime_ns") == archive_dir_stat.st_mtime_ns
        and isinstance(recent_index.get("files"), list)
    ):
        archive_files = recent_index["files"]
    else:
        scanned_files = []
        for entry in os.scandir(archive_dir):
            if not entry.name.endswith(".yaml"):
                continue
            st = entry.stat()
            scanned_files.append(
                {
                    "path": entry.path,
                    "mtime_ns": st.st_mtime_ns,
                    "size": st.st_size,
                }
            )
        scanned_files.sort(key=lambda item: item["mtime_ns"], reverse=True)
        archive_files = scanned_files[:20]
        if archive_dir_stat is not None:
            cache["_archive_recent_files"] = {
                "archive_dir": os.path.abspath(archive_dir),
                "dir_mtime_ns": archive_dir_stat.st_mtime_ns,
                "files": archive_files,
            }
            cache_dirty = True

    archive_hits = []
    for archive_file in archive_files:
        af = archive_file.get("path") if isinstance(archive_file, dict) else str(archive_file)
        if not af:
            continue
        try:
            st_mtime_ns = archive_file.get("mtime_ns") if isinstance(archive_file, dict) else None
            st_size = archive_file.get("size") if isinstance(archive_file, dict) else None
            if st_mtime_ns is None or st_size is None:
                st = os.stat(af)
                st_mtime_ns = st.st_mtime_ns
                st_size = st.st_size
        except OSError:
            continue
        cache_key = os.path.abspath(af)
        cache_entry = cache.get(cache_key, {})
        if (
            isinstance(cache_entry, dict)
            and cache_entry.get("mtime_ns") == st_mtime_ns
            and cache_entry.get("size") == st_size
            and isinstance(cache_entry.get("commands"), dict)
        ):
            acmds = cache_entry["commands"]
        else:
            acmds = parse_title_purpose(af)
            cache[cache_key] = {
                "mtime_ns": st_mtime_ns,
                "size": st_size,
                "commands": acmds,
            }
            cache_dirty = True
        for acid, aentry in acmds.items():
            if not isinstance(aentry, dict):
                continue
            t = str(aentry.get("title", "") or "")
            p = str(aentry.get("purpose", "") or "")
            other_words = tokenize(t) | tokenize(p)
            sim = similarity(new_words, other_words)
            if sim >= 50:
                archive_hits.append((acid, t[:50], sim))

    if archive_hits:
        archive_hits.sort(key=lambda x: -x[2])
        print("WARNING: archive内に類似cmdを検出（類似度50%以上）(archive)", file=sys.stderr)
        for cid, title, sim in archive_hits:
            print(f"  (archive) {cid}: {title} — 類似度{sim:.0f}%", file=sys.stderr)
        print("  → 過去の完了cmdとの重複でないか確認してください（BLOCKではありません）", file=sys.stderr)

    if cache_dirty:
        try:
            tmp_path = f"{cache_path}.tmp"
            with open(tmp_path, "w", encoding="utf-8") as fh:
                json.dump(cache, fh, ensure_ascii=False)
            os.replace(tmp_path, cache_path)
        except Exception:
            pass
PY
}

# WSL2最適化: archive scan(cold ~1-2s)を非同期化（全出力>&2、判定に影響しない）
if [[ "${CMD_QUALITY_FAST_METADATA:-0}" != "1" ]]; then
    check_content_duplicate &
fi

# --- Check 13: ACパラメータ充足度チェック（WARN — WARN_COUNTに加算） ---
# 起源: cmd_1681事故 — ACに「前処理4条件」とだけ書き具体値未記載→忍者が独自判断でKalman_auto使用→条件不一致
# 目的: ACに「N条件」「N項目」等の数量指定があり具体値列挙がない場合にWARN
emit_ac_param_candidate_hints() {
    local ac_line="${1:-}"
    [[ -n "$ac_line" ]] || return 0

    CMD_SAVE_AC_LINE="$ac_line" \
    CMD_SAVE_CMD_BLOCK="${CMD_BLOCK_NC:-}" \
    CMD_SAVE_PROJECT_DIR="$PROJECT_DIR" \
    CMD_SAVE_PROJECT_ID="$CMD_BLOCK_PROJECT" \
    python3 - <<'PY' >&2 || true
import os
import re
from pathlib import Path

root = Path(os.environ.get("CMD_SAVE_PROJECT_DIR", ".")).resolve()
cmd_block = os.environ.get("CMD_SAVE_CMD_BLOCK", "")
ac_line = os.environ.get("CMD_SAVE_AC_LINE", "")
project_id = os.environ.get("CMD_SAVE_PROJECT_ID", "").strip()

paths: list[Path] = []

def add_path(raw: str) -> None:
    raw = raw.strip().strip("`'\"")
    if not raw:
        return
    path = Path(raw)
    if not path.is_absolute():
        path = root / path
    try:
        path = path.resolve()
    except OSError:
        return
    if path.is_file() and path not in paths:
        paths.append(path)

for match in re.findall(r'(?:(?:/[^\s`"\']+/)?(?:context|projects)/[^\s`"\':,()]+?\.(?:md|ya?ml))', cmd_block):
    add_path(match)

if project_id:
    add_path(f"projects/{project_id}.yaml")
    add_path(f"context/{project_id}.md")
    if project_id == "infra":
        add_path("context/infrastructure.md")

for extra in os.environ.get("CMD_SAVE_AC_HINT_EXTRA_FILES", "").split(":"):
    add_path(extra)

generic = {
    "AC", "以下", "満たす", "こと", "これ", "それ", "ため", "する", "される",
    "条件", "項目", "手法", "種類", "パラメータ", "要件", "ステップ", "設定", "フィールド",
}
quantity_match = re.search(r'([0-9]+)(条件|項目|手法|種類|パラメータ|要件|ステップ|設定|フィールド|種)', ac_line)
quantity_word = quantity_match.group(2) if quantity_match else ""
tokens = [
    t for t in re.findall(r'[A-Za-z0-9_./-]{3,}|[一-龥ぁ-んァ-ン]{2,}', ac_line)
    if t not in generic and not re.fullmatch(r'AC[0-9]+|[0-9]+', t)
]

hits: list[tuple[int, str, int, str]] = []
for path in paths[:12]:
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        continue
    for idx, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped or len(stripped) > 220:
            continue
        score = 0
        if quantity_word and quantity_word in stripped:
            score += 3
        for token in tokens:
            if token and token in stripped:
                score += 2
        if re.search(r'(^[-*]|\||:|: |：|/|・|,)', stripped):
            score += 1
        if score >= 3:
            rel = str(path)
            try:
                rel = str(path.relative_to(root))
            except ValueError:
                pass
            hits.append((score, rel, idx, stripped))

print("  候補値ヒント（関連context/projectsから自動抽出）:")
if not hits:
    searched = ", ".join(
        str(p.relative_to(root)) if str(p).startswith(str(root)) else str(p)
        for p in paths[:6]
    )
    if not searched:
        searched = "関連ファイル未検出"
    print(f"    - 候補なし: {searched}")
else:
    seen: set[tuple[str, str]] = set()
    count = 0
    for _score, rel, idx, text in sorted(hits, key=lambda item: (-item[0], item[1], item[2])):
        key = (rel, text)
        if key in seen:
            continue
        seen.add(key)
        print(f"    - {rel}:{idx}: {text[:160]}")
        count += 1
        if count >= 5:
            break
PY
}

check_ac_param_sufficiency() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # acceptance_criteria セクションを抽出。キー自体がない旧形式のみCMD全文へフォールバック。
    local AC_SECTION
    AC_SECTION="$(extract_acceptance_criteria_block)"
    if [[ -z "${AC_SECTION//[[:space:]]/}" ]]; then
        grep -qE '^[[:space:]]*acceptance_criteria[[:space:]]*:' <<< "$CMD_BLOCK_NC" && return 0
        AC_SECTION="$CMD_BLOCK_NC"
    fi

    # 数量指定パターン検出: 「N条件」「N項目」「N手法」「N種類」「N種」「Nパラメータ」等
    local QUANT_LINES
    QUANT_LINES=$(grep -E '[0-9]+(条件|項目|手法|種類|パラメータ|要件|ステップ|設定|フィールド|種)' <<< "$AC_SECTION" || true)
    [[ -z "$QUANT_LINES" ]] && return 0

    local HIT=false
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if grep -qE '^[[:space:]]*binary_check:' <<< "$line"; then
            continue
        fi
        if grep -qE '偵察の既定観点|既定観点|デフォルト品質[0-9]+要件|偵察[0-9]+要件' <<< "$line"; then
            continue
        fi
        if grep -qE 'C\([0-9]+,[0-9]+\)|[0-9]+件中[0-9]+件|[0-9]+/[0-9]+|duration|p[0-9]+|median|最大[0-9]+|実測[0-9]+' <<< "$line"; then
            continue
        fi
        if grep -qE '(参照|引用|節番号|章番号|項番).{0,40}(第[0-9]+|[0-9]+章|[0-9]+節|Q[0-9]+|AC[0-9]+|cmd_[0-9]+)|(第[0-9]+|[0-9]+章|[0-9]+節|Q[0-9]+|AC[0-9]+|cmd_[0-9]+).{0,40}(参照|引用|節番号|章番号|項番)' <<< "$line"; then
            continue
        fi
        # 具体値列挙チェック: 括弧内にスラッシュ区切り or カンマ区切り or 中点区切りの項目
        if ! grep -qE '\([^)]*[/,・][^)]*\)' <<< "$line"; then
            if [[ "$HIT" == false ]]; then
                echo "WARN: ACに数量指定があるが具体値が列挙されていません（cmd_1681教訓）" >&2
                HIT=true
            fi
            echo "  → $(echo "$line" | sed 's/^[[:space:]]*//' | cut -c1-80)" >&2
            emit_ac_param_candidate_hints "$line"
        fi
    done <<< "$QUANT_LINES"

    if [[ "$HIT" == true ]]; then
        echo "  具体値を列挙せよ。例: 「4条件」→「4条件(EMA/SMA/Kalman/Bandpass)」" >&2
        echo "  理由: 忍者は独自判断で条件を補完する（cmd_1681実証済み）" >&2
        record_warn_reason "ac_param_sufficiency" "check=check_ac_param_sufficiency"
    fi
}

check_ac_param_sufficiency

cmd_save_checks_main_mark "content_and_ac"
# --- Check 14: 前段results.yamlとのパラメータ空間縮小検出（BLOCK） ---
# 起源: 2026-04-04 将軍4回連続で範囲縮小(top_n=5/lookback=6/PBO=5/MaxDD=1)
# 目的: 後段cmdが前段cmdを参照している場合、前段results.yamlのconfig空間を削っていないか構造的に検査
check_param_space_against_results() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    local CMD_SECTION
    CMD_SECTION=$(awk '
        /^[[:space:]]*command:[[:space:]]*\|/ { found=1; next }
        found && /^      / { sub(/^      /, ""); print; next }
        found { exit }
    ' <<< "$CMD_BLOCK_NC")
    if [[ -z "$CMD_SECTION" ]]; then
        CMD_SECTION=$(awk '
            /^[[:space:]]*command:[[:space:]]*/ {
                sub(/^[[:space:]]*command:[[:space:]]*/, "")
                gsub(/^"/, "")
                gsub(/"$/, "")
                print
                exit
            }
        ' <<< "$CMD_BLOCK_NC")
    fi
    [[ -z "$CMD_SECTION" ]] && return 0

    local PROJECT_ID PROJECT_ROOT_FOR_CMD PROJECT_FILE
    PROJECT_ID=$(awk '
        /^[[:space:]]*project:/ {
            sub(/^[[:space:]]*project:[[:space:]]*/, "")
            gsub(/["'\''[:space:]]/, "")
            print
            exit
        }
    ' <<< "$CMD_BLOCK_NC")
    if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "infra" ]]; then
        # infra projectはGS結果YAMLなし → python3不要 (cmd_2077最適化)
        return 0
    else
        PROJECT_FILE="$PROJECT_DIR/projects/${PROJECT_ID}.yaml"
        [[ ! -f "$PROJECT_FILE" ]] && return 0
        PROJECT_ROOT_FOR_CMD=$(awk '
            /^project:/ { in_project=1; next }
            in_project && /^[^[:space:]]/ { exit }
            in_project && /^  path:/ {
                sub(/^  path:[[:space:]]*/, "")
                gsub(/["'\''[:space:]]/, "")
                print
                exit
            }
        ' "$PROJECT_FILE")
        [[ -z "$PROJECT_ROOT_FOR_CMD" ]] && return 0
    fi
    # results YAML候補が存在しなければpython3不要 (cmd_2077最適化)
    # -print -quit: 存在判定だけなので最初の1件で走査打ち切り(NTFS上のfind全列挙0.6s→ms級)
    if [[ -z "$(find "$PROJECT_ROOT_FOR_CMD/outputs/analysis" -maxdepth 3 -name "*.yaml" -print -quit 2>/dev/null)" ]]; then
        return 0
    fi

    CMD_SECTION="$CMD_SECTION" \
    CURRENT_CMD_ID="$CMD_ID" \
    PROJECT_ROOT_FOR_CMD="$PROJECT_ROOT_FOR_CMD" \
    python3 - <<'PY'
import glob
import os
import re
import sys

cmd_section = os.environ.get("CMD_SECTION", "")
current_cmd_id = os.environ.get("CURRENT_CMD_ID", "")
project_root = os.environ.get("PROJECT_ROOT_FOR_CMD", "")

if not cmd_section or not project_root:
    sys.exit(0)


def unique(values):
    seen = set()
    out = []
    for value in values:
        marker = repr(value)
        if marker in seen:
            continue
        seen.add(marker)
        out.append(value)
    return out


def normalize_scalar(raw):
    raw = raw.strip()
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in {"'", '"'}:
        raw = raw[1:-1]
    if re.fullmatch(r"-?\d+", raw):
        return int(raw)
    return raw


def parse_config_lists(path):
    config = {}
    in_config = False
    current_key = None
    with open(path, encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.rstrip("\n")
            if not in_config:
                if line.strip() == "config:":
                    in_config = True
                continue

            if re.match(r"^\S", line):
                break

            match = re.match(r"^  ([A-Za-z0-9_]+):\s*$", line)
            if match:
                current_key = match.group(1)
                config.setdefault(current_key, [])
                continue

            match = re.match(r"^  ([A-Za-z0-9_]+):\s+.+$", line)
            if match:
                current_key = None
                continue

            match = re.match(r"^  -\s*(.+)$", line)
            if match and current_key:
                config.setdefault(current_key, []).append(normalize_scalar(match.group(1)))
                continue

            if line.strip():
                current_key = None

    return {key: unique(values) for key, values in config.items() if values}


def parse_value_expr(expr):
    expr = expr.strip()
    if expr.startswith("["):
        end = expr.find("]")
        if end == -1:
            return None
        content = expr[1:end]
        parts = [part.strip() for part in content.split(",") if part.strip()]
        return [normalize_scalar(part) for part in parts]

    range_match = re.match(r"^(\d+)\s*-\s*(\d+)\b", expr)
    if range_match:
        start = int(range_match.group(1))
        end = int(range_match.group(2))
        step = 1 if end >= start else -1
        return list(range(start, end + step, step))

    csv_match = re.match(r"^(\d+(?:\s*,\s*\d+)+)\b", expr)
    if csv_match:
        return [int(part.strip()) for part in csv_match.group(1).split(",")]

    return None


ALIASES = {
    "lookbacks": ["lookbacks", "lookback"],
    "top_ns": ["top_ns", "top_n"],
    "rolling_windows": ["rolling_windows", "rolling_window"],
}


def extract_cmd_values(text, config_key):
    aliases = ALIASES.get(config_key, [config_key])
    found = []
    for alias in aliases:
        patterns = [
            rf"\b{re.escape(alias)}\b\s*[:=]\s*(\[[^\]]+\])",
            rf"\b{re.escape(alias)}\b\s*[:=]\s*([0-9]+\s*-\s*[0-9]+)",
            rf"\b{re.escape(alias)}\b\s*[:=]\s*([0-9]+(?:\s*,\s*[0-9]+)+)",
        ]
        for pattern in patterns:
            for match in re.finditer(pattern, text, flags=re.IGNORECASE):
                values = parse_value_expr(match.group(1))
                if values:
                    found.extend(values)
    return unique(found)


blocked = []
ref_cmds = unique(re.findall(r"(?<![A-Za-z0-9_])cmd_\d+(?![A-Za-z0-9_])", cmd_section))
for ref_cmd in ref_cmds:
    if ref_cmd == current_cmd_id:
        continue

    matches = glob.glob(os.path.join(project_root, "outputs", "analysis", "*", f"{ref_cmd}_results.yaml"))
    if not matches:
        continue

    result_path = matches[0]
    config_lists = parse_config_lists(result_path)
    if not config_lists:
        continue

    for config_key, previous_values in config_lists.items():
        current_values = extract_cmd_values(cmd_section, config_key)
        if not current_values:
            continue
        if set(current_values).issubset(set(previous_values)) and set(current_values) != set(previous_values):
            blocked.append((ref_cmd, config_key, previous_values, current_values, result_path))

if blocked:
    ref_cmd, config_key, previous_values, current_values, result_path = blocked[0]
    print(
        f"BLOCK: 前段cmdのパラメータ空間を縮小しています "
        f"({ref_cmd} {config_key}: current={current_values} previous={previous_values})",
        file=sys.stderr,
    )
    print(f"  参照results: {result_path}", file=sys.stderr)
    print("  後段cmdは前段と同一または拡張のみ許可。部分列挙での縮小は不可。", file=sys.stderr)
    sys.exit(1)
PY
}

check_param_space_against_results

# --- Check 15: パラメータ空間縮小検出（WARN） ---
# 起源: 2026-04-04 将軍4回連続で範囲縮小(top_n=5/lookback=6/PBO=5/MaxDD=1)
# 目的: commandに「計算量を言い訳に範囲を狭めた」記述があればWARN
check_param_space_shrink() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    local CMD_SECTION
    CMD_SECTION=$(awk '
        /^[[:space:]]*command:/ { found=1; next }
        found && /^[[:space:]]{4,}/ { print; next }
        found && /^[[:space:]]*[a-z]/ { exit }
    ' <<< "$CMD_BLOCK_NC")
    [[ -z "$CMD_SECTION" ]] && return 0

    local SHRINK_PATTERNS="代表[0-9]+組|代表[0-9]+点|主要な[0-9]+パターン|計算量を考慮し|重いため[0-9]|に絞って検証|に絞って実行|非現実的なので|コスト的に[0-9]"
    local HITS
    HITS=$(grep -Ec "$SHRINK_PATTERNS" <<< "$CMD_SECTION" || true)

    if [[ "$HITS" -gt 0 ]]; then
        echo "WARN: パラメータ空間を縮小していないか？(${HITS}箇所で縮小表現を検出)" >&2
        echo "  → 計算量が多いなら: (1)道具を磨け (2)並列にせよ (3)チャンクに分けよ" >&2
        echo "  → 範囲を狭めることは殿の時間を奪う最大の無駄(2026-04-04殿厳命)" >&2
        record_warn_reason "param_space_shrink_expression" "check=check_param_space_shrink_expression"
    fi
}

check_param_space_shrink

# --- Check 17: 軍師設計書参照cmdの数値緩和検出（WARN — record_warn_reason経由でWARN_COUNTに加算） ---
# 起源: cmd_1781事故 — 軍師設計書の数値→cmdで緩和して起票(cmd_1783教訓)
# 目的: gunshi設計書参照cmdでq8_why_what数値とAC数値を突合し、緩和をWARN
check_gunshi_design_num_relax() {
    [[ -z "${CMD_BLOCK_NC:-}" ]] && return 0

    local scope_mode scout_exempt
    scope_mode="$(cmd_block_get_field "scope_mode")"
    scout_exempt="$(cmd_block_get_field "scout_exempt")"
    if [[ "${scope_mode:-}" == "SCOUT" || "${scout_exempt:-}" == "true" ]]; then
        return 0
    fi

    # 軍師設計書参照検出: q5_verified_sourceに設計書パスが含まれる場合（gunshi補足 2026-04-07）
    # 理由: q5は検証ソースの一次情報→設計書参照の信頼性が最も高い判定基準
    local Q5_VAL
    Q5_VAL="$(cmd_block_get_field "quality_gate.q5_verified_source")"
    if ! grep -qiE 'gunshi[-_]|設計書|context/gunshi' <<< "$Q5_VAL"; then
        return 0
    fi

    # カタログ参照除外: q5にカタログ|catalog|takeaway-catalogが含まれる場合スキップ（LS-A22 cmd_2279）
    # 理由: カタログ由来の閾値は設計書数値でなく分類基準→緩和と誤検出される
    if grep -qiE 'カタログ|catalog|takeaway-catalog' <<< "$Q5_VAL"; then
        return 0
    fi

    # 出口判定: AC YAML構造が適切なら本Check17をスキップ（覚醒設計書v3 cmd_3402）
    # 原理: description非空+binary_check非空+FILL_THIS不在ならAC記入済み=数値精査不要
    if [[ -n "${AC_TEXT:-}" ]]; then
        local _c17_fill _c17_desc_empty _c17_ac_cnt _c17_bc_total _c17_bc_empty
        _c17_fill=$(grep -c 'FILL_THIS' <<< "$AC_TEXT" || true)
        _c17_desc_empty=$(grep -cE "^[[:space:]]*description:[[:space:]]*(\"\"|''|)[[:space:]]*$" <<< "$AC_TEXT" || true)
        _c17_ac_cnt=$(grep -cE '^[[:space:]]+AC[0-9]+:[[:space:]]*$' <<< "$AC_TEXT" || true)
        _c17_bc_total=$(grep -cE '^[[:space:]]*binary_check:' <<< "$AC_TEXT" || true)
        _c17_bc_empty=$(grep -cE "^[[:space:]]*binary_check:[[:space:]]*(\"\"|''|)[[:space:]]*$" <<< "$AC_TEXT" || true)
        if [[ "${_c17_fill:-0}" -eq 0 && "${_c17_desc_empty:-0}" -eq 0 && \
              ( "${_c17_ac_cnt:-0}" -eq 0 || "${_c17_bc_total:-0}" -gt 0 ) && \
              "${_c17_bc_empty:-0}" -eq 0 ]]; then
            return 0  # AC構造OK → Check17スキップ（出口判定 覚醒設計書v3）
        fi
    fi

    # q8_why_whatの存在確認（なければ上のBLOCKで終了済み）
    local Q8_LINE
    Q8_LINE="$(cmd_block_get_field "quality_gate.q8_why_what")"
    [[ -z "$Q8_LINE" ]] && return 0

    # WHAT部分から数値を抽出
    local WHAT_PART Q8_NUMS Q8_MAX
    WHAT_PART="${Q8_LINE#*WHAT:}"
    # FP修正(2026-06-26): WHEN/WHERE/WHO/HOW/複利セクションの数値はWHATの設計パラメータではない
    # 根因: WHO「忍者1名」の1がWHAT数値として抽出されFP(cmd_3537/3538。L3030-3034と同じ除去が必要)
    WHAT_PART="${WHAT_PART%%WHEN:*}"
    WHAT_PART="${WHAT_PART%%WHERE:*}"
    WHAT_PART="${WHAT_PART%%WHO:*}"
    WHAT_PART="${WHAT_PART%%HOW:*}"
    WHAT_PART="${WHAT_PART%%複利:*}"
    # FP修正(2026-06-10 LS050): 日付リテラル(2026/7/1, 2026-06-10, ISO時刻)は設計数値ではない
    WHAT_PART="$(echo "$WHAT_PART" | sed -E 's#(19|20)[0-9]{2}[-/][0-9]{1,2}([-/][0-9]{1,2})?(T[0-9:]+)?##g')"
    # FP修正(2026-07-11 cmd_3850): float8send/sha256等の英字始まり識別子内の数字は設計数値ではない
    WHAT_PART="$(echo "$WHAT_PART" | sed -E 's#[A-Za-z][A-Za-z]*[0-9][A-Za-z0-9]*##g')"
    Q8_NUMS=$(grep -oE '[0-9]+(\.[0-9]+)?' <<< "$WHAT_PART" | sort -n || true)
    [[ -z "$Q8_NUMS" ]] && return 0
    Q8_MAX=$(echo "$Q8_NUMS" | tail -1)

    # acceptance_criteriaから数値を抽出
    local AC_SECTION AC_NUMS AC_MAX
    AC_SECTION=$(awk '
        /acceptance_criteria:/ { found=1; next }
        found && /^    - / { print; next }
        found && /^      / { print; next }
        found { exit }
    ' <<< "$CMD_BLOCK_NC")
    [[ -z "$AC_SECTION" ]] && AC_SECTION="$CMD_BLOCK_NC"
    AC_NUMS=$(echo "$AC_SECTION" | sed -E 's#(19|20)[0-9]{2}[-/][0-9]{1,2}([-/][0-9]{1,2})?(T[0-9:]+)?##g' | sed 's|AC[0-9]\{1,\}||g; s|[A-Za-z_]*_[0-9]\{1,\}[A-Za-z0-9_.-]*||g; s|[A-Za-z_/]\{1,\}/[^ ]*||g; s|[αβγδ][0-9]\{1,\}||g; s|§[0-9.]\{1,\}||g' | sed -E 's#[A-Za-z][A-Za-z]*[0-9][A-Za-z0-9]*##g' | grep -oE '[0-9]+(\.[0-9]+)?' | sort -n || true)

    [[ -n "$AC_NUMS" ]] || return 0

    AC_MAX=$(echo "$AC_NUMS" | tail -1)

    local _c17_relax
    _c17_relax="$(Q8_WHAT="$WHAT_PART" AC_CLAIMS="$AC_SECTION" python3 - <<'PY'
import os, re
pat = re.compile(r'(\d+(?:\.\d+)?)\s*(件|本|個|項目|基準|files?|tests?|秒|分|時間)')
def claims(text):
    out = {}
    for n, unit in pat.findall(text): out.setdefault(unit.lower(), []).append(float(n))
    return out
q, a = claims(os.environ['Q8_WHAT']), claims(os.environ['AC_CLAIMS'])
for unit in q.keys() & a.keys():
    if min(a[unit]) < max(q[unit]): print(f'{max(q[unit]):g}{unit}->{min(a[unit]):g}{unit}')
PY
)"
    if [[ -n "$_c17_relax" ]]; then
        echo "WARN: 軍師設計書参照cmdで数値緩和を検出（cmd_1783教訓）" >&2
        echo "  同一数量主張の縮小: ${_c17_relax}" >&2
        echo "  設計書の数値をACで緩和するな。元の設計書数値を維持せよ" >&2
        record_warn_reason "設計書数値緩和" "check=check_gunshi_reference_numeric_relaxation"
    fi
}

check_gunshi_design_num_relax

# --- Check 16: 行動→即確認原則（全cmd対象 — PI-023汎用化） ---
# 真因: 全ての問題の根源は「行動した後に結果を確認しない」。
# 本番変更かどうかのキーワード判定は各論。全cmdの全ACに確認を問う。
# reason: リアルワールドに事前通告はない(2026-04-07殿指摘)
check_action_immediate_verification() {
    local ac_block verify_ac_count
    ac_block="$(extract_acceptance_criteria_block || true)"
    [[ -n "${ac_block//[[:space:]]/}" ]] || return 0

    verify_ac_count=$(grep -ciE "確認|verify|パリティ|parity|検証|validate|assert|比較|突合|PASS" <<< "$ac_block" 2>/dev/null || true)
    verify_ac_count=$(( ${verify_ac_count:-0} + 0 ))
    if [ "$verify_ac_count" -eq 0 ]; then
        echo "WARNING: 全ACが行動のみで確認を含みません。行動→即確認(PI-023)。" >&2
        echo "  各ACに「やった後どう確認するか」を含めよ。確認なき行動は想像と同じ" >&2
    fi
}

check_action_immediate_verification

show_semantic_index_matches() {
    local SEARCH_TEXT="$1"
    local INDEX_PATH="${SEMANTIC_INDEX_PATH:-$PROJECT_DIR/docs/semantic-index/index.md}"
    [[ -z "$SEARCH_TEXT" || ! -f "$INDEX_PATH" ]] && return 0

    local _semantic_rows _semantic_label _semantic_aliases _semantic_files
    local _semantic_alias _semantic_alias_re
    _semantic_rows=$(awk -F'|' '
        function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
        function flush() {
            if (label != "" && aliases != "") print label "\t" aliases "\t" files
            label=""; aliases=""; files=""
        }
        /^## / { flush(); next }
        trim($2) == "label" {
            label=trim($3)
            next
        }
        trim($2) == "aliases" {
            aliases=trim($3)
            next
        }
        trim($2) == "file" {
            line=trim($3)
            if (files == "") files=line; else files=files ", " line
            next
        }
        END { flush() }
    ' "$INDEX_PATH" 2>/dev/null || true)
    [[ -z "$_semantic_rows" ]] && return 0

    # 全alias照合を単一awkプロセスで実行する。
    # 旧実装はalias毎にsed×2+grep×1-2をforkし(実測3,199 alias≈1万fork=35秒)、
    # cmd_save全体を36秒に劣化させていた(将軍実測2026-07-10)。判定ロジックは旧実装と同一:
    # ASCII語([A-Za-z0-9_ -]+)は単語境界付き大文字小文字無視マッチ、それ以外は部分一致。
    SEMANTIC_SEARCH_TEXT="$SEARCH_TEXT" awk -F'\t' '
        BEGIN { t = tolower(ENVIRON["SEMANTIC_SEARCH_TEXT"]) }
        function esc(s) { gsub(/[][(){}.^$*+?|\\\/]/, "\\\\&", s); return s }
        {
            label = $1; aliases = $2; files = $3
            if (label == "" || aliases == "") next
            n = split(aliases, arr, ",")
            for (i = 1; i <= n; i++) {
                a = arr[i]
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", a)
                if (a == "") continue
                al = tolower(a); hit = 0
                if (a ~ /^[A-Za-z0-9_ -]+$/) {
                    if (t ~ ("(^|[^[:alnum:]_])" esc(al) "([^[:alnum:]_]|$)")) hit = 1
                } else if (index(t, al) > 0) {
                    hit = 1
                }
                if (hit) {
                    printf "INFO: [SEMANTIC] %s matched alias '\''%s'\''\n", label, a > "/dev/stderr"
                    if (files != "") printf "  主要ファイル: %s\n", files > "/dev/stderr"
                    break
                }
            }
        }
    ' <<< "$_semantic_rows"
}

# --- Check 18: 研究cmd道具明示チェック（dm-signal研究cmd対象 — WARNING） ---
# 起源: cmd_1822事故 — 将軍がACに研究エンジンのCLI引数を書かず忍者がhang
# 目的: dm-signal研究cmdでAC内にスクリプトパスが未記載の場合WARNING表示（WARN_COUNTに加算しない）
# カタログ: context/dm-signal-ops.md §18 参照
check_research_tool_explicit() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    # project=dm-signalのみ対象
    local PROJECT_ID
    PROJECT_ID="$CMD_BLOCK_PROJECT"
    [[ "$PROJECT_ID" != "dm-signal" ]] && return 0

    # 出口判定: AC YAML構造が適切なら本Check18をスキップ（覚醒設計書v3 cmd_3402）
    # 原理: description非空+binary_check非空+FILL_THIS不在ならAC記入済み=道具パス精査不要
    if [[ -n "${AC_TEXT:-}" ]]; then
        local _c18_fill _c18_desc_empty _c18_ac_cnt _c18_bc_total _c18_bc_empty
        _c18_fill=$(grep -c 'FILL_THIS' <<< "$AC_TEXT" || true)
        _c18_desc_empty=$(grep -cE "^[[:space:]]*description:[[:space:]]*(\"\"|''|)[[:space:]]*$" <<< "$AC_TEXT" || true)
        _c18_ac_cnt=$(grep -cE '^[[:space:]]+AC[0-9]+:[[:space:]]*$' <<< "$AC_TEXT" || true)
        _c18_bc_total=$(grep -cE '^[[:space:]]*binary_check:' <<< "$AC_TEXT" || true)
        _c18_bc_empty=$(grep -cE "^[[:space:]]*binary_check:[[:space:]]*(\"\"|''|)[[:space:]]*$" <<< "$AC_TEXT" || true)
        if [[ "${_c18_fill:-0}" -eq 0 && "${_c18_desc_empty:-0}" -eq 0 && \
              ( "${_c18_ac_cnt:-0}" -eq 0 || "${_c18_bc_total:-0}" -gt 0 ) && \
              "${_c18_bc_empty:-0}" -eq 0 ]]; then
            return 0  # AC構造OK → Check18スキップ（出口判定 覚醒設計書v3）
        fi
    fi

    # title + command本文から研究ツールキーワード検出
    local FULL_CMD TITLE_LINE SEARCH_TEXT WF_SEARCH_TEXT
    FULL_CMD=$(awk '
        /^\s*command:\s*\|/ { found=1; next }
        /^\s*command:\s*[^|]/ { found=1; sub(/^\s*command:\s*/, ""); print; next }
        found && /^    [a-zA-Z_][a-zA-Z0-9_]*:/ { exit }
        found && /^\s{4,}/ { print; next }
        found { exit }
    ' <<< "$CMD_BLOCK_NC")
    TITLE_LINE=$(grep -m1 '^\s*title:' <<< "$CMD_BLOCK_NC" || true)
    # FP防止(cmd_3384): quality_gate配下のテキストを除外しtitle+command欄のみ対象
    SEARCH_TEXT="${TITLE_LINE}
${FULL_CMD}"

    show_semantic_index_matches "$SEARCH_TEXT"

    local HIT_GS=false HIT_WF=false
    local GS_PATH_CANDIDATE WF_PATH_CANDIDATE
    GS_PATH_CANDIDATE=$(grep -o -m1 -E 'scripts/analysis/grid_search/run_077_[A-Za-z0-9_]+\.py' <<< "$SEARCH_TEXT" || true)
    WF_PATH_CANDIDATE=$(grep -o -m1 -E 'outputs/scripts/l1_alm_wf_engine\.py|[^[:space:]"]+wf_engine[^[:space:]"]*\.py' <<< "$SEARCH_TEXT" || true)
    # cmd_2172: WF四神/WF選別はWF engine実行ではなく分類ラベル。説明文だけでの誤検出を避ける。
    WF_SEARCH_TEXT=$(printf '%s\n' "$SEARCH_TEXT" | sed -E 's/WF(四神|選別)//g')

    # GS検出: bare grid_search は outputs/grid_search/*.csv を誤検出するため、
    # 研究スクリプト参照または明示的なGS文言に限定する。
    # "GS CSV" = データファイル参照であり研究スクリプト実行ではないため除外(cmd_2227 FP修正)
    local GS_SEARCH_TEXT
    GS_SEARCH_TEXT=$(grep -vE 'outputs/grid_search|grid_monthly_fast|grid_results_fast|gs_price_preflight|download_all_prices|data_sync' <<< "$SEARCH_TEXT" | sed -E 's/GS[[:space:]]*CSV//g' || true)
    if grep -qE 'run_077|scripts/analysis/grid[_-]search|grid[_-]search/run|グリッドサーチ|[[:space:]]GS[[:space:]　]|[[:space:]]GS新規|忍法GS|GS[[:space:]を]|GS[[:space:]の]' <<< "$GS_SEARCH_TEXT"; then
        HIT_GS=true
    fi
    if [[ "$HIT_GS" == true ]] && [[ -z "$GS_PATH_CANDIDATE" ]] \
        && grep -qE 'outputs/grid_search|grid_monthly_fast|grid_results_fast' <<< "$SEARCH_TEXT" \
        && grep -qE '偵察|分析|調査|結果参照|CSV|差分確認|算出|相関' <<< "$SEARCH_TEXT"; then
        HIT_GS=false
    fi

    # WF検出: l1_alm_wf_engine / walk.forward / WF(大文字) / ウォークフォワード
    if grep -qE 'l1_alm_wf_engine|wf_engine|walk[_-]forward|ウォークフォワード|[[:space:]]WF[[:space:]　]|窓WF|WF[[:space:]を]|WFで' <<< "$WF_SEARCH_TEXT"; then
        HIT_WF=true
    fi
    if [[ "$HIT_WF" == true ]] && [[ -z "$WF_PATH_CANDIDATE" ]] \
        && grep -qE '偵察|分析|調査|結果参照|CSV|差分確認' <<< "$SEARCH_TEXT"; then
        HIT_WF=false
    fi

    # どちらも検出されなければ対象外
    [[ "$HIT_GS" == false && "$HIT_WF" == false ]] && return 0

    # ACセクションを抽出
    local AC_SECTION
    AC_SECTION=$(awk '
        /acceptance_criteria:/ { found=1; next }
        found && /^    - / { print; next }
        found && /^      / { print; next }
        found { exit }
    ' <<< "$CMD_BLOCK_NC")
    [[ -z "$AC_SECTION" ]] && AC_SECTION="$CMD_BLOCK_NC"

    local HIT=false

    # GS検出 → ACにrun_077が含まれるか確認
    if [[ "$HIT_GS" == true ]]; then
        if ! grep -qE 'run_077|grid_search/run|shin_shijin_l1_gs|wf_alpha_select|champion_select' <<< "$AC_SECTION"; then
            if [[ "$HIT" == false ]]; then
                echo "WARNING: 研究cmd道具明示チェック(Check 18)。ACに研究スクリプトパスが未記載(cmd_1822教訓)" >&2
                HIT=true
            fi
            echo "  GS道具: scripts/analysis/grid_search/run_077_{忍法}.py をACに明記せよ" >&2
            if [[ -n "$GS_PATH_CANDIDATE" ]]; then
                echo "  ACパス候補: ${GS_PATH_CANDIDATE}" >&2
            fi
            echo '  例: "run_077_oikaze.py --universe config/portfolio_universes/XXX.yaml を実行"' >&2
        fi
    fi

    # WF検出 → ACにl1_alm_wf_engineが含まれるか確認
    if [[ "$HIT_WF" == true ]]; then
        if ! grep -qE 'l1_alm_wf_engine|wf_engine|wf_alpha_select' <<< "$AC_SECTION"; then
            if [[ "$HIT" == false ]]; then
                echo "WARNING: 研究cmd道具明示チェック(Check 18)。ACに研究スクリプトパスが未記載(cmd_1822教訓)" >&2
                HIT=true
            fi
            echo "  WF道具: outputs/scripts/l1_alm_wf_engine.py をACに明記せよ" >&2
            if [[ -n "$WF_PATH_CANDIDATE" ]]; then
                echo "  ACパス候補: ${WF_PATH_CANDIDATE}" >&2
            fi
            echo '  例: "l1_alm_wf_engine.py --batch-csvs <paths> --multi-is --cmd-id XXX を実行"' >&2
        fi
    fi

    if [[ "$HIT" == true ]]; then
        echo "  道具カタログ: context/dm-signal-ops.md §18 参照" >&2
        record_warn_reason "研究cmd道具未記載" "check=check_research_tool_explicit"
    fi
}

check_research_tool_explicit

cmd_save_checks_main_mark "parameter_space"
# --- Check 18.5: LK-A10 研究cmd成果物・context還流AC (BLOCK) ---
# 起源: LK-A10 — 研究cmdはcommit checkが効きにくく、成果物現物確認とcontext還流が後追いになっていた。
# 目的: 研究/分析cmd保存時に、成果物ファイル名プレフィックス・ls/head等の現物確認・context還流をACへ明示させる。
check_research_artifact_reflux_ac() {
    [[ -z "${CMD_BLOCK:-}" ]] && return 0

    local TASK_TYPE PROJECT_ID SEARCH_TEXT_EN SEARCH_TEXT_JA AC_SECTION
    TASK_TYPE="$(cmd_block_get_field "type")"
    PROJECT_ID="$CMD_BLOCK_PROJECT"
    # English classifier terms are intentionally limited to semantic header fields.
    # Scanning the whole command made artifact/design paths such as
    # docs/research/... classify ordinary implementation commands as research.
    SEARCH_TEXT_EN="$(printf '%s\n%s\n%s\n' \
        "$TASK_TYPE" \
        "$(cmd_block_get_field "title")" \
        "$(cmd_block_get_field "purpose")")"
    # A docs/research/... spec PATH reference is not research INTENT. Strip path
    # tokens containing "research/" so an implementation command that merely cites
    # a spec living under docs/research/ is not misclassified as a research command
    # (LK-A10 false positive; 殿裁定2026-07-23 cmd_4131). Standalone intent words
    # ("research the market", "analysis of X") survive and still classify.
    SEARCH_TEXT_EN="$(sed -E 's#[A-Za-z0-9_./-]*research/[A-Za-z0-9_./-]*##g' <<< "$SEARCH_TEXT_EN")"
    # Keep Japanese classifier terms on the same semantic-header boundary as
    # English. Full-command scanning misclassifies implementation commands when
    # explanatory AC/q5 text merely mentions research, analysis, or investigation.
    SEARCH_TEXT_JA="$SEARCH_TEXT_EN"

    if ! grep -qiE '(^|[^[:alnum:]_])(research|analysis|investigation)([^[:alnum:]_]|$)' <<< "$SEARCH_TEXT_EN" \
        && ! grep -qE '研究|分析|調査|リサーチ' <<< "$SEARCH_TEXT_JA"; then
        return 0
    fi

    AC_SECTION=$(awk '
        /^[[:space:]]*acceptance_criteria:/ { found=1; next }
        # binary_check: はAC配下の常設キー。exit条件に含めるとAC1のdescription
        # 1行しか検査されず、AC2以降の記述が検出されないFPを生む
        # (2026-07-10 cmd_3836/3837で4回BLOCK往復実証。4関数同型を一括修正)
        found && /^[[:space:]]*[a-z_]+:/ && !/^[[:space:]]*- / && !/^[[:space:]]*description:/ && !/^[[:space:]]*binary_check:/ && !/^[[:space:]]*id:/ { exit }
        found { print }
    ' <<< "$CMD_BLOCK_NC")
    [[ -n "$AC_SECTION" ]] || AC_SECTION="$CMD_BLOCK_NC"

    # LK-A10 protects research-only commands whose markdown/data artifacts can
    # otherwise escape commit-oriented checks.  An implementation command may
    # still mention research/analysis in its semantic header; classify it by
    # its executable AC structure before imposing the research artifact trio.
    # Either a structured test/gate environment change, or a concrete artifact
    # path paired with a binary check, proves that the command has an
    # implementation/test deliverable rather than a research-only deliverable.
    if grep -qiE 'environment_change:.*type=(test|gate)(;|[[:space:]]|$)' <<< "$CMD_BLOCK_NC"; then
        return 0
    fi
    if grep -qE '(^|[[:space:]`"'\''])(scripts|tests|src|app|lib|config|frontend|components|backend)/[^[:space:]`"'\'']+\.[A-Za-z0-9]+' <<< "$AC_SECTION" \
        && grep -qE 'binary_check:' <<< "$AC_SECTION"; then
        return 0
    fi

    local missing=()
    if ! grep -qE 'cmd_[A-Za-z0-9_-]+_[^[:space:]"'\'']*[*]|cmd_[A-Za-z0-9_-]+[*]|docs/research/cmd_[A-Za-z0-9_-]+|outputs/[^[:space:]"'\'']*cmd_[A-Za-z0-9_-]+' <<< "$AC_SECTION"; then
        missing+=("成果物ファイル名プレフィックス(cmd_XXXX_*等)")
    fi
    if ! grep -qiE '(^|[^A-Za-z])(ls|head|wc -l|test -s|stat)([^A-Za-z]|$)|現物確認|ファイル実在|成果物.*(確認|存在)|artifact.*(verify|exists)' <<< "$AC_SECTION"; then
        missing+=("成果物現物確認(ls/head/test -s等)")
    fi
    if ! grep -qiE 'context/|context還流|コンテキスト還流|知識還流|semantic-map|knowledge_candidate|lesson_candidate|projects/[^[:space:]]+\.yaml' <<< "$AC_SECTION"; then
        missing+=("context還流")
    fi

    if ((${#missing[@]} > 0)); then
        local joined
        joined="$(printf '%s, ' "${missing[@]}")"
        joined="${joined%, }"
        record_block_reason "LK-A10: 研究/分析cmdのACに ${joined} が不足。成果物プレフィックス、現物確認、context還流をACへ明記せよ"
        echo "  対象: project=${PROJECT_ID:-unknown} type=${TASK_TYPE:-unknown}" >&2
        echo '  例: "docs/research/cmd_XXXX_*.md を生成し、ls -l + head -40で現物確認し、context/<project>.mdへ結論+参照を還流したか"' >&2
        abort_if_block_immediate || return 1
    fi
}

check_research_artifact_reflux_ac

# --- Quality Summary (品質パターン表示) ---
show_quality_summary() {
    local QUALITY_LOG="$QUALITY_LOG_FILE"

    # AC3: ファイル不存在・空→スキップ（エラーなし）
    if [[ ! -f "$QUALITY_LOG" ]] || [[ ! -s "$QUALITY_LOG" ]]; then
        return 0
    fi

    local scan_file
    scan_file="$(make_quality_log_scan_file)" || return 0

    # Single awk pass over recent index layer: parse entries, output AC1 summary + AC2 warnings
    awk '
    /^ *- cmd_id:/ { n++ }
    /karo_rework:/ {
        val = $2; gsub(/[" ]/, "", val)
        if (val == "yes") rw[n] = 1
    }
    /ninja_blockers:/ {
        val = $2 + 0
        if (val > 0) bl[n] = 1
    }
    /supplementary_cmds:/ {
        val = $2 + 0
        if (val > 0) sp[n] = 1
    }
    END {
        if (n == 0) exit

        # AC1: 直近10件サマリー（10件未満ならあるだけ）
        s10 = (n > 10) ? n - 9 : 1
        c10 = n - s10 + 1
        rw10 = 0; bl10 = 0; sp10 = 0
        for (i = s10; i <= n; i++) {
            rw10 += rw[i]; bl10 += bl[i]; sp10 += sp[i]
        }
        printf "品質: %dcmd中 rework=%d blocker=%d supplementary=%d\n", c10, rw10, bl10, sp10

        # AC2: 直近5件でパターン警告
        s5 = (n > 5) ? n - 4 : 1
        c5 = n - s5 + 1
        if (c5 < 2) exit
        r5 = 0; b5 = 0; p5 = 0
        for (i = s5; i <= n; i++) {
            r5 += rw[i]; b5 += bl[i]; p5 += sp[i]
        }
        rr = (r5 / c5) * 100
        br = (b5 / c5) * 100
        sr = (p5 / c5) * 100
        if (rr > 20) printf "WARNING: rework率%.0f%%。AC設計の精度を確認せよ\n", rr
        if (br > 10) printf "WARNING: blocker率%.0f%%。前提条件の確認を強化せよ\n", br
        if (sr > 30) printf "WARNING: 補足cmd率%.0f%%。スコープ漏れの傾向\n", sr
    }
    ' "$scan_file" || true
}

show_quality_summary

# --- Gunshi直近指摘表示（informational — WARN_COUNTに加算しない） ---
show_gunshi_recent_issues() {
    local GUNSHI_LOG="${CMD_SAVE_GUNSHI_REVIEW_LOG_FILE:-$PROJECT_DIR/logs/gunshi_review_log.yaml}"

    # AC3: ファイル不存在/空→スキップ
    if [[ ! -f "$GUNSHI_LOG" ]] || [[ ! -s "$GUNSHI_LOG" ]]; then
        return 0
    fi

    # AC1+AC2: 直近REQ_CHANGES/FAILを最大3件表示
    awk '
    /^- cmd_id:/ {
        n++
        cmd[n] = $3
    }
    /^  verdict:/ {
        v = $2
        gsub(/#.*/, "", v)
        gsub(/[" ]/, "", v)
        verdict[n] = v
    }
    /^  findings_summary:/ {
        s = $0
        sub(/^  findings_summary: *"?/, "", s)
        sub(/"$/, "", s)
        summary[n] = substr(s, 1, 60)
    }
    END {
        m = 0
        for (i = 1; i <= n; i++) {
            if (verdict[i] == "REQUEST_CHANGES" || verdict[i] == "FAIL") {
                issues[++m] = i
            }
        }
        if (m == 0) exit
        start = (m > 3) ? m - 2 : 1
        for (j = start; j <= m; j++) {
            k = issues[j]
            printf "軍師直近指摘: %s %s — %s\n", cmd[k], verdict[k], summary[k]
        }
    }
    ' "$GUNSHI_LOG" 2>/dev/null || true
}

show_gunshi_recent_issues


# --- 軍師ペイン活動状況表示（informational — WARN_COUNTに加算しない） ---
show_gunshi_pane_status() {
    local PANE_TARGET=""
    if [[ -f "$SCRIPT_DIR/scripts/lib/pane_lookup.sh" ]]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/scripts/lib/pane_lookup.sh"
        PANE_TARGET="$(pane_lookup gunshi 2>/dev/null || true)"
    fi
    PANE_TARGET="${PANE_TARGET:-${TMUX_WINDOW:-shogun:agents}.2}"

    # ペイン存在確認（tmux未起動 or ペインなし → スキップ）
    if ! tmux capture-pane -t "$PANE_TARGET" -p >/dev/null 2>&1; then
        return 0
    fi

    # 最終3行をキャプチャ（空行を除去してから末尾3行）
    local PANE_CONTENT
    PANE_CONTENT=$(tmux capture-pane -t "$PANE_TARGET" -p 2>/dev/null | sed '/^$/d' | tail -n 3) || return 0

    if [[ -n "$PANE_CONTENT" ]]; then
        echo "軍師ペイン(最終3行):"
        while IFS= read -r line; do
            echo "  $line"
        done <<< "$PANE_CONTENT"
    fi
}

show_gunshi_pane_status

# AC_TEXT: acceptance_criteriaセクション全行を結合（Check 19/20で使用）
# description:形式とAC1:"..."形式の両方をカバー
AC_TEXT=$(awk '
  /acceptance_criteria:/ { found=1; next }
  found && /^[[:space:]]{0,4}[a-z_]+:/ && !/^[[:space:]]*AC[0-9]/ && !/^[[:space:]]*description:/ { exit }
  found { print }
' <<< "$CMD_BLOCK" || true)

# --- Check 19: AC YAML構造判定（description非空+binary_check非空+未記入マーカー不在） ---
check_ac_structure_quality

# --- Check 19.5: 共通実行時間契約（BLOCK） ---
# 10分超の自然境界と15分超のexecution_envを配備入口と同じvalidatorで左シフト検証する。
check_long_runtime_execution_env_contract() {
    [[ -n "${CMD_BLOCK_NC:-}" ]] || return 0

    local result rc=0
    result="$(printf '%s\n' "$CMD_BLOCK_NC" |
        python3 "$PROJECT_DIR/scripts/lib/time_contract_validator.py" \
            --allow-missing-estimated -)" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        record_block_reason "$result"
        return 1
    fi
    return 0
}

if ! check_long_runtime_execution_env_contract; then
    [[ "$CMD_SAVE_ACCUMULATE_BLOCKS" == "1" ]] || exit 1
fi

# --- Check 19.6: role-neutral universal shard entrance (30分単独をfail-closed) ---
# Save入口でも同じ契約を自動検証する。manifestの永続生成はdeploy_task入口が担当する。
check_universal_shard_contract() {
    local tmp result rc=0 estimated
    estimated="$(cmd_block_get_field "estimated_minutes")"
    # The Python contract only performs substantive work at >=30 minutes.
    # Keep the exact not_required result on the overwhelmingly common short
    # path without starting Python or scanning every worker task YAML.
    if [[ -z "$estimated" ]]; then
        printf 'PASS(universal_shard={"estimated_minutes": 0.0, "status": "not_required"})\n'
        return 0
    fi
    if [[ "$estimated" =~ ^[0-9]+([.][0-9]+)?$ ]] && awk -v n="$estimated" 'BEGIN { exit !(n < 30) }'; then
        printf 'PASS(universal_shard={"estimated_minutes": %s, "status": "not_required"})\n' "$estimated"
        return 0
    fi
    tmp="$(mktemp)"
    printf '%s\n' "$CMD_BLOCK_NC" >"$tmp"
    result="$(python3 "$PROJECT_DIR/scripts/lib/universal_shard_contract.py" "$tmp" \
        --tasks-dir "$PROJECT_DIR/queue/tasks" 2>&1)" || rc=$?
    rm -f "$tmp"
    if [ "$rc" -ne 0 ]; then
        record_block_reason "$result"
        return 1
    fi
    printf 'PASS(universal_shard=%s)\n' "$result"
}
if ! check_universal_shard_contract; then
    [[ "$CMD_SAVE_ACCUMULATE_BLOCKS" == "1" ]] || exit 1
fi

# --- Check 20: assumptionsフィールド検査（BLOCK昇格 cmd_1906） ---
# 起源: cmd_1905 — 暗黙前提を構造的に可視化し、未検証前提がcmdに混入するのを防ぐ
# 目的: 全cmdにassumptionsがない/未検証前提があるcmdをBLOCKし、暗黙前提の混入を防ぐ（cmd_2157: AC≥3→全cmd）
# cmd_1906: trust:unverified→BLOCK昇格。trust:verified+sourceにファイルパスがある場合実在確認
if true; then
    # 出口判定: AC YAML構造が適切なら本Check20をスキップ（覚醒設計書v3 cmd_3402）
    # 原理: description非空+binary_check非空+FILL_THIS不在ならAC記入済み=assumptions精査不要
    _c20_ac_ok=false
    if [[ -n "${AC_TEXT:-}" ]]; then
        # Check19 already computed these exact counters from the same AC_TEXT.
        # Reuse them instead of spawning five duplicate grep processes.
        _c20_fill="${_FILL_COUNT:-0}"
        _c20_desc_empty="${_DESC_EMPTY_COUNT:-0}"
        _c20_ac_cnt="${_AC_ENTRY_COUNT:-0}"
        _c20_bc_total="${_BC_TOTAL:-0}"
        _c20_bc_empty="${_BC_EMPTY:-0}"
        if [[ "${_c20_fill:-0}" -eq 0 && "${_c20_desc_empty:-0}" -eq 0 && \
              ( "${_c20_ac_cnt:-0}" -eq 0 || "${_c20_bc_total:-0}" -gt 0 ) && \
              "${_c20_bc_empty:-0}" -eq 0 ]]; then
            _c20_ac_ok=true  # AC構造OK → Check20スキップ（出口判定 覚醒設計書v3）
        fi
    fi
    # assumptions存在チェックはpreflight(Check 3)済み。以下は内容検証のみ
    if [[ "$_c20_ac_ok" == false ]] && grep -q "assumptions:" <<< "$CMD_BLOCK_NC"; then
        check_unverified_assumptions_block
        check_assumption_source_paths_block
        check_assumption_claim_dates_warn
        check_negative_claim_grep_evidence_warn
        check_bulletin_count_grep_evidence_warn
        check_measurement_env_info
    fi
fi

# --- Check 20.5: 計測/研究cmdのタイムボックス欄要求（BLOCK） ---
# 起源: LG019 — 研究/計測cmdの実行時間見積がなく、CTX圧迫やOOMを入口で防げない
# 目的: 時間コスト関連cmdに timeout_minutes を明示させ、無制限の計測・探索を防ぐ
check_timebox_minutes_required() {
    [[ -n "${CMD_BLOCK_NC:-}" ]] || return 0

    local SEARCH_TEXT COMMAND_TEXT TIMEOUT_MINUTES FIRST_HIT
    COMMAND_TEXT=$(awk '
        /^[[:space:]]*command:[[:space:]]*\|?[[:space:]]*$/ { in_command=1; next }
        in_command && /^[[:space:]]{4}[a-zA-Z_][a-zA-Z0-9_]*:/ && !/^[[:space:]]*- / { exit }
        in_command { print }
        /^[[:space:]]*command:[[:space:]]*[^|]/ {
            line=$0
            sub(/^[[:space:]]*command:[[:space:]]*/, "", line)
            print line
        }
    ' <<< "$CMD_BLOCK_NC")
    SEARCH_TEXT="$(cmd_block_get_field "purpose")
${COMMAND_TEXT}
${AC_TEXT:-}"

    FIRST_HIT=$(grep -i -m1 -E 'benchmark|計測|研究|grid[_-]?search|探索|見積|見込み|profil' <<< "$SEARCH_TEXT" || true)
    [[ -n "${FIRST_HIT:-}" ]] || return 0

    TIMEOUT_MINUTES="$(cmd_block_get_field "timeout_minutes")"
    if [[ -z "${TIMEOUT_MINUTES//[[:space:]]/}" ]]; then
        TIMEOUT_MINUTES="$(awk '
            /^[[:space:]]*timeout_minutes:[[:space:]]*/ {
                line=$0
                sub(/^[[:space:]]*timeout_minutes:[[:space:]]*/, "", line)
                print line
                exit
            }
        ' <<< "$CMD_BLOCK_NC")"
    fi
    local TIMEOUT_MINUTES_CLEAN
    TIMEOUT_MINUTES_CLEAN="${TIMEOUT_MINUTES//[[:space:]\"]/}"
    TIMEOUT_MINUTES_CLEAN="${TIMEOUT_MINUTES_CLEAN//\'/}"
    if [[ -n "$TIMEOUT_MINUTES_CLEAN" ]]; then
        return 0
    fi

    echo "BLOCK: 計測/研究/見積cmdにtimeout_minutes未記入(LG019)" >&2
    echo "  → timeout_minutes: <想定実行時間上限(分)> をcmdに記入してください" >&2
    echo "  → 検出行: $(printf '%s' "$FIRST_HIT" | sed -E 's/^[[:space:]-]*(description|check|purpose|command):[[:space:]]*//; s/^\"//; s/\"$//' | cut -c1-100)" >&2
    echo "  check=check_timebox_minutes_required" >&2
    record_block_reason "計測研究cmd timeout_minutes未記入。無制限実行を防ぐため上限を明記せよ"
}

check_timebox_minutes_required

# --- Check 20.6: スケーラビリティ見積の内部ループ計上（BLOCK） ---
# 起源: LG028 — per_combo固定値だけで見積り、関数内部の反復を落として実測が10倍外れた
# 目的: 外側件数だけの見積を保存させず、外側×内側×単位時間の積を入口で強制する
check_scalability_internal_loop_estimate() {
    [[ -n "${CMD_BLOCK_NC:-}" ]] || return 0

    local command_text search_text estimate_lines evidence_text first_hit
    command_text="$(extract_command_text_block)"
    search_text="$(cmd_block_get_field "purpose")
${command_text}
${AC_TEXT:-}"
    estimate_lines="$(grep -iE 'スケーラビリティ|scalab|計算時間.*(推定|見積)|実行時間.*(推定|見積)|runtime.*estim|per[_ -]?combo' <<< "$search_text" || true)"
    [[ -n "${estimate_lines:-}" ]] || return 0

    evidence_text="${search_text}
$(collect_numeric_derivation_source_evidence)"
    if grep -qiE '外側|outer|combo|組合せ|組み合わせ' <<< "$evidence_text" &&
       grep -qiE '内側|内部ループ|inner|反復|iteration|回[/ ]?(combo|組合せ|組み合わせ)' <<< "$evidence_text" &&
       grep -qiE '単位時間|1回|per[_ -]?(iteration|call)|ms|ミリ秒|秒[/ ]?回' <<< "$evidence_text"; then
        return 0
    fi

    first_hit="$(sed -n '1p' <<< "$estimate_lines" | sed -E 's/^[[:space:]-]*(description|check|purpose|command):[[:space:]]*//; s/^"//; s/"$//' | cut -c1-100)"
    echo "BLOCK: スケーラビリティ見積に内部ループ計上証跡がない(LG028)" >&2
    echo "  → 外側回数 × 内側回数 × 単位時間を、関数内部まで追跡して明記してください" >&2
    echo "  → 検出行: ${first_hit}" >&2
    record_block_reason "LG028: スケーラビリティ見積に外側回数×内側回数×単位時間の証跡がない"
    abort_if_block_immediate || exit 1
}

check_scalability_internal_loop_estimate

# --- Check 21: ACの数値絶対値WARN検出（informational — WARN_COUNTに加算しない） ---
# 起源: cmd_1910事故 — ACに「テスト数=118」のような固定値を記載し、並行cmdで即陳腐化
# 目的: AC description内の絶対値パターンを検出し、相対条件への書換えを促す
check_ac_absolute_literals() {
    [[ -z "${AC_TEXT:-}" ]] && return 0

    local ABSOLUTE_HITS
    ABSOLUTE_HITS=$(echo "$AC_TEXT" | grep -iE \
        '=[[:space:]]*[0-9]+|テスト数[[:space:]]*[=:：]?[[:space:]]*[0-9]+|[0-9]+(件|個|本|行|回|分|秒|時間|箇所|テスト)([[:space:]]*(PASS|成功|通過))?|ゼロ' \
        || true)
    [[ -z "$ABSOLUTE_HITS" ]] && return 0

    echo "WARN: ACに数値絶対値パターンを検出。並行配備時に陳腐化リスクあり(cmd_1910教訓)" >&2
    echo "  → 相対条件(例: 減少しないこと)への書換えを検討せよ。Check 21はinformationalのみ" >&2
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "  → $(echo "$line" | sed -E 's/^[[:space:]-]*description:[[:space:]]*//; s/^\"//; s/\"$//' | cut -c1-100)" >&2
    done <<< "$ABSOLUTE_HITS"
}

is_db_operation_command_text() {
    local command_text="${1:-}"
    [[ -n "${command_text//[[:space:]]/}" ]] || return 1

    # SCOUT(偵察)cmdは読取専用。DB変更を含まない
    if [[ -n "${CMD_BLOCK_NC:-}" ]] && grep -qiE 'scope_mode.*SCOUT' <<< "$CMD_BLOCK_NC"; then
        return 1
    fi

    # GS出力SQLite(quick_check/出力/結果/experiments.db/突合/統計/経路/参照)は読取のみでDB操作ではない
    local filtered
    filtered="$(grep -viE 'quick_check|GS.*SQLite|SQLite.*出力|SQLite.*結果|SQLite.*記録|SQLite.*統計|SQLite.*突合|SQLite.*経路|SQLite.*参照|grid_search|experiments\.db|daily_prices' <<< "$command_text")"
    [[ -n "${filtered//[[:space:]]/}" ]] || return 1
    grep -qiE '(^|[^A-Za-z0-9_])(migrate|schema[[:space:]_-]+migration|ALTER[[:space:]]+SCHEMA|ALTER[[:space:]]+TABLE|database|init_database|SQLite|DROP|TRUNCATE|DELETE[[:space:]]+FROM)([^A-Za-z0-9_]|$)' <<< "$filtered" || return 1
}

check_db_backup_ac_warn() {
    local command_text ac_text backup_check_text
    command_text="$(extract_command_text_block)"
    is_db_operation_command_text "$command_text" || return 0

    ac_text="$(extract_acceptance_criteria_block)"
    backup_check_text="${command_text}
${ac_text}"
    if grep -qiE 'バックアップ|backup' <<< "$backup_check_text"; then
        return 0
    fi

    echo "WARNING: DB操作cmdを検出。ACに「変更前バックアップ実行済みであること」を追加せよ" >&2
    record_warn_reason "変更前バックアップ実行済みであること" "check=db_backup_required"
}

# --- Check 21.3: 種別連動の実行・復元契約（BLOCK） ---
# 起源: cmd_3861のテスト修正リレーとcmd_3859の本番DB安全停止。
check_execution_contract_requirements_block() {
    local command_text ac_text signal_text missing=()
    command_text="$(extract_command_text_block)"
    ac_text="$(extract_acceptance_criteria_block)"
    signal_text="${command_text}
$(cmd_block_get_field "title")
$(cmd_block_get_field "purpose")"
    [[ -n "${signal_text//[[:space:]]/}" ]] || return 0

    # 語境界\bで英語トークンを囲み、gate_test_health(_test=語境界不成立)やhotfix(tfix=不成立)等の
    # 識別子内substring誤マッチを排除する(2026-07-21 cmd_4112設計cmド誤BLOCK FP修正。LS-A22(13))。
    # 日本語(テスト/修正/回帰)は語境界問題がないため従来通り。挙動は正本と真陽性ケースで一致、FPのみ除去。
    if grep -qiE 'テスト.*(修正|\bfix|回帰|regression)|\bCI\b.*(修正|\bfix|failure|\bfail)|continuous[[:space:]]+integration|\btest.*(\bfix|\bregression|\bfailure)|\bci\b.*(\bfix|\bfailure)' <<< "$signal_text"; then
        # 2026-07-24: 本checkが「全量実行」語を強制した結果、将軍ACに全量unitが焼き込まれ
        # 忍者がフルスイート実行する経路になっていた(実測: unit全量 rolling_median 2454s vs
        # task選択実行 数秒。run_tests.sh cmd_4105計測=99.7%削減が選択実行の設計原則)。
        # 是正: 要求を選択実行契約(run_tests.sh task|file|affected)へ反転し、フルスイート指定はBLOCK。
        if grep -qiE 'run_tests\.sh[[:space:]]+(unit|all|push)\b|全量.*(実行|run)|full.*(run|suite)' <<< "$ac_text"; then
            missing+=("フルスイート指定検出(原則禁止。run_tests.sh task/file/affectedの選択実行へ書換えよ)")
        fi
        if ! grep -qiE 'run_tests\.sh[[:space:]]+(task|file|affected)\b|選択実行' <<< "$ac_text"; then missing+=("選択実行コマンド(run_tests.sh task/file/affected)"); fi
        if ! grep -qiE 'FAIL[[:space:]]*0|0[[:space:]]*(failures?|fails?|失敗)|no[[:space:]]*(failures?|fails?)' <<< "$ac_text"; then missing+=("FAIL0"); fi
        if ! grep -qiE 'SKIP[[:space:]]*0|0[[:space:]]*(skips?|skip|スキップ)|no[[:space:]]*skips?' <<< "$ac_text"; then missing+=("SKIP0"); fi
        if ! grep -qiE '中断.*(再開|resume)|再開.*(成果物|artifact|引継|handoff)|成果物.*(引継|handoff)' <<< "$ac_text"; then missing+=("中断再開時の成果物引継ぎ"); fi
        if (( ${#missing[@]} > 0 )); then
            record_block_reason "test_ci_execution_contract_missing: ${missing[*]}。ACに選択実行コマンド(run_tests.sh task/file/affected)・FAIL0/SKIP0・中断再開時の成果物引継ぎ契約を固定せよ。フルスイート(unit/all)はテスト時間を極端に悪化させるため選択実行が原則(unit全量2454s vs 選択数秒の実測)"
            abort_if_block_immediate || exit 1
        fi
    fi

    is_db_operation_command_text "$command_text" || return 0
    missing=()
    if ! grep -qiE 'restore|復元' <<< "$ac_text"; then missing+=("restore手順"); fi
    if ! grep -qiE 'identity|実行[[:space:]]*(identity|ID|者)|service[[:space:]-]?account' <<< "$ac_text"; then missing+=("実行identity"); fi
    if ! grep -qiE '破壊.*(復元|証跡|evidence)|復元.*(証跡|evidence)|restore.*(証跡|evidence)' <<< "$ac_text"; then missing+=("破壊時復元証跡"); fi
    if (( ${#missing[@]} > 0 )); then
        record_block_reason "production_db_restore_contract_missing: ${missing[*]}。ACにrestore手順・実行identity・破壊時復元証跡を固定せよ"
        abort_if_block_immediate || exit 1
    fi
}

collect_numeric_derivation_source_evidence() {
    [[ -n "${CMD_BLOCK_NC:-}" ]] || return 0

    awk '
        /^[[:space:]]*quality_gate:/ { in_qg=1; next }
        in_qg && /^[[:space:]]+q5_verified_source:/ {
            if ($0 ~ /^[[:space:]]*q5_verified_source:/) print
        }
        /^[[:space:]]*assumptions:/ {
            in_assumptions=1
            match($0, /^[ ]*/)
            assumptions_indent=RLENGTH
            next
        }
        in_assumptions {
            match($0, /^[ ]*/)
            cur_indent=RLENGTH
            if ($0 !~ /^[[:space:]]*$/ && cur_indent <= assumptions_indent) {
                in_assumptions=0
            } else {
                print
            }
        }
    ' <<< "$CMD_BLOCK_NC"
}

numeric_derivation_source_evidence_exists() {
    local evidence_text
    evidence_text="$(collect_numeric_derivation_source_evidence)"
    [[ -n "${evidence_text//[[:space:]]/}" ]] || return 1

    if ! grep -qiE 'grep|rg|wc|awk|sed|find|python|bash|計測|測定|実測|benchmark|ベンチ' <<< "$evidence_text"; then
        return 1
    fi
    grep -qE '→|->|=>|[0-9]+[[:space:]]*(件|行|個|本|箇所|matches?|lines?)|0件|0[[:space:]]+lines?' <<< "$evidence_text"
}

check_numeric_literal_derivation_source_info() {
    local search_text numeric_hits first_hit
    search_text="$(extract_acceptance_criteria_block; extract_command_text_block)"
    [[ -n "${search_text//[[:space:]]/}" ]] || return 0

    numeric_hits="$(grep -E '(^|[^[:alnum:]_])([0-9]{3,}|L[0-9]+)([^[:alnum:]_]|$)' <<< "$search_text" || true)"
    [[ -n "$numeric_hits" ]] || return 0
    numeric_derivation_source_evidence_exists && return 0

    first_hit="$(sed -n '1p' <<< "$numeric_hits" | sed -E 's/^[[:space:]-]*(description|check|id|command):[[:space:]]*//; s/^"//; s/"$//' | cut -c1-100)"
    record_block_reason "LG020: AC/command内の数値リテラルに算出元コマンド+結果がない。入力データから再計算した一次証跡を記載せよ"
    echo "BLOCK: AC/command内に数値リテラルを検出したが、算出元コマンド+結果がない(LG020)" >&2
    echo "  → assumptions claim または q5_verified_source に grep/rg/wc等の算出元と結果を記載してください" >&2
    echo "  → ${first_hit}" >&2
    abort_if_block_immediate || exit 1
}

count_acceptance_criteria_items() {
    local ac_block
    ac_block="$(extract_acceptance_criteria_block)"
    [[ -n "$ac_block" ]] || {
        printf '0'
        return 0
    }

    awk '
        /^[[:space:]]*-[[:space:]]/ { c++; next }
        /^[[:space:]]*(AC|ac)?[0-9]+:/ { c++; next }
        END { print c+0 }
    ' <<< "$ac_block"
}

check_ac_phase_mixing() {
    local ac_block
    ac_block="$(extract_acceptance_criteria_block)"
    [[ -n "${ac_block//[[:space:]]/}" ]] || return 0

    # AC単位の文脈判定: 同一AC内にimpl+measure/deliveryが共起する場合のみWARN
    # 異なるAC間にまたがる場合は正当(実装ACとテストACの共存)
    local mixing_found
    mixing_found="$(awk '
    function check_buf(text,    lt) {
        if (text == "") return
        lt = tolower(text)
        # Exclude concrete file/script references before keyword matching.
        # Example: scripts/deploy_task.sh contains "deploy" but is not a delivery action.
        gsub(/[A-Za-z0-9_.\/-]+\.(md|sh|bash|py|tsx|ts|jsx|js|yaml|yml|json|sql|html|css|toml|cfg|env|bats)/, " ", lt)
        # Exclude function calls that happen to contain phase keywords.
        # Example: deploy_task() names a function; "deploy" alone remains a delivery action.
        gsub(/[a-z_][a-z0-9_]*[[:space:]]*\(/, " ", lt)
        # Exclude snake_case identifiers (DB tables, variables, config keys).
        # Example: benchmark_p_average_results is a table name, not a measurement action.
        # FP fix (2026-06-26): cmd_3533 "benchmark_p_average_results" triggered benchmark keyword.
        gsub(/[a-z][a-z0-9]*(_[a-z][a-z0-9]*)+/, " ", lt)
        if (lt !~ /実装|追加|修正|改修|変更|作成|導入|implement|implementation|add|fix|modify|change|create|introduce/) return
        # Exempt "implementing measurement" pattern: measurement term as object of impl verb
        # e.g. "計測機能を追加" "計測ロジックを実装" "benchmarkを作成" = measurement is the target
        if (lt ~ /(計測|測定|実測|measure|measurement|benchmark|ベンチ).*(を|が|の|機能|ロジック|処理|セクション).*(実装|追加|修正|改修|変更|作成|導入|implement|add|fix|create)/) return
        if (lt ~ /(implement|add|create|fix).*(measure|measurement|benchmark|計測|測定)/) return
        if (lt ~ /cdp|計測|測定|実測|measure|measurement|benchmark|ベンチ/ ||
            lt ~ /push|deploy|デプロイ/) { print "FOUND" }
    }
    BEGIN { min_indent = -1; dict_indent = -1; buf = "" }
    {
        if (min_indent == -1 && /^[[:space:]]*- /) {
            s = $0; gsub(/[^ ].*/, "", s); min_indent = length(s)
        }
        if (dict_indent == -1 && /^[[:space:]]*(AC|ac)?[0-9]+:[[:space:]]*$/) {
            s = $0; gsub(/[^ ].*/, "", s); dict_indent = length(s)
        }
        s = $0; gsub(/[^ ].*/, "", s)
        if (min_indent >= 0 && length(s) == min_indent && substr($0, min_indent+1, 2) == "- ") {
            check_buf(buf); buf = $0 "\n"
        } else if (dict_indent >= 0 && length(s) == dict_indent && $0 ~ /^[[:space:]]*(AC|ac)?[0-9]+:[[:space:]]*$/) {
            check_buf(buf); buf = $0 "\n"
        } else {
            buf = buf $0 "\n"
        }
    }
    END { check_buf(buf) }
    ' <<< "$ac_block")"

    [[ -n "$mixing_found" ]] || return 0

    local impl_hits measure_hits delivery_hits
    impl_hits="$(grep -inE '実装|追加|修正|改修|変更|作成|導入|implement|implementation|add|fix|modify|change|create|introduce' <<< "$ac_block" || true)"
    measure_hits="$(grep -inE 'CDP|計測|測定|実測|measure|measurement|benchmark|ベンチ' <<< "$ac_block" || true)"
    delivery_hits="$(grep -inE 'push|deploy|デプロイ' <<< "$ac_block" || true)"

    echo "WARN: ACフェーズ混在を検出。同一AC内に実装と計測/deployが共起しています" >&2
    echo "  実装ACと後続フェーズACはcmdを分割せよ(cmd_2300教訓)" >&2
    echo "  実装側: $(sed -n '1,2p' <<< "$impl_hits" | tr '\n' ' ')" >&2
    if [[ -n "$measure_hits" ]]; then
        echo "  計測側: $(sed -n '1,2p' <<< "$measure_hits" | tr '\n' ' ')" >&2
    fi
    if [[ -n "$delivery_hits" ]]; then
        echo "  deploy側: $(sed -n '1,2p' <<< "$delivery_hits" | tr '\n' ' ')" >&2
    fi
    # Level5: フェーズ分割テンプレート提案
    echo "  ─── 分割案(コピペ用) ───" >&2
    echo "  AC-impl: 「{実装内容}。batsテストPASS。commit」" >&2
    echo "  AC-verify: 「{計測/CDP確認/deploy}。結果を報告」" >&2
    echo "  ─────────────────────────" >&2
    record_warn_reason "ac_phase_mixing" "check=check_ac_phase_mixing"
}

check_ac_test_scope() {
    local ac_block scope_hits cmd_text category requirement_pattern

    ac_block="$(extract_acceptance_criteria_block)"
    [[ -n "${ac_block//[[:space:]]/}" ]] || return 0

    # スコープ未指定のテスト全件条件を検出。
    # binary_check は同じACの description を二値化した派生要約であり、独立した
    # 受入条件ではない。description が具体的な対象を指定していても binary_check
    # 側だけを行単位で再判定すると cmd_4006 のような既知FPになるため除外する。
    # FP除外: 変更対象/関連テスト/ファイル名/.bats/pre-existing/限定テスト群を含む行はスコープ済みとみなし除外
    scope_hits="$(printf '%s\n' "$ac_block" | \
        grep -v -iE '^[[:space:]]*binary_check:' | \
        grep -v -iE '(変更対象|対象の関連|関連テスト|pre[_\-]?existing|\.bats|scripts/|DB依存テスト|CI固有テスト|退行確認)' | \
        grep -inE \
        '全[[:space:]]*(テスト|test)[[:space:]]*(PASS|通過|成功|pass|green)|テスト[[:space:]]*全[[:space:]]*(PASS|通過|成功|pass|green)|0[[:space:]]*(failures?|errors?|skips?|失敗|エラー|スキップ)|all[[:space:]]*(tests?|テスト)[[:space:]]*(pass|green|通過)|no[[:space:]]*(failures?|errors?|skips?)' \
        || true)"
    if [[ -n "$scope_hits" ]]; then
        echo "WARN: ACにスコープ未指定のテスト全件条件を検出。変更対象の関連テストのみに限定すべき" >&2
        sed -n '1,5p' <<< "$scope_hits" | while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            echo "  → $(echo "$line" | sed -E 's/^[[:space:]-]*(description|check|id):[[:space:]]*//; s/^\"//; s/\"$//' | cut -c1-100)" >&2
        done
        echo "  修正例: 「全テストPASS」→「変更対象(scripts/cmd_save.sh)の関連テストPASS」" >&2
        echo "  修正例: 「0 failures」→「変更ファイルに対応するテスト(test_cmd_save*.bats等)0 failures」" >&2
        echo "  理由: スコープ未指定のAC=pre-existing failureを全て抱え込み、AC達成不能になりうる(cmd_2342教訓)" >&2
        record_warn_reason "ac_test_scope_too_broad" "check=check_ac_test_scope"
    fi

    # D7: テスト作成規律の適用表をcmd入口で固定する。実行対象の選択は
    # 新selectorを作らず既存test_select.shの3層mappingへ委ねる。
    cmd_text="$(printf '%s\n' "${CMD_BLOCK_NC:-$CMD_BLOCK}" | tr '[:upper:]' '[:lower:]')"
    category=""
    requirement_pattern=""
    if grep -qE '(bugfix|bug[ _-]?fix|バグ修正|不具合修正|障害修正|回帰修正)' <<< "$cmd_text"; then
        category="bugfix"
        requirement_pattern='(再現|regression|回帰).*(test|テスト)|(test|テスト).*(再現|regression|回帰)'
    elif grep -qE '(behavior[ _-]?不変|behavior[ _-]?preserving|挙動不変|動作不変).*(refactor|リファクタ)|(refactor|リファクタ).*(behavior[ _-]?不変|behavior[ _-]?preserving|挙動不変|動作不変)' <<< "$cmd_text"; then
        category="behavior_preserving_refactor"
        requirement_pattern='(既存|existing).*(coverage|カバレッジ).*(維持|保持|preserv)|(coverage|カバレッジ).*(維持|保持|preserv)'
    elif grep -qE '(docs?[ /_-]?only|data[ /_-]?only|文書のみ|ドキュメントのみ|データのみ|docs/data-only)' <<< "$cmd_text"; then
        category="docs_data_only"
        requirement_pattern='(実行テスト|test|テスト).*(免除|不要|省略).*(根拠|理由)|(根拠|理由).*(実行テスト|test|テスト).*(免除|不要|省略)'
    elif grep -qE '(新規実装|新機能|新behavior|new[ _-]?behavior|behavior追加|機能追加|分岐追加)' <<< "$cmd_text"; then
        category="new_behavior"
        requirement_pattern='(新規|追加|拡張|new|regression|回帰).*(test|テスト)|(test|テスト).*(新規|追加|拡張|new|regression|回帰)'
    fi

    if [[ -n "$category" ]] && ! grep -qiE "$requirement_pattern" <<< "$ac_block"; then
        echo "WARN: D7テスト作成規律(${category})のAC証跡が不足" >&2
        echo "  適用表: 新behavior=新/拡張test、bugfix=再現regression、behavior不変refactor=既存coverage維持、docs/data-only=実行test免除の根拠" >&2
        echo "  配置: 同一fixture/責務・isolation・per-file wall・並列laneで既存file拡張か新fileかを二値決定" >&2
        echo "  test double: 外部サービス/破壊的操作/実時間依存/side-effect境界failure injectionのみ。第4類型は正常系real pathまたはcontract test併設" >&2
        echo "  削除: contract消滅時のみ。置換/refactorではcoverageを維持" >&2
        record_warn_reason "ac_test_creation_discipline" "check=check_ac_test_scope category=${category}"
    fi
}

check_ac_absolute_literals

# --- Check 21.1: AC/command数値リテラルの算出元記載強制（BLOCK） ---
# 起源: LG020 — 数値の算出元未確認により、grep結果の対象を誤認した
# 目的: 3桁以上整数またはL行番号参照を検出し、算出元コマンド+結果がなければ保存を止める
check_numeric_literal_derivation_source_info

# --- Check 21.2: DB操作cmdのバックアップAC注入提案（WARN） ---
# 起源: 殿厳命 — コードは書き直せる、データは書き直せない。
# 目的: DB変更を含むcmd保存時に変更前バックアップACを必ず可視化する
check_db_backup_ac_warn

# --- Check 21.3: テスト/CI実行・本番DB復元契約（BLOCK） ---
# BLOCKはhandle_cmd_save_exit→log_cmd_save_fire_eventを通り、detector_fp_rate計測へ接続される。
check_execution_contract_requirements_block
cmd_save_checks_main_mark "contracts"

# --- Check 21.5: ACフェーズ混在検出（WARN） ---
# 起源: cmd_2300事故 — 実装ACとCDP計測ACが1cmdに同居し、実装完了後に計測不能でFAIL
# 目的: 実装フェーズと計測/deployフェーズの同居を検出し、cmd分割を促す
check_ac_phase_mixing

# --- Check 21.6: ACテストスコープ検証（WARN） ---
# 起源: cmd_2342 — ACに「全テストPASS」「0 failures」等のスコープ未指定条件を記載すると
#         pre-existing failureを全て抱え込みAC達成不能になる
# 目的: スコープ未指定のテスト全件条件を検出し、変更対象の関連テストのみへの限定を促す
check_ac_test_scope

# --- Check 21.7: Tier1 UNCONDITIONAL規則の例外追記検出（WARN） ---
# 起源: LS092 (cmd_karo_ci_fix_29574746129) — D006趣旨解釈で例外追記→家老拒否
# 目的: Tier1(D001-D009)はUNCONDITIONAL。例外/緩和/除外の共起を検出し代替手段を促す
check_tier1_exception_warn() {
    [[ -z "${CMD_BLOCK_NC:-}" ]] && return
    local tier1_re='D00[1-9]'
    local exception_re='例外|除外|緩和|スコープ追記|趣旨解釈|適用外|対象外|上書き|exemption|exception|override'
    if grep -qE "$tier1_re" <<< "$CMD_BLOCK_NC" && \
       grep -qE "$exception_re" <<< "$CMD_BLOCK_NC"; then
        echo "WARNING: Tier1 UNCONDITIONAL規則(D001-D009)の例外追記を検出。趣旨解釈で緩めてはならない。代替手段(timeout等)で解決せよ(LS092)" >&2
        record_warn_reason "tier1_unconditional_exception" "check=check_tier1_exception_warn"
    fi
}
check_tier1_exception_warn

# --- Check 22: command欄ステップ数 vs AC数の不整合検出（WARN） ---
# 起源: cmd_1953-1958でcommand欄に(1)(2)(3)(4)の4ステップを書いたがAC2個→忍者がspec/設計書をスキップ
# 原理: command欄の番号付きステップ数 > AC数 = 中間成果物がACに分解されていない可能性
# CoDD固有でなく全cmdに適用。手順が増えれば自動検出(100億パターン対応)
if [[ -n "${CMD_BLOCK_NC:-}" ]]; then
    _CMD_SECTION=$(awk '
        /^[[:space:]]*command:[[:space:]]*\|/ { found=1; next }
        /^[[:space:]]*command:[[:space:]]*[^|]/ { found=1; sub(/^[[:space:]]*command:[[:space:]]*/, ""); print; next }
        found && /^[[:space:]]{4}[a-zA-Z_][a-zA-Z0-9_]*:/ { exit }
        found && /^[[:space:]]{4,}/ { print; next }
    ' <<< "$CMD_BLOCK_NC")
    _STEP_COUNT=$(awk '
        function indent_len(s,    t) { t=s; sub(/[^ ].*$/, "", t); return length(t) }
        /^\s*\([0-9]+\)/ || /^\s*[0-9]+[\.\)]\s/ {
            ind = indent_len($0)
            if (min == "" || ind < min) min = ind
            lines[++n] = $0
            indents[n] = ind
        }
        END {
            for (i = 1; i <= n; i++) if (indents[i] == min) c++
            print c+0
        }
    ' <<< "$_CMD_SECTION")
    _AC_COUNT="$(count_acceptance_criteria_items)"
    if (( _STEP_COUNT > 0 && _STEP_COUNT > _AC_COUNT )); then
        echo "WARN: command欄に${_STEP_COUNT}ステップあるがACは${_AC_COUNT}個。中間成果物がACに分解されていない可能性" >&2
        echo "  忍者はACにないことは実行しない。各ステップの成果物をACに対応させよ" >&2
        # Level5: commandステップからAC候補を自動生成
        echo "  ─── AC候補(commandステップから自動生成) ───" >&2
        awk '
            function indent_len(s,    t) { t=s; sub(/[^ ].*$/, "", t); return length(t) }
            /^\s*\([0-9]+\)/ || /^\s*[0-9]+[\.\)]\s/ {
                ind = indent_len($0)
                if (min == "" || ind < min) min = ind
                lines[++n] = $0
                indents[n] = ind
            }
            END {
                for (i = 1; i <= n; i++) {
                    if (indents[i] != min) continue
                    line = lines[i]
                    sub(/^\s*\(?[0-9]+[\.\)]\s*/, "", line)
                    printf "  - \"%s。binary_check: yes/no\"\n", line
                }
            }
        ' <<< "$_CMD_SECTION" >&2
        echo "  ─────────────────────────" >&2
        record_warn_reason "command_steps_over_ac" "check=check_command_steps_vs_ac"
    fi
fi

# --- Check 22: ACにpush要求があればWARN（配備時にpush_allowed自動付与を確認せよ） ---
# 根因: 将軍がACに「commit+push」を習慣的に記載→忍者はデフォルトpush不可(G2ガード)
# cmd_2225/cmd_2226で実証(2026-04-22殿指摘)。
# §42v2(2026-07-10殿裁定: 自走push+deploy)以降、deploy_task.shのinject_push_allowed()が
# AC内'push'検出時にpush_allowed:trueを自動付与する(cmd_3820 push_deploy_permission_gap対策)
if load_cmd_block; then
    _AC_BLOCK="$(extract_acceptance_criteria_block)"
    # \bpush\b はC.UTF-8ロケールで日本語に直接隣接するASCII境界を検出できない(「pushして」等がNOMATCH)。
    # deploy_task.sh inject_push_allowed()と同一の自前境界パターンで検出を揃える。
    if grep -qiE '(^|[^A-Za-z])push($|[^A-Za-z])' <<< "$_AC_BLOCK"; then
        echo "WARN: ACに'push'が含まれている。配備時にpush_allowed:trueが自動付与される(inject_push_allowed)" >&2
        echo "  自走push+deployが不要なら'commit'のみに変更せよ。家老はtask YAMLのpush_allowed付与を確認すること" >&2
        record_warn_reason "ac_contains_push" "check=check_ac_contains_push"
    fi
fi

# --- Check 23: new_file/new_structure request warning ---
# 目的: ACやcommandに新規ファイル/新規構造作成が含まれるときWARNし、既存活用を促す。
check_new_file_structure_warning() {
    local ac_block command_block search_text hits

    ac_block="$(extract_acceptance_criteria_block)"
    command_block="$(awk '
        /^[[:space:]]*command:[[:space:]]*\|/ { found=1; next }
        /^[[:space:]]*command:[[:space:]]*[^|]/ {
            found=1
            sub(/^[[:space:]]*command:[[:space:]]*/, "")
            print
            next
        }
        found && /^[[:space:]]{4,}/ {
            line=$0
            sub(/^[[:space:]]+/, "", line)
            print line
            next
        }
        found && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*:/ { exit }
    ' <<< "$CMD_BLOCK_NC")"
    search_text="${ac_block}"$'\n'"${command_block}"
    [[ -n "${search_text//[[:space:]]/}" ]] || return 0

    # Filter out quality_gate/diagnosis/assumptions content that may leak into search scope
    # (defensive: extract functions should exclude these, but edge cases exist)
    hits="$(grep -v -E '^[[:space:]]*(-[[:space:]]*)?(diagnosis|nazenaze_root_cause|quality_gate|q[0-9]+_[A-Za-z0-9_]*|q_ambiguity|assumptions|trust|claim|environment_change|delegated_at):' <<< "$search_text" | grep -inE 'new_file|new_structure|新規ファイル|新規構造|新規作成|新設|新規に.*(作成|追加)|新しい.*(ファイル|構造)' || true)"
    [[ -n "$hits" ]] || return 0

    echo "WARN: new_file/new_structure要求を検出。既存活用できるファイル・構造がないか確認せよ" >&2
    sed -n '1,5p' <<< "$hits" >&2
    echo "  既存活用を優先し、新規作成が必要なら理由と既存代替の現物確認をcmdに明記せよ" >&2
    # Level5: 新規ファイル名から既存類似ファイルを自動検索して提案
    local _new_names
    # grep無ヒットrc=1がpipefail下でスクリプト全体をexit 1させる(2026-07-12 cmd_3854で実証: WARN表示直後にsilent crash)
    _new_names=$(grep -oE '[a-zA-Z_][a-zA-Z0-9_-]*\.(sh|py|yaml|md|tsx?)' <<< "$hits" | sort -u | sed -n '1,3p' || true)
    if [[ -n "$_new_names" ]]; then
        echo "  ─── 既存類似ファイル候補 ───" >&2
        while IFS= read -r _nf; do
            local _stem="${_nf%.*}" _ext="${_nf##*.}"
            _stem=$(echo "$_stem" | tr '_-' '*')
            local _found
            _found=$(timeout 3 find "$SCRIPT_DIR" -maxdepth 3 \( -name "*${_stem}*" -o -name "*${_ext}" \) 2>/dev/null | head -3 || true)
            [[ -n "$_found" ]] && printf '  %s → 類似: %s\n' "$_nf" "$(echo "$_found" | xargs -I{} basename {} | tr '\n' ', ')" >&2
        done <<< "$_new_names"
        echo "  ─────────────────────────" >&2
    fi
    record_warn_reason "new_file_or_structure_requested" "check=check_new_file_structure_warning"
}

# PRUNED 2026-07-15: fp_rate=100%(4/4偽陽性, logs/detector_fp_rate.yaml)につき呼び出し停止
# (throughput v1.1原則: FP率計測は削るための装置。INS-20260714-223520338-c75b)
# 関数と回帰batsは温存。再有効化は真陽性の実例が出てから
# if load_cmd_block; then
#     check_new_file_structure_warning
# fi

# --- Check 3.6b: WARN時environment_change強制（殿指摘2026-04-20） ---
# 目的: WARNが出た=問題がある。次のcmdで同じWARNが出ないように環境に埋め込め。
# Check 3.6(PRIOR_ATTEMPT_COUNT>0)は過去BLOCK後の再PASS用。こちらはWARN初回用。
# 全チェック完了後に配置(WARNは後段のCheckで蓄積されるため)
if (( WARN_COUNT > 0 )) && (( PRIOR_ATTEMPT_COUNT == 0 )); then
    if load_cmd_block; then
        _ENV_CHANGE_WARN="$(awk '/environment_change:/{found=1; sub(/.*environment_change:[[:space:]]*["\x27]?/,""); sub(/["\x27]?[[:space:]]*$/,""); print; exit} END{if(!found) print ""}' <<< "$CMD_BLOCK_NC")"
        if [[ -z "$_ENV_CHANGE_WARN" ]]; then
            record_block_reason "WARNが${WARN_COUNT}件検出。environment_changeを記載せよ。次のcmdで同じWARNが出ないように環境に何を埋め込むか書け"
            echo '  形式: environment_change: "type=gate|lesson|hook; file=対象パス; pattern=grep検証文字列"' >&2
        else
            # 構造化形式チェック(Check 3.6と同一ロジック)
            if _ENV_WARN_STRUCTURED="$(parse_structured_environment_change "$_ENV_CHANGE_WARN" 2>/dev/null)"; then
                IFS=$'\t' read -r _EW_TYPE _EW_FILE _EW_PATTERN <<< "$_ENV_WARN_STRUCTURED"
                _EW_FILE_RESOLVED="$_EW_FILE"
                [[ "$_EW_FILE_RESOLVED" == /* ]] || _EW_FILE_RESOLVED="$PROJECT_DIR/$_EW_FILE_RESOLVED"
                if ! grep -qE -- "$_EW_PATTERN" "$_EW_FILE_RESOLVED" 2>/dev/null; then
                    record_block_reason "environment_change未実装(WARN対応)。file=${_EW_FILE} に pattern=${_EW_PATTERN} が見つからない"
                fi
            else
                record_block_reason "environment_changeが非構造化(WARN対応)。type=xxx; file=xxx; pattern=xxx の形式で記載せよ"
            fi
        fi
    fi
fi

# --- WARN累計昇格: 同一WARNパターンが繰り返しでBLOCK昇格（cmd_2159） ---
# 目的: WARNを無視し続けるとBLOCKに昇格。WARNを解消しない運用を防ぐ
# 穴2対処(殿指摘2026-04-20): environment_changeを書いたのに同じWARNが再発
#   = 前回の環境変化が無効だった証拠。通常のWARN累計昇格メッセージに加え、
#   「前回のenvironment_changeが効いていない」を明示的にフィードバック。
_WARN_ESCALATE_THRESHOLD=2
if [[ ${#WARN_REASONS[@]} -gt 0 ]]; then
    # カウントを先に(log書込み前)。書込み後だと自分自身をカウントする(閾値1で即BLOCK)
    # 殿裁定(2026-07-09 22:50): 過去の別cmdのWARNが新cmdをBLOCKするのはインフラバグ。
    # 同一cmd_id内の繰り返しのみ累計昇格対象とする。
    for _warn_r in "${WARN_REASONS[@]}"; do
        case "$_warn_r" in
            *"check=cmd_text_deferral_language"*|*"check=quality_gate_q8_scope_expression"*|*"check=check_ac_param_sufficiency"*|*"check=check_causal_verification_requirement"*)
                continue
                ;;
        esac
        _warn_prior_cmd_ids="$(count_same_warn_pattern "$_warn_r" cmd_ids 2>/dev/null || true)"
        # 殿裁定(2026-07-09 22:50): 過去の別cmdのWARNで新cmdをBLOCKしない。
        # 同一cmd_id内の繰り返しのみ累計昇格対象。
        _warn_prior_count=0
        if [[ -n "${_warn_prior_cmd_ids:-}" && -n "${CMD_ID:-}" ]]; then
            for _wid in $(echo "$_warn_prior_cmd_ids" | tr ',' ' '); do
                [[ "$_wid" == "$CMD_ID" ]] && (( _warn_prior_count++ )) || true
            done
        fi
        if (( _warn_prior_count >= _WARN_ESCALATE_THRESHOLD )); then
            log_preflight_autolearn "$_warn_r" "$_warn_prior_count"
            if [[ -n "${_warn_prior_cmd_ids:-}" ]]; then
                record_block_reason "WARN累計昇格: 「${_warn_r}」が${_warn_prior_count}回繰り返されています(cmd_ids=${_warn_prior_cmd_ids})。WARNを解消してからcmd_save.shを実行せよ"
            else
                record_block_reason "WARN累計昇格: 「${_warn_r}」が${_warn_prior_count}回繰り返されています。WARNを解消してからcmd_save.shを実行せよ"
            fi
            echo "  ★ 前回このWARNに対してenvironment_changeを書いたはず。効いていない。" >&2
            echo "  ★ 前回の環境変化の質が低い(根に到達していない)。なぜなぜ7回で深く掘り直せ。" >&2
        fi
    done
    log_cmd_save_warns
fi

# --- BLOCK同一パターン3回なぜなぜ強制(cmd_3243) ---
# 目的: 同一checkで3回BLOCKした場合、ack+修正だけでは通過不能。
# nazenaze_root_cause記入を強制し、L4(BLOCK)→L6(学習速度最大化)を接続する。
if [[ ${#BLOCK_CHECKS[@]} -gt 0 ]]; then
    declare -A _NAZENAZE_CHECKED=()
    for _nz_check in "${BLOCK_CHECKS[@]}"; do
        [[ -v "_NAZENAZE_CHECKED[$_nz_check]" ]] && continue
        _NAZENAZE_CHECKED["$_nz_check"]=1
        _same_check_count=$(count_same_check_prior_blocks "$_nz_check" 2>/dev/null || echo 0)
        [[ "$_same_check_count" =~ ^[0-9]+$ ]] || _same_check_count=0
        if (( _same_check_count >= 2 )); then
            _nazenaze_value="$(extract_nazenaze_root_cause)"
            if [[ -z "$_nazenaze_value" ]]; then
                # BLOCK撤去(殿裁定2026-07-23 gate品質バグ即時修正): count_same_check_prior_blocks は
                # 同一cmd_idの過去BLOCK数を数えるが、BLOCK解消の検証手段は cmd_save 再実行しかなく、
                # 正当なfix-and-retryで数が増え3回目で恒久BLOCK=WARN経路(L7101)で撤去済みの自己参照と
                # 同型。nazenazeの推奨(と学習)は残すがBLOCKはしない。
                echo "  ★ 同一チェック(${_nz_check})で複数回BLOCK。diagnosis.nazenaze_root_cause でなぜなぜ7回の根因分析を推奨(BLOCKはしない)。" >&2
                echo "  形式: nazenaze_root_cause: \"なぜ1→なぜ2→...→根因: ...→仕組み: ...\"" >&2
            fi
        fi
    done
fi

cmd_save_checks_main_mark "final_guards"
cmd_save_phase_mark "checks_main"

# --- 結果出力 ---
# AC1(cmd_3243): PASS時にBLOCK→成功の所要時間を計算
if [[ -f "$BLOCK_START_FILE" ]]; then
    _block_start_epoch=$(cat "$BLOCK_START_FILE" 2>/dev/null || echo 0)
    if [[ "$_block_start_epoch" =~ ^[0-9]+$ ]] && (( _block_start_epoch > 0 )); then
        _block_end_epoch=$(date +%s)
        _block_age=$(( _block_end_epoch - _block_start_epoch ))
        if (( _block_age < 86400 )); then
            BLOCK_DURATION_MINUTES=$(( (_block_end_epoch - _block_start_epoch + 30) / 60 ))
        fi
    fi
fi

if [[ "$BLOCK_COUNT" -eq 0 ]]; then
    # 殿裁定(2026-07-09 22:50): WARNのみ(BLOCKなし)はPASS扱い。
    # WARNは記録するがcmd起票をBLOCKしない。cmdを通した後に修正する。
    if (( WARN_COUNT > 0 )); then
        echo "  WARN ${WARN_COUNT}件あり(BLOCKなし=PASS扱い)。次cmdまでに解消せよ。" >&2
    fi
    # PASS: clean up block start file
    [[ "$CMD_SAVE_PREFLIGHT_ONLY" == "1" ]] || rm -f "$BLOCK_START_FILE"
    if (( BLOCK_DURATION_MINUTES > 0 )); then
        echo "  BLOCK→PASS所要時間: ${BLOCK_DURATION_MINUTES}分" >&2
    fi
    if [[ "$CMD_SAVE_PREFLIGHT_ONLY" == "1" ]]; then
        echo "事前検証OK: ${CMD_ID}"
        echo "  書込みなし: 累計記録/履歴/通知/自動補完は更新していません"
        echo "  保存時は: bash scripts/cmd_save.sh ${CMD_ID}"
    else
        echo "保存確認OK: ${CMD_ID}"
        echo "  次: bash scripts/cmd_delegate.sh ${CMD_ID} \"<家老への配備メッセージ>\" で委任せよ（inbox_write直接のcmd_new送信はcmd_new_gateがBLOCKする）"
    fi
    log_cmd_save_pass
    if [[ "$CMD_SAVE_PREFLIGHT_ONLY" != "1" && -f "$MEMORY_DB_LIVE_INSERT" ]]; then
        printf -v _CMD_SAVE_MEMORY_TS '%(%Y-%m-%dT%H:%M:%S)T' -1
        _CMD_SAVE_MEMORY_SUMMARY="$(awk '
            /^[[:space:]]*title:[[:space:]]*/ {
                sub(/^[[:space:]]*title:[[:space:]]*/, "")
                gsub(/^["'\'']|["'\'']$/, "")
                print
                exit
            }
            /^[[:space:]]*purpose:[[:space:]]*/ {
                sub(/^[[:space:]]*purpose:[[:space:]]*/, "")
                gsub(/^["'\'']|["'\'']$/, "")
                print
                exit
            }
        ' <<< "$CMD_BLOCK_NC")"
        [[ -n "$_CMD_SAVE_MEMORY_SUMMARY" ]] || _CMD_SAVE_MEMORY_SUMMARY="$CMD_ID saved"
        _CMD_SAVE_MEMORY_INSERT_ARGS=(
            "$MEMORY_DB_LIVE_INSERT" cmd_save
            --cmd-id "$CMD_ID"
            --ts "$_CMD_SAVE_MEMORY_TS"
            --summary "$_CMD_SAVE_MEMORY_SUMMARY"
            --detail "$CMD_BLOCK_NC"
            --source-file "${QUEUE_FILE#"$PROJECT_DIR"/}"
        )
        if [[ "$MEMORY_DB_LIVE_INSERT" == *"_async.py" ]]; then
            # WSL2最適化: async wrapperは判定に影響しないためバックグラウンド化。
            python3 "${_CMD_SAVE_MEMORY_INSERT_ARGS[@]}" >/dev/null 2>&1 &
            disown 2>/dev/null || true
        else
            python3 "${_CMD_SAVE_MEMORY_INSERT_ARGS[@]}" >/dev/null 2>&1 || true
        fi
        unset _CMD_SAVE_MEMORY_INSERT_ARGS
    fi
    _BULLETIN_ACTIONED_UPDATED=""
    if [[ "$CMD_SAVE_PREFLIGHT_ONLY" != "1" ]]; then
        _BULLETIN_ACTIONED_UPDATED="$(update_bulletin_actioned_by_for_cmd 2>/dev/null || true)"
    fi
    if [[ -n "$_BULLETIN_ACTIONED_UPDATED" ]]; then
        echo "  bulletin actioned_by更新: ${_BULLETIN_ACTIONED_UPDATED} → ${CMD_ID}"
    fi
    # status: pending 自動注入/昇格。draftのままなら家老監視が無視するため、
    # cmd_save PASS後にだけpendingへ上げる（保存前配備レース防止）。
    _EXISTING_STATUS=$(awk '/status:/{gsub(/.*status: */, ""); gsub(/"/, ""); print; exit}' <<< "$CMD_BLOCK")
    if [[ "$CMD_SAVE_PREFLIGHT_ONLY" != "1" && ( -z "$_EXISTING_STATUS" || "$_EXISTING_STATUS" == "draft" ) ]]; then
        if bash "$SCRIPT_DIR/lib/yaml_field_set.sh" "$QUEUE_FILE" "$CMD_ID" status pending 2>/dev/null; then
            if [[ "$_EXISTING_STATUS" == "draft" ]]; then
                echo "  status: draft→pending — 自動昇格"
            else
                echo "  status: pending — 自動設定"
            fi
        fi
    fi
    # 前回cmd_id記録（次回呼出し時のpending昇格チェック用 — Check 1.6）
    if [[ "$CMD_SAVE_PREFLIGHT_ONLY" != "1" ]]; then
        echo "$CMD_ID" > "$CMD_SAVE_LAST_CMD_FILE"
        remind_missing_current_cmd_lesson_after_clear
    fi
else
if [[ "$CMD_SAVE_PREFLIGHT_ONLY" != "1" && "$BLOCK_COUNT" -gt 0 ]]; then
        # AC1(cmd_3243): Record first BLOCK timestamp for duration tracking
        if [[ "$CMD_SAVE_PREFLIGHT_ONLY" != "1" && ! -f "$BLOCK_START_FILE" ]]; then
            date +%s > "$BLOCK_START_FILE"
        fi
        echo "保存確認NG: ${CMD_ID} (${BLOCK_COUNT}件のBLOCK, ${WARN_COUNT}件のWARN)" >&2
        # 全BLOCK理由の一括サマリ(将軍フリーズ防止: 修正箇所を一目で把握)
        echo "━━━ BLOCK理由一覧 ━━━" >&2
        for i in "${!BLOCK_REASONS[@]}"; do
            echo "  $((i+1)). ${BLOCK_REASONS[$i]}" >&2
        done
        echo "━━━━━━━━━━━━━━━━" >&2
        emit_block_warn_trigger_summary
    else
        echo "保存確認NG: ${CMD_ID} (${WARN_COUNT}件のWARN)" >&2
        emit_block_warn_trigger_summary
    fi
    exit 1
fi
