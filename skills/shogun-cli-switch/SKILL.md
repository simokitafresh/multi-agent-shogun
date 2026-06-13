---
name: shogun-cli-switch
argument-hint: "[status|to-claude|to-codex|pin-2.1.87|unpin-latest] [--agent <name>] [--scope core|all|csv]"
quality_metric: "将軍系: CLI/version切替cmdのcmd_save.shチェック通過率(q1-q4 BLOCKなしで保存できた割合)"
description: |
  【将軍専用】multi-agent-shogun のCLI種別(Claude⇔Codex)とClaude Code version運用を切り替える。
  switch-to-codex / switch-to-opus / shogun-claude-version-switch の上位互換。
  settings.yaml更新→tmux変数同期→idle paneのみrespawn。in_progress/active paneはスキップして設定だけ反映する。
  TRIGGER: /shogun-cli-switch、Claude auto-update再許可、2.1.87固定へロールバック、Claude version確認、pinned/latest切替、Claude⇔Codex切替、家老をCodexに、軍師をOpusに、CLI pane respawn
  DO NOT TRIGGER: 忍者モデル編成切替（→/hensei）、通常の /model 操作、全員Codex緊急切替（→/shogun-all-codex-switch）
---

<!-- script_refs_checked_at: 2026-06-13T15:21:03+0900 -->

Script refs verified: 2026-06-13. `shogun_cli_switch.sh` は `status/pin-2.1.87/unpin-latest/to-claude/to-codex/--agent/--scope/--dry-run/--settings-only` を契約にする。CLI切替は `scripts/switch_cli_mode.sh`、Claude version切替は `config/cli_profiles.yaml` の `profiles.claude.launch_cmd` と個別 `settings.yaml launch_cmd` を正本にする。

# Shogun CLI Switch

## Overview

multi-agent-shogun の指揮官/指定agentを Claude Code と Codex CLI の間で切り替え、必要に応じて Claude Code の pinned/latest version も切り替える。
旧 `/switch-to-codex` と `/switch-to-opus` は本スキルへ統合済み。旧 `/shogun-claude-version-switch` の機能も保持する。

## Commands

```bash
# 現状確認
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh status

# 全Claude paneを 2.1.87 へ固定
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh pin-2.1.87

# 全Claude paneを最新版へ
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh unpin-latest

# 特定paneだけ最新版に（他は変更なし）
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh unpin-latest --agent hayate

# 特定paneをピン止めに戻す（個別オーバーライド削除）
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh pin-2.1.87 --agent hayate

# 指定agentをCodexへ切替
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh to-codex --agent karo

# 指定agentをClaude/Opusへ復帰
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh to-claude --agent karo

# 複数agentまたはcore(shogun,karo)を切替
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh to-codex --scope shogun,karo,gunshi
```

## Safety

- まず `status` か `--dry-run` を実行せよ
- CLI/version 切替は設定変更だけでは不十分。**idle paneのrespawnが必須**
- `active` / `in_progress` 相当のpaneはスキップし、設定だけを次回起動へ反映する
- `--settings-only` は「次回 respawn 時に反映したい」時だけ使え。CLI切替では `scripts/switch_cli_mode.sh --no-relaunch` に対応する
- 正本ランブックを先に読む: `docs/research/claude-code-version-runbook.md`
- Codex切替の前提: `~/.codex/config.toml` に `model_context_window = 1000000`、`model_auto_compact_token_limit = 900000`、hooks有効化があること
- Codexロール指示: `instructions/generated/codex-{role}.md` と AGENTS.md Recovery手順を使う
- 将軍切替時は殿が将軍ペインにいるため、別paneから実行せよ

## Options

```bash
~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh <status|pin-2.1.87|unpin-latest|to-claude|to-codex> [--agent <name>] [--scope <core|all|csv>] [--repo <path>] [--dry-run] [--settings-only]
```

## Notes

- `pin-2.1.87` / `unpin-latest` の対象は **Claude 系 pane のみ**
- `to-claude` / `to-codex` は `settings.yaml` の `type` を変更し、tmux `@agent_cli` / `@model_name` を同期する
- 2.1.87 固定資産が欠けている場合は停止して報告する
- `--agent` 指定時: CLI切替では単一agentの `type` を変更、version切替では個別 `launch_cmd` を操作（cli_lookup.sh のオーバーライド機構を利用）
- `--agent` + `pin-2.1.87`: 個別オーバーライドを削除しプロファイルデフォルト(ピン止め)に戻す
- shutsujin再起動時は指揮官(shogun/karo/gunshi)をデフォルトClaude/Opusへ戻す。Codex切替は手動実行時のみの一時状態である

## 関連スキル

- [[shogun-all-codex-switch]] — 全忍者をCodex CLIに一括切替（モデル系ではなくCLI種別の切替）
- [[shogun-peacetime-rollback]] — CodexからClaude（平時編成）への一括ロールバック
- [[hensei]] — 忍者モデル編成切替
