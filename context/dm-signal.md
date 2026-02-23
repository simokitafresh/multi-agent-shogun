# DM-signal コンテキスト
<!-- last_updated: 2026-02-23 cmd_274 Cycle3統合+Cycle1-3総括 -->

> 読者: エージェント。推測するな。ここに書いてあることだけを使え。

タスクに `project: dm-signal` がある場合このファイルを読め。パス: `/mnt/c/Python_app/DM-signal/`

## 0. 研究レイヤー構造

| Layer | 名前 | 内容 | 状態 |
|-------|------|------|------|
| L1 | 基本PF発見 | 個別DM戦略（青龍/朱雀/白虎/玄武）のパラメータGS・検証 | 完了(12体登録済み) |
| L2 | 忍法FoF | 5忍法(分身/追い風/抜き身/変わり身/加速)×3モード(激攻/鉄壁/常勝)のGS・登録。命名: {忍法名}-{モード} | 完了(12体登録+全0.00bp PASS) |
| L3 | 組合せ堅牢化 | 上位構造の堅牢性検証（WF優先。FoFは乗り換え戦略のため時間軸評価が本質。CPCVは補助） | 未着手(cmd_176殿裁定待ち) |

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
→ **cmd_246完了**: 12体チャンピオンを本番DB登録済み。全12体 0.00bp パリティPASS。PF総数89体(上限100)。
→ **新忍法候補**: 逆風(ReversalFilter)追加決定(cmd_249偵察完了)。RelativeMomentum(cmd_250偵察完了) / MultiViewMomentum(cmd_251偵察完了)。パラメータカタログは§4参照。
※ 智将(Calmar)→鉄壁(MaxDD)変更理由: Spearman相関分析でCalmarはCAGRと高相関(rho=0.86)で冗長。MaxDDはCAGRと低相関(rho=0.49)で独自軸。

⚠ L1/L2混同禁止:
- L1 = 神の中身（GSパラメータ: lookback/safe_haven/rebalance/topN）
- L2 = 神の組み合わせ（ビルディングブロック: omote/am/svm/acc/ura）
- FoFレベルのブロックを個別の神に適用しても意味がない

### L2忍法チャンピオン一覧（cmd_246完了 — 全12体 0.00bp PASS）

全5忍法ミニパリティ0bp確定（cmd_227完了）後、4忍法フルGSを実行。

**フルGS規模**:

| 忍法 | パターン数 | 備考 |
|------|-----------|------|
| 追い風 | 42,174 | tiebreak修正後コードで再実行 |
| 抜き身 | 152,295 | — |
| 変わり身 | 28,116 | — |
| 加速 | 238,986 | — |
| 分身 | 781 | cmd_214完了済み(EqualWeight) |

合計: 462,352パターン。

**12体チャンピオン（本番DB登録済み）**:

| 忍法 | 激攻(CAGR) | 鉄壁(MaxDD) | 常勝(NHR) |
|------|-----------|------------|----------|
| 追い風 | 64.85% / 18M,N1 | -15.87% / 18M,N2 | 64.56% / 9M,N3 |
| 抜き身 | 74.21% / 18M,SK3,N1 | -15.51% / 18M,SK1,N1 | 65.73% / 24M,SK1,N4 |
| 変わり身 | 62.25% / 24M,N1 | -13.51% / 24M,N1 | 65.7% / 24M,N2 |
| 加速 | 76.27% / 10D/4M,ratio,N1 | -14.47% / 9M/10M,diff,N1 | 66.03% / 18M/24M,ratio,N1 |

詳細（UUID・構成四神・パリティ月数）: `queue/reports/hanzo_report.yaml` (cmd_246 AC5)

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

### BB種別分類（cmd_247棚卸し結果）

| 区分 | BB名(BlockType) | クラス名 | 対応忍法 |
|------|----------------|---------|---------|
| 採用(忍法) | MomentumFilter | MomentumFilterBlock | 追い風 |
| 採用(忍法) | SingleViewMomentumFilter | SingleViewMomentumFilterBlock | 抜き身 |
| 採用(忍法) | TrendReversalFilter | TrendReversalFilterBlock | 変わり身 |
| 採用(忍法) | MomentumAccelerationFilter | MomentumAccelerationFilterBlock | 加速 |
| 採用(忍法) | AbsoluteMomentumFilter | AbsoluteMomentumBlock | 門番 |
| 採用(忍法) | EqualWeight | EqualWeightBlock | 分身/全忍法terminal |
| 補助 | SafeHavenSwitch | SafeHavenSwitchBlock | 門番補助(空集合時切替) |
| 補助 | MonthlyReturnMomentumFilter | MonthlyReturnMomentumFilterBlock | 追い風(GS方式) |
| 未採用 | ReversalFilter | ReversalFilterBlock | → **逆風**として採用決定(cmd_249偵察完了) |
| 未採用 | RelativeMomentumFilter | RelativeMomentumFilterBlock | 偵察完了(cmd_250) |
| 未採用 | MultiViewMomentumFilter | MultiViewMomentumFilterBlock | 偵察完了(cmd_251) ※本番DB使用あり |
| 未採用 | ComponentPrice | ComponentPriceBlock | FoF構成PF価格データ化 |
| 未採用 | CashTerminal | CashTerminalBlock | 全額Cash退避終端 |
| 未採用 | KalmanMeta | KalmanMetaBlock | 外部weights適用メタ終端(ディスコン) |

分類: 採用6種(忍法マッピング済み) + 補助2種 + 未採用6種(うち3種が新忍法候補として偵察中)。

### 全14種BB パラメータカタログ（cmd_253統合）

共通型: `LookbackPeriod` = `{months: int(0-24), days: Optional[int](max 504), weight: float(0-1)}`

#### Selection Blocks（11種）

| BB名(BlockType) | パラメータ名 | 型 | 範囲 | デフォルト | GS探索範囲 | Pydantic制約（`schemas/models.py`） | 意味 |
|---|---|---|---|---|---|---|---|
| **MomentumFilter** (追い風) | top_n | int | ge=1 | 1 | T1-T5 | `Portfolio.top_n`: `ge=1, le=2`（Portfolio層） | モメンタム上位選出数 |
| | lookback_periods | List[LookbackPeriod] | リスト長制限なし | [] | 標準18点GS grid | 要素`LookbackPeriod`: `months ge=0, le=24` / `days le=504` / `weight ge=0, le=1` | モメンタム計算期間(加重合成) |
| **AbsoluteMomentumFilter** (門番) | lookback_periods | List[LookbackPeriod] | リスト長制限なし | [] | 標準18点GS grid | 要素`LookbackPeriod`: `months ge=0, le=24` / `days le=504` / `weight ge=0, le=1` | モメンタム計算期間 |
| | threshold | float | 制限なし | 0.0 | ― | 制約なし（`models.py`に該当Field定義なし） | 固定モード時の最低モメンタム閾値 |
| | threshold_mode | str | 'fixed'\|'reference_asset' | 'fixed' | ― | 制約なし（`models.py`に該当Field定義なし） | 判定モード(固定閾値/参照資産比較) |
| | absolute_asset | str | ticker symbol | None | ― | `Portfolio.absolute_asset`: `strip()+upper()`バリデータ | ゲートキーパー資産(例:LQD,TMF,^VIX,SPXL) |
| | reference_asset | str | ticker/経済指標 | None | ― | 制約なし（`models.py`に該当Field定義なし） | 基準資産(例:DTB3=リスクフリーレート) |
| | reference_lookback_periods | List[LookbackPeriod] | リスト長制限なし | None(→lookback_periods) | ― | 制約なし（`models.py`に該当Field定義なし） | 基準資産用lookback(省略時はlookback_periodsを流用) |
| **RelativeMomentumFilter** (相対) | benchmark | str | ticker symbol(空文字不可) | ""(事実上必須) | SPY,EFA,AGG等 | `Portfolio.benchmark_ticker`: 空文字禁止、`DTB3/CASH`禁止、`strip()+upper()` | 比較対象ベンチマーク銘柄 |
| | lookback_periods | List[LookbackPeriod] | リスト長制限なし | [] | 標準18点GS grid | 要素`LookbackPeriod`: `months ge=0, le=24` / `days le=504` / `weight ge=0, le=1` | モメンタム計算期間(加重合成) |
| **MomentumAccelerationFilter** (加速) | top_n | int | ge=1 | 1 | T1-T5 | `Portfolio.top_n`: `ge=1, le=2`（Portfolio層） | 加速度上位選出数 |
| | numerator_period | LookbackPeriod | 必須 | ― | 日次:10D,15D,20D / 月次:1M-24M | `LookbackPeriod`: `months ge=0, le=24` / `days le=504` / `weight ge=0, le=1` | 短期(分子)期間 |
| | denominator_period | LookbackPeriod | 必須 | ― | 日次:10D,15D,20D / 月次:1M-24M | `LookbackPeriod`: `months ge=0, le=24` / `days le=504` / `weight ge=0, le=1` | 長期(分母)期間 |
| | method | str | 'ratio'\|'diff' | 'ratio' | ratio, diff | 制約なし（`models.py`に該当Field定義なし） | 加速度計算方法(比率/差分) |
| **ReversalFilter** (逆風) | bottom_n | int | 制限なし(実質ge=1) | 1 | B1-B5 | 制約なし（`models.py`に該当Field定義なし） | モメンタム下位からの逆張り選出数 |
| | lookback_periods | List[LookbackPeriod] | リスト長制限なし | [] | 標準18点GS grid | 要素`LookbackPeriod`: `months ge=0, le=24` / `days le=504` / `weight ge=0, le=1` | モメンタム計算期間(加重合成) |
| **SafeHavenSwitch** (セーフヘイブン) | safe_haven_asset | str | ticker or 'Cash' | 'Cash' | ―(インフラBB) | `Portfolio.safe_haven_asset`: `strip()+upper()`バリデータ | 退避先銘柄(例:XLU,GLD,AGG) |
| | switch_condition | str | 'empty_tickers'のみ | 'empty_tickers' | ― | 制約なし（`models.py`に該当Field定義なし） | 切替条件(上流BB出力が空の時) |
| **ComponentPrice** (FoF価格読込) | lookback_days | int | ge=1 | 730 | ―(インフラBB) | 制約なし（`models.py`に該当Field定義なし） | MonthlyReturnテーブルからのデータ読込日数 |
| **MultiViewMomentumFilter** (多眼) | base_period_months | int | **ge=4必須**(L100) | 12 | 4M-24M(12点) | 制約なし（`models.py`に該当Field定義なし） | ルックバック月数(各視点でbase-skip) |
| | top_n | int | ge=1 | 2 | T1-T5 | `Portfolio.top_n`: `ge=1, le=2`（Portfolio層） | 各視点からの選出数(和集合サイズ=top_n〜4×top_n) |
| | *SKIP_MONTHS_LIST* | *List[int]* | *[0,1,2,3]固定* | *―(クラス変数)* | *config不可* | *制約なし（`models.py`に該当Field定義なし）* | *4視点のスキップ月数(変更不可)* |
| **SingleViewMomentumFilter** (抜き身) | base_period_months | int | ge=1 | 12 | 標準18点GS grid | 制約なし（`models.py`に該当Field定義なし） | ルックバック月数 |
| | skip_months | int | 0-3推奨 | 0 | 0,1,2,3 | 制約なし（`models.py`に該当Field定義なし） | 直近N月をスキップ |
| | top_n | int | ge=1 | 2 | T1-T5 | `Portfolio.top_n`: `ge=1, le=2`（Portfolio層） | モメンタム上位選出数 |
| **TrendReversalFilter** (変わり身) | period_months | int | ge=1 | 3 | 標準18点GS grid | 制約なし（`models.py`に該当Field定義なし） | モメンタム計算月数 |
| | select_n | int | ge=1 | 2 | T1-T5 | 制約なし（`models.py`に該当Field定義なし） | 上位N+下位Nそれぞれの選出数(和集合) |
| **MonthlyReturnMomentumFilter** (月次GS方式) | base_period_months | int | ge=1 | 12 | 標準18点GS grid | 制約なし（`models.py`に該当Field定義なし） | ルックバック月数 |
| | skip_months | int | ge=0 | 0 | 0,1,2,3 | 制約なし（`models.py`に該当Field定義なし） | 直近N月をスキップ |
| | top_n | int | ge=1 | 1 | T1-T5 | `Portfolio.top_n`: `ge=1, le=2`（Portfolio層） | モメンタム上位選出数 |

#### Terminal Blocks（3種）

| BB名(BlockType) | パラメータ名 | 型 | 範囲 | デフォルト | GS探索範囲 | Pydantic制約（`schemas/models.py`） | 意味 |
|---|---|---|---|---|---|---|---|
| **EqualWeight** (分身) | ― | ― | ― | ― | ― | 制約なし（`models.py`に該当Field定義なし） | パラメータなし。1/n均等配分 |
| **CashTerminal** (キャッシュ退避) | ― | ― | ― | ― | ― | 制約なし（`models.py`に該当Field定義なし） | パラメータなし。100% Cash固定 |
| **KalmanMeta** (カルマン加重/ディスコン) | weights | Dict[str,float] | 非空dict | None | ―(外部注入) | 制約なし（`models.py`に該当Field定義なし） | 直接重み指定 |
| | weights_key | str | context lookup key | "kalman_weights" | ― | 制約なし（`models.py`に該当Field定義なし） | context.intermediate_resultsからの取得キー |

#### 選出方式サマリー

| 方式 | 対象BB | 動作 |
|------|--------|------|
| cutoff_score全包含 | MomentumFilter, SingleViewMomentumFilter, MomentumAccelerationFilter, MultiViewMomentumFilter, MonthlyReturnMomentumFilter | 境界スコアと同点の銘柄を全て採用(top_n超過許容) |
| strict slice | TrendReversalFilter, ReversalFilter | 厳密にN件切り出し(同点でも切り捨て) |
| 閾値フィルタ | AbsoluteMomentumFilter | threshold/参照資産比較。通過/遮断のみ |
| ベンチマーク超過 | RelativeMomentumFilter | benchmark超過の全ticker通過(上限なし) |
| 条件切替 | SafeHavenSwitch | 空集合→safe_haven_assetに差し替え |
| N/A | ComponentPrice, EqualWeight, CashTerminal, KalmanMeta | データ読込/終端処理(選出なし) |

標準18点GS grid: 日次=10D,15D,20D / 月次=1M,2M,3M,4M,5M,6M,7M,8M,9M,10M,11M,12M,15M,18M,24M (1M=21営業日)

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

### SVMF/MVMFバグ修正（cmd_235 + cmd_244）

本番パイプラインの`SingleViewMomentumFilterBlock`(SVMF)と`MultiViewMomentumFilterBlock`(MVMF)に2件のバグが存在し、修正済み。

| cmd | 問題 | 修正 | commit | 影響PF |
|-----|------|------|--------|--------|
| cmd_235 | `is_monthly_data()`未使用。行数ベース判定(`len<base*5`)が月次データ168-192行を日次と誤判定 | skip処理前に`is_monthly_data()`を呼び出し(L097) | a6ba012 | MIX2/3/4(SVMF) + bam-2/6(MVMF) |
| cmd_244 | SVMF fallbackパスが`price_data_cache`全期間を参照し`target_date`未フィルタ。将来データを参照(L098) | `df_ticker[index<=target_date]`フィルタ追加(PD-015 A案) | 2e970ed | 同上 |

修正後`recalculate-sync`で5PF全PASS。回帰検証完了。

### 新忍法候補（2026-02-22 偵察開始）

| 忍法候補 | BB型 | 状態 | cmd | 主要パラメータ |
|---------|------|------|-----|-------------|
| 逆風(gyakufuu) | ReversalFilterBlock | 採用決定・偵察完了 | cmd_249 | bottom_n(B1-B5), lookback_periods。strict slice方式 |
| 追い越し(oikoshi) | RelativeMomentumFilterBlock | 偵察完了 | cmd_250 | benchmark=SPY(固定), lookback_periods。ベンチマーク超過全通過 |
| 四つ目(yotsume) | MultiViewMomentumFilterBlock | 偵察完了 | cmd_251 | base_period_months(≥4), top_n。SKIP_MONTHS_LIST=[0,1,2,3]固定 |

逆風は追い風(順張り)の対となる逆張りフィルタ。殿裁定で採用決定済み。
追い越しはベンチマーク対比で超過リターンが高い銘柄を選抜(殿命名: cmd_250)。
追い越しのベンチマークはSPY一本に固定（殿裁定: PD-023）。複数候補は採用しない。
四つ目は4視点(0/1/2/3Mスキップ)のTop N和集合。本番bam-2/bam-6で実使用中(cmd_247霧丸DB調査)。
全パラメータ詳細は§4パラメータカタログ参照。

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

PD-028裁定（2026-02-23）:
- GS制約同期は仕組み化しない。
- 運用は「BBカタログにPydantic制約を明記」+「各GSスクリプトのPARAM_GRIDを制約範囲へ修正」で対応する。

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

## 18. backend `folder_id` 実態（cmd_269 偵察A, 2026-02-23）

### 18.1 カラム定義とFK

- `Portfolio.folder_id` は `backend/app/db/models.py:75` で定義。
  - 型: `String`
  - 制約: `ForeignKey("portfolio_folders.id", ondelete="SET NULL")`
  - nullable: `True`
- 親テーブル `portfolio_folders` は `backend/app/db/models.py:46-64` でORM定義済み。
- `portfolio_folders.parent_id` も自己参照FK（`ON DELETE SET NULL`）。

### 18.2 テーブル作成/マイグレーション履歴

- Alembic構成は存在しない（`backend/alembic/` や `alembic/versions` ディレクトリなし、`rg "alembic"` もヒットなし）。
- 実運用のマイグレーションは `backend/app/db/migrations.py` の起動時処理:
  - `backend/app/db/migrations.py:66-79` で `portfolio_folders` テーブル作成
  - `backend/app/db/migrations.py:87` で `portfolios.folder_id` を `TEXT REFERENCES portfolio_folders(id) ON DELETE SET NULL` として追加
- `backend/migrations/*.py` には folder 関連処理なし（grepヒットなし）。

### 18.3 `folder_id` 使用箇所（backend全体）

`rg -n "folder_id" backend` の結果、実装上の中心は `api/folders.py`:

- 定義/DDL
  - `backend/app/db/models.py:75`
  - `backend/app/db/migrations.py:87`
- Folder API（参照）
  - `backend/app/api/folders.py:77`
  - `backend/app/api/folders.py:104`
  - `backend/app/api/folders.py:213`
  - `backend/app/api/folders.py:251`
- Folder API（更新）
  - `backend/app/api/folders.py:304` (`portfolio.folder_id = payload.folder_id`)
- その他は request/route引数やログ文字列上の出現（`folder_ids`, `folder_id`）。

### 18.4 API/Schema露出状況

- `/api/portfolios` ルータ (`backend/app/api/portfolios.py`) の公開エンドポイントは:
  - `GET /api/portfolios/get` (`:147`)
  - `POST /api/portfolios/save` (`:215`)
  - `POST /api/portfolios/save-legacy` (`:582`)
- これらの response_model は `PortfoliosPayload` / `SavePortfoliosResponse` で、`Portfolio` スキーマ (`backend/app/schemas/models.py:53-140`) に `folder_id` フィールドは存在しない。
- `backend/app/schemas/` 配下で `folder_id` は0件ヒット。
- フォルダ情報は専用API `/api/admin/folders` (`backend/app/api/folders.py:19`) 側で扱う設計。

### 18.5 Portfolio CRUDでの読み書き可否

- `PortfolioRepository.load()` は `p_db.config` を `Portfolio` モデルへ詰め替える実装で、`p_db.folder_id` を `Portfolio` へ写していない（`backend/app/storage/repository.py:85-113`）。
- `PortfolioRepository.save()` も `name/type/config/hide_*/is_active` を更新するが `folder_id` を更新しない（`backend/app/storage/repository.py:154-183`）。
- 結論: Portfolio CRUD (`/api/portfolios/*`) では `folder_id` の読み書き未実装。`folder_id` 更新は `POST /api/admin/folders/portfolios/{portfolio_id}/move` (`backend/app/api/folders.py:283-309`) に限定。

### 18.6 本番DB実値（SELECTのみ確認）

2026-02-23 実行結果（`DATABASE_URL` 直結, `SELECT folder_id, COUNT(*) FROM portfolios GROUP BY folder_id`）:

- `total_portfolios = 88`
- `null_folder_id = 88`
- `DISTINCT folder_id = {NULLのみ}`

現時点の本番DBでは、全ポートフォリオがルート配下（未フォルダ割当）で運用されている。

## 19. 月次リターン傾き分析（cmd_270, 2026-02-23）

### 19.1 手法

PFの「今の調子」を月次リターン分布の時間的変化で判定する。3Phase構成。

| Phase | 内容 | 結論 |
|-------|------|------|
| A: ACF分析 | 代表PF8体(四神4+殿PF4)の月次リターン自己相関を算出し、有意lag消失点から統計的推奨窓幅を決定 | 最大有意lag=35M(DM7+/DM-safe)、推奨41M |
| B: 窓幅比較 | 24M/36M/48M/60Mの4窓幅でローリング中央値・95%CI・5%ileを可視化。既知レジーム変化(COVID 2020-03/利上げ 2022-01)の検出率を評価 | 36Mが最良検出率(38%)。48M/60Mは過剰平滑化 |
| C: 傾きランキング | 最終推奨窓幅で全PFの月次リターンに線形回帰。傾き+95%CIで4分類 | 92PF中: Improving 0/Stable 6/Declining 12/Inconclusive 74 |

### 19.2 推奨窓幅: 36ヶ月

- ACF推奨: 41M（最大有意lag 35M + バッファ6M）
- レジーム検出最良: 36M（24Mは31%、36Mは38%、48Mは0%、60Mは12%）
- 総合判定: **36M**。ACFとレジーム検出の中間で、実用上のバランスが最良

### 19.3 ACF分析結果（代表PF8体）

| PF | 最後の有意lag | 解釈 |
|----|-------------|------|
| DM2(青龍) | 2M | 短期相関のみ。ほぼランダムウォーク |
| DM3(朱雀) | 15M | 中程度の持続性 |
| DM6(白虎) | 28M | 強い持続性。トレンドが長期継続 |
| DM7+(玄武) | 35M | 最も強い持続性。長期レジーム依存 |
| DM-safe | 35M | 玄武と同様の長期構造 |
| DM-safe-2 | 13M | 中程度 |
| Ave-X | 5M | 短期。FoF分散効果で自己相関が薄まる |
| DM5 | 15M | 中程度 |

### 19.4 全PF調子分類（36M窓）

分類基準: 線形回帰の傾き + 95%CI + p値

| 分類 | 条件 | 該当数 | 解釈 |
|------|------|--------|------|
| Improving | p≤0.10 かつ CI下限>0 | 0体 | 統計的に有意な改善トレンドを持つPFはゼロ |
| Stable | p≤0.10 かつ CIが0を跨ぐ | 6体 | 有意だが方向不明確 |
| Declining | p≤0.10 かつ CI上限<0 | 12体 | 統計的に有意な下降トレンド |
| Inconclusive | p>0.10 | 74体 | 傾きがノイズと区別できない |

主要PFの傾き:
- DM7+(玄武): slope=-0.00346/月, **Declining** — エッジ消失の兆候
- DM6(白虎): slope=-0.00143/月, Inconclusive
- DM2(青龍): slope=-0.00066/月, Inconclusive
- DM3(朱雀): slope=-0.00048/月, Inconclusive
- DM-safe: slope=+0.00045/月, Inconclusive
- Ave-X: slope=+0.00054/月, Inconclusive

### 19.5 実運用への示唆

1. **Improving(好調)が0体**: 36M窓では、統計的に有意に改善中のPFは存在しない。過去の累積成績に頼る判断は危険という殿の直感を支持。
2. **DM7+(玄武)のDeclining判定**: 四神の中で唯一の有意下降。モニタリング対象。
3. **大多数がInconclusive(74/92)**: 月次リターンのノイズが大きく、36M窓でも傾きの方向を統計的に確定できないPFが多い。これはDM戦略の本質的特性（レジーム切替型）を反映。
4. **窓幅36Mの限界**: レジーム変化検出率38%は低い。補完手段（例: 構造変化点検出、Bairon-Perron検定）が将来課題。

### 19.6 成果物

| ファイル | 内容 |
|---------|------|
| `outputs/charts/cmd270_phaseA_acf.png` | ACFプロット(代表PF8体) |
| `outputs/charts/cmd270_phaseB_window_comparison.png` | 4窓幅比較チャート(代表PF8体) |
| `outputs/charts/cmd270_phaseC_slope_ranking.png` | 全PFフォレストプロット(傾き+CI) |
| `outputs/charts/cmd270_phaseC_slope_ranking.csv` | 全PFランキング(CSV) |
| `scripts/analysis/cmd270_monthly_return_slope.py` | 分析スクリプト |

### 19.7 SPY超過リターン(α)分析（cmd_271, 2026-02-23）

cmd_270の「生リターン傾き」に対し、市場βを除去したα傾きを追加分析した。

- α定義: `alpha_t = PF_monthly_return_t - SPY_monthly_return_t`
- SPY月次リターン: `experiments.db daily_prices` から Open-to-Open で算出（RULE09準拠）
- SPY統計（2000-02〜2026-02, 313 months）: 平均 `0.7439%/月`, 標準偏差 `4.5151%/月`
- 回帰窓幅: 12M / 24M / 36M の3種

### 19.8 α分類基準と全PFサマリー

分類基準（cmd_271）:
- Alpha-Positive: α正（アルファ健在）
- Alpha-Neutral: αゼロ近傍（SPY並み）
- Alpha-Negative: α負（エッジ消失）

`outputs/charts/cmd271_alpha_slope_ranking.csv` 集計（全92PF）:

| 窓幅 | Alpha-Positive | Alpha-Neutral | Alpha-Negative | 解釈 |
|------|----------------|---------------|----------------|------|
| 12M | 0 | 90 | 2 | 短期では大半が中立、2体のみα負 |
| 24M | 0 | 92 | 0 | 全PFが中立（識別力が低い） |
| 36M | 0 | 82 | 10 | 長期で10体がα負、82体はSPY並み |

補足: 3窓幅すべてで `Alpha-Positive=0`。統計的に有意な「α改善」PFは確認されなかった。

### 19.9 推奨窓幅（α視点）

推奨: **36M**

理由:
1. 24Mは全PFがAlpha-Neutralとなり識別力が不足
2. 12Mは短期ノイズの影響が相対的に大きい
3. 36Mは「SPY並み」と「エッジ消失」を分離し、運用判断に使える粒度を保持

### 19.10 β除去前後の判定変化（cmd_270 36Mとの比較）

cmd_270（raw傾き36M）とcmd_271（α傾き36M）を同一92PFで突合。

| 変化タイプ | 件数 | 内容 |
|-----------|------|------|
| Other | 80 | 判定の実質変化なし |
| True-decline | 10 | raw=Declining かつ α=Alpha-Negative（真のエッジ消失） |
| Market-masked | 2 | raw=Declining だが α=Alpha-Neutral（市場要因で見かけ悪化） |
| Market-carried | 0 | raw=Improving かつ α=Alpha-Negative（該当なし） |

判定変化があったPF:
- Market-masked（2）: `95db7c30`, `9ec5ef18`
- True-decline（10）: `87c64386`, `5c06d995`, `3f54546a`, `9834480c`, `e37d84fb`, `ee5d1a32`, `cff7778c`, `94360073`, `DM7+`, `3b2eecab`

### 19.11 実運用への示唆（α視点）

- 殿の哲学: **「ベータの除去は大事。本当にアルファがあるかどうかがわかる」**
- rawで不調に見えるPFの一部（2/12）は市場要因を除くと中立であり、即時除外は早計。
- 一方で10PFはβ除去後もα負で、真のエッジ消失候補として優先監視対象。
- したがって、PF評価は「raw傾き」単独ではなく「raw + α」の二段判定を標準化する。

### 19.12 エッジ残存率分析（cmd_272, 2026-02-23）

殿考案の「エッジ残存率」指標。α傾き分析(cmd_271)が「壊れたものの検知」に有効な一方、「健在の証明」にはならないという殿の指摘を受けて設計された。

**定義**: エッジ残存率 = 直近12Mα ÷ 全期間α × 100%
- α = PF月次平均リターン − SPY月次平均リターン（Open-to-Open, RULE09準拠）
- 全期間αが正のPFのみ計算可能（負/ゼロは別扱い）
- 100%超 = エッジ拡大中、0-100% = エッジ部分残存、0%未満 = エッジ逆転（SPYに劣後）

**殿の指摘（重要）**:
- α中立（傾きゼロ）≠ α水準ゼロ。SPYを上回るPFが多いのに「中立」は理論側の解釈ミス
- 現実と理論の乖離がある場合、間違っているのは理論の方

**全体統計（92PF、全期間α正のもののみ）**:
- Mean: 48%, Median: 32%, Std: 139%
- >100%（エッジ拡大）: 26PF, 0-100%（部分残存）: 38PF, <0%（逆転）: 28PF

**四神エッジ残存率**:

| PF | ランク(/92) | エッジ残存率 | 全期間α | 直近12Mα | 判定 |
|----|------------|-------------|---------|----------|------|
| DM6 | #56 | 9.3% | +2.92% | +0.27% | 大幅劣化 |
| DM7+ | #60 | 5.1% | +1.62% | +0.08% | 大幅劣化 |
| DM2 | #77 | -21.4% | +3.00% | -0.64% | エッジ逆転 |
| DM3 | #93(最下位) | -741.7% | +0.75% | -5.55% | 壊滅的逆転 |

四神は全てエッジが大幅に劣化または逆転。DM3は全期間αが小さく(+0.75%)、直近12Mαが大きく負(-5.55%)のため、比率が極端な負値。

### 19.13 3指標統合の結論（cmd_270/271/272, 2026-02-23）

cmd_270（rawリターン傾き）、cmd_271（α傾き）、cmd_272（エッジ残存率）の3指標を統合。

**統合判定**:
1. **rawリターン傾き**(cmd_270): 大半が"Inconclusive"（傾きが統計的に有意でない）
2. **α傾き**(cmd_271, 12M窓): 大半が"Alpha-Neutral"（α変化の傾きが有意でない）
3. **エッジ残存率**(cmd_272): Median 32% — 半数以上のPFでエッジが3分の2以上縮小

3指標の整合性: rawとα傾きが「変化なし」でもエッジ残存率が低いPFが多い。これは「急速な劣化」ではなく「全期間にわたる緩やかなα低下」を示唆。特に四神(DM2/3/6/7+)は3指標全てで低評価であり、優先監視対象。

**成果物**:
- `scripts/analysis/cmd272_edge_retention_rate.py` — 分析スクリプト
- `outputs/charts/cmd272_edge_retention_histogram.png` — 分布ヒストグラム
- `outputs/charts/cmd272_edge_retention_ranking.png` — ランキングチャート
- `outputs/charts/cmd272_edge_retention_ranking.csv` — ランキングデータ
- `outputs/charts/cmd272_three_indicator_summary.png` — 3指標統合チャート
- `outputs/charts/cmd272_three_indicator_summary.csv` — 3指標統合データ

### 19.14 エッジ残存率バックテスト（cmd_273, 2026-02-23）

cmd_272のエッジ残存率を過去に遡ってローリング算出し、「エッジ低下検知→リターン低下の予測精度」をバックテストした。殿の発想: 推論が正しいか過去データと見比べれば確信度が明確になる。

**手法**:
- ローリングエッジ残存率: 各月tで「全期間α(月1～t)」「直近12Mα(月t-11～t)」を算出し比率を取る。look-ahead bias排除（各月tでt以降のデータは一切参照しない）
- イベント検出: (1)前月比大幅低下(MoM drop): 負の変化量のP10/P25/P50パーセンタイルを閾値に使用（データ駆動、ハードコードなし）(2)0%下回り(alpha reversal)
- 予測精度: イベント後3M/6M/12Mの累積超過リターン(PF-SPY)がマイナスかどうかでprecision/recallを算出

**Precision/Recall結果（全PF対象）**:

| 閾値 | Horizon | N_events | TP | Precision | Recall | F1 |
|------|---------|----------|-----|-----------|--------|----|
| MoM Severe(P10) | 3M | 802 | 272 | 33.9% | 4.3% | 0.077 |
| MoM Severe(P10) | 12M | 792 | 177 | 22.3% | 5.3% | 0.086 |
| MoM Strong(P25) | 3M | 2005 | 592 | 29.5% | 9.4% | 0.143 |
| MoM Strong(P25) | 12M | 1914 | 352 | 18.4% | 10.6% | 0.135 |
| MoM Moderate(P50) | 3M | 3991 | 1193 | 29.9% | 19.0% | 0.233 |
| MoM Moderate(P50) | 12M | 3824 | 668 | 17.5% | 20.1% | 0.187 |
| ZeroCross | 3M | 979 | 302 | 30.8% | 4.8% | 0.083 |

**主要な発見**:
1. Precisionは閾値によらず20-35%で安定。厳しい閾値(P10)でも精度は限定的
2. Recallは緩い閾値(P50)で最大~20%。厳しい閾値では5%未満
3. F1スコアは全体的に低い（最大0.233）。エッジ残存率の急落は「弱いがランダムではない予測シグナル」
4. 短期(3M)の方がPrecisionが高い。長期(12M)になるほどPrecisionは低下しRecallが若干向上
5. 代表PF時系列チャート: DM2ではエッジ残存率の低下と累積超過リターンの停滞に視覚的相関あり

**殿の発想の背景**: cmd_272で静的に算出したエッジ残存率が「現在のスナップショット」であるのに対し、cmd_273は「過去のどの時点でもこの指標が予測力を持っていたか」を検証する。確信度を数値化する科学的アプローチ。結果としてPrecision~30%は「ランダムより高い」が「単独で意思決定指標にするには不十分」であることが判明。3指標統合(§19.13)の文脈で他の指標と組み合わせて使うのが妥当。

**成果物**:
- `scripts/analysis/cmd273_edge_retention_backtest.py` — バックテストスクリプト（853行）
- `outputs/charts/cmd273_timeseries_{PF}.png` — 代表PF5体の時系列チャート（DM2/DM3/DM6/DM7+/Ave-X）
- `outputs/charts/cmd273_precision_recall_table.png` — Precision/Recall/F1スコア表
- `outputs/charts/cmd273_sensitivity_analysis.png` — 閾値別感度分析チャート
- `outputs/charts/cmd273_rolling_edge_retention.csv` — ローリングER全データ
- `outputs/charts/cmd273_all_events.csv` — 全イベント+事後リターンデータ

### 19.15 Cycle1: 複合指標探索結果（cmd_274, 2026-02-23）

cmd_273の単独指標(エッジ残存率 precision 18-34%)を起点に、3指標(raw傾き/α傾き/ER)の複合判定でprecision 80%到達を試みた。2探索者が7アプローチを並行探索。

**判定: precision 80%は未達。構造的に困難。**

**統合比較表（3M horizon、精度順）**:

| アプローチ | 探索者 | Precision | Recall | F1 | N_events | 過学習リスク |
|-----------|--------|-----------|--------|-----|----------|------------|
| LogisticCV (expanding-CV) | 才蔵 | 60.6% | 5.2% | 0.096 | 388 | SEVERE(gap30.8%, 実質~40%) |
| VolWeighted | 才蔵 | 42.0% | 11.6% | 0.182 | 1325 | Low |
| MAJORITY 2/3 | 佐助 | 41.7% | 11.2% | 0.176 | 1286 | Low |
| AND 3/3 | 佐助 | 39.1% | 6.1% | 0.105 | 747 | Low |
| Idiosyncratic | 才蔵 | 38.1% | 13.6% | 0.200 | 1706 | Low |
| ER MoM P10(単独baseline) | cmd_273 | 33.9% | 4.3% | 0.077 | 802 | N/A |
| Sharpe Trend | 才蔵 | 28.2% | 7.8% | 0.122 | 1325 | Low |
| CUSUM | 才蔵 | 27.6% | 3.8% | 0.067 | 663 | Low |

**単独→複合の改善**: cmd_273単独最良33.9% → 複合最良42.0%（VolWeighted）= +23.9%改善。ただし80%までの乖離は38pp。

**成功パターン**:
1. 3M horizonが全アプローチで一貫して最良（短期予測にのみ微弱な信号あり）
2. ボラティリティ重み付け(vol_ratio)が有効: Sharpe 28.2%→VolWeighted 42.0%（高ボラ時のシグナルは信頼性高い）
3. β除去(Idiosyncratic)がF1最良(0.200): 市場全体の劣化を除外し、PF固有のα崩壊のみ検知するコンセプトは妥当
4. LogisticCV名目60.6%は「信号が存在する」ことの証拠だが、過学習gap30.8%で実用不可

**失敗パターン**:
1. AND(3/3)は厳格すぎ: precision微増(+5pp)だがrecall急落(6.1%)、イベント数747と少なく実用性なし
2. CUSUMは月次粒度で線形slope系と同等(27.6%)に収束。累積偏差検知の優位性は年12点では発現せず
3. 全7特徴量のunivariate AUCが0.50-0.57 → 個別に強い予測力を持つ特徴量は存在しない
4. 全特徴量が同一月次リターン系列の派生 → 組合せても独立情報量の増加は限定的

**80%が構造的に困難な理由**（才蔵の理論分析）:
1. SNRの壁: 月次リターンσ(4-8%/月) >> 平均α(0.5-2%/月)、SNR≈0.1-0.5
2. 「崩壊」の定義(SPY劣後)のベースレート~30-38%。precision 80%はベースレートの2倍以上の精度が必要
3. DM戦略はレジーム遷移時にDD発生。レジーム遷移自体の予測が困難(EMH核心)
4. 崩壊後も平均回帰で正リターン多発(L108確認済み)

**次サイクルへの仮説**:
- H1: 週次/日次粒度への移行（月次=年12点は情報量不足）
- H2: 外部データ特徴量（VIX/イールドカーブ/クレジットスプレッド）= 独立情報源
- H3: レジーム適応型閾値（高ボラ/低ボラで異なる閾値）
- H4: 目的転換 — 二値崩壊予測 → 連続リスクスコアリング
- H5: VolWeighted + Idiosyncratic のアンサンブル（最良precision + 最良F1の組合せ）

**成果物**:
- `scripts/analysis/cmd274_cycle1_integration.py` — 統合スクリプト
- `outputs/charts/cmd274_cycle1_comparison.csv` — 全アプローチ統合比較表(24行)
- `outputs/charts/cmd274_cycle1_single_vs_composite.csv` — 単独vs複合比較(3M)
- `outputs/charts/cmd274_cycle1_summary_comparison.png` — Precision比較+PR散布図

### 19.16 Cycle2: 独立情報源+粒度変更+レジーム探索（cmd_274, 2026-02-23）

Cycle1の「全特徴量が同一月次リターン派生」という構造限界を受け、3つの異なる角度から打開を試みた。

**C2-A: 独立情報源検出器（影丸）**
- 手法: VIX/イールドカーブ/クレジットスプレッド等をcomposite detectorに統合
- 結果: precision 38.0%(expanding_cv, 3M)、AUC ~0.50
- 発見: 外部指標もDM戦略のPF固有崩壊の予測力を持たない。「独立情報源」だが「無関連情報源」

**C2-B: 粒度変更 — 22特徴量（佐助）★Cycle2最良**
- 手法: 週次αスロープ/歪度/尖度/DD/ボラクラスタ/KS乖離等22特徴量でLogReg
- 結果: DM3高確信度(P>0.7)のみ precision 65.5%(n=29)、AUC 0.589
- 他PF: DM2=37.5%, DM6=33.3%, DM7+=33.3% → DM3固有の信号
- 発見: 日次/週次粒度で月次の4倍の情報量。ただしDM3以外では無効（L110教訓）
- overfit gap: train 67.5% vs test 65.5% = 2pp → MODERATE（許容範囲）

**C2-C: レジームリスクスコア（半蔵）**
- 手法: Composite regime(SMA200+VIX+DD) + HMM 2-state + Combined score
- 結果: Composite 3M AUC=0.510、HMM AUC=0.508、Combined AUC=0.517
- 高確信度: DM3 bear_composite regime HC0.7 = precision 72.7%(n=11)★最高値
- 発見: 連続リスクスコアのAUCはランダム付近(0.51)だが、bear限定+HC filteringで高精度を実現。nの犠牲が大きい

**Cycle2総括**: C2-B(粒度変更)が唯一の実質的改善(42%→65.5%)。DM3に限定すれば信号は存在するが弱い。C2-C(レジーム)はCycle3で深掘りへ。

### 19.17 Cycle3: 9並列探索の結果（cmd_274, 2026-02-23）

C2-B(LogReg 22特徴量, DM3 HC 65.5%)を共通ベースラインとして、9探索を並列実行。

**9探索横断比較表（DM3基準、precision順）**:

| ID | 手法 | 担当 | Precision | Recall | F1 | AUC | n | 過学習 | 主要発見 |
|----|------|------|-----------|--------|-----|-----|---|--------|---------|
| C3-E | ターゲット再定義(DD>10%) | 小太郎 | 88.9%* | 31.2% | 0.462 | 0.651 | 27 | LOW | *base_rate=55.7%。問題変更であり精度改善ではない |
| C3-G | 確率キャリブレーション(Isotonic) | 半蔵 | 83.3% | — | — | 0.510 | 6 | N/A | **n=6, CI=[36%,100%]。統計的に無効** |
| C3-C | レジーム条件付き(Bear+HC0.7) | 半蔵 | **72.7%** | — | — | — | 11 | LOW | **★実質ベスト**。composite regime+HC filtering |
| C3-D | 非線形GBC/RF(Grid Search) | 雑蔵 | 61.8% | — | — | 0.585 | 55 | LOW | GBC HC0.7最良。非線形≤LogReg。特徴量重要度均一(5-8%) |
| C3-B | Top5特徴量+VolWeighted | 霧丸 | 58.8% | 83.3% | 0.690 | 0.742 | 22 | LOW | 高recall。Top5: recovery/skew/ks/α_slope/max_dd |
| C3-A | 全PF汎化(C2-B特徴量) | 佐助 | 58.5% | 55.9% | 0.571 | 0.589 | 132 | MOD | DM3のみ58.5%、他PF<45%。DM3固有信号は弱い |
| C3-H | 時間ラグ22+Cross-PF 9特徴量 | 佐助 | 53.3% | 35.8% | 0.429 | 0.565 | 132 | LOW | ラグ/Cross-PF特徴量は信号を追加しない |
| C3-I | KNN距離ベース(k=3,5,7,11) | 小太郎 | 52.5% | 47.1% | 0.496 | 0.542 | 133 | LOW | KNN<LogReg(57.6%)。距離ベースは劣後 |
| C3-F | 多粒度90特徴量+スタッキング | 飛猿 | 39.7% | 37.2% | 0.384 | 0.381 | 155 | LOW | **最悪**。90特徴量+stackingはベースライン(65.5%)より悪化 |

**成功パターン分析(AC7)**:
1. **C3-C(72.7%)の成功要因**: (a)bearレジームに限定してノイズ削減 (b)HC P>0.7で低確信予測を排除 (c)composite regime(SMA200+VIX+DD)で多面的bear判定。ただしn=11は30未満で統計的に脆弱
2. **C3-B(58.8%)の構造**: Top5特徴量選択で次元圧縮成功。VolWeighted ensembleは高ボラ期の信頼性を活用。recall 83.3%は全手法中最高だがn=22と小さい
3. **HC filteringの一貫した効果**: C3-C/C3-D/C3-B全てでHC閾値適用が精度を改善。予測確信度が実際に情報を持っている

**失敗パターン分析(AC7)**:
1. **C3-F(39.7%)の失敗要因**: 特徴量90個に拡張→次元の呪い。stackingで複雑性追加→過学習ではなく**信号希釈**。AUC 0.381はランダム以下
2. **C3-I(52.5%)の失敗**: 距離ベース(KNN)は高次元・低SNRデータに不適。LogRegの線形決定境界の方が頑健
3. **C3-H(53.3%)の失敗**: 時間ラグ/Cross-PF特徴量が追加情報を持たない。月次粒度では1-3ヶ月ラグは既にベースに内包済み
4. **C3-E(88.9%)のトラップ**: 予測ターゲット変更(崩壊→DD>10%)でbase_rate 55.7%に。3xレバETFでは10%DDが日常変動であり、問題自体が変わっている

### 19.18 Cycle1-3 横断的総括（cmd_274, 2026-02-23）

**精度推移（DM3最良、同一ターゲット定義）**:

| Cycle | 最良手法 | Precision | n | AUC帯 | 探索数 |
|-------|---------|-----------|---|-------|-------|
| C1 | VolWeighted(3指標複合) | 42.0% | 1,325 | 0.50-0.57 | 7 |
| C2-B | LogReg HC(22特徴量) | 65.5% | 132 | 0.45-0.59 | 3 |
| C3-C | Regime条件付きHC0.7 | 72.7% | 11 | 0.38-0.59 | 9 |

改善: +30.7pp(3 cycles)。ただしnは1,325→132→11と**2桁減少**。

**構造的SNR限界の定量的証拠(AC3)**:
1. AUC分布: 全探索(19手法)のAUC中央値=0.545。0.38-0.59の狭帯域に収束。「どのモデルでもランダム付近」
2. 特徴量重要度: GBC/RFの全特徴量が5-8%で均一分布。支配的予測因子は存在しない
3. モデルクラス非依存: LogReg≈GBC≈RF≈KNN(C3-D/I)。線形/非線形/距離ベース全て同水準
4. 特徴量拡張は有害: 22→90で**悪化**(65.5%→39.7%)。情報がないところに次元を追加すると精度低下
5. ラグ/Cross-PF情報ゼロ: C3-H(+0pp)。時間的・空間的に新情報が存在しない
6. キャリブレーションは情報を創造しない: C3-G AUC=0.51。後処理では信号の根本不足を補えない
7. 月次SNR: σ(4-8%/月)>>α(0.5-2%/月)、SNR≈0.1-0.5

**precision-n(予測回数)トレードオフ**:

| n範囲 | precision | 代表 | 統計的信頼性 |
|-------|-----------|------|------------|
| n≥100 | 39.7-58.5% | C3-A/F/H/I | 高（Wilson CI狭い） |
| n=50-99 | 61.8% | C3-D | 中 |
| n=10-49 | 58.8-72.7% | C3-B/C/E | 低（CI±15-20pp） |
| n<10 | 83.3% | C3-G | 無効（CI=[36%,100%]） |

→ 統計的に有意なn≥30でのprecision天井: **~62%**。80%には18pp不足（構造的）。

### 19.19 Cycle4方針提案（cmd_274, 2026-02-23）

**80%は構造的に不可能か？** — 現時点の証拠ではn≥30で80%到達は困難。ただし「完全に不可能」と結論づけるにはまだ試行の余地がある。

**提案A: フレーミング転換（推奨）**
- 月次二値分類(崩壊Y/N)を放棄し、**連続リスクスコア**に転換
- C2-C(regime risk)の延長。AUC低くても閾値調整で運用可能
- 殿のユースケース: 「今月のリスクは高い/中/低」のシグナルで十分かもしれない

**提案B: 外部データ統合**
- 未試行: FRED経済指標(失業率変化/PMI)、セクターローテーション指標、機関投資家ポジション(COT)
- Cycle2で試したVIX/yield curveは「独立だが無関連」だった。より直接的な先行指標が必要
- リスク: 月次粒度ではマクロ指標も年12点に圧縮されるためSNR改善は限定的

**提案C: 日次粒度への移行**
- 月次=年12点から日次=年252点。情報量20倍増
- ただしターゲット定義(「月間で崩壊」)の日次変換が非自明
- 実装コスト高い。experiments.db daily_prices(414K行)の活用が前提

**提案D: 「80%不到達」の正式結論**
- 3 Cycles×19手法で十分探索した。精度天井は~62%(n≥30)
- 殿への報告: 「予測精度80%は月次粒度・DM戦略固有のSNR限界により構造的に困難。リスクスコアリング(連続値)への転換を推奨」
- これ以上の探索は限界収益逓減

**成果物**:
- `scripts/analysis/cmd274_cycle3_integration.py` — 統合スクリプト
- `outputs/charts/cmd274_cycle3_comparison.csv` — 全9探索統合比較表
- `outputs/charts/cmd274_cycle123_progression.png` — Cycle1-3精度推移チャート
- `outputs/charts/cmd274_precision_n_tradeoff.png` — precision-nトレードオフ(Wilson CI付き)
