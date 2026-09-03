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

# test_necessity: cmd_karo_hotfix_t3s40_post_source_v6 AC2 (RC 202609040403).
# v5 (cmd_karo_hotfix_t3s40_post_source_v5_202609040305) code-audited >=10
# synchronous subprocess starts inside finalize_pre_postclear, two of which
# (gunshi_verdict cmd_design_quality.yaml flock -w10, and the terminal
# send_clear_notifications_once -> notify_shogun_gate_clear timeout-10
# inbox_write) carry a documented worst-case 10s wait each. Karo's RC on the
# first cut (plain `(...) &`) explained why that alone is insufficient: a
# plain background job stays in this process's own process group and is
# killed alongside it by a group-wide kill (tmux respawn-pane -k, /clear
# respawn) — exactly the loss mode INS-20260709-000457431-b624 already
# documents for cmd_quality_log.sh. None of these five side effects gates the
# CLEAR decision or a state-queue row, so each must run through the same
# durable dispatch (`nohup setsid`) already used by
# semantic_causal_post_clear.sh elsewhere in this file, which detaches into a
# new session and survives that kill. False positive here = a claimed
# "durable async" label without an actual nohup+setsid dispatch (the delay
# would silently return, and a session-boundary kill would silently drop it).
@test "AC2 positive: gunshi reflux/review_feedback/verdict/workaround-rate/clear-notify side effects run through durable (nohup+setsid) dispatch" {
    local gate_script="$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh"

    # gunshi_gate_reflux (1st run) + gunshi review_feedback: one ordered
    # durable dispatch (reflux must textually precede the review_feedback
    # notification so the "review_log synced before gunshi is notified"
    # invariant survives being moved off the synchronous path), and the
    # dispatch itself must be nohup+setsid, not a plain `&` subshell.
    local block_start block_end reflux_rel feedback_rel setsid_rel
    block_start=$(grep -n '^    echo "Gunshi gate_result reflux + review_feedback (GATE CLEAR, durable async ordered):"$' "$gate_script" | head -1 | cut -d: -f1)
    [ -n "$block_start" ]
    block_end=$(awk -v s="$block_start" 'NR > s && $0 ~ /^        .*<\/dev\/null >> "\$LOG_DIR\/cmd_complete_gate_async\.log" 2>&1 &$/ { print NR; exit }' "$gate_script")
    [ -n "$block_end" ]
    setsid_rel=$(sed -n "${block_start},${block_end}p" "$gate_script" | grep -n 'nohup setsid bash -c' | head -1 | cut -d: -f1)
    reflux_rel=$(sed -n "${block_start},${block_end}p" "$gate_script" | grep -n 'gunshi_gate_reflux.sh"' | head -1 | cut -d: -f1)
    feedback_rel=$(sed -n "${block_start},${block_end}p" "$gate_script" | grep -n 'inbox_write.sh" gunshi ' | head -1 | cut -d: -f1)
    [ -n "$setsid_rel" ]
    [ -n "$reflux_rel" ]
    [ -n "$feedback_rel" ]
    [ "$setsid_rel" -lt "$reflux_rel" ]
    [ "$reflux_rel" -lt "$feedback_rel" ]

    # gunshi_verdict update to cmd_design_quality.yaml: extracted to its own
    # script (scripts/gate_gunshi_verdict_sync.sh, no logic change — the
    # bats-loaded copy below diffs it against the inline body this replaced)
    # and launched via nohup+setsid.
    [ -f "$BATS_TEST_DIRNAME/../../scripts/gate_gunshi_verdict_sync.sh" ]
    grep -q 'nohup setsid bash "\$SCRIPT_DIR/scripts/gate_gunshi_verdict_sync.sh" "\$CMD_ID"' "$gate_script"
    grep -q '^    echo "  gunshi_verdict update: queued (durable async; survives session-boundary kill)"$' "$gate_script"

    # Workaround-rate display: purely informational ("情報のみ、BLOCKしない"),
    # dispatched via nohup+setsid rather than run inline in the synchronous span.
    grep -q "nohup setsid bash -c 'bash \"\\\$SCRIPT_DIR/scripts/gates/gate_workaround_rate.sh\"" "$gate_script"
    grep -q 'workaround_rate: queued (durable async' "$gate_script"

    # gunshi_gate_reflux 2nd run (post-CLEAR catch-up, no downstream ordering
    # dependency in this invocation): nohup+setsid dispatched.
    grep -q '^        echo "  gunshi_gate_reflux (2nd run): queued (durable async; survives session-boundary kill)"$' "$gate_script"

    # Terminal shogun/karo notifications (send_clear_notifications_once):
    # send_clear_notifications_once is also called synchronously from the
    # emergency-override paths elsewhere in this file, so it stays one
    # shared in-process function — moved (not duplicated) to
    # scripts/lib/gate_clear_notify.sh, which cmd_complete_gate.sh sources
    # back in and a standalone scripts/gate_clear_terminal_notify.sh also
    # sources for durable(nohup+setsid) dispatch (an earlier export -f cut of
    # this dispatch is deliberately absent: a smoke test proved bash's
    # function-export round-trip corrupts one of its dependencies'
    # here-documents in this environment).
    [ -f "$BATS_TEST_DIRNAME/../../scripts/lib/gate_clear_notify.sh" ]
    [ -f "$BATS_TEST_DIRNAME/../../scripts/gate_clear_terminal_notify.sh" ]
    grep -q '^source "\$SCRIPT_DIR/scripts/lib/gate_clear_notify.sh"$' "$gate_script"
    ! grep -q '^export -f send_clear_notifications_once' "$gate_script"
    grep -q 'nohup setsid bash "\$SCRIPT_DIR/scripts/gate_clear_terminal_notify.sh"' "$gate_script"
    grep -q '"\$CMD_ID" "GATE CLEAR terminal" "\$LOG_DIR" "\${ARCHIVE_AUTO_HANDLED:-0}"' "$gate_script"
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

# test_necessity: cmd_karo_hotfix_t3s40_post_source_v6 AC2 (RC 202609040403).
# Behavioral proof, not just structural grep, that the `nohup setsid` dispatch
# every AC2 side effect now uses actually survives termination of the
# launching process group — the exact "再起動・異常終了" scenario the RC
# named (tmux respawn-pane -k sends SIGKILL to the whole pane process group;
# a plain background `&` job shares that pgid and dies with it, while a
# setsid-detached job is in its own session and is unaffected). False
# negative here = the dispatched side effect getting silently dropped by a
# session-boundary kill even though "queued (async)" was printed.
@test "AC2 durability: nohup+setsid dispatch survives SIGKILL of the launching process group (plain background does not)" {
    local durable_marker="$BATS_TEST_TMPDIR/durable-dispatch-marker"
    local plain_marker="$BATS_TEST_TMPDIR/plain-bg-marker"
    rm -f "$durable_marker" "$plain_marker"

    # setsid isolates the whole simulated launcher into a fresh session/
    # process group first, so "kill this launcher's own process group" below
    # can never reach the bats test runner's own group. Inside that isolated
    # launcher: a plain background job (the shape every one of these 5 AC2
    # sites had before this RC) shares the launcher's pgid and must die with
    # it; a nohup+setsid dispatch (the shape every site uses after this RC)
    # detaches into its own session and must survive — mirroring tmux
    # respawn-pane -k, which sends SIGKILL to the whole pane process group.
    setsid bash -c '
        (sleep 1; echo done > "$1") &
        nohup setsid bash -c "sleep 1; echo done > \"\$1\"" _ "$2" </dev/null >/dev/null 2>&1 &
        sleep 0.3
        kill -KILL -- -$$
    ' _ "$plain_marker" "$durable_marker" >/dev/null 2>&1 || true

    local waited=0
    while [ ! -f "$durable_marker" ] && [ "$waited" -lt 10 ]; do
        sleep 0.5
        waited=$((waited + 1))
    done
    [ -f "$durable_marker" ]
    grep -qF "done" "$durable_marker"
    [ ! -f "$plain_marker" ]
}

# test_necessity: cmd_karo_hotfix_t3s40_post_source_v6 AC2 (RC 202609040403).
# Regression guard for a real bug this RC's first attempt (export -f the
# notify function closure) hit: a smoke test proved bash's function-export
# environment-variable round-trip corrupts
# gate_clear_notify_historical_evidence's embedded python heredoc in this
# environment, so every downstream call silently became "command not found"
# (send_clear_notifications_once still printed its normal-looking OK lines).
# This test runs the real scripts/gate_clear_terminal_notify.sh end-to-end
# (source-based dispatch, the fix) against stub inbox_write.sh and asserts
# both notifications actually reached the stub and no shell parse/import
# error leaked into the log — a false positive here (green log full of
# swallowed "command not found") is exactly the failure mode this guards.
@test "AC2 regression guard: gate_clear_terminal_notify.sh delivers both notifications with no shell import/parse errors" {
    local test_root="$BATS_TEST_TMPDIR/notify-wrapper"
    mkdir -p "$test_root/queue/inbox" "$test_root/queue/gates" "$test_root/scripts/lib" "$test_root/logs"
    local repo_root="$BATS_TEST_DIRNAME/../.."
    cp "$repo_root/scripts/lib/append_line_locked.sh" "$test_root/scripts/lib/"
    cp "$repo_root/scripts/lib/lock_path.sh" "$test_root/scripts/lib/"
    cp "$repo_root/scripts/lib/gate_clear_notify.sh" "$test_root/scripts/lib/"
    cp "$repo_root/scripts/gate_clear_terminal_notify.sh" "$test_root/scripts/"
    cat > "$test_root/scripts/inbox_write.sh" <<'STUB'
#!/usr/bin/env bash
echo "STUB to=$1 type=$3" >> "$(dirname "$0")/../logs/stub_calls.log"
exit 0
STUB
    chmod +x "$test_root/scripts/inbox_write.sh"
    # ntfy_cmd.sh absent is fine (non-blocking, logged); no ntfy_batch.sh either.
    echo "messages: []" > "$test_root/queue/inbox/shogun.yaml"
    echo "messages: []" > "$test_root/queue/inbox/karo.yaml"

    local rc=0
    bash "$test_root/scripts/gate_clear_terminal_notify.sh" \
        cmd_regression_guard_probe "GATE CLEAR terminal" "$test_root/logs" 0 \
        > "$test_root/logs/run.log" 2>&1 || rc=$?

    ! grep -qiE 'command not found|error importing function definition|syntax error' "$test_root/logs/run.log"
    grep -qF 'STUB to=shogun type=gate_clear' "$test_root/logs/stub_calls.log"
    grep -qF 'STUB to=karo type=skill_hint' "$test_root/logs/stub_calls.log"
    [ "$rc" -eq 0 ]
}
