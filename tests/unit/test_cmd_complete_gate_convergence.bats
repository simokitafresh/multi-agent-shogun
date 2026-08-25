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
    run bash -c '
        set -euo pipefail
        gate=$1; root=$2
        source "$(dirname "$gate")/lib/lock_path.sh"
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
        printf "runtime checkpoint\n" >> "$shared/context/infrastructure.md"

        source <(sed -n "/^postclear_runtime_path_is_publishable()/,/^}/p" "$gate")
        source <(sed -n "/^publish_postclear_runtime_deltas()/,/^}/p" "$gate")
        source <(sed -n "/^converge_shared_execution_sources()/,/^}/p" "$gate")
        push_from_clean_worktree() {
            local repo=$1 remote_name=$3 source_sha=$6 remote_url
            remote_url=$(git -C "$repo" remote get-url "$remote_name")
            git clone -q --branch main "$remote_url" "$publisher"
            git -C "$publisher" config user.name test
            git -C "$publisher" config user.email test@example.invalid
            git -C "$publisher" fetch -q "$repo" "$source_sha"
            git -C "$publisher" cherry-pick FETCH_HEAD >/dev/null
            GIT_COMMITTER_DATE="2030-01-01T00:00:00+00:00" git -C "$publisher" commit -q --amend --no-edit
            printf "%s\n" "$source_sha" > "$root/source.sha"
            git -C "$publisher" rev-parse HEAD > "$root/published.sha"
            git -C "$publisher" push -q origin HEAD:main
        }
        SCRIPT_DIR=$shared GATES_DIR=$shared/queue/gates CMD_ID=cmd_fixture
        publish_postclear_runtime_deltas pregate
        source_sha=$(cat "$root/source.sha"); published_sha=$(cat "$root/published.sha")
        test "$source_sha" != "$published_sha"
        test "$(git -C "$shared" rev-parse "$source_sha:context/infrastructure.md")" = \
             "$(git -C "$shared" rev-parse "$published_sha:context/infrastructure.md")"
        converge_shared_execution_sources "$shared" scripts/cmd_complete_gate.sh
        test -z "$(git -C "$shared" status --porcelain=v1 --untracked-files=no)"
        test "$(git -C "$shared" show HEAD:context/infrastructure.md)" = $'"'"'before\nruntime checkpoint'"'"'
        printf "runtime_checkpoint_first=1 overlap_equivalence=1 differing_sha=1\n"
    ' _ "$BATS_TEST_DIRNAME/../../scripts/cmd_complete_gate.sh" "$BATS_TEST_TMPDIR/runtime-convergence"
    [ "$status" -eq 0 ]
    [[ "$output" == *"runtime_checkpoint_first=1 overlap_equivalence=1 differing_sha=1" ]]
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
