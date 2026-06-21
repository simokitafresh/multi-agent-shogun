# Codex per-agent effort/service_tier 設定調査 (cmd_3481)

<!-- generated: 2026-06-21 by saizo -->

## 問題

`~/.codex/config.toml` の `model_reasoning_effort` と `service_tier` は全Codex共有。
hayateだけ `low` にしたくても全員 `low` になる。

## 調査対象：対策案3種

### 方式A: CLI引数 (`-c key=value`)

**結論: 採用。すでに実装済みで最も適切。**

Codex CLIは `-c key=value` オプションで config.toml の値を起動時に上書きできる。

```
codex -c model_reasoning_effort=low ...
codex -c service_tier=fast ...
```

`scripts/lib/cli_lookup.sh` の `cli_launch_cmd` 関数がすでに対応済み:
- `model_name` の接尾辞 (`gpt-5.5-low`, `gpt-5.5-medium`, `gpt-5.5-high`) から `-c model_reasoning_effort={effort}` を自動生成
- 生成例: `model_name=gpt-5.5-low` → `-c model_reasoning_effort=low`

**現在の問題**: `cli_profiles.yaml` と `settings.yaml` の hayate/kagemaru/hanzo の `model_name` が空 (`""`)。
このため、`cli_launch_cmd` が `-c` を追加せず、config.tomlのグローバル値に依存している。

**解決策**: `model_name` を `gpt-5.5-low` に設定するだけで即動作する。

### 方式B: per-agent toml (`-p profile`)

Codex CLIは `-p <name>` で `$CODEX_HOME/<name>.config.toml`（= `~/.codex/<name>.config.toml`）を
基本設定の上に重ね掛けする。

```bash
# ~/.codex/hayate.config.toml
model_reasoning_effort = "low"
service_tier = "fast"

# 起動
codex -p hayate --dangerously-bypass-approvals-and-sandbox --no-alt-screen
```

**評価**: 可能だが、プロファイルファイルをリポジトリ管理できない（`~/.codex/` は .gitignore 対象）。
方式Aと比べてメリットなし。方式Aで制御できない追加設定（将来の拡張）には有効。

### 方式C: 起動前の一時書換え

config.toml を書き換えてから起動し、完了後に元に戻す。

**評価: 不採用。**
- hayate/kagemaru/hanzo が並列起動する場合に競合する（Race Condition）
- 方式Aで解決できるため不要

## 実装方針

### model_reasoning_effort のper-agent対応

**SSOT**: `config/settings.yaml` の各エージェントの `model_name` フィールド

| agent | 設定値 | CLI引数 |
|-------|--------|---------|
| hayate | `gpt-5.5-low` | `-c model_reasoning_effort=low` |
| kagemaru | `gpt-5.5-low` | `-c model_reasoning_effort=low` |
| hanzo | `gpt-5.5-low` | `-c model_reasoning_effort=low` |

変換ロジック: `cli_lookup.sh` L493-498（既存）

### service_tier のper-agent対応

現状は config.toml のグローバル設定 `service_tier = "fast"` が全員に適用されている。
殿裁定2026-06-11: 忍者=low+fast、家老=medium+fast → 現状全員fastなので問題なし。

将来 per-agent で変えたい場合の設計:
- `settings.yaml` に `service_tier: fast` フィールドを追加
- `cli_launch_cmd` が `-c service_tier=XXX` を生成

本cmdでは `cli_launch_cmd` に `service_tier` 読み取りロジックを追加し、
`settings.yaml` に `service_tier` を書ける構造を整備する。

## ファイル変更対象

1. `config/settings.yaml`: hayate/kagemaru/hanzo の `model_name` を `gpt-5.5-low` に設定
2. `config/cli_profiles.yaml`: defaults.agents の同3エージェントを更新
3. `scripts/lib/cli_lookup.sh`: `service_tier` per-agent 対応ロジックを追加

## 検証コマンド

```bash
cd /mnt/c/tools/multi-agent-shogun
source scripts/lib/cli_lookup.sh
cli_launch_cmd hayate    # → ...codex ... -c model_reasoning_effort=low
cli_launch_cmd kagemaru  # → ...codex ... -c model_reasoning_effort=low
cli_launch_cmd hanzo     # → ...codex ... -c model_reasoning_effort=low
```
