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

retro_pane_prompt_enter_delay() {
    local delay="${RETRO_PANE_ENTER_DELAY_SECONDS:-0.5}"
    if [ -n "${RETRO_PANE_SLEEP_CMD:-}" ]; then
        "$RETRO_PANE_SLEEP_CMD" "$delay"
    else
        sleep "$delay"
    fi
}

retro_pane_prompt_reconcile_terminal() {
    local root="$1" event_file="$2"
    [ -f "$event_file" ] || return 1
    python3 - "$root" "$event_file" <<'PY'
import sys
from pathlib import Path

import yaml

root = Path(sys.argv[1])
event_file = Path(sys.argv[2])
fields = event_file.read_text(encoding="utf-8").splitlines()
if len(fields) < 2:
    raise SystemExit(1)
event_id = fields[1]

if event_id.startswith("report_received:"):
    print("report_terminal")
    raise SystemExit(0)

if not event_id.startswith("task_failed:rpt-"):
    raise SystemExit(1)
report_id = event_id.split(":", 2)[1]

try:
    inbox = yaml.safe_load((root / "queue/inbox/gunshi.yaml").read_text(encoding="utf-8")) or {}
except Exception:
    inbox = {}
parent_cmd = ""
for message in inbox.get("messages", []) if isinstance(inbox, dict) else []:
    if isinstance(message, dict) and message.get("report_id") == report_id:
        parent_cmd = str(message.get("parent_cmd") or "")
        break
if not parent_cmd:
    raise SystemExit(1)

try:
    reviews = yaml.safe_load((root / "logs/gunshi_review_log.yaml").read_text(encoding="utf-8")) or []
except Exception:
    reviews = []
for review in reversed(reviews if isinstance(reviews, list) else []):
    if not isinstance(review, dict):
        continue
    verdict = str(review.get("verdict") or "")
    if (review.get("cmd_id") == parent_cmd and review.get("review_type") == "report"
            and verdict in {"PASS", "FAIL"}):
        print(f"review_terminal:{parent_cmd}:{verdict}")
        raise SystemExit(0)
raise SystemExit(1)
PY
}

retro_pane_prompt_reconcile_pending() {
    local root="$1" event_file="$2" target="$3" event_id="$4" reason reconciled_dir ledger
    reason=$(retro_pane_prompt_reconcile_terminal "$root" "$event_file") || return 1
    reconciled_dir="${RETRO_PANE_RECONCILED_DIR:-$root/queue/retro/verbatim_reconciled}"
    ledger="${RETRO_PANE_LEDGER:-${RETRO_VERBATIM_LOG:-$root/logs/retro_pane_prompt.tsv}}"
    mkdir -p "$reconciled_dir" "$(dirname "$ledger")"
    mv "$event_file" "$reconciled_dir/${event_file##*/}"
    printf '%s\treconciled_terminal\t%s\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" "$reason" >> "$ledger"
    printf '%s\n' "$reason"
}

retro_pane_prompt_deliver() {
    local root="$1" target="$2" event_id="$3" from="$4"
    local state_dir="${RETRO_PANE_STATE_DIR:-${RETRO_VERBATIM_STATE_DIR:-$root/queue/retro/pane_prompt}}"
    local ledger="${RETRO_PANE_LEDGER:-${RETRO_VERBATIM_LOG:-$root/logs/retro_pane_prompt.tsv}}"
    local key claim pane expected_sha actual_sha payload payload_sha buffer state_tmp quarantine_state tmux_bin="${RETRO_PANE_TMUX_BIN:-tmux}"

    mkdir -p "$state_dir" "$(dirname "$ledger")"
    key=$(retro_pane_prompt_key "$target" "$event_id")
    claim="$state_dir/$key.claimed"
    if ! mkdir "$claim" 2>/dev/null; then
        if [ -f "$claim/sent" ]; then
            printf '%s\tdeduplicated\t%s\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" "$key" >> "$ledger"
            return 0
        fi
        quarantine_state=$(head -n 1 "$claim/quarantined" 2>/dev/null || true)
        if [ "$quarantine_state" = "paste_succeeded" ] || [ "$quarantine_state" = "input_sha_mismatch" ]; then
            pane=$(retro_pane_prompt_resolve "$target") || return 1
            retro_pane_prompt_idle "$pane" "$target" || return 1
            if ! retro_pane_prompt_enter_delay; then
                printf '%s\tfailed_enter_delay\t%s\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" "$key" >> "$ledger"
                return 1
            fi
            if ! "$tmux_bin" send-keys -t "$pane" Enter; then
                printf '%s\tfailed_enter_recovery\t%s\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" "$key" >> "$ledger"
                return 1
            fi
            state_tmp="$claim/.sent.tmp.$$"
            printf '%s\t%s\n' "$RETRO_PANE_PROMPT_SHA256" "$(date -Iseconds)" > "$state_tmp"
            mv "$state_tmp" "$claim/sent"
            rm -f "$claim/quarantined"
            printf '%s\trecovered_enter\t%s\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" "$key" >> "$ledger"
            return 0
        fi
        printf '%s\tdeduplicated_unconfirmed\t%s\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" "$key" >> "$ledger"
        return 1
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
    buffer="retro-${key:0:24}-$$"
    if [ "$actual_sha" != "$expected_sha" ] ||
       ! printf '%s' "$RETRO_PANE_PROMPT" | "$tmux_bin" load-buffer -b "$buffer" -; then
        rmdir "$claim" 2>/dev/null || true
        printf '%s\tfailed_buffer_load\t%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" "$key" "$expected_sha" >> "$ledger"
        return 1
    fi
    payload=$("$tmux_bin" show-buffer -b "$buffer" 2>/dev/null) || payload=""
    payload_sha=$(printf '%s' "$payload" | sha256sum | cut -d' ' -f1)
    if [ "$payload_sha" != "$expected_sha" ]; then
        "$tmux_bin" delete-buffer -b "$buffer" 2>/dev/null || true
        rmdir "$claim" 2>/dev/null || true
        printf '%s\tfailed_payload_sha\t%s\t%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" "$key" "$expected_sha" "$payload_sha" >> "$ledger"
        return 1
    fi
    if ! "$tmux_bin" paste-buffer -t "$pane" -b "$buffer" -d; then
        "$tmux_bin" delete-buffer -b "$buffer" 2>/dev/null || true
        rmdir "$claim" 2>/dev/null || true
        printf '%s\tfailed_paste\t%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" "$key" "$expected_sha" >> "$ledger"
        return 1
    fi
    state_tmp="$claim/.quarantined.tmp.$$"
    printf '%s\n' "paste_succeeded" > "$state_tmp"
    mv "$state_tmp" "$claim/quarantined"
    if ! retro_pane_prompt_enter_delay; then
        printf '%s\tfailed_enter_delay\t%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" "$key" "$expected_sha" >> "$ledger"
        return 1
    fi
    if ! "$tmux_bin" send-keys -t "$pane" Enter; then
        printf '%s\tfailed_enter\t%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" "$key" "$expected_sha" >> "$ledger"
        return 1
    fi
    state_tmp="$claim/.sent.tmp.$$"
    printf '%s\t%s\n' "$expected_sha" "$(date -Iseconds)" > "$state_tmp"
    mv "$state_tmp" "$claim/sent"
    rm -f "$claim/quarantined"
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
    local retro_queue_dir="${pending_dir%/*}"
    [[ "$pending_dir" == */verbatim_pending ]] && retro_queue_dir="${pending_dir%/verbatim_pending}"
    local backlog_dir="${RETRO_PANE_BACKLOG_DIR:-$retro_queue_dir/verbatim_backlog}"
    local state_dir="${RETRO_PANE_STATE_DIR:-${RETRO_VERBATIM_STATE_DIR:-$root/queue/retro/pane_prompt}}"
    local key tmp event_file existing existing_target pending_lock backlog_file
    mkdir -p "$pending_dir" "$backlog_dir"
    RETRO_PANE_ENQUEUE_DECISION=queued
    pending_lock="${pending_dir%/}.enqueue.lock"
    exec {retro_pending_lock_fd}>"$pending_lock"
    flock -x "$retro_pending_lock_fd"
    key=$(retro_pane_prompt_key "$target" "$event_id")
    event_file="$pending_dir/$key.event"
    backlog_file="$backlog_dir/$key.event"
    if [ -e "$event_file" ] || [ -e "$backlog_file" ] || [ -f "$state_dir/$key.claimed/sent" ]; then
        flock -u "$retro_pending_lock_fd"
        exec {retro_pending_lock_fd}>&-
        RETRO_PANE_ENQUEUE_DECISION=suppressed
        return 0
    fi
    # Bound each target to one visible prompt, but never discard a later event.
    # Answer identity is finalized at the locked append checkpoint of the message
    # queue writer; the durable awaiting/backlog files here are that live identity source.
    for existing in "$pending_dir"/*.event "${pending_dir%/verbatim_pending}/verbatim_awaiting_answer"/*.event; do
        [ -f "$existing" ] || continue
        IFS= read -r existing_target < "$existing" || true
        if [ "$existing_target" = "$target" ]; then
            tmp="$backlog_file.tmp.$$"
            printf '%s\n%s\n%s\n%s\n%s\n' "$target" "$event_id" "$from" "$key" "$(date +%s%N)" > "$tmp"
            mv -n "$tmp" "$backlog_file" 2>/dev/null || rm -f "$tmp"
            printf '%s\tqueued_backlog\t%s\t%s\t%s\n' "$(date -Iseconds)" "$target" "$event_id" "$key" >> "${RETRO_PANE_LEDGER:-${RETRO_VERBATIM_LOG:-$root/logs/retro_pane_prompt.tsv}}"
            flock -u "$retro_pending_lock_fd"
            exec {retro_pending_lock_fd}>&-
            RETRO_PANE_ENQUEUE_DECISION=backlogged
            return 0
        fi
    done
    tmp="$event_file.tmp.$$"
    printf '%s\n%s\n%s\n%s\n' "$target" "$event_id" "$from" "$key" > "$tmp"
    mv -n "$tmp" "$event_file" 2>/dev/null || rm -f "$tmp"
    flock -u "$retro_pending_lock_fd"
    exec {retro_pending_lock_fd}>&-
}

retro_pane_prompt_promote_backlog() {
    local root="$1" target="$2"
    local pending_dir="${RETRO_PANE_PENDING_DIR:-${RETRO_VERBATIM_PENDING_DIR:-$root/queue/retro/verbatim_pending}}"
    local retro_queue_dir="${pending_dir%/*}"
    [[ "$pending_dir" == */verbatim_pending ]] && retro_queue_dir="${pending_dir%/verbatim_pending}"
    local backlog_dir="${RETRO_PANE_BACKLOG_DIR:-$retro_queue_dir/verbatim_backlog}"
    local awaiting_dir="$retro_queue_dir/verbatim_awaiting_answer"
    local pending_lock="${pending_dir%/}.enqueue.lock" existing existing_target oldest="" order oldest_order=""
    mkdir -p "$pending_dir" "$backlog_dir"
    exec {retro_promote_lock_fd}>"$pending_lock"
    flock -x "$retro_promote_lock_fd"
    for existing in "$pending_dir"/*.event "$awaiting_dir"/*.event; do
        [ -f "$existing" ] || continue
        IFS= read -r existing_target < "$existing" || true
        if [ "$existing_target" = "$target" ]; then
            flock -u "$retro_promote_lock_fd"; exec {retro_promote_lock_fd}>&-
            return 0
        fi
    done
    for existing in "$backlog_dir"/*.event; do
        [ -f "$existing" ] || continue
        IFS= read -r existing_target < "$existing" || true
        [ "$existing_target" = "$target" ] || continue
        order=$(sed -n '5p' "$existing")
        if [ -z "$oldest" ] || [[ "$order" < "$oldest_order" ]]; then oldest="$existing"; oldest_order="$order"; fi
    done
    if [ -n "$oldest" ]; then
        mv "$oldest" "$pending_dir/${oldest##*/}"
        printf '%s\tpromoted_backlog\t%s\t%s\n' "$(date -Iseconds)" "$target" "$(sed -n '2p' "$pending_dir/${oldest##*/}")" >> "${RETRO_PANE_LEDGER:-${RETRO_VERBATIM_LOG:-$root/logs/retro_pane_prompt.tsv}}"
    fi
    flock -u "$retro_promote_lock_fd"; exec {retro_promote_lock_fd}>&-
}

retro_pane_prompt_async() {
    local root="$1" target="$2" event_id="$3" from="$4"
    # Persist before the detached attempt.  A busy pane or send failure leaves
    # this event for ninja_monitor's next idle cycle; only the claim is released.
    local enqueue_rc=0
    RETRO_PANE_ENQUEUE_DECISION=
    retro_pane_prompt_enqueue "$root" "$target" "$event_id" "$from" || enqueue_rc=$?
    # Suppression is a successful exactly-once outcome: the event is already
    # durable or this target already has an unresolved prompt.  In either case
    # starting a detached delivery would violate the enqueue decision.
    { [ "$RETRO_PANE_ENQUEUE_DECISION" = suppressed ] || [ "$RETRO_PANE_ENQUEUE_DECISION" = backlogged ]; } && return 0
    [ "$enqueue_rc" -eq 0 ] || return "$enqueue_rc"
    ( retro_pane_prompt_deliver "$root" "$target" "$event_id" "$from" ) >/dev/null 2>&1 &
}
