# SSOT Registry — cmd_3463 AC1

作成日: 2026-06-20
担当: hanzo
根拠: `queue/shogun_to_karo.yaml` cmd_3463 / `docs/research/ssot-audit-round1.md`

## 計測条件

- 対象: `scripts/`, `.claude/`, `.codex/`, `config/`, `skills/`, `AGENTS.md`, `CLAUDE.md`
- コマンド: `rg -l --hidden --glob '!/.git/**' --glob '!docs/research/ssot-registry.md' <pattern> ... | wc -l`
- 実測日時: 2026-06-20T12:05 JST
- 注意: 消費者ファイル数は概念名・現行ヘルパー名・代表literalを含むファイル数。詳細な置換対象数ではない。

## 概念レジストリ

| 概念 | SSOT正本 | ヘルパー関数 | Guard状態 | 消費者ファイル数 | 実測パターン |
|---|---|---|---|---:|---|
| 忍者名 | `config/settings.yaml:cli.agents` | `scripts/lib/agent_config.sh:get_ninja_names`, `get_all_agents`, `get_allowed_targets`, `get_agent_role` | `.claude/hooks/pre-write-edit-combined.sh` Guard16あり。忍者名/全エージェント名直書きを検出 | 29 | `\b(hayate\|kagemaru\|hanzo\|saizo\|kotaro\|tobisaru)\b` |
| リポジトリパス | 未整備。現状は各scriptの`SCRIPT_DIR`/`ROOT_DIR`算出と直書きが混在 | 未整備。cmd_3463 AC3で`scripts/lib/repo_root.sh`予定 | 未整備。Guard16の対象外 | 21 | `/mnt/c/tools/multi-agent-shogun\|SCRIPT_DIR\|ROOT_DIR\|REPO_ROOT\|get_repo_root` |
| PJパス | `config/projects.yaml:projects[].path` | `scripts/lib/project_path.sh:get_project_path` (cmd_3463 AC3実装済み) | `.claude/hooks/pre-write-edit-combined.sh` Guard16あり。`/mnt/c/Python_app/`直書きを検出 (cmd_3464 AC2) | 18 | `/mnt/c/Python_app\|projects\.yaml\|project_path\|PROJECT_PATH\|get_project_path` |
| `gist_url` | `config/settings.yaml:gist_url`がグローバル正本候補。`config/projects.yaml`にはPJ固有値も存在 | 未整備 | 未整備 | 0 | `gist_url\|gist\.github\.com` |
| `launch_cmd` | `config/cli_profiles.yaml:profiles.*.launch_cmd`。`config/settings.yaml:cli.agents.shogun.launch_cmd`は曖昧SSOTとしてcmd_3463 AC2対象 | `scripts/lib/cli_lookup.sh:cli_launch_cmd` | `.claude/hooks/pre-write-edit-combined.sh` Guard17あり。`settings.yaml`のCLI/model手動変更をBLOCK | 4 | `launch_cmd\|cli_launch_cmd\|/bin/claude\|/.local/bin/claude\|codex` |
| スキルパス | `config/settings.yaml:skill.save_path`/`skill.local_path`が同値二重定義。cmd_3463 AC2対象 | 未整備 | 未整備 | 7 | `skill\.save_path\|skill\.local_path\|skills/\|SKILL\.md` |
| ユーザーホーム | 未整備。`/home/simokitafresh`直書きと`$HOME`参照が混在 | 未整備 | 未整備 | 5 | `/home/simokitafresh\|\$HOME\|~/` |
| tmuxウィンドウ名 | 未整備。`shogun:agents`/`shogun:2`/`shogun:main`が分散 | 未整備 | 未整備 | 5 | `shogun:agents\|shogun:2\|shogun:main\|tmux_sessions\|tmux .*shogun` |
| モデル名 | `config/settings.yaml:cli.agents.*.model_name`。表示解決は`config/cli_profiles.yaml`とlive tmux値も併用 | `scripts/lib/cli_lookup.sh:cli_model_display`, `scripts/lib/model_resolve.sh:resolve_model_display`, `scripts/lib/model_colors.sh` | `.claude/hooks/pre-write-edit-combined.sh` Guard17あり。`model_name`手動変更をBLOCK | 6 | `model_name\|resolve_model\|model_resolve\|opus\|sonnet\|haiku\|gpt-5\|codex` |
| ロール名 | `config/settings.yaml:cli.agents`のagent集合 + `instructions/parts/roles/*`。現状は用途別literalも残存 | `scripts/lib/agent_config.sh:get_agent_role` | Guard16がエージェント名直書きを一部検出。ロール名全般のGuardは未整備 | 23 | `\b(shogun\|karo\|gunshi\|ninja)\b\|get_agent_role\|roles/` |

## AC1判定

- 全10概念: 10/10記載済み。
- 消費者ファイル数: 10/10で`rg -l ... | wc -l`の実測値を記載済み。
- 未整備明記: リポジトリパス、PJパス、gist_url、スキルパス、ユーザーホーム、tmuxウィンドウ名、ロール名の不足ヘルパー/Guardを「未整備」と明記済み。
