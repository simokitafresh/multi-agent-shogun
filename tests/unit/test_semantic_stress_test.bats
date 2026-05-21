#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/semantic_stress.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/queue" "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/logs"

    export SEMANTIC_STRESS_LORD_LOG="$TEST_TMPDIR/queue/lord_conversation.jsonl"
    export SEMANTIC_STRESS_CMD_QUEUE="$TEST_TMPDIR/queue/shogun_to_karo.yaml"
    export SEMANTIC_SEARCH_CMD="$TEST_TMPDIR/scripts/semantic_search.sh"
    export SEMANTIC_INSIGHT_WRITE="$TEST_TMPDIR/scripts/insight_write.sh"

    cat > "$SEMANTIC_STRESS_LORD_LOG" <<'EOF'
{"content":"lord hit concept"}
{"content":"lord uncovered phrase"}
EOF
    cat > "$SEMANTIC_STRESS_CMD_QUEUE" <<'EOF'
cmds:
- id: cmd_hit
  purpose: cmd hit concept
EOF
    cat > "$TEST_TMPDIR/file_queries.txt" <<'EOF'
file hit concept
file uncovered phrase
EOF
    cat > "$SEMANTIC_SEARCH_CMD" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"hit"* ]]; then
  echo "MATCH: mock"
  exit 0
fi
echo "NO_MATCH: $*"
exit 1
EOF
    chmod +x "$SEMANTIC_SEARCH_CMD"
    cat > "$SEMANTIC_INSIGHT_WRITE" <<'EOF'
#!/usr/bin/env bash
file="${INSIGHTS_FILE:?INSIGHTS_FILE required}"
mkdir -p "$(dirname "$file")"
if [ ! -f "$file" ]; then
  printf 'insights:\n' > "$file"
fi
printf -- '- id: INS-MOCK-%s\n  insight: "%s"\n  priority: "%s"\n  source: "%s"\n  status: pending\n' \
  "$(wc -l < "$file")" "$1" "${2:-medium}" "${3:-manual}" >> "$file"
echo INS-MOCK
EOF
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "all sources: measures hit rate, logs summary, and writes NO_MATCH candidate aliases" {
    run bash "$PROJECT_ROOT/scripts/semantic_stress_test.sh" \
        --source all \
        --file "$TEST_TMPDIR/file_queries.txt" \
        --limit 2 \
        --baseline "$TEST_TMPDIR/logs/baseline.json" \
        --log "$TEST_TMPDIR/logs/stress.log" \
        --insights "$TEST_TMPDIR/queue/insights.yaml"

    [ "$status" -eq 0 ]
    [[ "$output" == *"SEMANTIC_STRESS total=5 hits=3 no_match=2 errors=0 hit_rate=60.0%"* ]]
    [[ "$output" == *"lord: hit_rate=50.0% hits=1/2 no_match=1 errors=0"* ]]
    [[ "$output" == *"cmds: hit_rate=100.0% hits=1/1 no_match=0 errors=0"* ]]
    [[ "$output" == *"file: hit_rate=50.0% hits=1/2 no_match=1 errors=0"* ]]
    [[ "$output" == *"candidate_aliases=2"* ]]
    [[ "$output" == *"baseline: created $TEST_TMPDIR/logs/baseline.json"* ]]

    grep -q '"hit_rate": 60.0' "$TEST_TMPDIR/logs/baseline.json"
    grep -q 'semantic_stress_test candidate_aliases' "$TEST_TMPDIR/queue/insights.yaml"
    grep -q '\[\[lord uncovered phrase\]\]' "$TEST_TMPDIR/queue/insights.yaml"
    grep -q '\[\[file uncovered phrase\]\]' "$TEST_TMPDIR/queue/insights.yaml"
    grep -q '"hit_rate": 60.0' "$TEST_TMPDIR/logs/stress.log"
}

@test "existing baseline: prints before after diff instead of recreating baseline" {
    cat > "$TEST_TMPDIR/logs/baseline.json" <<'EOF'
{
  "timestamp": "2026-05-20T00:00:00+00:00",
  "total": 5,
  "hits": 2,
  "no_match": 3,
  "errors": 0,
  "hit_rate": 40.0
}
EOF

    run bash "$PROJECT_ROOT/scripts/semantic_stress_test.sh" \
        --source all \
        --file "$TEST_TMPDIR/file_queries.txt" \
        --limit 2 \
        --baseline "$TEST_TMPDIR/logs/baseline.json" \
        --log "$TEST_TMPDIR/logs/stress.log" \
        --insights "$TEST_TMPDIR/queue/insights.yaml" \
        --no-insights

    [ "$status" -eq 0 ]
    [[ "$output" == *"before_after: hit_rate_delta=20.0 no_match_delta=-1 total_delta=0"* ]]
    [ ! -f "$TEST_TMPDIR/queue/insights.yaml" ]
}

@test "candidate aliases: operational noise is excluded and semantic candidates pass" {
    cat > "$SEMANTIC_STRESS_LORD_LOG" <<'EOF'
{"content":"【INFOバッチ】 2026-05-21 04:14:16|CI緑: run 26183925378"}
{"content":"【家老】復帰済み。全忍者idle。cmd待ち。"}
{"content":"意味検索改善"}
EOF
    cat > "$SEMANTIC_STRESS_CMD_QUEUE" <<'EOF'
cmds:
- id: cmd_noise
  purpose: 速度計測テスト用のダミーcmd
EOF
    cat > "$TEST_TMPDIR/file_queries.txt" <<'EOF'
title: セマンティクスマップ
modules
EOF

    run bash "$PROJECT_ROOT/scripts/semantic_stress_test.sh" \
        --source all \
        --file "$TEST_TMPDIR/file_queries.txt" \
        --limit 5 \
        --baseline "$TEST_TMPDIR/logs/noise-baseline.json" \
        --log "$TEST_TMPDIR/logs/noise-stress.log" \
        --insights "$TEST_TMPDIR/queue/insights.yaml"

    [ "$status" -eq 0 ]
    [[ "$output" == *"candidate_aliases=1"* ]]
    [[ "$output" == *"意味検索改善 (lord)"* ]]
    grep -q '\[\[意味検索改善\]\]' "$TEST_TMPDIR/queue/insights.yaml"
    ! grep -q 'INFOバッチ' "$TEST_TMPDIR/queue/insights.yaml"
    ! grep -q '復帰済み' "$TEST_TMPDIR/queue/insights.yaml"
    ! grep -q 'ダミーcmd' "$TEST_TMPDIR/queue/insights.yaml"
    ! grep -q 'title: セマンティクスマップ' "$TEST_TMPDIR/queue/insights.yaml"
    ! grep -q 'modules' "$TEST_TMPDIR/queue/insights.yaml"
}
