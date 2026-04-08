# cmd_319: mcas OSS公開準備 調査結果

> 調査日: 2026-02-25 | 調査者: hanzo(偵察A), kotaro(偵察B)

## 差別化分析（14ツール調査）

### 主要競合（トップ層）

| ツール | Stars | 言語 | OS | カテゴリ |
|--------|-------|------|----|----------|
| ccusage | ~11,000 | TypeScript | 全OS | CLIログ分析(ローカルJSONL) |
| Claude-Code-Usage-Monitor | ~6,700 | Python | 全OS | ターミナル監視(ML予測) |
| CCS(kaitranntt) | ~1,200 | TS/Bun | 全OS | マルチプロバイダプロキシ |
| Claude-Usage-Tracker(hamed) | ~1,300 | Swift | macOS | メニューバー監視 |
| ccflare | ~872 | TypeScript | 全OS | 負荷分散プロキシ |

### mcas差別化5ポイント

1. **WSL2ネイティブ**: GUI系はmacOS偏重(Swift/SwiftUI)。WSL2ファーストは皆無
2. **マルチアカウント同時監視+切替統合**: 既存は「監視のみ」か「切替のみ」
3. **Android通知統合**: ntfy連携でWSL2→Androidリアルタイム通知。既存になし
4. **軽量シェルベース**: bash+Python。Node/Electron/Swift/Dockerより軽量
5. **tmux統合**: マルチエージェント環境との親和性

### 競合の空白地帯

- Anthropic公式マルチアカウント未提供(issue #261/#12810/#18435/#27359全open)
- macOS以外のGUI監視=electron系のみ（重い）
- WSL2+tmux最適化ツール=存在しない

## 配布方式比較（WSL2ユーザー視点）

| 基準 | pip/pipx | npm | curl\|bash | Homebrew | cargo |
|------|----------|-----|-----------|----------|-------|
| WSL2前提条件 | Python(組込) | Node(要導入) | curl,bash(組込) | brew(要導入) | Rust(要導入) |
| 導入ステップ(前提あり) | 1-2 | 1 | 1 | 1 | 1+待ち |
| bash+Python適合度 | 高い | 低い | 最高 | 高い | なし |

**推奨**: 主系統=pip/pipx、副系統=curl|bash (→PD-035)
注意: Ubuntu 24.04以降PEP 668でpip直接不可→pipx必須(→L004)

## Android通知方式比較

| 基準 | ntfy | Telegram Bot | PWA | GitHub Gist |
|------|------|-------------|-----|-------------|
| 送信側複雑度 | 極低(curl) | 低(curl) | 極高 | 低(curl) |
| 遅延 | <2秒 | <2秒 | 1-5秒 | ポーリングのみ |
| 既存利用 | あり | なし | なし | あり |

**推奨**: ntfy — 既存インフラ活用、curl依存のみ、自前ホスト可

## ライセンス

エコシステム実態: MIT 88% → **MIT推奨** (→PD-036)

## リポジトリ推奨構造

```
multi-claude-account-switcher/
├── scripts/              # Shell scripts (core)
├── src/                  # Python modules (advanced)
├── config/
│   └── config.example.yaml
├── tests/
├── docs/
├── .github/workflows/
├── README.md         ← 作成済み
├── LICENSE           ← 作成済み(MIT)
├── .gitignore        ← 作成済み
└── CONTRIBUTING.md   ← 作成済み
```

## セキュリティ考慮（公開禁止情報）

### .gitignore必須項目
- .credentials.json, *credentials*.json
- .env / .env.*, config/config.yaml, config/secrets.*
- *.key / *.pem, tokens.*, api_keys.*

### 絶対にコミットしない情報
- アカウントメールアドレス/OAuth tokens/ntfy topic名(private)/CLAUDE_CONFIG_DIR内credentials/殿の個人PFデータ

## 作成済みファイル

| ファイル | 内容 |
|----------|------|
| README.md | 概要/機能一覧/Quick Start/構造図 |
| LICENSE | MIT License (2026 simokitafresh) |
| .gitignore | 5セクション(Security/Python/Shell/IDE/Project) |
| CONTRIBUTING.md | Dev Setup/Code Style/Testing/PR Process |

## 未決裁定

- PD-035: 配布方式(pip/pipx主 推奨)
- PD-036: ライセンス(MIT 推奨)
