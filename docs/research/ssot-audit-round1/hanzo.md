# SSOT Audit Round 1: Hanzo

task_id: `cmd_3458_hanzo_normal`
scope: `scripts/*daemon*`, `scripts/*monitor*`, `scripts/*watch*`, `scripts/*layout*`, `scripts/*switch*`, `scripts/*model*` and related lib references
generated_at: `2026-06-20T04:16:00+09:00`

## Scope

現行監査対象は実行対象の現行スクリプト19件。`*.bak.*` 5件は同名条件に該当するが、旧スナップショットであり修正対象SSOTではないため主表から除外した。

対象:

- `scripts/clipboard_watcher.sh`
- `scripts/daemon_supervisor.sh`
- `scripts/daemon_watchdog.sh`
- `scripts/gates/gate_daemon.py`
- `scripts/inbox_watcher.sh`
- `scripts/lib/layout_string.sh`
- `scripts/lib/model_colors.sh`
- `scripts/lib/model_detect.sh`
- `scripts/lib/model_resolve.sh`
- `scripts/model_analysis.sh`
- `scripts/model_switch_preflight.sh`
- `scripts/ninja_monitor.sh`
- `scripts/reset_layout.sh`
- `scripts/restart_all_daemons.sh`
- `scripts/restart_monitor.sh`
- `scripts/restart_watchers.sh`
- `scripts/switch_cli_mode.sh`
- `scripts/switch_project.sh`
- `scripts/usage_monitor.sh`

## Measurement

```bash
find scripts -maxdepth 2 -type f \( -name '*daemon*' -o -name '*monitor*' -o -name '*watch*' -o -name '*layout*' -o -name '*switch*' -o -name '*model*' \) | sort
rg -n '\b(karo|gunshi|sasuke|kirimaru|hayate|kagemaru|hanzo|saizo|kotaro|tobisaru|shogun)\b|shogun:(main|agents|[0-9])|agents\.[0-9]|shogun:[0-9]\.[0-9]|\b(claude|codex|copilot|kimi|opus|sonnet|haiku|gpt-[0-9]|/model)\b|/mnt/c|/home/simokitafresh|\$HOME/bin|\.nvm|config/settings.yaml|config/cli_profiles.yaml|agent_config.sh|cli_lookup.sh|model_resolve.sh|model_detect.sh|layout_string.sh' <scope files>
```

| category | rg hits | reading |
|---|---:|---|
| agent names / role names | 169 | 多くは `agent_config.sh` 経由または通知文。`shogun`/`karo` special-caseは複数ファイルに残る |
| pane targets / window names | 59 | `shogun:agents`, `shogun:main`, `shogun:1`, `shogun:2` が複数箇所で定義 |
| CLI / model literals | 97 | `claude/codex/copilot/kimi` と `opus/sonnet/haiku/gpt` の分類ロジックが複数箇所にある |
| absolute path literals | 4 | `/home/simokitafresh/bin/claude`, `.nvm/.../node` など起動系fallback |
| SSOT/config references | 64 | `agent_config.sh`, `cli_lookup.sh`, `model_resolve.sh`, `model_detect.sh`, `config/settings.yaml`, `config/cli_profiles.yaml` |

## Hardcode Table

| file:line | kind | value | SSOT | repair candidate |
|---|---|---|---|---|
| `scripts/switch_cli_mode.sh:121` | agent list | `ALL_AGENTS=(shogun "${_cfg_agents[@]}")` | partial: `agent_config.sh` for non-shogun | introduce `get_all_system_agents` or local documented exception for shogun |
| `scripts/switch_cli_mode.sh:123` | role group | `CORE_AGENTS=(shogun karo)` | none | move core/scope presets to config or `agent_config.sh` helper |
| `scripts/switch_cli_mode.sh:180` | pane target | `shogun:agents`, fallback `shogun:2` | none | centralize tmux window aliases in pane helper |
| `scripts/switch_cli_mode.sh:210` | pane target | `shogun:main`, fallback `shogun:1` | none | centralize tmux window aliases in pane helper |
| `scripts/daemon_watchdog.sh:279` | agent list | `shogun $(get_all_agents)` | partial: `agent_config.sh` | same `get_all_system_agents` helper |
| `scripts/daemon_watchdog.sh:309-318` | pane target | `shogun:main`, `shogun:agents.${pane_index}` | none | reuse shared pane target resolver |
| `scripts/daemon_supervisor.sh:146-147` | pane target | `shogun:main` | none | reuse shared pane target resolver |
| `scripts/daemon_supervisor.sh:276-285` | agent list | emits `shogun`, `karo`, then `get_all_agents` | partial: `agent_config.sh` | define daemon target groups in one helper |
| `scripts/restart_watchers.sh:113-118` | watcher target | shogun watcher uses `shogun:main` | none | call `daemon_supervisor`/shared resolver instead of own launch map |
| `scripts/ninja_monitor.sh:72-75` | pane target | `KARO_PANE`, `GUNSHI_PANE`, fallback `shogun:agents.1` | partial: tmux `@agent_id` primary, fallback none | remove numeric fallback or derive from `agent_config.sh` order helper |
| `scripts/ninja_monitor.sh:626` | agent list | `("shogun" "karo" "gunshi" "${NINJA_NAMES[@]}")` | partial: `agent_config.sh` | `get_all_system_agents` helper |
| `scripts/ninja_monitor.sh:2111` | ninja regex | fallback `hayate|kagemaru|hanzo|saizo|kotaro|tobisaru` | partial: `get_ninja_names`; fallback none | fail closed or cache config-derived regex instead of literal fallback |
| `scripts/ninja_monitor.sh:3260` | agent list | `("shogun" "karo" "gunshi" "${NINJA_NAMES[@]}")` | partial: `agent_config.sh` | helper for all panes/roles |
| `scripts/ninja_monitor.sh:3499-3508` | pane target | `shogun:1`, `shogun:agents` | none | shared pane target resolver |
| `scripts/ninja_monitor.sh:3648-3708` | watcher target | `shogun`, `karo`, `${NINJA_NAMES[@]}` and pane lookup | partial: `agent_config.sh` | include `gunshi` consistently via helper if watcher target remains all agents |
| `scripts/ninja_monitor.sh:3960` | agent list | `("shogun" "karo" "gunshi" "${NINJA_NAMES[@]}")` | partial: `agent_config.sh` | helper for system agents |
| `scripts/ninja_monitor.sh:4131` | pane target | `shogun:1` | none | shared pane target resolver |
| `scripts/ninja_monitor.sh:4252-4262` | pane target | `shogun:1.1` | none | shared pane target resolver; verify actual shogun pane id |
| `scripts/reset_layout.sh:61-75` | agent/order/role | `EXPECTED_AGENTS` from `get_all_agents`; role colors for `karo/gunshi/ninja` | `agent_config.sh` | OK for agent list; color role mapping could move to role metadata |
| `scripts/reset_layout.sh:96` | pane target | `shogun:agents` | none | shared pane target resolver/window alias |
| `scripts/reset_layout.sh:114-140` | CLI config parse | inline awk over `config/settings.yaml` | `config/settings.yaml`, but parser duplicated | prefer `cli_lookup.sh` batch/helper or single parser lib |
| `scripts/reset_layout.sh:140-158` | CLI config parse | inline awk over `config/cli_profiles.yaml` | `config/cli_profiles.yaml`, but parser duplicated | prefer `cli_lookup.sh` batch/helper |
| `scripts/reset_layout.sh:163-189` | launch/model mapping | `claude`, `codex`, `$HOME/bin/claude`, `gpt-*` | `cli_profiles.yaml` partial | put full launch command resolution in cli profile helper |
| `scripts/reset_layout.sh:244-264` | model group mapping | `karo`, `codex`, `opus`, `sonnet`, `haiku`, `claude` | partial: `model_colors.sh`, `model_resolve.sh` | move group classification to `model_resolve.sh` or `model_colors.sh` |
| `scripts/reset_layout.sh:302-578` | pane target | repeated `shogun:agents.${p}` / `shogun:2` | none | shared pane target formatter |
| `scripts/inbox_watcher.sh:438-447` | CLI types | `claude|codex|copilot|kimi`, fallback `codex` | `cli_lookup.sh` partial | expose valid CLI set and default safe CLI from `cli_profiles.yaml` |
| `scripts/inbox_watcher.sh:482-492` | CLI command semantics | `/clear`, `/model` | `cli_profiles.yaml` partial | OK if all command strings come from profile; whitelist remains policy |
| `scripts/inbox_watcher.sh:883` | model whitelist | `claude-|gpt-|o[0-9]|opus|sonnet|haiku` | none | move model switch whitelist to profile/config |
| `scripts/model_switch_preflight.sh:66-70` | model/CLI patterns | dynamic agents plus `gpt-5`, `claude-(opus|sonnet|haiku)` | partial: `agent_config.sh` | move stale hardcode detector pattern to config/profile-driven generator |
| `scripts/lib/model_detect.sh:33-147` | CLI parser dispatch | `claude`, `codex`, fallback others | parser library itself | acceptable SSOT for live model detection |
| `scripts/lib/model_resolve.sh:46-50` | CLI display fallback | `Codex`, `Copilot`, `Kimi`, `Claude` | `cli_profiles.yaml` partial | prefer `cli_profile_get display_name`; keep only emergency fallback |
| `scripts/lib/model_colors.sh:20-33` | role/model colors | `karo/gunshi`, `Codex/Opus/Sonnet/Haiku` | this file claims SSOT | OK for colors; consumers should not duplicate group mapping |
| `scripts/model_analysis.sh:78-135` | model families | `opus_4_6`, `gpt_5`, default `claude` | none | move model family classification to shared lib/config |
| `scripts/ninja_monitor.sh:960-987` | launch fallback | `.nvm/versions/node/v20.20.0/bin`, `/home/simokitafresh/bin/claude --effort high` | `cli_profiles.yaml` partial | get node path/launch command from profile; avoid absolute fallback |
| `scripts/ninja_monitor.sh:3826-3847` | model short mapping | `Op/So/Ha/GPT/Cx` | partial: `model_resolve.sh`, `model_colors.sh` | share one display/group/short-name helper |
| `scripts/ninja_monitor.sh:4175-4215` | model check | `resolve_model_display`, `resolve_bg_color` | `model_resolve.sh`, `model_colors.sh` | OK; keep as consumer |

## Duplicate Definitions

### D1: agent roster and role group

Same concept appears in:

- `scripts/lib/agent_config.sh`: parses `config/settings.yaml` and exposes `get_all_agents`, `get_ninja_names`, `get_agent_role`.
- `scripts/switch_cli_mode.sh:121-123`: defines `ALL_AGENTS` and `CORE_AGENTS`.
- `scripts/daemon_watchdog.sh:279`: prefixes `shogun` to `get_all_agents`.
- `scripts/daemon_supervisor.sh:276-285`: has a separate fallback sequence for `shogun`, `karo`, then `get_all_agents`.
- `scripts/ninja_monitor.sh:626`, `3260`, `3960`: reconstructs all-agent arrays.

修正候補: `agent_config.sh` に `get_system_agents`, `get_core_agents`, `get_watchable_agents` を追加し、各スクリプトの局所配列を削除する。

### D2: tmux pane/window target resolution

Same concept appears in:

- `scripts/switch_cli_mode.sh:167-216`
- `scripts/daemon_watchdog.sh:308-318`
- `scripts/daemon_supervisor.sh:146-158`
- `scripts/restart_watchers.sh:113-131`
- `scripts/ninja_monitor.sh:72-75`, `3499-3508`, `3705-3708`, `4131`, `4252-4262`
- `scripts/reset_layout.sh` repeated `shogun:agents.${p}` and `shogun:2`

修正候補: `scripts/lib/pane_lookup.sh` などへ `resolve_agent_pane`, `agents_window`, `main_window`, `format_agents_pane` を集約する。`shogun:1` / `shogun:2` fallbackは一箇所に閉じ込める。

### D3: CLI/model display, group, launch command

Same concept appears in:

- `scripts/lib/model_detect.sh`: live model parser
- `scripts/lib/model_resolve.sh`: display fallback
- `scripts/lib/model_colors.sh`: model color SSOT
- `scripts/reset_layout.sh:114-189`, `244-264`: settings/profile parser and group mapping
- `scripts/ninja_monitor.sh:960-987`, `3826-3847`, `4175-4215`: launch fallback, short name, consistency check
- `scripts/model_analysis.sh:78-135`: model family classifier
- `scripts/model_switch_preflight.sh:66-70`: hardcode detector model pattern

修正候補: `cli_lookup.sh` / `model_resolve.sh` に batch APIs for type, launch command, display, family, short label を追加し、reset/monitor/model_analysis/preflightの分類ロジックを消す。

### D4: watcher supervision/startup

Same concept appears in:

- `scripts/daemon_supervisor.sh`: start/restart/deduplicate `inbox_watcher` and `ninja_monitor`.
- `scripts/daemon_watchdog.sh`: separate watchdog with restart throttle and hang detection.
- `scripts/restart_watchers.sh`: manual watcher launch path.
- `scripts/ninja_monitor.sh:3648-3718`: watcher health check.

修正候補: `daemon_supervisor.sh` を watcher process SSOTにし、`restart_watchers.sh` は薄い wrapper、`daemon_watchdog.sh`/`ninja_monitor.sh` は状態確認のみへ寄せる。

## Summary

現行コードはSSOT化が途中まで進んでいる。`agent_config.sh`, `cli_lookup.sh`, `model_detect.sh`, `model_resolve.sh`, `model_colors.sh`, `layout_string.sh` は正本候補として機能している一方、pane/window target、system agent group、model family/short label、watcher supervision が複数ファイルで同値定義されている。

優先修正順:

1. pane/window target resolverを作り、`shogun:main`, `shogun:agents`, `shogun:1`, `shogun:2` を集約する。
2. `agent_config.sh` に system/core/watchable group helperを追加する。
3. model family/short label/launch commandを `cli_lookup.sh` / `model_resolve.sh` に寄せる。
4. watcher起動系を `daemon_supervisor.sh` 中心に整理する。
