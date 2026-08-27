# cmd_4407 クローン依存台帳

- 作成日: 2026-08-27
- 目的: `first_setup.sh` 完了後に `shutsujin_departure.sh` が要求する実行時依存を、別PC/別cloneでも再現できる単一の確認表にする。
- 抽出対象: `scripts/`, `scripts/lib/`, `shutsujin_departure.sh`, `.git/hooks/`, `.githooks/`, `.claude/hooks/`, `.codex/hooks.json`。
- 区分: 必須=通常起動・監視・ゲート・検証のいずれかが要求するもの、任意=特定機能または手動操作だけが要求するもの。

## 1. 機械抽出コマンド

```bash
python3 - <<'PY'
from pathlib import Path
import re

roots = [Path('scripts'), Path('.claude/hooks'), Path('.githooks'), Path('.git/hooks')]
files = [Path('shutsujin_departure.sh'), Path('.codex/hooks.json')]
for root in roots:
    if root.exists():
        files.extend(p for p in root.rglob('*') if p.is_file())
files = sorted(set(p for p in files if p.exists()))
commands = 'bash python3 node npm tmux git jq rg gh inotifywait bats flock timeout setsid crontab claude codex curl sqlite3'.split()
for command in commands:
    count = sum(len(re.findall(r'(?<![A-Za-z0-9_])' + re.escape(command) + r'(?![A-Za-z0-9_])', p.read_text(errors='replace'))) for p in files)
    if count:
        print(f'{command}\t{count}')
print('files_scanned', len(files))
PY

for c in bash python3 node npm tmux git jq rg gh inotifywait bats flock timeout setsid crontab claude codex curl; do
  command -v "$c" 2>/dev/null || echo "$c MISSING"
done

git ls-files --others --exclude-standard -- data queue logs
crontab -l
```

## 2. 抽出結果（生出力）

### 2.1 対象数とコマンド参照数

抽出実行結果は `files_scanned 640`。参照数（コメント・文字列・バックアップを含むため、存在判定には使わない）は次のとおり。

```text
bash 2295
python3 1332
node 339
npm 13
tmux 725
git 1833
jq 196
rg 234
gh 64
inotifywait 77
bats 428
flock 724
timeout 653
setsid 29
crontab 13
claude 303
codex 149
curl 73
sqlite3 235
```

### 2.2 現環境の解決結果

```text
/usr/bin/bash
/usr/bin/python3
/home/simokitafresh/.nvm/versions/node/v20.20.0/bin/node
/home/simokitafresh/.nvm/versions/node/v20.20.0/bin/npm
/usr/bin/tmux
/usr/bin/git
/usr/bin/jq
/home/simokitafresh/.nvm/versions/node/v20.20.0/lib/node_modules/@openai/codex/node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/codex-path/rg
/usr/bin/gh
/usr/bin/inotifywait
/home/simokitafresh/.nvm/versions/node/v20.20.0/bin/bats
/usr/bin/flock
/usr/bin/timeout
/usr/bin/setsid
/usr/bin/crontab
/home/simokitafresh/.local/bin/claude
/home/simokitafresh/.nvm/versions/node/v20.20.0/bin/codex
/usr/bin/curl
```

### 2.3 cronの生出力

```text
# daemon_watchdog: デーモン死活監視+自動再起動 (毎分)
* * * * * bash /mnt/c/tools/multi-agent-shogun/scripts/daemon_watchdog.sh >> /mnt/c/tools/multi-agent-shogun/logs/daemon_watchdog_cron.log 2>&1
17 0 * * 1 cd "/mnt/c/tools/multi-agent-shogun" && "/mnt/c/tools/multi-agent-shogun/scripts/weekly_metrics_trend.sh" >/dev/null 2>&1 # shogun-weekly-metrics-trend
```

### 2.4 未追跡実行時データの生出力

```text
git ls-files --others --exclude-standard -- data queue logs
(空出力)
```

存在確認（`test -e`）:

```text
config/settings.yaml present
config/cli_profiles.yaml present
requirements.txt present
data/multi_agent_shogun_memory.db present
queue/lord_conversation.jsonl present
queue/pending_decisions.yaml present
queue/bulletin_board.yaml present
queue/insights.yaml present
logs present
~/.codex/config.toml present
~/.claude present
~/bin/claude present
```

## 3. 依存区分

| 区分 | 依存 | 根拠・first_setup対応 |
|---|---|---|
| 必須 | bash, git, python3, node, npm, tmux | launcher・各scriptの実行基盤。既存Step/確認を維持 |
| 必須 | jq, rg, gh, inotifywait, bats | hooks・監視・CI/検証・inbox watcher。STEP 5.5で存在確認、Debian系では不足時のみapt補完 |
| 必須 | flock, timeout, setsid, crontab, curl | 排他・bounded実行・daemon/installer。STEP 5.5で存在確認、不足時のみapt補完 |
| 必須 | `requirements.txt` + `.venv/bin/python3` + PyYAML | Python依存をclone内venvへ隔離し、欠落時のみvenv/pip準備 |
| 必須 | Codex CLI + `~/.codex/config.toml` | settings/cli_profilesがCodexを含む。設定ファイルは欠落時だけ雛形作成、既存設定は非上書き |
| 必須 | `data/multi_agent_shogun_memory.db` | 三層preflight・memory queryの実体。欠落時だけ `scripts/memory_db_init.sh` で初期化 |
| 必須 | `queue/lord_conversation.jsonl`, `queue/pending_decisions.yaml`, `queue/bulletin_board.yaml`, `queue/insights.yaml`, `logs/` | watcher・gate・reflux・記憶還流の入力。欠落時だけ空の初期構造を作成 |
| 必須 | `~/bin/claude` の2.1.87 pin | Claude起動方針。first_setupは存在/versionを確認するが、既存CLIを暗黙に置換しない |
| 必須 | cron: `daemon_watchdog.sh`, `shogun-weekly-metrics-trend` | 毎分daemon監視・週次計測。既存行を保持し、marker不在時だけ登録 |
| 必須 | `scripts/*.sh` 実行ビット | clone後の直接実行契約。欠落ビットだけ `chmod +x` |
| 任意（Windows Terminal） | `wt.exe` | `-t/--terminal` 指定時のみ |
| 任意（WSLメモリ） | `cmd.exe`, `wslpath` | WSLの`.wslconfig`補助。存在しない環境では案内のみ |
| 任意（Memory MCP） | Claude CLIのMCP機能、`npx`、Memory MCP package | Claudeが存在し、未設定の場合だけ追加を試行。認証情報は手動領域 |
| 任意（手動運用） | `~/.claude/` 認証・Memory MCP状態、`queue/`内の履歴・archive | first_setupは既存データを変更せず、欠落時のみ空構造を生成 |

## 4. first_setupとの差分と反映状態

| 項目 | 反映 |
|---|---|
| 外部コマンドの一括確認と不足時のapt補完 | `first_setup.sh` STEP 5.5 |
| venv/PyYAMLのclone内準備 | `first_setup.sh` STEP 5.5 |
| Codex CLI確認と`~/.codex/config.toml`欠落時雛形 | `first_setup.sh` STEP 5.5 |
| memory DB・queue主要ファイルの欠落時初期化 | `first_setup.sh` STEP 8後 |
| shell script実行ビット確認 | `first_setup.sh` STEP 9 |
| cron二本のmarker付き冪等登録 | `first_setup.sh` STEP 10.5後 |
| 既存設定・既存queue・既存DBの上書き抑止 | 全て存在チェックで分岐 |
| `curl | bash` の直接実行回避 | installerを一時ファイルへ取得してbash実行する関数へ集約 |

## 5. 再現検証コマンド

```bash
bash -n first_setup.sh
bash -n shutsujin_departure.sh
timeout 180 bash first_setup.sh -S
TMUX_TMPDIR="$(mktemp -d)" timeout 180 bash shutsujin_departure.sh -s
```

`shutsujin_departure.sh -s` はCLI・常駐daemonを起動せず、`TMUX_TMPDIR`でtmux socketを隔離して検証する。通常運用のセッション・watcher・queueを触らないことがAC3の安全条件である。
