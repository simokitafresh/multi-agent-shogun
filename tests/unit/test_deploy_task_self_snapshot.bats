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

# test_necessity(AC1, cmd_karo_hotfix_contract_schema_20260907): ninja_monitor.sh's
# report_gate_generation_key binds its completion-gate dedupe cache to the
# report's own identity/AC when a task_contract_snapshot is present, so
# redeploying the worker's task file to a new generation cannot silently
# change a still-unarchived past report's cache bucket. A snapshot-free
# (legacy) report must keep reading the live task exactly as before, and an
# actual report content change must still change the key regardless.
@test "ninja_monitor report_gate_generation_key is stable across task redeploy once a snapshot exists" {
    awk '/^report_gate_generation_key\(\) \{/{flag=1} flag{print} flag && /^}$/{exit}' \
        "$PROJECT_ROOT/scripts/ninja_monitor.sh" > "$WORK_DIR/rgk_fn.sh"
    [ -s "$WORK_DIR/rgk_fn.sh" ]

    cat > "$WORK_DIR/task_gen1.yaml" <<'YAML'
task:
  task_id: cmd_x_full
  parent_cmd: cmd_x
  ac_version: old_ac_111
  deployed_at: "2026-09-01T00:00:00"
  target_path: [a.py]
  planned_paths: [a.py]
  acceptance_criteria: [{id: AC1, description: old}]
  not_in_scope: []
  commit_contract: {required: true}
YAML
    cat > "$WORK_DIR/task_gen2_redeployed.yaml" <<'YAML'
task:
  task_id: cmd_y_full
  parent_cmd: cmd_y
  ac_version: new_ac_222
  deployed_at: "2026-09-01T00:00:00"
  target_path: [a.py]
  planned_paths: [a.py]
  acceptance_criteria: [{id: AC1, description: new}]
  not_in_scope: []
  commit_contract: {required: true}
YAML
    cat > "$WORK_DIR/report_no_snapshot.yaml" <<'YAML'
worker_id: kotaro
parent_cmd: cmd_x
task_id: cmd_x_full
ac_version_read: old_ac_111
YAML
    cat > "$WORK_DIR/report_with_snapshot.yaml" <<'YAML'
worker_id: kotaro
parent_cmd: cmd_x
task_id: cmd_x_full
ac_version_read: old_ac_111
task_contract_snapshot:
  parent_cmd: cmd_x
  task_id: cmd_x_full
  ac_fingerprint: old_ac_111
  acceptance_criteria: [{id: AC1, description: old}]
YAML

    key() {
        SCRIPT_DIR="$PROJECT_ROOT" bash -c '
            source "$1"
            report_gate_generation_key "$2" "$3"
        ' _ "$WORK_DIR/rgk_fn.sh" "$1" "$2"
    }

    # Negative (legacy compatibility): no snapshot -> redeploy still changes
    # the key, exactly as before this fix.
    before_legacy="$(key "$WORK_DIR/report_no_snapshot.yaml" "$WORK_DIR/task_gen1.yaml")"
    after_legacy="$(key "$WORK_DIR/report_no_snapshot.yaml" "$WORK_DIR/task_gen2_redeployed.yaml")"
    [ -n "$before_legacy" ]
    [ "$before_legacy" != "$after_legacy" ]

    # Positive (the fix): a snapshot is present -> redeploying the task's
    # identity/AC fields the snapshot carries no longer changes the key.
    before_snapshot="$(key "$WORK_DIR/report_with_snapshot.yaml" "$WORK_DIR/task_gen1.yaml")"
    after_snapshot="$(key "$WORK_DIR/report_with_snapshot.yaml" "$WORK_DIR/task_gen2_redeployed.yaml")"
    [ -n "$before_snapshot" ]
    [ "$before_snapshot" = "$after_snapshot" ]

    # Negative (still correctness-preserving): an actual report content
    # change must still change the key even with a snapshot present.
    cp "$WORK_DIR/report_with_snapshot.yaml" "$WORK_DIR/report_with_snapshot_changed.yaml"
    printf 'extra_field: changed\n' >> "$WORK_DIR/report_with_snapshot_changed.yaml"
    changed="$(key "$WORK_DIR/report_with_snapshot_changed.yaml" "$WORK_DIR/task_gen1.yaml")"
    [ "$before_snapshot" != "$changed" ]
}

# test_necessity(cmd_karo_hotfix_contract_schema_20260907, karo 01:09): a real
# deployed report (it declares its own task_id) whose LIVE task file's
# task_id later reads empty (e.g. a stage timeout / idle reset nulled it)
# must not take the minimal-fixture compatibility skip in
# _autolink_terminal_test_receipt -- that let a real report reach
# status=completed with its receipt/commit checks silently unexecuted. It
# must resolve identity from the report's own frozen task_contract_snapshot,
# or fail closed when even that is absent. A genuine minimal fixture (no
# task_id anywhere) must keep the existing compatibility skip.
@test "report_field_set does not skip receipt validation for a real report when the live task_id is empty" {
    FIXTURE_ROOT="$WORK_DIR/identity_fixture_root"
    mkdir -p "$FIXTURE_ROOT/tasks_dir"

    # Live task file with task_id/parent_cmd nulled out (simulated stage
    # timeout / idle reset), matching karo's P07 observation.
    cat > "$FIXTURE_ROOT/tasks_dir/idleworker.yaml" <<'TASKYAML'
task:
  task_id: ""
  parent_cmd: ""
  project: infra
TASKYAML

    # Case A (fail closed): the report declares a real task_id but has no
    # task_contract_snapshot to recover identity from -> must BLOCK, not
    # silently finish terminal.
    cat > "$FIXTURE_ROOT/report_no_snapshot.yaml" <<'REPORTYAML'
worker_id: idleworker
task_id: cmd_z_full
parent_cmd: cmd_z
ac_version_read: dummyac01
status: in_progress
commit_contract: {required: true}
commit_hash: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
binary_checks:
  AC1:
  - check: dummy check
    result: 'yes'
files_modified:
  - path: queue/notes/dummy_fixture.md
lessons_useful: []
lesson_candidate:
  found: false
  no_lesson_reason: n/a
REPORTYAML
    run env RFS_TASK_FILE_PATH="$FIXTURE_ROOT/tasks_dir/idleworker.yaml" \
        REPORT_FIELD_SET_TASK_ROOT="$FIXTURE_ROOT" \
        bash "$PROJECT_ROOT/scripts/report_field_set.sh" --batch \
        "$FIXTURE_ROOT/report_no_snapshot.yaml" <<'EOF'
status: completed
EOF
    [ "$status" -ne 0 ]
    [[ "$output" == *"task identity unresolved"* ]]
    grep -q '^status: in_progress$' "$FIXTURE_ROOT/report_no_snapshot.yaml"

    # Case B (resolve from snapshot): same nulled live task, but the report
    # carries its own deploy-time snapshot with the real task_id -> identity
    # must resolve from the snapshot, not silently skip and not fail-closed
    # on identity. (It may still fail later on an unrelated field this
    # minimal fixture omits; the point under test is that it does not stop
    # at "task identity unresolved" nor silently accept the write.)
    cat > "$FIXTURE_ROOT/report_with_snapshot.yaml" <<'REPORTYAML'
worker_id: idleworker
task_id: cmd_z_full
parent_cmd: cmd_z
ac_version_read: dummyac01
status: in_progress
commit_contract: {required: true}
commit_hash: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
task_contract_snapshot:
  task_id: cmd_z_full
  parent_cmd: cmd_z
binary_checks:
  AC1:
  - check: dummy check
    result: 'yes'
files_modified:
  - path: queue/notes/dummy_fixture.md
lessons_useful: []
lesson_candidate:
  found: false
  no_lesson_reason: n/a
REPORTYAML
    run env RFS_TASK_FILE_PATH="$FIXTURE_ROOT/tasks_dir/idleworker.yaml" \
        REPORT_FIELD_SET_TASK_ROOT="$FIXTURE_ROOT" \
        bash "$PROJECT_ROOT/scripts/report_field_set.sh" --batch \
        "$FIXTURE_ROOT/report_with_snapshot.yaml" <<'EOF'
status: completed
EOF
    [[ "$output" != *"task identity unresolved"* ]]
    [[ "$output" != *"task_id mismatch"* ]]

    # Case C (legacy compatibility preserved): neither the live task nor the
    # report itself declares any task_id -> a genuine minimal fixture, keep
    # the existing compatibility skip (no BLOCK from this function at all).
    cat > "$FIXTURE_ROOT/report_minimal_fixture.yaml" <<'REPORTYAML'
worker_id: idleworker
status: in_progress
commit_contract: {required: false, reason: "fixture"}
commit_hash: no-code-change
binary_checks:
  AC1:
  - check: dummy check
    result: 'yes'
files_modified: []
lessons_useful: []
lesson_candidate:
  found: false
  no_lesson_reason: n/a
REPORTYAML
    run env RFS_TASK_FILE_PATH="$FIXTURE_ROOT/tasks_dir/idleworker.yaml" \
        REPORT_FIELD_SET_TASK_ROOT="$FIXTURE_ROOT" \
        bash "$PROJECT_ROOT/scripts/report_field_set.sh" --batch \
        "$FIXTURE_ROOT/report_minimal_fixture.yaml" <<'EOF'
status: completed
EOF
    [[ "$output" != *"task identity unresolved"* ]]
    [[ "$output" != *"terminal test receipt"* ]]
}

# test_necessity(cmd_karo_hotfix_contract_schema_20260907, karo 01:19/01:09): the
# completion gate's handle_empty_lessons_useful_check (scripts/cmd_complete_gate.sh)
# is the second half of the P07 lesson_safety_net bug: it judged an empty
# lessons_useful purely on the LIVE task's related_lessons, with no
# snapshot-authoritative escape hatch, so a report that correctly stayed
# faithful to an empty deploy-time lesson_set was CRITICAL-blocked once
# post-deploy injection later populated the live task. It must now consult
# the shared lesson-empty-allowed rule and only WARN when the snapshot
# genuinely permits empty; a report with no snapshot (or one that
# genuinely owed lessons) must keep the pre-existing CRITICAL BLOCK.
@test "cmd_complete_gate handle_empty_lessons_useful_check consults the snapshot before CRITICAL-blocking an empty report" {
    HELPERS_FILE="$WORK_DIR/gate_helpers.sh"
    python3 - "$PROJECT_ROOT/scripts/cmd_complete_gate.sh" > "$HELPERS_FILE" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
for name in ("record_block_reason", "is_lessons_useful_empty_warn_task_type", "handle_empty_lessons_useful_check"):
    match = re.search(rf"(?m)^{re.escape(name)}\(\) \{{.*?^\}}", source, re.DOTALL)
    if match is None:
        raise SystemExit(f"missing helper: {name}")
    print(match.group(0), end="\n\n")
PY
    [ -s "$HELPERS_FILE" ]

    cat > "$WORK_DIR/task_injected.yaml" <<'TASKYAML'
task:
  task_id: cmd_p07_full
  parent_cmd: cmd_p07
  task_type: hotfix
  related_lessons:
  - id: L097
  - id: L019
TASKYAML
    cat > "$WORK_DIR/report_empty_with_snapshot.yaml" <<'REPORTYAML'
worker_id: kotaro
parent_cmd: cmd_p07
task_id: cmd_p07_full
task_contract_snapshot:
  parent_cmd: cmd_p07
  task_id: cmd_p07_full
  lesson_set:
    mode: subset
    ids: []
lessons_useful: []
REPORTYAML
    cat > "$WORK_DIR/report_empty_no_snapshot.yaml" <<'REPORTYAML'
worker_id: kotaro
parent_cmd: cmd_p07
task_id: cmd_p07_full
lessons_useful: []
REPORTYAML

    # Positive (the fix): snapshot legitimately permits empty -> WARN, not
    # CRITICAL; ALL_CLEAR stays true; no block reason recorded.
    run bash -c '
        source "$1"
        SCRIPT_DIR="$2"
        ALL_CLEAR=true
        BLOCK_REASONS=()
        handle_empty_lessons_useful_check "kotaro" "hotfix" "L097,L019" "$3" "$4"
        echo "ALL_CLEAR=$ALL_CLEAR"
        echo "BLOCK_REASONS_COUNT=${#BLOCK_REASONS[@]}"
    ' _ "$HELPERS_FILE" "$PROJECT_ROOT" "$WORK_DIR/task_injected.yaml" "$WORK_DIR/report_empty_with_snapshot.yaml"
    [[ "$output" == *"[WARN]"* ]]
    [[ "$output" != *"[CRITICAL]"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
    [[ "$output" == *"BLOCK_REASONS_COUNT=0"* ]]

    # Negative (preserve correctness): the report has no snapshot at all, so
    # there is nothing establishing that empty was ever allowed -> keep the
    # existing CRITICAL BLOCK behavior unchanged.
    run bash -c '
        source "$1"
        SCRIPT_DIR="$2"
        ALL_CLEAR=true
        BLOCK_REASONS=()
        handle_empty_lessons_useful_check "kotaro" "hotfix" "L097,L019" "$3" "$4"
        echo "ALL_CLEAR=$ALL_CLEAR"
        echo "BLOCK_REASONS_COUNT=${#BLOCK_REASONS[@]}"
    ' _ "$HELPERS_FILE" "$PROJECT_ROOT" "$WORK_DIR/task_injected.yaml" "$WORK_DIR/report_empty_no_snapshot.yaml"
    [[ "$output" == *"[CRITICAL]"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
    [[ "$output" == *"BLOCK_REASONS_COUNT=1"* ]]

    # Negative (backward compatibility): calling with the original 3-arg
    # form (no task_file/report_file) must behave exactly as before -
    # CRITICAL BLOCK for a non-exempt task_type.
    run bash -c '
        source "$1"
        ALL_CLEAR=true
        BLOCK_REASONS=()
        handle_empty_lessons_useful_check "sasuke" "exact" "L001,L002"
        echo "ALL_CLEAR=$ALL_CLEAR"
    ' _ "$HELPERS_FILE"
    [[ "$output" == *"[CRITICAL]"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
}
