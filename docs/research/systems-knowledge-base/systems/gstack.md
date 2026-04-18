# gstack

> Garry Tan(YC CEO)作。Claude Codeを23専門ロール×Markdownスキルで"バーチャルソフトウェアファクトリー"に変換。6スキル(v0.0.2)から1年未満で75k+ stars・23スキル・v1.0に達した高速進化OSS。

## Basic Info

| 項目 | 内容 |
|------|------|
| Author | Garry Tan (Y Combinator President & CEO) |
| Status | OSS 本番稼働・高速進化中 |
| Stars | 75,800+(前回調査 2026-03-13時点: 414) |
| Forks | 10,800+ |
| Version | v1.0.0.0 (2026-04-18) |
| Last Commit | 2026-04-18 |
| Repo | https://github.com/garrytan/gstack |
| License | MIT |

## Design Philosophy

**「1人でチーム20人分をship」**

Garry Tanの核心：AIコーディング速度で製品を出し続けるには、ロールを明示した認知モード切替が必要。

- **Sprint Process強制**: Think → Plan → Build → Review → Test → Ship → Reflect の各フェーズを分離。LLMが1セッションで全役割を担うと"planning is not review"が崩れる。
- **810×の生産性**: Tan自身が2013年比で810倍(論理的コード変更換算)を報告。「2013年のペースに私は決して戻れない」
- **"Browser is the nervous system, skills are the product"**: ブラウザ自動化を基盤に全スキルが乗る。
- **"fork it, improve it, make it yours"**: MIT OSS。個人最適化を前提とした設計。コミュニティPRを積極統合。

v0.0.2時点の「認知モード切替」哲学は維持しつつ、v1.0では：
- チーム利用（Team Mode）を正式サポート
- 10 AI platformへのマルチホスト展開
- 自己改善ループ（Project Learnings System）を追加
- セキュリティ・DX観点を専門スキルに昇格

## Architecture

### Sprint Process（Think→Ship→Reflect）

```
Claude Code (or 10 other hosts)
  → gstack Skills (23 Markdown slash commands)
    → Specialized Role per Phase:
        /plan-ceo-review   — CEO: 前提検証・スコープ問い直し
        /plan-eng-review   — EM: アーキテクチャ・データフロー固定
        /plan-design-review — Designer: UX/UI意思決定
        /review            — Staff Engineer: 本番バグ検出 (+ Review Army: 7並列)
        /qa                — QA Lead: 実ブラウザテスト・修正
        /ship              — Release Eng: テスト・マージ・デプロイ管理
        /retro             — EM: メトリクス分析・学習蓄積
    → Persistent Playwright Browser Daemon (Bun, port 9400)
```

### Multi-Host Support (v0.15.6.0以降)

| ホスト | 対応状況 |
|--------|---------|
| Claude Code | デフォルト |
| OpenAI Codex CLI | 公式サポート |
| OpenClaw | ネイティブスキル4本(ClawHub公開) |
| Cursor / Factory Droid / Slate / Kiro / Hermes / GBrain | v0.18.0.0 以降 |

### 通信方式

- **スキル内**: Markdownプロンプト。Claude Codeのスキルディスカバリ機構に乗る
- **ブラウザ**: CLI → HTTP POST localhost:9400 → Bun.serve → Playwright API
- **マルチエージェント**: `/pair-agent`でスコープ付きトークン+レート制限+活動帰属

## Key Features

| 機能名 | 説明 | 導入バージョン |
|--------|------|--------------|
| `/plan-ceo-review` | 前提検証・10-star product問い | v0.0.1 |
| `/plan-eng-review` | アーキテクチャ固定・構築可能性検証 | v0.0.1 |
| `/review` | 本番バグ検出(CRITICAL/INFO 2-pass) | v0.0.1 |
| `/ship` | 非インタラクティブ全自動リリース | v0.0.1 |
| `/browse` | Playwright永続daemonによるブラウザ操作 | v0.0.1 |
| `/retro` | メトリクス分析・week-over-week比較 | v0.0.1 |
| `/plan-design-review` | UX/UIデザイン観点レビュー | v0.0.x |
| `/design-html` | モックアップ→本番HTML生成(Pretext) | v0.14.0.0 |
| `/design-shotgun` | 4-6バリアント並列生成+比較ボード | v0.14.x |
| `/cso` | OWASP Top10 + STRIDEセキュリティ監査 | v0.x |
| `/investigate` | 根本原因デバッグ(6フェーズ) | v0.x |
| `/learn` | Project Learningsシステム(信頼度スコア付き) | v0.13.6.0 |
| `/plan-devex-review` | 8次元DXスコアリング | v0.15.3.0 |
| `/devex-review` | 競合ベンチマーク+魔法の瞬間設計 | v0.15.5.0 |
| Session Intelligence | セッションタイムライン・コンテキスト復元 | v0.15.0.0 |
| Review Army | 7並列専門家レビュー(JSONスキーマ+指紋dedup) | v0.14.4.0 |
| Team Mode | `./setup --team`でリポジトリ共有・自動更新 | v0.15.13.0 |
| Browser Data Platform | scrape/media/data/download/archive | v0.16.0.0 |
| `/plan-tune` | 繰返し質問学習・ユーザー設定記憶 | v0.19.0.0 |
| Confusion Protocol | 高ステークス決定の曖昧さゲート | v0.18.0.0 |
| `/pair-agent` | マルチエージェント同一サイト並列操作 | v0.x |
| `/careful` / `/freeze` / `/guard` | 破壊的操作防止 | v0.x |
| Composable Skills | `{{INVOKE_SKILL}}`でスキル間呼び出し | v0.13.9.0 |

## Changelog since 2026-03-13

| 日付 | バージョン | 変更 | 影響 |
|------|-----------|------|------|
| 2026-03-29 | v0.13.6.0 | Project Learningsシステム、信頼度スコア付き学習管理 | 自己改善ループ追加 |
| 2026-03-29 | v0.13.9.0 | Composable Skills: `{{INVOKE_SKILL}}`リゾルバ | スキル間構成可能に |
| 2026-03-30 | v0.14.0.0 | `/design-html`スキル: Pretextモックアップ→コード | デザイン→実装直結 |
| 2026-03-30 | v0.14.2.0 | Sidebar CSS Inspector: ライブスタイル編集+LLM | リアルタイムデザイン修正 |
| 2026-03-31 | v0.14.3.0 | 常時オン対立的レビュー、スコープドリフト検出 | レビュー品質向上 |
| 2026-03-31 | v0.14.4.0 | Review Army: 7並列専門家・JSONスキーマ・指紋dedup | レビュー体制強化 |
| 2026-03-31 | v0.14.6.0 | 再帰的自己改善: 運用学習システム、トップ3学習をプリアンブルに | 知識の永続化 |
| 2026-04-01 | v0.15.0.0 | Session Intelligence: `/checkpoint` `/health`スキル | CTX復元・予測提案 |
| 2026-04-03 | v0.15.3.0 | `/plan-devex-review` `/devex-review` (8次元DXスコア) | DX評価の専門化 |
| 2026-04-04 | v0.15.5.0 | Interactive DX Review: 競合ベンチマーク+魔法の瞬間設計 | DX品質強化 |
| 2026-04-04 | v0.15.6.0 | 宣言的マルチホストプラットフォーム(8ホスト) | Claude Code以外へ展開 |
| 2026-04-05 | v0.15.7.0 | Security Wave 1: 14修正(ローカルホスト縛り/パストラバーサル等) | セキュリティ強化 |
| 2026-04-05 | v0.15.8.0 | Smarter Reviews: クロスレビューdedup、適応的専門家ゲーティング | レビュー精度向上 |
| 2026-04-05 | v0.15.10.0 | OpenClaw: 4スキルをClawHubに公開 | エコシステム拡張 |
| 2026-04-04 | v0.15.13.0 | Team Mode: `./setup --team`、セッションベース自動更新 | チーム利用正式対応 |
| 2026-04-06 | v0.15.15.0 | コミュニティセキュリティwave: 8PR・クッキー値リダクション | セキュリティ民主化 |
| 2026-04-07 | v0.16.0.0 | Browser Data Platform: media/data/download/scrape/archive | ブラウザ→データ基盤 |
| 2026-04-08 | v0.16.1.0 | Cookie picker auth token セキュリティ修正(CVSS 7.8) | クリティカル脆弱性対応 |
| 2026-04-13 | v0.16.4.0 | Cookie origin固定、コマンド監査ログ、14セキュリティ修正 | エンタープライズ強化 |
| 2026-04-14 | v0.17.0.0 | UX行動的基盤、6ユーザビリティテスト、`$B ux-audit` | UXテスト自動化 |
| 2026-04-15 | v0.18.0.0 | Confusion Protocol、Hermesホスト、GBrain統合 | マルチホスト拡大 |
| 2026-04-17 | v0.18.3.0 | Windows cookieインポート、OpenCode 1コマンドインストール | Windows対応強化 |
| 2026-04-17 | v0.19.0.0 | `/plan-tune`: 繰返し質問学習、ビルダーアーキタイプ | 個人適応化 |
| 2026-04-18 | v1.0.0.0 | v1プロンプト簡略化、技術glossy注釈、簡潔モード、/retroメトリクス改善 | メジャーバージョン到達 |

## Notable Techniques

| テクニック名 | 説明 | このシステム固有か |
|-------------|------|-----------------|
| Suppressions（偽陽性抑制） | 9項目の「報告不要」リストでLLMレビューの偽陽性を制御 | 固有(gstack発祥) |
| 停止条件の二分法 | `stop_for`/`never_stop_for`で過剰確認を構造的排除 | 固有(我が軍に導入済) |
| 「判断を述べよ、メニューを出すな」 | `"I'm paying for your judgment, not a menu."` | 固有(我が軍に導入済) |
| モードコミットメント | SCOPE EXPANSION/HOLD/REDUCTION の3モード+ドリフト防止 | 固有 |
| 反復STOP | 全セクション末尾に同一STOP指示を11回繰り返し | 固有 |
| Priority Hierarchy | 不等号表記で優先順位を視覚的に定義 | 固有(我が軍に導入済) |
| Engineering Preferences | 6判断基準をプロンプトに事前注入 | 固有(我が軍に導入済) |
| Two-pass Review | CRITICAL(ship停止)/INFORMATIONAL(PR本文)の2分類 | 固有 |
| @ref要素選択 | AXTree ariaSnapshot → @e1/@e2 refでDOM非改変 | Vercelと同技術 |
| Review Army | 7並列専門家レビュー + 指紋ベースdedup | 固有(v0.14.4以降) |
| Project Learnings | 信頼度スコア付き学習・30日減衰・クロスプロジェクト参照 | 固有(v0.13.6以降) |
| Confusion Protocol | 高ステークス決定の曖昧さゲート(v0.18.0以降) | 固有 |
| Composable Skills | `{{INVOKE_SKILL}}`でスキル間パラメータ呼び出し | 固有(v0.13.9以降) |
| Session Intelligence | セッションタイムライン+コンテキスト復元+スキル予測提案 | 固有(v0.15.0以降) |

## Ecosystem

| カテゴリ | 内容 |
|---------|------|
| コミュニティ | Stars 75.8k、Forks 10.8k。コミュニティPRを積極統合(セキュリティwave 8PR等) |
| ClawHub | OpenClawプラットフォームに4スキル公開(office-hours/ceo-review/investigate/retro) |
| 対応プラットフォーム | Claude Code/Codex/OpenClaw/Cursor/Factory Droid/Slate/Kiro/Hermes/GBrain(10種) |
| Conductor | 10-15並列Claude Codeセッション管理ツール(Tan本人が利用、gstackと連携) |
| YC採用 | YCがgstackを使って製品をship可能なエンジニアを採用中 |
| 記事/チュートリアル | SitePoint/Medium/MarkTechPost/TechCrunch等多数。「gstackは神モード」と評価 |

## Garry Tanの最新発言（2026-03-13以降）

| 日付 | 発言 | 文脈 |
|------|------|------|
| 2026-03-12頃 | "It's just one paste to install it on your local Claude Code, and it's a 2nd one to install it in your repo for teammates." | gstack公開時のX投稿 |
| 2026-03頃 | "I've been having such an amazing time with Claude Code I wanted you to be able to have my *exact* skill setup" | gstack公開の動機 |
| 2026-03-15頃 | "I'm averaging 17k lines of code per day, 35% tests, all thanks to gstack." (Conductor+15セッション) | X投稿、productivity実績 |
| 2026-03以降 | CTO友人からのDM: "Your gstack is crazy. This is like god mode. Your eng review discovered a subtle cross site scripting attack that I don't even think my team is aware of." | X投稿(引用) |
| 2026-03以降 | "Many such cases I made GStack to speed up for myself. Now everyone has it. Fork it. Improve it. Make it yours." | コミュニティ展開方針 |

## Sources

| カテゴリ | URL |
|---------|-----|
| Repository | https://github.com/garrytan/gstack |
| CHANGELOG | https://github.com/garrytan/gstack/blob/main/CHANGELOG.md |
| README | https://github.com/garrytan/gstack/blob/main/README.md |
| 前回調査 | `docs/research/gstack-analysis.md` (v0.0.2詳細分析) |
| MarkTechPost記事 | https://www.marktechpost.com/2026/03/14/garry-tan-releases-gstack-an-open-source-claude-code-system-for-planning-code-review-qa-and-shipping/ |
| SitePoint Tutorial | https://www.sitepoint.com/gstack-garry-tan-claude-code/ |

## Verification

| 項目 | 内容 |
|------|------|
| verified_at | 2026-04-19T00:30:00+09:00 |
| method | WebFetch(GitHub README/CHANGELOG) + WebSearch(多メディア記事) |
| source | github.com/garrytan/gstack (CHANGELOG 170+バージョン確認) |
| confidence | HIGH — GitHub直接確認。Garry TanのX発言は検索結果引用(直接fetch不可) |
| 前回差分基準 | 前回調査 2026-03-13 v0.0.2時点。6スキル/414 stars → 23スキル/75.8k stars/v1.0.0.0 |
