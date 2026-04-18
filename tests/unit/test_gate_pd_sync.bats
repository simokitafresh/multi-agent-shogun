#!/usr/bin/env bats
# test_gate_pd_sync.bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE="$PROJECT_ROOT/scripts/gates/gate_pd_sync.sh"
    [ -f "$SRC_GATE" ] || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gate_pd_sync.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/queue/alerts"
    cp "$SRC_GATE" "$TEST_TMPDIR/scripts/gates/gate_pd_sync.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_pd_sync.sh"
    export GATE_UNDER_TEST="$TEST_TMPDIR/scripts/gates/gate_pd_sync.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "missing pending_decisions file returns warning and success" {
    run bash "$GATE_UNDER_TEST" "PD-001"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
}

@test "target synced and no unsynced entries passes" {
    cat > "$TEST_TMPDIR/queue/pending_decisions.yaml" <<'YAML'
summary:
  total: 1
  resolved: 1
  pending: 0
decisions:
- id: PD-001
  status: resolved
  context_synced: true
YAML

    run bash "$GATE_UNDER_TEST" "PD-001"
    [ "$status" -eq 0 ]
    [[ "$output" == *"context_synced=true"* ]]
}

@test "any unsynced entry blocks and logs ids" {
    cat > "$TEST_TMPDIR/queue/pending_decisions.yaml" <<'YAML'
summary:
  total: 2
  resolved: 1
  pending: 1
decisions:
- id: PD-001
  status: resolved
  context_synced: true
- id: PD-002
  status: pending
  context_synced: false
YAML

    run bash "$GATE_UNDER_TEST" "PD-001"
    [ "$status" -eq 1 ]
    [[ "$output" == *"context未反映PDあり: PD-002"* ]]
    [ -f "$TEST_TMPDIR/queue/alerts/pd_unsync.log" ]
}

@test "target not found returns warning when there are no unsynced ids" {
    cat > "$TEST_TMPDIR/queue/pending_decisions.yaml" <<'YAML'
summary:
  total: 1
  resolved: 1
  pending: 0
decisions:
- id: PD-010
  status: resolved
  context_synced: true
YAML

    run bash "$GATE_UNDER_TEST" "PD-999"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PD-999 not found"* ]]
}
