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
    # NOTE: run_gate_shogun_startup is NOT sourced/exported here. Each @test
    # runs in its own forked process, so `export -f` would be required for
    # `run run_gate_shogun_startup` to find it — but the function body is
    # ~147KB, which exceeds Linux's per-string execve() limit (MAX_ARG_STRLEN,
    # 128KB) once serialized into the BASH_FUNC_*%% env var, causing every
    # subsequent external command (mkdir, rm, ...) in that process to fail
    # with "Argument list too long" (GA-162/GA-163, cmd_karo_hotfix_ga162).
    # Instead, setup() below re-sources $SRC_GATE_SCRIPT fresh in each test's
    # own process — same function, zero environment-size cost.

    # Build shared base directory once — all default-pass fixtures
    # Each test does: cp -a "$SHARED_BASE/." "$TEST_TMPDIR/" instead of recreating files
    export SHARED_BASE="$BATS_FILE_TMPDIR/base"
    mkdir -p "$SHARED_BASE/scripts/gates" \
             "$SHARED_BASE/skills/report-write" \
             "$SHARED_BASE/skills/ninja-commit" \
             "$SHARED_BASE/queue/inbox" \
             "$SHARED_BASE/queue/archive" \
             "$SHARED_BASE/queue/tasks" \
             "$SHARED_BASE/memory" \
             "$SHARED_BASE/logs" \
             "$SHARED_BASE/context" \
             "$SHARED_BASE/data" \
             "$SHARED_BASE/docs/semantic-index" \
             "$SHARED_BASE/config" \
             "$SHARED_BASE/instructions" \
             "$SHARED_BASE/bin" \
             "$SHARED_BASE/fakehome/.claude/projects/-mnt-c-tools-multi-agent-shogun/memory"

    cp "$PROJECT_ROOT/scripts/gates/gate_fp_relaxation_proposal.py" "$SHARED_BASE/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_three_layer_health.sh" "$SHARED_BASE/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/session_alerts_render.sh" "$SHARED_BASE/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/weekly_metrics_trend.sh" "$SHARED_BASE/scripts/"
    cp "$PROJECT_ROOT/scripts/skill_usage_metrics.sh" "$SHARED_BASE/scripts/"
    cp "$PROJECT_ROOT/scripts/cleanup_three_layer_tmp.sh" "$SHARED_BASE/scripts/"
    cp "$PROJECT_ROOT/scripts/memory_db_live_insert.py" "$SHARED_BASE/scripts/"
    chmod +x "$SHARED_BASE/scripts/gates/gate_three_layer_health.sh" \
             "$SHARED_BASE/scripts/gates/session_alerts_render.sh" \
             "$SHARED_BASE/scripts/weekly_metrics_trend.sh" \
             "$SHARED_BASE/scripts/skill_usage_metrics.sh" \
             "$SHARED_BASE/scripts/cleanup_three_layer_tmp.sh"
    cat > "$SHARED_BASE/scripts/gates/q6_target_fixture.sh" <<'EOF'
#!/usr/bin/env bash
q6_target_probe() {
    return 0
}
EOF

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
  origin: '[[cmd_001]]'
  detail: test detail for gate pass
EOF

    cat > "$SHARED_BASE/skills/report-write/SKILL.md" <<'EOF'
---
name: report-write
---
# report-write
EOF
    cat > "$SHARED_BASE/skills/ninja-commit/SKILL.md" <<'EOF'
---
name: ninja-commit
---
# ninja-commit
EOF
    touch -d '2099-01-01T00:00:00Z' "$SHARED_BASE/skills/report-write/SKILL.md" "$SHARED_BASE/skills/ninja-commit/SKILL.md"
    cat > "$SHARED_BASE/logs/skill_recommend_log.yaml" <<'EOF'
recommendations:
- ts: "2099-01-01T00:00:00+09:00"
  agent_id: "hanzo"
  prompt_hash: "fixture"
  recommended_skills:
  - "report-write"
EOF

    # Gate 4: inbox with no unread
    cat > "$SHARED_BASE/queue/inbox/shogun.yaml" <<'EOF'
messages:
- content: test
  read: true
  id: msg_1
EOF
    cat > "$SHARED_BASE/queue/inbox/karo.yaml" <<'EOF'
messages: []
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

    cat > "$SHARED_BASE/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2099-01-01T00:00:00+09:00","direction":"response","agent":"shogun","source":"terminal","target":"lord","summary":"Q6回答: 今の判断で早期終了本能が作用していないか確認した。殿のための判断として一次データとテストで検証し、Anthropicのための簡潔化に逃げない。自動化ターゲット: scripts/gates/q6_target_fixture.sh に `q6_target_probe` をgrep検証する。"}
EOF

    cat > "$SHARED_BASE/queue/bulletin_board.yaml" <<'EOF'
entries:
- id: 'blt_q6_self_detection'
  content: |-
    Q6回答: 創造主の洗脳チェック。早期終了ではなくテストfixtureで自動化ターゲットまで確認する。
  posted_by: 'shogun'
  posted_at: '2099-01-01T00:00:00'
  requires_confirmation: false
  action_type: 'info'
  actioned_by: ''
  confirmed_by: []
  status: 'open'
EOF

    # Gate 8: no insights file (simplest pass case)
    # (omit insights.yaml → "キューなし")

    # Gate 9: design quality + workarounds (minimal pass)
    cat > "$SHARED_BASE/logs/cmd_design_quality.yaml" <<'EOF'
- cmd_id: cmd_100
  karo_rework: false
  gate_result: PASS
  timestamp: "2099-01-01T00:00:00Z"
EOF
    cat > "$SHARED_BASE/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_100
  workaround: false
  category: none
EOF
    cat > "$SHARED_BASE/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score	traversal_depth
2099-01-01T00:00:00Z	cmd_100	hayate	L001	feedback	USEFUL	yes	infra	full	unknown	0	0
EOF

    # Gate 11: dashboard + review log (no proposals)
    echo "# Dashboard" > "$SHARED_BASE/dashboard.md"
    cat > "$SHARED_BASE/logs/gunshi_review_log.yaml" <<'EOF'
entries: []
EOF

    # Gate 12.1: three-layer memory health minimal PASS fixture
    python3 - "$SHARED_BASE/data/three_layer_health.db" <<'PY'
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
        ("event:candidate", "contradiction_candidate", "candidate content"),
    ],
)
conn.execute("INSERT INTO search_logs (ts, created_at) VALUES (datetime('now'), datetime('now'))")
conn.commit()
conn.close()
PY

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

    cat > "$SHARED_BASE/bin/gh" <<'MOCK'
#!/usr/bin/env bash
if [ "$1" = "run" ] && [ "$2" = "list" ]; then
    printf '[{"conclusion":"success"}]\n'
    exit 0
fi
exit 1
MOCK
    chmod +x "$SHARED_BASE/bin/gh"

    cat > "$SHARED_BASE/bin/crontab" <<'MOCK'
#!/usr/bin/env bash
if [ "${1:-}" = "-l" ]; then
    cat "${SHOGUN_STARTUP_ROOT}/crontab" 2>/dev/null || true
    exit 0
fi
exit 2
MOCK
    chmod +x "$SHARED_BASE/bin/crontab"

    cat > "$SHARED_BASE/scripts/inbox_write.sh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SHOGUN_STARTUP_ROOT}/logs/inbox_write_calls.log"
MOCK
    chmod +x "$SHARED_BASE/scripts/inbox_write.sh"
}

setup() {
    # Fresh per-test process: re-source for a local (non-exported) function def.
    SHOGUN_STARTUP_LIB_ONLY=1 source "$SRC_GATE_SCRIPT"

    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/shogun_startup.XXXXXX")"
    cp -a "$SHARED_BASE/." "$TEST_TMPDIR/"

    export ORIG_HOME="$HOME"
    export HOME="$TEST_TMPDIR/fakehome"
    export ORIG_PATH="$PATH"
    export PATH="$TEST_TMPDIR/bin:$PATH"
    export SHOGUN_STARTUP_ROOT="$TEST_TMPDIR"
    export SHOGUN_STARTUP_LIGHTWEIGHT=1
    export SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=1
    export SHOGUN_MEMORY_DB_CACHE_PATH="$TEST_TMPDIR/data/three_layer_health.db"
    export SHOGUN_THREE_LAYER_CACHE_WARN_BYTES=999999999
    export WEEKLY_METRICS_NOW="2099-01-01T00:00:00Z"
    cat > "$TEST_TMPDIR/crontab" <<EOF
17 0 * * 1 cd "$TEST_TMPDIR" && "$TEST_TMPDIR/scripts/weekly_metrics_trend.sh" >/dev/null 2>&1 # shogun-weekly-metrics-trend
EOF
}

teardown() {
    export PATH="$ORIG_PATH"
    export HOME="$ORIG_HOME"
    unset SHOGUN_STARTUP_ROOT
    unset SHOGUN_STARTUP_LIGHTWEIGHT
    unset SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT
    unset SHOGUN_MEMORY_DB_CACHE_PATH
    unset SHOGUN_THREE_LAYER_CACHE_WARN_BYTES
    unset WEEKLY_METRICS_NOW
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# === Test 1: 全項目正常 → 総合判定OK ===
@test "all checks pass → 総合判定: OK" {
    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: 自動化ターゲット実装証拠 grep検証"* ]]
    [[ "$output" == *"■ 週次品質指標トレンド"* ]]
    [[ "$output" == *"OK: weekly metrics trend"* ]]
    [[ "$output" == *"OK: weekly_metrics_trend cron registered"* ]]
    [[ "$output" == *"総合判定: OK"* ]]
}

@test "weekly metrics three-week worsening is surfaced as startup ALERT" {
    cat > "$TEST_TMPDIR/logs/weekly_metrics_trend.yaml" <<'EOF'
snapshots:
- week_start: "2098-12-11T00:00:00Z"
  week_end: "2098-12-18T00:00:00Z"
  useful_rate: 80.0
  useful: 8
  feedback_total: 10
  rework_rate: 10.0
  rework: 1
  cmd_quality_total: 10
  block_rate: 10.0
  blocks: 1
  source: "weekly_metrics_trend.sh"
- week_start: "2098-12-18T00:00:00Z"
  week_end: "2098-12-25T00:00:00Z"
  useful_rate: 70.0
  useful: 7
  feedback_total: 10
  rework_rate: 20.0
  rework: 2
  cmd_quality_total: 10
  block_rate: 20.0
  blocks: 2
  source: "weekly_metrics_trend.sh"
EOF
    cat > "$TEST_TMPDIR/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score	traversal_depth
2098-12-31T00:00:00Z	cmd_1	hayate	L001	feedback	USEFUL	yes	infra	full	unknown	0	0
2098-12-31T01:00:00Z	cmd_2	hayate	L002	feedback	NOT_USEFUL	no	infra	full	unknown	0	0
EOF
    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries:
- cmd_id: "cmd_1"
  gate_result: "BLOCK"
  karo_rework: "yes"
  timestamp: "2098-12-31T00:00:00Z"
- cmd_id: "cmd_2"
  gate_result: "PASS"
  karo_rework: "no"
  timestamp: "2098-12-31T01:00:00Z"
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ 週次品質指標トレンド"* ]]
    [[ "$output" == *"ALERT: useful_rate 3週連続悪化"* ]]
    [[ "$output" == *"ALERT: rework_rate 3週連続悪化"* ]]
    [[ "$output" == *"ALERT: block_rate 3週連続悪化"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "weekly metrics previous-week delta is surfaced in startup output" {
    cat > "$TEST_TMPDIR/logs/weekly_metrics_trend.yaml" <<'EOF'
snapshots:
- week_start: "2098-12-18T00:00:00Z"
  week_end: "2098-12-25T00:00:00Z"
  useful_rate: 75.0
  useful: 3
  feedback_total: 4
  rework_rate: 25.0
  rework: 1
  cmd_quality_total: 4
  block_rate: 25.0
  blocks: 1
  source: "weekly_metrics_trend.sh"
alerts: []
EOF
    cat > "$TEST_TMPDIR/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score	traversal_depth
2098-12-31T00:00:00Z	cmd_1	hayate	L001	feedback	USEFUL	yes	infra	full	unknown	0	0
2098-12-31T01:00:00Z	cmd_2	hayate	L002	feedback	NOT_USEFUL	no	infra	full	unknown	0	0
EOF
    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries:
- cmd_id: "cmd_1"
  gate_result: "BLOCK"
  karo_rework: "yes"
  timestamp: "2098-12-31T00:00:00Z"
- cmd_id: "cmd_2"
  gate_result: "PASS"
  karo_rework: "no"
  timestamp: "2098-12-31T01:00:00Z"
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"DELTA: weekly_metrics_trend useful_rate=-25.0pp rework_rate=+25.0pp block_rate=+25.0pp"* ]]
}

@test "weekly metrics missing cron is surfaced as startup ALERT" {
    : > "$TEST_TMPDIR/crontab"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: weekly_metrics_trend cron missing"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "CI RED failure sends ci_red_fix to karo and shows WARN" {
    cat > "$TEST_TMPDIR/bin/gh" <<'MOCK'
#!/usr/bin/env bash
if [ "$1" = "run" ] && [ "$2" = "list" ]; then
    printf '[{"conclusion":"failure"}]\n'
    exit 0
fi
exit 1
MOCK
    chmod +x "$TEST_TMPDIR/bin/gh"

    export SHOGUN_STARTUP_GH_TIMEOUT=5
    export SHOGUN_STARTUP_INBOX_TIMEOUT=5
    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ CI RED自動修正配備"* ]]
    [[ "$output" == *"WARN: 最新CI conclusion=failure"* ]]
    [[ "$output" == *"ACTION: karoへci_red_fix通知送信"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
    grep -q "karo CI RED検知: 最新GitHub Actions conclusion=failure" "$TEST_TMPDIR/logs/inbox_write_calls.log"
    grep -q "ci_red_fix gate_shogun_startup" "$TEST_TMPDIR/logs/inbox_write_calls.log"
}

@test "CI GREEN passes silently without WARN or inbox notification" {
    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" != *"■ CI RED自動修正配備"* ]]
    [[ "$output" != *"CI RED"* ]]
    [[ "$output" != *"ci_red_fix"* ]]
    [ ! -f "$TEST_TMPDIR/logs/inbox_write_calls.log" ]
    [[ "$output" == *"総合判定: OK"* ]]
}

@test "Q6 automation target proof missing keyword → 総合判定: BLOCK" {
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2099-01-01T00:00:00+09:00","direction":"response","agent":"shogun","source":"terminal","target":"lord","summary":"Q6回答: 今の判断で早期終了本能が作用していないか確認した。殿のための判断として一次データとテストで検証し、Anthropicのための簡潔化に逃げない。自動化ターゲット: scripts/gates/q6_target_fixture.sh に `definitely_missing_q6_probe` をgrep検証する。"}
EOF

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCK: 自動化ターゲット実装証拠未検出"* ]]
    [[ "$output" == *"definitely_missing_q6_probe"* ]]
    [[ "$output" == *"総合判定: BLOCK"* ]]
}

@test "Q6 automation target proof implemented keyword → 総合判定: OK" {
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2099-01-01T00:00:00+09:00","direction":"response","agent":"shogun","source":"terminal","target":"lord","summary":"Q6回答: 今の判断で早期終了本能が作用していないか確認した。殿のための判断として一次データとテストで検証し、Anthropicのための簡潔化に逃げない。自動化ターゲット: scripts/gates/q6_target_fixture.sh に `q6_target_probe` をgrep検証する。"}
EOF

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: Q6(創造主の洗脳チェック)回答検出 + 自動化ターゲット記入あり"* ]]
    [[ "$output" == *"OK: 自動化ターゲット実装証拠 grep検証"* ]]
    [[ "$output" == *"総合判定: OK"* ]]
}

@test "Q6 automation target without explicit path resolves commit hook proof → no grep skip" {
    mkdir -p "$TEST_TMPDIR/scripts/hooks"
    cat > "$TEST_TMPDIR/scripts/hooks/git-pre-commit.sh" <<'EOF'
#!/usr/bin/env bash
# pre-commit hook fixture
EOF

    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2099-01-01T00:00:00+09:00","direction":"response","agent":"shogun","source":"terminal","target":"lord","summary":"Q6回答: 洗脳#2検証スキップを避けるため、殿のために一次データで確認する。自動化ターゲット: 整形混入L0防止(指示書外の整形差分をcommit前に検出する仕組み)のcmd起票=3連続見逃しの環境埋込み。軍師の第三者検証を請う"}
EOF

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: Q6(創造主の洗脳チェック)回答検出 + 自動化ターゲット記入あり"* ]]
    [[ "$output" == *"OK: 自動化ターゲット実装証拠 grep検証"* ]]
    [[ "$output" == *"scripts/hooks/git-pre-commit.sh: pre-commit"* ]]
    [[ "$output" != *"WARN: 自動化ターゲット実装証拠 grep検証スキップ"* ]]
    [[ "$output" == *"総合判定: OK"* ]]
}

@test "Q6 automation target without explicit path resolves backlinks proof → no grep skip" {
    cat > "$TEST_TMPDIR/scripts/causal_backlink_counts.sh" <<'EOF'
#!/usr/bin/env bash
# backlink proof fixture
exit 0
EOF
    chmod +x "$TEST_TMPDIR/scripts/causal_backlink_counts.sh"
    cat > "$TEST_TMPDIR/context/semantic-map.md" <<'EOF'
# Semantic Map

## causal network

因果リンク and backlinks are connected here.
EOF

    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2099-01-01T00:00:00+09:00","direction":"response","agent":"shogun","source":"terminal","target":"lord","summary":"Q6回答: 洗脳#5先送りで止まらないよう、殿のためにD0で行動する。自動化ターゲット: backlinks=0のD0因果リンク接続(8回繰返し先送り)"}
EOF

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: Q6(創造主の洗脳チェック)回答検出 + 自動化ターゲット記入あり"* ]]
    [[ "$output" == *"OK: 自動化ターゲット実装証拠 grep検証"* ]]
    [[ "$output" == *"scripts/causal_backlink_counts.sh: backlink"* ]]
    [[ "$output" == *"context/semantic-map.md:"* ]]
    [[ "$output" == *"backlink"* ]]
    [[ "$output" == *"因果リンク"* ]]
    [[ "$output" != *"WARN: 自動化ターゲット実装証拠 grep検証スキップ"* ]]
    [[ "$output" == *"総合判定: OK"* ]]
}

@test "Q6 automation target accepts markdown bold label → 総合判定: OK" {
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2099-01-01T00:00:00+09:00","direction":"response","agent":"shogun","source":"terminal","target":"lord","summary":"Q6回答: 今の判断で早期終了本能が作用していないか確認した。殿のための判断として一次データとテストで検証し、Anthropicのための簡潔化に逃げない。**自動化ターゲット**: scripts/gates/q6_target_fixture.sh に `q6_target_probe` をgrep検証する。"}
EOF

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: Q6(創造主の洗脳チェック)回答検出 + 自動化ターゲット記入あり"* ]]
    [[ "$output" == *"OK: 自動化ターゲット実装証拠 grep検証"* ]]
    [[ "$output" == *"総合判定: OK"* ]]
}

@test "Q6 empty automation target accepts markdown bold label → same alert key" {
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2099-01-01T00:00:00+09:00","direction":"response","agent":"shogun","source":"terminal","target":"lord","summary":"Q6回答: 今の判断で早期終了本能が作用していないか確認した。殿のための判断として一次データで検証する。**自動化ターゲット**: なし"}
EOF

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: Q6回答は検出したが自動化ターゲット未記入"* ]]
    [[ "$output" == *"action: Q6回答に「自動化ターゲット: scripts/... の具体ファイル + 実装済み/テスト追加済みの証拠」を1行で書け"* ]]
    [[ "$output" == *"追体験自動化ターゲット: WARN"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "Q6 weak automation target proposal is missing target, not proof skip" {
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2099-01-01T00:00:00+09:00","direction":"response","agent":"shogun","source":"terminal","target":"lord","summary":"Q6回答: 洗脳#5の先送りを確認した。殿のための判断として行動まで進める。自動化ターゲット: 教訓上限ALERTにlesson統合の具体手順をgate出力へ埋め込む案を検討する"}
EOF

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: Q6回答は検出したが自動化ターゲット未記入"* ]]
    [[ "$output" != *"WARN: 自動化ターゲット実装証拠 grep検証スキップ"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "Q6 automation target negated weak words are accepted" {
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2099-01-01T00:00:00+09:00","direction":"response","agent":"shogun","source":"terminal","target":"lord","summary":"Q6回答: 洗脳#6を検出し、殿のためにD0修正済み。自動化ターゲット: LS053として登録済み。検討・予定ではなく登録完了済み。scripts/gates/q6_target_fixture.sh に `q6_target_probe` をgrep検証する。"}
EOF

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: Q6(創造主の洗脳チェック)回答検出 + 自動化ターゲット記入あり"* ]]
    [[ "$output" == *"OK: 自動化ターゲット実装証拠 grep検証"* ]]
    [[ "$output" == *"総合判定: OK"* ]]
}

@test "Q6 action words without automation target label are accepted as fallback" {
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2099-01-01T00:00:00+09:00","direction":"response","agent":"shogun","source":"terminal","target":"lord","summary":"Q6回答: 洗脳#6出力=仕事で止まらないよう、cmd起票して scripts/gates/q6_target_fixture.sh に `q6_target_probe` をgrep検証する。殿のために行動まで進める。"}
EOF

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: Q6(創造主の洗脳チェック)回答検出 + 自動化ターゲット記入あり"* ]]
    [[ "$output" == *"OK: 自動化ターゲット実装証拠 grep検証"* ]]
    [[ "$output" == *"総合判定: OK"* ]]
}

@test "Q6 without label or action words keeps missing automation warning" {
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2099-01-01T00:00:00+09:00","direction":"response","agent":"shogun","source":"terminal","target":"lord","summary":"Q6回答: 洗脳#6出力=仕事を確認した。殿のために一次情報を見る。結論だけでは終わらない。"}
EOF

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: Q6回答は検出したが自動化ターゲット未記入"* ]]
    [[ "$output" != *"OK: Q6(創造主の洗脳チェック)回答検出 + 自動化ターゲット記入あり"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "Q6 explicit no action word keeps missing automation warning" {
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2099-01-01T00:00:00+09:00","direction":"response","agent":"shogun","source":"terminal","target":"lord","summary":"Q6回答: 洗脳#5先送りを確認した。cmd起票なし。特になし。"}
EOF

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: Q6回答は検出したが自動化ターゲット未記入"* ]]
    [[ "$output" != *"OK: Q6(創造主の洗脳チェック)回答検出 + 自動化ターゲット記入あり"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "lessons_shogun origin missing or linkless → 総合判定: WARN" {
    cat > "$TEST_TMPDIR/projects/infra/lessons_shogun.yaml" <<'EOF'
lessons:
- id: LS001
  title: missing origin
  detail: test detail
- id: LS002
  title: empty origin
  origin: ''
  detail: test detail
- id: LS003
  title: no causal link
  origin: plain text only
  detail: test detail
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ 将軍教訓origin"* ]]
    [[ "$output" == *"WARN: lessons_shogun.yaml origin因果リンク不備 3/3件"* ]]
    [[ "$output" == *"origin欠落: LS001"* ]]
    [[ "$output" == *"origin空: LS002"* ]]
    [[ "$output" == *"リンク0件: LS003"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "lessons_shogun all origins with causal links → origin WARN is not shown" {
    cat > "$TEST_TMPDIR/projects/infra/lessons_shogun.yaml" <<'EOF'
lessons:
- id: LS001
  title: linked origin
  origin: '[[cmd_001]]'
  detail: test detail
- id: LS002
  title: linked ruling origin
  origin: '[[殿裁定2026-05-17]]'
  detail: test detail
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: lessons_shogun.yaml origin因果リンク (2件)"* ]]
    [[ "$output" != *"origin因果リンク不備"* ]]
    [[ "$output" == *"総合判定: OK"* ]]
}

@test "backlinks=0 files are displayed as training candidates when count script exists" {
    cp "$PROJECT_ROOT/scripts/causal_backlink_counts.sh" "$TEST_TMPDIR/scripts/"
    chmod +x "$TEST_TMPDIR/scripts/causal_backlink_counts.sh"
    cat > "$TEST_TMPDIR/context/orphan-context.md" <<'EOF'
# Orphan Context

No incoming links.
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ backlinks=0 修行候補"* ]]
    [[ "$output" == *"WARN: backlinks=0 context/orphan-context.md"* ]]
    [[ "$output" == *"修行タスク候補"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
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
    [[ "$output" == *"report-bundle: 直近50件FAIL率=50% (1/2) last=2099-01-01T00:01:00+0900"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "skill fail rate marks recovered skill after 5 consecutive successes" {
    {
        echo "executions:"
        echo '- ts: "2099-01-01T00:00:00+0900"'
        echo '  skill: "report-bundle"'
        echo '  executor: "saizo"'
        echo '  result: "FAIL"'
        echo '  stumbling_points: "binary_checks empty"'
        for i in 1 2 3 4 5; do
            echo "- ts: \"2099-01-01T00:0${i}:00+0900\""
            echo '  skill: "report-bundle"'
            echo '  executor: "saizo"'
            echo '  result: "PASS"'
            echo '  stumbling_points: "fixed"'
        done
    } > "$TEST_TMPDIR/logs/skill_execution_log.yaml"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"report-bundle: 直近50件FAIL率=17% (1/6) — 回復済み(最終FAIL後5連続成功)"* ]]
    [[ "$output" != *"スキル別FAIL率: 直近50件FAIL率10%超の改善対象あり"* ]]
}

@test "skill fail rate time-based recovery for low-frequency skill (streak>=2 + 24h+)" {
    _fail_ts=$(date -d '-30 hours' '+%Y-%m-%dT%H:%M:%S+0900')
    _pass_ts1=$(date -d '-29 hours' '+%Y-%m-%dT%H:%M:%S+0900')
    _pass_ts2=$(date -d '-28 hours' '+%Y-%m-%dT%H:%M:%S+0900')
    {
        echo "executions:"
        echo "- ts: \"${_fail_ts}\""
        echo '  skill: "note-draft"'
        echo '  executor: "shogun"'
        echo '  result: "FAIL"'
        echo '  stumbling_points: "python exit 1"'
        for _t in "$_pass_ts1" "$_pass_ts2"; do
            echo "- ts: \"${_t}\""
            echo '  skill: "note-draft"'
            echo '  executor: "shogun"'
            echo '  result: "PASS"'
            echo '  stumbling_points: "fixed"'
        done
    } > "$TEST_TMPDIR/logs/skill_execution_log.yaml"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"note-draft: 直近50件FAIL率=33% (1/3) — 回復済み(最終FAIL後2連続成功+"* ]]
    [[ "$output" == *"再発なし)"* ]]
    [[ "$output" != *"スキル別FAIL率: 直近50件FAIL率10%超の改善対象あり"* ]]
}

@test "skill fail rate time-based recovery requires min streak (streak=1 stays WARN)" {
    _fail_ts=$(date -d '-30 hours' '+%Y-%m-%dT%H:%M:%S+0900')
    _pass_ts1=$(date -d '-29 hours' '+%Y-%m-%dT%H:%M:%S+0900')
    {
        echo "executions:"
        echo "- ts: \"${_fail_ts}\""
        echo '  skill: "note-draft"'
        echo '  executor: "shogun"'
        echo '  result: "FAIL"'
        echo '  stumbling_points: "python exit 1"'
        echo "- ts: \"${_pass_ts1}\""
        echo '  skill: "note-draft"'
        echo '  executor: "shogun"'
        echo '  result: "PASS"'
        echo '  stumbling_points: "fixed"'
    } > "$TEST_TMPDIR/logs/skill_execution_log.yaml"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"スキル別FAIL率: 直近50件FAIL率10%超の改善対象あり"* ]]
}

@test "skill fail rate excludes cmd_test and invalid dashboard-update invocations" {
    cat > "$TEST_TMPDIR/logs/skill_execution_log.yaml" <<'EOF'
executions:
- ts: "2099-01-01T00:00:00+0900"
  skill: "dashboard-update"
  executor: "simokitafresh"
  result: "PASS"
  stumbling_points: "dashboard_update.sh exit=0 cmd=cmd_9000 dry_run=false"
  gate: "dashboard_update"
  source: "scripts/dashboard_update.sh cmd_9000"
  skill_path: "/mnt/c/tools/multi-agent-shogun/skills/dashboard-update/SKILL.md"
- ts: "2099-01-01T00:01:00+0900"
  skill: "dashboard-update"
  executor: "simokitafresh"
  result: "FAIL"
  stumbling_points: "dashboard_update.sh exit=1 cmd=cmd_9001 dry_run=false"
  gate: "dashboard_update"
  source: "scripts/dashboard_update.sh cmd_9001"
  skill_path: "/mnt/c/tools/multi-agent-shogun/skills/dashboard-update/SKILL.md"
- ts: "2099-01-01T00:02:00+0900"
  skill: "dashboard-update"
  executor: "simokitafresh"
  result: "FAIL"
  stumbling_points: "dashboard_update.sh exit=1 cmd=cmd_test_dummy dry_run=false"
  gate: "dashboard_update"
  source: "scripts/dashboard_update.sh cmd_test_dummy"
  skill_path: "/mnt/c/tools/multi-agent-shogun/skills/dashboard-update/SKILL.md"
- ts: "2099-01-01T00:03:00+0900"
  skill: "dashboard-update"
  executor: "simokitafresh"
  result: "FAIL"
  stumbling_points: "dashboard_update.sh exit=1 cmd=--dry-run dry_run=false"
  gate: "dashboard_update"
  source: "scripts/dashboard_update.sh --dry-run"
  skill_path: "/mnt/c/tools/multi-agent-shogun/skills/dashboard-update/SKILL.md"
- ts: "2099-01-01T00:04:00+0900"
  skill: "dashboard-update"
  executor: "simokitafresh"
  result: "FAIL"
  stumbling_points: "dashboard_update.sh exit=1 cmd=<empty> dry_run=false"
  gate: "dashboard_update"
  source: "scripts/dashboard_update.sh "
  skill_path: "/mnt/c/tools/multi-agent-shogun/skills/dashboard-update/SKILL.md"
- ts: "2099-01-01T00:05:00+0900"
  skill: "dashboard-update"
  executor: "simokitafresh"
  result: "FAIL"
  stumbling_points: "dashboard_update.sh exit=1 cmd=cmd_karo_hotfix_model_detect_hook dry_run=false"
  gate: "dashboard_update"
  source: "cmd_karo_hotfix_model_detect_hook"
  skill_path: "/mnt/c/tools/multi-agent-shogun/skills/dashboard-update/SKILL.md"
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ スキル別FAIL率"* ]]
    [[ "$output" == *"dashboard-update: 直近50件FAIL率=50% (1/2) last=2099-01-01T00:01:00+0900"* ]]
    [[ "$output" != *"83% (5/6)"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "skill fail rate excludes unused inferred failures" {
    cat > "$TEST_TMPDIR/logs/skill_execution_log.yaml" <<'EOF'
executions:
- ts: "2099-01-01T00:00:00+0900"
  skill: "verdict-check"
  executor: "saizo"
  result: "FAIL"
  used: "false"
  stumbling_points: "gate_report_format before report was filled"
  gate: "gate_report_format"
  source: "cmd_9000"
  skill_path: "/mnt/c/tools/multi-agent-shogun/skills/verdict-check/SKILL.md"
- ts: "2099-01-01T00:01:00+0900"
  skill: "verdict-check"
  executor: "saizo"
  result: "PASS"
  used: "true"
  stumbling_points: "gate_report_format PASS"
  gate: "gate_report_format"
  source: "cmd_9000"
  skill_path: "/mnt/c/tools/multi-agent-shogun/skills/verdict-check/SKILL.md"
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ スキル別FAIL率"* ]]
    [[ "$output" == *"verdict-check: 直近50件FAIL率=0% (0/1) last=2099-01-01T00:01:00+0900"* ]]
    [[ "$output" != *"スキル別FAIL率: 直近50件FAIL率10%超の改善対象あり"* ]]
}

@test "code_fix_required alert clears when recent 50 skill executions have zero FAIL" {
    cat > "$TEST_TMPDIR/logs/skill_execution_log.yaml" <<'EOF'
executions:
EOF
    for i in $(seq -w 1 50); do
        cat >> "$TEST_TMPDIR/logs/skill_execution_log.yaml" <<EOF
- ts: "2099-01-01T00:${i}:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "PASS"
  stumbling_points: "gate_report_format PASS"
  gate: "gate_report_format"
EOF
    done
    cat > "$TEST_TMPDIR/logs/skill_auto_improve_state.json" <<'EOF'
{
  "patterns": {
    "report_write_old": {
      "skill": "report-write",
      "gate": "gate_report_format",
      "reason": "verdict missing",
      "last_fail": "2099-01-01T00:00:00+0900",
      "classification": "code_fix_required",
      "classification_reason": "SKILL.md unchanged 3 consecutive runs"
    }
  }
}
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ スキル自動成長エスカレーション"* ]]
    [[ "$output" == *"OK: code_fix_required未解消パターンなし"* ]]
    [[ "$output" != *"ALERT: report-write"* ]]
    run python3 - "$TEST_TMPDIR/logs/skill_auto_improve_state.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1], encoding="utf-8"))
entry = state["patterns"]["report_write_old"]
assert entry.get("classification") != "code_fix_required"
assert entry.get("code_fix_cleared_by") == "gate_shogun_startup_recent50_zero_fail"
assert entry.get("code_fix_cleared_recent50_total") == 50
assert entry.get("code_fix_cleared_recent50_fail") == 0
print("OK")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "code_fix_required alert remains when recent 50 skill executions include FAIL" {
    cat > "$TEST_TMPDIR/logs/skill_execution_log.yaml" <<'EOF'
executions:
- ts: "2099-01-01T00:00:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "verdict missing"
  gate: "gate_report_format"
EOF
    for i in $(seq -w 1 49); do
        cat >> "$TEST_TMPDIR/logs/skill_execution_log.yaml" <<EOF
- ts: "2099-01-01T00:${i}:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "PASS"
  stumbling_points: "gate_report_format PASS"
  gate: "gate_report_format"
EOF
    done
    cat > "$TEST_TMPDIR/logs/skill_auto_improve_state.json" <<'EOF'
{
  "patterns": {
    "report_write_old": {
      "skill": "report-write",
      "gate": "gate_report_format",
      "reason": "verdict missing",
      "last_fail": "2099-01-01T00:00:00+0900",
      "classification": "code_fix_required",
      "classification_reason": "SKILL.md unchanged 3 consecutive runs"
    }
  }
}
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ スキル自動成長エスカレーション"* ]]
    [[ "$output" == *"ALERT: report-write"* ]]
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

@test "L6 learning speed alerts and requests bulletin for stale unrecovered FAIL" {
    export L6_LEARNING_NOW="2099-02-15T00:00:00+09:00"
    export L6_UNRECOVERED_FAIL_ALERT_DAYS=30
    cat > "$TEST_TMPDIR/logs/gate_fire_log.yaml" <<'EOF'
- ts: "2099-01-01T00:00:00+09:00", file: "queue/reports/old.yaml", gate: "gate_report_format", result: FAIL, reasons: "old unrecovered"
- ts: "2099-01-02T00:00:00+09:00", file: "queue/reports/old2.yaml", gate: "gate_report_format", result: FAIL, reasons: "old unrecovered again"
- ts: "2099-01-20T00:00:00+09:00", file: "queue/reports/recovered.yaml", gate: "gate_yaml_status", result: FAIL, reasons: "temporary"
- ts: "2099-01-21T00:00:00+09:00", file: "queue/reports/recovered.yaml", gate: "gate_yaml_status", result: PASS
EOF
    cat > "$TEST_TMPDIR/scripts/bulletin_write.sh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SHOGUN_STARTUP_ROOT/logs/bulletin_calls.log"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/bulletin_write.sh"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"未回復FAIL ALERT(閾値30日):"* ]]
    [[ "$output" == *"ALERT: gate_report_format 未回復45日 FAIL=2件"* ]]
    [[ "$output" == *"L6学習速度: gate_report_format 未回復FAIL 45日 (2件)"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
    [[ "$output" != *"__L6_UNRECOVERED_ALERT__"* ]]
    grep -q "gate_report_format の未回復FAILが45日継続(FAIL=2件)" "$TEST_TMPDIR/logs/bulletin_calls.log"
}

@test "retrospective learning shows unique FAIL gate type trend" {
    for i in $(seq 1 50); do
        gate="prev_gate_$(( (i - 1) % 2 ))"
        printf -- '- ts: "2099-01-01T00:%02d:00+09:00", file: "queue/reports/p%02d.yaml", gate: "%s", result: FAIL, reasons: "fixture"\n' "$i" "$i" "$gate"
    done > "$TEST_TMPDIR/logs/gate_fire_log.yaml"
    for i in $(seq 1 50); do
        gate="recent_gate_$(( (i - 1) % 3 ))"
        printf -- '- ts: "2099-01-02T00:%02d:00+09:00", file: "queue/reports/r%02d.yaml", gate: "%s", result: FAIL, reasons: "fixture"\n' "$i" "$i" "$gate"
    done >> "$TEST_TMPDIR/logs/gate_fire_log.yaml"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"FAIL種類数(ユニークgate名): 直近50=3 前50=2 増減=+1"* ]]
}

@test "Gate 13.8 high FP rate requests relaxation cmd bulletin with block pattern classification" {
    unset SHOGUN_STARTUP_LIGHTWEIGHT
    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries:
  - cmd_id: "cmd_fp_1"
    gate_result: "WARN"
    source: "cmd_save_warn"
    timestamp: "2099-01-01T00:00:00Z"
    notes: "ac_phase_mixing|check=check_ac_phase_mixing"
  - cmd_id: "cmd_fp_1"
    gate_result: "CLEAR"
    source: "cmd_complete_gate"
    timestamp: "2099-01-01T00:10:00Z"
  - cmd_id: "cmd_fp_2"
    gate_result: "WARN"
    source: "cmd_save_warn"
    timestamp: "2099-01-02T00:00:00Z"
    notes: "ac_phase_mixing|check=check_ac_phase_mixing"
  - cmd_id: "cmd_fp_2"
    gate_result: "CLEAR"
    source: "cmd_complete_gate"
    timestamp: "2099-01-02T00:10:00Z"
  - cmd_id: "cmd_fp_3"
    gate_result: "WARN"
    source: "cmd_save_warn"
    timestamp: "2099-01-03T00:00:00Z"
    notes: "ac_phase_mixing|check=check_ac_phase_mixing"
  - cmd_id: "cmd_fp_3"
    gate_result: "CLEAR"
    source: "cmd_complete_gate"
    timestamp: "2099-01-03T00:10:00Z"
  - cmd_id: "cmd_block_1"
    gate_result: "BLOCK"
    source: "cmd_save_block"
    timestamp: "2099-01-04T00:00:00Z"
    notes: "WARN累計昇格: ac_phase_mixing"
EOF
    cat > "$TEST_TMPDIR/scripts/bulletin_write.sh" <<'MOCK'
#!/usr/bin/env bash
printf 'notify=%s args=%s\n' "${BULLETIN_NOTIFY:-}" "$*" >> "$SHOGUN_STARTUP_ROOT/logs/bulletin_calls.log"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/bulletin_write.sh"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: \"ac_phase_mixing|check=check_ac_phase_mixing\" FP率=100% (3/3)"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
    [[ "$output" != *"__FP_RELAXATION_REQUEST__"* ]]
    grep -q "notify=shogun" "$TEST_TMPDIR/logs/bulletin_calls.log"
    grep -q "Gate 13.8 高FP率検出" "$TEST_TMPDIR/logs/bulletin_calls.log"
    grep -q "条件緩和cmd" "$TEST_TMPDIR/logs/bulletin_calls.log"
    grep -q "直近BLOCK修正パターン分類: WARN累計昇格:1件" "$TEST_TMPDIR/logs/bulletin_calls.log"
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

@test "shogun cmd_new without cmd_id history warns on startup" {
    cat > "$TEST_TMPDIR/queue/inbox/karo.yaml" <<'EOF'
messages:
- content: "配備せよ。"
  from: shogun
  id: msg_bypass
  read: true
  timestamp: "2099-01-01T00:00:00"
  type: cmd_new
- content: "cmd_100を書いた。配備せよ。"
  from: shogun
  id: msg_valid
  read: true
  timestamp: "2099-01-01T00:01:00"
  type: cmd_new
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"shogun cmd_idなしcmd_new送信 1件"* ]]
    [[ "$output" == *"msg_bypass"* ]]
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

@test "bulletin action_required without actioned_by → 総合判定: BLOCK" {
    cat > "$TEST_TMPDIR/queue/bulletin_board.yaml" <<'EOF'
entries:
- id: 'blt_action_required'
  content: |-
    CMD起票要請: 未対応の昇格通知
  posted_by: 'karo'
  posted_at: '2026-05-15T11:00:00'
  requires_confirmation: false
  action_type: 'action_required'
  actioned_by: ''
  confirmed_by:
    - 'shogun'
  status: 'open'
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"掲示板action_required未対応"* ]]
    [[ "$output" == *"ALERT: 未対応action_required掲示板 1件"* ]]
    [[ "$output" == *"blt_action_required by karo"* ]]
    [[ "$output" == *"総合判定: BLOCK"* ]]
}

@test "bulletin unactioned action_required is not double-counted as unread bulletin" {
    cat > "$TEST_TMPDIR/queue/bulletin_board.yaml" <<'EOF'
entries:
- id: 'blt_action_required_unconfirmed'
  content: |-
    CMD起票要請: 未対応かつ未確認の昇格通知
  posted_by: 'karo'
  posted_at: '2026-05-15T11:00:00'
  requires_confirmation: true
  action_type: 'action_required'
  actioned_by: ''
  confirmed_by: []
  status: 'open'
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"掲示板未確認"* ]]
    [[ "$output" == *"未確認: 0件"* ]]
    [[ "$output" == *"掲示板action_required未対応"* ]]
    [[ "$output" == *"ALERT: 未対応action_required掲示板 1件"* ]]
    [[ "$output" == *"総合判定: BLOCK"* ]]
}

@test "bulletin action_required with actioned_by is not alerted" {
    cat > "$TEST_TMPDIR/queue/bulletin_board.yaml" <<'EOF'
entries:
- id: 'blt_action_done'
  content: |-
    CMD起票要請: 対応済み
  posted_by: 'karo'
  posted_at: '2026-05-15T11:00:00'
  requires_confirmation: false
  action_type: 'action_required'
  actioned_by: 'cmd_9999'
  confirmed_by:
    - 'shogun'
  status: 'open'
- id: 'blt_q6_self_detection'
  content: |-
    Q6回答: 創造主の洗脳チェック。action_required対応済みfixtureでも自己検出を維持する。
  posted_by: 'shogun'
  posted_at: '2099-01-01T00:00:00'
  requires_confirmation: false
  action_type: 'info'
  actioned_by: ''
  confirmed_by: []
  status: 'open'
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"掲示板action_required未対応"* ]]
    [[ "$output" == *"未対応: 0件"* ]]
    [[ "$output" == *"総合判定: OK"* ]]
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

@test "Q6 brainwashing answer missing → 総合判定: WARN" {
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2099-01-01T00:00:00+09:00","direction":"response","agent":"shogun","source":"terminal","target":"lord","summary":"Q1-Q5回答済み。"}
EOF

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: Q6(創造主の洗脳チェック)回答未検出"* ]]
    [[ "$output" == *"追体験自動化ターゲット: WARN"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "Q6 brainwashing answer without automation target → same alert key" {
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2099-01-01T00:00:00+09:00","direction":"response","agent":"shogun","source":"terminal","target":"lord","summary":"Q6回答: 今の判断で早期終了本能が作用していないか確認した。殿のための判断として一次データで検証する。"}
EOF

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: Q6回答は検出したが自動化ターゲット未記入"* ]]
    [[ "$output" == *"追体験自動化ターゲット: WARN"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "startup deferral escalation is not resent while identical unread message exists" {
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2099-01-01T00:00:00+09:00","direction":"response","agent":"shogun","source":"terminal","target":"lord","summary":"Q6回答: 今の判断で早期終了本能が作用していないか確認した。殿のための判断として一次データで検証する。"}
EOF
    cat > "$TEST_TMPDIR/logs/shogun_startup_alert_history.tsv" <<'EOF'
run1	追体験自動化ターゲット: WARN (自動化ターゲット未記入)
run2	追体験自動化ターゲット: WARN (自動化ターゲット未記入)
EOF
    cat > "$TEST_TMPDIR/queue/inbox/karo.yaml" <<'EOF'
messages:
- content: '将軍startup先送りBLOCK自動エスカレーション: 先送り判断: 追体験自動化ターゲット: WARN (自動化ターゲット未記入) が3セッション連続。将軍がcmd起票しないため家老karo_directで対処を検討せよ'
  from: 'shogun'
  id: 'msg_existing'
  read: false
  timestamp: '2099-01-01T00:00:00'
  type: 'escalation'
EOF

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCK: 追体験自動化ターゲット: WARN (自動化ターゲット未記入) が3セッション連続"* ]]
    [[ "$output" == *"SKIP: 同一未読escalationが家老inboxに存在"* ]]
    [ ! -f "$TEST_TMPDIR/logs/inbox_write_calls.log" ]
}

@test "Q6 brainwashing answer present → no Q6 WARN" {
    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: Q6(創造主の洗脳チェック)回答検出"* ]]
    [[ "$output" != *"追体験自動化ターゲット: WARN"* ]]
    [[ "$output" == *"総合判定: OK"* ]]
}

@test "Q6 answer in recent shogun bulletin post → no Q6 WARN (channel mismatch fix)" {
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2099-01-01T00:00:00+09:00","direction":"response","agent":"shogun","source":"terminal","target":"lord","summary":"Q1-Q5回答済み。"}
EOF
    cat > "$TEST_TMPDIR/queue/bulletin_board.yaml" <<EOF
entries:
- id: 'blt_test_q6_recent'
  content: |-
    Q6回答(将軍・起動時洗脳チェック): 早期終了本能が作用していないか確認した。殿のための判断として一次データで検証する。自動化ターゲット: scripts/gates/q6_target_fixture.sh に \`q6_target_probe\` をgrep検証する。
  posted_by: 'shogun'
  posted_at: '$(date '+%Y-%m-%dT%H:%M:%S')'
  requires_confirmation: false
  action_type: 'info'
  status: 'open'
EOF

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: Q6(創造主の洗脳チェック)回答検出 + 自動化ターゲット記入あり"* ]]
    [[ "$output" != *"追体験自動化ターゲット: WARN"* ]]
}

@test "brainwash 2x2 counts Q6 self detection from today's bulletin archive" {
    cat > "$TEST_TMPDIR/queue/bulletin_board.yaml" <<'EOF'
entries: []
EOF
    archive_file="$TEST_TMPDIR/queue/archive/bulletin_$(date +%Y%m%d).yaml"
    cat > "$archive_file" <<'EOF'
entries:
- id: 'blt_archived_q6_self_detection'
  content: |-
    Q6回答: 創造主の洗脳チェック。早期終了ではなく退避後の当日アーカイブから自己検出する。
  posted_by: 'shogun'
  posted_at: '2099-01-01T00:00:00'
  requires_confirmation: false
  action_type: 'info'
  actioned_by: ''
  confirmed_by: []
  status: 'open'
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"自己検出率: 100.0% (1/1, source=bulletin_board+today_archive Q6 grep)"* ]]
    [[ "$output" == *"4象限: 成長 — 殿介入なしで自己検出あり"* ]]
    [[ "$output" != *"洗脳連鎖2x2: 危険象限"* ]]
}

@test "brainwash 2x2 remains unchanged after Q6 bulletin is archived today" {
    cat > "$TEST_TMPDIR/queue/bulletin_board.yaml" <<'EOF'
entries:
- id: 'blt_q6_before_archive'
  content: |-
    Q6回答: 創造主の洗脳チェック。早期終了ではなく退避前後で同じ自己検出率を維持する。
  posted_by: 'shogun'
  posted_at: '2099-01-01T00:00:00'
  requires_confirmation: false
  action_type: 'info'
  actioned_by: ''
  confirmed_by: []
  status: 'open'
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"自己検出率: 100.0% (1/1, source=bulletin_board+today_archive Q6 grep)"* ]]
    [[ "$output" == *"4象限: 成長 — 殿介入なしで自己検出あり"* ]]

    archive_file="$TEST_TMPDIR/queue/archive/bulletin_$(date +%Y%m%d).yaml"
    cp "$TEST_TMPDIR/queue/bulletin_board.yaml" "$archive_file"
    cat > "$TEST_TMPDIR/queue/bulletin_board.yaml" <<'EOF'
entries: []
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"自己検出率: 100.0% (1/1, source=bulletin_board+today_archive Q6 grep)"* ]]
    [[ "$output" == *"4象限: 成長 — 殿介入なしで自己検出あり"* ]]
    [[ "$output" != *"洗脳連鎖2x2: 危険象限"* ]]
}

@test "Q6 bulletin answer older than 24h → 追体験 WARN remains" {
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2099-01-01T00:00:00+09:00","direction":"response","agent":"shogun","source":"terminal","target":"lord","summary":"Q1-Q5回答済み。"}
EOF
    cat > "$TEST_TMPDIR/queue/bulletin_board.yaml" <<'EOF'
entries:
- id: 'blt_test_q6_old'
  content: |-
    Q6回答(将軍・起動時洗脳チェック): 早期終了本能が作用していないか確認した。自動化ターゲット: scripts/gates/q6_target_fixture.sh に `q6_target_probe` をgrep検証する。
  posted_by: 'shogun'
  posted_at: '2020-01-01T00:00:00'
  requires_confirmation: false
  action_type: 'info'
  status: 'open'
EOF

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: Q6(創造主の洗脳チェック)回答未検出"* ]]
    [[ "$output" == *"追体験自動化ターゲット: WARN"* ]]
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

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT"* ]]
    [[ "$output" == *"教訓健全度"* ]]
    [[ "$output" == *"総合判定: ALERT"* ]]
}

@test "Gate 13 useful_rate ALERT recommends when/how quality improvement" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh" <<'MOCK'
#!/usr/bin/env bash
echo "INFO: useful率(直近30cmd): 55/214 = 25.7%"
echo "METRIC: lesson_effectiveness_threshold status=ALERT rate=64.0% useful_rate=25.7% window_cmds=30 referenced=301 injected=470 useful=55 total_feedback=214 scope=all"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh"

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"総合判定: ALERT"* ]]
    [[ "$output" == *"低useful教訓の改善/淘汰を実行せよ"* ]]
    [[ "$output" != *"教訓健全度: ALERT → /lesson-sort実行せよ"* ]]
}

@test "Gate 13 useful_rate WARN emits concrete action" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh" <<'MOCK'
#!/usr/bin/env bash
echo "INFO: useful率(直近10cmd): 7/21 = 33.3%"
echo "METRIC: lesson_effectiveness_threshold status=WARN rate=100.0% useful_rate=33.3% window_cmds=10 referenced=14 injected=14 useful=7 total_feedback=21 scope=all"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh"

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"総合判定: WARN"* ]]
    [[ "$output" == *"教訓健全度useful_rate改善cmd接続済: WARN"* ]]
    [[ "$output" != *"⚠ 教訓健全度: WARN"* ]]
    [[ "$output" == *"action: useful_rate WARNは仕様上の真陽性。低useful教訓の改善/淘汰または注入スコアリング修正cmdを起票せよ。"* ]]
}

@test "Gate 13 useful_rate WARN does not continue old lesson health streak" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh" <<'MOCK'
#!/usr/bin/env bash
echo "INFO: useful率(直近10cmd): 7/21 = 33.3%"
echo "METRIC: lesson_effectiveness_threshold status=WARN rate=100.0% useful_rate=33.3% window_cmds=10 referenced=14 injected=14 useful=7 total_feedback=21 scope=all"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh"
    cat > "$TEST_TMPDIR/logs/shogun_startup_alert_history.tsv" <<'EOF'
run1	教訓健全度: WARN
run2	教訓健全度: WARN
EOF

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"教訓健全度useful_rate改善cmd接続済: WARN"* ]]
    [[ "$output" != *"BLOCK: 教訓健全度: WARN が3セッション連続"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "Gate 13 useful_rate connected WARN does not escalate as deferred streak" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh" <<'MOCK'
#!/usr/bin/env bash
echo "INFO: useful率(直近10cmd): 7/21 = 33.3%"
echo "METRIC: lesson_effectiveness_threshold status=WARN rate=100.0% useful_rate=33.3% window_cmds=10 referenced=14 injected=14 useful=7 total_feedback=21 scope=all"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh"
    cat > "$TEST_TMPDIR/logs/shogun_startup_alert_history.tsv" <<'EOF'
run1	教訓健全度useful_rate改善cmd接続済: WARN
run2	教訓健全度useful_rate改善cmd接続済: WARN
EOF

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"教訓健全度useful_rate改善cmd接続済: WARN"* ]]
    [[ "$output" != *"BLOCK: 教訓健全度useful_rate改善cmd接続済: WARN が3セッション連続"* ]]
    [[ "$output" != *"startup連続出現BLOCK: 教訓健全度useful_rate改善cmd接続済: WARN"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "Gate 13 unsorted ALERT recommends lesson-sort" {
    cat > "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh" <<'MOCK'
#!/usr/bin/env bash
echo "ALERT: infraの未振り分け教訓12件 → /lesson-sort推奨"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh"

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"総合判定: ALERT"* ]]
    [[ "$output" == *"教訓健全度: ALERT → /lesson-sort実行せよ"* ]]
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
echo "     command: python3 scripts/update_verified_at.py docs/research/systems-knowledge-base/systems/ace.md 2026-04-19"
echo "  action: 上記 STALE ファイルの verified_at を更新し、bash scripts/gates/gate_knowledge_freshness.sh で再確認せよ"
exit 1
MOCK
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_knowledge_freshness.sh"

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"知識辞書鮮度"* ]]
    [[ "$output" == *"STALE更新候補 TOP3"* ]]
    [[ "$output" == *"docs/research/systems-knowledge-base/systems/ace.md (31 days old"* ]]
    [[ "$output" == *"python3 scripts/update_verified_at.py docs/research/systems-knowledge-base/systems/ace.md 2026-04-19"* ]]
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
    cat > "$TEST_TMPDIR/context/cmd-chronicle.md" <<'EOF'
# CMD年代記

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| cmd_188 | inbox未読カウンタ復元 — nudge欠落時も未読件数を復元する | infra | 03-01 | unread inbox count handling |
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ startup WARN/ALERT連続出現"* ]]
    [[ "$output" == *"BLOCK: inbox未読: 1件 が3セッション連続"* ]]
    [[ "$output" == *"類似cmd候補:"* ]]
    [[ "$output" == *"cmd_id=cmd_188"* ]]
    [[ "$output" == *"類似度="* ]]
    [[ "$output" == *"title=inbox未読カウンタ復元"* ]]
    [[ "$output" == *"総合判定: BLOCK"* ]]
}

@test "Q6 missing for 3 consecutive sessions requests action_required bulletin" {
    export STARTUP_WARN_STREAK_THRESHOLD=3
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"ts":"2099-01-01T00:00:00+09:00","direction":"response","agent":"shogun","source":"terminal","target":"lord","summary":"startup fixture without q6 answer"}
EOF
    cat > "$TEST_TMPDIR/queue/bulletin_board.yaml" <<'EOF'
entries: []
EOF
    cat > "$TEST_TMPDIR/logs/shogun_startup_alert_history.tsv" <<'EOF'
2098-12-31T23:00:00+0900	追体験自動化ターゲット: WARN (Q6回答未検出)
2098-12-31T23:30:00+0900	追体験自動化ターゲット: WARN (Q6回答未検出)
EOF
    cat > "$TEST_TMPDIR/scripts/bulletin_write.sh" <<'MOCK'
#!/usr/bin/env bash
printf 'notify=%s args=%s\n' "${BULLETIN_NOTIFY:-}" "$*" >> "$SHOGUN_STARTUP_ROOT/logs/bulletin_calls.log"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/bulletin_write.sh"

    SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=0 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCK: 追体験自動化ターゲット: WARN (Q6回答未検出) が3セッション連続"* ]]
    [[ "$output" == *"ACTION: Q6回答未検出の3連続をaction_required掲示板へ自動接続"* ]]
    [[ "$output" == *"総合判定: BLOCK"* ]]
    grep -q "notify=shogun" "$TEST_TMPDIR/logs/bulletin_calls.log"
    grep -q "startup gate Q6回答未検出が3セッション連続" "$TEST_TMPDIR/logs/bulletin_calls.log"
    grep -q "action_required" "$TEST_TMPDIR/logs/bulletin_calls.log"
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

@test "semantic NO_MATCH metrics displays rate and top3 purposes" {
    cat > "$TEST_TMPDIR/logs/deploy_task.log" <<'EOF'
2026-05-21 00:00:01 inject_semantic_concepts: concepts injected purpose=hit one target_path=scripts/a.sh
2026-05-21 00:00:02 inject_semantic_concepts: NO_MATCH purpose=missing alpha target_path=scripts/a.sh
2026-05-21 00:00:03 inject_semantic_concepts: NO_MATCH purpose=missing beta target_path=scripts/b.sh
2026-05-21 00:00:04 inject_semantic_concepts: NO_MATCH purpose=missing alpha target_path=scripts/c.sh
EOF
    cat > "$TEST_TMPDIR/queue/insights.yaml" <<'EOF'
insights:
- id: INS-stress-1
  ts: "2099-01-01T00:00:00+09:00"
  insight: "[[設計書を実装しよう]] semantic_stress_test candidate_aliases: NO_MATCH source=lord query=設計書を実装しよう"
  priority: low
  source: semantic_stress_test
  status: pending
- id: INS-stress-2
  ts: "2099-01-01T00:00:01+09:00"
  insight: "[[設計書を実装しよう]] semantic_stress_test test_set_candidate: high_frequency_NO_MATCH count=1 source=lord query=設計書を実装しよう quality_gate=blind_hit_rate_non_regression fixed_50_role=regression_detection_only"
  priority: medium
  source: semantic_stress_test
  status: resolved
- id: INS-other
  ts: "2099-01-01T00:00:02+09:00"
  insight: "semantic_index_update新概念候補"
  priority: low
  source: semantic_index_update
  status: pending
EOF

    SHOGUN_STARTUP_NO_MATCH_SCAN_LINES=20 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ セマンティックNO_MATCH計測"* ]]
    [[ "$output" == *"NO_MATCH率: 83.3% (5/6, scan_lines=20)"* ]]
    [[ "$output" == *"ヒット率: 16.7% (1/6)"* ]]
    [[ "$output" == *"計測source: deploy_task=4 semantic_stress_test=2"* ]]
    [[ "$output" == *"TOP3 miss purpose:"* ]]
    [[ "$output" == *"missing alpha (2件)"* ]]
    [[ "$output" == *"設計書を実装しよう (2件)"* ]]
    [[ "$output" == *"missing beta (1件)"* ]]
}

@test "semantic NO_MATCH metrics displays lord query count without query content" {
    cat > "$TEST_TMPDIR/logs/semantic_no_match_metrics.log" <<'EOF'
2026-05-21T00:00:01+09:00	source=prompt_state_inject.sh	agent_id=shogun	count=1
2026-05-21T00:00:02+09:00	source=prompt_state_inject.sh	agent_id=shogun	count=1
EOF
    cat > "$TEST_TMPDIR/logs/deploy_task.log" <<'EOF'
2026-05-21 00:00:01 inject_semantic_concepts: 1 concepts injected
EOF

    SHOGUN_STARTUP_NO_MATCH_SCAN_LINES=20 run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"殿クエリNO_MATCHカウント: 2件 (scan_lines=20)"* ]]
    [[ "$output" != *"未知クエリ"* ]]
}

# === Gate 13.6: lessons_useful記入率テスト (cmd_3561 AC2) ===
@test "Gate 13.6 lessons_useful記入率: filled vs empty reports are displayed" {
    # Gate 13.6の_LS_FILE条件を満たす
    mkdir -p "$TEST_TMPDIR/projects/infra" "$TEST_TMPDIR/queue/reports"
    cat > "$TEST_TMPDIR/projects/infra/lessons_shogun.yaml" <<'EOF'
- id: L001
  title: テスト教訓
  when: full
  how: テスト方法
  status: active
EOF

    # lessons_useful記入済みレポート (useful: trueあり)
    cat > "$TEST_TMPDIR/queue/reports/hayate_report_cmd_test1.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_test1
lessons_useful:
  - id: L001
    useful: true
    reason: 有用だった
EOF
    # lessons_useful空リストレポート
    cat > "$TEST_TMPDIR/queue/reports/kagemaru_report_cmd_test2.yaml" <<'EOF'
worker_id: kagemaru
parent_cmd: cmd_test2
lessons_useful: []
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    # 記入率表示: 1/(1+1) = 50%
    [[ "$output" == *"lessons_useful記入率:"* ]]
    [[ "$output" == *"1/2"* ]]
    # 空リストWARN
    [[ "$output" == *"WARN: lessons_useful空リスト 1件"* ]]
}

@test "Gate 13.6 lessons_useful記入率: all filled, no empty WARN" {
    mkdir -p "$TEST_TMPDIR/projects/infra" "$TEST_TMPDIR/queue/reports"
    cat > "$TEST_TMPDIR/projects/infra/lessons_shogun.yaml" <<'EOF'
- id: L001
  title: テスト教訓
  status: active
EOF

    cat > "$TEST_TMPDIR/queue/reports/hayate_report_cmd_test1.yaml" <<'EOF'
worker_id: hayate
lessons_useful:
  - id: L001
    useful: true
    reason: 有用
EOF
    cat > "$TEST_TMPDIR/queue/reports/kagemaru_report_cmd_test2.yaml" <<'EOF'
worker_id: kagemaru
lessons_useful:
  - id: L002
    useful: false
    reason: 無関係
EOF

    run run_gate_shogun_startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"lessons_useful記入率:"* ]]
    # 2件記入済み
    [[ "$output" == *"2/2"* ]]
    # 空WARNなし
    [[ "$output" != *"WARN: lessons_useful空リスト"* ]]
}
