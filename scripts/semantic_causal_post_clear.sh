#!/usr/bin/env bash
# Durable post-CLEAR semantic causal audit.
# Usage: bash scripts/semantic_causal_post_clear.sh <cmd_id>

set -euo pipefail

CMD_ID="${1:?Usage: semantic_causal_post_clear.sh <cmd_id>}"
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
GATE_DIR="$SCRIPT_DIR/queue/gates/$CMD_ID"
PENDING="$GATE_DIR/semantic_causal_audit.pending"
RESULT="$GATE_DIR/semantic_causal_audit.result"
LOG_FILE="$GATE_DIR/semantic_causal_audit.log"
PAYLOAD_FILE="$GATE_DIR/semantic_causal_payload.json"
SAFE_CMD="${CMD_ID//[^[:alnum:]_.-]/_}"
LOCK_FILE="/tmp/mas-semantic-causal-${SAFE_CMD}.lock"
FINALIZED=0
RESULT_TMP=""

mkdir -p "$GATE_DIR"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    exit 0
fi

prepare_result() {
    local state="$1" reason="$2" affected="$3" pass="$4" fail="$5" missing="$6" no_test="$7"
    RESULT_TMP="${RESULT}.tmp.$$"
    {
        printf 'state=%s\n' "$state"
        printf 'reason=%s\n' "$reason"
        printf 'affected=%s\n' "$affected"
        printf 'tests_pass=%s\n' "$pass"
        printf 'tests_fail=%s\n' "$fail"
        printf 'tests_missing=%s\n' "$missing"
        printf 'nodes_without_tests=%s\n' "$no_test"
        printf 'finished_at=%s\n' "$(date -Iseconds)"
    } > "$RESULT_TMP"
}

publish_result() {
    [ -n "$RESULT_TMP" ] && [ -f "$RESULT_TMP" ] || return 1
    # The result file is the externally observed completion marker.  Clear the
    # pending marker first and publish result last so consumers may immediately
    # remove the fixture/directory without racing any later worker file access.
    rm -f "$PENDING"
    mv "$RESULT_TMP" "$RESULT"
    RESULT_TMP=""
    FINALIZED=1
}

notify_warn() {
    local message="$1"
    BULLETIN_NOTIFY=karo,gunshi timeout 10 bash "$SCRIPT_DIR/scripts/bulletin_write.sh" \
        system "$message" false info >/dev/null 2>&1 || true
}

finalize_unexpected_exit() {
    local rc=$?
    if [ "$FINALIZED" -eq 0 ]; then
        prepare_result FAIL "worker_exit_${rc}" 0 0 1 0 0 || true
        notify_warn "[WARN] ${CMD_ID} semantic causal audit worker exited unexpectedly (rc=${rc})" || true
        publish_result || true
    fi
}
trap finalize_unexpected_exit EXIT

exec >> "$LOG_FILE" 2>&1
printf '%s [%s] semantic causal audit started\n' "$(date -Iseconds)" "$CMD_ID"

# The traversal resolves cmd_id from docs/semantic-index/index.md.  Updating
# that index in a separate background job races and can produce a false
# "start concept not found" result, so index -> map -> traverse is one worker.
if [ ! -s "$PAYLOAD_FILE" ]; then
    prepare_result FAIL semantic_payload_missing 0 0 1 0 0
    notify_warn "[WARN] ${CMD_ID} semantic causal audit payload is missing"
    publish_result
    exit 0
fi
if ! timeout 30 bash "$SCRIPT_DIR/scripts/semantic_index_update.sh" \
    cmd_complete "$(cat "$PAYLOAD_FILE")"; then
    prepare_result FAIL semantic_index_update_failed 0 0 1 0 0
    notify_warn "[WARN] ${CMD_ID} semantic index update failed before causal audit"
    publish_result
    exit 0
fi
if [ -f "$SCRIPT_DIR/scripts/semantic_map_generate.sh" ]; then
    timeout 30 bash "$SCRIPT_DIR/scripts/semantic_map_generate.sh" || \
        printf '%s [%s] semantic-map regeneration WARN\n' "$(date -Iseconds)" "$CMD_ID"
fi

traverse_output="$(timeout 20 bash "$SCRIPT_DIR/scripts/semantic_causal_traverse.sh" \
    --cmd-id "$CMD_ID" --depth 3 --format json 2>/dev/null || true)"
if [ -z "$traverse_output" ]; then
    prepare_result FAIL traverse_no_output 0 0 1 0 0
    notify_warn "[WARN] ${CMD_ID} semantic causal audit returned no output"
    publish_result
    exit 0
fi

if ! traverse_meta="$(python3 -c '
import json, sys
d=json.load(sys.stdin)
starts=",".join(d.get("start_concepts", [])) or "none"
print(d.get("total", 0), d.get("no_test_scripts_count", 0), starts)
' <<< "$traverse_output" 2>/dev/null)"; then
    prepare_result FAIL traverse_invalid_json 0 0 1 0 0
    notify_warn "[WARN] ${CMD_ID} semantic causal audit returned invalid JSON"
    publish_result
    exit 0
fi
read -r affected no_test starts <<< "$traverse_meta"

mapfile -t test_scripts < <(python3 -c '
import json, sys
d=json.load(sys.stdin); seen=set()
for node in d.get("affected_nodes", []):
    for path in node.get("test_scripts", []):
        if path not in seen:
            seen.add(path); print(path)
' <<< "$traverse_output")

tests_pass=0
tests_fail=0
tests_missing=0
failures=()
for test_script in "${test_scripts[@]}"; do
    test_path="$SCRIPT_DIR/$test_script"
    if [ ! -f "$test_path" ]; then
        tests_missing=$((tests_missing + 1))
        failures+=("missing:$test_script")
        continue
    fi
    if [[ "$test_script" == *.bats ]]; then
        test_cmd=(bats "$test_path")
    else
        test_cmd=(bash "$test_path")
    fi
    if env SHOGUN_HEAVY_JOB_LOCK_HELD=0 bash "$SCRIPT_DIR/scripts/heavy_job_admission.sh" -- \
        timeout 60 "${test_cmd[@]}" >/dev/null 2>&1; then
        tests_pass=$((tests_pass + 1))
    else
        tests_fail=$((tests_fail + 1))
        failures+=("failed:$test_script")
    fi
done

state=PASS
reason=ok
if [ "$tests_fail" -gt 0 ] || [ "$tests_missing" -gt 0 ]; then
    state=FAIL
    reason=test_failure
elif [ "$no_test" -gt 0 ]; then
    state=WARN
    reason=nodes_without_tests
fi

prepare_result "$state" "$reason" "$affected" "$tests_pass" "$tests_fail" "$tests_missing" "$no_test"
printf '%s [%s] state=%s affected=%s pass=%s fail=%s missing=%s no_test=%s\n' \
    "$(date -Iseconds)" "$CMD_ID" "$state" "$affected" "$tests_pass" "$tests_fail" "$tests_missing" "$no_test"

if [ "$state" != PASS ]; then
    notify_warn "[WARN] ${CMD_ID} semantic causal audit ${state}: fail=${tests_fail} missing=${tests_missing} nodes_without_tests=${no_test} ${failures[*]:-}"
fi
if [ "$affected" -gt 0 ] && [ "$starts" != none ]; then
    BULLETIN_NOTIFY=karo,gunshi timeout 10 bash "$SCRIPT_DIR/scripts/bulletin_write.sh" \
        system "因果トラバース ${CMD_ID}: 起点[${starts}] → 影響${affected}ノード(depth=3), audit=${state}" false info >/dev/null 2>&1 || true
fi
publish_result
