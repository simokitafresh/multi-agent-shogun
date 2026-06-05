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
    /*) ;;
    *) _self="$PWD/$_self" ;;
esac
ROOT="${_self%/.claude/hooks/pretool-dispatch.sh}"
unset _self

# Preserve the former always-on PreToolUse state update without a separate hook entry.
if [ -n "${TMUX_PANE:-}" ]; then
    printf -v now '%(%s)T' -1 2>/dev/null || now="$(date +%s)"
    tmux set-option -p -t "$TMUX_PANE" @agent_state active 2>/dev/null || true
    tmux set-option -p -t "$TMUX_PANE" @last_active "$now" 2>/dev/null || true
    unset now
fi

case "$payload" in
    *'"Bash"'*)
        HOOK_PAYLOAD="$payload"
        export HOOK_PAYLOAD
        source "$ROOT/.claude/hooks/pre-bash-combined.sh"
        ;;
    *'"Read"'*)
        source "$ROOT/.claude/hooks/pre-write-read-tracker.sh" <<< "$payload"
        ;;
    *'"Write"'*|*'"Edit"'*)
        set +e
        out="$(printf '%s' "$payload" | bash "$ROOT/.claude/hooks/pre-write-edit-combined.sh" 2>&1)"
        rc=$?
        set -e
        [ -z "$out" ] || printf '%s\n' "$out"
        [ "$rc" -eq 0 ] || exit "$rc"
        printf '%s' "$payload" | exec bash "$ROOT/.claude/hooks/pre-edit-pi-inject.sh"
        ;;
    *'"Skill"'*)
        source "$ROOT/.claude/hooks/pre-skill-project-guard.sh" <<< "$payload"
        ;;
    *)
        exit 0
        ;;
esac
