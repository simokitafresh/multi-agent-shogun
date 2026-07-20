# 才蔵 Codex per-agent model/effort 切替実機検証（2026-07-21）

## 目的

共有 `~/.codex/config.toml` を汚染せず、既存の `codex_config_apply_agent` → `tmux respawn-pane -k` → `codex_config_restore` 経路で才蔵のみ `gpt-5.6-sol-high` を起動し、その後 `gpt-5.6-sol-low` へ復元できるかを二値検証する。

## AC1: 切替前一次記録（再計測）

- 計測時点: 2026-07-21 01時台 JST
- agent / pane / PID: `saizo` / `%5` (`shogun:agents.6`) / `615498`
- task: `cmd_karo_model_effort_saizo_sol_high_normal`, `status=in_progress`, `ac_version=59d7d64d`
- tmux表示: `cli=codex`, `model=GPT 5.6 Sol low`, `state=active`
- settings実値: `type=codex`, `model_name=gpt-5.6-sol-high`, `service_tier=default`
- 実pane起動コマンド: `/home/simokitafresh/.nvm/versions/node/v20.20.0/bin/codex --dangerously-bypass-approvals-and-sandbox --no-alt-screen`
- 実バナー: `gpt-5.6-sol high`
- 実process: PID `615498` node Codex、子PID `615524` native Codex
- 共有config: `model=gpt-5.6-luna`, `model_reasoning_effort=medium`, `service_tier=default`
- 共有config SHA-256: `da1c49e9ac5f2eb4ef02301a9f609abb3863dd4da4b3291b38de6bc6ffb03340`
- 判定: AC1 PASS 1/1。tmux `@model_name` はlowで実バナーhighと不一致のため、以後も実バナーと実processを一次情報とする。

## 切替前の他agent実バナー基準

| agent | pane | 実バナー要約 |
|---|---:|---|
| karo | `%1` | `gpt-5.6-sol medium` |
| gunshi | `%3` | `Opus 4.6` |
| hayate | `%6` | `gpt-5.6-sol low` |
| kagemaru | `%2` | `gpt-5.6-sol low` |
| hanzo | `%4` | `gpt-5.6-luna medium` |
| saizo | `%5` | `gpt-5.6-sol high` |
| kotaro | `%7` | `gpt-5.6-luna high` |
| tobisaru | `%8` | `gpt-5.6-sol low` |

## 実験結果

- 追加live respawn禁止通知後は新規試行を行わず、保存済み証跡と現在の実態のみを照合した。
- tmux pane option: `@exp_before_pid=615498`, `@exp_after_pid=715259`, `@exp_done=complete`。PID世代変化は1/1確認。
- respawn後の現実バナー: `gpt-5.6-sol high`。
- respawn後の実process: PID `715259` / 子PID `715298`、いずれも `-c model_reasoning_effort=high -c service_tier=default`。
- モデル/effort一致: 1/1。AC2 PASS。
- 一方、`@exp_before_sha`, `@exp_apply_sha`, `@exp_after_sha` は全て空で、後述の共有config不一致を実験自体の影響か並行作業の影響か分離できない。
- 他agentバナーは現在値を再取得したが、並行のモデル実験中のため、本試行による意図しない変化0件を因果分離できずAC3 FAIL。

## low復元結果

- tmuxの保存値には `@exp_banner="gpt-5.6-sol low"` があるが、同一PID `715259`の現実バナーは `gpt-5.6-sol high`、実processも `model_reasoning_effort=high`。二次情報より一次情報を採用し、low復元は0/1と判定。
- 共有config SHA-256: before `da1c49e9ac5f2eb4ef02301a9f609abb3863dd4da4b3291b38de6bc6ffb03340` → final `036228c47dfd7f6f8ab82061f7b689b931b1748dcc35eba12f565df34e1d470a`。不一致。
- final共有config: `model=gpt-5.6-luna`, `model_reasoning_effort=high`, `service_tier=default`。
- 追加respawn禁止により再復元は実施せず、AC4のlive low復元はFAIL。

## 成功数・失敗理由・正規手順

- sol-high起動のモデル/effort一致: **1/1成功**。
- low復元: **0/1成功**。
- AC二値チェック: AC1=yes, AC2=yes, AC3=no, AC4-low=no, AC4-doc=yes, AC5=yes。全体 **4/6 yes** で総合FAIL。
- 失敗理由: (1) SHA証跡のpane option保存が空、(2) final checksumがbeforeと不一致、(3) low復元の保存バナーと現実バナー/実processが矛盾。
- 当時経路の再現に必要な証跡が不足したため、このactive worker実験を正規手順として採用しない。
- 現行の正規手順: active workerをrespawnせず、`shogun_cli_switch.sh probe-codex --model gpt-5.6-sol --effort high` のisolated processを使う。その最終checkpointで、実モデル/effort、共有config checksum不変、全pane PID変化0件を同時確認する。
