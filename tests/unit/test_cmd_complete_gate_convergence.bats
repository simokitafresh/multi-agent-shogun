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
        timeout --signal=TERM --kill-after=5 60 \
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

# test_necessity: runtime dirty publication must finish before the shared gate
# source merge, including overlap where equivalent content has a different SHA.
@test "pregate runtime publication precedes shared source convergence" {
    run env GATE_PATH="$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh" \
        ROOT_PATH="$BATS_TEST_TMPDIR/runtime-convergence" bash -c '
        set -euo pipefail
        gate=$GATE_PATH; root=$ROOT_PATH
        remote=$root/remote.git; shared=$root/shared; publisher=$root/publisher
        git init -q --bare "$remote"
        git init -q -b main "$shared"
        git -C "$shared" config user.name test
        git -C "$shared" config user.email test@example.invalid
        mkdir -p "$shared/scripts" "$shared/context" "$shared/queue/gates"
        printf "#!/usr/bin/env bash\necho stable\n" > "$shared/scripts/cmd_complete_gate.sh"
        printf "before\n" > "$shared/context/infrastructure.md"
        git -C "$shared" add scripts/cmd_complete_gate.sh context/infrastructure.md
        git -C "$shared" commit -qm initial
        git -C "$shared" remote add origin "$remote"
        git -C "$shared" push -qu -u origin main
        remote_before=$(git --git-dir "$remote" rev-parse refs/heads/main)
        printf "runtime checkpoint\n" >> "$shared/context/infrastructure.md"

        source <(sed -n "/^postclear_runtime_path_is_publishable()/,/^}/p" "$gate")
        source <(sed -n "/^publish_postclear_runtime_deltas()/,/^}/p" "$gate")
        source <(sed -n "/^converge_shared_execution_sources()/,/^}/p" "$gate")
        push_from_clean_worktree() {
            printf "unexpected origin push\n" > "$root/origin-push-called"
            return 99
        }
        SCRIPT_DIR=$shared GATES_DIR=$shared/queue/gates CMD_ID=cmd_fixture
        publish_postclear_runtime_deltas pregate
        test ! -e "$root/origin-push-called"
        shared_commit=$(git -C "$shared" rev-parse HEAD)
        test "$(git -C "$shared" show "$shared_commit:context/infrastructure.md")" = $'"'"'before\nruntime checkpoint'"'"'
        test "$(git --git-dir "$remote" rev-parse refs/heads/main)" = "$remote_before"
        test "$(git -C "$shared" diff-tree --no-commit-id --name-only -r "$shared_commit^" "$shared_commit")" = "context/infrastructure.md"
        converge_shared_execution_sources "$shared" scripts/cmd_complete_gate.sh
        test -z "$(git -C "$shared" status --porcelain=v1 --untracked-files=no)"
        test "$(git -C "$shared" show HEAD:context/infrastructure.md)" = $'"'"'before\nruntime checkpoint'"'"'
        test -n "$(grep -F 'runtime_shared_main_checkpoint' "$shared/queue/gates/postclear_publication.log")"
        printf "runtime_checkpoint_first=1 shared_main_commit=1 origin_push_calls=0\n"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"runtime_checkpoint_first=1 shared_main_commit=1 origin_push_calls=0" ]]
}

# test_necessity: runtime publication must never call the origin-writing helper;
# Karo's oldest-first shared-main lane is the sole remote publication owner.
@test "runtime publisher has no direct origin push caller" {
    run python3 - "$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh" <<'PY'
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
start = text.index("publish_postclear_runtime_deltas()")
end = text.index("\n}\n\n# The semantic index/map writer", start) + 2
block = text[start:end]
assert "push_from_clean_worktree" not in block
assert "git -C \"$clean_repo\" push" not in block
assert "runtime_publish.shared_main_field_aware_commit" in block
assert "runtime_shared_main_checkpoint" in block
print("runtime_origin_push_callers=0 shared_main_field_aware_commit=1 rev_list_observation=1")
PY
    [ "$status" -eq 0 ]
    [ "$output" = "runtime_origin_push_callers=0 shared_main_field_aware_commit=1 rev_list_observation=1" ]
}

# test_necessity: repeated failed preflight archives for one logical task must
# resolve to one live task and its declared report identity, never five report
# names derived from timestamped archive basenames.
@test "logical task identity dedupes failed archives and binds report path" {
    run bash -c '
        set -euo pipefail
        gate=$1; root=$2; live=$root/queue/tasks; archive=$root/queue/archive/tasks
        report=$root/queue/reports/hayate_report_cmd_fixture.yaml
        mkdir -p "$live" "$archive" "$root/queue/reports"
        for i in 1 2 3 4 5; do
            printf "task:\n  task_id: cmd_fixture_normal\n  parent_cmd: cmd_fixture\n  deployed_at: 2026-08-19T00:0%s:00+09:00\n  report_path: queue/reports/bogus_%s.yaml\n" "$i" "$i" > "$archive/hayate_cmd_fixture_failed_$i.yaml"
            printf "parent_cmd: cmd_fixture\ntask_id: wrong_%s\n" "$i" > "$root/queue/reports/bogus_$i.yaml"
        done
        printf "task:\n  task_id: cmd_fixture_normal\n  parent_cmd: cmd_fixture\n  deployed_at: 2026-08-19T02:00:00+09:00\n  report_path: queue/reports/hayate_report_cmd_fixture.yaml\n" > "$live/hayate.yaml"
        printf "parent_cmd: cmd_fixture\ntask_id: cmd_fixture_normal\nstatus: completed\n" > "$report"
        source <(sed -n "/^dedupe_task_files_by_logical_identity()/,/^}/p" "$gate")
        source <(sed -n "/^resolve_declared_task_report_path()/,/^}/p" "$gate")
        mapfile -t selected < <(dedupe_task_files_by_logical_identity "$live" "$archive"/*.yaml "$live/hayate.yaml")
        test "${#selected[@]}" -eq 1
        test "${selected[0]}" = "$live/hayate.yaml"
        resolved=$(resolve_declared_task_report_path "${selected[0]}" "$root" cmd_fixture)
        test "$resolved" = "$report"
        bogus=0
        for path in "$root"/queue/reports/bogus_*.yaml; do test "$resolved" != "$path" || bogus=$((bogus + 1)); done
        printf "archives=5 logical_tasks=%s report_identity=1 bogus_reports=%s\n" "${#selected[@]}" "$bogus"
    ' _ "$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh" "$BATS_TEST_TMPDIR/task-dedupe"
    [ "$status" -eq 0 ]
    [ "$output" = "archives=5 logical_tasks=1 report_identity=1 bogus_reports=0" ]
}
