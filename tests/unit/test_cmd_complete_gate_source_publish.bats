#!/usr/bin/env bats

# test_necessity: source-only publication proof must bind the exact remote tip;
# a stale receipt cannot mark a non-contained, non-equivalent source as published.
#
# test_necessity: cmd_complete_gate_publisher_origin_ready
# (cmd_karo_hotfix_cmd_complete_post_source_async_202609031931) must defer
# origin-ancestor resolution to the publisher's own already_published(rc=0)
# event for the exact task-id+source-sha pair, and fail closed (bounded wait,
# no false PASS) when no matching positive event exists yet.

setup_file() {
    export GATE_SOURCE_PUBLISH_HELPERS="$BATS_FILE_TMPDIR/source_publish_helpers.sh"
    python3 - "$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh" >"$GATE_SOURCE_PUBLISH_HELPERS" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
names = (
    "source_publish_receipt_matches",
    "cmd_complete_gate_publisher_origin_ready",
    "queue_postclear_publication_followup",
)
chunks = []
for name in names:
    match = re.search(r"(?ms)^" + re.escape(name) + r"\(\) \{.*?^\}", text)
    if match is None:
        raise SystemExit(name + " helper not found")
    chunks.append(match.group(0))
print("\n\n".join(chunks))
PY

    # cmd_karo_hotfix_t3s40_post_source_v6 (RC 2nd): the durable-queue helpers
    # (queue-record -> worker -> recovery sweep for the 4 non-critical GATE
    # CLEAR side effects) extracted the same way as above, for the AC2
    # durability behavioral fixture below.
    export GATE_SOURCE_PUBLISH_HELPERS_DURABLE="$BATS_FILE_TMPDIR/source_publish_helpers_durable.sh"
    python3 - "$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh" >"$GATE_SOURCE_PUBLISH_HELPERS_DURABLE" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
names = (
    "gate_notify_pending_path",
    "gate_notify_done_path",
    "gate_notify_enqueue",
    "gate_notify_complete",
    "gate_run_gunshi_reflux_feedback",
    "gate_run_gunshi_reflux_only",
    "gate_run_gunshi_verdict_update",
    "gate_notify_reconcile_stale",
)
chunks = []
for name in names:
    match = re.search(r"(?ms)^" + re.escape(name) + r"\(\) \{.*?^\}", text)
    if match is None:
        raise SystemExit(name + " helper not found")
    chunks.append(match.group(0))
print("\n\n".join(chunks))
PY
}

@test "stale receipt cannot mark current non-equivalent remote tip published" {
    local base="$BATS_TEST_TMPDIR/stale-receipt"
    local receipt="$base/receipt.json"
    local marker="$base/marker"
    local generation="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    local source_sha="1111111111111111111111111111111111111111"
    local old_remote="2222222222222222222222222222222222222222"
    local current_remote="3333333333333333333333333333333333333333"
    mkdir -p "$base"

    cat >"$receipt" <<EOF
{"version":1,"state":"published","cmd_id":"cmd_stale_receipt_probe","completion_generation":"$generation","entries":[{"cmd_id":"cmd_stale_receipt_probe","completion_generation":"$generation","report_generation":"rpt-stale","repo":"$base/repo","source_sha":"$source_sha","remote_tip":"$old_remote","remote_contains_source_rc":0}]}
EOF
    source "$GATE_SOURCE_PUBLISH_HELPERS"
    run source_publish_receipt_matches "$receipt" cmd_stale_receipt_probe "$generation" "$base/repo" "$current_remote" "$source_sha" rpt-stale
    [ "$status" -ne 0 ]

    if source_publish_receipt_matches "$receipt" cmd_stale_receipt_probe "$generation" "$base/repo" "$current_remote" "$source_sha" rpt-stale; then
        printf '%s\n' "$current_remote" >"$marker"
    fi
    [ ! -e "$marker" ]
}

@test "publisher origin-ready: matching already_published(rc=0) event resolves immediately" {
    local base="$BATS_TEST_TMPDIR/origin-ready-positive"
    local source_sha="1111111111111111111111111111111111111111"
    mkdir -p "$base/publish_queue"
    cat >"$base/publish_queue/events.jsonl" <<EOF
{"seq":1,"ts":"2026-09-03T10:00:00.000Z","kind":"already_published","request":"cmd_origin_ready_probe","rc":0,"reason":"identity=source_commit:$source_sha origin_tip=2222222222222222222222222222222222222222","pid":1}
EOF
    source "$GATE_SOURCE_PUBLISH_HELPERS"
    local ids=(cmd_origin_ready_probe)
    SHOGUN_STATE_DIR="$base" CMD_COMPLETE_GATE_ORIGIN_ANCESTOR_WAIT_SECONDS=5 \
        run cmd_complete_gate_publisher_origin_ready ids "$source_sha"
    [ "$status" -eq 0 ]
}

@test "publisher origin-ready: no matching event fails closed within the bounded wait" {
    local base="$BATS_TEST_TMPDIR/origin-ready-negative"
    local source_sha="1111111111111111111111111111111111111111"
    local other_sha="9999999999999999999999999999999999999999"
    mkdir -p "$base/publish_queue"
    # Same request id, but neither a matching source sha nor rc=0 kind=already_published.
    cat >"$base/publish_queue/events.jsonl" <<EOF
{"seq":1,"ts":"2026-09-03T10:00:00.000Z","kind":"already_published","request":"cmd_origin_ready_probe","rc":0,"reason":"identity=source_commit:$other_sha origin_tip=2222222222222222222222222222222222222222","pid":1}
{"seq":2,"ts":"2026-09-03T10:00:01.000Z","kind":"c2a_rc","request":"cmd_origin_ready_probe","rc":1,"reason":"base_blob_mismatch path=$source_sha","pid":1}
EOF
    source "$GATE_SOURCE_PUBLISH_HELPERS"
    local ids=(cmd_origin_ready_probe)
    local start_ts end_ts elapsed
    start_ts=$(date +%s)
    SHOGUN_STATE_DIR="$base" CMD_COMPLETE_GATE_ORIGIN_ANCESTOR_WAIT_SECONDS=1 \
        run cmd_complete_gate_publisher_origin_ready ids "$source_sha"
    end_ts=$(date +%s)
    elapsed=$((end_ts - start_ts))
    [ "$status" -ne 0 ]
    [ "$elapsed" -le 3 ]
}

# test_necessity: cmd_karo_hotfix_t3s40_post_source_perf_202609032243 (re-deploy
# of cmd_karo_hotfix_cmd_complete_post_source_async_202609031931): production
# measured post_source_checks max ~60s / p50 16.1s->27.5s despite the 10s
# configured ceiling, because each 0.5s poll iteration re-encoded the
# invariant ids/source_shas via two extra python3 spawns and the elapsed
# check only ran *after* a (possibly slow, CPU-contended) python3 check
# completed. A stalled/slow single check must not be able to push the total
# wait past CMD_COMPLETE_GATE_ORIGIN_ANCESTOR_WAIT_SECONDS.
@test "publisher origin-ready: a stalled per-iteration check is still hard-bounded to the configured timeout" {
    local base="$BATS_TEST_TMPDIR/origin-ready-slow-check"
    local source_sha="1111111111111111111111111111111111111111"
    local other_sha="9999999999999999999999999999999999999999"
    mkdir -p "$base/publish_queue"
    cat >"$base/publish_queue/events.jsonl" <<EOF
{"seq":1,"ts":"2026-09-03T10:00:00.000Z","kind":"already_published","request":"cmd_origin_ready_probe","rc":0,"reason":"identity=source_commit:$other_sha origin_tip=2222222222222222222222222222222222222222","pid":1}
EOF

    # Stub python3 only stalls the per-iteration heredoc check (invoked as
    # `python3 - <<PY`, i.e. first arg "-"). The one-time ids/source_shas
    # encoding (`python3 -c ...`) must stay real so the function has valid
    # JSON to poll with. Resolve the real interpreter's absolute path before
    # writing the stub: re-dispatching through `python3` by name would
    # re-resolve via the overridden PATH below and recurse into this same
    # stub forever instead of reaching the real interpreter.
    local real_python3
    real_python3="$(command -v python3)"
    local stub_dir="$BATS_TEST_TMPDIR/slow-python-bin"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/python3" <<STUB
#!/usr/bin/env bash
if [ "\$1" = "-" ]; then
    exec sleep 100
fi
exec "$real_python3" "\$@"
STUB
    chmod +x "$stub_dir/python3"

    source "$GATE_SOURCE_PUBLISH_HELPERS"
    local ids=(cmd_origin_ready_probe)
    local start_ts end_ts elapsed
    start_ts=$(date +%s)
    PATH="$stub_dir:$PATH" SHOGUN_STATE_DIR="$base" CMD_COMPLETE_GATE_ORIGIN_ANCESTOR_WAIT_SECONDS=2 \
        run cmd_complete_gate_publisher_origin_ready ids "$source_sha"
    end_ts=$(date +%s)
    elapsed=$((end_ts - start_ts))
    [ "$status" -ne 0 ]
    [ "$elapsed" -le 5 ]
}

# test_necessity: cmd_karo_hotfix_t3s40_post_source_v3_202609040000 AC1/AC2.
# Production evidence (bulletin msg_20260903_235739_1881534_35233737 /
# docs/research/tsumari_root_causes_20260901.md T3-S-40, cmd
# cmd_karo_hotfix_t3s40_post_source_perf_202609032243, 23:29 cycle):
# postclear_followup.push_task_repositories=6.022s,
# post_source_checks.durable_writer_wait=10.791s. Both run inside
# queue_postclear_publication_followup's detached background subshell
# (trailing `&`); the caller must never observe either delay, or a
# regression that drops the trailing `&` would silently re-inflate the
# synchronous post_source_checks subphase past the 5s p50 / 10s max target.
@test "queue_postclear_publication_followup stays non-blocking when the durable writer drain is slow" {
    local base="$BATS_TEST_TMPDIR/postclear-slow-durable"
    mkdir -p "$base"
    GATES_DIR="$base"
    CMD_ID="cmd_postclear_slow_durable_probe"
    MATCHING_TASK_FILES=()

    push_task_repositories() { return 0; }
    wait_for_postclear_durable_writers() { sleep 8; return 0; }
    publish_postclear_runtime_deltas() { return 0; }
    gate_detail_begin() { :; }
    gate_detail_finish() { :; }

    source "$GATE_SOURCE_PUBLISH_HELPERS"

    local start_ts end_ts elapsed
    start_ts=$(date +%s)
    queue_postclear_publication_followup
    end_ts=$(date +%s)
    elapsed=$((end_ts - start_ts))
    [ "$elapsed" -le 2 ]

    wait
    grep -qF "$(printf '\t%s\t0\t0\t0' "$CMD_ID")" "$base/postclear_publication.log"
}

@test "queue_postclear_publication_followup stays non-blocking when push_task_repositories is slow" {
    local base="$BATS_TEST_TMPDIR/postclear-slow-push"
    mkdir -p "$base"
    GATES_DIR="$base"
    CMD_ID="cmd_postclear_slow_push_probe"
    MATCHING_TASK_FILES=()

    push_task_repositories() { sleep 8; return 0; }
    wait_for_postclear_durable_writers() { return 0; }
    publish_postclear_runtime_deltas() { return 0; }
    gate_detail_begin() { :; }
    gate_detail_finish() { :; }

    source "$GATE_SOURCE_PUBLISH_HELPERS"

    local start_ts end_ts elapsed
    start_ts=$(date +%s)
    queue_postclear_publication_followup
    end_ts=$(date +%s)
    elapsed=$((end_ts - start_ts))
    [ "$elapsed" -le 2 ]

    wait
    grep -qF "$(printf '\t%s\t0\t0\t0' "$CMD_ID")" "$base/postclear_publication.log"
}

@test "queue_postclear_publication_followup: normal path finishes end-to-end well under the 10s ceiling" {
    local base="$BATS_TEST_TMPDIR/postclear-normal"
    mkdir -p "$base"
    GATES_DIR="$base"
    CMD_ID="cmd_postclear_normal_probe"
    MATCHING_TASK_FILES=()

    push_task_repositories() { return 0; }
    wait_for_postclear_durable_writers() { return 0; }
    publish_postclear_runtime_deltas() { return 0; }
    gate_detail_begin() { :; }
    gate_detail_finish() { :; }

    source "$GATE_SOURCE_PUBLISH_HELPERS"

    local start_ts end_ts elapsed
    start_ts=$(date +%s)
    queue_postclear_publication_followup
    wait
    end_ts=$(date +%s)
    elapsed=$((end_ts - start_ts))
    [ "$elapsed" -le 10 ]
    grep -qF "$(printf '\t%s\t0\t0\t0' "$CMD_ID")" "$base/postclear_publication.log"
}

# test_necessity: AC2 requires the region between capture_rework_event and
# queue_postclear_publication_followup to have zero unmeasured detail-log
# gap (production showed ~6-13s unaccounted there). Assert the wrapping
# post_source_checks.finalize_pre_postclear span exists, precedes the call,
# and is the only gate_detail_begin/finish pair in that stretch (no nested
# begin re-opens/steals the span before it is explicitly closed), and that
# the semantic memory scan that used to run synchronously inside that
# stretch is launched through the async queue wrapper instead.
@test "post_source finalize_pre_postclear span is exclusive and semantic memory scan runs off the sync path" {
    local gate_script="$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh"

    ! grep -q 'run_report_memory_semantic_scan ||' "$gate_script"
    grep -q '^queue_report_memory_semantic_scan()' "$gate_script"
    grep -q '    queue_report_memory_semantic_scan$' "$gate_script"

    local finalize_begin_line followup_line
    finalize_begin_line=$(grep -n 'gate_detail_begin "post_source_checks.finalize_pre_postclear"' "$gate_script" | head -1 | cut -d: -f1)
    followup_line=$(grep -n '^    queue_postclear_publication_followup$' "$gate_script" | tail -1 | cut -d: -f1)
    [ -n "$finalize_begin_line" ]
    [ -n "$followup_line" ]
    [ "$finalize_begin_line" -lt "$followup_line" ]

    local begin_count finish_count
    begin_count=$(sed -n "$((finalize_begin_line + 1)),$((followup_line - 1))p" "$gate_script" | grep -c 'gate_detail_begin' || true)
    finish_count=$(sed -n "$((finalize_begin_line + 1)),$((followup_line - 1))p" "$gate_script" | grep -c 'gate_detail_finish' || true)
    [ "$begin_count" -eq 0 ]
    [ "$finish_count" -eq 1 ]
}

# test_necessity: cmd_karo_hotfix_t3s40_post_source_v6 AC2 (RC 2nd, msg_20260904_044654).
# v5 code-audited >=10 synchronous subprocess starts inside
# finalize_pre_postclear; a first RC cut (plain `&`, then nohup+setsid) moved
# them off the synchronous path but karo rejected both: neither recovers work
# that never started (crash before the worker launches) or was in-flight
# across a full process/OS restart with no later re-invocation for the same
# cmd. This checks that each of the 4 stateful side effects (gunshi reflux
# x2, gunshi review_feedback, gunshi_verdict update, clear notifications) is
# wrapped in the queue-record (gate_notify_enqueue) -> worker
# (gate_run_gunshi_*/send_clear_notifications_once) -> gate_notify_complete
# durable-queue shape, and that reflux still textually precedes
# review_feedback inside the same subshell (ordering survives the redesign).
# workaround-rate stays plain background (no persistent side effect to lose,
# purely informational). False positive here = a claimed "durable async"
# label with no real gate_notify_enqueue/complete pairing (a crash would
# silently drop the work with no queue record to recover it from).
@test "AC2 positive: gunshi reflux/review_feedback/verdict/clear-notify side effects go through the durable queue (enqueue -> worker -> complete)" {
    local gate_script="$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh"

    # gunshi_gate_reflux (1st run) + gunshi review_feedback: durable-queued as
    # one item (gunshi_reflux_feedback) via the shared gate_run_gunshi_reflux_feedback
    # worker, which must itself still run reflux before the feedback notify.
    grep -q '^    gate_notify_enqueue "\$CMD_ID" gunshi_reflux_feedback$' "$gate_script"
    grep -q '^        gate_run_gunshi_reflux_feedback "\$CMD_ID"$' "$gate_script"
    grep -q '^        gate_notify_complete "\$CMD_ID" gunshi_reflux_feedback$' "$gate_script"
    local reflux_rel feedback_rel
    reflux_rel=$(sed -n '/^gate_run_gunshi_reflux_feedback() {/,/^}/p' "$gate_script" | grep -n 'gunshi_gate_reflux.sh"' | head -1 | cut -d: -f1)
    feedback_rel=$(sed -n '/^gate_run_gunshi_reflux_feedback() {/,/^}/p' "$gate_script" | grep -n 'inbox_write.sh" gunshi ' | head -1 | cut -d: -f1)
    [ -n "$reflux_rel" ]
    [ -n "$feedback_rel" ]
    [ "$reflux_rel" -lt "$feedback_rel" ]

    # gunshi_verdict update: durable-queued via gate_run_gunshi_verdict_update.
    grep -q '^    gate_notify_enqueue "\$CMD_ID" gunshi_verdict_update$' "$gate_script"
    grep -q '^        gate_run_gunshi_verdict_update "\$CMD_ID"$' "$gate_script"
    grep -q '^        gate_notify_complete "\$CMD_ID" gunshi_verdict_update$' "$gate_script"

    # gunshi_gate_reflux 2nd run: durable-queued via gate_run_gunshi_reflux_only.
    grep -q '^        gate_notify_enqueue "\$CMD_ID" gunshi_reflux_2nd$' "$gate_script"
    grep -q '^            gate_run_gunshi_reflux_only "\$CMD_ID"$' "$gate_script"
    grep -q '^            gate_notify_complete "\$CMD_ID" gunshi_reflux_2nd$' "$gate_script"

    # Workaround-rate display: no persistent side effect to lose, so it stays
    # plain background (not durable-queued) — explicitly NOT enqueued.
    ! grep -q 'gate_notify_enqueue "\$CMD_ID" workaround_rate' "$gate_script"
    grep -q 'workaround_rate: queued (async' "$gate_script"

    # Terminal shogun/karo notifications: durable-queued (item=clear_notify),
    # matching the case arm gate_notify_reconcile_stale replays on recovery.
    grep -q '^    gate_notify_enqueue "\$CMD_ID" clear_notify$' "$gate_script"
    grep -q '^        send_clear_notifications_once "\$CMD_ID" "GATE CLEAR terminal"$' "$gate_script"
    grep -q '^        gate_notify_complete "\$CMD_ID" clear_notify$' "$gate_script"
    grep -q 'clear_notify)' "$gate_script"
}

# test_necessity: cmd_karo_hotfix_t3s40_post_source_v6 AC2 (RC 2nd). Structural
# proof that the recovery sweep (a) is defined once and called exactly once,
# unconditionally, near the top of the script (so it runs for every cmd's
# invocation, not just this one — recovery must not depend on the SAME cmd or
# process running again) and (b) is guarded so an internal error can never
# propagate into this cmd's own gate decision.
@test "AC2 positive: gate_notify_reconcile_stale is invoked exactly once, unconditionally, and fail-open" {
    local gate_script="$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh"
    grep -q '^gate_notify_reconcile_stale() {' "$gate_script"
    local call_count
    call_count=$(grep -c '^gate_notify_reconcile_stale || true$' "$gate_script")
    [ "$call_count" -eq 1 ]
}

# test_necessity: cmd_karo_hotfix_t3s40_post_source_v6 AC2 (RC 2nd) durability
# fixture — behavioral, not just structural. Proves the actual failure mode
# karo named: a worker that never even launches (crash between enqueue and
# worker start, or the process/OS dying before either runs) is still
# recovered, because the reservation lives on disk under queue/gates/ and any
# later invocation's gate_notify_reconcile_stale sweep (here: a direct call,
# modeling "some other cmd's GATE ran later") picks it up and completes it —
# using the REAL gate_run_gunshi_verdict_update from cmd_complete_gate.sh
# itself (extracted the same way GATE_SOURCE_PUBLISH_HELPERS already is),
# not a reimplementation. Also proves idempotency (a second reconcile sweep
# after completion is a no-op) and that a fresh (non-stale) pending record is
# left alone rather than raced against a legitimately in-flight worker.
@test "AC2 durability: a worker that never launches is recovered by a later reconcile sweep, and recovery is idempotent" {
    local base="$BATS_TEST_TMPDIR/durable-queue-recovery"
    mkdir -p "$base/scripts" "$base/logs"
    SCRIPT_DIR="$base"
    LOG_DIR="$base/logs"
    lock_path() { printf '%s.lock\n' "$1"; }

    source "$GATE_SOURCE_PUBLISH_HELPERS_DURABLE"

    # Step 1: enqueue (the reservation record this cmd's dispatch would have
    # written) but never launch any worker — models a crash between the
    # queue-record write and the worker actually starting, which neither
    # plain `&` nor nohup+setsid can ever recover from on their own.
    gate_notify_enqueue cmd_recover_probe gunshi_verdict_update
    local pending done
    pending="$(gate_notify_pending_path cmd_recover_probe gunshi_verdict_update)"
    done="$(gate_notify_done_path cmd_recover_probe gunshi_verdict_update)"
    [ -f "$pending" ]
    [ ! -f "$done" ]
    # No gunshi_review_log.yaml/cmd_design_quality.yaml exist under $base, so
    # the real worker's own SKIP branch proves it actually ran (not skipped
    # by the harness) when reconcile replays it below.

    # Step 2: force staleness (0s threshold) and let a later, independent
    # reconcile sweep — this is deliberately just gate_notify_reconcile_stale
    # itself, i.e. what any future cmd's own gate invocation would run —
    # recover it, entirely in-process (no export -f/declare -f).
    GATE_NOTIFY_STALE_AFTER_S=0 gate_notify_reconcile_stale
    [ -f "$done" ]
    [ ! -f "$pending" ]
    grep -q 'gate_notify_reconcile: recovering stale cmd_recover_probe/gunshi_verdict_update' "$LOG_DIR/cmd_complete_gate_async.log"
    grep -q 'SKIP (cmd_design_quality.yaml or gunshi_review_log.yaml not found)' "$LOG_DIR/cmd_complete_gate_async.log"

    # Step 3: idempotency — a second sweep after done must not replay it.
    local before_lines after_lines
    before_lines=$(wc -l < "$LOG_DIR/cmd_complete_gate_async.log")
    GATE_NOTIFY_STALE_AFTER_S=0 gate_notify_reconcile_stale
    after_lines=$(wc -l < "$LOG_DIR/cmd_complete_gate_async.log")
    [ "$before_lines" -eq "$after_lines" ]

    # Step 4: a fresh (not-yet-stale) pending record for a different item is
    # left alone — a large stale_after threshold must not sweep it early,
    # protecting a legitimately in-flight worker from being raced.
    gate_notify_enqueue cmd_recover_probe2 clear_notify
    GATE_NOTIFY_STALE_AFTER_S=3600 gate_notify_reconcile_stale
    [ -f "$(gate_notify_pending_path cmd_recover_probe2 clear_notify)" ]
    [ ! -f "$(gate_notify_done_path cmd_recover_probe2 clear_notify)" ]
}

# test_necessity: cmd_karo_hotfix_t3s40_post_source_v6 AC2 negative fixture.
# AC2 requires keeping "必須状態遷移のみ同期保持" (only essential state
# transitions stay synchronous). A false negative here = one of these three
# fail-closed state transitions getting accidentally backgrounded by a future
# edit, which would let GATE CLEAR return before the durable marker/quality
# log/terminal status row is actually persisted (session-boundary kill would
# then silently lose it, reproducing the exact class of bug documented at
# INS-20260709-000457431-b624 for cmd_quality_log.sh).
@test "AC2 negative: durable CLEAR marker, cmd_quality_log, and terminal status stay synchronous and fail-closed" {
    local gate_script="$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh"

    # Durable CLEAR marker write: "Everything above this point is fail-closed"
    # boundary comment; must still hard BLOCK (exit 1) on persist failure and
    # must not be backgrounded.
    local marker_line
    marker_line=$(grep -n 'if ! python3 - "\$CMD_COMPLETE_GATE_CLEAR_MARKER" "\$CMD_ID" \\$' "$gate_script" | head -1 | cut -d: -f1)
    [ -n "$marker_line" ]
    sed -n "${marker_line}p" "$gate_script" | grep -qv ' &[[:space:]]*$'
    grep -q 'echo "GATE BLOCK: \${CMD_ID}:durable_clear_marker_persist_failed"' "$gate_script"

    # cmd_quality_log.sh: documented synchronous-by-design (INS-20260709-000457431-b624).
    local cql_line
    cql_line=$(grep -n 'bash "\$SCRIPT_DIR/scripts/cmd_quality_log.sh" "\$CMD_ID" "CLEAR"' "$gate_script" | head -1 | cut -d: -f1)
    [ -n "$cql_line" ]
    sed -n "${cql_line}p" "$gate_script" | grep -qv ' &[[:space:]]*$'
    grep -q '同期実行必須(INS-20260709-000457431-b624)' "$gate_script"

    # Terminal "status: completed" write: must still hard BLOCK (exit 1) on
    # setter failure and must not be backgrounded.
    local status_line
    status_line=$(grep -n 'yaml_field_set.sh" "\$YAML_FILE" "\$CMD_ID" status completed' "$gate_script" | head -1 | cut -d: -f1)
    [ -n "$status_line" ]
    sed -n "${status_line}p" "$gate_script" | grep -qv ' &[[:space:]]*$'
    grep -q 'echo "GATE BLOCK: \${CMD_ID}:status_completed_publish_failed"' "$gate_script"
}
