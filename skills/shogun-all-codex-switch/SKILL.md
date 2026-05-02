---
name: shogun-all-codex-switch
description: Switch multi-agent-shogun to Codex-only operation via scripts/switch_cli_mode.sh, then normalize cli.default=codex and restart inbox watchers. Use when you need every role (shogun, karo, gunshi, all ninja) on Codex immediately.
---

# Shogun All Codex Switch

## Overview

Force the system into all-Codex mode using one deterministic script chain instead of manual pane operations.

This skill is for the full command chain, not just execution panes:
- shogun
- karo
- gunshi
- all ninja

## Runbook

1. Move to the target repository.
```bash
cd /mnt/c/tools/multi-agent-shogun
```

2. Run dry-run first.
```bash
~/.codex/skills/shogun-all-codex-switch/scripts/switch_all_codex.sh --dry-run
```

3. Execute the switch.
```bash
~/.codex/skills/shogun-all-codex-switch/scripts/switch_all_codex.sh
```

## Preconditions

- Run this only in a `multi-agent-shogun` working tree.
- Ensure the repo already has Codex instruction coverage for every active role, especially `gunshi`.
- If role instruction generation was just changed, rebuild first:

```bash
bash scripts/build_instructions.sh
```

## What The Script Changes

- Delegate runtime/settings switch to `scripts/switch_cli_mode.sh codex --scope all`.
- Normalize `config/settings.yaml`:
- `cli.default: codex`
- **CLI / model表示の実ランタイム反映には pane respawn が必須**。`--settings-only` は設定ファイルだけを書き換えるため、既存paneの `@agent_cli` / `@model_name` や実プロセスは変わらない。
- Respawn tmux panes for all agents in Codex CLI (unless `--settings-only`).
- Refresh pane metadata through the central switch flow.
- Restart inbox watchers via `scripts/restart_watchers.sh` (unless `--settings-only`).

## Options

- `--dry-run`: Print planned actions only.
- `--settings-only`: Update `config/settings.yaml` only (skip tmux respawn + watcher restart). Use this only when you intentionally do **not** want running panes to reflect the new CLI/model yet.
- `--repo <path>`: Target another multi-agent-shogun working tree.

## Verification

Run after execution:

```bash
tmux list-panes -a -F '#S:#I.#P agent=#{@agent_id} cli=#{@agent_cli} model=#{@model_name}'
```

Expected state:

- Every managed agent (`shogun`, `karo`, `gunshi`, `sasuke`, `kirimaru`, `hayate`, `kagemaru`, `hanzo`, `saizo`, `kotaro`, `tobisaru`) shows `cli=codex`.

If `gunshi` is missing from the verification output, treat that as an incomplete switch.

## Failure Handling

If execution stops mid-way, rerun the same command once.
The script is idempotent for the same target repository.
