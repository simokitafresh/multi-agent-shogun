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

durable_state_lease_acquire() {
    local root="$1" subject_type="$2" subject_id="$3" owner_id="$4" lease_ttl="${5:-30.0}"
    python3 "$DURABLE_STATE_PY" lease-acquire \
        --root "$root" --subject-type "$subject_type" --subject-id "$subject_id" \
        --owner-id "$owner_id" --lease-ttl "$lease_ttl"
}

durable_state_reconcile() {
    local root="$1" subject_type="$2" subject_id="$3" owner_id="$4"
    local observed_artifact_hash="${5:-}" side_effect_ledger="${6:-}" lease_ttl="${7:-30.0}"
    python3 "$DURABLE_STATE_PY" reconcile \
        --root "$root" --subject-type "$subject_type" --subject-id "$subject_id" \
        --owner-id "$owner_id" --observed-artifact-hash "$observed_artifact_hash" \
        --side-effect-ledger "$side_effect_ledger" --lease-ttl "$lease_ttl"
}

durable_state_terminal_receipt() {
    local root="$1" subject_type="$2" subject_id="$3" generation="$4"
    python3 "$DURABLE_STATE_PY" terminal-receipt \
        --root "$root" --subject-type "$subject_type" --subject-id "$subject_id" \
        --generation "$generation"
}

durable_state_outbox_reserve() {
    local root="$1" idempotency_key="$2" action="$3" target="$4" payload_hash="$5"
    python3 "$DURABLE_STATE_PY" outbox-reserve \
        --root "$root" --idempotency-key "$idempotency_key" --action "$action" \
        --target "$target" --payload-hash "$payload_hash"
}

durable_state_outbox_apply() {
    local root="$1" idempotency_key="$2" side_effect_log="${3:-}" fail_after_effect="${4:-}"
    local extra_args=()
    if [ -n "$fail_after_effect" ]; then
        extra_args+=(--fail-after-effect)
    fi
    python3 "$DURABLE_STATE_PY" outbox-apply \
        --root "$root" --idempotency-key "$idempotency_key" --side-effect-log "$side_effect_log" \
        "${extra_args[@]}"
}

durable_state_outbox_reconcile() {
    local root="$1" idempotency_key="$2" provider_receipt="${3:-}" not_executed_proof="${4:-}"
    python3 "$DURABLE_STATE_PY" outbox-reconcile \
        --root "$root" --idempotency-key "$idempotency_key" \
        --provider-receipt "$provider_receipt" --not-executed-proof "$not_executed_proof"
}

durable_state_shadow_compare() {
    local root="$1" subject_type="$2" subject_id="$3"
    python3 "$DURABLE_STATE_PY" shadow-compare \
        --root "$root" --subject-type "$subject_type" --subject-id "$subject_id"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd="${1:-}"
    shift || true
    case "$cmd" in
        begin) durable_state_begin "$@" ;;
        mutate) durable_state_mutate "$@" ;;
        read) durable_state_read "$@" ;;
        lease-acquire) durable_state_lease_acquire "$@" ;;
        reconcile) durable_state_reconcile "$@" ;;
        terminal-receipt) durable_state_terminal_receipt "$@" ;;
        outbox-reserve) durable_state_outbox_reserve "$@" ;;
        outbox-apply) durable_state_outbox_apply "$@" ;;
        outbox-reconcile) durable_state_outbox_reconcile "$@" ;;
        shadow-compare) durable_state_shadow_compare "$@" ;;
        *)
            echo "usage: durable_state.sh {begin|mutate|read|lease-acquire|reconcile|terminal-receipt|outbox-reserve|outbox-apply|outbox-reconcile|shadow-compare} ..." >&2
            exit 64
            ;;
    esac
fi
