#!/usr/bin/env bats

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    SCRIPT="$TEST_TMPDIR/cmd_complete_gate.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh" "$SCRIPT"
}

teardown() {
    rm -f "$TEST_TMPDIR/ready" "$TEST_TMPDIR/release" "$TEST_TMPDIR/output" "$SCRIPT"
    rmdir "$TEST_TMPDIR"
}

# test_necessity: a running completion gate must observe one immutable script
# generation even when pregate convergence replaces its canonical source.
# regression_justification: cmd_reflux_insight_202608190151_hayate published
# successfully, then the running gate read a mixed generation and stopped at
# line 11084 with rc=2 although the updated canonical file passed bash -n.
@test "running gate uses immutable source across canonical self-update" {
    CMD_COMPLETE_GATE_SNAPSHOT_PROBE_READY="$TEST_TMPDIR/ready" \
    CMD_COMPLETE_GATE_SNAPSHOT_PROBE_RELEASE="$TEST_TMPDIR/release" \
        bash "$SCRIPT" cmd_probe >"$TEST_TMPDIR/output" 2>&1 &
    gate_pid=$!

    for _ in $(seq 1 100); do
        [ -e "$TEST_TMPDIR/ready" ] && break
        sleep 0.05
    done
    [ -e "$TEST_TMPDIR/ready" ]

    printf '\n# canonical generation replaced during execution\n' >> "$SCRIPT"
    touch "$TEST_TMPDIR/release"
    wait "$gate_pid"

    run cat "$TEST_TMPDIR/output"
    [ "$status" -eq 0 ]
    [[ "$output" == snapshot_immutable=1* ]]
    [[ "$output" == *"canonical=$SCRIPT"* ]]
    run bash -n "$SCRIPT"
    [ "$status" -eq 0 ]
}
