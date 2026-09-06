#!/usr/bin/env bats
# test_necessity: deploy_taskのdelivery後まで続くbash processは、並行編集されるworking-tree原本ではなく構文検証済みimmutable self-snapshotだけをparseし続けなければならない。

setup() {
    PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    WORK_DIR="$(mktemp -d "$BATS_TMPDIR/deploy-self-snapshot.XXXXXX")"
    mkdir -p "$WORK_DIR/scripts" "$WORK_DIR/hold"
    cp "$PROJECT_ROOT/scripts/deploy_task.sh" "$WORK_DIR/scripts/deploy_task.sh"
}

teardown() {
    rm -rf "$WORK_DIR"
}

@test "running deploy parses immutable snapshot when working-tree source changes mid-process" {
    run bash -c '
        set -euo pipefail
        fixture="$1"
        root="$2"
        hold="$3"
        out="$4"
        err="$5"

        DEPLOY_TASK_ROOT_OVERRIDE="$root" \
        DEPLOY_TASK_SELF_SNAPSHOT_TEST_ONLY=1 \
        DEPLOY_TASK_SELF_SNAPSHOT_TEST_HOLD_DIR="$hold" \
            bash "$fixture" >"$out" 2>"$err" &
        child=$!

        for _ in $(seq 1 500); do
            [ -e "$hold/ready" ] && break
            sleep 0.01
        done
        [ -e "$hold/ready" ]

        # This deliberately makes the original path unparsable while the
        # already-running deployment is paused near the start of its snapshot.
        printf "if then impossible\n" > "$fixture"
        touch "$hold/release"
        wait "$child"
        grep -qx SELF_SNAPSHOT_OK "$out"
        [ ! -s "$err" ]
    ' _ "$WORK_DIR/scripts/deploy_task.sh" "$PROJECT_ROOT" "$WORK_DIR/hold" \
        "$WORK_DIR/out" "$WORK_DIR/err"

    [ "$status" -eq 0 ]
}

@test "invalid source snapshot fails closed before deployment" {
    printf 'if then invalid\n' > "$WORK_DIR/scripts/deploy_task.sh"

    run env DEPLOY_TASK_ROOT_OVERRIDE="$PROJECT_ROOT" \
        bash "$WORK_DIR/scripts/deploy_task.sh"

    [ "$status" -ne 0 ]
}

# test_necessity: a task_contract_snapshot with no contract_version key predates
# the versioned schema and must read as compatible forever, so redeploying a
# schema-unaware old task can never newly BLOCK it under the new reader.
@test "contract-status reads a legacy snapshot with no contract_version as compatible" {
    cat > "$WORK_DIR/task.yaml" <<'YAML'
task:
  task_id: cmd_legacy_full
  parent_cmd: cmd_legacy
  target_path: [scripts/example.py]
YAML
    cat > "$WORK_DIR/report.yaml" <<'YAML'
worker_id: kotaro
parent_cmd: cmd_legacy
task_id: cmd_legacy_full
task_contract_snapshot:
  parent_cmd: cmd_legacy
  task_id: cmd_legacy_full
  ac_fingerprint: abc12345
YAML

    run python3 "$PROJECT_ROOT/scripts/lib/report_gate_contract.py" contract-status \
        "$WORK_DIR/task.yaml" "$WORK_DIR/report.yaml"

    [ "$status" -eq 0 ]
    [[ "$output" == *"legacy snapshot (no contract_version)"* ]]
}

# test_necessity: a snapshot tagged with a contract_version this reader does
# not recognize must fail explicitly (never silently pass, never silently
# reinterpreted), while an ordinary same-generation current-version snapshot
# must still pass — an unrecognized future version cannot become the default
# way normal deploys start failing.
@test "contract-status rejects an unrecognized contract_version but accepts the current one" {
    cat > "$WORK_DIR/task.yaml" <<'YAML'
task:
  task_id: cmd_current_full
  parent_cmd: cmd_current
  target_path: [scripts/example.py]
YAML
    cat > "$WORK_DIR/report_future.yaml" <<'YAML'
worker_id: kotaro
parent_cmd: cmd_current
task_id: cmd_current_full
task_contract_snapshot:
  contract_version: 99
  parent_cmd: cmd_current
  task_id: cmd_current_full
  ac_fingerprint: abc12345
YAML
    cat > "$WORK_DIR/report_current.yaml" <<'YAML'
worker_id: kotaro
parent_cmd: cmd_current
task_id: cmd_current_full
task_contract_snapshot:
  contract_version: 1
  parent_cmd: cmd_current
  task_id: cmd_current_full
  ac_fingerprint: abc12345
YAML

    run python3 "$PROJECT_ROOT/scripts/lib/report_gate_contract.py" contract-status \
        "$WORK_DIR/task.yaml" "$WORK_DIR/report_future.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"CONTRACT_INVALID contract_version unsupported: 99"* ]]

    run python3 "$PROJECT_ROOT/scripts/lib/report_gate_contract.py" contract-status \
        "$WORK_DIR/task.yaml" "$WORK_DIR/report_current.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK contract_version=1"* ]]
}
