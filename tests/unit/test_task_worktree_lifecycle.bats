#!/usr/bin/env bats

# test_necessity: source tasks must edit, commit, publish, and clean from a
# remote-tip linked worktree while shared main and runtime state stay isolated.

setup_fixture_repo() {
    FIXTURE="$BATS_TEST_TMPDIR/repo"
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
