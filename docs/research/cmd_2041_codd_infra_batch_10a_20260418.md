# cmd_2041 CoDD Infra Batch 10-A

日付: 2026-04-18
担当: saizo
対象: `scripts/lib/cli_lookup.sh`, `scripts/cmd_delegate.sh`, `scripts/gates/gate_ninja_workaround_rate.sh`

## 変更要約

- `scripts/lib/cli_lookup.sh`
  - Python YAMLパースを bash 1-pass へ置換。
  - source 時のパス解決も string ops 化し、hot path の subshell を削減。
  - `CLI_LOOKUP_SETTINGS` / `CLI_LOOKUP_PROFILES` override を許可し、テスト容易性を維持。
- `scripts/cmd_delegate.sh`
  - path 解決を string ops 化。
  - 未配備 pending cmd 検出を Python から awk へ置換。
  - archive 完了判定を `find|grep` から glob へ置換。
  - `date` subprocess を `printf -v %T` に置換。
  - `CMD_DELEGATE_SCRIPT_DIR` / `CMD_DELEGATE_PROJECT_DIR` override を追加し、既存テストの分離を維持。
- `scripts/gates/gate_ninja_workaround_rate.sh`
  - Python パーサを awk 実装へ置換。
  - cache hit 時の `head` / `tail` を軽量化。
  - source 時のパス解決を string ops 化。
  - top-level list / `workarounds:` nested 両形式を継続サポート。

## ベンチ手法

- `cli_lookup.sh`
  - `source scripts/lib/cli_lookup.sh; cli_profile_get saizo launch_cmd; cli_model_display gunshi`
  - 各 run ごとに新しい `bash -lc` を起動し、12回の中央値。
- `cmd_delegate.sh`
  - temp fixture 上で `cmd_save.sh` / `inbox_write.sh` を成功モック化。
  - `cmd_delegate.sh cmd_100 ...` を 10 回実行し中央値。
- `gate_ninja_workaround_rate.sh`
  - 実ログ `logs/karo_workarounds.yaml` に対して `--quiet` 実行。
  - cache を毎回削除し、12回の cold median。

## ベンチ結果

| 対象 | Before | After | 改善 |
|------|--------|-------|------|
| `scripts/lib/cli_lookup.sh` | `113.6ms` | `44.8ms` | `-60.6%` |
| `scripts/cmd_delegate.sh` | `93.8ms` | `59.7ms` | `-36.4%` |
| `scripts/gates/gate_ninja_workaround_rate.sh` | `146.2ms` | `38.8ms` | `-73.5%` |

## 検証

- `bats tests/unit/test_cli_lookup.bats`
- `bats tests/unit/test_cmd_delegate.bats`
- `bats tests/unit/test_gate_ninja_workaround_rate.bats`

全PASS。
