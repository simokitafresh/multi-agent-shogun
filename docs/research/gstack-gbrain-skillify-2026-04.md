# GStack v1.11 + GBrain v0.19 + Skillify 全分析（2026-04-25更新）

> 前版: docs/research/gstack-analysis.md (2026-03-13, gstack v0.0.2)
> 本版: gstack v1.11 (23スキル) + GBrain v0.19 (29スキル) + Skillify 10ステップ
> Source: https://github.com/garrytan/gstack / https://github.com/garrytan/gbrain
> Author: Garry Tan (YC President/CEO)

---

## §1 進化の全体像（v0.0.2 → v1.11/v0.19）

| 観点 | 旧版(2026-03-13) | 最新版(2026-04-25) |
|------|-----------------|-------------------|
| gstack | v0.0.2, 6スキル | v1.11, **23スキル** |
| GBrain | 未存在 | v0.19, **29スキル**, 21 cron jobs本番稼働 |
| スケール | 1エージェント×6モード | 10-15並列スプリント(Conductor) |
| データ規模 | — | 17,888ページ, 4,383人, 723社 |
| ブラウザ | Playwright+persistent daemon | +サイドバーエージェント+Cookie import+CAPTCHA handoff |
| テスト | — | Skillify 10ステップ(unit/integration/LLM eval/routing eval) |
| メモリ | stateless | PGLite/Supabase永続化+ハイブリッド検索(Vector+BM25+Graph) |
| 決定論的実行 | — | **Minions**(Postgres job queue, $0トークン, 753ms) |

### 最大の変化
1. **GBrain新登場**: gstackが「開発ツール」なのに対しGBrainは「知識管理+自律エージェント基盤」。将軍システムの直接競合
2. **Skillify**: 失敗→永続修正パイプライン。将軍のgate→lesson→enforcementと同じ設計思想
3. **Minions**: 決定論的タスクをLLMから分離。トークンコスト$0。将軍のbashスクリプト群と同じ着想

---

## §2 Skillify 完全解説

### 2.1 概念

AIエージェントの失敗を**永続的なスキル（二度と同じ失敗をしない仕組み）**に変換する10ステップパイプライン。Garry Tanが2026-04-22に提唱、766k views。

設計思想: 「バグは一時的な修正ではなく、恒久的なスキルに変換すべき」

### 2.2 The Four Verbs (v0.19)

| Verb | 説明 | コマンド |
|------|------|---------|
| **Scaffold** | スタブ一式生成(SKILL.md+スクリプト+テスト+resolver) | `gbrain skillify scaffold <name>` |
| **Implement** | SKILLIFY_STUBセンチネルをロジックに置換 | 手動編集 |
| **Check** | 10項目監査 | `gbrain skillify check <script>` |
| **Verify** | ツリー全体の整合性検証 | `gbrain check-resolvable [--strict]` |

### 2.3 10ステップチェックリスト

| # | チェック項目 | 説明 | 将軍システム対応 |
|---|------------|------|-----------------|
| 1 | SKILL.md存在+frontmatter | スキル定義ファイル | `~/.claude/skills/*/SKILL.md` — **同一** |
| 2 | スクリプト存在+実行可能 | 実装本体 | bashスクリプト群 — **同一** |
| 3 | ユニットテスト存在 | 179本, <2秒 | batsテスト — **同等** |
| 4 | E2Eテスト存在 | 統合テスト | 家老E2Eテスト — **同等** |
| 5 | LLM eval存在 | 日次35本のLLM判定テスト | **未実装** — 修行サイクルが近いが日次自動ではない |
| 6 | Resolver entry作成 | スキルルーティング定義 | スキルdescription — **部分実装** |
| 7 | Trigger eval通過 | intent→expectedSkillのテスト(50+ケース) | **未実装** |
| 8 | Brain filing audit通過 | スキルが書き込むディレクトリの宣言一致 | **未実装** |
| 9 | SKILLIFY_STUBなし | 未実装部分が残っていないこと | AC binary_checks — **類似** |
| 10 | Check-resolvable通過 | 全スキルの到達可能性・MECE・DRY | **未実装** — スキル数が少ないため未必要だが将来必要 |

### 2.4 Check-Resolvable（スキル健全性検証）

```bash
gbrain check-resolvable           # 警告のみ
gbrain check-resolvable --strict  # 警告でもブロック(CI用)
```

検証項目:
- **Reachability**: 到達不能スキルの検出（40スキル中15%=6本が到達不能だった実績）
- **MECE overlap**: trigger重複の検出（false positive防止）
- **DRY violations**: 機能重複の検出
- **Routing gaps**: どのスキルにもルーティングされないintentの検出
- **Filing audit**: スキルの書き込み先ディレクトリが宣言と一致
- **SKILLIFY_STUB**: 未実装センチネルの残存検出

### 2.5 Routing Evaluation

```bash
gbrain routing-eval --llm
```

`routing-eval.jsonl`にテストケースを記述:
```json
{"intent": "verify webhook", "expected_skill": "webhook-verify"}
{"intent": "check tunnel", "expected_skill": "webhook-verify", "ambiguous_with": ["health-check"]}
```

LLM tie-breakレイヤーが検出:
- False positives（誤ったスキルがマッチ）
- Missed routes（どのスキルもマッチしない）
- Tautological fixtures（intentがtriggerのコピー=テストの意味がない）

### 2.6 将軍システムとの対比（Skillify）

| Skillify概念 | 将軍システム | 差異 |
|-------------|-------------|------|
| 失敗→スキル化 | gate BLOCK→lesson→enforcement | 将軍の方が深い（なぜなぜ→自動化ターゲット特定） |
| SKILL.md | `~/.claude/skills/*/SKILL.md` | **同一** |
| 10ステップチェック | cmd_save.sh品質gate+cmd_complete_gate | 将軍の方がチェック項目が多い(20+) |
| check-resolvable | **未実装** | スキル20+で必要になる。取り込み候補 |
| routing-eval | **未実装** | スキルdescriptionの品質検証。取り込み候補 |
| LLM eval (日次) | 修行サイクル(手動配備) | Skillifyの方が自動化されている |
| 4 Verbs | cmd起票→配備→実装→gate | フロー類似だが将軍は人間(殿)が起点 |

---

## §3 GBrain v0.19 全体アーキテクチャ

### 3.1 設計哲学

**"Thin harness, fat skills"** — 知性はMarkdownスキルファイルに住む。ランタイムではない。

シグナル処理ループ:
1. Signal到着（会議/メール/ツイート/リンク）
2. Signal detector: アイデア+エンティティを並列キャプチャ（安価モデル）
3. Brain-ops: 外部API前にbrain内検索（5ステップlookup）
4. Response生成（フルコンテキスト付き）
5. Write: ページ更新（citation付き）
6. Auto-link: 型付き関係抽出（LLMコール0）
7. Sync: 次クエリ用インデックス更新

### 3.2 29スキル完全カタログ

#### Always-on (2)
| スキル | 説明 |
|--------|------|
| signal-detector | 全メッセージで発火。安価モデルでエンティティキャプチャ |
| brain-ops | 外部API前のbrain内5ステップlookup |

#### Content Ingestion (4)
| スキル | 説明 |
|--------|------|
| ingest | 入力タイプ検出ルーター |
| idea-ingest | リンク/記事→ページ化+分析 |
| media-ingest | 動画/音声/PDF/スクショ/リポジトリ |
| meeting-ingestion | トランスクリプト+出席者enrichment |

#### Brain Operations (7)
| スキル | 説明 |
|--------|------|
| enrich | 段階的エンティティenrichment (Tier 1/2/3) |
| query | 3層検索(Vector+BM25+Graph)+synthesis+citation |
| maintain | 定期健全性（staleページ/孤児/dead link） |
| citation-fixer | citation修正スキャン |
| repo-architecture | ファイリングプロトコル |
| publish | パスワード保護HTML共有 |
| data-research | YAML recipeベース構造化データ抽出 |

#### Operational (10)
| スキル | 説明 |
|--------|------|
| daily-task-manager | タスクライフサイクル P0-P3 |
| daily-task-prep | 朝のカレンダーコンテキスト |
| cron-scheduler | スタガリング/quiet hours/冪等性 |
| reports | タイムスタンプ付きルーティング |
| cross-modal-review | 第2モデルによる品質ゲート |
| webhook-transforms | 外部イベント→brainページ |
| testing | スキル準拠バリデーション |
| skill-creator | 新スキルスキャフォールディング |
| **skillify** | **メタスキル: 10ステップ失敗→永続修正ループ** |
| skillpack-check | ヘルスレポート(CI用exit code) |

#### Identity & Setup (4)
| スキル | 説明 |
|--------|------|
| soul-audit | 6フェーズインタビュー→SOUL.md/USER.md/ACCESS_POLICY.md/HEARTBEAT.md |
| setup | PGLite/Supabase自動プロビジョニング |
| migrate | Obsidian/Notion/Logseq/Roamからの移行 |
| briefing | 日次ブリーフィング |

#### Conventions (共有品質ゲート)
| ファイル | 説明 |
|---------|------|
| quality.md | citation/backlink/notability gate |
| brain-first.md | 外部API前の5ステップlookup |
| model-routing.md | タスク→モデル割当 |
| test-before-bulk.md | バッチ前の3-5件テスト |
| cross-modal.yaml | レビューペア+拒否ルーティング |

### 3.3 Minions（決定論的タスク実行）

**ルーティングルール**:
- **決定論的**(投稿取得/JSONパース/ページ書込/同期) → **Minions** ($0トークン, ミリ秒, 100%成功)
- **判断**(トリアージ/優先度評価/返信判断) → **サブエージェント**

**本番ベンチマーク** (30日分ソーシャル投稿取込):

| メトリック | Minions | sessions_spawn |
|-----------|---------|----------------|
| 所要時間 | **753ms** | >10,000ms (timeout) |
| トークンコスト | **$0.00** | ~$0.03 |
| 成功率 | **100%** | 0% (spawn失敗) |
| メモリ/job | ~2 MB | ~80 MB |

将軍システム対応: bashスクリプト群（inbox_write.sh/deploy_task.sh等）が同じ役割。LLMを通さず決定論的に実行。

### 3.4 ハイブリッド検索

Vector + BM25 + Graph traversal の3層:
- 型付き関係: `attended`, `works_at`, `invested_in`, `founded`, `advises`
- ベンチマーク(v0.12, 240ページ): P@5=49.1%, R@5=97.9%
- Graph優位: vector-only RAGに対して**P@5 +31.4pt**

将軍システム対応: MCP Memory（Entity+Relation+Observation）が同じ構造。ただしハイブリッド検索は未実装（MCPはキーワードマッチ）。

### 3.5 Durable Agents

サブエージェント実行がクラッシュ耐性:
- 全Anthropicターンが`subagent_messages`にcommit
- 全ツールコールが`subagent_tool_executions`にcommit
- Two-phase ledger: pending → complete/failed
- リプレイ安全（構造的に保証）

将軍システム対応: task YAML + 報告YAML + dashboard。クラッシュ耐性は/clear→復帰手順で実現。

### 3.6 品質ゲート

5つのConvention（全スキル横断）:
1. **Citations**: 全主張にソース `[Source: domain, YYYY-MM-DD]`
2. **Backlinks**: 全参照に型付き双方向リンク
3. **Notability Gate**: Tier 3スタブが3+言及 or 1会議でTier 1に昇格
4. **Cross-modal Review**: 第2モデルによる品質ゲート+拒否ルーティングfallback
5. **Test-Before-Bulk**: バッチ操作前に3-5件テスト

将軍システム対応:
- Citations → cmd_save.sh q5_verified_source
- Notability Gate → insight_write.sh pending→done昇格
- Cross-modal Review → 軍師レビュー(第2モデル)
- Test-Before-Bulk → PI-005(full一括実行)の逆発想だが用途が異なる

---

## §4 GStack v1.11 全体アーキテクチャ

### 4.1 設計哲学

**"Not a copilot — a team."** 23の専門エージェントがプロセスリゴーを強制。

スプリントワークフロー: **Think → Plan → Build → Review → Test → Ship → Reflect**

### 4.2 23スキル完全カタログ

#### Planning Phase (6)
| スキル | 説明 | 将軍対応 |
|--------|------|---------|
| /office-hours | 6つの強制質問 | cmd起票前の品質チェック3問 |
| /plan-ceo-review | 4モード(Expansion/Hold/Reduction) | scope_mode宣言 |
| /plan-eng-review | アーキテクチャ+テストマトリクス | 偵察cmd |
| /plan-design-review | 0-10評価×設計次元 | — |
| /plan-devex-review | 20-45強制質問 | — |
| /autoplan | CEO→design→eng自動パイプライン | cmdパイプライン(将軍→家老→忍者) |

#### Building & Design (3)
| スキル | 説明 | 将軍対応 |
|--------|------|---------|
| /design-consultation | デザインシステム構築 | — |
| /design-shotgun | 4-6 AIモックアップ比較 | — |
| /design-html | モックアップ→Pretext HTML | — |

#### Review & Quality (6)
| スキル | 説明 | 将軍対応 |
|--------|------|---------|
| /review | スタッフエンジニアレビュー | 軍師レビュー(SGプロトコル) |
| /investigate | 体系的root-cause(3修正制限) | 偵察cmd+なぜなぜ7回 |
| /design-review | ライブデザイン監査+自動修正 | — |
| /devex-review | オンボーディングフロー実テスト | — |
| /qa | ブラウザテスト+修正+回帰テスト自動生成 | CDP計測(cmd_2262) |
| /qa-only | バグ報告のみ(コード変更なし) | 偵察cmd(scope_mode=SCOUT) |

#### Deployment & Monitoring (5)
| スキル | 説明 | 将軍対応 |
|--------|------|---------|
| /ship | 同期→テスト→カバレッジ→push→PR | cmd_complete_gate + deploy |
| /land-and-deploy | PR merge→CI/deploy→本番ヘルスチェック | cmd_2268(deploy+検証) |
| /canary | デプロイ後監視(コンソールエラー/性能) | — |
| /benchmark | ベースラインページロード+Core Web Vitals | cmd_2262(CDP計測) |
| /document-release | ドキュメント自動更新 | context更新(家老担当) |

#### Browser & Tools (5+)
| スキル | 説明 | 将軍対応 |
|--------|------|---------|
| /browse | Chromium ~100ms/cmd | CDP(cdp_cli.sh) |
| /open-gstack-browser | anti-bot stealth+サイドバー | — |
| /setup-browser-cookies | Chrome/Arc/Brave/EdgeからCookie import | — |
| /pair-agent | マルチエージェントブラウザ共有 | — |
| /connect-chrome | 既存Chrome接続 | CDP port接続 |

#### その他
| スキル | 説明 | 将軍対応 |
|--------|------|---------|
| /codex | OpenAI Codexクロスレビュー | — |
| /retro | 週次レトロ+出荷ストリーク | dashboard+cmd_design_quality |
| /learn | 永続学習管理 | lessons.yaml |
| /context-save/restore | セッションチェックポイント | /clear前手順+復帰手順 |
| /careful | 破壊コマンド警告 | Tier 1 ABSOLUTE BAN |
| /freeze | ディレクトリロック | — |
| /cso | OWASP Top 10+STRIDEモデリング | — |

### 4.3 並列実行（Conductor）

10-15並列スプリント。各Claude Codeセッションが独立ワークスペースで動作。

将軍システム対応: 6忍者同時並列。ただし将軍は鎖の原理で統制、gstackは独立セッション。

### 4.4 プロンプトインジェクション防御

- 22MB MLクラシファイア（ローカルスキャン）
- Claude Haikuトランスクリプト投票
- ランダムcanaryトークン（セッション漏洩検出）
- オプション721MB DeBERTa-v3アンサンブル

将軍システム対応: CLAUDE.md「Prompt Injection Defense」セクション（ルールベース）。MLクラシファイアは未実装。

---

## §5 将軍システムとの統合対比（更新版）

### 5.1 スコアカード

| 観点 | gstack v1.11 | GBrain v0.19 | 将軍システム | 勝者 |
|------|-------------|-------------|-------------|------|
| エージェント数 | 23スキル | 29スキル | 10エージェント+軍師 | GBrain(スキル数) / 将軍(実体エージェント数) |
| 並列処理 | 10-15(Conductor) | DAGサブエージェント | **8忍者同時** | 同等 |
| 品質管理 | /review 2-pass | cross-modal + skillify | **鎖+gate+軍師+deepdive** | 将軍(深さ) |
| 永続メモリ | /learn(セッション跨ぎ) | **PGLite+ハイブリッド検索** | lessons+MCP+deepdive | GBrain(検索) / 将軍(追体験) |
| テスト自動化 | /qa+/benchmark | **Skillify 10ステップ** | bats+修行サイクル | Skillify(体系性) |
| 決定論的実行 | — | **Minions($0)** | bashスクリプト群 | 同等(設計思想同一) |
| ブラウザ | Playwright+sidebar | — | CDP直接 | gstack(機能) / 将軍(GUI制御) |
| 教訓蓄積 | /retro JSON | brain enrichment | **lessons+PI+deepdive** | 将軍(深さ) |
| 失敗→永続修正 | — | **Skillify 4 Verbs** | **gate→lesson→enforcement** | 同等(設計思想同一) |
| メタ改善 | — | skillify+check-resolvable | cmd_save.sh自己改善 | GBrain(体系性) |
| プロンプト注入防御 | **MLクラシファイア+canary** | — | ルールベース | gstack |

### 5.2 将軍システムの独自強み（gstack/GBrainにないもの）

1. **鎖の原理**: 垂直統制(殿→将軍→家老→忍者)。gstack/GBrainは水平
2. **追体験(deepdive)**: 結論ではなく過程を追体験する学習方式。GBrainにもSkillifyにもない
3. **なぜなぜ7回**: 根因特定の深さ。Skillifyは失敗→スキル化だが「なぜ失敗したか」の深掘り度が浅い
4. **殿の判断**: 人間がアーキテクチャを判断。GBrainは自律だが「殿の怒り」に相当するフィードバックがない
5. **Production Invariants**: 本番不変量24件。GBrainのConventions 5件より具体的かつ多い
6. **成長ループ3層**: 個(ロール)・対(セット)・全(システム)のスコープ分離

### 5.3 将軍システムが取り込むべきもの

| 優先度 | 取り込み元 | 概念 | 取り込み方法 |
|--------|-----------|------|-------------|
| **P0** | Skillify | check-resolvable(スキル到達可能性+MECE+DRY) | スキル数20超でCI化。現時点は未必要 |
| **P0** | Skillify | routing-eval(intent→expectedSkillテスト) | スキルdescription品質検証として取り込み |
| **P1** | GBrain | Minions的決定論/判断分離の明示化 | 既にbashスクリプトで実現済み。設計書に原理を明文化 |
| **P1** | GBrain | cross-modal review(第2モデル品質ゲート) | 軍師レビューが同等。ただし自動ルーティング(refusal fallback)は未実装 |
| **P1** | GBrain | ハイブリッド検索(Vector+BM25+Graph) | MCP Memoryの検索強化。現状キーワードマッチのみ |
| **P2** | gstack | /canary(デプロイ後監視) | CDP計測のcron化で実現可能 |
| **P2** | gstack | /benchmark(Core Web Vitals) | cmd_2262+Phase 1-Aで着手済み |
| **P2** | GBrain | soul-audit(エージェントIDペルソナ定義) | instructions/*.mdが同等 |
| **P3** | gstack | MLクラシファイア注入防御 | 現状ルールベースで十分。スケール時に検討 |

---

## §6 Skillifyスケール限界（X上の議論）

### 6.1 到達不能スキル問題
- 40スキル中15%(6本)がcheck-resolvable初回で到達不能
- 原因: trigger定義の粗さ + ルーティングモデルの限界

### 6.2 スキル数上限
- Ryan Lynn (@ryan_lynn_): "too many skills can mess the agent up... maximum number of skills between 10-20"
- 現時点でGBrainは29スキル。ルーティング精度をどう維持するかが課題

### 6.3 運用コスト
- 179 unit tests (2sec) + 35 LLM evals daily + integration/smoke test
- トークンコスト/レイテンシの増大はsampling/batchingで対処（未言及）

### 6.4 将軍システムへの示唆
- 現在20+スキル。30超えるとcheck-resolvable相当の仕組みが必要
- routing-eval的なテストを修行サイクルに統合すると予防的
