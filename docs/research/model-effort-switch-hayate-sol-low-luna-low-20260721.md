# 疾風 model×effort 切替実験（2026-07-21）

## 結論

- 対象ペイン `%6` では `gpt-5.6-sol-low` と `gpt-5.6-luna-low` のapply→respawn→restoreを各1回実行し、バナーと実processの一致は2/2だった。
- 各試行後の共有 `~/.codex/config.toml` checksum復元は2/2成功した。
- 最終状態はsettings=`gpt-5.6-sol-low`、バナー=`gpt-5.6-sol low`、process引数=`model_reasoning_effort=low` / `service_tier=default` で一致した。
- 各試行時点における他agent全ペインのバナー不変証跡を取得していなかったため、AC3は未達。追加live respawn禁止の指示に従い再試行せず、総合判定はFAILとする。

## 切替前一次記録

| 項目 | 値 |
|---|---|
| agent / pane | `hayate` / `%6` |
| task | `cmd_karo_model_effort_hayate_sol_low_luna_low_normal` |
| config | `model=gpt-5.6-luna`, `effort=medium`, `service_tier=default` |
| config SHA-256 | `da1c49e9ac5f2eb4ef02301a9f609abb3863dd4da4b3291b38de6bc6ffb03340` |
| runtime banner | `gpt-5.6-sol low` |
| runtime process | Codex起動引数 `-c model_reasoning_effort=low -c service_tier=default` |

## 実測結果

| 試行 | apply中config | バナー | process | restore checksum | 判定 |
|---|---|---|---|---|---|
| sol-low | `gpt-5.6-sol / low / default` | `gpt-5.6-sol default`（起動直後表示。後続最終確認は`sol low`） | `model_reasoning_effort=low`, `service_tier=default` | baseline一致 | PASS |
| luna-low | `gpt-5.6-luna / low / default` | `gpt-5.6-luna low` | `model_reasoning_effort=low`, `service_tier=default` | baseline一致 | PASS |
| 最終sol-low | `gpt-5.6-sol / low / default` | `gpt-5.6-sol low` | `model_reasoning_effort=low`, `service_tier=default` | baseline一致 | PASS |

成功数は切替対象モデル一致2/2、restore checksum一致2/2、最終復元1/1。他agent不変の時系列証跡は0/2で未達。

## 使用した既存経路

1. `config/settings.yaml` の対象agent `model_name` を `yaml_field_set.sh` で設定する。
2. `scripts/lib/cli_lookup.sh` をsourceし、`codex_config_apply_agent hayate` を実行する。
3. `cli_launch_cmd hayate` の返すコマンドで対象ペインをrespawnする。
4. バナーとpane PID配下のprocess引数を確認する。
5. `codex_config_restore` を実行し、共有config checksumがbaselineへ戻ったことを確認する。
6. 各試行の前後で他agent全ペインのバナーも取得し、不変0件を時系列で証明する。

今回の失敗理由は手順6の証跡欠落。追加live respawnは禁止されたため、既取得証跡だけでFAIL終結した。
