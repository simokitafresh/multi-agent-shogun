#!/usr/bin/env bats
# test_pending_decision_write.bats — pending_decision_write.sh unit tests
# Optimized: shared tmpdir(per-test mktemp/cp排除) + source方式 + grep検証
# cmd_training_L4_R12_kagemaru

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/pending_decision_write.sh"
    [ -f "$SRC_SCRIPT" ] || return 1

    # 共有tmpdir (全19テストで1回のみ作成)
    export SHARED_TMPDIR
    SHARED_TMPDIR="$(mktemp -d)"
    mkdir -p "$SHARED_TMPDIR/scripts/gates" \
             "$SHARED_TMPDIR/queue/alerts" \
             "$SHARED_TMPDIR/config"

    # スクリプトコピー (1回のみ)
    cp "$SRC_SCRIPT" "$SHARED_TMPDIR/scripts/pending_decision_write.sh"
    chmod +x "$SHARED_TMPDIR/scripts/pending_decision_write.sh"

    # 静的ファイル (1回のみ)
    cat > "$SHARED_TMPDIR/config/projects.yaml" <<'EOF'
projects:
  - id: infra
    status: active
  - id: dm-signal
    status: active
  - id: old-project
    status: archived
EOF
    cat > "$SHARED_TMPDIR/scripts/gates/gate_pd_sync.sh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "$SHARED_TMPDIR/scripts/gates/gate_pd_sync.sh"

    # 関数をsource (1回のみ) — main guardによりdispatchはスキップ
    # BASH_SOURCE[0]=$SHARED_TMPDIR/scripts/... なので SCRIPT_DIR=$SHARED_TMPDIR になる
    # shellcheck source=/dev/null
    source "$SHARED_TMPDIR/scripts/pending_decision_write.sh"
    # batsはrunコマンドで関数を外部コマンドとして検索するため、ラッパー経由で呼び出す
    # 直接関数呼び出し(runなし)はbatsのサブシェル継承で機能する
}

teardown_file() {
    rm -rf "$SHARED_TMPDIR"
}

setup() {
    # テストごとに独立したディレクトリを作成（--jobs並列実行の分離保証）
    export TEST_TMPDIR="$BATS_TEST_TMPDIR"
    mkdir -p "$TEST_TMPDIR/scripts/gates" \
             "$TEST_TMPDIR/queue/alerts" \
             "$TEST_TMPDIR/config"

    # スクリプトをコピー（BASH_SOURCE[0]がTEST_TMPDIRを向くよう）
    cp "$SHARED_TMPDIR/scripts/pending_decision_write.sh" "$TEST_TMPDIR/scripts/"
    cp "$SHARED_TMPDIR/scripts/gates/gate_pd_sync.sh" "$TEST_TMPDIR/scripts/gates/"
    cp "$SHARED_TMPDIR/config/projects.yaml" "$TEST_TMPDIR/config/"
    export SCRIPT_UNDER_TEST="$TEST_TMPDIR/scripts/pending_decision_write.sh"

    # 可変ファイルを初期化
    cat > "$TEST_TMPDIR/dashboard.md" <<'EOF'
## 要対応
（なし）
## 次セクション
EOF
}

teardown() {
    true  # BATS_TEST_TMPDIRはbatsが自動クリーンアップ
}

# ─── _run_pd: SCRIPT_UNDER_TESTのラッパー (DATA_FILEパスをTEST_TMPDIRで共有) ───
_run_pd() { bash "$SCRIPT_UNDER_TEST" "$@"; }

# ── Test 1: Invalid subcommand shows usage and exits 1 ──
@test "invalid subcommand shows usage and exits 1" {
    run _run_pd badcommand
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: pending_decision_write.sh"* ]]
}

# ── Test 2: No subcommand shows usage and exits 1 ──
@test "no subcommand shows usage and exits 1" {
    run _run_pd
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: pending_decision_write.sh"* ]]
}

# ── Test 3: create - missing required fields exits 1 ──
@test "create with missing fields exits 1" {
    run _run_pd create "summary_only"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: pending_decision_write.sh create"* ]]
}

# ── Test 4: create - invalid type exits 1 ──
@test "create with invalid type exits 1" {
    run _run_pd create "test summary" "cmd_100" "bad_type" "shogun"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid type"* ]]
}

# ── Test 5: create - valid create generates PD-001 and writes YAML ──
@test "create generates PD-001 and writes data file" {
    run _run_pd create "Test decision" "cmd_100" "lord_decision" "shogun"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PD_ID=PD-001"* ]]

    # Verify data file was created
    [ -f "$TEST_TMPDIR/queue/pending_decisions.yaml" ]

    # Verify content (grep — yaml.dump形式: 2spインデント)
    local df="$TEST_TMPDIR/queue/pending_decisions.yaml"
    grep -q "id: PD-001"             "$df"
    grep -q "status: pending"         "$df"
    grep -q "type: lord_decision"     "$df"
    grep -q "summary: Test decision"  "$df"
    grep -q "source_cmd: cmd_100"     "$df"
    grep -q "created_by: shogun"      "$df"
    grep -q "  total: 1$"             "$df"
    grep -q "  pending: 1$"           "$df"
}

# ── Test 5b: create - optional origin is written to YAML ──
@test "create records origin field with causal links" {
    run _run_pd create "Origin decision" "cmd_2820" "lord_decision" "shogun" "[[cmd_2820]] [[LS-A123]] 根拠リンク"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PD_ID=PD-001"* ]]

    local df="$TEST_TMPDIR/queue/pending_decisions.yaml"
    grep -q "origin: '\\[\\[cmd_2820\\]\\] \\[\\[LS-A123\\]\\] 根拠リンク'" "$df"
    grep -q "\\[\\[cmd_2820\\]\\]" "$df"
    grep -q "\\[\\[LS-A123\\]\\]" "$df"
}

# ── Test 6: create - auto-increment generates PD-002 when PD-001 exists ──
@test "create auto-increments ID when existing PD exists" {
    # Create first PD
    _run_pd create "First decision" "cmd_100" "lord_decision" "shogun" >/dev/null 2>&1
    # Create second PD
    run _run_pd create "Second decision" "cmd_101" "escalation" "karo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PD_ID=PD-002"* ]]

    # Verify both exist
    local df="$TEST_TMPDIR/queue/pending_decisions.yaml"
    grep -q "id: PD-001" "$df"
    grep -q "id: PD-002" "$df"
    grep -q "  total: 2$"   "$df"
    grep -q "  pending: 2$" "$df"
}

# ── Test 7: create - init_data_file creates file when absent ──
@test "create initializes data file when absent" {
    # Ensure no data file exists
    rm -f "$TEST_TMPDIR/queue/pending_decisions.yaml"

    run _run_pd create "Init test" "cmd_200" "skill_candidate" "karo"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/queue/pending_decisions.yaml" ]
    [[ "$output" == *"PD_ID=PD-001"* ]]
}

# ── Test 8: create - all four valid types accepted ──
@test "create accepts all four valid types" {
    for t in lord_decision skill_candidate escalation action_required; do
        run _run_pd create "Type $t" "cmd_300" "$t" "shogun"
        [ "$status" -eq 0 ]
    done

    # Verify 4 entries created
    [ "$(grep -c "^- id:" "$TEST_TMPDIR/queue/pending_decisions.yaml")" -eq 4 ]
}

# ── Test 9: resolve - missing required fields exits 1 ──
@test "resolve with missing fields exits 1" {
    run _run_pd resolve "PD-001"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: pending_decision_write.sh resolve"* ]]
}

# ── Test 10: resolve - nonexistent ID exits 1 ──
@test "resolve nonexistent PD ID exits 1" {
    # Create a PD first so data file exists
    _run_pd create "Existing" "cmd_400" "lord_decision" "shogun" >/dev/null 2>&1

    run _run_pd resolve "PD-999" "resolved content"
    [ "$status" -eq 1 ]
    [[ "$output" == *"PD-999 not found"* ]]
}

# ── Test 11: resolve - already resolved PD exits 0 with WARN ──
@test "resolve already resolved PD exits 0 with WARN" {
    # Create and resolve
    _run_pd create "To resolve" "cmd_500" "lord_decision" "shogun" >/dev/null 2>&1
    _run_pd resolve "PD-001" "first resolve" "cmd_501" >/dev/null 2>&1

    # Try to resolve again
    run _run_pd resolve "PD-001" "second resolve" "cmd_502"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already resolved"* ]]
}

# ── Test 12: resolve - normal resolve sets correct fields ──
@test "resolve sets status, resolved_at, resolved_content, resolved_by" {
    _run_pd create "To resolve" "cmd_600" "lord_decision" "shogun" >/dev/null 2>&1

    run _run_pd resolve "PD-001" "Decision made" "cmd_601"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Resolved PD-001"* ]]

    # Verify fields (grep)
    local df="$TEST_TMPDIR/queue/pending_decisions.yaml"
    grep -q "status: resolved"            "$df"
    grep -q "resolved_content: Decision made" "$df"
    grep -q "resolved_by: cmd_601"        "$df"
    grep -q "resolved_at:"                "$df"
    grep -q "  resolved: 1$"              "$df"
    grep -q "  pending: 0$"               "$df"
}

# ── Test 13: resolve - --no-context-sync sets context_synced=True ──
@test "resolve with --no-context-sync sets context_synced true" {
    _run_pd create "No sync test" "cmd_700" "lord_decision" "shogun" >/dev/null 2>&1

    run _run_pd resolve "PD-001" "Resolved no sync" "cmd_701" "--no-context-sync"
    [ "$status" -eq 0 ]

    grep -q "context_synced: true" "$TEST_TMPDIR/queue/pending_decisions.yaml"
}

# ── Test 14: resolve - default resolved_by is 'direct' ──
@test "resolve defaults resolved_by to direct" {
    _run_pd create "Default by" "cmd_800" "lord_decision" "shogun" >/dev/null 2>&1

    run _run_pd resolve "PD-001" "Resolved default"
    [ "$status" -eq 0 ]

    grep -q "resolved_by: direct" "$TEST_TMPDIR/queue/pending_decisions.yaml"
}

# ── Test 15: list - shows pending decisions by default ──
@test "list shows only pending decisions by default" {
    _run_pd create "Pending one" "cmd_900" "lord_decision" "shogun" >/dev/null 2>&1
    _run_pd create "Pending two" "cmd_901" "escalation" "karo" >/dev/null 2>&1
    _run_pd resolve "PD-001" "Done" "cmd_902" >/dev/null 2>&1

    run _run_pd list
    [ "$status" -eq 0 ]
    # PD-001 is resolved, should NOT appear
    [[ "$output" != *"PD-001"* ]]
    # PD-002 is pending, should appear
    [[ "$output" == *"PD-002"* ]]
}

# ── Test 16: list --status all shows all decisions ──
@test "list --status all shows all decisions" {
    _run_pd create "Item one" "cmd_1000" "lord_decision" "shogun" >/dev/null 2>&1
    _run_pd create "Item two" "cmd_1001" "escalation" "karo" >/dev/null 2>&1
    _run_pd resolve "PD-001" "Done" "cmd_1002" >/dev/null 2>&1

    run _run_pd list --status all
    [ "$status" -eq 0 ]
    [[ "$output" == *"PD-001"* ]]
    [[ "$output" == *"PD-002"* ]]
}

# ── Test 17: list - multiline summary is flattened correctly ──
@test "list flattens multiline summary" {
    cat > "$TEST_TMPDIR/queue/pending_decisions.yaml" <<'EOF'
summary:
  total: 1
  resolved: 0
  pending: 1
decisions:
- id: PD-001
  type: lord_decision
  summary: 'bench one wraps over
    multiple words'
  source_cmd: cmd_1003
  status: pending
  created_at: '2026-04-02T00:00:00+09:00'
  created_by: shogun
EOF

    run _run_pd list --status all
    [ "$status" -eq 0 ]
    [[ "$output" == *"PD-001  [pending]  (cmd_1003)  bench one wraps over multiple words"* ]]
}

# ── Test 18: list on empty data shows 'No decisions found' ──
@test "list on empty data shows no decisions" {
    run _run_pd list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No decisions found"* ]]
}

# ── Test 19: create - dashboard sync adds entry to 要対応 section ──
@test "create syncs new PD to dashboard 要対応 section" {
    _run_pd create "Dashboard test" "cmd_1100" "lord_decision" "shogun" >/dev/null 2>&1

    run cat "$TEST_TMPDIR/dashboard.md"
    [[ "$output" == *"PD-001"* ]]
    [[ "$output" == *"Dashboard test"* ]]
    # (なし) should be removed
    [[ "$output" != *"（なし）"* ]]
}

# ── Test 20: resolve - summary counts are correctly updated ──
@test "resolve updates summary counts correctly" {
    _run_pd create "One" "cmd_1200" "lord_decision" "shogun" >/dev/null 2>&1
    _run_pd create "Two" "cmd_1201" "escalation" "karo" >/dev/null 2>&1
    _run_pd resolve "PD-001" "Done" "cmd_1202" >/dev/null 2>&1

    local df="$TEST_TMPDIR/queue/pending_decisions.yaml"
    grep -q "  total: 2$"    "$df"
    grep -q "  resolved: 1$" "$df"
    grep -q "  pending: 1$"  "$df"
}

# ── Test 21: recalc - fixes stale summary to match actual decisions ──
@test "recalc fixes stale summary to match actual decisions" {
    # Set up a file with stale summary (resolved=1 but actually 2 resolved)
    cat > "$TEST_TMPDIR/queue/pending_decisions.yaml" <<'EOF'
summary:
  total: 2
  resolved: 1
  pending: 1
decisions:
- id: PD-001
  type: lord_decision
  summary: First decision
  source_cmd: cmd_1300
  status: resolved
  created_at: '2026-04-01T00:00:00+09:00'
  created_by: shogun
  resolved_at: '2026-04-02T00:00:00+09:00'
  resolved_content: done
  resolved_by: direct
- id: PD-002
  type: escalation
  summary: Second decision
  source_cmd: cmd_1301
  status: resolved
  created_at: '2026-04-03T00:00:00+09:00'
  created_by: karo
  resolved_at: '2026-04-04T00:00:00+09:00'
  resolved_content: also done
  resolved_by: direct
EOF

    run _run_pd recalc
    [ "$status" -eq 0 ]
    [[ "$output" == *"total=2"* ]]
    [[ "$output" == *"resolved=2"* ]]
    [[ "$output" == *"pending=0"* ]]

    local df="$TEST_TMPDIR/queue/pending_decisions.yaml"
    grep -q "  total: 2$"    "$df"
    grep -q "  resolved: 2$" "$df"
    grep -q "  pending: 0$"  "$df"
}
