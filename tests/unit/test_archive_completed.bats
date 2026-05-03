#!/usr/bin/env bats
# test_archive_completed.bats - unit tests for scripts/archive_completed.sh

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_ARCHIVE_SCRIPT="$PROJECT_ROOT/scripts/archive_completed.sh"
    export SRC_FIELD_GET_SCRIPT="$PROJECT_ROOT/scripts/lib/field_get.sh"
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/archive_completed.root.XXXXXX")"
    export TEST_TEMPLATE="$TEST_ROOT/template"

    [ -f "$SRC_ARCHIVE_SCRIPT" ] || return 1
    [ -f "$SRC_FIELD_GET_SCRIPT" ] || return 1
    command -v awk >/dev/null 2>&1 || return 1
    command -v flock >/dev/null 2>&1 || return 1

    mkdir -p "$TEST_TEMPLATE/scripts/lib" "$TEST_TEMPLATE/queue/reports" "$TEST_TEMPLATE/context"
    ln -s "$SRC_ARCHIVE_SCRIPT" "$TEST_TEMPLATE/scripts/archive_completed.sh"
    ln -s "$SRC_FIELD_GET_SCRIPT" "$TEST_TEMPLATE/scripts/lib/field_get.sh"

    # postconditionで呼ばれても外部通知しないようにスタブ化
    cat > "$TEST_TEMPLATE/scripts/ntfy.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$TEST_TEMPLATE/scripts/ntfy.sh"
}

setup() {
    export TEST_PROJECT="$TEST_ROOT/project_${BATS_TEST_NUMBER}"
    mkdir -p "$TEST_PROJECT"
    cp -a "$TEST_TEMPLATE/." "$TEST_PROJECT/"
}

teardown_file() {
    [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"
}

@test "archives cmd when status is missing but cmd exists in completed_changelog" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_520
    purpose: "test purpose"
    project: infra
YAML

    cat > "$TEST_PROJECT/queue/completed_changelog.yaml" <<'YAML'
entries:
  - id: cmd_520
    completed_at: "2026-03-04T00:00:00"
YAML

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]

    run grep -q "cmd_520" "$TEST_PROJECT/queue/shogun_to_karo.yaml"
    [ "$status" -eq 1 ]

    run ls "$TEST_PROJECT"/queue/archive/cmds/cmd_520_completed_*.yaml
    [ "$status" -eq 0 ]
}

@test "keeps cmd when status is missing and completed_changelog has no exact cmd match" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_521
    purpose: "test purpose"
    project: infra
YAML

    cat > "$TEST_PROJECT/queue/completed_changelog.yaml" <<'YAML'
entries:
  - id: cmd_5210
    completed_at: "2026-03-04T00:00:00"
YAML

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]

    run grep -q "id: cmd_521" "$TEST_PROJECT/queue/shogun_to_karo.yaml"
    [ "$status" -eq 0 ]

    run ls "$TEST_PROJECT"/queue/archive/cmds/cmd_521_*.yaml
    [ "$status" -ne 0 ]
}

@test "preserves existing status-based archive behavior" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_530
    status: completed
    purpose: "status completed"
    project: infra
YAML

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]

    run grep -q "cmd_530" "$TEST_PROJECT/queue/shogun_to_karo.yaml"
    [ "$status" -eq 1 ]

    run ls "$TEST_PROJECT"/queue/archive/cmds/cmd_530_completed_*.yaml
    [ "$status" -eq 0 ]
}

# ============================================================
# chronicle append tests (AC2/AC4)
# ============================================================

@test "chronicle: creates file and appends entry on cmd archive" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_550
    status: completed
    purpose: "chronicle test"
    project: infra
YAML

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]

    # chronicle file should exist
    [ -f "$TEST_PROJECT/context/cmd-chronicle.md" ]

    # should contain the cmd entry
    run grep -q "cmd_550" "$TEST_PROJECT/context/cmd-chronicle.md"
    [ "$status" -eq 0 ]

    # should contain purpose
    run grep -q "chronicle test" "$TEST_PROJECT/context/cmd-chronicle.md"
    [ "$status" -eq 0 ]

    # should contain project
    run grep -q "infra" "$TEST_PROJECT/context/cmd-chronicle.md"
    [ "$status" -eq 0 ]
}

@test "chronicle: auto-generates month section with table header" {
    # Use a recent date in the previous month (within 30 days) so trim_cmd_chronicle
    # does not archive it. Fallback to last-day-of-prev-month when 25-days-ago lands
    # in the current month (day-of-month >= 26).
    local prev_ym prev_date
    prev_ym="$(date -d '25 days ago' '+%Y-%m')"
    prev_date="$(date -d '25 days ago' '+%m-%d')"
    if [ "$prev_ym" = "$(date '+%Y-%m')" ]; then
        local fallback
        fallback="$(date -d "$(date '+%Y-%m-01') - 1 day" '+%Y-%m-%d')"
        prev_ym="$(date -d "$fallback" '+%Y-%m')"
        prev_date="$(date -d "$fallback" '+%m-%d')"
    fi

    # Create chronicle without current month but with a recent old section
    cat > "$TEST_PROJECT/context/cmd-chronicle.md" <<MD
# CMD年代記
<!-- last_updated: $(date '+%Y-%m-%d') -->

## ${prev_ym}

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| cmd_100 | old test | infra | ${prev_date} | — |
MD

    # Ensure archive directory exists for trim_cmd_chronicle
    mkdir -p "$TEST_PROJECT/archive/cmd-chronicle"

    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_551
    status: completed
    purpose: "month section test"
    project: dm-signal
YAML

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]

    # current month section should be auto-generated
    local year_month
    year_month="$(date '+%Y-%m')"
    run grep -q "^## ${year_month}$" "$TEST_PROJECT/context/cmd-chronicle.md"
    [ "$status" -eq 0 ]

    # old month section should still exist if within 30-day retention.
    # Edge case: on day 31 of months following shorter months (e.g., March 31),
    # the last day of the previous month (Feb 28) can exceed the 30-day cutoff.
    local cutoff_date prev_day
    cutoff_date="$(date -d '30 days ago' '+%Y-%m-%d')"
    prev_day="${prev_date##*-}"
    if [[ ! "${prev_ym}-${prev_day}" < "$cutoff_date" ]]; then
        run grep -q "^## ${prev_ym}$" "$TEST_PROJECT/context/cmd-chronicle.md"
        [ "$status" -eq 0 ]
    fi

    # new entry should be present
    run grep -q "cmd_551" "$TEST_PROJECT/context/cmd-chronicle.md"
    [ "$status" -eq 0 ]
}

@test "chronicle: includes report summary in key_result" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_552
    status: completed
    purpose: "report summary test"
    project: infra
YAML

    # Create a report with summary field
    cat > "$TEST_PROJECT/queue/reports/hanzo_report_cmd_552.yaml" <<'YAML'
parent_cmd: cmd_552
status: done
summary: "All ACs passed. Chronicle append works correctly."
YAML

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]

    # key_result should contain truncated summary (30 chars)
    run grep "cmd_552" "$TEST_PROJECT/context/cmd-chronicle.md"
    [ "$status" -eq 0 ]
    # summary should appear (first 30 chars)
    [[ "$output" == *"All ACs passed"* ]]
}

@test "chronicle: existing archive behavior unaffected" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_553
    status: completed
    purpose: "should archive"
    project: infra
  - id: cmd_554
    purpose: "should keep (no status)"
    project: infra
YAML

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]

    # cmd_553 should be archived (not in queue)
    run grep -q "cmd_553" "$TEST_PROJECT/queue/shogun_to_karo.yaml"
    [ "$status" -eq 1 ]

    # cmd_554 should be kept (in queue)
    run grep -q "cmd_554" "$TEST_PROJECT/queue/shogun_to_karo.yaml"
    [ "$status" -eq 0 ]

    # chronicle should only contain cmd_553
    run grep -q "cmd_553" "$TEST_PROJECT/context/cmd-chronicle.md"
    [ "$status" -eq 0 ]
    run grep -q "cmd_554" "$TEST_PROJECT/context/cmd-chronicle.md"
    [ "$status" -eq 1 ]
}

@test "chronicle: flock timeout suppresses batch synced success log" {
    mkdir -p "$TEST_PROJECT/bin"
    cat > "$TEST_PROJECT/bin/flock" <<'EOF'
#!/usr/bin/env bash
fd="${@: -1}"
if [ "$fd" = "200" ] && [ "$(readlink "/proc/$$/fd/200" 2>/dev/null)" = "/tmp/mas-chronicle.lock" ]; then
    exit 1
fi
exec /usr/bin/flock "$@"
EOF
    chmod +x "$TEST_PROJECT/bin/flock"

    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_555
    status: completed
    purpose: "chronicle flock timeout"
    project: infra
YAML

    run env PATH="$TEST_PROJECT/bin:$PATH" bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[chronicle] WARN: flock timeout on chronicle"* ]]
    [[ "$output" != *"[chronicle] batch synced"* ]]
}

@test "chronicle: flock timeout suppresses trim done success log" {
    mkdir -p "$TEST_PROJECT/bin" "$TEST_PROJECT/archive/cmd-chronicle"
    cat > "$TEST_PROJECT/bin/flock" <<'EOF'
#!/usr/bin/env bash
fd="${@: -1}"
if [ "$fd" = "200" ] && [ "$(readlink "/proc/$$/fd/200" 2>/dev/null)" = "/tmp/mas-chronicle.lock" ]; then
    exit 1
fi
exec /usr/bin/flock "$@"
EOF
    chmod +x "$TEST_PROJECT/bin/flock"

    local old_ym old_date
    old_ym="$(date -d '60 days ago' '+%Y-%m')"
    old_date="$(date -d '60 days ago' '+%m-%d')"
    cat > "$TEST_PROJECT/context/cmd-chronicle.md" <<MD
# CMD年代記
<!-- last_updated: $(date '+%Y-%m-%d') -->

## ${old_ym}

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| cmd_100 | old test | infra | ${old_date} | — |
MD

    run env PATH="$TEST_PROJECT/bin:$PATH" bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[chronicle-trim] WARN: flock timeout"* ]]
    [[ "$output" != *"[chronicle-trim] done"* ]]
    [[ "$output" == *"[archive_completed] done"* ]]
}

@test "pending decisions archive: set +e scope only wraps helper return capture" {
    run bash -c '
        section=$(sed -n "/^archive_pending_decisions_for_cmd()/,/^}/p" "$1")
        [[ "$section" == *"set +e"* ]]
        [[ "$section" == *"archived_count=\"\$(archive_pending_decisions_for_cmd_locked \"\$cmd_id\")\""* ]]
        [[ "$section" == *"archive_rc=\$?"* ]]
        [[ "$section" == *"set -e"* ]]
        set_plus_line=$(grep -nF "set +e" <<< "$section" | head -1 | cut -d: -f1)
        set_e_line=$(grep -nF "set -e" <<< "$section" | head -1 | cut -d: -f1)
        [[ -n "$set_plus_line" && -n "$set_e_line" ]]
        [[ $((set_e_line - set_plus_line)) -le 3 ]]
    ' _ "$SRC_ARCHIVE_SCRIPT"
    [ "$status" -eq 0 ]
}

@test "chronicle: single-entry sync propagates flock timeout before synced log" {
    run bash -c '
        section=$(sed -n "/^sync_chronicle_entry()/,/^}/p" "$1")
        [[ "$section" == *"local chronicle_rc"* ]]
        [[ "$section" == *"chronicle_rc=\$?"* ]]
        [[ "$section" == *"return \"\$chronicle_rc\""* ]]
        capture_line=$(grep -nF "chronicle_rc=\$?" <<< "$section" | head -1 | cut -d: -f1)
        echo_line=$(grep -nF "echo \"[chronicle] synced:" <<< "$section" | head -1 | cut -d: -f1)
        [[ -n "$capture_line" && -n "$echo_line" && "$capture_line" -lt "$echo_line" ]]
    ' _ "$SRC_ARCHIVE_SCRIPT"
    [ "$status" -eq 0 ]
}

# ============================================================
# training/cycle/selfimprovement cmd exemption tests (cmd_1522)
# ============================================================

@test "report archive: training/cycle/selfimprovement cmd reports skip review_gate.done check" {
    # cmd_training_*, cmd_cycle_*, cmd_selfimprovement_* の3プレフィックスを1テストで網羅
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_training_001
    status: completed
    purpose: "training cycle test"
    project: infra
  - id: cmd_cycle_002
    status: completed
    purpose: "cycle test"
    project: infra
  - id: cmd_selfimprovement_003
    status: completed
    purpose: "selfimprovement test"
    project: infra
YAML

    cat > "$TEST_PROJECT/queue/reports/kotaro_report_cmd_training_001.yaml" <<'YAML'
parent_cmd: cmd_training_001
status: done
result:
  summary: "training report"
YAML
    cat > "$TEST_PROJECT/queue/reports/hayate_report_cmd_cycle_002.yaml" <<'YAML'
parent_cmd: cmd_cycle_002
status: done
result:
  summary: "cycle report"
YAML
    cat > "$TEST_PROJECT/queue/reports/hanzo_report_cmd_selfimprovement_003.yaml" <<'YAML'
parent_cmd: cmd_selfimprovement_003
status: done
result:
  summary: "selfimprovement report"
YAML

    # NO review_gate.done — all 3 exempt prefixes should still be archived
    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]

    [ -L "$TEST_PROJECT/queue/reports/kotaro_report_cmd_training_001.yaml" ]
    [ -L "$TEST_PROJECT/queue/reports/hayate_report_cmd_cycle_002.yaml" ]
    [ -L "$TEST_PROJECT/queue/reports/hanzo_report_cmd_selfimprovement_003.yaml" ]
    [ -f "$(readlink "$TEST_PROJECT/queue/reports/kotaro_report_cmd_training_001.yaml")" ]
    [ -f "$(readlink "$TEST_PROJECT/queue/reports/hayate_report_cmd_cycle_002.yaml")" ]
    [ -f "$(readlink "$TEST_PROJECT/queue/reports/hanzo_report_cmd_selfimprovement_003.yaml")" ]
}

@test "GP-133: report archive skips when review_gate.done is deploy_preflight placeholder" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_1623
    status: completed
    purpose: "GP-133 placeholder test"
    project: dm-signal
YAML

    cat > "$TEST_PROJECT/queue/reports/hanzo_report_cmd_1623.yaml" <<'YAML'
parent_cmd: cmd_1623
status: completed
result:
  summary: "placeholder test report"
YAML

    # Create placeholder review_gate.done (simulates deploy_task.sh behavior)
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_1623"
    cat > "$TEST_PROJECT/queue/gates/cmd_1623/review_gate.done" <<'GATE'
timestamp: 2026-03-31T18:57:33
source: deploy_preflight
note: 配備時placeholder。軍師レビュー完了時に上書きされる。
GATE

    # Create archive.done to allow sweep mode to proceed past that check
    touch "$TEST_PROJECT/queue/gates/cmd_1623/archive.done"

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]

    # Report should NOT be archived (placeholder = review not complete)
    [ -f "$TEST_PROJECT/queue/reports/hanzo_report_cmd_1623.yaml" ]
}

@test "cmd_2529: sweep backfills missing archive.done when gate_metrics has CLEAR" {
    mkdir -p "$TEST_PROJECT/logs" "$TEST_PROJECT/queue/gates/cmd_2529a"
    cat > "$TEST_PROJECT/logs/gate_metrics.log" <<'EOF'
2026-05-03T00:00:00	cmd_2529a	CLEAR	-	impl	model	routine	none	title
EOF
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_2529a
    status: completed
    purpose: "archive.done backfill test"
    project: infra
YAML
    cat > "$TEST_PROJECT/queue/gates/cmd_2529a/review_gate.done" <<'GATE'
timestamp: 2026-05-03T00:00:00
source: gunshi_review
result: LGTM
GATE
    cat > "$TEST_PROJECT/queue/reports/saizo_report_cmd_2529a.yaml" <<'YAML'
parent_cmd: cmd_2529a
status: completed
result:
  summary: "archive done backfill"
YAML

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]
    [ -f "$TEST_PROJECT/queue/gates/cmd_2529a/archive.done" ]
    [ -L "$TEST_PROJECT/queue/reports/saizo_report_cmd_2529a.yaml" ]
}

@test "cmd_2529: sweep replaces deploy_preflight placeholder when gate_metrics has CLEAR" {
    mkdir -p "$TEST_PROJECT/logs" "$TEST_PROJECT/queue/gates/cmd_2529b"
    cat > "$TEST_PROJECT/logs/gate_metrics.log" <<'EOF'
2026-05-03T00:00:00	cmd_2529b	CLEAR	-	impl	model	routine	none	title
EOF
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_2529b
    status: completed
    purpose: "placeholder backfill test"
    project: infra
YAML
    cat > "$TEST_PROJECT/queue/gates/cmd_2529b/review_gate.done" <<'GATE'
timestamp: 2026-05-03T00:00:00
source: deploy_preflight
note: placeholder
GATE
    cat > "$TEST_PROJECT/queue/reports/saizo_report_cmd_2529b.yaml" <<'YAML'
parent_cmd: cmd_2529b
status: completed
result:
  summary: "placeholder backfill"
YAML

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]
    grep -q '^source: gate_metrics_backfill$' "$TEST_PROJECT/queue/gates/cmd_2529b/review_gate.done"
    [ -f "$TEST_PROJECT/queue/gates/cmd_2529b/archive.done" ]
    [ -L "$TEST_PROJECT/queue/reports/saizo_report_cmd_2529b.yaml" ]
}

@test "cmd_2529: sweep backfills missing review_gate.done when gate_metrics has CLEAR" {
    mkdir -p "$TEST_PROJECT/logs"
    cat > "$TEST_PROJECT/logs/gate_metrics.log" <<'EOF'
2026-05-03T00:00:00	cmd_2529c	CLEAR	-	impl	model	routine	none	title
EOF
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_2529c
    status: completed
    purpose: "missing review gate backfill test"
    project: infra
YAML
    cat > "$TEST_PROJECT/queue/reports/saizo_report_cmd_2529c.yaml" <<'YAML'
parent_cmd: cmd_2529c
status: completed
result:
  summary: "missing review gate backfill"
YAML

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]
    grep -q '^source: gate_metrics_backfill$' "$TEST_PROJECT/queue/gates/cmd_2529c/review_gate.done"
    [ -f "$TEST_PROJECT/queue/gates/cmd_2529c/archive.done" ]
    [ -L "$TEST_PROJECT/queue/reports/saizo_report_cmd_2529c.yaml" ]
}

@test "cmd_2529: sweep archives 14d stale gate-incomplete report without CLEAR" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_2529d
    status: completed
    purpose: "stale gate incomplete archive test"
    project: infra
YAML
    cat > "$TEST_PROJECT/queue/reports/saizo_report_cmd_2529d.yaml" <<'YAML'
parent_cmd: cmd_2529d
status: completed
result:
  summary: "stale gate incomplete"
YAML
    touch -d '15 days ago' "$TEST_PROJECT/queue/reports/saizo_report_cmd_2529d.yaml"

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_PROJECT/queue/gates/cmd_2529d/review_gate.done" ]
    [ -L "$TEST_PROJECT/queue/reports/saizo_report_cmd_2529d.yaml" ]
}

@test "cmd_2529: sweep archives 14d stale deploy_preflight placeholder without CLEAR" {
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_2529e"
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_2529e
    status: completed
    purpose: "stale placeholder archive test"
    project: infra
YAML
    cat > "$TEST_PROJECT/queue/gates/cmd_2529e/review_gate.done" <<'GATE'
timestamp: 2026-05-03T00:00:00
source: deploy_preflight
note: placeholder
GATE
    cat > "$TEST_PROJECT/queue/reports/saizo_report_cmd_2529e.yaml" <<'YAML'
parent_cmd: cmd_2529e
status: completed
result:
  summary: "stale placeholder"
YAML
    touch -d '15 days ago' "$TEST_PROJECT/queue/reports/saizo_report_cmd_2529e.yaml"

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]
    grep -q '^source: deploy_preflight$' "$TEST_PROJECT/queue/gates/cmd_2529e/review_gate.done"
    [ -L "$TEST_PROJECT/queue/reports/saizo_report_cmd_2529e.yaml" ]
}

@test "cmd_2529: sweep caps completed report backlog at 10 while preserving pending" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands: []
YAML
    for i in $(seq 1 12); do
        cat > "$TEST_PROJECT/queue/reports/saizo_report_cmd_2529cap_${i}.yaml" <<YAML
parent_cmd: cmd_2529cap_${i}
status: completed
result:
  summary: "overflow ${i}"
YAML
        touch -d "$((20 - i)) minutes ago" "$TEST_PROJECT/queue/reports/saizo_report_cmd_2529cap_${i}.yaml"
    done
    cat > "$TEST_PROJECT/queue/reports/saizo_report_cmd_2529cap_pending.yaml" <<'YAML'
parent_cmd: cmd_2529cap_pending
status: pending
result:
  summary: "pending"
YAML

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]
    [ "$(find "$TEST_PROJECT/queue/reports" -maxdepth 1 -type f -name '*.yaml' | wc -l)" -eq 10 ]
    [ -f "$TEST_PROJECT/queue/reports/saizo_report_cmd_2529cap_pending.yaml" ]
    [ "$(find "$TEST_PROJECT/queue/reports" -maxdepth 1 -type f -name '*cmd_2529cap_[0-9]*.yaml' | wc -l)" -eq 9 ]
}

@test "GP-133: report archive proceeds when review_gate.done is gunshi_review" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_1624
    status: completed
    purpose: "GP-133 real review test"
    project: dm-signal
YAML

    cat > "$TEST_PROJECT/queue/reports/hanzo_report_cmd_1624.yaml" <<'YAML'
parent_cmd: cmd_1624
status: completed
result:
  summary: "real review test report"
YAML

    # Create real review_gate.done (simulates gunshi LGTM update)
    mkdir -p "$TEST_PROJECT/queue/gates/cmd_1624"
    cat > "$TEST_PROJECT/queue/gates/cmd_1624/review_gate.done" <<'GATE'
timestamp: 2026-03-31T19:20:00
source: gunshi_review
result: LGTM
note: 軍師レビュー完了。placeholderから上書き(GP-133)。
GATE

    # Create archive.done
    touch "$TEST_PROJECT/queue/gates/cmd_1624/archive.done"

    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]

    # Report SHOULD be archived (real review = complete) with a GP-230 symlink left behind.
    [ -L "$TEST_PROJECT/queue/reports/hanzo_report_cmd_1624.yaml" ]
    [ -f "$(readlink "$TEST_PROJECT/queue/reports/hanzo_report_cmd_1624.yaml")" ]
}

@test "report archive: regular cmd still requires review_gate.done" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  - id: cmd_999
    status: completed
    purpose: "regular cmd"
    project: infra
YAML

    cat > "$TEST_PROJECT/queue/reports/saizo_report_cmd_999.yaml" <<'YAML'
parent_cmd: cmd_999
status: done
result:
  summary: "regular report"
YAML

    # NO review_gate.done — regular cmd should NOT be archived
    run bash "$TEST_PROJECT/scripts/archive_completed.sh"
    [ "$status" -eq 0 ]

    # report should still be in queue/reports/ (not archived)
    [ -f "$TEST_PROJECT/queue/reports/saizo_report_cmd_999.yaml" ]
}
