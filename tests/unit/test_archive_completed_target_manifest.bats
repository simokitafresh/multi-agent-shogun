#!/usr/bin/env bats
# test_necessity: cmd_id指定の完了処理は、そのgenerationのcmd/worker/report manifestに
#                 含まれる報告だけを読み、無関係report・未読inbox・task運用YAMLを
#                 byte-identicalに保ったまま、report退避、世代検証、dashboard保持数を
#                 従来どおり成立させる不変量を守る。
# regression_justification: 既存archive testsは退避可否を検証するが、無関係reportを
#                           開かないI/O境界と世代/retentionとの合成を固定していない。
# test_necessity: task worktree cleanupはCLEAR-bound no-code identityまたはexact-bytesに
#                 結合したformal FAIL_CLOSEだけを受理し、dirty・HEAD不一致・非祖先・
#                 commit必須taskを全てremove前にBLOCKする不変量を守る。
# origin: [[cmd_karo_recon_cmd_complete_postclear_bottleneck_20260810]] -> [[cmd指定後の全report後段除外]] -> [[完了tail長時間滞留]]

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    FIX="$BATS_TEST_TMPDIR/project"
    CMD="cmd_karo_archive_target_fixture"
    GEN="$(printf 'a%.0s' {1..64})"
    mkdir -p "$FIX/queue/reports" "$FIX/queue/tasks" "$FIX/queue/inbox" \
        "$FIX/queue/gates/$CMD" "$FIX/queue/archive/reports" "$FIX/logs" \
        "$FIX/context" "$FIX/config" "$FIX/archive/cmd-chronicle"
    printf 'commands:\n' > "$FIX/queue/shogun_to_karo.yaml"
    printf 'timestamp\tCLEAR\t%s\n' "$CMD" > "$FIX/logs/gate_metrics.log"
    printf 'timestamp: now\nsource: two_phase_review\nresult: LGTM\n' \
        > "$FIX/queue/gates/$CMD/review_gate.done"
    printf '# CMD年代記\n<!-- last_updated: 2026-08-10 -->\n' > "$FIX/context/cmd-chronicle.md"
    {
        printf '# Dashboard\n\n## 最新更新\n\n'
        printf '| id | result |\n|---|---|\n'
        printf '| %s | PASS |\n' 1 2 3 4 5
    } > "$FIX/dashboard.md"
    printf 'messages:\n- id: unread-1\n  read: false\n  content: preserve\n' \
        > "$FIX/queue/inbox/karo.yaml"
}

run_archive() {
    ARCHIVE_COMPLETED_PROJECT_DIR="$FIX" \
        SHOGUN_COMPLETION_GENERATION="$GEN" \
        DEFENSE_OVERHEAD_LEDGER="$FIX/logs/defense_overhead.jsonl" \
        QUEUE_FLAG_RETENTION_MODE=off \
        timeout 30 bash "$REPO_ROOT/scripts/archive_completed.sh" 3 "$CMD" 2>&1
}

write_worktree_marker() {
    marker_tip="$1"
    marker_task_id="${2:-${WT_CMD}_normal}"
    printf '{"version":1,"state":"active","task_id":"%s","parent_cmd":"%s","repo":"%s","worktree":"%s","remote_tip":"%s","published_commit":"","generation":"%s","created_at_ns":1}\n' \
        "$marker_task_id" "$WT_CMD" "$WT_REPO" "$WT_PATH" "$marker_tip" "$WT_MARKER_GEN" \
        > "$FIX/queue/gates/$WT_CMD/task_worktree.json"
}

write_worktree_report() {
    report_status="$1"
    report_verdict="$2"
    contract_required="$3"
    report_task_type="$4"
    report_task_id="${5:-${WT_CMD}_normal}"
    printf 'worker_id: kotaro\ntask_id: %s\nparent_cmd: %s\ntask_type: %s\nstatus: %s\nverdict: %s\ncommit_contract:\n  required: %s\n  task_type: %s\n  planned_paths: []\n  repo_root: %s\n' \
        "$report_task_id" "$WT_CMD" "$report_task_type" "$report_status" "$report_verdict" \
        "$contract_required" "$report_task_type" "$WT_REPO" \
        > "$FIX/queue/reports/kotaro_report_${WT_CMD}.yaml"
    printf '{"reviews":[{"cmd":"%s","report":"queue/reports/kotaro_report_%s.yaml"}]}\n' \
        "$WT_CMD" "$WT_CMD" > "$FIX/queue/gates/$WT_CMD/single_review_manifest.json"
}

setup_worktree_cleanup_fixture() {
    WT_CMD="cmd_karo_archive_nocode_fixture"
    WT_GEN="$(printf 'b%.0s' {1..64})"
    WT_MARKER_GEN="$(printf 'c%.0s' {1..64})"
    WT_REPO="$BATS_TEST_TMPDIR/source-repo"
    WT_REMOTE="$BATS_TEST_TMPDIR/remote.git"
    WT_PATH="$BATS_TEST_TMPDIR/linked-worktree"
    mkdir -p "$FIX/queue/gates/$WT_CMD" "$FIX/queue/reports"
    git init -q -b main "$WT_REPO"
    git -C "$WT_REPO" config user.email fixture@example.com
    git -C "$WT_REPO" config user.name fixture
    printf 'base\n' > "$WT_REPO/source.txt"
    git -C "$WT_REPO" add source.txt
    git -C "$WT_REPO" commit -q -m base
    WT_BASE="$(git -C "$WT_REPO" rev-parse HEAD)"
    printf 'current\n' >> "$WT_REPO/source.txt"
    git -C "$WT_REPO" commit -qam current
    WT_CURRENT="$(git -C "$WT_REPO" rev-parse HEAD)"
    WT_SIDE="$(printf 'side\n' | git -C "$WT_REPO" commit-tree "${WT_BASE}^{tree}" -p "$WT_BASE")"
    git init -q --bare "$WT_REMOTE"
    git -C "$WT_REPO" remote add origin "$WT_REMOTE"
    git -C "$WT_REPO" push -q -u origin main
    git -C "$WT_REPO" worktree add -q --detach "$WT_PATH" "$WT_BASE"
    write_worktree_marker "$WT_BASE"
    write_worktree_report completed PASS false recon
    printf '{"version":1,"state":"clear","cmd_id":"%s","completion_generation":"%s","persisted_at_ns":1}\n' \
        "$WT_CMD" "$WT_GEN" > "$FIX/queue/gates/$WT_CMD/gate_worker.clear.json"
}

run_worktree_cleanup() {
    ARCHIVE_COMPLETED_PROJECT_DIR="$FIX" \
        ARCHIVE_TASK_WORKTREE_CLEANUP_ONLY=1 \
        ARCHIVE_REQUIRE_CLEAR_RECEIPT=1 \
        SHOGUN_COMPLETION_GENERATION="$WT_GEN" \
        timeout 30 bash "$REPO_ROOT/scripts/archive_completed.sh" 3 "$WT_CMD" 2>&1
}

# A FIFO is an access detector: opening an unrelated report blocks forever.
# Metadata-only directory operations do not open it.
@test "targeted archive reads only the worker report manifest and preserves operational YAML" {
    target="$FIX/queue/reports/custom-terminal-report.yaml"
    printf 'worker_id: hayate\nparent_cmd: %s\nstatus: completed\nverdict: PASS\nsummary: target\n' \
        "$CMD" > "$target"
    printf 'task:\n  parent_cmd: %s\n  status: done\n  report_path: queue/reports/custom-terminal-report.yaml\n' \
        "$CMD" > "$FIX/queue/tasks/hayate.yaml"
    printf 'worker_id: saizo\nparent_cmd: cmd_unrelated\nstatus: pending\nverdict: null\n' \
        > "$FIX/queue/reports/saizo_report_cmd_unrelated.yaml"
    for i in $(seq 1 10); do
        parent="cmd_retained_$i"
        mkdir -p "$FIX/queue/gates/$parent"
        : > "$FIX/queue/gates/$parent/archive.done"
        printf 'worker_id: retained_%s\nparent_cmd: %s\nstatus: completed\nverdict: PASS\n' \
            "$i" "$parent" > "$FIX/queue/reports/retained_${i}_report_${parent}.yaml"
    done
    mkfifo "$FIX/queue/reports/kotaro_report_cmd_unrelated_fifo.yaml"

    inbox_before="$(sha256sum "$FIX/queue/inbox/karo.yaml")"
    task_before="$(sha256sum "$FIX/queue/tasks/hayate.yaml")"
    unrelated_before="$(sha256sum "$FIX/queue/reports/saizo_report_cmd_unrelated.yaml")"
    retained_before="$(sha256sum "$FIX/queue/reports"/retained_*_report_*.yaml | sha256sum)"

    run run_archive
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"target-report-manifest: cmd=$CMD reports=1"* ]]
    [[ "$output" == *"reports: archived=1"* ]]
    [[ "$output" == *"overflow-cap: targeted monotonic-decrease"* ]]
    [ -L "$target" ]
    archived=("$FIX/queue/archive/reports/custom-terminal-report_"*.yaml)
    [ -f "${archived[0]}" ]
    [ -p "$FIX/queue/reports/kotaro_report_cmd_unrelated_fifo.yaml" ]
    [ "$(sha256sum "$FIX/queue/inbox/karo.yaml")" = "$inbox_before" ]
    [ "$(sha256sum "$FIX/queue/tasks/hayate.yaml")" = "$task_before" ]
    [ "$(sha256sum "$FIX/queue/reports/saizo_report_cmd_unrelated.yaml")" = "$unrelated_before" ]
    [ "$(sha256sum "$FIX/queue/reports"/retained_*_report_*.yaml | sha256sum)" = "$retained_before" ]
    [ "$(find "$FIX/queue/reports" -maxdepth 1 -type f -name 'retained_*_report_*.yaml' | wc -l)" -eq 10 ]
    [ "$(grep -c '^| [0-9]' "$FIX/dashboard.md")" -eq 3 ]
    [ "$(grep -c '^| [0-9]' "$FIX/queue/archive/dashboard_archive.md")" -eq 2 ]
    [ -f "$FIX/queue/gates/$CMD/archive.done" ]
}

@test "terminal review manifest resolves a report after the worker task slot was reused" {
    target="$FIX/queue/reports/nonstandard-name.yaml"
    printf 'worker_id: kagemaru\nreport_id: rpt-target\nparent_cmd: %s\nstatus: completed\nverdict: PASS\n' \
        "$CMD" > "$target"
    printf 'task:\n  parent_cmd: cmd_new_owner\n  status: in_progress\n  report_path: queue/reports/new.yaml\n' \
        > "$FIX/queue/tasks/kagemaru.yaml"
    printf '{"version":1,"cmd_id":"%s","reports":[{"logical_path":"queue/reports/nonstandard-name.yaml","report_id":"rpt-target"}]}\n' \
        "$CMD" > "$FIX/queue/gates/$CMD/terminal_review_manifest.json"

    run run_archive
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"target-report-manifest: cmd=$CMD reports=1"* ]]
    [ -L "$target" ]
    archived=("$FIX/queue/archive/reports/nonstandard-name_"*.yaml)
    [ -f "${archived[0]}" ]
}

@test "invalid completion generation fails before report or operational YAML mutation" {
    target="$FIX/queue/reports/hayate_report_${CMD}.yaml"
    printf 'worker_id: hayate\nparent_cmd: %s\nstatus: completed\nverdict: PASS\n' \
        "$CMD" > "$target"
    before="$(sha256sum "$target" "$FIX/queue/inbox/karo.yaml" "$FIX/dashboard.md")"
    GEN=invalid

    run run_archive
    echo "$output"
    [ "$status" -ne 0 ]
    [[ "$output" == *"SHOGUN_COMPLETION_GENERATION missing or invalid"* ]]
    [ "$(sha256sum "$target" "$FIX/queue/inbox/karo.yaml" "$FIX/dashboard.md")" = "$before" ]
    [ ! -e "$FIX/queue/gates/$CMD/archive.done" ]
}

@test "clean no-code worktree recovers its verified remote-ancestor base and cleans up" {
    setup_worktree_cleanup_fixture

    run run_worktree_cleanup
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"publication recovered from verified no-code base"* ]]
    [ ! -d "$WT_PATH" ]
    python3 - "$FIX/queue/gates/$WT_CMD/task_worktree.json" "$WT_BASE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["state"] == "cleaned"
assert data["published_commit"] == sys.argv[2]
assert data["published_recovery_source"] == "verified_no_code_base"
PY
}

@test "dirty no-code worktree remains fail-closed" {
    setup_worktree_cleanup_fixture
    printf 'dirty\n' > "$WT_PATH/dirty.txt"

    run run_worktree_cleanup
    echo "$output"
    [ "$status" -ne 0 ]
    [ -d "$WT_PATH" ]
    [[ "$output" == *"published commit receipt missing, mismatched, or unresolved"* ]]
}

@test "no-code marker whose tip differs from worktree HEAD remains fail-closed" {
    setup_worktree_cleanup_fixture
    git -C "$WT_PATH" checkout -q --detach "$WT_CURRENT"

    run run_worktree_cleanup
    echo "$output"
    [ "$status" -ne 0 ]
    [ -d "$WT_PATH" ]
}

@test "clean no-code tip outside current remote ancestry remains fail-closed" {
    setup_worktree_cleanup_fixture
    git -C "$WT_PATH" checkout -q --detach "$WT_SIDE"
    write_worktree_marker "$WT_SIDE"

    run run_worktree_cleanup
    echo "$output"
    [ "$status" -ne 0 ]
    [ -d "$WT_PATH" ]
}

@test "implementation-commit-required report cannot use no-code base recovery" {
    setup_worktree_cleanup_fixture
    write_worktree_report completed PASS true hotfix

    run run_worktree_cleanup
    echo "$output"
    [ "$status" -ne 0 ]
    [ -d "$WT_PATH" ]
}

@test "formal Karo fail-close cleans a clean worktree without fabricating CLEAR" {
    setup_worktree_cleanup_fixture
    rm "$FIX/queue/gates/$WT_CMD/gate_worker.clear.json"
    write_worktree_report failed FAIL true hotfix
    approval_dir="$FIX/queue/gates/$WT_CMD/review_approvals/reports/fixture"
    mkdir -p "$approval_dir"
    report_rel="queue/reports/kotaro_report_${WT_CMD}.yaml"
    report_generation="$(sha256sum "$FIX/$report_rel" | awk '{print $1}')"
    printf 'timestamp: now\nrole: karo\nresult: ACCEPT\ngeneration: %s\nreport: %s\n' \
        "$report_generation" "$report_rel" > "$approval_dir/karo.yaml"

    run run_worktree_cleanup
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cleanup without CLEAR fabrication"* ]]
    [ ! -e "$FIX/queue/gates/$WT_CMD/gate_worker.clear.json" ]
    [ ! -d "$WT_PATH" ]
}
