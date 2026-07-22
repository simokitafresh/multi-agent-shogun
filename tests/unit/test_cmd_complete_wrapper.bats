#!/usr/bin/env bats

setup() {
    export CMD_COMPLETE_SYNC_TAIL=1
    export FIXTURE="$BATS_TEST_TMPDIR/root"
    mkdir -p "$FIXTURE/scripts/gates" "$FIXTURE/scripts/lib" "$FIXTURE/queue/gates/cmd_fixture"
    cp "$BATS_TEST_DIRNAME/../../scripts/cmd_complete.sh" "$FIXTURE/scripts/cmd_complete.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/defense_overhead_writer.sh" \
        "$FIXTURE/scripts/lib/defense_overhead_writer.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/retro_pane_prompt.sh" \
        "$FIXTURE/scripts/lib/retro_pane_prompt.sh"
    printf '{}\n' > "$FIXTURE/queue/gates/cmd_fixture/sg7_bundle.json"

    cat > "$FIXTURE/scripts/review_bundle.py" <<'PY'
import json
print(json.dumps({"acceptance_criteria_count": 2, "scope": ["scripts"], "project": "infra"}))
PY
    for name in lesson_review.sh cmd_complete_gate.sh cmd_quality_log.sh dashboard_update.sh ntfy_cmd.sh inbox_mark_read.sh inbox_archive.sh karo_workaround_log.sh; do
        make_stub "$FIXTURE/scripts/$name" "$name"
    done
    make_stub "$FIXTURE/scripts/gates/gate_context_freshness.sh" gate_context_freshness.sh
    make_stub "$FIXTURE/scripts/gates/gate_yaml_status.sh" gate_yaml_status.sh
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

# test_necessity: all known slow/failing tail variants must remain outside the public caller while the worker preserves checkpoints.
@test "five tail latency variants return from public caller below five seconds" {
    unset CMD_COMPLETE_SYNC_TAIL
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/five-variants.log"
    local variant cmd start_ns elapsed_ms
    for variant in sleep5 huge_archive endpoint_failure notification_throttle dashboard_contention; do
        cmd="cmd_${variant}"
        mkdir -p "$FIXTURE/queue/gates/$cmd"
        cp "$FIXTURE/queue/gates/cmd_fixture/sg7_bundle.json" "$FIXTURE/queue/gates/$cmd/sg7_bundle.json"
        start_ns="$(date +%s%N)"
        run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
            CMD_COMPLETE_TEST_VARIANT="$variant" bash "$FIXTURE/scripts/cmd_complete.sh" "$cmd"
        elapsed_ms=$(( ($(date +%s%N) - start_ns) / 1000000 ))
        [ "$status" -eq 0 ]
        [ "$elapsed_ms" -lt 5000 ]
        [[ "$output" == *"QUEUED completion_tail"* ]]
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

# test_necessity: normal wrapper and standalone/emergency completion paths must each select exactly one dashboard writer.
# regression_justification: the pre-fix gate launched dashboard_update twice plus dashboard_auto_section once (3 writers).
@test "single dashboard writer ownership is explicit for wrapper and standalone gate paths" {
    local wrapper="$BATS_TEST_DIRNAME/../../scripts/cmd_complete.sh"
    local gate="$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh"
    run python3 - "$wrapper" "$gate" <<'PY'
import pathlib, sys
wrapper = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
gate = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
assert 'CMD_COMPLETE_WRAPPER_ACTIVE=1' in wrapper
assert gate.count('scripts/dashboard_update.sh" "$CMD_ID"') == 2  # emergency + normal standalone
assert 'scripts/dashboard_auto_section.sh"' not in gate
assert gate.count('dashboard_update: delegated to cmd_complete wrapper') == 2
print('before_writer_invocations=3 after_wrapper=1 after_standalone=1')
PY
    [ "$status" -eq 0 ]
    [ "$output" = "before_writer_invocations=3 after_wrapper=1 after_standalone=1" ]
}

# test_necessity: three distinct completion tails must queue before dashboard publication so no caller enters dashboard's own flock/retry competition and every terminal event remains durable.
@test "three concurrent command completions singleflight dashboard and complete 3 of 3" {
    local cmd
    for cmd in cmd_parallel_a cmd_parallel_b cmd_parallel_c; do
        mkdir -p "$FIXTURE/queue/gates/$cmd"
        cp "$FIXTURE/queue/gates/cmd_fixture/sg7_bundle.json" "$FIXTURE/queue/gates/$cmd/sg7_bundle.json"
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

@test "archived command not-found continues only with all three CLEAR evidences" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/archived.log"
    mkdir -p "$FIXTURE/queue/archive/cmds" "$FIXTURE/logs"
    : > "$FIXTURE/queue/archive/cmds/cmd_fixture_completed.yaml"
    printf 'cmd_fixture complete\n' > "$FIXTURE/dashboard.md"
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
    cp "$FIXTURE/queue/gates/cmd_fixture/sg7_bundle.json" "$FIXTURE/queue/gates/$cmd/sg7_bundle.json"
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
    cp "$FIXTURE/queue/gates/cmd_fixture/sg7_bundle.json" "$FIXTURE/queue/gates/$cmd/sg7_bundle.json"
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
