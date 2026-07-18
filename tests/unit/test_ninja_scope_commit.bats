#!/usr/bin/env bats

setup() {
    REPO="$(mktemp -d "$BATS_TMPDIR/ninja_scope_commit.XXXXXX")"
    git -C "$REPO" init -q
    git -C "$REPO" config user.email test@example.com
    git -C "$REPO" config user.name test
    printf 'base\n' > "$REPO/own.txt"
    printf 'base\n' > "$REPO/other.txt"
    git -C "$REPO" add own.txt other.txt
    git -C "$REPO" commit -qm initial
    HELPER="$BATS_TEST_DIRNAME/../../scripts/ninja_scope_commit.sh"
    # ninja_scope_commit.sh unconditionally sources scripts/lib/scope_path.sh
    # (SSOT for scope path normalization); every sandbox repo needs a copy.
    mkdir -p "$REPO/scripts/lib"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/scope_path.sh" "$REPO/scripts/lib/scope_path.sh"
}

@test "explicit ignored new scope is committed without force-staging ignored files outside scope" {
    printf '*\n' > "$REPO/.gitignore"
    git -C "$REPO" add -f .gitignore
    git -C "$REPO" commit -qm ignore-all
    printf owned > "$REPO/owned.txt"
    printf foreign > "$REPO/foreign.txt"

    run bash -c 'cd "$1" && exec bash "$2" -m "ignored owned" -- owned.txt' _ "$REPO" "$HELPER"

    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" show --format= --name-only HEAD)" = "owned.txt" ]
    [ "$(git -C "$REPO" show HEAD:owned.txt)" = owned ]
    ! git -C "$REPO" ls-tree -r --name-only HEAD | grep -qx foreign.txt
    git -C "$REPO" check-ignore -q foreign.txt
}

teardown() {
    rm -rf "$REPO"
}

make_ga282_fixture() {
    mkdir -p "$REPO/queue/tasks" "$REPO/projects/infra"
    printf 'task: base\n' > "$REPO/queue/tasks/hayate.yaml"
    printf 'lesson: base\n' > "$REPO/projects/infra/lessons_gunshi.yaml"
    printf 'lesson2: base\n' > "$REPO/projects/infra/lessons_karo.yaml"
    git -C "$REPO" add queue/tasks/hayate.yaml projects/infra/lessons_gunshi.yaml projects/infra/lessons_karo.yaml
    git -C "$REPO" commit -qm ga282-base
}

install_ga282_boundary_hook() {
    mkdir -p "$REPO/.git/hooks"
    cat > "$REPO/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
mapfile -t staged < <(git diff --cached --name-only)
printf '%s\n' "${staged[@]}" > .git/ga282-hook-seen
has_task=false
has_impl=false
for path in "${staged[@]}"; do
    [[ "$path" == queue/tasks/*.yaml ]] && has_task=true
    [[ "$path" == projects/* || "$path" == scripts/* || "$path" == tests/* || "$path" == context/* ]] && has_impl=true
done
if [[ "$has_task" == true && "$has_impl" == true ]]; then
    echo 'BLOCKED: queue/tasks/*.yaml cannot be committed with implementation files (GA-408)' >&2
    exit 1
fi
HOOK
    chmod +x "$REPO/.git/hooks/pre-commit"
}

@test "修正前: 通常commitは事前stage済み他者fileも含め2件commitする" {
    printf 'other change\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    printf 'own change\n' >> "$REPO/own.txt"
    git -C "$REPO" add own.txt

    git -C "$REPO" commit -qm unsafe

    run git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 2 ]
}

@test "ambient merge state is blocked before scoped commit and HEAD remains unchanged" {
    git -C "$REPO" checkout -qb side
    printf 'side\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    git -C "$REPO" commit -qm side
    git -C "$REPO" checkout -q master
    printf 'main\n' >> "$REPO/own.txt"
    git -C "$REPO" add own.txt
    git -C "$REPO" commit -qm main
    git -C "$REPO" merge --no-commit --no-ff side
    head_before="$(git -C "$REPO" rev-parse HEAD)"
    printf 'scoped\n' >> "$REPO/own.txt"

    run bash -c 'cd "$1" && bash "$2" -m must-block-merge -- own.txt' _ "$REPO" "$HELPER"

    [ "$status" -eq 2 ]
    [[ "$output" == *"repository operation state is active: MERGE_HEAD"* ]]
    [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
    [ "$(git -C "$REPO" rev-parse -q --verify MERGE_HEAD)" != "" ]
}

@test "cherry-pick and rebase ambient states are fail-closed without false success" {
    head_before="$(git -C "$REPO" rev-parse HEAD)"
    printf 'scoped\n' >> "$REPO/own.txt"
    for state in CHERRY_PICK_HEAD rebase-merge rebase-apply; do
        state_path="$(git -C "$REPO" rev-parse --git-path "$state")"
        [[ "$state_path" = /* ]] || state_path="$REPO/$state_path"
        if [[ "$state" == rebase-* ]]; then
            mkdir -p "$state_path"
        else
            printf '%s\n' "$head_before" > "$state_path"
        fi
        run bash -c 'cd "$1" && bash "$2" -m must-block-operation -- own.txt' _ "$REPO" "$HELPER"
        [ "$status" -eq 2 ]
        [[ "$output" == *"repository operation state is active: $state"* ]]
        [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
        if [[ "$state" == rebase-* ]]; then
            rmdir "$state_path"
        else
            rm -f "$state_path"
        fi
    done
}

@test "normal scoped commit has exactly the captured HEAD as its sole parent" {
    parent="$(git -C "$REPO" rev-parse HEAD)"
    printf 'single-parent\n' >> "$REPO/own.txt"

    run bash -c 'cd "$1" && bash "$2" -m single-parent -- own.txt 2>single-parent.err' _ "$REPO" "$HELPER"

    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" show -s --format=%P "$output")" = "$parent" ]
    [ "$(git -C "$REPO" show -s --format=%P "$output" | wc -w)" -eq 1 ]
}

@test "scoped commit publishes through commit-tree and update-ref without git commit porcelain" {
    printf 'bounded publication\n' >> "$REPO/own.txt"
    trace="$REPO/trace.json"

    run bash -c 'cd "$1" && GIT_TRACE2_EVENT="$3" bash "$2" -m bounded-publish -- own.txt' _ "$REPO" "$HELPER" "$trace"

    [ "$status" -eq 0 ]
    [[ "$output" == *"event=terminal_receipt"* ]]
    [ "$(printf '%s\n' "$output" | tail -1)" = "$(git -C "$REPO" rev-parse HEAD)" ]
    [ "$(grep -c '"name":"commit"' "$trace" || true)" -eq 0 ]
    [ "$(grep -c '"name":"commit-tree"' "$trace" || true)" -eq 1 ]
    [ "$(grep -c '"name":"update-ref"' "$trace" || true)" -eq 1 ]
}

@test "commit済みoutput消失後のno-change再照会はdurable receiptからhashと同一telemetryを返す" {
    printf 'recoverable publication\n' >> "$REPO/own.txt"
    run_id="receipt-reconnect-$BATS_TEST_NUMBER"

    run bash -c 'cd "$1" && NINJA_SCOPE_COMMIT_RUN_ID="$3" bash "$2" -m reconnect -- own.txt' _ "$REPO" "$HELPER" "$run_id"
    [ "$status" -eq 0 ]
    owner_hash="$(printf '%s\n' "$output" | tail -1)"
    owner_event="$(printf '%s\n' "$output" | grep '^event=completed ')"
    [[ "$owner_hash" =~ ^[0-9a-f]{40}$ ]]
    [[ "$owner_event" == *"commit_hash=$owner_hash"* ]]

    run bash -c 'cd "$1" && NINJA_SCOPE_COMMIT_RUN_ID="$3" bash "$2" -m reconnect -- own.txt' _ "$REPO" "$HELPER" "$run_id"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | tail -1)" = "$owner_hash" ]
    [ "$(printf '%s\n' "$output" | grep '^event=completed ')" = "$owner_event" ]
    [[ "$output" == *"event=terminal_receipt role=follower"* ]]
    [ -z "$(git -C "$REPO" status --porcelain -- own.txt)" ]
}

@test "stdout欠落後はrun id terminal ledgerからcomplete commitを回復しduplicateを作らない" {
    printf 'ledger recovery\n' >> "$REPO/own.txt"
    run_id="terminal-ledger-$BATS_TEST_NUMBER"

    run bash -c 'cd "$1" && NINJA_SCOPE_COMMIT_RUN_ID="$3" bash "$2" -m ledger-recovery -- own.txt >/dev/null' _ "$REPO" "$HELPER" "$run_id"
    [ "$status" -eq 0 ]
    head_after_first="$(git -C "$REPO" rev-parse HEAD)"
    ledger="$(printf '%s\n' "$output" | sed -n 's/.* ledger=\([^ ]*\).*/\1/p' | tail -1)"
    [ -s "$ledger" ]
    grep -qx "run_id=$run_id" "$ledger"
    grep -qx "commit_hash=$head_after_first" "$ledger"
    grep -qx 'rc=0' "$ledger"
    grep -qx 'phase=complete' "$ledger"
    grep -qx 'status_clean=true' "$ledger"
    grep -qx "head_generation=$head_after_first" "$ledger"
    grep -qx 'complete=true' "$ledger"

    run bash -c 'cd "$1" && NINJA_SCOPE_COMMIT_RUN_ID="$3" bash "$2" -m ledger-recovery -- own.txt' _ "$REPO" "$HELPER" "$run_id"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | tail -1)" = "$head_after_first" ]
    [ "$(git -C "$REPO" rev-list --count HEAD)" -eq 2 ]
}

@test "normal commit appends maintenance.auto=false and preserves caller config" {
    printf 'maintenance lane\n' >> "$REPO/own.txt"
    mkdir -p "$REPO/.git/hooks"
    cat > "$REPO/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
test "$(git config --bool maintenance.auto)" = false
test "$(git config scoped.fixture)" = preserved
HOOK
    chmod +x "$REPO/.git/hooks/pre-commit"
    trace="$REPO/trace.json"

    run bash -c 'cd "$1" && GIT_TRACE2_EVENT="$3" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=scoped.fixture GIT_CONFIG_VALUE_0=preserved bash "$2" -m maintenance-isolated -- own.txt' _ "$REPO" "$HELPER" "$trace"

    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" show --format= --name-only HEAD)" = own.txt ]
    [ "$(grep -c 'maintenance run --auto' "$trace" || true)" -eq 0 ]
    [ "$(grep -c '\"event\":\"cmd_name\".*\"name\":\"commit-tree\"' "$trace" || true)" -eq 1 ]
}

@test "invalid caller config count fails closed before commit" {
    head_before="$(git -C "$REPO" rev-parse HEAD)"
    printf 'must not commit\n' >> "$REPO/own.txt"

    run bash -c 'cd "$1" && GIT_CONFIG_COUNT=invalid bash "$2" -m invalid-config -- own.txt' _ "$REPO" "$HELPER"

    [ "$status" -eq 2 ]
    [[ "$output" == *"GIT_CONFIG_COUNT must be a non-negative integer"* ]]
    [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
}

@test "helperは対象1件だけcommitし他者stage1件を保持する" {
    printf 'other change\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    other_index_before="$(git -C "$REPO" ls-files -s -- other.txt)"
    printf 'own change\n' >> "$REPO/own.txt"

    run bash -c "cd '$REPO' && bash '$HELPER' -m safe -- own.txt"
    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD)" = own.txt ]
    [ "$(git -C "$REPO" diff --cached --name-only)" = other.txt ]
    [ "$(git -C "$REPO" ls-files -s -- other.txt)" = "$other_index_before" ]
}

@test "terminal eventは7 phaseを一意に記録し合計誤差200ms以下・計測overhead 50ms以下" {
    printf 'timed change\n' >> "$REPO/own.txt"

    run bash -c 'cd "$1" && bash "$2" -m timed -- own.txt 2>&1' _ "$REPO" "$HELPER"

    [ "$status" -eq 0 ]
    event="$(printf '%s\n' "$output" | grep '^event=completed ')"
    [ -n "$event" ]
    EVENT="$event" python3 - <<'PY'
import os, re

fields = dict(re.findall(r"([a-z0-9_]+)=([^ ]+)", os.environ["EVENT"]))
phases = (
    "read_tree", "add", "scope_sync", "guard", "git_commit",
    "advance_shared_index", "post_check",
)
for phase in phases:
    assert f"phase_{phase}_ms" in fields, phase
    assert fields[f"phase_{phase}_rc"] == "0", phase
assert sum(int(fields[f"phase_{phase}_ms"]) for phase in phases) == int(fields["phase_total_ms"])
assert abs(int(fields["phase_unattributed_ms"])) <= 200
assert int(fields["telemetry_overhead_ms"]) <= 50
measured = [key for key in fields if key.startswith("phase_") and key.endswith("_ms")
            and key not in {"phase_total_ms", "phase_unattributed_ms"}]
assert len(measured) == 7, measured
PY
}

@test "patch terminal eventも7 phaseを一意に記録し誤帰属しない" {
    make_shared_fixture; make_own_patch
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m patch-phases --patch '$REPO/own.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 0 ]
    terminal="$(printf '%s\n' "$output" | grep 'event=completed' | tail -1)"
    python3 - "$terminal" <<'PY'
import sys
fields = dict(item.split("=", 1) for item in sys.argv[1].split() if "=" in item)
phases = ["read_tree", "add", "scope_sync", "guard", "git_commit", "advance_shared_index", "post_check"]
assert all(fields.get(f"phase_{p}_rc") == "0" for p in phases), fields
assert len([k for k in fields if k.startswith("phase_") and k.endswith("_rc")]) == 7, fields
assert sum(int(fields[f"phase_{p}_ms"]) for p in phases) == int(fields["phase_total_ms"])
assert abs(int(fields["phase_unattributed_ms"])) <= 200, fields
assert int(fields["telemetry_overhead_ms"]) <= 50, fields
PY
}

@test "実行中helper本体の書換え後も起動時snapshotでcommitとshared indexを完遂する" {
    printf 'before\n' > "$REPO/self-mutation.txt"
    git -C "$REPO" add self-mutation.txt
    git -C "$REPO" commit -qm base-self-mutation
    printf 'after\n' > "$REPO/self-mutation.txt"
    mkdir -p "$REPO/helper/scripts/lib"
    helper_copy="$REPO/helper/scripts/ninja_scope_commit.sh"
    cp "$HELPER" "$helper_copy"
    cp "$(dirname "$HELPER")/lib/lock_path.sh" "$REPO/helper/scripts/lib/"
    cp "$(dirname "$HELPER")/lib/scope_path.sh" "$REPO/helper/scripts/lib/"
    cp "$(dirname "$HELPER")/lib/report_commit_nonoverlap_filter.sh" "$REPO/helper/scripts/lib/"

    ( sleep 0.2; printf '\nexit 2 # injected after immutable snapshot\n' >> "$helper_copy" ) &
    mutator_pid=$!
    run bash -c "cd '$REPO' && NINJA_SCOPE_COMMIT_TEST_AFTER_SNAPSHOT_DELAY=0.5 bash '$helper_copy' -m self-snapshot -- self-mutation.txt"
    run_status="$status"
    wait "$mutator_pid" || true

    [ "$run_status" -eq 0 ]
    [ "$(git -C "$REPO" show HEAD:self-mutation.txt)" = "after" ]
    [ -z "$(git -C "$REPO" status --porcelain -- self-mutation.txt)" ]
    [[ "$output" == *"event=completed"* ]]
}

@test "normal modeは専用indexから対象だけcommitしforeign stageをblob不変で保持する" {
    printf 'foreign staged\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    foreign_before="$(git -C "$REPO" ls-files -s -- other.txt)"
    printf 'own unstaged\n' >> "$REPO/own.txt"

    run bash -c "cd '$REPO' && bash '$HELPER' -m isolated-index -- own.txt"

    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD)" = own.txt ]
    [ "$(git -C "$REPO" diff --cached --name-only)" = other.txt ]
    [ "$(git -C "$REPO" ls-files -s -- other.txt)" = "$foreign_before" ]
    [ "$(git -C "$REPO" status --porcelain -- own.txt)" = "" ]
}

@test "2並列の事前stage済みcommitはsubject/pathを分離しforeign stageを保持する" {
    printf 'alpha change\n' >> "$REPO/own.txt"
    printf 'beta change\n' >> "$REPO/other.txt"
    printf 'foreign base\n' > "$REPO/foreign.txt"
    git -C "$REPO" add foreign.txt
    git -C "$REPO" commit -qm foreign-base
    printf 'foreign pending\n' >> "$REPO/foreign.txt"
    git -C "$REPO" add own.txt other.txt foreign.txt
    foreign_index_before="$(git -C "$REPO" ls-files -s -- foreign.txt)"
    mkdir -p "$REPO/.git/hooks"
    cat > "$REPO/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
sleep 0.2
HOOK
    chmod +x "$REPO/.git/hooks/pre-commit"

    (
        cd "$REPO"
        bash "$HELPER" -m subject-alpha -- own.txt
        printf 'alpha-parent-alive\n' > "$REPO/alpha.alive"
    ) >"$REPO/alpha.out" 2>&1 &
    alpha_pid=$!
    (
        cd "$REPO"
        bash "$HELPER" -m subject-beta -- other.txt
        printf 'beta-parent-alive\n' > "$REPO/beta.alive"
    ) >"$REPO/beta.out" 2>&1 &
    beta_pid=$!

    wait "$alpha_pid"
    alpha_rc=$?
    wait "$beta_pid"
    beta_rc=$?

    [ "$alpha_rc" -eq 0 ]
    [ "$beta_rc" -eq 0 ]
    [ -f "$REPO/alpha.alive" ]
    [ -f "$REPO/beta.alive" ]
    [ "$(git -C "$REPO" log -2 --format=%s | sort)" = $'subject-alpha\nsubject-beta' ]
    [ "$(git -C "$REPO" log --format=%H --grep='^subject-alpha$' -1 | xargs -r git -C "$REPO" diff-tree --no-commit-id --name-only -r)" = own.txt ]
    [ "$(git -C "$REPO" log --format=%H --grep='^subject-beta$' -1 | xargs -r git -C "$REPO" diff-tree --no-commit-id --name-only -r)" = other.txt ]
    [ "$(git -C "$REPO" ls-files -s -- foreign.txt)" = "$foreign_index_before" ]
    [ "$(git -C "$REPO" diff --cached --name-only)" = foreign.txt ]
}

@test "normal modeは対象pathの完全stage済みblobを安全にcommitする" {
    printf 'fully staged own change\n' >> "$REPO/own.txt"
    git -C "$REPO" add own.txt

    run bash -c "cd '$REPO' && bash '$HELPER' -m staged-safe -- own.txt"

    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD)" = own.txt ]
    [ "$(git -C "$REPO" status --porcelain -- own.txt)" = "" ]
}

@test "GA-282 mixed stageはtask YAMLを分離しimplementationだけcommit、foreign task stageを保持する" {
    make_ga282_fixture
    install_ga282_boundary_hook
    printf 'task: assigned\n' > "$REPO/queue/tasks/hayate.yaml"
    printf 'lesson: fixed\n' > "$REPO/projects/infra/lessons_gunshi.yaml"
    git -C "$REPO" add queue/tasks/hayate.yaml projects/infra/lessons_gunshi.yaml
    task_index_before="$(git -C "$REPO" ls-files -s -- queue/tasks/hayate.yaml)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m ga282-mixed -- queue/tasks/hayate.yaml projects/infra/lessons_gunshi.yaml"

    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO(GA-282): separated live task YAML"* ]]
    [ "$(git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD)" = projects/infra/lessons_gunshi.yaml ]
    [ "$(git -C "$REPO" show HEAD:projects/infra/lessons_gunshi.yaml)" = 'lesson: fixed' ]
    [ "$(git -C "$REPO" diff --cached --name-only)" = queue/tasks/hayate.yaml ]
    [ "$(git -C "$REPO" ls-files -s -- queue/tasks/hayate.yaml)" = "$task_index_before" ]
    [ "$(cat "$REPO/.git/ga282-hook-seen")" = projects/infra/lessons_gunshi.yaml ]
}

@test "GA-282 task-only commitは分離せずpre-commit境界を通過する" {
    make_ga282_fixture
    install_ga282_boundary_hook
    printf 'task: completed\n' > "$REPO/queue/tasks/hayate.yaml"
    git -C "$REPO" add queue/tasks/hayate.yaml

    run bash -c "cd '$REPO' && bash '$HELPER' -m ga282-task-only -- queue/tasks/hayate.yaml"

    [ "$status" -eq 0 ]
    [[ "$output" != *"INFO(GA-282)"* ]]
    [ "$(git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD)" = queue/tasks/hayate.yaml ]
    [ "$(cat "$REPO/.git/ga282-hook-seen")" = queue/tasks/hayate.yaml ]
}

@test "GA-282 implementation-only commitは実装欠落なしで従来通りcommitする" {
    make_ga282_fixture
    install_ga282_boundary_hook
    printf 'lesson: implementation-only\n' > "$REPO/projects/infra/lessons_gunshi.yaml"

    run bash -c "cd '$REPO' && bash '$HELPER' -m ga282-implementation-only -- projects/infra/lessons_gunshi.yaml"

    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD)" = projects/infra/lessons_gunshi.yaml ]
    [ "$(git -C "$REPO" show HEAD:projects/infra/lessons_gunshi.yaml)" = 'lesson: implementation-only' ]
}

@test "GA-282 parallel mixed workersは実装2commitを分離しtask stageをblob不変で保持する" {
    make_ga282_fixture
    install_ga282_boundary_hook
    printf 'task: running\n' > "$REPO/queue/tasks/hayate.yaml"
    printf 'lesson: worker-a\n' > "$REPO/projects/infra/lessons_gunshi.yaml"
    printf 'lesson2: worker-b\n' > "$REPO/projects/infra/lessons_karo.yaml"
    git -C "$REPO" add queue/tasks/hayate.yaml projects/infra/lessons_gunshi.yaml projects/infra/lessons_karo.yaml
    task_index_before="$(git -C "$REPO" ls-files -s -- queue/tasks/hayate.yaml)"

    (cd "$REPO" && bash "$HELPER" -m ga282-worker-a -- queue/tasks/hayate.yaml projects/infra/lessons_gunshi.yaml) >"$REPO/a.out" 2>&1 &
    a_pid=$!
    (cd "$REPO" && bash "$HELPER" -m ga282-worker-b -- queue/tasks/hayate.yaml projects/infra/lessons_karo.yaml) >"$REPO/b.out" 2>&1 &
    b_pid=$!
    wait "$a_pid"; a_rc=$?
    wait "$b_pid"; b_rc=$?

    [ "$a_rc" -eq 0 ]
    [ "$b_rc" -eq 0 ]
    [ "$(git -C "$REPO" log -2 --format=%s | sort)" = $'ga282-worker-a\nga282-worker-b' ]
    [ "$(git -C "$REPO" log --format=%H --grep='^ga282-worker-a$' -1 | xargs -r git -C "$REPO" diff-tree --no-commit-id --name-only -r)" = projects/infra/lessons_gunshi.yaml ]
    [ "$(git -C "$REPO" log --format=%H --grep='^ga282-worker-b$' -1 | xargs -r git -C "$REPO" diff-tree --no-commit-id --name-only -r)" = projects/infra/lessons_karo.yaml ]
    [ "$(git -C "$REPO" diff --cached --name-only)" = queue/tasks/hayate.yaml ]
    [ "$(git -C "$REPO" ls-files -s -- queue/tasks/hayate.yaml)" = "$task_index_before" ]
}

@test "normal modeはpartial stageとworktree不一致をfail-closedしindexを保持する" {
    printf 'staged owner unknown\n' >> "$REPO/own.txt"
    git -C "$REPO" add own.txt
    staged_before="$(git -C "$REPO" ls-files -s -- own.txt)"
    printf 'additional unstaged\n' >> "$REPO/own.txt"
    head_before="$(git -C "$REPO" rev-parse HEAD)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m must-block -- own.txt"

    [ "$status" -eq 2 ]
    [[ "$output" == *"partial/foreign staged content"* ]]
    [ "$(git -C "$REPO" ls-files -s -- own.txt)" = "$staged_before" ]
    [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
}

@test "commit後に同一hunkのdirty差分が残れば報告前にBLOCKする" {
    mkdir -p "$REPO/.git/hooks"
    cat > "$REPO/.git/hooks/post-commit" <<'HOOK'
#!/bin/sh
printf 'dirty after commit\n' > own.txt
HOOK
    chmod +x "$REPO/.git/hooks/post-commit"
    printf 'committed change\n' > "$REPO/own.txt"

    run bash -c "cd '$REPO' && bash '$HELPER' -m overlap -- own.txt"

    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK(GA-260)"* ]]
    [[ "$output" == *"own.txt"* ]]
}

make_shared_fixture() {
    : > "$REPO/shared.txt"
    for i in $(seq 1 36); do printf 'base-%02d\n' "$i" >> "$REPO/shared.txt"; done
    git -C "$REPO" add shared.txt
    git -C "$REPO" commit -qm shared-base
}

make_own_patch() {
    cp "$REPO/shared.txt" "$REPO/shared.working"
    for i in 2 9 16 23 30; do sed -i "${i}s/$/-own/" "$REPO/shared.txt"; done
    git -C "$REPO" diff -- shared.txt > "$REPO/own.patch"
    mv "$REPO/shared.working" "$REPO/shared.txt"
}

@test "patch modeは同内容hunkが別位置へ適用されたらcommit前にBLOCKする" {
    printf 'start\nrepeat\nend\nstart\nrepeat\nend\n' > "$REPO/ambiguous.txt"
    git -C "$REPO" add ambiguous.txt && git -C "$REPO" commit -qm ambiguous-base
    printf '%s\n' \
        'diff --git a/ambiguous.txt b/ambiguous.txt' \
        '--- a/ambiguous.txt' '+++ b/ambiguous.txt' \
        '@@ -4,3 +4,3 @@' ' start' '-repeat' '+changed' ' end' > "$REPO/ambiguous.patch"
    # Remove the intended bottom block only in the working fixture used to
    # demonstrate that git apply can relocate identical context to the top.
    sed -i '4,6d' "$REPO/ambiguous.txt"
    git -C "$REPO" add ambiguous.txt && git -C "$REPO" commit -qm split-delete
    base_blob="$(git -C "$REPO" rev-parse HEAD:ambiguous.txt)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m must-block --patch '$REPO/ambiguous.patch' --base-blob '$base_blob' -- ambiguous.txt"
    [ "$status" -eq 2 ]
    [[ "$output" == *"does not exactly match requested patch position/content"* ]]
    [ "$(git -C "$REPO" log --format=%s -1)" = split-delete ]
}

@test "patch modeはlinked worktreeでも意図位置をcommitしforeign hunkを保全する" {
    make_shared_fixture; make_own_patch
    linked="$BATS_TMPDIR/linked-$BATS_TEST_NUMBER"
    git -C "$REPO" worktree add -q -b linked-branch "$linked"
    for i in 1 4 7; do sed -i "${i}s/$/-foreign/" "$linked/shared.txt"; done
    before="$(cat "$linked/shared.txt")"
    base_blob="$(git -C "$linked" rev-parse HEAD:shared.txt)"

    run bash -c "cd '$linked' && bash '$HELPER' -m linked-own --patch '$REPO/own.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 0 ]
    [ "$(git -C "$linked" show HEAD:shared.txt | grep -c -- '-own')" -eq 5 ]
    [ "$(cat "$linked/shared.txt")" = "$before" ]
    [ "$(grep -c -- '-foreign' "$linked/shared.txt")" -eq 3 ]
    git -C "$REPO" worktree remove -f "$linked"
}

@test "patch modeはpostverify異常時にcommitせずforeign stageを保全する" {
    make_shared_fixture; make_own_patch
    printf 'foreign staged\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    foreign_before="$(git -C "$REPO" ls-files -s -- other.txt)"
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"
    printf 'not a patch\n' > "$REPO/own.patch"

    run bash -c "cd '$REPO' && bash '$HELPER' -m invalid --patch '$REPO/own.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 2 ]
    [ "$(git -C "$REPO" log --format=%s -1)" = shared-base ]
    [ "$(git -C "$REPO" ls-files -s -- other.txt)" = "$foreign_before" ]
}

@test "patch modeは同一fileの自分5 hunkだけcommitし他者13 hunkと共有indexを完全保全する" {
    make_shared_fixture
    make_own_patch
    for i in 1 4 7 10 13 18 21 24 27 31 33 35 36; do sed -i "${i}s/$/-other/" "$REPO/shared.txt"; done
    printf 'other staged\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    other_index_before="$(git -C "$REPO" ls-files -s -- other.txt)"
    worktree_before="$(cat "$REPO/shared.txt")"
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m own-five --patch '$REPO/own.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" show --format= --numstat HEAD -- shared.txt | awk '{print $1+$2}')" -eq 10 ]
    [ "$(git -C "$REPO" show HEAD:shared.txt | grep -c -- '-own')" -eq 5 ]
    [ "$(cat "$REPO/shared.txt")" = "$worktree_before" ]
    [ "$(grep -c -- '-other' "$REPO/shared.txt")" -eq 13 ]
    [ "$(git -C "$REPO" ls-files -s -- other.txt)" = "$other_index_before" ]
    [ "$(git -C "$REPO" diff --cached --name-only)" = other.txt ]
}

@test "patch mode commit後の直接git add競合はforeign stageを上書きしない" {
    make_shared_fixture; make_own_patch
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"
    mkdir -p "$REPO/.git/hooks"
    cat > "$REPO/.git/hooks/post-commit" <<'HOOK'
#!/usr/bin/env bash
printf 'foreign-after-commit\n' >> shared.txt
unset GIT_INDEX_FILE
git add shared.txt
HOOK
    chmod +x "$REPO/.git/hooks/post-commit"

    run bash -c "cd '$REPO' && bash '$HELPER' -m patch-cas --patch '$REPO/own.patch' --base-blob '$base_blob' -- shared.txt"

    [ "$status" -eq 0 ]
    [[ "$output" == *"preserving newer staged entry"* ]]
    [ "$(git -C "$REPO" show :shared.txt | tail -1)" = foreign-after-commit ]
    [ "$(git -C "$REPO" show HEAD:shared.txt | grep -c -- '-own')" -eq 5 ]
    [ "$(git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD)" = shared.txt ]
}

@test "旧HEAD blobがshared indexに残るMM状態は後続patchをBLOCKし内容を保持する" {
    make_shared_fixture; make_own_patch
    old_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"
    base_blob="$old_blob"
    run bash -c "cd '$REPO' && bash '$HELPER' -m first --patch '$REPO/own.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 0 ]

    # 隔離fixtureで事故状態を構成: HEADは新blob、indexだけ旧HEAD、worktreeはforeign hunk。
    git -C "$REPO" update-index --cacheinfo "100644,$old_blob,shared.txt"
    printf 'foreign-worktree\n' >> "$REPO/shared.txt"
    stale_entry="$(git -C "$REPO" ls-files -s -- shared.txt)"
    head_before="$(git -C "$REPO" rev-parse HEAD)"
    printf '%s\n' 'diff --git a/shared.txt b/shared.txt' '--- a/shared.txt' '+++ b/shared.txt' \
        '@@ -1 +1 @@' '-base-01-own' '+next-owner' > "$REPO/next.patch"
    new_base="$(git -C "$REPO" rev-parse HEAD:shared.txt)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m must-block-stale --patch '$REPO/next.patch' --base-blob '$new_base' -- shared.txt"
    [ "$status" -eq 2 ]
    [[ "$output" == *"already has staged content"* ]]
    [ "$(git -C "$REPO" ls-files -s -- shared.txt)" = "$stale_entry" ]
    [ "$(tail -1 "$REPO/shared.txt")" = foreign-worktree ]
    [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
}

@test "patch modeはbase blob不一致をcommit前にBLOCKする" {
    make_shared_fixture; make_own_patch
    run bash -c "cd '$REPO' && bash '$HELPER' -m stale --patch '$REPO/own.patch' --base-blob 0000000000000000000000000000000000000000 -- shared.txt"
    [ "$status" -eq 2 ]
    [[ "$output" == *"base blob mismatch"* ]]
}

@test "patch modeはscope外path混入をcommit前にBLOCKする" {
    make_shared_fixture; make_own_patch
    printf 'other change\n' >> "$REPO/other.txt"
    git -C "$REPO" diff -- shared.txt other.txt > "$REPO/mixed.patch"
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"
    run bash -c "cd '$REPO' && bash '$HELPER' -m mixed --patch '$REPO/mixed.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 2 ]
    [[ "$output" == *"out-of-scope path"* ]]
}

@test "patch modeは空patchと適用不能patchをcommit前にBLOCKする" {
    make_shared_fixture
    : > "$REPO/empty.patch"
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"
    run bash -c "cd '$REPO' && bash '$HELPER' -m empty-patch --patch '$REPO/empty.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 2 ]
    [[ "$output" == *"missing or empty"* ]]

    printf '%s\n' 'diff --git a/shared.txt b/shared.txt' '--- a/shared.txt' '+++ b/shared.txt' '@@ -1 +1 @@' '-not-the-base' '+changed' > "$REPO/bad.patch"
    run bash -c "cd '$REPO' && bash '$HELPER' -m bad-patch --patch '$REPO/bad.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 2 ]
    [[ "$output" == *"does not apply cleanly"* ]]
}

@test "patch modeは削除・新規file・改行境界のpatchを扱う" {
    make_shared_fixture
    printf 'tail-no-newline' >> "$REPO/shared.txt"
    git -C "$REPO" add shared.txt && git -C "$REPO" commit -qm newline-base
    printf '\nchanged-tail\n' >> "$REPO/shared.txt"
    git -C "$REPO" diff -- shared.txt > "$REPO/newline.patch"
    git -C "$REPO" checkout -q -- shared.txt
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"
    run bash -c "cd '$REPO' && bash '$HELPER' -m newline --patch '$REPO/newline.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 0 ]

    printf 'new file\n' > "$REPO/new.txt"
    git -C "$REPO" diff --no-index /dev/null new.txt > "$REPO/new.patch" || true
    run bash -c "cd '$REPO' && bash '$HELPER' -m new --patch '$REPO/new.patch' --base-blob 0000000000000000000000000000000000000000 -- new.txt"
    [ "$status" -eq 0 ]

    # patch modeはworking treeを意図的に不変に保つ。次の独立edge fixture前に
    # sandbox内だけHEADへ同期する（本番helperは他者差分へ触れない）。
    git -C "$REPO" checkout -q -- shared.txt
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"
    git -C "$REPO" rm -q shared.txt
    git -C "$REPO" diff --cached -- shared.txt > "$REPO/delete.patch"
    git -C "$REPO" reset -q HEAD -- shared.txt
    git -C "$REPO" checkout -q -- shared.txt
    run bash -c "cd '$REPO' && bash '$HELPER' -m delete --patch '$REPO/delete.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 0 ]
    ! git -C "$REPO" cat-file -e HEAD:shared.txt
}

@test "空scopeはBLOCKする" {
    run bash -c "cd '$REPO' && bash '$HELPER' -m empty --"
    [ "$status" -eq 2 ]
    [[ "$output" == *"commit scope is empty"* ]]
}

@test "stale shared index.lock is removed inside commit transaction" {
    printf 'own change\n' >> "$REPO/own.txt"
    : > "$REPO/.git/index.lock"
    run bash -c "cd '$REPO' && bash '$HELPER' -m stale-lock -- own.txt"
    [ "$status" -eq 0 ]
    [ ! -e "$REPO/.git/index.lock" ]
    [ -z "$(git -C "$REPO" status --porcelain -- own.txt)" ]
}

@test "foreign active index lock after HEAD publication is retried and foreign stage is preserved" {
    printf 'own change\n' >> "$REPO/own.txt"
    printf 'foreign change\n' >> "$REPO/other.txt"
    mkdir -p "$REPO/.git/hooks"
cat > "$REPO/.git/hooks/post-commit" <<'HOOK'
#!/usr/bin/env bash
(
    cp .git/index .git/foreign-index
    GIT_INDEX_FILE=.git/foreign-index git add other.txt
    mv .git/foreign-index .git/index.lock
    exec 9>>.git/index.lock
    sleep 0.15
    mv .git/index.lock .git/index
) </dev/null >.git/foreign-writer.log 2>&1 &
for _ in $(seq 1 100); do
    [[ -e .git/index.lock ]] && exit 0
    sleep 0.01
done
exit 1
HOOK
    chmod +x "$REPO/.git/hooks/post-commit"

    run bash -c 'cd "$1" && NINJA_SCOPE_COMMIT_INDEX_RETRY_ATTEMPTS=100 NINJA_SCOPE_COMMIT_INDEX_RETRY_DELAY=0.01 bash "$2" -m foreign-lock -- own.txt' _ "$REPO" "$HELPER"

    [ "$status" -eq 0 ]
    hash="$(printf '%s\n' "$output" | tail -1)"
    [[ "$hash" =~ ^[0-9a-f]{40}$ ]]
    [ "$(git -C "$REPO" diff --cached --name-only)" = other.txt ]
    [ -z "$(git -C "$REPO" status --porcelain -- own.txt)" ]
    [[ "$output" == *"event=terminal_receipt"* ]]
}

@test "foreign active index lock retry exhaustion emits durable commit receipt" {
    printf 'own change\n' >> "$REPO/own.txt"
    mkdir -p "$REPO/.git/hooks"
    cat > "$REPO/.git/hooks/post-commit" <<'HOOK'
#!/usr/bin/env bash
(
    exec 9>.git/index.lock
    sleep 1
    rm -f .git/index.lock
) </dev/null >.git/foreign-writer.log 2>&1 &
for _ in $(seq 1 100); do
    [[ -e .git/index.lock ]] && exit 0
    sleep 0.01
done
exit 1
HOOK
    chmod +x "$REPO/.git/hooks/post-commit"
    run_id="foreign-timeout-$BATS_TEST_NUMBER"

    run bash -c 'cd "$1" && NINJA_SCOPE_COMMIT_RUN_ID="$3" NINJA_SCOPE_COMMIT_INDEX_RETRY_ATTEMPTS=2 NINJA_SCOPE_COMMIT_INDEX_RETRY_DELAY=0.01 bash "$2" -m foreign-timeout -- own.txt' _ "$REPO" "$HELPER" "$run_id"

    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK: shared index did not converge after 2 attempts"* ]]
    event="$(printf '%s\n' "$output" | grep '^event=failed ')"
    hash="$(printf '%s\n' "$event" | sed -n 's/.* commit_hash=\([0-9a-f]\{40\}\).*/\1/p')"
    [[ "$hash" =~ ^[0-9a-f]{40}$ ]]
    receipt="$(printf '%s\n' "$output" | sed -n 's/.* receipt=\([^ ]*\).*/\1/p' | tail -1)"
    [ -s "$receipt" ]
    grep -qx "commit_hash=$hash" "$receipt"
    grep -qx 'rc=1' "$receipt"
    ledger="$(printf '%s\n' "$output" | sed -n 's/.* ledger=\([^ ]*\).*/\1/p' | tail -1)"
    [ -s "$ledger" ]
    grep -qx "commit_hash=$hash" "$ledger"
    grep -qx 'rc=1' "$ledger"
    grep -qx 'phase=advance_shared_index' "$ledger"
    grep -qx 'complete=false' "$ledger"
}

@test "存在しないpathはBLOCKする" {
    run bash -c "cd '$REPO' && bash '$HELPER' -m missing -- absent.txt"
    [ "$status" -eq 2 ]
    [[ "$output" == *"scope path does not exist"* ]]
}

@test "GA-222 final edge RC: root scope '.' はBLOCKされindex/working treeが不変のまま" {
    printf 'other change\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    other_index_before="$(git -C "$REPO" ls-files -s -- other.txt)"
    other_worktree_before="$(cat "$REPO/other.txt")"
    printf 'own change\n' >> "$REPO/own.txt"
    own_worktree_before="$(cat "$REPO/own.txt")"
    head_before="$(git -C "$REPO" rev-parse HEAD)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m root-scope -- ."

    [ "$status" -eq 2 ]
    [[ "$output" == *"repository root"* ]]
    [ "$(git -C "$REPO" ls-files -s -- other.txt)" = "$other_index_before" ]
    [ "$(cat "$REPO/other.txt")" = "$other_worktree_before" ]
    [ "$(cat "$REPO/own.txt")" = "$own_worktree_before" ]
    [ "$(git -C "$REPO" status --porcelain -- own.txt)" = " M own.txt" ]
    [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
}

@test "GA-222 4回目RC: root scope別名'subdir/..'はBLOCKされindex/working treeが不変のまま" {
    mkdir -p "$REPO/subdir"
    printf 'other change\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    other_index_before="$(git -C "$REPO" ls-files -s -- other.txt)"
    printf 'own change\n' >> "$REPO/own.txt"
    own_worktree_before="$(cat "$REPO/own.txt")"
    head_before="$(git -C "$REPO" rev-parse HEAD)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m subdir-dotdot -- subdir/.."

    [ "$status" -eq 2 ]
    [[ "$output" == *"'..'"* ]]
    [ "$(git -C "$REPO" ls-files -s -- other.txt)" = "$other_index_before" ]
    [ "$(cat "$REPO/own.txt")" = "$own_worktree_before" ]
    [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
}

@test "GA-222 4回目RC: 単独'..'はBLOCKされindex/working treeが不変のまま" {
    printf 'other change\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    other_index_before="$(git -C "$REPO" ls-files -s -- other.txt)"
    printf 'own change\n' >> "$REPO/own.txt"
    own_worktree_before="$(cat "$REPO/own.txt")"
    head_before="$(git -C "$REPO" rev-parse HEAD)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m bare-dotdot -- .."

    [ "$status" -eq 2 ]
    [[ "$output" == *"'..'"* ]]
    [ "$(git -C "$REPO" ls-files -s -- other.txt)" = "$other_index_before" ]
    [ "$(cat "$REPO/own.txt")" = "$own_worktree_before" ]
    [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
}

@test "pre-commit hookを実行する" {
    mkdir -p "$REPO/.git/hooks"
    printf '#!/usr/bin/env bash\nprintf hook-ran > .git/hook-marker\n' > "$REPO/.git/hooks/pre-commit"
    chmod +x "$REPO/.git/hooks/pre-commit"
    printf 'own change\n' >> "$REPO/own.txt"

    run bash -c "cd '$REPO' && bash '$HELPER' -m hooked -- own.txt"
    [ "$status" -eq 0 ]
    [ "$(cat "$REPO/.git/hook-marker")" = hook-ran ]
}

@test "GA-222: 正本が無いrepoではsync_git_hooks呼び出しが無害にno-opする" {
    printf 'own change\n' >> "$REPO/own.txt"

    run bash -c "cd '$REPO' && bash '$HELPER' -m no-sync-source -- own.txt"
    [ "$status" -eq 0 ]
}

@test "GA-222: commit前にstale/未配備の.git/hooks/pre-commitを正本と同期する" {
    SYNC_SCRIPT="$BATS_TEST_DIRNAME/../../scripts/sync_git_hooks.sh"
    mkdir -p "$REPO/scripts" "$REPO/scripts/hooks" "$REPO/.git/hooks"
    cp "$SYNC_SCRIPT" "$REPO/scripts/sync_git_hooks.sh"
    chmod +x "$REPO/scripts/sync_git_hooks.sh"

    printf '#!/usr/bin/env bash\nprintf hook-ran-fixed > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"
    chmod +x "$REPO/scripts/hooks/git-pre-commit.sh"
    printf '#!/usr/bin/env bash\nprintf hook-ran-stale > .git/hook-marker\n' \
        > "$REPO/.git/hooks/pre-commit"
    chmod +x "$REPO/.git/hooks/pre-commit"
    (
        cd "$REPO"
        git add scripts/sync_git_hooks.sh scripts/hooks/git-pre-commit.sh
        git commit -qm "add tracked hook source + sync helper"
    )

    printf 'own change\n' >> "$REPO/own.txt"

    run bash -c "cd '$REPO' && bash '$HELPER' -m sync-then-commit -- own.txt"
    [ "$status" -eq 0 ]
    cmp -s "$REPO/scripts/hooks/git-pre-commit.sh" "$REPO/.git/hooks/pre-commit"
    [ "$(cat "$REPO/.git/hook-marker")" = hook-ran-fixed ]
}

@test "GA-222 REQUEST_CHANGES: another agent's uncommitted hook-source edit does not leak in via an unrelated ninja commit" {
    mkdir -p "$REPO/scripts/hooks"
    cp "$BATS_TEST_DIRNAME/../../scripts/sync_git_hooks.sh" "$REPO/scripts/sync_git_hooks.sh"
    chmod +x "$REPO/scripts/sync_git_hooks.sh"
    printf '#!/usr/bin/env bash\nprintf hook-ran-committed > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"
    chmod +x "$REPO/scripts/hooks/git-pre-commit.sh"
    (
        cd "$REPO"
        git add scripts/sync_git_hooks.sh scripts/hooks/git-pre-commit.sh
        git commit -qm "add tracked hook source + sync helper"
    )

    # Another agent is mid-edit: unstaged, uncommitted change to the hook
    # source, unrelated to this ninja's own.txt-only commit scope.
    printf '#!/usr/bin/env bash\nprintf OTHER_AGENT_WIP > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"
    printf 'own change\n' >> "$REPO/own.txt"

    run bash -c "cd '$REPO' && bash '$HELPER' -m unrelated-commit -- own.txt"
    [ "$status" -eq 0 ]
    run cat "$REPO/.git/hooks/pre-commit"
    [[ "$output" == *"hook-ran-committed"* ]]
    [[ "$output" != *"OTHER_AGENT_WIP"* ]]
}

@test "GA-222 REQUEST_CHANGES: committing the hook source itself installs the newly staged content" {
    mkdir -p "$REPO/scripts/hooks"
    cp "$BATS_TEST_DIRNAME/../../scripts/sync_git_hooks.sh" "$REPO/scripts/sync_git_hooks.sh"
    chmod +x "$REPO/scripts/sync_git_hooks.sh"
    printf '#!/usr/bin/env bash\nprintf OLD_VERSION > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"
    chmod +x "$REPO/scripts/hooks/git-pre-commit.sh"
    (
        cd "$REPO"
        git add scripts/sync_git_hooks.sh scripts/hooks/git-pre-commit.sh
        git commit -qm "add tracked hook source + sync helper"
    )

    # This ninja's own commit scope IS the hook source itself.
    printf '#!/usr/bin/env bash\nprintf NEW_VERSION > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"

    run bash -c "cd '$REPO' && bash '$HELPER' -m update-hook-source -- scripts/hooks/git-pre-commit.sh"
    [ "$status" -eq 0 ]
    run cat "$REPO/.git/hooks/pre-commit"
    [[ "$output" == *"NEW_VERSION"* ]]
}

@test "GA-222 followup: committing a directory scope that contains the hook source installs the newly staged content" {
    mkdir -p "$REPO/scripts/hooks"
    cp "$BATS_TEST_DIRNAME/../../scripts/sync_git_hooks.sh" "$REPO/scripts/sync_git_hooks.sh"
    chmod +x "$REPO/scripts/sync_git_hooks.sh"
    printf '#!/usr/bin/env bash\nprintf OLD_VERSION > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"
    chmod +x "$REPO/scripts/hooks/git-pre-commit.sh"
    (
        cd "$REPO"
        git add scripts/sync_git_hooks.sh scripts/hooks/git-pre-commit.sh
        git commit -qm "add tracked hook source + sync helper"
    )

    # This ninja commits the whole scripts/hooks directory (not the exact
    # file path). git add stages git-pre-commit.sh recursively, and the
    # committed tree includes the new content — the live hook must match
    # that same new content immediately after commit, not the stale HEAD
    # value from before this commit (which would otherwise cause an
    # immediate re-drift right after the commit completes).
    printf '#!/usr/bin/env bash\nprintf NEW_VERSION_VIA_DIR_SCOPE > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"

    run bash -c "cd '$REPO' && bash '$HELPER' -m update-hook-source-dir-scope -- scripts/hooks"
    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" show HEAD:scripts/hooks/git-pre-commit.sh)" = "$(cat "$REPO/scripts/hooks/git-pre-commit.sh")" ]
    run cat "$REPO/.git/hooks/pre-commit"
    [[ "$output" == *"NEW_VERSION_VIA_DIR_SCOPE"* ]]
}

@test "GA-222 final edge RC: 'scripts/hooks/.' (trailing /.) scope path installs the newly staged content" {
    mkdir -p "$REPO/scripts/hooks"
    cp "$BATS_TEST_DIRNAME/../../scripts/sync_git_hooks.sh" "$REPO/scripts/sync_git_hooks.sh"
    chmod +x "$REPO/scripts/sync_git_hooks.sh"
    printf '#!/usr/bin/env bash\nprintf OLD_VERSION > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"
    chmod +x "$REPO/scripts/hooks/git-pre-commit.sh"
    (
        cd "$REPO"
        git add scripts/sync_git_hooks.sh scripts/hooks/git-pre-commit.sh
        git commit -qm "add tracked hook source + sync helper"
    )

    # "scripts/hooks/." is pathspec-equivalent to "scripts/hooks" for git add,
    # but is a distinct string — is_in_scope must normalize before comparing.
    printf '#!/usr/bin/env bash\nprintf NEW_VERSION_VIA_TRAILING_DOT > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"

    run bash -c "cd '$REPO' && bash '$HELPER' -m update-hook-source-trailing-dot -- scripts/hooks/."
    [ "$status" -eq 0 ]
    run cat "$REPO/.git/hooks/pre-commit"
    [[ "$output" == *"NEW_VERSION_VIA_TRAILING_DOT"* ]]
}

@test "GA-222 4回目RC: 'scripts//hooks' (double slash) scope path installs the newly staged content" {
    mkdir -p "$REPO/scripts/hooks"
    cp "$BATS_TEST_DIRNAME/../../scripts/sync_git_hooks.sh" "$REPO/scripts/sync_git_hooks.sh"
    chmod +x "$REPO/scripts/sync_git_hooks.sh"
    printf '#!/usr/bin/env bash\nprintf OLD_VERSION > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"
    chmod +x "$REPO/scripts/hooks/git-pre-commit.sh"
    (
        cd "$REPO"
        git add scripts/sync_git_hooks.sh scripts/hooks/git-pre-commit.sh
        git commit -qm "add tracked hook source + sync helper"
    )

    # "scripts//hooks" is pathspec-equivalent to "scripts/hooks" for git add.
    printf '#!/usr/bin/env bash\nprintf NEW_VERSION_VIA_DOUBLE_SLASH > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"

    run bash -c "cd '$REPO' && bash '$HELPER' -m update-hook-source-double-slash -- scripts//hooks"
    [ "$status" -eq 0 ]
    run cat "$REPO/.git/hooks/pre-commit"
    [[ "$output" == *"NEW_VERSION_VIA_DOUBLE_SLASH"* ]]
}
