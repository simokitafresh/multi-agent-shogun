#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/semantic_stress.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/queue" "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/logs"

    export SEMANTIC_STRESS_LORD_LOG="$TEST_TMPDIR/queue/lord_conversation.jsonl"
    export SEMANTIC_STRESS_CMD_QUEUE="$TEST_TMPDIR/queue/shogun_to_karo.yaml"
    export SEMANTIC_SEARCH_CMD="$TEST_TMPDIR/scripts/semantic_search.sh"
    export SEMANTIC_INSIGHT_WRITE="$TEST_TMPDIR/scripts/insight_write.sh"
    export SEMANTIC_QUALITY_TEST_CMD="$TEST_TMPDIR/scripts/semantic_quality_test.sh"

    cat > "$SEMANTIC_STRESS_LORD_LOG" <<'EOF'
{"content":"lord hit concept","direction":"inbound"}
{"content":"lord uncovered phrase","direction":"inbound"}
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
    chmod +x "$SEMANTIC_INSIGHT_WRITE"
    cat > "$SEMANTIC_QUALITY_TEST_CMD" <<'EOF'
#!/usr/bin/env bash
fixture=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --fixture) fixture="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$fixture" ] || exit 2
python3 - "$fixture" <<'PY'
import json
import sys
json.load(open(sys.argv[1], encoding="utf-8"))
PY
echo "semantic_quality_score: 100.0% (1/1)"
EOF
    chmod +x "$SEMANTIC_QUALITY_TEST_CMD"
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
{"content":"【INFOバッチ】 2026-05-21 04:14:16|CI緑: run 26183925378","direction":"inbound"}
{"content":"【家老】復帰済み。全忍者idle。cmd待ち。","direction":"inbound"}
{"content":"意味検索改善","direction":"inbound"}
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

@test "candidate aliases: short mundane NO_MATCH is not written but long conceptual NO_MATCH is written" {
    cat > "$SEMANTIC_STRESS_LORD_LOG" <<'EOF'
{"content":"そうだな","direction":"inbound"}
{"content":"セマンティック辞書の未カバー概念を追加して検索品質を改善する","direction":"inbound"}
EOF
    cat > "$SEMANTIC_STRESS_CMD_QUEUE" <<'EOF'
cmds: []
EOF

    run bash "$PROJECT_ROOT/scripts/semantic_stress_test.sh" \
        --source lord \
        --limit 5 \
        --baseline "$TEST_TMPDIR/logs/short-baseline.json" \
        --log "$TEST_TMPDIR/logs/short-stress.log" \
        --insights "$TEST_TMPDIR/queue/insights.yaml"

    [ "$status" -eq 0 ]
    [[ "$output" == *"candidate_aliases=1"* ]]
    [[ "$output" == *"セマンティック辞書の未カバー概念を追加して検索品質を改善する (lord)"* ]]
    grep -q '\[\[セマンティック辞書の未カバー概念を追加して検索品質を改善する\]\]' "$TEST_TMPDIR/queue/insights.yaml"
    ! grep -q 'そうだな' "$TEST_TMPDIR/queue/insights.yaml"
}

@test "lord queries: task notification junk is filtered before search and candidate aliases" {
    cat > "$SEMANTIC_STRESS_LORD_LOG" <<'EOF'
{"content":"<task-notification> <task-id>bo84ps0qy</task-id> <tool-use-id>toolu_01Bbj2rdY7GrXVYLN9WLHcgL</tool-use-id> <output-file>/tmp/out</output-file>","direction":"inbound"}
{"content":"x","direction":"inbound"}
{"content":"ab","direction":"inbound"}
{"content":"意味検索改善","direction":"inbound"}
EOF
    cat > "$SEMANTIC_STRESS_CMD_QUEUE" <<'EOF'
cmds: []
EOF

    run bash "$PROJECT_ROOT/scripts/semantic_stress_test.sh" \
        --source lord \
        --limit 10 \
        --baseline "$TEST_TMPDIR/logs/junk-baseline.json" \
        --log "$TEST_TMPDIR/logs/junk-stress.log" \
        --insights "$TEST_TMPDIR/queue/insights.yaml"

    [ "$status" -eq 0 ]
    [[ "$output" == *"SEMANTIC_STRESS total=1 hits=0 no_match=1 errors=0 hit_rate=0.0%"* ]]
    [[ "$output" == *"candidate_aliases=1"* ]]
    grep -q '\[\[意味検索改善\]\]' "$TEST_TMPDIR/queue/insights.yaml"
    ! grep -q 'task-notification' "$TEST_TMPDIR/queue/insights.yaml"
    ! grep -q 'toolu_' "$TEST_TMPDIR/queue/insights.yaml"
    ! grep -q 'bo84ps0qy' "$TEST_TMPDIR/queue/insights.yaml"
    ! grep -q '"query": "ab"' "$TEST_TMPDIR/logs/junk-baseline.json"
}

@test "auto test-set add: high-frequency NO_MATCH passes blind non-regression and fixed fixture remains regression-only" {
    cat > "$TEST_TMPDIR/quality_fixture.json" <<'EOF'
{
  "version": 1,
  "entries": [
    {
      "query": "existing regression",
      "expected_concept": null
    }
  ]
}
EOF
    cat > "$SEMANTIC_STRESS_LORD_LOG" <<'EOF'
{"content":"セマンティック辞書の新しい穴をテストセットに入れる","direction":"inbound"}
EOF
    cat > "$SEMANTIC_STRESS_CMD_QUEUE" <<'EOF'
cmds: []
EOF

    run bash "$PROJECT_ROOT/scripts/semantic_stress_test.sh" \
        --source lord \
        --limit 5 \
        --baseline "$TEST_TMPDIR/logs/auto-baseline.json" \
        --log "$TEST_TMPDIR/logs/auto-stress.log" \
        --insights "$TEST_TMPDIR/queue/insights.yaml" \
        --quality-fixture "$TEST_TMPDIR/quality_fixture.json" \
        --auto-test-set-add

    [ "$status" -eq 0 ]
    [[ "$output" == *"evaluation_mode=blind_random_sampling"* ]]
    [[ "$output" == *"improvement_judgement=blind_hit_rate_non_regression_only"* ]]
    [[ "$output" == *"fixed_50_test_role=regression_detection_only"* ]]
    [[ "$output" == *"high_frequency_NO_MATCH=1"* ]]
    grep -q 'test_set_candidate: high_frequency_NO_MATCH' "$TEST_TMPDIR/queue/insights.yaml"
    grep -q 'blind_hit_rate_non_regression' "$TEST_TMPDIR/quality_fixture.json"
    grep -q 'regression_detection_only' "$TEST_TMPDIR/quality_fixture.json"
    grep -q 'セマンティック辞書の新しい穴をテストセットに入れる' "$TEST_TMPDIR/quality_fixture.json"
}

@test "dirty hit candidates: generic hits are surfaced without converting them to NO_MATCH aliases" {
    cat > "$SEMANTIC_SEARCH_CMD" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"記憶"* ]]; then
  echo "## local_memory_db — ローカル記憶DB"
  echo "matched: 記憶"
  exit 0
fi
echo "NO_MATCH: $*"
exit 1
EOF
    chmod +x "$SEMANTIC_SEARCH_CMD"
    cat > "$SEMANTIC_STRESS_LORD_LOG" <<'EOF'
{"content":"記憶","direction":"inbound"}
EOF
    cat > "$SEMANTIC_STRESS_CMD_QUEUE" <<'EOF'
cmds: []
EOF

    run bash "$PROJECT_ROOT/scripts/semantic_stress_test.sh" \
        --source lord \
        --limit 5 \
        --baseline "$TEST_TMPDIR/logs/dirty-hit-baseline.json" \
        --log "$TEST_TMPDIR/logs/dirty-hit-stress.log" \
        --insights "$TEST_TMPDIR/queue/insights.yaml" \
        --no-insights

    [ "$status" -eq 0 ]
    [[ "$output" == *"SEMANTIC_STRESS total=1 hits=1 no_match=0 errors=0 hit_rate=100.0%"* ]]
    [[ "$output" == *"candidate_aliases=0"* ]]
    [[ "$output" == *"dirty_hit_candidates=1"* ]]
    [[ "$output" == *"DIRTY_HIT 記憶 (lord) -> local_memory_db: generic_short_query:記憶->local_memory_db"* ]]
    grep -q '"dirty_hit_candidates"' "$TEST_TMPDIR/logs/dirty-hit-stress.log"
}
