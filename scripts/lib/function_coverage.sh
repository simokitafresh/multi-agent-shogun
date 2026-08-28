#!/usr/bin/env bash
# function_coverage.sh — low-overhead Bash function call coverage.
#
# The hot path is deliberately one associative-array increment per DEBUG
# event.  The daily JSONL write happens once at process completion under a
# separate flock, so parallel deployments cannot interleave records.

_fc_is_internal() {
    case "${1:-}" in
        _fc_*|function_coverage_*|_dt_function_timing_*) return 0 ;;
        *) return 1 ;;
    esac
}

_fc_command_name() {
    local command=${1:-}
    # DEBUG supplies a simple command here.  Strip the common shell prefixes
    # without regex/BASH_REMATCH, because callers may rely on that global.
    command=${command#"${command%%[!$' \t']*}"}
    command=${command%%[ $'\t']*}
    command=${command##*/}
    printf '%s\n' "$command"
}

_fc_collect_functions() {
    local _fc_decl _fc_name
    while read -r _fc_decl _fc_name; do
        [ -n "${_fc_name:-}" ] || continue
        _fc_is_internal "$_fc_name" && continue
        _FC_DEFINED["$_fc_name"]=1
    done < <(declare -F | awk '{print $1 " " $3}')
}

function_coverage_record_command() {
    [ "${_FC_ENABLED:-0}" -eq 1 ] || return 0
    local _fc_name _fc_current
    _fc_name=${1:-}
    _fc_name=${_fc_name#"${_fc_name%%[!$' \t']*}"}
    _fc_name=${_fc_name%%[ $'\t']*}
    _fc_name=${_fc_name##*/}
    [ -n "$_fc_name" ] || return 0
    _fc_is_internal "$_fc_name" && return 0
    [ "${_FC_DEFINED["$_fc_name"]+present}" = present ] || return 0
    # Bash emits the function command once at the caller and once when the
    # callee begins executing with the same BASH_COMMAND.  The latter has the
    # callee at frame 2; ignoring it also keeps recursive self-entry out of
    # the coverage signal, as required for retirement decisions.
    _fc_current=${FUNCNAME[2]:-}
    [ "$_fc_current" != "$_fc_name" ] || return 0
    _FC_CALLS["$_fc_name"]=$(( ${_FC_CALLS["$_fc_name"]:-0} + 1 ))
}

_fc_debug() {
    # A DEBUG trap inherited by a function can fire once for the call and
    # again while the trap helper returns.  Keep the call-site token stable
    # across that re-entrant span; repeated calls on the same source line are
    # still counted because the intervening function body changes the token.
    [ "${_FC_IN_HOOK:-0}" -eq 0 ] || return 0
    local _fc_token="${BASH_COMMAND:-}|${FUNCNAME[1]:-}|${BASH_LINENO[0]:-}|${BASH_LINENO[1]:-}"
    [ "${_FC_LAST_TOKEN:-}" != "$_fc_token" ] || return 0
    _FC_LAST_TOKEN="$_fc_token"
    _FC_IN_HOOK=1
    function_coverage_record_command "${BASH_COMMAND:-}"
    _FC_IN_HOOK=0
}

function_coverage_enable() {
    [ "${1:-}" != "" ] || return 2
    local _fc_script=${1##*/}
    local _fc_log=${2:-}
    case "${_fc_log:-}" in
        disabled|0) return 0 ;;
    esac
    _fc_log=${_fc_log:-${FUNCTION_COVERAGE_LOG:-logs/function_coverage/${_fc_script}.jsonl}}
    mkdir -p "$(dirname -- "$_fc_log")" 2>/dev/null || return 0

    declare -gA _FC_DEFINED=()
    declare -gA _FC_CALLS=()
    _FC_SCRIPT="$_fc_script"
    _FC_LOG="$_fc_log"
    _FC_DATE="$(date -u '+%Y-%m-%d')"
    _FC_OBSERVED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    _FC_EXECUTION_ID="${_fc_script%.sh}-$$-${EPOCHREALTIME//./}"
    _FC_ENABLED=1
    _FC_EXTERNAL_DEBUG=0
    _fc_collect_functions
    _FC_EXTERNAL_DEBUG=${FUNCTION_COVERAGE_EXTERNAL_DEBUG:-0}
    _FC_PREV_DEBUG_TRAP="$(trap -p DEBUG 2>/dev/null || true)"

    # deploy_task already has a DEBUG trap for timing.  Its trap calls
    # function_coverage_record_command directly, avoiding a second trap.
    # Standalone callers use this helper's own trap.
    if [ "$_FC_EXTERNAL_DEBUG" != 1 ]; then
        set -T
        trap '_fc_debug' DEBUG
    elif [ -z "$_FC_PREV_DEBUG_TRAP" ]; then
        set -T
        trap '_fc_debug' DEBUG
        _FC_EXTERNAL_DEBUG=0
    fi
    export FUNCTION_COVERAGE_ACTIVE=1
    return 0
}

_fc_json_record() {
    local _fc_fn=$1 _fc_calls=$2
    printf '{"schema":"function_coverage.v1","observed_date":"%s","observed_at":"%s","execution_id":"%s","script":"%s","function":"%s","calls":%s,"defined":true}\n' \
        "$_FC_DATE" "$_FC_OBSERVED_AT" "$_FC_EXECUTION_ID" "$_FC_SCRIPT" "$_fc_fn" "$_fc_calls"
}

function_coverage_finish() {
    [ "${_FC_ENABLED:-0}" -eq 1 ] || return 0
    _FC_ENABLED=0
    if [ "${_FC_EXTERNAL_DEBUG:-0}" != 1 ]; then
        trap - DEBUG
        set +T
        if [ -n "${_FC_PREV_DEBUG_TRAP:-}" ]; then
            eval "$_FC_PREV_DEBUG_TRAP" 2>/dev/null || true
        fi
    fi
    [ -n "${_FC_LOG:-}" ] || return 0
    {
        flock -x 9 || exit 0
        local _fc_fn
        for _fc_fn in "${!_FC_DEFINED[@]}"; do
            _fc_json_record "$_fc_fn" "${_FC_CALLS["$_fc_fn"]:-0}"
        done | sort -t '"' -k 12,12
    } 9>"${_FC_LOG}.lock" >>"$_FC_LOG" 2>/dev/null || true
    unset FUNCTION_COVERAGE_ACTIVE
    return 0
}

function_coverage_daily_aggregate() {
    local _fc_log=${1:-}
    [ -f "$_fc_log" ] || { printf '%s\n' '{"eligible":false,"reason":"log_missing"}'; return 0; }
    python3 - "$_fc_log" <<'PY'
import json, sys
from collections import defaultdict
path = sys.argv[1]
rows = defaultdict(int)
for raw in open(path, encoding="utf-8"):
    try:
        item = json.loads(raw)
        rows[(item["observed_date"], item["script"], item["function"])] += int(item["calls"])
    except (ValueError, KeyError, TypeError):
        continue
for (day, script, function), calls in sorted(rows.items()):
    print(json.dumps({"schema": "function_coverage.daily.v1", "observed_date": day,
                      "script": script, "function": function, "calls": calls},
                     separators=(",", ":")))
PY
}

function_coverage_retirement_candidates() {
    local _fc_log=${1:-} _fc_days=${2:-7} _fc_as_of=${3:-}
    [ -n "$_fc_log" ] || return 2
    python3 - "$_fc_log" "$_fc_days" "$_fc_as_of" <<'PY'
import datetime as dt, json, os, sys
from collections import defaultdict
path, days_text, as_of_text = sys.argv[1:]
days = int(days_text)
script_from_path = os.path.basename(path)
if script_from_path.endswith('.jsonl'):
    script_from_path = script_from_path[:-6]
if not os.path.exists(path):
    print(json.dumps({"schema":"function_coverage.retirement.v1", "eligible":False,
                      "reason":"log_missing", "log":path}, separators=(",", ":")))
    raise SystemExit(0)
rows = []
identity_errors = []
identity_scripts = {}
for line_no, raw in enumerate(open(path, encoding="utf-8"), 1):
    try:
        item = json.loads(raw)
        day = dt.date.fromisoformat(item["observed_date"])
        fn = item["function"]
        script = item["script"]
        execution = item["execution_id"]
        calls = int(item["calls"])
        if not execution or script != script_from_path:
            raise ValueError("execution_identity_mixed")
        prior = identity_scripts.setdefault(execution, script)
        if prior != script:
            raise ValueError("execution_identity_mixed")
        rows.append((day, fn, calls))
    except (ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        identity_errors.append(str(exc) or "malformed_record")
if identity_errors:
    print(json.dumps({"schema":"function_coverage.retirement.v1", "eligible":False,
                      "reason":"execution_identity_mixed", "details":sorted(set(identity_errors))},
                     separators=(",", ":")))
    raise SystemExit(0)
if not rows:
    print(json.dumps({"schema":"function_coverage.retirement.v1", "eligible":False,
                      "reason":"no_observations"}, separators=(",", ":")))
    raise SystemExit(0)
latest = max(day for day, _, _ in rows)
end = dt.date.fromisoformat(as_of_text) if as_of_text else latest
expected = {end - dt.timedelta(days=i) for i in range(days)}
by_function = defaultdict(lambda: defaultdict(int))
for day, fn, calls in rows:
    by_function[fn][day] += calls
for fn in sorted(by_function):
    observed = set(by_function[fn])
    missing = sorted(expected - observed)
    base = {"schema":"function_coverage.retirement.v1", "script":script_from_path,
            "function":fn, "window_days":days, "observed_days":len(observed)}
    if missing:
        base.update(eligible=False, reason="observation_days_insufficient", missing_dates=[d.isoformat() for d in missing])
    elif all(by_function[fn][day] == 0 for day in expected):
        base.update(eligible=True, reason="zero_calls_for_window")
    else:
        base.update(eligible=False, reason="calls_observed")
    print(json.dumps(base, separators=(",", ":")))
PY
}

function_coverage_cli() {
    case "${1:-}" in
        --aggregate|aggregate) shift; function_coverage_daily_aggregate "$@" ;;
        --dry-run|retirement-candidates|candidates) shift; function_coverage_retirement_candidates "$@" ;;
        *)
            printf '%s\n' 'usage: function_coverage.sh --aggregate LOG | --dry-run LOG [DAYS] [AS_OF]' >&2
            return 2
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    function_coverage_cli "$@"
fi
