# Claude Code / Agent SDK / Agent Teams

> Anthropic公式のAIコーディングアシスタント兼マルチエージェントフレームワーク。CLI・デスクトップアプリ・IDE拡張機能で提供。Agent SDKでプロダクション自動化も可能。

## Basic Info

| 項目 | 値 |
|------|-----|
| Author | Anthropic |
| Status | 本番稼働(GA)。Agent Teams は実験的(デフォルト無効) |
| Stars | 115,000(GitHub, 2026-04-18時点) |
| Forks | 19,300 |
| CLI Version | v2.1.114 (2026-04-18) |
| Agent SDK (Python/TS) | v0.1.59 |
| Repo | https://github.com/anthropics/claude-code |
| License | Anthropic Commercial Terms of Service |
| Docs | https://code.claude.com/docs/en/overview |

## Design Philosophy

**「プラットフォームが協調プリミティブを提供する」**

- CLIツールでありながらSDK化しプロダクション自動化に対応する二刀流設計
- コンテキスト管理をプラットフォーム側が担う（CLAUDE.md, MCP, Skills）
- 並列エージェント協調はAgent Teamsで実現。ただしチームリードが統括する中央集権型
- セキュリティを設計レベルで組み込む（PID namespace isolation, credential scrubbing, sandbox設定）
- 複数のデプロイ先に同一エージェントを展開（CLI/Desktop/IDE/Web/Cloud）

## Architecture

### エージェント構造

| 層 | 役割 |
|---|---|
| Team Lead (session) | タスク割り当て・調整・結果統合 |
| Teammates (parallel) | 独立したコンテキストウィンドウで並列実行 |
| Subagents | チームリード内でのサブタスク委譲 |
| Shared Task List | 全エージェントが読み書きできる協調層 |

### 通信方式

- Agent Teams: Shared Task List + ピアツーピア直接通信（チームリード経由不要）
- Agent SDK: Sessions API（マルチターン会話・状態保持・フォーク対応）
- Hooks: PreToolUse / PostToolUse / Stop / SessionStart / SessionEnd / UserPromptSubmit

### 記憶

| 種別 | 仕組み |
|---|---|
| プロジェクト記憶 | CLAUDE.md（自動ロード） |
| セッション記憶 | Recap機能・Checkpoint自動保存 |
| 永続記憶 | MCP Memory（外部システム連携） |
| スキル | ~/.claude/skills/ 以下のMarkdown定義 |

### 品質保証

- Checkpoint system: 変更前に自動保存、Esc×2または`/rewind`で即時巻き戻し
- `/ultrareview`: 複数エージェントが並列でコードレビュー
- Permissions: ツールアクセス制御（allow/block/approval要求）
- `sandbox.network.deniedDomains`: ネットワーク制限設定

## Key Features

| 機能名 | 説明 | 導入バージョン |
|--------|------|--------------|
| Ultraplan | クラウドで下書き作成→Webエディタでレビュー→ローカル/リモート実行 | Early Preview |
| Computer Use | ターミナルからネイティブアプリを操作・クリック・確認 | Research Preview |
| Checkpoint / Rewind | 変更前の自動スナップショット + Esc×2即時巻き戻し | v2.1.108 |
| Monitor tool | バックグラウンドイベントをストリーム・ログをtail・ライブ反応 | v2.1.x |
| Agent Teams | 複数Claude Codeインスタンスの並列協調（実験的） | 実験的 |
| 1hプロンプトキャッシュ | `ENABLE_PROMPT_CACHING_1H`環境変数で有効化 | v2.1.x |
| NO_FLICKERレンダリング | チラつきゼロのUI描画エンジン | v2.1.x |
| Focus View | タスク集中モード | v2.1.x |
| Writeツール60%高速化 | ファイル書き込み処理の速度改善 | v2.1.113 |
| Opus 4.7 対応 | `/effort`チューニング付き最新モデル | v2.1.111 |
| 1M context window GA | Claude Opus 4.6で100万トークン対応 | v2.1.x |
| PowerShellツール | Windows向け段階的ロールアウト（opt-in/out可能） | v2.1.x |
| `/ultrareview` | 包括的な並列マルチエージェントコードレビュー | v2.1.x |
| `/team-onboarding` | チームセットアップを再実行可能ガイドにパッケージング | v2.1.x |
| Sidebar | 全アクティブ・過去セッションの表示・ステータス/プロジェクト/環境でフィルタ | v2.1.x |
| Named sub-agents | サブエージェントに名前を付与して管理 | v2.1.x |
| Tool Decorator | `@tool`デコレータ + `typing.Annotated`でパラメータ説明付与 (SDK) | v0.1.x |

## Changelog since 2026-03-13

| 日付 | バージョン | 変更 | 影響 |
|------|-----------|------|------|
| 2026-04-18 | v2.1.114 | 最新安定版 | 本番利用 |
| 2026-04-17 | v2.1.113 | セキュリティ強化(PID namespace isolation/Credential scrubbing/PowerShell hardening)、Writeツール60%高速化、ネイティブバイナリをプラットフォーム別optional dependencyで配布 | セキュリティ・速度向上 |
| 2026-04-16 | v2.1.111 | Opus 4.7(claude-opus-4-7)サポート。Agent SDK v0.2.111以降が必要 | 最新モデル利用可能 |
| 2026-04-15 | v2.1.110 | 安定性改善 | 品質改善 |
| 2026-04-14 | v2.1.108 | Checkpoint/Rewind機能 | 変更の即時巻き戻し |
| ~2026-03 | v2.1.x | Computer Use(Research Preview)、Ultraplan(Early Preview)、Monitor tool | 新機能プレビュー |
| ~2026-03 | v2.1.x | 1hプロンプトキャッシュTTL、Recap機能、Sidebar | 操作性向上 |
| ~2026-03 | v2.1.x | `/ultrareview`、`/team-onboarding`、Named sub-agents | チーム開発強化 |
| ~2026-03 | v2.1.x | Ctrl+A/E/Backspace/U キーバインド追加、Fullscreenモード | キーボード操作改善 |
| ~2026-03 | v2.0.x | Homebrew公式配布、WinGet配布、Desktop App(macOS/Windows) | インストール多様化 |

## Notable Techniques

| テクニック名 | 説明 | このシステム固有か |
|-------------|------|-----------------|
| CLAUDE.md索引層 | パッシブコンテキスト自動ロード。Vercel AGENTS.md設計を採用 | 否。Vercel提唱、GSD・おしお殿でも類似実装 |
| MCP (Model Context Protocol) | 外部システム(DB/ブラウザ/API)への標準接続インターフェース | Anthropic提唱。他システムも採用中 |
| Hooks (Pre/PostToolUse) | ツール実行前後にカスタムコードを注入 | Claude Code独自の実装。他システムは類似機能を別方法で実現 |
| Skills (Markdown定義) | 再利用可能な能力をMarkdownで定義・配布 | 類似: gstackのSKILL.md。WHY/WHEN/NOT WHEN形式 |
| Checkpoint / Rewind | ファイル変更前の自動スナップショット | Claude Code独自。GSDのCONTEXT.mdバックアップとは異なる |
| Permissions API | ツールへのアクセスをAllow/Block/Approval要求で制御 | Claude Code独自の粒度。sandboxレベルの設定も可能 |
| Agent Teams (実験的) | Shared Task List + ピアツーピア通信による並列エージェント協調 | Claude Code独自。我が軍のYAML+inbox方式と異なるアプローチ |
| Sessions + Fork | コンテキストを保持しながらセッションを分岐・再開 | Claude Code独自。会話の非線形管理 |
| Tool Decorator (@tool) | `@tool`デコレータでカスタムツールを定義。Annotated型でパラメータ説明付与 | SDK固有 |
| Context Usage Monitoring | `get_context_usage()`でカテゴリ別のコンテキスト消費量を取得 | SDK固有 |

## Ecosystem

### コミュニティ

- GitHub Stars: 115,000 (急成長中)
- 公式ドキュメント: code.claude.com/docs
- Anthropic Engineering Blog: 実装事例・設計解説を掲載

### 統合先

| 種別 | 内容 |
|------|------|
| IDE | VS Code拡張、JetBrains(IntelliJ/PyCharm/WebStorm等) |
| Cloud | Amazon Bedrock、Google Vertex AI、Microsoft Azure AI Foundry |
| Desktop | macOS(Intel/Apple Silicon)、Windows(x64/ARM64) |
| Web | ブラウザ版(ローカル環境不要) |
| CI/CD | GitHub Actions連携、`/autofix-pr`でPR自動修正 |

### 実装事例

- **C言語コンパイラ**: 16エージェント、~2,000セッション、$20,000 API費用。100,000行のコンパイラでLinux 6.9をx86/ARM/RISC-Vでビルド成功。（Anthropic Engineering記事, 2026）

### 記事

- Anthropic Engineering: https://www.anthropic.com/engineering/building-c-compiler
- Builder.io Claude Code Updates: https://www.builder.io/blog/claude-code-updates

## Pitfalls

| 落とし穴 | 何が問題か | どこで表面化するか |
|---------|-----------|------------------|
| Agent Teams を一般提供済みの安定機能とみなす | 文書上でも実験的・デフォルト無効であり、共有タスクリストや直接通信の仕様は変わりうる | Teams導入を前提に運用設計した時 |
| Checkpoint / Rewind を品質保証そのものと誤解する | 巻き戻しは変更安全性を高めるが、仕様適合やテスト通過までは保証しない | 修正後の検証を省略した時 |
| SDK/CLI/Desktop/IDE を同一機能集合だと思い込む | Claude Codeは複数面に展開しているが、Computer Use・Teams・Monitor などは提供面や成熟度が揃わない | 配布面を跨いで同じ手順を流用した時 |
| 高速リリースを追うだけでバージョン検証を省く | v2.1.x の更新頻度が高く、セキュリティや機能差分が短期間で変わるため、古い前提が崩れやすい | 既知手順を長期間据え置いた時 |

## Cross-References

| 軸 | 対象 | 関係 |
|----|------|------|
| 補完 | [vercel](vercel.md) | Claude Codeが実行主体なら、Vercelは受動的知識供給・sandbox・gatewayで周辺基盤を補う |
| 競合 | [gstack](gstack.md) | どちらも複数エージェント協調を扱うが、Claude Codeは製品機能、gstackはskills主導の運用フレームとして競合する |
| 前提 | [oshio](oshio.md) | multi-agent-shogun は CLAUDE.md・hooks・skills・MCP といった Claude Code の概念を主要前提として組んでいる |

## Sources

| 種別 | URL |
|------|-----|
| Repository | https://github.com/anthropics/claude-code |
| Documentation | https://code.claude.com/docs/en/overview |
| Agent SDK Docs | https://code.claude.com/docs/en/agent-sdk/overview |
| Agent Teams Docs | https://code.claude.com/docs/en/agent-teams |
| What's New | https://code.claude.com/docs/en/whats-new |
| GitHub Releases | https://github.com/anthropics/claude-code/releases |
| Anthropic Blog | https://www.anthropic.com/engineering |

## Verification

- verified_at: 2026-04-19
- method: WebSearch("Claude Code 2026 changelog update") + WebFetch(GitHub releases, 公式ドキュメント, Anthropic Engineering)
- source: github.com/anthropics/claude-code/releases, code.claude.com/docs/en/whats-new, code.claude.com/docs/en/agent-teams, www.anthropic.com/engineering/building-c-compiler
