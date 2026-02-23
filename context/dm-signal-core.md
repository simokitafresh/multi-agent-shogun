# DM-signal コアコンテキスト
<!-- last_updated: 2026-02-23 cmd_286 詳細移動+圧縮(631→300行以下) -->

> 読者: エージェント。推測するな。ここに書いてあることだけを使え。

タスクに `project: dm-signal` がある場合このファイルを読め。パス: `/mnt/c/Python_app/DM-signal/`

## 0. 研究レイヤー構造

| Layer | 名前 | 内容 | 状態 |
|-------|------|------|------|
| L1 | 基本PF発見 | 個別DM戦略（青龍/朱雀/白虎/玄武）のパラメータGS・検証 | 完了(12体登録済み) |
| L2 | 忍法FoF | 5忍法(分身/追い風/抜き身/変わり身/加速)×3モード(激攻/鉄壁/常勝)のGS・登録 | 完了(12体登録+全0.00bp PASS) |
| L3 | 組合せ堅牢化 | 上位構造の堅牢性検証（WF優先。FoFは乗り換え戦略のため時間軸評価が本質。CPCVは補助） | 未着手(cmd_176殿裁定待ち) |

## 1. システム全体像

本番: Render.com — PostgreSQL + FastAPI + Next.js。StockData API毎日01:00 UTC自動同期。
ローカル: WSL2 — dm_signal.db(本番ミラー) + experiments.db(分析用ground truth)。

| Layer | 時刻(UTC) | ジョブ | 内容 |
|-------|-----------|--------|------|
| 0 | 01:00 | sync-prices | StockData APIから価格DL |
| 1 | 01:05 | sync-tickers | ティッカーメタデータ同期 |
| 2 | 01:10 | sync-standard | 個別DM戦略シグナル計算 |
| 3 | 01:40 | sync-fof | FoFシグナル計算 |

再計算排他制御: `recalc_status.py`の`threading.Lock`。同時実行不可。409=正常排他(FAILではない)。30秒待って再実行。→ `projects/dm-signal.yaml` (c) recalculate_concurrency

## 2. DB地図

核心ルール(接続先/書込禁止等) → `projects/dm-signal.yaml` (c) database
テーブル詳細(全DB) → `docs/research/core-db-tables.md`

要点: experiments.db=価格ground truth(daily_prices 414K行) | dm_signal.db=本番ミラー(PF設定用) | 本番PostgreSQL=SSOT
UUID不一致: DM7+以外は2DB間でUUID異なる（§3参照）
DLコマンド: `download_all_prices.py grid-search`(価格) | `download_prod_data.py monthly-returns`(月次)。`prices`は422エラー(cmd_042)

## 3. 四神（しじん）構成

四神 = 各DMファミリー全パラメータ総当たりGS(172,818パターン) → GFS → チャンピオン戦略均等配分FoF。

| 四神 | 構成 | チャンピオン戦略 | FoF CAGR |
|------|------|----------------|----------|
| 青龍 | DM2 FoF n=3 | Qj_GLD_10D_T1, Qj_XLU_11M_5M_1M_w50_30_20_T1, Be_GLD_18M_7M_1M_w60_30_10_T1 | 59.5% |
| 朱雀 | DM3 FoF n=2 | M_TMV_4M_3M_20D_w50_40_10_T1, Qj_TMV_3M_15D_w50_50_T1 | 40.0% |
| 白虎 | DM6 FoF n=2 | Qj_XLU_15M_3M_w70_30_T2, Qj_GLD_4M_1M_w50_50_T1 | 54.7% |
| 玄武 | DM7+ Prod n=1 | M_SPXL_XLU_24M_T1 | 29.5% |

選定: GFS(CAGR最大化順次追加) | 堅牢性: SUSPECT検出 | 参照: portfolio-research/015→023§2.3

### 命名規則（殿裁定 2026-02-20）

L1四神FoF: {モード}-{四神名}（激攻-青龍等） | L2忍法FoF: {忍法名}-{モード}（加速-激攻等）
モード: 激攻(CAGR) / 鉄壁(MaxDD) / 常勝(NewHigh)。旧サフィックス廃止。同一config→忍法名のみ
※ 智将(Calmar)→鉄壁(MaxDD)変更理由: Spearman相関分析でCalmarはCAGRと高相関(rho=0.86)で冗長。MaxDDはCAGRと低相関(rho=0.49)で独自軸
現四神=CAGRモード（激攻）のみ。12パターン計画: 4神×3モード（激攻/鉄壁/常勝）
L2忍法FoF: 5忍法×3モード=最大15体。monban除外(ext_pricesのCSV化に追加設計必要)。nukimi_c→nukimiに統合(L054)
cmd_246完了: 12体チャンピオン本番DB登録済み。全0.00bp PASS。PF総数89(上限100)
新忍法候補: 逆風(cmd_249採用決定)/追い越し(cmd_250)/四つ目(cmd_284フルGS完了) → §4新忍法候補参照

⚠ L1/L2混同禁止: L1=神の中身(GSパラメータ) | L2=神の組み合わせ(BB)

### L2忍法チャンピオン（cmd_246完了 — 全12体 0.00bp PASS）

全5忍法ミニパリティ0bp確定(cmd_227)後、4忍法フルGSを実行。

| 忍法 | パターン数 | 備考 |
|------|-----------|------|
| 追い風 | 42,174 | tiebreak修正後コードで再実行 |
| 抜き身 | 152,295 | — |
| 変わり身 | 28,116 | — |
| 加速 | 238,986 | — |
| 分身 | 781 | cmd_214完了済み(EqualWeight) |

合計: 462,352パターン。

| 忍法 | 激攻(CAGR) | 鉄壁(MaxDD) | 常勝(NHR) |
|------|-----------|------------|----------|
| 追い風 | 64.85% / 18M,N1 | -15.87% / 18M,N2 | 64.56% / 9M,N3 |
| 抜き身 | 74.21% / 18M,SK3,N1 | -15.51% / 18M,SK1,N1 | 65.73% / 24M,SK1,N4 |
| 変わり身 | 62.25% / 24M,N1 | -13.51% / 24M,N1 | 65.7% / 24M,N2 |
| 加速 | 76.27% / 10D/4M,ratio,N1 | -14.47% / 9M/10M,diff,N1 | 66.03% / 18M/24M,ratio,N1 |

詳細（UUID・構成四神・パリティ月数）→ `queue/reports/hanzo_report.yaml` (cmd_246 AC5)

### ポートフォリオ一覧

UUID・銘柄構成・リバランス設定 → `projects/dm-signal.yaml` (e) shijin。全銘柄: GLD|LQD|SPXL|SPY|TECL|TMF|TMV|TQQQ|XLU|^VIX

| 四神 | dm_signal.db UUID | experiments.db UUID | 戦略 |
|------|-------------------|---------------------|------|
| 青龍(DM2) | f8d70415 | 4db9a1f5 | ロング株式 |
| 朱雀(DM3) | c55a7f68 | 8300036e | ロングVol/債券 |
| 白虎(DM6) | 212e9eee | a23464f7 | VIXレジーム |
| 玄武(DM7+) | 8650d48d | **8650d48d(同一)** | リセッション防御 |

シグナル生成(例DM2): MomentumFilter(top1) → AbsoluteMomentum(LQD>DTB3?) → SafeHavenSwitch(空→XLU) → EqualWeight → signal

## 4. ビルディングブロック

パス: `backend/app/services/pipeline/blocks/` | BlockType enum: `schemas/pipeline.py:18-37` | 登録: `shared.py:208-253`
標準パターン → `projects/dm-signal.yaml` (d) pipeline
全14種BBパラメータ詳細・選出方式 → `docs/research/core-param-catalog.md`

### BB種別分類（cmd_247）

| 区分 | BB名(BlockType) | 対応忍法 |
|------|----------------|---------|
| 採用 | MomentumFilter / SingleViewMomentumFilter / TrendReversalFilter / MomentumAccelerationFilter | 追い風 / 抜き身 / 変わり身 / 加速 |
| 採用 | AbsoluteMomentumFilter / EqualWeight | 門番 / 分身(全忍法terminal) |
| 補助 | SafeHavenSwitch / MonthlyReturnMomentumFilter | 門番補助 / 追い風GS方式 |
| 未採用 | ReversalFilter → **逆風**(cmd_249採用決定) / RelativeMomentumFilter(cmd_250) / MultiViewMomentumFilter(cmd_251) | 新忍法候補 |
| 未採用 | ComponentPrice / CashTerminal / KalmanMeta | インフラ/ディスコン |

### tiebreakルール（cmd_217, L086/L092）

| 方式 | 対象忍法 | 動作 |
|------|---------|------|
| cutoff_score全包含 | 追い風・抜き身・加速(+MultiView/MonthlyReturn) | 境界同点を全採用(top_n超過許容) |
| strict slice | 変わり身・逆風 | 厳密N件切出し |

L092: float64同値タイ→ハイブリッド方式(desc/asc別ソート+重複時desc単一リスト両端スライス)

GS修正経緯(cmd_215→217): cmd_215でtop_n同点パリティ差分検知→cmd_217で方式差(cutoff_score vs strict slice)確定。追い風=commit `9277881`修正済み/加速=cutoff_score適用済み/抜き身=cmd_217 Phase3で修正継続

### GS-本番パリティ統一原則（cmd_229: PD-011/012/013）

- 全4忍法は**cumulative_return→pct_change方式**で統一。旧monthly_return方式禁止(PD-013)
- 504日分の日次データが揃うまでCash扱い(PD-011)。長lookback(12M/24M)で差異顕在化
- モメンタム算出は`cumulative_return`から`pct_change(mc)`。本番同一コードパス優先(PD-012/L076)
- 教訓詳細→§19.3(L086-L092)

### SVMF/MVMFバグ修正（cmd_235 + cmd_244）

| cmd | 問題 | 修正 | commit |
|-----|------|------|--------|
| cmd_235 | `is_monthly_data()`未使用→行数ベース誤判定(L097) | skip前に呼出 | a6ba012 |
| cmd_244 | SVMF fallback `target_date`未フィルタ→将来データ参照(L098) | `index<=target_date`追加 | 2e970ed |

影響PF: MIX2/3/4(SVMF)+bam-2/6(MVMF)。修正後5PF全PASS。

### 新忍法候補（2026-02-22 偵察開始）

| 忍法候補 | BB型 | 状態 | cmd | 主要パラメータ |
|---------|------|------|-----|-------------|
| 逆風(gyakufuu) | ReversalFilterBlock | 採用決定 | cmd_249 | bottom_n(B1-B5), lookback。strict slice |
| 追い越し(oikoshi) | RelativeMomentumFilterBlock | 偵察完了 | cmd_250 | benchmark=SPY固定(殿裁定PD-023: 複数候補不採用), lookback |
| 四つ目(yotsume) | MultiViewMomentumFilterBlock | **フルGS完了** | cmd_284 | base_period(≥4), top_n。SKIP=[0,1,2,3]固定 |

### パイプライン実行・シグナル

`PipelineEngine.execute_pipeline(pipeline_config, target_date, initial_tickers, price_data_cache, momentum_cache)` → `{signal, momentum_data, block_results, weights}`
PipelineContext(黒板): `current_tickers`(絞込) / `momentum_data`(各BB結果) / `final_weights`(Terminal配分)
**signal**: パイプライン生出力 | **holding_signal**: リバランス月でなければ前月維持。MonthlyReturnはholding_signalで計算せよ

## 5. ローカル分析関数

`simulate_strategy_vectorized()`: `grid_search_metrics_v2.py`。MomentumCache必須(渡さないと黙って空リスト)。
月次リターン: 月末シグナル→翌月適用。Return=(月末価格/月初価格)-1。マルチアセット=単純平均。
詳細(全パラメータ・スケジュール) → `docs/research/core-local-analysis.md`

## 8. APIエンドポイント概要

FastAPI 22ルーター/84-88EP | Next.js frontend | 共通: `ApiResponse{success,data,error,message}`
主要: `/api/signals` `/api/portfolios/get|save` `/admin/recalculate-sync` `/healthz`
詳細(全EP・レスポンス構造) → `docs/research/core-api-endpoints.md` | yaml → `projects/dm-signal.yaml` (h) api

## 10. ディレクトリ構成

詳細ツリー → `docs/research/core-directory-structure.md`
主要: backend/app/(api|services/pipeline|jobs|db|schemas) | frontend/lib/ | scripts/analysis/grid_search/ | analysis_runs/experiments.db

## 11. Lookback標準グリッド（恒久ルール）

18パターン基本探索範囲。換算: 1M=21営業日。

| # | 値 | 営業日数 | # | 値 | 営業日数 | # | 値 | 営業日数 |
|---|-----|---------|---|-----|---------|---|-----|---------|
| 1 | 10D | 10 | 7 | 4M | 84 | 13 | 10M | 210 |
| 2 | 15D | 15 | 8 | 5M | 105 | 14 | 11M | 231 |
| 3 | 20D | 20 | 9 | 6M | 126 | 15 | 12M | 252 |
| 4 | 1M | 21 | 10 | 7M | 147 | 16 | 15M | 315 |
| 5 | 2M | 42 | 11 | 8M | 168 | 17 | 18M | 378 |
| 6 | 3M | 63 | 12 | 9M | 189 | 18 | 24M | 504 |

既存パラメータがこの18点のどれに該当するか常に明示。カバレッジマップでは探索済み/未探索を示せ。

## 13. StockData API

エンドポイント: `stockdata-api-6xok.onrender.com` | クライアント: `backend/app/client.py`
環境変数: `STOCK_API_BASE_URL` | リトライ3回(指数バックオフ) | タイムアウト60秒 | ローカルDL: `download_all_prices.py grid-search`

## 15. 殿の個人PF保護リスト（絶対ルール — cmd_198）

> DB操作(DELETE/UPDATE)タスクでは以下のPFを**絶対に削除・変更してはならない**。

**Standard PF(21体)**: DM2, DM2-20%/-40%/-60%/-80%/-test/-top, DM3, DM4, DM5, DM5-006, DM6, DM6-5/-20%/-40%/-60%/-80%/-Top, DM7+, DM-safe, DM-safe-2
**FoF PF(14体)**: Ave-X, Ave四神, 裏Ave-X, MIX1-4, bam-2/-6, 劇薬DMオリジナル/スムーズ/bam/bam_guard/bam_solid
削除許可: L0-*(GS生成) / 四神L1(12体) / 忍法L2(15体) のみ
運用: DB操作タスクのdescriptionに「殿PF除外」明記必須 / dry-runで残存PFリスト確認してから本削除
詳細→`projects/dm-signal.yaml` protected_portfolios

## 18. backend `folder_id` 実態（cmd_269, 2026-02-23）

| 観点 | 内容 |
|------|------|
| カラム | `Portfolio.folder_id`: String, nullable, FK→`portfolio_folders.id`(ON DELETE SET NULL) (`models.py:75`) |
| マイグレーション | Alembicなし。起動時処理(`migrations.py:66-79`作成, `:87`追加) |
| 使用箇所 | 定義: `models.py:75` / 参照+更新: `api/folders.py:77,104,213,251,304` |
| Schema | `Portfolio`スキーマに`folder_id`なし。CRUD未対応。更新は`folders.py:283-309`のみ |
| 本番実値 | 全88PFが`folder_id=NULL` |

## 19. 教訓索引（Lesson Index）
<!-- cmd_286: lessons.yaml 50件から core該当28件を索引化 -->

### 19.1 DB関連

| ID | 結論(1行) | 出典 |
|---|---|---|
| L084 | `recalculate-status`の`is_running=None`は完了ではない。DB行数カウントで判定せよ | cmd_215 |
| L085 | テストPF削除のFK依存は16テーブル。4テーブルだけでは不足 | cmd_215 |
| L099 | `pipeline_config LIKE '%ReversalFilter%'`はTrendReversalFilterを誤検知→`jsonb_path_exists`で解決 | cmd_222 |
| L118 | DTB3は`economic_indicators`ではなく`daily_prices`テーブルに`ticker='DTB3'`として格納 | cmd_282 |
| L119 | DATA_CATALOG 86銘柄は本番PostgreSQL側。`experiments.db`は実際14銘柄のみ(ETF12+DTB3+VIX) | cmd_282 |
| L126 | `experiments.db`はスナップショットでありSSOTではない | cmd_222 |

### 19.2 BB仕様・バグ修正

| ID | 結論(1行) | 出典 |
|---|---|---|
| L093 | SVMF月次/日次判定バグ: `is_monthly_data()`未使用で行数ベース判定が月次データを日次と誤判定 | cmd_227 |
| L096 | skip処理のデータ頻度判定は`is_monthly_data()`を使え(行数ヒューリスティック禁止) | cmd_234 |
| L097 | SVMF/MVMFのskip計算に`is_monthly_data()`使え。同一ファイル内に既存実装あり | cmd_233 |
| L098 | SVMF fallbackパスが`price_data_cache`全期間参照し`target_date`未フィルタ→将来データ参照バグ | cmd_227 |
| L100 | MVMF `base_period_months`≥4必須。skip=3で`effective_months`≤0になる | cmd_222 |
| L101 | MVMF Phase3 momentum_cache事前計算はFoF専用でスキップ。Phase5 fallbackで計算 | cmd_222 |
| L102 | MVMF 4視点`SKIP_MONTHS_LIST=[0,1,2,3]`はクラス変数固定。configで変更不可 | cmd_222 |
| L105 | BB config未拘束(`Dict[str,Any]`)がGS無効パターン量産の根因。制約注入は`build_grid`直後が最適 | cmd_264 |
| L124 | ブロック名は`BlockType` enum値で統一する | cmd_222 |

### 19.3 GS-本番パリティ

| ID | 結論(1行) | 出典 |
|---|---|---|
| L086 | GS tiebreak本番準拠: `cutoff_score`全包含方式。strict top_nでは短lookbackでFAIL | cmd_217 |
| L087 | kasoku長lookback(12M/24M)でGS-本番初期化期間差異が発生(504日ルール) | cmd_217 |
| L088 | L1パリティPASSはtie処理網羅の証明にならない(構造的にtie不発だっただけ) | cmd_218 |
| L089 | GS-本番パリティはデータソース一致が前提。CSV vs DBでは保証されない | cmd_222 |
| L090 | GS `monthly_return` NaN系 vs 本番 `cumulative_return` 系でコンポーネント選出数が変わる | cmd_225 |
| L091 | GSモメンタムは`cumulative_return` ratio方式を使え。prod方式はタイブレーク不一致を誘発 | cmd_222 |
| L092 | kawarimi float64同値タイ: ハイブリッド方式(desc/asc別ソート+重複時desc単一リスト両端スライス) | cmd_223 |
| L094 | oikaze `cutoff_score` epsilon tolerance(1e-12)が必要。float64精度差~2e-16 | cmd_227 |
| L095 | kasoku `main()`が`cumulative_returns`を未ロード。常にfallback(prod方式)が使用される | cmd_227 |

### 19.4 FoF登録フロー

| ID | 結論(1行) | 出典 |
|---|---|---|
| L127 | FoFパリティ比較は本番の現行パラメータを先に確認する | cmd_222 |
| L129 | 新FoF追加後の再計算は`sync-fof`(L3)を使う。sync-standardでは不足 | cmd_222 |
| L130 | GS構成四神と本番FoF構成PFの不一致に注意。登録前に突合必須 | cmd_222 |
| L133 | FoF作成は12ステップ省略不可。ステップ2-4省略でGS前提崩壊(抜き身3の失敗) | cmd_284 |

### 19.5 GS運用・config

| ID | 結論(1行) | 出典 |
|---|---|---|
| L112 | `monthly_returns.signal`がJSON辞書形式(`'{"TECL":1.0}'`)のとき`json.loads`でキー抽出必須 | cmd_274 |
| L123 | `pipeline_config`テンプレートのパラメータ名はコードと1:1一致必須 | cmd_222 |
| L132 | GS結果を利用する際は`DATA_CATALOG.md`と`meta.yaml`を必ず参照する | cmd_222 |
