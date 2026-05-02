---
name: shogun-claude-version-switch
argument-hint: "[pinned|latest|status]"
description: "【将軍専用】multi-agent-shogun の Claude Code version 運用を切り替える。TRIGGER: Claude auto-update再許可、2.1.87固定へロールバック、Claude version確認、pinned/latest切替、Claude pane respawn。DO NOT TRIGGER: Codex編成切替、モデル配備方針変更、通常の /model 操作、Codex-only 切替。"
---

# Shogun Claude Version Switch

## Overview

Claude Code の version 運用だけを切り替えるスキルである。
正本手順は `docs/research/claude-code-version-runbook.md`。このスキルはその実行補助に徹する。

## Commands

```bash
# 現状確認
~/.codex/skills/shogun-claude-version-switch/scripts/claude_version_switch.sh status

# 2.1.87 へ固定（config変更 + Claude pane respawn）
~/.codex/skills/shogun-claude-version-switch/scripts/claude_version_switch.sh pin-2.1.87

# updater管理版へ戻す（config変更 + Claude pane respawn）
~/.codex/skills/shogun-claude-version-switch/scripts/claude_version_switch.sh unpin-latest
```

## Safety

- まず `status` か `--dry-run` を実行せよ
- version 切替は `launch_cmd` 変更だけでは不十分。**Claude pane respawn が必須**
- `--settings-only` は「次回 respawn 時に反映したい」時だけ使え
- 正本ランブックを先に読む: `docs/research/claude-code-version-runbook.md`

## Options

```bash
~/.codex/skills/shogun-claude-version-switch/scripts/claude_version_switch.sh <status|pin-2.1.87|unpin-latest> [--repo <path>] [--dry-run] [--settings-only]
```

## Notes

- 対象は **Claude 系 pane のみ**
- Codex 配備や mixed 編成そのものは変えない
- 2.1.87 固定資産が欠けている場合は停止して報告する
