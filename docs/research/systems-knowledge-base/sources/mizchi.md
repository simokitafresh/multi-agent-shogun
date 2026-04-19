# mizchi — TypeScript/AI記事・コーディングエージェント知見

> 「Programmer in the Loop」を掲げる日本語圏の著名エンジニア。TypeScript/フロントエンドを主戦場としつつ、Claude Code登場以降はコーディングエージェントの設計哲学・実践知見を精力的に発信。"AI×人間の協働モデル"を実験・言語化し続けている。

## Basic Info

| 項目 | 内容 |
|------|------|
| Author | mizchi |
| Tagline | "Programmer in the Loop" |
| Platform | Zenn (mizchi), GitHub (mizchi), mizchi.dev, X (@mizchi) |
| Status | 継続執筆中 |
| Articles Covered | AI/コーディングエージェント関連4記事 + ai-coding-guide GitHub repo |
| Zenn 総記事数 | 191記事 (2025-04-14時点) |
| Language | 日本語 |
| Zenn | https://zenn.dev/mizchi |
| GitHub | https://github.com/mizchi |
| Twitter/X | https://x.com/mizchi |
| Site | https://mizchi.dev |
| License | — |

## Design Philosophy

- **Programmer in the Loop**: AIが実装を高速に担い、人間が設計・判断・品質評価・リファクタリングを担う協働モデル。AIを「指示待ち下請け」ではなく「実装速度を上げるペア」として位置づける
- **自己改善ループ (Singularity Point)**: Claude CodeがClaude自身で開発される構造により、モデル性能向上→エージェント能力向上→フィードバック収集→さらなるモデル改善の相互強化サイクルが成立すると論じる
- **CLI特化による自己進化の容易性**: Cursor/ClineのUI層の複雑性を排除し、CLIに特化することでAIが自身の環境を理解・改善しやすくなるという観察
- **Document-First Development**: コードを書かせる前に `docs/` 配下にMarkdownで仕様・知識を蓄積し、`@doc.md に従って書き直せ` パターンでAIに参照させる開発スタイル
- **漸進的権限委譲**: AIへの自動化権限を徐々に拡張する設計（デフォルト → auto-accept → plan mode → bypassing permissions）。習熟に応じたセキュリティと効率のバランスを重視

## Architecture (記事体系)

### AI/コーディングエージェント関連記事

```
A1: Claude Code による技術的特異点を見届けろ (2025年)
    ↓ 「モデル改善」から「モデル×エージェント相互強化」へ
A2: 速習 Claude Code (2025年)
    ↓ 「概念理解」から「実践テクニック習得」へ
A3: プログラミング用途の生成AI関連ツールの評価 2025/04/14
    ↓ 「単一ツール」から「ツール使い分けの評価基準」へ
A4: AI による自然言語アサーション (2025年)
    ↓ 「従来テスト」から「AI駆動アサーションの可能性と限界」へ
```

記事群は思想(A1)→実践(A2)→評価(A3)→実験的応用(A4)と展開する。

### ai-coding-guide-202507 (GitHub)

7段階の段階的学習プロジェクト集。AIとの協働を実体験させる構造。

| フェーズ | 内容 | AIの役割 |
|---------|------|---------|
| 00-setup | TypeScript + Vitest環境構築 | 補助 |
| 01-dijkstra | 既知アルゴリズム実装 | 主担当（得意領域） |
| 02-todo | SQLite + Prisma ORM | 主担当 |
| 03-ink-game | React Inkターミナルゲーム | 主担当 |
| 04-mcp | MCPサーバー実装 | 主担当 |
| 05-survivor-game | React + SVGゲーム | 主担当 |
| 07-real-world | Next.js + E2E | 人間と協働 |

## Key Features (主要記事・コンセプト)

| 記事/プロジェクト | 投稿日 | 主要コンセプト | URL |
|----------------|--------|--------------|-----|
| **A1: Claude Code による技術的特異点を見届けろ** | 2025年 | 自己改善ループ / CLI特化の優位性 / 技術的特異点 | https://zenn.dev/mizchi/articles/claude-code-singularity-point |
| **A2: 速習 Claude Code** | 2025年 | セッション管理 / 漸進的権限委譲 / CLAUDE.md二層構造 / MCP統合 | https://zenn.dev/mizchi/articles/claude-code-cheatsheet |
| **A3: プログラミング用途の生成AI関連ツールの評価** | 2025-04-14 | モデル別使い分け / Document-First / iterative refinement | https://zenn.dev/mizchi/articles/ai-model-current-snapshot-2025-0414 |
| **A4: AI による自然言語アサーション** | 2025年 | assertAI() / 自然言語テストの限界 / 仕様→テスト自動生成の中間ステップ | https://zenn.dev/mizchi/articles/ai-assertion-with-claude-code |
| **ai-coding-guide-202507** | 2025-07 | AI得意/不得意の明示 / 7段階学習フレームワーク / 実体験重視 | https://github.com/mizchi/ai-coding-guide-202507 |

## Changelog since 2025-04-14

| 日付 | 記事/更新 | 内容 |
|------|----------|------|
| 2025-04-14 | A3公開 | プログラミング用途AI評価。claude-3.7-sonnetとGemini 2.5の使い分けを解説 |
| 2025年 | A1公開 | Claude Codeの自己改善ループと技術的特異点論 |
| 2025年 | A2公開 | 速習チートシート。セッション管理・権限・MCP |
| 2025年 | A4公開 | AI自然言語アサーションの概念実証と限界の率直な評価 |
| 2025-07 | ai-coding-guide-202507 | 7段階AI協働学習プロジェクト集をGitHubで公開 |

## Notable Techniques (主要洞察)

| テクニック | 説明 | 出典 | 独自概念か |
|-----------|------|------|----------|
| 技術的特異点論 | モデル改善→エージェント能力向上→統計的フィードバック→さらなる改善の自己強化ループが既に動いていると分析 | A1 | Yes（このフレーミングは著者独自） |
| Document-First Development | コード生成前にdocs/にMarkdownで仕様・知識を蓄積し、`@doc.md に従って書き直せ` パターンでAIに参照させる | A3 | No（業界的潮流。著者が実践・整理） |
| 漸進的権限委譲 (Progressive Permission) | default → auto-accept → plan mode → bypassing permissionsの4段階。習熟と信頼に応じて自動化を拡張 | A2 | Yes（段階的アプローチの明示は著者独自） |
| AI Natural Language Assertion | `assertAI("README.mdが存在するか")` でAIにファイルシステムを自然言語で検査させる実験的手法。著者自身が"最悪なアイデア"と評し限界を明示 | A4 | Yes（概念実証は著者独自） |
| CLAUDE.md二層構造 | グローバルメモリ(`~/.claude/CLAUDE.md`)とプロジェクトメモリ(`./CLAUDE.md`)を分離。永続知識 vs プロジェクト固有の分類 | A2 | No（Claude Code公式機能。著者が整理） |
| AI得意/不得意の明示 | AIが得意な領域（既知アルゴリズム、明確な仕様、既存テスト環境）と不得意な領域（環境セットアップ、GUI調整、最新API）を実体験から分類 | ai-coding-guide | Yes（7段階設計での体系化は著者独自） |
| モデル別使い分け | claude-3.7-sonnet（1000行単独コーディング得意）vs Gemini 2.5（大量コード読み＋小規模変更得意）の実践評価 | A3 | Yes（著者の実測評価） |

## Ecosystem (関連リソース)

| 項目 | 関係 | URL/参照 |
|------|------|---------|
| ai-coding-guide-202507 | AI協働学習の実践プロジェクト集。7フェーズ構成 | https://github.com/mizchi/ai-coding-guide-202507 |
| Zenn プロフィール | 191記事、33,706いいね (2025-04-14時点) | https://zenn.dev/mizchi |
| TypeScript OSS群 | mizchiは複数のTypeScript OSSを公開。AMDXなど | https://github.com/mizchi |

## Pitfalls

| 落とし穴 | 何が問題か | どこで表面化するか |
|---------|-----------|------------------|
| 書き手バイアスの残存リスク | mizchiの記事はTypeScript/フロントエンド個人開発視点が強い。バックエンド/データ系/チーム開発の課題は過小評価される可能性がある。例: git-workflowへの依存度評価、Claude Code不採用の理由もmizchiの個人スタイルに依存 | Claude CodeやDocument-First Developmentをチーム・バックエンド環境に適用しようとする際 |
| シナリオ過適合 | 各テクニックはmizchiの個人開発スタイル（ゆるいgit運用、TypeScript中心）に最適化されており、他のスタイルでは効果が変わる。例: 「Claude Codeのgit-workflow依存が自分のスタイルと合わない」はmizchi固有の評価 | チーム・厳格git運用・多言語環境での知見移植時 |
| コスト対効果の閾値 | $200プランで3並列1時間/5時間制限など、具体的なコスト情報はモデル・料金体系変更で即陳腐化する。数字を引用する際は必ず時点(2025-04-14)を確認し、現行料金で再検証が必要 | API料金・プラン体系が変更されたタイミングで旧情報を参照する場合 |

## Cross-References

| 軸 | 対象 | 関係 |
|----|------|------|
| 補完 | [karpathy-principles](../systems/karpathy-principles.md) | mizchiの"Programmer in the Loop"(協働モデル)に対し、Karpathyは"Think Before Coding"(LLM個別の推論品質制御)の原則を補完する |
| 補完 | [gyakusegawa](gyakusegawa.md) | mizchiのDocument-First開発パターンに対し、逆瀬川のフィードバック速度ヒエラルキーとAGENTS.md生きたドキュメント原則が実装面を補完する |
| 競合 | [gstack](../systems/gstack.md) | mizchiは個人の漸進的習熟モデルを重視するのに対し、gstackはcognitive mode切替による組織的なスキル管理を中心に置く |
| 前提 | [claude-code](../systems/claude-code.md) | mizchiの知見の大半はClaude Code環境(CLI・CLAUDE.md・MCP)を前提とする。Claude Code未整備の環境では多くのテクニックが適用不可 |

## Sources

| 種別 | URL |
|------|-----|
| Zenn プロフィール | https://zenn.dev/mizchi |
| A1: 技術的特異点 | https://zenn.dev/mizchi/articles/claude-code-singularity-point |
| A2: 速習 Claude Code | https://zenn.dev/mizchi/articles/claude-code-cheatsheet |
| A3: AI評価 2025-04-14 | https://zenn.dev/mizchi/articles/ai-model-current-snapshot-2025-0414 |
| A4: AI自然言語アサーション | https://zenn.dev/mizchi/articles/ai-assertion-with-claude-code |
| GitHub (ai-coding-guide) | https://github.com/mizchi/ai-coding-guide-202507 |
| GitHub (プロフィール) | https://github.com/mizchi |
| Twitter/X | https://x.com/mizchi |
| 個人サイト | https://mizchi.dev |

## Verification

- verified_at: 2026-04-19
- method: WebSearch ("mizchi Claude Code zenn 2025 2026") + WebFetch (zenn.dev/mizchi, mizchi.dev, 各記事URL, github.com/mizchi/ai-coding-guide-202507)
- source: https://zenn.dev/mizchi / https://github.com/mizchi
