# cmd_504 Qiita偵察A（kagemaru）

- source: https://qiita.com/ProgrammingForEver/items/ee68fc621f7d1c53ffe1
- fetched_at: 2026-03-03 23:20 JST
- scope: 記事の設計思想を multi-agent-shogun(infra) へ移植可能か評価
- independence: 他忍者報告は未参照

## 抽出案（6件）

| id | 案 | 期待効果 | 導入コスト | 競合リスク | 既存仕組みとの重複 |
|---|---|---|---|---|---|
| A1 | 固定名+世代アーカイブのHANDOFF運用 | PC/CLI切替時の再開時間短縮 | 中 | inbox/reportsと二重運用化 | 部分重複 |
| A2 | AGENTS不変ルール化と運用知識の層分離徹底 | 復帰時の読込負荷低減 | 低 | 既存context/projectsとの境界混乱 | 部分重複 |
| A3 | 軽量SDDゲート(PLAN→SPEC→TODO)を配備前に導入 | 曖昧指示の手戻り削減 | 中 | 緊急修正の初動遅延 | 部分重複 |
| A4 | project bootstrapスキルで初期構成一発生成 | 新規PJ立上げ工数削減 | 低 | switch-project系と責務競合 | 部分重複 |
| A5 | MEMORY/HANDOFF人手キュレーション手順の制度化 | ノイズ知識抑制 | 中 | レビュー負荷増 | 部分重複 |
| A6 | LLM中立ディレクトリ仕様の外部PJ共通化 | ツール横断の引継ぎ統一 | 高 | queue/projectsと二重SSOT化 | 高重複 |

## 上位3案

1. A3（軽量SDDゲート）
- 理由: 現行cmd配備フローへ自然に接続でき、手戻り削減の直接効果が大きい。

2. A1（HANDOFF運用標準化）
- 理由: マルチPC/マルチCLIでの再開ロスへ直撃。用途定義を切ればinboxと共存可能。

3. A4（bootstrapスキル）
- 理由: 低コスト・即効性。外部PJ展開時の品質下限を引き上げやすい。

## 見送り優先

- A6は現行設計と重複が高く、二重SSOTリスクが高いため現時点では見送り推奨。

---

# cmd_504 Qiita偵察B（sasuke）

- source: https://qiita.com/ProgrammingForEver/items/ee68fc621f7d1c53ffe1
- fetched_at: 2026-03-04 00:25 JST
- scope: 記事の設計思想を multi-agent-shogun(infra) へ移植可能か評価
- independence: 原文（Qiita記事）を主資料として抽出

## 抽出案（6件）

| id | 案 | 期待効果 | 導入コスト | 競合リスク | 既存仕組みとの重複 |
|---|---|---|---|---|---|
| B1 | HANDOFF固定名+世代アーカイブを「復帰専用ログ」に限定導入 | セッション再開時の判断復元を高速化 | 中 | inbox/reportsと用途境界が曖昧だと二重運用 | 部分重複 |
| B2 | AGENTS↔MEMORY重複検出の自動lint（行数上限監視付き） | 記憶ノイズ/重複記載を抑制し復帰品質を安定化 | 低 | 判定厳格すぎると有用メモまで警告化 | 部分重複 |
| B3 | 配備前ミニSDDゲート（PLAN草案→SPEC確定→TODO分解） | 曖昧指示起因の手戻り削減、ACの明確化 | 中 | 緊急hotfixで初動遅延の可能性 | 部分重複 |
| B4 | 外部PJ向け `.agent` 互換パック（memory/handoff/workflow）標準雛形 | マルチPC/マルチLLMの横展開を高速化 | 高 | 現行queue/projectsをSSOTにしている運用と競合 | 高重複 |
| B5 | `project-init` スキルに preflight（Git URL/同期手段/ignore）を標準搭載 | 新規PJ初期化の品質ばらつきを抑制 | 低 | switch-project/reset系と責務重複しうる | 部分重複 |
| B6 | Before/After運用KPI（再開時間・再説明回数・手戻り率）を定点計測 | 改善施策の有効性を定量比較可能 | 低 | 計測項目追加で報告負荷増 | 低重複 |

## 上位3案

1. B3（配備前ミニSDDゲート）
- 理由: 品質ばらつきに直接効き、既存AC運用へ接続しやすい。

2. B2（AGENTS↔MEMORY重複lint）
- 理由: 低コストで復帰品質の劣化要因（重複/行数逼迫）を先回り抑止できる。

3. B5（project-initスキル強化）
- 理由: 初期構築の再現性を短期で底上げでき、横展開効果が高い。

## 見送り優先

- B4は現行infraのSSOT構造との競合リスクが高く、設計整理前の導入は見送り推奨。

---

# cmd_504 家老統合判定

- integrator: karo
- timestamp: 2026-03-04 00:27
- recon_a: kagemaru (6案: A1-A6)
- recon_b: sasuke (6案: B1-B6)

## 一致/不一致分析

### 独立一致（2名が独立して同一結論）

| 対応 | 概要 | A順位 | B順位 | 統合判定 |
|------|------|-------|-------|----------|
| A3=B3 | 配備前SDDゲート（PLAN→SPEC→TODO段階化） | 1位 | 1位 | **採用候補1位** |
| A4≈B5 | PJ初期化スキル強化（bootstrap/preflight） | 3位 | 3位 | **採用候補3位** |
| A6≈B4 | LLM中立/.agent互換パック | 見送り | 見送り | 見送り（高重複一致） |
| A1≈B1 | HANDOFF/復帰専用ログ | 2位 | 圏外 | 要検討（一致だが優先度差） |

### 不一致（片方のみ提案）

| 案 | 提案者 | 概要 | 統合判定 |
|---|--------|------|----------|
| B2 | 佐助独自 | AGENTS↔MEMORY重複検出lint | **採用候補2位**（低コスト・即効性） |
| B6 | 佐助独自 | Before/After運用KPI定点計測 | 検討（既存gate_metricsで部分カバー） |
| A2 | 影丸独自 | AGENTS不変ルール分離 | 既存で概ね実現済（CLAUDE.md=恒久/context=運用） |
| A5 | 影丸独自 | キュレーション手順明文化 | 既存で部分実現済（/shogun-memory-teire, lesson-sort） |

## 既存基盤との重複除外

| 案 | 既存仕組み | 重複度 | 真の新規性 |
|---|-----------|--------|-----------|
| A3/B3 SDDゲート | acceptance_criteria + Five Questions | 部分 | **PLAN→SPEC段階化は未統一。新規性あり** |
| B2 重複lint | gate_shogun_memory.sh（行数監視のみ） | 低 | **AGENTS↔MEMORY重複検出は未実装。新規性あり** |
| A4/B5 PJ初期化 | switch-project（切替のみ） | 部分 | **初期構築品質ゲートは未実装。新規性あり** |
| A1/B1 HANDOFF | karo_snapshot + inbox + reports | 中 | セッション継続知識の単一窓口は弱いが、snapshot改善で代替可能 |
| A6/B4 LLM中立 | 現行YAML中心運用 | 高 | 新規性低。現行で概ね実現 |

## 統合結論 — 即実装候補（優先順）

1. **SDDゲート**（A3/B3一致）: 配備前のPLAN→SPEC→TODO段階化。既存ACフローに統合。中コスト・高効果
2. **AGENTS↔MEMORY重複lint**（B2独自）: 低コスト・即効性。gate_shogun_memory.shの拡張として実装可能
3. **PJ初期化スキル強化**（A4/B5一致）: project-initにpreflight搭載。低コスト

### 見送り

- A6/B4（LLM中立パック）: 高コスト・高重複。現行で代替済
- A1/B1（HANDOFF）: karo_snapshot改善で代替可能。独立導入は二重運用リスク
- A2/A5: 既存仕組みで概ね実現済

## 付録: 次cmd候補（実装CMD草案）

```yaml
# cmd_506候補: SDDゲート導入
- title: "配備前SDDゲート（PLAN→SPEC→TODO）をdeploy_task.shに統合"
  type: enhance
  project: infra
  priority: medium
  acceptance_criteria:
    - ac1: "deploy_task.shにtask_type=implementかつscout_exempt=falseの場合、PLAN/SPEC確定チェックを追加"
    - ac2: "cmd YAMLにspec_confirmed: trueフラグがない場合はWARN出力（BLOCK化は段階導入後）"
    - ac3: "緊急対応(priority=critical)はゲート免除"
  notes: "2名独立一致。既存ACフローの上流に軽量ゲートを追加"

# cmd_507候補: AGENTS↔MEMORY重複lint
- title: "gate_shogun_memory.shに重複検出lintを追加"
  type: enhance
  project: infra
  priority: low
  acceptance_criteria:
    - ac1: "CLAUDE.md↔MEMORY.md間の重複行を検出し、WARNレベルで出力"
    - ac2: "閾値: 類似度25%以上の行ペアを検出"
  notes: "佐助独自提案。低コスト即効性"

# cmd_508候補: project-init preflight
- title: "switch-projectスキルにpreflight品質ゲートを追加"
  type: enhance
  project: infra
  priority: low
  acceptance_criteria:
    - ac1: "PJ切替時にprojects/{id}.yaml/context/{id}.md/lessons.yamlの存在チェック"
    - ac2: "不足ファイルの雛形自動生成(confirmation付き)"
  notes: "2名独立一致。低コスト"
```
