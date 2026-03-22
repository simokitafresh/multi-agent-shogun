# DM-signal コアコンテキスト
<!-- last_updated: 2026-03-20 cmd_1123 PI制度導入+FoF flush修正(cmd_1096)+resample修正(cmd_1115)+PBarSelectionBlock+p̄バッチ -->

> 読者: エージェント。推測するな。ここに書いてあることだけを使え。

タスクに `project: dm-signal` がある場合このファイルを読め。パス: `/mnt/c/Python_app/DM-signal/`

## 0. 研究レイヤー構造

| Layer | 名前 | 内容 | 状態 |
|-------|------|------|------|
| L1 | 基本PF発見 | 個別DM戦略（青龍/朱雀/白虎/玄武）のパラメータGS・検証 | 完了(12体登録済み) |
| L2 | 忍法FoF | 5忍法(分身/追い風/抜き身/変わり身/加速)×3モード(激攻/鉄壁/常勝)のGS・登録 | 完了(12体登録+全0.00bp PASS) |
| L3 | 組合せ堅牢化 | 上位構造の堅牢性検証（WF優先。FoFは乗り換え戦略のため時間軸評価が本質。CPCVは補助） | 未着手(cmd_176殿裁定待ち) |

**Trade-Rule教訓（cmd_766）** — LLMが間違えやすいルール:
- L233: RULE09 Open/Closeは独立計算系列、混在禁止
- L234: RULE10 シグナル判定はClose固定、Openはリターン計算限定
- L235: RULE11 Monthly Trade ReturnとMonthly Returns Returnは完全一致
- L236: 誤解5 リターンは累積インデックス比ではなく価格比×ウェイト
- L237: 誤解6 日次複利積ではなく価格比×ウェイトで月次を出す
- L238: 誤解7 FoFのシグナル参照日は当月初営業日のholding_signal
- L239: 誤解13 Open-to-Openは異なる日のOpen同士を結ぶ
- L240: 誤解14 Open/Closeデフォルト判断はOpen-to-Open

## 1. システム全体像

本番: Render.com — PostgreSQL + FastAPI + Next.js。StockData API毎日01:00 UTC自動同期。viewer/admin認証は in-memory dict ではなく DB-backed token (`viewer_tokens`/`admin_tokens`) + HttpOnly Cookie (`viewer_session`/`admin_session`) が正で、Cookie期限は JST 期限日 23:59:59 を UTC に変換して設定する。参照: `/mnt/c/Python_app/DM-signal/backend/app/auth.py`, `/mnt/c/Python_app/DM-signal/backend/app/api/auth.py`, `/mnt/c/Python_app/DM-signal/backend/app/db/models.py`
ローカル: WSL2 — dm_signal.db(本番ミラー) + experiments.db(分析用ground truth)。

| Layer | 時刻(UTC) | ジョブ | 内容 |
|-------|-----------|--------|------|
| 0 | 01:00 | sync-prices | StockData APIから価格DL |
| 1 | 01:05 | sync-tickers | ティッカーメタデータ同期 |
| 2 | 01:10 | sync-standard | 個別DM戦略シグナル計算 |
| 3 | 01:40 | sync-fof | FoFシグナル計算 |

再計算排他制御: `recalc_status.py`の`threading.Lock`。同時実行不可。409=正常排他(FAILではない)。30秒待って再実行。→ `projects/dm-signal.yaml` (c) recalculate_concurrency
p̄バッチ: `p_average_results`テーブルに事前計算結果を格納。バッチ未実行 or cold sleepで空(L319)。p̄ゲート: `gate_p_average_freshness.sh`で鮮度監視。
- L232: recalculate_fast.pyのholding_signal更新は「月変わりANDリバランス月」の2条件で制御される（cmd_764）

## 2. DB地図

核心ルール(接続先/書込禁止等) → `projects/dm-signal.yaml` (c) database
テーブル詳細(全DB) → `docs/research/core-db-tables.md`

要点: experiments.db=価格ground truth(daily_prices 414K行) | dm_signal.db=本番ミラー(PF設定用) | 本番PostgreSQL=SSOT

### SSOT 3層階層（殿確定 2026-03-11 §25）

| Level | 名前 | 役割 | ファイル |
|-------|------|------|---------|
| L0(データ) | Price table | 全ての原点。営業日=Priceレコード存在日 | — |
| L0(ルール) | trade-rule.md | 理論上の理想形(11絶対ルール定義) | `docs/rule/trade-rule.md` |
| L1a | calculate_monthly_return() | 月次リターンのSSOT関数 | `backend/app/services/return_calculator.py` |
| L1b | calculate_trade_period_return() | Trade期間リターンのSSOT関数（月次複利合成方式 cmd_768） | `backend/app/services/return_calculator.py` |
| L2 | MonthlyReturn table | L1aの事前計算キャッシュ。`recalculate_fast.py`で生成 | — |
| L3 | UI表示層 | L1/L2を使用する派生実装 | — |

→ `projects/dm-signal.yaml` ssot_hierarchy
UUID不一致: DM7+以外は2DB間でUUID異なる（§3参照）
DLコマンド: `download_all_prices.py grid-search`(価格) | `download_prod_data.py monthly-returns`(月次)。`prices`は422エラー(cmd_042)
- L156: pending判定のas_of基準は2系統存在する: DB最新日(signals) vs date.today()(monthly-trade)（cmd_524）
- L171: バッチジョブのUPSERTはdb.merge()パターンが最も簡潔（cmd_550）
- L172: 新規テーブル導入時はインデックス作成をif/else外に置くと自己修復性が上がる（cmd_550）
- L173: パイロット→本番移植ではDB層分離がパリティ検証を容易にする（cmd_550）
- L296: 履歴特徴量系の新手法を入れる前にsnapshot SSOTを埋めよ（cmd_861）
- L420: monthly_returnsテーブルにはmonthly_return(Close)とmonthly_return_open(Open)の2列。GSはOpen-to-Open方式。パリティ検証はmonthly_return_open列を使うこと（cmd_1098）[PI-008]

## 3. 四神（しじん）構成

**★ 設計原理（殿直伝 2026-03-15 — 全エージェント必読、すべての検討の前提条件）**

**L0概念（最重要）**: 単一銘柄=受動的価格系列（判断なし）。DM PF=意思決定が埋め込まれた価格系列（市場+アルゴリズム判断の合成物）。DM-SignalはこのDM PFをL0として扱う。論文手法をそのまま適用できるケースはほぼない——意思決定システムの出力であることを常に意識せよ。モメンタム(二階微分)・相関(時変)・forward-looking(多変数)・最適化(二重化)・性能分解(因果不明)の全てが受動的資産と異なる。

源流はDM2+/DM3/DM6/DM7+の4ファミリー。四神はここから生まれた。
- **absolute assetが戦略のDNA**: ファミリーを定義し、戦略の性格を決定する
- **全パラメータが一体で一つの意味を成す**: lookback/rebalance/relative/safe_havenを個別に見ても本質は掴めない
- **3モード(激攻/鉄壁/常勝)はDNA内の味付け**: absolute+relative+safe_havenは不変。源流の性格は変わらない

| 源流 | Absolute | DNA（不変の性格） | 全パラメータの統一意思 |
|------|----------|-------------------|---------------------|
| DM2+ | LQD(安定債券) | **降りない** | LQD基準で退避ほぼ不発動+XLU退避=株内残留+12M複合窓でノイズ平滑化。常時リスクオン |
| DM3 | TMF(3倍債券) | **債券方向スイッチ** | TMF↔TMV(完全逆ポジション)を20D窓で切替。bimonthlyが3倍レバの過剰切替を制御。債券でアルファ |
| DM6 | ^VIX(恐怖指数) | **レジーム判定** | VIXで恐怖の上下を検知。15D観測(最速)×quarterly行動(最遅)でノイズ除去。GLD=恐怖時の第三軸 |
| DM7+ | SPXL(3倍S&P) | **構造的逆張り** | 攻守逆転(relative=XLU守り,safe_haven=TQQQ攻め)+24M窓。短期暴落を無視し最攻撃ポジション維持 |

**⚠ よくある誤解（一般常識の暗黙の前提で四神を判断すると全て間違える）**:
- SM01: safe haven=防御的→玄武のTQQQは最大火力。SM02: 3倍レバ=長期不適→四神の核心設計
- SM03: 暴落時=退避→青龍は「降りない」がDNA。SM04: 危機=債券→朱雀はTMV(債券ショート)
- SM05: VIX高=危険→DM6は方向(上昇/下降)を見る。SM07: 短lookback=良→DM7+は鈍さが本質
- SM08: ラベル信頼→玄武「リセッション防御」は実態と真逆。SM09: CAGR最低=劣→低相関が価値
- SM12: SPY/QQQ(非レバ)=安全→DM2+のLQD常時保有でレバが活きる。非レバは設計の無駄遣い
- **思想レベル**: SM13: 動的ウェイト最適化→メタ最適化=過適合。SM14: 10PFを1完璧PFに→過適合(殿明確否定)
- SM15: 好成績に集中/悪成績を外す→低相関を捨てる。SM16: 4神一致で行動→1戦略に縮退
- SM17: 忍法=四神の上位互換→レイヤーが違う。SM18: 神同士のシグナル制御→独立性破壊
- SM19: 動的配分=高度→殿哲学は真逆(不可知→単純保有)。SM20: BB増=精度↑→シンプルBBがGSチャンピオン
- **根源**: SM21: DM PFを単一銘柄と同じに扱える→受動的資産vs意思決定システムの出力。SM13-SM20の全根源
- 全21件の詳細 → `projects/dm-signal.yaml` (e) common_misconceptions_shijin

- **計算と解釈の分離原則（殿裁定 2026-03-16）**: 評価指標（p̄, CPCV等）は全PFに一律で計算し、結果はそのまま記録する。計算結果をどう解釈・運用するかは別レイヤーの人間判断。朱雀がp̄で高く出ても/CPCVで不合格でも、それは「単独システムとしての一貫性がない」という事実であり、素材としての価値否定ではない。四神は素材であり、FoFが動的に組み合わせる完成品。素材レベルで一貫性を要求するのは設計思想と矛盾する。**CPCVやp̄の結果が悪いからFoFに使わない、は誤用。**
- **殿の指標哲学(2026-03-16裁定)**: 体験→指標→道具の順で設計。Sharpe/σ後回し。優先4指標: Max Run-up / Tail Contribution / Left-tail Jumps / NHF。「平均は悪、極値が全て」
- **辞書フィットネス**: ◎M03(Rank Persistence) ○→◎M10(DSR→CAGR/NHR差替) △→○M05(HMM→市場適用) △M09(PSR=Sharpe衝突) ×M08(Meta-Labeling=再訓練なし)
- 詳細 → `projects/dm-signal.yaml` (f) indicator_philosophy + dictionary_fitness

詳細設計・DNA制約・誤解リスト → `projects/dm-signal.yaml` (e) shijin

### 旧四神(v1: cmd_246時代 — FoF構成) ⚠ ディスコン

> **v1(191,796パターン広探索→CPCV→32ユニット方式)は全廃。シン四神v2に移行済み。**
> 以下は記録として残置。新規タスクではシン四神v2を参照せよ。

四神 = 各DMファミリー全パラメータ総当たりGS(172,818パターン) → GFS → チャンピオン戦略均等配分FoF。

| 四神 | 構成 | チャンピオン戦略 | FoF CAGR |
|------|------|----------------|----------|
| 青龍 | DM2 FoF n=3 | Qj_GLD_10D_T1, Qj_XLU_11M_5M_1M_w50_30_20_T1, Be_GLD_18M_7M_1M_w60_30_10_T1 | 59.5% |
| 朱雀 | DM3 FoF n=2 | M_TMV_4M_3M_20D_w50_40_10_T1, Qj_TMV_3M_15D_w50_50_T1 | 40.0% |
| 白虎 | DM6 FoF n=2 | Qj_XLU_15M_3M_w70_30_T2, Qj_GLD_4M_1M_w50_50_T1 | 54.7% |
| 玄武 | DM7+ Prod n=1 | M_SPXL_XLU_24M_T1 | 29.5% |

選定: GFS(CAGR最大化順次追加) | 堅牢性: SUSPECT検出 | 参照: portfolio-research/015→023§2.3

### シン四神v2（cmd_1018-1080: L1 standard PF）— 現行

旧v1を全面廃止。DNA事前制約→データ駆動lookback→3モードチャンピオン直接選出。
**12スロット設計**(4ファミリー×3モード)。GS結果(cmd_1018)では重複吸収後**10体**。
朱雀・玄武は激攻=常勝が同一変種→常勝消滅。
登録形態: **L1 standard PF**（旧四神のFoF構成とは異なる）。
シン忍法v2(21体)はこの10体を材料として構築。

確定パラメータ・DNA制約根拠・データ分析 → `context/dm-signal-research.md` §27

### 命名規則（殿裁定 2026-02-20）

L1四神FoF: {モード}-{四神名}（激攻-青龍等） | L2忍法FoF: {忍法名}-{モード}（加速-激攻等）
モード: 激攻(CAGR) / 鉄壁(MaxDD) / 常勝(NewHigh)。旧サフィックス廃止。同一config→忍法名のみ
※ 智将(Calmar)→鉄壁(MaxDD)変更理由: Spearman相関分析でCalmarはCAGRと高相関(rho=0.86)で冗長。MaxDDはCAGRと低相関(rho=0.49)で独自軸
シン四神v2確定: 4神×3モード=12スロット（吸収後10体）。旧四神(激攻のみ4体FoF)はディスコン
L2忍法FoF: 5忍法×3モード=最大15体。monban除外(ext_pricesのCSV化に追加設計必要)。nukimi_c→nukimiに統合(L054)
cmd_246完了: 12体チャンピオン本番DB登録済み。全0.00bp PASS。PF総数89(上限100)
新忍法候補: 逆風(cmd_249採用決定)/追い越し(cmd_250)/四つ目(cmd_284フルGS完了) → §4新忍法候補参照

⚠ L1/L2混同禁止: L1=神の中身(GSパラメータ) | L2=神の組み合わせ(BB)
- L262: recursive FoF expanderはroute層からrequest-scope cacheを注入しない限りquery storm化する（cmd_830）
- L269: FoF request-scope cacheのkeyはauth→portfolio_id+signal_dateに寄せ、maskingはroute後段に隔離せよ（cmd_834）

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
- L325: FoF valid_start_dateとdownstream warm-upは別物。valid_startはselection block lookback考慮、warm-upはcash初期化期間（cmd_1003）

## 4. ビルディングブロック

パス: `backend/app/services/pipeline/blocks/` | BlockType enum: `schemas/pipeline.py:18-37` | 登録: `shared.py:225-270`
標準パターン → `projects/dm-signal.yaml` (d) pipeline
全14種BBパラメータ詳細・選出方式 → `docs/research/core-param-catalog.md`

### BB種別分類（cmd_247）

| 区分 | BB名(BlockType) | 対応忍法 |
|------|----------------|---------|
| 採用 | MomentumFilter / SingleViewMomentumFilter / TrendReversalFilter / MomentumAccelerationFilter | 追い風 / 抜き身 / 変わり身 / 加速 |
| 採用 | AbsoluteMomentumFilter / EqualWeight | 門番 / 分身(全忍法terminal) |
| 補助 | SafeHavenSwitch / MonthlyReturnMomentumFilter | 門番補助 / 追い風GS方式 |
| 採用 | ReversalFilter → **逆風**(cmd_249採用決定) / MultiViewMomentumFilter → **四つ目**(cmd_284フルGS完了) | シン忍法v2で7忍法体制確定 |
| 採用 | PBarSelectionBlock → **p̄選別**(cmd_977-987) | p̄ベースFoF材料選別。月次戦術運用は無効(cmd_1009) |
| 偵察中 | RelativeMomentumFilter(cmd_250) | 新忍法候補 |
| 未採用 | ComponentPrice / CashTerminal / KalmanMeta | インフラ/スケルトン |

- L151: OPEN/CLOSE切替導入時はbenchmark側の*_open適用も同時チェック必須（cmd_507）
- L154: OPEN/CLOSE切替修正ではbenchmark側の*_open参照を全ビューで同時点検する（cmd_522）
- L318: p̄(richmanbtc式)は安定型(青龍)を構造的に優遇し、スイッチ型(朱雀/TMF-TMV)を排除する（cmd_981）
- L320: p̄検定は朱雀(DM3)のDNA「債券方向スイッチ」と構造的に不適合（cmd_981）

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
- L419: fof_component_weightsフラッシュ未配線(全FoF影響)。flush関数実装済みでもrecalculate_fof.pyのimport+呼出がなければ永久に空（cmd_1096）
- L421: flush関数の実装+exportだけでは不十分。呼出元のimport+呼出コードが存在するか二値チェック必須（cmd_1101）
- L423: FoF BBシミュレーションM-1オフセット必須（cmd_1102）
- L427: resample(ME).last()はカレンダー月末を返す。実取引日との差異がシグナル帰属ズレを引き起こす（cmd_1115）
- L428: valid_start_date計算は全構成シンボル(relative+absolute+safe_haven+DTB3)を含めよ（cmd_1115）
- L429: パリティ検証における非決定的順序とpartial-month初月の扱い（cmd_1116）

## 5. ローカル分析関数

`simulate_strategy_vectorized()`: `grid_search_metrics_v2.py`。MomentumCache必須(渡さないと黙って空リスト)。
月次リターン: 月末シグナル→翌月適用。Return=(月末価格/月初価格)-1。マルチアセット=単純平均。
詳細(全パラメータ・スケジュール) → `docs/research/core-local-analysis.md`
- L260: 上流の件数制限はprecomputed queryとfallback queryの両方へ必ず伝播させる（cmd_829）
- L264: precomputedテーブル存在時はraw再計算APIを残さずfast pathを導入せよ（cmd_830）
- L271: years付きmonthly fast pathは境界月だけdaily fallbackを残すと完全一致と高速化を両立できる（cmd_833）
- L317: MetricsCalculator右尾4指標は実装済みだがFE未露出（cmd_976）

## 8. APIエンドポイント概要

FastAPI 22ルーター/84-88EP | Next.js frontend | 共通: `ApiResponse{success,data,error,message}`。FE `api-client.ts` は TTL付きGET (`annual-returns`/`monthly-returns`/`rolling-returns`/`monthly-trade` 等) で auth-scope込み `cacheKey` を生成し、保存済みETagを `If-None-Match` 送信、`304 Not Modified` は成功扱いで保存済みpayloadへ復元する。参照: `/mnt/c/Python_app/DM-signal/frontend/lib/api-client.ts`
主要: `/api/signals` `/api/portfolios/get|save` `/admin/recalculate-sync` `/healthz`
詳細(全EP・レスポンス構造) → `docs/research/core-api-endpoints.md` | yaml → `projects/dm-signal.yaml` (h) api
- L153: signals APIのpending判定はrebalance_trigger共通化しないとFoF/非月次で表示不整合が起きる（cmd_515）
- L174: 最新+前月比較APIは『前月年月サブクエリ→同テーブル再JOIN』でN+1を回避できる（cmd_550）
- L176: 一覧トレンド判定は前月ラベルだけでなく前月p12をAPIで同時返却しないとB4を満たせない（cmd_552）
- L246: months引数の件数制限は末尾sliceだけでなく下流queryまで通せ（cmd_782）
- L252: PriceCacheパターン横展開がN+1最適化の最安全手法（cmd_806）
- L254: FoF展開共通関数のcache未注入でquery storm化する（cmd_806）
- L255: ticker precompute欠落時のfallbackはmonths windowをPrice queryへ必ず伝播させる（cmd_805）
- L257: Monthly Trade raw payload: Pydantic未宣言fieldもAPI contract（cmd_819）
- L310: apiCache.clear()はETag IDB未削除→304エラーの可能性。汎用clear()は未対応（cmd_962）
- L311: isRetryableError()はHTTP 5xx未対応→Render cold start 502/503で即エラー表示（cmd_962）
- L314: CORS expose_headersなしではFEがカスタムレスポンスヘッダを読めない（cmd_964）
- L315: Payload cache+validator cache分離構成ではinvalidatorが両層同時破棄必須（cmd_964）
- L412: BE定数変更時はFE定数(frontend/lib/constants.ts)も必ず確認・同期せよ（cmd_1079）

## 10. ディレクトリ構成

詳細ツリー → `docs/research/core-directory-structure.md`
主要: backend/app/(api|services/pipeline|jobs|db|schemas) | frontend/lib/ | scripts/analysis/grid_search/ | analysis_runs/experiments.db
- L168: 未使用判定はimport探索と呼び出し探索を分離すると誤検知が減る（cmd_548）

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
**FoF PF(13体)**: Ave-X, 裏Ave-X, MIX1-4, bam-2/-6, 劇薬DMオリジナル/スムーズ/bam/bam_guard/bam_solid
~~Ave四神~~: 2026-03-11時点で本番不在（削除済み）
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
| L124 | DB JSONカラムのstr型防御: `isinstance(value, str)+json.loads()`。`or {}`はtruthy文字列で発火しない | cmd_296 |
| L128 | `experiments.db`はスナップショットでありSSOTではない | cmd_222 |

### 19.2 実装パターン
- L258: try/exceptフォールバックでbulk preload+mock DB両立。bulk_loaded flagで本番最適化/テストmock分岐（cmd_820）
- L259: try/exceptフォールバックパターンでmock DB互換性とN+1最適化を両立（cmd_820）

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
| L126 | ブロック名は`BlockType` enum値で統一する | cmd_222 |
| L438 | MomentumAccelerationFilterのnumerator/denominator_periodはLookbackPeriodスキーマ準拠必須 | cmd_1190 |
| L445 | DTB3を株式用momentum関数で処理してはならない | cmd_1194 |
| L447 | nukimiのみ`_run_mp`関数不在で構造差異 | cmd_1196 |

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
| L129 | FoFパリティ比較は本番の現行パラメータを先に確認する | cmd_222 |
| L131 | 新FoF追加後の再計算は`sync-fof`(L3)を使う。sync-standardでは不足 | cmd_222 |
| L132 | GS構成四神と本番FoF構成PFの不一致に注意。登録前に突合必須 | cmd_222 |
| L135 | FoF作成は12ステップ省略不可。ステップ2-4省略でGS前提崩壊(抜き身3の失敗) | cmd_284 |
| L283 | FoFパイプラインのsnapshot参照はleakage-free設計必須。当月snapshot参照=データリーク | cmd_860 |
| L431 | 既存PF更新時はUUID維持でFoF参照を保護 | cmd_1126 |
| L478 | 吸収(absorption)はGS概念。DB物理では独立PFとして全体が登録される | cmd_1259 |

### 19.5 GS運用・config

| ID | 結論(1行) | 出典 |
|---|---|---|
| L112 | `monthly_returns.signal`がJSON辞書形式(`'{"TECL":1.0}'`)のとき`json.loads`でキー抽出必須 | cmd_274 |
| L125 | `pipeline_config`テンプレートのパラメータ名はコードと1:1一致必須 | cmd_222 |
| L134 | GS結果を利用する際は`DATA_CATALOG.md`と`meta.yaml`を必ず参照する | cmd_222 |

### 19.6 追加統合（cmd_322）

| ID | 結論(1行) | 出典 |
|---|---|---|
| L083 | close_fallback=openは部分欠損closeを補完しない | cmd_215 |
| L078 | PortfolioRepository.load()は1PFバリデーションエラーで全PF読込失敗する単一障害点 | cmd_207 |
| L065 | 本番コードパス統一原則: 数学的等価でも本番と同一コードパスを使え | cmd_196 |
| L056 | wide形式CSV(76万列)の`pd.read_csv`はヘッダー先読み+`usecols`が必須 | cmd_184 |
| L054 | nukimi_c統合可能: PARAM_GRID差分のみで戦略ロジック同一 | cmd_165 |
| L045 | nukimi_c高速化: ロジック共通、差分はパラメータグリッドのみ(T1-T3 vs T1-T5) | cmd_161 |
| L037 | standard PFでpipeline_config未設定だとrecalculate_fastがCashフォールバック | cmd_128 |
| L032 | データ構造変更時は全使用箇所を確認せよ（tuple化後の属性アクセス破綻を防ぐ） | — |
| L030 | Pipelineにmomentum_cache未提供だとsignal_calcが大幅劣化（9s→439s） | — |
| L023 | DTB3経済指標のDB照会はPipelineEngine呼出回数分だけ累積する | — |
| L022 | PipelineEngine統合の偽陽性（0/0=OK）に注意 | — |
| L020 | signal vs holding_signalの差はリバランスタイミング差として扱え | — |
| L018 | RULE10: シグナル判定はClose、リターン記録はOpenを厳守 | — |
| L002 | ブロック名は`BlockType` enum値で統一する | — |
| L001 | `pipeline_config`テンプレートのパラメータ名はコードと1:1一致必須 | — |

### 19.7 trade-rule突合・SSOT（cmd_766-770）

| ID | 結論(1行) | 出典 |
|---|---|---|
| L241 | SSOT関数書き換え時、呼び出し元の不要引数計算を残さない | cmd_768 |
| L242 | trade-rule整合レビューでは同一文書内の二次SSOT表もgrepで潰す | cmd_770 |

## 20. Deterioration色丸(ColorDot)マッピング

コンポーネント: `DeteriorationDots` | 定義: `frontend/lib/constants/deterioration-colors.ts`

| 色 | Hex | Label対応 |
|----|-----|----------|
| 緑(good) | #22c55e | GOOD, EARLY_WARNING |
| 黄(caution) | #eab308 | WATCH, MIXED |
| オレンジ(warning) | #f97316 | DETERIORATING |
| 灰(neutral) | #9ca3af | INSUFFICIENT_DATA |

### 指標別→Label変換ロジック

| 指標 | 関数 | 閾値 |
|------|------|------|
| G1(μ_long slope) | `g1ValueToColorLabel` | < -0.0002 → DETERIORATING, < 0 → WATCH, ≥ 0 → GOOD |
| G2(p_erosion) | `g2ValueToColorLabel` | ≥ 0.8 → DETERIORATING, ≥ 0.7 → WATCH, < 0.7 → GOOD |
| P(det) | `pValueToColorLabel` | G2と同一ロジック |

null/NaN → INSUFFICIENT_DATA(灰)。Label→色変換は `labelToColorDot()` で統一。
