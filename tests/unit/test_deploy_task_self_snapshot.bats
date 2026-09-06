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

# test_necessity: inbox_write.sh's lesson_safety_net (inject_universal_lessons_if_missing)
# can add related_lessons to the LIVE task file after the deploy-time snapshot
# already froze an empty lesson_set. A report that correctly stays faithful to
# the frozen (empty) snapshot must read as allowed/OK via the snapshot, not be
# judged against the live task's post-injection lessons; a report that instead
# reports the live post-injection lessons must be rejected as extra, since the
# report's own generation never had those lessons assigned to it.
@test "snapshot-authoritative lesson reads survive a post-deploy lesson_safety_net injection" {
    cat > "$WORK_DIR/task_after_injection.yaml" <<'YAML'
task:
  task_id: cmd_p07_full
  parent_cmd: cmd_p07
  task_type: hotfix
  related_lessons:
  - id: L097
  - id: L019
YAML
    cat > "$WORK_DIR/report_empty.yaml" <<'YAML'
worker_id: kotaro
parent_cmd: cmd_p07
task_id: cmd_p07_full
task_contract_snapshot:
  parent_cmd: cmd_p07
  task_id: cmd_p07_full
  ac_fingerprint: abc12345
  lesson_set:
    mode: subset
    ids: []
lessons_useful: []
YAML
    cat > "$WORK_DIR/report_injected.yaml" <<'YAML'
worker_id: kotaro
parent_cmd: cmd_p07
task_id: cmd_p07_full
task_contract_snapshot:
  parent_cmd: cmd_p07
  task_id: cmd_p07_full
  ac_fingerprint: abc12345
  lesson_set:
    mode: subset
    ids: []
lessons_useful:
- id: L097
  useful: true
  reason: injected post-deploy by lesson_safety_net
- id: L019
  useful: true
  reason: injected post-deploy by lesson_safety_net
YAML

    run python3 "$PROJECT_ROOT/scripts/lib/report_gate_contract.py" lesson-feedback-set \
        "$WORK_DIR/task_after_injection.yaml" "$WORK_DIR/report_empty.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK mode=subset allowed=0 reported=0"* ]]

    run python3 "$PROJECT_ROOT/scripts/lib/report_gate_contract.py" lesson-empty-allowed \
        "$WORK_DIR/task_after_injection.yaml" "$WORK_DIR/report_empty.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == "ALLOWED" ]]

    run python3 "$PROJECT_ROOT/scripts/lib/report_gate_contract.py" lesson-feedback-set \
        "$WORK_DIR/task_after_injection.yaml" "$WORK_DIR/report_injected.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"extra=L019,L097"* ]]
}

# test_necessity(P07, cmd_karo_hotfix_contract_schema_20260907): a no-code
# report whose commit_contract.repo_root names a different repository (e.g. a
# DM-Signal cross-repo recon) must resolve its receipt commit's tree inside
# THAT repository via the gate's canonical repo resolver
# (gate_report_format_main._resolve_commit_repo), not always this repo's own
# root; otherwise every cross-repo no-code terminal write fails-BLOCK with
# "terminal no-code receipt tree unavailable" even when the receipt and
# evidence genuinely agree. This file's own planned_paths does not list
# tests/unit/test_report_field_set_terminal_readiness.bats (the more natural
# home for this); placed here to stay within this task's authorized scope.
@test "report_field_set no-code receipt tree check resolves commit_contract.repo_root, not always this repo" {
    OTHER_REPO="$WORK_DIR/other_repo"
    mkdir -p "$OTHER_REPO"
    (cd "$OTHER_REPO" && git init -q)
    BLOB=$(cd "$OTHER_REPO" && printf 'hello\n' | git hash-object -w --stdin)
    TREE=$(cd "$OTHER_REPO" && printf '100644 blob %s\tf.txt\n' "$BLOB" | git mktree)
    # A tree object peels to itself under ^{tree}, so this stands in for a
    # receipt commit sha without creating an actual commit object.
    run bash -c 'cd "$1" && git rev-parse --verify "$2^{tree}"' _ "$OTHER_REPO" "$TREE"
    [ "$status" -eq 0 ]
    [ "$output" = "$TREE" ]

    FIXTURE_ROOT="$WORK_DIR/fixture_root"
    mkdir -p "$FIXTURE_ROOT/tasks_dir"
    RECEIPT_DIR="$WORK_DIR/receipt_dir"
    mkdir -p "$RECEIPT_DIR"
    printf 'artifact\n' > "$RECEIPT_DIR/artifact.txt"
    SHA=$(sha256sum "$RECEIPT_DIR/artifact.txt" | awk '{print $1}')
    cat > "$RECEIPT_DIR/receipt.json" <<JSON
{"complete": true, "result": "PASS", "rc": 0, "skip_count": 0,
 "test_paths": ["dummy_test_path"], "artifact": "$RECEIPT_DIR/artifact.txt",
 "output_sha256": "$SHA", "task_id": "cmd_p07x_full", "commit_sha": "$TREE"}
JSON

    cat > "$FIXTURE_ROOT/tasks_dir/p07worker.yaml" <<TASKYAML
task:
  task_id: cmd_p07x_full
  parent_cmd: cmd_p07x
  project: infra
  task_type: recon2
  commit_contract:
    required: false
    reason: no_code_recon
    task_type: recon2
    planned_paths: []
    repo_root: $OTHER_REPO
TASKYAML

    write_report() {
        local before_tree="$1"
        cat > "$FIXTURE_ROOT/p07worker_report.yaml" <<REPORTYAML
worker_id: p07worker
task_id: cmd_p07x_full
parent_cmd: cmd_p07x
ac_version_read: dummyac01
status: in_progress
commit_contract:
  required: false
  reason: no_code_recon
  task_type: recon2
  planned_paths: []
  repo_root: $OTHER_REPO
commit_hash: no-code-change
no_code_change_evidence:
  tree_unchanged: true
  before_tree: "$before_tree"
  after_tree: "$before_tree"
binary_checks:
  AC1:
  - check: dummy check
    result: 'yes'
files_modified:
  - path: queue/notes/p07_dummy_fixture.md
lessons_useful: []
lesson_candidate:
  found: false
  no_lesson_reason: n/a
REPORTYAML
    }

    # Positive: repo_root resolves to the other repo and the tree matches.
    write_report "$TREE"
    run env RFS_TASK_FILE_PATH="$FIXTURE_ROOT/tasks_dir/p07worker.yaml" \
        REPORT_FIELD_SET_TASK_ROOT="$FIXTURE_ROOT" \
        bash "$PROJECT_ROOT/scripts/report_field_set.sh" --batch \
        "$FIXTURE_ROOT/p07worker_report.yaml" <<EOF
test_receipt_path: $RECEIPT_DIR/receipt.json
status: completed
EOF
    # Downstream report-completeness prechecks (unrelated to this receipt
    # check) still fail this minimal fixture; the fix under test is proven by
    # the status/test_receipt_path having already been written before that.
    grep -q '^status: completed$' "$FIXTURE_ROOT/p07worker_report.yaml"
    grep -q "test_receipt_path: $RECEIPT_DIR/receipt.json" "$FIXTURE_ROOT/p07worker_report.yaml"

    # Negative: same valid repo_root, but the recorded tree does not match.
    write_report "ffffffffffffffffffffffffffffffffffffffff"
    run env RFS_TASK_FILE_PATH="$FIXTURE_ROOT/tasks_dir/p07worker.yaml" \
        REPORT_FIELD_SET_TASK_ROOT="$FIXTURE_ROOT" \
        bash "$PROJECT_ROOT/scripts/report_field_set.sh" --batch \
        "$FIXTURE_ROOT/p07worker_report.yaml" <<EOF
test_receipt_path: $RECEIPT_DIR/receipt.json
status: completed
EOF
    [ "$status" -ne 0 ]
    [[ "$output" == *"terminal no-code receipt tree mismatch"* ]]

    # Negative: repo_root itself does not resolve to a real git repository.
    sed -i "s#repo_root: $OTHER_REPO#repo_root: $WORK_DIR/does-not-exist#" \
        "$FIXTURE_ROOT/tasks_dir/p07worker.yaml"
    write_report "$TREE"
    sed -i "s#repo_root: $OTHER_REPO#repo_root: $WORK_DIR/does-not-exist#" \
        "$FIXTURE_ROOT/p07worker_report.yaml"
    run env RFS_TASK_FILE_PATH="$FIXTURE_ROOT/tasks_dir/p07worker.yaml" \
        REPORT_FIELD_SET_TASK_ROOT="$FIXTURE_ROOT" \
        bash "$PROJECT_ROOT/scripts/report_field_set.sh" --batch \
        "$FIXTURE_ROOT/p07worker_report.yaml" <<EOF
test_receipt_path: $RECEIPT_DIR/receipt.json
status: completed
EOF
    [ "$status" -ne 0 ]
    [[ "$output" == *"terminal no-code receipt repo"* ]]
}
