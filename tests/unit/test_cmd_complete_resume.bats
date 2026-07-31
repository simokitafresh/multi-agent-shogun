#!/usr/bin/env bats

setup() {
    # test_necessity: resume tests must observe the durable worker's terminal
    # failure status rather than the public caller's successful queue handoff.
    # These tests exercise the worker's durable failure propagation and resume
    # contract.  Keep the tail synchronous so Bats observes the worker exit
    # status; the public caller's detached latency contract is covered by
    # test_cmd_complete_wrapper.bats.
    export CMD_COMPLETE_SYNC_TAIL=1
    ROOT="$BATS_TEST_TMPDIR/root"
    mkdir -p "$ROOT/scripts/gates" "$ROOT/scripts/lib" "$ROOT/queue/gates/cmd_resume" "$ROOT/queue/archive/cmds" "$ROOT/logs"
    cp "$BATS_TEST_DIRNAME/../../scripts/cmd_complete.sh" "$ROOT/scripts/cmd_complete.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/defense_overhead_writer.sh" "$ROOT/scripts/lib/defense_overhead_writer.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/retro_pane_prompt.sh" "$ROOT/scripts/lib/retro_pane_prompt.sh"
    printf '{"project":"infra","verdict":"APPROVE","review":{"cmd_id":"cmd_resume","report_fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}\n' > "$ROOT/queue/gates/cmd_resume/sg7_bundle.json"
    : > "$ROOT/logs/gate_metrics.log"
    for name in lesson_review cmd_complete_gate cmd_quality_log dashboard_update ntfy_cmd inbox_archive; do
        cat > "$ROOT/scripts/$name.sh" <<'EOF'
#!/usr/bin/env bash
name="$(basename "$0" .sh)"
printf '%s\n' "$name" >> "$CMD_COMPLETE_TEST_LOG"
fail_file="${CMD_COMPLETE_FAIL_DIR:-}/$name"
if [[ -f "$fail_file" ]]; then
    n="$(cat "$fail_file")"
    if (( n > 0 )); then printf '%s\n' "$((n-1))" > "$fail_file"; exit 1; fi
fi
[[ "$name" == cmd_complete_gate ]] && printf '%s CLEAR\n' "$2" >> "${CMD_COMPLETE_ROOT_DIR}/logs/gate_metrics.log"
exit 0
EOF
        chmod +x "$ROOT/scripts/$name.sh"
    done
    cat > "$ROOT/scripts/gates/gate_yaml_status.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$ROOT/scripts/gates/gate_yaml_status.sh"
    cat > "$ROOT/scripts/review_bundle.py" <<'PY'
import json, os
with open(os.environ["CMD_COMPLETE_TEST_LOG"], "a") as fh: fh.write("sg7_consume\n")
print(json.dumps({"project": "infra"}))
PY
    LOG="$ROOT/steps.log"
    FAIL="$ROOT/fail"
    mkdir -p "$FAIL"
    export CMD_COMPLETE_ROOT_DIR="$ROOT" CMD_COMPLETE_SCRIPT_DIR="$ROOT/scripts"
    export CMD_COMPLETE_TEST_LOG="$LOG" CMD_COMPLETE_FAIL_DIR="$FAIL"
    export CMD_COMPLETE_DASHBOARD_RETRY_DELAY=0 CMD_COMPLETE_NTFY_RETRY_DELAY=0
    export DEFENSE_OVERHEAD_ENABLED=0
}

run_complete() {
    run bash "$ROOT/scripts/cmd_complete.sh" cmd_resume "$ROOT/queue/gates/cmd_resume/sg7_bundle.json"
}

@test "archive failure resumes at the sole unfinished step without duplicate dashboard or ntfy" {
    printf '1\n' > "$FAIL/inbox_archive"
    run_complete
    [ "$status" -ne 0 ]
    [ "$(wc -l < "$LOG")" -eq 7 ]
    run_complete
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$LOG")" -eq 8 ]
    [ "$(grep -c '^dashboard_update$' "$LOG")" -eq 1 ]
    [ "$(grep -c '^ntfy_cmd$' "$LOG")" -eq 1 ]
    [[ "$output" == *"SKIP ntfy checkpoint_verified"* ]]
}

@test "dashboard transient exhaustion resumes at dashboard and does not repeat the first five steps" {
    printf '3\n' > "$FAIL/dashboard_update"
    run_complete
    [ "$status" -ne 0 ]
    [ "$(wc -l < "$LOG")" -eq 7 ]
    run_complete
    [ "$status" -eq 0 ]
    [ "$(grep -c '^sg7_consume$' "$LOG")" -eq 1 ]
    [ "$(grep -c '^dashboard_update$' "$LOG")" -eq 4 ]
    [ "$(grep -c '^ntfy_cmd$' "$LOG")" -eq 1 ]
}

@test "ntfy exhaustion resumes at ntfy without duplicate dashboard" {
    printf '3\n' > "$FAIL/ntfy_cmd"
    run_complete
    [ "$status" -ne 0 ]
    run_complete
    [ "$status" -eq 0 ]
    [ "$(grep -c '^dashboard_update$' "$LOG")" -eq 1 ]
    [ "$(grep -c '^ntfy_cmd$' "$LOG")" -eq 4 ]
}

# test_necessity: an external notification already acknowledged for one
# completion generation must not be repeated if the worker crashes before the
# enclosing checkpoint update.
@test "ntfy durable receipt suppresses resend after receipt-to-checkpoint crash" {
    export CMD_COMPLETE_TEST_CRASH_AFTER_NTFY_RECEIPT=1
    run_complete
    [ "$status" -ne 0 ]
    [ "$(grep -c '^ntfy_cmd$' "$LOG")" -eq 1 ]
    unset CMD_COMPLETE_TEST_CRASH_AFTER_NTFY_RECEIPT
    run_complete
    [ "$status" -eq 0 ]
    [ "$(grep -c '^ntfy_cmd$' "$LOG")" -eq 1 ]
    [[ "$output" == *"SKIP ntfy durable_receipt_verified"* ]]
}

@test "corrupt checkpoint fails closed before any side effect" {
    printf '{broken\n' > "$ROOT/queue/gates/cmd_resume/completion_checkpoint.json"
    run_complete
    [ "$status" -ne 0 ]
    [ ! -s "$LOG" ]
    [[ "$output" == *"FAILED corrupt checkpoint"* ]]
}

@test "changed SG7 fingerprint starts a new generation instead of skipping old steps" {
    run_complete
    [ "$status" -eq 0 ]
    printf ' \n' >> "$ROOT/queue/gates/cmd_resume/sg7_bundle.json"
    run_complete
    [ "$status" -eq 0 ]
    [ "$(grep -c '^sg7_consume$' "$LOG")" -eq 2 ]
    [ "$(grep -c '^dashboard_update$' "$LOG")" -eq 2 ]
}

@test "same cmd parallel invocations serialize and publish each side effect once" {
    bash "$ROOT/scripts/cmd_complete.sh" cmd_resume "$ROOT/queue/gates/cmd_resume/sg7_bundle.json" > "$ROOT/a.out" 2>&1 &
    p1=$!
    bash "$ROOT/scripts/cmd_complete.sh" cmd_resume "$ROOT/queue/gates/cmd_resume/sg7_bundle.json" > "$ROOT/b.out" 2>&1 &
    p2=$!
    wait "$p1"; wait "$p2"
    [ "$(grep -c '^dashboard_update$' "$LOG")" -eq 1 ]
    [ "$(grep -c '^ntfy_cmd$' "$LOG")" -eq 1 ]
    [ "$(grep -c '^inbox_archive$' "$LOG")" -eq 1 ]
}

# test_necessity: terminal review recovery must derive its immutable report set
# from archived report identity after all worker task slots have been reused.
@test "archived reports retain six fingerprint-bound approvals and terminal snapshot" {
    local review_root="$BATS_TEST_TMPDIR/review-root"
    mkdir -p "$review_root/scripts/lib" "$review_root/queue/archive/reports" \
        "$review_root/queue/reports" "$review_root/queue/tasks" \
        "$review_root/queue/gates/cmd_4200/review_approvals/reports"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/review_approval.sh" "$review_root/scripts/lib/"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/report_commit_identity.py" "$review_root/scripts/lib/"
    printf 'task:\n  parent_cmd: cmd_new_generation\n' > "$review_root/queue/tasks/kotaro.yaml"

    for n in 1 2 3 4 5 6; do
        report="$review_root/queue/archive/reports/ninja${n}_report_cmd_4200.yaml"
        printf 'report_id: rpt-%s\nparent_cmd: cmd_4200\ncommit_hash: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nresult: {summary: ok}\n' "$n" > "$report"
    done
    printf 'report_id: rpt-other\nparent_cmd: cmd_other\ncommit_hash: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' \
        > "$review_root/queue/archive/reports/other_cmd.yaml"

    run bash -c '
        set -e
        export PROJECT_ROOT="$1"
        source "$1/scripts/lib/review_approval.sh"
        mapfile -t reports < <(review_resolve_reports cmd_4200)
        [ "${#reports[@]}" -eq 6 ]
        for report in "${reports[@]}"; do
            logical=$(review_report_logical_path "$report")
            key=$(review_report_key "$logical")
            dir="$1/queue/gates/cmd_4200/review_approvals/reports/$key"
            mkdir -p "$dir"
            fp=$(review_report_fingerprint "$report")
            printf "result: LGTM\nfingerprint: %s\n" "$fp" > "$dir/gunshi.yaml"
            printf "result: ACCEPT\nfingerprint: %s\n" "$fp" > "$dir/karo.yaml"
        done
        review_all_reports_ready cmd_4200 "${reports[@]}"
        review_terminal_snapshot_write cmd_4200 "${reports[@]}" >/dev/null
        python3 - "$1/queue/gates/cmd_4200/terminal_review_manifest.json" <<"PY"
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(d["reports"]) == 6
assert len({x["logical_path"] for x in d["reports"]}) == 6
assert all(x["logical_path"].startswith("queue/reports/") for x in d["reports"])
assert all(x["gunshi"]["result"] == "LGTM" and x["karo"]["result"] == "ACCEPT" for x in d["reports"])
PY
    ' _ "$review_root"
    [ "$status" -eq 0 ]

    cp "$review_root/queue/archive/reports/ninja1_report_cmd_4200.yaml" \
        "$review_root/queue/reports/ninja1_report_cmd_4200.yaml"
    printf 'task:\n  parent_cmd: cmd_4200\n  report_filename: ninja1_report_cmd_4200.yaml\n' \
        > "$review_root/queue/tasks/kotaro.yaml"
    run bash -c 'export PROJECT_ROOT="$1"; source "$1/scripts/lib/review_approval.sh"; review_resolve_reports cmd_4200' _ "$review_root"
    [ "$status" -ne 0 ]
}

# test_necessity: the formal approval writer must use the same logical report
# key as terminal readers and explicitly authorize archived SG7 input.
@test "formal archived approvals share logical key and pass SG7 archive authorization" {
    local root="$BATS_TEST_TMPDIR/formal-archive"
    mkdir -p "$root/scripts/lib" "$root/queue/archive/reports" "$root/queue/reports" \
        "$root/queue/tasks" "$root/queue/gates/cmd_archive"
    cp "$BATS_TEST_DIRNAME/../../scripts/review_approval.sh" "$root/scripts/"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/review_approval.sh" "$root/scripts/lib/"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/report_commit_identity.py" "$root/scripts/lib/"
    printf 'yaml_field_set_batch() { :; }\n' > "$root/scripts/lib/yaml_field_set.sh"
    printf 'defense_overhead_write() { :; }\n' > "$root/scripts/lib/defense_overhead_writer.sh"
    printf 'import pathlib,sys\npathlib.Path(__file__).with_name("sg7.args").write_text(" ".join(sys.argv[1:]))\n' \
        > "$root/scripts/review_bundle.py"
    for n in 1 2 3 4 5 6; do
        report="$root/queue/archive/reports/ninja${n}_report_cmd_archive.yaml"
        printf 'report_id: rpt-archive-%s\nparent_cmd: cmd_archive\nstatus: completed\nverdict: PASS\ncommit_hash: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nresult: {summary: ok}\n' "$n" > "$report"
        run env REVIEW_APPROVAL_ROOT="$root" REVIEW_APPROVAL_SKIP_LEDGER_CHECK=1 \
            REVIEW_APPROVAL_NO_NOTIFY=1 REVIEW_APPROVAL_NO_TRIGGER=1 \
            bash "$root/scripts/review_approval.sh" cmd_archive gunshi LGTM "$report"
        [ "$status" -eq 0 ]
    done
    for n in 1 2 3 4 5 6; do
        report="$root/queue/archive/reports/ninja${n}_report_cmd_archive.yaml"
        run env REVIEW_APPROVAL_ROOT="$root" REVIEW_APPROVAL_SKIP_LEDGER_CHECK=1 \
            REVIEW_APPROVAL_NO_NOTIFY=1 REVIEW_APPROVAL_NO_TRIGGER=1 \
            bash "$root/scripts/review_approval.sh" cmd_archive karo ACCEPT "$report"
        [ "$status" -eq 0 ]
        logical_key=$(printf '%s' "queue/reports/ninja${n}_report_cmd_archive.yaml" | sha256sum | awk '{print $1}')
        physical_key=$(printf '%s' "queue/archive/reports/ninja${n}_report_cmd_archive.yaml" | sha256sum | awk '{print $1}')
        [ -f "$root/queue/gates/cmd_archive/review_approvals/reports/$logical_key/gunshi.yaml" ]
        [ -f "$root/queue/gates/cmd_archive/review_approvals/reports/$logical_key/karo.yaml" ]
        [ ! -e "$root/queue/gates/cmd_archive/review_approvals/reports/$physical_key" ]
    done
    grep -q -- '--allow-archived' "$root/scripts/sg7.args" || { cat "$root/scripts/sg7.args" >&3; false; }
    [ "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["reports"]))' "$root/queue/gates/cmd_archive/terminal_review_manifest.json")" -eq 6 ]
}

# test_necessity: archive identity resolution must reject every ambiguity and
# path-boundary escape before any approval can be consumed.
@test "archived report resolver fails closed on malformed identity and boundary escapes" {
    local cases_root="$BATS_TEST_TMPDIR/archive-negative"
    for kind in nested symlink symlink_other_cmd invalid missing duplicate; do
        root="$cases_root/$kind"
        mkdir -p "$root/scripts/lib" "$root/queue/reports" "$root/queue/archive/reports" "$root/queue/tasks"
        cp "$BATS_TEST_DIRNAME/../../scripts/lib/review_approval.sh" "$root/scripts/lib/"
        printf 'report_id: rpt-1\nparent_cmd: cmd_4200\ncommit_hash: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' \
            > "$root/queue/archive/reports/one.yaml"
        case "$kind" in
            nested)
                mkdir -p "$root/queue/archive/reports/nested"
                printf 'report_id: rpt-2\nparent_cmd: cmd_4200\n' > "$root/queue/archive/reports/nested/two.yaml" ;;
            symlink)
                printf 'report_id: rpt-2\nparent_cmd: cmd_4200\n' > "$root/outside.yaml"
                ln -s "$root/outside.yaml" "$root/queue/archive/reports/two.yaml" ;;
            symlink_other_cmd)
                printf 'report_id: rpt-other\nparent_cmd: cmd_other\n' > "$root/outside.yaml"
                ln -s "$root/outside.yaml" "$root/queue/archive/reports/two.yaml" ;;
            invalid)
                printf 'report_id: [unterminated\nparent_cmd: cmd_4200\n' \
                    > "$root/queue/archive/reports/two.yaml" ;;
            missing)
                printf 'parent_cmd: cmd_4200\n' > "$root/queue/archive/reports/two.yaml" ;;
            duplicate)
                printf 'report_id: rpt-1\nparent_cmd: cmd_4200\n' > "$root/queue/archive/reports/two.yaml" ;;
        esac
        run bash -c 'export PROJECT_ROOT="$1"; source "$1/scripts/lib/review_approval.sh"; review_resolve_reports cmd_4200' _ "$root"
        [ "$status" -ne 0 ]
    done
}
