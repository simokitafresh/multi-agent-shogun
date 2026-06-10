---
name: shogun-claude-version-switch
argument-hint: "[pinned|latest|status] [--agent <name>]"
quality_metric: "将軍系: Claude version切替cmdのcmd_save.shチェック通過率(q1-q4 BLOCKなしで保存できた割合)"
description: |
  【将軍専用】multi-agent-shogun の Claude Code version 運用を切り替える。
  TRIGGER: /shogun-claude-version-switch、Claude auto-update再許可、2.1.87固定へロールバック、Claude version確認、pinned/latest切替、Claude pane respawn
  DO NOT TRIGGER: Codex編成切替、モデル配備方針変更、通常の /model 操作、Codex-only 切替
---

<!-- script_refs_checked_at: 2026-06-10T18:30:00+09:00 -->

Script refs verified: 2026-06-10. `claude_version_switch.sh` の契約は `status/pin-2.1.87/latest/--agent` のまま。666173827(respawn_single_agentのwindow探索修正)・f93c4fded(set_launch_cmd yaml.safe_dump除去)はいずれも内部実装変更で、呼び出し引数・動作・出力の契約は変更なし。

# Shogun Claude Version Switch

## Overview

Claude Code の version 運用だけを切り替えるスキルである。
正本手順は `docs/research/claude-code-version-runbook.md`。このスキルはその実行補助に徹する。

## Commands

```bash
# 現状確認
~/.codex/skills/shogun-claude-version-switch/scripts/claude_version_switch.sh status

# 全Claude paneを 2.1.87 へ固定
~/.codex/skills/shogun-claude-version-switch/scripts/claude_version_switch.sh pin-2.1.87

# 全Claude paneを最新版へ
~/.codex/skills/shogun-claude-version-switch/scripts/claude_version_switch.sh unpin-latest

# 特定paneだけ最新版に（他は変更なし）
~/.codex/skills/shogun-claude-version-switch/scripts/claude_version_switch.sh unpin-latest --agent hayate

# 特定paneをピン止めに戻す（個別オーバーライド削除）
~/.codex/skills/shogun-claude-version-switch/scripts/claude_version_switch.sh pin-2.1.87 --agent hayate
```

## Safety

- まず `status` か `--dry-run` を実行せよ
- version 切替は `launch_cmd` 変更だけでは不十分。**Claude pane respawn が必須**
- `--settings-only` は「次回 respawn 時に反映したい」時だけ使え
- 正本ランブックを先に読む: `docs/research/claude-code-version-runbook.md`

## Options

```bash
~/.codex/skills/shogun-claude-version-switch/scripts/claude_version_switch.sh <status|pin-2.1.87|unpin-latest> [--agent <name>] [--repo <path>] [--dry-run] [--settings-only]
```

## Notes

- 対象は **Claude 系 pane のみ**
- Codex 配備や mixed 編成そのものは変えない
- 2.1.87 固定資産が欠けている場合は停止して報告する
- `--agent` 指定時: settings.yaml の個別 `launch_cmd` を操作（cli_lookup.sh のオーバーライド機構を利用）
- `--agent` + `pin-2.1.87`: 個別オーバーライドを削除しプロファイルデフォルト(ピン止め)に戻す
