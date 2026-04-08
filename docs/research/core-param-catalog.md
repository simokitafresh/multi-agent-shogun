# BB全14種パラメータカタログ
<!-- cmd_286 | 2026-02-23 | core.md §4から移動。全BB型のパラメータ・制約・GS範囲を網羅 -->

共通型: `LookbackPeriod` = `{months: int(0-24), days: Optional[int](max 504), weight: float(0-1)}`

## Selection Blocks（11種）

| BB名(BlockType) | パラメータ名 | 型 | 範囲 | デフォルト | GS探索範囲 | Pydantic制約（`schemas/models.py`） | 意味 |
|---|---|---|---|---|---|---|---|
| **MomentumFilter** (追い風) | top_n | int | ge=1 | 1 | T1-T5 | `Portfolio.top_n`: `ge=1, le=2`（Portfolio層） | モメンタム上位選出数 |
| | lookback_periods | List[LookbackPeriod] | リスト長制限なし | [] | 標準18点GS grid | 要素`LookbackPeriod`: `months ge=0, le=24` / `days le=504` / `weight ge=0, le=1` | モメンタム計算期間(加重合成) |
| **AbsoluteMomentumFilter** (門番) | lookback_periods | List[LookbackPeriod] | リスト長制限なし | [] | 標準18点GS grid | 要素`LookbackPeriod`: `months ge=0, le=24` / `days le=504` / `weight ge=0, le=1` | モメンタム計算期間 |
| | threshold | float | 制限なし | 0.0 | ― | 制約なし | 固定モード時の最低モメンタム閾値 |
| | threshold_mode | str | 'fixed'\|'reference_asset' | 'fixed' | ― | 制約なし | 判定モード(固定閾値/参照資産比較) |
| | absolute_asset | str | ticker symbol | None | ― | `Portfolio.absolute_asset`: `strip()+upper()` | ゲートキーパー資産(例:LQD,TMF,^VIX,SPXL) |
| | reference_asset | str | ticker/経済指標 | None | ― | 制約なし | 基準資産(例:DTB3=リスクフリーレート) |
| | reference_lookback_periods | List[LookbackPeriod] | リスト長制限なし | None(→lookback_periods) | ― | 制約なし | 基準資産用lookback(省略時はlookback_periodsを流用) |
| **RelativeMomentumFilter** (相対) | benchmark | str | ticker symbol(空文字不可) | ""(事実上必須) | SPY,EFA,AGG等 | `Portfolio.benchmark_ticker`: 空文字禁止、`DTB3/CASH`禁止、`strip()+upper()` | 比較対象ベンチマーク銘柄 |
| | lookback_periods | List[LookbackPeriod] | リスト長制限なし | [] | 標準18点GS grid | 要素`LookbackPeriod`: `months ge=0, le=24` / `days le=504` / `weight ge=0, le=1` | モメンタム計算期間(加重合成) |
| **MomentumAccelerationFilter** (加速) | top_n | int | ge=1 | 1 | T1-T5 | `Portfolio.top_n`: `ge=1, le=2`（Portfolio層） | 加速度上位選出数 |
| | numerator_period | LookbackPeriod | 必須 | ― | 日次:10D,15D,20D / 月次:1M-24M | `LookbackPeriod`: `months ge=0, le=24` / `days le=504` / `weight ge=0, le=1` | 短期(分子)期間 |
| | denominator_period | LookbackPeriod | 必須 | ― | 日次:10D,15D,20D / 月次:1M-24M | `LookbackPeriod`: `months ge=0, le=24` / `days le=504` / `weight ge=0, le=1` | 長期(分母)期間 |
| | method | str | 'ratio'\|'diff' | 'ratio' | ratio, diff | 制約なし | 加速度計算方法(比率/差分) |
| **ReversalFilter** (逆風) | bottom_n | int | 制限なし(実質ge=1) | 1 | B1-B5 | 制約なし | モメンタム下位からの逆張り選出数 |
| | lookback_periods | List[LookbackPeriod] | リスト長制限なし | [] | 標準18点GS grid | 要素`LookbackPeriod`: `months ge=0, le=24` / `days le=504` / `weight ge=0, le=1` | モメンタム計算期間(加重合成) |
| **SafeHavenSwitch** (セーフヘイブン) | safe_haven_asset | str | ticker or 'Cash' | 'Cash' | ―(インフラBB) | `Portfolio.safe_haven_asset`: `strip()+upper()` | 退避先銘柄(例:XLU,GLD,AGG) |
| | switch_condition | str | 'empty_tickers'のみ | 'empty_tickers' | ― | 制約なし | 切替条件(上流BB出力が空の時) |
| **ComponentPrice** (FoF価格読込) | lookback_days | int | ge=1 | 730 | ―(インフラBB) | 制約なし | MonthlyReturnテーブルからのデータ読込日数 |
| **MultiViewMomentumFilter** (多眼) | base_period_months | int | **ge=4必須**(L100) | 12 | 4M-24M(12点) | 制約なし | ルックバック月数(各視点でbase-skip) |
| | top_n | int | ge=1 | 2 | T1-T5 | `Portfolio.top_n`: `ge=1, le=2`（Portfolio層） | 各視点からの選出数(和集合サイズ=top_n〜4×top_n) |
| | *SKIP_MONTHS_LIST* | *List[int]* | *[0,1,2,3]固定* | *―(クラス変数)* | *config不可* | *制約なし* | *4視点のスキップ月数(変更不可)* |
| **SingleViewMomentumFilter** (抜き身) | base_period_months | int | ge=1 | 12 | 標準18点GS grid | 制約なし | ルックバック月数 |
| | skip_months | int | 0-3推奨 | 0 | 0,1,2,3 | 制約なし | 直近N月をスキップ |
| | top_n | int | ge=1 | 2 | T1-T5 | `Portfolio.top_n`: `ge=1, le=2`（Portfolio層） | モメンタム上位選出数 |
| **TrendReversalFilter** (変わり身) | period_months | int | ge=1 | 3 | 標準18点GS grid | 制約なし | モメンタム計算月数 |
| | select_n | int | ge=1 | 2 | T1-T5 | 制約なし | 上位N+下位Nそれぞれの選出数(和集合) |
| **MonthlyReturnMomentumFilter** (月次GS方式) | base_period_months | int | ge=1 | 12 | 標準18点GS grid | 制約なし | ルックバック月数 |
| | skip_months | int | ge=0 | 0 | 0,1,2,3 | 制約なし | 直近N月をスキップ |
| | top_n | int | ge=1 | 1 | T1-T5 | `Portfolio.top_n`: `ge=1, le=2`（Portfolio層） | モメンタム上位選出数 |

## Terminal Blocks（3種）

| BB名(BlockType) | パラメータ名 | 型 | 範囲 | デフォルト | GS探索範囲 | Pydantic制約 | 意味 |
|---|---|---|---|---|---|---|---|
| **EqualWeight** (分身) | ― | ― | ― | ― | ― | 制約なし | パラメータなし。1/n均等配分 |
| **CashTerminal** (キャッシュ退避) | ― | ― | ― | ― | ― | 制約なし | パラメータなし。100% Cash固定 |
| **KalmanMeta** (カルマン加重/ディスコン) | weights | Dict[str,float] | 非空dict | None | ―(外部注入) | 制約なし | 直接重み指定 |
| | weights_key | str | context lookup key | "kalman_weights" | ― | 制約なし | context.intermediate_resultsからの取得キー |

## 選出方式サマリー

| 方式 | 対象BB | 動作 |
|------|--------|------|
| cutoff_score全包含 | MomentumFilter, SingleViewMomentumFilter, MomentumAccelerationFilter, MultiViewMomentumFilter, MonthlyReturnMomentumFilter | 境界スコアと同点の銘柄を全て採用(top_n超過許容) |
| strict slice | TrendReversalFilter, ReversalFilter | 厳密にN件切り出し(同点でも切り捨て) |
| 閾値フィルタ | AbsoluteMomentumFilter | threshold/参照資産比較。通過/遮断のみ |
| ベンチマーク超過 | RelativeMomentumFilter | benchmark超過の全ticker通過(上限なし) |
| 条件切替 | SafeHavenSwitch | 空集合→safe_haven_assetに差し替え |
| N/A | ComponentPrice, EqualWeight, CashTerminal, KalmanMeta | データ読込/終端処理(選出なし) |

標準18点GS grid: 日次=10D,15D,20D / 月次=1M,2M,3M,4M,5M,6M,7M,8M,9M,10M,11M,12M,15M,18M,24M (1M=21営業日)
