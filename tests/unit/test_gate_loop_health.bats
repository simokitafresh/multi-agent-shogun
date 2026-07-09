#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_loop_health.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gate_loop_health.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/logs" "$TEST_TMPDIR/queue"
    cp "$SRC_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_loop_health.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_loop_health.sh"

    cat > "$TEST_TMPDIR/scripts/insight_write.sh" <<'EOF'
#!/usr/bin/env bash
echo "INSIGHT_TEST"
exit 0
EOF
    chmod +x "$TEST_TMPDIR/scripts/insight_write.sh"

    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_loop_health.sh"
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "gate_loop_health warns when recent CLEAR duration is a strong outlier vs median" {
    cat > "$TEST_TMPDIR/logs/gate_fire_log.yaml" <<'EOF'
- ts: "2026-04-19T14:00:00" file: "queue/reports/sasuke_report_cmd_1.yaml" result: FAIL reasons: "binary_checks.ACx missing" fixes: ""
EOF

    cat > "$TEST_TMPDIR/logs/gate_metrics.log" <<'EOF'
2026-04-19T14:00:00	cmd_1	CLEAR	all_gates_passed	impl	gpt-5.4_high_fast	routine	none	title 1	duration_sec=120
2026-04-19T14:01:00	cmd_2	CLEAR	all_gates_passed	impl	gpt-5.4_high_fast	routine	none	title 2	duration_sec=150
2026-04-19T14:02:00	cmd_3	CLEAR	all_gates_passed	impl	gpt-5.4_high_fast	routine	none	title 3	duration_sec=180
2026-04-19T14:03:00	cmd_4	CLEAR	all_gates_passed	impl	gpt-5.4_high_fast	routine	none	title 4	duration_sec=210
2026-04-19T14:04:00	cmd_5	CLEAR	all_gates_passed	impl	gpt-5.4_high_fast	routine	none	title 5	duration_sec=3600
EOF

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"=== Task Duration Outlier Check ==="* ]]
    [[ "$output" == *"WARNING: task duration異常値 cmd_5 (duration=3600s, median=180.0s, ratio=20.00x, delta=+3420.0s)"* ]]
}

@test "gate_loop_health fail rate warning uses recent 20 entries not lifetime totals" {
    {
        for i in $(seq 1 30); do
            printf -- '- ts: "2026-04-19T13:%02d:00" file: "queue/reports/old_report_%02d.yaml" result: FAIL reasons: "old_pattern MISSING" fixes: ""\n' "$i" "$i"
        done
        for i in $(seq 1 20); do
            printf -- '- ts: "2026-04-19T14:%02d:00" file: "queue/reports/recent_report_%02d.yaml" result: PASS reasons: "" fixes: ""\n' "$i" "$i"
        done
    } > "$TEST_TMPDIR/logs/gate_fire_log.yaml"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING: FAIL率20%超"* ]]
    [[ "$output" == *"OK: 直近のFAILパターンなし"* ]]
}

@test "gate_loop_health INVESTIGATE recommendations use recent 20 reason counts" {
    {
        for i in $(seq 1 12); do
            printf -- '- ts: "2026-04-19T13:%02d:00" file: "queue/reports/old_report_%02d.yaml" result: FAIL reasons: "legacy_field MISSING" fixes: ""\n' "$i" "$i"
        done
        for i in $(seq 1 20); do
            printf -- '- ts: "2026-04-19T14:%02d:00" file: "queue/reports/recent_report_%02d.yaml" result: PASS reasons: "" fixes: ""\n' "$i" "$i"
        done
    } > "$TEST_TMPDIR/logs/gate_fire_log.yaml"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" != *'INVESTIGATE: "legacy_field MISSING"'* ]]
    [[ "$output" == *"現時点で成熟提案なし"* ]]
}

@test "gate_loop_health missing-field recommendations do not suggest valid default values" {
    {
        for i in $(seq 1 10); do
            printf -- '- ts: "2026-04-19T14:%02d:00" file: "queue/reports/recent_fail_%02d.yaml" result: FAIL reasons: "result.summary: MISSING or empty" fixes: ""\n' "$i" "$i"
        done
    } > "$TEST_TMPDIR/logs/gate_fire_log.yaml"

    run bash "$TEST_GATE"
    [ "$status" -eq 1 ]
    [[ "$output" == *'テンプレート導線/事前警告を強化。空欄を有効値で隠す補完は禁止'* ]]
    [[ "$output" == *'テンプレート導線強化: result.summary: MISSING or empty'* ]]
    [[ "$output" != *'デフォルト値追加'* ]]
}

@test "gate_loop_health bc result empty recommends non-autofix quality defenses" {
    {
        for i in $(seq 1 7); do
            printf -- '- ts: "2026-04-19T14:%02d:00" file: "queue/reports/recent_fail_%02d.yaml" result: FAIL reasons: "binary_checks.AC1[0].result: 空文字。\\\"yes\\\" または \\\"no\\\" を記入せよ" fixes: ""\n' "$i" "$i"
        done
        for i in $(seq 1 13); do
            printf -- '- ts: "2026-04-19T15:%02d:00" file: "queue/reports/recent_pass_%02d.yaml" result: PASS reasons: "" fixes: ""\n' "$i" "$i"
        done
    } > "$TEST_TMPDIR/logs/gate_fire_log.yaml"

    run bash "$TEST_GATE"
    [ "$status" -eq 1 ]
    [[ "$output" == *'QUALITY: "binary_checks.ACx[0].result: 空文字。'* ]]
    [[ "$output" == *'(7回) → 値の推定auto-fix禁止。deploy_taskテンプレート警告・report_field_set導線・L1修行サイクルでresult記入を強制せよ'* ]]
    [[ "$output" != *'gate_report_autofix.sh'* ]]
}

@test "gate_loop_health bc result empty at 10+ fires does not re-raise already-judged GP-107 insight" {
    {
        for i in $(seq 1 10); do
            printf -- '- ts: "2026-04-19T14:%02d:00" file: "queue/reports/recent_fail_%02d.yaml" result: FAIL reasons: "binary_checks.AC1[0].result: 空文字。\\\"yes\\\" または \\\"no\\\" を記入せよ" fixes: ""\n' "$i" "$i"
        done
    } > "$TEST_TMPDIR/logs/gate_fire_log.yaml"

    run bash "$TEST_GATE"
    # QUALITY推奨(Maturation recommendations)は表示され続ける
    [[ "$output" == *'QUALITY: "binary_checks.ACx[0].result: 空文字。'* ]]
    # cmd_1614でGP-107判定済み(auto-fix禁止・意図的BLOCK)のため、矛盾する「高頻度FAIL...GP-107で判定後に」insightは生成しない
    [[ "$output" != *'高頻度FAIL: binary_checks.ACx[0].result: 空文字'* ]]
    [[ "$output" != *'INSIGHT_TEST'* ]]
}

@test "gate_loop_health verdict empty at 14+ fires (escaped quotes) does not re-raise already-judged GP-107 insight" {
    {
        # 本番gate_fire_log.yamlの実フォーマットを再現: 埋込み引用符は \" とバックスラッシュ
        # エスケープされたまま記録される(正規表現キャプチャにunescape処理がないため)。
        for i in $(seq 1 14); do
            printf -- '- ts: "2026-07-09T09:%02d:00" file: "queue/reports/recent_fail_%02d.yaml" result: FAIL reasons: "verdict: \\"\\" is not valid (must be \\"PASS\\", \\"FAIL\\", or \\"PASS_NO_IMPROVEMENT\\")" fixes: ""\n' "$i" "$i"
        done
    } > "$TEST_TMPDIR/logs/gate_fire_log.yaml"

    run bash "$TEST_GATE"
    # QUALITY推奨(Maturation recommendations)は表示され続ける
    [[ "$output" == *'QUALITY: "verdict: "" is not valid'* ]]
    # cmd_reflux_insight_202607091222_tobisaruでGP-107判定済み(binary_checks空文字と100%co-occurrence)
    # のため、矛盾する「高頻度FAIL...GP-107で判定後に」insightは生成しない
    [[ "$output" != *'高頻度FAIL: verdict:'* ]]
    [[ "$output" != *'INSIGHT_TEST'* ]]
}

@test "gate_loop_health AC self-verification missing points to AC parser fix" {
    {
        for i in $(seq 1 10); do
            printf -- '- ts: "2026-04-19T14:%02d:00" file: "queue/reports/recent_fail_%02d.yaml" result: FAIL reasons: "binary_checks: AC self-verification missing (0/3 ACs). 全ACの二値チェックを記入せよ" fixes: ""\n' "$i" "$i"
        done
    } > "$TEST_TMPDIR/logs/gate_fire_log.yaml"

    run bash "$TEST_GATE"
    [ "$status" -eq 1 ]
    [[ "$output" == *'報告テンプレートAC展開漏れ: binary_checks: AC self-verification missing'* ]]
    [[ "$output" != *'高頻度FAIL: binary_checks: AC self-verification missing'* ]]
}

@test "gate_loop_health autofix蓄積があっても自己修正率判定が実行される" {
    {
        # 10 self-corrected files (FAIL→PASS)
        for i in $(seq 1 10); do
            printf -- '- ts: "2026-04-19T13:%02d:00" file: "queue/reports/sc_%02d.yaml" result: FAIL reasons: "quality_check" fixes: ""\n' "$i" "$i"
            printf -- '- ts: "2026-04-19T13:%02d:30" file: "queue/reports/sc_%02d.yaml" result: PASS reasons: "" fixes: ""\n' "$i" "$i"
        done
        # 2 uncorrected files
        for i in $(seq 11 12); do
            printf -- '- ts: "2026-04-19T13:%02d:00" file: "queue/reports/uc_%02d.yaml" result: FAIL reasons: "quality_check" fixes: ""\n' "$i" "$i"
        done
        # 5 AUTO-FIXED entries (autofix蓄積)
        for i in $(seq 1 5); do
            printf -- '- ts: "2026-04-19T14:%02d:00" file: "queue/reports/af_%02d.yaml" result: AUTO-FIXED reasons: "" fixes: "fixed"\n' "$i" "$i"
        done
    } > "$TEST_TMPDIR/logs/gate_fire_log.yaml"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Self-correction: 10/12 (83%)"* ]]
    [[ "$output" == *"OK: 免疫系正常"* ]]
}

@test "gate_loop_health FAIL率はFAIL/TOTALで計算されFAIL/PASSではない" {
    {
        # 5 FAIL + 3 AUTO-FIXED + 12 PASS = 20 entries (all in recent window)
        # FAIL/PASS = 5/12 = 41.7% > 30% (old buggy code would warn)
        # FAIL/TOTAL = 5/20 = 25% <= 30% (new code does NOT warn)
        for i in $(seq 1 5); do
            printf -- '- ts: "2026-04-19T14:%02d:00" file: "queue/reports/fail_%02d.yaml" result: FAIL reasons: "quality_issue" fixes: ""\n' "$i" "$i"
        done
        for i in $(seq 1 3); do
            printf -- '- ts: "2026-04-19T14:%02d:00" file: "queue/reports/auto_%02d.yaml" result: AUTO-FIXED reasons: "" fixes: "fixed"\n' $((i+5)) "$i"
        done
        for i in $(seq 1 12); do
            printf -- '- ts: "2026-04-19T14:%02d:00" file: "queue/reports/pass_%02d.yaml" result: PASS reasons: "" fixes: ""\n' $((i+8)) "$i"
        done
    } > "$TEST_TMPDIR/logs/gate_fire_log.yaml"

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING: FAIL率30%超"* ]]
    [[ "$output" == *"INFO: 品質系FAIL"* ]]
}

@test "gate_loop_health fail rate warning threshold is above 30 percent" {
    {
        for i in $(seq 1 5); do
            printf -- '- ts: "2026-04-19T13:%02d:00" file: "queue/reports/old_report_%02d.yaml" result: FAIL reasons: "old_pattern MISSING" fixes: ""\n' "$i" "$i"
        done
        printf -- '- ts: "2026-04-19T13:30:00" file: "queue/reports/autofixed_report.yaml" result: AUTO-FIXED reasons: "" fixes: "fixed"\n'
        for i in $(seq 1 7); do
            printf -- '- ts: "2026-04-19T14:%02d:00" file: "queue/reports/recent_fail_%02d.yaml" result: FAIL reasons: "recent_quality_issue" fixes: ""\n' "$i" "$i"
        done
        for i in $(seq 1 13); do
            printf -- '- ts: "2026-04-19T15:%02d:00" file: "queue/reports/recent_pass_%02d.yaml" result: PASS reasons: "" fixes: ""\n' "$i" "$i"
        done
    } > "$TEST_TMPDIR/logs/gate_fire_log.yaml"

    run bash "$TEST_GATE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"WARNING: FAIL率30%超"* ]]
    [[ "$output" != *"WARNING: FAIL率20%超"* ]]
}
