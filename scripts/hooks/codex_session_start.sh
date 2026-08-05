#!/usr/bin/env bash
# Codex SessionStart adapter.
# Kept separate from Claude settings so Codex startup behavior can evolve
# without pretending every CLI has the same lifecycle semantics.
set -euo pipefail

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
ROOT="${_self%/scripts/hooks/codex_session_start.sh}"

# Round9 lane0pp: measure this Codex adapter boundary only.  The shared
# session_start_inject.sh is intentionally not instrumented because this
# adapter owns that event and otherwise the same SessionStart is counted twice.
CODEX_SESSION_START_TOTAL_T0_US="${EPOCHREALTIME/./}"
CODEX_SESSION_START_TOTAL_T0_US="${CODEX_SESSION_START_TOTAL_T0_US:0:16}"
DEFENSE_OVERHEAD_REPO_ROOT="${DEFENSE_OVERHEAD_REPO_ROOT:-$ROOT}"
if [[ -f "$ROOT/scripts/lib/defense_overhead_writer.sh" ]]; then
    source "$ROOT/scripts/lib/defense_overhead_writer.sh"
else
    defense_overhead_write_async() { return 0; }
fi
CODEX_SESSION_START_TOTAL_RECORDED=0
codex_session_start_record_total() {
    local rc="${1:-0}" now_us wall_ms verdict
    [ "${CODEX_SESSION_START_TOTAL_RECORDED:-0}" -eq 0 ] || return 0
    CODEX_SESSION_START_TOTAL_RECORDED=1
    now_us="${EPOCHREALTIME/./}"
    now_us="${now_us:0:16}"
    wall_ms=$(( (now_us - CODEX_SESSION_START_TOTAL_T0_US + 999) / 1000 ))
    verdict=PASS
    [ "$rc" -eq 0 ] || verdict=FAIL
    defense_overhead_write_async codex_session_start codex_session_start_total "$wall_ms" "$verdict" \
        "codex-session-start-${BASHPID}-${CODEX_SESSION_START_TOTAL_T0_US}" || true
}
codex_session_start_total_on_exit() { local rc=$?; codex_session_start_record_total "$rc"; return "$rc"; }
trap codex_session_start_total_on_exit EXIT

# The shared helper may be instrumented when invoked as a Claude entrypoint;
# this Codex adapter owns the same SessionStart event, so suppress the nested
# helper row for this call and keep exactly one event in the ledger.
DEFENSE_OVERHEAD_ENABLED=0 bash "$ROOT/scripts/hooks/session_start_inject.sh" || true
