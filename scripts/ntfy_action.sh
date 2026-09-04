#!/usr/bin/env bash
# T3-S-63: physically separate notifications that require the Lord's action.
# Keep ntfy.sh's one-argument contract and implementation unchanged; this
# wrapper selects the dedicated topic and synchronous fail-closed delivery.
set -euo pipefail

if [[ "$#" -ne 1 || -z "${1:-}" ]]; then
    echo "Usage: ntfy_action.sh <message>" >&2
    exit 1
fi

_self_path="${BASH_SOURCE[0]}"
[[ "$_self_path" = /* ]] || _self_path="$PWD/$_self_path"
_script_dir="${_self_path%/*}"
unset _self_path

readonly ACTION_TOPIC="shogun-simokitafresh-action"
readonly ACTION_ENDPOINT="https://ntfy.sh/${ACTION_TOPIC}?priority=high"
message="【要操作】${1}"
log_file="$_script_dir/../logs/ntfy.log"
lock_file="${NTFY_ACTION_LOCK_FILE:-${TMPDIR:-/tmp}/shogun-ntfy-action.lock}"
state_dir="${NTFY_ACTION_STATE_DIR:-/tmp/multi_agent_shogun_ntfy_action}"

exec 9>"$lock_file"
flock -w 30 9 || {
    echo "ntfy_action: transport lock timeout" >&2
    exit 1
}

before_bytes=0
if [[ -f "$log_file" ]]; then
    before_bytes="$(wc -c < "$log_file")"
fi

# NTFY_SYNC makes transport failures observable by the caller. The endpoint's
# priority query is ntfy's supported equivalent of a Priority: high header.
set +e
env NTFY_SYNC=1 NTFY_MIN_INTERVAL_SECONDS=0 NTFY_429_COOLDOWN_SECONDS=0 \
    NTFY_STATE_DIR="$state_dir" NTFY_ENDPOINT="$ACTION_ENDPOINT" \
    bash "$_script_dir/ntfy.sh" "$message"
transport_status=$?
set -e
if (( transport_status != 0 )); then
    exit "$transport_status"
fi

# ntfy.sh deliberately treats HTTP 429 as a cooldown success for information
# traffic. Action traffic must prove a 200 line for its own prefix; otherwise
# a throttle/cooldown or an unlogged result is fail-closed.
if [[ ! -f "$log_file" ]]; then
    echo "ntfy_action: delivery result not recorded" >&2
    exit 1
fi
new_log="$(tail -c +$((before_bytes + 1)) "$log_file")"
if ! awk '/msg="【要操作】/ { if ($0 ~ /http=200/) ok=1; if ($0 ~ /http=429|SKIP (cooldown|throttle)/) bad=1 } END { exit (ok && !bad) ? 0 : 1 }' <<< "$new_log"; then
    echo "ntfy_action: delivery was not confirmed" >&2
    exit 1
fi
