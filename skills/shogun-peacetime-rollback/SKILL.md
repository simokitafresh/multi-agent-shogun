---
name: shogun-peacetime-rollback
argument-hint: ""
quality_metric: "将軍系: peacetime rollback cmdのcmd_save.shチェック通過率(q1-q4 BLOCKなしで保存できた割合)"
description: |
  What: Restore multi-agent-shogun from emergency Codex-only mode back to peacetime CLI allocation with scripts/switch_cli_mode.sh and deterministic settings rollback.
  TRIGGER: /shogun-peacetime-rollback、平時編成へ戻す、Codex-only解除、Claude復旧後ロールバック
  DO NOT TRIGGER: 全員Codex切替（→/shogun-all-codex-switch）、単体ペイン修復
---

<!-- script_refs_checked_at: 2026-05-29T23:35:23+09:00 -->

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
- `restart_watchers.sh` now requires a clean singleton watcher set. It sends SIGTERM to existing `inbox_watcher.sh` and `inotifywait ... queue/inbox` processes, escalates to SIGKILL only on residue, then fails if any old watcher remains.
- Rollback is incomplete unless the restart creates exactly `EXPECTED_WATCHER_COUNT` watcher processes (default `9`) and every launched agent has a matching `inbox_watcher.sh <agent>` process.
- The watcher count check uses bracketed pgrep patterns such as `[i]nbox_watcher\.sh` to avoid self-matching. Treat count mismatch as rollback failure and rerun or investigate before reporting completion.

Script refs verified: 2026-05-29 cmd_3107/a4a64068. `restart_watchers.sh` counts only top-level inbox watcher wrapper processes via `ps`/`awk`, excluding child watcher processes from the total; diagnostic listing uses the same top-level filter. Singleton restart and exact `EXPECTED_WATCHER_COUNT` requirements remain unchanged. 2026-05-22 cmd_2967.

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

<!-- script_refs_checked_at: 2026-06-07T21:51:07+09:00 -->
