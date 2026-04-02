#!/usr/bin/env bash
# PreToolUse[Bash]: bats全量実行をBLOCK
# 変更対象のテストファイルのみ実行を強制
input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$command" ]] && exit 0

# bats tests/unit/ (末尾スラッシュ=ディレクトリ全量)をBLOCK
if [[ "$command" =~ bats[[:space:]]+tests/unit/?[[:space:]]*$ ]] || \
   [[ "$command" =~ bats[[:space:]]+tests/unit/\*  ]]; then
    echo "BLOCK: bats tests/unit/ 全量実行は禁止。変更対象のテストファイルのみ指定せよ。"
    echo "例: bats tests/unit/test_specific_file.bats"
    echo "全量実行が必要な場合はgit push(pre-pushフック)に任せよ。"
    exit 2
fi

exit 0
