# cmd_317 偵察報告（Codex）: CLAUDE_CONFIG_DIR 仕様調査

- 実施日: 2026-02-25
- 担当: sasuke (codex)
- 対象: Claude Code `CLAUDE_CONFIG_DIR`

## 1. 結論（先出し）

1. 公式仕様としては、`CLAUDE_CONFIG_DIR` は「Claude Code の設定・データ保存先をカスタマイズする環境変数」と定義されている。
2. 公式ドキュメントは設定系の保存先として `~/.claude/`（settings.json 等）と `~/.claude.json`（MCP user/local, OAuth, project state, cache）を明示しており、未設定時のデフォルト実体はこのホーム配下である。
3. 影響範囲は少なくとも `settings.json`、`~/.claude.json`、MCP 設定、hooks 設定、各種データファイル（community reports では `.credentials.json`, `projects/`, `shell-snapshots/`）に及ぶ。
4. 既知の注意点として、過去バージョンで `CLAUDE_CONFIG_DIR` の適用漏れが複数報告されている（IDE lockfile, installation detection 等）。`CHANGELOG` には 1.0.6 で「Respect CLAUDE_CONFIG_DIR everywhere」と記録あり。

## 2. 公式仕様（primary source）

### 2.1 定義

- Settings ページの environment variables 表:
  - `CLAUDE_CONFIG_DIR`: "Customize where Claude Code stores its configuration and data files"

### 2.2 デフォルト値（未設定時）

- 公式は「default value」を明示数値/文字列で列挙していない。
- ただし同ページで次を明示:
  - User scope location: `~/.claude/`
  - Other configuration: `~/.claude.json`
- よって未設定時の実運用デフォルトはホーム配下（`~/.claude/` と `~/.claude.json`）と判断できる。

> 注: この項目は docs の保存先記述からの推論を含む。

### 2.3 設定可能な値と制約

- 公式上は「保存先をカスタマイズするディレクトリパス」であることのみ明示。
- 受け付け形式・相対パス可否・シンボリックリンク制約などの詳細仕様は公開ドキュメント上で限定的。

## 3. 影響範囲（credentials/settings/projects/MCP/hooks）

| 対象 | 公式/コミュニティ | 根拠 | 判定 |
|---|---|---|---|
| `settings.json` | 公式 | Settings files は `~/.claude/settings.json` / `.claude/settings.json` / `.claude/settings.local.json` | 影響あり |
| `settings.yaml` | 公式 | Claude Code settings の公式メカニズムは `settings.json` と明記。`settings.yaml` 記載なし | 公式サポート不明（少なくとも主経路ではない） |
| `MCP` | 公式 | `~/.claude.json`（user/local）と `.mcp.json`（project）に保存と明記 | 影響あり |
| `hooks` | 公式 | hooks 設定は `~/.claude/settings.json`, `.claude/settings.json`, `.claude/settings.local.json`, plugin `hooks/hooks.json` | 影響あり |
| `credentials.json` | コミュニティ + 公式定義 | Issue #3833 で `$CLAUDE_CONFIG_DIR` 配下の `.credentials.json` 実例。公式定義は「configuration and data files」 | 影響あり（公式の個別ファイル明示は限定的） |
| `projects/` | コミュニティ + 公式定義 | Issue #3833 で `$CLAUDE_CONFIG_DIR/projects/` 実例 | 影響あり（同上） |

## 4. 分離運用ユースケース（マルチアカウント/複数環境）

### 4.1 マルチアカウント運用

- 口座/用途ごとに保存先を分離:
  - 例: `CLAUDE_CONFIG_DIR=~/.claude-work` と `CLAUDE_CONFIG_DIR=~/.claude-personal`
- 期待効果:
  - OAuth セッション・MCP 構成・各種ローカル状態の混線抑止

### 4.2 開発/本番相当の分離

- 環境ごとに設定・状態を隔離:
  - 例: `~/.claude-dev`, `~/.claude-prod`
- 期待効果:
  - 実験的 hooks/MCP 設定を本番系へ誤混入しにくい

### 4.3 実務上の注意

- 既知不具合があったバージョン帯では、全機能が一貫して `CLAUDE_CONFIG_DIR` を参照しないケースが報告されている。
- 導入時は `/status`, `/mcp`, `/ide` など機能単位で挙動確認するのが安全。

## 5. 既知の制約・注意点（OSS issues/discussions）

| Issue | 状態 | 要点 |
|---|---|---|
| #1455 | open | デフォルトが `~/.claude` / `~/.claude.json` で XDG 非準拠という指摘 |
| #3833 | closed (2026-01-29) | `CLAUDE_CONFIG_DIR` 動作不明瞭・local `.claude/` 併存報告。本文に `.credentials.json`, `projects/`, `shell-snapshots/` 記載 |
| #4739 | closed (2026-01-31) | `/ide` が default `~/.claude/ide` と `$CLAUDE_CONFIG_DIR/ide` の不一致で検出失敗 |
| #2986 | closed (2025-12-10) | local installation detection が `CLAUDE_CONFIG_DIR` を無視する報告 |
| #2898 | closed (2025-09-04) | global `autoUpdates` 適用不整合報告（設定系の整合性論点） |
| #1414 | closed (2025-06-17) | `.credentials.json` のプラットフォーム差異（mac/linux）報告 |

補足:
- OSS `CHANGELOG.md` 1.0.6 に `Respect CLAUDE_CONFIG_DIR everywhere` の記録あり（過去に適用漏れが存在したことを示唆）。

## 6. 実装・運用上の推奨

1. `CLAUDE_CONFIG_DIR` は「起動前に」明示 export する（セッション途中変更は避ける）。
2. 分離先は絶対パスで固定し、環境ごとにディレクトリを分ける。
3. 初回導入時に以下を確認する:
   - `settings.json` 読み込み
   - `/mcp` の server 一覧
   - `/ide` 接続可否
   - 認証状態（再ログイン要否）
4. 旧バージョン運用中なら、上記 issue の再現有無を先に検証する。

## 7. 参照元

### 公式ドキュメント（primary）
- https://code.claude.com/docs/en/settings
- https://code.claude.com/docs/en/hooks
- https://code.claude.com/docs/en/mcp

### 公式 OSS（primary）
- https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md

### コミュニティ報告（補助）
- https://github.com/anthropics/claude-code/issues/1455
- https://github.com/anthropics/claude-code/issues/3833
- https://github.com/anthropics/claude-code/issues/4739
- https://github.com/anthropics/claude-code/issues/2986
- https://github.com/anthropics/claude-code/issues/2898
- https://github.com/anthropics/claude-code/issues/1414
