#!/usr/bin/env bash
# ============================================================
# triggering_test.sh
# スキルトリガリングテスト雛形
#
# 各スキルの「発火すべき入力」「発火すべきでない入力」のペアを定義。
# Claude CLIの発火判定はスクリプトから自動検証できないため、
# 手動テスト用チェックリストとして使用する。
#
# Usage:
#   bash tests/skills/triggering_test.sh          # チェックリスト表示
#   bash tests/skills/triggering_test.sh --csv     # CSV出力（外部ツール連携用）
#
# 実行方法:
#   1. このスクリプトを実行してチェックリストを表示
#   2. 将軍CLIで各入力フレーズを投げて発火/非発火を確認
#   3. 結果を記録（PASS/FAIL）
# ============================================================
set -euo pipefail

CSV_MODE=false
[ "${1:-}" = "--csv" ] && CSV_MODE=true

# テストケース定義
# 形式: "スキル名|期待|入力フレーズ"
# 期待: FIRE=発火すべき, NO_FIRE=発火すべきでない
CASES=(
    # --- lesson-sort ---
    "lesson-sort|FIRE|/lesson-sort"
    "lesson-sort|FIRE|教訓の振り分けをして"
    "lesson-sort|FIRE|未振り分け教訓を整理して"
    "lesson-sort|NO_FIRE|教訓を新規登録して"
    "lesson-sort|NO_FIRE|知識の棚卸しをして"

    # --- note-article ---
    "note-article|FIRE|/note-article"
    "note-article|FIRE|note記事を書いて"
    "note-article|FIRE|DM-Signalの機能紹介記事を作って"
    "note-article|NO_FIRE|開発裏話の記事を書いて"
    "note-article|NO_FIRE|週報を作って"

    # --- reset-layout ---
    "reset-layout|FIRE|/reset-layout"
    "reset-layout|FIRE|ペインが消えたので復元して"
    "reset-layout|FIRE|レイアウトをリセットして"
    "reset-layout|NO_FIRE|設定ファイルを編集して"
    "reset-layout|NO_FIRE|ninja_monitorの状態は？"

    # --- sengoku-writer ---
    "sengoku-writer|FIRE|/sengoku-writer"
    "sengoku-writer|FIRE|開発裏話の記事を書いて"
    "sengoku-writer|FIRE|戦国AI列伝を書いて"
    "sengoku-writer|NO_FIRE|ユーザー向けの機能紹介を書いて"
    "sengoku-writer|NO_FIRE|週報を生成して"

    # --- shogun-clear-prep ---
    "shogun-clear-prep|FIRE|/shogun-clear-prep"
    "shogun-clear-prep|FIRE|/clear前の準備をして"
    "shogun-clear-prep|NO_FIRE|知識の棚卸しをして"
    "shogun-clear-prep|NO_FIRE|PD反映確認して"

    # --- shogun-memory-teire ---
    "shogun-memory-teire|FIRE|/shogun-memory-teire"
    "shogun-memory-teire|FIRE|MEMORY.mdが肥大化したので整理して"
    "shogun-memory-teire|FIRE|MCP observationを整理して"
    "shogun-memory-teire|NO_FIRE|7層監査をして"
    "shogun-memory-teire|NO_FIRE|教訓を振り分けて"

    # --- shogun-param-neighbor-check ---
    "shogun-param-neighbor-check|FIRE|/shogun-param-neighbor-check"
    "shogun-param-neighbor-check|FIRE|チャンピオンの隣接パラメータを比較して"
    "shogun-param-neighbor-check|FIRE|過適合リスクを判定して"
    "shogun-param-neighbor-check|NO_FIRE|グリッドサーチを実行して"
    "shogun-param-neighbor-check|NO_FIRE|知識の棚卸しをして"

    # --- shogun-pd-sync ---
    "shogun-pd-sync|FIRE|/shogun-pd-sync"
    "shogun-pd-sync|FIRE|裁定のcontext反映を確認して"
    "shogun-pd-sync|FIRE|PD解決後の知識鮮度チェックして"
    "shogun-pd-sync|NO_FIRE|MEMORY.mdの棚卸しをして"
    "shogun-pd-sync|NO_FIRE|MCPに裁定を記録して"

    # --- shogun-teire ---
    "shogun-teire|FIRE|/shogun-teire"
    "shogun-teire|FIRE|知識の状態は？"
    "shogun-teire|FIRE|棚卸しをして"
    "shogun-teire|FIRE|7層監査をして"
    "shogun-teire|NO_FIRE|MEMORY.mdだけ整理して"
    "shogun-teire|NO_FIRE|教訓を振り分けて"
    "shogun-teire|NO_FIRE|/clear前の準備をして"

    # --- switch-project ---
    "switch-project|FIRE|/switch-project"
    "switch-project|FIRE|プロジェクトを切り替えて"
    "switch-project|FIRE|PJフォーカスをdm-signalに変えて"
    "switch-project|NO_FIRE|PJ情報を見せて"
    "switch-project|NO_FIRE|新しいプロジェクトを作って"

    # --- weekly-report ---
    "weekly-report|FIRE|/weekly-report"
    "weekly-report|FIRE|週報を作って"
    "weekly-report|FIRE|DM-Signal Weekly Reportを生成して"
    "weekly-report|NO_FIRE|X検索して"
    "weekly-report|NO_FIRE|note記事を書いて"

    # --- x-research ---
    "x-research|FIRE|/x-research"
    "x-research|FIRE|Xで最新トレンドを検索して"
    "x-research|FIRE|トピック調査して"
    "x-research|NO_FIRE|週報を作って"
    "x-research|NO_FIRE|note記事を書いて"
)

# 出力
if $CSV_MODE; then
    echo "skill,expected,input_phrase,result"
    for case in "${CASES[@]}"; do
        IFS='|' read -r skill expected phrase <<< "$case"
        echo "${skill},${expected},\"${phrase}\","
    done
else
    echo "======================================================"
    echo "  スキルトリガリングテスト チェックリスト"
    echo "  テストケース数: ${#CASES[@]}"
    echo "======================================================"
    echo ""
    echo "【実行手順】"
    echo "  1. 将軍CLIで各「入力フレーズ」を投入"
    echo "  2. FIRE=当該スキルが発火すべき、NO_FIRE=発火すべきでない"
    echo "  3. 結果を確認し、期待と異なる場合はdescriptionを修正"
    echo ""

    current_skill=""
    for case in "${CASES[@]}"; do
        IFS='|' read -r skill expected phrase <<< "$case"
        if [ "$skill" != "$current_skill" ]; then
            echo "--- $skill ---"
            current_skill="$skill"
        fi
        if [ "$expected" = "FIRE" ]; then
            printf "  [  ] FIRE    : %s\n" "$phrase"
        else
            printf "  [  ] NO_FIRE : %s\n" "$phrase"
        fi
    done

    echo ""
    echo "======================================================"
    echo "  [ ] = 未確認, [OK] = 期待通り, [NG] = 不一致"
    echo "======================================================"
fi
