#!/usr/bin/env bash
# Thin shell adapter over durable_state.py. All schema/checksum/WAL/fence/
# transition logic lives in the Python module; this file only forwards
# arguments and propagates its exit code (no reimplementation, per cmd_4200
# AC2 constraint). See docs/research/hidden-infrastructure-gate-hook-remediation-design-20260730.md §5.2.
set -euo pipefail

DURABLE_STATE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DURABLE_STATE_PY="$DURABLE_STATE_SCRIPT_DIR/durable_state.py"

durable_state_begin() {
    local root="$1" subject_type="$2" subject_id="$3" attempt_id="$4" payload_hash="$5" artifact_hash="${6:-}"
    python3 "$DURABLE_STATE_PY" begin \
        --root "$root" --subject-type "$subject_type" --subject-id "$subject_id" \
        --attempt-id "$attempt_id" --payload-hash "$payload_hash" --artifact-hash "$artifact_hash"
}

durable_state_mutate() {
    local root="$1" subject_type="$2" subject_id="$3" expected_fence="$4" phase="$5"
    local terminal_result="${6:-}" side_effect_ledger="${7:-}"
    python3 "$DURABLE_STATE_PY" mutate \
        --root "$root" --subject-type "$subject_type" --subject-id "$subject_id" \
        --expected-fence "$expected_fence" --phase "$phase" \
        --terminal-result "$terminal_result" --side-effect-ledger "$side_effect_ledger"
}

durable_state_read() {
    local root="$1" subject_type="$2" subject_id="$3"
    python3 "$DURABLE_STATE_PY" read \
        --root "$root" --subject-type "$subject_type" --subject-id "$subject_id"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd="${1:-}"
    shift || true
    case "$cmd" in
        begin) durable_state_begin "$@" ;;
        mutate) durable_state_mutate "$@" ;;
        read) durable_state_read "$@" ;;
        *)
            echo "usage: durable_state.sh {begin|mutate|read} ..." >&2
            exit 64
            ;;
    esac
fi
