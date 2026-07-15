#!/usr/bin/env bats

setup() {
    export FIXTURE="$BATS_TEST_TMPDIR/root"
    mkdir -p "$FIXTURE/scripts/gates" "$FIXTURE/queue/gates/cmd_fixture"
    cp "$BATS_TEST_DIRNAME/../../scripts/cmd_complete.sh" "$FIXTURE/scripts/cmd_complete.sh"
    printf '{}\n' > "$FIXTURE/queue/gates/cmd_fixture/sg7_bundle.json"

    cat > "$FIXTURE/scripts/review_bundle.py" <<'PY'
import json
print(json.dumps({"acceptance_criteria_count": 2, "scope": ["scripts"], "project": "infra"}))
PY
    for name in lesson_review.sh cmd_complete_gate.sh cmd_quality_log.sh dashboard_update.sh ntfy_cmd.sh inbox_archive.sh karo_workaround_log.sh; do
        make_stub "$FIXTURE/scripts/$name" "$name"
    done
    make_stub "$FIXTURE/scripts/gates/gate_context_freshness.sh" gate_context_freshness.sh
    make_stub "$FIXTURE/scripts/gates/gate_yaml_status.sh" gate_yaml_status.sh
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

@test "failed step stops later steps and names the failure" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/failed.log"
    run env CMD_COMPLETE_ROOT_DIR="$FIXTURE" CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" \
        CMD_COMPLETE_FAIL_STEP=cmd_complete_gate.sh bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture
    [ "$status" -ne 0 ]
    [[ "$output" == *"FAILED cmd_complete_gate"* ]]
    [ "$(wc -l < "$CMD_COMPLETE_TEST_LOG")" -eq 2 ]
    ! grep -q 'dashboard_update.sh' "$CMD_COMPLETE_TEST_LOG"
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

@test "parallel invocations keep complete independent ordered flows" {
    local log_a="$BATS_TEST_TMPDIR/parallel-a.log" log_b="$BATS_TEST_TMPDIR/parallel-b.log"
    env CMD_COMPLETE_TEST_LOG="$log_a" CMD_COMPLETE_ROOT_DIR="$FIXTURE" \
        CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture &
    local pid_a=$!
    env CMD_COMPLETE_TEST_LOG="$log_b" CMD_COMPLETE_ROOT_DIR="$FIXTURE" \
        CMD_COMPLETE_SCRIPT_DIR="$FIXTURE/scripts" bash "$FIXTURE/scripts/cmd_complete.sh" cmd_fixture &
    local pid_b=$!
    wait "$pid_a"
    wait "$pid_b"
    [ "$(wc -l < "$log_a")" -eq 7 ]
    [ "$(wc -l < "$log_b")" -eq 7 ]
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

@test "direct command not-found continues with consumed SG7 and correlated CLEAR" {
    export CMD_COMPLETE_TEST_LOG="$BATS_TEST_TMPDIR/direct.log"
    local cmd=cmd_karo_fixture
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
