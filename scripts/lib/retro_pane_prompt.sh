#!/usr/bin/env bash
# Deliver retrospective prompts verbatim to an explicitly idle agent pane.

RETRO_PANE_PROMPT='この作業で時間がかかった原因を分析し、利他の精神で調査を行いインフラバグの疑いとして家老に報告せよ'
RETRO_PANE_PROMPT_SHA256='b605951bd574d99027a6a1e496aabd5d4e1e67d6d8a4be1b88f4e6472595f84f'

retro_pane_prompt_key() {
    local target="$1" event_id="$2"
    printf '%s\0%s' "$target" "$event_id" | sha256sum | cut -d' ' -f1
}

retro_pane_prompt_resolve() {
    local target="$1"
    if [ -n "${RETRO_PANE_TARGET:-}" ]; then
        printf '%s\n' "$RETRO_PANE_TARGET"
        return 0
    fi
    tmux list-panes -a -F '#{session_name}:#{window_name}.#{pane_index}|#{@agent_id}' 2>/dev/null |
        awk -F'|' -v wanted="$target" '$2 == wanted { print $1; found=1; exit } END { if (!found) exit 1 }'
}

retro_pane_prompt_idle() {
    local pane="$1" target="$2"
    if [ -n "${RETRO_PANE_IDLE_CHECK:-}" ]; then
        "$RETRO_PANE_IDLE_CHECK" "$pane" "$target"
        return
    fi
    local state dead
    state=$(tmux display-message -t "$pane" -p '#{@agent_state}' 2>/dev/null) || return 1
    dead=$(tmux display-message -t "$pane" -p '#{pane_dead}' 2>/dev/null) || return 1
    [ "$dead" = 0 ] && [ "$state" = idle ]
}

retro_pane_prompt_seen() {
    local pane="$1" target="$2"
    if [ -n "${RETRO_PANE_SEEN_CHECK:-}" ]; then
        "$RETRO_PANE_SEEN_CHECK" "$pane" "$target" "$RETRO_PANE_PROMPT"
        return
    fi
    local attempt
    for attempt in 1 2 3 4 5; do
        if tmux capture-pane -t "$pane" -p -J -S -30 2>/dev/null |
            grep -Fq -- "$RETRO_PANE_PROMPT"; then
            return 0
        fi
        [ "$attempt" -eq 5 ] || sleep 0.1
    done
    return 1
}

retro_pane_prompt_deliver() {
    local root="$1" target="$2" event_id="$3" from="$4"
    local state_dir="${RETRO_PANE_STATE_DIR:-${RETRO_VERBATIM_STATE_DIR:-$root/queue/retro/pane_prompt}}"
    local ledger="${RETRO_PANE_LEDGER:-${RETRO_VERBATIM_LOG:-$root/logs/retro_pane_prompt.tsv}}"
    local key claim pane expected_sha actual_sha tmux_bin="${RETRO_PANE_TMUX_BIN:-tmux}"

    mkdir -p "$state_dir" "$(dirname "$ledger")"
    key=$(retro_pane_prompt_key "$target" "$event_id")
    claim="$state_dir/$key.claimed"
    if ! mkdir "$claim" 2>/dev/null; then
        printf '%s\tdeduplicated\t%s\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" "$key" >> "$ledger"
        return 0
    fi

    pane=$(retro_pane_prompt_resolve "$target") || {
        rmdir "$claim" 2>/dev/null || true
        printf '%s\tfailed_no_pane\t%s\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" "$key" >> "$ledger"
        return 1
    }
    if ! retro_pane_prompt_idle "$pane" "$target"; then
        rmdir "$claim" 2>/dev/null || true
        printf '%s\tfailed_busy\t%s\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" "$key" >> "$ledger"
        return 1
    fi

    expected_sha="$RETRO_PANE_PROMPT_SHA256"
    actual_sha=$(printf '%s' "$RETRO_PANE_PROMPT" | sha256sum | cut -d' ' -f1)
    if [ "$actual_sha" != "$expected_sha" ] ||
       ! "$tmux_bin" send-keys -t "$pane" -l -- "$RETRO_PANE_PROMPT" ||
       ! "$tmux_bin" send-keys -t "$pane" Enter; then
        rmdir "$claim" 2>/dev/null || true
        printf '%s\tfailed_send\t%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" "$key" "$expected_sha" >> "$ledger"
        return 1
    fi
    if ! retro_pane_prompt_seen "$pane" "$target"; then
        # send-keys and Enter already succeeded.  The pane check is only an
        # observation and must never turn a completed send back into a retry:
        # wrapped Codex input is not byte-for-byte visible in capture-pane.
        printf '%s\tdelivered_unverified\t%s\t%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" "$key" "$expected_sha" "$pane" >> "$ledger"
        return 0
    fi
    printf '%s\tdelivered_prompt_seen\t%s\t%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" "$key" "$expected_sha" "$pane" >> "$ledger"
}

retro_pane_prompt_enqueue() {
    local root="$1" target="$2" event_id="$3" from="$4"
    local pending_dir="${RETRO_PANE_PENDING_DIR:-${RETRO_VERBATIM_PENDING_DIR:-$root/queue/retro/verbatim_pending}}"
    local key tmp event_file existing existing_target
    mkdir -p "$pending_dir"
    key=$(retro_pane_prompt_key "$target" "$event_id")
    event_file="$pending_dir/$key.event"
    [ -e "$event_file" ] && return 0
    # Bound each target to one outstanding prompt.  A later event remains in
    # the append-only retro ledger/state and can be reconciled there; stacking
    # a second pane prompt while the first is unresolved has no user benefit.
    for existing in "$pending_dir"/*.event "${pending_dir%/verbatim_pending}/verbatim_awaiting_answer"/*.event; do
        [ -f "$existing" ] || continue
        IFS= read -r existing_target < "$existing" || true
        if [ "$existing_target" = "$target" ]; then
            printf '%s\tsuppressed_outstanding\t%s\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" "$key" >> "${RETRO_PANE_LEDGER:-${RETRO_VERBATIM_LOG:-$root/logs/retro_pane_prompt.tsv}}"
            return 0
        fi
    done
    tmp="$event_file.tmp.$$"
    printf '%s\n%s\n%s\n%s\n' "$target" "$event_id" "$from" "$key" > "$tmp"
    mv -n "$tmp" "$event_file" 2>/dev/null || rm -f "$tmp"
}

retro_pane_prompt_async() {
    local root="$1" target="$2" event_id="$3" from="$4"
    # Persist before the detached attempt.  A busy pane or send failure leaves
    # this event for ninja_monitor's next idle cycle; only the claim is released.
    retro_pane_prompt_enqueue "$root" "$target" "$event_id" "$from" || return 1
    ( retro_pane_prompt_deliver "$root" "$target" "$event_id" "$from" ) >/dev/null 2>&1 &
}
