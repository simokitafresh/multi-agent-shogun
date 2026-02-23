# DM-signal コアコンテキスト
<!-- last_updated: 2026-02-23 cmd_280 dm-signal.md分割 -->

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

## 13. StockData API

- エンドポイント: `stockdata-api-6xok.onrender.com`
- クライアント: `backend/app/client.py` → `StockApiClient`
- リトライ: 3回(1s→2s→4s指数バックオフ) | タイムアウト: 60秒
- 環境変数: `STOCK_API_BASE_URL`
- ローカルDL: `download_all_prices.py grid-search` を使え。`download_prod_data.py prices` は422エラーで使用不可（cmd_042）

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
