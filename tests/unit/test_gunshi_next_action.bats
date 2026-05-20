#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gunshi_next_action.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/logs" "$TEST_TMPDIR/queue"

    cat > "$TEST_TMPDIR/semantic_stress_mock.sh" <<'EOF'
#!/usr/bin/env bash
log_file="${GUNSHI_NEXT_ACTION_STRESS_CALL_LOG:?call log required}"
printf 'semantic_stress_called %s\n' "$*" >> "$log_file"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --insights) insights="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$(dirname "$insights")"
if [ ! -f "$insights" ]; then
  printf 'insights:\n' > "$insights"
fi
printf -- '- id: INS-MOCK\n  insight: "NO_MATCH alias candidate"\n  priority: "low"\n  source: "semantic_stress_test"\n  status: pending\n' >> "$insights"
echo 'SEMANTIC_STRESS total=1 hits=0 no_match=1 errors=0 hit_rate=0.0%'
EOF
    chmod +x "$TEST_TMPDIR/semantic_stress_mock.sh"

    export SEMANTIC_STRESS_CMD="$TEST_TMPDIR/semantic_stress_mock.sh"
    export GUNSHI_NEXT_ACTION_STRESS_CALL_LOG="$TEST_TMPDIR/logs/stress_call.log"
    export GUNSHI_NEXT_ACTION_DEPLOY_LOG="$TEST_TMPDIR/logs/deploy_task.log"
    export GUNSHI_NEXT_ACTION_PROMPT_NO_MATCH_LOG="$TEST_TMPDIR/logs/semantic_no_match_metrics.log"
    export GUNSHI_NEXT_ACTION_INSIGHTS="$TEST_TMPDIR/queue/insights.yaml"
    export GUNSHI_NEXT_ACTION_NO_MATCH_SCAN_LINES=20
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "idle next action runs semantic stress when NO_MATCH exists and accumulates insights" {
    cat > "$GUNSHI_NEXT_ACTION_DEPLOY_LOG" <<'EOF'
2026-05-21 inject_semantic_concepts: NO_MATCH purpose=未登録概念 target_path=scripts/foo.sh
EOF

    run bash "$PROJECT_ROOT/scripts/gunshi_next_action.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"semantic_stress: NO_MATCH 1件 → insights蓄積実行"* ]]
    [[ "$output" == *"SEMANTIC_STRESS total=1 hits=0 no_match=1 errors=0 hit_rate=0.0%"* ]]
    [[ "$output" == *"semantic_stress: OK"* ]]
    grep -q 'semantic_stress_called' "$GUNSHI_NEXT_ACTION_STRESS_CALL_LOG"
    grep -q 'NO_MATCH alias candidate' "$GUNSHI_NEXT_ACTION_INSIGHTS"
}
