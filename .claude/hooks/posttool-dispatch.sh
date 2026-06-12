#!/usr/bin/env bash
# PostToolUse dispatcher: one Claude hook entry, event-specific routing inside.
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
ROOT="${_self%/.claude/hooks/posttool-dispatch.sh}"
unset _self

run_hook() {
    local script="$1" out rc
    set +e
    out="$(printf '%s' "$payload" | bash "$script" 2>&1)"
    rc=$?
    set -e
    [ -z "$out" ] || printf '%s\n' "$out"
    return "$rc"
}

is_shogun_agent() {
    [ -n "${TMUX_PANE:-}" ] || return 1
    local non_cache="/tmp/shogun_not_shogun_${TMUX_PANE}"
    [ -e "$non_cache" ] && return 1
    local cache="/tmp/shogun_aid_${TMUX_PANE}" agent=""
    if [ -r "$cache" ]; then
        IFS= read -r agent < "$cache" || true
    fi
    if [ "$agent" = "shogun" ]; then
        return 0
    elif [ -n "$agent" ]; then
        : > "$non_cache" 2>/dev/null || true
        return 1
    fi
    agent="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
    if [ "$agent" = "shogun" ]; then
        printf '%s\n' "$agent" > "$cache" 2>/dev/null || true
        return 0
    fi
    if [ -n "$agent" ]; then
        printf '%s\n' "$agent" > "$cache" 2>/dev/null || true
    fi
    : > "$non_cache" 2>/dev/null || true
    return 1
}

# Preserve the former matcher-less shogun inbox check without taxing non-shogun hot paths.
if is_shogun_agent; then
    run_hook "$ROOT/.claude/hooks/post-shogun-inbox-check.sh" || true
fi

case "$payload" in
    *'"Bash"'*)
        if [ "$payload" = "${payload%inbox_mark_read.sh*}" ]; then
            run_hook "$ROOT/.claude/hooks/post-bash-combined.sh" || exit "$?"
        else
            source "$ROOT/.claude/hooks/post-bulletin-notify-read-check.sh" <<< "$payload"
        fi
        ;;
    *'"Grep"'*|*'"Glob"'*)
        printf '%s\n' "⚠ この検索結果は網羅的ではない可能性がある。別の手法でも確認したか？（Grep→Glob / Glob→Grep / lord_conversation確認）" >&2
        ;;
    *'"Write"'*|*'"Edit"'*)
        source "$ROOT/.claude/hooks/post-write-edit-combined.sh" <<< "$payload"
        ;;
    *'"Skill"'*)
        HOOK_PAYLOAD="$payload" run_hook "$ROOT/.claude/hooks/post-skill-execution.sh" || true
        ;;
    *)
        exit 0
        ;;
esac
