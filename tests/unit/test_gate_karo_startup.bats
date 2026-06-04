#!/usr/bin/env bats
# test_gate_karo_startup.bats — gate_karo_startup.sh unit tests
# cmd_1554: 家老起動ゲート8項目チェックのテスト可能分岐を検証

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_karo_startup.sh"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/karo_startup.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" \
             "$TEST_TMPDIR/scripts/lib" \
             "$TEST_TMPDIR/queue/inbox" \
             "$TEST_TMPDIR/queue/tasks" \
             "$TEST_TMPDIR/memory" \
             "$TEST_TMPDIR/logs" \
             "$TEST_TMPDIR/data" \
             "$TEST_TMPDIR/docs/semantic-index"

    # Copy the gate script
    cp "$SRC_GATE_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_karo_startup.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_karo_startup.sh"
    cp "$PROJECT_ROOT/scripts/gates/gate_wa_data_quality.sh" "$TEST_TMPDIR/scripts/gates/gate_wa_data_quality.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_wa_data_quality.sh"
    cp "$PROJECT_ROOT/scripts/gates/gate_three_layer_health.sh" "$TEST_TMPDIR/scripts/gates/gate_three_layer_health.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_three_layer_health.sh"
    cp "$PROJECT_ROOT/scripts/lib/known_ninjas.sh" "$TEST_TMPDIR/scripts/lib/known_ninjas.sh"
    cp "$PROJECT_ROOT/scripts/cleanup_three_layer_tmp.sh" "$TEST_TMPDIR/scripts/cleanup_three_layer_tmp.sh"
    chmod +x "$TEST_TMPDIR/scripts/cleanup_three_layer_tmp.sh"
    cp "$PROJECT_ROOT/scripts/memory_db_live_insert.py" "$TEST_TMPDIR/scripts/memory_db_live_insert.py"
    cp "$PROJECT_ROOT/scripts/skill_execution_log.sh" "$TEST_TMPDIR/scripts/skill_execution_log.sh"
    chmod +x "$TEST_TMPDIR/scripts/skill_execution_log.sh"

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
  result: "PASS"
  stumbling_points: "none"
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

    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_karo_startup.sh"
    export KARO_WA_RATE_CACHE="$TEST_TMPDIR/karo_wa_rate_cache"
    export KARO_NINJA_WA_CACHE="$TEST_TMPDIR/karo_ninja_wa_cache"
    export KARO_SKILL_SUMMARY_CACHE="$TEST_TMPDIR/karo_skill_summary_cache"
    export KARO_AGGREGATE_CACHE="$TEST_TMPDIR/karo_startup_aggregate_cache"
    export SHOGUN_MEMORY_DB_CACHE_PATH="$TEST_TMPDIR/data/three_layer_health.db"
    export SHOGUN_THREE_LAYER_CACHE_WARN_BYTES=999999999
    export ORIG_PATH="$PATH"
    export PATH="$TEST_TMPDIR/bin:$PATH"
}

teardown() {
    export PATH="$ORIG_PATH"
    unset SHOGUN_MEMORY_DB_CACHE_PATH
    unset SHOGUN_THREE_LAYER_CACHE_WARN_BYTES
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
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
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"総合判定: OK"* ]]
    [[ "$output" == *"スキル品質: 全PASS"* ]]
}

@test "skill FAIL summary is displayed at startup" {
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"フェーズ別スキル一覧:"* ]]
    [[ "$output" == *"cmd完了処理: /cmd-complete"* ]]
    [[ "$output" == *"家老自立配備(CI修正/hotfix/recon2単独): /karo-direct"* ]]
    [[ "$output" == *"偵察2名配備: /recon-dual"* ]]
    [[ "$output" == *"スキル品質: dashboard-update FAIL:1"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

# === Test 2: 陣形図が30分以上古い → WARN ===
@test "snapshot older than 30 min → 総合判定: WARN" {
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
    [[ "$output" == *"総合判定: WARN"* ]]
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
@test "snapshot missing → 総合判定: WARN" {
    rm -f "$TEST_TMPDIR/queue/karo_snapshot.txt"
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: karo_snapshot.txt不在"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
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
    [[ "$output" == *"総合判定: WARN"* ]]
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

@test "latest workaround true → WA regression ALERT" {
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
  root_cause: "field missing"
EOF
    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"連続clean: 0件 (総記録3件)"* ]]
    [[ "$output" == *"ALERT: WA復活 — 最新cmd cmd_202 が workaround=true (category=report_yaml_format)"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "WA data quality issues → startup gate shows False WA TOP3" {
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
    [[ "$output" == *"総合判定: WARN"* ]]
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
