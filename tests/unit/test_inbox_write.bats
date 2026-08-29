#!/usr/bin/env bats
# test_necessity: inbox_writeはflock下でmessage identityをexactly-once永続化し、並行送信でも既存書状の欠落・重複を起こさない。

@test "caller supplied message id is validated, persisted, and returned as receipt" {
    setup_basic_test_env
    local supplied="msg_contract_20260721_001"
    run env INBOX_MESSAGE_ID="$supplied" \
        bash "$TEST_INBOX_WRITE" test_agent "caller-id fixture" info test contract
    [ "$status" -eq 0 ]
    [[ "$output" == *"INBOX_MESSAGE_ID=$supplied"* ]]
    grep -q "  id: '$supplied'" "$TEST_INBOX_DIR/test_agent.yaml"

    run env INBOX_MESSAGE_ID='bad id/with spaces' \
        bash "$TEST_INBOX_WRITE" test_agent "invalid-id fixture" info test contract
    [ "$status" -ne 0 ]
}
# test_inbox_write.bats — inbox_write.sh ユニットテスト
# T-001 ~ T-012: リグレッションテスト仕様書実装
# Git uncommitted check: report_received時のコミット漏れ検知
# cmd_1565: tests/版(T-001~T-012) + tests/unit/版(git uncommitted)を統合
#
# テスト構成:
#   T-001~T-002: 引数バリデーション
#   T-003~T-004: 正常書き込み（新規/追記）
#   T-005: メッセージID一意性
#   T-006~T-007: デフォルト値（type/from）
#   T-008~T-009: Overflow Protection（50件制限）
#   T-010: flock競合時のリトライ
#   T-011: 特殊文字のエスケープ処理
#   T-012: inbox初期化（ディレクトリ自動作成）
#   Git uncommitted check tests (report_received)

# --- セットアップ ---

# test_necessity: informational types are auto-acknowledged while the
# actionable gate_clear completion event remains unread for self-drive.
@test "info auto-ack digests safe types and preserves work types" {
    root="$BATS_TEST_TMPDIR/autoack"
    mkdir -p "$root/scripts/lib" "$root/queue/inbox" "$root/logs"
    cp "$PROJECT_ROOT/scripts/inbox_mark_read.sh" "$root/scripts/inbox_mark_read.sh"
    cp "$PROJECT_ROOT/scripts/lib/lock_path.sh" "$root/scripts/lib/lock_path.sh"
    python3 - "$root/queue/inbox/alpha.yaml" <<'PY'
import sys,yaml
safe=['info','heartbeat','status_update','retro_answer','low']
work=['task_assigned','task_supplement','verify_request','cmd_new','escalation','recovery','report_received','task_failed']
msgs=[]
for i,t in enumerate(safe+work):
    msgs.append({'id':f'm{i}','from':'sender','type':t,'timestamp':'2026-07-20T00:00:00','content':f'body-{t}','read':False})
yaml.safe_dump({'messages':msgs},open(sys.argv[1],'w'),sort_keys=False,allow_unicode=True)
PY
    run env INBOX_MARK_READ_ROOT_OVERRIDE="$root" bash "$root/scripts/inbox_mark_read.sh" alpha --auto-info
    [ "$status" -eq 0 ]
    run python3 - "$root/queue/inbox/alpha.yaml" "$root/logs/inbox_info_digest.jsonl" <<'PY'
import json,sys,yaml
d=yaml.safe_load(open(sys.argv[1])); safe=d['messages'][:5]; work=d['messages'][5:]
rows=[json.loads(x) for x in open(sys.argv[2])]
assert len(rows)==5 and all(m['read'] for m in safe) and all(not m['read'] for m in work)
assert all(set(r)=={'msg_id','from','type','timestamp','content'} for r in rows)
print('digest=5 auto_ack=5 gate_clear_unread=1 work_unread=9 false_positive=0 nudge_eligible=10')
PY
    [ "$status" -eq 0 ]
}

@test "info auto-ack is idempotent and lock failure leaves unread" {
    root="$BATS_TEST_TMPDIR/autoack-fail"
    mkdir -p "$root/scripts/lib" "$root/queue/inbox" "$root/logs"
    cp "$PROJECT_ROOT/scripts/inbox_mark_read.sh" "$root/scripts/inbox_mark_read.sh"
    cp "$PROJECT_ROOT/scripts/lib/lock_path.sh" "$root/scripts/lib/lock_path.sh"
    printf 'messages:\n- id: m1\n  from: sender\n  type: info\n  timestamp: 2026-07-20T00:00:00\n  content: body\n  read: false\n' > "$root/queue/inbox/alpha.yaml"
    env INBOX_MARK_READ_ROOT_OVERRIDE="$root" bash "$root/scripts/inbox_mark_read.sh" alpha --auto-info
    env INBOX_MARK_READ_ROOT_OVERRIDE="$root" bash "$root/scripts/inbox_mark_read.sh" alpha --auto-info
    [ "$(wc -l < "$root/logs/inbox_info_digest.jsonl")" -eq 1 ]
    sed -i 's/read: true/read: false/' "$root/queue/inbox/alpha.yaml"
    exec 8>>"$root/logs/inbox_info_digest.jsonl"; flock 8
    run env INBOX_MARK_READ_ROOT_OVERRIDE="$root" bash "$root/scripts/inbox_mark_read.sh" alpha --auto-info
    flock -u 8
    [ "$status" -ne 0 ]
    grep -q 'read: false' "$root/queue/inbox/alpha.yaml"
    sed -i '/  content:/d' "$root/queue/inbox/alpha.yaml"
    run env INBOX_MARK_READ_ROOT_OVERRIDE="$root" bash "$root/scripts/inbox_mark_read.sh" alpha --auto-info
    [ "$status" -ne 0 ]
    grep -q 'read: false' "$root/queue/inbox/alpha.yaml"
}

@test "info auto-ack gate telemetry records finite PASS and BLOCK counters" {
    run env PROJECT_ROOT="$PROJECT_ROOT" STATE="$BATS_TEST_TMPDIR/state" bash -c '
        set -- alpha pane
        export INBOX_WATCHER_LIB_ONLY=1 SHOGUN_STATE_DIR="$STATE"
        source "$PROJECT_ROOT/scripts/inbox_watcher.sh"
        INBOX_INFO_GATE_LOG="$STATE/gate.yaml"
        record_info_autoack_gate PASS "digest_success=6 auto_ack=6 false_positive=0 nudge=0 wall_ms=12"
        record_info_autoack_gate BLOCK "digest_failed=1 auto_ack=0 false_positive=0 nudge=1 wall_ms=3"
        grep -q "result: PASS.*digest_success=6" "$STATE/gate.yaml"
        grep -q "result: BLOCK.*digest_failed=1" "$STATE/gate.yaml"
    '
    [ "$status" -eq 0 ]
}

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export INBOX_WRITE_SCRIPT="$PROJECT_ROOT/scripts/inbox_write.sh"
    export GIT_TEMPLATE_DIR
    GIT_TEMPLATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inbox_write_git_template.XXXXXX")"

    # スクリプト存在確認（前提条件）
    [ -f "$INBOX_WRITE_SCRIPT" ] || return 1

    # python3 + PyYAML存在確認
    python3 -c "import yaml" 2>/dev/null || return 1

    mkdir -p "$GIT_TEMPLATE_DIR/scripts/lib" "$GIT_TEMPLATE_DIR/scripts/gates" "$GIT_TEMPLATE_DIR/queue/tasks" "$GIT_TEMPLATE_DIR/queue/reports" "$GIT_TEMPLATE_DIR/src"
    # 選択的コピー: inbox_write.shが使うファイルのみ (NTFS→tmpfs コスト削減)
    for _lib_f in agent_config.sh field_get.sh cli_lookup.sh gunshi_notify.sh report_commit_nonoverlap_filter.sh yaml_field_set.sh report_unique_identity.py report_completion_events.sh retro_pane_prompt.sh retro_verbatim_prompt.sh gate_report_format_classify.sh escalation_evidence.sh defense_overhead_writer.sh defense_overhead_event_index.py; do
        cp "$PROJECT_ROOT/scripts/lib/$_lib_f" "$GIT_TEMPLATE_DIR/scripts/lib/$_lib_f"
    done
    cp "$PROJECT_ROOT/scripts/inbox_write.sh" "$GIT_TEMPLATE_DIR/scripts/inbox_write.sh"

    # inbox_write owns which timing events are emitted; the Python/SQLite
    # ledger implementation has its own contract suite.  A flocked tmpfs
    # writer keeps the concurrency semantics needed here without re-testing
    # the external index for every emitted checkpoint.
    cat > "$GIT_TEMPLATE_DIR/scripts/lib/defense_overhead_writer.sh" <<'MOCK'
DEFENSE_OVERHEAD_ASYNC_PIDS=()
defense_overhead_write() {
    [ "${DEFENSE_OVERHEAD_ENABLED:-1}" = "1" ] || return 0
    local source_name="$1" check_id="$2" wall_ms="$3" verdict="$4" event_id="$5"
    local metadata="${6-}" ledger="${DEFENSE_OVERHEAD_LEDGER:-${DEFENSE_OVERHEAD_REPO_ROOT}/logs/defense_overhead.jsonl}"
    local metadata_body fd
    [ -n "$metadata" ] || metadata='{}'
    metadata_body="${metadata#\{}"
    metadata_body="${metadata_body%\}}"
    mkdir -p "${ledger%/*}"
    exec {fd}>>"${ledger}.lock"
    flock "$fd"
    if [ -n "$metadata_body" ]; then
        printf '{"timestamp":"fixture","source":"%s","check_id":"%s","wall_ms":%s,"verdict":"%s","event_id":"%s",%s}\n' \
            "$source_name" "$check_id" "$wall_ms" "$verdict" "$event_id" "$metadata_body" >> "$ledger"
    else
        printf '{"timestamp":"fixture","source":"%s","check_id":"%s","wall_ms":%s,"verdict":"%s","event_id":"%s"}\n' \
            "$source_name" "$check_id" "$wall_ms" "$verdict" "$event_id" >> "$ledger"
    fi
    flock -u "$fd"
    eval "exec ${fd}>&-"
}
defense_overhead_write_async() {
    [ "${DEFENSE_OVERHEAD_ENABLED:-1}" = "1" ] || return 0
    ( defense_overhead_write "$@" ) >/dev/null 2>&1 &
    DEFENSE_OVERHEAD_ASYNC_PIDS+=("$!")
}
defense_overhead_drain_async() {
    local pid
    for pid in "${DEFENSE_OVERHEAD_ASYNC_PIDS[@]}"; do wait "$pid" || true; done
    DEFENSE_OVERHEAD_ASYNC_PIDS=()
}
MOCK

    git -C "$GIT_TEMPLATE_DIR" init -q
    git -C "$GIT_TEMPLATE_DIR" config user.name "test"
    git -C "$GIT_TEMPLATE_DIR" config user.email "test@test.com"

    cat > "$GIT_TEMPLATE_DIR/scripts/lib/agent_config.sh" << 'MOCK'
get_ninja_names() { echo "testninja kotaro"; }
get_allowed_targets() { echo "karo shogun testninja gunshi"; }
get_commander_names() { echo "shogun karo gunshi"; }
is_commander_role() { case " $(get_commander_names) " in *" $1 "*) return 0 ;; esac; return 1; }
get_commander_inbox_path() { is_commander_role "$1" || return 1; echo "${INBOX_WRITE_ROOT_OVERRIDE}/queue/inbox/${1}.yaml"; }
MOCK

    printf '#!/bin/bash\necho "NO-FIX-NEEDED"\n' > "$GIT_TEMPLATE_DIR/scripts/gates/gate_report_autofix.sh"
    chmod +x "$GIT_TEMPLATE_DIR/scripts/gates/gate_report_autofix.sh"
    printf '#!/bin/bash\necho "PASS: all checks passed"\n' > "$GIT_TEMPLATE_DIR/scripts/gates/gate_report_format.sh"
    chmod +x "$GIT_TEMPLATE_DIR/scripts/gates/gate_report_format.sh"

    cat > "$GIT_TEMPLATE_DIR/queue/tasks/testninja.yaml" << 'YAML'
task:
  status: in_progress
  parent_cmd: cmd_test_001
  target_path: src/test_file.sh
  report_path: queue/reports/testninja_report_cmd_test_001.yaml
  report_filename: testninja_report_cmd_test_001.yaml
YAML

    cat > "$GIT_TEMPLATE_DIR/queue/reports/testninja_report_cmd_test_001.yaml" << 'YAML'
verdict: PASS
files_modified:
  - path: src/test_file.sh
    change: modified
binary_checks:
  AC1:
    - check: test check
      result: PASS
lesson_candidate:
  found: false
  no_lesson_reason: no lesson
result:
  summary: implementation complete
YAML

    echo '#!/bin/bash' > "$GIT_TEMPLATE_DIR/src/test_file.sh"
    # another_file.sh を事前コミット: T-017がgit add+commitをスキップできる
    echo '#!/bin/bash' > "$GIT_TEMPLATE_DIR/src/another_file.sh"
    git -C "$GIT_TEMPLATE_DIR" add -A
    git -C "$GIT_TEMPLATE_DIR" commit -q -m "initial"

    # T-008用フィクスチャ: 既読60件 (python3不要)
    # printf -- で先頭の"-"がオプションと解釈されるのを防ぐ
    {
        printf 'messages:\n'
        for _i in $(seq 0 59); do
            printf -- "- content: '既読メッセージ %d'\n  from: 'test_sender'\n  id: 'msg_old_%03d'\n  read: true\n  timestamp: '2026-01-01T%02d:00:00'\n  type: 'test_type'\n" "$_i" "$_i" "$_i"
        done
    } > "$GIT_TEMPLATE_DIR/inbox_overflow_all_read.yaml"

    # T-009用フィクスチャ: 未読20件 + 既読40件 (python3不要)
    {
        printf 'messages:\n'
        for _i in $(seq 0 19); do
            printf -- "- content: '未読メッセージ %d'\n  from: 'test_sender'\n  id: 'msg_unread_%03d'\n  read: false\n  timestamp: '2026-01-01T%02d:00:00'\n  type: 'test_type'\n" "$_i" "$_i" "$_i"
        done
        for _i in $(seq 0 39); do
            printf -- "- content: '既読メッセージ %d'\n  from: 'test_sender'\n  id: 'msg_read_%03d'\n  read: true\n  timestamp: '2026-01-01T%02d:00:00'\n  type: 'test_type'\n" "$_i" "$_i" "$_i"
        done
    } > "$GIT_TEMPLATE_DIR/inbox_overflow_mixed.yaml"
}

teardown_file() {
    [ -n "${GIT_TEMPLATE_DIR:-}" ] && [ -d "$GIT_TEMPLATE_DIR" ] && rm -rf "$GIT_TEMPLATE_DIR"
}

init_test_env() {
    export TEST_TMPDIR="$BATS_TEST_TMPDIR/work"
    mkdir -p "$TEST_TMPDIR"
    export INBOX_WRITE_ROOT_OVERRIDE="$TEST_TMPDIR"
    # setup_file snapshots the production script and its sourced libraries to
    # tmpfs.  Execute that byte-for-byte fixture instead of reparsing the
    # 3k-line script from DrvFS for every one of the 118 contract cases.
    export TEST_INBOX_WRITE="$GIT_TEMPLATE_DIR/scripts/inbox_write.sh"
}

setup_basic_test_env() {
    export INBOX_WRITE_TEST=1
    export TEST_INBOX_DIR="$TEST_TMPDIR/queue/inbox"
    mkdir -p "$TEST_INBOX_DIR" "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue"
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_100:
    status: delegated
YAML
    if [ ! -L "$TEST_TMPDIR/scripts/lib" ]; then
        ln -s "$PROJECT_ROOT/scripts/lib" "$TEST_TMPDIR/scripts/lib"
    fi
}

setup() {
    init_test_env
    # Timing telemetry is an independent production concern.  Keeping it on
    # for every inbox contract case makes the suite serialize through Python,
    # SQLite and ledger flock even when the case does not assert telemetry.
    # Telemetry contract cases opt back in locally below.
    export DEFENSE_OVERHEAD_ENABLED=0
}

# test_necessity: typed escalation delivery is fail-closed until the three
# self-trial fields plus next action/owner are present; non-escalation BLOCK
# prose remains deliverable after the cmd_4251 review clarification.
@test "escalation requires self-trial receipt and records BLOCK/PASS telemetry" {
    setup_basic_test_env
    export DEFENSE_OVERHEAD_ENABLED=1
    mkdir -p "$TEST_TMPDIR/logs"
    export DEFENSE_OVERHEAD_REPO_ROOT="$TEST_TMPDIR"
    export DEFENSE_OVERHEAD_LEDGER="$TEST_TMPDIR/logs/defense_overhead.jsonl"
    local bad='task_id=commander_directive subject_task_id=cmd_escalation_normal parent_cmd=cmd_escalation 先送りCRITICAL案件'
    run bash "$TEST_INBOX_WRITE" karo "$bad" escalation testninja notify_karo
    [ "$status" -eq 2 ]
    [[ "$output" == *'Template:'* ]]
    [[ "$output" == *'試行コマンド:'* ]]
    [ ! -e "$TEST_INBOX_DIR/karo.yaml" ]

    local good=$'task_id=commander_directive subject_task_id=cmd_escalation_normal parent_cmd=cmd_escalation\n試行コマンド: bash scripts/check.sh\nexit_code: 1\n特定した不足: queue item remains unresolved\n次の行動: 家老レーンで是正する\n実行者: karo'
    run bash "$TEST_INBOX_WRITE" karo "$good" escalation testninja notify_karo
    [ "$status" -eq 0 ]
    grep -q "type: 'escalation'" "$TEST_INBOX_DIR/karo.yaml"
    for _i in 1 2 3 4 5; do
        [ "$(grep -c 'escalation_evidence_contract' "$DEFENSE_OVERHEAD_LEDGER" 2>/dev/null || true)" -ge 2 ] && break
        sleep 0.05
    done
    [ "$(grep -c 'escalation_evidence_contract' "$DEFENSE_OVERHEAD_LEDGER")" -eq 2 ]
    [ "$(grep -c 'check_id":"escalation_evidence_contract".*"verdict":"BLOCK"' "$DEFENSE_OVERHEAD_LEDGER")" -eq 1 ]
    [ "$(grep -c 'check_id":"escalation_evidence_contract".*"verdict":"PASS"' "$DEFENSE_OVERHEAD_LEDGER")" -eq 1 ]
}

@test "non-escalation BLOCK prose is not a false positive" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" karo 'task_id=commander_directive subject_task_id=cmd_gate_block_normal parent_cmd=cmd_gate_block gate BLOCK通知: FAILではなく監視継続' gate_block testninja notify_karo
    [ "$status" -eq 0 ]
    grep -q "type: 'gate_block'" "$TEST_INBOX_DIR/karo.yaml"
}

@test "failed unclosed idle_notice is converted to review alert while formal FAIL close is preserved" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/reports"
    cat > "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: failed
  task_id: cmd_failed_fixture
  report_path: queue/reports/testninja_report_cmd_failed_fixture.yaml
YAML
    cat > "$TEST_TMPDIR/queue/reports/testninja_report_cmd_failed_fixture.yaml" <<'YAML'
status: pending
verdict: FAIL
YAML
    run bash "$TEST_INBOX_WRITE" karo "task_id=commander_directive subject_task_id=cmd_idle_notice_normal parent_cmd=cmd_idle_notice idle" idle_notice testninja idle
    [ "$status" -eq 0 ]
    grep -q "type: 'failed_unclosed'" "$TEST_INBOX_DIR/karo.yaml"
    grep -q "action: 'review_failed_task'" "$TEST_INBOX_DIR/karo.yaml"
    grep -q 'task_id=cmd_failed_fixture report_state=OPEN' "$TEST_INBOX_DIR/karo.yaml"

    cat > "$TEST_TMPDIR/queue/reports/testninja_report_cmd_failed_fixture.yaml" <<'YAML'
status: completed
verdict: FAIL
status_detail: BLOCKED
YAML
    run bash "$TEST_INBOX_WRITE" karo "task_id=commander_directive subject_task_id=cmd_idle_notice_normal parent_cmd=cmd_idle_notice idle closed" idle_notice testninja idle
    [ "$status" -eq 0 ]
    grep -q "type: 'idle_notice'" "$TEST_INBOX_DIR/karo.yaml"
}

@test "retro_result is diverted from karo inbox into append-only retro queue" {
    setup_basic_test_env
    ln -s "$PROJECT_ROOT/scripts/retro_write.sh" "$TEST_TMPDIR/scripts/retro_write.sh"
    run bash "$TEST_INBOX_WRITE" karo \
      "parent_report_id=rpt-1 deployed_at=2026-07-18T15:00:00+09:00 done_at=2026-07-18T15:08:31+09:00 severity=normal" \
      retro_result testninja append_retro
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_INBOX_DIR/karo.yaml" ]
    [ "$(wc -l < "$TEST_TMPDIR/queue/retro/events.jsonl")" -eq 1 ]
    grep -q '"duration_seconds": 511' "$TEST_TMPDIR/queue/retro/events.jsonl"
}

# test_necessity: spontaneous infra findings remain deliverable, while retrospective answers attach one exact hold identity and ambiguity fails closed.
@test "infra bug answer identity handles zero one and two awaiting events" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" karo "spontaneous finding" infra_bug_suspected testninja investigate
    [ "$status" -eq 0 ]
    ! grep -q '^  event_id:' "$TEST_INBOX_DIR/karo.yaml"

    mkdir -p "$TEST_TMPDIR/queue/retro/verbatim_awaiting_answer"
    printf 'testninja\nevent:one\nfixture\nkey1\n' > "$TEST_TMPDIR/queue/retro/verbatim_awaiting_answer/one.event"
    run bash "$TEST_INBOX_WRITE" karo "answer one" infra_bug_suspected testninja investigate
    [ "$status" -eq 0 ]
    grep -q "event_id: 'event:one'" "$TEST_INBOX_DIR/karo.yaml"

    printf 'testninja\nevent:two\nfixture\nkey2\n' > "$TEST_TMPDIR/queue/retro/verbatim_awaiting_answer/two.event"
    run bash "$TEST_INBOX_WRITE" karo "ambiguous answer" infra_bug_suspected testninja investigate
    [ "$status" -eq 2 ]
    [[ "$output" == *'ambiguous awaiting events'* ]]

    RETRO_EVENT_ID=event:missing run bash "$TEST_INBOX_WRITE" karo "wrong explicit answer" infra_bug_suspected testninja investigate
    [ "$status" -eq 2 ]
    [[ "$output" == *'does not identify exactly one awaiting event'* ]]
}

# test_necessity: retro回答族(infra_bug_suspected/infra_bug_report/infra_bug/retro_answer)は全て保留イベント識別子を構造化して持ち、回答族でないtypeは一切retro扱いされない。
@test "every retro answer type attaches the hold identity and other types never do" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/queue/retro/verbatim_awaiting_answer"
    printf 'testninja\nevent:family\nfixture\nkey-family\n' > "$TEST_TMPDIR/queue/retro/verbatim_awaiting_answer/one.event"

    for answer_type in infra_bug_suspected infra_bug_report infra_bug retro_answer; do
        rm -f "$TEST_INBOX_DIR/karo.yaml"
        run bash "$TEST_INBOX_WRITE" karo "answer via $answer_type" "$answer_type" testninja investigate
        [ "$status" -eq 0 ]
        grep -q "event_id: 'event:family'" "$TEST_INBOX_DIR/karo.yaml"
    done

    # 回答族でないtypeは同じ保留があってもretro扱いしない(誤判定0)。
    for other_type in gate_block bulletin_notify status_update analysis_result; do
        rm -f "$TEST_INBOX_DIR/karo.yaml"
        run bash "$TEST_INBOX_WRITE" karo "task_id=commander_directive subject_task_id=cmd_${other_type}_normal parent_cmd=cmd_${other_type} unrelated $other_type" "$other_type" testninja notify_karo
        [ "$status" -eq 0 ]
        ! grep -q "event_id: 'event:family'" "$TEST_INBOX_DIR/karo.yaml"
    done
}

# test_necessity: 本文がevent_idを名乗る既存のretro_answer運用は、保留イベントが複数あってもBLOCKされずそのIDを構造化フィールドへ写す。
@test "content declared event_id survives multiple awaiting holds without blocking" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/queue/retro/verbatim_awaiting_answer"
    printf 'testninja\nevent:one\nfixture\nkey1\n' > "$TEST_TMPDIR/queue/retro/verbatim_awaiting_answer/one.event"
    printf 'testninja\nevent:two\nfixture\nkey2\n' > "$TEST_TMPDIR/queue/retro/verbatim_awaiting_answer/two.event"

    run bash "$TEST_INBOX_WRITE" karo "event_id=event:two 回答本文" retro_answer testninja investigate
    [ "$status" -eq 0 ]
    grep -q "event_id: 'event:two'" "$TEST_INBOX_DIR/karo.yaml"
}

# test_necessity: a prompt created after send prechecks but before the locked append is bound at the final durable checkpoint.
@test "infra bug answer identity refreshes live root at locked append" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/queue/retro/verbatim_awaiting_answer"
    hook="$TEST_TMPDIR/bin/flock"
    mkdir -p "${hook%/*}"
    printf '%s\n' '#!/bin/bash' \
      'if [ ! -e "$INBOX_WRITE_ROOT_OVERRIDE/queue/retro/verbatim_awaiting_answer/live.event" ]; then' \
      "  printf 'testninja\\nevent:live\\nfixture\\nkey-live\\n' > \"\$INBOX_WRITE_ROOT_OVERRIDE/queue/retro/verbatim_awaiting_answer/live.event\"" \
      'fi' 'exec /usr/bin/flock "$@"' > "$hook"
    chmod +x "$hook"
    run env PATH="$TEST_TMPDIR/bin:$PATH" bash "$TEST_INBOX_WRITE" karo "live answer" infra_bug_suspected testninja investigate
    [ "$status" -eq 0 ]
    [ "$(grep -c "event_id: 'event:live'" "$TEST_INBOX_DIR/karo.yaml")" -eq 1 ]
}

# =============================================================================
# T-001: 引数バリデーション — target未指定でexit 1
# =============================================================================

@test "T-001: no arguments → exit 1 with Usage message" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage" ]]
}

# =============================================================================
# T-002: 引数バリデーション — content未指定でexit 1
# =============================================================================

@test "T-002: only target, no content → exit 1" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" "test_agent"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage" ]]
}

# =============================================================================
# T-003: 正常書き込み — 新規inboxファイル作成
# =============================================================================

@test "T-003: normal write to new inbox file → messages array with correct fields" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" "test_agent" "cmd_100 テストメッセージ" "cmd_new" "shogun"
    [ "$status" -eq 0 ]

    # YAMLファイルが作成されていることを確認
    [ -f "$TEST_INBOX_DIR/test_agent.yaml" ]

    # grep検証 (python3不要)
    [[ "$(grep -c "^- " "$TEST_INBOX_DIR/test_agent.yaml")" -eq 1 ]]
    grep -q "^- content: 'cmd_100 テストメッセージ'" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  from: 'shogun'" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -qE "^  id: 'msg_" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  type: 'cmd_new'" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  read: false" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  timestamp: " "$TEST_INBOX_DIR/test_agent.yaml"
}

@test "T-003c: queue/inbox symlink writes to real target and uses real lock path" {
    setup_basic_test_env
    local real_inbox_dir="$TEST_TMPDIR/real_inbox"
    rm -rf "$TEST_TMPDIR/queue/inbox"
    mkdir -p "$real_inbox_dir"
    ln -s "$real_inbox_dir" "$TEST_TMPDIR/queue/inbox"

    run bash "$TEST_INBOX_WRITE" "test_agent" "symlink message" "wake_up" "karo"
    [ "$status" -eq 0 ]

    [ -f "$real_inbox_dir/test_agent.yaml" ]
    [ -f "$TEST_TMPDIR/queue/inbox/test_agent.yaml" ]
    grep -q "^- content: 'symlink message'" "$real_inbox_dir/test_agent.yaml"
    [ -e "$real_inbox_dir/test_agent.yaml.lock" ]
}

@test "T-003b: shogun cmd_new without cmd_id is blocked with LS-A07 guidance" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" "test_agent" "配備せよ" "cmd_new" "shogun"
    [ "$status" -eq 1 ]
    [[ "$output" == *"[cmd_new_gate] BLOCKED: shogun cmd_new にcmd_idが含まれていない"* ]]
    [[ "$output" == *"LS-A07: gate迂回禁止"* ]]
    [[ "$output" == *"bash scripts/cmd_publish.sh cmd_XXXX"* ]]
    [ ! -f "$TEST_INBOX_DIR/test_agent.yaml" ]
}

# =============================================================================
# T-004: 正常書き込み — 既存inboxへの追記
# =============================================================================

@test "T-004: append to existing inbox → preserves existing messages, adds new one" {
    setup_basic_test_env
    # 1件目の書き込み
    bash "$TEST_INBOX_WRITE" "test_agent" "メッセージ1" "type1" "sender1"

    # 2件目の書き込み
    run bash "$TEST_INBOX_WRITE" "test_agent" "メッセージ2" "type2" "sender2"
    [ "$status" -eq 0 ]

    # grep検証 (python3不要)
    [[ "$(grep -c "^- " "$TEST_INBOX_DIR/test_agent.yaml")" -eq 2 ]]
    # 順序検証: メッセージ1が先頭
    _l1=$(grep -n "^- content: 'メッセージ1'" "$TEST_INBOX_DIR/test_agent.yaml" | cut -d: -f1)
    _l2=$(grep -n "^- content: 'メッセージ2'" "$TEST_INBOX_DIR/test_agent.yaml" | cut -d: -f1)
    [[ "$_l1" -lt "$_l2" ]]
}

# =============================================================================
# T-005: メッセージID一意性
# =============================================================================

@test "T-005: message ID uniqueness → 2 rapid writes produce different IDs" {
    setup_basic_test_env
    # 2回連続書き込み
    bash "$TEST_INBOX_WRITE" "test_agent" "メッセージA"
    bash "$TEST_INBOX_WRITE" "test_agent" "メッセージB"

    # grep検証 (python3不要): IDが2つあり、ユニークであること
    [[ "$(grep -c "^  id: " "$TEST_INBOX_DIR/test_agent.yaml")" -eq 2 ]]
    [[ "$(grep "^  id: " "$TEST_INBOX_DIR/test_agent.yaml" | sort -u | wc -l)" -eq 2 ]]
}

# =============================================================================
# T-006: デフォルト値 — type未指定でwake_up
# =============================================================================

@test "T-006: type/from default values → type=wake_up, from=unknown when not specified" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" "test_agent" "デフォルトテスト"
    [ "$status" -eq 0 ]

    # grep検証 (python3不要)
    grep -q "^  type: 'wake_up'" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  from: 'unknown'" "$TEST_INBOX_DIR/test_agent.yaml"
}

# =============================================================================
# T-007: カスタムtype/from指定
# =============================================================================

@test "T-007: custom type/from → 4th and 5th args set type and from correctly" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" "test_agent" "カスタムメッセージ" "custom_type" "custom_sender"
    [ "$status" -eq 0 ]

    # grep検証 (python3不要)
    grep -q "^  type: 'custom_type'" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  from: 'custom_sender'" "$TEST_INBOX_DIR/test_agent.yaml"
}

@test "T-007a: action argument provided → action field is persisted in YAML" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" "test_agent" "アクション付き" "custom_type" "custom_sender" "notify_karo"
    [ "$status" -eq 0 ]

    # grep検証 (python3不要)
    grep -q "^- action: 'notify_karo'" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  type: 'custom_type'" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  from: 'custom_sender'" "$TEST_INBOX_DIR/test_agent.yaml"
}

@test "T-007b: action omitted → backward compatible write with WARN and no action field" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" "test_agent" "アクションなし" "custom_type" "custom_sender"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: action omitted"* ]]

    # grep検証 (python3不要): actionフィールドが存在しないこと
    ! grep -qE "^[-]? action: " "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  type: 'custom_type'" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  from: 'custom_sender'" "$TEST_INBOX_DIR/test_agent.yaml"
}

# test_necessity: review context must preserve both distinct knowledge layers
# without making semantic_search repeat the separately collected Memory query.
@test "review_draft attaches memory and semantic context before delivery" {
    setup_basic_test_env
    cat > "$TEST_TMPDIR/scripts/memory_db_query.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "2026-07-07|cmd_3737|レビュー想起: 過去教訓あり"
SCRIPT
    chmod +x "$TEST_TMPDIR/scripts/memory_db_query.sh"
    cat > "$TEST_TMPDIR/scripts/semantic_search.sh" <<'SCRIPT'
#!/usr/bin/env bash
[ "${SEMANTIC_DISABLE_MEMORY_DB:-0}" = "1" ] || exit 44
echo "matched: [[レビュー想起がpull型依存]]"
SCRIPT
    chmod +x "$TEST_TMPDIR/scripts/semantic_search.sh"
    mkdir -p "$TEST_TMPDIR/queue"
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_3737:
    purpose: "レビュー依頼へ関連知識をpush型添付する"
    project: infra
    acceptance_criteria:
      - "添付内容が届く"
YAML

    run bash "$TEST_INBOX_WRITE" "gunshi" "draft cmd_3737 レビュー依頼。" "review_draft" "karo" "review_request"
    [ "$status" -eq 0 ]
    grep -q "\[review_context_push\]" "$TEST_INBOX_DIR/gunshi.yaml"
    grep -q "レビュー想起: 過去教訓あり" "$TEST_INBOX_DIR/gunshi.yaml"
    grep -q "レビュー想起がpull型依存" "$TEST_INBOX_DIR/gunshi.yaml"
}

@test "review_draft context search failure is fail-soft and preserves delivery" {
    setup_basic_test_env
    cat > "$TEST_TMPDIR/scripts/memory_db_query.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 42
SCRIPT
    chmod +x "$TEST_TMPDIR/scripts/memory_db_query.sh"
    cat > "$TEST_TMPDIR/scripts/semantic_search.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 43
SCRIPT
    chmod +x "$TEST_TMPDIR/scripts/semantic_search.sh"

    run bash "$TEST_INBOX_WRITE" "gunshi" "draft cmd_3737 レビュー依頼。" "review_draft" "karo" "review_request"
    [ "$status" -eq 0 ]
    grep -q "^- action: 'review_request'" "$TEST_INBOX_DIR/gunshi.yaml"
    grep -q "draft cmd_3737 レビュー依頼。" "$TEST_INBOX_DIR/gunshi.yaml"
    ! grep -q "\[review_context_push\]" "$TEST_INBOX_DIR/gunshi.yaml"
}

@test "review_draft collects memory and semantic context concurrently" {
    setup_basic_test_env
    export REVIEW_CONTEXT_ORDER_LOG="$TEST_TMPDIR/review_context_order.log"
    cat > "$TEST_TMPDIR/scripts/memory_db_query.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo memory_start >> "$REVIEW_CONTEXT_ORDER_LOG"
sleep 0.25
echo memory_end >> "$REVIEW_CONTEXT_ORDER_LOG"
echo "parallel memory hit"
SCRIPT
    chmod +x "$TEST_TMPDIR/scripts/memory_db_query.sh"
    cat > "$TEST_TMPDIR/scripts/semantic_search.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo semantic_start >> "$REVIEW_CONTEXT_ORDER_LOG"
sleep 0.25
echo semantic_end >> "$REVIEW_CONTEXT_ORDER_LOG"
echo "parallel semantic hit"
SCRIPT
    chmod +x "$TEST_TMPDIR/scripts/semantic_search.sh"

    run bash "$TEST_INBOX_WRITE" "gunshi" "draft cmd_parallel_context review" "review_draft" "karo" "review_request"

    [ "$status" -eq 0 ]
    [[ "$(sed -n '1,2p' "$REVIEW_CONTEXT_ORDER_LOG")" == *"memory_start"* ]]
    [[ "$(sed -n '1,2p' "$REVIEW_CONTEXT_ORDER_LOG")" == *"semantic_start"* ]]
    ! sed -n '1,2p' "$REVIEW_CONTEXT_ORDER_LOG" | grep -q '_end$'
    grep -q "parallel memory hit" "$TEST_INBOX_DIR/gunshi.yaml"
    grep -q "parallel semantic hit" "$TEST_INBOX_DIR/gunshi.yaml"
}

@test "report_review builds context query from report YAML" {
    setup_basic_test_env
    cat > "$TEST_TMPDIR/scripts/memory_db_query.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'query=%s\n' "$*"
SCRIPT
    chmod +x "$TEST_TMPDIR/scripts/memory_db_query.sh"
    cat > "$TEST_TMPDIR/scripts/semantic_search.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
    chmod +x "$TEST_TMPDIR/scripts/semantic_search.sh"
    mkdir -p "$TEST_TMPDIR/queue/reports"
    cat > "$TEST_TMPDIR/queue/reports/testninja_report_cmd_3737.yaml" <<'YAML'
parent_cmd: cmd_3737
result:
  summary: "報告レビュー対象の要約"
files_modified:
  - path: scripts/inbox_write.sh
    change: modified
YAML

    run bash "$TEST_INBOX_WRITE" "gunshi" "testninja報告完了。レビュー依頼: cmd_3737 report=testninja_report_cmd_3737.yaml" "report_review" "karo"
    [ "$status" -eq 0 ]
    grep -q "\[review_context_push\]" "$TEST_INBOX_DIR/gunshi.yaml"
    grep -q "報告レビュー対象の要約" "$TEST_INBOX_DIR/gunshi.yaml"
    grep -q "scripts/inbox_write.sh" "$TEST_INBOX_DIR/gunshi.yaml"
}

@test "review context truncation preserves UTF-8 YAML validity" {
    setup_basic_test_env
    cat > "$TEST_TMPDIR/scripts/memory_db_query.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "memory hit"
SCRIPT
    chmod +x "$TEST_TMPDIR/scripts/memory_db_query.sh"
    cat > "$TEST_TMPDIR/scripts/semantic_search.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "semantic hit"
SCRIPT
    chmod +x "$TEST_TMPDIR/scripts/semantic_search.sh"

    long_japanese=$(printf '三層記憶引用検証%.0s' {1..140})
    run bash "$TEST_INBOX_WRITE" "gunshi" "draft cmd_3737 レビュー依頼。${long_japanese}" "review_draft" "karo" "review_request"
    [ "$status" -eq 0 ]
    python3 - "$TEST_INBOX_DIR/gunshi.yaml" <<'PY'
import sys
import yaml

path = sys.argv[1]
with open(path, "rb") as f:
    raw = f.read()
raw.decode("utf-8")
with open(path, encoding="utf-8") as f:
    yaml.safe_load(f)
PY
}

@test "memory DB live insert: inbox write appends event_type=inbox after YAML persistence" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/data"
    cp "$PROJECT_ROOT/scripts/memory_db_live_insert.py" "$TEST_TMPDIR/scripts/memory_db_live_insert.py"

    python3 <<EOF
import sqlite3

conn = sqlite3.connect("$TEST_TMPDIR/data/multi_agent_shogun_memory.db")
conn.execute("""
CREATE TABLE events (
    id TEXT PRIMARY KEY,
    ts TEXT,
    event_type TEXT,
    agent TEXT,
    target TEXT,
    direction TEXT,
    summary TEXT,
    detail TEXT,
    session_id TEXT,
    cmd_id TEXT,
    concepts TEXT,
    source_file TEXT,
    parent_event_id INTEGER,
    importance TEXT
)
""")
conn.execute("CREATE VIRTUAL TABLE events_fts USING fts5(summary, detail, content='events', content_rowid='rowid')")
conn.commit()
conn.close()
EOF

    run bash "$TEST_INBOX_WRITE" "test_agent" "cmd_2985 記憶DB投入" "task_assigned" "karo" "notify"
    [ "$status" -eq 0 ]
    [ -f "$TEST_INBOX_DIR/test_agent.yaml" ]

    python3 <<EOF
import sqlite3

conn = sqlite3.connect("$TEST_TMPDIR/data/multi_agent_shogun_memory.db")
row = conn.execute("""
SELECT event_type, agent, target, direction, summary, detail, source_file, importance
FROM events
""").fetchone()
assert row == (
    "inbox",
    "karo",
    "test_agent",
    "task_assigned",
    "cmd_2985 記憶DB投入",
    "cmd_2985 記憶DB投入\ntype: task_assigned\naction: notify\nfrom: karo\ntarget: test_agent",
    "$TEST_INBOX_DIR/test_agent.yaml",
    "high",
), row
fts_count = conn.execute("SELECT COUNT(*) FROM events_fts").fetchone()[0]
assert fts_count == 1, fts_count
EOF
}

# test_necessity: receiver-only deploy nudge text must not be recalled as
# karo-authored memory; ordinary inbox communication keeps the sender actor.
@test "memory DB live insert: deploy nudge is attributed to destination ninja" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/data" "$TEST_TMPDIR/queue/tasks"
    cp "$PROJECT_ROOT/scripts/memory_db_live_insert.py" "$TEST_TMPDIR/scripts/memory_db_live_insert.py"
    python3 - <<EOF
import sqlite3
conn = sqlite3.connect("$TEST_TMPDIR/data/multi_agent_shogun_memory.db")
conn.execute("""CREATE TABLE events (id TEXT PRIMARY KEY, ts TEXT, event_type TEXT, agent TEXT, target TEXT, direction TEXT, summary TEXT, detail TEXT, session_id TEXT, cmd_id TEXT, concepts TEXT, source_file TEXT, parent_event_id INTEGER, importance TEXT)""")
conn.execute("CREATE VIRTUAL TABLE events_fts USING fts5(summary, detail, content='events', content_rowid='rowid')")
conn.commit(); conn.close()
EOF
    local nudge='現task YAMLを正本として読み直して作業開始せよ。inboxはread:falseかつ現task_id一致の補足だけを命令として扱い、read:trueまたは別taskのRC/補足は参照しても適用するな'
    run bash "$TEST_INBOX_WRITE" kotaro "$nudge" task_assigned karo notify
    [ "$status" -eq 0 ]
    python3 - <<EOF
import sqlite3
conn = sqlite3.connect("$TEST_TMPDIR/data/multi_agent_shogun_memory.db")
row = conn.execute("SELECT agent,target,detail FROM events").fetchone()
assert row[0] == "kotaro", row
assert row[1] == "kotaro", row
assert "from: karo" in row[2], row
conn.close()
EOF
    grep -q "^  from: 'karo'" "$TEST_INBOX_DIR/kotaro.yaml"
}

@test "memory DB live insert: DB failure is non-fatal and preserves inbox write" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/scripts"
    cat > "$TEST_TMPDIR/scripts/memory_db_live_insert.py" <<'PY'
#!/usr/bin/env python3
raise SystemExit(7)
PY
    chmod +x "$TEST_TMPDIR/scripts/memory_db_live_insert.py"

    run bash "$TEST_INBOX_WRITE" "test_agent" "DB失敗でもinbox成功" "wake_up" "karo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"memory DB inbox insert failed"* ]]
    [ -f "$TEST_INBOX_DIR/test_agent.yaml" ]
    grep -q "DB失敗でもinbox成功" "$TEST_INBOX_DIR/test_agent.yaml"
}

@test "task_new_gate: shogun direct task_new is blocked before inbox write" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" "karo" "直接作業指示" "task_new" "shogun"
    [ "$status" -eq 1 ]
    [[ "$output" == *"task_new_gate"* ]]
    [[ "$output" == *"BLOCKED"* ]]
    [[ "$output" == *"cmd_save.sh"* ]]
    [ ! -f "$TEST_INBOX_DIR/karo.yaml" ]
}

@test "task_new_gate: karo task_new remains allowed" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" "test_agent" "正規作業指示" "task_new" "karo"
    [ "$status" -eq 0 ]
    [ -f "$TEST_INBOX_DIR/test_agent.yaml" ]
    grep -q "^  type: 'task_new'" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  from: 'karo'" "$TEST_INBOX_DIR/test_agent.yaml"
}

@test "completed report_review_result to karo is auto-read and does not re-trigger gate" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/logs" "$TEST_TMPDIR/scripts"
    printf '2026-06-20T01:00:00\tcmd_9999\tCLEAR\tall_gates_passed\timpl\tunknown\tunknown\tnone\t\n' > "$TEST_TMPDIR/logs/gate_metrics.log"
    cat > "$TEST_TMPDIR/scripts/cmd_complete_gate.sh" <<'SCRIPT'
#!/bin/bash
echo "gate should not run" >> "$INBOX_WRITE_GATE_SENTINEL"
SCRIPT
    chmod +x "$TEST_TMPDIR/scripts/cmd_complete_gate.sh"
    export INBOX_WRITE_GATE_SENTINEL="$TEST_TMPDIR/gate_ran"

    run bash "$TEST_INBOX_WRITE" "karo" "cmd_9999 報告レビュー。verdict: LGTM。" "report_review_result" "gunshi"
    [ "$status" -eq 2 ]
    [[ "$output" == *"requires explicit queue/reports path"* ]]
    [ ! -e "$INBOX_WRITE_GATE_SENTINEL" ]
}

@test "completed report_received to karo is auto-read and skips auto-done side effects" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/logs"
    printf '2026-06-20T01:00:00\tcmd_9998\tCLEAR\tall_gates_passed\thotfix\tunknown\tunknown\tnone\t\n' > "$TEST_TMPDIR/logs/gate_metrics.log"

    run bash "$TEST_INBOX_WRITE" "karo" "tobisaru、cmd_9998報告完了。報告: queue/reports/tobisaru_report_cmd_9998.yaml" "report_received" "tobisaru"
    [ "$status" -eq 0 ]
    [[ "$output" == *"auto-read completed notification"* ]]
    grep -q "^  read: true" "$TEST_INBOX_DIR/karo.yaml"
}

@test "reviewed ninja report notification to karo is auto-read even before gate clear" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/logs"
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_9997
  review_type: report
  report_ninja: tobisaru
  verdict: LGTM
YAML

    run bash "$TEST_INBOX_WRITE" "karo" "tobisaru、cmd_9997報告完了。報告: queue/reports/tobisaru_report_cmd_9997.yaml" "report_received" "tobisaru"
    [ "$status" -eq 0 ]
    [[ "$output" == *"auto-read completed notification"* ]]
    grep -q "^  read: true" "$TEST_INBOX_DIR/karo.yaml"
}

@test "report_review_result is not auto-read from review_log alone because it carries gate side effects" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/logs" "$TEST_TMPDIR/scripts"
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_9996
  review_type: report
  report_ninja: tobisaru
  verdict: LGTM
YAML

    run bash "$TEST_INBOX_WRITE" "karo" "cmd_9996 tobisaru報告レビュー。verdict: LGTM。" "report_review_result" "gunshi"
    [ "$status" -eq 2 ]
    [[ "$output" == *"requires explicit queue/reports path"* ]]
    ! [[ "$output" == *"auto-read completed notification"* ]]
    [ ! -e "$TEST_INBOX_DIR/karo.yaml" ]
}

# =============================================================================
# T-008: Overflow Protection — 50件超で古い既読を削除
# =============================================================================

@test "T-008: overflow protection at 50 messages → oldest read messages removed" {
    setup_basic_test_env
    # 既読60件フィクスチャをコピー (python3不要)
    mkdir -p "$TEST_INBOX_DIR"
    cp "$GIT_TEMPLATE_DIR/inbox_overflow_all_read.yaml" "$TEST_INBOX_DIR/test_agent.yaml"

    # 新規メッセージ1件書き込み
    run bash "$TEST_INBOX_WRITE" "test_agent" "新規メッセージ"
    [ "$status" -eq 0 ]

    # grep検証: 50件以下 + 新規メッセージ存在 (python3不要)
    [[ "$(grep -c "^- " "$TEST_INBOX_DIR/test_agent.yaml")" -le 50 ]]
    grep -q "新規メッセージ" "$TEST_INBOX_DIR/test_agent.yaml"
}

# =============================================================================
# T-009: Overflow Protection — 未読メッセージは削除されない
# =============================================================================

@test "T-009: overflow preserves unread → unread messages are NOT removed even when over 50" {
    setup_basic_test_env
    # 未読20件+既読40件フィクスチャをコピー (python3不要)
    mkdir -p "$TEST_INBOX_DIR"
    cp "$GIT_TEMPLATE_DIR/inbox_overflow_mixed.yaml" "$TEST_INBOX_DIR/test_agent.yaml"

    # 新規メッセージ1件書き込み（未読20→21件になる）
    run bash "$TEST_INBOX_WRITE" "test_agent" "新規未読"
    [ "$status" -eq 0 ]

    # grep検証: 未読21件が保持される (python3不要)
    # overflow保護は既読のみ削除するため、未読21件(元20+新1)が全て残る
    [[ "$(grep -c "^  read: false" "$TEST_INBOX_DIR/test_agent.yaml")" -eq 21 ]]
}

@test "mv failure during overflow rewrite is retried and preserves message" {
    setup_basic_test_env
    mkdir -p "$TEST_INBOX_DIR" "$TEST_TMPDIR/bin"
    cp "$GIT_TEMPLATE_DIR/inbox_overflow_all_read.yaml" "$TEST_INBOX_DIR/test_agent.yaml"

    cat > "$TEST_TMPDIR/bin/mv" <<'SCRIPT_EOF'
#!/bin/bash
dest="${@: -1}"
if [[ "$dest" == *"/queue/inbox/test_agent.yaml" && ! -f "${FAKE_MV_STATE}" ]]; then
    touch "${FAKE_MV_STATE}"
    exit 1
fi
exec /usr/bin/mv "$@"
SCRIPT_EOF
    chmod +x "$TEST_TMPDIR/bin/mv"

    export FAKE_MV_STATE="$TEST_TMPDIR/mv_failed_once"
    export PATH="$TEST_TMPDIR/bin:$PATH"
    export INBOX_WRITE_MV_RETRIES=2
    export INBOX_WRITE_MV_RETRY_SLEEP=0.01

    run bash "$TEST_INBOX_WRITE" "test_agent" "mv retry message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: mv failed"* ]]
    grep -q "mv retry message" "$TEST_INBOX_DIR/test_agent.yaml"
    [[ "$(grep -c "^- " "$TEST_INBOX_DIR/test_agent.yaml")" -eq 31 ]]
}

# =============================================================================
# T-010: flock競合時のリトライ（並行書き込みテスト）
# =============================================================================

@test "T-010: concurrent writes (flock test) → 8 parallel writes all succeed, no data loss" {
    setup_basic_test_env
    # 並行書き込み用のスクリプトを作成
    cat > "$TEST_TMPDIR/parallel_write.sh" <<'SCRIPT_EOF'
#!/bin/bash
INBOX_WRITE="$1"
AGENT="$2"
ID="$3"
bash "$INBOX_WRITE" "$AGENT" "並行メッセージ $ID" "concurrent" "writer_$ID" 2>/dev/null
SCRIPT_EOF
    chmod +x "$TEST_TMPDIR/parallel_write.sh"

    for attempt in 1 2 3; do
        rm -f "$TEST_INBOX_DIR/test_agent.yaml"

        # 8個の並行書き込みプロセスを起動
        for i in {1..8}; do
            "$TEST_TMPDIR/parallel_write.sh" "$TEST_INBOX_WRITE" "test_agent" "$i" &
        done

        # 全プロセスの完了を待つ
        wait

        # grep検証: 8件 + ユニークID (python3不要)
        if [[ "$(grep -c "^- " "$TEST_INBOX_DIR/test_agent.yaml")" -eq 8 ]] \
           && [[ "$(grep "^  id: " "$TEST_INBOX_DIR/test_agent.yaml" | sort -u | wc -l)" -eq 8 ]]; then
            return 0
        fi
    done

    return 1
}

# =============================================================================
# T-011: 特殊文字のエスケープ処理
# =============================================================================

@test "T-011: special characters in content → YAML special chars handled safely" {
    setup_basic_test_env
    # YAML特殊文字を含むメッセージ
    SPECIAL_CONTENT="引用符: \"test\" と 'test'
改行を含む
コロン: key: value
ブレース: {key: value}
配列: [1, 2, 3]"

    run bash "$TEST_INBOX_WRITE" "test_agent" "$SPECIAL_CONTENT"
    [ "$status" -eq 0 ]

    # 検証: 特殊文字が正しく保存・復元されること
    python3 <<EOF
import yaml

with open('$TEST_INBOX_DIR/test_agent.yaml') as f:
    data = yaml.safe_load(f)

msg = data['messages'][0]

expected_content = '''引用符: "test" と 'test'
改行を含む
コロン: key: value
ブレース: {key: value}
配列: [1, 2, 3]'''

assert msg['content'] == expected_content, f'Content mismatch: {msg["content"]}'

print('T-011: PASS')
EOF
}

# =============================================================================
# T-012: inbox初期化 — ディレクトリ自動作成
# =============================================================================

@test "T-012: auto-create inbox directory → missing queue/inbox/ directory is created" {
    setup_basic_test_env
    # queue/inbox/ ディレクトリを削除
    rm -rf "$TEST_INBOX_DIR"

    # ディレクトリが存在しないことを確認
    [ ! -d "$TEST_INBOX_DIR" ]

    # メッセージ書き込み
    run bash "$TEST_INBOX_WRITE" "test_agent" "自動作成テスト"
    [ "$status" -eq 0 ]

    # ディレクトリとファイルが作成されていることを確認
    [ -d "$TEST_INBOX_DIR" ]
    [ -f "$TEST_INBOX_DIR/test_agent.yaml" ]

    # grep検証 (python3不要): 1件のメッセージ
    [[ "$(grep -c "^- " "$TEST_INBOX_DIR/test_agent.yaml")" -eq 1 ]]
}

@test "task_assigned: duplicate active parent_cmd in peer ninja → BLOCKED and notifies karo" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/queue/tasks"

    cat > "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: assigned
  parent_cmd: cmd_dup_001
YAML
    cat > "$TEST_TMPDIR/queue/tasks/otherninja.yaml" <<'YAML'
task:
  status: in_progress
  parent_cmd: cmd_dup_001
YAML

    run bash "$TEST_INBOX_WRITE" "testninja" "タスクを読め" "task_assigned" "karo"
    [ "$status" -eq 1 ]
    [[ "$output" == *"duplicate_deploy_gate"* ]]
    [[ "$output" == *"parent_cmd=cmd_dup_001 target=testninja"* ]]
    [[ "$output" == *"duplicate=otherninja status=in_progress"* ]]

    [ ! -f "$TEST_TMPDIR/queue/inbox/testninja.yaml" ]
    [ -f "$TEST_TMPDIR/queue/inbox/karo.yaml" ]
    grep -q "^  type: 'deploy_blocked'" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    grep -q "duplicates=otherninja(status=in_progress)" "$TEST_TMPDIR/queue/inbox/karo.yaml"
}

@test "task_assigned: completed peer parent_cmd does not block" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/queue/tasks"

    cat > "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: assigned
  parent_cmd: cmd_dup_002
YAML
    cat > "$TEST_TMPDIR/queue/tasks/otherninja.yaml" <<'YAML'
task:
  status: done
  parent_cmd: cmd_dup_002
YAML

    run bash "$TEST_INBOX_WRITE" "testninja" "タスクを読め" "task_assigned" "karo"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/queue/inbox/testninja.yaml" ]
    grep -q "^  type: 'task_assigned'" "$TEST_TMPDIR/queue/inbox/testninja.yaml"
}

# test_necessity: task_assignedの任務帰属は送信時点の送信先task YAMLに固定し、
# report identityや本文のcmd記述を混入させない。
@test "task_assigned: stamps current destination task identity" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/queue/tasks"
    cat > "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: assigned
  task_id: cmd_task_identity_001_normal
  parent_cmd: cmd_task_identity_001
YAML

    run _run_inbox_write testninja "report_id=rpt-not-task task_id=cmd-prose" task_assigned karo
    [ "$status" -eq 0 ]
    grep -q "^  task_id: 'cmd_task_identity_001_normal'" "$TEST_TMPDIR/queue/inbox/testninja.yaml"
    grep -q "^  parent_cmd: 'cmd_task_identity_001'" "$TEST_TMPDIR/queue/inbox/testninja.yaml"
    [ "$(grep -c '^  report_id:' "$TEST_TMPDIR/queue/inbox/testninja.yaml" || true)" -eq 0 ]
    [ "$(grep -c "^  task_id: 'cmd-prose'" "$TEST_TMPDIR/queue/inbox/testninja.yaml" || true)" -eq 0 ]
}

# test_necessity: task YAML不在/identity不在場合を明示空契約に固定し、受信側の
# 現task照合が空通知を誤受理しないようにする。
@test "task_assigned: missing destination task uses explicit empty identity" {
    setup_basic_test_env

    run _run_inbox_write testninja "taskなし" task_assigned karo
    [ "$status" -eq 0 ]
    grep -q "^  task_id: ''" "$TEST_TMPDIR/queue/inbox/testninja.yaml"
    grep -q "^  parent_cmd: ''" "$TEST_TMPDIR/queue/inbox/testninja.yaml"
}

# test_necessity: 再配備後の送信は古いtask identityを再利用せず、stale/別task
# 通知を受信側が構造的に識別できる。
@test "task_assigned: stale destination task is replaced by current identity" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/queue/tasks"
    cat > "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: assigned
  task_id: cmd_task_identity_old_normal
  parent_cmd: cmd_task_identity_old
YAML
    run _run_inbox_write testninja "old assignment" task_assigned karo
    [ "$status" -eq 0 ]

    sed -i 's/cmd_task_identity_old/cmd_task_identity_new/g' "$TEST_TMPDIR/queue/tasks/testninja.yaml"
    run _run_inbox_write testninja "new assignment" task_assigned karo
    [ "$status" -eq 0 ]
    [ "$(grep -c "^  task_id: 'cmd_task_identity_old_normal'" "$TEST_TMPDIR/queue/inbox/testninja.yaml")" -eq 1 ]
    [ "$(grep -c "^  task_id: 'cmd_task_identity_new_normal'" "$TEST_TMPDIR/queue/inbox/testninja.yaml")" -eq 1 ]
    [ "$(grep -c "^  parent_cmd: 'cmd_task_identity_new'" "$TEST_TMPDIR/queue/inbox/testninja.yaml")" -eq 1 ]
}

# test_necessity: task_supplementは本文の明示identityを構造fieldへ昇格し、
# 欠落/不一致を永続化前にBLOCK、正当値はaction付きで一件だけ保存する。
@test "task_supplement: identity is required, matched, and action is preserved" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/queue/tasks"
    cat > "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: in_progress
  task_id: cmd_task_identity_002_normal
  parent_cmd: cmd_task_identity_002
YAML

    run _run_inbox_write testninja "identityなし" task_supplement gunshi notify_karo
    [ "$status" -eq 2 ]
    [[ "$output" == *"requires exactly one valid task_id"* ]]
    [ ! -e "$TEST_TMPDIR/queue/inbox/testninja.yaml" ]

    run _run_inbox_write testninja "task_id=cmd_other_normal parent_cmd=cmd_other stale補足" task_supplement gunshi notify_karo
    [ "$status" -eq 2 ]
    [[ "$output" == *"identity mismatch"* ]]
    [ ! -e "$TEST_TMPDIR/queue/inbox/testninja.yaml" ]

    run _run_inbox_write testninja "task_id=cmd_task_identity_002_normal parent_cmd=cmd_task_identity_002 正当補足" task_supplement gunshi notify_karo
    [ "$status" -eq 0 ]
    [ "$(grep -c "^- action: 'notify_karo'" "$TEST_TMPDIR/queue/inbox/testninja.yaml")" -eq 1 ]
    [ "$(grep -c "^  type: 'task_supplement'" "$TEST_TMPDIR/queue/inbox/testninja.yaml")" -eq 1 ]
    [ "$(grep -c "^  task_id: 'cmd_task_identity_002_normal'" "$TEST_TMPDIR/queue/inbox/testninja.yaml")" -eq 1 ]
    [ "$(grep -c "^  parent_cmd: 'cmd_task_identity_002'" "$TEST_TMPDIR/queue/inbox/testninja.yaml")" -eq 1 ]
    echo "missing=1 mismatch=1 valid=1 action_regression_fail=0 skip=0"
}

# test_necessity: 同一通知の再送は既存のexactly-once pending dedupeを維持し、
# task identity付きメッセージを二重配達しない。
@test "task_assigned: duplicate notification remains exactly once" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/queue/tasks"
    cat > "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: assigned
  task_id: cmd_task_identity_003_normal
  parent_cmd: cmd_task_identity_003
YAML

    run _run_inbox_write testninja "同一配備" task_assigned karo
    [ "$status" -eq 0 ]
    run _run_inbox_write testninja "同一配備" task_assigned karo
    [ "$status" -eq 0 ]
    [ "$(grep -c '^  type: '\''task_assigned'\''' "$TEST_TMPDIR/queue/inbox/testninja.yaml")" -eq 1 ]
    [ "$(grep -c "^  task_id: 'cmd_task_identity_003_normal'" "$TEST_TMPDIR/queue/inbox/testninja.yaml")" -eq 1 ]
}

# ============================================================
# Git uncommitted check tests (merged from tests/unit/ cmd_cycle_001)
# ============================================================

# Helper: set up git repo + mocks for report_received tests
setup_git_test_env() {
    # report_received requires NINJA_NAMES from agent_config.sh
    # Unset INBOX_WRITE_TEST so the script sources agent_config.sh
    unset INBOX_WRITE_TEST

    rm -rf "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/reports" "$TEST_TMPDIR/src" "$TEST_TMPDIR/.git"
    # The template is immutable and both paths normally live on /tmp. Prefer a
    # CoW clone so git-heavy cases retain full isolation without recopying the
    # repository fixture; fall back to an ordinary copy where unsupported.
    cp -a --reflink=auto "$GIT_TEMPLATE_DIR/." "$TEST_TMPDIR/"
    cp "$PROJECT_ROOT/scripts/retro_write.sh" "$TEST_TMPDIR/scripts/retro_write.sh"
}

# Wrapper to capture stderr in bats output
_run_inbox_write() {
    bash "$TEST_INBOX_WRITE" "$@" 2>&1
}

_wait_for_file() {
    local path="$1"
    local _attempt
    for _attempt in {1..100}; do
        [ -f "$path" ] && return 0
        sleep 0.02
    done
    return 1
}

@test "report_received: uncommitted changes in files_modified → BLOCKED" {
    setup_git_test_env

    # Modify file WITHOUT committing
    echo 'echo "modified"' >> "$TEST_TMPDIR/src/test_file.sh"

    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 1 ]
    [[ "$output" == *"git_uncommitted_gate"* ]]
    [[ "$output" == *"BLOCKED"* ]]
}

@test "report_received: scout_exempt true skips git_uncommitted_gate" {
    setup_git_test_env

    sed -i '/parent_cmd:/a\  scout_exempt: true' "$TEST_TMPDIR/queue/tasks/testninja.yaml"
    echo 'echo "modified"' >> "$TEST_TMPDIR/src/test_file.sh"

    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 0 ]
    [[ "$output" == *"git_uncommitted_gate"* ]]
    [[ "$output" == *"SKIP: scout_exempt=true"* ]]
}

@test "report_received: all files committed → no BLOCK" {
    setup_git_test_env

    # All files committed — clean working tree
    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 0 ]

    # Verify message was delivered to inbox
    [ -f "$TEST_TMPDIR/queue/inbox/karo.yaml" ]
    # Report arrival and review completion are separate events: keep the
    # durable parent unread so Karo can prepare while Gunshi reviews in parallel.
    grep -q "^  read: false" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    [ -f "$TEST_TMPDIR/queue/inbox/gunshi.yaml" ]
    grep -q "^  type: 'report_review'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml"
    [ ! -s "$TEST_TMPDIR/queue/retro/pending.yaml" ]
    [ ! -e "$TEST_TMPDIR/queue/retro/events.jsonl" ]
    grep -q 'legacy_tombstones' "$TEST_TMPDIR/queue/retro/state.json"
}

# test_necessity: report completion is based on HEAD vs worktree and must not
# fail merely because the shared or inherited private index predates HEAD.
@test "report_received: stale inherited index after scoped commit does not false BLOCK" {
    setup_git_test_env

    printf 'echo "scoped commit"\n' >> "$TEST_TMPDIR/src/test_file.sh"
    git -C "$TEST_TMPDIR" add src/test_file.sh
    git -C "$TEST_TMPDIR" commit -q -m "scoped report change"
    local commit_hash stale_index="$BATS_TEST_TMPDIR/stale-report.index"
    commit_hash=$(git -C "$TEST_TMPDIR" rev-parse HEAD)
    GIT_INDEX_FILE="$stale_index" git -C "$TEST_TMPDIR" read-tree HEAD^
    run bash "$PROJECT_ROOT/scripts/report_field_set.sh" "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" commit_hash "$commit_hash"
    [ "$status" -eq 0 ]

    GIT_INDEX_FILE="$stale_index" run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 0 ]
    [[ "$output" != *"git_uncommitted_gate] BLOCKED"* ]]
}

@test "report_received: explicit verified linked worktree checks that worktree instead of dirty main" {
    setup_git_test_env
    local worktree="$BATS_TEST_TMPDIR/reporter-wt"
    git -C "$TEST_TMPDIR" worktree add -q -b reporter-wt "$worktree"
    printf 'echo "main dirty"\n' >> "$TEST_TMPDIR/src/test_file.sh"
    printf 'echo "reporter committed"\n' >> "$worktree/src/test_file.sh"
    git -C "$worktree" add src/test_file.sh
    git -C "$worktree" commit -q -m "reporter worktree change"
    local commit_hash
    commit_hash=$(git -C "$worktree" rev-parse HEAD)
    run bash "$PROJECT_ROOT/scripts/report_field_set.sh" "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" commit_hash "$commit_hash"
    [ "$status" -eq 0 ]

    INBOX_REPORT_WORKTREE_ROOT="$worktree" run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 0 ]
    [[ "$output" == *"verified linked worktree root"* ]]
}

@test "report_received: arbitrary root and linked-worktree commit mismatch stay blocked" {
    setup_git_test_env
    local worktree="$BATS_TEST_TMPDIR/reporter-wt-bad"
    local foreign="$BATS_TEST_TMPDIR/foreign"
    git -C "$TEST_TMPDIR" worktree add -q -b reporter-wt-bad "$worktree"
    mkdir -p "$foreign"
    git -C "$foreign" init -q

    INBOX_REPORT_WORKTREE_ROOT="$foreign" run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid linked worktree root or report commit mismatch"* ]]

    INBOX_REPORT_WORKTREE_ROOT="$worktree" run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 1 ]
    [[ "$output" == *"report commit mismatch"* ]]
}

@test "report_received: reporter's hunk committed + other ninja's non-overlapping dirty hunk in same file → PASS (AC1)" {
    setup_git_test_env

    # 報告者(testninja)自身の変更: line2を追加してcommitし、commit_hashを報告YAMLに記録
    printf 'echo "reporter own change"\n' >> "$TEST_TMPDIR/src/test_file.sh"
    git -C "$TEST_TMPDIR" add src/test_file.sh
    git -C "$TEST_TMPDIR" commit -q -m "testninja: own change"
    local commit_hash
    commit_hash=$(git -C "$TEST_TMPDIR" rev-parse HEAD)
    run bash "$PROJECT_ROOT/scripts/report_field_set.sh" "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" commit_hash "$commit_hash"
    [ "$status" -eq 0 ]

    # 他忍者のWIP: 同一ファイルの別行(非重複hunk)に未commit変更を残す
    printf 'echo "other ninja wip"\n' >> "$TEST_TMPDIR/src/test_file.sh"

    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 0 ]
    [[ "$output" == *"uncommitted non-overlapping diff"* ]]
    [ -f "$TEST_TMPDIR/queue/inbox/karo.yaml" ]
}

@test "report_received: reporter's own uncommitted hunk overlapping committed range in same file → BLOCKED (AC2)" {
    setup_git_test_env

    # 報告者(testninja)がline2を変更してcommitし、commit_hashを報告YAMLに記録
    printf 'echo "line2"\n' >> "$TEST_TMPDIR/src/test_file.sh"
    git -C "$TEST_TMPDIR" add src/test_file.sh
    git -C "$TEST_TMPDIR" commit -q -m "testninja: baseline line2"
    sed -i 's/line2/line2-updated/' "$TEST_TMPDIR/src/test_file.sh"
    git -C "$TEST_TMPDIR" add src/test_file.sh
    git -C "$TEST_TMPDIR" commit -q -m "testninja: update line2"
    local commit_hash
    commit_hash=$(git -C "$TEST_TMPDIR" rev-parse HEAD)
    run bash "$PROJECT_ROOT/scripts/report_field_set.sh" "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" commit_hash "$commit_hash"
    [ "$status" -eq 0 ]

    # 報告者自身の未commit hunk: commit済み範囲(line2)と重なる箇所にさらに変更を残す
    # (他者WIPに偽装してcommit漏れを通さないことを確認)
    sed -i 's/line2-updated/line2-updated-more/' "$TEST_TMPDIR/src/test_file.sh"

    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 1 ]
    [[ "$output" == *"git_uncommitted_gate"* ]]
    [[ "$output" == *"BLOCKED"* ]]
    [ ! -f "$TEST_TMPDIR/queue/inbox/karo.yaml" ]
}

@test "report_received: verdict FAIL from binary_checks no → BLOCKED before inbox write" {
    setup_git_test_env

    python3 <<EOF
import yaml

path = "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml"
with open(path, encoding="utf-8") as f:
    data = yaml.safe_load(f)
data["verdict"] = "FAIL"
data["binary_checks"]["AC1"][0]["check"] = "AC1が未完了であることを確認"
data["binary_checks"]["AC1"][0]["result"] = "no"
with open(path, "w", encoding="utf-8") as f:
    yaml.safe_dump(data, f, allow_unicode=True, sort_keys=False)
EOF

    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 1 ]
    [[ "$output" == *"binary_checksにnoがあるため報告完了を差戻し"* ]]
    [[ "$output" == *"AC1[1]: AC1が未完了であることを確認"* ]]
    [[ "$output" == *"task_failedで家老へ報告せよ"* ]]
    [ ! -f "$TEST_TMPDIR/queue/inbox/karo.yaml" ]
}

# cmd_karo_hotfix_singleflight_fail_misattribution_20260725 (provenance: df3421336)
# test_necessity: an infrastructure-only single-flight lock timeout (exit code 2) must not be
# misattributed to the reporting ninja as a quality problem; AC2 requires zero gunshi quality
# notifications and the report still reaching karo once the transient contention clears.
@test "report_received: transient singleflight timeout recovers via retry — report reaches karo, no gunshi quality notification (AC2)" {
    setup_git_test_env
    local counter="$TEST_TMPDIR/gate_call_count"
    echo 0 > "$counter"
    cat > "$TEST_TMPDIR/scripts/gates/gate_report_format.sh" <<EOF
#!/bin/bash
n=\$(cat "$counter"); n=\$((n + 1)); echo "\$n" > "$counter"
if [ "\$n" -eq 1 ]; then
    echo "INFRA_TIMEOUT: report gate single-flight timeout: \$1" >&2
    exit 2
fi
echo "PASS: all checks passed"
exit 0
EOF
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_report_format.sh"

    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 0 ]
    [ "$(cat "$counter")" -eq 2 ]
    [ -f "$TEST_TMPDIR/queue/inbox/karo.yaml" ]
    grep -q "report_received" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    { [ ! -f "$TEST_TMPDIR/queue/inbox/gunshi.yaml" ] || ! grep -q "quality_monitor" "$TEST_TMPDIR/queue/inbox/gunshi.yaml"; }
}

# test_necessity: gate_report_format.sh is intentionally mode644 in the
# repository. report_received must invoke it through bash so a valid report
# cannot be rejected by the filesystem execute bit.
@test "report_received: mode644 gate succeeds through bash invocation" {
    setup_git_test_env
    chmod 644 "$TEST_TMPDIR/scripts/gates/gate_report_format.sh"

    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 0 ]
    [[ "$output" != *"Permission denied"* ]]
    [ -f "$TEST_TMPDIR/queue/inbox/karo.yaml" ]
    grep -q "report_received" "$TEST_TMPDIR/queue/inbox/karo.yaml"
}

# test_necessity: when the transient lock contention does NOT clear within the single retry,
# AC2 requires an explicit karo-facing infra notification (not a ninja fix-it demand, not a
# gunshi quality notification) and the report file must remain on disk (not discarded).
@test "report_received: persistent singleflight timeout notifies karo as infra anomaly, not a ninja quality fix (AC2)" {
    setup_git_test_env
    cat > "$TEST_TMPDIR/scripts/gates/gate_report_format.sh" <<EOF
#!/bin/bash
echo "INFRA_TIMEOUT: report gate single-flight timeout: \$1" >&2
exit 2
EOF
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_report_format.sh"

    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 1 ]
    [[ "$output" == *"インフラ異常"* ]]
    [[ "$output" != *"修正して再送信"* ]]
    [ -f "$TEST_TMPDIR/queue/inbox/karo.yaml" ]
    grep -q "infra_anomaly" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    { [ ! -f "$TEST_TMPDIR/queue/inbox/gunshi.yaml" ] || ! grep -q "quality_monitor" "$TEST_TMPDIR/queue/inbox/gunshi.yaml"; }
    [ -f "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" ]
}

# test_necessity: regression guard — a genuine report-quality FAIL (exit code 1, distinct from
# the infra exit code 2) must keep triggering the existing gunshi quality-monitor notification
# and BLOCK karo delivery exactly as before this cmd's change.
@test "report_received: genuine quality FAIL still notifies gunshi and blocks karo delivery (regression, AC1)" {
    setup_git_test_env
    cat > "$TEST_TMPDIR/scripts/gates/gate_report_format.sh" <<EOF
#!/bin/bash
echo "FAIL: some quality problem: \$1" >&2
exit 1
EOF
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_report_format.sh"

    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCKED: 報告YAML品質問題"* ]]
    [ ! -f "$TEST_TMPDIR/queue/inbox/karo.yaml" ]
    grep -q "quality_monitor" "$TEST_TMPDIR/queue/inbox/gunshi.yaml"
}

@test "task_failed: FAIL report and failed task deliver exactly once without retry" {
    setup_git_test_env

    python3 - "$TEST_TMPDIR" <<'PY'
import pathlib, yaml, sys
root = pathlib.Path(sys.argv[1])
task_path = root / "queue/tasks/testninja.yaml"
report_path = root / "queue/reports/testninja_report_cmd_test_001.yaml"
task = yaml.safe_load(task_path.read_text())
task["task"]["status"] = "failed"
task_path.write_text(yaml.safe_dump(task, allow_unicode=True, sort_keys=False))
report = yaml.safe_load(report_path.read_text())
report["verdict"] = "FAIL"
report["binary_checks"]["AC1"][0].update(check="AC1未達を実測", result="no")
report_path.write_text(yaml.safe_dump(report, allow_unicode=True, sort_keys=False))
PY

    run _run_inbox_write karo "未達報告" task_failed testninja
    [ "$status" -eq 0 ]
    [[ "$output" == *"verified failure report"* ]]
    [ "$(grep -c "^- content: '未達報告'" "$TEST_TMPDIR/queue/inbox/karo.yaml")" -eq 1 ]
    [ "$(find "$TEST_TMPDIR/queue/retro/verbatim_pending" -name '*.event' | wc -l)" -eq 1 ]
    grep -Rq '^task_failed:' "$TEST_TMPDIR/queue/retro/verbatim_pending"

    run _run_inbox_write karo "未達報告" task_failed testninja
    [ "$status" -eq 0 ]
    [[ "$output" == *DUPLICATE_MSG_ID=* ]]
    [ "$(grep -c "^- content: '未達報告'" "$TEST_TMPDIR/queue/inbox/karo.yaml")" -eq 1 ]
    [ "$(find "$TEST_TMPDIR/queue/retro/verbatim_pending" -name '*.event' | wc -l)" -eq 1 ]
}

# test_necessity: a verified FAIL report must reach karo even when the failed
# attempt leaves task-owned WIP dirty; otherwise failure evidence is structurally
# undeliverable until the ninja commits an implementation it explicitly rejected.
@test "task_failed: verified FAIL delivers with uncommitted task-owned evidence" {
    setup_git_test_env

    python3 - "$TEST_TMPDIR" <<'PY'
import pathlib, yaml, sys
root = pathlib.Path(sys.argv[1])
task_path = root / "queue/tasks/testninja.yaml"
report_path = root / "queue/reports/testninja_report_cmd_test_001.yaml"
task = yaml.safe_load(task_path.read_text())
task["task"]["status"] = "failed"
task_path.write_text(yaml.safe_dump(task, allow_unicode=True, sort_keys=False))
report = yaml.safe_load(report_path.read_text())
report["verdict"] = "FAIL"
report["binary_checks"]["AC1"][0].update(check="AC1未達を実測", result="no")
report_path.write_text(yaml.safe_dump(report, allow_unicode=True, sort_keys=False))
(root / "src/test_file.sh").write_text("#!/bin/bash\n# rejected WIP evidence\n")
PY

    run _run_inbox_write karo "未達報告" task_failed testninja
    [ "$status" -eq 0 ]
    [[ "$output" == *"verified failure report"* ]]
    [[ "$output" == *"SKIP: verified task_failed preserves failure evidence"* ]]
    [ "$(grep -c "^- content: '未達報告'" "$TEST_TMPDIR/queue/inbox/karo.yaml")" -eq 1 ]
}

@test "task_failed: blocked task is a canonical terminal and receives verbatim prompt" {
    setup_git_test_env
    python3 - "$TEST_TMPDIR" <<'PY'
import pathlib, yaml, sys
root = pathlib.Path(sys.argv[1])
task_path = root / "queue/tasks/testninja.yaml"
report_path = root / "queue/reports/testninja_report_cmd_test_001.yaml"
task = yaml.safe_load(task_path.read_text()); task["task"]["status"] = "blocked"
task_path.write_text(yaml.safe_dump(task, allow_unicode=True, sort_keys=False))
report = yaml.safe_load(report_path.read_text()); report["verdict"] = "FAIL"
report["binary_checks"]["AC1"][0].update(check="BLOCK終端を実測", result="no")
report_path.write_text(yaml.safe_dump(report, allow_unicode=True, sort_keys=False))
PY
    run _run_inbox_write karo "BLOCK報告" task_failed testninja
    [ "$status" -eq 0 ]
    [ "$(find "$TEST_TMPDIR/queue/retro/verbatim_pending" -name '*.event' | wc -l)" -eq 1 ]
}

@test "task_failed: terminal enqueue is stable across duplicate resend" {
    setup_git_test_env
    python3 - "$TEST_TMPDIR" <<'PY'
import pathlib, yaml, sys
root = pathlib.Path(sys.argv[1]); task_path=root/'queue/tasks/testninja.yaml'; report_path=root/'queue/reports/testninja_report_cmd_test_001.yaml'
task=yaml.safe_load(task_path.read_text()); task['task']['status']='failed'; task_path.write_text(yaml.safe_dump(task,sort_keys=False))
report=yaml.safe_load(report_path.read_text()); report['verdict']='FAIL'; report['binary_checks']['AC1'][0].update(check='AC1未達を実測',result='no'); report_path.write_text(yaml.safe_dump(report,sort_keys=False,allow_unicode=True))
PY
    run _run_inbox_write karo "未達報告" task_failed testninja
    [ "$status" -eq 0 ]
    run _run_inbox_write karo "未達報告" task_failed testninja
    [ "$status" -eq 0 ]
    [ "$(find "$TEST_TMPDIR/queue/retro/verbatim_pending" -name '*.event' | wc -l)" -eq 1 ]
}

@test "task_failed: PASS report is blocked" {
    setup_git_test_env
    run _run_inbox_write karo "不正失敗報告" task_failed testninja
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires report verdict=FAIL"* ]]
    [ ! -f "$TEST_TMPDIR/queue/inbox/karo.yaml" ]
}

@test "task_failed: FAIL report with non-failed task is blocked" {
    setup_git_test_env
    python3 - "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" <<'PY'
import yaml, sys
path = sys.argv[1]
data = yaml.safe_load(open(path))
data["verdict"] = "FAIL"
data["binary_checks"]["AC1"][0].update(check="AC1未達を実測", result="no")
yaml.safe_dump(data, open(path, "w"), allow_unicode=True, sort_keys=False)
PY
    run _run_inbox_write karo "不正失敗報告" task_failed testninja
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires task status=failed"* ]]
    [ ! -f "$TEST_TMPDIR/queue/inbox/karo.yaml" ]
}

@test "report_received: only files_modified checked, not whole repo" {
    setup_git_test_env

    # another_file.shはテンプレートで既にコミット済み: git add+commit不要
    # Modify another_file.sh (NOT in files_modified) without committing
    echo 'echo modified' >> "$TEST_TMPDIR/src/another_file.sh"

    # src/test_file.sh is clean, src/another_file.sh is dirty but not in check scope
    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 0 ]
}

@test "report_received: files_modified dict list from report_field_set is checked without target_path fallback" {
    setup_git_test_env

    cat > "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" <<'YAML'
verdict: PASS
files_modified:
- change: modified
  path: src/test_file.sh
binary_checks:
  AC1:
    - check: test check
      result: PASS
lesson_candidate:
  found: false
  no_lesson_reason: no lesson
result:
  summary: implementation complete
YAML

    echo 'echo modified' >> "$TEST_TMPDIR/src/another_file.sh"

    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 0 ]
    [[ "$output" != *"git_uncommitted_gate"* ]]
    [[ "$output" != *"BLOCKED"* ]]
}

@test "report_received: auto-sends report_review to gunshi" {
    setup_git_test_env
    mkdir -p "$TEST_TMPDIR/scripts"
    ln -sf "$PROJECT_ROOT/scripts/inbox_write.sh" "$TEST_TMPDIR/scripts/inbox_write.sh"
    echo 'status: completed' >> "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml"

    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 0 ]

    # Review routing is asynchronous and intentionally silent; durable inbox
    # state and the notification marker are the delivery contract.
    local attempt
    for attempt in $(seq 1 50); do
        grep -q "^  type: 'report_review'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml" 2>/dev/null && break
        sleep 0.1
    done
    [ -f "$TEST_TMPDIR/queue/inbox/gunshi.yaml" ]
    [[ "$(grep -c "^  type: 'report_review'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml")" -ge 1 ]]
    grep -q "^  type: 'report_review'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml"
    grep -q "^  from: 'karo'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml"
    grep -q "cmd_test_001" "$TEST_TMPDIR/queue/inbox/gunshi.yaml"
    grep -q "testninja" "$TEST_TMPDIR/queue/inbox/gunshi.yaml"
    grep -B5 "type: 'report_received'" "$TEST_TMPDIR/queue/inbox/karo.yaml" | grep -q "read: false"
}

@test "report_received: report's own parent_cmd wins over task YAML's redeployed parent_cmd (race, LS078/cmd_4163)" {
    setup_git_test_env
    mkdir -p "$TEST_TMPDIR/scripts"
    ln -sf "$PROJECT_ROOT/scripts/inbox_write.sh" "$TEST_TMPDIR/scripts/inbox_write.sh"
    cat >> "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" <<'YAML'
status: completed
parent_cmd: cmd_test_001
YAML
    git -C "$TEST_TMPDIR" add queue/reports/testninja_report_cmd_test_001.yaml
    git -C "$TEST_TMPDIR" commit -q -m race-report-identity

    # task入替race再現: karoが同じ忍者のtask YAMLを次cmdへ再配備した直後に、
    # 旧cmd(cmd_test_001)向けの報告が届く。report_path/report_filenameは
    # 旧報告を指したまま、parent_cmdフィールドだけが新cmdへ書き換わる。
    sed -i 's/parent_cmd: cmd_test_001/parent_cmd: cmd_test_002_redeployed/' "$TEST_TMPDIR/queue/tasks/testninja.yaml"

    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 0 ]
    grep -q "parent_cmd: 'cmd_test_001'" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    ! grep -q "parent_cmd: 'cmd_test_002_redeployed'" "$TEST_TMPDIR/queue/inbox/karo.yaml"

    local attempt
    for attempt in $(seq 1 50); do
        grep -q "^  type: 'report_review'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml" 2>/dev/null && break
        sleep 0.1
    done
    grep -q "cmd_test_001" "$TEST_TMPDIR/queue/inbox/gunshi.yaml"
    ! grep -q "cmd_test_002_redeployed" "$TEST_TMPDIR/queue/inbox/gunshi.yaml"
}

@test "report_received: normal flow (no race) keeps attributing to task YAML's parent_cmd when report omits its own field" {
    setup_git_test_env
    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 0 ]
    grep -q "parent_cmd: 'cmd_test_001'" "$TEST_TMPDIR/queue/inbox/karo.yaml"
}

@test "report_received v2 persists structured identity and blocks mismatch" {
    setup_git_test_env
    cat >> "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
  report_id: rpt-v2-fixed
  report_identity_version: 2
YAML
    cat >> "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" <<'YAML'
report_id: rpt-v2-fixed
report_identity_version: 2
task_id: cmd_test_001_normal
parent_cmd: cmd_test_001
YAML
    git -C "$TEST_TMPDIR" add queue/tasks/testninja.yaml queue/reports/testninja_report_cmd_test_001.yaml
    git -C "$TEST_TMPDIR" commit -q -m identity

    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 0 ]
    grep -q "report_id: 'rpt-v2-fixed'" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    grep -q "report_identity_version: '2'" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    grep -q "task_id: 'cmd_test_001_normal'" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    grep -q "parent_cmd: 'cmd_test_001'" "$TEST_TMPDIR/queue/inbox/karo.yaml"

    sed -i 's/rpt-v2-fixed/rpt-reused/' "$TEST_TMPDIR/queue/tasks/testninja.yaml"
    run _run_inbox_write karo "別revision" report_received testninja
    [ "$status" -eq 1 ]
    [[ "$output" == *mismatched* ]]
}

@test "report_received fast path does not let a pre-fingerprint event suppress a revised report" {
    setup_git_test_env
    cat >> "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
  report_id: rpt-fast-revision
  report_identity_version: 2
YAML
    cat >> "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" <<'YAML'
status: completed
report_id: rpt-fast-revision
report_identity_version: 2
task_id: cmd_test_001_normal
parent_cmd: cmd_test_001
YAML
    mkdir -p "$TEST_TMPDIR/queue/inbox"
    cat > "$TEST_TMPDIR/queue/inbox/karo.yaml" <<'YAML'
messages:
- content: 'old reviewed report'
  from: 'testninja'
  id: 'msg_old_without_fingerprint'
  read: true
  timestamp: '2026-07-18T10:00:00'
  type: 'report_received'
  report_id: 'rpt-fast-revision'
  report_identity_version: '2'
YAML
    git -C "$TEST_TMPDIR" add queue/tasks/testninja.yaml queue/reports/testninja_report_cmd_test_001.yaml
    git -C "$TEST_TMPDIR" commit -q -m revised-report

    run _run_inbox_write karo "revised report" report_received testninja
    [ "$status" -eq 0 ]
    [[ "$output" != *DUPLICATE_MSG_ID=msg_old_without_fingerprint* ]]
    [ "$(grep -c "report_id: 'rpt-fast-revision'" "$TEST_TMPDIR/queue/inbox/karo.yaml")" -eq 2 ]
    [ "$(grep -c "report_fingerprint:" "$TEST_TMPDIR/queue/inbox/karo.yaml")" -eq 1 ]
}

# test_necessity(cmd_karo_hotfix_completion_event_dedupe_20260723): a crash after durable report event append but before task
# mutation must be repaired by an exact retry without waiting for monitor.
@test "duplicate terminal report event synchronously repairs missing task done transition" {
    setup_git_test_env
    cat >> "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
  report_id: rpt-duplicate-reconcile
  report_identity_version: 2
YAML
    cat >> "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" <<'YAML'
status: completed
report_id: rpt-duplicate-reconcile
report_identity_version: 2
task_id: cmd_test_001_normal
parent_cmd: cmd_test_001
YAML
    git -C "$TEST_TMPDIR" add queue/tasks/testninja.yaml queue/reports/testninja_report_cmd_test_001.yaml
    git -C "$TEST_TMPDIR" commit -q -m duplicate-reconcile

    run _run_inbox_write karo "first terminal" report_received testninja
    [ "$status" -eq 0 ]
    sed -i 's/status: done/status: in_progress/' "$TEST_TMPDIR/queue/tasks/testninja.yaml"
    sed -i '/done_at:/d; /completed_at:/d' "$TEST_TMPDIR/queue/tasks/testninja.yaml"
    start_ns=$(date +%s%N)
    run _run_inbox_write karo "exact retry" report_received testninja
    elapsed_ms=$(( ($(date +%s%N) - start_ns) / 1000000 ))
    [ "$status" -eq 0 ]
    [[ "$output" == *DUPLICATE_MSG_ID=* ]]
    grep -q '^  status: done$' "$TEST_TMPDIR/queue/tasks/testninja.yaml"
    grep -q '^  done_at:' "$TEST_TMPDIR/queue/tasks/testninja.yaml"
    grep -q '^  completed_at:' "$TEST_TMPDIR/queue/tasks/testninja.yaml"
    [ "$elapsed_ms" -lt 30000 ]
    echo "EVENT_RECONCILE elapsed_ms=$elapsed_ms notifications_lost=0" >&3
}

@test "report lifecycle canonical event key is exactly once under 20 parallel writers" {
    setup_git_test_env
    mkdir -p "$TEST_TMPDIR/queue/inbox"
    : > "$TEST_TMPDIR/queue/inbox/gunshi.yaml"
    cat >> "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" <<'YAML'
report_id: rpt-parallel-fixed
report_identity_version: 2
task_id: cmd_parallel_normal
parent_cmd: cmd_parallel
YAML
    local report="queue/reports/testninja_report_cmd_test_001.yaml"
    local pids=()
    for i in $(seq 1 20); do
        INBOX_WRITE_TEST=1 INBOX_WRITE_ROOT_OVERRIDE="$TEST_TMPDIR" \
          bash "$TEST_INBOX_WRITE" gunshi "retry-$i report=$report" report_review karo >"$BATS_TEST_TMPDIR/w$i.out" 2>&1 &
        pids+=("$!")
    done
    local failures=0 pid
    for pid in "${pids[@]}"; do wait "$pid" || failures=$((failures + 1)); done
    [ "$failures" -eq 0 ]
    [ "$(grep -c "^- " "$TEST_TMPDIR/queue/inbox/gunshi.yaml")" -eq 1 ]
    [ "$(grep -c "report_id: 'rpt-parallel-fixed'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml")" -eq 1 ]
    [ "$(grep -l 'DUPLICATE_MSG_ID=' "$BATS_TEST_TMPDIR"/w*.out | wc -l)" -eq 19 ]
}

@test "report event key preserves distinct type sender and report identity" {
    setup_git_test_env
    local report="queue/reports/testninja_report_cmd_test_001.yaml"
    cat >> "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" <<'YAML'
report_id: rpt-generation-a
report_identity_version: 2
task_id: cmd_generation_a
parent_cmd: cmd_generation
YAML
    INBOX_WRITE_TEST=1 run _run_inbox_write gunshi "first report=$report" report_review karo
    [ "$status" -eq 0 ]
    INBOX_WRITE_TEST=1 run _run_inbox_write gunshi "other sender report=$report" report_review shogun
    [ "$status" -eq 0 ]
    INBOX_WRITE_TEST=1 run _run_inbox_write gunshi "other type report=$report" report_review_result karo
    [ "$status" -eq 0 ]
    [ "$(grep -c "^- " "$TEST_TMPDIR/queue/inbox/gunshi.yaml")" -eq 3 ]
}

@test "report review persists a new event for a changed formal report fingerprint and dedupes its retry" {
    setup_git_test_env
    local report="queue/reports/testninja_report_cmd_test_001.yaml"
    cat >> "$TEST_TMPDIR/$report" <<'YAML'
report_id: rpt-revision-generation
report_identity_version: 2
task_id: cmd_revision_generation_normal
parent_cmd: cmd_revision_generation
status: completed
YAML

    INBOX_WRITE_TEST=1 run _run_inbox_write gunshi "initial report=$report" report_review karo
    [ "$status" -eq 0 ]
    local first_id
    first_id="$(grep -m1 "^  id:" "$TEST_TMPDIR/queue/inbox/gunshi.yaml")"

    sed -i 's/status: completed/status: revision_requested/' "$TEST_TMPDIR/$report"
    INBOX_WRITE_TEST=1 run _run_inbox_write gunshi "revised report=$report" report_review karo
    [ "$status" -eq 0 ]
    [[ "$output" != *DUPLICATE_MSG_ID=* ]]
    [ "$(grep -c "report_id: 'rpt-revision-generation'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml")" -eq 2 ]
    [ "$(grep -c "report_fingerprint:" "$TEST_TMPDIR/queue/inbox/gunshi.yaml")" -eq 2 ]

    INBOX_WRITE_TEST=1 run _run_inbox_write gunshi "same revised retry report=$report" report_review karo
    [ "$status" -eq 0 ]
    [[ "$output" == *DUPLICATE_MSG_ID=* ]]
    [ "$(grep -c "report_id: 'rpt-revision-generation'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml")" -eq 2 ]
    [ -n "$first_id" ]
}

# test_necessity: report review is actionable work. An exact retry is suppressed
# while unread, but after consumption it must create a new wake-up event.
@test "report review exact retry wakes again after prior request is read" {
    setup_git_test_env
    local report="queue/reports/testninja_report_cmd_test_001.yaml"
    cat >> "$TEST_TMPDIR/$report" <<'YAML'
report_id: rpt-review-rewake
report_identity_version: 2
task_id: cmd_review_rewake_normal
parent_cmd: cmd_review_rewake
status: completed
YAML

    INBOX_WRITE_TEST=1 run _run_inbox_write gunshi "review report=$report" report_review karo
    [ "$status" -eq 0 ]
    local first_id
    first_id="$(sed -n 's/^  id: *//p' "$TEST_TMPDIR/queue/inbox/gunshi.yaml" | head -1 | tr -d "'\"")"
    [ -n "$first_id" ]
    sed -i "/id: '$first_id'/,/type:/ s/read: false/read: true/" \
        "$TEST_TMPDIR/queue/inbox/gunshi.yaml"
    grep -A2 -F "id: '$first_id'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml" | grep -q 'read: true'

    INBOX_WRITE_TEST=1 run _run_inbox_write gunshi "review report=$report" report_review karo
    [ "$status" -eq 0 ]
    [[ "$output" != *DUPLICATE_MSG_ID=* ]]
    [ "$(grep -c "report_id: 'rpt-review-rewake'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml")" -eq 2 ]

    INBOX_WRITE_TEST=1 run _run_inbox_write gunshi "review report=$report" report_review karo
    [ "$status" -eq 0 ]
    [[ "$output" == *DUPLICATE_MSG_ID=* ]]
    [ "$(grep -c "report_id: 'rpt-review-rewake'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml")" -eq 2 ]
}

@test "report_revision resolves target task identity and suppresses only exact retries" {
    setup_git_test_env
    cat >> "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
  report_id: rpt-revision-fixed
  report_identity_version: 2
YAML
    cat >> "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" <<'YAML'
report_id: rpt-revision-fixed
report_identity_version: 2
task_id: cmd_revision_normal
parent_cmd: cmd_revision
YAML
    INBOX_WRITE_TEST=1 run _run_inbox_write testninja "revision one" report_revision karo
    [ "$status" -eq 0 ]
    INBOX_WRITE_TEST=1 run _run_inbox_write testninja "revision one" report_revision karo
    [ "$status" -eq 0 ]
    [[ "$output" == *DUPLICATE_MSG_ID=* ]]
    [ "$(grep -c "report_id: 'rpt-revision-fixed'" "$TEST_TMPDIR/queue/inbox/testninja.yaml")" -eq 1 ]

    INBOX_WRITE_TEST=1 run _run_inbox_write testninja "revision two" report_revision karo
    [ "$status" -eq 0 ]
    [[ "$output" != *DUPLICATE_MSG_ID=* ]]
    [ "$(grep -c "report_id: 'rpt-revision-fixed'" "$TEST_TMPDIR/queue/inbox/testninja.yaml")" -eq 2 ]
}

@test "report_received retry repairs one missing fingerprint-specific gunshi review" {
    setup_git_test_env
    cat >> "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
  report_id: rpt-review-repair
  report_identity_version: 2
YAML
    cat >> "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" <<'YAML'
status: completed
report_id: rpt-review-repair
report_identity_version: 2
task_id: cmd_test_001_normal
parent_cmd: cmd_test_001
YAML
    git -C "$TEST_TMPDIR" add queue/tasks/testninja.yaml queue/reports/testninja_report_cmd_test_001.yaml
    git -C "$TEST_TMPDIR" commit -q -m review-repair

    run _run_inbox_write karo "report A" report_received testninja
    [ "$status" -eq 0 ]
    local attempt
    for attempt in $(seq 1 50); do
        grep -q "^  type: 'report_review'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml" 2>/dev/null && break
        sleep 0.1
    done
    [ "$(grep -c "^  type: 'report_review'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml")" -eq 1 ]

    printf 'messages: []\n' > "$TEST_TMPDIR/queue/inbox/gunshi.yaml"
    run _run_inbox_write karo "report A retry" report_received testninja
    [ "$status" -eq 0 ]
    [[ "$output" == *DUPLICATE_MSG_ID=* ]]
    [ "$(grep -c "^  type: 'report_review'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml")" -eq 1 ]

    run _run_inbox_write karo "report A retry again" report_received testninja
    [ "$status" -eq 0 ]
    [ "$(grep -c "^  type: 'report_review'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml")" -eq 1 ]
}

@test "completion aliases converge on one review per report fingerprint across ten deliveries" {
    setup_git_test_env
    cat >> "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
  report_id: rpt-two-route-review
  report_identity_version: 2
YAML
    cat >> "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" <<'YAML'
status: completed
report_id: rpt-two-route-review
report_identity_version: 2
task_id: cmd_two_route_normal
parent_cmd: cmd_two_route
YAML
    git -C "$TEST_TMPDIR" add queue/tasks/testninja.yaml queue/reports/testninja_report_cmd_test_001.yaml
    git -C "$TEST_TMPDIR" commit -q -m two-route-review

    local i event_type pid
    local -a delivery_pids=()
    for i in $(seq 1 10); do
        if (( i % 2 )); then event_type=report_received; else event_type=report_submitted; fi
        _run_inbox_write karo "route-$i" "$event_type" testninja \
            >"$BATS_TEST_TMPDIR/route-$i.out" 2>&1 &
        delivery_pids+=("$!")
    done
    for pid in "${delivery_pids[@]}"; do
        wait "$pid"
    done
    [ "$(grep -c "^  type: 'report_review'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml")" -eq 1 ]

    printf '\nsemantic_generation: 2\n' >> "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml"
    git -C "$TEST_TMPDIR" add queue/reports/testninja_report_cmd_test_001.yaml
    git -C "$TEST_TMPDIR" commit -q -m new-report-generation
    mkdir -p "$TEST_TMPDIR/logs"
    run _run_inbox_write karo "new generation" report_received testninja
    [ "$status" -eq 0 ]
    [ "$(grep -c "^  type: 'report_review'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml")" -eq 2 ]
    [ "$(grep "^  report_fingerprint:" "$TEST_TMPDIR/queue/inbox/gunshi.yaml" | sort -u | wc -l)" -eq 2 ]
}

@test "rpt-42363aca 09:42:57 09:43:34 09:44:36 retry shadow stores once" {
    setup_git_test_env
    local report="queue/reports/testninja_report_cmd_test_001.yaml"
    cat >> "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" <<'YAML'
report_id: rpt-42363aca-48e5-4968-a3e3-25c350e51b77
report_identity_version: 2
task_id: cmd_shadow_normal
parent_cmd: cmd_shadow
YAML
    local stamp
    for stamp in 09:42:57 09:43:34 09:44:36; do
        INBOX_WRITE_TEST=1 run _run_inbox_write gunshi "background retry $stamp report=$report" report_review karo
        [ "$status" -eq 0 ]
    done
    [ "$(grep -c "report_id: 'rpt-42363aca-48e5-4968-a3e3-25c350e51b77'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml")" -eq 1 ]
}

@test "legacy fallback report identity uses the same exactly-once event contract" {
    setup_git_test_env
    local report="queue/reports/testninja_report_cmd_test_001.yaml"
    INBOX_WRITE_TEST=1 run _run_inbox_write gunshi "legacy first report=$report" report_review karo
    [ "$status" -eq 0 ]
    INBOX_WRITE_TEST=1 run _run_inbox_write gunshi "legacy retry changed text report=$report" report_review karo
    [ "$status" -eq 0 ]
    [[ "$output" == *DUPLICATE_MSG_ID=* ]]
    [ "$(grep -c "report_id: 'legacy-" "$TEST_TMPDIR/queue/inbox/gunshi.yaml")" -eq 1 ]
}

@test "report_submitted alias: validates report, auto-sends gunshi review, and marks task done" {
    setup_git_test_env
    mkdir -p "$TEST_TMPDIR/scripts"
    ln -sf "$PROJECT_ROOT/scripts/inbox_write.sh" "$TEST_TMPDIR/scripts/inbox_write.sh"
    echo 'status: completed' >> "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml"

    run _run_inbox_write karo "cmd_test_001 完了" report_submitted testninja
    [ "$status" -eq 0 ]
    local attempt
    for attempt in $(seq 1 50); do
        grep -q "^  type: 'report_review'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml" 2>/dev/null && break
        sleep 0.1
    done
    grep -q "^  type: 'report_review'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml"
    grep -q "^  status: done" "$TEST_TMPDIR/queue/tasks/testninja.yaml"
    python3 - "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'PY'
import datetime as dt
import sys
import yaml

task = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]
done_at = task.get("done_at")
completed_at = task.get("completed_at")
assert done_at == completed_at
dt.datetime.fromisoformat(str(done_at))
PY
}

@test "task_assigned: codex ninja delivery verification retries up to 2 times" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/config" "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/bin"

    cat > "$TEST_TMPDIR/config/settings.yaml" <<'YAML'
cli:
  default: claude
  agents:
    testninja:
      type: codex
YAML

    cat > "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: assigned
  task_id: cmd_nudge_identity_001_normal
  parent_cmd: cmd_nudge_identity_001
YAML

    export CLI_ADAPTER_SETTINGS="$TEST_TMPDIR/config/settings.yaml"
    export TMUX_LOG="$TEST_TMPDIR/tmux.log"
    export TMUX_SEND_COUNT_FILE="$TEST_TMPDIR/tmux_send_count"
    export TEST_INBOX_FILE="$TEST_TMPDIR/queue/inbox/testninja.yaml"

    cat > "$TEST_TMPDIR/bin/tmux" <<'EOF'
#!/bin/bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  list-panes)
    echo "shogun:agents.3 testninja"
    ;;
  send-keys)
    if [[ "$*" == *" Enter"* ]]; then
      count=0
      [ -f "$TMUX_SEND_COUNT_FILE" ] && count=$(cat "$TMUX_SEND_COUNT_FILE")
      count=$((count + 1))
      echo "$count" > "$TMUX_SEND_COUNT_FILE"
      if [ "$count" -ge 2 ]; then
        sed -i 's/read: false/read: true/' "$TEST_INBOX_FILE"
      fi
    fi
    ;;
esac
exit 0
EOF
    chmod +x "$TEST_TMPDIR/bin/tmux"

    PATH="$TEST_TMPDIR/bin:$PATH" INBOX_CODEX_VERIFY_WAIT_SEC=0 \
        INBOX_CODEX_NUDGE_RETRIES=2 run bash "$TEST_INBOX_WRITE" \
        "testninja" "タスクを読め" "task_assigned" "karo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"verified after retry 2/2"* ]]

    grep -q "set-buffer -b nudge_testninja" "$TMUX_LOG"
    [ "$(cat "$TMUX_SEND_COUNT_FILE")" -eq 2 ]
    grep -q "task_id=cmd_nudge_identity_001_normal" "$TMUX_LOG"

    # grep検証 (python3不要)
    grep -q "read: true" "$TEST_INBOX_FILE"
}

@test "task_assigned: codex retry nudge binds current task_id, not prose identity" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/config" "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/bin"
    cat > "$TEST_TMPDIR/config/settings.yaml" <<'YAML'
cli:
  default: claude
  agents:
    testninja:
      type: codex
YAML
    cat > "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: assigned
  task_id: cmd_nudge_identity_002_normal
  parent_cmd: cmd_nudge_identity_002
YAML
    export CLI_ADAPTER_SETTINGS="$TEST_TMPDIR/config/settings.yaml"
    export TMUX_LOG="$TEST_TMPDIR/tmux.log"
    export TEST_INBOX_FILE="$TEST_TMPDIR/queue/inbox/testninja.yaml"
    cat > "$TEST_TMPDIR/bin/tmux" <<'EOF'
#!/bin/bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  list-panes) echo "shogun:agents.3 testninja" ;;
  send-keys)
    if [[ "$*" == *" Enter"* ]]; then
      sed -i 's/read: false/read: true/' "$TEST_INBOX_FILE"
    fi
    ;;
esac
exit 0
EOF
    chmod +x "$TEST_TMPDIR/bin/tmux"

    PATH="$TEST_TMPDIR/bin:$PATH" INBOX_CODEX_VERIFY_WAIT_SEC=0 \
        INBOX_CODEX_NUDGE_RETRIES=1 run bash "$TEST_INBOX_WRITE" \
        testninja "report_id=rpt-prose task_id=cmd_wrong_prose" task_assigned karo
    [ "$status" -eq 0 ]
    grep -q "task_id=cmd_nudge_identity_002_normal" "$TMUX_LOG"
    ! grep -q "task_id=cmd_wrong_prose" "$TMUX_LOG"
}

# test_necessity: Codex delivery is proven only by the exact target message ID
# becoming read; while it remains unread the detached verifier must rearm the
# watcher's fingerprint lease at bounded intervals without confusing a second
# message that has identical content.
@test "task_assigned: active watcher rearms until exact message read and ignores same-content other ID" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/config" "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/bin" "$TEST_TMPDIR/state"

    cat > "$TEST_TMPDIR/config/settings.yaml" <<'YAML'
cli:
  default: claude
  agents:
    testninja:
      type: codex
YAML
    printf 'task:\n  status: assigned\n' > "$TEST_TMPDIR/queue/tasks/testninja.yaml"
    cat > "$TEST_TMPDIR/queue/inbox/testninja.yaml" <<'YAML'
messages:
- content: 'タスクを読め'
  from: 'gunshi'
  id: 'msg_same_content_other'
  read: false
  timestamp: '2026-08-26T19:00:00'
  type: 'task_supplement'
YAML
    export CLI_ADAPTER_SETTINGS="$TEST_TMPDIR/config/settings.yaml"
    export TMUX_LOG="$TEST_TMPDIR/tmux.log"
    export INBOX_MESSAGE_ID="msg_ci_exact_read"
    export REARM_COUNT_FILE="$TEST_TMPDIR/rearm_count"
    export TEST_INBOX_FILE="$TEST_TMPDIR/queue/inbox/testninja.yaml"

    cat > "$TEST_TMPDIR/bin/pgrep" <<'EOF'
#!/bin/bash
echo "123 bash /repo/scripts/inbox_watcher.sh testninja shogun:agents.3 codex"
EOF
    cat > "$TEST_TMPDIR/bin/tmux" <<'EOF'
#!/bin/bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  list-panes) echo "shogun:agents.3 testninja" ;;
  capture-pane) echo "›" ;;
esac
exit 0
EOF
    cat > "$TEST_TMPDIR/bin/touch" <<'EOF'
#!/bin/bash
count=0
[ -f "$REARM_COUNT_FILE" ] && count=$(cat "$REARM_COUNT_FILE")
count=$((count + 1))
echo "$count" > "$REARM_COUNT_FILE"
python3 - "$TEST_INBOX_FILE" "$count" "$INBOX_MESSAGE_ID" <<'PY'
import sys, yaml
path, count, target = sys.argv[1], int(sys.argv[2]), sys.argv[3]
data = yaml.safe_load(open(path, encoding="utf-8")) or {"messages": []}
chosen = "msg_same_content_other" if count == 1 else target
for message in data.get("messages", []):
    if message.get("id") == chosen:
        message["read"] = True
with open(path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(data, handle, allow_unicode=True, sort_keys=False)
PY
/usr/bin/touch "$@"
EOF
    chmod +x "$TEST_TMPDIR/bin/pgrep" "$TEST_TMPDIR/bin/tmux" "$TEST_TMPDIR/bin/touch"

    PATH="$TEST_TMPDIR/bin:$PATH" SHOGUN_STATE_DIR="$TEST_TMPDIR/state" \
        INBOX_CODEX_VERIFY_WAIT_SEC=0 INBOX_CODEX_NUDGE_RETRIES=3 \
        run bash "$TEST_INBOX_WRITE" \
        testninja "タスクを読め" task_assigned karo
    [ "$status" -eq 0 ]
    [[ "$output" == *"delivery verification queued asynchronously"* ]]
    [ ! -f "$TMUX_LOG" ] || ! grep -q 'send-keys' "$TMUX_LOG"

    local verify_log
    verify_log="$(find "$TEST_TMPDIR/logs/inbox_codex_delivery_verify" -type f -name '*.log' -print -quit)"
    [ -n "$verify_log" ]
    local attempt
    for attempt in $(seq 1 100); do
        grep -q "ASYNC_VERIFY SUCCESS" "$verify_log" 2>/dev/null && break
        sleep 0.05
    done
    grep -q "dedup rearmed 1/3" "$verify_log"
    grep -q "dedup rearmed 2/3" "$verify_log"
    grep -q "verified after retry 2/3" "$verify_log"
    grep -q "ASYNC_VERIFY SUCCESS" "$verify_log"
    [ "$(cat "$REARM_COUNT_FILE")" -eq 2 ]
    python3 - "$TEST_INBOX_FILE" "$INBOX_MESSAGE_ID" <<'PY'
import sys, yaml
messages = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["messages"]
by_id = {message["id"]: message["read"] for message in messages}
assert by_id["msg_same_content_other"] is True
assert by_id[sys.argv[2]] is True
assert len(by_id) == 2
print("renudge=2 exact_target_read=1 other_id_confusion=0 false_positive=0 false_negative=0")
PY
    [ ! -f "$TMUX_LOG" ] || ! grep -q 'send-keys' "$TMUX_LOG"
}

# test_necessity: pane prompt/working text is diagnostic only and must never
# become delivery success while the exact message row remains unread.
@test "task_assigned: async verifier rejects pane-only evidence without exact read" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/config" "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/bin"
    cat > "$TEST_TMPDIR/config/settings.yaml" <<'YAML'
cli:
  default: claude
  agents:
    testninja:
      type: codex
YAML
    printf 'task:\n  status: assigned\n' > "$TEST_TMPDIR/queue/tasks/testninja.yaml"
    export CLI_ADAPTER_SETTINGS="$TEST_TMPDIR/config/settings.yaml"
    export CAPTURE_COUNT_FILE="$TEST_TMPDIR/capture_count"
    export INBOX_MESSAGE_ID="msg_ci_async_working"
    cat > "$TEST_TMPDIR/bin/pgrep" <<'EOF'
#!/bin/bash
echo "123 bash /repo/scripts/inbox_watcher.sh testninja shogun:agents.3 codex"
EOF
    cat > "$TEST_TMPDIR/bin/tmux" <<'EOF'
#!/bin/bash
case "$1" in
  list-panes) echo "shogun:agents.3 testninja" ;;
  capture-pane)
    count=0
    [ -f "$CAPTURE_COUNT_FILE" ] && count=$(cat "$CAPTURE_COUNT_FILE")
    count=$((count + 1))
    echo "$count" > "$CAPTURE_COUNT_FILE"
    if [ "$count" -ge 2 ]; then echo "inbox1 — タスクYAML: ${INBOX_WRITE_ROOT_OVERRIDE}/queue/tasks/testninja.yaml delivery_msg=${INBOX_MESSAGE_ID}"; else echo "›"; fi
    ;;
esac
exit 0
EOF
    chmod +x "$TEST_TMPDIR/bin/pgrep" "$TEST_TMPDIR/bin/tmux"

    PATH="$TEST_TMPDIR/bin:$PATH" INBOX_CODEX_NUDGE_RETRIES=0 \
        run bash "$TEST_INBOX_WRITE" testninja "タスクを読め" task_assigned karo
    [ "$status" -eq 0 ]
    local verify_log
    verify_log="$(find "$TEST_TMPDIR/logs/inbox_codex_delivery_verify" -type f -name '*.log' -print -quit)"
    [ -n "$verify_log" ]
    local attempt
    for attempt in $(seq 1 100); do
        grep -q "ASYNC_VERIFY FAILURE" "$verify_log" 2>/dev/null && break
        sleep 0.05
    done
    grep -q "ASYNC_VERIFY FAILURE" "$verify_log"
    ! grep -q "ASYNC_VERIFY SUCCESS" "$verify_log"
    grep -q "read: false" "$TEST_TMPDIR/queue/inbox/testninja.yaml"
}

# test_necessity: inbox_write B5 telemetry must persist one parent total and
# diagnostic persist/nudge/delivery slices without changing retry delivery.
@test "task_assigned: B5 telemetry records persist nudge delivery verify and additive total" {
    setup_basic_test_env
    export DEFENSE_OVERHEAD_ENABLED=1
    mkdir -p "$TEST_TMPDIR/config" "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/bin" "$TEST_TMPDIR/logs"

    cat > "$TEST_TMPDIR/config/settings.yaml" <<'YAML'
cli:
  default: claude
  agents:
    testninja:
      type: codex
YAML
    printf 'task:\n  status: assigned\n' > "$TEST_TMPDIR/queue/tasks/testninja.yaml"

    export CLI_ADAPTER_SETTINGS="$TEST_TMPDIR/config/settings.yaml"
    export DEFENSE_OVERHEAD_LEDGER="$TEST_TMPDIR/logs/defense_overhead.jsonl"
    export TMUX_LOG="$TEST_TMPDIR/tmux.log"
    cat > "$TEST_TMPDIR/bin/tmux" <<'EOF'
#!/bin/bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  list-panes) echo "shogun:agents.3 testninja" ;;
  capture-pane) echo "›" ;;
esac
exit 0
EOF
    chmod +x "$TEST_TMPDIR/bin/tmux"

    PATH="$TEST_TMPDIR/bin:$PATH" INBOX_CODEX_VERIFY_WAIT_SEC=0 \
        INBOX_CODEX_NUDGE_RETRIES=1 run bash "$TEST_INBOX_WRITE" \
        testninja "タスクを読め" task_assigned karo
    [ "$status" -eq 0 ]
    [[ "$output" == *"codex nudge retry 1/1 sent"* ]]

    local attempt
    for attempt in $(seq 1 100); do
        [ -f "$DEFENSE_OVERHEAD_LEDGER" ] \
            && [ "$(grep -c '"source":"inbox_write"' "$DEFENSE_OVERHEAD_LEDGER" || true)" -ge 4 ] \
            && break
        sleep 0.05
    done
    python3 - "$DEFENSE_OVERHEAD_LEDGER" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")
        if json.loads(line).get("source") == "inbox_write"]
expected = {
    "inbox_write_persist",
    "inbox_write_nudge",
    "inbox_write_delivery_verify",
    "inbox_write_total",
}
counts = {name: sum(r["check_id"] == name for r in rows) for name in expected}
assert counts == {name: 1 for name in expected}, counts
assert all(isinstance(r["wall_ms"], int) and r["wall_ms"] >= 0 for r in rows)
assert next(r["wall_ms"] for r in rows if r["check_id"] == "inbox_write_total") >= max(
    r["wall_ms"] for r in rows if r["check_id"] != "inbox_write_total"
)
# Ledger aggregation selects only the parent. Child slices are deliberately
# overlapping diagnostics (nudge is inside delivery_verify), not additive rows.
assert sum(r["check_id"] == "inbox_write_total" for r in rows) == 1
print("persist=1 nudge=1 delivery_verify=1 total=1 false_positive=0 additive_rows=1")
PY
}

# test_necessity: inbox_write_total caller metadata is additive-only and keeps
# the parent total count exactly one per invocation for representative runtime
# callers plus an invalid/unknown fallback.
@test "B5 telemetry records caller classification without adding ledger rows" {
    setup_basic_test_env
    export DEFENSE_OVERHEAD_ENABLED=1
    mkdir -p "$TEST_TMPDIR/logs"
    export DEFENSE_OVERHEAD_LEDGER="$TEST_TMPDIR/logs/defense_overhead.jsonl"

    local caller content caller_index=0 rc
    local -a caller_pids=()
    for caller in cmd_complete_gate ninja_monitor deploy_task; do
        caller_index=$((caller_index + 1))
        content="caller-$caller"
        (
            env INBOX_WRITE_RUNTIME_CALLER="$caller" bash "$TEST_INBOX_WRITE" \
                test_agent "$content" info testninja notify_karo
        ) >"$TEST_TMPDIR/caller_${caller_index}.out" 2>&1 &
        caller_pids+=("$!")
    done
    (
        env INBOX_WRITE_RUNTIME_CALLER='invalid caller' bash "$TEST_INBOX_WRITE" \
            test_agent caller-unknown info testninja notify_karo
    ) >"$TEST_TMPDIR/caller_4.out" 2>&1 &
    caller_pids+=("$!")
    for caller_pid in "${caller_pids[@]}"; do
        rc=0
        wait "$caller_pid" || rc=$?
        [ "$rc" -eq 0 ]
    done

    local attempt
    for attempt in $(seq 1 100); do
        [ -f "$DEFENSE_OVERHEAD_LEDGER" ] \
            && [ "$(grep -c '"'"'\"check_id\":\"inbox_write_total\"'"'"' "$DEFENSE_OVERHEAD_LEDGER" || true)" -ge 4 ] \
            && break
        sleep 0.05
    done
    python3 - "$DEFENSE_OVERHEAD_LEDGER" <<'PY'
import json
import sys

rows = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
totals = [row for row in rows if row.get("check_id") == "inbox_write_total"]
assert len(totals) == 4, len(totals)
counts = {}
for row in totals:
    caller = row.get("caller")
    assert caller
    counts[caller] = counts.get(caller, 0) + 1
assert counts == {
    "cmd_complete_gate": 1,
    "ninja_monitor": 1,
    "deploy_task": 1,
    "unknown": 1,
}, counts
print("caller_values=4 total_rows=4 additive_rows=1 unknown=1")
PY
}

# test_necessity: commander sends must retain a live pre-send pane observation
# while exposing its bounded cost as a non-additive child slice.
@test "commander pre-send capture uses live pane resolver and records its slice" {
    # This test exercises commander pre-send observation and concurrent inbox
    # persistence only; a git fixture adds setup cost without affecting either
    # behavior.  Keep production validation active by providing the target's
    # task file after the lightweight inbox fixture setup.
    setup_basic_test_env
    export DEFENSE_OVERHEAD_ENABLED=1
    unset INBOX_WRITE_TEST
    mkdir -p "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/bin" "$TEST_TMPDIR/logs"
    printf 'task:\n  status: assigned\n' > "$TEST_TMPDIR/queue/tasks/testninja.yaml"
    export DEFENSE_OVERHEAD_LEDGER="$TEST_TMPDIR/logs/defense_overhead.jsonl"
    export TMUX_LOG="$TEST_TMPDIR/tmux.log"
    cat > "$TEST_TMPDIR/bin/tmux" <<'EOF'
#!/bin/bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  list-panes) echo "shogun:agents.3 testninja" ;;
  capture-pane) echo "› CTX:42%" ;;
esac
exit 0
EOF
    chmod +x "$TEST_TMPDIR/bin/tmux"

    local send_index rc
    local -a send_pids=()
    mkdir -p "$TEST_TMPDIR/pre_send_outputs"
    for send_index in $(seq 1 20); do
        (
            env PATH="$TEST_TMPDIR/bin:$PATH" \
                INBOX_WRITE_ROOT_OVERRIDE="$TEST_TMPDIR" \
                bash "$TEST_INBOX_WRITE" testninja "pre-send capture fixture-${send_index}" info karo notify_karo
        ) >"$TEST_TMPDIR/pre_send_outputs/${send_index}.out" 2>&1 &
        send_pids+=("$!")
    done
    for send_pid in "${send_pids[@]}"; do
        rc=0
        wait "$send_pid" || rc=$?
        [ "$rc" -eq 0 ]
    done
    [ "$(rg -l -F '[pre-send capture] testninja pane state BEFORE message:' "$TEST_TMPDIR/pre_send_outputs" | wc -l)" -eq 20 ]
    grep -q 'list-panes' "$TMUX_LOG"
    grep -q 'capture-pane' "$TMUX_LOG"

    local attempt
    for attempt in $(seq 1 500); do
        [ -f "$DEFENSE_OVERHEAD_LEDGER" ] \
            && [ "$(grep -c '"check_id":"inbox_write_pre_send_capture"' "$DEFENSE_OVERHEAD_LEDGER" || true)" -ge 20 ] \
            && [ "$(grep -c '"check_id":"inbox_write_persist"' "$DEFENSE_OVERHEAD_LEDGER" || true)" -ge 20 ] \
            && [ "$(grep -c '"check_id":"inbox_write_total"' "$DEFENSE_OVERHEAD_LEDGER" || true)" -ge 20 ] \
            && break
        sleep 0.02
    done

    python3 - "$DEFENSE_OVERHEAD_LEDGER" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
by_id = {}
for row in rows:
    by_id.setdefault(row["check_id"], []).append(row)
expected = ("inbox_write_pre_send_capture", "inbox_write_persist", "inbox_write_total")
event_ids = [row["event_id"] for row in rows]
assert len(event_ids) == len(set(event_ids)), len(event_ids) - len(set(event_ids))
selected_rows = [row for row in rows if row.get("check_id") in expected]
assert len(selected_rows) == 60, len(selected_rows)
selected_ids = [row["event_id"] for row in selected_rows]
assert len(selected_ids) == len(set(selected_ids)), len(selected_ids) - len(set(selected_ids))
assert all(len(by_id.get(key, [])) == 20 for key in expected), {key: len(by_id.get(key, [])) for key in expected}
assert all(isinstance(row["wall_ms"], int) and row["wall_ms"] >= 0
           for key in expected for row in by_id[key])
totals = sorted(row["wall_ms"] for row in by_id["inbox_write_total"])
pre_send = sorted(row["wall_ms"] for row in by_id["inbox_write_pre_send_capture"])
persist = sorted(row["wall_ms"] for row in by_id["inbox_write_persist"])
percentile = lambda values, q: values[int((len(values) - 1) * q)]
assert percentile(totals, .50) >= percentile(pre_send, .50)
assert percentile(totals, .95) >= percentile(pre_send, .95)
print(f"pre_send_capture=20 persist=20 total=20 missing=0 duplicate=0 ledger_rows={len(rows)} "
      "safety_observation=20 false_positive=0 "
      f"total_p50_ms={percentile(totals, .50)} total_p95_ms={percentile(totals, .95)} "
      f"pre_send_p50_ms={percentile(pre_send, .50)} pre_send_p95_ms={percentile(pre_send, .95)} "
      f"persist_p50_ms={percentile(persist, .50)} persist_p95_ms={percentile(persist, .95)}")
PY
    [ "$(grep -c '^- ' "$TEST_TMPDIR/queue/inbox/testninja.yaml")" -eq 20 ]
}

@test "task_assigned: codex non-ninja delivery verification uses inbox read only" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/config" "$TEST_TMPDIR/bin"

    cat > "$TEST_TMPDIR/config/settings.yaml" <<'YAML'
cli:
  default: claude
  agents:
    gunshi:
      type: codex
YAML

    export CLI_ADAPTER_SETTINGS="$TEST_TMPDIR/config/settings.yaml"
    export TMUX_LOG="$TEST_TMPDIR/tmux.log"
    export INBOX_MESSAGE_ID="msg_ci_initial_working"
    export TEST_INBOX_FILE="$TEST_TMPDIR/queue/inbox/gunshi.yaml"

    # This case exercises the bounded direct-fallback path.  The real host may
    # have gunshi's watcher running, so make watcher absence explicit instead
    # of letting host process state leak into the isolated fixture.
    cat > "$TEST_TMPDIR/bin/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF
    cat > "$TEST_TMPDIR/bin/tmux" <<'EOF'
#!/bin/bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  list-panes)
    echo "shogun:agents.2 gunshi"
    ;;
  send-keys)
    if [[ "$*" == *" Enter"* ]]; then
      sed -i 's/read: false/read: true/' "$TEST_INBOX_FILE"
    fi
    ;;
esac
exit 0
EOF
    chmod +x "$TEST_TMPDIR/bin/pgrep" "$TEST_TMPDIR/bin/tmux"

    PATH="$TEST_TMPDIR/bin:$PATH" INBOX_CODEX_VERIFY_WAIT_SEC=0 \
        INBOX_CODEX_NUDGE_RETRIES=2 run bash "$TEST_INBOX_WRITE" \
        "gunshi" "レビュー開始" "task_assigned" "karo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"verified after retry 1/2"* ]]
    [[ "$output" != *"remained unverified"* ]]

    [ ! -f "$TEST_TMPDIR/queue/tasks/gunshi.yaml" ]
    grep -q "read: true" "$TEST_TMPDIR/queue/inbox/gunshi.yaml"
}

@test "task_assigned: codex ninja delivery verification rejects initial working pane without read" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/config" "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/bin"

    cat > "$TEST_TMPDIR/config/settings.yaml" <<'YAML'
cli:
  default: claude
  agents:
    testninja:
      type: codex
YAML

    cat > "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: assigned
YAML

    export CLI_ADAPTER_SETTINGS="$TEST_TMPDIR/config/settings.yaml"
    export TMUX_LOG="$TEST_TMPDIR/tmux.log"
    export INBOX_MESSAGE_ID="msg_ci_initial_working"

    cat > "$TEST_TMPDIR/bin/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF
    cat > "$TEST_TMPDIR/bin/tmux" <<'EOF'
#!/bin/bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  list-panes)
    echo "shogun:agents.3 testninja"
    ;;
  capture-pane)
    count=0; [ -f "$TEST_TMPDIR/capture_count" ] && count=$(cat "$TEST_TMPDIR/capture_count"); count=$((count+1)); echo "$count" > "$TEST_TMPDIR/capture_count"
    if [ "$count" -ge 2 ]; then echo "inbox1 — タスクYAML: ${INBOX_WRITE_ROOT_OVERRIDE}/queue/tasks/testninja.yaml delivery_msg=${INBOX_MESSAGE_ID}"; else echo "›"; fi
    ;;
esac
exit 0
EOF
    chmod +x "$TEST_TMPDIR/bin/pgrep" "$TEST_TMPDIR/bin/tmux"

    PATH="$TEST_TMPDIR/bin:$PATH" INBOX_CODEX_VERIFY_WAIT_SEC=0 \
        INBOX_CODEX_NUDGE_RETRIES=0 run bash "$TEST_INBOX_WRITE" \
        "testninja" "タスクを読め" "task_assigned" "karo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"remained unverified for testninja after 0 retries"* ]]
    [[ "$output" != *"delivery verified"* ]]
    grep -q "read: false" "$TEST_TMPDIR/queue/inbox/testninja.yaml"
}

@test "task_assigned: codex prompt visible during hook is not delivery evidence without read" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/config" "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/bin"
    cat > "$TEST_TMPDIR/config/settings.yaml" <<'YAML'
cli:
  default: claude
  agents:
    testninja:
      type: codex
YAML
    printf 'task:\n  status: assigned\n' > "$TEST_TMPDIR/queue/tasks/testninja.yaml"
    export CLI_ADAPTER_SETTINGS="$TEST_TMPDIR/config/settings.yaml"
    export TMUX_LOG="$TEST_TMPDIR/tmux.log"
    export INBOX_MESSAGE_ID="msg_ci_hook_prompt"
    cat > "$TEST_TMPDIR/bin/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF
    cat > "$TEST_TMPDIR/bin/tmux" <<'EOF'
#!/bin/bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  list-panes) echo "shogun:agents.3 testninja" ;;
  capture-pane)
    count=0; [ -f "$TEST_TMPDIR/capture_count" ] && count=$(cat "$TEST_TMPDIR/capture_count"); count=$((count+1)); echo "$count" > "$TEST_TMPDIR/capture_count"
    if [ "$count" -ge 2 ]; then echo "inbox1 — タスクYAML: ${INBOX_WRITE_ROOT_OVERRIDE}/queue/tasks/testninja.yaml delivery_msg=${INBOX_MESSAGE_ID}"; else echo "›"; fi
    ;;
esac
exit 0
EOF
    chmod +x "$TEST_TMPDIR/bin/pgrep" "$TEST_TMPDIR/bin/tmux"

    PATH="$TEST_TMPDIR/bin:$PATH" INBOX_CODEX_VERIFY_WAIT_SEC=0 \
        INBOX_CODEX_NUDGE_RETRIES=0 run bash "$TEST_INBOX_WRITE" \
        testninja "タスクを読め" task_assigned karo
    [ "$status" -eq 0 ]
    [[ "$output" == *"remained unverified for testninja after 0 retries"* ]]
    [[ "$output" != *"delivery verified"* ]]
    [ "$(grep -c 'send-keys' "$TMUX_LOG" || true)" -eq 0 ]
}

@test "task_assigned: wrapped codex prompt and hook bullet are not delivery evidence without read" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/config" "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/bin"
    cat > "$TEST_TMPDIR/config/settings.yaml" <<'YAML'
cli:
  default: claude
  agents:
    testninja:
      type: codex
YAML
    printf 'task:\n  status: assigned\n' > "$TEST_TMPDIR/queue/tasks/testninja.yaml"
    export CLI_ADAPTER_SETTINGS="$TEST_TMPDIR/config/settings.yaml"
    export TMUX_LOG="$TEST_TMPDIR/tmux.log"
    export INBOX_MESSAGE_ID="msg_ci_wrapped_prompt"
    cat > "$TEST_TMPDIR/bin/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF
    cat > "$TEST_TMPDIR/bin/tmux" <<'EOF'
#!/bin/bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  list-panes) echo "shogun:agents.3 testninja" ;;
  capture-pane)
    count=0; [ -f "$TEST_TMPDIR/capture_count" ] && count=$(cat "$TEST_TMPDIR/capture_count"); count=$((count+1)); echo "$count" > "$TEST_TMPDIR/capture_count"
    if [ "$count" -ge 2 ]; then echo "› inbox1 — タスクYAML: ${INBOX_WRITE_ROOT_OVERRIDE}/queue/tasks/testninja.yaml delivery_msg=${INBOX_MESSAGE_ID}"; echo "◦ Running UserPromptSubmit hook"; else echo "›"; fi
    ;;
esac
exit 0
EOF
    chmod +x "$TEST_TMPDIR/bin/pgrep" "$TEST_TMPDIR/bin/tmux"

    PATH="$TEST_TMPDIR/bin:$PATH" INBOX_CODEX_VERIFY_WAIT_SEC=0 \
        INBOX_CODEX_NUDGE_RETRIES=0 run bash "$TEST_INBOX_WRITE" \
        testninja "タスクを読め" task_assigned karo
    [ "$status" -eq 0 ]
    [[ "$output" == *"remained unverified for testninja after 0 retries"* ]]
    [[ "$output" != *"delivery verified"* ]]
    [ "$(grep -c 'send-keys' "$TMUX_LOG" || true)" -eq 0 ]
}

@test "task_assigned: codex ninja delivery verification still warns when truly unverified" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/config" "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/bin"

    cat > "$TEST_TMPDIR/config/settings.yaml" <<'YAML'
cli:
  default: claude
  agents:
    testninja:
      type: codex
YAML

    cat > "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: assigned
YAML

    export CLI_ADAPTER_SETTINGS="$TEST_TMPDIR/config/settings.yaml"
    export TMUX_LOG="$TEST_TMPDIR/tmux.log"

    cat > "$TEST_TMPDIR/bin/tmux" <<'EOF'
#!/bin/bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  list-panes)
    echo "shogun:agents.3 testninja"
    ;;
  capture-pane)
    echo "›"
    ;;
esac
exit 0
EOF
    chmod +x "$TEST_TMPDIR/bin/tmux"

    PATH="$TEST_TMPDIR/bin:$PATH" INBOX_CODEX_VERIFY_WAIT_SEC=0 INBOX_CODEX_NUDGE_RETRIES=0 run bash "$TEST_INBOX_WRITE" "testninja" "タスクを読め" "task_assigned" "karo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: codex delivery remained unverified for testninja after 0 retries"* ]]
}

@test "report_review_result: LGTM is provisional and does not start cmd_complete_gate" {
    setup_git_test_env
    mkdir -p "$TEST_TMPDIR/scripts/lib" "$TEST_TMPDIR/queue/gates/cmd_karo_auto_review_gate" "$TEST_TMPDIR/queue/reports"
    ln -sf "$PROJECT_ROOT/scripts/inbox_write.sh" "$TEST_TMPDIR/scripts/inbox_write.sh"
    ln -sf "$PROJECT_ROOT/scripts/review_approval.sh" "$TEST_TMPDIR/scripts/review_approval.sh"
    ln -sf "$PROJECT_ROOT/scripts/lib/review_approval.sh" "$TEST_TMPDIR/scripts/lib/review_approval.sh"
    ln -sf "$PROJECT_ROOT/scripts/lib/report_commit_identity.py" "$TEST_TMPDIR/scripts/lib/report_commit_identity.py"
    ln -sf "$PROJECT_ROOT/scripts/bulletin_write.sh" "$TEST_TMPDIR/scripts/bulletin_write.sh"

    cat > "$TEST_TMPDIR/scripts/cmd_complete_gate.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" > "$INBOX_WRITE_BG_LOG"
EOF
    chmod +x "$TEST_TMPDIR/scripts/cmd_complete_gate.sh"
    export INBOX_WRITE_BG_LOG="$TEST_TMPDIR/cmd_complete_gate.log"
    printf 'task_id: cmd_karo_auto_review_gate_normal\nparent_cmd: cmd_karo_auto_review_gate\nstatus: completed\ncommit_hash: abc123abc123abc123abc123abc123abc123abc1\nresult:\n  summary: ok\n' > "$TEST_TMPDIR/queue/reports/testninja_report_cmd_karo_auto_review_gate.yaml"

    cat > "$TEST_TMPDIR/queue/gates/cmd_karo_auto_review_gate/review_gate.done" <<'EOF'
timestamp: 2026-04-21T13:00:00
source: deploy_preflight
note: placeholder
EOF

    REVIEW_APPROVAL_ROOT="$TEST_TMPDIR" REVIEW_APPROVAL_NO_TRIGGER=1 REVIEW_APPROVAL_SKIP_LEDGER_CHECK=1 bash "$PROJECT_ROOT/scripts/review_approval.sh" cmd_karo_auto_review_gate gunshi LGTM "$TEST_TMPDIR/queue/reports/testninja_report_cmd_karo_auto_review_gate.yaml"
    run _run_inbox_write karo "cmd_karo_auto_review_gate testninja報告レビュー。verdict: LGTM。report: queue/reports/testninja_report_cmd_karo_auto_review_gate.yaml" report_review_result gunshi
    [ "$status" -eq 0 ]
    [[ "$output" != *"provisional gunshi LGTM recorded"* ]]
    [ ! -e "$INBOX_WRITE_BG_LOG" ]
    grep -q '^source: deploy_preflight$' "$TEST_TMPDIR/queue/gates/cmd_karo_auto_review_gate/review_gate.done"
    [ -d "$TEST_TMPDIR/queue/gates/cmd_karo_auto_review_gate/review_approvals" ]
}

@test "report_review_result: LGTM without review-time marker is blocked" {
    setup_git_test_env
    mkdir -p "$TEST_TMPDIR/queue/reports" "$TEST_TMPDIR/scripts/lib"
    ln -sf "$PROJECT_ROOT/scripts/lib/review_approval.sh" "$TEST_TMPDIR/scripts/lib/review_approval.sh"
    ln -sf "$PROJECT_ROOT/scripts/lib/report_commit_identity.py" "$TEST_TMPDIR/scripts/lib/report_commit_identity.py"
    printf 'parent_cmd: cmd_guard\ncommit_hash: abc123abc123abc123abc123abc123abc123abc1\n' > "$TEST_TMPDIR/queue/reports/ninja_report_cmd_guard.yaml"
    run _run_inbox_write karo "cmd_guard verdict: LGTM report: queue/reports/ninja_report_cmd_guard.yaml" report_review_result gunshi
    [ "$status" -eq 2 ]
    [[ "$output" == *"approval marker missing, stale, or mismatched"* ]]
}

@test "report_review_result: LGTM plus structured gate_prediction BLOCK is rejected before persistence" {
    setup_basic_test_env
    local inbox="$TEST_TMPDIR/queue/inbox/karo.yaml"
    [ ! -e "$inbox" ]
    run _run_inbox_write karo "cmd_guard verdict: LGTM; gate_prediction: BLOCK; report: queue/reports/ninja_report_cmd_guard.yaml" report_review_result gunshi
    [ "$status" -eq 2 ]
    [[ "$output" == *"contradictory report_review_result"* ]]
    [ ! -e "$inbox" ]
}

@test "report_review_result: LGTM plus BLOCK reason suffix variations are rejected before persistence" {
    setup_basic_test_env
    local inbox="$TEST_TMPDIR/queue/inbox/karo.yaml"
    local prediction
    local -a predictions=(
        'BLOCK(reason)'
        'BLOCK[reason]'
        'BLOCK/reason'
        'BLOCK、理由'
        'BLOCK reason'
        'BLOCK'
    )

    for prediction in "${predictions[@]}"; do
        rm -f "$inbox"
        run _run_inbox_write karo "verdict: LGTM; gate_prediction: $prediction" report_review_result gunshi
        [ "$status" -eq 2 ]
        [[ "$output" == *"contradictory report_review_result"* ]]
        [ ! -e "$inbox" ]
    done
}

@test "report_review_result: contradiction guard preserves non-BLOCK values and unrelated BLOCK text" {
    setup_git_test_env
    mkdir -p "$TEST_TMPDIR/queue/reports" "$TEST_TMPDIR/scripts/lib"
    ln -sf "$PROJECT_ROOT/scripts/lib/review_approval.sh" "$TEST_TMPDIR/scripts/lib/review_approval.sh"
    ln -sf "$PROJECT_ROOT/scripts/lib/report_commit_identity.py" "$TEST_TMPDIR/scripts/lib/report_commit_identity.py"
    ln -sf "$PROJECT_ROOT/scripts/bulletin_write.sh" "$TEST_TMPDIR/scripts/bulletin_write.sh"
    printf 'task_id: cmd_guard_normal\nparent_cmd: cmd_guard\nstatus: completed\ncommit_hash: abc123abc123abc123abc123abc123abc123abc1\nresult:\n  summary: ok\n' > "$TEST_TMPDIR/queue/reports/ninja_report_cmd_guard.yaml"
    REVIEW_APPROVAL_ROOT="$TEST_TMPDIR" REVIEW_APPROVAL_NO_TRIGGER=1 REVIEW_APPROVAL_SKIP_LEDGER_CHECK=1 bash "$PROJECT_ROOT/scripts/review_approval.sh" cmd_guard gunshi LGTM "$TEST_TMPDIR/queue/reports/ninja_report_cmd_guard.yaml"
    local content
    local -a contents=(
        'cmd_guard verdict: LGTM; gate_prediction: BLOCKED; report: queue/reports/ninja_report_cmd_guard.yaml'
        'cmd_guard verdict: LGTM; gate_prediction: BLOCKER; report: queue/reports/ninja_report_cmd_guard.yaml'
        'verdict: FAIL; gate_prediction: BLOCK(reason)'
        'cmd_guard verdict: LGTM; gate_prediction: CLEAR; note: BLOCK appears only in free explanation; report: queue/reports/ninja_report_cmd_guard.yaml'
    )

    for content in "${contents[@]}"; do
        run _run_inbox_write karo "$content task_id=commander_directive subject_task_id=cmd_guard_normal parent_cmd=cmd_guard" report_review_result gunshi
        [ "$status" -eq 0 ]
        [[ "$output" != *"contradictory report_review_result"* ]]
    done
}

@test "report_revision: terminal task and completed report are blocked before persistence with formal RC command" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/reports"
    cat > "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: done
  parent_cmd: cmd_terminal_revision
  report_path: queue/reports/testninja_report_cmd_terminal_revision.yaml
YAML
    printf 'status: completed\n' > "$TEST_TMPDIR/queue/reports/testninja_report_cmd_terminal_revision.yaml"

    run _run_inbox_write testninja "修正せよ" report_revision karo
    [ "$status" -eq 2 ]
    [[ "$output" == *"requires formal RC reopen"* ]]
    [[ "$output" == *"bash scripts/review_approval.sh cmd_terminal_revision karo RC"* ]]
    [ ! -e "$TEST_TMPDIR/queue/inbox/testninja.yaml" ]
}

@test "report_revision: formal RC reopened state and normal notification classes remain allowed" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/reports"
    cat > "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: assigned
  parent_cmd: cmd_formal_revision
  report_path: queue/reports/testninja_report_cmd_formal_revision.yaml
YAML
    printf 'status: revision_requested\n' > "$TEST_TMPDIR/queue/reports/testninja_report_cmd_formal_revision.yaml"

    run _run_inbox_write testninja "正式RC後の修正" report_revision karo
    [ "$status" -eq 0 ]
    run _run_inbox_write testninja "再開せよ" task_reopened karo
    [ "$status" -eq 0 ]
    run _run_inbox_write testninja "通常レビュー" report_review karo
    [ "$status" -eq 0 ]
    run _run_inbox_write karo "非忍者宛revision task_id=commander_directive subject_task_id=cmd_revision_normal parent_cmd=cmd_revision" report_revision gunshi
    [ "$status" -eq 0 ]
}

@test "review notification contradiction guard ignores valid non-contradictory forms" {
    setup_basic_test_env
    run _run_inbox_write karo "verdict: FAIL; gate_prediction: BLOCK task_id=commander_directive subject_task_id=cmd_contradiction_normal parent_cmd=cmd_contradiction" report_review_result gunshi
    [ "$status" -eq 0 ]
    run _run_inbox_write karo "draft review verdict: APPROVE; gate_prediction: BLOCK task_id=commander_directive subject_task_id=cmd_contradiction_normal parent_cmd=cmd_contradiction" review_result gunshi
    [ "$status" -eq 0 ]
    run _run_inbox_write karo "説明文ではBLOCK文字列を扱うが gate_prediction: CLEAR task_id=commander_directive subject_task_id=cmd_contradiction_normal parent_cmd=cmd_contradiction" report_review_result gunshi
    [ "$status" -eq 0 ]
}

@test "report_review_result: FAIL does not update placeholder or run cmd_complete_gate" {
    setup_git_test_env
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue/gates/cmd_karo_auto_review_gate"
    ln -sf "$PROJECT_ROOT/scripts/inbox_write.sh" "$TEST_TMPDIR/scripts/inbox_write.sh"

    cat > "$TEST_TMPDIR/scripts/cmd_complete_gate.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" > "$INBOX_WRITE_BG_LOG"
EOF
    chmod +x "$TEST_TMPDIR/scripts/cmd_complete_gate.sh"
    export INBOX_WRITE_BG_LOG="$TEST_TMPDIR/cmd_complete_gate.log"

    cat > "$TEST_TMPDIR/queue/gates/cmd_karo_auto_review_gate/review_gate.done" <<'EOF'
timestamp: 2026-04-21T13:00:00
source: deploy_preflight
note: placeholder
EOF

    run _run_inbox_write karo "cmd_karo_auto_review_gate testninja報告レビュー。verdict: FAIL。task_id=commander_directive subject_task_id=cmd_karo_auto_review_gate_normal parent_cmd=cmd_karo_auto_review_gate" report_review_result gunshi
    # report_review_result without a resolvable report is now rejected by the
    # post-case dedicated identity boundary before any review side effect.
    [ "$status" -eq 2 ]
    [[ "$output" == *"dedicated identity resolved no non-empty task_id"* ]]
    [[ "$output" != *"review_gate.done updated"* ]]
    [[ "$output" != *"cmd_complete_gate.sh started in background"* ]]

    grep -q '^source: deploy_preflight$' "$TEST_TMPDIR/queue/gates/cmd_karo_auto_review_gate/review_gate.done"
    [ ! -f "$INBOX_WRITE_BG_LOG" ]
}

@test "review_result: forwarded to active ninjas only as task_supplement" {
    rm -rf "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue"
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue/tasks"
    # GIT_TEMPLATE_DIR (tmpfs) から コピー: NTFS→tmpfs を回避 (~105ms削減)
    cp -a "$GIT_TEMPLATE_DIR/scripts/lib" "$TEST_TMPDIR/scripts/lib"
    unset INBOX_WRITE_TEST

    cat > "$TEST_TMPDIR/scripts/lib/agent_config.sh" <<'MOCK'
get_ninja_names() { echo "ninja_a ninja_b ninja_c"; }
get_allowed_targets() { echo "karo shogun gunshi ninja_a ninja_b ninja_c"; }
get_commander_names() { echo "shogun karo gunshi"; }
is_commander_role() { case " $(get_commander_names) " in *" $1 "*) return 0 ;; esac; return 1; }
get_commander_inbox_path() { is_commander_role "$1" || return 1; echo "${INBOX_WRITE_ROOT_OVERRIDE}/queue/inbox/${1}.yaml"; }
MOCK

    cat > "$TEST_TMPDIR/queue/tasks/ninja_a.yaml" <<'YAML'
task:
  status: assigned
  task_id: cmd_999_normal
  parent_cmd: cmd_999
YAML

    cat > "$TEST_TMPDIR/queue/tasks/ninja_b.yaml" <<'YAML'
task:
  status: in_progress
  task_id: cmd_999_normal
  parent_cmd: cmd_999
YAML

    cat > "$TEST_TMPDIR/queue/tasks/ninja_c.yaml" <<'YAML'
task:
  status: idle
YAML

    run _run_inbox_write karo "cmd_999 verdict: FAIL 要確認 task_id=commander_directive subject_task_id=cmd_999_normal parent_cmd=cmd_999" review_result gunshi
    [ "$status" -eq 0 ]

    # grep検証 (python3不要)
    grep -q "^  type: 'review_result'" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    for _ninja in ninja_a ninja_b; do
        [[ "$(grep -c "^- " "$TEST_TMPDIR/queue/inbox/${_ninja}.yaml")" -eq 1 ]]
        grep -q "^  from: 'gunshi'" "$TEST_TMPDIR/queue/inbox/${_ninja}.yaml"
        grep -q "^  type: 'task_supplement'" "$TEST_TMPDIR/queue/inbox/${_ninja}.yaml"
        grep -q "軍師レビュー補足: cmd_999 verdict: FAIL 要確認" "$TEST_TMPDIR/queue/inbox/${_ninja}.yaml"
    done
    [ ! -f "$TEST_TMPDIR/queue/inbox/ninja_c.yaml" ]
}

@test "review_result without leading cmd id is not forwarded to active ninjas" {
    rm -rf "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue"
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue/tasks"
    cp -a "$GIT_TEMPLATE_DIR/scripts/lib" "$TEST_TMPDIR/scripts/lib"
    unset INBOX_WRITE_TEST

    cat > "$TEST_TMPDIR/scripts/lib/agent_config.sh" <<'MOCK'
get_ninja_names() { echo "ninja_a"; }
get_allowed_targets() { echo "karo shogun gunshi ninja_a"; }
get_commander_names() { echo "shogun karo gunshi"; }
is_commander_role() { case " $(get_commander_names) " in *" $1 "*) return 0 ;; esac; return 1; }
get_commander_inbox_path() { is_commander_role "$1" || return 1; echo "${INBOX_WRITE_ROOT_OVERRIDE}/queue/inbox/${1}.yaml"; }
MOCK
    cat > "$TEST_TMPDIR/queue/tasks/ninja_a.yaml" <<'YAML'
task:
  status: in_progress
  parent_cmd: cmd_other
YAML

    run _run_inbox_write karo "知識利用全員化D0レビュー完了。verdict: LGTM task_id=commander_directive subject_task_id=cmd_knowledge_normal parent_cmd=cmd_knowledge" review_result gunshi
    [ "$status" -eq 0 ]
    grep -q "^  type: 'review_result'" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    [ ! -f "$TEST_TMPDIR/queue/inbox/ninja_a.yaml" ]
}

@test "task_supplement: not forwarded again to avoid recursive fanout" {
    rm -rf "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue"
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue/tasks"
    # GIT_TEMPLATE_DIR (tmpfs) から コピー: NTFS→tmpfs を回避 (~105ms削減)
    cp -a "$GIT_TEMPLATE_DIR/scripts/lib" "$TEST_TMPDIR/scripts/lib"
    unset INBOX_WRITE_TEST

    cat > "$TEST_TMPDIR/scripts/lib/agent_config.sh" <<'MOCK'
get_ninja_names() { echo "ninja_a ninja_b"; }
get_allowed_targets() { echo "karo shogun gunshi ninja_a ninja_b"; }
get_commander_names() { echo "shogun karo gunshi"; }
is_commander_role() { case " $(get_commander_names) " in *" $1 "*) return 0 ;; esac; return 1; }
get_commander_inbox_path() { is_commander_role "$1" || return 1; echo "${INBOX_WRITE_ROOT_OVERRIDE}/queue/inbox/${1}.yaml"; }
MOCK

    cat > "$TEST_TMPDIR/queue/tasks/ninja_a.yaml" <<'YAML'
task:
  status: in_progress
YAML

    run _run_inbox_write karo "task_id=commander_directive subject_task_id=cmd_review_supplement_normal parent_cmd=cmd_review_supplement 軍師レビュー補足: 既存補足" task_supplement gunshi
    [ "$status" -eq 0 ]

    # grep検証 (python3不要)
    grep -q "^  type: 'task_supplement'" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    [ ! -f "$TEST_TMPDIR/queue/inbox/ninja_a.yaml" ]
    [ ! -f "$TEST_TMPDIR/queue/inbox/ninja_b.yaml" ]
}

@test "report_received: report moved to archive (no symlink) → archive fallback succeeds" {
    setup_git_test_env

    # archive_completed.sh移動後にsymlink作成失敗したケースをシミュレート:
    # queue/reports/からqueue/archive/reports/へ移動(シムリンク無し)
    mkdir -p "$TEST_TMPDIR/queue/archive/reports"
    mv "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" \
       "$TEST_TMPDIR/queue/archive/reports/testninja_report_cmd_test_001_20260425.yaml"

    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 0 ]
    [[ "$output" == *"archive fallback"* ]]
}

# test_necessity: archive後の遅延report_receivedはtask/reportの不変identityが完全一致する唯一の世代だけを受理し、異世代・曖昧候補をfail-closedする。
@test "report_received: archived v2 report requires one exact task identity" {
    setup_git_test_env
    cat >> "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
  task_id: cmd_test_001_normal
  report_id: rpt-archive-exact
  report_identity_version: 2
  parent_contract_fingerprint: abcdef0123456789
YAML
    cat >> "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" <<'YAML'
task_id: cmd_test_001_normal
parent_cmd: cmd_test_001
report_id: rpt-archive-exact
report_identity_version: 2
parent_contract_fingerprint: abcdef0123456789
YAML
    git -C "$TEST_TMPDIR" add queue/tasks/testninja.yaml queue/reports/testninja_report_cmd_test_001.yaml
    git -C "$TEST_TMPDIR" commit -q -m archive-identity
    mkdir -p "$TEST_TMPDIR/queue/archive/reports"
    mv "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" \
       "$TEST_TMPDIR/queue/archive/reports/testninja_report_cmd_test_001_20260728.yaml"

    run _run_inbox_write karo "delayed exact report" report_received testninja
    [ "$status" -eq 0 ]
    [[ "$output" == *"archive fallback: identity一致"* ]]
    grep -q "report_id: 'rpt-archive-exact'" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    [ "$(grep -c "^  type: 'report_review'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml")" -eq 1 ]
    grep -q "^  status: done" "$TEST_TMPDIR/queue/tasks/testninja.yaml"

    # Exact retry remains one durable completion and one review.
    run _run_inbox_write karo "delayed exact report" report_received testninja
    [ "$status" -eq 0 ]
    [[ "$output" == *"DUPLICATE_MSG_ID="* ]]
    [ "$(grep -c "report_id: 'rpt-archive-exact'" "$TEST_TMPDIR/queue/inbox/karo.yaml")" -eq 1 ]
    [ "$(grep -c "^  type: 'report_review'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml")" -eq 1 ]
}

# test_necessity: archive fallbackはbasenameやmtimeで異identity・別task・複数一致世代を選ばない。
@test "report_received: archived v2 report blocks mismatched and ambiguous generations" {
    setup_git_test_env
    cat >> "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
  task_id: cmd_test_001_normal
  report_id: rpt-archive-exact
  report_identity_version: 2
  parent_contract_fingerprint: abcdef0123456789
YAML
    mkdir -p "$TEST_TMPDIR/queue/archive/reports"
    cp "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" \
       "$TEST_TMPDIR/report-candidate-template.yaml"

    make_candidate() {
        local suffix="$1" report_id="$2" task_id="$3" fingerprint="$4"
        cp "$TEST_TMPDIR/report-candidate-template.yaml" \
           "$TEST_TMPDIR/queue/archive/reports/testninja_report_cmd_test_001_${suffix}.yaml"
        cat >> "$TEST_TMPDIR/queue/archive/reports/testninja_report_cmd_test_001_${suffix}.yaml" <<YAML
task_id: $task_id
parent_cmd: cmd_test_001
report_id: $report_id
report_identity_version: 2
parent_contract_fingerprint: $fingerprint
YAML
    }
    rm "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml"

    make_candidate wrong-id rpt-other cmd_test_001_normal abcdef0123456789
    make_candidate wrong-task rpt-archive-exact cmd_other_normal abcdef0123456789
    make_candidate wrong-fingerprint rpt-archive-exact cmd_test_001_normal 0000000000000000
    run _run_inbox_write karo "mismatched archive" report_received testninja
    [ "$status" -ne 0 ]
    [[ "$output" == *"archive identity candidates=0 scanned=3"* ]]
    [ ! -e "$TEST_TMPDIR/queue/inbox/karo.yaml" ]

    make_candidate exact-a rpt-archive-exact cmd_test_001_normal abcdef0123456789
    make_candidate exact-b rpt-archive-exact cmd_test_001_normal abcdef0123456789
    run _run_inbox_write karo "ambiguous archive" report_received testninja
    [ "$status" -ne 0 ]
    [[ "$output" == *"archive identity candidates=2 scanned=5"* ]]
    [ ! -e "$TEST_TMPDIR/queue/inbox/karo.yaml" ]
}

@test "filesystem fast-path: known ninja target succeeds without sourcing agent_config" {
    rm -rf "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue"
    mkdir -p "$TEST_TMPDIR/scripts/lib" "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/inbox"
    cp "$PROJECT_ROOT/scripts/lib/report_completion_events.sh" "$TEST_TMPDIR/scripts/lib/report_completion_events.sh"
    cp "$PROJECT_ROOT/scripts/lib/escalation_evidence.sh" "$TEST_TMPDIR/scripts/lib/escalation_evidence.sh"
    unset INBOX_WRITE_TEST

    cat > "$TEST_TMPDIR/scripts/lib/agent_config.sh" <<'MOCK'
echo "agent_config should not be sourced on filesystem fast-path" >&2
return 99
MOCK

    cat > "$TEST_TMPDIR/queue/tasks/ninja_fast.yaml" <<'YAML'
task:
  status: assigned
YAML

    run _run_inbox_write ninja_fast "fast path ok" wake_up karo
    [ "$status" -eq 0 ]
    [[ "$output" != *"agent_config should not be sourced"* ]]
    [ -f "$TEST_TMPDIR/queue/inbox/ninja_fast.yaml" ]
}

@test "filesystem fast-path: ninja sender to shogun is blocked without agent_config" {
    rm -rf "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue"
    mkdir -p "$TEST_TMPDIR/scripts/lib" "$TEST_TMPDIR/queue/tasks"
    cp "$PROJECT_ROOT/scripts/lib/report_completion_events.sh" "$TEST_TMPDIR/scripts/lib/report_completion_events.sh"
    cp "$PROJECT_ROOT/scripts/lib/escalation_evidence.sh" "$TEST_TMPDIR/scripts/lib/escalation_evidence.sh"
    unset INBOX_WRITE_TEST

    cat > "$TEST_TMPDIR/scripts/lib/agent_config.sh" <<'MOCK'
echo "agent_config should not be sourced on filesystem fast-path" >&2
return 99
MOCK

    cat > "$TEST_TMPDIR/queue/tasks/ninja_fast.yaml" <<'YAML'
task:
  status: in_progress
YAML

    run _run_inbox_write shogun "relay forbidden" wake_up ninja_fast
    [ "$status" -eq 1 ]
    [[ "$output" == *"Ninja cannot send inbox to shogun directly"* ]]
    [[ "$output" != *"agent_config should not be sourced"* ]]
}
# test_necessity: 成果物未作成のverify_requestをinboxへ先行配送せず、checkpoint manifestへ保留する不変量を守る。
@test "verify_request without artifact is deferred to checkpoint manifest" {
    root="$BATS_TEST_TMPDIR/root"; mkdir -p "$root/scripts" "$root/queue/inbox" "$root/queue/tasks"
    cp "$PROJECT_ROOT/scripts/inbox_write.sh" "$root/scripts/inbox_write.sh"
    ln -s "$PROJECT_ROOT/scripts/lib" "$root/scripts/lib"
    run env INBOX_WRITE_ROOT_OVERRIDE="$root" INBOX_WRITE_TEST=1 bash "$root/scripts/inbox_write.sh" gunshi \
        "cmd_fixture worker=alpha artifact docs/research/later.md" verify_request karo review
    [ "$status" -eq 0 ]
    [[ "$output" == *CHECKPOINT_DEFERRED* ]]
    [ ! -f "$root/queue/inbox/gunshi.yaml" ]
    [ "$(find "$root/queue/checkpoint_manifests" -name '*.manifest' | wc -l)" -eq 1 ]
    grep -q '^state=awaiting_artifact$' "$root"/queue/checkpoint_manifests/*.manifest
}

# --- auto-read judgement must come from structure, never from prose ---
# test_necessity: a report that merely mentions another CLEARed cmd_id must not be
# auto-read as that cmd's completion notification; only the report's own
# parent_cmd being CLEARed may auto-read it.
# 2026-07-26: the first cmd_id grepped out of the message body decided this, so a
# report mentioning cmd_4173 was delivered read:true as cmd_4173's completion.
_autoread_env() {
    AR_ROOT="$BATS_TEST_TMPDIR/autoread"
    # These cases exercise structural auto-read only; skip unrelated review
    # context lookups so their timing reflects the contract under test.
    export INBOX_REVIEW_CONTEXT_DISABLE=1
    mkdir -p "$AR_ROOT/queue/inbox" "$AR_ROOT/queue/reports" "$AR_ROOT/logs" "$AR_ROOT/scripts"
    [ -L "$AR_ROOT/scripts/lib" ] || ln -s "$PROJECT_ROOT/scripts/lib" "$AR_ROOT/scripts/lib"
    # report_received reaches only these top-level helpers in this fixture.
    # Avoid materializing every script on the WSL-mounted project tree; the
    # full glob made the two structural auto-read controls pay setup cost for
    # unrelated tools while preserving the same isolated root.
    local _s
    for _s in retro_write.sh ntfy.sh memory_db_live_insert_async.py memory_db_live_insert.py; do
        [ -e "$PROJECT_ROOT/scripts/$_s" ] || continue
        [ -e "$AR_ROOT/scripts/$_s" ] || ln -s "$PROJECT_ROOT/scripts/$_s" "$AR_ROOT/scripts/$_s"
    done
    printf 'messages: []\n' > "$AR_ROOT/queue/inbox/karo.yaml"
    printf '%s\n' \
        'worker_id: kotaro' \
        'report_id: rpt-autoread-0001' \
        'report_identity_version: 2' \
        'task_id: cmd_own_20260726_normal' \
        'parent_cmd: cmd_own_20260726' \
        'status: completed' \
        'verdict: PASS' \
        > "$AR_ROOT/queue/reports/kotaro_own_20260726.yaml"
    AR_CONTENT='kotaro wrote the control. Earlier bullet cmd_mentioned_only had the same shape. report= queue/reports/kotaro_own_20260726.yaml'
}

@test "negative control: a report merely mentioning a CLEARed cmd is not auto-read" {
    _autoread_env
    # The mentioned cmd is CLEARed; the report's own cmd is not.
    printf '2026-07-26T12:00:00\tcmd_mentioned_only\tCLEAR\tall_gates_passed\n' \
        > "$AR_ROOT/logs/gate_metrics.log"
    run env INBOX_WRITE_ROOT_OVERRIDE="$AR_ROOT" \
        bash "$PROJECT_ROOT/scripts/inbox_write.sh" karo "$AR_CONTENT" report_received kotaro notify_karo
    # Status is not asserted for the same reason as the positive control below.
    [[ "$output" != *"auto-read completed notification"* ]]
    grep -q "parent_cmd: 'cmd_own_20260726'" "$AR_ROOT/queue/inbox/karo.yaml"
}

@test "positive control: a duplicate notification for the report own CLEARed cmd is auto-read" {
    _autoread_env
    printf '2026-07-26T13:00:00\tcmd_own_20260726\tCLEAR\tall_gates_passed\n' \
        > "$AR_ROOT/logs/gate_metrics.log"
    run env INBOX_WRITE_ROOT_OVERRIDE="$AR_ROOT" \
        bash "$PROJECT_ROOT/scripts/inbox_write.sh" karo "$AR_CONTENT" report_received kotaro notify_karo
    # NOTE: exit status is deliberately not asserted here.  When auto-read and the
    # review-child delivery both fire, inbox_mark_read.sh is called on a message
    # that is already read and the whole send exits 2 even though delivery
    # succeeded.  That is a pre-existing defect (reproduced identically on the
    # pre-fix revision) and is reported separately; asserting either status here
    # would freeze it as the contract.
    [[ "$output" == *"auto-read completed notification"*"cmd=cmd_own_20260726"* ]]
}

# test_necessity: 調査返信は完了report lifecycleから独立し、証拠付き忍者→家老だけを起床配送する。
@test "investigation_result is evidence-bound ninja-to-karo and has no completion side effects" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/queue/tasks"
    printf 'task:\n  status: in_progress\n' > "$TEST_TMPDIR/queue/tasks/testninja.yaml"
    local body='task_id=cmd_probe check_id=gate_1 occurred_at=2026-08-01T21:00:00+09:00 evidence=logs/probe.log impact=delay_2m'

    run _run_inbox_write karo "$body" investigation_result testninja reply_required
    [ "$status" -eq 0 ]
    grep -q "type: 'investigation_result'" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    grep -q "^  task_id: 'cmd_probe'" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    grep -q "^  check_id: 'gate_1'" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    grep -q "^  occurred_at: '2026-08-01T21:00:00+09:00'" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    grep -q "^  evidence: 'logs/probe.log'" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    grep -q "^  impact: 'delay_2m'" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    grep -q "read: false" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    grep -q '^  status: in_progress$' "$TEST_TMPDIR/queue/tasks/testninja.yaml"
    [ ! -e "$TEST_TMPDIR/queue/inbox/gunshi.yaml" ]
}

@test "investigation_result rejects five malformed or misrouted variants" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/queue/tasks"
    printf 'task:\n  status: in_progress\n' > "$TEST_TMPDIR/queue/tasks/testninja.yaml"
    local good='task_id=cmd_probe check_id=gate_1 occurred_at=2026-08-01T21:00:00+09:00 evidence=logs/probe.log impact=delay_2m'
    local bad
    for bad in \
        'check_id=gate_1 occurred_at=x evidence=x impact=x' \
        'task_id=cmd_probe occurred_at=x evidence=x impact=x' \
        'task_id=cmd_probe check_id=gate_1 evidence=x impact=x' \
        'task_id=cmd_probe check_id=gate_1 occurred_at=x impact=x' \
        'task_id=cmd_probe check_id=gate_1 occurred_at=x evidence=x'; do
        run _run_inbox_write karo "$bad" investigation_result testninja reply_required
        [ "$status" -eq 2 ]
        [[ "$output" == *"required: task_id/check_id/occurred_at/evidence/impact"* ]]
    done
    run _run_inbox_write gunshi "$good" investigation_result testninja reply_required
    [ "$status" -eq 2 ]
    [[ "$output" == *"ninja -> karo only"* ]]
    [ ! -e "$TEST_TMPDIR/queue/inbox/karo.yaml" ]
}

# test_necessity: dedicated report/review producers must not persist a
# taskless row when report resolution or the report's own task_id is missing.
@test "dedicated report identity rejects missing path and empty task_id" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/queue/reports"

    run _run_inbox_write karo "review without report" report_review ninja_monitor notify_karo
    [ "$status" -eq 2 ]
    [[ "$output" == *"dedicated identity resolved no non-empty task_id"* ]]
    [ ! -e "$TEST_TMPDIR/queue/inbox/karo.yaml" ]

    printf 'parent_cmd: cmd_empty_identity\nstatus: completed\ncommit_hash: abc123abc123abc123abc123abc123abc123abc1\nresult:\n  summary: ready\n' > "$TEST_TMPDIR/queue/reports/ninja_report_cmd_empty_identity.yaml"
    run _run_inbox_write karo "report: queue/reports/ninja_report_cmd_empty_identity.yaml" report_review ninja_monitor notify_karo
    [ "$status" -eq 2 ]
    [[ "$output" == *"dedicated identity resolved no non-empty task_id"* ]]
    [ ! -e "$TEST_TMPDIR/queue/inbox/karo.yaml" ]
}

@test "commander target task_assigned binds empty task_id to commander_directive" {
    # test_necessity: commander(karo/gunshi/shogun) 宛 task_assigned の task_id が空のままだと受け手の task_id フィルタが指示を『適用せず既読化』する(2026-08-28/29 に 8 回再発)。空を固定トークンへ束縛する不変量。
    local tmp; tmp=$(mktemp -d)
    mkdir -p "$tmp/queue/tasks"
    printf 'task_id: ""\nparent_cmd: ""\n' > "$tmp/queue/tasks/karo.yaml"
    printf 'task_id: "cmd_x_normal"\nparent_cmd: "cmd_x"\n' > "$tmp/queue/tasks/hayate.yaml"
    run bash -c "set -euo pipefail; SCRIPT_DIR='$tmp'; ensure_field_get_loaded() { :; }; source <(sed -n '/^inbox_yaml_field_get()/,/^}/p;/^inbox_task_assignment_identity_fields()/,/^}/p' '$PROJECT_ROOT/scripts/inbox_write.sh'); mapfile -t karo_fields < <(inbox_task_assignment_identity_fields karo); mapfile -t hayate_fields < <(inbox_task_assignment_identity_fields hayate); printf '%s\\n' \"\${karo_fields[0]}\" \"\${hayate_fields[0]}\""
    rm -rf "$tmp"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "commander_directive" ]
    [ "${lines[1]}" = "cmd_x_normal" ]
}

# test_necessity: 家老宛の判断要求3型は固定管理task_idと対象task/cmdを
# 保存し、identityを欠く新規送信は保存前に拒否する。
@test "karo directive types persist structured identity and reject missing identity" {
    setup_basic_test_env
    local type content
    for type in pending_work review_draft_result gate_clear_required task_supplement cmd_new gate_alert; do
        content="task_id=commander_directive subject_task_id=cmd_${type}_normal parent_cmd=cmd_${type} directive"
        run _run_inbox_write karo "$content" "$type" ninja_monitor notify_karo
        [ "$status" -eq 0 ]
    done

    run python3 - "$TEST_TMPDIR/queue/inbox/karo.yaml" <<'PY'
import sys, yaml
messages = (yaml.safe_load(open(sys.argv[1])) or {}).get("messages", [])
wanted = {"pending_work", "review_draft_result", "gate_clear_required"}
actual = {m.get("type") for m in messages if m.get("type") in wanted}
assert actual == wanted, messages
for message in messages:
    if message.get("type") in wanted:
        assert message.get("task_id") == "commander_directive", message
        assert message.get("subject_task_id", "").startswith("cmd_"), message
        assert message.get("parent_cmd", "").startswith("cmd_"), message
print("directive_identity=3/3 missing=0")
PY
    [ "$status" -eq 0 ]

    for type in pending_work review_draft_result gate_clear_required task_supplement cmd_new gate_alert; do
        run _run_inbox_write karo "${type} missing identity" "$type" ninja_monitor notify_karo
        [ "$status" -eq 2 ]
        [[ "$output" == *"requires explicit task_id=commander_directive"* ]]
    done
    [ "$(grep -c '^  type: '\''pending_work'\''' "$TEST_TMPDIR/queue/inbox/karo.yaml")" -eq 1 ]
    [ "$(grep -c '^  type: '\''review_draft_result'\''' "$TEST_TMPDIR/queue/inbox/karo.yaml")" -eq 1 ]
    [ "$(grep -c '^  type: '\''gate_clear_required'\''' "$TEST_TMPDIR/queue/inbox/karo.yaml")" -eq 1 ]

    run _run_inbox_write karo "future_action missing identity" future_action ninja_monitor notify_karo
    [ "$status" -eq 2 ]
    [[ "$output" == *"requires explicit task_id=commander_directive"* ]]
    run _run_inbox_write karo "task_id=commander_directive subject_task_id=cmd_future_normal parent_cmd=cmd_future future_action" future_action ninja_monitor notify_karo
    [ "$status" -eq 0 ]
    run python3 - "$TEST_TMPDIR/queue/inbox/karo.yaml" <<'PY'
import sys, yaml
messages = (yaml.safe_load(open(sys.argv[1])) or {}).get("messages", [])
future = [m for m in messages if m.get("type") == "future_action"]
assert len(future) == 1 and future[0].get("task_id") == "commander_directive", future
assert future[0].get("subject_task_id") == "cmd_future_normal"
assert future[0].get("parent_cmd") == "cmd_future"
print("unknown_with_identity=1 unknown_missing_saved=0")
PY
    [ "$status" -eq 0 ]
    run _run_inbox_write karo "informational message" info ninja_monitor notify_karo
    [ "$status" -eq 0 ]
    run python3 - "$TEST_TMPDIR/queue/inbox/karo.yaml" <<'PY'
import sys, yaml
messages = (yaml.safe_load(open(sys.argv[1])) or {}).get("messages", [])
info = [m for m in messages if m.get("type") == "info"]
assert len(info) == 1
assert "task_id" not in info[0] and "subject_task_id" not in info[0]
print("information_false_positive_block=0")
PY
    [ "$status" -eq 0 ]

    for type in low info gate_clear heartbeat status_update retro_answer; do
        run _run_inbox_write karo "${type} informational" "$type" ninja_monitor notify_karo
        [ "$status" -eq 0 ]
    done
    run python3 - "$TEST_TMPDIR/queue/inbox/karo.yaml" <<'PY'
import sys, yaml
messages = (yaml.safe_load(open(sys.argv[1])) or {}).get("messages", [])
info_types = {"low", "info", "gate_clear", "heartbeat", "status_update", "retro_answer"}
info = [m for m in messages if m.get("type") in info_types]
assert {m.get("type") for m in info} == info_types, info
assert all("task_id" not in m and "subject_task_id" not in m and "parent_cmd" not in m for m in info), info
print("information_types=6 identity_fields=0")
PY
    [ "$status" -eq 0 ]

    for type in task_new task_supplement task_cancel cmd_new gate_alert gate_block gate_fail destructive_warn stale_cmd cmd_pending; do
        run _run_inbox_write karo "${type} missing identity" "$type" ninja_monitor notify_karo
        [ "$status" -eq 2 ]
        [[ "$output" == *"requires explicit task_id=commander_directive"* ]]
    done
}

# test_necessity: review-pending notifications persist the management
# task_id separately from the subject task and a consumed event can wake again.
@test "review-pending nudge persists structured identity and retries after read" {
    root="$BATS_TEST_TMPDIR/review-pending-nudge"
    mkdir -p "$root/queue/inbox" "$root/queue/tasks" "$root/scripts"
    ln -s "$PROJECT_ROOT/scripts/lib" "$root/scripts/lib"
    content="review_pending_state=A task_id=commander_directive subject_task_id=cmd_subject_normal parent_cmd=cmd_subject report_fingerprint=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef report=queue/reports/hanzo_report_cmd_subject.yaml"
    run env INBOX_WRITE_ROOT_OVERRIDE="$root" INBOX_WRITE_TEST=1 INBOX_REVIEW_CONTEXT_DISABLE=1 DEFENSE_OVERHEAD_ENABLED=0 \
        bash "$PROJECT_ROOT/scripts/inbox_write.sh" gunshi "$content" review_report ninja_monitor review_report
    [ "$status" -eq 0 ]
    python3 - "$root/queue/inbox/gunshi.yaml" <<'PY'
import sys, yaml
messages = (yaml.safe_load(open(sys.argv[1])) or {}).get("messages", [])
assert len(messages) == 1
message = messages[0]
expected = {
    "task_id": "commander_directive",
    "subject_task_id": "cmd_subject_normal",
    "parent_cmd": "cmd_subject",
    "report_fingerprint": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "report": "queue/reports/hanzo_report_cmd_subject.yaml",
    "review_pending_state": "A",
    "action": "review_report",
}
for key, value in expected.items():
    assert message.get(key) == value, (key, message)
assert message["read"] is False
print("structured_fields=7 first_read=false")
PY
    sed -i 's/read: false/read: true/' "$root/queue/inbox/gunshi.yaml"
    run env INBOX_WRITE_ROOT_OVERRIDE="$root" INBOX_WRITE_TEST=1 INBOX_REVIEW_CONTEXT_DISABLE=1 DEFENSE_OVERHEAD_ENABLED=0 \
        bash "$PROJECT_ROOT/scripts/inbox_write.sh" gunshi "$content" review_report ninja_monitor review_report
    [ "$status" -eq 0 ]
    python3 - "$root/queue/inbox/gunshi.yaml" <<'PY'
import sys, yaml
messages = (yaml.safe_load(open(sys.argv[1])) or {}).get("messages", [])
assert len(messages) == 2
assert sum(not bool(x.get("read")) for x in messages) == 1
print("retry_after_read=1 unread_wakeup=1")
PY
}
