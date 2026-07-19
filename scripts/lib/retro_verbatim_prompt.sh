#!/usr/bin/env bash
# Detached, idempotent delivery of the Lord's verbatim retrospective prompt.

RETRO_VERBATIM_PROMPT='この作業で時間がかかった原因を分析し、利他の精神で調査を行いインフラバグの疑いとして家老に報告せよ'

retro_verbatim_prompt_async() {
    local root="$1" target="$2" event_id="$3" from="$4"
    local state_dir="${RETRO_VERBATIM_STATE_DIR:-$root/queue/retro/verbatim_prompt}"
    local log="${RETRO_VERBATIM_LOG:-$root/logs/retro_verbatim_prompt.log}"
    (
        mkdir -p "$state_dir" "$(dirname "$log")"
        local key marker
        key=$(printf '%s\0%s\0%s' "$target" "$event_id" "$from" | sha256sum | cut -d' ' -f1)
        marker="$state_dir/$key.claimed"
        if ! mkdir "$marker" 2>/dev/null; then
            printf '%s\tdeduplicated\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" >> "$log"
            exit 0
        fi
        if bash "$root/scripts/inbox_write.sh" "$target" "$RETRO_VERBATIM_PROMPT" retro_prompt "$from" analyze_and_report; then
            printf '%s\tdelivered\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" >> "$log"
        else
            rmdir "$marker" 2>/dev/null || true
            printf '%s\tfailed\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" >> "$log"
        fi
    ) >/dev/null 2>&1 &
}
