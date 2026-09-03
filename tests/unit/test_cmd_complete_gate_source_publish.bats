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
    "cmd_complete_gate_queue_auto_push_ancestry_retry",
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

    # cmd_karo_hotfix_t3s40_post_source_full_instrumentation AC1/AC2: real
    # gate_detail_begin/finish/gate_subphase_tick (the span primitives
    # themselves) plus the literal WAIT-path code -- the L4 ancestry
    # if/elif/else block and the else/wait_block_finalize tail that follows
    # it -- extracted verbatim (not reimplemented) so the dynamic coverage
    # fixture below runs the actual production control flow, not a
    # hand-written stand-in that could silently drift from it.
    export GATE_DETAIL_SPAN_HELPERS="$BATS_FILE_TMPDIR/gate_detail_span_helpers.sh"
    python3 - "$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh" >"$GATE_DETAIL_SPAN_HELPERS" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
lines = text.split("\n")

def find_line(substr, start_from=0):
    for i in range(start_from, len(lines)):
        if substr in lines[i]:
            return i
    raise SystemExit("anchor not found: " + substr)

def extract_func(name):
    match = re.search(r"(?ms)^" + re.escape(name) + r"\(\) \{.*?^\}", text)
    if match is None:
        raise SystemExit(name + " not found")
    return match.group(0)

chunks = []
for name in (
    "gate_phase_now_us",
    "gate_detail_now_us",
    "gate_detail_finish",
    "gate_detail_begin",
    "gate_subphase_tick",
):
    chunks.append(extract_func(name))
# gate_phase_tick/GATE_PHASE_LOG govern a separate, coarser log this fixture
# does not exercise; gate_phase_finish's real body is
# "gate_phase_tick terminal; gate_subphase_finish" -- keep only the half that
# closes the subphase clock this fixture measures.
chunks.append('gate_subphase_finish() { gate_subphase_tick "terminal"; }')
chunks.append('gate_phase_finish() { gate_subphase_tick "terminal"; }')

# --- WAIT path L4 ancestry block: `if [ "$ALL_CLEAR" = true ]; then` two
# lines above the unique L4 heading, through its own matching top-level
# (column-0) `fi`. ---
l4_anchor = find_line('level_heading "[L4]" "Report commit main ancestry check:"')
l4_start = l4_anchor - 2
assert lines[l4_start].strip() == 'if [ "$ALL_CLEAR" = true ]; then', lines[l4_start]
l4_end = None
for i in range(l4_start + 1, len(lines)):
    if lines[i] == "fi":
        l4_end = i
        break
assert l4_end is not None, "L4 block closing fi not found"
chunks.append("run_wait_l4_block() {\n" + "\n".join(lines[l4_start:l4_end + 1]) + "\n}")

# --- WAIT path tail: the else-branch body (block-reason classification +
# metrics append + rotate_gate_metrics.sh + the self-contained
# `if [ "$_gate_record_category" = WAIT ]; then ... fi`), excluding the
# outer `else`/`fi` keywords themselves so the body stands alone as a valid
# function. ---
tail_anchor = find_line(
    "cmd_karo_hotfix_t3s40_post_source_full_instrumentation: block-reason"
)
tail_else_line = tail_anchor - 1
assert lines[tail_else_line].strip() == "else", lines[tail_else_line]
wait_if_anchor = find_line('if [ "$_gate_record_category" = WAIT ]; then')
tail_end = None
for i in range(wait_if_anchor + 1, len(lines)):
    if lines[i] == "    fi":
        tail_end = i
        break
assert tail_end is not None, "WAIT tail block closing fi not found"
chunks.append(
    "run_wait_tail_block() {\n"
    + "\n".join(lines[tail_else_line + 1:tail_end + 1])
    + "\n}"
)

print("\n\n".join(chunks))
PY
    bash -n "$GATE_DETAIL_SPAN_HELPERS"
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

# test_necessity: cmd_karo_hotfix_t3s40_auto_push_wait_async AC2. Production
# evidence (cmd_karo_hotfix_t3s40_post_source_full_instrumentation) measured
# post_source_checks.report_commit_main_ancestry.auto_push_wait
# (cmd_complete_gate_auto_push_ancestry_wait -> push_task_repositories) as a
# ~28.043s unnamed residual dominating the WAIT cycle. The L4 caller's gate
# decision is already fail-closed WAIT the instant the ancestry boundary is
# unresolved, independent of this retry's outcome, so the retry must never
# block the current gate invocation. False negative here = a regression that
# drops the trailing `&`, silently re-inflating post_source_checks past the
# ~28s the production cycle measured.
@test "cmd_complete_gate_queue_auto_push_ancestry_retry stays non-blocking when the underlying push retry is slow" {
    local base="$BATS_TEST_TMPDIR/auto-push-retry-slow"
    mkdir -p "$base"
    GATES_DIR="$base"
    CMD_ID="cmd_auto_push_retry_slow_probe"

    cmd_complete_gate_auto_push_ancestry_wait() { sleep 8; return 0; }

    source "$GATE_SOURCE_PUBLISH_HELPERS"

    local start_ts end_ts elapsed
    start_ts=$(date +%s)
    cmd_complete_gate_queue_auto_push_ancestry_retry task1.yaml task2.yaml
    end_ts=$(date +%s)
    elapsed=$((end_ts - start_ts))
    [ "$elapsed" -le 2 ]

    wait
    grep -qF "$(printf '\t%s\tPASS' "$CMD_ID")" "$base/auto_push_ancestry_retry.log"
}

# test_necessity: false-positive guard for the same fixture -- a failed
# underlying retry (push_task_repositories exhausted its own retries and
# failed closed) must still record a distinguishable outcome, not be silently
# swallowed as if it had passed, so a human/monitor scanning the retry log can
# tell a still-unresolved boundary from a landed one.
@test "cmd_complete_gate_queue_auto_push_ancestry_retry records a distinguishable outcome when the underlying push retry fails" {
    local base="$BATS_TEST_TMPDIR/auto-push-retry-fail"
    mkdir -p "$base"
    GATES_DIR="$base"
    CMD_ID="cmd_auto_push_retry_fail_probe"

    cmd_complete_gate_auto_push_ancestry_wait() { return 1; }

    source "$GATE_SOURCE_PUBLISH_HELPERS"

    cmd_complete_gate_queue_auto_push_ancestry_retry task1.yaml
    wait
    grep -qF "$(printf '\t%s\tFAIL' "$CMD_ID")" "$base/auto_push_ancestry_retry.log"
    ! grep -qF "$(printf '\t%s\tPASS' "$CMD_ID")" "$base/auto_push_ancestry_retry.log"
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

# test_necessity: cmd_karo_hotfix_t3s40_auto_push_wait_async AC2 (WAIT
# fixture, updated from the cmd_karo_hotfix_t3s40_post_source_full_instrumentation
# version). Runs the ACTUAL WAIT-path source (the L4 ancestry block and the
# wait_block_finalize tail, extracted verbatim by setup_file, not
# reimplemented) with the real gate_detail_begin/finish/gate_subphase_tick
# span primitives and a stubbed cmd_complete_gate_queue_auto_push_ancestry_retry
# (the fire-and-forget dispatcher that replaced the direct, blocking
# cmd_complete_gate_auto_push_ancestry_wait call -- the ~28.043s residual
# AC1 confirmed) returning immediately, matching its real non-blocking
# contract (proved separately above). false_positive = an unexpected/
# duplicate span label (would mean a span re-opened without closing, double
# counting time); false_negative = named_sum falling under the total (a
# still-unwrapped region). Asserts both are 0, coverage >=95%, and the
# fixture itself produces no additional FAIL/SKIP (a non-zero exit from
# run_wait_tail_block other than the expected WAIT-path 1 would be exactly
# that).
@test "AC2 WAIT fixture: post_source_checks named span coverage is >=95% with 0 false positives/negatives" {
    source "$GATE_DETAIL_SPAN_HELPERS"

    local base="$BATS_TEST_TMPDIR/wait-coverage"
    mkdir -p "$base/gates"
    GATE_DETAIL_LOG="$base/details.log"
    GATE_SUBPHASE_LOG="$base/subphases.log"
    GATE_DETAIL_LOG_MAX_BYTES=5242880
    GATE_DETAIL_LOG_ROTATION_CHECKED=false
    GATE_DETAIL_CURRENT=""
    GATE_DETAIL_CLASS=""
    GATE_DETAIL_START_US=""
    GATE_SUBPHASE_LOG_MAX_BYTES=5242880
    GATE_SUBPHASE_LOG_ROTATION_CHECKED=false
    GATE_SUBPHASE_CURRENT=""
    GATE_SUBPHASE_START_US=""
    CMD_ID="cmd_wait_coverage_probe"
    SCRIPT_DIR="$base/no-such-scripts-dir"
    GATE_METRICS_LOG="$base/gate_metrics.log"
    GATES_DIR="$base/gates"
    GATE_TASK_TYPE="" GATE_MODEL="" GATE_BLOOM_LEVEL="" GATE_INJECTED_LESSONS=""
    CMD_TITLE="" GATE_FIRST_MODEL_METRIC="" ci_run_id="" ci_run_conclusion=""
    ALL_GATES=() DEFERRED_GATES=()
    ALL_CLEAR=true
    MATCHING_TASK_FILES=()
    BLOCK_REASONS=()
    WAIT_REASONS=()
    MISSING_GATES=()

    # Real function used verbatim; only the two production dependencies that
    # would otherwise touch git/network/disk are stubbed.
    level_heading() { :; }
    local _ancestry_calls=0
    check_report_commit_main_ancestry() {
        # This remains real synchronous work on the L4 sync path (unlike the
        # push retry, it was not moved off it). A fixed delay large enough to
        # dominate fork/flock/tick overhead (the same margin the original
        # fixture used before this task moved the ~28s push off this path)
        # keeps this span's share of the total stable against timer noise,
        # without fabricating time inside the (now near-instant) dispatch
        # span below.
        _ancestry_calls=$((_ancestry_calls + 1))
        sleep 3
        REPORT_COMMIT_MAIN_ANCESTRY_WAIT=true
        [ "$_ancestry_calls" -eq 1 ]
    }
    record_block_reason() { :; }
    record_wait_reason() { WAIT_REASONS+=("$1"); }
    cmd_complete_gate_queue_auto_push_ancestry_retry() {
        # Real contract: fire-and-forget dispatch that returns immediately
        # (see the dedicated non-blocking fixtures above); the ~28s
        # push_task_repositories work this replaced now runs detached and
        # must never appear inside this span's duration.
        return 0
    }
    classify_gate_record_reasons() { printf 'WAIT'; }
    append_line_locked() { :; }
    format_ci_raw_columns() { printf 'stub'; }

    gate_subphase_tick "post_source_checks"
    run_wait_l4_block
    run run_wait_tail_block
    [ "$status" -eq 1 ]

    [ -s "$GATE_DETAIL_LOG" ]
    [ -s "$GATE_SUBPHASE_LOG" ]

    local total named_sum label_count
    total=$(awk -F'\t' '$3=="post_source_checks"{print $4}' "$GATE_SUBPHASE_LOG")
    [ -n "$total" ]
    named_sum=$(awk -F'\t' '{sum+=$5} END{printf "%.6f", sum+0}' "$GATE_DETAIL_LOG")

    # false_positive check: exactly the 3 expected labels, each exactly once
    # (a duplicate would mean a span re-opened without its own begin, i.e.
    # double-counted/overlapping time). No .reverify span exists any more --
    # the synchronous reverify-after-inline-push step was removed along with
    # the blocking push itself.
    local expected_labels actual_labels
    expected_labels=$'post_source_checks.report_commit_main_ancestry\npost_source_checks.report_commit_main_ancestry.auto_push_wait\npost_source_checks.wait_block_finalize'
    actual_labels=$(awk -F'\t' '{print $4}' "$GATE_DETAIL_LOG" | sort)
    [ "$actual_labels" = "$(printf '%s\n' "$expected_labels" | sort)" ]

    # false_negative check + 95% floor, via python for float comparison.
    CMD_COMPLETE_GATE_TOTAL="$total" CMD_COMPLETE_GATE_NAMED_SUM="$named_sum" python3 - <<'PY'
import os
total = float(os.environ["CMD_COMPLETE_GATE_TOTAL"])
named_sum = float(os.environ["CMD_COMPLETE_GATE_NAMED_SUM"])
assert named_sum <= total + 0.01, f"named_sum {named_sum} exceeds total {total} (span overlap / false positive)"
coverage = named_sum / total
assert coverage >= 0.95, f"coverage {coverage:.4f} under the 95% floor (total={total}, named_sum={named_sum})"
PY
}

# test_necessity: cmd_karo_hotfix_t3s40_post_source_full_instrumentation AC2
# (CLEAR fixture, structural). The CLEAR path's dominant span
# (finalize_pre_postclear) already has its own exclusivity fixture above;
# this proves the two additions this task made -- clear_metrics_build
# (wraps the 4 build_clear_*/build_karo_ctx_metric subshell calls between
# capture_durable_writer_snapshot and cdp_production_check) and
# postclear_status_archive (wraps status/archive/notify-enqueue between
# queue_postclear_publication_followup and gate_phase_finish) -- leave no
# gap: begin/finish counts balance across every branch (including both
# early-exit failure arms of the status case statement), and the only
# non-span-wrapped statement in the connecting stretches is the
# already-proven-non-blocking queue_postclear_publication_followup dispatch
# itself. A false positive here = a claimed span whose begin/finish counts
# don't balance (an accidental early return leaves it permanently "open" for
# the next cmd's gate run); a false negative = a synchronous subprocess call
# outside every span in this stretch.
@test "AC2 CLEAR fixture: clear_metrics_build and postclear_status_archive spans close every gap with no orphaned begin" {
    local gate_script="$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh"

    # clear_metrics_build: begin immediately after the snapshot span's
    # finish, finish immediately before cdp_production_check's begin -- no
    # other gate_detail_begin/finish appears between them (a single,
    # non-overlapping pair).
    local metrics_begin cdp_begin
    metrics_begin=$(grep -n 'gate_detail_begin "post_source_checks.clear_metrics_build"' "$gate_script" | head -1 | cut -d: -f1)
    cdp_begin=$(grep -n 'gate_detail_begin "post_source_checks.cdp_production_check"' "$gate_script" | head -1 | cut -d: -f1)
    [ -n "$metrics_begin" ]; [ -n "$cdp_begin" ]
    [ "$metrics_begin" -lt "$cdp_begin" ]
    local metrics_span_begins metrics_span_finishes
    metrics_span_begins=$(sed -n "$((metrics_begin + 1)),$((cdp_begin - 1))p" "$gate_script" | grep -c 'gate_detail_begin' || true)
    metrics_span_finishes=$(sed -n "$((metrics_begin + 1)),$((cdp_begin - 1))p" "$gate_script" | grep -c 'gate_detail_finish' || true)
    [ "$metrics_span_begins" -eq 0 ]
    [ "$metrics_span_finishes" -eq 1 ]
    sed -n "$((cdp_begin - 1))p" "$gate_script" | grep -q 'gate_detail_finish'

    # postclear_status_archive: begin immediately follows the
    # queue_postclear_publication_followup dispatch (only comments/blank
    # lines between them -- that dispatch itself is the already-proven
    # non-blocking call, see the "stays non-blocking" fixtures above).
    local archive_begin followup_line
    archive_begin=$(grep -n 'gate_detail_begin "post_source_checks.postclear_status_archive"' "$gate_script" | head -1 | cut -d: -f1)
    followup_line=$(grep -n '^    queue_postclear_publication_followup$' "$gate_script" | tail -1 | cut -d: -f1)
    [ -n "$archive_begin" ]; [ -n "$followup_line" ]
    [ "$archive_begin" -gt "$followup_line" ]
    sed -n "$((followup_line + 1)),$((archive_begin - 1))p" "$gate_script" | grep -qvE '^\s*(#.*)?$' && {
        echo "non-comment statement between queue_postclear_publication_followup and postclear_status_archive begin" >&2
        return 1
    }

    # The span must close exactly once on the normal completion path,
    # immediately before gate_phase_finish (with two additional early-exit
    # finishes on the case statement's failure arms in between -- verified
    # by the existing "durable CLEAR marker/status/notify stay synchronous"
    # fixture's grep anchors on the same exit points).
    local phase_finish_line
    phase_finish_line=$(awk -v s="$archive_begin" 'NR>s && $0=="    gate_phase_finish"{print NR; exit}' "$gate_script")
    [ -n "$phase_finish_line" ]
    local nearest_nonblank
    nearest_nonblank=$(awk -v end="$phase_finish_line" 'NR<end && NF{last=$0} END{print last}' "$gate_script")
    printf '%s\n' "$nearest_nonblank" | grep -q 'gate_detail_finish'
    local total_begins total_finishes
    total_begins=$(sed -n "${archive_begin},${phase_finish_line}p" "$gate_script" | grep -c 'gate_detail_begin' || true)
    total_finishes=$(sed -n "${archive_begin},${phase_finish_line}p" "$gate_script" | grep -c 'gate_detail_finish' || true)
    [ "$total_begins" -eq 1 ]
    [ "$total_finishes" -eq 3 ]
}

# test_necessity: regression guard for the two dynamically-fixtured WAIT-path
# blocks above. Re-scans their literal source for any statement that spawns
# a subprocess (bash/python3/git -C/sleep/tmux/curl, or any $(...)/backtick
# command substitution) outside an open gate_detail_begin..gate_detail_finish
# span. A future edit that adds a new synchronous call inside either block
# without wrapping it would silently reopen the exact class of gap this task
# closed; this fails loudly instead the next time named_sum vs total drifts
# structurally, without needing to wait for another 28s production WAIT
# cycle to notice.
@test "AC2 regression guard: no synchronous subprocess call in the WAIT-path blocks sits outside a named span" {
    local gate_script="$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh"

    run python3 - "$gate_script" <<'PY'
import re
import sys
from pathlib import Path

gate_script = sys.argv[1]
text = Path(gate_script).read_text(encoding="utf-8")
lines = text.split("\n")

def find_line(substr, start_from=0):
    for i in range(start_from, len(lines)):
        if substr in lines[i]:
            return i
    raise SystemExit("anchor not found: " + substr)

risky = re.compile(r'\bbash\s+"|`|\$\(|\bpython3\b|\bgit\s+-C\b|\bsleep\b|\btmux\b|\bcurl\b')

def sweep(start, end, allow):
    open_span = False
    violations = []
    for i in range(start, end + 1):
        line = lines[i]
        if "gate_detail_begin" in line:
            open_span = True
            continue
        if "gate_detail_finish" in line:
            open_span = False
            continue
        if open_span:
            continue
        stripped = line.strip()
        if stripped.startswith("#") or stripped == "":
            continue
        if any(a in line for a in allow):
            continue
        if risky.search(line):
            violations.append((i + 1, line))
    return violations

l4_anchor = find_line('level_heading "[L4]" "Report commit main ancestry check:"')
l4_start = l4_anchor - 2
l4_end = None
for i in range(l4_start + 1, len(lines)):
    if lines[i] == "fi":
        l4_end = i
        break

tail_anchor = find_line(
    "cmd_karo_hotfix_t3s40_post_source_full_instrumentation: block-reason"
)
tail_start = tail_anchor - 1
wait_if_anchor = find_line('if [ "$_gate_record_category" = WAIT ]; then')
tail_end = None
for i in range(wait_if_anchor + 1, len(lines)):
    if lines[i] == "    fi":
        tail_end = i
        break

all_violations = sweep(l4_start, l4_end, ()) + sweep(tail_start, tail_end, ())
if all_violations:
    for ln, text_ in all_violations:
        print(f"{ln}: {text_}")
    sys.exit(1)
PY
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
