#!/usr/bin/env bats
# test_necessity: x_post_gate.sh is the sole fail-close checkpoint before any X post reaches the
# API (P1). Regression here means a holding/ticker leak, a standalone multiplier, a disallowed
# URL, a missing disclaimer, a forbidden word, or first-line internal jargon could reach
# production posting undetected.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    GATE="$PROJECT_ROOT/scripts/x_ops/x_post_gate.sh"
    FIXTURE_DIR="$BATS_TEST_TMPDIR"

    cat > "$FIXTURE_DIR/showcase.json" <<'EOF'
{"data":{"hero":{"name":"Basic-DualMomentum","holding":"XLU","components":{"relative_assets":["SPY","QQQ"],"safe_haven_asset":"XLU"}},"plans":[{"name":"Premium-ShinYotsume","holding":"XLK","ticker":"XLK","components":{"relative_assets":["IWM"],"safe_haven_asset":"BIL"}}]}}
EOF
    export X_GATE_SHOWCASE_JSON="$FIXTURE_DIR/showcase.json"
}

run_gate() {
    run bash "$GATE" "$1"
}

@test "PASS: 枠A教材再掲の下書き(数字なし、免責あり、許可URLのみ)" {
    cat > "$FIXTURE_DIR/pass_a.txt" <<'EOF'
デュアルモメンタムは2つだけ見る。今いちばん強い資産か。その資産は現金より強いか。弱ければ退避。確認は月1回。

詳細と検証は無料ガイド。
https://note.com/tokyojibika/n/n171daa7f92a1
助言ではない。過去は未来を保証しない。
EOF
    run_gate "$FIXTURE_DIR/pass_a.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == "PASS" ]]
}

@test "PASS: 枠B検証の一切れの下書き(倍率は期間/CAGR/MaxDD/ベンチと同一段落)" {
    cat > "$FIXTURE_DIR/pass_b.txt" <<'EOF'
市場の追い風を差し引いた実力を検証した。
2011年〜2026年の約14年間、SPYは年率15.6%、対する検証対象は年率101.9%。最大ドローダウンはSPY-23.8%に対し-17.7%だった。

期間と前提は記事に全部ある。
https://note.com/tokyojibika/n/n171daa7f92a1
教育目的。特定銘柄の推奨ではない。過去の検証は将来を保証しない。
EOF
    run_gate "$FIXTURE_DIR/pass_b.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == "PASS" ]]
}

@test "FAIL rule1: Basic-DualMomentum以外の保有ticker(XLK)が本文にあればFAIL" {
    cat > "$FIXTURE_DIR/fail1.txt" <<'EOF'
プレミアム限定戦略はXLKを中心に運用しています。助言ではない。過去は未来を保証しない。
EOF
    run_gate "$FIXTURE_DIR/fail1.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rule1_holding_or_ticker_leak:XLK"* ]]
}

@test "FAIL rule2: 単独倍率(期間/CAGR/MaxDD/ベンチのいずれとも同一段落に無い)はFAIL" {
    cat > "$FIXTURE_DIR/fail2.txt" <<'EOF'
このポートフォリオは資産を7倍にしました。助言ではない。過去は未来を保証しない。
EOF
    run_gate "$FIXTURE_DIR/fail2.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rule2_standalone_multiplier"* ]]
}

@test "FAIL rule3: 完全ガイド/How toマガジン/dm-signal.com以外のURLはFAIL" {
    cat > "$FIXTURE_DIR/fail3.txt" <<'EOF'
詳細はこちら。
https://example.com/spam
助言ではない。過去は未来を保証しない。
EOF
    run_gate "$FIXTURE_DIR/fail3.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rule3_disallowed_url:https://example.com/spam"* ]]
}

@test "FAIL rule4: 免責1行(助言ではない/保証しない)が無ければFAIL" {
    cat > "$FIXTURE_DIR/fail4.txt" <<'EOF'
デュアルモメンタムは2つだけ見る。今いちばん強い資産か。
EOF
    run_gate "$FIXTURE_DIR/fail4.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rule4_missing_disclaimer"* ]]
}

@test "FAIL rule5: 禁止語(劇薬など)があればFAIL" {
    cat > "$FIXTURE_DIR/fail5.txt" <<'EOF'
この劇薬のような戦略はすごい。助言ではない。過去は未来を保証しない。
EOF
    run_gate "$FIXTURE_DIR/fail5.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rule5_forbidden_word:劇薬"* ]]
}

@test "FAIL rule6: 第一文に内部用語(FoFなど)があればFAIL" {
    cat > "$FIXTURE_DIR/fail6.txt" <<'EOF'
FoFの仕組みで運用しています。助言ではない。過去は未来を保証しない。
EOF
    run_gate "$FIXTURE_DIR/fail6.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rule6_internal_term_in_first_line:FoF"* ]]
}
