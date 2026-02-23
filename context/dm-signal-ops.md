# DM-signal 運用コンテキスト
<!-- last_updated: 2026-02-23 cmd_280 dm-signal.md分割 -->

> 読者: エージェント。推測するな。ここに書いてあることだけを使え。

コア定義(§0-5,8,10-11,13,15,18) → `context/dm-signal-core.md`
研究・検証結果(§19-21) → `context/dm-signal-research.md`

## 6. recalculate_fast.py Phase別処理フロー

ファイル: `backend/app/jobs/recalculate_fast.py`
殿の制約: 全PF×全日を計算（差分計算・PF数削減・日数間引き禁止）

```
recalculate_history_fast()
│
├─ Phase0 (L694)  クリーンアップ
│   └─ _cleanup_before_recalculate(): DELETE(独立COMMIT)
│      ⚠ L038/L039: DELETE→INSERT間でOOM/redeployするとデータ消失
│
├─ Phase1 (L702)  データロード
│   └─ _load_all_prices(): 全銘柄の価格データをDBから一括ロード
│
├─ Phase1.5 (L740)  有効開始日決定
│   └─ 各PFの計算開始日を決定
│
├─ Phase2 (L827)  前処理 + MomentumCache初期化
│   └─ pivot + 全期間モメンタム事前計算。PriceCacheの構築
│
├─ Phase2.5 (L867)  MonthlyProductMomentumCache
│   └─ 月次プロダクトモメンタムのキャッシュ構築
│
├─ Phase3 (L903)  Pipeline モメンタムCache事前計算 (OPT-A)
│   └─ 全BBブロック×全ティッカーの事前計算
│
├─ Phase3.5 (L1166)  Pipeline block事前解決 (OPT-A)
│   └─ 各PFのpipeline_configからブロック設定を事前解決
│
├─ Phase3.7 (L1178)  ★OPT-E: Vectorizedシグナル事前計算
│   └─ _precompute_pipeline_signals()
│      全pipeline PFの全日付シグナルを1パスで事前計算→dictに格納
│      データ構造: Dict[str, Dict[date, str]] (L1185)
│      → Phase4ではO(1) dict lookupのみ
│      → miss時: 日次フォールバック→execute_pipeline_with_blocks (L1718-1738)
│
├─ Phase4 (L1508)  L2日次ループ（シグナル+パフォーマンス計算）
│   └─ 全日付×全PFをループ
│      OPT-E PF: Phase3.7のdict lookup (O(1))
│      Legacy PF: determine_signal_fast()
│      ボトルネック: trade_perf (58.7s) ← signal_calcは0.53sで脱落
│
├─ Phase4.5 (L1909)  月次リターン計算
│   └─ 月次リターンの集計・書込
│
├─ Phase5 (L1921)  L3 FoF再計算 (~89s)
│   └─ L2シグナルを集約→FoFシグナル+パフォーマンス計算
│
└─ Phase5 precompute (L1958)  プリコンピュートテーブル
    └─ パフォーマンスデータの事前計算テーブル生成
```

## 7. OPT-Eアーキテクチャ

### 概要

OPT-E = Phase3.7で全pipeline PFの全日付シグナルを**1パスで事前計算**し、Phase4では**O(1) dict lookup**で取得する最適化。signal_calc時間を**1,724s→0.53s（3,786倍高速化）**。

### 実装構造

```
Phase3.7: _precompute_pipeline_signals()
  ├─ 入力: pipeline PF一覧, 全日付リスト, momentum_cache
  ├─ 処理: 全PF×全日付でexecute_pipeline_with_blocks()を1回呼び
  ├─ 出力: vectorized_pipeline_signals: Dict[str, Dict[date, str]]
  │         key=portfolio_id, value={date: signal_string}
  └─ bisect: _dict_lookup_with_bisect (L509-523)
             target_date以前の直近日を検索(休日対応)

Phase4: dict lookup
  ├─ hit → O(1)でsignal取得
  └─ miss → 日次フォールバック: execute_pipeline_with_blocks (L1718-1738)
             ※91c04a4で追加(L045対応)
```

### バグ修正履歴

| Commit | 問題 | 修正 | 教訓 |
|--------|------|------|------|
| dc35b83 | OPT-E初期実装 | — | — |
| f452c23 | ReversalFilter方向逆転 | top_n降順→bottom_n昇順 | L045 |
| 151345c | bisectフォールバック消滅 | dict厳密一致→旧パスのbisect復元 | L045 |
| 91c04a4 | 112件signal消失 | Phase4にcontinue→日次フォールバック追加 | L045 |

### 112件signal消失の調査経緯

**症状**: OPT-E適用後、signal行が112件減少。

**調査過程**:
1. L045仮説: Phase3.7のdict厳密一致参照で旧パスのbisect(target_date以前の直近日)フォールバックが消滅→151345cで修正→**効果なし**
2. L045真因特定: Phase4のOPT-E経路でpre-computed dictにdate keyが無い場合`continue`で行をスキップ。旧パスのPipelineEngineは空集合でもSafeHaven/Terminal blocksでsignal値を返すため、`continue`は旧パスと非等価
3. 修正(91c04a4): continueの代わりに日次フォールバック(`execute_pipeline_with_blocks`)を実装→1件の差異も不可（殿の裁定）

**教訓**: 最適化でskipするパスが旧ロジックと等価か必ず検証せよ。

## 9. 性能ベースライン

### 再計算性能推移

| 段階 | 全体 | signal_calc | 備考 |
|------|------|-------------|------|
| 初回ベースライン | 11,818s (3h17m) | — | — |
| OPT-A/D/F適用 | 2,397s (40m) | 2,007s | Phase3事前計算 |
| OPT-E適用 | 389s (6m30s) | 0.53s | **3,786倍高速化** |

### 現在のボトルネック (OPT-E後)

| 項目 | 時間 | 比率 |
|------|------|------|
| trade_perf | 58.7s | **新ボトルネック** |
| signal_calc | 0.53s | 脱落 |
| L3 FoF | ~89s | OPT-E対象外 |

### 注意事項

- ローカル→シンガポールDBでの再計算は197分（ネットワーク遅延支配的）(L041)
- 効果検証はRender上(DB同一サーバ)で行うべき
- フル計算を毎回待つな。2年テスト(2024-01-01〜)で計測→改善→再テストのサイクルを回せ

## 12. 計算データ管理の原則

殿の5原則: 再現性100%、データ+インデックス、第三者可読、上書き禁止、過剰設計回避。

### 命名規則

```
{cmd番号}_{ブロック名}_{説明}.csv      — GS結果
{cmd番号}_{ブロック名}_{説明}.meta.yaml — CSVと同名・同ディレクトリ
```

ブロック号名: bunshin(分身) / oikaze(追い風) / nukimi(抜き身) / monban(門番) / kasoku(加速) / kawarimi(変わり身)

### 運用ルール

1. **上書き禁止**: 既存ファイルと同名のファイルを出力してはならない。再実行は`_v2`サフィックス等で区別
2. **meta.yaml必須**: 全計算出力に`.meta.yaml`を添付。入力/パラメータ/実行日時/スクリプトパス/MD5ハッシュを記録
3. **カタログ追記必須**: 新ファイル出力時に`DATA_CATALOG.md`の「Active Catalog」テーブルへ行を追加
4. **旧データ参照禁止**: 035/036/037/038/053/058/066/069/070は歴史的参考のみ。分析の根拠に使わない

### テンプレートスクリプト

パス: `scripts/analysis/grid_search/template_gs_runner.py`

コピー&リネームで即使用可能。4セクション構成:
1. PARAMETERS（書き換え必須: CMD_ID, BLOCK_NAME, PARAM_GRID等）
2. Utilities（変更不要: load_monthly_returns, calc_metrics, write_meta_yaml, append_data_catalog）
3. Block Logic（書き換え: simulate_pattern, build_grid, pattern_to_row）
4. Main（変更不要: 上書き防止+進捗表示+CSV→meta→カタログ3段出力）

### 共通CSVローダー (cmd_160)

パス: `scripts/analysis/grid_search/gs_csv_loader.py`

全GSスクリプト(monban除く6本)はsqlite3/experiments.dbに依存せず、CSV直接読込で動作する。

```python
# 主要関数
load_monthly_returns_from_csv(component_spec, return_kind='open', drop_latest=False) → Dict[str, pd.Series]
load_monthly_returns_dual_from_csv(spec_open, spec_close=None, close_fallback='open') → Tuple[Dict, Dict]
build_wide_component_spec(csv_path, column_names, year_month_col='year_month') → Dict
get_csv_provenance(csv_paths) → Dict  # meta.yaml用
```

データソース: `outputs/grid_search/064_champion_monthly_returns.csv` (暫定。12パターン×143ヶ月)
- DM_IDS(UUID辞書) → COMPONENT_SOURCES(component_spec辞書)に置換済み
- meta.yaml: db_md5 → csv_provenance + source_type: csv_direct
- GS高速化知見: `context/gs-speedup-knowledge.md`

### ブロック別GSスクリプト

全6ブロックのGSスクリプトが `scripts/analysis/grid_search/run_077_{block}.py` に配置済み。
詳細（パラメータ空間・本番Parity・対応ソース）: `DATA_CATALOG.md` C-7参照。

PD-028裁定（2026-02-23）:
- GS制約同期は仕組み化しない。
- 運用は「BBカタログにPydantic制約を明記」+「各GSスクリプトのPARAM_GRIDを制約範囲へ修正」で対応する。

### データカタログ

パス: `outputs/grid_search/DATA_CATALOG.md`

前提知識なしで全データの概要を把握できるように構造化。Active Catalog（cmd_071以降）/ Existing Analysis Data（040-064）/ Historical Reference（035-070）/ Legacy（cmd以前）の4層。System Definition C-1〜C-7でデータソース/共通ルール/四神設定/ブロック定義/パラメータ空間/分析フレームワーク/スクリプト一覧を定義。

### 堅牢性検証ツール（承認済み・未実装）

- 構造的SUSPECT検出+自動Ban機能: 設計書 `docs/skills/structural-suspect-ban.md`
- 条件: Ban履歴ログ必須、誤Ban防止安全機構必須。設計書→承認→実装の流れ

## 14. 既存ドキュメントインデックス

> cmd_195で佐助(skills)・霧丸(rule)の偵察報告から統合。圧縮索引（ポインタ+1-2行要約）。

### docs/skills/ (25件)

| ファイル | 目的 | 優先度 | マーカー |
|---------|------|--------|---------|
| _INDEX.md | skills全体の目次と更新導線の集約 | high | — |
| api-reference.md | バックエンドAPIの包括リファレンス。認証・エンドポイント・環境設定 | high | API |
| building-block-addition-guide.md | 新規BB追加の実装チェックリスト(BE→registry→FE型→ドキュメント) | high | — |
| building-block-pattern.md | FoFパイプライン設計原則。Selection/Terminal分離、13ブロック構成 | high | — |
| database-schema.md | 本番DBスキーマ・信頼度・整合性ルール。29テーブル、SSOT=monthly_returns | high | DB, PARITY |
| environment-switching.md | ローカル/本番環境切替と検証手順。DATABASE_URL・認証変数・Render設定 | high | DB, API |
| fof-pipeline-troubleshooting.md | FoFパイプライン不具合の症状別トラブルシュート集 | high | — |
| portfolio-analysis-idea-loop.md | 分析→アイデア→検証のPF改善ループ。Sortino超え/Return最大化2トラック | high | API |
| portfolio-analysis-verification.md | PF構造確認・比較・検証の総合リファレンス。3視点独立評価 | high | API, PARITY, DB |
| structural-suspect-ban.md | GSにおける構造的SUSPECT自動Ban機能の設計 | high | — |
| Agent Skills.md | Agent Skills標準の概念・作成方法の入門 | medium | — |
| best-practices.md | Skills/CLAUDE.md/AGENTS.mdの役割分離と文書作法の標準化 | medium | — |
| passive-context-index-standard.md | AGENTS.md中心の受動コンテキスト設計標準 | medium | — |
| password-expiry-management.md | Tier課金連動のパスワード有効期限管理パターン | medium | — |
| tier-visibility-control.md | Tier別可視性制御(L1-L4)実装パターン | medium | — |
| knowledge-01〜06.md | 戦略背景知識(トレンド/MR/リセッション/FoF設計/補完戦略/予備) | low | — |
| document-naming-convention.md | docs配下の命名規則とステータス運用 | low | — |
| performance-audit.md | HARを使う定期パフォーマンス監査手順 | low | — |
| performance-measurement.md | 計測・レポート・改善反映の定量評価ワークフロー | low | — |
| skills-creation-guide.md | skills文書の新規作成/更新/削除手順 | low | — |

### docs/rule/ (25件)

| ファイル | 目的 | 優先度 | マーカー |
|---------|------|--------|---------|
| _INDEX.md | rule配下の全体地図と優先読了順 | high | — |
| trade-rule.md | signal/holding/rebalance/return計算の絶対ルール(RULE01-11)。**最重要SSOT** | high | — |
| calculation-theory.md | リターン計算理論の正規定義(Level0-3データソース階層) | high | — |
| business_rules.md | 業務ルール包括定義(データ/計算/UI/FoF/可視性) | high | — |
| check-rule.md | Truth-Based検証ルール標準化。Stock API=Truth(D)、bp閾値判定 | high | PARITY |
| database-info.md | DB構造・テーブル役割・データフロー明文化 | high | DB |
| DTB3-guide.md | DTB3リスクフリーリターン計算仕様。FRED年率→日次→21D月次変換 | high | — |
| gs-parity-verification-guide.md | GSエンジンと本番計算の一致検証手順。simulate_strategy_vectorized突合 | high | PARITY |
| api-usage-guide.md | Stock Data Platform API利用規約・制約・エンドポイント仕様 | high | API |
| rebalance-verification.md | rebalance_trigger準拠とsignal/holding整合の検証 | high | PARITY |
| requirements-spec.md | 機能要件・技術構成・データモデル・API要件の基準定義 | high | — |
| return-consistency-verification.md | RULE11(Return同一性)の検証と不一致調査手順 | high | PARITY |
| local-postgresql-guide.md | ローカルPostgreSQL環境の構築・クローン・運用手順 | medium | DB |
| local-verification-guide.md | 本番API依存を減らしたローカル検証フロー | medium | — |
| ninpou-fof-creation-runbook.md | 忍法FoF(L3)作成・登録・検証の標準手順 | medium | — |
| portfolio-naming-convention.md | PF命名規則統一(日次/月次プレフィックス、四神/L2忍法パターン) | medium | — |
| renderyaml_guide.md | Renderデプロイ時の接続設定ベストプラクティス | medium | — |
| rule.md | ドキュメント作成時の必須参照・テンプレート・禁止事項 | medium | — |
| security-status.md | セキュリティ実装現状(認証・可視性・レート制限) | medium | — |
| shijin-pf-creation-runbook.md | 四神PF作成のGS→抽出→変換→登録→再計算手順 | medium | — |
| timing-and-bottleneck-analysis.md | Layer別計測とボトルネック分析手順 | medium | — |
| design.md | デザインシステム(ダークテーマ)規定 | low | — |
| design-light.md | ライトモードのデザイン原則と配色仕様 | low | — |
| design-list.md | 現行デザイン実装の統一状況と基準値 | low | — |
| design-list-light.md | ライトモードの実装チェックリスト | low | — |

### 重要ルール抜粋（DB接続・パリティ検証・API使用法）

**DB接続ルール**:
- 本番データ参照・書き込みはPostgreSQL(`DATABASE_URL`)を正とし、`dm_signal.db`への書き込みは禁止
- 価格truthは`experiments.db`(daily_prices)、PF設定truthは`dm_signal.db`(portfolios)を使い分ける
- ローカルPostgreSQL環境: Docker起動、pg_dump/restore前提 → `docs/rule/local-postgresql-guide.md`
- 本番データ読み取りもDATABASE_URL直接接続。Render HTTP API経由禁止(L064)

**パリティ検証ルール**:
- `monthly_returns`をSSOTとして整合性検証(annual=Π(1+monthly)-1)を優先 → `docs/skills/database-schema.md`
- Stock APIをTruth(D)に据え、A/C/D比較で検証。bp閾値でPASS/FAIL判定 → `docs/rule/check-rule.md`
- GS-本番パリティ: `simulate_strategy_vectorized`とmonthly_return_open突合が正道 → `docs/rule/gs-parity-verification-guide.md`
- rebalance_trigger別(月次/隔月/四半期/FoF)に検証観点+FAIL条件定義 → `docs/rule/rebalance-verification.md`
- RULE11(Return同一性)の株価計算値・DB値・UI表示の差分診断 → `docs/rule/return-consistency-verification.md`
- 3視点独立評価(return/downside/UD比)で交差点候補判定 → `docs/skills/portfolio-analysis-verification.md`

**API使用法ルール**:
- 検証時は本番API(`https://dm-signal-backend.onrender.com`) + Basic認証を使用 → `docs/skills/api-reference.md`
- 認証情報は環境変数(ADMIN_USER/ADMIN_PASS等)経由。ハードコード禁止
- Stock Data Platform: rate limit、auto_fetch差分、ページング仕様 → `docs/rule/api-usage-guide.md`
- ローカル/本番環境切替手順: DATABASE_URL・Render設定 → `docs/skills/environment-switching.md`

## 16. 知識基盤改善（穴1/2/3対策完了 — 2026-02-22）

DM-signal教訓管理に影響するインフラ改善。3つの「穴」を全て対策済み。

| 穴 | 問題 | 対策 | cmd |
|----|------|------|-----|
| 穴1 | 教訓登録ボトルネック(忍者→家老の手動フロー) | `auto_draft_lesson.sh`自動draft登録 + confirmed化 | cmd_232 + cmd_242 |
| 穴2 | 知識鮮度管理の欠如 | `context/*.md`のlast_updated管理 + `deploy_task.sh`実行時の鮮度警告 | cmd_239 |
| 穴3 | 裁定伝播遅延(PD解決→context未反映) | `pending_decision_write.sh` resolve時にcontext未反映フラグ自動追記 + `cmd_complete_gate.sh`がWARNING | cmd_239 |
| 補助 | lesson sync上限不足 | sync上限を50に引き上げ | cmd_241 |

原則: 検出+警告のみ。自動修正はしない（指示系統厳守）。

## 17. 現在の全体ステータス（2026-02-22）

| 項目 | 状態 |
|------|------|
| L0 GS生成PF | ~30体(本番登録済み) |
| L1 四神12体 | 本番登録済み+パリティPASS |
| L2 忍法12体 | 本番登録済み+全12体 0.00bp PASS(cmd_246) |
| 本番PF総数 | 89体(上限100) |
| L3 堅牢性検証 | 未着手(cmd_176殿裁定待ち) |
| 新忍法偵察 | 逆風(cmd_249)/RelMom(cmd_250)/MultiView(cmd_251)偵察中 |
| SVMF/MVMFバグ | 修正完了(cmd_235+cmd_244) |
| 穴1/2/3 | 全対策完了 |
