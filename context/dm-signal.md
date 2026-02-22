# DM-signal コンテキスト

> 読者: エージェント。推測するな。ここに書いてあることだけを使え。

タスクに `project: dm-signal` がある場合このファイルを読め。パス: `/mnt/c/Python_app/DM-signal/`

## 0. 研究レイヤー構造

| Layer | 名前 | 内容 |
|-------|------|------|
| L1 | 基本PF発見 | 個別DM戦略（青龍/朱雀/白虎/玄武）のパラメータGS・検証 |
| L2 | 忍法FoF | 5忍法(分身/追い風/抜き身/変わり身/加速)×3モード(激攻/鉄壁/常勝)のGS・登録。命名: {忍法名}-{モード} |
| L3 | 組合せ堅牢化 | 上位構造の堅牢性検証（WF優先。FoFは乗り換え戦略のため時間軸評価が本質。CPCVは補助） |

## 1. システム全体像

```
[本番] Render.com
  PostgreSQL (dm_signal) ← StockData API (毎日01:00 UTC自動同期)
  FastAPI backend ← Next.js frontend

[ローカル] WSL2
  dm_signal.db   ← 本番PostgreSQLミラー(手動DL)
  experiments.db ← StockData APIからDL(分析用)
```

本番日次パイプライン:

| Layer | 時刻(UTC) | ジョブ | 内容 |
|-------|-----------|--------|------|
| 0 | 01:00 | sync-prices | StockData APIから価格DL |
| 1 | 01:05 | sync-tickers | ティッカーメタデータ同期 |
| 2 | 01:10 | sync-standard | 個別DM戦略シグナル計算 |
| 3 | 01:40 | sync-fof | FoFシグナル計算 |

## 1.5. 再計算の排他制御（重要）

本番の再計算(recalculate-sync)は**排他制御が効いている**。同時に2つの再計算は走らない。

| 状況 | 結果 | 対応 |
|------|------|------|
| 再計算中に別のrecalculate要求 | **HTTP 409 Conflict** で即拒否 | 30秒待って再実行。パニック不要 |
| sync-standard実行中にsync-fof要求 | レイヤー依存チェックで拒否 | L2完了を待つ |
| 409を受けた | 正常な排他動作 | **FAILではない。報告にエラーと書くな** |

仕組み: `recalc_status.py` の `threading.Lock` + `start_recalculation()` で原子的排他。
詳細: `projects/dm-signal.yaml` (c) database → recalculate_concurrency を参照。

## 2. DB地図

> 核心ルール(接続先/書き込み禁止等) → `projects/dm-signal.yaml` (c) database を読め。

### 追加詳細（projects/dm-signal.yamlに含まれない情報）

**experiments.db テーブル詳細**:

| テーブル | 行数 | 内容 | 信頼度 |
|---------|------|------|--------|
| daily_prices | 414K | OHLCV日次価格(86銘柄) | **価格ground truth** |
| monthly_returns | 14K | バックテスト月次リターン | 本番APIからDL済み |
| download_metadata | 3 | 最終DL日時 | — |
| signal_history | 0 | 空 | — |
| trades | 0 | 空 | — |

DLコマンド:
- 価格DL: `python scripts/analysis/data_sync/download_all_prices.py grid-search`
- 月次リターンDL: `python scripts/analysis/data_sync/download_prod_data.py monthly-returns`
- `download_prod_data.py prices` → 422エラー。**使うな。** `download_all_prices.py`を使え（cmd_042で判明）

**dm_signal.db テーブル詳細**:

| テーブル | 行数 | 内容 | 信頼度 |
|---------|------|------|--------|
| portfolios | 19 | PF設定(UUID, config JSON) | **PF設定ground truth** |
| signals | 30K | 日次シグナル+モメンタム | 本番ミラー |
| monthly_returns | 1.5K | 本番計算月次リターン | 本番ミラー |
| prices | **40** | テストデータのみ(AGG/SPY各20行) | **使うな** |
| performance | 42K | 日次パフォーマンス | 本番ミラー |

**本番PostgreSQL完全接続情報**:
- ホスト: `dpg-d542chchg0os73979vg0-a.singapore-postgres.render.com`

**UUID不一致警告**: 2つのDBのUUIDは**DM7+以外は異なる**（§3参照）

## 3. 四神（しじん）構成

### 四神の本質（最重要 — 全エージェント必読）

四神は単なるポートフォリオ定義ではない。各DMファミリーの全パラメータ
総当たりGS（172,818パターン）からGreedy Forward Selectionで選ばれた
チャンピオン戦略を均等配分で組み合わせたFoFである。

| 四神 | 構成 | チャンピオン戦略 | FoF CAGR |
|------|------|----------------|----------|
| 青龍 | DM2 FoF n=3 | Qj_GLD_10D_T1, Qj_XLU_11M_5M_1M_w50_30_20_T1, Be_GLD_18M_7M_1M_w60_30_10_T1 | 59.5% |
| 朱雀 | DM3 FoF n=2 | M_TMV_4M_3M_20D_w50_40_10_T1, Qj_TMV_3M_15D_w50_50_T1 | 40.0% |
| 白虎 | DM6 FoF n=2 | Qj_XLU_15M_3M_w70_30_T2, Qj_GLD_4M_1M_w50_50_T1 | 54.7% |
| 玄武 | DM7+ Prod n=1 | M_SPXL_XLU_24M_T1 | 29.5% |

選定手法: Greedy Forward Selection（CAGR最大化で順次追加、改善停止で終了）
堅牢性検証: SUSPECT検出（パラメータ近傍比較、孤立ピーク排除）
参照: DM-signal/docs/portfolio-research/ 015→016→017→019→021
選定スクリプト: scripts/analysis/grid_search/max_cagr_fof_search.py
FoF構成詳細: docs/portfolio-research/023 §2.3

### 命名規則（殿裁定 2026-02-20）

| 階層 | 形式 | 例 |
|------|------|-----|
| L1四神FoF | {モード}-{四神名} | 激攻-青龍, 鉄壁-朱雀 |
| L2忍法FoF | {忍法名}-{モード} | 加速-激攻, 分身-鉄壁 |

モード: 激攻(CAGR) / 鉄壁(MaxDD) / 常勝(NewHigh)
同一config集約: 全モード同一→忍法名のみ。2モード同一+1異なる→同一側無印+異なる側にモード付与。
旧サフィックス(-Dd/-Nh/-C/-So/-Sh)は廃止。

現四神 = CAGRモード（激攻）のみ。
12パターン計画: 4神 × 3モード（激攻/鉄壁/常勝）。
L2忍法FoF: 5忍法(分身/追い風/抜き身/変わり身/加速) × 3モード = 最大15体。monban除外。nukimi_c→nukimiに統合(L054)。
※ 智将(Calmar)→鉄壁(MaxDD)変更理由: Spearman相関分析でCalmarはCAGRと高相関(rho=0.86)で冗長。MaxDDはCAGRと低相関(rho=0.49)で独自軸。

⚠ L1/L2混同禁止:
- L1 = 神の中身（GSパラメータ: lookback/safe_haven/rebalance/topN）
- L2 = 神の組み合わせ（ビルディングブロック: omote/am/svm/acc/ura）
- FoFレベルのブロックを個別の神に適用しても意味がない

### ポートフォリオ一覧

| 四神 | 名前 | dm_signal.db UUID | experiments.db UUID | 戦略 |
|------|------|-------------------|---------------------|------|
| 青龍 | DM2 | f8d70415 | 4db9a1f5 | ロング株式 |
| 朱雀 | DM3 | c55a7f68 | 8300036e | ロングVol/債券 |
| 白虎 | DM6 | 212e9eee | a23464f7 | VIXレジーム |
| 玄武 | DM7+ | 8650d48d | **8650d48d(同一)** | リセッション防御 |

### 銘柄構成

> UUID・銘柄構成・リバランス設定 → `projects/dm-signal.yaml` (e) shijin を読め。

全銘柄: GLD|LQD|SPXL|SPY|TECL|TMF|TMV|TQQQ|XLU|^VIX

### シグナル生成フロー（例: DM2）

```
1. MomentumFilterBlock: TQQQ/TECLの12ヶ月モメンタム比較 → top1選択
2. AbsoluteMomentumBlock: LQDモメンタム > DTB3(リスクフリー)か？
   → YES: 選択銘柄パススルー → NO: 空（キャッシュ）
3. SafeHavenSwitchBlock: 空なら → XLU(セーフヘイブン)に切替
4. EqualWeightBlock(分身の術): 100%配分 → signal="TQQQ" or "XLU"
```

## 4. ビルディングブロック

> ブロック型カタログ(14型: Selection 11 + Terminal 3)・標準パターン → `projects/dm-signal.yaml` (d) pipeline を読め。

パス: `backend/app/services/pipeline/blocks/`
BlockType enum定義: `backend/app/schemas/pipeline.py:18-37`
ブロック登録: `backend/app/jobs/shared.py:208-253`

### top_n同点時のtiebreakルール（cmd_217, L092補強）

本番のselection blockは、top_n境界で同点が出たときに次の2方式で動作する。

- **cutoff_score全包含方式**: 境界スコアと同点の銘柄は全て採用し、`top_n`超過を許容する。
- **strict slice方式**: 厳密に`top_n`/`worst_n`件だけを切り出す。

忍法FoFの対応は以下。

- 追い風（`MomentumFilterBlock`）: cutoff_score全包含
- 抜き身（`SingleViewMomentumFilterBlock`）: cutoff_score全包含
- 加速（`MomentumAccelerationFilterBlock`）: cutoff_score全包含
- 変わり身（`TrendReversalFilterBlock`）: strict slice

補足:
- `MultiViewMomentumFilterBlock` と `MonthlyReturnMomentumFilterBlock` も cutoff_score全包含方式。
- 変わり身のみ本番実装がstrict sliceのため、GS側もstrict sliceで一致させる。
- L092補強: float64同値タイでtop/worst重複が出る場合、ハイブリッド方式（基本=desc/asc別ソート、重複時=desc単一リスト両端スライス）で本番挙動に寄せる。

GS修正経緯（cmd_215 → cmd_217）:
- cmd_215でtop_n境界同点時のパリティ差分を検知。
- cmd_217で影丸・霧丸の偵察結果を統合し、方式差（cutoff_score vs strict slice）を確定。
- 追い風はcommit `9277881`で修正済み、加速はcutoff_score適用済み、抜き身はcmd_217 Phase 3で修正継続。

### GS-本番パリティ統一原則（cmd_229: PD-011/012/013）

#### 全忍法の計算方式統一（AC1/PD-013）

- 対象忍法: 追い風・抜き身・加速・変わり身。
- 上記4忍法は、**cumulative_return → pct_change** 方式で統一する。
- 分身（`EqualWeightBlock`）はこの統一対象外（モメンタム選抜を持たない）。
- 旧方式（`monthly_return`直接取得、`dropna`前提、NaN除外で成立させる計算）は禁止。

#### 504日閾値の厳守（AC2/PD-011）

- GS側も本番同様、**504日分の日次データが揃うまでCash扱い**とする。
- 月次蓄積で先行して有効値を作る近道は不可。
- とくに長lookback（12M/24M）では、初期化期間の扱い差が大きな乖離を生むため厳守する。

#### モメンタム計算パス統一（AC2/PD-012）

- GS側も本番と同じく、`cumulative_return`系列から `pct_change(mc)` でモメンタムを算出する。
- `monthly_return`を直接使う方式は、本番コードパスと一致しないため不採用。
- 「数学的に近い」実装より「本番と同一コードパス」を優先する（`projects/dm-signal.yaml` L076原則）。

#### パリティ教訓の原則要約（AC3: L086-L092）

- L086: top_n同点は `cutoff_score` 全包含方式を基本にし、本番 `MonthlyReturnMomentumFilterBlock` 準拠で揃える。
- L087: 長lookback（12M/24M）でGS-本番の初期化期間差異が顕在化しやすい。
- L089: パリティ検証はデータソース一致が前提。比較両辺で同一ソースを使う。
- L090: GS `monthly_return` NaN系と本番 `cumulative_return` 系で、選出コンポーネント数が変わり得る。
- L091: GSモメンタムは `cumulative_return` ratio方式を使う（prod方式はタイブレーク不一致を誘発）。
- L092: float64同値タイはハイブリッド方式で重複を抑止し、strict slice実装と整合させる。

### パイプライン実行

```python
PipelineEngine.execute_pipeline(
    pipeline_config,   # PipelineConfig (selection_pipeline + terminal_block)
    target_date,       # シグナル算出日
    initial_tickers,   # 候補銘柄リスト
    price_data_cache,  # 事前ロード済み価格（FoF用）
    momentum_cache     # 事前計算済みモメンタム
) → {signal, momentum_data, block_results, weights}
```

**PipelineContext** — 全ブロック間共有の黒板パターン:
- `current_tickers`: 選択フェーズで徐々に絞られる
- `momentum_data`: 各ブロックのモメンタム計算結果
- `final_weights`: TerminalBlockが決定する最終配分

### signal vs holding_signal

- **signal**: パイプライン生出力（例: "TQQQ"）
- **holding_signal**: リバランス月でなければ前月維持。MonthlyReturnはこちらで計算せよ

## 5. ローカル分析関数

### simulate_strategy_vectorized()

パス: `scripts/analysis/grid_search/grid_search_metrics_v2.py`

```python
simulate_strategy_vectorized(
    monthly_returns_df,   # 月次リターンDF
    rebalance_schedule,   # 'monthly', 'quarterly_jan', etc.
    base_portfolio_name,  # 'DM2', 'DM3', 'DM6', 'DM7+'
    candidate_params      # オーバーライドパラメータ
) → {total_return, cagr, max_drawdown, sharpe_ratio, sortino_ratio, monthly_returns, ...}
```

注意:
- **MomentumCache必須**: `momentum_cache`を渡さないと黙って空リストを返す（例外なし）
- `date_from`/`date_to`で期間制限可（WF検証用）
- リバランススケジュール: monthly|bimonthly_odd|quarterly_jan|semiannual_jan|annual_jan

### 月次リターン計算ルール

```
シグナル実行: 月末シグナル → 翌月リターン適用
月次リターン = (月末価格 / 月初価格) - 1
マルチアセット: 保有銘柄リターンの単純平均
```

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

## 8. APIエンドポイント概要

> 詳細構成 → `projects/dm-signal.yaml` (h) api を読め。

### アーキテクチャ

- Backend: FastAPI (22ルーター, 84-88エンドポイント)
- Frontend: Next.js (`frontend/lib/api-client.ts`)
- 共通ラッパー: `ApiResponse{success,data,error,message}` (`backend/app/schemas/response.py:7-12`)
- ルーター登録: `backend/app/main.py:313-337 (+debug:341-343)`

### 主要エンドポイント

| パス | 用途 | Backend | Frontend |
|------|------|---------|----------|
| GET /api/signals | シグナル取得 | signals.py:67 | api-client.ts:751 |
| GET /api/portfolios/get | PF一覧 | portfolios.py:147 | api-client.ts:578 |
| POST /api/portfolios/save | PF保存 | portfolios.py:215 | api-client.ts:587 |
| POST /admin/recalculate-sync | 再計算トリガー | etl_trigger.py:235 | api-client.ts:641 |
| GET /api/history/{id} | 履歴 | history.py:27 | api-client.ts:754 |
| GET /api/performance/{id} | パフォーマンス | performance.py:27 | api-client.ts:757 |
| GET /api/metrics/summary | メトリクスサマリー | metrics.py | api-client.ts:777 |
| GET /healthz | ヘルスチェック | main.py | — |

### レスポンス構造（/api/signals）

```
{
  as_of: date,
  calculated_at: datetime,
  portfolios: [
    {
      id, name, type, signal, momentum, hide_symbols, hide_signal, hide_components, benchmark_ticker
      // momentum: { relative: [], absolute, risk_free, safe_haven }
      // _sanitize_momentum_data() (signals.py:28-64) で正規化
    }
  ]
}
```

Frontend型: `SignalsLightResponse` (frontend/lib/types/api.ts:45-49)
状態管理: `SignalsContext` (frontend/contexts/signals-context.tsx)

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

## 10. ディレクトリ構成

```
/mnt/c/Python_app/DM-signal/
├── backend/
│   ├── app/
│   │   ├── main.py                   # FastAPI起動, router登録(:313-337 +debug:341-343), /healthz
│   │   ├── client.py                 # StockData APIクライアント
│   │   ├── api/                      # 22ルーターファイル(84-88エンドポイント)
│   │   │   ├── signals.py            # GET /api/signals (:67)
│   │   │   ├── portfolios.py         # GET/POST/DELETE /api/portfolios/* (:147,215)
│   │   │   ├── etl_trigger.py        # POST /admin/recalculate-sync (:235)
│   │   │   ├── history.py            # GET /api/history/{id} (:27)
│   │   │   ├── performance.py        # GET /api/performance/{id} (:27)
│   │   │   ├── metrics.py            # GET /api/metrics/* (:18)
│   │   │   └── ... (16 more routers)
│   │   ├── schemas/
│   │   │   ├── response.py           # ApiResponse{success,data,error,message} (:7-12)
│   │   │   ├── pipeline.py           # BlockType enum (:18-37)
│   │   │   └── models.py             # PortfoliosPayload等
│   │   ├── db/
│   │   │   └── models.py             # signals(:91-101), portfolios(:66-84) ORM
│   │   ├── services/
│   │   │   ├── pipeline/
│   │   │   │   ├── base.py           # PipelineBlock, PipelineContext
│   │   │   │   ├── engine.py         # PipelineEngine, execute_pipeline(:63), execute_pipeline_with_blocks(:191)
│   │   │   │   └── blocks/           # 14ブロック実装(Selection 11 + Terminal 3)
│   │   │   ├── return_calculator.py  # SSOT: calculate_monthly_return()
│   │   │   ├── momentum_cache.py     # MomentumCache
│   │   │   ├── vectorized_momentum.py
│   │   │   └── price_ratio_calculator.py  # PFのticker展開ロジック
│   │   └── jobs/
│   │       ├── recalculate_fast.py   # 高速再計算本体(Phase0-5)
│   │       ├── recalculate_fof.py    # FoF再計算（本番用・ローカル不可）
│   │       ├── shared.py             # ブロック登録(:208-253)
│   │       └── flush/
│   │           └── signal_flush.py   # UPSERT実装(:45-54)
│   ├── static/data/
│   │   └── dm_signal.db              # 本番ミラー（PF設定用）
│   └── .env                          # 本番DB接続情報
├── frontend/
│   ├── lib/
│   │   ├── api-client.ts             # API呼び出し(credentials=include, NEXT_PUBLIC_API_HOST)
│   │   └── types/
│   │       ├── api.ts                # SignalsLightResponse(:45-49), PortfoliosPayload(:5-7)
│   │       ├── portfolio.ts          # PortfolioSignal(:97-107)
│   │       └── market.ts             # PortfolioMomentum(:8-13)
│   └── contexts/
│       └── signals-context.tsx       # SignalsContext(:16,38,75-79)
├── scripts/                          # 671件
│   ├── analysis/
│   │   ├── grid_search/              # 188件(探索・検証ランナー群)
│   │   │   ├── grid_search_metrics_v2.py # simulate_strategy_vectorized()
│   │   │   ├── gs_csv_loader.py      # 共通CSVローダー(cmd_160)
│   │   │   ├── template_gs_runner.py # GSテンプレート
│   │   │   └── run_077_*.py          # 全6ブロックGSスクリプト(CSV直接読込)
│   │   └── data_sync/
│   │       └── download_all_prices.py # 価格DL(推奨)
│   ├── verify/                       # 29件(仮説検証/回帰確認)
│   └── core/                         # 6件(運用トリガー/収集)
├── analysis_runs/
│   └── experiments.db                # 分析用DB（価格ground truth）
├── docs/                             # 419-443件
│   ├── _INDEX.md                     # 全体目次（最初にここを読め）
│   ├── rule/                         # 25件: ビジネスルール(trade-rule.md=63K)
│   ├── skills/                       # 25件: 実装パターン
│   ├── portfolio-research/           # 33件: GSガイド
│   └── experiment_log.md             # 実験記録（cmd_035〜の全実験ログ）
├── tasks/                            # _INDEX.md, decisions.md, lessons.md, todo.md
└── outputs/grid_search/              # 分析結果出力先(DATA_CATALOG.md)
```

## 11. Lookback標準グリッド（恒久ルール）

グリッドサーチのlookbackは以下18パターンを基本探索範囲とせよ。換算: 1M=21営業日(21D)。

| # | 値 | 営業日数 | # | 値 | 営業日数 | # | 値 | 営業日数 |
|---|-----|---------|---|-----|---------|---|-----|---------|
| 1 | 10D | 10 | 7 | 4M | 84 | 13 | 10M | 210 |
| 2 | 15D | 15 | 8 | 5M | 105 | 14 | 11M | 231 |
| 3 | 20D | 20 | 9 | 6M | 126 | 15 | 12M | 252 |
| 4 | 1M | 21 | 10 | 7M | 147 | 16 | 15M | 315 |
| 5 | 2M | 42 | 11 | 8M | 168 | 17 | 18M | 378 |
| 6 | 3M | 63 | 12 | 9M | 189 | 18 | 24M | 504 |

- 既存パラメータがこの18点のどれに該当するか常に明示せよ
- カバレッジマップではこの18点に対する探索済み/未探索を示せ

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

### データカタログ

パス: `outputs/grid_search/DATA_CATALOG.md`

前提知識なしで全データの概要を把握できるように構造化。Active Catalog（cmd_071以降）/ Existing Analysis Data（040-064）/ Historical Reference（035-070）/ Legacy（cmd以前）の4層。System Definition C-1〜C-7でデータソース/共通ルール/四神設定/ブロック定義/パラメータ空間/分析フレームワーク/スクリプト一覧を定義。

### 堅牢性検証ツール（承認済み・未実装）

- 構造的SUSPECT検出+自動Ban機能: 設計書 `docs/skills/structural-suspect-ban.md`
- 条件: Ban履歴ログ必須、誤Ban防止安全機構必須。設計書→承認→実装の流れ

## 13. StockData API

- エンドポイント: `stockdata-api-6xok.onrender.com`
- クライアント: `backend/app/client.py` → `StockApiClient`
- リトライ: 3回(1s→2s→4s指数バックオフ) | タイムアウト: 60秒
- 環境変数: `STOCK_API_BASE_URL`
- ローカルDL: `download_all_prices.py grid-search` を使え。`download_prod_data.py prices` は422エラーで使用不可（cmd_042）

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

## 15. 殿の個人PF保護リスト（絶対ルール — cmd_198 殿直伝）

> DB操作(DELETE/UPDATE)タスクでは、以下のPFを**絶対に削除・変更してはならない**。

### 保護対象（35体）

**Standard PF（21体）**:
DM2, DM2-20%, DM2-40%, DM2-60%, DM2-80%, DM2-test, DM2-top,
DM3, DM4, DM5, DM5-006,
DM6, DM6-5, DM6-20%, DM6-40%, DM6-60%, DM6-80%, DM6-Top,
DM7+, DM-safe, DM-safe-2

**FoF PF（14体）**:
Ave-X, Ave四神, 裏Ave-X,
MIX1, MIX2, MIX3, MIX4,
bam-2, bam-6,
劇薬DMオリジナル, 劇薬DMスムーズ, 劇薬bam, 劇薬bam_guard, 劇薬bam_solid

### 削除許可対象（3カテゴリのみ）

| カテゴリ | 判定基準 | 件数 |
|---------|---------|------|
| L0 GS生成PF | name LIKE 'L0-%' | ~30 |
| 四神L1 | 激攻/鉄壁/常勝 × 青龍/朱雀/白虎/玄武 | 12 |
| 忍法L2 | 分身/追い風/抜き身/変わり身/加速 × 激攻/鉄壁/常勝 | 15 |

### 運用ルール

- DB操作タスクのdescriptionに「殿PF除外」を明記必須
- dry-runで残存PFリストを確認してから本削除
- `projects/dm-signal.yaml` の `protected_portfolios` にリスト恒久化済み

## 殿裁定履歴

