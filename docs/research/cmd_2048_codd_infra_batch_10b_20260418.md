# cmd_2048 CoDD Infra Batch 10-B

日付: 2026-04-18
担当: saizo
対象: `scripts/gates/mark_no_learning.sh`, `scripts/log_terminal_input.sh`, `scripts/statusline.sh`

## 変更要約

- `scripts/gates/mark_no_learning.sh`
  - path 解決を string ops 化。
  - `date -u` + heredoc を `printf -v` + `printf` に置換。
- `scripts/log_terminal_input.sh`
  - `cat | jq` をやめ、stdin を `jq` へ直接流す形に変更。
  - path 解決を string ops 化。
  - 既存の slash / inbox nudge 除外と lord conversation 記録フローは維持。
- `scripts/statusline.sh`
  - `cat | jq` をやめ、stdin を `jq` へ直接流す形に変更。
  - `date +%s` を `printf -v %(%s)T` に置換。
  - invalid JSON / 負数 clamp / tmux 更新契約は維持。

## ベンチ手法

- `mark_no_learning.sh`
  - temp workdir で `scripts/gates/mark_no_learning.sh cmd_999` を 12 回実行し中央値。
- `log_terminal_input.sh`
  - `tmux display-message` を `shogun` 返却 stub に差し替え。
  - 正常 prompt JSON を stdin から与え、temp workdir で 12 回実行し中央値。
- `statusline.sh`
  - `tmux` を no-op stub に差し替え。
  - `{"context_window":{"used_percentage":33.7}}` を stdin から与え、12 回実行し中央値。

## ベンチ結果

| 対象 | Before | After | 改善 |
|------|--------|-------|------|
| `scripts/gates/mark_no_learning.sh` | `30.9ms` | `27.2ms` | `-12.0%` |
| `scripts/log_terminal_input.sh` | `109.7ms` | `83.9ms` | `-23.5%` |
| `scripts/statusline.sh` | `27.8ms` | `25.4ms` | `-8.6%` |

## 検証

- `bats tests/unit/test_mark_no_learning.bats`
- `bats tests/unit/test_log_terminal.bats`
- `bats tests/unit/test_statusline.bats`

全PASS。
