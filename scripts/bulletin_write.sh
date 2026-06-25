#!/usr/bin/env bash
# semantic-links: [[掲示板通信基盤]]
# bulletin_write.sh — 全エージェント共有掲示板への書込み
# Usage: bash scripts/bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]
#    or: bash scripts/bulletin_write.sh <content> [requires_confirmation] [action_type]

set -euo pipefail

# ── Fast-path: no-args before SCRIPT_DIR/source ──────────────────────────────
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${2:-}" == "-h" || "${2:-}" == "--help" ]]; then
    echo "Usage: bash scripts/bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]"
    echo "    or: bash scripts/bulletin_write.sh <content> [requires_confirmation] [action_type]"
    exit 0
fi
if [[ $# -lt 1 ]]; then
    echo "Usage: bash scripts/bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]" >&2
    exit 1
fi

SCRIPT_DIR="${BULLETIN_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BULLETIN_FILE="$SCRIPT_DIR/queue/bulletin_board.yaml"
LOCK_FILE="${BULLETIN_FILE}.lock"
AGENT_CONFIG="$SCRIPT_DIR/scripts/lib/agent_config.sh"

KNOWN_AGENTS_RAW=""
if [[ -f "$AGENT_CONFIG" ]]; then
    # shellcheck disable=SC1090
    source "$AGENT_CONFIG"
    KNOWN_AGENTS_RAW="$(get_allowed_targets)"
fi

if [[ -z "$KNOWN_AGENTS_RAW" ]]; then
    KNOWN_AGENTS_RAW="shogun karo gunshi $(get_ninja_names 2>/dev/null || echo 'hayate kagemaru hanzo saizo kotaro tobisaru')"
fi

is_known_agent() {
    local candidate="$1"
    local agent=""
    for agent in $KNOWN_AGENTS_RAW; do
        [[ "$agent" == "$candidate" ]] && return 0
    done
    return 1
}

normalize_csv_agents() {
    local raw="$1"
    local field_name="$2"
    local token=""
    local trimmed=""
    local normalized=()
    local joined=""
    local old_ifs="$IFS"
    local i=0
    declare -A seen=()

    IFS=',' read -ra _bw_tokens <<< "$raw"
    IFS="$old_ifs"
    for token in "${_bw_tokens[@]}"; do
        trimmed="${token#"${token%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        [[ -z "$trimmed" ]] && continue
        if ! is_known_agent "$trimmed"; then
            echo "ERROR: unknown ${field_name} agent: $trimmed" >&2
            return 1
        fi
        if [[ -z "${seen[$trimmed]+x}" ]]; then
            normalized+=("$trimmed")
            seen["$trimmed"]=1
        fi
    done

    if [[ ${#normalized[@]} -eq 0 ]]; then
        printf '\n'
        return 0
    fi

    joined="${normalized[0]}"
    for ((i = 1; i < ${#normalized[@]}; i++)); do
        joined+=",${normalized[$i]}"
    done
    printf '%s\n' "$joined"
}

normalize_confirmation_arg() {
    local raw="$1"
    local lowered="${raw,,}"
    case "$lowered" in
        ""|1|true|yes|y|0|false|no|n)
            printf '%s\n' "$raw"
            ;;
        *)
            normalize_csv_agents "$raw" "requires_confirmation"
            ;;
    esac
}

normalize_action_type() {
    local raw="${1:-info}"
    local lowered="${raw,,}"
    case "$lowered" in
        ""|info)
            printf '%s\n' "info"
            ;;
        action_required)
            printf '%s\n' "action_required"
            ;;
        *)
            echo "ERROR: invalid action_type: $raw (expected info or action_required)" >&2
            return 1
            ;;
    esac
}

compute_notify_targets() {
    local posted_by="$1"
    local raw_targets=""
    local token=""
    local normalized=()
    local i=0
    local joined=""
    declare -A seen=()

    if [[ -n "${BULLETIN_NOTIFY:-}" ]]; then
        raw_targets="$BULLETIN_NOTIFY"
    else
        raw_targets="shogun,karo,gunshi"
    fi

    IFS=',' read -ra _bw_nt_tokens <<< "$raw_targets"
    for token in "${_bw_nt_tokens[@]}"; do
        token="${token#"${token%%[![:space:]]*}"}"
        token="${token%"${token##*[![:space:]]}"}"
        [[ -z "$token" ]] && continue
        [[ "$token" == "$posted_by" ]] && continue
        if [[ -z "${seen[$token]+x}" ]]; then
            normalized+=("$token")
            seen["$token"]=1
        fi
    done

    if [[ ${#normalized[@]} -eq 0 ]]; then
        printf '\n'
        return 0
    fi

    joined="${normalized[0]}"
    for ((i = 1; i < ${#normalized[@]}; i++)); do
        joined+=",${normalized[$i]}"
    done
    printf '%s\n' "$joined"
}

POSTED_BY=""
if [[ $# -ge 2 ]] && is_known_agent "$1"; then
    POSTED_BY="$1"
else
    if [[ -n "${TMUX_PANE:-}" ]]; then
        POSTED_BY="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
    fi
    if [[ -z "$POSTED_BY" ]]; then
        POSTED_BY="$(tmux display-message -p '#{@agent_id}' 2>/dev/null || true)"
    fi
    if [[ -z "$POSTED_BY" ]]; then
        POSTED_BY=""
    fi
fi

# Usage: bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]
# posted_by is $1 (explicit), content is $2, requires_confirmation is $3
# posted_byはtmuxからも取得するが、引数で明示されたものを優先(互換性)
if [[ $# -ge 2 ]]; then
    # 新形式: bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]
    POSTED_BY_ARG="$1"
    CONTENT="$2"
    REQUIRES_CONFIRMATION="${3:-false}"
    ACTION_TYPE="${4:-info}"
    # posted_byが既知エージェント名なら引数を信頼
    if is_known_agent "$POSTED_BY_ARG"; then
        POSTED_BY="$POSTED_BY_ARG"
    else
        if [[ -z "$POSTED_BY" ]]; then
            echo "ERROR: agent_id unavailable from tmux; use explicit posted_by argument" >&2
            exit 1
        fi
        # 第1引数がエージェント名でない→旧形式(content, requires_confirmation)
        CONTENT="$1"
        REQUIRES_CONFIRMATION="${2:-false}"
        ACTION_TYPE="${3:-info}"
    fi
else
    if [[ -z "$POSTED_BY" ]]; then
        echo "ERROR: agent_id unavailable from tmux; use explicit posted_by argument" >&2
        exit 1
    fi
    CONTENT="$1"
    REQUIRES_CONFIRMATION="false"
    ACTION_TYPE="info"
fi

# GP-207: contentがエージェント名のみの場合はBLOCK(引数順序ミス検出)
if is_known_agent "$CONTENT"; then
    echo "BLOCK: contentがエージェント名のみ。引数順序ミスの可能性。Usage: bulletin_write.sh <posted_by> <content> [requires_confirmation] [action_type]" >&2
    exit 1
fi

REQUIRES_CONFIRMATION="$(normalize_confirmation_arg "$REQUIRES_CONFIRMATION")"
ACTION_TYPE="$(normalize_action_type "$ACTION_TYPE")"

if [[ -n "${BULLETIN_NOTIFY:-}" ]]; then
    BULLETIN_NOTIFY="$(normalize_csv_agents "$BULLETIN_NOTIFY" "BULLETIN_NOTIFY")"
fi
NOTIFY_TARGETS_CSV="$(compute_notify_targets "$POSTED_BY")"

DATE_FIELDS="$(date '+%Y-%m-%dT%H:%M:%S %s%N %Y%m%d_%H%M%S')"
read -r POSTED_AT DATE_NANOS ENTRY_STAMP <<< "$DATE_FIELDS"
HASH_RESULT="$(printf '%s' "${DATE_NANOS}${POSTED_BY}${CONTENT}" | sha1sum)"
RAND_SUFFIX="${HASH_RESULT:0:6}"
ENTRY_ID="blt_${ENTRY_STAMP}_${RAND_SUFFIX}"

mkdir -p "${BULLETIN_FILE%/*}"

WRITE_RESULT="$({
    flock -x 200

    # ── GP-210: Dedup check (Python3-lite: sys/os only, no yaml import) ─────────
    if [[ -f "$BULLETIN_FILE" && -s "$BULLETIN_FILE" ]]; then
        _bw_dedup_result="$(python3 - "$BULLETIN_FILE" "$POSTED_BY" "$CONTENT" <<'PY'
import sys, os
bf, poster, content_target = sys.argv[1], sys.argv[2], sys.argv[3].strip()
if not os.path.exists(bf):
    sys.exit(0)
lines = open(bf, encoding='utf-8').read().splitlines()
in_content = False
cur_lines = []
cur_poster = None
cur_id = None
def check():
    if cur_poster == poster:
        c = '\n'.join(cur_lines).strip()
        if c == content_target:
            print(f"DEDUP: 同一内容の掲示板エントリが既存 ({cur_id})")
            sys.exit(0)
for line in lines:
    if line.startswith('- id:'):
        check()
        cur_id = line[7:-1].replace("''", "'") if line.endswith("'") else line[7:]
        in_content = False; cur_lines = []; cur_poster = None
    elif line == '  content: |-':
        in_content = True
    elif in_content and line.startswith('    '):
        cur_lines.append(line[4:])
    elif in_content:
        in_content = False
        if line.startswith("  posted_by: '"):
            raw = line[14:]
            cur_poster = (raw[:-1] if raw.endswith("'") else raw).replace("''", "'")
    elif line.startswith("  posted_by: '"):
        raw = line[14:]
        cur_poster = (raw[:-1] if raw.endswith("'") else raw).replace("''", "'")
check()
PY
)"
        if [[ "$_bw_dedup_result" == DEDUP:* ]]; then
            printf '%s\n' "$_bw_dedup_result"
            exit 0
        fi
    fi

    # ── Write new entry (bash-only, prepend — no yaml import) ───────────────────
    _bw_sq() { printf '%s' "${1//\'/\'\'}"; }
    _bw_stripped_content="${CONTENT%$'\n'}"

    {
        printf '%s\n' "- id: '$(_bw_sq "$ENTRY_ID")'"
        printf "  content: |-\n"
        while IFS= read -r _bw_line; do
            printf "    %s\n" "$_bw_line"
        done <<< "$_bw_stripped_content"
        printf "  posted_by: '%s'\n" "$(_bw_sq "$POSTED_BY")"
        printf "  posted_at: '%s'\n" "$(_bw_sq "$POSTED_AT")"
        case "${REQUIRES_CONFIRMATION,,}" in
            ""|0|false|no|n) printf "  requires_confirmation: false\n" ;;
            1|true|yes|y)    printf "  requires_confirmation: true\n" ;;
            *)
                printf "  requires_confirmation:\n"
                IFS=',' read -ra _bw_rc_agents <<< "$REQUIRES_CONFIRMATION"
                for _bw_rc_a in "${_bw_rc_agents[@]}"; do
                    _bw_rc_a="${_bw_rc_a#"${_bw_rc_a%%[![:space:]]*}"}"
                    _bw_rc_a="${_bw_rc_a%"${_bw_rc_a##*[![:space:]]}"}"
                    [[ -n "$_bw_rc_a" ]] && printf "    - '%s'\n" "$(_bw_sq "$_bw_rc_a")"
                done
                ;;
        esac
        printf "  action_type: '%s'\n" "$(_bw_sq "$ACTION_TYPE")"
        printf "  actioned_by: ''\n"
        if [[ -n "$NOTIFY_TARGETS_CSV" ]]; then
            printf "  notify_targets:\n"
            IFS=',' read -ra _bw_nt_agents <<< "$NOTIFY_TARGETS_CSV"
            for _bw_nt_a in "${_bw_nt_agents[@]}"; do
                [[ -n "$_bw_nt_a" ]] && printf "    - '%s'\n" "$(_bw_sq "$_bw_nt_a")"
            done
        else
            printf "  notify_targets: []\n"
        fi
        printf "  confirmed_by: []\n"
        printf "  status: 'open'\n"
    } > "${BULLETIN_FILE}.new_entry"

    {
        printf "entries:\n"
        cat "${BULLETIN_FILE}.new_entry"
        [[ -f "$BULLETIN_FILE" ]] && tail -n +2 "$BULLETIN_FILE"
    } > "${BULLETIN_FILE}.tmp"
    rm -f "${BULLETIN_FILE}.new_entry"
    mv "${BULLETIN_FILE}.tmp" "$BULLETIN_FILE"

    printf '%s\n' "$ENTRY_ID"

} 200>"$LOCK_FILE")"

if [[ "$WRITE_RESULT" == DEDUP:* ]]; then
    printf '%s\n' "$WRITE_RESULT"
    exit 0
fi

printf '%s\n' "$WRITE_RESULT"

MEMORY_DB_LIVE_INSERT="$SCRIPT_DIR/scripts/memory_db_live_insert_async.py"
if [[ ! -f "$MEMORY_DB_LIVE_INSERT" ]]; then
    MEMORY_DB_LIVE_INSERT="$SCRIPT_DIR/scripts/memory_db_live_insert.py"
fi
if [[ -f "$MEMORY_DB_LIVE_INSERT" ]]; then
    _memory_db_insert_cmd=(
        python3 "$MEMORY_DB_LIVE_INSERT" bulletin
        --entry-id "$WRITE_RESULT" \
        --ts "$POSTED_AT" \
        --agent "$POSTED_BY" \
        --content "$CONTENT" \
        --requires-confirmation "$REQUIRES_CONFIRMATION" \
        --action-type "$ACTION_TYPE" \
        --actioned-by "" \
        --status "open" \
        --source-file "$BULLETIN_FILE"
    )
    if [[ "${MEMORY_DB_LIVE_INSERT_SYNC:-0}" == "1" || -n "${SHOGUN_MEMORY_DB:-}" || ( "$SCRIPT_DIR" != /mnt/c/* && "$SCRIPT_DIR" != /mnt/d/* ) ]]; then
        "${_memory_db_insert_cmd[@]}" >/dev/null 2>&1 || true
    else
        "${_memory_db_insert_cmd[@]}" >/dev/null 2>&1 &
        disown 2>/dev/null || true
    fi
fi

if [[ -f "$BULLETIN_FILE" && -x "$SCRIPT_DIR/scripts/bulletin_archive.sh" ]]; then
    ENTRY_COUNT="$(awk '/^- id: / {count++} END {print count + 0}' "$BULLETIN_FILE")"
    if [[ "$ENTRY_COUNT" -gt 50 ]]; then
        bash "$SCRIPT_DIR/scripts/bulletin_archive.sh" --max-keep 30 >/dev/null 2>&1 || true
    fi
fi

SHOGUN_ROOT="$SCRIPT_DIR" bash "$SCRIPT_DIR/scripts/yaml_auto_archive.sh" >/dev/null 2>&1 || true

# --- 投稿者以外に自動通知 ---
INBOX_WRITE="$SCRIPT_DIR/scripts/inbox_write.sh"
if [[ -f "$INBOX_WRITE" ]]; then
    # BULLETIN_NOTIFY: 環境変数で通知先を限定可能(カンマ区切り)
    # 未指定時は将軍+家老+軍師の全3者
    if [[ -n "$NOTIFY_TARGETS_CSV" ]]; then
        IFS=',' read -ra NOTIFY_TARGETS <<< "$NOTIFY_TARGETS_CSV"
    else
        NOTIFY_TARGETS=()
    fi
    # GP-208: 掲示板全文をinboxに含める。80文字要約→全文。
    # 理由: 通知だけでは読みに行く行動は強制できない。
    # inboxを読む行動は既に強制されている(startup gate+stop hook)。
    # その中に全文があれば、別途掲示板を読みに行く必要がない。
    for target in "${NOTIFY_TARGETS[@]}"; do
        if ! bash "$INBOX_WRITE" "$target" "掲示板新規投稿($ENTRY_ID): ${CONTENT}" bulletin_notify "$POSTED_BY" 2>/dev/null; then
            echo "[bulletin_write] WARN: inbox_write failed for ${target} — bulletin notification not delivered" >&2
            continue
        fi
        if ! pgrep -f "inbox_watcher.sh ${target}" >/dev/null 2>&1; then
            echo "[bulletin_write] WARN: inbox_watcher not running for ${target} — nudge may be lost" >&2
        fi
    done
fi
