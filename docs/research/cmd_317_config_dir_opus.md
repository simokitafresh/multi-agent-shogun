# cmd_317: CLAUDE_CONFIG_DIR 環境変数 仕様調査（Opus偵察）

> 調査日: 2026-02-25 | 調査者: hayate | モデル: opus

---

## §1 基本仕様

### デフォルト値（未設定時）

| OS | デフォルトパス |
|----|--------------|
| macOS / Linux | `~/.claude/` |
| Windows | `%APPDATA%\Claude\` |

### 設定方法

```bash
export CLAUDE_CONFIG_DIR=/custom/path
# or
CLAUDE_CONFIG_DIR=/custom/path claude
```

### 公式ドキュメント記載

公式Settings docs (code.claude.com/docs/en/settings) に1行だけ記載:
> "Customize where Claude Code stores its configuration and data files"

**詳細仕様は未ドキュメント**。Issue #6531で文書化が要求されたが "not planned" でクローズ。

---

## §2 影響範囲

### CLAUDE_CONFIG_DIR が制御するファイル（リダイレクト対象）

| ファイル/ディレクトリ | 説明 |
|---------------------|------|
| `.credentials.json` | 認証トークン（Linux/Windows。macOSはKeychain） |
| `.claude.json` / `.claude.json.backup` | ユーザーMCPサーバー/プリファレンス/OAuth/状態キャッシュ |
| `settings.json` | ユーザーレベル設定 |
| `settings.local.json` | ユーザーローカル設定 |
| `CLAUDE.md` | ユーザーメモリ |
| `projects/` | プロジェクト別会話履歴・設定 |
| `shell-snapshots/` | シェルスナップショット |
| `statsig/` | 分析キャッシュ |
| `todos/` | タスクリスト |
| `history.jsonl` | コマンド履歴 |
| `agents/` | ユーザーレベルカスタムサブエージェント |
| `plans/` | プランファイル |

### CLAUDE_CONFIG_DIR が制御しないファイル（既知の例外）

| ファイル/ディレクトリ | 実際のパス | Issue |
|---------------------|-----------|-------|
| プロジェクトローカル `.claude/settings.local.json` | ワークスペース内 `.claude/` | #3833 |
| IDE連携ロックファイル | `~/.claude/ide/[port].lock` (ハードコード) | #4739 |
| plugins/marketplaces | `~/.claude/plugins/marketplaces/` (ハードコード) | #15071 |
| ユーザー設定の一部 | `~/.config/claude-code/` (skills, agents, commands) | #3833 |
| managed-settings.json | OS固有のシステムパス | 仕様通り |

### MCP設定への影響

- `~/.claude.json` 内のMCPサーバー設定 → **制御される**（`$CLAUDE_CONFIG_DIR/.claude.json`に移動）
- `.mcp.json`（プロジェクトスコープ） → **影響なし**（プロジェクトルートに固定）
- `managed-mcp.json` → **影響なし**（システムパスに固定）

### hooks設定への影響

- `~/.claude/settings.json` 内のhooks → **制御される**（settings.jsonごと移動）
- `.claude/settings.json`（プロジェクトレベル） → **影響なし**（プロジェクトルートに固定）

---

## §3 マルチアカウント運用

### 基本パターン（Shell Alias）

```bash
# ~/.bashrc or ~/.zshrc
alias claude-work="CLAUDE_CONFIG_DIR=~/.claude-work claude"
alias claude-personal="CLAUDE_CONFIG_DIR=~/.claude-personal claude"
alias claude="echo 'Use claude-work or claude-personal'"
```

### セットアップ手順

1. ディレクトリ作成: `mkdir ~/.claude-work ~/.claude-personal`
2. 各エイリアスで別々に認証: `claude-work` → ログイン、`claude-personal` → ログイン
3. 認証情報は各ディレクトリの `.credentials.json` に保存される
4. 同時並列実行可能（別ターミナルタブ）

### Windows (PowerShell)

```powershell
function claude-work { $env:CLAUDE_CONFIG_DIR="$env:USERPROFILE\.claude-work"; claude }
function claude-personal { $env:CLAUDE_CONFIG_DIR="$env:USERPROFILE\.claude-personal"; claude }
```

### WSL2環境

```bash
# WSL2では Linux ファイルシステム上に配置すること
export CLAUDE_CONFIG_DIR=/home/username/.claude-account2
# /mnt/c/ 上は非推奨（パフォーマンス問題）
```

### 分離の限界

| 項目 | 分離される | 分離されない |
|------|-----------|------------|
| credentials | ✅ | |
| settings | ✅ | |
| 会話履歴 | ✅ | |
| MCP設定 | ✅ | |
| IDEロックファイル | | ❌ (#4739) |
| plugins/marketplaces | | ❌ (#15071) |
| プロジェクトローカル設定 | | ❌ (ワークスペース内) |

---

## §4 開発/本番環境分離

### ユースケース

```bash
# 開発環境（個人アカウント、緩い権限）
alias claude-dev="CLAUDE_CONFIG_DIR=~/.claude-dev claude"

# 本番環境（企業アカウント、managed-settings適用）
alias claude-prod="CLAUDE_CONFIG_DIR=~/.claude-prod claude"
```

### 環境ごとの設定分離

- settings.json（許可ツール、モデル設定）が完全分離
- MCP接続先を環境ごとに変更可能
- managed-settings.jsonはOS固有パスに固定のため、環境分離には使えない

---

## §5 既知の制約・注意点

### バグ・不整合（GitHub Issues）

| Issue | 状態 | 概要 |
|-------|------|------|
| [#3833](https://github.com/anthropics/claude-code/issues/3833) | Closed (not planned) | 挙動不明確。プロジェクトローカル `.claude/` が依然作成される |
| [#4739](https://github.com/anthropics/claude-code/issues/4739) | Closed (not planned) | `/ide`コマンドがCLAUDE_CONFIG_DIRを無視 |
| [#6531](https://github.com/anthropics/claude-code/issues/6531) | Closed (duplicate) | ドキュメント未記載 |
| [#15071](https://github.com/anthropics/claude-code/issues/15071) | Closed (duplicate of #972) | plugins/marketplacesがハードコード |
| [#23676](https://github.com/anthropics/claude-code/issues/23676) | Closed (duplicate) | Agent Teamsが親のCLAUDE_CONFIG_DIRを継承しない |
| [#25762](https://github.com/anthropics/claude-code/issues/25762) | Open | 機能リクエスト（正式サポート要望） |

### 重要な注意事項

1. **`.claude.json`の配置が変わる**: 未設定時は`~/.claude.json`（`~/.claude/`の外）、設定時は`$CLAUDE_CONFIG_DIR/.claude.json`（内部）
2. **Agent Teamsの非継承**: 子エージェントにCLAUDE_CONFIG_DIRが伝播しない → タスクリスト共有が壊れる
3. **XDG非準拠**: 名前はconfig dirだが実態はstate dir。設定と状態が混在
4. **Windows特有**: `~/.claude.json`（グローバルstate）がCLAUDE_CONFIG_DIRと別に存在し干渉する可能性

### コミュニティ提案（Issue #3833, @graelo）

- `CLAUDE_CONFIG_DIR` → `CLAUDE_STATE_DIR` にリネーム
- XDG準拠: `~/.config/claude-code/`（設定）と `~/.local/state/claude-code/`（状態）に分離
- 現時点で未採用

---

## §6 我々の環境(multi-agent-shogun)への示唆

### mcas (multi-claude-account-switcher) との関連

CLAUDE_CONFIG_DIRはmcasの核心技術。アカウント切替の実現手段そのもの。

### 現在の我々の使い方

- 将軍CLIは `~/.claude/`（デフォルト）を使用
- mcasがCLAUDE_CONFIG_DIRでアカウント別ディレクトリを切り替える構想

### 注意すべき制約

1. Agent Teams非継承 → マルチエージェント運用ではCLAUDE_CONFIG_DIRの伝播を自前で保証する必要あり
2. IDE連携・pluginsのハードコード → 完全分離にはシンボリックリンク等のワークアラウンドが必要
3. managed-settingsは環境固定 → 企業ポリシーの環境別適用は不可

---

## 調査ソース

- [公式Settings docs](https://code.claude.com/docs/en/settings)
- [Issue #3833: 挙動不明確](https://github.com/anthropics/claude-code/issues/3833)
- [Issue #4739: /ide不具合](https://github.com/anthropics/claude-code/issues/4739)
- [Issue #6531: ドキュメント要望](https://github.com/anthropics/claude-code/issues/6531)
- [Issue #15071: plugins非対応](https://github.com/anthropics/claude-code/issues/15071)
- [Issue #23676: Agent Teams非継承](https://github.com/anthropics/claude-code/issues/23676)
- [Issue #25762: 正式サポート要望](https://github.com/anthropics/claude-code/issues/25762)
- [Gist: マルチアカウント設定](https://gist.github.com/KMJ-007/0979814968722051620461ab2aa01bf2)
- [@JacquesThibs: マルチアカウント運用](https://x.com/JacquesThibs/status/1946412707995140347)
