#!/usr/bin/env bats
# test_gate_shogun_startup.bats — gate_shogun_startup.sh unit tests
# cmd_1556: 将軍起動ゲート15項目チェックのテスト可能分岐を検証

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_shogun_startup.sh"
    export REAL_GIT_BIN
    REAL_GIT_BIN="$(command -v git)"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1
    # Source once per file (function-only load) and export for run subshell
    SHOGUN_STARTUP_LIB_ONLY=1 source "$SRC_GATE_SCRIPT"
    export -f run_gate_shogun_startup

    # Build shared base directory once — all default-pass fixtures
    # Each test does: cp -a "$SHARED_BASE/." "$TEST_TMPDIR/" instead of recreating files
    export SHARED_BASE="$BATS_FILE_TMPDIR/base"
    mkdir -p "$SHARED_BASE/scripts/gates" \
             "$SHARED_BASE/queue/inbox" \
             "$SHARED_BASE/queue/archive" \
             "$SHARED_BASE/queue/tasks" \
             "$SHARED_BASE/memory" \
             "$SHARED_BASE/logs" \
             "$SHARED_BASE/context" \
             "$SHARED_BASE/docs/semantic-index" \
             "$SHARED_BASE/config" \
             "$SHARED_BASE/instructions" \
             "$SHARED_BASE/bin" \
             "$SHARED_BASE/fakehome/.claude/projects/-mnt-c-tools-multi-agent-shogun/memory"

    # Gate 1 mock: gate_shogun_memory.sh → OK
    cat > "$SHARED_BASE/scripts/gates/gate_shogun_memory.sh" <<'MOCK'
#!/usr/bin/env bash
echo "Memory健全度: OK"
MOCK
    chmod +x "$SHARED_BASE/scripts/gates/gate_shogun_memory.sh"

    # Gate 2 mock: gate_p_average_freshness.sh → OK
    cat > "$SHARED_BASE/scripts/gates/gate_p_average_freshness.sh" <<'MOCK'
#!/usr/bin/env bash
echo "p̄鮮度: OK"
MOCK
    chmod +x "$SHARED_BASE/scripts/gates/gate_p_average_freshness.sh"

    # Gate 2.5 mock: gate_knowledge_freshness.sh → OK
    cat > "$SHARED_BASE/scripts/gates/gate_knowledge_freshness.sh" <<'MOCK'
#!/usr/bin/env bash
echo "知識鮮度: OK — fresh=8 stale=0 warn=0 total=8"
MOCK
    chmod +x "$SHARED_BASE/scripts/gates/gate_knowledge_freshness.sh"

    # Gate 3.5: semantic index freshness (fresh by default)
    cat > "$SHARED_BASE/docs/semantic-index/index.md" <<'EOF'
# セマンティクスインデックス SSOT

## recalculate_pipeline — 再計算パイプライン

| 属性 | 値 |
|------|---|
| id | recalculate_pipeline |
| label | 再計算パイプライン |
| aliases | fullrecalculate, recalc |

| 種別 | パス/参照 |
|------|----------|
| file | `context/dm-signal-core.md` |
EOF

    # Gate 3 mock: gate_cmd_state.sh → OK
    cat > "$SHARED_BASE/scripts/gates/gate_cmd_state.sh" <<'MOCK'
#!/usr/bin/env bash
echo "cmd委任状態: OK"
MOCK
    chmod +x "$SHARED_BASE/scripts/gates/gate_cmd_state.sh"

    # Gate 12 mock: gate_loop_health.sh → OK
    cat > "$SHARED_BASE/scripts/gates/gate_loop_health.sh" <<'MOCK'
#!/usr/bin/env bash
echo "Total fires: 10"
echo "FAIL: 0"
echo "AUTO-FIXED: 0"
echo "Loop Status: OK"
MOCK
    chmod +x "$SHARED_BASE/scripts/gates/gate_loop_health.sh"

    # Gate 13 mock: gate_lesson_health.sh → OK
    cat > "$SHARED_BASE/scripts/gates/gate_lesson_health.sh" <<'MOCK'
#!/usr/bin/env bash
echo "教訓健全度: OK"
MOCK
    chmod +x "$SHARED_BASE/scripts/gates/gate_lesson_health.sh"

    # Gate 13.5: lessons_shogun.yaml (minimal pass)
    mkdir -p "$SHARED_BASE/projects/infra"
    cat > "$SHARED_BASE/projects/infra/lessons_shogun.yaml" <<'EOF'
lessons:
- id: LS001
  title: test lesson
  detail: test detail for gate pass
EOF

    # Gate 4: inbox with no unread
    cat > "$SHARED_BASE/queue/inbox/shogun.yaml" <<'EOF'
messages:
- content: test
  read: true
  id: msg_1
EOF

    echo "entries: []" > "$SHARED_BASE/queue/bulletin_board.yaml"

    # Gate 5: fresh snapshot (fixed future date — Gate 5 only displays, no staleness check)
    cat > "$SHARED_BASE/queue/karo_snapshot.txt" <<'EOF'
# 家老陣形図(karo_snapshot)
# Generated: 2099-01-01T00:00:00
ninja|hayate|cmd_100_impl|in_progress|infra|CTX:30%
ninja|kagemaru|cmd_101_impl|in_progress|infra|CTX:25%
EOF

    # Gate 6: required deepdive files
    echo "# deepdive content" > "$SHARED_BASE/memory/deepdive_why_chain_20260321.md"
    echo "# deepdive causal tracing" > "$SHARED_BASE/memory/deepdive_causal_tracing_20260415.md"

    # Gate 7: lord-conversation-index (no rulings)
    cat > "$SHARED_BASE/context/lord-conversation-index.md" <<'EOF'
# Lord Conversation Index
## 殿の直近裁定・方針
## その他
EOF

    # Gate 8: no insights file (simplest pass case)
    # (omit insights.yaml → "キューなし")

    # Gate 9: design quality + workarounds (minimal pass)
    cat > "$SHARED_BASE/logs/cmd_design_quality.yaml" <<'EOF'
- cmd_id: cmd_100
  karo_rework: false
  gate_result: PASS
EOF
    cat > "$SHARED_BASE/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_100
  workaround: false
  category: none
EOF

    # Gate 11: dashboard + review log (no proposals)
    echo "# Dashboard" > "$SHARED_BASE/dashboard.md"
    cat > "$SHARED_BASE/logs/gunshi_review_log.yaml" <<'EOF'
entries: []
EOF

    # Gate 14: no gunshi context files (pass)
    # (no gunshi-*.md in context/)

    cat > "$SHARED_BASE/context/senkyoku-log.md" <<'EOF'
# 戦局日誌

## 2099-01-01
- 2099-01-01 cmd_001: old entry
- 2099-01-01 cmd_002: recent entry 2
- 2099-01-01 cmd_003: recent entry 3
- 2099-01-01 cmd_004: recent entry 4
- 2099-01-01 cmd_005: recent entry 5
- 2099-01-01 cmd_006: recent entry 6
EOF

    # Gate 15: minimal knowledge map files for progress detection
    echo "# CLAUDE.md" > "$SHARED_BASE/CLAUDE.md"
    echo "# instructions" > "$SHARED_BASE/instructions/shogun.md"
    echo "# projects" > "$SHARED_BASE/config/projects.yaml"

    # HOME override for MEMORY.md path (Gate 15)
    echo "# MEMORY index" > "$SHARED_BASE/fakehome/.claude/projects/-mnt-c-tools-multi-agent-shogun/memory/MEMORY.md"

    # Mock git for rev-list (unpushed count)
    cat > "$SHARED_BASE/bin/git" <<'MOCK'
#!/usr/bin/env bash
if [ "$1" = "rev-list" ]; then
    echo "0"
elif [ "$1" = "log" ]; then
    echo "unknown"
elif [ "$1" = "status" ]; then
    exit 0
else
    "$REAL_GIT_BIN" "$@"
fi
MOCK
    chmod +x "$SHARED_BASE/bin/git"
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/shogun_startup.XXXXXX")"
    cp -a "$SHARED_BASE/." "$TEST_TMPDIR/"

    export ORIG_HOME="$HOME"
    export HOME="$TEST_TMPDIR/fakehome"
    export ORIG_PATH="$PATH"
    export PATH="$TEST_TMPDIR/bin:$PATH"
    export SHOGUN_STARTUP_ROOT="$TEST_TMPDIR"
    export SHOGUN_STARTUP_LIGHTWEIGHT=1
}

teardown() {
    export PATH="$ORIG_PATH"
    export HOME="$ORIG_HOME"
    unset SHOGUN_STARTUP_ROOT
    unset SHOGUN_STARTUP_LIGHTWEIGHT
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# === Test 1: 全項目正常 → 総合判定OK ===
@test "all checks pass → 総合判定: OK" {
    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"総合判定: OK"* ]]
}

@test "強制度監査 ALERT shows hook registration proposal" {
    unset SHOGUN_STARTUP_LIGHTWEIGHT
    cat > "$TEST_TMPDIR/scripts/gates/gate_enforcement_audit.sh" <<'MOCK'
#!/usr/bin/env bash
echo "=== 強制度監査 gate 2099-01-01T00:00:00+00:00 ==="
echo "■ CLAUDE.md 参照 script: 2 本"
echo "■ settings(*.json) 登録 hook script: 1 本"
echo ""
echo "■ ⚠️ 意志依存 script 検出: 1 本"
echo "  - scripts/hooks/manual_b.sh"
echo ""
echo "■ hooks登録コマンド候補(settings.json追記例)"
echo "  # 既定例: missing script を .claude/settings.json の SessionStart hooks に追記"
echo "  python3 - /tmp/example/.claude/settings.json <<'PY'"
echo "      'bash scripts/hooks/manual_b.sh',"
echo "  PY"
echo ""
echo "=== 総合判定: ALERT (要対処) ==="
exit 1
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_enforcement_audit.sh"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: 意志依存 script 1 本"* ]]
    [[ "$output" == *"hooks登録コマンド候補(settings.json追記例)"* ]]
    [[ "$output" == *"'bash scripts/hooks/manual_b.sh',"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "skill fail rate is displayed from skill execution log" {
    cat > "$TEST_TMPDIR/logs/skill_execution_log.yaml" <<'EOF'
executions:
- ts: "2099-01-01T00:00:00+0900"
  skill: "report-bundle"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "binary_checks empty"
- ts: "2099-01-01T00:01:00+0900"
  skill: "report-bundle"
  executor: "saizo"
  result: "PASS"
  stumbling_points: "fixed"
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ スキル別FAIL率"* ]]
    [[ "$output" == *"report-bundle: FAIL率=50% (1/2)"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "L6 learning speed shows per-gate FAIL to PASS transition rates" {
    export L6_LEARNING_NOW="2099-01-31T00:00:00+09:00"
    cat > "$TEST_TMPDIR/logs/gate_fire_log.yaml" <<'EOF'
- ts: "2099-01-02T00:00:00+09:00", file: "/tmp/test/report.yaml", gate: "gate_report_format", result: FAIL, reasons: "test fixture excluded"
- ts: "2099-01-10T00:00:00+09:00", file: "queue/reports/a.yaml", gate: "gate_report_format", result: FAIL, reasons: "binary_checks empty"
- ts: "2099-01-10T00:01:00+09:00", file: "queue/reports/a.yaml", gate: "gate_report_format", result: FAIL, reasons: "binary_checks empty"
- ts: "2099-01-10T00:02:00+09:00", file: "queue/reports/a.yaml", gate: "gate_report_format", result: PASS
- ts: "2099-01-11T00:00:00+09:00", file: "queue/reports/b.yaml", gate: "gate_report_format", result: FAIL, reasons: "verdict empty"
- ts: "2099-01-12T00:00:00+09:00", file: "queue/reports/c.yaml", gate: "gate_yaml_status", result: FAIL, reasons: "status bad"
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ L6学習速度"* ]]
    [[ "$output" == *"FAIL→PASS遷移率(直近30日):"* ]]
    [[ "$output" == *"gate_report_format: 67% (2/3 FAIL回復, 未回復=1, PASS=1)"* ]]
    [[ "$output" == *"gate_yaml_status: 0% (0/1 FAIL回復, 未回復=1, PASS=0)"* ]]
    [[ "$output" != *"test fixture excluded"* ]]
}

@test "L6 learning speed shows L6 rate from growth-loop section 11 lists" {
    cat > "$TEST_TMPDIR/context/growth-loop.md" <<'EOF'
# Growth Loop

## §11 防御階層原則

**L6化済み仕組み完全リスト(テスト)**:

| 対象 | 名称 | 実装箇所 | 機能 |
|------|------|----------|------|
| 忍者 | `ninja_weak_points` | `scripts/deploy_task.sh` | 弱点を注入する |
| 将軍 | `preflight_autolearn` | `scripts/cmd_save.sh` | WARNを学習する |
| 全体 | `lesson_impact.tsv` | `scripts/cmd_complete_gate.sh` | 教訓効果を計測する |

**L6未化仕組み(テスト)**:

| 名称 | 現Level | 不足内容 | L6化方向 |
|------|---------|----------|----------|
| `gate_context_freshness.sh` | Level 1 | stale検出のみ | 更新候補を注入する |
| `gate_enforcement_audit.sh` | Level 2 | 監査のみ | 改善候補へ接続する |
| `gate_knowledge_freshness.sh` | Level 4 | BLOCKのみ | 配備入力へ接続する |

## §12 Other
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"L6化率: 50% (3/6)"* ]]
    [[ "$output" == *"L6未到達仕組みTOP3:"* ]]
    [[ "$output" == *"L1 \`gate_context_freshness.sh\`: stale検出のみ"* ]]
    [[ "$output" == *"L2 \`gate_enforcement_audit.sh\`: 監査のみ"* ]]
    [[ "$output" == *"L4 \`gate_knowledge_freshness.sh\`: BLOCKのみ"* ]]
    [[ "$output" != *"\`preflight_autolearn\`: WARNを学習する"* ]]
}

# === Test 2: Memory健全度 ALERT → 総合判定ALERT ===
@test "Memory ALERT → 総合判定: ALERT" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_shogun_memory.sh" <<'MOCK'
#!/usr/bin/env bash
echo "Memory健全度: ALERT — MCP obs超過"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_shogun_memory.sh"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT"* ]]
    [[ "$output" == *"Memory健全度"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 3: p̄鮮度 ALERT → 総合判定ALERT ===
@test "p̄鮮度 ALERT → 総合判定: ALERT" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_p_average_freshness.sh" <<'MOCK'
#!/usr/bin/env bash
echo "p̄鮮度: ALERT — 7日超過"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_p_average_freshness.sh"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 4: cmd委任状態 ALERT → 総合判定ALERT ===
@test "cmd状態 ALERT → 総合判定: ALERT" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_cmd_state.sh" <<'MOCK'
#!/usr/bin/env bash
echo "cmd委任状態: ALERT — 長期滞留"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_cmd_state.sh"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT"* ]]
    [[ "$output" == *"cmd委任状態"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 5: 複合ALERT — Memory + 必読ファイル不在 ===
@test "compound: Memory ALERT + deepdive missing → 総合判定: ALERT with multiple alerts" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_shogun_memory.sh" <<'MOCK'
#!/usr/bin/env bash
echo "Memory健全度: ALERT"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_shogun_memory.sh"
    rm -f "$TEST_TMPDIR/memory/deepdive_why_chain_20260321.md"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"Memory健全度"* ]]
    [[ "$output" == *"必読ファイル不在"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 6: inbox未読あり → WARN ===
@test "inbox 2 unread → 総合判定: WARN" {
    cat > "$TEST_TMPDIR/queue/inbox/shogun.yaml" <<'EOF'
messages:
- content: msg1
  read: false
  id: msg_1
- content: msg2
  read: false
  id: msg_2
- content: msg3
  read: true
  id: msg_3
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"未読: 2件"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "bulletin pending for shogun → 総合判定: WARN" {
    cat > "$TEST_TMPDIR/queue/bulletin_board.yaml" <<'EOF'
entries:
- id: 'blt_test'
  content: |-
    全員確認事項
  posted_by: 'karo'
  posted_at: '2026-04-15T18:00:00'
  requires_confirmation: true
  confirmed_by:
    - 'karo'
  status: 'open'
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"掲示板未確認"* ]]
    [[ "$output" == *"WARN: 未確認掲示板 1件"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "senkyoku-log recent 5 entries are displayed at startup" {
    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ 戦局日誌 直近5エントリ"* ]]
    [[ "$output" != *"cmd_001: old entry"* ]]
    [[ "$output" == *"cmd_002: recent entry 2"* ]]
    [[ "$output" == *"cmd_003: recent entry 3"* ]]
    [[ "$output" == *"cmd_004: recent entry 4"* ]]
    [[ "$output" == *"cmd_005: recent entry 5"* ]]
    [[ "$output" == *"cmd_006: recent entry 6"* ]]
}

# === Test 7: 陣形図不在 → WARN ===
@test "snapshot missing → WARN 陣形図不在" {
    rm -f "$TEST_TMPDIR/queue/karo_snapshot.txt"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: karo_snapshot.txt不在"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

# === Test 8: 必読ファイル不在 → ALERT ===
@test "deepdive missing → 総合判定: ALERT" {
    rm -f "$TEST_TMPDIR/memory/deepdive_why_chain_20260321.md"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT"* ]]
    [[ "$output" == *"必読ファイル不在"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 9: idle自走トリガー ON (全忍者idle) ===
@test "all ninjas idle → idle trigger ON" {
    cat > "$TEST_TMPDIR/queue/karo_snapshot.txt" <<EOF
# 家老陣形図(karo_snapshot)
# Generated: $(date '+%Y-%m-%dT%H:%M:%S')
ninja|hayate|cmd_100_impl|idle|infra|CTX:0%
ninja|kagemaru|cmd_101_impl|idle|infra|CTX:0%
ninja|hanzo|cmd_102_impl|done|infra|CTX:0%
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"全忍者idle"* ]]
    [[ "$output" == *"idle時自己分析に入れ"* ]]
}

@test "all ninjas idle → gate_autofix_proposal runs automatically" {
    cat > "$TEST_TMPDIR/queue/karo_snapshot.txt" <<EOF
# 家老陣形図(karo_snapshot)
# Generated: $(date '+%Y-%m-%dT%H:%M:%S')
ninja|hayate|cmd_100_impl|idle|infra|CTX:0%
ninja|kagemaru|cmd_101_impl|idle|infra|CTX:0%
EOF
    cat > "$TEST_TMPDIR/scripts/gates/gate_autofix_proposal.sh" <<'MOCK'
#!/usr/bin/env bash
echo "AUTOFIX-PROPOSAL-RAN"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_autofix_proposal.sh"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ idle時BLOCK提案"* ]]
    [[ "$output" == *"AUTOFIX-PROPOSAL-RAN"* ]]
}

# === Test 10: active忍者あり → idle trigger OFF ===
@test "active ninjas → no idle trigger" {
    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" != *"全忍者idle"* ]]
    [[ "$output" == *"稼働中cmd"* ]]
    [[ "$output" == *"■ idle時BLOCK提案"* ]]
    [[ "$output" == *"SKIP: active cmdあり"* ]]
}

# Test 11 (--brief mode) は 2026-04-12 殿裁定で削除。
# 呼出元session_start_injectへの統合が21日間未実現のままdead code化したため撤去。

# === Test 12: 教訓健全度 ALERT → 総合判定ALERT ===
@test "lesson health ALERT → 総合判定: ALERT" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh" <<'MOCK'
#!/usr/bin/env bash
echo "教訓健全度: ALERT — 未振り分け10件"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT"* ]]
    [[ "$output" == *"教訓健全度"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 13: p̄鮮度 WARN (ALERTではない) → 総合判定WARN ===
@test "p̄鮮度 WARN → 総合判定: WARN" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_p_average_freshness.sh" <<'MOCK'
#!/usr/bin/env bash
echo "p̄鮮度: WARN — 3日超過"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_p_average_freshness.sh"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "知識辞書鮮度 ALERT → 総合判定: ALERT" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_knowledge_freshness.sh" <<'MOCK'
#!/usr/bin/env bash
echo "知識鮮度: ALERT — fresh=7 stale=1 warn=0 total=8"
echo "■ STALE更新候補 TOP3 (経過日数降順)"
echo "  1. docs/research/systems-knowledge-base/systems/ace.md (31 days old; verified_at=2026-03-19)"
echo "     command: python3 scripts/tools/update_verified_at.py docs/research/systems-knowledge-base/systems/ace.md 2026-04-19"
echo "  action: 上記 STALE ファイルの verified_at を更新し、bash scripts/gates/gate_knowledge_freshness.sh で再確認せよ"
exit 1
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_knowledge_freshness.sh"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"知識辞書鮮度"* ]]
    [[ "$output" == *"STALE更新候補 TOP3"* ]]
    [[ "$output" == *"docs/research/systems-knowledge-base/systems/ace.md (31 days old"* ]]
    [[ "$output" == *"python3 scripts/tools/update_verified_at.py docs/research/systems-knowledge-base/systems/ace.md 2026-04-19"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "semantic index stale 14+ days → 総合判定: ALERT" {
    touch -d '15 days ago' "$TEST_TMPDIR/docs/semantic-index/index.md"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"セマンティクスインデックス鮮度"* ]]
    [[ "$output" == *"ALERT: セマンティクスインデックスが"* ]]
    [[ "$output" == *"日間未更新"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

# === Test 14: 未処理PROPOSAL → WARN ===
@test "pending proposals → WARN with proposal count" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'EOF'
- cmd_id: cmd_test_prop
  proposals:
    - id: GP-999
      description: "テスト提案"
      status: pending
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"未処理PROPOSAL"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "stale pending insights older than threshold → ALERT" {
    export SHOGUN_STARTUP_LIGHTWEIGHT=0
    export INSIGHT_STALE_DAYS=7
    cat > "$TEST_TMPDIR/queue/insights.yaml" <<'EOF'
insights:
- id: INS-OLD
  ts: "2026-01-01T00:00:00+09:00"
  insight: "old pending insight"
  status: pending
- id: INS-FRESH
  ts: "2099-01-01T00:00:00+09:00"
  insight: "fresh pending insight"
  status: pending
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: 未消化insights 1件が7日超過"* ]]
    [[ "$output" == *"INS-OLD"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "karo_sent GP proposal older than threshold → ALERT" {
    export SHOGUN_STARTUP_LIGHTWEIGHT=0
    export GP_STALE_DAYS=14
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'EOF'
- cmd_id: cmd_gp_old
  review_type: self_study
  timestamp: "2026-01-01T00:00:00+09:00"
  proposals:
    - id: GP-OLD
      description: "old proposal"
      status: karo_sent
      sent_at: "2026-01-01T00:00:00+09:00"
- cmd_id: cmd_gp_done
  review_type: self_study
  timestamp: "2026-01-01T00:00:00+09:00"
  proposals:
    - id: GP-DONE
      description: "done proposal"
      status: implemented
      sent_at: "2026-01-01T00:00:00+09:00"
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ GP proposal滞留"* ]]
    [[ "$output" == *"ALERT: karo_sent GP 1件が14日超過"* ]]
    [[ "$output" == *"GP-OLD"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "same startup alert for 3 consecutive sessions → BLOCK" {
    export STARTUP_WARN_STREAK_THRESHOLD=3
    cat > "$TEST_TMPDIR/queue/inbox/shogun.yaml" <<'EOF'
messages:
- content: msg1
  read: false
  id: msg_1
EOF
    cat > "$TEST_TMPDIR/logs/shogun_startup_alert_history.tsv" <<'EOF'
run1	inbox未読: 1件
run2	inbox未読: 1件
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ startup WARN/ALERT連続出現"* ]]
    [[ "$output" == *"BLOCK: inbox未読: 1件 が3セッション連続"* ]]
    [[ "$output" == *"総合判定: BLOCK"* ]]
}

# Test 15 (--brief + ALERT) は 2026-04-12 殿裁定で削除。Test 11と同じ理由。

# === Test 16: AC注入一致 → WARNING無し (cmd_1668) ===
@test "AC injection match → OK, no WARNING" {
    mkdir -p "$TEST_TMPDIR/queue/tasks"
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  status: in_progress
  parent_cmd: cmd_100
  acceptance_criteria:
  - id: AC1
    description: "test ac1"
    criteria: "test criteria1"
  - id: AC2
    description: "test ac2"
    criteria: "test criteria2"
EOF
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_100:
    status: pending
    acceptance_criteria:
      - id: AC1
        description: "test ac1"
      - id: AC2
        description: "test ac2"
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"AC注入検証"* ]]
    [[ "$output" != *"WARNING: AC不一致"* ]]
    [[ "$output" == *"OK: 稼働中1件のAC整合確認"* ]]
}

# === Test 17: AC注入不一致(件数差) → WARNING出力 (cmd_1668) ===
@test "AC injection count mismatch → WARNING" {
    mkdir -p "$TEST_TMPDIR/queue/tasks"
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  status: in_progress
  parent_cmd: cmd_100
  acceptance_criteria:
  - id: AC1
    description: "test"
    criteria: "test"
EOF
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_100:
    status: pending
    acceptance_criteria:
      - id: AC1
        description: "test"
      - id: AC2
        description: "test2"
      - id: AC3
        description: "test3"
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: AC不一致"* ]]
    [[ "$output" == *"hayate(cmd_100)"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

# === Test 18: scout_exempt=true cmd → AC不一致でもWARNINGなし (AC2修正検証) ===
@test "scout_exempt=true cmd → AC mismatch skipped, no WARNING" {
    mkdir -p "$TEST_TMPDIR/queue/tasks"
    cat > "$TEST_TMPDIR/queue/tasks/hayate.yaml" <<'EOF'
task:
  status: assigned
  parent_cmd: cmd_100
  acceptance_criteria:
  - id: AC1
    description: "test"
EOF
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_100:
    status: pending
    scout_exempt: true
    acceptance_criteria:
      - id: AC1
        description: "test"
      - id: AC2
        description: "test2"
      - id: AC3
        description: "test3"
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING: AC不一致"* ]]
}
