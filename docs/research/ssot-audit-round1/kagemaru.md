# SSOT Audit Round 1 - kagemaru

task: `cmd_3458_kagemaru_normal`
scope: `.claude/**`, `.codex/**`, `scripts/*.sh`, `scripts/*.py` only
created_at: `2026-06-20`

## 実測サマリ

| category | rg command | hits |
|---|---:|---:|
| agent/role names | `rg '(shogun\|karo\|gunshi\|hayate\|kagemaru\|hanzo\|saizo\|kotaro\|tobisaru)' .claude .codex scripts/*.sh scripts/*.py` | 1301 |
| paths | `rg '(/mnt/c/tools/multi-agent-shogun\|/home/simokitafresh\|~/.claude\|~/.codex\|queue/\|scripts/\|logs/\|context/\|projects/)' .claude .codex scripts/*.sh scripts/*.py` | 1795 |
| model/CLI names | `rg '(claude\|codex\|opus\|sonnet\|haiku\|gpt-[0-9])' .claude .codex scripts/*.sh scripts/*.py` | 331 |
| pane/tmux names | `rg '(shogun:agents\|shogun:2\|shogun:main\|pane\|tmux)' .claude .codex scripts/*.sh scripts/*.py` | 770 |

Note: counts are raw line hits and intentionally include comments/help text. The table below normalizes repeated constants into fixable groups.

## ハードコード抽出表

| id | category | examples | files/lines | SSOT | 修正候補 |
|---|---|---|---|---|---|
| K-01 | agent names | `hayate kagemaru hanzo saizo kotaro tobisaru` | `scripts/normalize_karo_workarounds.py:117`, `scripts/training_completion_check.sh:75`, `scripts/skill_auto_improve.sh:12,231`, `scripts/deploy_task.sh:68`, `scripts/bulletin_confirm.sh:10,103`, `scripts/bulletin_write.sh:33` | `config/settings.yaml` via `scripts/lib/agent_config.sh:get_ninja_names` / `get_all_agents` | Replace fallback literals with a shared helper fallback constant or source `agent_config.sh`; keep fallback only inside `agent_config.sh`. |
| K-02 | commander roles | `shogun karo gunshi` | `scripts/shutsujin_departure.sh:65`, `scripts/build_instructions.sh:188,226`, `scripts/bulletin_confirm.sh:10`, `scripts/bulletin_write.sh:33` | `config/settings.yaml` via `scripts/lib/agent_config.sh:get_agent_names_by_role` or `get_all_agents` | Add role helper for commander/core agents and use it in scripts that currently spell the list. |
| K-03 | tmux agents window | `shogun:agents`, fallback `shogun:2` | `scripts/reset_layout.sh:96,322,563,574,616`, `scripts/ninja_monitor.sh:72,643,659,3508,3708`, `scripts/switch_cli_mode.sh:180`, `scripts/restart_watchers.sh:115,129`, `scripts/daemon_watchdog.sh:312,318`, `scripts/health_check.sh:170,198`, `scripts/deploy_task.sh:452` | partial: `scripts/lib/pane_lookup.sh:pane_lookup`; no single window-name SSOT in root scripts | Introduce `scripts/lib/tmux_targets.sh` or extend `pane_lookup.sh` with `agents_window_target` / `main_window_target`; replace direct window literals outside layout construction. |
| K-04 | legacy tmux window index | `shogun:2`, `2.#{pane_index}`, `shogun:2.2` | `scripts/cmd_complete_gate.sh:1712`, `scripts/cmd_save.sh:5334`, `scripts/ninja_monitor.sh:3508`, `scripts/reset_layout.sh:561,563`, `scripts/inbox_watcher.sh:7` | none; current named target is `shogun:agents` with fallback in some scripts | Convert legacy `shogun:2` lookups to named-target resolver used by `switch_cli_mode.sh:resolve_window_target`; avoid fixed gunshi pane `shogun:2.2`. |
| K-05 | repo absolute path | `/mnt/c/tools/multi-agent-shogun` | `.claude/settings.json:8,19,29,43,47,51,56,67,82,86`, `.codex/hooks.json:9,19,29,41`, `.claude/hooks/post-shogun-inbox-check.sh:3,48,77,119`, `.claude/hooks/post-skill-execution.sh:15`, `.claude/hooks/pre-skill-project-guard.sh:7`, `.claude/hooks/pre-edit-pi-inject.sh:26,34`, `scripts/note_draft.sh:38,50,390,420` | partial: `SHOGUN_ROOT`, `REPO_ROOT`, self-path derivation; settings files have no runtime derivation | For hook config JSON, keep absolute path if CLI requires it but generate from one settings template. For scripts, replace with `${SHOGUN_ROOT:-...}` or self-path derivation. |
| K-06 | Claude binary path | `/home/simokitafresh/bin/claude --effort high`, `.local/bin/claude` | `scripts/ninja_monitor.sh:987`, `config/settings.yaml:13`, task scope references | `config/settings.yaml` plus `config/cli_profiles.yaml` if present; `scripts/lib/cli_lookup.sh:cli_launch_command` | Replace monitor fallback literal with `cli_launch_command` or profile lookup; keep manual fallback in one CLI profile file only. |
| K-07 | Claude/Codex config dirs | `$HOME/.claude`, `$HOME/.claude-secondary`, `$HOME/.codex/state_5.sqlite` | `scripts/usage_compare.sh:5,6`, `scripts/usage_monitor.sh:30,47,343`, `scripts/token_refresh.sh:216,217`, `scripts/api_usage.sh:93`, `.claude/settings.local.json:25,26` | partial: environment variables `MCAS_PRIMARY_DIR`, `CODEX_DB`, `PRIMARY_DIR`, `SECONDARY_DIR`; no shared path helper | Create CLI account/config path helper or document env vars as SSOT; avoid repeating defaults in multiple usage/token scripts. |
| K-08 | model family strings | `opus`, `sonnet`, `haiku`, `gpt-5.5-low`, `claude-opus-4-6` | `config/settings.yaml:11,17,22,27,32,37,42,47,52`, `scripts/model_analysis.sh:106,134,331`, `scripts/knowledge_metrics.sh:126-155,890-892`, `scripts/dashboard_auto_section.sh:792-793`, `scripts/reset_layout.sh:171-184,257-264`, `scripts/lib/model_colors.sh`, `scripts/lib/model_resolve.sh` | `config/settings.yaml` for active model; `scripts/lib/model_resolve.sh` / `model_colors.sh` for display/color | Centralize family normalization in `scripts/lib/model_resolve.sh` or `model_colors.sh`; make dashboards/metrics call the same normalizer. |
| K-09 | hook/root infra roots | `.claude/hooks`, `scripts/hooks`, `scripts/gates` | `.claude/hooks/pre-bash-combined.sh:66`, `.claude/hooks/pre-write-edit-combined.sh:83,501,530`, `scripts/test_select.sh:187-215`, `scripts/semantic_index_update.sh:915-916`, `scripts/ninja_monitor.sh:470,479` | no single SSOT; semantic index owns category mapping separately | Extract infra-sensitive path set to a small data file or lib function used by hooks, test selection, semantic index, and monitor exclusions. |
| K-10 | operational YAML path patterns | `queue/tasks/*.yaml`, `queue/reports/*.yaml`, `shogun_to_karo.yaml`, `logs/karo_workarounds.yaml` | `.claude/hooks/pre-write-read-tracker.sh:42-50`, `.claude/hooks/pre-write-edit-combined.sh:229-239,432-439`, `.claude/hooks/pre-bash-combined.sh:359-390`, `.claude/hooks/post-write-edit-combined.sh:47,62-63`, `.claude/hooks/post-edit-report-guard.sh:15-24`, `.claude/hooks/pre-edit-report-deny.sh:20-29`, `.claude/hooks/pre-bash-yaml-dump-guard.sh:26` | partial: AGENTS rules; no code SSOT for guarded operational YAML patterns | Define guarded path patterns in one hook lib or generated pattern file; dispatch hooks should consume it instead of each hook spelling the same paths. |

## hook/root scripts 同値重複

| duplicate | hook side | root script side | risk | 修正候補 |
|---|---|---|---|---|
| agent ontology guard: direct ninja list detection | `.claude/hooks/pre-write-edit-combined.sh:543-555` | `scripts/normalize_karo_workarounds.py:117`, `scripts/training_completion_check.sh:75`, `scripts/skill_auto_improve.sh:12,231`, `scripts/deploy_task.sh:68` | Hook blocks new direct lists, but root scripts still contain fallback lists that can drift. | Allow only `agent_config.sh` to contain fallback names; make hook whitelist that file and make scripts source it. |
| report YAML direct-edit guard | `.claude/hooks/pre-edit-report-deny.sh:20-29`, `.claude/hooks/post-edit-report-guard.sh:15-24`, `.claude/hooks/pre-write-read-tracker.sh:49-50`, `.claude/hooks/pre-write-edit-combined.sh:432-436`, `.claude/hooks/post-write-edit-combined.sh:47,62-63` | `scripts/report_field_set.sh`, `scripts/gates/gate_report_format.sh` | Same policy is enforced in several hook files with independent regex strings. | Move regex and message to shared hook lib or generated guard config; keep `report_field_set.sh` as SSOT for allowed mutation. |
| yaml.dump operational YAML ban | `.claude/hooks/pre-bash-yaml-dump-guard.sh:26-32`, `.claude/hooks/pre-bash-combined.sh:359-364` | `scripts/lib/yaml_field_set.sh`, `scripts/lib/yaml_atomic.py`, `scripts/report_field_set.sh` | Two hook implementations list the guarded YAML patterns separately. | Delete standalone duplicate or have both source one guard function/pattern list. |
| tmux pane lookup | hooks use `tmux display-message/list-panes` directly in many places | `scripts/lib/pane_lookup.sh`, `scripts/lib/tmux_utils.sh`, `scripts/reset_layout.sh`, `scripts/restart_watchers.sh` | Fixed targets and ad hoc tmux calls diverge from `pane_lookup` behavior. | Add hook-safe pane helper or expose `pane_lookup` for hooks that need agent targets. |
| model display normalization | hook/status UI literals in `.claude/settings.json` and pane formats | `scripts/lib/model_resolve.sh`, `scripts/lib/model_colors.sh`, `scripts/reset_layout.sh`, `scripts/dashboard_auto_section.sh` | New model family requires edits in several scripts. | Make `model_resolve.sh` the only model-family normalizer; scripts should consume its output. |

## AC checkpoints

- AC1: PASS. Raw `rg` extraction completed for agent/role names, paths, model/CLI names, and pane/tmux names; hit counts recorded above.
- AC2: PASS. Each normalized row has SSOT and correction candidate.
- AC3: PASS. Five hook/root duplicate groups recorded.
- AC4: PASS. This file is the required output artifact; report YAML should record summary counts.

## 次周回候補

1. Promote `scripts/lib/agent_config.sh` from partial SSOT to enforced SSOT by removing root-script fallback lists.
2. Add `scripts/lib/tmux_targets.sh` or extend `pane_lookup.sh` so `shogun:agents`, `shogun:main`, and legacy `shogun:2` fallbacks are not repeated.
3. Generate `.claude/settings.json` and `.codex/hooks.json` hook command paths from one repo-root template.
4. Merge operational YAML guard patterns into one hook library consumed by pre-bash, pre-write, post-write, and report-deny hooks.
