# SSOT Audit Round 1: Saizo

task_id: `cmd_3458_saizo_normal`
scope: `config/**`, `queue/*.yaml`, `skills/**/SKILL.md`, `skills/**/scripts/**`
generated_at: `2026-06-20T04:30:00+09:00`

## Scope

担当範囲:
- `config/settings.yaml`
- `config/cli_profiles.yaml`
- `config/projects.yaml`
- `config/lesson_tags.yaml`
- `queue/*.yaml` (read-only)
- `skills/**/SKILL.md`
- `skills/**/scripts/**`

## Measurement

```bash
# config内の定数検索
grep -n "launch_cmd|gist_url|save_path|local_path|ntfy_topic" config/settings.yaml config/cli_profiles.yaml config/projects.yaml

# skills内のハードコードパス検索
grep -rn "/home/simokitafresh/|/mnt/c/Python_app|/mnt/c/tools/multi-agent-shogun" skills/
```

| category | 件数 | 内容 |
|---|---:|---|
| config内 同値二重定義 | 3 | gist_url(3箇所)、skill path(同値2フィールド) |
| config間 SSOT分裂 | 1 | launch_cmd(異なる値2箇所) |
| skills ハードコードユーザーパス | 12 | `/home/simokitafresh/` 直書き |
| skills ハードコードプロジェクトパス | 18 | `/mnt/c/Python_app/` 直書き |
| shogun-cli-switch.sh 同値重複 | 2 | PINNED_CMD/LATEST_CMDがcli_profiles.yaml/settings.yamlと同値 |

## Hardcode Table

| # | file:line | kind | value | SSOT存在 | 参照先(SSOT) | repair candidate |
|---|---|---|---|---|---|---|
| 1 | `config/settings.yaml:58` | gist_url | `https://gist.github.com/simokitafresh/6eb495d917fb00ba4d4333c237a4ee0c` | Partial | `config/projects.yaml:dm-signal.gist_url` | settings.yamlのgist_urlはprojects.yamlを参照すべき。もしくは削除 |
| 2 | `config/projects.yaml:6` | gist_url | `https://gist.github.com/simokitafresh/6eb495d917fb00ba4d4333c237a4ee0c` | Yes | `config/projects.yaml:dm-signal.gist_url` (正本候補) | 正本はここ。infra(L23)と同値重複を解消せよ |
| 3 | `config/projects.yaml:23` | gist_url | `https://gist.github.com/simokitafresh/6eb495d917fb00ba4d4333c237a4ee0c` | Yes | `config/projects.yaml:dm-signal.gist_url` | dm-signalと同一値。infraは別URLを持つべきか、またはgist_urlを削除 |
| 4 | `config/settings.yaml:4` | skill.save_path | `/mnt/c/tools/multi-agent-shogun/skills/` | — | `config/settings.yaml:skill.local_path` | skill.save_pathとlocal_pathが同値。1フィールドに統一せよ |
| 5 | `config/settings.yaml:5` | skill.local_path | `/mnt/c/tools/multi-agent-shogun/skills/` | — | `config/settings.yaml:skill.save_path` | 同上。どちらを残すか決めて片方削除 |
| 6 | `config/settings.yaml:14` | launch_cmd (shogun override) | `/home/simokitafresh/.local/bin/claude --dangerously-skip-permissions` | Yes | `config/cli_profiles.yaml:profiles.claude.launch_cmd` | shogunのみlatest binをオーバーライド。意図的ならコメントで明記。cli_profilesとの差分を管理 |
| 7 | `config/cli_profiles.yaml:16` | launch_cmd (claude profile) | `/home/simokitafresh/bin/claude --dangerously-skip-permissions` | Yes | `config/cli_profiles.yaml:profiles.claude.launch_cmd` (正本) | pinned版が正本。settings.yaml L14のovertideと値が異なる（意図的設計） |
| 8 | `config/cli_profiles.yaml:45` | launch_cmd (codex profile) | `/home/simokitafresh/.nvm/versions/node/v20.20.0/bin/codex --dangerously-bypass-approvals-and-sandbox --no-alt-screen` | Yes | `config/cli_profiles.yaml:profiles.codex.launch_cmd` (正本) | nvm pathはcodexバージョン変更で陳腐化リスク。`$(nvm which node)`で動的取得も検討 |
| 9 | `skills/shogun-cli-switch/scripts/shogun_cli_switch.sh:11` | PINNED_CMD | `/home/simokitafresh/bin/claude --dangerously-skip-permissions` | Yes | `config/cli_profiles.yaml:profiles.claude.launch_cmd` | cli_profiles.yamlと同値のハードコード。cli_profile_getで動的取得すべき |
| 10 | `skills/shogun-cli-switch/scripts/shogun_cli_switch.sh:12` | LATEST_CMD | `/home/simokitafresh/.local/bin/claude --dangerously-skip-permissions` | Yes | `config/settings.yaml:cli.agents.shogun.launch_cmd` | settings.yamlのshogun override同値。動的取得すべき |
| 11 | `skills/shogun-cli-switch/scripts/shogun_cli_switch.sh:13` | PINNED_BIN | `/home/simokitafresh/bin/claude` | Partial | `config/cli_profiles.yaml:profiles.claude.launch_cmd`からパス抽出 | cli_profiles.yamlのlaunch_cmdと一致するが独立定数。抽出関数化 |
| 12 | `skills/shogun-cli-switch/scripts/shogun_cli_switch.sh:14` | PINNED_BACKUP | `/home/simokitafresh/.local/bin/claude.pinned` | No | SSOTなし | バックアップパス規則をcli_profiles.yamlに追加、またはSTABLE_BIN規則化 |
| 13 | `skills/shogun-cli-switch/scripts/shogun_cli_switch.sh:15` | PINNED_STABLE | `/home/simokitafresh/claude-2.1.87-stable` | No | SSOTなし | バージョン固定パスをdocs/research/claude-code-version-runbook.mdまたはcli_profiles.yamlに記録 |
| 14 | `skills/shogun-cli-switch/scripts/shogun_cli_switch.sh:16` | LATEST_BIN | `/home/simokitafresh/.local/bin/claude` | Partial | `config/cli_profiles.yaml`からlaunch_cmdのパス部分を抽出可 | #11と同様 |
| 15 | `skills/codd/SKILL.md:24-27,129` | codd実行パス + ai_command | `/home/simokitafresh/.codd-venv/bin/codd`, `/home/simokitafresh/bin/claude --print --model claude-opus-4-6` | No | SSOTなし | codd pathをconfig/tool_paths.yaml等に集約。現状3 SKILL.mdに同値重複 |
| 16 | `skills/codd-fix/SKILL.md:24-25,35,55-56` | codd実行パス | `/home/simokitafresh/.codd-venv/bin/codd` | No | SSOTなし | skills/codd/SKILL.mdと同値。共通preflight変数化の候補 |
| 17 | `skills/codd-refactor/SKILL.md:55-56` | codd実行パス | `/home/simokitafresh/.codd-venv/bin/codd` | No | SSOTなし | 同上。3ファイルで同値重複 |
| 18 | `skills/db-check/SKILL.md:24,40,41,44,324` | DM-Signalプロジェクトパス | `/mnt/c/Python_app/DM-signal` | Yes | `config/projects.yaml:dm-signal.path` | config/projects.yamlのパスを参照すべき |
| 19 | `skills/gs-bench-gate/SKILL.md:38,50,67,68,103,114,115,155` | DM-Signalプロジェクトパス | `/mnt/c/Python_app/DM-signal` | Yes | `config/projects.yaml:dm-signal.path` | 同上。8箇所に直書き |
| 20 | `skills/monthly-report-writer/SKILL.md:73,82` | DM-Signal/SHOGUNパス | `/mnt/c/Python_app/DM-signal`, `/mnt/c/tools/multi-agent-shogun` | Yes | `config/projects.yaml`; 環境変数 `DM_SIGNAL_ROOT`/`SHOGUN_ROOT` | L82で変数化しているが、デフォルト値が直書き。projects.yamlを参照元に |
| 21 | `skills/note-writer/SKILL.md:153` | DM-Signalパス | `/mnt/c/Python_app/DM-signal/marketing-director/content/articles/` | Yes | `config/projects.yaml:dm-signal.path` | 同上 |
| 22 | `skills/sengoku-writer/SKILL.md:52,190` | DM-Signalパス | `/mnt/c/Python_app/DM-signal/marketing-director/content/articles/shogun/` | Yes | `config/projects.yaml:dm-signal.path` | 同上 |
| 23 | `skills/weekly-report-writer/SKILL.md:9,42` | DM-Signalパス | `/mnt/c/Python_app/DM-signal/marketing-director/content/weekly_report/` | Yes | `config/projects.yaml:dm-signal.path` | 同上 |
| 24 | `skills/cdp-browse/SKILL.md:68,147` | auto-opsプロジェクトパス | `/mnt/c/Python_app/auto-ops` | Yes | `config/projects.yaml:auto-ops.path` | 同上 |

## Config YAML Duplicate Definitions (AC3)

### D1: gist_url — 同値3箇所

```
config/settings.yaml:58        gist_url: https://gist.github.com/simokitafresh/6eb495d917fb00ba4d4333c237a4ee0c
config/projects.yaml:6         dm-signal.gist_url: "https://gist.github.com/simokitafresh/6eb495d917fb00ba4d4333c237a4ee0c"
config/projects.yaml:23        infra.gist_url: "https://gist.github.com/simokitafresh/6eb495d917fb00ba4d4333c237a4ee0c"
```

正本候補: `config/projects.yaml:dm-signal.gist_url`
修正方針: settings.yamlの`gist_url`フィールドは用途不明。削除またはprojects.yamlへのポインタに変更。infraのgist_urlはdm-signalと同値のため設計意図を確認要。

### D2: launch_cmd (claude) — 値が異なる2箇所（SSOT分裂）

```
config/settings.yaml:14        shogun.launch_cmd: /home/simokitafresh/.local/bin/claude --dangerously-skip-permissions  # latest binary
config/cli_profiles.yaml:16    claude.launch_cmd: "/home/simokitafresh/bin/claude --dangerously-skip-permissions"        # pinned binary
```

設計意図: `shogun-cli-switch/SKILL.md L15` によると「`profiles.claude.launch_cmd`と個別`settings.yaml launch_cmd`を正本」とある。
両方が正本として機能する意図的設計だが、値が異なる（latest vs pinned）。
修正方針: コメントで設計意図を明記。「shogunはlatest、他のClaude忍者はpinned」の差分を文書化。

### D3: skill.save_path = skill.local_path — 同値2フィールド

```
config/settings.yaml:4    skill.save_path: /mnt/c/tools/multi-agent-shogun/skills/
config/settings.yaml:5    skill.local_path: /mnt/c/tools/multi-agent-shogun/skills/
```

修正方針: 用途の違いを確認の上、同一用途なら1フィールドに統一。異なる用途なら明示的にコメントで差分を記述。

### D4: shogun_cli_switch.sh ↔ cli_profiles.yaml 同値重複

```
skills/shogun-cli-switch/scripts/shogun_cli_switch.sh:11  PINNED_CMD="..."  ← config/cli_profiles.yaml:profiles.claude.launch_cmd と同値
skills/shogun-cli-switch/scripts/shogun_cli_switch.sh:12  LATEST_CMD="..."  ← config/settings.yaml:cli.agents.shogun.launch_cmd と同値
```

修正方針: スクリプト冒頭で`source scripts/lib/cli_lookup.sh`+`cli_launch_cmd claude`で動的取得し、ハードコード定数を除去。

## Summary

| 区分 | 件数 |
|---|---:|
| config YAML間二重定義 | 4件 (D1-D4) |
| skills ハードコードユーザーパス (`/home/simokitafresh/`) | 14件 (#9-#17) |
| skills ハードコードプロジェクトパス (`/mnt/c/Python_app/`) | 7件 (#18-#24) |
| **合計** | **25件** |

最重要修正候補:
1. **D4 (shogun_cli_switch.sh)**: cli_profiles.yamlの正本を参照するよう変更すれば6定数を除去可能
2. **D1 (gist_url)**: settings.yamlのgist_urlフィールドの用途を確認し、不要なら削除
3. **codd-venv path** (#15-17): 3 SKILL.mdに同値重複。将来のパス変更時に3ファイル修正が必要
