#!/usr/bin/env bash
# Detached, idempotent delivery of the Lord's verbatim retrospective prompt.

RETRO_VERBATIM_PROMPT='この作業で時間がかかった原因を分析し、利他の精神で調査を行いインフラバグの疑いとして家老に報告せよ'

retro_verbatim_prompt_key() {
    local target="$1" event_id="$2" from="$3"
    local canonical_cmd_context
    canonical_cmd_context=$(printf '%s\n' "$event_id" | grep -oE 'cmd_[A-Za-z0-9_]+' | tail -n 1 || true)
    [ -n "$canonical_cmd_context" ] || canonical_cmd_context="$RETRO_VERBATIM_PROMPT"
    printf '%s\0%s\0%s\0%s' \
        "$target" "$from" "$RETRO_VERBATIM_PROMPT" "$canonical_cmd_context" |
        sha256sum | cut -d' ' -f1
}

retro_verbatim_prompt_deliver() {
    local root="$1" target="$2" event_id="$3" from="$4"
    local state_dir="${RETRO_VERBATIM_STATE_DIR:-$root/queue/retro/verbatim_prompt}"
    local log="${RETRO_VERBATIM_LOG:-$root/logs/retro_verbatim_prompt.log}"
    local key marker

    mkdir -p "$state_dir" "$(dirname "$log")"
    key=$(retro_verbatim_prompt_key "$target" "$event_id" "$from")
    marker="$state_dir/$key.claimed"
    if ! mkdir "$marker" 2>/dev/null; then
        printf '%s\tdeduplicated\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" >> "$log"
        return 0
    fi
    if bash "$root/scripts/inbox_write.sh" "$target" "$RETRO_VERBATIM_PROMPT" retro_prompt "$from" analyze_and_report; then
        printf '%s\tdelivered\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" >> "$log"
        return 0
    fi
    rmdir "$marker" 2>/dev/null || true
    printf '%s\tfailed\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" >> "$log"
    return 1
}

retro_verbatim_prompt_enqueue() {
    local root="$1" target="$2" event_id="$3" from="$4"
    local pending_dir="${RETRO_VERBATIM_PENDING_DIR:-$root/queue/retro/verbatim_pending}"
    local key tmp event_file
    mkdir -p "$pending_dir"
    key=$(retro_verbatim_prompt_key "$target" "$event_id" "$from")
    event_file="$pending_dir/$key.event"
    [ -e "$event_file" ] && return 0
    tmp="$event_file.tmp.$$"
    printf '%s\n%s\n%s\n%s\n' "$target" "$event_id" "$from" "$key" > "$tmp"
    mv -n "$tmp" "$event_file" 2>/dev/null || rm -f "$tmp"
}

retro_verbatim_prompt_async() {
    local root="$1" target="$2" event_id="$3" from="$4"
    local state_dir="${RETRO_VERBATIM_STATE_DIR:-$root/queue/retro/verbatim_prompt}"
    local log="${RETRO_VERBATIM_LOG:-$root/logs/retro_verbatim_prompt.log}"
    (
        retro_verbatim_prompt_deliver "$root" "$target" "$event_id" "$from"
    ) >/dev/null 2>&1 &
}
