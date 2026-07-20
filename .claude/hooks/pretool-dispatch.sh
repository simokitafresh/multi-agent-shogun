#!/usr/bin/env bash
# PreToolUse dispatcher: one Claude hook entry, event-specific routing inside.
# L164: use set -eu only for Claude hook shell scripts.
set -eu

payload="$(cat 2>/dev/null || true)"
case "$payload" in
    *[![:space:]]*) ;;
    *) exit 0 ;;
esac

_self="${BASH_SOURCE[0]:-$0}"
case "$_self" in
    /*/.claude/hooks/pretool-dispatch.sh) ROOT="${_self%/.claude/hooks/pretool-dispatch.sh}" ;;
    .claude/hooks/pretool-dispatch.sh) ROOT="$PWD" ;;
    *) ROOT="${PWD}/${_self%/.claude/hooks/pretool-dispatch.sh}" ;;
esac
unset _self

_mirror_block_reason_if_needed() {
    local rc="$1" out="$2" err_file="$3" reason

    [ "$rc" -eq 2 ] || return 0
    [ ! -s "$err_file" ] || return 0

    reason="$(printf '%s\n' "$out" | sed -n 's/.*"permissionDecisionReason":"\([^"]*\)".*/\1/p' | head -1)"
    if [ -z "$reason" ]; then
        reason="$(printf '%s\n' "$out" | sed -n '/[^[:space:]]/{p;q;}')"
    fi
    if [ -z "$reason" ]; then
        reason="BLOCK: PreToolUse hook exited 2 without a reason. Check ${ROOT}/.claude/hooks/pretool-dispatch.sh child hook output."
    fi
    printf '%s\n' "$reason" >&2
}

_run_pretool_child() {
    local err_file out rc
    err_file="$(mktemp)"
    set +e
    out="$("$@" 2>"$err_file")"
    rc=$?
    set -e
    [ -z "$out" ] || printf '%s\n' "$out"
    if [ -s "$err_file" ]; then
        cat "$err_file" >&2
    fi
    _mirror_block_reason_if_needed "$rc" "$out" "$err_file"
    rm -f "$err_file"
    return "$rc"
}

# Preserve the former PreToolUse state update, but do not pay two tmux
# set-option calls on every tool. Consumers treat active hooks as fresh for
# 15s+ and stale only after 30-60s, so a 10s refresh interval stays inside
# every monitor grace window.
if [ -n "${TMUX_PANE:-}" ]; then
    printf -v now '%(%s)T' -1 2>/dev/null || now="$(date +%s)"
    _pane_cache_key="${TMUX_PANE//[^A-Za-z0-9_.-]/_}"
    _state_cache_dir="${TMPDIR:-/tmp}/shogun-pretool-state"
    _state_cache_file="${_state_cache_dir}/${_pane_cache_key}.last"
    _last_state_update=0
    if [ -r "$_state_cache_file" ]; then
        IFS= read -r _last_state_update < "$_state_cache_file" || _last_state_update=0
    fi
    case "$_last_state_update" in
        ''|*[!0-9]*) _last_state_update=0 ;;
    esac
    if [ $((now - _last_state_update)) -ge "${PRETOOL_STATE_REFRESH_INTERVAL:-10}" ]; then
        mkdir -p "$_state_cache_dir" 2>/dev/null || true
        tmux set-option -p -t "$TMUX_PANE" @agent_state active 2>/dev/null || true
        tmux set-option -p -t "$TMUX_PANE" @last_active "$now" 2>/dev/null || true
        printf '%s\n' "$now" > "$_state_cache_file" 2>/dev/null || true
    fi
    unset now _pane_cache_key _state_cache_dir _state_cache_file _last_state_update
fi

case "$payload" in
    *'"Bash"'*)
        HOOK_PAYLOAD="$payload"
        export HOOK_PAYLOAD
        bash "$ROOT/.claude/hooks/pre-bash-combined.sh" || exit "$?"
        ;;
    *'"Read"'*)
        source "$ROOT/.claude/hooks/pre-write-read-tracker.sh" <<< "$payload"
        ;;
    *'"Write"'*|*'"Edit"'*)
        printf '%s' "$payload" | _run_pretool_child bash "$ROOT/.claude/hooks/pre-write-edit-combined.sh" || exit "$?"
        printf '%s' "$payload" | _run_pretool_child bash "$ROOT/.claude/hooks/pre-edit-pi-inject.sh" || exit "$?"
        ;;
    *'"Skill"'*)
        # Guard: /clear自発禁止 (殿裁定2026-06-28 LS074)
        if [[ "${AGENT_ID:-}" == "shogun" ]] && echo "$payload" | grep -qi 'clear-prep\|shogun-clear-prep'; then
          echo "BLOCK: /clear自発禁止。/clearは殿の専権事項。autocompact=90%が自動管理。殿の明示的指示なしに/clearスキルを実行するな。" >&2
          exit 2
        fi
        source "$ROOT/.claude/hooks/pre-skill-project-guard.sh" <<< "$payload"
        ;;
    *)
        exit 0
        ;;
esac
