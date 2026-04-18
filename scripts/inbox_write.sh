#!/bin/bash
# inbox_write.sh — メールボックスへのメッセージ書き込み（排他ロック付き）
# Usage: bash scripts/inbox_write.sh <target_agent> <content> [type] [from] [action]
# Example: bash scripts/inbox_write.sh karo "半蔵、任務完了" report_received hanzo notify_karo
#
# Supported types:
#   wake_up              — デフォルト。汎用起動通知
#   task_assigned        — タスク配備通知（家老→忍者）
#   task_supplement      — タスク補足通知（家老/軍師→忍者）
#   task_cancel          — タスク取消通知（家老→忍者）
#   cmd_new              — 新cmd通知（将軍→家老）
#   report_received      — 忍者報告完了通知（忍者→家老）※報告YAML検証+auto-done hookあり
#   uncommitted_block    — 未commitブロック通知
#   review_draft         — draft cmdレビュー依頼（家老→軍師）
#   review_result        — レビュー結果（軍師→家老）
#   review_feedback      — GATEフィードバック（家老→軍師）
#   report_review        — 忍者報告一次レビュー依頼（家老→軍師）
#   report_review_result — 忍者報告レビュー結果（軍師→家老）
#   workaround_feedback  — workaround原因共有（家老→軍師）
#   review_hint          — レビューヒント（家老→軍師）
#   analysis_result      — idle時データ分析結果（軍師→家老）
#   gunshi_lesson_candidate — 軍師教訓候補（軍師→家老）
#   decomposition_feedback  — 分解フィードバック（軍師→家老）
#   verify_request       — RC修正再検証依頼（家老→軍師）
#   verify_result        — RC修正再検証結果（軍師→家老）
#   clear_command        — /clear送信（特殊: inbox_watcherがCLI直接操作）
#   model_switch         — /model切替（特殊: inbox_watcherがCLI直接操作）
#   recovery             — 復帰通知

set -e

# SCRIPT_DIR/SELF_SCRIPT_PATH: string ops instead of dirname/basename/cd subshells (~5ms savings on WSL2)
_iw_self="${BASH_SOURCE[0]:-$0}"
[[ "$_iw_self" != /* ]] && _iw_self="$PWD/$_iw_self"
SCRIPT_DIR="${INBOX_WRITE_ROOT_OVERRIDE:-${_iw_self%/scripts/inbox_write.sh}}"
SELF_SCRIPT_PATH="$_iw_self"
NINJA_NAMES=""
AGENT_CONFIG_LOADED=0

FIELD_GET_LOADED=0
CLI_LOOKUP_LOADED=0

usage() {
    cat <<'EOF'
Usage: inbox_write.sh <target_agent> <content> [type] [from] [action]
EOF
}

is_core_agent() {
    case "$1" in
        shogun|karo|gunshi)
            return 0
            ;;
    esac
    return 1
}

known_agent_from_fs() {
    local agent="$1"

    is_core_agent "$agent" && return 0
    [ -f "$SCRIPT_DIR/queue/tasks/${agent}.yaml" ] && return 0
    [ -f "$SCRIPT_DIR/queue/inbox/${agent}.yaml" ] && return 0
    return 1
}

sender_is_ninja_from_fs() {
    local agent="$1"

    [ "$agent" = "ninja_monitor" ] && return 1
    is_core_agent "$agent" && return 1
    [ -f "$SCRIPT_DIR/queue/tasks/${agent}.yaml" ]
}

ensure_agent_config_loaded() {
    if [ "${AGENT_CONFIG_LOADED:-0}" = "1" ]; then
        return 0
    fi

    if [ "${INBOX_WRITE_TEST:-}" != "1" ] && [ -f "$SCRIPT_DIR/scripts/lib/agent_config.sh" ]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/scripts/lib/agent_config.sh"
        NINJA_NAMES=$(get_ninja_names)
    else
        NINJA_NAMES=""
    fi

    AGENT_CONFIG_LOADED=1
}

ensure_field_get_loaded() {
    if [ "${FIELD_GET_LOADED:-0}" = "1" ]; then
        return 0
    fi
    if [ -f "$SCRIPT_DIR/scripts/lib/field_get.sh" ]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/scripts/lib/field_get.sh" 2>/dev/null || true
    fi
    FIELD_GET_LOADED=1
}

ensure_cli_lookup_loaded() {
    if [ "${CLI_LOOKUP_LOADED:-0}" = "1" ]; then
        return 0
    fi
    if [ -f "$SCRIPT_DIR/scripts/lib/cli_lookup.sh" ]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/scripts/lib/cli_lookup.sh" 2>/dev/null || true
    fi
    CLI_LOOKUP_LOADED=1
}

lock_path() {
    case "$1" in
        /mnt/c/*|/mnt/d/*)
            local sanitized="${1//[^[:alnum:]._-]/_}"
            if ((${#sanitized} > 180)); then
                sanitized="${sanitized:0:120}_${sanitized: -40}_${#1}"
            fi
            printf '/tmp/shogun_lock_%s.lock' "$sanitized"
            ;;
        *)
            printf '%s.lock' "$1"
            ;;
    esac
}

inbox_yaml_field_get() {
    local yaml_file="$1"
    local field_name="$2"
    local default_value="${3:-}"

    ensure_field_get_loaded
    if type field_get &>/dev/null; then
        FIELD_GET_NO_LOG=1 field_get "$yaml_file" "$field_name" "$default_value" 2>/dev/null || true
        return 0
    fi

    grep -m1 -E "^[[:space:]]*${field_name}:" "$yaml_file" 2>/dev/null \
        | sed 's/^[^:]*:[[:space:]]*//' \
        | sed "s/^['\"]//;s/['\"]$//"
}

report_yaml_is_template() {
    local report_path="$1"
    local verdict=""

    verdict=$(inbox_yaml_field_get "$report_path" "verdict" "")
    if [ -z "${verdict//[[:space:]]/}" ]; then
        echo "yes"
        return 0
    fi

    if grep -Eq '^[[:space:]]*result:[[:space:]]*.*FILL_THIS' "$report_path" 2>/dev/null; then
        echo "yes"
        return 0
    fi

    echo "no"
}

inbox_yaml_strip_quotes() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
        value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
        value="${value:1:${#value}-2}"
        value="${value//\'\'/\'}"
    fi
    printf '%s' "$value"
}

inbox_yaml_emit_field() {
    local first="$1"
    local key="$2"
    local value="$3"
    local prefix="  "
    [[ "$first" == "1" ]] && prefix="- "

    if [[ "$value" == "true" || "$value" == "false" ]]; then
        printf '%s%s: %s\n' "$prefix" "$key" "$value"
        return 0
    fi

    if [[ "$value" == *$'\n'* ]]; then
        printf '%s%s: |-\n' "$prefix" "$key"
        while IFS= read -r _line || [[ -n "$_line" ]]; do
            printf '    %s\n' "$_line"
        done <<< "$value"
        return 0
    fi

    value="${value//\'/\'\'}"
    printf "%s%s: '%s'\n" "$prefix" "$key" "$value"
}

inbox_build_message_block() {
    local output="" first=1
    local field_output=""
    while [[ $# -ge 2 ]]; do
        field_output="$(inbox_yaml_emit_field "$first" "$1" "$2")"
        output+="${field_output}"$'\n'
        first=0
        shift 2
    done
    printf '%s' "$output"
}

inbox_collect_records() {
    local inbox_file="$1"
    INBOX_RECORDS=()
    INBOX_RECORD_READS=()
    [[ -f "$inbox_file" ]] || return 0

    while IFS= read -r -d '' _record_item; do
        INBOX_RECORD_READS+=("${_record_item%%$'\034'*}")
        INBOX_RECORDS+=("${_record_item#*$'\034'}")
    done < <(
        awk '
            BEGIN { started = 0; rec = ""; read_state = "false"; }
            /^messages:[[:space:]]*\[\][[:space:]]*$/ { next }
            /^messages:[[:space:]]*$/ { next }
            /^- / {
                if (started) {
                    printf "%s\034%s\0", read_state, rec
                }
                rec = $0 "\n"
                read_state = "false"
                started = 1
                next
            }
            started {
                rec = rec $0 "\n"
                if ($0 ~ /^  read:[[:space:]]*/) {
                    read_state = $0
                    sub(/^  read:[[:space:]]*/, "", read_state)
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", read_state)
                }
            }
            END {
                if (started) {
                    printf "%s\034%s\0", read_state, rec
                }
            }
        ' "$inbox_file"
    )
}

inbox_write_records() {
    local inbox_file="$1"
    shift
    local tmp_file
    tmp_file=$(mktemp "${inbox_file}.XXXXXX.tmp")
    if [[ $# -eq 0 ]]; then
        printf 'messages: []\n' > "$tmp_file"
    else
        printf 'messages:\n' > "$tmp_file"
        local _record
        for _record in "$@"; do
            printf '%s' "$_record" >> "$tmp_file"
        done
    fi
    mv "$tmp_file" "$inbox_file"
}

inbox_is_empty_file() {
    local inbox_file="$1"
    [[ -f "$inbox_file" ]] || {
        return 0
    }

    local first_line=""
    IFS= read -r first_line < "$inbox_file" || first_line=""
    [[ "$first_line" == "messages: []" ]]
}

inbox_message_count() {
    local inbox_file="$1"
    if inbox_is_empty_file "$inbox_file"; then
        echo 0
        return 0
    fi
    local count
    count=$(grep -c '^- ' "$inbox_file" 2>/dev/null || true)
    printf '%s\n' "${count:-0}"
}

inbox_unread_count() {
    local inbox_file="$1"
    [[ -f "$inbox_file" ]] || {
        echo 0
        return 0
    }

    awk '
        BEGIN { c = 0 }
        /^- / { in_msg = 1; read_state = "false"; next }
        in_msg && /^  read:[[:space:]]*/ {
            line = $0
            sub(/^  read:[[:space:]]*/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            if (tolower(line) != "true") c++
            in_msg = 0
        }
        END {
            if (in_msg) c++
            print c
        }
    ' "$inbox_file"
}

inbox_message_marked_read() {
    local inbox_file="$1"
    local msg_id="$2"
    [[ -f "$inbox_file" ]] || return 1

    awk -v msg_id="$msg_id" '
        BEGIN { in_msg = 0; found = 0; read_state = "false" }
        /^- / {
            if (found) exit(tolower(read_state) == "true" ? 0 : 1)
            in_msg = 1
            read_state = "false"
            next
        }
        in_msg && /^  id:[[:space:]]*/ {
            line = $0
            sub(/^  id:[[:space:]]*/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            gsub(/^["'\'']|["'\'']$/, "", line)
            if (line == msg_id) found = 1
            next
        }
        in_msg && found && /^  read:[[:space:]]*/ {
            read_state = $0
            sub(/^  read:[[:space:]]*/, "", read_state)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", read_state)
            exit(tolower(read_state) == "true" ? 0 : 1)
        }
        END {
            if (found) exit(tolower(read_state) == "true" ? 0 : 1)
            exit 1
        }
    ' "$inbox_file"
}

resolve_agent_pane_target() {
    local agent="$1"
    command -v tmux >/dev/null 2>&1 || return 1

    tmux list-panes -a -F '#{session_name}:#{window_name}.#{pane_index} #{@agent_id}' 2>/dev/null \
        | awk -v agent="$agent" '$2 == agent { print $1; exit }'
}

run_tmux_with_timeout() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 5 tmux "$@"
    else
        tmux "$@"
    fi
}

send_codex_task_nudge() {
    local target="$1"
    local pane_target="$2"
    local unread_count="$3"
    local nudge="inbox${unread_count} — タスクYAML: queue/tasks/${target}.yaml を読んで作業開始せよ"

    tmux set-buffer -b "nudge_${target}" "$nudge" 2>/dev/null || return 1
    run_tmux_with_timeout paste-buffer -t "$pane_target" -b "nudge_${target}" -d >/dev/null 2>&1 || return 1
    sleep 0.02
    run_tmux_with_timeout send-keys -t "$pane_target" Enter >/dev/null 2>&1 || return 1
}

verify_codex_task_delivery() {
    local target="$1"
    local msg_id="$2"
    local inbox_file="$SCRIPT_DIR/queue/inbox/${target}.yaml"
    local task_file="$SCRIPT_DIR/queue/tasks/${target}.yaml"

    if inbox_message_marked_read "$inbox_file" "$msg_id"; then
        return 0
    fi

    if [ -f "$task_file" ]; then
        local task_status
        task_status=$(inbox_yaml_field_get "$task_file" "status" "")
        case "$task_status" in
            acknowledged|in_progress|done|failed|blocked)
                return 0
                ;;
        esac
    fi

    return 1
}

maybe_verify_codex_delivery() {
    local target="$1"
    local msg_id="$2"
    local type="$3"

    [ "$type" = "task_assigned" ] || return 0

    ensure_cli_lookup_loaded
    type cli_type >/dev/null 2>&1 || return 0
    [ "$(cli_type "$target")" = "codex" ] || return 0

    local inbox_file="$SCRIPT_DIR/queue/inbox/${target}.yaml"
    [ -f "$inbox_file" ] || return 0

    local retries="${INBOX_CODEX_NUDGE_RETRIES:-2}"
    local wait_sec="${INBOX_CODEX_VERIFY_WAIT_SEC:-1}"
    local attempt=0

    local pane_target
    pane_target=$(resolve_agent_pane_target "$target" || true)

    while [ "$attempt" -le "$retries" ]; do
        if [ "$attempt" -gt 0 ]; then
            # Working状態の忍者にはretry不要（既に処理中）
            if [ -n "$pane_target" ]; then
                local pane_snapshot
                pane_snapshot=$(tmux capture-pane -t "$pane_target" -p -S -5 2>/dev/null || true)
                if echo "$pane_snapshot" | grep -qE '• (Working|Ran |Waiting)'; then
                    echo "[inbox_write] codex delivery verified (ninja working) for ${target}" >&2
                    return 0
                fi
            fi
            local unread_count
            unread_count=$(inbox_unread_count "$inbox_file")
            if [ -n "$pane_target" ] && [ "$unread_count" -gt 0 ] 2>/dev/null; then
                if send_codex_task_nudge "$target" "$pane_target" "$unread_count"; then
                    echo "[inbox_write] codex nudge retry ${attempt}/${retries} sent to ${target}" >&2
                else
                    echo "[inbox_write] codex nudge retry ${attempt}/${retries} failed for ${target}" >&2
                fi
            else
                echo "[inbox_write] codex nudge retry ${attempt}/${retries} skipped for ${target} (pane/unread unavailable)" >&2
            fi
        fi

        sleep "$wait_sec"

        if verify_codex_task_delivery "$target" "$msg_id"; then
            if [ "$attempt" -eq 0 ]; then
                echo "[inbox_write] codex delivery verified for ${target}" >&2
            else
                echo "[inbox_write] codex delivery verified after retry ${attempt}/${retries} for ${target}" >&2
            fi
            return 0
        fi

        attempt=$((attempt + 1))
    done

    echo "[inbox_write] WARN: codex delivery remained unverified for ${target} after ${retries} retries" >&2
}

list_active_ninjas() {
    local ninja=""
    local task_file=""
    local task_status=""

    ensure_agent_config_loaded
    for ninja in $NINJA_NAMES; do
        task_file="$SCRIPT_DIR/queue/tasks/${ninja}.yaml"
        [ -f "$task_file" ] || continue

        task_status=$(inbox_yaml_field_get "$task_file" "status" "")
        case "$task_status" in
            assigned|acknowledged|in_progress)
                printf '%s\n' "$ninja"
                ;;
        esac
    done
}

forward_gunshi_review_result_to_active_ninjas() {
    local review_content="$1"
    local ninja=""
    local forward_message=""

    while IFS= read -r ninja; do
        [ -n "$ninja" ] || continue
        forward_message="軍師レビュー補足: $review_content"
        if ! INBOX_WRITE_ROOT_OVERRIDE="$SCRIPT_DIR" \
            INBOX_WRITE_TEST="${INBOX_WRITE_TEST:-}" \
            bash "$SELF_SCRIPT_PATH" \
                "$ninja" "$forward_message" task_supplement gunshi; then
            echo "[inbox_write] WARN: gunshi review forward failed for ${ninja}" >&2
        fi
    done < <(list_active_ninjas)
}

inbox_append_message_fast_locked() {
    local inbox_file="$1"
    local message_block="$2"

    if inbox_is_empty_file "$inbox_file"; then
        printf 'messages:\n%s' "$message_block" > "$inbox_file"
        return 0
    fi

    printf '%s' "$message_block" >> "$inbox_file"
}

inbox_append_message_locked() {
    local inbox_file="$1"
    local message_block="$2"
    local -a unread_records=() read_records=() kept_records=()
    local i start_idx=0 existing_count=0

    if inbox_is_empty_file "$inbox_file"; then
        printf 'messages:\n%s' "$message_block" > "$inbox_file"
        return 0
    fi

    existing_count=$(grep -c '^- ' "$inbox_file" 2>/dev/null || true)
    if (( existing_count < 50 )); then
        printf '%s' "$message_block" >> "$inbox_file"
        return 0
    fi

    inbox_collect_records "$inbox_file"
    INBOX_RECORDS+=("$message_block")
    INBOX_RECORD_READS+=("false")

    if (( ${#INBOX_RECORDS[@]} > 50 )); then
        for ((i=0; i<${#INBOX_RECORDS[@]}; i++)); do
            if [[ "${INBOX_RECORD_READS[$i],,}" == "true" ]]; then
                read_records+=("${INBOX_RECORDS[$i]}")
            else
                unread_records+=("${INBOX_RECORDS[$i]}")
            fi
        done
        if (( ${#read_records[@]} > 30 )); then
            start_idx=$(( ${#read_records[@]} - 30 ))
        fi
        kept_records=("${unread_records[@]}" "${read_records[@]:start_idx}")
        inbox_write_records "$inbox_file" "${kept_records[@]}"
        return 0
    fi

    inbox_write_records "$inbox_file" "${INBOX_RECORDS[@]}"
}

inbox_extract_report_paths() {
    local report_path="$1"
    [[ -f "$report_path" ]] || return 0

    awk '
        BEGIN { in_files = 0 }
        /^files_modified:[[:space:]]*$/ { in_files = 1; next }
        in_files {
            if ($0 ~ /^  - path:[[:space:]]*/) {
                line = $0
                sub(/^  - path:[[:space:]]*/, "", line)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
                print line
                next
            }
            if ($0 ~ /^  - [^[:space:]][^:]*$/) {
                line = $0
                sub(/^  - /, "", line)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
                print line
                next
            }
            if ($0 ~ /^  [^[:space:]-][^:]*:/ || $0 !~ /^  /) {
                exit
            }
        }
    ' "$report_path" | while IFS= read -r _path; do
        inbox_yaml_strip_quotes "$_path"
        printf '\n'
    done
}

inbox_extract_task_paths() {
    local task_path="$1"
    local raw_values="" raw_entry=""
    [[ -f "$task_path" ]] || return 0

    for _field_name in target_path files; do
        raw_values=$(inbox_yaml_field_get "$task_path" "$_field_name" "")
        [[ -z "${raw_values//[[:space:]]/}" ]] && continue
        IFS=',' read -ra _value_list <<< "$raw_values"
        for raw_entry in "${_value_list[@]}"; do
            raw_entry="$(inbox_yaml_strip_quotes "$raw_entry")"
            [[ -n "${raw_entry//[[:space:]]/}" ]] && printf '%s\n' "$raw_entry"
        done
    done
}

task_has_related_lessons() {
    local task_path="$1"
    awk '
        BEGIN { in_block = 0 }
        /^  related_lessons:[[:space:]]*$/ { in_block = 1; next }
        in_block {
            if ($0 ~ /^  - id:[[:space:]]*/) {
                found = 1
                exit
            }
            if ($0 ~ /^  [^[:space:]-][^:]*:/ || $0 !~ /^  /) {
                exit
            }
        }
        END { exit(found ? 0 : 1) }
    ' "$task_path"
}

extract_universal_lessons() {
    local lessons_file="$1"
    [[ -f "$lessons_file" ]] || return 0

    awk '
        function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
        function unquote(s) {
            s = trim(s)
            if (s ~ /^'\''.*'\''$/) {
                sub(/^'\''/, "", s)
                sub(/'\''$/, "", s)
                gsub(/'\'''\''/, "'\''", s)
            } else if (s ~ /^".*"$/) {
                sub(/^"/, "", s)
                sub(/"$/, "", s)
            }
            return s
        }
        function flush() {
            if (lesson_id != "" && universal == 1 && retired == 0 && status != "deprecated") {
                out_summary = summary
                out_detail = detail
                if (out_summary == "") out_summary = title
                if (out_detail == "") out_detail = content
                if (out_detail == "") out_detail = out_summary
                print lesson_id "\t" out_summary "\t" out_detail
            }
            lesson_id = title = summary = detail = content = status = ""
            universal = retired = in_tags = 0
        }
        /^lessons:[[:space:]]*$/ { in_lessons = 1; next }
        !in_lessons { next }
        /^- id:[[:space:]]*/ {
            flush()
            line = $0
            sub(/^- id:[[:space:]]*/, "", line)
            lesson_id = unquote(line)
            next
        }
        lesson_id == "" { next }
        /^  title:[[:space:]]*/ {
            line = $0
            sub(/^  title:[[:space:]]*/, "", line)
            title = unquote(line)
            next
        }
        /^  summary:[[:space:]]*/ {
            line = $0
            sub(/^  summary:[[:space:]]*/, "", line)
            summary = unquote(line)
            next
        }
        /^  detail:[[:space:]]*/ {
            line = $0
            sub(/^  detail:[[:space:]]*/, "", line)
            detail = unquote(line)
            next
        }
        /^  content:[[:space:]]*/ {
            line = $0
            sub(/^  content:[[:space:]]*/, "", line)
            content = unquote(line)
            next
        }
        /^  status:[[:space:]]*/ {
            line = $0
            sub(/^  status:[[:space:]]*/, "", line)
            status = tolower(unquote(line))
            next
        }
        /^  retired:[[:space:]]*true([[:space:]]|$)/ {
            retired = 1
            next
        }
        /^  tags:[[:space:]]*$/ {
            in_tags = 1
            next
        }
        in_tags && /^  - / {
            line = $0
            sub(/^  - /, "", line)
            if (tolower(unquote(line)) == "universal") {
                universal = 1
            }
            next
        }
        in_tags && !/^  - / { in_tags = 0 }
        !/^  / {
            flush()
            in_lessons = 0
        }
        END { flush() }
    ' "$lessons_file"
}

inject_universal_lessons_if_missing() {
    local task_path="$1"
    local project_id="$2"
    local stripped_file="" tmp_file="" lessons_file=""
    local -a lesson_sources=() selected_lessons=()
    local -A seen_lessons=()
    local lesson_id="" lesson_summary="" lesson_detail=""

    task_has_related_lessons "$task_path" && {
        echo "OK: related_lessons already injected"
        return 0
    }

    lesson_sources+=("$SCRIPT_DIR/projects/${project_id}/lessons_archive.yaml")
    lesson_sources+=("$SCRIPT_DIR/projects/${project_id}/lessons.yaml")
    if [[ "$project_id" != "infra" ]]; then
        lesson_sources+=("$SCRIPT_DIR/projects/infra/lessons_archive.yaml")
        lesson_sources+=("$SCRIPT_DIR/projects/infra/lessons.yaml")
    fi

    for lessons_file in "${lesson_sources[@]}"; do
        [[ -f "$lessons_file" ]] || continue
        while IFS=$'\t' read -r lesson_id lesson_summary lesson_detail; do
            [[ -z "$lesson_id" || -n "${seen_lessons[$lesson_id]:-}" ]] && continue
            seen_lessons["$lesson_id"]=1
            selected_lessons+=("$lesson_id"$'\t'"$lesson_summary"$'\t'"$lesson_detail")
            (( ${#selected_lessons[@]} >= 10 )) && break 2
        done < <(extract_universal_lessons "$lessons_file")
    done

    if (( ${#selected_lessons[@]} == 0 )); then
        echo "WARN: no universal lessons found"
        return 0
    fi

    stripped_file=$(mktemp "${task_path}.strip.XXXXXX")
    awk '
        BEGIN { skip = 0 }
        /^  related_lessons:[[:space:]]*$/ {
            skip = 1
            next
        }
        skip {
            if ($0 ~ /^  [^[:space:]-][^:]*:/ || $0 !~ /^  /) {
                skip = 0
            } else {
                next
            }
        }
        { print }
    ' "$task_path" > "$stripped_file"

    tmp_file=$(mktemp "${task_path}.XXXXXX.tmp")
    cat "$stripped_file" > "$tmp_file"
    rm -f "$stripped_file"
    printf '  related_lessons:\n' >> "$tmp_file"
    local lesson_entry
    for lesson_entry in "${selected_lessons[@]}"; do
        IFS=$'\t' read -r lesson_id lesson_summary lesson_detail <<< "$lesson_entry"
        {
            printf "  - id: '%s'\n" "${lesson_id//\'/\'\'}"
            printf "    summary: '%s'\n" "${lesson_summary//\'/\'\'}"
            printf "    detail: '%s'\n" "${lesson_detail//\'/\'\'}"
        } >> "$tmp_file"
    done
    mv "$tmp_file" "$task_path"
    echo "INJECTED: ${#selected_lessons[@]} universal lessons (safety net)"
}

TARGET="$1"
CONTENT="$2"
TYPE="${3:-wake_up}"
FROM="${4:-unknown}"
ACTION="${5:-}"

# Fast path: profiling/usage queries should not pay the agent-config cost.
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

# Validate arguments
if [ -z "$TARGET" ] || [ -z "$CONTENT" ]; then
    usage >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

if [[ "$TARGET" == cmd_* ]]; then
    echo "ERROR: 第1引数はtarget_agent（例: karo, hanzo）。cmd_idではない。" >&2
    usage >&2
    echo "受け取った引数: $*" >&2
    exit 1
fi

if [ -z "$ACTION" ]; then
    echo "[inbox_write] WARN: action omitted; writing message without action field for backward compatibility" >&2
fi

# HIGH-2: パストラバーサル防止 + sender/target制約
# Common path: 静的役職 + queue/tasks|inbox の実在確認だけで判定できる場合は
# agent_config.sh を読まない。fallback時のみロードする。
if [ "${INBOX_WRITE_TEST:-}" != "1" ]; then
    valid_target=0
    if known_agent_from_fs "$TARGET"; then
        valid_target=1
        ALLOWED_TARGETS="shogun karo gunshi + known queue agents"
    else
        ensure_agent_config_loaded
        if type get_allowed_targets &>/dev/null; then
            ALLOWED_TARGETS=$(get_allowed_targets)
            for allowed in $ALLOWED_TARGETS; do
                if [ "$TARGET" = "$allowed" ]; then
                    valid_target=1
                    break
                fi
            done
        fi
    fi
    if [ "$valid_target" -eq 0 ]; then
        echo "ERROR: Invalid target agent: '$TARGET'. Allowed: ${ALLOWED_TARGETS:-none}" >&2
        exit 1
    fi

    is_ninja_sender=0
    if sender_is_ninja_from_fs "$FROM"; then
        is_ninja_sender=1
    elif [ "$TARGET" = "shogun" ]; then
        ensure_agent_config_loaded
        for ninja in $NINJA_NAMES; do
            if [ "$FROM" = "$ninja" ]; then
                is_ninja_sender=1
                break
            fi
        done
    fi

    if [ "$is_ninja_sender" -eq 1 ] && [ "$TARGET" = "shogun" ]; then
        echo "ERROR: Ninja cannot send inbox to shogun directly. Use karo as relay." >&2
        exit 1
    fi

    if [ "$FROM" = "ninja_monitor" ] && [ "$TARGET" != "karo" ] && [ "$TARGET" != "shogun" ]; then
        echo "ERROR: ninja_monitor can send only to karo or shogun." >&2
        exit 1
    fi
fi

INBOX="$SCRIPT_DIR/queue/inbox/${TARGET}.yaml"
LOCKFILE="$(lock_path "$INBOX")"

# Initialize inbox if not exists
if [ ! -f "$INBOX" ]; then
    mkdir -p "$(dirname "$INBOX")"
    echo "messages: []" > "$INBOX"
fi

# Generate message ID and timestamp using bash builtins to avoid subprocess overhead
printf -v _msg_stamp '%(%Y%m%d_%H%M%S)T' -1
printf -v _msg_rand '%04x%04x' "$RANDOM" "$RANDOM"
MSG_ID="msg_${_msg_stamp}_$$_${_msg_rand}"
printf -v TIMESTAMP '%(%Y-%m-%dT%H:%M:%S)T' -1

# Pre-action auto-capture: 将軍→エージェント送信時、送信先ペインの現在状態を送信前に自動表示+ログ
# 目的: 「観察なき行動」を構造的に防止（知性の外部化原則 2026-03-21）
if [ "${INBOX_WRITE_TEST:-}" != "1" ] && { [ "$FROM" = "shogun" ] || [ "$FROM" = "karo" ]; }; then
    _pane_idx=""
    while IFS=' ' read -r _idx _aid; do
        if [ "$_aid" = "$TARGET" ]; then
            _pane_idx="$_idx"
            break
        fi
    done < <(tmux list-panes -t shogun:agents -F '#{pane_index} #{@agent_id}' 2>/dev/null || true)

    if [ -n "$_pane_idx" ]; then
        _capture=$(tmux capture-pane -t "shogun:agents.${_pane_idx}" -p 2>/dev/null | tail -8 || true)
        echo "[pre-send capture] ${TARGET} pane state BEFORE message:"
        echo "$_capture"
        echo "★10回問い: このアクションを10回繰り返したら正の複利か負の複利か？"
        echo "★前提問い: この指示に含まれる数値・条件は自分で確認したか？出典は？中継元の主張を鵜呑みにしていないか？"
        # CTX:0%検知 — task_assigned送信先がCTX:0%なら反応しない可能性を警告
        if [ "$TYPE" = "task_assigned" ]; then
            _ctx_val=$(echo "$_capture" | grep -oP 'CTX:\K[0-9]+' | tail -1)
            if [ "${_ctx_val:-99}" = "0" ]; then
                echo "⚠⚠⚠ WARNING: ${TARGET} CTX:0% — STALL高リスク。30秒後にペイン確認せよ ⚠⚠⚠"
            fi
        fi
        echo "---"
        # Persistent log (survives /clear, enables post-mortem)
        _logdir="$SCRIPT_DIR/logs"
        mkdir -p "$_logdir"
        printf '%s [%s→%s type=%s] pane:\n%s\n---\n' \
            "$TIMESTAMP" "$FROM" "$TARGET" "$TYPE" "$_capture" \
            >> "$_logdir/shogun_action_log.txt" 2>/dev/null || true
    fi
fi

# Lesson injection safety net: type=task_assigned → 教訓注入チェック
# 目的: deploy_task.sh未使用時でも教訓が忍者に届くことを保証（ラルフループ断絶防止）
if [ "$TYPE" = "task_assigned" ]; then
    NINJA_TASK="$SCRIPT_DIR/queue/tasks/${TARGET}.yaml"
    if [ -f "$NINJA_TASK" ]; then
        TASK_LOCKFILE="$(lock_path "$NINJA_TASK")"
        LESSON_CHECK=$(
            (
                flock -w 5 200 || { echo "[lesson_safety_net] WARN: flock timeout on ${TARGET} task YAML, skipping lesson injection" >&2; exit 1; }
                project_id=$(inbox_yaml_field_get "$NINJA_TASK" "project" "infra")
                inject_universal_lessons_if_missing "$NINJA_TASK" "${project_id:-infra}"
            ) 200>"$TASK_LOCKFILE" 2>&1 || true)
        if [ -n "$LESSON_CHECK" ]; then
            echo "[lesson_safety_net] $LESSON_CHECK" >&2
        fi
    fi
fi

# cmd_new gate: type=cmd_new → cmd_save.sh gate照合
# 目的: gate BLOCK中のcmd委任を防止（将軍がcmd_delegate.shを迂回してinbox_write直送信する経路を封鎖）
# 原因事故: cmd_2004でcmd_save.sh BLOCK中に手動inbox_writeで家老に送信→gate未通過cmdが配備された
if [ "$TYPE" = "cmd_new" ]; then
    # contentからcmd_idを抽出（"cmd_XXXX"パターン）
    _CMD_NEW_ID=$(echo "$CONTENT" | grep -oP 'cmd_\d+' | head -1 || true)
    if [ -n "$_CMD_NEW_ID" ]; then
        # statusを確認。pendingならgate未通過(cmd_delegate.shはinbox_write前にstatus=delegatedに変更済み)
        _CMD_STATUS=$(awk -v id="$_CMD_NEW_ID" '
            $0 ~ "^  " id ":" { found=1; next }
            found && /^    status:/ { gsub(/.*status:[[:space:]]*/, ""); gsub(/"/, ""); print; exit }
            found && /^  [a-zA-Z]/ { exit }
        ' "$SCRIPT_DIR/queue/shogun_to_karo.yaml" 2>/dev/null)
        if [ -z "$_CMD_STATUS" ]; then
            echo "[cmd_new_gate] BLOCKED: ${_CMD_NEW_ID} がshogun_to_karo.yamlに存在しない" >&2
            exit 1
        fi
        if [ "$_CMD_STATUS" = "pending" ]; then
            echo "" >&2
            echo "==============================" >&2
            echo "[cmd_new_gate] BLOCKED: ${_CMD_NEW_ID} はstatus=pending(gate未通過)" >&2
            echo "[cmd_new_gate] cmd_save.sh→cmd_delegate.shの正規フローでgateを通せ" >&2
            echo "==============================" >&2
            exit 1
        fi
    fi
fi

# Report format gate: type=report_received → 報告YAMLのフォーマット検証
# 目的: 家老の手動修正作業を根絶（karo_workarounds 5件連続同一問題を自動化×強制で解消）
if [ "$TYPE" = "report_received" ]; then
    # Find report YAML path from task YAML
    ensure_agent_config_loaded
    is_ninja_reporter=0
    for ninja in $NINJA_NAMES; do
        if [ "$FROM" = "$ninja" ]; then
            is_ninja_reporter=1
            break
        fi
    done

    if [ "$is_ninja_reporter" -eq 1 ]; then
        TASK_YAML="$SCRIPT_DIR/queue/tasks/${FROM}.yaml"
        if [ -f "$TASK_YAML" ]; then
            REPORT_PATH=$(inbox_yaml_field_get "$TASK_YAML" "report_path" "")

            FULL_REPORT=""
            if [ -n "$REPORT_PATH" ]; then
                FULL_REPORT="$SCRIPT_DIR/$REPORT_PATH"
            else
                # Fallback: report_path未設定 → queue/reports/{from}_report_{cmd_id}*.yaml を検索
                CMD_ID=$(inbox_yaml_field_get "$TASK_YAML" "parent_cmd" "")
                if [ -n "$CMD_ID" ]; then
                    FALLBACK=$(find "$SCRIPT_DIR/queue/reports" -maxdepth 1 -name "${FROM}_report_${CMD_ID}*.yaml" -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2- || true)
                    if [ -n "$FALLBACK" ]; then
                        FULL_REPORT="$FALLBACK"
                        echo "[report_format_gate] fallback: report_path未設定 → $(basename "$FALLBACK") を検出" >&2
                    else
                        echo "[report_format_gate] BLOCKED: 報告YAMLが見つからない: queue/reports/${FROM}_report_${CMD_ID}*.yaml" >&2
                        exit 1
                    fi
                else
                    echo "[report_format_gate] BLOCKED: 報告YAMLが見つからない: report_path未設定 + parent_cmd未設定 (ninja: ${FROM})" >&2
                    exit 1
                fi
            fi

            if [ -n "$FULL_REPORT" ]; then
                if [ -f "$FULL_REPORT" ]; then
                    # Phase 1: 機械的フォーマット自動修正（忍者ペインで局所免疫）
                    AUTOFIX_RESULT=$("$SCRIPT_DIR/scripts/gates/gate_report_autofix.sh" "$FULL_REPORT" 2>&1 || true)
                    if echo "$AUTOFIX_RESULT" | grep -q "^AUTO-FIXED"; then
                        echo "[report_autofix] $AUTOFIX_RESULT" >&2
                    fi
                    # Phase 2: フォーマット検証（auto-fix後に実行）
                    GATE_RESULT=$("$SCRIPT_DIR/scripts/gates/gate_report_format.sh" "$FULL_REPORT" 2>&1 || true)
                    if echo "$GATE_RESULT" | grep -q "^FAIL"; then
                        # GP-071: テンプレート状態検出 — 忍者がまだ記入中ならquality_fix_requestスキップ
                        # FILL_THIS残存 or verdict未記入 → テンプレート状態（忍者が書いている途中）
                        # verdict記入済み + FAIL → 本物の品質問題 → 軍師に転送
                        IS_TEMPLATE=$(report_yaml_is_template "$FULL_REPORT")

                        if [ "$IS_TEMPLATE" = "yes" ]; then
                            # GP-071改: テンプレート状態でreport_received = 報告未完了のまま完了報告 = BLOCK
                            # 旧: exit 0でバイパス → 不完全報告がkaroに届く → workaround（消火構造）
                            # 新: exit 1でBLOCK → 忍者がフィールドを埋めてから再送信（品質向上）
                            echo "" >&2
                            echo "==============================" >&2
                            echo "[report_format_gate] BLOCKED: 報告が未完了 (ninja: ${FROM})" >&2
                            echo "[report_format_gate] verdict未記入 or FILL_THIS残存。フィールドを全て埋めてから再送信せよ" >&2
                            echo "[report_format_gate] FAIL理由:" >&2
                            while IFS= read -r _gate_line; do
                                echo "  $_gate_line" >&2
                            done <<< "$GATE_RESULT"
                            echo "" >&2
                            echo "[report_format_gate] 修正後に再送信せよ: bash scripts/inbox_write.sh karo \"報告完了\" report_received ${FROM}" >&2
                            echo "==============================" >&2
                            exit 1
                        fi

                        # Phase 3: 品質問題→軍師に監視通知（第二層分離）
                        # GP-102: 修正指示→監視通知に変更(消火→品質向上)
                        # 旧: 軍師に修正を指示 → 軍師が代行修正 = 消火の移転(忍者が学ばない)
                        # 新: 軍師に監視通知のみ → 忍者がBLOCKエラーを見て自分で修正 → 学習ループ回転
                        GUNSHI_INBOX="$SCRIPT_DIR/queue/inbox/gunshi.yaml"
                        ROUTE_TS=$(date -Is)
                        ROUTE_ID="msg_$(date +%s%N | head -c 16)"
                        (
                            flock -w 5 200 || { echo "[report_quality_route] WARN: flock timeout for gunshi inbox, skipping quality notification" >&2; exit 1; }
                            if [ ! -f "$GUNSHI_INBOX" ]; then
                                mkdir -p "$(dirname "$GUNSHI_INBOX")"
                                printf 'messages: []\n' > "$GUNSHI_INBOX"
                            fi
                            _gunshi_msg="$(inbox_build_message_block \
                                content "【監視通知】忍者${FROM}の報告YAMLにgate FAIL。忍者にBLOCK済み。忍者が自分で修正して再送信する。軍師は直接修正するな(消火行為)。パターン分析用の記録。" \
                                from "system" \
                                id "$ROUTE_ID" \
                                read "false" \
                                timestamp "$ROUTE_TS" \
                                type "quality_monitor" \
                                gate_errors "$GATE_RESULT" \
                                original_ninja "$FROM" \
                                report_path "$FULL_REPORT")"$'\n'
                            inbox_append_message_locked "$GUNSHI_INBOX" "$_gunshi_msg"
                        ) 200>"$(lock_path "$GUNSHI_INBOX")" \
                            && echo "[report_quality_route] 品質問題を軍師に監視通知済み(修正は忍者が行う)" >&2 \
                            || echo "[report_quality_route] WARN: gunshi notification skipped (flock timeout)" >&2
                        # BLOCK: verdict記入済み+gate FAIL → 忍者が修正して再送信するまでkaroに届けない
                        echo "" >&2
                        echo "==============================" >&2
                        echo "[report_format_gate] BLOCKED: 報告YAML品質問題 (ninja: ${FROM})" >&2
                        echo "[report_format_gate] FAIL理由:" >&2
                        while IFS= read -r _gate_line; do
                            echo "  $_gate_line" >&2
                        done <<< "$GATE_RESULT"
                        echo "" >&2
                        echo "[report_format_gate] 修正方法: bash scripts/report_field_set.sh <report_path> <key> <value>" >&2
                        echo "[report_format_gate] 修正例:" >&2
                        echo "  bash scripts/report_field_set.sh $REPORT_PATH verdict PASS" >&2
                        echo "  bash scripts/report_field_set.sh $REPORT_PATH lesson_candidate.found false" >&2
                        echo "  bash scripts/report_field_set.sh $REPORT_PATH lesson_candidate.no_lesson_reason '既知のL084と同じパターン'" >&2
                        echo "  bash scripts/report_field_set.sh $REPORT_PATH result.summary '実装完了'" >&2
                        echo "==============================" >&2
                        echo "[report_format_gate] 修正後に再送信せよ: bash scripts/inbox_write.sh karo \"報告完了\" report_received ${FROM}" >&2
                        exit 1
                    fi
                else
                    echo "[report_format_gate] BLOCKED: 報告YAMLが見つからない: $FULL_REPORT" >&2
                    exit 1
                fi
            fi

            # Git uncommitted check: 報告YAMLのfiles_modified + task YAMLのtarget_pathを確認
            # cmd_1296教訓: 全repoではなく忍者が申告したファイルのみチェック（運用ファイル誤検知防止）
            # サイクル2: WARNING→BLOCK昇格。commit漏れは忍者ペインで止める（局所免疫）
            GIT_CHECK_PATHS=$(
                (
                    inbox_extract_report_paths "$FULL_REPORT"
                    inbox_extract_task_paths "$TASK_YAML"
                ) | awk '!seen[$0]++'
            )

            if [ -n "$GIT_CHECK_PATHS" ]; then
                mapfile -t _check_paths <<< "$GIT_CHECK_PATHS"
                # プロジェクトリポジトリの解決: task YAMLのproject:からprojects/{project}.yamlのpath:を参照
                # cmd_1412教訓: SCRIPT_DIR(multi-agent-shogun)でDM-signalファイルをチェックしても検出不能
                GIT_REPO_DIR="$SCRIPT_DIR"
                if [ -n "$TASK_YAML" ] && [ -f "$TASK_YAML" ]; then
                    _proj=$(grep -m1 '^\s*project:' "$TASK_YAML" 2>/dev/null | sed 's/.*project:[[:space:]]*//' | sed "s/['\"]//g" | tr -d '[:space:]' || true)
                    if [ -n "$_proj" ] && [ -f "$SCRIPT_DIR/projects/${_proj}.yaml" ]; then
                        _proj_path=$(grep -m1 '^\s*path:' "$SCRIPT_DIR/projects/${_proj}.yaml" 2>/dev/null | sed 's/.*path:[[:space:]]*//' | sed "s/['\"]//g" | sed 's/[[:space:]]*$//' || true)
                        if [ -n "$_proj_path" ] && [ -d "$_proj_path/.git" ]; then
                            GIT_REPO_DIR="$_proj_path"
                        fi
                    fi
                fi
                UNCOMMITTED=$(git -C "$GIT_REPO_DIR" status --porcelain -- "${_check_paths[@]}" 2>/dev/null || true)
                if [ -n "$UNCOMMITTED" ]; then
                    echo "[git_uncommitted_gate] BLOCKED: 未commitファイルあり (ninja: ${FROM})" >&2
                    while IFS= read -r _uline; do
                        echo "  $_uline" >&2
                    done <<< "$UNCOMMITTED"
                    echo "[git_uncommitted_gate] git add + git commitを実行してから報告せよ" >&2
                    exit 1
                fi
            fi
        fi
    fi
fi

# Atomic write with flock (3 retries)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 5 200 || exit 1

        if [ -n "$ACTION" ]; then
            _msg_block="$(inbox_build_message_block \
                action "$ACTION" \
                content "$CONTENT" \
                from "$FROM" \
                id "$MSG_ID" \
                read "false" \
                timestamp "$TIMESTAMP" \
                type "$TYPE")"$'\n'
        else
            _msg_block="$(inbox_build_message_block \
                content "$CONTENT" \
                from "$FROM" \
                id "$MSG_ID" \
                read "false" \
                timestamp "$TIMESTAMP" \
                type "$TYPE")"$'\n'
        fi
        inbox_append_message_locked "$INBOX" "$_msg_block" || exit 1

    ) 200>"$LOCKFILE"; then
        # Success — inbox message persisted

        # Hook: report_received from ninja → auto-update task YAML to done
        if [ "$TYPE" = "report_received" ]; then
            ensure_agent_config_loaded
            is_ninja=0
            for ninja in $NINJA_NAMES; do
                if [ "$FROM" = "$ninja" ]; then
                    is_ninja=1
                    break
                fi
            done

            if [ "$is_ninja" -eq 1 ]; then
                TASK_YAML="$SCRIPT_DIR/queue/tasks/${FROM}.yaml"
                if [ -f "$TASK_YAML" ]; then
                    # Report YAML existence verification before done transition (cmd_813)
                    REPORT_FILENAME=$(inbox_yaml_field_get "$TASK_YAML" "report_filename" "")
                    if [ -z "$REPORT_FILENAME" ]; then
                        _parent_cmd=$(inbox_yaml_field_get "$TASK_YAML" "parent_cmd" "")
                        if [ -n "$_parent_cmd" ]; then
                            REPORT_FILENAME="${FROM}_report_${_parent_cmd}.yaml"
                        fi
                    fi

                    report_found=0
                    if [ -n "$REPORT_FILENAME" ]; then
                        if [ -f "$SCRIPT_DIR/queue/reports/$REPORT_FILENAME" ]; then
                            report_found=1
                        elif [ -f "$SCRIPT_DIR/queue/archive/reports/$REPORT_FILENAME" ]; then
                            report_found=1
                        else
                            # Archive files may have date suffix
                            base="${REPORT_FILENAME%.yaml}"
                            shopt -s nullglob
                            archived=("$SCRIPT_DIR/queue/archive/reports/${base}"_*.yaml)
                            shopt -u nullglob
                            if [ "${#archived[@]}" -gt 0 ]; then
                                report_found=1
                            fi
                        fi
                    fi

                    if [ "$report_found" -eq 0 ]; then
                        echo "[inbox_write] auto-done BLOCKED: report YAML not found: ${REPORT_FILENAME:-unknown} (ninja: $FROM)" >&2
                    else
                        # Check current status — don't overwrite terminal states
                        CURRENT_STATUS=$(inbox_yaml_field_get "$TASK_YAML" "status" "")
                        case "$CURRENT_STATUS" in
                            done|failed|blocked) ;;
                            *)
                                # yaml_field_set.sh has its own flock on ${yaml_file}.lock.
                                # Outer flock on same lockfile via different fd = self-deadlock
                                # on WSL2/DrvFs (POSIX flock treats different open file descriptions
                                # independently; same-process exclusive vs exclusive = blocked).
                                if ! bash "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh" "$TASK_YAML" task status "done" 2>/dev/null; then
                                    echo "[inbox_write] auto-done: task status更新失敗（非致命的。メッセージ送信は成功済み）" >&2
                                fi
                                ;;
                        esac
                    fi
                fi
            fi
        fi

        # GP-133: report_review_result from gunshi → review_gate.done placeholder上書き
        # 軍師のLGTM verdict受信時にplaceholderを正式版に上書きし、archive_completed.shが報告をアーカイブ可能にする
        if [ "$TYPE" = "report_review_result" ] && [ "$FROM" = "gunshi" ]; then
            # メッセージからcmd_idとverdictを抽出
            _rr_cmd_id=$(echo "$CONTENT" | grep -oP 'cmd_\d+' | head -1 || true)
            _rr_verdict=$(echo "$CONTENT" | grep -oP 'verdict: \K(LGTM|FAIL)' | head -1 || true)
            if [ -n "$_rr_cmd_id" ] && [ "$_rr_verdict" = "LGTM" ]; then
                _rr_gate_file="$SCRIPT_DIR/queue/gates/${_rr_cmd_id}/review_gate.done"
                if [ -f "$_rr_gate_file" ] && grep -q "source: deploy_preflight" "$_rr_gate_file" 2>/dev/null; then
                    cat > "$_rr_gate_file" <<REVIEWEOF
timestamp: $(date '+%Y-%m-%dT%H:%M:%S')
source: gunshi_review
result: LGTM
note: 軍師レビュー完了。placeholderから上書き(GP-133)。
REVIEWEOF
                    echo "[inbox_write] review_gate.done updated: ${_rr_cmd_id} (placeholder→gunshi_review LGTM)" >&2
                fi
            fi
        fi

        # 軍師review_resultのみ、配備中忍者へ補足として自動forwardする
        # task_supplement/review_feedback 等の二次通知はforwardしない（再帰ループ防止）
        if [ "$TYPE" = "review_result" ] && [ "$FROM" = "gunshi" ] && [ "$TARGET" = "karo" ]; then
            forward_gunshi_review_result_to_active_ninjas "$CONTENT"
        fi

        maybe_verify_codex_delivery "$TARGET" "$MSG_ID" "$TYPE"
        exit 0
    else
        # Lock timeout or error
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[inbox_write] Lock timeout for $INBOX (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[inbox_write] Failed to acquire lock after $max_attempts attempts for $INBOX (target=$TARGET, from=$FROM)" >&2
            bash "$SCRIPT_DIR/scripts/ntfy.sh" "[inbox_write] FAIL: lock取得失敗 target=$TARGET from=$FROM" 2>/dev/null || true
            exit 1
        fi
    fi
done
