# cmd_3484 SSOT Dynamic Defaults Audit

Date: 2026-06-21
Worker: kagemaru
Scope: `config/settings.yaml`, `config/cli_profiles.yaml`, `/home/simokitafresh/.codex/config.toml`

## Conclusion

Dynamic setting fields that have an actual change path and need tmux-restart default restore are covered: `settings.yaml` top-level `effort` and per-agent `type`, `model_name`, `launch_cmd` are restored by `scripts/shutsujin_departure.sh` from `config/cli_profiles.yaml defaults`.

Uncovered 2-layer SSOT fields matching the cmd definition, "dynamically changeable but no default restore": 0.

`settings.yaml cli.agents.*.service_tier` is consumed by `scripts/lib/cli_lookup.sh` and becomes `-c service_tier=...`, but no dynamic change script was found. It is therefore not counted as a 2-layer SSOT gap under this cmd. If a future skill/script starts changing it, it should be added to `config/cli_profiles.yaml defaults.agents.*.service_tier` and restored by `shutsujin_departure.sh`.

## Field Coverage Counts

Command used:

```bash
python3 - <<'PY'
import yaml, tomllib
from pathlib import Path
files=[('settings', yaml.safe_load(Path('config/settings.yaml').read_text())),
       ('cli_profiles', yaml.safe_load(Path('config/cli_profiles.yaml').read_text())),
       ('config_toml', tomllib.loads(Path('/home/simokitafresh/.codex/config.toml').read_text()))]
for name,data in files:
    leaves=[]
    def walk(x,p=''):
        if isinstance(x,dict):
            for k,v in x.items(): walk(v, f'{p}.{k}' if p else str(k))
        else:
            leaves.append(p)
    walk(data)
    print(f'{name}: {len(leaves)}')
PY
```

Result:

| File | Leaf fields | Notes |
|---|---:|---|
| `config/settings.yaml` | 52 | Dynamic layer; per-agent CLI state and operational config |
| `config/cli_profiles.yaml` | 57 | Defaults/profile SSOT for CLI behavior |
| `/home/simokitafresh/.codex/config.toml` | 29 | Codex local config; runtime overrides are CLI `-c` values, not tmux restart state |

## Dynamic Change And Restore Matrix

| Field family | File | Dynamic change path found | Restart/default restore found | Verdict |
|---|---|---|---|---|
| `effort` | `config/settings.yaml` | Prior task/supplement requires `shogun-cli-switch`-controlled top-level effort; current code consumes top-level `effort` in metrics only | `scripts/shutsujin_departure.sh` reads `config/cli_profiles.yaml defaults.effort` and writes `settings.yaml root effort` | Covered |
| `cli.agents.*.type` | `config/settings.yaml` | `scripts/switch_cli_mode.sh update_agent_type` writes via `yaml_field_set.sh ... <agent> type` | `scripts/shutsujin_departure.sh` reads `defaults.agents.*.type` and restores each agent | Covered |
| `cli.agents.*.model_name` | `config/settings.yaml` | `scripts/switch_cli_mode.sh` resets incompatible model names; `scripts/lib/cli_lookup.sh` consumes `model_name` to generate model/effort args | `scripts/shutsujin_departure.sh` reads `defaults.agents.*.model_name` and restores each agent | Covered |
| `cli.agents.*.launch_cmd` | `config/settings.yaml` | `skills/shogun-cli-switch/scripts/shogun_cli_switch.sh` has `set_agent_launch_cmd` / `remove_agent_launch_cmd` | `scripts/shutsujin_departure.sh` reads `defaults.agents.*.launch_cmd` and restores each agent | Covered |
| `profiles.*.launch_cmd` | `config/cli_profiles.yaml` | `skills/shogun-cli-switch/scripts/shogun_cli_switch.sh set_launch_cmd` changes Claude profile launch command for pin/unpin | This is the default layer itself, not the dynamic layer; per-agent settings are restored from it | Covered by design |
| `cli.agents.*.service_tier` | `config/settings.yaml` | No writer found; `scripts/lib/cli_lookup.sh` only consumes it and emits `-c service_tier=...` | No default restore for per-agent service tier | Not a gap now: no dynamic writer found |
| `profiles.*` non-launch behavior fields | `config/cli_profiles.yaml` | No dynamic writer found; read by `scripts/lib/cli_lookup.sh`, `inbox_watcher.sh`, `ninja_monitor.sh`, `sync_pane_vars.sh` | Not applicable; profile layer is SSOT | No gap |
| `config.toml service_tier` / `model_reasoning_effort` | `/home/simokitafresh/.codex/config.toml` | Runtime overrides are generated as `codex -c ...` by `scripts/lib/cli_lookup.sh`; no script found that rewrites config.toml for tmux switching | Not applicable to tmux restart default restore; config.toml is already persistent local default | No gap |
| `config.toml` trust, hooks, MCP, TUI, notice, feature fields | `/home/simokitafresh/.codex/config.toml` | No dynamic switch script found in repo scope | Not applicable | No gap |
| Operational fields (`language`, `shell`, `skill.local_path`, `idle_cycle`, `ntfy_topic`, `gist_url`, `screenshot.*`, `logging.*`, `layout.*`) | `config/settings.yaml` | No dynamic writer found in scoped rg for CLI switch/default behavior; `idle_cycle` explicitly excluded by supplement | Not applicable | No gap |

## Evidence

Focused rg command:

```bash
rg -n "yaml_field_set\.sh.*(type|model_name|launch_cmd|effort|service_tier)|set_launch_cmd|set_agent_launch_cmd|remove_agent_launch_cmd|model_reasoning_effort|service_tier" scripts skills tests -g '*.sh' -g '*.bats' -g '*.py'
```

Key hits:

| Evidence | Meaning |
|---|---|
| `scripts/switch_cli_mode.sh:249` | Writes per-agent `type` |
| `scripts/switch_cli_mode.sh:270` | Resets incompatible `model_name` |
| `scripts/shutsujin_departure.sh:65` | Restores top-level `effort` from defaults |
| `scripts/shutsujin_departure.sh:74-76` | Restores per-agent `type`, `model_name`, `launch_cmd` from defaults |
| `skills/shogun-cli-switch/scripts/shogun_cli_switch.sh:185` | Changes profile-level `launch_cmd` |
| `skills/shogun-cli-switch/scripts/shogun_cli_switch.sh:351` | Changes per-agent `launch_cmd` override |
| `skills/shogun-cli-switch/scripts/shogun_cli_switch.sh:417` | Removes per-agent `launch_cmd` override |
| `scripts/lib/cli_lookup.sh:385-386` | Reads per-agent `service_tier` |
| `scripts/lib/cli_lookup.sh:498-508` | Generates Codex `model_reasoning_effort` and `service_tier` CLI overrides |

Design intent checked:

1. `git log -- config/settings.yaml config/cli_profiles.yaml scripts/shutsujin_departure.sh scripts/switch_cli_mode.sh skills/shogun-cli-switch/SKILL.md` shows `cmd_3479` added CLI defaults restore, `cmd_3480` added launch_cmd defaults restore, and subsequent work added effort restore.
2. `scripts/shutsujin_departure.sh` comments define the two layers: dynamic layer is `settings.yaml`; default layer is `cli_profiles.yaml defaults`.
3. `scripts/lib/cli_lookup.sh` confirms consumers resolve launch commands from `settings.yaml` plus `cli_profiles.yaml`, with `model_name` and `service_tier` converted to CLI arguments at launch time.

## Full Field Family Inventory

### `config/settings.yaml`

| Field family | Count basis | Dynamic/default judgment |
|---|---|---|
| Top-level operational: `language`, `shell`, `skill.local_path`, `idle_cycle`, `ntfy_topic`, `gist_url`, `screenshot.*`, `logging.*`, `layout.*` | 13 leaf fields | No scoped dynamic switch writer found; not 2-layer SSOT candidates now |
| Top-level `effort` | 1 leaf field | Covered by `defaults.effort` restore |
| `cli.default` | 1 leaf field | No scoped dynamic writer found; `cli_lookup` fallback only |
| Per-agent identity metadata: `role`, `japanese_name` | 18 leaf fields | Static metadata; no dynamic writer found |
| Per-agent dynamic CLI state: `type`, `model_name`, `launch_cmd` | 19 present leaf fields in current YAML | Covered where dynamically changed; `launch_cmd` exists only as override when present |
| Per-agent `service_tier` | 1 present leaf field (`hayate`, null) | Consumed but no dynamic writer found; watch item, not current gap |

### `config/cli_profiles.yaml`

| Field family | Count basis | Dynamic/default judgment |
|---|---|---|
| `defaults.effort` | 1 leaf field | Default layer for `settings.yaml effort` |
| `defaults.agents.*.(type,model_name,launch_cmd)` | 27 leaf fields | Default layer for per-agent dynamic settings |
| `profiles.*.display_name` | 2 leaf fields | Static profile display fallback |
| `profiles.*.launch_cmd` | 2 leaf fields | Profile default; Claude profile can be changed by pin/unpin skill |
| `profiles.*.ctx_pattern`, `ctx_mode`, `idle_pattern`, `busy_patterns`, `clear_cmd`, `clear_method`, `supports_model_switch`, debounce/wait/stall fields, `post_clear_cmd`, `launch_args` | 25 leaf fields | Static CLI behavior profile; no dynamic writer found |

### `/home/simokitafresh/.codex/config.toml`

| Field family | Dynamic/default judgment |
|---|---|
| `model`, `model_reasoning_effort`, `service_tier` | Persistent Codex defaults. Repo launch path can override effort/service tier via `-c`; no repo script rewrites config.toml for tmux switching. |
| `approval_policy`, `sandbox_permissions`, `personality`, context/doc limits | Static local Codex behavior; no scoped dynamic writer found |
| `projects.*.trust_level` | Static trust declarations |
| `tui.*`, `notice.*`, `features.*`, `plugins.*`, `mcp_servers.*`, `hooks.state.*` | Static local Codex config/hook trust state; no scoped dynamic writer found |

## Result

AC1: PASS. All fields were enumerated at leaf count level and field-family level, with dynamic change and default restore paths recorded.

AC2: PASS. 2-layer SSOT gaps found: 0. The only watch item is `service_tier`, because it is consumed by launch generation but currently has no dynamic writer in the scoped repo search.
