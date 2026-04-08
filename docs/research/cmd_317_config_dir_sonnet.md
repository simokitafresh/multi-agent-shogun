# CLAUDE_CONFIG_DIR 仕様調査

| meta | value |
|------|-------|
| cmd | cmd_317 Phase1 |
| 担当 | tobisaru (Sonnet) |
| 日付 | 2026-02-25 |
| 目的 | CLAUDE_CONFIG_DIR環境変数の仕様調査（マルチアカウント運用での活用） |

---

## §1 CLAUDE_CONFIG_DIR の基本仕様

### デフォルト値

| 状態 | パス |
|------|------|
| 未設定時 (現行) | `~/.claude/` |
| v1.0.30以前の旧path | `~/.config/claude/` (legacy; ccusageは両方を自動検索) |

### 設定方法

```bash
# シェルプロファイル（永続）
export CLAUDE_CONFIG_DIR="/path/to/custom/config"

# コマンドライン（一時）
CLAUDE_CONFIG_DIR="/path/to/config" claude

# エイリアス（アカウント切替用）
alias claude-work="CLAUDE_CONFIG_DIR=~/.claude-work claude"
alias claude-personal="CLAUDE_CONFIG_DIR=~/.claude-personal claude"
```

### 制約

- 公式ドキュメント（docs.anthropic.com/settings, cli-reference）への**記載なし**（未文書化）
- 実装は存在するが仕様保証なし → バージョンアップで動作変化の可能性あり

---

## §2 影響範囲

### ✅ CLAUDE_CONFIG_DIR で移動されるファイル

| ファイル/ディレクトリ | 内容 | 備考 |
|---------------------|------|------|
| `settings.json` | グローバルユーザー設定 | 全PJに適用 |
| `settings.local.json` | マシン固有設定 | 非同期 |
| `CLAUDE.md` | グローバル指示 | 全PJに自動ロード |
| `.credentials.json` | API認証情報 | **Linux/Windowsのみ**。macOSはKeychain |
| `projects/` | セッション履歴 | エンコードされたPJパスで整理 |
| `statsig/` | アナリティクスキャッシュ | |
| `commands/` | カスタムスラッシュコマンド | |
| `.claude.json` | ユーザースコープMCP設定 | `$CLAUDE_CONFIG_DIR/.claude.json` に移動 |
| OAuth sessions | 認証セッション | macOS Keychain問題あり → §4参照 |

### ⚠️ CLAUDE_CONFIG_DIR で移動されない（プロジェクトローカル）

| ファイル/ディレクトリ | 内容 | 備考 |
|---------------------|------|------|
| `./.claude/settings.local.json` | PJ固有ローカル設定 | ワークスペース内に作成され続ける |
| `./.claude/ide` | IDE統合フォルダー | CLAUDE_CONFIG_DIR設定後も作成 |
| `./.mcp.json` | PJスコープMCP設定 | プロジェクトディレクトリ内 |

**重要**: CLAUDE_CONFIG_DIRは「全ての`.claude/`ディレクトリを集約する」わけではない。
グローバル設定のみ移動。各ワークスペースのローカル`.claude/`は引き続き個別に作成される。

### MCP設定の影響範囲まとめ

| MCP設定スコープ | 保存先 | CLAUDE_CONFIG_DIRの影響 |
|--------------|--------|----------------------|
| ユーザースコープ | `~/.claude.json` | ✅ `$CLAUDE_CONFIG_DIR/.claude.json` に移動 |
| PJローカルスコープ | `./.claude/settings.local.json` | ❌ 移動されない |
| PJスコープ | `./.mcp.json` | ❌ 移動されない |

### Hooks設定

- hooks はユーザースコープの `settings.json` に記載 → ✅ CLAUDE_CONFIG_DIR で移動される
- PJスコープ hooks は `./.claude/settings.json` → ❌ 移動されない

---

## §3 マルチアカウント運用での活用

### 基本パターン（Linux/Windows推奨）

```bash
# ~/.bashrc または ~/.zshrc に追加
alias claude-account1="CLAUDE_CONFIG_DIR=~/.claude-account1 claude"
alias claude-account2="CLAUDE_CONFIG_DIR=~/.claude-account2 claude"

# 初回: 各アカウントで別々にlogin
CLAUDE_CONFIG_DIR=~/.claude-account1 claude auth login  # account1
CLAUDE_CONFIG_DIR=~/.claude-account2 claude auth login  # account2
```

### ディレクトリ構造例（2アカウント）

```
~/.claude-account1/
├── .credentials.json   ← account1の認証情報
├── settings.json       ← account1の設定
├── CLAUDE.md           ← account1のグローバル指示
└── projects/           ← account1のセッション履歴

~/.claude-account2/
├── .credentials.json   ← account2の認証情報
├── settings.json       ← account2の設定
└── projects/
```

### 我が軍（multi-agent-shogun）への適用

- **現在の実装** (`cmd_314`): `claude auth logout` → `claude auth login` で全体切替
- **CLAUDE_CONFIG_DIR方式の利点**: ログアウト不要。alias切替で即時起動可能
- **前提**: 各エージェントのtmuxペインで `CLAUDE_CONFIG_DIR` を個別に設定すれば、ペインごとに別アカウントで動作可能
- **手順**: `tmux set-environment CLAUDE_CONFIG_DIR ~/.claude-account2` → CLI再起動

---

## §4 既知の制約・注意点

### 🚨 Critical: macOS Keychain OAuth衝突バグ (Issue #20553)

**症状**: macOSで複数アカウント使用時、約8時間後に両アカウントがOAuthエラーで再ログイン要求

**原因**: Keychainのサービス名がハードコード (`Claude Code-credentials`)。
CLAUDE_CONFIG_DIRでnamespace化されていないため、アカウント2がアカウント1のトークンを上書き。

```
Error: 401 {"type":"error","error":{"type":"authentication_error","message":"OAuth token has expired..."}}
```

**ステータス**: v2.1.19時点でオープン。`stale`ラベル付き。

**影響範囲**: **macOS限定**。Linux/Windowsは`.credentials.json`で分離されるため影響なし。

**WSL2の場合**: Linux動作のため`.credentials.json`ベースの分離が有効。macOS Keychainは使用しない。
→ **我が軍（WSL2）はこのバグの影響を受けない**

### ⚠️ 注意点一覧

| # | 問題 | 影響 | 回避策 |
|---|------|------|--------|
| 1 | **公式未文書化** | 仕様変更リスク | バージョン固定 or 定期確認 |
| 2 | **`.claude.json`位置の非一貫性** | 未設定時は `~/.claude.json`（ディレクトリ外）。設定時は`$CLAUDE_CONFIG_DIR/.claude.json`（ディレクトリ内） | v2.0.42-74以降で修正の可能性あり |
| 3 | **IDE統合破損** | `/ide`コマンドが失敗する場合あり | IDE使用時はCLAUDE_CONFIG_DIR未設定を推奨 |
| 4 | **PJローカル`.claude/`は分離不可** | 複数アカウントで同一PJを操作すると`.claude/settings.local.json`が共有 | PJディレクトリを分けるか許容する |
| 5 | **macOS Keychain衝突** | OAuthトークン上書き（§4参照） | Linux/WSL2使用 or CCS(サードパーティ)使用 |

### 代替ツール（参考）

- **CCS (Claude Code Switch)**: CLAUDE_CONFIG_DIRの上に構築。プロファイル管理UI付き。macOS Keychain問題に対処
  - URL: https://ccs.kaitran.ca/

---

## §5 まとめ（結論）

| 観点 | 結論 |
|------|------|
| デフォルト値 | `~/.claude/` |
| 主な用途 | グローバル設定の分離（認証・settings・CLAUDE.md・セッション履歴） |
| マルチアカウント有効性 | **Linux/WSL2: 有効**（`.credentials.json`で分離）。macOS: Keychainバグあり |
| 我が軍への適用性 | WSL2環境なのでClaude_CONFIG_DIR方式が有効。alias + CLAUDE_CONFIG_DIR でペインごとアカウント分離可能 |
| 主要リスク | 未文書化のため仕様変更リスク。IDE統合が壊れる可能性 |

---

## 参考リンク

- [Claude Code Settings公式](https://code.claude.com/docs/en/settings)
- [Issue #3833: CLAUDE_CONFIG_DIR動作が不明確](https://github.com/anthropics/claude-code/issues/3833)
- [Issue #20553: macOS Keychain OAuth衝突バグ](https://github.com/anthropics/claude-code/issues/20553)
- [マルチアカウント管理Gist](https://gist.github.com/KMJ-007/0979814968722051620461ab2aa01bf2)
- [Jacques on X: マルチアカウントalias設定](https://x.com/JacquesThibs/status/1946412707995140347)
