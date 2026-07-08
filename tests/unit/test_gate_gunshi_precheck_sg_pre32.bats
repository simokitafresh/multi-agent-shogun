#!/usr/bin/env bats
# SG-PRE32: 視点列間一致検出(LG049)の回帰テスト
# cmd_3780実データ(Expanding/WF全数一致の縮退)を検出できるか、
# cmd_3518系の健全な視点列(全て異なる値)で誤検出しないかを検証する。
# 本体の_sg_pre32_check関数をsourceして直接呼び出す(ロジック複製排除)
# 引数はエンジン(gate_gunshi_report_precheck_engine.py)がyaml.safe_loadで
# 抽出済みの$FILES_MODIFIED相当(1行1path)を模した文字列を渡す。

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export PROJECT_ROOT
    export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
    FIXTURE_DIR="$TMPDIR/pre32_fixtures_$$"
    mkdir -p "$FIXTURE_DIR/docs/research"
    # 本体スクリプトから_sg_pre32_check関数だけを抽出してsource
    eval "$(sed -n '/_sg_pre32_check()/,/^}/p' "$PROJECT_ROOT/scripts/gates/gate_gunshi_report_precheck.sh")"
}

teardown() {
    rm -rf "$FIXTURE_DIR"
}

@test "SG-PRE32: cmd_3780実データ(Expanding/WF全数一致)を検出しWARNが発火する" {
    # commit 83b76b06 (cmd_3780初回報告)由来の実データ抜粋。
    # Expanding列とWF列が全行で完全一致(独立算出されるべき2視点が縮退)。
    cat > "$FIXTURE_DIR/docs/research/degenerate_report.md" << 'EOF'
# cmd_3780 α6堅牢性報告書（新バンド対応チャンピオン）

## 1. まとめ（レイヤー別SPY差分）

| レイヤー | 指標 | IS | OOS | Expanding | WF | Bull | Neutral | Bear |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| L0 | CAGR | 0.2464 | 0.3026 | 0.2998 | 0.2998 | 1.2335 | 0.1913 | -0.0514 |
| L0 | NHF | -0.0937 | -0.0482 | -0.0720 | -0.0720 | -0.2343 | -0.3626 | 0.0285 |
| L0 | MaxDD | -0.2490 | -0.2486 | -0.2486 | -0.2486 | -0.1669 | -0.1994 | -0.0647 |
| L1 | CAGR | 0.4534 | 0.6092 | 0.5325 | 0.5325 | 1.7706 | 0.3422 | 0.0245 |
| L1 | NHF | 0.0584 | 0.1467 | 0.1035 | 0.1035 | -0.0870 | -0.1879 | 0.0114 |
| L1 | MaxDD | -0.0665 | -0.0658 | -0.0663 | -0.0663 | -0.0555 | -0.1077 | 0.0219 |
EOF
    run _sg_pre32_check "docs/research/degenerate_report.md" "$FIXTURE_DIR" "$PROJECT_ROOT"
    [[ "$output" == *"WARN(LG049)"* ]]
    [[ "$output" == *"Expanding"* ]]
    [[ "$output" == *"WF"* ]]
    [[ "$output" == *"完全一致"* ]]
}

@test "SG-PRE32: cmd_3518系の健全な視点列(全て異なる値)ではWARNが発火しない" {
    cat > "$FIXTURE_DIR/docs/research/healthy_report.md" << 'EOF'
# 健全データ(視点列が正しく独立している場合)

## 1. まとめ（レイヤー別SPY差分）

| レイヤー | 指標 | IS | OOS | Expanding | WF | Bull | Neutral | Bear |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| L0 | CAGR | 0.2464 | 0.3026 | 0.2998 | 0.3105 | 1.2335 | 0.1913 | -0.0514 |
| L0 | NHF | -0.0937 | -0.0482 | -0.0720 | -0.0611 | -0.2343 | -0.3626 | 0.0285 |
| L0 | MaxDD | -0.2490 | -0.2486 | -0.2453 | -0.2401 | -0.1669 | -0.1994 | -0.0647 |
| L1 | CAGR | 0.4534 | 0.6092 | 0.5325 | 0.5488 | 1.7706 | 0.3422 | 0.0245 |
| L1 | NHF | 0.0584 | 0.1467 | 0.1035 | 0.1122 | -0.0870 | -0.1879 | 0.0114 |
| L1 | MaxDD | -0.0665 | -0.0658 | -0.0663 | -0.0599 | -0.0555 | -0.1077 | 0.0219 |
EOF
    run _sg_pre32_check "docs/research/healthy_report.md" "$FIXTURE_DIR" "$PROJECT_ROOT"
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"WARN(LG049)"* ]]
}

@test "SG-PRE32: cmd_3780実報告書のfiles_modified形式(非インデントリスト)からもmd抽出できる" {
    # 実報告書のfiles_modifiedはトップレベル"- path:"(非インデント)形式。
    # エンジンのyaml.safe_load抽出結果を模した1行1pathの文字列を渡すことで、
    # インデント方言に依存しないことを確認する(cmd_3780実データ回帰)。
    cat > "$FIXTURE_DIR/docs/research/degenerate_report.md" << 'EOF'
| レイヤー | 指標 | IS | OOS | Expanding | WF |
| --- | --- | --- | --- | --- | --- |
| L0 | CAGR | 0.24 | 0.30 | 0.29 | 0.29 |
| L1 | CAGR | 0.45 | 0.60 | 0.53 | 0.53 |
| L2 | CAGR | 0.78 | 0.82 | 0.89 | 0.89 |
EOF
    local files_modified
    files_modified=$'docs/research/degenerate_report.md\noutputs/analysis/cmd_3780_alpha6_band_champions_input_contract.json\nscripts/analysis/grid_search/cmd_3780_alpha6_band_champions.py'
    run _sg_pre32_check "$files_modified" "$FIXTURE_DIR" "$PROJECT_ROOT"
    [[ "$output" == *"WARN(LG049)"* ]]
    [[ "$output" == *"Expanding"* ]]
}

@test "SG-PRE32: files_modifiedにmd成果物がなければ対象外PASS" {
    run _sg_pre32_check "scripts/gates/gate_report_format.sh" "$FIXTURE_DIR" "$PROJECT_ROOT"
    [[ "$output" == *"PASS"* ]]
    [[ "$output" == *"対象外"* ]]
    [[ "$output" != *"WARN(LG049)"* ]]
}

@test "SG-PRE32: files_modified空ならPASS" {
    run _sg_pre32_check "" "$FIXTURE_DIR" "$PROJECT_ROOT"
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"WARN(LG049)"* ]]
}

@test "SG-PRE32: 3行未満のテーブルはFP防止のため対象外PASS" {
    cat > "$FIXTURE_DIR/docs/research/short_report.md" << 'EOF'
| レイヤー | 指標 | IS | OOS | Expanding | WF |
| --- | --- | --- | --- | --- | --- |
| L0 | CAGR | 0.2464 | 0.3026 | 0.2998 | 0.2998 |
| L1 | CAGR | 0.4534 | 0.6092 | 0.5325 | 0.5325 |
EOF
    run _sg_pre32_check "docs/research/short_report.md" "$FIXTURE_DIR" "$PROJECT_ROOT"
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"WARN(LG049)"* ]]
}

@test "SG-PRE32: 参照先ファイルが存在しない場合はPASS扱い(FP回避)" {
    run _sg_pre32_check "docs/research/does_not_exist_report.md" "$FIXTURE_DIR" "$PROJECT_ROOT"
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"WARN(LG049)"* ]]
}
