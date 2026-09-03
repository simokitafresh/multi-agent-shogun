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
names = ("source_publish_receipt_matches", "cmd_complete_gate_publisher_origin_ready")
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
