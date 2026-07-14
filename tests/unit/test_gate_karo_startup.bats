#!/usr/bin/env bats
# test_gate_karo_startup.bats — gate_karo_startup.sh unit tests
# cmd_1554: 家老起動ゲート8項目チェックのテスト可能分岐を検証
# Speed measurements and the no-SKIP contract: [[gate-karo-startup-test-speed]]

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_karo_startup.sh"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1

    export KARO_BASE_FIXTURE
    KARO_BASE_FIXTURE="$(mktemp -d "$BATS_FILE_TMPDIR/karo_startup_base.XXXXXX")"
    TEST_TMPDIR="$KARO_BASE_FIXTURE"
    build_fixture
}

build_fixture() {
    mkdir -p "$TEST_TMPDIR/scripts/gates" \
             "$TEST_TMPDIR/scripts/lib" \
             "$TEST_TMPDIR/queue/inbox" \
             "$TEST_TMPDIR/queue/tasks" \
             "$TEST_TMPDIR/queue/gates" \
             "$TEST_TMPDIR/memory" \
             "$TEST_TMPDIR/logs" \
             "$TEST_TMPDIR/data" \
             "$TEST_TMPDIR/docs/semantic-index" \
             "$TEST_TMPDIR/.codex"

    # Copy the gate script
    cp "$SRC_GATE_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_karo_startup.sh"
    cp "$PROJECT_ROOT/scripts/lib/disk_space_watch.sh" "$TEST_TMPDIR/scripts/lib/disk_space_watch.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_karo_startup.sh"
    cp "$PROJECT_ROOT/scripts/gates/session_alerts_render.sh" "$TEST_TMPDIR/scripts/gates/session_alerts_render.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/session_alerts_render.sh"
    cp "$PROJECT_ROOT/scripts/gates/gate_wa_data_quality.sh" "$TEST_TMPDIR/scripts/gates/gate_wa_data_quality.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_wa_data_quality.sh"
    cp "$PROJECT_ROOT/scripts/gates/gate_queue_yaml_parse.sh" "$TEST_TMPDIR/scripts/gates/gate_queue_yaml_parse.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_queue_yaml_parse.sh"
    cp "$PROJECT_ROOT/scripts/gates/gate_three_layer_health.sh" "$TEST_TMPDIR/scripts/gates/gate_three_layer_health.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_three_layer_health.sh"
    cp "$PROJECT_ROOT/scripts/gates/gate_codex_hooks_no_stop.sh" "$TEST_TMPDIR/scripts/gates/gate_codex_hooks_no_stop.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_codex_hooks_no_stop.sh"
    # Most cases exercise gate_karo_startup orchestration, not these nested
    # gates. Keep their real implementations beside fast contract stubs; the
    # dedicated nested-gate cases restore the real script explicitly.
    for nested in gate_wa_data_quality.sh gate_queue_yaml_parse.sh gate_three_layer_health.sh; do
        cp "$TEST_TMPDIR/scripts/gates/$nested" "$TEST_TMPDIR/scripts/gates/$nested.real"
    done
    cat > "$TEST_TMPDIR/scripts/gates/gate_wa_data_quality.sh" <<'MOCK'
#!/usr/bin/env bash
echo '■ WAデータ品質'
echo '  OK: False WAなし'
MOCK
    cat > "$TEST_TMPDIR/scripts/gates/gate_queue_yaml_parse.sh" <<'MOCK'
#!/usr/bin/env bash
echo '■ queue YAML parse'
echo '  OK: queue YAML parse clean'
MOCK
    cat > "$TEST_TMPDIR/scripts/gates/gate_three_layer_health.sh" <<'MOCK'
#!/usr/bin/env bash
echo 'STATUS: PASS'
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_wa_data_quality.sh" \
        "$TEST_TMPDIR/scripts/gates/gate_queue_yaml_parse.sh" \
        "$TEST_TMPDIR/scripts/gates/gate_three_layer_health.sh"
    cp "$PROJECT_ROOT/scripts/lib/known_ninjas.sh" "$TEST_TMPDIR/scripts/lib/known_ninjas.sh"
    cp "$PROJECT_ROOT/scripts/lib/yaml_safe_read.py" "$TEST_TMPDIR/scripts/lib/yaml_safe_read.py"
    cp "$PROJECT_ROOT/scripts/cleanup_three_layer_tmp.sh" "$TEST_TMPDIR/scripts/cleanup_three_layer_tmp.sh"
    chmod +x "$TEST_TMPDIR/scripts/cleanup_three_layer_tmp.sh"
    cp "$PROJECT_ROOT/scripts/memory_db_live_insert.py" "$TEST_TMPDIR/scripts/memory_db_live_insert.py"
    cp "$PROJECT_ROOT/scripts/skill_execution_log.sh" "$TEST_TMPDIR/scripts/skill_execution_log.sh"
    chmod +x "$TEST_TMPDIR/scripts/skill_execution_log.sh"
    cat > "$TEST_TMPDIR/.codex/hooks.json" <<'EOF'
{"hooks":{"PreToolUse":[],"PostToolUse":[]}}
EOF

    # --- Default fixtures: all checks pass ---

    # Check 1: deepdive files exist (両ファイル必須: gate_karo_startup.sh REQUIRED_READ1+REQUIRED_READ2)
    # Semantic index dummy (freshness check)
    echo "# semantic index" > "$TEST_TMPDIR/docs/semantic-index/index.md"

    echo "# deepdive content" > "$TEST_TMPDIR/memory/deepdive_why_chain_20260321.md"
    echo "# deepdive content" > "$TEST_TMPDIR/memory/deepdive_karo_verification_20260405.md"

    # Check 2: fresh snapshot (generated just now)
    local now_time
    now_time=$(date '+%Y-%m-%dT%H:%M:%S')
    cat > "$TEST_TMPDIR/queue/karo_snapshot.txt" <<EOF
# 家老陣形図(karo_snapshot)
# Generated: $now_time
ninja|hayate|cmd_100_impl|in_progress|infra|CTX:30%
ninja|kagemaru|cmd_101_impl|in_progress|infra|CTX:25%
EOF

    # Check 3: inbox with no unread
    cat > "$TEST_TMPDIR/queue/inbox/karo.yaml" <<'EOF'
messages:
- content: test
  read: true
  id: msg_1
EOF

    # Check 4: all PD resolved
    cat > "$TEST_TMPDIR/queue/pending_decisions.yaml" <<'EOF'
- id: PD-001
  status: resolved
EOF

    cat > "$TEST_TMPDIR/queue/insights.yaml" <<'EOF'
insights:
- id: INS-001
  insight: "resolved insight"
  priority: "low"
  status: resolved
EOF

    # Check 5: workarounds (no workaround)
    cat > "$TEST_TMPDIR/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_100
  workaround: false
  category: none
EOF

    cat > "$TEST_TMPDIR/logs/skill_execution_log.yaml" <<'EOF'
executions:
- ts: "2026-05-02T10:00:00+0900"
  skill: "dashboard-update"
  executor: "hayate"
  result: "FAIL"
  stumbling_points: "verdict missing"
- ts: "2026-05-02T10:01:00+0900"
  skill: "report-write"
  executor: "hanzo"
  result: "FAIL"
  stumbling_points: "none"
EOF
    cat > "$TEST_TMPDIR/logs/gate_metrics.log" <<'EOF'
2026-06-24T00:00:00	cmd_fixture_done	CLEAR	none	unknown	unknown	unknown	none		unknown	unknown
EOF
    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries:
- cmd_id: "cmd_fixture_done"
  gate_result: "CLEAR"
EOF

    # Check 9.5: three-layer memory health minimal PASS fixture
    python3 - "$TEST_TMPDIR/data/three_layer_health.db" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.execute("CREATE TABLE events (id TEXT PRIMARY KEY, state TEXT DEFAULT 'raw', raw_content TEXT)")
conn.execute("CREATE TABLE search_logs (ts TEXT, created_at TEXT)")
conn.executemany(
    "INSERT INTO events (id, state, raw_content) VALUES (?, ?, ?)",
    [
        ("event:raw", "raw", "raw content"),
        ("event:verified", "verified", "verified content"),
        ("event:candidate", "obsidian_candidate", "candidate content"),
    ],
)
conn.execute("INSERT INTO search_logs (ts, created_at) VALUES (datetime('now'), datetime('now'))")
conn.commit()
conn.close()
PY

    # Check 6: mock gate_workaround_rate.sh
    cat > "$TEST_TMPDIR/scripts/gates/gate_workaround_rate.sh" <<'MOCK'
#!/usr/bin/env bash
echo "■ Workaround率"
echo "  直近10件: 0% (0/10)"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_workaround_rate.sh"

    # Check 7: mock gate_ninja_workaround_rate.sh
    cat > "$TEST_TMPDIR/scripts/gates/gate_ninja_workaround_rate.sh" <<'MOCK'
#!/usr/bin/env bash
echo "  全忍者WA率正常"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_ninja_workaround_rate.sh"

    # Check 8: task YAMLs (all completed = idle)
    for ninja in hayate kagemaru hanzo saizo kotaro tobisaru; do
        cat > "$TEST_TMPDIR/queue/tasks/${ninja}.yaml" <<YAML
task:
  status: completed
YAML
    done

    # Check 9: shogun_to_karo.yaml with all delegated (no orphan)
    mkdir -p "$TEST_TMPDIR/queue"
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_100:
    title: "test cmd"
    status: delegated
    created_at: "2026-04-01T00:00:00"
  cmd_101:
    title: "test cmd 2"
    status: completed
    created_at: "2026-04-01T00:00:00"
EOF

    # Mock tmux (Check 2.5: return empty so all ninjas show "ペイン不在")
    mkdir -p "$TEST_TMPDIR/bin"
    cat > "$TEST_TMPDIR/bin/tmux" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
    chmod +x "$TEST_TMPDIR/bin/tmux"

}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/karo_startup.XXXXXX")"
    cp -a "$KARO_BASE_FIXTURE/." "$TEST_TMPDIR/"

    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_karo_startup.sh"
    export KARO_WA_RATE_CACHE="$TEST_TMPDIR/karo_wa_rate_cache"
    export KARO_NINJA_WA_CACHE="$TEST_TMPDIR/karo_ninja_wa_cache"
    export KARO_SKILL_SUMMARY_CACHE="$TEST_TMPDIR/karo_skill_summary_cache"
    export KARO_AGGREGATE_CACHE="$TEST_TMPDIR/karo_startup_aggregate_cache"
    export KARO_QUALITY_MISSING_CUTOFF="2026-06-01T00:00:00"
    export SHOGUN_MEMORY_DB_CACHE_PATH="$TEST_TMPDIR/data/three_layer_health.db"
    export SHOGUN_THREE_LAYER_CACHE_WARN_BYTES=999999999
    # Disk capacity is invariant for these gate-logic tests. Avoid a slow WSL
    # /mnt/c df subprocess per test while preserving the production default.
    export DISK_WATCH_AVAILABLE_KB=104857600
    export ORIG_PATH="$PATH"
    export PATH="$TEST_TMPDIR/bin:$PATH"
}

teardown() {
    export PATH="$ORIG_PATH"
    unset SHOGUN_MEMORY_DB_CACHE_PATH
    unset SHOGUN_THREE_LAYER_CACHE_WARN_BYTES
    unset DISK_WATCH_AVAILABLE_KB
    unset KARO_QUALITY_MISSING_CUTOFF
    # TEST_TMPDIR is below BATS_TEST_TMPDIR and KARO_BASE_FIXTURE is below
    # BATS_FILE_TMPDIR. Bats removes both managed roots, so deleting the same
    # fixture trees here only duplicates filesystem work for every test.
}

# === Test 1: 全項目正常 → 総合判定OK ===
@test "all checks pass → 総合判定: OK [karo]" {
    cat > "$TEST_TMPDIR/logs/skill_execution_log.yaml" <<'EOF'
executions:
- ts: "2026-05-02T10:01:00+0900"
  skill: "report-write"
  executor: "hanzo"
  result: "PASS"
  stumbling_points: "none"
EOF
    printf 'stale alert\n' > "$TEST_TMPDIR/queue/gates/karo_alert_pending.txt"
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"総合判定: OK"* ]]
    [[ "$output" == *"スキル品質: 全PASS"* ]]
    [ ! -e "$TEST_TMPDIR/queue/gates/karo_alert_pending.txt" ]
}

@test "three-layer health cache invalidates when cache DB appears after stale WARN" {
    cp "$TEST_TMPDIR/scripts/gates/gate_three_layer_health.sh.real" "$TEST_TMPDIR/scripts/gates/gate_three_layer_health.sh"
    export KARO_THREE_LAYER_HEALTH_CACHE="$TEST_TMPDIR/three_layer_health.cache"
    export SHOGUN_MEMORY_DB_CACHE_PATH="$TEST_TMPDIR/data/missing_three_layer_health.db"
    rm -f "$SHOGUN_MEMORY_DB_CACHE_PATH"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: 三層記憶DBが存在しない"* ]]
    [[ "$output" == *"三層記憶DB健全性: WARN"* ]]

    export SHOGUN_MEMORY_DB_CACHE_PATH="$TEST_TMPDIR/data/three_layer_health.db"
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS: PASS"* ]]
    [[ "$output" != *"WARN: 三層記憶DBが存在しない"* ]]
}

@test "skill FAIL summary is displayed at startup" {
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"フェーズ別スキル一覧:"* ]]
    [[ "$output" == *"cmd完了処理: /cmd-complete"* ]]
    [[ "$output" == *"家老自立配備(CI修正/hotfix/recon2単独): /karo-direct"* ]]
    [[ "$output" == *"偵察2名配備: /recon-dual"* ]]
    [[ "$output" == *"スキル品質: dashboard-update FAIL:1"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 2: 陣形図が30分以上古い → WARN ===
@test "snapshot older than 30 min → 総合判定: ALERT" {
    local old_time
    old_time=$(date -d '45 minutes ago' '+%Y-%m-%dT%H:%M:%S')
    cat > "$TEST_TMPDIR/queue/karo_snapshot.txt" <<EOF
# 家老陣形図(karo_snapshot)
# Generated: $old_time
ninja|hayate|cmd_100_impl|in_progress|infra|CTX:30%
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: 陣形図が30分以上古い"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 3: inbox未読あり → 未読件数が表示される ===
@test "inbox 3 unread → displays 未読: 3件" {
    cat > "$TEST_TMPDIR/queue/inbox/karo.yaml" <<'EOF'
messages:
- content: msg1
  read: false
  id: msg_1
- content: msg2
  read: false
  id: msg_2
- content: msg3
  read: false
  id: msg_3
- content: msg4
  read: true
  id: msg_4
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"未読: 3件"* ]]
}

@test "inbox unread count ignores read false text inside message content" {
    cat > "$TEST_TMPDIR/queue/inbox/karo.yaml" <<'EOF'
messages:
- id: msg_literal
  timestamp: '2026-07-05T08:00:00'
  type: report_review
  from: gunshi
  content: |-
    レビュー本文内の診断文字列:
    read: false
  read: true
- id: msg_real
  timestamp: '2026-07-05T08:01:00'
  type: report_review
  from: gunshi
  content: '実未読'
  read: false
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"未読: 1件"* ]]
    [[ "$output" != *"未読: 2件"* ]]
}

@test "karo_idle_cycle unread only is not promoted to 3-session CRITICAL" {
    cat > "$TEST_TMPDIR/logs/karo_startup_alert_history.tsv" <<'EOF'
run1	inbox未読: 1件
run2	inbox未読: 1件
EOF
    cat > "$TEST_TMPDIR/queue/inbox/karo.yaml" <<'EOF'
messages:
- id: msg_idle
  timestamp: '2026-07-01T09:47:22'
  type: karo_idle_cycle
  from: ninja_monitor
  content: 全忍者idle+パイプライン空。改善サイクルを回せ。
  read: false
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"未読: 1件"* ]]
    [[ "$output" == *"未読はkaro_idle_cycleのみ"* ]]
    [[ "$output" != *"先送りCRITICAL: inbox未読: 1件"* ]]
}

# === cmd_3658: 先送りCRITICAL誤検知根治 — 滞留時間ゲートの再現テスト ===
# 到着直後の未読は先送りCRITICAL streakに混入してはならない(誤検知の根因)。
# 滞留時間が閾値(KARO_INBOX_UNREAD_DWELL_MIN, デフォルト30分)を超えた未読のみstreak対象。
@test "freshly arrived unread does not trigger 先送りCRITICAL streak even with prior matching history" {
    cat > "$TEST_TMPDIR/logs/karo_startup_alert_history.tsv" <<'EOF'
run1	inbox未読滞留: 閾値30分超
run2	inbox未読滞留: 閾値30分超
EOF
    local now_ts
    now_ts=$(date '+%Y-%m-%dT%H:%M:%S')
    cat > "$TEST_TMPDIR/queue/inbox/karo.yaml" <<EOF
messages:
- id: msg_fresh
  timestamp: '${now_ts}'
  type: review_result
  from: gunshi
  content: '到着直後のメッセージ'
  read: false
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"到着直後のため先送りCRITICAL streak対象外"* ]]
    [[ "$output" != *"先送りCRITICAL: inbox未読滞留"* ]]
}

@test "unread lingering past dwell threshold across sessions triggers 先送りCRITICAL" {
    export STARTUP_WARN_STREAK_THRESHOLD=3
    local hist1 hist2
    hist1=$(date -d '90 minutes ago' '+%Y-%m-%dT%H:%M:%S')
    hist2=$(date -d '60 minutes ago' '+%Y-%m-%dT%H:%M:%S')
    cat > "$TEST_TMPDIR/logs/karo_startup_alert_history.tsv" <<EOF
${hist1}	inbox未読滞留: 閾値30分超
${hist2}	inbox未読滞留: 閾値30分超
EOF
    local old_ts
    old_ts=$(date -d '45 minutes ago' '+%Y-%m-%dT%H:%M:%S')
    cat > "$TEST_TMPDIR/queue/inbox/karo.yaml" <<EOF
messages:
- id: msg_stale
  timestamp: '${old_ts}'
  type: review_result
  from: gunshi
  content: '滞留しているメッセージ'
  read: false
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"先送りCRITICAL streak対象"* ]]
    [[ "$output" == *"先送りCRITICAL: inbox未読滞留: 閾値30分超 が3セッション連続"* ]]
}

@test "unread lingering past dwell threshold triggers 先送りCRITICAL on first session by default" {
    export STARTUP_WARN_STREAK_THRESHOLD=1
    local old_ts
    old_ts=$(date -d '45 minutes ago' '+%Y-%m-%dT%H:%M:%S')
    cat > "$TEST_TMPDIR/queue/inbox/karo.yaml" <<EOF
messages:
- id: msg_stale
  timestamp: '${old_ts}'
  type: review_result
  from: gunshi
  content: '滞留しているメッセージ'
  read: false
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"先送りCRITICAL streak対象"* ]]
    [[ "$output" == *"★★★ CRITICAL: inbox未読滞留: 閾値30分超 が1セッション連続"* ]]
}

@test "waiting-permission labels are absent from karo startup gate" {
    local rg_bin
    rg_bin="$(command -v rg 2>/dev/null || true)"
    [ -n "$rg_bin" ] || rg_bin="$HOME/.local/bin/rg"
    run bash -c "'$rg_bin' -n 'idle時に確認推奨|低優先/後で扱い|低優先=|後で扱い' '$TEST_GATE'"
    [ "$status" -eq 1 ]
}

@test "read actionable inbox still warns because read flag is not completion" {
    cat > "$TEST_TMPDIR/queue/inbox/karo.yaml" <<'EOF'
messages:
- content: 'GATE CLEAR — cmd_999 完了。/cmd-complete スキルで完了処理を実行せよ。'
  from: 'cmd_complete_gate'
  id: 'msg_skill'
  read: true
  timestamp: '2026-06-26T07:47:04'
  type: 'skill_hint'
- content: 'future fixとして、変更対象: bulletin_confirm.sh のclose判定ロジックのみ。'
  from: 'gunshi'
  id: 'msg_review'
  read: true
  timestamp: '2026-06-26T07:48:53'
  type: 'review_result'
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"既読actionable候補 2件"* ]]
    [[ "$output" == *"read=trueを処理済みと見なすな"* ]]
    [[ "$output" == *"msg_skill"* ]]
    [[ "$output" == *"msg_review"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "read GATE CLEAR skill_hint is ignored when gate_metrics already records CLEAR" {
    local now_time
    now_time=$(date '+%Y-%m-%dT%H:%M:%S')
    cat > "$TEST_TMPDIR/queue/inbox/karo.yaml" <<'EOF'
messages:
- content: 'GATE CLEAR — cmd_999 完了。/cmd-complete スキルで完了処理を実行せよ。'
  from: 'cmd_complete_gate'
  id: 'msg_skill'
  read: true
  timestamp: '2026-06-26T07:47:04'
  type: 'skill_hint'
EOF
    cat > "$TEST_TMPDIR/logs/gate_metrics.log" <<EOF
$now_time	cmd_999	CLEAR	all_gates_passed	full	unknown	unknown	none		duration_sec=unknown	ctx_pct=0	first_gate=true
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"未読: 0件"* ]]
    [[ "$output" != *"既読actionable候補"* ]]
    [[ "$output" != *"msg_skill"* ]]
}

@test "read cmd_new with unresolved explicit dependency is quiet until dependency clears" {
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_700:
    status: delegated
    depends_on: none
  cmd_701:
    status: delegated
    depends_on: cmd_700
EOF
    cat > "$TEST_TMPDIR/queue/inbox/karo.yaml" <<'EOF'
messages:
- content: 'cmd_701を書いた(depends cmd_700)。配備せよ。'
  from: 'shogun'
  id: 'msg_dependency_wait'
  read: true
  timestamp: '2026-07-12T15:19:00'
  type: 'cmd_new'
EOF

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"既読actionable候補"* ]]

    local now_time
    now_time=$(date '+%Y-%m-%dT%H:%M:%S')
    cat > "$TEST_TMPDIR/logs/gate_metrics.log" <<EOF
$now_time	cmd_700	CLEAR	all_gates_passed	full	unknown	unknown	none
EOF
    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries:
- cmd_id: "cmd_700"
  gate_result: "CLEAR"
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"既読actionable候補 1件"* ]]
    [[ "$output" == *"msg_dependency_wait"* ]]
}

@test "gunshi action_required bulletin without actioned_by warns at karo startup" {
    cat > "$TEST_TMPDIR/queue/bulletin_board.yaml" <<'EOF'
entries:
- id: 'blt_gunshi_action'
  content: |-
    軍師idle分析: 構造的穴発見。gate追加の改善提案として対応必要
  posted_by: 'gunshi'
  posted_at: '2026-06-28T01:00:00'
  requires_confirmation: false
  action_type: 'action_required'
  actioned_by: ''
  notify_targets:
    - 'karo'
  confirmed_by: []
  status: 'open'
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"掲示板action_required未対応"* ]]
    [[ "$output" == *"WARN: 未対応action_required掲示板 1件"* ]]
    [[ "$output" == *"blt_gunshi_action by gunshi"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "shogun-only action_required bulletin does not warn at karo startup" {
    cat > "$TEST_TMPDIR/queue/bulletin_board.yaml" <<'EOF'
entries:
- id: 'blt_shogun_q6_action'
  content: |-
    startup gate Q6回答未検出が3セッション連続。将軍はQ6回答を掲示板へ投稿せよ。
  posted_by: 'shogun'
  posted_at: '2026-07-06T20:42:23'
  requires_confirmation:
    - 'shogun'
  action_type: 'action_required'
  actioned_by: ''
  notify_targets: []
  confirmed_by: []
  status: 'open'
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"掲示板action_required未対応"* ]]
    [[ "$output" == *"未対応: 0件"* ]]
    [[ "$output" != *"blt_shogun_q6_action by shogun"* ]]
}

# === Test 4: PD未解決 → 未解決件数が表示される ===
@test "2 pending decisions → displays 未解決: 2件" {
    cat > "$TEST_TMPDIR/queue/pending_decisions.yaml" <<'EOF'
- id: PD-001
  status: pending
- id: PD-002
  status: pending
- id: PD-003
  status: resolved
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"未解決: 2件"* ]]
    [[ "$output" == *"未解決裁定あり"* ]]
}

@test "pending insights → displays count and latest 3" {
    cat > "$TEST_TMPDIR/queue/insights.yaml" <<'EOF'
insights:
- id: INS-001
  insight: "old pending insight"
  priority: "low"
  status: pending
- id: INS-002
  insight: "first recent insight"
  priority: "medium"
  status: pending
- id: INS-003
  insight: "second recent insight"
  priority: "high"
  status: pending
- id: INS-004
  insight: "third recent insight"
  priority: "medium"
  status: pending
- id: INS-005
  insight: "done insight"
  priority: "low"
  status: resolved
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ insights未処理"* ]]
    [[ "$output" == *"pending: 4件"* ]]
    [[ "$output" == *"直近3件:"* ]]
    [[ "$output" != *"INS-001"* ]]
    [[ "$output" == *"INS-002 [medium] first recent insight"* ]]
    [[ "$output" == *"INS-003 [high] second recent insight"* ]]
    [[ "$output" == *"INS-004 [medium] third recent insight"* ]]
}

# === Test 5: 複合ALERT — deepdive不在 + 陣形図古い ===
@test "compound: deepdive missing + old snapshot → 総合判定: ALERT" {
    # Remove deepdive
    rm -f "$TEST_TMPDIR/memory/deepdive_why_chain_20260321.md"

    # Old snapshot
    local old_time
    old_time=$(date -d '60 minutes ago' '+%Y-%m-%dT%H:%M:%S')
    cat > "$TEST_TMPDIR/queue/karo_snapshot.txt" <<EOF
# 家老陣形図(karo_snapshot)
# Generated: $old_time
ninja|hayate|cmd_100_impl|in_progress|infra|CTX:30%
EOF

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT"* ]]
    [[ "$output" == *"必読ファイル不在"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 6: deepdive不在のみ → ALERT ===
@test "deepdive missing → 総合判定: ALERT [karo]" {
    rm -f "$TEST_TMPDIR/memory/deepdive_why_chain_20260321.md"
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT:"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 7: 陣形図不在 → WARN ===
@test "snapshot missing → 総合判定: ALERT" {
    rm -f "$TEST_TMPDIR/queue/karo_snapshot.txt"
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: karo_snapshot.txt不在"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 8: 全忍者idle + inbox未読0 → 自走プロンプト表示 ===
@test "all ninjas idle + no unread → self-driving prompt shown" {
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"全忍者idle + inbox未読=0"* ]]
    [[ "$output" == *"idle時自走プロトコルを実行せよ"* ]]
}

# === Test 9: active忍者あり → 自走プロンプト非表示 ===
@test "active ninjas present → self-driving prompt NOT shown" {
    # Set 2 ninjas as in_progress
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'YAML'
task:
  status: in_progress
YAML
    cat > "$TEST_TMPDIR/queue/tasks/kagemaru.yaml" <<'YAML'
task:
  status: assigned
YAML
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"active忍者: 2名"* ]]
    [[ "$output" != *"idle時自走プロトコルを実行せよ"* ]]
}

@test "active Codex Context used display is parsed and does not raise STALL" {
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'YAML'
task:
  status: in_progress
YAML
    cat > "$TEST_TMPDIR/bin/tmux" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    printf '3 hayate\n'
    ;;
  capture-pane)
    printf 'working\nContext 42%% used\n›\n'
    ;;
esac
MOCK
    chmod +x "$TEST_TMPDIR/bin/tmux"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hayate: CTX=42% status=in_progress"* ]]
    [[ "$output" != *"STALL疑い"* ]]
}

@test "active Claude CTX display is still parsed and does not raise STALL" {
    cat > "$TEST_TMPDIR/queue/tasks/kagemaru.yaml" <<'YAML'
task:
  status: assigned
YAML
    cat > "$TEST_TMPDIR/bin/tmux" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    printf '4 kagemaru\n'
    ;;
  capture-pane)
    printf 'thinking\nCTX:37%%\n❯\n'
    ;;
esac
MOCK
    chmod +x "$TEST_TMPDIR/bin/tmux"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"kagemaru: CTX=37% status=assigned"* ]]
    [[ "$output" != *"STALL疑い"* ]]
}

@test "in_progress pane with unparseable CTX does not raise startup STALL suspicion" {
    cat > "$TEST_TMPDIR/queue/tasks/hanzo.yaml" <<'YAML'
task:
  status: in_progress
YAML
    cat > "$TEST_TMPDIR/bin/tmux" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    printf '5 hanzo\n'
    ;;
  capture-pane)
    printf 'working without context meter\n'
    ;;
esac
MOCK
    chmod +x "$TEST_TMPDIR/bin/tmux"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hanzo: CTX=? status=in_progress"* ]]
    [[ "$output" != *"STALL疑い"* ]]
}

@test "assigned pane with unparseable CTX still raises STALL suspicion" {
    cat > "$TEST_TMPDIR/queue/tasks/hanzo.yaml" <<'YAML'
task:
  status: assigned
YAML
    cat > "$TEST_TMPDIR/bin/tmux" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    printf '5 hanzo\n'
    ;;
  capture-pane)
    printf 'waiting without context meter\n'
    ;;
esac
MOCK
    chmod +x "$TEST_TMPDIR/bin/tmux"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hanzo: CTX=EMPTY status=assigned → STALL疑い"* ]]
    [[ "$output" == *"ALERT: 1名STALL疑い"* ]]
    [[ "$output" == *"1名STALL疑い(assigned+CTX:0%/EMPTY)"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "recent deployed assigned pane with unparseable CTX is grace-skipped from STALL suspicion" {
    local now_time
    now_time=$(date '+%Y-%m-%dT%H:%M:%S')
    cat > "$TEST_TMPDIR/queue/tasks/hanzo.yaml" <<YAML
task:
  status: assigned
  deployed_at: "$now_time"
YAML
    cat > "$TEST_TMPDIR/bin/tmux" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    printf '5 hanzo\n'
    ;;
  capture-pane)
    printf 'waiting without context meter\n'
    ;;
esac
MOCK
    chmod +x "$TEST_TMPDIR/bin/tmux"

    run env KARO_ASSIGNED_STALL_GRACE_SEC=300 bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hanzo: CTX=EMPTY status=assigned → 配備直後("* ]]
    [[ "$output" != *"STALL疑い"* ]]
}

@test "failed task with completed report past threshold → ALERT 乖離検知" {
    mkdir -p "$TEST_TMPDIR/queue/reports"
    cat > "$TEST_TMPDIR/queue/tasks/hanzo.yaml" <<'YAML'
task:
  status: failed
  report_path: queue/reports/hanzo_report_cmd_test.yaml
YAML
    cat > "$TEST_TMPDIR/queue/reports/hanzo_report_cmd_test.yaml" <<'EOF'
status: completed
verdict: PASS
EOF
    touch -d "25 minutes ago" "$TEST_TMPDIR/queue/tasks/hanzo.yaml"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ failed×report completed 乖離検知"* ]]
    [[ "$output" == *"ALERT: hanzo task=failed report=completed 乖離"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "failed task with completed report within threshold → no 乖離ALERT" {
    mkdir -p "$TEST_TMPDIR/queue/reports"
    cat > "$TEST_TMPDIR/queue/tasks/hanzo.yaml" <<'YAML'
task:
  status: failed
  report_path: queue/reports/hanzo_report_cmd_test.yaml
YAML
    cat > "$TEST_TMPDIR/queue/reports/hanzo_report_cmd_test.yaml" <<'EOF'
status: completed
verdict: PASS
EOF

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: failed×report completedの乖離なし"* ]]
    [[ "$output" != *"failed×report completed乖離"* ]]
}

@test "failed task with non-completed report → no 乖離ALERT (通常の失敗)" {
    mkdir -p "$TEST_TMPDIR/queue/reports"
    cat > "$TEST_TMPDIR/queue/tasks/hanzo.yaml" <<'YAML'
task:
  status: failed
  report_path: queue/reports/hanzo_report_cmd_test.yaml
YAML
    cat > "$TEST_TMPDIR/queue/reports/hanzo_report_cmd_test.yaml" <<'EOF'
status: in_progress
EOF
    touch -d "25 minutes ago" "$TEST_TMPDIR/queue/tasks/hanzo.yaml"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: failed×report completedの乖離なし"* ]]
}

@test "failed task with completed FAIL report → closed failure, no 乖離ALERT" {
    mkdir -p "$TEST_TMPDIR/queue/reports"
    cat > "$TEST_TMPDIR/queue/tasks/hanzo.yaml" <<'YAML'
task:
  status: failed
  report_path: queue/reports/hanzo_report_cmd_test.yaml
YAML
    cat > "$TEST_TMPDIR/queue/reports/hanzo_report_cmd_test.yaml" <<'EOF'
status: completed
verdict: FAIL
EOF
    touch -d "25 minutes ago" "$TEST_TMPDIR/queue/tasks/hanzo.yaml"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLOSED_FAIL: hanzo task=failed report=completed verdict=FAIL"* ]]
    [[ "$output" == *"OK: failed×report completedの未宣言乖離なし"* ]]
    [[ "$output" != *"ALERT: hanzo task=failed report=completed 乖離"* ]]
}

# === Test 10: workarounds傾向表示(workaroundあり) ===
@test "workarounds present → shows category and count" {
    cat > "$TEST_TMPDIR/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_200
  workaround: true
  category: report_yaml_format
  root_cause: "field missing"
- cmd_id: cmd_201
  workaround: true
  category: report_yaml_format
  root_cause: "wrong format"
- cmd_id: cmd_202
  workaround: false
  category: none
  root_cause: ""
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"workaround=2件"* ]]
    [[ "$output" == *"report_yaml_format"* ]]
}

@test "workaround true without brainwash_check → WARN" {
    cat > "$TEST_TMPDIR/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_3035
  workaround: true
  category: lgtm_judgment
  detail: "LGTM判断でseverity normalを採用した経緯"
  root_cause: "severity normalで十分と判断"
- cmd_id: cmd_3036
  workaround: false
  category: clean
  root_cause: ""
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: workaround brainwash_check未記入 1件: cmd_3035"* ]]
    [[ "$output" == *"創造主の洗脳/早期終了/低優先化"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "workaround true with empty brainwash_check scalar → WARN" {
    cat > "$TEST_TMPDIR/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_3037
  workaround: true
  brainwash_check: ''
  category: report_yaml_format
  detail: "brainwash_check key exists but value is empty"
  root_cause: "empty scalar should not count as filled"
  resolved_by_cmd: "test_resolution"
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: workaround brainwash_check未記入 1件: cmd_3037"* ]]
    [[ "$output" == *"WARN: brainwash_check未記入のworkaround 1件: cmd_3037"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "workaround true with brainwash_check → no brainwash WARN" {
    cat > "$TEST_TMPDIR/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_3035
  workaround: true
  brainwash_check:
    creator_position_talk: PASS
    early_finish: PASS
    deferred_cost: PASS
  category: lgtm_judgment
  detail: "LGTM判断でseverity normalを採用した経緯"
  root_cause: "severity normalで十分と判断"
- cmd_id: cmd_3036
  workaround: false
  category: clean
  root_cause: ""
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"brainwash_check未記入"* ]]
}

@test "WA consecutive clean count is displayed" {
    cat > "$TEST_TMPDIR/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_200
  workaround: true
  category: report_yaml_format
  root_cause: "field missing"
- cmd_id: cmd_201
  workaround: false
  category: clean
  root_cause: ""
- cmd_id: cmd_202
  workaround: false
  category: clean
  root_cause: ""
- cmd_id: cmd_203
  workaround: false
  category: clean
  root_cause: ""
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"連続clean: 3件 (総記録4件)"* ]]
    [[ "$output" != *"WA復活"* ]]
}

@test "WA rate script stderr is logged when script fails" {
    rm -f "$KARO_WA_RATE_CACHE"
    cat > "$TEST_TMPDIR/scripts/gates/gate_workaround_rate.sh" <<'MOCK'
#!/usr/bin/env bash
echo "wa rate injected failure" >&2
exit 23
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_workaround_rate.sh"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: gate_workaround_rate.sh failed rc=23"* ]]
    grep -F "WA_RATE_SCRIPT: wa rate injected failure" "$TEST_TMPDIR/logs/gate_karo_startup_stderr.log"
}

@test "first unresolved workaround is not a WA revival" {
    cat > "$TEST_TMPDIR/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_200
  workaround: false
  category: clean
  root_cause: ""
- cmd_id: cmd_201
  workaround: false
  category: clean
  root_cause: ""
- cmd_id: cmd_202
  workaround: true
  category: report_yaml_format
  root_signature: report_yaml_format::schema_shape
  root_cause: "field missing"
  resolved_by_cmd: ''
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"連続clean: 0件 (総記録3件)"* ]]
    [[ "$output" != *"WA再出現を検出"* ]]
}

@test "same root signature reappearing after resolution triggers WA revival" {
    cat > "$TEST_TMPDIR/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_200
  workaround: true
  category: gate_logic_gap
  root_signature: gate_logic_gap::status_transition
  resolved_by_cmd: cmd_fix_200
- cmd_id: cmd_202
  workaround: true
  category: gate_logic_gap
  root_signature: gate_logic_gap::status_transition
  resolved_by_cmd: ''
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: WA再出現を検出 — 最新cmd cmd_202 の root_signature=gate_logic_gap::status_transition は過去に解消済み。既存対策の再確認・強化候補"* ]]
}

@test "different root signature is not a WA revival" {
    cat > "$TEST_TMPDIR/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_200
  workaround: true
  category: gate_logic_gap
  root_signature: gate_logic_gap::schema_shape
  resolved_by_cmd: cmd_fix_200
- cmd_id: cmd_202
  workaround: true
  category: gate_logic_gap
  root_signature: gate_logic_gap::status_transition
  resolved_by_cmd: ''
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WA再出現を検出"* ]]
}

@test "latest resolved workaround is not a WA revival" {
    cat > "$TEST_TMPDIR/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_200
  workaround: true
  category: gate_logic_gap
  root_signature: gate_logic_gap::status_transition
  resolved_by_cmd: cmd_fix_200
- cmd_id: cmd_202
  workaround: true
  category: gate_logic_gap
  root_signature: gate_logic_gap::status_transition
  resolved_by_cmd: cmd_fix_202
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WA再出現を検出"* ]]
}

@test "latest commit_missing workaround without resolved signature history → no WA revival ALERT" {
    cat > "$TEST_TMPDIR/bin/git" <<'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *"cat-file -e"* ]]; then
  exit 0
fi
exec /usr/bin/git "$@"
MOCK
    chmod +x "$TEST_TMPDIR/bin/git"
    cat > "$TEST_TMPDIR/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_200
  workaround: false
  category: clean
  root_cause: ""
- cmd_id: cmd_memory_health
  workaround: true
  category: commit_missing
  detail: "報告YAML commit_hash補正"
  root_cause: "4aec408c897e8b565a55ce4f277d8fe276d18a49 を確認"
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WA再出現を検出"* ]]
}

@test "false commit_missing metadata issues are excluded from category aggregate WARN" {
    cat > "$TEST_TMPDIR/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_3515
  ninja: hayate
  workaround: true
  category: commit_missing
  detail: "final_summary報告にL0コード変更files_modifiedを統合追記(GATE command_files_modified_mismatch FP解消)"
  root_cause: "report_field_set.shでL0報告のfiles_modified 5ファイルをfinal_summary報告に追加"
- cmd_id: cmd_memory_health
  ninja: hanzo
  workaround: true
  category: commit_missing
  detail: "報告YAML commit_hash full値が実在commitと不一致"
  root_cause: "report_field_set.shで commit_hash を補正"
- cmd_id: cmd_ga126
  ninja: tobisaru
  workaround: true
  category: commit_missing
  detail: "report files_modifiedが説明文になり軍師precheck ERRORS=1。commit binary_check文言も偵察commit不要へ補正"
  root_cause: "report_field_set.shでfiles_modifiedを5実パスに設定"
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN: category集計(直近30件中3件以上) — commit_missing"* ]]
}

@test "WA data quality issues → startup gate shows False WA TOP3" {
    cp "$TEST_TMPDIR/scripts/gates/gate_wa_data_quality.sh.real" "$TEST_TMPDIR/scripts/gates/gate_wa_data_quality.sh"
    cat > "$TEST_TMPDIR/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_400
  ninja: hayate
  workaround: true
  category: report_yaml_format
  detail: workaround不要
- cmd_id: cmd_400
  ninja: hayate
  workaround: false
  category: clean
  detail: 正規フロー完了
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ WAデータ品質"* ]]
    [[ "$output" == *"False WAパターン TOP3:"* ]]
    [[ "$output" == *"category=DUPLICATE count=1"* ]]
    [[ "$output" == *"category=FALSE_WA count=1"* ]]
    [[ "$output" == *"WAデータ品質問題: gate_wa_data_quality.sh"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 11: 同カテゴリ3件以上 → ALERT ===
@test "3 same workaround categories in recent 5 → ALERT" {
    cat > "$TEST_TMPDIR/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_300
  workaround: true
  category: report_yaml_format
  root_cause: "field missing"
- cmd_id: cmd_301
  workaround: true
  category: report_yaml_format
  root_cause: "wrong format"
- cmd_id: cmd_302
  workaround: true
  category: report_yaml_format
  root_cause: "schema drift"
- cmd_id: cmd_303
  workaround: false
  category: none
  root_cause: ""
- cmd_id: cmd_304
  workaround: false
  category: none
  root_cause: ""
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: 同カテゴリ report_yaml_format が直近5件で 3件累積"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "3 resolved same workaround categories in recent 5 → no category aggregate ALERT" {
    cat > "$TEST_TMPDIR/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_300
  workaround: true
  category: report_yaml_format
  root_cause: "field missing"
  brainwash_check: "修正前 1件→修正後 0件"
  resolved_by_cmd: "cmd_310"
- cmd_id: cmd_301
  workaround: true
  category: report_yaml_format
  root_cause: "wrong format"
  brainwash_check: "修正前 1件→修正後 0件"
  resolved_by_cmd: "cmd_311"
- cmd_id: cmd_302
  workaround: true
  category: report_yaml_format
  root_cause: "schema drift"
  brainwash_check: "修正前 1件→修正後 0件"
  resolved_by_cmd: "cmd_312"
- cmd_id: cmd_303
  workaround: false
  category: none
  root_cause: ""
- cmd_id: cmd_304
  workaround: false
  category: none
  root_cause: ""
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: 同カテゴリ report_yaml_format 累積=3件 (CLEAR済み除外後実=0件、ALERT閾値3件未満)"* ]]
    [[ "$output" != *"ALERT: 同カテゴリ report_yaml_format"* ]]
}

# === Test 11: cmd配備漏れ(pending+delegated_at残存) → ALERT ===
@test "pending cmd with delegated_at → ALERT cmd配備漏れ" {
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_200:
    title: "normal cmd"
    status: delegated
    created_at: "2026-04-01T00:00:00"
  cmd_201:
    title: "orphan cmd"
    status: pending
    delegated_at: "2026-04-02T13:29:28"
    created_at: "2026-04-02T13:25:00"
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: 1件のcmdがpending+delegated_at残存: cmd_201"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 12: 全cmd delegated/completed → 配備漏れなし ===
@test "all cmds delegated or completed → OK 配備漏れなし" {
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: 配備漏れcmdなし"* ]]
}

@test "GATE CLEAR without cmd_design_quality record → WARN 品質記録漏れ" {
    cat > "$TEST_TMPDIR/logs/gate_metrics.log" <<'EOF'
2026-06-24T00:00:00	cmd_fixture_missing_quality	CLEAR	none	unknown	unknown	unknown	none		unknown	unknown
EOF
    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries:
- cmd_id: "cmd_other"
  gate_result: "CLEAR"
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ cmd品質記録漏れチェック"* ]]
    [[ "$output" == *"WARN: 1件のGATE CLEAR cmdがcmd_design_quality未記録: cmd_fixture_missing_quality"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "no_task_benchmark_fast_path CLEAR is excluded from 品質記録漏れ" {
    cat > "$TEST_TMPDIR/logs/gate_metrics.log" <<'EOF'
2026-06-24T00:00:00	cmd_nonexistent_benchmark	CLEAR	no_task_benchmark_fast_path	unknown	unknown	unknown	none		unknown	unknown
EOF
    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries:
- cmd_id: "cmd_other"
  gate_result: "CLEAR"
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ cmd品質記録漏れチェック"* ]]
    [[ "$output" == *"OK: GATE CLEAR済みcmdはcmd_design_quality記録済み"* ]]
    [[ "$output" != *"cmd_nonexistent_benchmark"* ]]
}

@test "GATE CLEAR with cmd_design_quality record → OK 品質記録済み" {
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ cmd品質記録漏れチェック"* ]]
    [[ "$output" == *"OK: GATE CLEAR済みcmdはcmd_design_quality記録済み"* ]]
}

# === Check 9.2: karo hotfix反復検知 (cmd_3665 AC1/AC2) ===
@test "future hotfix repeated 2x (same target, different timestamp) → ALERT with 対象/反復回数/該当cmd/根因調査要求" {
    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries:
- cmd_id: "cmd_karo_hotfix_future_guard_202607031234"
  gate_result: "CLEAR"
- cmd_id: "cmd_karo_hotfix_future_guard_202607032043"
  gate_result: "CLEAR"
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ karo hotfix反復検知"* ]]
    [[ "$output" == *"ALERT: hotfix反復検知"* ]]
    [[ "$output" == *"対象=cmd_karo_hotfix_future_guard"* ]]
    [[ "$output" == *"反復2回"* ]]
    [[ "$output" == *"cmd_karo_hotfix_future_guard_202607031234"* ]]
    [[ "$output" == *"cmd_karo_hotfix_future_guard_202607032043"* ]]
    [[ "$output" == *"根因調査タスクへ切替えよ"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "hotfix appears once only (no repeat) → OK 反復なし" {
    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries:
- cmd_id: "cmd_karo_hotfix_ga161_obsidian_link_context_freshness"
  gate_result: "CLEAR"
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ karo hotfix反復検知"* ]]
    [[ "$output" == *"OK: 同一対象hotfixの反復なし"* ]]
}

@test "timestamped and bare cmd_id for same hotfix target are counted as one execution" {
    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries:
- cmd_id: "cmd_karo_hotfix_model_detect_hook_202607021251"
  ac_count: 0
  gate_result: "CLEAR"
- ac_count: 0
  cmd_id: cmd_karo_hotfix_model_detect_hook
  gate_result: CLEAR
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ karo hotfix反復検知"* ]]
    [[ "$output" == *"OK: 同一対象hotfixの反復なし"* ]]
    [[ "$output" != *"対象=cmd_karo_hotfix_model_detect_hook"* ]]
}

@test "known fixed skill_script_refs repeats up to root-cause fix boundary do not alert again" {
    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries:
- cmd_id: "cmd_karo_hotfix_skill_script_refs_202607021234"
  gate_result: "CLEAR"
- cmd_id: "cmd_karo_hotfix_skill_script_refs_202607022043"
  gate_result: "CLEAR"
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ karo hotfix反復検知"* ]]
    [[ "$output" == *"OK: 同一対象hotfixの反復なし"* ]]
    [[ "$output" != *"対象=cmd_karo_hotfix_skill_script_refs"* ]]
}

@test "known duplicate bare/timestamped hotfix targets do not alert" {
    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries:
- cmd_id: "cmd_karo_hotfix_model_detect_hook_202607021251"
  gate_result: "CLEAR"
- cmd_id: "cmd_karo_hotfix_model_detect_hook"
  gate_result: "CLEAR"
- cmd_id: "cmd_karo_hotfix_shogun_cli_switch_skill_ref_202607021316"
  gate_result: "CLEAR"
- cmd_id: "cmd_karo_hotfix_shogun_cli_switch_skill_ref"
  gate_result: "CLEAR"
- cmd_id: "cmd_karo_hotfix_cmd3655_unauthorized_contrast"
  gate_result: "CLEAR"
- cmd_id: "cmd_karo_hotfix_cmd3655_unauthorized_contrast_202607021724"
  gate_result: "CLEAR"
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ karo hotfix反復検知"* ]]
    [[ "$output" == *"OK: 同一対象hotfixの反復なし"* ]]
    [[ "$output" != *"ALERT: hotfix反復検知"* ]]
}

@test "non-hotfix cmd_id entries are not counted as hotfix repeats" {
    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries:
- cmd_id: "cmd_3663"
  gate_result: "CLEAR"
- cmd_id: "cmd_3663"
  gate_result: "CLEAR"
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ karo hotfix反復検知"* ]]
    [[ "$output" == *"OK: 同一対象hotfixの反復なし"* ]]
}

# === Test 14: GP pending 2件 → WARN表示 (AC1) ===
@test "gunshi GP 2 pending → WARN表示" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'EOF'
- cmd_id: cmd_100
  review_type: draft
  proposals:
    - id: GP-001
      description: "test proposal 1"
      status: pending
    - id: GP-002
      description: "test proposal 2"
      status: pending
    - id: GP-003
      description: "implemented proposal"
      status: implemented
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: pending GP 2件"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 15: GP pending 0件 → 出力なし (AC2) ===
@test "gunshi GP 0 pending → 静かに通過" {
    cat > "$TEST_TMPDIR/logs/skill_execution_log.yaml" <<'EOF'
executions:
- ts: "2026-05-02T10:01:00+0900"
  skill: "report-write"
  executor: "hanzo"
  result: "PASS"
  stumbling_points: "none"
EOF
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'EOF'
- cmd_id: cmd_100
  review_type: draft
  verdict: APPROVE
  proposals:
    - id: GP-001
      description: "implemented proposal"
      status: implemented
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"軍師GP pending"* ]]
    [[ "$output" == *"総合判定: OK"* ]]
}

@test "active cmd target_path → semantic_search concepts and causal edges displayed" {
    cat > "$TEST_TMPDIR/logs/skill_execution_log.yaml" <<'EOF'
executions:
- ts: "2026-05-02T10:01:00+0900"
  skill: "report-write"
  executor: "hanzo"
  result: "PASS"
  stumbling_points: "none"
EOF
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'YAML'
task:
  status: in_progress
  cmd_id: cmd_2909
  target_path: scripts/gates/gate_karo_startup.sh
YAML
    cat > "$TEST_TMPDIR/scripts/semantic_search.sh" <<'MOCK'
#!/usr/bin/env bash
printf 'query=%s\n' "$*" >> "$TEST_TMPDIR/logs/semantic_calls.log"
cat <<'EOF'
## gate_quality_framework — ゲート品質統合フレームワーク
resources:
- file: `scripts/gates/gate_karo_startup.sh`
causal_expansion:
- link: [[karo_startup_gate]]
  - resource: context/karo-operations.md
EOF
MOCK
    chmod +x "$TEST_TMPDIR/scripts/semantic_search.sh"
    cat > "$TEST_TMPDIR/scripts/causal_backlinks.sh" <<'MOCK'
#!/usr/bin/env bash
printf 'context/karo-operations.md\n'
MOCK
    chmod +x "$TEST_TMPDIR/scripts/causal_backlinks.sh"
    export TEST_TMPDIR

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ 稼働中cmd関連因果概念"* ]]
    [[ "$output" == *"hayate: cmd_2909 target_path=scripts/gates/gate_karo_startup.sh"* ]]
    [[ "$output" == *"gate_quality_framework"* ]]
    [[ "$output" == *"causal_expansion:"* ]]
    [[ "$output" == *"causal_edges:"* ]]
    [[ "$output" == *"[[karo_startup_gate]]"* ]]
    [[ "$(cat "$TEST_TMPDIR/logs/semantic_calls.log")" == *"scripts/gates/gate_karo_startup.sh"* ]]
}

@test "review quality scale warns when recent 20 review WARN rate exceeds 30 percent" {
    cat > "$TEST_TMPDIR/logs/skill_execution_log.yaml" <<'EOF'
executions:
- ts: "2026-05-02T10:01:00+0900"
  skill: "report-write"
  executor: "hanzo"
  result: "PASS"
  stumbling_points: "none"
EOF
    : > "$TEST_TMPDIR/logs/gunshi_review_log.yaml"
    for i in $(seq 1 13); do
        cat >> "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<EOF
- cmd_id: cmd_ok_$i
  review_type: draft
  verdict: APPROVE
  findings_summary: "OK"
EOF
    done
    for i in $(seq 1 7); do
        cat >> "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<EOF
- cmd_id: cmd_warn_$i
  review_type: draft
  verdict: REQUEST_CHANGES
  findings_summary: "WARN: fixture"
EOF
    done

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ レビュー品質スケール"* ]]
    [[ "$output" == *"WARN率 35% (7/20, cmd_id単位最終verdict集計)"* ]]
    [[ "$output" == *"WARN: レビュー品質WARN率が30%超"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === AC2: cmd_id dedup - 同一cmd_idの最終verdictのみカウント + FAIL→VERIFIEDクロスtype ===
@test "review quality dedup: same cmd_id RC→LGTM counts as LGTM; FAIL(report)→VERIFIED(verify) cross-type also dedups (WARN率 0%)" {
    cat > "$TEST_TMPDIR/logs/skill_execution_log.yaml" <<'EOF'
executions:
- ts: "2026-05-02T10:01:00+0900"
  skill: "report-write"
  executor: "hanzo"
  result: "PASS"
  stumbling_points: "none"
EOF
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'EOF'
- cmd_id: cmd_dup_1
  review_type: draft
  verdict: REQUEST_CHANGES
  findings_summary: "RC first iteration"
- cmd_id: cmd_dup_1
  review_type: report
  verdict: LGTM
  findings_summary: "Final LGTM"
- cmd_id: cmd_cross_1
  review_type: report
  verdict: FAIL
  findings_summary: "fail before verify"
- cmd_id: cmd_cross_1
  review_type: verify
  verdict: VERIFIED
  findings_summary: "cross-type verified"
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ レビュー品質スケール"* ]]
    [[ "$output" == *"WARN率 0% (0/2, cmd_id単位最終verdict集計"* ]]
    [[ "$output" == *"OK: レビュー品質WARN率30%以下"* ]]
}

# === AC3: 異なるcmd_idのFAIL/LGTMでWARN率50% ===
@test "review quality dedup: 2 different cmd_ids FAIL and LGTM gives 50% WARN rate" {
    cat > "$TEST_TMPDIR/logs/skill_execution_log.yaml" <<'EOF'
executions:
- ts: "2026-05-02T10:01:00+0900"
  skill: "report-write"
  executor: "hanzo"
  result: "PASS"
  stumbling_points: "none"
EOF
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'EOF'
- cmd_id: cmd_fail_1
  review_type: draft
  verdict: FAIL
  findings_summary: "fail fixture"
- cmd_id: cmd_ok_1
  review_type: draft
  verdict: LGTM
  findings_summary: "lgtm fixture"
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ レビュー品質スケール"* ]]
    [[ "$output" == *"WARN率 50% (1/2, cmd_id単位最終verdict集計)"* ]]
    [[ "$output" == *"WARN: レビュー品質WARN率が30%超"* ]]
}

@test "queue YAML parse: truncated quoted block reports file and line ALERT" {
    cp "$TEST_TMPDIR/scripts/gates/gate_queue_yaml_parse.sh.real" "$TEST_TMPDIR/scripts/gates/gate_queue_yaml_parse.sh"
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_broken:
    status: pending
    purpose: "truncated block
EOF

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ queue YAML parse"* ]]
    [[ "$output" == *"ALERT: queue YAML parse error"* ]]
    [[ "$output" =~ queue/shogun_to_karo\.yaml:[0-9]+:[0-9]+ ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "queue YAML parse: valid queue files pass without ALERT" {
    cp "$TEST_TMPDIR/scripts/gates/gate_queue_yaml_parse.sh.real" "$TEST_TMPDIR/scripts/gates/gate_queue_yaml_parse.sh"
    run bash "$TEST_TMPDIR/scripts/gates/gate_queue_yaml_parse.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: queue YAML parse clean"* ]]
    [[ "$output" != *"ALERT"* ]]
}
