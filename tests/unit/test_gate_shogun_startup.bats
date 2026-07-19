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
