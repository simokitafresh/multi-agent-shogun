# 逆瀬川ちゃん (@gyakuse) — Coding Agent技術記事

> 日本語ブログ・Zenn・noteにてCoding Agentワークフロー、Harness Engineering、Skill設計を発信するエンジニア。2026年2〜3月に執筆した4記事が日本語圏のCoding Agent実践知識の主要一次資料となっている。

## Basic Info

| 項目 | 内容 |
|------|------|
| Author | 逆瀬川ちゃん (@gyakuse / @sakasegawa) |
| Platform | Blog (nyosegawa.com), note.com, Zenn (sakasegawa) |
| Status | 継続執筆中 |
| Articles Covered | 4記事 (2026-02-15〜2026-03-14) |
| Language | 日本語 |
| Blog | https://nyosegawa.com |
| Twitter/X | https://x.com/gyakuse |
| Zenn | https://zenn.dev/sakasegawa |
| note | https://note.com/sakasegawa |
| License | — |

## Design Philosophy

- **Harness Engineering最優先**: エージェントの性能はモデルよりもハーネス（環境・制約・フィードバックループ）の設計で決まる
- **フィードバック速度が品質を決定**: PostToolUse(ms) > プリコミット(s) > CI(分) > 人間レビュー(時間) — 検査を早くするほどエージェント性能が上がる
- **AGENTS.mdは生きたドキュメント**: 静的設定ファイルではなく、プロジェクトと共に変化するもの。指示は20〜30行以下に保ち、古い指示は積極的に削除する
- **LLMの指示上限**: フロンティアモデルで確実に従える指示数は150〜200個程度が上限。簡潔さが正確性を保証する

## Architecture (記事体系)

### 4記事の位置づけ

```
A1: AGENTS.md自動生成 (2026-02-15)
    ↓ 「ドキュメント設計」から「エージェント環境設計」へ
A2: Skill設計・オーケストレーション (2026-03-04)
    ↓ 「個別スキル」から「スキル間連携」へ
A3: Harness Engineering (2026-03-09)
    ↓ 「ツール」から「環境全体の最適化」へ
A4: Coding Agentワークフロー総括 (2026-03-14)
    ↓ 「実装テクニック」から「プロジェクト管理手法」へ
```

記事群は個別技術(A1/A2)から体系的フレームワーク(A3/A4)へと段階的に抽象度を上げる構造。

### A4記事の3層構造

| 層 | 内容 |
|----|------|
| ワークフロー層 | Harper Reed式/SDD/RPI/Superpowers の4手法比較 |
| テクニック層 | Context Engineering / TDD×Agent / Best-of-N |
| インフラ層 | AGENTS.md / Skills / Hooks / Worktree |

### A3記事のフィードバック速度ヒエラルキー

```
高速  PostToolUse Hook (ミリ秒)
      ↓ エージェントの自己修正を即座に駆動
      プリコミット Hook (秒)
      ↓
      CI テスト (分)
      ↓
低速  人間レビュー (時間〜日)
```

## Key Features (主要記事)

| 記事 | 投稿日 | 主要コンセプト | URL |
|------|--------|--------------|-----|
| **A1: AGENTS.mdを自動で育てる仕組みを作った** | 2026-02-15 | agents-md-generator / 生きたドキュメント原則 / 20〜30行制限 | https://nyosegawa.com/posts/agents-md-generator/ |
| **A2: skill-creatorから学ぶSkill設計と、Orchestration Skillの作り方** | 2026-03-04 | 7設計パターン / Sub-agent型 vs Skill Chain型 / Progressive Disclosure | https://nyosegawa.com/posts/skill-creator-and-orchestration-skill/ |
| **A3: Harness Engineeringベストプラクティス** | 2026-03-09 | 7ベストプラクティス / フィードバック速度ヒエラルキー / 決定論的ツール | https://nyosegawa.com/posts/harness-engineering-best-practices-2026/ |
| **A4: Coding Agent時代の開発ワークフロー** | 2026-03-14 | 4ワークフロー比較 / Context Engineering / 確率的カスケード / Best-of-N | https://nyosegawa.com/posts/coding-agent-workflow-2026/ |

### A2: 7つのSkill設計パターン

| パターン | 説明 |
|---------|------|
| SKILL.mdのオーケストレーター化 | スキル自身が子スキルを呼び出す上位構造を担う |
| 確定的処理のスクリプト化 | 決定論的な処理はシェルスクリプトに分離 |
| スキーマ契約 | 厳密な入出力スキーマで接続品質を保証 |
| Why-driven設計 | 各ルールにWHYを明記し、エッジケースで適切に適用される |
| descriptionの最適化 | スキル発見時のマッチング精度をdescriptionで最大化 |
| Human-in-the-Loopの外部UI化 | 承認フローを外部UIとして分離 |
| 環境別フォールバック | 実行環境の違いに対応した分岐を持つ |

### A3: 7つのHarness Engineeringベストプラクティス

| # | ベストプラクティス | 核心 |
|---|--------------|------|
| 1 | リポジトリ衛生 | テストとADRを配置。腐敗しやすい説明文書を排除 |
| 2 | 決定論的ツール | リンター・型チェック・テストをPostToolUseフックで自動実行 |
| 3 | AGENTS.md/CLAUDE.md設計 | 50行以下のポインタとして機能。詳細は外部リソースへ参照 |
| 4 | 計画と実行の分離 | エージェントに先に計画を立てさせ、人間が承認してから実行 |
| 5 | E2Eテスト戦略 | Playwright/agent-browserでアクセシビリティツリーを活用 |
| 6 | セッション間状態管理 | Gitコミット・JSON進捗ファイル・起動ルーチン標準化 |
| 7 | プラットフォーム選定 | Claude Code（フック安定性）と Codex（並列実行）の使い分け |

## Changelog since 2026-02-15

| 日付 | 記事/更新 | 内容 |
|------|----------|------|
| 2026-02-15 | A1公開 | agents-md-generator公開。AGENTS.md自動生成の仕組みを解説 |
| 2026-03-04 | A2公開 | skill-creator解析。7設計パターン抽出とオーケストレーション戦略 |
| 2026-03-09 | A3公開 | Harness Engineering定義・7ベストプラクティス体系化 |
| 2026-03-14 | A4公開 | Coding Agentワークフロー総括。4手法比較と文脈整理 |
| 2026-03-26 | 追加記事 | 「Skillにアプリケーションを組み込んでみる」 |
| 2026-03-27 | 追加記事 | 「各Coding Agentでのデータ学習利用調査」 |
| 2026-03-28 | 追加記事 | 「.claudeignoreの宗教現象学的考察」 |
| 2026-04-07 | 追加記事 | 「Claude Codeの文字化け問題の簡易的対応方法」 |

## Notable Techniques (主要洞察)

| テクニック | 説明 | 出典記事 | 独自概念か |
|-----------|------|---------|----------|
| フィードバック速度ヒエラルキー | PostToolUse(ms) > プリコミット(s) > CI(分) > 人間レビュー(時間)。速いほど効果大 | A3 | Yes（ヒエラルキー定式化は著者独自） |
| 確率的カスケード | N段パイプラインの成功率 = p^N で急落。段数最小化が本質的解決策 | A4 | No（学術的概念。著者が整理） |
| Context Engineering | プロンプトの外側=環境・ファイル・ツール構成の最適化。Prompt Engineeringの上位概念 | A4 | No（業界概念。著者が整理） |
| AGENTS.md生きたドキュメント | 静的設定ではなくプロジェクトと共に進化。古い指示を積極削除。20〜30行上限 | A1/A4 | Yes（自動生成ツールは著者独自） |
| Progressive Disclosure in Skill | スキルに段階的情報開示でコンテキスト効率最大化 | A2 | Yes（スキル設計への適用は著者） |
| Skill Composability | SKILL.mdのオーケストレーター化。スキル間の{{INVOKE_SKILL}}による呼び出し | A2 | No（Anthropic/gstack概念を整理） |
| 計画と実行の分離 | エージェントに先に計画を立てさせ、人間が承認してから実行 | A3 | No（業界ベストプラクティス） |
| Comprehension Debt | AI生成速度と人間理解速度の5〜7倍ギャップ。生成時の説明強制で対策 | A4 | No（Addy Osmani概念。著者が整理） |
| SDD vs RPI対比 | SDD=仕様→実装(一方向)。RPI=仕様⇔実装(再帰双方向)。既存コード対応にはRPI | A4 | Yes（対比整理は著者） |
| LLM指示上限150〜200個 | フロンティアモデルで確実に従える指示数の実践的上限値 | A1 | Yes（著者の観察） |

## Ecosystem (関連リソース)

| 項目 | 関係 | URL/参照 |
|------|------|---------|
| nizos/tdd-guard | A4で紹介。TDD×Agent強制ツール (1,811 stars) | https://github.com/nizos/tdd-guard |
| Vercel AGENTS.md実証 | A4で引用。60,000+ OSSリポジトリ採用データ | — |
| Boris Tane RPI | A4で紹介。Recursive Planning Iteration開発手法 | — |
| Harper Reed | A4で紹介。Brainstorm→Plan→Execute個人向けワークフロー | — |
| Addy Osmani | A4で引用。Comprehension Debt概念提唱者 | — |
| Geoffrey Huntley | A4の文脈で参照。Ralph Loopパターン（Context Rot回避） | — |
| Anthropic skill-creator | A2で分析対象。公式メタスキル | — |
| 深掘り分析（我が軍） | A4記事の詳細分析。22概念の網羅的対比 | docs/research/gyakusegawa-article-analysis.md |

## Pitfalls

| 落とし穴 | 何が問題か | どこで表面化するか |
|---------|-----------|------------------|
| 確率的カスケードの無視 | N段パイプラインで各段の成功率を掛け算せずに全体を設計すると、成功率がp^Nで急落する。段数最小化の重要性を過小評価しやすい | 複雑なSkill Chainや多段オーケストレーション設計時 |
| AGENTS.md指示上限超過 | フロンティアモデルで確実に従える指示数の実践的上限は150〜200個。長期運用でルールを追加し続けると上限を超え、指示の遵守率が低下する | 長期プロジェクトでCLAUDE.md/AGENTS.mdを継続拡張する場合 |
| フィードバック速度の軽視 | CI段階(分単位)だけでテストするとエージェントのコンテキスト消費が大きく、品質管理のコストが高騰する。PostToolUseフック(ミリ秒)から設計しないと効果が半減する | PostToolUseフック未設定の環境、CI依存のQAフロー |

## Cross-References

| 軸 | 対象 | 関係 |
|----|------|------|
| 補完 | [karpathy-principles](../systems/karpathy-principles.md) | 逆瀬川のHarness全体設計・Skill構成に対し、LLM個別の思考・精度・ゴール設定に関する指示原則を補完する |
| 補完 | [mizchi](mizchi.md) | 逆瀬川のHarness Engineering・AGENTS.md自動生成に対し、mizchiのDocument-First開発と漸進的権限委譲が実践面の補完知見となる |
| 競合 | [ace](../systems/ace.md) | 逆瀬川はフィードバック速度と環境設計を中心に置く実装ファーストのアプローチで、ACEの抽象的6層認知モデルとは設計の出発点が異なる |
| 前提 | [our-army](../systems/our-army.md) | inotifywait + YAML mailbox + gate によるハーネス基盤が整っていることが、記事の知見をフル活用する前提条件となる |

## Sources

| 種別 | URL |
|------|-----|
| Blog (現行) | https://nyosegawa.com |
| A1: AGENTS.md自動生成 | https://nyosegawa.com/posts/agents-md-generator/ |
| A2: Skill設計 | https://nyosegawa.com/posts/skill-creator-and-orchestration-skill/ |
| A3: Harness Engineering | https://nyosegawa.com/posts/harness-engineering-best-practices-2026/ |
| A4: ワークフロー | https://nyosegawa.com/posts/coding-agent-workflow-2026/ |
| Zenn | https://zenn.dev/sakasegawa |
| note | https://note.com/sakasegawa |
| Twitter/X | https://x.com/gyakuse |

## Verification

- verified_at: 2026-04-19
- method: WebFetch (nyosegawa.com全記事一覧 + 各記事直接取得) + WebSearch ("逆瀬川 Claude Code 2026", "@gyakuse coding agent workflow 2026")
- source: https://nyosegawa.com / https://x.com/gyakuse
