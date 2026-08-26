#!/usr/bin/env bats

setup() {
    export CMD_COMPLETE_SYNC_TAIL=1
    # Existing dashboard-tail contracts explicitly exercise the opt-in path.
    # The default-off contract is covered by the test below with env -u.
    export CMD_COMPLETE_DASHBOARD_ENABLED=1
    export FIXTURE="$BATS_TEST_TMPDIR/root"
    mkdir -p "$FIXTURE/scripts/gates" "$FIXTURE/scripts/lib" "$FIXTURE/queue/gates/cmd_fixture"
    cp "$BATS_TEST_DIRNAME/../../scripts/cmd_complete.sh" "$FIXTURE/scripts/cmd_complete.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/defense_overhead_writer.sh" \
        "$FIXTURE/scripts/lib/defense_overhead_writer.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/retro_pane_prompt.sh" \
        "$FIXTURE/scripts/lib/retro_pane_prompt.sh"
    printf '%s\n' '{"review":{"cmd_id":"cmd_fixture","report_fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}' > "$FIXTURE/queue/gates/cmd_fixture/sg7_bundle.json"

    cat > "$FIXTURE/scripts/review_bundle.py" <<'PY'
import json
print(json.dumps({"acceptance_criteria_count": 2, "scope": ["scripts"], "project": "infra"}))
PY
    for name in lesson_review.sh cmd_complete_gate.sh cmd_quality_log.sh dashboard_update.sh ntfy_cmd.sh inbox_mark_read.sh inbox_archive.sh karo_workaround_log.sh; do
        make_stub "$FIXTURE/scripts/$name" "$name"
    done
    cat > "$FIXTURE/scripts/cmd_complete_gate.sh" <<'SH'
#!/usr/bin/env bash
printf 'cmd_complete_gate.sh|%s\n' "$*" >> "$CMD_COMPLETE_TEST_LOG"
if [[ -n "${CMD_COMPLETE_GATE_CLEAR_MARKER:-}" ]]; then
    python3 - "$CMD_COMPLETE_GATE_CLEAR_MARKER" "$1" "$SHOGUN_COMPLETION_GENERATION" <<'PY'
import json, os, sys, tempfile
path, cmd_id, generation = sys.argv[1:]
data = {"version": 1, "state": "clear", "cmd_id": cmd_id,
        "completion_generation": generation}
fd, tmp = tempfile.mkstemp(prefix=".clear.", dir=os.path.dirname(path))
with os.fdopen(fd, "w", encoding="utf-8") as fh:
    json.dump(data, fh); fh.write("\n"); fh.flush(); os.fsync(fh.fileno())
os.replace(tmp, path)
PY
fi
[[ "${CMD_COMPLETE_FAIL_STEP:-}" != 'cmd_complete_gate.sh' ]]
SH
    chmod +x "$FIXTURE/scripts/cmd_complete_gate.sh"
    make_stub "$FIXTURE/scripts/gates/gate_context_freshness.sh" gate_context_freshness.sh
    make_stub "$FIXTURE/scripts/gates/gate_yaml_status.sh" gate_yaml_status.sh
}

# test_necessity: by default the completion tail must checkpoint dashboard without
# invoking dashboard_update.sh; CMD_COMPLETE_DASHBOARD_ENABLED=1 preserves the
# explicit opt-in publication behavior.
@test "dashboard publication is disabled by default and opt-in via environment" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/dashboard-default.log"
    run env -u CMD_COMPLETE_DASHBOARD_ENABLED \
        CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP dashboard disabled_by_default(lord ruling 2026-08-17)"* ]]
    ! grep -q '^dashboard_update.sh|' "$CMD_COMPLETE_TEST_LOG"
    [ ! -e "$FIXTURE/queue/gates/completion_dashboard.lock" ]
    run python3 - "$FIXTURE/queue/gates/cmd_fixture/completion_checkpoint.json" <<'PY'
import json, sys
completed = json.load(open(sys.argv[1], encoding="utf-8"))["completed"]
assert completed[-3:] == ["dashboard", "ntfy", "inbox_archive"], completed
PY
    [ "$status" -eq 0 ]

    local optin_checkpoint="$BATS_TEST_TMPDIR/dashboard-optin-checkpoint"
    mkdir -p "$optin_checkpoint"
    : > "$CMD_COMPLETE_TEST_LOG"
    run env CMD_COMPLETE_DASHBOARD_ENABLED=1 \
        CMD_COMPLETE_CHECKPOINT_DIR="$optin_checkpoint" \
        CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -eq 0 ]
    grep -q '^dashboard_update.sh|' "$CMD_COMPLETE_TEST_LOG"
}

# test_necessity: the public completion caller must not inherit latency from the durable dashboard/notification tail.
# regression_justification: production measurements showed dashboard=18.307s and ntfy≈23s despite ntfy's lower-level async worker.
@test "public caller detaches ordered completion tail before slow dashboard and ntfy" {
    unset CMD_COMPLETE_SYNC_TAIL
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/async-tail.log"
    cat > "$FIXTURE/scripts/dashboard_update.sh" <<'SH'
#!/usr/bin/env bash
sleep 5
printf 'dashboard_update.sh|%s\n' "$*" >> "$CMD_COMPLETE_TEST_LOG"
SH
    chmod +x "$FIXTURE/scripts/dashboard_update.sh"

    local start_ns elapsed_ms
    start_ns="$(date +%s%N)"
    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    elapsed_ms=$(( ($(date +%s%N) - start_ns) / 1000000 ))
    [ "$status" -eq 0 ]
    [ "$elapsed_ms" -lt 5000 ]
    [[ "$output" == *"QUEUED completion_tail"* ]]
    [ ! -e "$CMD_COMPLETE_TEST_LOG" ] || ! grep -q '^ntfy_cmd.sh|' "$CMD_COMPLETE_TEST_LOG"
}

# test_necessity: a wrapper-aware gate must publish a durable CLEAR receipt before the public caller returns, while exactly one worker owns every post-CLEAR gate and terminal completion side effect.
# regression_justification: cmd_4293 printed CLEAR but the synchronous wrapper still waited 12.054s for post-CLEAR gate work.
@test "public caller returns at durable gate CLEAR while one worker completes the ordered tail" {
    unset CMD_COMPLETE_SYNC_TAIL
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/post-clear-worker.log"
    cat > "$FIXTURE/scripts/cmd_complete_gate.sh" <<'SH'
#!/usr/bin/env bash
# CMD_COMPLETE_GATE_CLEAR_MARKER is the wrapper/gate contract token.
printf 'cmd_complete_gate.sh|%s\n' "$*" >> "$CMD_COMPLETE_TEST_LOG"
printf 'invoked\n' >> "$(dirname "$CMD_COMPLETE_GATE_CLEAR_MARKER")/gate_invocations.log"
python3 - "$CMD_COMPLETE_GATE_CLEAR_MARKER" "$1" "$SHOGUN_COMPLETION_GENERATION" <<'PY'
import json, os, sys, tempfile
path, cmd_id, generation = sys.argv[1:]
data = {"version": 1, "state": "clear", "cmd_id": cmd_id,
        "completion_generation": generation}
fd, tmp = tempfile.mkstemp(prefix=".clear.", dir=os.path.dirname(path))
with os.fdopen(fd, "w", encoding="utf-8") as fh:
    json.dump(data, fh); fh.write("\n"); fh.flush(); os.fsync(fh.fileno())
os.replace(tmp, path)
PY
sleep 6
SH
    chmod +x "$FIXTURE/scripts/cmd_complete_gate.sh"

    local start_ns clear_end_ns worker_end_ns elapsed_ms worker_elapsed_ms checkpoint i
    start_ns="$(date +%s%N)"
    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    elapsed_ms=$(( ($(date +%s%N) - start_ns) / 1000000 ))
    clear_end_ns="$(date +%s%N)"
    [ "$status" -eq 0 ]
    echo "public_clear_ms=$elapsed_ms"
    [ "$elapsed_ms" -lt 5000 ]
    [[ "$output" == *"GATE CLEAR durable_worker_receipt_verified"* ]]
    [[ "$output" == *"QUEUED completion_tail"* ]]

    checkpoint="$FIXTURE/queue/gates/cmd_fixture/completion_checkpoint.json"
    for i in $(seq 1 300); do
        grep -q '^\[cmd_complete\] COMPLETE cmd_fixture$' \
            "$FIXTURE/queue/gates/cmd_fixture/completion_tail.log" 2>/dev/null && break
        sleep 0.05
    done
    [ "$(wc -l < "$FIXTURE/queue/gates/cmd_fixture/gate_invocations.log")" -eq 1 ]
    grep -q '^\[cmd_complete\] COMPLETE cmd_fixture$' \
        "$FIXTURE/queue/gates/cmd_fixture/completion_tail.log"
    worker_end_ns="$(date +%s%N)"
    worker_elapsed_ms=$(( (worker_end_ns - start_ns) / 1000000 ))
    echo "public_clear_ms=$elapsed_ms worker_complete_ms=$worker_elapsed_ms post_clear_ms=$(( (worker_end_ns - clear_end_ns) / 1000000 ))"
    run python3 - "$checkpoint" <<'PY'
import json, sys
completed = json.load(open(sys.argv[1], encoding="utf-8"))["completed"]
assert completed == ["sg7_consume", "lesson_review", "cmd_complete_gate", "quality_log",
                     "status_completed", "archive_terminal", "dashboard", "ntfy", "inbox_archive"]
PY
    [ "$status" -eq 0 ]
}

# test_necessity: CLEAR must be persisted only after all pre-CLEAR fail-closed checks and before public CLEAR output.
@test "gate durable CLEAR marker precedes output and post-CLEAR body" {
    local gate="$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh"
    run python3 - "$gate" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
normal = text.index('CMD_COMPLETE_GATE_CLEAR_MARKER', text.index('if [ "$ALL_CLEAR" = true ]'))
clear_output = text.index('echo "GATE CLEAR: cmd完了許可"', normal)
post_clear = text.index('Status completed (post-runtime-publish):', clear_output)
assert normal < clear_output < post_clear
assert text.index('capture_completed_rework_event', text.index('if [ "$ALL_CLEAR" = true ]')) < normal
PY
    [ "$status" -eq 0 ]
}

# test_necessity: a parent crash after worker launch but before launch-receipt persistence must recover the generation-bound private session and must not invoke the gate twice.
# regression_justification: the original launch-then-receipt ordering exposed an exactly-once gap where the next caller could launch a duplicate worker.
@test "receipt-window crash recovers one reserved private gate worker without relaunch" {
    unset CMD_COMPLETE_SYNC_TAIL
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/receipt-crash.log"
    cat > "$FIXTURE/scripts/cmd_complete_gate.sh" <<'SH'
#!/usr/bin/env bash
# CMD_COMPLETE_GATE_CLEAR_MARKER is the wrapper/gate contract token.
printf 'invoked\n' >> "$(dirname "$CMD_COMPLETE_GATE_CLEAR_MARKER")/gate_invocations.log"
python3 - "$CMD_COMPLETE_GATE_CLEAR_MARKER" "$1" "$SHOGUN_COMPLETION_GENERATION" <<'PY'
import json, os, sys, tempfile
path, cmd_id, generation = sys.argv[1:]
data = {"version": 1, "state": "clear", "cmd_id": cmd_id,
        "completion_generation": generation}
fd, tmp = tempfile.mkstemp(prefix=".clear.", dir=os.path.dirname(path))
with os.fdopen(fd, "w", encoding="utf-8") as fh:
    json.dump(data, fh); fh.write("\n"); fh.flush(); os.fsync(fh.fileno())
os.replace(tmp, path)
PY
sleep 4
SH
    chmod +x "$FIXTURE/scripts/cmd_complete_gate.sh"

    run env CMD_COMPLETE_TEST_CRASH_AFTER_GATE_LAUNCH=1 \
        CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -eq 96 ]
    [[ "$output" == *"TEST_CRASH after durable gate launch before receipt"* ]]
    [ -f "$FIXTURE/queue/gates/cmd_fixture/gate_worker.reserved.json" ]
    [ ! -f "$FIXTURE/queue/gates/cmd_fixture/gate_worker.launch.json" ]

    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -eq 0 ]
    [[ "$output" == *"launcher=tmux-"*"-recovered"* ]]
    [[ "$output" == *"GATE CLEAR durable_worker_receipt_verified"* ]]

    local i
    for i in $(seq 1 300); do
        grep -q '^\[cmd_complete\] COMPLETE cmd_fixture$' \
            "$FIXTURE/queue/gates/cmd_fixture/completion_tail.log" 2>/dev/null && break
        sleep 0.05
    done
    [ "$(wc -l < "$FIXTURE/queue/gates/cmd_fixture/gate_invocations.log")" -eq 1 ]
    grep -q '^\[cmd_complete\] COMPLETE cmd_fixture$' \
        "$FIXTURE/queue/gates/cmd_fixture/completion_tail.log"
}

# test_necessity: the public observer must release the real completion_checkpoint flock before CLEAR wait so continuation can acquire it and finish while the observer process is still alive.
# regression_justification: contract-runner test2 deadlocked with public fd9 held while the stable tmux continuation blocked acquiring the same checkpoint lock.
@test "real checkpoint flock is handed off before public CLEAR wait" {
    unset CMD_COMPLETE_SYNC_TAIL
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/real-flock.log"
    local public_log="$BATS_TEST_TMPDIR/public.log" public_pid i tail_log

    env CMD_COMPLETE_TEST_HOLD_AFTER_LOCK_RELEASE=8 \
        CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture >"$public_log" 2>&1 &
    public_pid=$!
    tail_log="$FIXTURE/queue/gates/cmd_fixture/completion_tail.log"
    for i in $(seq 1 140); do
        grep -q '^\[cmd_complete\] COMPLETE cmd_fixture$' "$tail_log" 2>/dev/null && break
        sleep 0.05
    done
    grep -q '^\[cmd_complete\] COMPLETE cmd_fixture$' "$tail_log"
    [ -d "/proc/$public_pid" ]
    wait "$public_pid"
    [ "$?" -eq 0 ]
    grep -q '^\[cmd_complete\] RELEASED checkpoint_lock before_clear_wait$' "$public_log"
}

# test_necessity: the detached tail must outlive its public parent and complete all ordered terminal side effects.
# regression_justification: cmd_4209 observed QUEUED followed by process0/log0byte because the child was not nohup-detached.
@test "detached completion tail survives parent exit and finishes dashboard ntfy and inbox archive" {
    unset CMD_COMPLETE_SYNC_TAIL
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/durable-tail.log"
    mkdir -p "$BATS_TEST_TMPDIR/tmux-no-server"
    run env TMUX= TMUX_TMPDIR="$BATS_TEST_TMPDIR/tmux-no-server" \
        CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -eq 0 ]
    [[ "$output" == *"QUEUED completion_tail"* ]]

    local i checkpoint="$FIXTURE/queue/gates/cmd_fixture/completion_checkpoint.json"
    for i in $(seq 1 100); do
        python3 - "$checkpoint" <<'PY' 2>/dev/null && break
import json, sys
completed = json.load(open(sys.argv[1], encoding='utf-8'))['completed']
raise SystemExit(0 if completed[-3:] == ['dashboard', 'ntfy', 'inbox_archive'] else 1)
PY
        sleep 0.05
    done
    grep -q '^dashboard_update.sh|cmd_fixture ' "$CMD_COMPLETE_TEST_LOG"
    grep -q '^ntfy_cmd.sh|cmd_fixture 完了$' "$CMD_COMPLETE_TEST_LOG"
    grep -q '^inbox_archive.sh|karo$' "$CMD_COMPLETE_TEST_LOG"
    run python3 - "$checkpoint" <<'PY'
import json, sys
completed = json.load(open(sys.argv[1], encoding='utf-8'))['completed']
assert completed[-3:] == ['dashboard', 'ntfy', 'inbox_archive'], completed
PY
    [ "$status" -eq 0 ]
}

# test_necessity: the production launcher must use a stable named private tmux session so receipt-window recovery cannot start a second worker.
# regression_justification: launch followed by parent crash before receipt persistence left no durable evidence and allowed duplicate relaunch.
@test "completion tail launcher uses generation-bound private tmux singleflight" {
    run grep -F '"$tmux_bin" -L "$socket" new-session -d -s completion' "$BATS_TEST_DIRNAME/../../scripts/cmd_complete.sh"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]
}

# test_necessity: durable worker launch failure must remain synchronous and fail closed before any terminal side effect is published.
@test "completion worker launch fails closed when tmux is unavailable" {
    unset CMD_COMPLETE_SYNC_TAIL
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/no-tmux-fallback.log"
    run env CMD_COMPLETE_TMUX_BIN="$BATS_TEST_TMPDIR/missing-tmux" \
        CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -ne 0 ]
    [[ "$output" == *"FAILED durable gate worker tmux unavailable"* ]]
    ! grep -q '^inbox_archive.sh|karo$' "$CMD_COMPLETE_TEST_LOG"
}

# test_necessity: all known slow/failing tail variants must remain outside the public caller while the worker preserves checkpoints.
@test "five tail latency variants return from public caller below five seconds" {
    unset CMD_COMPLETE_SYNC_TAIL
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/five-variants.log"
    local variant cmd start_ns elapsed_ms rc
    local -a variants=(sleep5 huge_archive endpoint_failure notification_throttle dashboard_contention)
    local -a pids=()
    for variant in "${variants[@]}"; do
        cmd="cmd_${variant}"
        mkdir -p "$FIXTURE/queue/gates/$cmd"
        sed "s/cmd_fixture/$cmd/" "$FIXTURE/queue/gates/cmd_fixture/sg7_bundle.json" > "$FIXTURE/queue/gates/$cmd/sg7_bundle.json"
        (
            start_ns="$(date +%s%N)"
            env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
                CMD_COMPLETE_TEST_VARIANT="$variant" bash "$FIXTURE/scripts/cmd_complete.sh" "$cmd" \
                >"$BATS_TEST_TMPDIR/$variant.output" 2>&1
            rc=$?
            elapsed_ms=$(( ($(date +%s%N) - start_ns) / 1000000 ))
            printf '%s\t%s\t%s\n' "$rc" "$elapsed_ms" "$variant" >"$BATS_TEST_TMPDIR/$variant.result"
            exit "$rc"
        ) &
        pids+=("$!")
    done
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    for variant in "${variants[@]}"; do
        IFS=$'\t' read -r rc elapsed_ms _ <"$BATS_TEST_TMPDIR/$variant.result"
        [ "$rc" -eq 0 ]
        echo "variant=$variant public_clear_ms=$elapsed_ms"
        [ "$elapsed_ms" -lt 5000 ]
        grep -q "QUEUED completion_tail" "$BATS_TEST_TMPDIR/$variant.output"
    done
}

# test_necessity: cmd notifications must read only a fixed tail window while preserving purpose, sender, verdict and gist payload fields.
@test "ntfy command metadata search is bounded and preserves payload contract" {
    local root="$BATS_TEST_TMPDIR/ntfy-root" output_file="$BATS_TEST_TMPDIR/ntfy-payload"
    mkdir -p "$root/scripts" "$root/queue/inbox" "$root/archive/inbox" "$root/config"
    cp "$BATS_TEST_DIRNAME/../../scripts/ntfy_cmd.sh" "$root/scripts/ntfy_cmd.sh"
    cat > "$root/scripts/ntfy.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1" > "$NTFY_PAYLOAD_FILE"
SH
    chmod +x "$root/scripts/ntfy.sh"
    dd if=/dev/zero bs=1024 count=2048 2>/dev/null | tr '\0' 'x' > "$root/queue/shogun_to_karo.yaml"
    printf '\n- id: cmd_bounded\n  purpose: bounded purpose\n' >> "$root/queue/shogun_to_karo.yaml"
    cat > "$root/queue/inbox/karo.yaml" <<'YAML'
messages:
- content: 'cmd_bounded draft verdict: APPROVE'
  from: gunshi
YAML
    cat > "$root/config/projects.yaml" <<'YAML'
current_project: infra
projects:
- id: infra
  gist_url: https://example.invalid/gist
YAML
    run env NTFY_PAYLOAD_FILE="$output_file" NTFY_CMD_SCAN_BYTES=4096 \
        bash "$root/scripts/ntfy_cmd.sh" cmd_bounded done
    [ "$status" -eq 0 ]
    grep -q 'cmd_bounded done' "$output_file"
    grep -q 'bounded purpose' "$output_file"
    grep -q '軍師: APPROVE' "$output_file"
    grep -q 'https://example.invalid/gist' "$output_file"
}

# test_necessity: cmd-complete must consume only its own CLEAR skill hint before the terminal inbox archive.
@test "completion acknowledges its matching skill hint before archive and preserves unrelated unread" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/hint-ack.log"
    mkdir -p "$FIXTURE/queue/inbox"
    cat > "$FIXTURE/queue/inbox/karo.yaml" <<'YAML'
messages:
- content: 'GATE CLEAR — cmd_fixture 完了。/cmd-complete スキルで完了処理を実行せよ。'
  from: cmd_complete_gate
  id: msg_matching
  read: false
  type: skill_hint
- content: '別件を処理せよ。'
  from: shogun
  id: msg_unrelated
  read: false
  type: cmd_new
YAML

    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -eq 0 ]
    grep -q '^inbox_mark_read.sh|karo msg_matching$' "$CMD_COMPLETE_TEST_LOG"
    ! grep -q 'msg_unrelated' "$CMD_COMPLETE_TEST_LOG"
    [ "$(grep -n -E '^(inbox_mark_read|inbox_archive)\.sh\|' "$CMD_COMPLETE_TEST_LOG" | cut -d: -f2-)" = $'inbox_mark_read.sh|karo msg_matching\ninbox_archive.sh|karo' ]
}

make_stub() {
    local path="$1" name="$2"
    mkdir -p "$(dirname "$path")"
    cat > "$path" <<SH
#!/usr/bin/env bash
printf '%s|%s\n' '$name' "\$*" >> "\$CMD_COMPLETE_TEST_LOG"
[[ "\${CMD_COMPLETE_FAIL_STEP:-}" != '$name' ]]
SH
    chmod +x "$path"
}

@test "completed fixture runs existing completion commands in canonical order" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/steps.log"
    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -eq 0 ]
    run cut -d'|' -f1 "$CMD_COMPLETE_TEST_LOG"
    [ "$status" -eq 0 ]
    [ "$output" = $'lesson_review.sh\ncmd_complete_gate.sh\ncmd_quality_log.sh\ngate_yaml_status.sh\ndashboard_update.sh\nntfy_cmd.sh\ninbox_archive.sh' ]
    ! grep -q 'gate_context_freshness.sh' "$CMD_COMPLETE_TEST_LOG"
    grep -q 'gate_yaml_status.sh|cmd_fixture' "$CMD_COMPLETE_TEST_LOG"
    grep -q 'dashboard_update.sh|cmd_fixture --bundle .*sg7_bundle.json' "$CMD_COMPLETE_TEST_LOG"
    grep -q 'ntfy_cmd.sh|cmd_fixture 完了' "$CMD_COMPLETE_TEST_LOG"
    grep -q 'inbox_archive.sh|karo' "$CMD_COMPLETE_TEST_LOG"
}

# test_necessity: dashboard publication ownership must remain explicit after the
# standalone gate path removed its legacy dashboard writers.
# regression_justification: the pre-fix gate launched dashboard_update twice plus dashboard_auto_section once (3 writers).
@test "dashboard writer ownership remains explicit after standalone removal" {
    local wrapper="$BATS_TEST_DIRNAME/../../scripts/cmd_complete.sh"
    local gate="$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh"
    run python3 - "$wrapper" "$gate" <<'PY'
import pathlib, sys
wrapper = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
gate = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
assert 'CMD_COMPLETE_WRAPPER_ACTIVE=1' in wrapper
assert gate.count('scripts/dashboard_update.sh" "$CMD_ID"') == 0
assert 'scripts/dashboard_auto_section.sh"' not in gate
assert gate.count('dashboard_update: SKIP') == 2
print('before_writer_invocations=3 after_wrapper=1 after_standalone=0')
PY
    [ "$status" -eq 0 ]
    [ "$output" = "before_writer_invocations=3 after_wrapper=1 after_standalone=0" ]
}

# test_necessity: three distinct completion tails must queue before dashboard publication so no caller enters dashboard's own flock/retry competition and every terminal event remains durable.
@test "three concurrent command completions singleflight dashboard and complete 3 of 3" {
    local cmd
    for cmd in cmd_parallel_a cmd_parallel_b cmd_parallel_c; do
        mkdir -p "$FIXTURE/queue/gates/$cmd"
        sed "s/cmd_fixture/$cmd/" "$FIXTURE/queue/gates/cmd_fixture/sg7_bundle.json" > "$FIXTURE/queue/gates/$cmd/sg7_bundle.json"
    done
    cat > "$FIXTURE/scripts/dashboard_update.sh" <<'SH'
#!/usr/bin/env bash
active="${CMD_COMPLETE_TEST_LOG}.dashboard-active"
mkdir "$active" 2>/dev/null || { printf 'dashboard_overlap\n' >> "${CMD_COMPLETE_TEST_LOG}.errors"; exit 91; }
sleep 0.05
printf 'dashboard_update.sh|%s\n' "$*" >> "$CMD_COMPLETE_TEST_LOG"
rmdir "$active"
SH
    chmod +x "$FIXTURE/scripts/dashboard_update.sh"
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/three-cmds.log"
    local cmd pid pids=()
    for cmd in cmd_parallel_a cmd_parallel_b cmd_parallel_c; do
        env CMD_COMPLETE_TEST_LOG="$CMD_COMPLETE_TEST_LOG" CMD_COMPLETE_ROOT_DIR="$FIXTURE" \
            CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" CMD_COMPLETE_SYNC_TAIL=1 \
            bash "$FIXTURE/scripts/cmd_complete.sh" "$cmd" >"$BATS_TEST_TMPDIR/$cmd.out" 2>&1 &
        pids+=("$!")
    done
    for pid in "${pids[@]}"; do wait "$pid"; done
    [ ! -e "${CMD_COMPLETE_TEST_LOG}.errors" ]
    [ "$(grep -c '^dashboard_update.sh|' "$CMD_COMPLETE_TEST_LOG")" -eq 3 ]
    [ "$(grep -c '^ntfy_cmd.sh|' "$CMD_COMPLETE_TEST_LOG")" -eq 3 ]
    [ "$(grep -h -c '^\[cmd_complete\] COMPLETE ' "$BATS_TEST_TMPDIR"/cmd_parallel_*.out | awk '{s+=$1} END{print s}')" -eq 3 ]
    ! grep -q 'RETRY dashboard' "$BATS_TEST_TMPDIR"/cmd_parallel_*.out
    ! grep -q 'RETRY ntfy' "$BATS_TEST_TMPDIR"/cmd_parallel_*.out
    grep -q 'DASHBOARD_CALLER_SINGLEFLIGHT=1' "$BATS_TEST_DIRNAME/../../scripts/cmd_complete.sh"
}

# test_necessity: completion identity must fail closed before any child step and
# the canonical report fingerprint must be propagated to the dashboard child.
@test "bundle identity is fail closed and canonical generation reaches dashboard" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/identity.log"
    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_other "$FIXTURE/queue/gates/cmd_fixture/sg7_bundle.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"review.cmd_id mismatch"* ]]
    [ ! -e "$CMD_COMPLETE_TEST_LOG" ]

    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -eq 0 ]
    grep -q 'dashboard_update.sh|cmd_fixture --bundle' "$CMD_COMPLETE_TEST_LOG"
}

# test_necessity: every completion step and dashboard retry attempt must expose wall time and exit reason for RCA.
@test "completion diagnostics record step wall time and retry failure reason" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/diagnostics.log"
    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        CMD_COMPLETE_FAIL_STEP=dashboard_update.sh CMD_COMPLETE_DASHBOARD_ATTEMPTS=1 \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -ne 0 ]
    [[ "$output" == *"PASS lesson_review wall_ms="* ]]
    [[ "$output" == *"ATTEMPT_FAILED dashboard attempt=1/1 wall_ms="*"reason=exit_rc_1"* ]]
}

@test "failed step stops later steps and names the failure" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/failed.log"
    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        CMD_COMPLETE_FAIL_STEP=cmd_complete_gate.sh bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -ne 0 ]
    [[ "$output" == *"FAILED cmd_complete_gate"* ]]
    [ "$(wc -l < "$CMD_COMPLETE_TEST_LOG")" -eq 2 ]
    ! grep -q 'dashboard_update.sh' "$CMD_COMPLETE_TEST_LOG"
}

@test "busy gate is non-terminal and wrapper publishes no completion side effects" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/busy.log"
    cat > "$FIXTURE/scripts/cmd_complete_gate.sh" <<'SH'
#!/usr/bin/env bash
printf 'cmd_complete_gate.sh|%s\n' "$*" >> "$CMD_COMPLETE_TEST_LOG"
echo 'cmd_complete_gate busy; terminal CLEAR/BLOCK is not established' >&2
exit 75
SH
    chmod +x "$FIXTURE/scripts/cmd_complete_gate.sh"

    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture

    [ "$status" -eq 75 ]
    [[ "$output" == *"FAILED cmd_complete_gate"* ]]
    [ "$(grep -c '^cmd_complete_gate.sh|' "$CMD_COMPLETE_TEST_LOG")" -eq 1 ]
    ! grep -Eq '^(cmd_quality_log|gate_yaml_status|dashboard_update|ntfy_cmd|inbox_archive)\.sh\|' "$CMD_COMPLETE_TEST_LOG"
}

# test_necessity: a later terminal CLEAR for the same generation must recover a
# durable busy failure instead of treating the earlier rc75 as final.
# regression_justification: cmd_4352 observed a failed marker winning over a
# later CLEAR and preventing the checkpointed completion tail from resuming.
@test "newer CLEAR supersedes busy failure and resumes completion once" {
    unset CMD_COMPLETE_SYNC_TAIL
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/recovered-clear.log"
    local checkpoint="$FIXTURE/queue/gates/cmd_fixture" generation
    generation="$(python3 - "$checkpoint/sg7_bundle.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["review"]["report_fingerprint"])
PY
)"
    python3 - "$checkpoint" "$generation" <<'PY'
import json, os, sys
root, generation = sys.argv[1:]
common = {"version": 1, "cmd_id": "cmd_fixture", "completion_generation": generation}
with open(os.path.join(root, "gate_worker.failed.json"), "w", encoding="utf-8") as fh:
    json.dump(dict(common, state="failed", rc=75, persisted_at_ns=100), fh)
with open(os.path.join(root, "gate_worker.clear.json"), "w", encoding="utf-8") as fh:
    json.dump(dict(common, state="clear", persisted_at_ns=200), fh)
PY

    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture

    [ "$status" -eq 0 ]
    [[ "$output" == *"RECOVERED durable gate CLEAR superseded failure marker"* ]]
    [[ "$output" == *"PASS cmd_complete_gate recovered_clear_checkpointed"* ]]
    [ "$(grep -c '^cmd_complete_gate.sh|' "$CMD_COMPLETE_TEST_LOG" 2>/dev/null || true)" -eq 0 ]
    local i
    for i in $(seq 1 300); do
        grep -q '^\[cmd_complete\] COMPLETE cmd_fixture$' \
            "$FIXTURE/queue/gates/cmd_fixture/completion_tail.log" 2>/dev/null && break
        sleep 0.05
    done
    grep -q '^\[cmd_complete\] COMPLETE cmd_fixture$' \
        "$FIXTURE/queue/gates/cmd_fixture/completion_tail.log"
}

# test_necessity: a failed marker without a strictly newer same-generation
# CLEAR remains terminal failure; recovery must not erase real failures.
@test "busy failure remains terminal when CLEAR is absent or older" {
    unset CMD_COMPLETE_SYNC_TAIL
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/terminal-failure.log"
    local checkpoint="$FIXTURE/queue/gates/cmd_fixture" generation
    generation="$(python3 - "$checkpoint/sg7_bundle.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["review"]["report_fingerprint"])
PY
)"
    python3 - "$checkpoint" "$generation" <<'PY'
import json, os, sys
root, generation = sys.argv[1:]
common = {"version": 1, "cmd_id": "cmd_fixture", "completion_generation": generation}
with open(os.path.join(root, "gate_worker.failed.json"), "w", encoding="utf-8") as fh:
    json.dump(dict(common, state="failed", rc=75, persisted_at_ns=200), fh)
with open(os.path.join(root, "gate_worker.clear.json"), "w", encoding="utf-8") as fh:
    json.dump(dict(common, state="clear", persisted_at_ns=100), fh)
PY

    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture

    [ "$status" -ne 0 ]
    [[ "$output" == *"FAILED durable gate worker marker="* ]]
    [ ! -e "$checkpoint/gate_worker.success.json" ]
}

@test "transient dashboard lock failure is retried before later steps" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/dashboard-retry.log"
    cat > "$FIXTURE/scripts/dashboard_update.sh" <<'SH'
#!/usr/bin/env bash
printf 'dashboard_update.sh|%s\n' "$*" >> "$CMD_COMPLETE_TEST_LOG"
attempt_file="${CMD_COMPLETE_TEST_LOG}.dashboard-attempt"
attempt=0
[ ! -f "$attempt_file" ] || attempt=$(cat "$attempt_file")
attempt=$((attempt + 1))
printf '%s\n' "$attempt" > "$attempt_file"
[ "$attempt" -ge 2 ]
SH
    chmod +x "$FIXTURE/scripts/dashboard_update.sh"

    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        CMD_COMPLETE_DASHBOARD_RETRY_DELAY=0 \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -eq 0 ]
    [ "$(grep -c '^dashboard_update.sh|' "$CMD_COMPLETE_TEST_LOG")" -eq 2 ]
    [ "$(grep -c '^ntfy_cmd.sh|' "$CMD_COMPLETE_TEST_LOG")" -eq 1 ]
    [[ "$output" == *"RETRY dashboard"* ]]
}

@test "persistent dashboard failure stops after bounded attempts" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/dashboard-fail.log"
    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        CMD_COMPLETE_FAIL_STEP=dashboard_update.sh \
        CMD_COMPLETE_DASHBOARD_ATTEMPTS=2 CMD_COMPLETE_DASHBOARD_RETRY_DELAY=0 \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -ne 0 ]
    [ "$(grep -c '^dashboard_update.sh|' "$CMD_COMPLETE_TEST_LOG")" -eq 2 ]
    ! grep -q '^ntfy_cmd.sh|' "$CMD_COMPLETE_TEST_LOG"
    [[ "$output" == *"FAILED dashboard after 2 attempts"* ]]
}

@test "transient ntfy timeout is retried before inbox archive" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/ntfy-retry.log"
    cat > "$FIXTURE/scripts/ntfy_cmd.sh" <<'SH'
#!/usr/bin/env bash
printf 'ntfy_cmd.sh|%s\n' "$*" >> "$CMD_COMPLETE_TEST_LOG"
attempt_file="${CMD_COMPLETE_TEST_LOG}.ntfy-attempt"
attempt=0
[ ! -f "$attempt_file" ] || attempt=$(cat "$attempt_file")
attempt=$((attempt + 1))
printf '%s\n' "$attempt" > "$attempt_file"
[ "$attempt" -ge 2 ] || sleep 0.2
SH
    chmod +x "$FIXTURE/scripts/ntfy_cmd.sh"

    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        CMD_COMPLETE_NTFY_TIMEOUT=0.1 CMD_COMPLETE_NTFY_RETRY_DELAY=0 \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -eq 0 ]
    [ "$(grep -c '^ntfy_cmd.sh|' "$CMD_COMPLETE_TEST_LOG")" -eq 2 ]
    grep -q '^inbox_archive.sh|' "$CMD_COMPLETE_TEST_LOG"
    [[ "$output" == *"RETRY ntfy after transient failure rc=124"* ]]
}

@test "persistent ntfy timeout blocks inbox archive after bounded attempts" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/ntfy-timeout.log"
    cat > "$FIXTURE/scripts/ntfy_cmd.sh" <<'SH'
#!/usr/bin/env bash
printf 'ntfy_cmd.sh|%s\n' "$*" >> "$CMD_COMPLETE_TEST_LOG"
sleep 0.2
SH
    chmod +x "$FIXTURE/scripts/ntfy_cmd.sh"

    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        CMD_COMPLETE_NTFY_ATTEMPTS=2 CMD_COMPLETE_NTFY_TIMEOUT=0.1 CMD_COMPLETE_NTFY_RETRY_DELAY=0 \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -eq 124 ]
    [ "$(grep -c '^ntfy_cmd.sh|' "$CMD_COMPLETE_TEST_LOG")" -eq 2 ]
    ! grep -q '^inbox_archive.sh|' "$CMD_COMPLETE_TEST_LOG"
    [[ "$output" == *"FAILED ntfy after 2 attempts"* ]]
}

@test "quoted bundle path remains one argument" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/quoted.log"
    local bundle="$FIXTURE/queue/gates/cmd_fixture/sg7 bundle.json"
    cp "$FIXTURE/queue/gates/cmd_fixture/sg7_bundle.json" "$bundle"
    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture "$bundle"
    [ "$status" -eq 0 ]
    grep -Fq "dashboard_update.sh|cmd_fixture --bundle $bundle" "$CMD_COMPLETE_TEST_LOG"
}

@test "wrapper resolves an explicitly linked root without repository assumptions" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/linked.log"
    ln -s "$FIXTURE" "$BATS_TEST_TMPDIR/linked-root"
    run env CMD_COMPLETE_ROOT_DIR="$BATS_TEST_TMPDIR/linked-root" \
        CMD_COMPLETE_SCRIPT_DIR="$BATS_TEST_TMPDIR/linked-root/scripts" \
        bash "$BATS_TEST_TMPDIR/linked-root/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$CMD_COMPLETE_TEST_LOG")" -eq 7 ]
}

@test "parallel invocations serialize one durable ordered flow" {
    local log_a="$BATS_TEST_TMPDIR/parallel-a.log" log_b="$BATS_TEST_TMPDIR/parallel-b.log"
    env CMD_COMPLETE_TEST_LOG="$log_a" CMD_COMPLETE_ROOT_DIR="$FIXTURE" \
        CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture &
    local pid_a=$!
    env CMD_COMPLETE_TEST_LOG="$log_b" CMD_COMPLETE_ROOT_DIR="$FIXTURE" \
        CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture &
    local pid_b=$!
    wait "$pid_a"
    wait "$pid_b"
    local total=0
    [[ -f "$log_a" ]] && total=$((total + $(wc -l < "$log_a")))
    [[ -f "$log_b" ]] && total=$((total + $(wc -l < "$log_b")))
    [ "$total" -eq 7 ]
}

@test "unrelated dashboard-wide freshness ALERT cannot block command completion" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/unrelated-global.log"
    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        CMD_COMPLETE_FAIL_STEP=gate_context_freshness.sh \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -eq 0 ]
    ! grep -q 'gate_context_freshness.sh' "$CMD_COMPLETE_TEST_LOG"
    grep -q 'cmd_complete_gate.sh|cmd_fixture' "$CMD_COMPLETE_TEST_LOG"
}

# test_necessity: archive_terminal must distinguish a parent report from a
# suffix-named child report while both are present in queue/reports.
# regression_justification: cmd_4393 was falsely BLOCKed because the parent
# prefix glob counted completed child reports as active parent reports.
@test "archive terminal counts only the exact parent report identity" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/exact-parent.log"
    local parent="$FIXTURE/queue/reports/hanzo_report_cmd_fixture.yaml"
    local child="$FIXTURE/queue/reports/saizo_report_cmd_fixture_recon2.yaml"
    mkdir -p "$FIXTURE/queue/reports" "$FIXTURE/queue/archive/reports"
    cat > "$parent" <<'YAML'
parent_cmd: cmd_fixture
status: completed
YAML
    cat > "$child" <<'YAML'
parent_cmd: cmd_fixture_recon2
status: completed
YAML

    local parent_hash
    parent_hash="$(sha256sum "$parent" | awk '{print $1}')"
    cat > "$FIXTURE/queue/gates/cmd_fixture/sg7_bundle.json" <<JSON
{"review":{"cmd_id":"cmd_fixture","report_fingerprint":"$parent_hash"}}
JSON
    cat > "$FIXTURE/scripts/archive_completed.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
project="${ARCHIVE_COMPLETED_PROJECT_DIR:?}"
printf 'archive_completed.sh|%s\n' "$*" >> "$CMD_COMPLETE_TEST_LOG"
archive="$project/queue/archive/reports/hanzo_report_cmd_fixture.yaml"
mv "$project/queue/reports/hanzo_report_cmd_fixture.yaml" "$archive"
ln -s "$archive" "$project/queue/reports/hanzo_report_cmd_fixture.yaml"
touch "$project/queue/gates/cmd_fixture/archive.done"
SH
    chmod +x "$FIXTURE/scripts/archive_completed.sh"

    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS archive_terminal marker=present active_reports=0"* ]]
    [ -L "$parent" ]
    [ -f "$child" ]
    grep -q '^archive_completed.sh|3 cmd_fixture$' "$CMD_COMPLETE_TEST_LOG"
}

@test "archived command not-found continues with archive and gate CLEAR evidence" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/archived.log"
    mkdir -p "$FIXTURE/queue/archive/cmds" "$FIXTURE/logs"
    : > "$FIXTURE/queue/archive/cmds/cmd_fixture_completed.yaml"
    printf 'cmd_fixture CLEAR\n' > "$FIXTURE/logs/gate_metrics.log"
    cat > "$FIXTURE/scripts/gates/gate_yaml_status.sh" <<'SH'
#!/usr/bin/env bash
printf 'gate_yaml_status.sh|%s\n' "$*" >> "$CMD_COMPLETE_TEST_LOG"
echo 'ERROR: cmd_fixture not found in shogun_to_karo.yaml' >&2
exit 1
SH
    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -eq 0 ]
    [[ "$output" == *"archived CLEAR evidence"* ]]
    grep -q 'dashboard_update.sh' "$CMD_COMPLETE_TEST_LOG"
}

@test "archived command not-found stops when any CLEAR evidence is missing" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/missing-evidence.log"
    mkdir -p "$FIXTURE/queue/archive/cmds" "$FIXTURE/logs"
    : > "$FIXTURE/queue/archive/cmds/cmd_fixture_completed.yaml"
    printf 'cmd_fixture complete\n' > "$FIXTURE/dashboard.md"
    : > "$FIXTURE/logs/gate_metrics.log"
    cat > "$FIXTURE/scripts/gates/gate_yaml_status.sh" <<'SH'
#!/usr/bin/env bash
printf 'gate_yaml_status.sh|%s\n' "$*" >> "$CMD_COMPLETE_TEST_LOG"
echo 'ERROR: cmd_fixture not found in shogun_to_karo.yaml' >&2
exit 1
SH
    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -ne 0 ]
    [[ "$output" == *"completion evidence incomplete"* ]]
    ! grep -q 'dashboard_update.sh' "$CMD_COMPLETE_TEST_LOG"
}

@test "unknown-prefix direct command not-found continues with consumed SG7 and correlated CLEAR" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/direct.log"
    local cmd=cmd_reflux_promotion_fixture
    mkdir -p "$FIXTURE/queue/gates/$cmd" "$FIXTURE/logs"
    sed "s/cmd_fixture/$cmd/" "$FIXTURE/queue/gates/cmd_fixture/sg7_bundle.json" > "$FIXTURE/queue/gates/$cmd/sg7_bundle.json"
    printf '%s CLEAR\n' "$cmd" > "$FIXTURE/logs/gate_metrics.log"
    cat > "$FIXTURE/scripts/gates/gate_yaml_status.sh" <<'SH'
#!/usr/bin/env bash
printf 'gate_yaml_status.sh|%s\n' "$*" >> "$CMD_COMPLETE_TEST_LOG"
echo "ERROR: $1 not found in shogun_to_karo.yaml" >&2
exit 1
SH
    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" "$cmd"
    [ "$status" -eq 0 ]
    [[ "$output" == *"direct SG7/CLEAR evidence"* ]]
    grep -q 'dashboard_update.sh' "$CMD_COMPLETE_TEST_LOG"
}

@test "unknown-prefix direct command not-found stops without consumed SG7 bundle" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/direct-missing-bundle.log"
    local cmd=cmd_reflux_promotion_fixture
    mkdir -p "$FIXTURE/logs"
    printf '%s CLEAR\n' "$cmd" > "$FIXTURE/logs/gate_metrics.log"
    cat > "$FIXTURE/scripts/gates/gate_yaml_status.sh" <<'SH'
#!/usr/bin/env bash
printf 'gate_yaml_status.sh|%s\n' "$*" >> "$CMD_COMPLETE_TEST_LOG"
echo "ERROR: $1 not found in shogun_to_karo.yaml" >&2
exit 1
SH
    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" "$cmd" "$FIXTURE/queue/gates/$cmd/missing.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"FAILED bundle missing"* ]]
    ! grep -q 'dashboard_update.sh' "$CMD_COMPLETE_TEST_LOG"
}

@test "direct command not-found stops without correlated CLEAR" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/direct-missing.log"
    local cmd=cmd_karo_fixture
    mkdir -p "$FIXTURE/queue/gates/$cmd" "$FIXTURE/logs"
    sed "s/cmd_fixture/$cmd/" "$FIXTURE/queue/gates/cmd_fixture/sg7_bundle.json" > "$FIXTURE/queue/gates/$cmd/sg7_bundle.json"
    : > "$FIXTURE/logs/gate_metrics.log"
    cat > "$FIXTURE/scripts/gates/gate_yaml_status.sh" <<'SH'
#!/usr/bin/env bash
printf 'gate_yaml_status.sh|%s\n' "$*" >> "$CMD_COMPLETE_TEST_LOG"
echo "ERROR: $1 not found in shogun_to_karo.yaml" >&2
exit 1
SH
    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        bash "$FIXTURE/scripts/cmd_complete.sh" "$cmd"
    [ "$status" -ne 0 ]
    [[ "$output" == *"completion evidence incomplete"* ]]
    ! grep -q 'dashboard_update.sh' "$CMD_COMPLETE_TEST_LOG"
}

@test "completion gate requires a valid SG7 bundle before publishing CLEAR" {
    local gate="$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh"
    run python3 - "$gate" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
sg7 = text.index("sg7_bundle_missing_or_invalid")
required = text.index("# task_type検出")
assert sg7 < required
assert 'review_bundle.py" consume' in text[sg7-1200:sg7+1200]
assert '--expect-verdict APPROVE' in text[sg7-1200:sg7+1200]
print("PASS: SG7 validation precedes completion gate evaluation")
PY
    [ "$status" -eq 0 ]
}

# test_necessity: cmd_karo_hotfix_karo_direct_gate_bypass_20260807 — karo_direct起源cmd
# (CMD_ID=cmd_karo_*)はSG7レビューフローを経由しないためqueue/gates/<cmd>/sg7_bundle.jsonが
# 存在しない場合がある。この不変量を固定する: SG7なしのcmd_karo_*は必須チェックをスキップし、
# review_two_phase(gunshi LGTM + karo ACCEPT)確認済みreport群のfingerprintから合成した
# 64桁hexをSHOGUN_COMPLETION_GENERATIONとして採用する。SG7が存在する場合は消費する。
@test "karo_direct origin cmd consumes SG7 when present and otherwise uses review_two_phase fingerprint" {
    local gate="$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh"
    run python3 - "$gate" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()

guard = text.index('[[ "$CMD_ID" != cmd_karo_* ]] || [ -f "$_sg7_bundle" ]')
sg7 = text.index("sg7_bundle_missing_or_invalid")
assert guard < sg7, "cmd_karo_* SG7-present guard must wrap bundle validation"

fallback = text.index('[[ "$CMD_ID" == cmd_karo_* ]] && [ -z "${SHOGUN_COMPLETION_GENERATION:-}" ]')
window = text[fallback:fallback + 900]
assert 'review_manifest_fingerprint' in window
assert '^[0-9a-f]{64}$' in window
assert 'karo_direct_completion_generation_invalid' in window
assert 'export SHOGUN_COMPLETION_GENERATION' in window
print("PASS: karo_direct cmds consume present SG7 or derive generation from review_two_phase")
PY
    [ "$status" -eq 0 ]
}
