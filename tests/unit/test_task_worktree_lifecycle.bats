#!/usr/bin/env bats

# test_necessity: source tasks must edit, commit, publish, and clean from a
# remote-tip linked worktree while shared main and runtime state stay isolated.

setup_fixture_repo() {
    FIXTURE="${1:-$BATS_TEST_TMPDIR/repo}"
    git init --bare -q "$FIXTURE/remote.git"
    git clone -q "$FIXTURE/remote.git" "$FIXTURE/shared"
    git -C "$FIXTURE/shared" config user.email test@example.invalid
    git -C "$FIXTURE/shared" config user.name fixture
    git -C "$FIXTURE/shared" switch -c main -q
    mkdir -p "$FIXTURE/shared/src" "$FIXTURE/shared/queue" "$FIXTURE/shared/logs" \
        "$FIXTURE/shared/context" "$FIXTURE/shared/docs/semantic-index"
    printf 'BASE=1\n' > "$FIXTURE/shared/src/app.py"
    printf 'runtime: base\n' > "$FIXTURE/shared/queue/runtime.yaml"
    printf 'baseline\n' > "$FIXTURE/shared/logs/defense_overhead.jsonl"
    printf 'semantic baseline\n' > "$FIXTURE/shared/context/semantic-map.md"
    printf 'index baseline\n' > "$FIXTURE/shared/docs/semantic-index/index.md"
    printf 'queue/gates/\n.cache/\nlogs/test_receipts/\n' > "$FIXTURE/shared/.gitignore"
    git -C "$FIXTURE/shared" add src/app.py queue/runtime.yaml logs/defense_overhead.jsonl \
        context/semantic-map.md docs/semantic-index/index.md .gitignore
    git -C "$FIXTURE/shared" commit -q -m base
    git -C "$FIXTURE/shared" push -q -u origin main
}

# test_necessity: archive cleanup must recover a publication that is durable in
# the exact generation-bound source receipt even when the task marker still has
# published_commit empty; mismatched identity or an unresolved tip must remain
# fail-closed and retain the worktree.
setup_receipt_recovery_fixture() {
    local case_name="$1" receipt_mode="$2"
    local generation="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    local receipt_generation="$generation" receipt_repo_mode="match" receipt_tip_mode="match"
    FIXTURE="$BATS_TEST_TMPDIR/receipt-$case_name"
    CMD="cmd_receipt_recovery_$case_name"
    setup_fixture_repo "$FIXTURE"
    git -C "$FIXTURE/shared" worktree add -q -b "task-$case_name" "$FIXTURE/task-wt" HEAD
    printf 'RECOVERED=1\n' > "$FIXTURE/task-wt/src/app.py"
    git -C "$FIXTURE/task-wt" add src/app.py
    git -C "$FIXTURE/task-wt" commit -q -m "receipt recovery $case_name"
    PUB="$(git -C "$FIXTURE/task-wt" rev-parse HEAD)"
    git -C "$FIXTURE/task-wt" push -q origin HEAD:refs/heads/main
    case "$receipt_mode" in
        generation) receipt_generation="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" ;;
        repo) receipt_repo_mode="mismatch" ;;
        tip) receipt_tip_mode="unresolved" ;;
        success) ;;
        *) printf 'unknown receipt mode: %s\n' "$receipt_mode" >&2; return 1 ;;
    esac
    mkdir -p "$FIXTURE/queue/gates/$CMD"
    python3 - "$FIXTURE/queue/gates/$CMD/task_worktree.json" "$FIXTURE/shared" "$FIXTURE/task-wt" "$CMD" "$PUB" <<'PY'
import json
import sys

marker, repo, worktree, cmd, remote_tip = sys.argv[1:]
json.dump({
    "version": 1,
    "parent_cmd": cmd,
    "repo": repo,
    "worktree": worktree,
    "state": "active",
    "published_commit": "",
    "remote_tip": remote_tip,
}, open(marker, "w"))
PY
    python3 - "$FIXTURE/queue/gates/$CMD/gate_worker.clear.json" "$CMD" "$generation" <<'PY'
import json
import sys

path, cmd, generation = sys.argv[1:]
json.dump({
    "version": 1,
    "state": "clear",
    "cmd_id": cmd,
    "completion_generation": generation,
    "persisted_at_ns": 1,
}, open(path, "w"))
PY
    local receipt_repo="$FIXTURE/shared" receipt_tip="$PUB"
    [ "$receipt_repo_mode" = "match" ] || receipt_repo="$FIXTURE/other-repo"
    [ "$receipt_tip_mode" = "match" ] || receipt_tip="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
    python3 - "$FIXTURE/queue/gates/$CMD/source_only_publish.receipt.json" "$CMD" "$receipt_generation" "$receipt_repo" "$receipt_tip" "$PUB" <<'PY'
import json
import sys

path, cmd, generation, repo, remote_tip, source_sha = sys.argv[1:]
json.dump({
    "version": 1,
    "state": "published",
    "cmd_id": cmd,
    "completion_generation": generation,
    "entries": [{
        "cmd_id": cmd,
        "completion_generation": generation,
        "repo": repo,
        "source_sha": source_sha,
        "report_generation": "rpt-receipt-recovery",
        "remote_tip": remote_tip,
        "remote_contains_source_rc": 0,
    }],
}, open(path, "w"))
PY
    GEN="$generation"
    WT="$FIXTURE/task-wt"
}

run_receipt_recovery_archive() {
    run env ARCHIVE_COMPLETED_PROJECT_DIR="$FIXTURE" \
        ARCHIVE_TASK_WORKTREE_CLEANUP_ONLY=1 \
        ARCHIVE_REQUIRE_CLEAR_RECEIPT=1 \
        SHOGUN_COMPLETION_GENERATION="$GEN" \
        bash "$BATS_TEST_DIRNAME/../../scripts/archive_completed.sh" 3 "$CMD"
}

@test "remote-tip deploy exposes absolute edit target and rejects shared source" {
    setup_fixture_repo
    task="$BATS_TEST_TMPDIR/task.yaml"
    printf 'task:\n  task_id: task_fixture\n  parent_cmd: cmd_fixture\n  project: infra\n  target_path: src/app.py\n  status: assigned\n' > "$task"
    run env PROJECT_ROOT="$BATS_TEST_DIRNAME/../.." FIXTURE="$FIXTURE/shared" TASK="$task" bash -c '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/deploy_task.sh"
        SCRIPT_DIR="$FIXTURE"; LOG=/dev/null; STATE_DIR="$FIXTURE/state"; mkdir -p "$STATE_DIR"
        deploy_task_prepare_remote_tip_worktree "$TASK" saizo
        wt=$(FIELD_GET_NO_LOG=1 field_get "$TASK" task_worktree_path)
        target=$(python3 - "$TASK" <<'PY'
import json,sys,yaml
task=yaml.safe_load(open(sys.argv[1],encoding="utf-8"))["task"]
print(json.loads(task["task_worktree_target_paths"])[0])
PY
        )
        test "$target" = "$wt/src/app.py"
        printf SHARED_EDIT=1 > "$FIXTURE/src/app.py"
        shared_rc=0
        env NINJA_SCOPE_TASK_FILE="$TASK" bash "$PROJECT_ROOT/scripts/ninja_scope_commit.sh" -m reject -- src/app.py >/dev/null 2>&1 || shared_rc=$?
        [ "$shared_rc" -ne 0 ]
        git -C "$FIXTURE" show HEAD:src/app.py > "$FIXTURE/src/app.py"
        printf WORKTREE_EDIT=1 > "$target"
        [ -z "$(git -C "$FIXTURE" status --porcelain -- src/app.py)" ]
        env NINJA_SCOPE_TASK_FILE="$TASK" bash "$PROJECT_ROOT/scripts/ninja_scope_commit.sh" -m publish -- "$target" >/dev/null
        [ -z "$(git -C "$wt" status --porcelain)" ]
        mkdir -p "$wt/.cache" "$wt/logs/test_receipts"
        printf cache > "$wt/.cache/probe.bin"
        printf receipt > "$wt/logs/test_receipts/probe.tap"
        echo runtime-event >> "$wt/logs/defense_overhead.jsonl"
        echo semantic-event >> "$wt/context/semantic-map.md"
        echo index-event >> "$wt/docs/semantic-index/index.md"
        marker=$(FIELD_GET_NO_LOG=1 field_get "$TASK" task_worktree_marker); published=$(git -C "$wt" rev-parse HEAD)
        python3 - "$marker" "$published" <<PY
import json,sys
p,pub=sys.argv[1:]; d=json.load(open(p)); d["published_commit"]=pub; json.dump(d,open(p,"w"))
PY
        parent=$(FIELD_GET_NO_LOG=1 field_get "$TASK" parent_cmd); mkdir -p "$FIXTURE/queue/gates/$parent"
        python3 - "$FIXTURE/queue/gates/$parent/gate_worker.clear.json" "$parent" <<PY
import json,sys
with open(sys.argv[1],"w") as f: json.dump({"version":1,"state":"clear","cmd_id":sys.argv[2],"completion_generation":"a"*64,"persisted_at_ns":1},f)
PY
        shared_log_before=$(sha256sum "$FIXTURE/logs/defense_overhead.jsonl" | awk "{print \$1}")
        shared_semantic_before=$(sha256sum "$FIXTURE/context/semantic-map.md" | awk "{print \$1}")
        shared_index_before=$(sha256sum "$FIXTURE/docs/semantic-index/index.md" | awk "{print \$1}")
        ARCHIVE_COMPLETED_PROJECT_DIR="$FIXTURE" ARCHIVE_TASK_WORKTREE_CLEANUP_ONLY=1 ARCHIVE_REQUIRE_CLEAR_RECEIPT=1 SHOGUN_COMPLETION_GENERATION="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" bash "$PROJECT_ROOT/scripts/archive_completed.sh" 3 "$parent" >/dev/null
        [ "$(git -C "$FIXTURE" worktree list --porcelain | grep -F "$wt" | wc -l)" -eq 0 ]
        [ "$(cat "$FIXTURE/queue/archive/task-worktree-artifacts/$parent/.cache/probe.bin")" = cache ]
        [ "$(cat "$FIXTURE/queue/archive/task-worktree-artifacts/$parent/logs/test_receipts/probe.tap")" = receipt ]
        grep -qx runtime-event "$FIXTURE/queue/archive/task-worktree-artifacts/$parent/tracked/logs/defense_overhead.jsonl"
        grep -qx semantic-event "$FIXTURE/queue/archive/task-worktree-artifacts/$parent/tracked/context/semantic-map.md"
        grep -qx index-event "$FIXTURE/queue/archive/task-worktree-artifacts/$parent/tracked/docs/semantic-index/index.md"
        [ "$(sha256sum "$FIXTURE/logs/defense_overhead.jsonl" | awk "{print \$1}")" = "$shared_log_before" ]
        [ "$(sha256sum "$FIXTURE/context/semantic-map.md" | awk "{print \$1}")" = "$shared_semantic_before" ]
        [ "$(sha256sum "$FIXTURE/docs/semantic-index/index.md" | awk "{print \$1}")" = "$shared_index_before" ]
        echo "absolute_target=1 shared_edit_block=1 scope_commit=1 ignored_preserved=2 tracked_preserved=3 cleanup_orphan=0"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"absolute_target=1 shared_edit_block=1 scope_commit=1 ignored_preserved=2 tracked_preserved=3 cleanup_orphan=0"* ]]
}

# test_necessity: task worktrees must survive host restart by default on the
# persistent ext4 home volume while preserving the explicit environment-root
# compatibility contract for isolated callers and existing deployments.
@test "task worktree default uses persistent home root and honors explicit root" {
    setup_fixture_repo
    task_default="$BATS_TEST_TMPDIR/task-default-root.yaml"
    printf 'task:\n  task_id: task_default_root\n  parent_cmd: cmd_default_root\n  project: infra\n  target_path: src/app.py\n  status: assigned\n' > "$task_default"

    run env PROJECT_ROOT="$BATS_TEST_DIRNAME/../.." FIXTURE="$FIXTURE/shared" TASK="$task_default" bash -c '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        unset DEPLOY_TASK_WORKTREE_ROOT
        source "$PROJECT_ROOT/scripts/deploy_task.sh"
        SCRIPT_DIR="$FIXTURE"; LOG=/dev/null; STATE_DIR="$FIXTURE/state"; mkdir -p "$STATE_DIR"
        deploy_task_prepare_remote_tip_worktree "$TASK" kagemaru
        wt=$(FIELD_GET_NO_LOG=1 field_get "$TASK" task_worktree_path)
        case "$wt" in
            /home/simokitafresh/shogun-task-worktrees/*) ;;
            *) printf "unexpected_default_root=%s\n" "$wt" >&2; exit 1 ;;
        esac
        test -d /home/simokitafresh/shogun-task-worktrees
        test -d "$wt"
        deploy_task_rollback_remote_tip_worktree "$FIXTURE" "$wt" "$(FIELD_GET_NO_LOG=1 field_get "$TASK" task_worktree_marker)"
        test ! -e "$wt"
        echo "default_root=home_ext4 created=1 cleanup=1"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"default_root=home_ext4 created=1 cleanup=1"* ]]

    task_explicit="$BATS_TEST_TMPDIR/task-explicit-root.yaml"
    explicit_root="$BATS_TEST_TMPDIR/explicit-tmp-root"
    printf 'task:\n  task_id: task_explicit_root\n  parent_cmd: cmd_explicit_root\n  project: infra\n  target_path: src/app.py\n  status: assigned\n' > "$task_explicit"

    run env PROJECT_ROOT="$BATS_TEST_DIRNAME/../.." FIXTURE="$FIXTURE/shared" TASK="$task_explicit" \
        DEPLOY_TASK_WORKTREE_ROOT="$explicit_root" bash -c '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/deploy_task.sh"
        SCRIPT_DIR="$FIXTURE"; LOG=/dev/null; STATE_DIR="$FIXTURE/state"; mkdir -p "$STATE_DIR"
        deploy_task_prepare_remote_tip_worktree "$TASK" kagemaru
        wt=$(FIELD_GET_NO_LOG=1 field_get "$TASK" task_worktree_path)
        case "$wt" in
            "$DEPLOY_TASK_WORKTREE_ROOT"/*) ;;
            *) printf "unexpected_explicit_root=%s\n" "$wt" >&2; exit 1 ;;
        esac
        test -d "$DEPLOY_TASK_WORKTREE_ROOT"
        test -d "$wt"
        deploy_task_rollback_remote_tip_worktree "$FIXTURE" "$wt" "$(FIELD_GET_NO_LOG=1 field_get "$TASK" task_worktree_marker)"
        test ! -e "$wt"
        echo "explicit_root=env_tmp created=1 cleanup=1"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"explicit_root=env_tmp created=1 cleanup=1"* ]]
}

@test "two sequential source tasks push remote tip with zero drift" {
    setup_fixture_repo
    task1="$BATS_TEST_TMPDIR/task1.yaml"; task2="$BATS_TEST_TMPDIR/task2.yaml"
    printf 'task:\n  task_id: task_one\n  parent_cmd: cmd_one\n  project: infra\n  target_path: src/app.py\n  status: assigned\n' > "$task1"
    printf 'task:\n  task_id: task_two\n  parent_cmd: cmd_two\n  project: infra\n  target_path: src/app.py\n  status: assigned\n' > "$task2"
    run env PROJECT_ROOT="$BATS_TEST_DIRNAME/../.." FIXTURE="$FIXTURE/shared" TASK1="$task1" TASK2="$task2" bash -c '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/deploy_task.sh"
        SCRIPT_DIR="$FIXTURE"; LOG=/dev/null; STATE_DIR="$FIXTURE/state"; mkdir -p "$STATE_DIR"
        shared_head=$(git -C "$FIXTURE" rev-parse HEAD)
        for task in "$TASK1" "$TASK2"; do
            deploy_task_prepare_remote_tip_worktree "$task" saizo
            wt=$(FIELD_GET_NO_LOG=1 field_get "$task" task_worktree_path)
            target=$(python3 - "$task" <<'PY'
import json,sys,yaml
task=yaml.safe_load(open(sys.argv[1],encoding="utf-8"))["task"]
print(json.loads(task["task_worktree_target_paths"])[0])
PY
            )
            printf SOURCE=1 > "$target"
            env NINJA_SCOPE_TASK_FILE="$task" bash "$PROJECT_ROOT/scripts/ninja_scope_commit.sh" -m publish -- "$target" >/dev/null
            git -C "$wt" push -q origin HEAD:refs/heads/main; git -C "$wt" fetch -q origin main
            read -r remote_only local_only < <(git -C "$wt" rev-list --left-right --count origin/main...HEAD)
            [ "$remote_only" -eq 0 ] && [ "$local_only" -eq 0 ]
            [ -z "$(git -C "$wt" status --porcelain)" ]
            [ -z "$(git -C "$FIXTURE" status --porcelain -- src/app.py)" ]
            [ "$(git -C "$FIXTURE" rev-parse HEAD)" = "$shared_head" ]
            git -C "$wt" ls-tree -r --name-only HEAD | grep -qx queue/runtime.yaml
            [ -z "$(git -C "$wt" ls-tree -r --name-only HEAD | grep '^queue/' | grep -v '^queue/runtime.yaml$' || true)" ]
            marker=$(FIELD_GET_NO_LOG=1 field_get "$task" task_worktree_marker); pub=$(git -C "$wt" rev-parse HEAD)
            python3 - "$marker" "$pub" <<PY
import json,sys
p,pub=sys.argv[1:]; d=json.load(open(p)); d["published_commit"]=pub; json.dump(d,open(p,"w"))
PY
            parent=$(FIELD_GET_NO_LOG=1 field_get "$task" parent_cmd); mkdir -p "$FIXTURE/queue/gates/$parent"
            python3 - "$FIXTURE/queue/gates/$parent/gate_worker.clear.json" "$parent" <<PY
import json,sys
with open(sys.argv[1],"w") as f: json.dump({"version":1,"state":"clear","cmd_id":sys.argv[2],"completion_generation":"a"*64,"persisted_at_ns":1},f)
PY
            ARCHIVE_COMPLETED_PROJECT_DIR="$FIXTURE" ARCHIVE_TASK_WORKTREE_CLEANUP_ONLY=1 ARCHIVE_REQUIRE_CLEAR_RECEIPT=1 SHOGUN_COMPLETION_GENERATION="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" bash "$PROJECT_ROOT/scripts/archive_completed.sh" 3 "$parent" >/dev/null
        done
        echo "two_tasks=2 remote_local=0/0 shared_head_unchanged=1 worktree_dirty=0 runtime_mixed=0 orphan=0 auto_gc=0 hard_reset=0"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"two_tasks=2 remote_local=0/0 shared_head_unchanged=1 worktree_dirty=0 runtime_mixed=0 orphan=0 auto_gc=0 hard_reset=0"* ]]
}

@test "YAML publish failure rolls back worktree and marker" {
    setup_fixture_repo
    task="$BATS_TEST_TMPDIR/task.yaml"
    printf 'task:\n  task_id: task_fail\n  parent_cmd: cmd_fail\n  project: infra\n  target_path: src/app.py\n  status: assigned\n' > "$task"
    run env PROJECT_ROOT="$BATS_TEST_DIRNAME/../.." FIXTURE="$FIXTURE/shared" TASK="$task" bash -c '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1 DEPLOY_TASK_TEST_FAIL_WORKTREE_YAML_PUBLISH=1
        source "$PROJECT_ROOT/scripts/deploy_task.sh"; SCRIPT_DIR="$FIXTURE"; LOG=/dev/null
        if deploy_task_prepare_remote_tip_worktree "$TASK" saizo; then exit 9; fi
        [ "$(git -C "$FIXTURE" worktree list --porcelain | grep -c shogun-task-worktrees)" -eq 0 ]
        [ ! -e "$FIXTURE/queue/gates/cmd_fail/task_worktree.json" ]
        echo "publish_failure=1 rollback_orphan=0 marker_removed=1"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"publish_failure=1 rollback_orphan=0 marker_removed=1"* ]]
}

@test "archive recovers exact source publication receipt and rejects three mismatches" {
    setup_receipt_recovery_fixture success success
    run_receipt_recovery_archive
    [ "$status" -eq 0 ]
    [[ "$output" == *"publication recovered from durable receipt"* ]]
    [ ! -e "$WT" ]
    python3 - "$FIXTURE/queue/gates/$CMD/task_worktree.json" "$PUB" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["state"] == "cleaned"
assert data["published_commit"] == sys.argv[2]
assert int(data["published_recovered_at_ns"]) > 0
PY

    false_positive=0
    false_negative=0
    for mode in generation repo tip; do
        setup_receipt_recovery_fixture "$mode" "$mode"
        run_receipt_recovery_archive
        [ "$status" -ne 0 ] || false_positive=$((false_positive + 1))
        [ -d "$WT" ] || false_negative=$((false_negative + 1))
        published="$(python3 - "$FIXTURE/queue/gates/$CMD/task_worktree.json" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8")).get("published_commit") or "")
PY
        )"
        [ -z "$published" ] || false_positive=$((false_positive + 1))
    done
    printf 'receipt_recovery success=1 generation_mismatch=1 repo_mismatch=1 unresolved_tip=1 false_positive=%s false_negative=%s\n' \
        "$false_positive" "$false_negative"
    [ "$false_positive" -eq 0 ]
    [ "$false_negative" -eq 0 ]
}

@test "multi-path remote-tip deploy preserves typed scope and resolves task selectors" {
    setup_fixture_repo
    mkdir -p "$FIXTURE/shared/tests/unit"
    printf 'BASE=2\n' > "$FIXTURE/shared/src/other.py"
    printf '#!/usr/bin/env bats\n@test "fixture contract" { true; }\n' > "$FIXTURE/shared/tests/unit/contract.bats"
    git -C "$FIXTURE/shared" add src/other.py tests/unit/contract.bats
    git -C "$FIXTURE/shared" commit -q -m fixture-contract
    git -C "$FIXTURE/shared" push -q origin main

    task="$BATS_TEST_TMPDIR/task-multi.yaml"
    cat > "$task" <<'YAML'
task:
  task_id: task_multi
  parent_cmd: cmd_multi
  project: infra
  task_worktree_required: true
  target_path:
    - src/app.py
    - src/other.py
  planned_paths:
    - src/app.py
    - src/other.py
    - tests/unit/contract.bats
  inspection_path: src/app.py
  commit_contract:
    required: true
    planned_paths:
      - src/app.py
      - src/other.py
      - tests/unit/contract.bats
  status: assigned
YAML

    run env PROJECT_ROOT="$BATS_TEST_DIRNAME/../.." FIXTURE="$FIXTURE/shared" TASK="$task" bash -c '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/deploy_task.sh"
        SCRIPT_DIR="$FIXTURE"; LOG=/dev/null
        deploy_task_prepare_remote_tip_worktree "$TASK" tobisaru
        wt=$(FIELD_GET_NO_LOG=1 field_get "$TASK" task_worktree_path)
        python3 - "$TASK" "$wt" <<'PY'
import json
import sys
import yaml

task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {})["task"]
wt = sys.argv[2]
assert task["target_path"] == ["src/app.py", "src/other.py"], task["target_path"]
assert task["planned_paths"] == ["src/app.py", "src/other.py", "tests/unit/contract.bats"], task["planned_paths"]
assert task["inspection_path"] == "src/app.py", task["inspection_path"]
target_paths = json.loads(task["task_worktree_target_paths"])
assert target_paths == [
    f"{wt}/src/app.py", f"{wt}/src/other.py", f"{wt}/tests/unit/contract.bats"
], target_paths
PY
        export REPO_ROOT="$PROJECT_ROOT"
        # Source the canonical function definitions structurally; fixed line
        # slices break when run_tests.sh grows or refactors its dispatch code.
        source "$PROJECT_ROOT/scripts/run_tests.sh"
        scope_rc=0
        scope=$(task_scope_paths "$TASK" | tr "\\0" "\\n") || scope_rc=$?
        [ "$scope_rc" -eq 0 ]
        [[ "$scope" == *"src/app.py"* ]]
        [[ "$scope" == *"src/other.py"* ]]
        [[ "$scope" == *"tests/unit/contract.bats"* ]]
        explicit_rc=0
        explicit=$(task_explicit_test_paths "$TASK" | tr "\\0" "\\n") || explicit_rc=$?
        [ "$explicit_rc" -eq 0 ]
        [[ "$explicit" == "tests/unit/contract.bats" ]]
        deploy_task_rollback_remote_tip_worktree "$FIXTURE" "$wt" "$(FIELD_GET_NO_LOG=1 field_get "$TASK" task_worktree_marker)"
        echo "target_type=list planned_type=list inspection_type=scalar projected_once=3 selector=resolved"
    '
    if [ "$status" -ne 0 ]; then
        printf '%s\n' "$output" >&3
    fi
    [ "$status" -eq 0 ]
    [[ "$output" == *"target_type=list planned_type=list inspection_type=scalar projected_once=3 selector=resolved"* ]]
}

@test "remote-tip projection removes only explicit relative prefix and preserves dot paths" {
    setup_fixture_repo
    mkdir -p "$FIXTURE/shared/.githooks" "$FIXTURE/shared/.codex" "$FIXTURE/shared/...dots"
    printf 'hook\n' > "$FIXTURE/shared/.githooks/pre-push"
    printf '{}\n' > "$FIXTURE/shared/.codex/hooks.json"
    printf 'ordinary\n' > "$FIXTURE/shared/src/ordinary.py"
    printf 'dots\n' > "$FIXTURE/shared/...dots/probe"
    git -C "$FIXTURE/shared" add .githooks/pre-push .codex/hooks.json src/ordinary.py ...dots/probe
    git -C "$FIXTURE/shared" commit -q -m fixture-dot-paths
    git -C "$FIXTURE/shared" push -q origin main

    task="$BATS_TEST_TMPDIR/task-dot-paths.yaml"
    cat > "$task" <<'YAML'
task:
  task_id: task_dot_paths
  parent_cmd: cmd_dot_paths
  project: infra
  task_worktree_required: true
  target_path:
    - .githooks/pre-push
    - ./.codex/hooks.json
    - src/ordinary.py
    - ...dots/probe
  status: assigned
YAML

    run env PROJECT_ROOT="$BATS_TEST_DIRNAME/../.." FIXTURE="$FIXTURE/shared" TASK="$task" bash -c '
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/deploy_task.sh"
        SCRIPT_DIR="$FIXTURE"; LOG=/dev/null
        deploy_task_prepare_remote_tip_worktree "$TASK" saizo
        wt=$(FIELD_GET_NO_LOG=1 field_get "$TASK" task_worktree_path)
        python3 - "$TASK" "$wt" <<'PY'
import json
import sys
import yaml

task = (yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {})["task"]
wt = sys.argv[2]
expected_source = [
    ".githooks/pre-push",
    "./.codex/hooks.json",
    "src/ordinary.py",
    "...dots/probe",
]
expected = [
    f"{wt}/.githooks/pre-push",
    f"{wt}/.codex/hooks.json",
    f"{wt}/src/ordinary.py",
    f"{wt}/...dots/probe",
]
assert task["target_path"] == expected_source, task["target_path"]
assert json.loads(task["task_worktree_target_paths"]) == expected
assert all(path.startswith(wt + "/") for path in expected)
assert all(__import__("os").path.isfile(path) for path in expected)
PY
        deploy_task_rollback_remote_tip_worktree "$FIXTURE" "$wt" "$(FIELD_GET_NO_LOG=1 field_get "$TASK" task_worktree_marker)"
        echo "dotpath=preserved explicit_relative_prefix=removed normal=preserved adversarial_dots=preserved"
    '
    if [ "$status" -ne 0 ]; then
        printf '%s\n' "$output" >&3
    fi
    [ "$status" -eq 0 ]
    [[ "$output" == *"dotpath=preserved explicit_relative_prefix=removed normal=preserved adversarial_dots=preserved"* ]]
}
