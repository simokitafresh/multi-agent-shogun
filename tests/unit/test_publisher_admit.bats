#!/usr/bin/env bats
# test_publisher_admit.bats — 単一 publisher 化 U5
# (scripts/publisher_admit.sh、scripts/publisher_queue.sh の enqueue 前 admit gate、
#  scripts/review_approval.sh の karo:ACCEPT --migration-ack option)
#
# test_necessity: LGTM+ACCEPT 未承認の request が queue に投入されないこと、kind=doc の
# 将軍投入が identity+path allowlist(docs/ context/ queue/shogun_todo_map.md)外へ漏れないこと、
# backend/app/db/ 配下を含む request が migration_ack 無しで admit されないこと(R13)、
# migration_ack は review_approval.sh の karo:ACCEPT --migration-ack option だけが書くことを
# 二値で固定する。設計書 docs/research/single_publisher_asis_tobe_5w1h_20260902.md §9.1 U5 / §4 R13。
#
# STATE_DIRはH2によりtracked repo root配下・/tmp配下が起動拒否(rc=2)対象のため、
# fixtureは$HOME配下(repo外・/tmp外)にmktemp -d --tmpdir=$HOMEで作る(test_publisher_queue.bats同型)。

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    FIXTURE_ROOT="$(mktemp -d --tmpdir="$HOME" publisher_admit_bats_root.XXXXXX)"
    mkdir -p "$FIXTURE_ROOT/scripts/lib" "$FIXTURE_ROOT/queue/reports"
    cp "$PROJECT_ROOT/scripts/publisher_admit.sh" "$FIXTURE_ROOT/scripts/publisher_admit.sh"
    cp "$PROJECT_ROOT/scripts/publisher_queue.sh" "$FIXTURE_ROOT/scripts/publisher_queue.sh"
    cp "$PROJECT_ROOT/scripts/lib/review_approval.sh" "$FIXTURE_ROOT/scripts/lib/review_approval.sh"
    cp "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$FIXTURE_ROOT/scripts/lib/yaml_field_set.sh"
    cp "$PROJECT_ROOT/scripts/lib/publisher_event.sh" "$FIXTURE_ROOT/scripts/lib/publisher_event.sh"
    cat > "$FIXTURE_ROOT/scripts/inbox_write.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${INBOX_WRITE_STUB_LOG:-/dev/null}"
exit 0
STUB
    chmod +x "$FIXTURE_ROOT/scripts/publisher_admit.sh" "$FIXTURE_ROOT/scripts/publisher_queue.sh" \
        "$FIXTURE_ROOT/scripts/lib/publisher_event.sh" "$FIXTURE_ROOT/scripts/inbox_write.sh"

    STATE_DIR="$(mktemp -d --tmpdir="$HOME" publisher_admit_bats_state.XXXXXX)"
    export SHOGUN_STATE_DIR="$STATE_DIR"
    export INBOX_WRITE_STUB_LOG="$FIXTURE_ROOT/inbox_stub.log"
    : > "$INBOX_WRITE_STUB_LOG"

    ADMIT="$FIXTURE_ROOT/scripts/publisher_admit.sh"
    PQ="$FIXTURE_ROOT/scripts/publisher_queue.sh"
}

teardown() {
    [ -n "$FIXTURE_ROOT" ] && find "$FIXTURE_ROOT" -depth -delete 2>/dev/null
    [ -n "$STATE_DIR" ] && find "$STATE_DIR" -depth -delete 2>/dev/null
    [ -n "$TRIGGER_ROOT" ] && find "$TRIGGER_ROOT" -depth -delete 2>/dev/null
    [ -n "$TRIGGER_STATE_DIR" ] && find "$TRIGGER_STATE_DIR" -depth -delete 2>/dev/null
    true
}

# review_report_key() と同一アルゴリズム(sha256 of "queue/reports/<basename>")。
# 正本(scripts/lib/review_approval.sh)を二重実装せず、admit/review_approval.shが
# 同じkeyを導出することをここでも同一計算式で検証する。
rkey() {
    printf '%s' "queue/reports/$(basename "$1")" | sha256sum | awk '{print $1}'
}

make_approval() {
    local cmd_id="$1" req="$2" dir
    dir="$FIXTURE_ROOT/queue/gates/$cmd_id/review_approvals/reports/$(rkey "$req")"
    mkdir -p "$dir"
    printf 'timestamp: t\nrole: gunshi\nresult: LGTM\n' > "$dir/gunshi.yaml"
    printf 'timestamp: t\nrole: karo\nresult: ACCEPT\n' > "$dir/karo.yaml"
    printf '%s\n' "$dir"
}

queue_count() {
    find "$STATE_DIR/publish_queue" -maxdepth 1 -type f -name '*.request' 2>/dev/null | wc -l | tr -d ' '
}

# ---- unit-level admit() 契約(AC1) ----

@test "missing approvals reject admission with rc=5 and enqueue never runs" {
    req="$FIXTURE_ROOT/queue/reports/req_missing.yaml"
    cat > "$req" <<'REQ'
cmd_id: cmd_missing
task_id: cmd_missing_full
kind: code
paths:
  - scripts/foo.sh
REQ
    run bash "$ADMIT" admit "$req"
    [ "$status" -eq 5 ]
    dir="$FIXTURE_ROOT/queue/gates/cmd_missing/review_approvals/reports/$(rkey "$req")"
    [ ! -f "$dir/gunshi.yaml" ]
    [ ! -f "$dir/karo.yaml" ]

    run bash "$PQ" enqueue "$req"
    [ "$status" -eq 5 ]
    [ "$(queue_count)" -eq 0 ]
}

@test "approved code-kind request is admitted with rc=0 and enqueue publishes one request" {
    req="$FIXTURE_ROOT/queue/reports/req_ok.yaml"
    cat > "$req" <<'REQ'
cmd_id: cmd_ok
task_id: cmd_ok_full
kind: code
paths:
  - scripts/foo.sh
REQ
    make_approval cmd_ok "$req" >/dev/null
    run bash "$ADMIT" admit "$req"
    [ "$status" -eq 0 ]
    run bash "$PQ" enqueue "$req"
    [ "$status" -eq 0 ]
    [ "$(queue_count)" -eq 1 ]
}

@test "kind doc path outside the shogun allowlist is rejected with rc=6" {
    req="$FIXTURE_ROOT/queue/reports/req_doc_bad.yaml"
    cat > "$req" <<'REQ'
cmd_id: cmd_doc_bad
task_id: cmd_doc_bad_full
kind: doc
paths:
  - scripts/foo.sh
REQ
    make_approval cmd_doc_bad "$req" >/dev/null
    run bash "$ADMIT" admit "$req"
    [ "$status" -eq 6 ]
}

@test "kind doc path inside the shogun allowlist is admitted with rc=0" {
    req="$FIXTURE_ROOT/queue/reports/req_doc_ok.yaml"
    cat > "$req" <<'REQ'
cmd_id: cmd_doc_ok
task_id: cmd_doc_ok_full
kind: doc
paths:
  - docs/research/foo.md
  - context/bar.md
  - queue/shogun_todo_map.md
REQ
    make_approval cmd_doc_ok "$req" >/dev/null
    run bash "$ADMIT" admit "$req"
    [ "$status" -eq 0 ]
}

@test "backend/app/db path without migration_ack is rejected and records r13_reject" {
    req="$FIXTURE_ROOT/queue/reports/req_r13.yaml"
    cat > "$req" <<'REQ'
cmd_id: cmd_r13
task_id: cmd_r13_full
kind: code
paths:
  - backend/app/db/models.py
REQ
    make_approval cmd_r13 "$req" >/dev/null
    run bash "$ADMIT" admit "$req"
    [ "$status" -eq 11 ]
    grep -q '^db_migration: true$' "$req"
    [ "$(grep -c '"kind":"r13_reject"' "$STATE_DIR/publish_queue/events.jsonl")" -eq 1 ]
    [ "$(wc -l < "$INBOX_WRITE_STUB_LOG" | tr -d ' ')" -eq 1 ]
    grep -q '^karo ' "$INBOX_WRITE_STUB_LOG"
}

@test "backend/app/db path with migration_ack present in karo.yaml is admitted with rc=0" {
    req="$FIXTURE_ROOT/queue/reports/req_r13_ack.yaml"
    cat > "$req" <<'REQ'
cmd_id: cmd_r13_ack
task_id: cmd_r13_ack_full
kind: code
paths:
  - backend/app/db/models.py
REQ
    dir=$(make_approval cmd_r13_ack "$req")
    printf 'timestamp: t\nrole: karo\nresult: ACCEPT\nmigration_ack: irreversible_accepted\n' > "$dir/karo.yaml"
    run bash "$ADMIT" admit "$req"
    [ "$status" -eq 0 ]
}

# ---- scripts/review_approval.sh 統合契約(AC2) ----
# setup_trigger_fixtureはtests/unit/test_review_approval.bats記載の実装cmdレビュー承認
# fixtureと同型(scripts/lib一式をsymlinkし、review_approval.sh自体を隔離rootで動かす)。

setup_trigger_fixture() {
    TRIGGER_ROOT="$BATS_TEST_TMPDIR/publisher-admit-trigger-root"
    mkdir -p "$TRIGGER_ROOT/queue/reports" "$TRIGGER_ROOT/queue/archive/reports" \
        "$TRIGGER_ROOT/queue/tasks" "$TRIGGER_ROOT/queue/gates" "$TRIGGER_ROOT/scripts" \
        "$TRIGGER_ROOT/logs"
    ln -s "$PROJECT_ROOT/scripts/review_approval.sh" "$TRIGGER_ROOT/scripts/review_approval.sh"
    ln -s "$PROJECT_ROOT/scripts/lib" "$TRIGGER_ROOT/scripts/lib"
    cp "$PROJECT_ROOT/scripts/publisher_queue.sh" "$TRIGGER_ROOT/scripts/publisher_queue.sh"
    cp "$PROJECT_ROOT/scripts/publisher_admit.sh" "$TRIGGER_ROOT/scripts/publisher_admit.sh"
    chmod +x "$TRIGGER_ROOT/scripts/publisher_queue.sh" "$TRIGGER_ROOT/scripts/publisher_admit.sh"
    cat > "$TRIGGER_ROOT/scripts/cmd_complete_gate.sh" <<'GATE'
#!/usr/bin/env bash
exit 0
GATE
    chmod +x "$TRIGGER_ROOT/scripts/cmd_complete_gate.sh"
    cat > "$TRIGGER_ROOT/queue/tasks/worker.yaml" <<'TASK'
task:
  task_id: cmd_trigger_full
  parent_cmd: cmd_trigger
  report_filename: worker_report_cmd_trigger.yaml
  task_type: full
TASK
    cat > "$TRIGGER_ROOT/queue/reports/worker_report_cmd_trigger.yaml" <<'REPORT'
worker_id: worker
task_id: cmd_trigger_full
report_id: rpt-trigger
report_identity_version: 2
parent_cmd: cmd_trigger
status: completed
verdict: PASS
commit_hash: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
result:
  summary: trigger fixture
REPORT
    export REVIEW_APPROVAL_ROOT="$TRIGGER_ROOT"
    export REVIEW_APPROVAL_NO_NOTIFY=1
    TRIGGER_STATE_DIR="$(mktemp -d --tmpdir="$HOME" publisher_admit_bats_trigger_state.XXXXXX)"
    export SHOGUN_STATE_DIR="$TRIGGER_STATE_DIR"
}

trigger_queue_count() {
    find "$TRIGGER_STATE_DIR/publish_queue" -maxdepth 1 -type f -name '*.request' 2>/dev/null | wc -l | tr -d ' '
}

@test "review_approval karo ACCEPT --migration-ack writes migration_ack and the report is then admitted" {
    setup_trigger_fixture
    report="$TRIGGER_ROOT/queue/reports/worker_report_cmd_trigger.yaml"
    REVIEW_APPROVAL_SKIP_LEDGER_CHECK=1 bash "$TRIGGER_ROOT/scripts/review_approval.sh" cmd_trigger gunshi LGTM "$report"
    run bash "$TRIGGER_ROOT/scripts/review_approval.sh" cmd_trigger karo ACCEPT "$report" --migration-ack irreversible_accepted
    [ "$status" -eq 0 ]
    dir="$TRIGGER_ROOT/queue/gates/cmd_trigger/review_approvals/reports/$(rkey "$report")"
    grep -q '^migration_ack: irreversible_accepted$' "$dir/karo.yaml"
    run bash "$TRIGGER_ROOT/scripts/publisher_admit.sh" admit "$report"
    [ "$status" -eq 0 ]
    [ "$(trigger_queue_count)" -eq 1 ]
}

@test "review_approval karo ACCEPT without the option does not write migration_ack" {
    setup_trigger_fixture
    report="$TRIGGER_ROOT/queue/reports/worker_report_cmd_trigger.yaml"
    REVIEW_APPROVAL_SKIP_LEDGER_CHECK=1 bash "$TRIGGER_ROOT/scripts/review_approval.sh" cmd_trigger gunshi LGTM "$report"
    run bash "$TRIGGER_ROOT/scripts/review_approval.sh" cmd_trigger karo ACCEPT "$report"
    [ "$status" -eq 0 ]
    dir="$TRIGGER_ROOT/queue/gates/cmd_trigger/review_approvals/reports/$(rkey "$report")"
    run grep -c '^migration_ack:' "$dir/karo.yaml"
    [ "$status" -eq 1 ]
    [ "$output" -eq 0 ]
    [ "$(trigger_queue_count)" -eq 1 ]
}
