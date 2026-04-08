# Claude Code Version Pin / Rollback Runbook
# 調査: 2026-04-08
# 対象: multi-agent-shogun の Claude 系 pane（shogun / karo / gunshi / Claude忍者）

## §1 結論（3行）

- multi-agent-shogun の Claude 起動は `PATH` ではなく `config/cli_profiles.yaml` の `profiles.claude.launch_cmd` が正本。
- **2.1.87 固定**は `/home/simokitafresh/bin/claude` を明示参照することで実現していた。
- **auto-update 許可**は launch_cmd を updater 管理の `/home/simokitafresh/.local/bin/claude` に戻し、Claude pane を respawn すればよい。

## §2 現在確認できた実体

| パス | 実体 | 役割 |
|------|------|------|
| `/home/simokitafresh/.local/bin/claude` | symlink → `~/.local/share/claude/versions/2.1.92` | updater 管理の最新系 |
| `/home/simokitafresh/bin/claude` | `2.1.87 (Claude Code)` | multi-agent-shogun が固定参照していた本命 |
| `/home/simokitafresh/.local/bin/claude.pinned` | `2.1.87 (Claude Code)` | pinned backup |
| `/home/simokitafresh/claude-2.1.87-stable` | `2.1.87 (Claude Code)` | stable backup |
| `/home/simokitafresh/claude-2.1.88-stable` | 別版 backup | 比較用 backup |

確認コマンド:

```bash
/home/simokitafresh/bin/claude --version
/home/simokitafresh/.local/bin/claude --version
/home/simokitafresh/.local/bin/claude.pinned --version
```

## §3 正本設定箇所

`multi-agent-shogun` の Claude pane はここを見る:

```yaml
# config/cli_profiles.yaml
profiles:
  claude:
    launch_cmd: "/home/simokitafresh/bin/claude --dangerously-skip-permissions"
```

つまり、shell で `claude --version` が何を返そうと、pane 起動は `launch_cmd` の絶対パスが優先される。

## §4 2.1.87 に固定する手順（緊急ロールバック）

### 4.1 もっとも簡単な固定

1. `config/cli_profiles.yaml` の `profiles.claude.launch_cmd` を以下へ設定:

```yaml
launch_cmd: "/home/simokitafresh/bin/claude --dangerously-skip-permissions"
```

2. Claude 系 pane を respawn:

```bash
bash scripts/switch_cli_mode.sh claude --scope shogun,karo,gunshi,kagemaru,hanzo,kotaro,tobisaru
```

3. 確認:

```bash
/home/simokitafresh/bin/claude --version
tmux list-panes -a -F '#S:#I.#P agent=#{@agent_id} cli=#{@agent_cli} model=#{@model_name}'
```

### 4.2 `~/bin/claude` が壊れた時の復元

`~/bin/claude` が消えた・上書きされた場合、どちらかで復元:

```bash
cp /home/simokitafresh/claude-2.1.87-stable /home/simokitafresh/bin/claude
chmod +x /home/simokitafresh/bin/claude
```

または:

```bash
cp /home/simokitafresh/.local/bin/claude.pinned /home/simokitafresh/bin/claude
chmod +x /home/simokitafresh/bin/claude
```

確認:

```bash
/home/simokitafresh/bin/claude --version
```

期待値:

```text
2.1.87 (Claude Code)
```

## §5 auto-update を許可する手順（通常運用復帰）

### 5.1 updater 管理版へ戻す

`config/cli_profiles.yaml` の `profiles.claude.launch_cmd` を以下へ変更:

```yaml
launch_cmd: "/home/simokitafresh/.local/bin/claude --dangerously-skip-permissions"
```

理由:
- `claude` だけにすると PATH 依存になる
- `~/.local/bin/claude` は updater が差し替える symlink であり、意図が明確

### 5.2 Claude 系 pane を respawn

```bash
bash scripts/switch_cli_mode.sh claude --scope shogun,karo,gunshi,kagemaru,hanzo,kotaro,tobisaru
```

### 5.3 確認

```bash
/home/simokitafresh/.local/bin/claude --version
```

期待値:
- 最新の updater 管理版（例: `2.1.92`）

## §6 なぜ respawn 必須か

- `launch_cmd` を変えても、既に起動している pane プロセスは変わらない
- `@agent_cli` / `@model_name` の表示更新だけでは実プロセスの Claude version は切り替わらない
- Claude の version 切替は `/model` ではなく **CLI バイナリの再起動** でのみ反映される

したがって、**version 切替 = `launch_cmd` 変更 + respawn** がワンセット。

## §7 緊急時ショート手順

### 最新版で不具合発生 → 2.1.87 へ即時退避

```bash
# 1. launch_cmdを2.1.87固定へ戻す
# config/cli_profiles.yaml:
#   launch_cmd: "/home/simokitafresh/bin/claude --dangerously-skip-permissions"

# 2. Claude系 paneを再起動
bash scripts/switch_cli_mode.sh claude --scope shogun,karo,gunshi,kagemaru,hanzo,kotaro,tobisaru

# 3. 実体確認
/home/simokitafresh/bin/claude --version
```

### 平時復帰 → auto-update 再開

```bash
# 1. launch_cmdをupdater管理版へ戻す
# config/cli_profiles.yaml:
#   launch_cmd: "/home/simokitafresh/.local/bin/claude --dangerously-skip-permissions"

# 2. Claude系 paneを再起動
bash scripts/switch_cli_mode.sh claude --scope shogun,karo,gunshi,kagemaru,hanzo,kotaro,tobisaru

# 3. 実体確認
/home/simokitafresh/.local/bin/claude --version
```

## §8 根拠

- `config/cli_profiles.yaml` の `profiles.claude.launch_cmd`
- `/home/simokitafresh/bin/claude --version` → `2.1.87`
- `/home/simokitafresh/.local/bin/claude --version` → updater 管理版
- `~/.local/share/claude/versions/` に `2.1.90`, `2.1.91`, `2.1.92` が存在

## §9 見つけ方

- 索引: `context/infrastructure.md` §Claude CLIモデル指定とコンテキスト
- auto-load索引: `CLAUDE.md` / `AGENTS.md` の Infra セクション
- 詳細本体: `docs/research/claude-code-version-runbook.md`
