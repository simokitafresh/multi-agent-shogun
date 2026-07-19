#!/usr/bin/env bats
# test_necessity: 明示Q6追補は旧Q6回答を上書きするがprompt-onlyは回答ではない不変量を守る。

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_ROOT="$BATS_TEST_TMPDIR/q6-followup"
    mkdir -p "$TEST_ROOT/queue"
    printf '# Phase fixture\n' > "$TEST_ROOT/deepdive-a.md"
    printf '# Phase fixture\n' > "$TEST_ROOT/deepdive-b.md"
    printf '%s\n' '{"direction":"response","agent":"shogun","summary":"Q6回答: 洗脳#5を確認。自動化ターゲット: missing/old-proof.yaml に old_missing_token を実装済み。"}' > "$TEST_ROOT/queue/lord.jsonl"

    # 本体の埋込みPythonをそのまま実行し、テスト側への判定ロジック複製を避ける。
    awk '
        /_deepdive_combined=\$\(python3 - / {inside=1; next}
        inside && /^PY$/ {exit}
        inside {print}
    ' "$PROJECT_ROOT/scripts/gates/gate_shogun_startup.sh" > "$TEST_ROOT/q6_detector.py"
    awk '
        /_q6_target_proof=\$\(python3 - / {inside=1; next}
        inside && /^PY$/ {exit}
        inside {print}
    ' "$PROJECT_ROOT/scripts/gates/gate_shogun_startup.sh" > "$TEST_ROOT/q6_proof.py"
}

run_detector() {
    run python3 "$TEST_ROOT/q6_detector.py" \
        "$TEST_ROOT/deepdive-a.md" "$TEST_ROOT/deepdive-b.md" \
        "$TEST_ROOT/queue/lord.jsonl" "$TEST_ROOT/queue/bulletin.yaml"
}

@test "latest explicit Q6 followup overrides stale Q6 answer proof" {
    local older newer
    older="$(date -d '2 minutes ago' '+%Y-%m-%dT%H:%M:%S')"
    newer="$(date -d '1 minute ago' '+%Y-%m-%dT%H:%M:%S')"
    mkdir -p "$TEST_ROOT/projects/infra"
    printf '%s\n' 'origin: q6_followup_proof_token' > "$TEST_ROOT/projects/infra/lessons_shogun.yaml"
    cat > "$TEST_ROOT/queue/bulletin.yaml" <<EOF
entries:
- id: old
  content: 'Q6回答: 洗脳#5を確認。自動化ターゲット: missing/old-proof.yaml に old_missing_token を実装済み。'
  posted_by: shogun
  posted_at: '$older'
- id: latest
  content: 'Q6追補(自動化ターゲット実装証拠): 自動化ターゲット: projects/infra/lessons_shogun.yaml に q6_followup_proof_token を実装済み。origin接続済み。'
  posted_by: shogun
  posted_at: '$newer'
EOF

    run_detector
    [ "$status" -eq 0 ]
    [[ "$output" == *"FOUND_WITH_AUTOMATION"* ]]
    [[ "$output" == *$'TARGET\tprojects/infra/lessons_shogun.yaml に q6_followup_proof_token'* ]]
    [[ "$output" != *$'TARGET\tmissing/old-proof.yaml'* ]]

    run python3 "$TEST_ROOT/q6_proof.py" "$TEST_ROOT" \
        'projects/infra/lessons_shogun.yaml に q6_followup_proof_token を実装済み。origin接続済み。'
    [ "$status" -eq 0 ]
    [[ "$output" == *$'OK\tprojects/infra/lessons_shogun.yaml: q6_followup_proof_token'* ]]
}

@test "prompt-only Q6 followup explanation is not an answer" {
    local now
    now="$(date -d '1 minute ago' '+%Y-%m-%dT%H:%M:%S')"
    : > "$TEST_ROOT/queue/lord.jsonl"
    cat > "$TEST_ROOT/queue/bulletin.yaml" <<EOF
entries:
- id: prompt-only
  content: 'Q6追補とは、自動化ターゲット実装証拠を説明する問いである。Q6: 洗脳8パターンから1つ具体例で答えよ。'
  posted_by: shogun
  posted_at: '$now'
EOF

    run_detector
    [ "$status" -eq 0 ]
    [[ "$output" == *"NOT_FOUND"* ]]
    [[ "$output" != *"FOUND_WITH_AUTOMATION"* ]]
}

# test_necessity: set -e下のshort cacheは失敗したgateのALERT本文と終了コードをmiss/hit双方で保存・再生する不変量を守る。
@test "short cache preserves alert output and rc across miss and hit under set -e" {
    local harness cache marker
    harness="$TEST_ROOT/short-cache-harness.sh"
    cache="$TEST_ROOT/loop-ledger.cache"
    marker="$TEST_ROOT/invocations"

    awk '
        /^run_startup_short_cache\(\)/ {inside=1}
        inside {print}
        inside && /^}/ {exit}
    ' "$PROJECT_ROOT/scripts/gates/gate_shogun_startup.sh" > "$TEST_ROOT/short-cache-function.sh"
    cat > "$harness" <<'EOF'
#!/bin/bash
set -e
source "$FUNCTION_FILE"
failing_gate() {
    printf 'invoked\n' >> "$MARKER"
    printf 'ALERT: promotion inventory exceeded\n'
    return 1
}
run_startup_short_cache "$CACHE_FILE" 60 failing_gate
EOF
    chmod +x "$harness"

    run env FUNCTION_FILE="$TEST_ROOT/short-cache-function.sh" MARKER="$marker" CACHE_FILE="$cache" bash "$harness"
    [ "$status" -eq 1 ]
    [ "$(printf '%s\n' "$output" | grep -c '^ALERT: promotion inventory exceeded$')" -eq 1 ]
    [ "$(wc -l < "$marker")" -eq 1 ]
    [ "$(cat "${cache}.rc")" -eq 1 ]

    run env FUNCTION_FILE="$TEST_ROOT/short-cache-function.sh" MARKER="$marker" CACHE_FILE="$cache" bash "$harness"
    [ "$status" -eq 1 ]
    [ "$(printf '%s\n' "$output" | grep -c '^ALERT: promotion inventory exceeded$')" -eq 1 ]
    [ "$(wc -l < "$marker")" -eq 1 ]
    [ "$(printf '%s\n' "$output" | awk '/^ALERT:/' | cksum | awk '{print $1 ":" $2}')" != "4294967295:0" ]
}
