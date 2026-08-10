#!/usr/bin/env bash
# commit_queue.sh — shared commit reservation ledger (Phase 1)
#
# The ledger is intentionally a small, volatile TSV under /tmp.  Every
# mutation is protected by flock and published with rename so a reader never
# observes a partially-written reservation.  This script is also sourceable:
# the public functions are useful to the scoped-commit wrapper and to focused
# contract tests.
set -euo pipefail

COMMIT_QUEUE_PATH="${COMMIT_QUEUE_PATH:-/tmp/shogun_commit_queue.tsv}"
COMMIT_QUEUE_LOCK_PATH="${COMMIT_QUEUE_LOCK_PATH:-${COMMIT_QUEUE_PATH}.lock}"
COMMIT_QUEUE_TTL_SECONDS="${COMMIT_QUEUE_TTL_SECONDS:-600}"
COMMIT_QUEUE_WAIT_SECONDS="${COMMIT_QUEUE_WAIT_SECONDS:-600}"
COMMIT_QUEUE_POLL_SECONDS="${COMMIT_QUEUE_POLL_SECONDS:-3}"
COMMIT_QUEUE_INDEX_WAIT_ATTEMPTS="${COMMIT_QUEUE_INDEX_WAIT_ATTEMPTS:-20}"
COMMIT_QUEUE_INDEX_POLL_SECONDS="${COMMIT_QUEUE_INDEX_POLL_SECONDS:-3}"

_cq_validate_positive_int() {
    local name="$1" value="$2"
    [[ "$value" =~ ^[1-9][0-9]*$ ]] || {
        echo "BLOCK: $name must be a positive integer" >&2
        return 2
    }
}

_cq_validate_identity() {
    local value="$1"
    [[ -n "$value" && "$value" != *$'\t'* && "$value" != *$'\n'* ]] || {
        echo "BLOCK: reservation identity must be a non-empty single-line value" >&2
        return 2
    }
}

_cq_ensure_paths() {
    mkdir -p -- "$(dirname -- "$COMMIT_QUEUE_PATH")"
    : >>"$COMMIT_QUEUE_PATH"
    : >>"$COMMIT_QUEUE_LOCK_PATH"
}

_cq_now() { date +%s; }

_cq_lock_open() {
    _cq_ensure_paths
    exec {COMMIT_QUEUE_FD}>"$COMMIT_QUEUE_LOCK_PATH"
    flock -w "${COMMIT_QUEUE_LOCK_TIMEOUT_SECONDS:-10}" "$COMMIT_QUEUE_FD" || {
        echo "BLOCK: commit reservation ledger lock unavailable" >&2
        return 2
    }
}

_cq_lock_close() {
    if [[ -n "${COMMIT_QUEUE_FD:-}" ]]; then
        flock -u "$COMMIT_QUEUE_FD" || true
        eval "exec ${COMMIT_QUEUE_FD}>&-" || true
        unset COMMIT_QUEUE_FD
    fi
}

_cq_atomic_replace_locked() {
    local tmp
    tmp="${COMMIT_QUEUE_PATH}.tmp.$$.$RANDOM"
    cat >"$tmp"
    mv -f -- "$tmp" "$COMMIT_QUEUE_PATH"
}

_cq_gc_locked() {
    local now="$1" ttl="$COMMIT_QUEUE_TTL_SECONDS" tmp
    _cq_validate_positive_int COMMIT_QUEUE_TTL_SECONDS "$ttl"
    tmp="${COMMIT_QUEUE_PATH}.tmp.$$.$RANDOM"
    awk -F '\t' -v now="$now" -v ttl="$ttl" '
        NF >= 5 && ($5 == "running" || $5 == "waiting") {
            if (now - $4 <= ttl) print
            next
        }
        NF >= 5 { print }
    ' "$COMMIT_QUEUE_PATH" >"$tmp"
    mv -f -- "$tmp" "$COMMIT_QUEUE_PATH"
}

gc() {
    local now
    now="$(_cq_now)"
    _cq_lock_open
    _cq_gc_locked "$now"
    _cq_lock_close
}

reserve() {
    local agent_id="${1:-}" repo_root="${2:-${PWD}}" now reservation existing
    _cq_validate_identity "$agent_id"
    _cq_validate_identity "$repo_root"
    now="$(_cq_now)"
    reservation="${agent_id}-${now}-${BASHPID}-${RANDOM}"
    _cq_lock_open
    _cq_gc_locked "$now"
    existing="$(awk -F '\t' -v agent="$agent_id" -v repo="$repo_root" \
        '$2 == agent && $3 == repo && ($5 == "waiting" || $5 == "running") {print $1; exit}' \
        "$COMMIT_QUEUE_PATH")"
    if [[ -n "$existing" ]]; then
        _cq_lock_close
        echo "BLOCK: duplicate commit reservation for agent=$agent_id repo=$repo_root id=$existing" >&2
        return 3
    fi
    {
        awk -F '\t' 'NF >= 5 {print}' "$COMMIT_QUEUE_PATH"
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$reservation" "$agent_id" "$repo_root" "$now" waiting "$now"
    } | _cq_atomic_replace_locked
    _cq_lock_close
    printf '%s\n' "$reservation"
}

_cq_find_row() {
    local reservation_id="$1"
    awk -F '\t' -v id="$reservation_id" '$1 == id {print; exit}' "$COMMIT_QUEUE_PATH"
}

wait_turn() {
    local reservation_id="${1:-}" started now first row repo_root
    _cq_validate_identity "$reservation_id"
    started="$(_cq_now)"
    _cq_validate_positive_int COMMIT_QUEUE_WAIT_SECONDS "$COMMIT_QUEUE_WAIT_SECONDS"
    _cq_validate_positive_int COMMIT_QUEUE_POLL_SECONDS "$COMMIT_QUEUE_POLL_SECONDS"
    while :; do
        now="$(_cq_now)"
        if (( now - started >= COMMIT_QUEUE_WAIT_SECONDS )); then
            echo "BLOCK: commit reservation wait timeout id=$reservation_id" >&2
            return 124
        fi
        _cq_lock_open
        _cq_gc_locked "$now"
        row="$(_cq_find_row "$reservation_id")"
        repo_root="$(printf '%s\n' "$row" | awk -F '\t' 'NR == 1 {print $3}')"
        first="$(awk -F '\t' -v repo="$repo_root" \
            '$3 == repo && ($5 == "waiting" || $5 == "running") {print $1; exit}' \
            "$COMMIT_QUEUE_PATH")"
        _cq_lock_close
        [[ -n "$row" ]] || { echo "BLOCK: reservation disappeared id=$reservation_id" >&2; return 2; }
        [[ "$first" == "$reservation_id" ]] && return 0
        sleep "$COMMIT_QUEUE_POLL_SECONDS"
    done
}

check_index() {
    local repo_root="${1:-${PWD}}" lock_path attempt
    _cq_validate_identity "$repo_root"
    _cq_validate_positive_int COMMIT_QUEUE_INDEX_WAIT_ATTEMPTS "$COMMIT_QUEUE_INDEX_WAIT_ATTEMPTS"
    _cq_validate_positive_int COMMIT_QUEUE_INDEX_POLL_SECONDS "$COMMIT_QUEUE_INDEX_POLL_SECONDS"
    lock_path="$(git -C "$repo_root" rev-parse --git-path index.lock 2>/dev/null)" || {
        echo "BLOCK: cannot resolve git index.lock for $repo_root" >&2
        return 2
    }
    [[ "$lock_path" = /* ]] || lock_path="$repo_root/$lock_path"
    for ((attempt=1; attempt<=COMMIT_QUEUE_INDEX_WAIT_ATTEMPTS; attempt++)); do
        [[ ! -e "$lock_path" ]] && return 0
        if command -v fuser >/dev/null 2>&1 && fuser "$lock_path" >/dev/null 2>&1; then
            sleep "$COMMIT_QUEUE_INDEX_POLL_SECONDS"
            continue
        fi
        if ! command -v fuser >/dev/null 2>&1; then
            echo "BLOCK: fuser is required before deciding whether index.lock is orphaned" >&2
            return 2
        fi
        rm -f -- "$lock_path"
        [[ ! -e "$lock_path" ]] && return 0
    done
    echo "BLOCK: git index.lock remained active after ${COMMIT_QUEUE_INDEX_WAIT_ATTEMPTS} checks: $lock_path" >&2
    return 124
}

_cq_update_status() {
    local reservation_id="$1" new_status="$2" now tmp
    now="$(_cq_now)"
    _cq_lock_open
    tmp="${COMMIT_QUEUE_PATH}.tmp.$$.$RANDOM"
    awk -F '\t' -v id="$reservation_id" -v status="$new_status" -v now="$now" '
        $1 == id { $5=status; $6=now; found=1 }
        { print }
        END { if (!found) exit 3 }
    ' OFS='\t' "$COMMIT_QUEUE_PATH" >"$tmp" || { rm -f -- "$tmp"; _cq_lock_close; return 3; }
    mv -f -- "$tmp" "$COMMIT_QUEUE_PATH"
    _cq_lock_close
}

mark_running() { _cq_update_status "${1:-}" running; }

release() {
    local reservation_id="${1:-}" tmp
    _cq_validate_identity "$reservation_id"
    _cq_lock_open
    tmp="${COMMIT_QUEUE_PATH}.tmp.$$.$RANDOM"
    awk -F '\t' -v id="$reservation_id" '$1 != id {print}' OFS='\t' "$COMMIT_QUEUE_PATH" >"$tmp"
    mv -f -- "$tmp" "$COMMIT_QUEUE_PATH"
    _cq_lock_close
}

run_reserved() {
    local agent_id="" repo_root="$PWD" reservation_id rc
    while (($#)); do
        case "$1" in
            --agent) agent_id="$2"; shift 2 ;;
            --repo) repo_root="$2"; shift 2 ;;
            --) shift; break ;;
            *) echo "BLOCK: unknown run option: $1" >&2; return 2 ;;
        esac
    done
    (($# > 0)) || { echo "BLOCK: reserved command is empty" >&2; return 2; }
    reservation_id="$(reserve "$agent_id" "$repo_root")" || return $?
    wait_turn "$reservation_id" || { rc=$?; release "$reservation_id" || true; return "$rc"; }
    check_index "$repo_root" || { rc=$?; release "$reservation_id" || true; return "$rc"; }
    mark_running "$reservation_id" || { rc=$?; release "$reservation_id" || true; return "$rc"; }
    _cq_release_trap() {
        local trapped_rc=$?
        trap - EXIT INT TERM
        release "${COMMIT_QUEUE_RESERVATION_ID:-}" || true
        exit "$trapped_rc"
    }
    trap _cq_release_trap EXIT INT TERM
    COMMIT_QUEUE_RESERVATION_ID="$reservation_id"; export COMMIT_QUEUE_RESERVATION_ID
    "$@"
    rc=$?
    release "$reservation_id" || true
    trap - EXIT INT TERM
    return "$rc"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    command_name="${1:-}"
    shift || true
    case "$command_name" in
        gc) gc "$@" ;;
        reserve) reserve "$@" ;;
        wait_turn) wait_turn "$@" ;;
        check_index) check_index "$@" ;;
        mark_running) mark_running "$@" ;;
        release) release "$@" ;;
        run) run_reserved "$@" ;;
        *) echo "Usage: $0 {gc|reserve|wait_turn|check_index|mark_running|release|run}" >&2; exit 2 ;;
    esac
fi
