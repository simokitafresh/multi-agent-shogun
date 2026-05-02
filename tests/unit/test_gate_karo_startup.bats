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
             "$TEST_TMPDIR/queue/inbox" \
             "$TEST_TMPDIR/queue/tasks" \
             "$TEST_TMPDIR/memory" \
             "$TEST_TMPDIR/logs"

    # Copy the gate script
    cp "$SRC_GATE_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_karo_startup.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_karo_startup.sh"
    cp "$PROJECT_ROOT/scripts/skill_execution_log.sh" "$TEST_TMPDIR/scripts/skill_execution_log.sh"
    chmod +x "$TEST_TMPDIR/scripts/skill_execution_log.sh"

    # --- Default fixtures: all checks pass ---

    # Check 1: deepdive files exist (両ファイル必須: gate_karo_startup.sh REQUIRED_READ1+REQUIRED_READ2)
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
    export ORIG_PATH="$PATH"
    export PATH="$TEST_TMPDIR/bin:$PATH"
}

teardown() {
    export PATH="$ORIG_PATH"
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# === Test 1: 全項目正常 → 総合判定OK ===
@test "all checks pass → 総合判定: OK" {
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
@test "deepdive missing → 総合判定: ALERT" {
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
