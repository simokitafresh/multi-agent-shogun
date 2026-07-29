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
    awk '
        /_deferred_dup_status=\$\(python3 - / {inside=1; next}
        inside && /^PY$/ {exit}
        inside {print}
    ' "$PROJECT_ROOT/scripts/gates/gate_shogun_startup.sh" > "$TEST_ROOT/escalation_dedupe.py"
}

run_escalation_dedupe() {
    run python3 "$TEST_ROOT/escalation_dedupe.py" "$TEST_ROOT/queue/karo.yaml" "$1"
}

# test_necessity: escalationはread状態に依存せず意味キーをbounded cooldown中だけ重複抑制し、新規キーと期限後の再通知を失わない不変量を守る。
@test "startup escalation dedupes same unresolved key despite companion warning changes" {
    cat > "$TEST_ROOT/queue/karo.yaml" <<'EOF'
messages:
- from: shogun
  type: escalation
  read: false
  content: '将軍startup先送りBLOCK自動エスカレーション: 先送り判断: 学習ループ台帳: 空転/在庫超過あり (3217019218:60) が1セッション連続; 先送り判断: scripts/未コミット変更: 4件 が1セッション連続。一次情報を再検証し、未解消なら家老karo_directで対処せよ'
EOF
    run_escalation_dedupe '将軍startup先送りBLOCK自動エスカレーション: 先送り判断: 学習ループ台帳: 空転/在庫超過あり (3217019218:60) が2セッション連続。一次情報を再検証し、未解消なら家老karo_directで対処せよ'
    [ "$status" -eq 0 ]
    [ "$output" = "duplicate_recent" ]
}

@test "startup escalation dedupes keys spread across unread messages" {
    cat > "$TEST_ROOT/queue/karo.yaml" <<'EOF'
messages:
- {from: shogun, type: escalation, read: false, content: '将軍startup先送りBLOCK自動エスカレーション: 先送り判断: key-A が1セッション連続。一次情報を再検証し、未解消なら家老karo_directで対処せよ'}
- {from: shogun, type: escalation, read: false, content: '将軍startup先送りBLOCK自動エスカレーション: 先送り判断: key-B が1セッション連続。一次情報を再検証し、未解消なら家老karo_directで対処せよ'}
EOF
    run_escalation_dedupe '将軍startup先送りBLOCK自動エスカレーション: 先送り判断: key-A が2セッション連続; 先送り判断: key-B が2セッション連続。一次情報を再検証し、未解消なら家老karo_directで対処せよ'
    [ "$status" -eq 0 ]
    [ "$output" = "duplicate_recent" ]
}

@test "startup escalation preserves message when any warning key is new" {
    cat > "$TEST_ROOT/queue/karo.yaml" <<'EOF'
messages:
- {from: shogun, type: escalation, read: false, content: '将軍startup先送りBLOCK自動エスカレーション: 先送り判断: key-A が1セッション連続。一次情報を再検証し、未解消なら家老karo_directで対処せよ'}
EOF
    run_escalation_dedupe '将軍startup先送りBLOCK自動エスカレーション: 先送り判断: key-A が2セッション連続; 先送り判断: key-NEW が1セッション連続。一次情報を再検証し、未解消なら家老karo_directで対処せよ'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "startup escalation dedupes matching message read within cooldown" {
    cat > "$TEST_ROOT/queue/karo.yaml" <<'EOF'
messages:
- {from: shogun, type: escalation, read: true, timestamp: '2026-07-29T11:10:11', content: '将軍startup先送りBLOCK自動エスカレーション: 先送り判断: key-A が1セッション連続。一次情報を再検証し、未解消なら家老karo_directで対処せよ'}
EOF
    export SHOGUN_STARTUP_ESCALATION_NOW_EPOCH
    SHOGUN_STARTUP_ESCALATION_NOW_EPOCH="$(date -d '2026-07-29T11:11:53' +%s)"
    run_escalation_dedupe '将軍startup先送りBLOCK自動エスカレーション: 先送り判断: key-A が2セッション連続。一次情報を再検証し、未解消なら家老karo_directで対処せよ'
    [ "$status" -eq 0 ]
    [ "$output" = "duplicate_recent" ]
}

@test "startup escalation allows unresolved key after cooldown" {
    cat > "$TEST_ROOT/queue/karo.yaml" <<'EOF'
messages:
- {from: shogun, type: escalation, read: true, timestamp: '2026-07-29T11:00:00', content: '将軍startup先送りBLOCK自動エスカレーション: 先送り判断: key-A が1セッション連続。一次情報を再検証し、未解消なら家老karo_directで対処せよ'}
EOF
    export SHOGUN_STARTUP_ESCALATION_NOW_EPOCH
    SHOGUN_STARTUP_ESCALATION_NOW_EPOCH="$(date -d '2026-07-29T11:11:53' +%s)"
    run_escalation_dedupe '将軍startup先送りBLOCK自動エスカレーション: 先送り判断: key-A が2セッション連続。一次情報を再検証し、未解消なら家老karo_directで対処せよ'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
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
