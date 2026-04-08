# cmd_314: アカウント切替手順・副作用調査・Gistマルチプロジェクト対応

> 偵察B (subtask_314_recon_b) | 小太郎 | 2026-02-25

---

## §1 アカウント切替の具体手順と推定所要時間

### 認証コマンド体系

| コマンド | 機能 |
|----------|------|
| `claude auth login` | Anthropicアカウントにサインイン（ブラウザOAuth） |
| `claude auth logout` | ログアウト |
| `claude auth status` | 認証状態を表示 |
| `claude setup-token` | 長期トークン設定（サブスクリプション必要） |

### 現行認証状態

| 項目 | 値 |
|------|-----|
| authMethod | claude.ai（ブラウザOAuth） |
| apiProvider | firstParty |
| subscriptionType | max |
| 認証ファイル | `~/.claude/.credentials.json`（mode 600） |

### 切替シナリオ: 全11CLI一括切替

**手順**:
1. `claude auth logout` — 現アカウントからログアウト
2. `claude auth login` — 新アカウントでブラウザ認証

**推定所要時間**:
- 認証はOAuthフロー（ブラウザリダイレクト）のため、1回あたり約15-30秒
- ただし認証情報は `~/.claude/.credentials.json` に保存 → **全11CLIで共有**
- つまり1回のlogin/logoutで全CLI分の認証が切り替わる
- **推定ダウンタイム: 30秒〜1分**（logout→login→ブラウザ認証完了）

**注意**: ログアウト中は全CLIが認証エラーになる。稼働中の忍者は全停止する。

### setup-token方式（代替案）

`claude setup-token` で長期トークンを設定すれば、ブラウザ不要で認証可能。
- 環境変数 `ANTHROPIC_API_KEY` でも認証できる可能性あり（API keyベース）
- ただしMax Plan特典（高レート等）が維持されるかは未確認

---

## §2 CLAUDE_CONFIG_DIR分離の実証

### ~/.claude/ ディレクトリ構造

| パス | 内容 | CONFIG_DIR依存 |
|------|------|---------------|
| `.credentials.json` | OAuth認証トークン（mode 600） | **YES** — これが認証の実体 |
| `settings.json` | モデル・権限・MCP・言語設定 | **YES** — CLI動作設定 |
| `history.jsonl` | 会話履歴（1.9MB） | YES |
| `projects/` | プロジェクト固有設定（MEMORY.md等） | YES |
| `skills/` | 10スキル | YES |
| `file-history/` | ファイル編集履歴（1110ディレクトリ） | YES |
| `session-env/` | セッション環境（221セッション分） | YES |

### 分離時の挙動（推定）

`CLAUDE_CONFIG_DIR=~/.claude-secondary/` で起動すると:
- **新規作成**: 空ディレクトリから開始。settings.json等は存在しない状態
- **設定は引き継がれない**: permissions, model, language, MCP全て再設定が必要
- **認証も独立**: `.credentials.json` が別ファイルになるため、別アカウントでlogin可能

### 分離に必要な最小対応

1. `settings.json` をコピー（または共有シンボリックリンク）
2. `skills/` をコピーまたはシンボリックリンク
3. `projects/` のMEMORY.mdをコピーまたはシンボリックリンク
4. `.credentials.json` は**独立**（別アカウントの認証を格納）

---

## §3 分割運用の可能性

### アカウントA(N台) + アカウントB(M台)の分割稼働

**方式**: tmuxペインごとに `CLAUDE_CONFIG_DIR` を変えてCLIを起動

### tmux環境変数のペインごと設定

| 方式 | スコープ | 永続性 | ペイン独立 |
|------|----------|--------|-----------|
| `tmux setenv NAME value` | セッション | セッション寿命 | **不可** |
| `split-window -e "FOO=bar"` | プロセス起動時 | 子プロセスのみ | 可（初回のみ） |
| `set-option -p @name value` | ペイン | ペイン寿命 | **可** |

**結論**: tmuxにはネイティブのペインレベル環境変数は存在しない。

### 実現方法

**方法1: respawn-paneで環境変数注入**
```bash
# アカウントB用ペイン（例: hayate=pane 4）
tmux respawn-pane -t shogun:2.4 -e "CLAUDE_CONFIG_DIR=/home/simokitafresh/.claude-b" -k "claude"
```
- `-e` フラグで起動時に環境変数を注入
- CLIプロセス内で `CLAUDE_CONFIG_DIR` が有効になる

**方法2: シェルラッパー**
```bash
# ペイン起動時のコマンドを変更
tmux send-keys -t shogun:2.4 "CLAUDE_CONFIG_DIR=~/.claude-b claude" Enter
```

**方法3: shutsujin_departure.sh改修**
- 各忍者の起動スクリプトにCONFIG_DIR設定を追加
- config/settings.yaml にペインごとのconfig_dir設定を追加

### 運用例: A(将軍+家老+上忍4) + B(上忍2+下忍2)

```
アカウントA (Max Plan): 将軍, karo, hayate, kagemaru, hanzo, saizo → ~/.claude/
アカウントB (Max Plan): kotaro, tobisaru, sasuke, kirimaru → ~/.claude-b/
```

---

## §4 副作用調査

### MCP Memory

- MCP設定は `settings.json` に格納（今回の調査では `settings.json` にMCPサーバー定義なし）
- MCP設定がプロジェクトの `.claude.json` にある場合 → CONFIG_DIR分離の影響なし
- MCP設定が `settings.json` にある場合 → CONFIG_DIR分離で設定が引き継がれない → コピー必要
- **Memory MCPのデータ自体**はMCPサーバー側に保存されるため、認証切替の影響なし

### プロジェクト設定

- `~/.claude/projects/` 配下のMEMORY.md等は認証非依存
- CONFIG_DIR分離時は `projects/` ディレクトリが別になるため、MEMORY.mdが共有されない
- **対策**: シンボリックリンクで共有するか、同一内容をコピー

### hooks/settings

- `settings.json` のpermissions, model, language設定はCONFIG_DIR依存
- CONFIG_DIR分離時は再設定が必要（またはコピー）

### inbox/watcher（我が軍のインフラ）

**影響箇所**: scripts/内で `~/.claude` を参照しているファイルは2つのみ

| ファイル | 参照箇所 | 影響 |
|----------|----------|------|
| `scripts/build_instructions.sh` | `~/.claude/` パス置換（6箇所） | CLI種別対応の処理。CONFIG_DIR分離の影響あり |
| `config/settings.yaml` | `save_path: "~/.claude/skills/"` | スキル保存先。CONFIG_DIR分離で不整合の可能性 |

**`CLAUDE_CONFIG_DIR` を参照しているスクリプト**: **0件**

**影響度**: 低。インフラスクリプト（inbox_write.sh, inbox_watcher.sh, ntfy.sh等）は `~/.claude` を直接参照していない。タスクYAML・inbox・dashboard等は全てプロジェクトディレクトリ(`/mnt/c/tools/multi-agent-shogun/queue/`)内で完結している。

---

## §5 Gistダッシュボードのマルチプロジェクト対応

### 現行構成

- 1 Gist URL: `https://gist.github.com/simokitafresh/6eb495d917fb00ba4d4333c237a4ee0c`
- 1ファイル: `dashboard.md`
- PJ切替で中身が変わる → 旧PJの戦果が見えなくなる

### gh gist のマルチファイル機能

| 操作 | コマンド | 対応 |
|------|---------|------|
| ファイル追加 | `gh gist edit <id> -a file.md` | **可能** |
| ファイル削除 | `gh gist edit <id> -r file.md` | **可能** |
| ファイル名変更 | `gh gist rename <id> old new` | **可能** |
| 特定ファイルのみ表示 | `gh gist view <id> -f file.md` | **可能** |
| スクリプトから非対話更新 | `gh api` でPATCH | **可能** |

### 対応案の比較

| 案 | 構成 | メリット | デメリット |
|----|------|----------|-----------|
| **A: 1 Gistにマルチファイル** | `dashboard-dm-signal.md`, `dashboard-mcas.md` 等 | URL1つで全PJ閲覧。Android Gist閲覧アプリで全ファイル一覧 | ファイルが増えると見にくくなる可能性 |
| B: PJ別Gist | PJごとに別Gist URL | PJ間の完全分離 | URL管理が煩雑。殿がAndroidで複数URLを管理する必要 |
| C: 1ファイル内セクション分け | `dashboard.md` 内に全PJセクション | 最もシンプル。URL・ファイル変更なし | ファイルが長くなる。スクロール量増加 |

### 推奨: 案A（1 Gistにマルチファイル）

**理由**:
1. **URL不変**: 殿のAndroidブックマークを変更不要
2. **GitHub Gist UIが自動でファイル一覧を表示**: タップ1つでPJ切替
3. **スクリプト対応が容易**: `gh gist edit <id> -a dashboard-{project}.md` で追加、更新はgh api PATCH
4. **切替時の実装**: PJ切替スクリプトで「旧PJのdashboard停止」「新PJのdashboard開始」が明確
5. **Gist内ファイルはアルファベット順表示**: 命名規則で表示順制御可能

**実装イメージ**:
```bash
# PJ切替時
# 1. 現PJのdashboard最終版をGistに保存
gh gist edit <gist_id> -a /tmp/dashboard-dm-signal.md

# 2. メインdashboard.mdを新PJの内容に更新
# （従来通りの更新フロー）

# 3. Gist上のファイル構成:
#   dashboard.md          ← 現在アクティブなPJ（常にメイン表示）
#   dashboard-dm-signal.md ← 過去PJのスナップショット
#   dashboard-mcas.md      ← 過去PJのスナップショット
```

**非対話的ファイル更新方法**（スクリプト向け）:
```bash
# gh api でPATCH（ファイル内容を直接指定）
gh api --method PATCH /gists/<gist_id> \
  -f "files[dashboard-dm-signal.md][content]=@/tmp/dashboard-dm-signal.md"
```
