#!/usr/bin/env bats
# test_pending_decision_write.bats — pending_decision_write.sh unit tests
# cmd_1557: PD書込みスクリプトのテスト可能分岐を検証

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/pending_decision_write.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/pd_write.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" \
             "$TEST_TMPDIR/queue/alerts" \
             "$TEST_TMPDIR/config"

    # Copy the script under test
    cp "$SRC_SCRIPT" "$TEST_TMPDIR/scripts/pending_decision_write.sh"
    chmod +x "$TEST_TMPDIR/scripts/pending_decision_write.sh"

    # Patch SCRIPT_DIR: the script uses $(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
    # So we place the script at TEST_TMPDIR/scripts/ and it resolves to TEST_TMPDIR
    # DATA_FILE will be TEST_TMPDIR/queue/pending_decisions.yaml

    # Create minimal dashboard.md with 要対応 section
    cat > "$TEST_TMPDIR/dashboard.md" <<'EOF'
## 要対応
（なし）
## 次セクション
EOF

    # Create minimal projects.yaml
    cat > "$TEST_TMPDIR/config/projects.yaml" <<'EOF'
projects:
  - id: infra
    status: active
  - id: dm-signal
    status: active
  - id: old-project
    status: archived
EOF

    # Stub gate_pd_sync.sh (called after resolve)
    cat > "$TEST_TMPDIR/scripts/gates/gate_pd_sync.sh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_pd_sync.sh"

    export SCRIPT_UNDER_TEST="$TEST_TMPDIR/scripts/pending_decision_write.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# ── Test 1: Invalid subcommand shows usage and exits 1 ──
@test "invalid subcommand shows usage and exits 1" {
    run bash "$SCRIPT_UNDER_TEST" badcommand
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: pending_decision_write.sh"* ]]
}

# ── Test 2: No subcommand shows usage and exits 1 ──
@test "no subcommand shows usage and exits 1" {
    run bash "$SCRIPT_UNDER_TEST"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: pending_decision_write.sh"* ]]
}

# ── Test 3: create - missing required fields exits 1 ──
@test "create with missing fields exits 1" {
    run bash "$SCRIPT_UNDER_TEST" create "summary_only"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: pending_decision_write.sh create"* ]]
}

# ── Test 4: create - invalid type exits 1 ──
@test "create with invalid type exits 1" {
    run bash "$SCRIPT_UNDER_TEST" create "test summary" "cmd_100" "bad_type" "shogun"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid type"* ]]
}

# ── Test 5: create - valid create generates PD-001 and writes YAML ──
@test "create generates PD-001 and writes data file" {
    run bash "$SCRIPT_UNDER_TEST" create "Test decision" "cmd_100" "lord_decision" "shogun"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PD_ID=PD-001"* ]]

    # Verify data file was created
    [ -f "$TEST_TMPDIR/queue/pending_decisions.yaml" ]

    # Verify content
    run python3 -c "
import yaml
with open('$TEST_TMPDIR/queue/pending_decisions.yaml') as f:
    data = yaml.safe_load(f)
assert data['decisions'][0]['id'] == 'PD-001'
assert data['decisions'][0]['status'] == 'pending'
assert data['decisions'][0]['type'] == 'lord_decision'
assert data['decisions'][0]['summary'] == 'Test decision'
assert data['decisions'][0]['source_cmd'] == 'cmd_100'
assert data['decisions'][0]['created_by'] == 'shogun'
assert data['summary']['total'] == 1
assert data['summary']['pending'] == 1
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# ── Test 6: create - auto-increment generates PD-002 when PD-001 exists ──
@test "create auto-increments ID when existing PD exists" {
    # Create first PD
    bash "$SCRIPT_UNDER_TEST" create "First decision" "cmd_100" "lord_decision" "shogun"
    # Create second PD
    run bash "$SCRIPT_UNDER_TEST" create "Second decision" "cmd_101" "escalation" "karo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PD_ID=PD-002"* ]]

    # Verify both exist
    run python3 -c "
import yaml
with open('$TEST_TMPDIR/queue/pending_decisions.yaml') as f:
    data = yaml.safe_load(f)
assert len(data['decisions']) == 2
assert data['decisions'][0]['id'] == 'PD-001'
assert data['decisions'][1]['id'] == 'PD-002'
assert data['summary']['total'] == 2
assert data['summary']['pending'] == 2
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# ── Test 7: create - init_data_file creates file when absent ──
@test "create initializes data file when absent" {
    # Ensure no data file exists
    rm -f "$TEST_TMPDIR/queue/pending_decisions.yaml"

    run bash "$SCRIPT_UNDER_TEST" create "Init test" "cmd_200" "skill_candidate" "karo"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/queue/pending_decisions.yaml" ]
    [[ "$output" == *"PD_ID=PD-001"* ]]
}

# ── Test 8: create - all four valid types accepted ──
@test "create accepts all four valid types" {
    for t in lord_decision skill_candidate escalation action_required; do
        run bash "$SCRIPT_UNDER_TEST" create "Type $t" "cmd_300" "$t" "shogun"
        [ "$status" -eq 0 ]
    done

    # Verify 4 entries created
    run python3 -c "
import yaml
with open('$TEST_TMPDIR/queue/pending_decisions.yaml') as f:
    data = yaml.safe_load(f)
assert len(data['decisions']) == 4
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# ── Test 9: resolve - missing required fields exits 1 ──
@test "resolve with missing fields exits 1" {
    run bash "$SCRIPT_UNDER_TEST" resolve "PD-001"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: pending_decision_write.sh resolve"* ]]
}

# ── Test 10: resolve - nonexistent ID exits 1 ──
@test "resolve nonexistent PD ID exits 1" {
    # Create a PD first so data file exists
    bash "$SCRIPT_UNDER_TEST" create "Existing" "cmd_400" "lord_decision" "shogun"

    run bash "$SCRIPT_UNDER_TEST" resolve "PD-999" "resolved content"
    [ "$status" -eq 1 ]
    [[ "$output" == *"PD-999 not found"* ]]
}

# ── Test 11: resolve - already resolved PD exits 0 with WARN ──
@test "resolve already resolved PD exits 0 with WARN" {
    # Create and resolve
    bash "$SCRIPT_UNDER_TEST" create "To resolve" "cmd_500" "lord_decision" "shogun"
    bash "$SCRIPT_UNDER_TEST" resolve "PD-001" "first resolve" "cmd_501"

    # Try to resolve again
    run bash "$SCRIPT_UNDER_TEST" resolve "PD-001" "second resolve" "cmd_502"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already resolved"* ]]
}

# ── Test 12: resolve - normal resolve sets correct fields ──
@test "resolve sets status, resolved_at, resolved_content, resolved_by" {
    bash "$SCRIPT_UNDER_TEST" create "To resolve" "cmd_600" "lord_decision" "shogun"

    run bash "$SCRIPT_UNDER_TEST" resolve "PD-001" "Decision made" "cmd_601"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Resolved PD-001"* ]]

    # Verify fields
    run python3 -c "
import yaml
with open('$TEST_TMPDIR/queue/pending_decisions.yaml') as f:
    data = yaml.safe_load(f)
d = data['decisions'][0]
assert d['status'] == 'resolved'
assert d['resolved_content'] == 'Decision made'
assert d['resolved_by'] == 'cmd_601'
assert 'resolved_at' in d
assert data['summary']['resolved'] == 1
assert data['summary']['pending'] == 0
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# ── Test 13: resolve - --no-context-sync sets context_synced=True ──
@test "resolve with --no-context-sync sets context_synced true" {
    bash "$SCRIPT_UNDER_TEST" create "No sync test" "cmd_700" "lord_decision" "shogun"

    run bash "$SCRIPT_UNDER_TEST" resolve "PD-001" "Resolved no sync" "cmd_701" "--no-context-sync"
    [ "$status" -eq 0 ]

    run python3 -c "
import yaml
with open('$TEST_TMPDIR/queue/pending_decisions.yaml') as f:
    data = yaml.safe_load(f)
d = data['decisions'][0]
assert d['context_synced'] == True, f'Expected True, got {d[\"context_synced\"]}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# ── Test 14: resolve - default resolved_by is 'direct' ──
@test "resolve defaults resolved_by to direct" {
    bash "$SCRIPT_UNDER_TEST" create "Default by" "cmd_800" "lord_decision" "shogun"

    run bash "$SCRIPT_UNDER_TEST" resolve "PD-001" "Resolved default"
    [ "$status" -eq 0 ]

    run python3 -c "
import yaml
with open('$TEST_TMPDIR/queue/pending_decisions.yaml') as f:
    data = yaml.safe_load(f)
d = data['decisions'][0]
assert d['resolved_by'] == 'direct'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# ── Test 15: list - shows pending decisions by default ──
@test "list shows only pending decisions by default" {
    bash "$SCRIPT_UNDER_TEST" create "Pending one" "cmd_900" "lord_decision" "shogun"
    bash "$SCRIPT_UNDER_TEST" create "Pending two" "cmd_901" "escalation" "karo"
    bash "$SCRIPT_UNDER_TEST" resolve "PD-001" "Done" "cmd_902"

    run bash "$SCRIPT_UNDER_TEST" list
    [ "$status" -eq 0 ]
    # PD-001 is resolved, should NOT appear
    [[ "$output" != *"PD-001"* ]]
    # PD-002 is pending, should appear
    [[ "$output" == *"PD-002"* ]]
}

# ── Test 16: list --status all shows all decisions ──
@test "list --status all shows all decisions" {
    bash "$SCRIPT_UNDER_TEST" create "Item one" "cmd_1000" "lord_decision" "shogun"
    bash "$SCRIPT_UNDER_TEST" create "Item two" "cmd_1001" "escalation" "karo"
    bash "$SCRIPT_UNDER_TEST" resolve "PD-001" "Done" "cmd_1002"

    run bash "$SCRIPT_UNDER_TEST" list --status all
    [ "$status" -eq 0 ]
    [[ "$output" == *"PD-001"* ]]
    [[ "$output" == *"PD-002"* ]]
}

# ── Test 17: list on empty data shows 'No decisions found' ──
@test "list on empty data shows no decisions" {
    run bash "$SCRIPT_UNDER_TEST" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No decisions found"* ]]
}

# ── Test 18: create - dashboard sync adds entry to 要対応 section ──
@test "create syncs new PD to dashboard 要対応 section" {
    bash "$SCRIPT_UNDER_TEST" create "Dashboard test" "cmd_1100" "lord_decision" "shogun"

    run cat "$TEST_TMPDIR/dashboard.md"
    [[ "$output" == *"PD-001"* ]]
    [[ "$output" == *"Dashboard test"* ]]
    # (なし) should be removed
    [[ "$output" != *"（なし）"* ]]
}

# ── Test 19: resolve - summary counts are correctly updated ──
@test "resolve updates summary counts correctly" {
    bash "$SCRIPT_UNDER_TEST" create "One" "cmd_1200" "lord_decision" "shogun"
    bash "$SCRIPT_UNDER_TEST" create "Two" "cmd_1201" "escalation" "karo"
    bash "$SCRIPT_UNDER_TEST" resolve "PD-001" "Done" "cmd_1202"

    run python3 -c "
import yaml
with open('$TEST_TMPDIR/queue/pending_decisions.yaml') as f:
    data = yaml.safe_load(f)
assert data['summary']['total'] == 2
assert data['summary']['resolved'] == 1
assert data['summary']['pending'] == 1
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}
