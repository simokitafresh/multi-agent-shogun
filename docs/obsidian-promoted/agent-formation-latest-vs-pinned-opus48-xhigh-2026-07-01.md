---
event_id: "karo:2026-07-01T23:44:47+09:00:agent-formation-latest-vs-pinned-opus48-xhigh"
source_state: "obsidian_promoted"
agent: "karo"
event_type: "operational_knowledge"
source_file: "skills/shogun-cli-switch/SKILL.md"
generated_at: "2026-07-01T23:45:00+09:00"
---

# 最新版とピン留めは版、Opus 4.8 xhigh は model/effort

## Core

- `pin-2.1.87` / `unpin-latest` が切り替えるのは **Claude Code の版** だけ。
- `pin-2.1.87` = `/home/simokitafresh/bin/claude`。
- `unpin-latest` = `/home/simokitafresh/.local/bin/claude`。
- `Opus 4.8 xhigh` は **起動時の `--model opus --effort xhigh` と `settings.yaml` の `model_name`** で決まる。
- よって `unpin-latest` だけでは `Opus 4.8 xhigh` にならない。

## Procedure

1. `~/.codex/skills/shogun-cli-switch/scripts/shogun_cli_switch.sh unpin-latest --agent <agent>`
2. `bash scripts/lib/yaml_field_set.sh config/settings.yaml <agent> model_name opus-4-8-xhigh`
3. `bash scripts/lib/yaml_field_set.sh config/settings.yaml <agent> launch_cmd "/home/simokitafresh/.local/bin/claude --dangerously-skip-permissions --model opus --effort xhigh"`
4. `tmux respawn-pane -k -t <pane> "cd /mnt/c/tools/multi-agent-shogun && /home/simokitafresh/.local/bin/claude --dangerously-skip-permissions --model opus --effort xhigh"`

## Verification

- `settings.yaml` に `model_name=opus-4-8-xhigh`
- `launch_cmd` に `~/.local/bin/claude --model opus --effort xhigh`
- `capture-pane -S -40` のバナーが `Claude Code v2.1.197` かつ `Opus 4.8 with xhigh effort`

## Why

`capture-pane` の model label は stale しうるため、version/model の確定は `settings.yaml` / `launch_cmd` / バナーの三点照合で行う。

origin: [[将軍と軍師を最新版のopus xhigh変更してくれ]] -> [[ピン留めと最新版の違いはわかるか？]] -> [[agent_formation_management]]
