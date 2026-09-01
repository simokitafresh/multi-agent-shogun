#!/usr/bin/env bats
# test_necessity: 最新Q6時系列単調性（最新の実回答だけを判定し、弱い/空targetから旧回答へfallbackしない）を守る。

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export FUNCTION_ROOT="$BATS_FILE_TMPDIR/q6-functions"
    mkdir -p "$FUNCTION_ROOT"

    # 本体の埋込みPythonはファイル全体で不変なので、各@testではなく1回だけ抽出する。
    awk '
        /_deepdive_combined=\$\(python3 - / {inside=1; next}
        inside && /^PY$/ {exit}
        inside {print}
    ' "$PROJECT_ROOT/scripts/gates/gate_shogun_startup.sh" > "$FUNCTION_ROOT/q6_detector.py"
    awk '
        /_q6_target_proof=\$\(python3 - / {inside=1; next}
        inside && /^PY$/ {exit}
        inside {print}
    ' "$PROJECT_ROOT/scripts/gates/gate_shogun_startup.sh" > "$FUNCTION_ROOT/q6_proof.py"
    awk '
        /_deferred_dup_status=\$\(python3 - / {inside=1; next}
        inside && /^PY$/ {exit}
        inside {print}
    ' "$PROJECT_ROOT/scripts/gates/gate_shogun_startup.sh" > "$FUNCTION_ROOT/escalation_dedupe.py"
}

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_ROOT="$BATS_TEST_TMPDIR/q6-followup"
    mkdir -p "$TEST_ROOT/queue"
    printf '# Phase fixture\n' > "$TEST_ROOT/deepdive-a.md"
    printf '# Phase fixture\n' > "$TEST_ROOT/deepdive-b.md"
    printf '%s\n' '{"direction":"response","agent":"shogun","summary":"Q6回答: 洗脳#5を確認。自動化ターゲット: missing/old-proof.yaml に old_missing_token を実装済み。"}' > "$TEST_ROOT/queue/lord.jsonl"
}

run_escalation_dedupe() {
    run python3 "$FUNCTION_ROOT/escalation_dedupe.py" "$TEST_ROOT/queue/karo.yaml" "$1"
}

# test_necessity: K/D分類は将軍gateの実行・表示から外し、家老laneの受領証と
# J判定を同時に維持する不変量を守る。
@test "cmd_4250 suppresses Karo-owned K/D startup output" {
    grep -q 'local SHOGUN_KD_SUPPRESSED=1' "$PROJECT_ROOT/scripts/gates/gate_shogun_startup.sh"
    run env SHOGUN_STARTUP_LIGHTWEIGHT=1 SHOGUN_STARTUP_SKIP_HEAVY_LIGHTWEIGHT=1 \
        SHOGUN_STARTUP_ROOT="$PROJECT_ROOT" \
        bash "$PROJECT_ROOT/scripts/gates/gate_shogun_startup.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *'■ daemon_watchdog heartbeat鮮度'* ]]
    [[ "$output" != *'■ テスト時間台帳鮮度'* ]]
    [[ "$output" != *'■ 将軍watcher環境変数'* ]]
    [[ "$output" != *'■ 将軍教訓'* ]]
    [[ "$output" != *'■ 教訓Stats'* ]]
    [[ "$output" != *'■ DIGEST:'* ]]
    run bash "$PROJECT_ROOT/scripts/gates/gate_karo_startup_migrated_checks.sh" "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *'K-LANE RECEIPT: classified=39'*'result=PASS'* ]]
    [[ "$output" == *'D-LANE RECEIPT: classified=9'*'result=PASS'* ]]
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
    run python3 "$FUNCTION_ROOT/q6_detector.py" \
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

    run python3 "$FUNCTION_ROOT/q6_proof.py" "$TEST_ROOT" \
        'projects/infra/lessons_shogun.yaml に q6_followup_proof_token を実装済み。origin接続済み。'
    [ "$status" -eq 0 ]
    [[ "$output" == *$'OK\tprojects/infra/lessons_shogun.yaml: q6_followup_proof_token'* ]]
}

@test "latest weak Q6 target does not fall back to older valid target" {
    local older newer
    older="$(date -d '2 minutes ago' '+%Y-%m-%dT%H:%M:%S')"
    newer="$(date -d '1 minute ago' '+%Y-%m-%dT%H:%M:%S')"
    cat > "$TEST_ROOT/queue/bulletin.yaml" <<EOF
entries:
- id: old-valid
  content: 'Q6回答: 洗脳#5を確認。自動化ターゲット: scripts/old-proof.sh を実装済み。'
  posted_by: shogun
  posted_at: '$older'
- id: latest-weak
  content: 'Q6回答: 洗脳#5を確認。自動化ターゲット: gate修正を予定。'
  posted_by: shogun
  posted_at: '$newer'
EOF

    run_detector
    [ "$status" -eq 0 ]
    [[ "$output" == *"FOUND_MISSING_AUTOMATION"* ]]
    [[ "$output" != *$'TARGET\tscripts/old-proof.sh'* ]]
}

@test "latest empty Q6 target does not fall back to older valid target" {
    local older newer
    older="$(date -d '2 minutes ago' '+%Y-%m-%dT%H:%M:%S')"
    newer="$(date -d '1 minute ago' '+%Y-%m-%dT%H:%M:%S')"
    cat > "$TEST_ROOT/queue/bulletin.yaml" <<EOF
entries:
- id: old-valid
  content: 'Q6回答: 洗脳#5を確認。自動化ターゲット: scripts/old-proof.sh を実装済み。'
  posted_by: shogun
  posted_at: '$older'
- id: latest-empty
  content: 'Q6回答: 洗脳#5を確認。自動化ターゲット: なし'
  posted_by: shogun
  posted_at: '$newer'
EOF

    run_detector
    [ "$status" -eq 0 ]
    [[ "$output" == *"FOUND_MISSING_AUTOMATION"* ]]
    [[ "$output" != *$'TARGET\tscripts/old-proof.sh'* ]]
}

@test "latest valid Q6 target remains the implementation proof target" {
    local older newer
    older="$(date -d '2 minutes ago' '+%Y-%m-%dT%H:%M:%S')"
    newer="$(date -d '1 minute ago' '+%Y-%m-%dT%H:%M:%S')"
    cat > "$TEST_ROOT/queue/bulletin.yaml" <<EOF
entries:
- id: old-valid
  content: 'Q6回答: 洗脳#5を確認。自動化ターゲット: scripts/old-proof.sh を実装済み。'
  posted_by: shogun
  posted_at: '$older'
- id: latest-valid
  content: 'Q6回答: 洗脳#5を確認。自動化ターゲット: scripts/new-proof.sh に new_proof_token を実装済み。'
  posted_by: shogun
  posted_at: '$newer'
EOF

    run_detector
    [ "$status" -eq 0 ]
    [[ "$output" == *"FOUND_WITH_AUTOMATION"* ]]
    [[ "$output" == *$'TARGET\tscripts/new-proof.sh に new_proof_token'* ]]
    [[ "$output" != *$'TARGET\tscripts/old-proof.sh'* ]]
}

@test "current bulletin Q6 takes precedence over archive fallback" {
    local older newer archive
    older="$(date -d '2 minutes ago' '+%Y-%m-%dT%H:%M:%S')"
    newer="$(date -d '1 minute ago' '+%Y-%m-%dT%H:%M:%S')"
    archive="$TEST_ROOT/queue/archive/bulletin_$(date '+%Y%m%d').yaml"
    mkdir -p "$(dirname "$archive")"
    cat > "$archive" <<EOF
entries:
- id: archived-valid
  content: 'Q6回答: 洗脳#5を確認。自動化ターゲット: scripts/archive-proof.sh を実装済み。'
  posted_by: shogun
  posted_at: '$older'
EOF
    cat > "$TEST_ROOT/queue/bulletin.yaml" <<EOF
entries:
- id: current-weak
  content: 'Q6回答: 洗脳#5を確認。自動化ターゲット: hook追加を検討中。'
  posted_by: shogun
  posted_at: '$newer'
EOF

    run_detector
    [ "$status" -eq 0 ]
    [[ "$output" == *"FOUND_MISSING_AUTOMATION"* ]]
    [[ "$output" != *$'TARGET\tscripts/archive-proof.sh'* ]]
}

# test_necessity: 「Q6追記」等のQ6追補と同義の実回答ラベルが実装証拠付きで検出される不変量を守る
# (cmd_karo_hotfix_shogun_startup_defer_two_alerts_20260730実測: 2026-07-19修正の完全一致要求
#  「追補（自動化ターゲット実装証拠）」がこの語彙違いを再度取りこぼしFOUND_MISSING_AUTOMATIONに埋没した)。
@test "Q6 followup using a synonymous label (追記) is still recognized as an answer" {
    local older newer
    older="$(date -d '2 minutes ago' '+%Y-%m-%dT%H:%M:%S')"
    newer="$(date -d '1 minute ago' '+%Y-%m-%dT%H:%M:%S')"
    cat > "$TEST_ROOT/queue/bulletin.yaml" <<EOF
entries:
- id: old
  content: 'Q6回答: 洗脳#2を確認。検証スキップの具体例を述べた。'
  posted_by: shogun
  posted_at: '$older'
- id: latest
  content: 'Q6追記(将軍): 自動化ターゲット: scripts/hooks/session_start_inject.sh 実装済み(commit deadbeef01)。'
  posted_by: shogun
  posted_at: '$newer'
EOF

    run_detector
    [ "$status" -eq 0 ]
    [[ "$output" == *"FOUND_WITH_AUTOMATION"* ]]
    [[ "$output" == *$'TARGET\tscripts/hooks/session_start_inject.sh 実装済み(commit deadbeef01)。'* ]]
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

setup_promotion_block_harness() {
    awk '
        /^        if printf .%s.n. "\$_loop_ledger_output" \| grep -q "promotion/ {inside=1}
        inside {print}
        inside && /^        fi$/ {exit}
    ' "$PROJECT_ROOT/scripts/gates/gate_shogun_startup.sh" > "$TEST_ROOT/promotion-block.sh"
    cat > "$TEST_ROOT/promotion-harness.sh" <<'EOF'
#!/bin/bash
SCRIPT_DIR="$FAKE_ROOT"
_loop_ledger_output='ALERT: promotion: 在庫超過(24h以上前400→今回438)'
source "$TEST_ROOT/promotion-block.sh"
EOF
    chmod +x "$TEST_ROOT/promotion-harness.sh"
}

# test_necessity: lord-authorized pause markerはpromotion単独ALERTだけを汎用エスカレーションから
# 除外し、markerなしpromotionと他channel混在を従来どおり警告対象に保つ不変量を守る。
@test "loop ledger classifies only lord-paused promotion-only alert as frozen" {
    awk '
        /^loop_ledger_is_lord_paused_promotion_only\(\)/ {inside=1}
        inside {print}
        inside && /^}/ {exit}
    ' "$PROJECT_ROOT/scripts/gates/gate_shogun_startup.sh" > "$TEST_ROOT/loop-ledger-classifier.sh"
    source "$TEST_ROOT/loop-ledger-classifier.sh"
    local marker="$TEST_ROOT/reflux_promotion.paused"
    cat > "$marker" <<'EOF'
authority: "lord"
EOF

    run loop_ledger_is_lord_paused_promotion_only \
        'ALERT: promotion: 在庫超過(24h以上前400→今回440)' "$marker"
    [ "$status" -eq 0 ]

    run loop_ledger_is_lord_paused_promotion_only \
        'ALERT: promotion: 在庫超過(24h以上前400→今回440)' "$TEST_ROOT/missing-marker"
    [ "$status" -eq 1 ]

    run loop_ledger_is_lord_paused_promotion_only \
        $'ALERT: promotion: 在庫超過(24h以上前400→今回440)\nALERT: lesson: 空転' "$marker"
    [ "$status" -eq 1 ]
}

# test_necessity: promotion在庫超過が殿裁定authority=lordの意図的凍結マーカーによる時、
# 検出バグではなく一次証跡(reason/resume_condition)と解消手順を必ず表示する不変量を守る
# (cmd_karo_hotfix_shogun_startup_defer_two_alerts_20260730: マーカー未提示のまま繰り返しWARNのみ
#  だと「先送り判断」に見え続け、438件の在庫増が2026-07-28 13:21付殿裁定による意図的凍結だと
#  毎回grepし直さねば分からなかった実測に基づく)。
@test "promotion inventory alert surfaces lord-authorized pause marker as primary evidence" {
    setup_promotion_block_harness
    export FAKE_ROOT="$TEST_ROOT/fake-root"
    mkdir -p "$FAKE_ROOT/logs" "$FAKE_ROOT/queue/gates"
    cat > "$FAKE_ROOT/queue/gates/reflux_promotion.paused" <<'EOF'
paused_at: "2026-07-28T13:21:00+09:00"
reason: "殿裁定によりpromotion在庫消化を凍結。第二弾最優先。"
authority: "lord"
resume_condition: "殿の明示裁可"
EOF

    run env TEST_ROOT="$TEST_ROOT" FAKE_ROOT="$FAKE_ROOT" bash "$TEST_ROOT/promotion-harness.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"意図的凍結中(検出バグではない): authority=lord since=2026-07-28T13:21:00+09:00"* ]]
    [[ "$output" == *'reason=殿裁定によりpromotion在庫消化を凍結。第二弾最優先。 / resume_condition=殿の明示裁可'* ]]
    [[ "$output" == *"解消手順: 殿へ凍結継続要否を確認し"* ]]
}

# test_necessity: pause markerなし時は凍結文脈を表示しない不変量を守る
# (queue/gates/reflux_promotion.pausedが存在しない通常のpromotion在庫超過では、
#  意図的凍結の一次証跡を捏造・混入させず既存のreflux配備ログ表示のみに留める)。
@test "promotion inventory alert stays silent on pause context when no marker exists" {
    setup_promotion_block_harness
    export FAKE_ROOT="$TEST_ROOT/fake-root-no-marker"
    mkdir -p "$FAKE_ROOT/logs" "$FAKE_ROOT/queue/gates"
    : > "$FAKE_ROOT/logs/ninja_monitor.log"

    run env TEST_ROOT="$TEST_ROOT" FAKE_ROOT="$FAKE_ROOT" bash "$TEST_ROOT/promotion-harness.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"意図的凍結中"* ]]
    [[ "$output" == *"reflux配備ログなし"* ]]
}

@test "T102 legacy old-root warning fires only outside evidence exclusions" {
    warn_root="$TEST_ROOT/legacy-warn"
    clean_root="$TEST_ROOT/legacy-clean"
    mkdir -p "$warn_root/config" "$clean_root"/{logs,archive,docs,memory} \
        "$clean_root/config" "$clean_root/.bak" "$clean_root/scripts"
    printf 'path=/mnt/c/tools/multi-agent-shogun/scripts/live.sh\n' > "$warn_root/config/runtime.env"
    for excluded in \
        "$clean_root/logs/history.log" \
        "$clean_root/archive/old.yaml" \
        "$clean_root/docs/old.md" \
        "$clean_root/memory/old.md" \
        "$clean_root/.bak/settings.yaml.bak" \
        "$clean_root/scripts/migrate_to_ext4_cutover.sh"; do
        printf 'path=/mnt/c/tools/multi-agent-shogun\n' > "$excluded"
    done

    run bash -c 'SHOGUN_STARTUP_LIB_ONLY=1 source "$1/scripts/gates/gate_shogun_startup.sh"; check_legacy_ext4_path_residuals "$2"' _ "$PROJECT_ROOT" "$warn_root"
    [ "$status" -eq 1 ]
    [[ "$output" == *"WARN: legacy ext4 old-root references remain"* ]]
    [[ "$output" == *"config/runtime.env"* ]]

    run bash -c 'SHOGUN_STARTUP_LIB_ONLY=1 source "$1/scripts/gates/gate_shogun_startup.sh"; check_legacy_ext4_path_residuals "$2"' _ "$PROJECT_ROOT" "$clean_root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: legacy ext4 old-root references clean"* ]]
}

@test "Gate 10.1d undeployed delegated cmd warns only when no task parent_cmd and no gate_metrics row" {
    root="$TEST_ROOT/undeployed"
    tasks_dir="$root/queue/tasks"
    mkdir -p "$tasks_dir" "$root/logs"
    old_ts="$(date -d '-120 minutes' +%Y-%m-%dT%H:%M:%S)"
    new_ts="$(date -d '-5 minutes' +%Y-%m-%dT%H:%M:%S)"
    cat > "$root/queue/shogun_to_karo.yaml" <<YAML
commands:
  cmd_9001:
    title: "stale and undeployed"
    status: delegated
    delegated_at: "\"${old_ts}\""
  cmd_9002:
    title: "stale but task exists"
    status: delegated
    delegated_at: "\"${old_ts}\""
  cmd_9003:
    title: "stale but gate_metrics row exists"
    status: delegated
    delegated_at: "${old_ts}"
  cmd_9004:
    title: "fresh"
    status: delegated
    delegated_at: "${new_ts}"
  cmd_9005:
    title: "completed"
    status: completed
    delegated_at: "${old_ts}"
YAML
    printf 'task:\n  task_id: cmd_9002_normal\n  parent_cmd: cmd_9002\n  status: assigned\n' > "$tasks_dir/hanzo.yaml"
    printf '2026-09-01T10:00:00\tcmd_9003_normal\tCLEAR\tall\n' > "$root/logs/gate_metrics.log"

    run bash -c 'SHOGUN_STARTUP_LIB_ONLY=1 source "$1/scripts/gates/gate_shogun_startup.sh"; check_undeployed_delegated_cmds "$2" 30' _ "$PROJECT_ROOT" "$root"
    [ "$status" -eq 1 ]
    [[ "$output" == *"WARN: delegated∧配備痕跡なし 1件(30分超)"* ]]
    [[ "$output" == *"cmd_9001("* ]]
    [[ "$output" != *"cmd_9002"* ]]
    [[ "$output" != *"cmd_9003"* ]]
    [[ "$output" != *"cmd_9004"* ]]
    [[ "$output" != *"cmd_9005"* ]]

    printf 'task:\n  task_id: cmd_9001_normal\n  parent_cmd: "cmd_9001_normal"\n  status: assigned\n' > "$tasks_dir/saizo.yaml"
    run bash -c 'SHOGUN_STARTUP_LIB_ONLY=1 source "$1/scripts/gates/gate_shogun_startup.sh"; check_undeployed_delegated_cmds "$2" 30' _ "$PROJECT_ROOT" "$root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: delegated∧配備痕跡なし(30分超) 0件"* ]]
}
