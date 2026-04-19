#!/usr/bin/env bash
# PreToolUse[Bash]: bats全量実行をBLOCK（run_tests.sh経由は許可）
# 変更対象のテストファイルのみ実行を強制
input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$command" ]] && exit 0

# run_tests.sh経由は許可（--jobs 8が自動適用される正規ルート）
[[ "$command" =~ run_tests\.sh ]] && exit 0

# bats tests/unit/ (末尾スラッシュ=ディレクトリ全量)をBLOCK
if [[ "$command" =~ bats[[:space:]]+tests/unit/?[[:space:]]*$ ]] || \
   [[ "$command" =~ bats[[:space:]]+tests/unit/\*  ]]; then
    echo "BLOCK: bats tests/unit/ 全量実行は禁止。bash scripts/run_tests.sh を使え（--jobs 8自動適用）。"
    echo "個別ファイル: bats tests/unit/test_specific_file.bats"
    echo "全量: bash scripts/run_tests.sh unit"
    exit 2
fi

exit 0
