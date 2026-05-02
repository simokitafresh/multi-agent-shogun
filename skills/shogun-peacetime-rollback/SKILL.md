---
name: shogun-peacetime-rollback
argument-hint: ""
quality_metric: "将軍系: peacetime rollback cmdのcmd_save.shチェック通過率(q1-q4 BLOCKなしで保存できた割合)"
description: Restore multi-agent-shogun from emergency Codex-only mode back to peacetime CLI allocation after Claude service recovery. Uses scripts/switch_cli_mode.sh for live pane relaunch and keeps settings rollback deterministic.
---

# Shogun Peacetime Rollback

## Overview

Return the system from emergency Codex-only operation to the normal peacetime formation.
Use the bundled script for deterministic rollback instead of manual pane-by-pane operations.

## Runbook

1. Move to the target repository.
```bash
cd /mnt/c/tools/multi-agent-shogun
```

2. Run dry-run first.
```bash
~/.codex/skills/shogun-peacetime-rollback/scripts/rollback_peacetime.sh --dry-run
```

3. Execute rollback.
```bash
~/.codex/skills/shogun-peacetime-rollback/scripts/rollback_peacetime.sh
```

## What The Script Changes

- Set `config/settings.yaml` CLI policy back to peacetime:
- `default: claude`
- `codex`: `sasuke`, `kirimaru`, `hayate`, `saizo`
- `claude-opus-4-6`: `kagemaru`, `hanzo`, `kotaro`, `tobisaru`
- `shogun` and `karo`: remove forced Codex override so they inherit `default: claude`
- Relaunch affected panes via:
- `scripts/switch_cli_mode.sh claude --scope shogun,karo,kagemaru,hanzo,kotaro,tobisaru`
- `scripts/switch_cli_mode.sh codex --scope sasuke,kirimaru,hayate,saizo`
- Pane metadata sync is handled by the central switch flow.
- Restart `inbox_watcher` processes via `scripts/restart_watchers.sh`.

## Options

- `--dry-run`: Print planned actions only.
- `--settings-only`: Update only `config/settings.yaml`.
- `--repo <path>`: Operate on another multi-agent-shogun working tree.

## Verification

Run after rollback:

```bash
tmux list-panes -a -F '#S:#I.#P agent=#{@agent_id} cli=#{@agent_cli} model=#{@model_name}'
```

Expected state:

- `shogun`, `karo`, `kagemaru`, `hanzo`, `kotaro`, `tobisaru` -> `cli=claude`
- `sasuke`, `kirimaru`, `hayate`, `saizo` -> `cli=codex`

## Failure Handling

If rollback stops mid-way, rerun the same command once.
The script is designed to be re-entrant for the same target repository.
