#!/usr/bin/env bats
# test_necessity: cmd_id指定の完了処理は、そのgenerationのcmd/worker/report manifestに
#                 含まれる報告だけを読み、無関係report・未読inbox・task運用YAMLを
#                 byte-identicalに保ったまま、report退避、世代検証、dashboard保持数を
#                 従来どおり成立させる不変量を守る。
# regression_justification: 既存archive testsは退避可否を検証するが、無関係reportを
#                           開かないI/O境界と世代/retentionとの合成を固定していない。
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
