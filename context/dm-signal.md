# DM-signal コンテキスト（索引）
<!-- last_updated: 2026-08-28 DOC_LANE_REQUEST blt_044030 source_equivalent 内容変更なし境界のみ -->
<!-- source_commit:e805b0d9d5ff reason:DOC_LANE_REQUEST blt_044030 source_equivalent 内容変更なし境界のみ evidence:git -C /mnt/c/Python_app/DM-signal log --oneline -1 e805b0d9d5ff; reason=source_equivalent -->
<!-- source_commit:5e9ea355d0ad reason:DOC_LANE_REQUEST blt_042403 source_equivalent 内容変更なし境界のみ evidence:git -C /mnt/c/Python_app/DM-signal log --oneline -1 5e9ea355d0ad; reason=source_equivalent -->
<!-- last_synced_lesson: L1603 -->
<!-- source_commit:d7cab63f3aaacf8392a98bf455035317c5d5e2d7 reason:D0 route preflight formal review accepted after C-x preflight commit evidence:D0 report d3d2567c; latest DM-Signal source d7cab63f; runner17/17; writes0 -->

> 読者: エージェント。推測するな。タスクに応じて必要なファイルを読め。

タスクに `project: dm-signal` がある場合、このファイルと必要な分割ファイルを読め。
パス: `/mnt/c/Python_app/DM-signal/`

## 分割ファイル一覧

| ファイル | 内容 | 読むべき場面 |
|---------|------|------------|
| `context/dm-signal-core.md` | DB構造、四神定義、忍法BB、API、ディレクトリ構成、恒久ルール | 実装・DB操作・パイプライン変更 |
| `context/dm-signal-ops.md` | recalculate Phase、OPT-E、性能、GS手順、ドキュメントインデックス、ステータス | 運用・GS実行・デプロイ・保守 |
| `/mnt/c/Python_app/DM-signal/context/dm-signal-terminology.md` | DM-Signal用語辞書terminology index。曖昧語27系統のcanonical name一覧 | cmd起票・レビュー・実装でDM-Signal用語の意味が曖昧な時 |
| `/mnt/c/Python_app/DM-signal/docs/knowledge-base/terminology/disambiguation.md` | DM-Signal用語辞書disambiguation SSOT。scope pattern別の意味・canonical定義 | 用語の正本確認・辞書更新・曖昧語解消設計 |
| `context/gunshi-silent-fallback-analysis.md` | cmd_1483偵察結果: 残9HIGH優先順位(4グループ)。SF-001/003修正済 | silent fallback修正cmd起票時 |

## DB操作ランブック（必読）

本番DB操作（PF登録・削除・再計算・Lookback変換等）を行うタスクでは必ず参照せよ:
→ `docs/rule/db-operations-runbook.md` （§1接続〜§9教訓索引、全9章）
| `context/dm-signal-research.md` | 月次リターン傾き分析、LA検証、過剰最適化検証 | 研究・分析・検証タスク |
| `context/dm-signal-frontend.md` | フロントエンド固有コンテキスト | フロントエンド変更 |

## セクション→ファイル対応表

| § | セクション名 | 分割先 |
|---|------------|--------|
| 0 | 研究レイヤー構造 | core |
| 1 | システム全体像 | core |
| 1.5 | 再計算の排他制御 | core |
| 2 | DB地図 | core |
| 3 | 四神構成 | core |
| 4 | ビルディングブロック | core |
| 5 | ローカル分析関数 | core |
| 6 | recalculate_fast.py Phase別処理フロー | ops |
| 7 | OPT-Eアーキテクチャ | ops |
| 8 | APIエンドポイント概要 | core |
| 9 | 性能ベースライン | ops |
| 10 | ディレクトリ構成 | core |
| 11 | Lookback標準グリッド | core |
| 12 | 計算データ管理の原則 | ops |
| 13 | StockData API | core |
| 14 | 既存ドキュメントインデックス | ops |
| 15 | 殿の個人PF保護リスト | core |
| 16 | 知識基盤改善 | ops |
| 17 | 現在の全体ステータス | ops |
| 18 | backend folder_id実態 | core |
| 19 | 月次リターン傾き分析 | research |
| 20 | ルックアヘッドバイアス検証 | research |
| 21 | 過剰最適化検証 | research |
| 22 | 弱体化確率推定 | (本ファイル) |
| 23 | Deterioration Monitor本番稼働 | (本ファイル) |
| 24 | G1/G2/P色丸ラベル | (本ファイル) |
| 25 | 殿確定事項（2026-03-11 trade-rule/business_rules突合） | (本ファイル) |
| 26 | 2026-03-12 性能・運用更新（cmd_804〜cmd_812） | (本ファイル) |
| 27 | シン四神v2設計（2026-03-19確定） | research |
| 28 | 2026-03-12〜03-20 主要更新（シン四神v2/GS高速化/パリティ） | (本ファイル) |
| 29 | 2026-03-28〜03-29 第2最適化サイクル（357.28s+crash-safety+GP-124） | (本ファイル) |
| 30 | 2026-04-20〜04-21 主要研究更新（GS memory最適化/L2 GS vs WF/vintage設計） | (本ファイル) |
| 31 | 2026-04-28〜04-30 運用鮮度更新（L1/L2登録+knowledge-base methods） | (本ファイル) |
| 32 | ビジネスプラン(Tier-プラン対応・推奨PF・記事) | (本ファイル) |
| 33 | L0-L3 GS再キャリブレーション計画（EODHD生値移行後） | (本ファイル) |

## §32 ビジネスプラン (殿裁定2026-05-10)

note.comメンバーシップの料金プランとDB viewer_tiersの対応。詳細 → `projects/dm-signal.yaml` tier_plan_mapping

### プラン階層(価値順)

- ベーシック(¥1,000/月 初月無料) → DB: Basic — 入門。3体シグナル可能
- スタンダード 古参スペシャル(¥4,000/月 募集停止) → DB: Standard — 四神12体+メンバーシップ2体
- 新スタンダード(¥8,000/月) ≒ 古参+アドオン → DB: NewStandard — 四神12+忍法3+2体。全17体シグナル可能
- スタンダード+アドオン(¥6,000/月 募集停止) → DB: Standard+AddOn — 四神12+忍法3+メンバーシップ3。18体シグナル可能。古参優遇
- ドクタープレミアム 完全招待制(¥20,000/月 初月無料) → DB: premium — 四神12+忍法6+メンバーシップ6。24体シグナル可能

劇薬DMシリーズ(¥30,000/月)はDB tier対応なし。

### 推奨PF(プラン別)

- ベーシック: basicデュアルモメンタム(入門)
- スタンダード(古参): シン白虎-鉄壁(四神中Sharpe最高・守備重視)
- 新スタンダード: GSシン分身-鉄壁(忍法アクセスが差別化・MaxDD-23%)
- ドクタープレミアム: 劇薬DMオリジナル(プレミアム限定の付加価値)

### 記事

- ベーシック向け: `marketing-director/content/articles/note-basic-dual-momentum.md`
- スタンダード向け: `marketing-director/content/articles/note-standard-bunshin-avex.md`
- プレミアム向け: `marketing-director/content/articles/note-premium-yotsume-gekiyaku.md`
- プラン別PF一覧: `marketing-director/content/articles/note-tier-portfolio-guide.md`

### 殿の指針

- 上位プランほど多角的に優れている必要がある
- 保有シグナル確認可能なPFから推奨を選ぶ(パフォーマンスのみは不可)
- Sortino Ratio推奨(Sharpeは上方ボラを罰するため好まない)
- α6指標: CAGR / NHF / MaxDD / MRU / Calmar / Avg UWP
- ALMはディスコン。殿が明示的に言わない限り話題禁止
- note記事の数値開示方針(PD-045): バレてよい詳細(α6指標名など既公開情報)はリアル数字を出し、核心(戦略パラメータ)は隠し、曖昧インパクト(数万パターン等)で印象形成する

## §33 L0-L3 GS再キャリブレーション計画 (2026-07-06)

### cmd_3826 バンド解除・復元完了 (2026-07-10)

cmd_3771 snapshotからstandard 24体をバンド適用前configへ復元し、試験登録1体もthreshold_bandのみ除去。PostgreSQL再照会でstandard `threshold_band`残存0件。fullrecalculate id=206/run `20260710_040539` はcompleted、2497.25s、103/103 PFのsignals・monthly_returns・portfolio_metrics生成を確認。L5 raw precomputeは1548 rows / 1659.78s / RSS 2075.2MB、L2は568.03s(9m28s、22.7%)。詳細→ `/mnt/c/Python_app/DM-signal/docs/research/cmd_3826_band_rollback.md`。

### cmd_3824 非決定性調査 (2026-07-10, tobisaru継続偵察で機構確定)

`秘奥義-変わり身-激攻` 2014-10-31で、再計算5回に対応するsignal変更5件が
`A→B→A→B→A→B` と反転した根因は`AbsoluteMomentumBlock`の`margin`(=`abs_mom-ref_mom`)が
`threshold_band=0.005`境界をまたぐ判定drift(`absolute_momentum.py:139-156`)と、
`band`状態を`safe_haven 0.5+選択資産0.5分割`へ変換する`SafeHavenSwitchBlock`
(`safe_haven_switch.py:40-52`)の組み合わせで完全一致確定。cmd_3817残75 mismatchの
`67/75`(89.3%)が同一機構(pipelineライブ再計算はpass/fail確定、ledger/signalは過去の
band期の値のままstale)で説明可能、うち65件はcmd_3816の`layer=NEW_IN_3812_PERSISTS_AFTER_3814`
(67件)とほぼ一致(97%)。残8件は別機構(旧式1/3均等ledger・safe haven銘柄差異)の疑い。
marginが実行間で動く一次トリガーはRender backend deployの連続着地(5回のrecalc実行の
全ての間隙+id=202自体がdeployによる中断)と相関するが、価格データ改定diffまでは未追跡。
standard PFの`signals.momentum_data`はintermediate_results(margin等)を永続化しない
構造的欠落を確認した。詳細→ `docs/research/cmd_3824_nondeterminism.md`

価格データソース多重化の本番適用により、GS入力はyfinance adjusted closeからEODHD生値+自前調整へ移行済み。既存本番PFのpipeline_configは旧入力価格で選出されたチャンピオンのため、L0→L1→L2→L3の依存順で全レイヤーを再GSし、新チャンピオン選出・本番config更新・パリティ検証が必要。

判断済み事項: 入力価格はEODHD生値+自前調整、パリティは全期間holding_signal(ticker×weight)+monthly_return完全一致、GSスクリプトは入力prices変更のみで原則変更不要、パラメータ空間は前回同一で縮小禁止、チャンピオン選別はin-sample最適化、WFは選別に使わない。

道具磨き順序: いきなり全計測せず、1PF×1パターンで計算パスを最速化し、5分以内を確認してからパターン数を段階拡大する。全パターンでも5分以内を達成してからGS本番実行。

E7速度確認(2026-07-06): L0四神GS full 191,796 patternsは `timeout 300` で246.09s完走し、5分目標は実測達成。ただし `--skip-parity` の速度確認であり、本番PF登録/fullrecalculate/PostgreSQL-Pipeline-Pydantic境界パリティは未実施。E7を本番適用完了として扱うな。

入力方式統一(cmd_3693): 秘奥義L3 `okugi_l3_168.yaml` は旧CSV84体から奥義21体DB componentsへ変更済み。四神GS `shin_shijin_l1_gs.py` は価格読込入口を `gs_data_loader` 経由へ統一し、少数検証用 `--pattern-limit` を追加。source_type棚卸しは db=4 / local_sqlite=2 / csv=14 / total=20。

pf_L3再GS完了(cmd_3779): 新pf_L2チャンピオン21体を構成PFとして7忍法全量GS(3,484,075 patterns)を完走し、21チャンピオンを選出。成果物は `/mnt/c/Python_app/DM-signal/outputs/analysis/cmd_3779_pf_l3_champions.json` と `docs/research/cmd_3779_pf_l3_champion_selection.md`。

GS価格経路偵察(cmd_3790, 2026-07-09): パリティ0/75の主因は登録configではなくGS入力価格系列差。`analysis_runs/experiments.db.daily_prices`は75,473行/14銘柄/最終2026-03-20、本番`prices`は99,871行/18銘柄/最終2026-07-08。同一2026-03-20でもTQQQ -0.394%、TECL -0.194%、LQD -1.145%、SPY -0.257%のclose差。再入替前にL0 daily price cacheとL1-L3 local_sqlite成果物を本番`prices`由来で再生成し、価格系列preflightをBLOCK化せよ。詳細: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3790_gs_price_path_recon.md`

Phase A再実行完了(cmd_3797, 2026-07-09): cmd_3762/3763(20260708)は本番未同期のEODHDローカルスナップショットで実行されており無効(殿裁定2026-07-09 13:40)。D1同期済みprices(`analysis_runs/experiments.db`, gs_price_preflight 14/14 PASS)でL0四神全量GS(191,796patterns、threshold_band=0.005込み、266s、exit 0)を再実行し、旧基準(CAGR/MaxDD/NHF)・新基準(CAGR/WorstYear/AvgUWP)で12体ずつ再選出、C1-C4比較を再実施。定性的傾向は前回踏襲(新基準は対象指標8スロット中6で改善、四神間相関は改善するが四神内相関は一部悪化、四神合成FoF後は青龍/朱雀/白虎でMaxDD悪化=個体最適化と合成後性能が逆転しうる)。副次発見: スクリプト内蔵legacyパリティ(`run_parity_check`, cmd_1018由来)はthreshold_band非対応で、band適用済み本番PF(工程1=cmd_3771で24PF適用済み)に対し必ずFAILする。GS計算経路自体の正確性は別の専用ツール`verify_gs_band_parity_pi009.py`(cmd_3794「D3」で本cmd同日に再検証、DM2含め該当PASS)で担保済みのため`--skip-parity`が正しい選択(cmd_3762前例と整合)。詳細 → `docs/research/cmd_3797_phase_a_l0.md`。L1-L3基準の採用裁定(設計書§2 Step 4)は引き続き殿裁定待ち。

Ledger band weights修正(cmd_3812, 2026-07-10): `signal_decision_ledger` historical_backfillが`signals.momentum_data.weights`を`decision_ticker_weights`へ保存し、`monthly_returns`生成がledger weightsを優先復元するよう修正。weightsなし旧ledger行は従来どおり等ウェイト展開で後方互換。詳細 → `/mnt/c/Python_app/DM-signal/docs/research/cmd_3812_ledger_band_weights.md`

matched_weight=0.5調査(cmd_3809, 2026-07-10): Render WARN `Matched weight 0.5000, missing_tickers=[]` の対象は `奥義-GS-変わり身-鉄壁`。本番DBの該当月 `momentum_data.weights` と `display_ticker_weights` はいずれも合計1.0で、band片側欠落は確認されず。問題はmonthly_trade APIがFoF表示用 `expanded_tickers` を後段で上書きした後、`matched_weight`/`missing_tickers`/return系を同じweight基準で再計算しない不整合の疑い。修正対象はband生成ではなくmonthly_trade整合性とWARNログ文脈追加。詳細 → `/mnt/c/Python_app/DM-signal/docs/research/cmd_3809_band_weights_half_bug.md`

monthly_trade表示ウェイト整合修正(cmd_3810, 2026-07-10): FoF API行で表示用`expanded_tickers`へ置換した後、同じ表示ウェイト基準で`matched_weight`/`missing_tickers`/`calculated_return_open/close`を再計算するよう修正。WARNログにはportfolio_id/year_month/weights_sum/weights_keysを追加。対象テスト36件+precomputed raw契約2件PASS。詳細 → `/mnt/c/Python_app/DM-signal/docs/research/cmd_3810_monthly_trade_weight_consistency.md`

L0本番突合完了(cmd_3800, 2026-07-09): 殿指摘(21:33「L0は本番とのパリティを確認したのか？」)への回答。cmd_3797の旧基準12体チャンピオンを本番`monthly_returns`(holding_signal/monthly_return_open)と全期間(171ヶ月, 2012-04〜2026-06)で突合した結果、**完全一致は12体中1体(シン玄武-鉄壁、171/171・最大差分4.9e-11)のみ**。threshold_bandは12/12で一致(0.005)だが、config(safe_haven_asset/top_n/rebalance_trigger/lookback)は12体中2体(シン玄武-激攻・鉄壁)のみ本番現行登録と完全一致し、残り10体は本番と異なるパラメータが選出されている。これはGS計算エンジンの誤りではなく、価格同期後の再探索で現行本番と異なるチャンピオンが選ばれた結果(config完全一致の2体は高精度で一致=エンジン自体は健全)。**L1以降へこの12体を使い続ける場合、本番反映時に11体の実際の挙動(保有銘柄・リターン)が現行から変わる**ことを意味し、意図された変化か将軍・殿の確認が必要。詳細 → `docs/research/cmd_3800_l0_prod_check.md`。

全12体同一パラメータエンジン正当性検証完了(cmd_3803, 2026-07-09): 殿指示(22:47)。cmd_3800はチャンピオン選出結果(新旧パラメータ相違)を確認したのみで、「GSエンジンが本番と同一パラメータで同一の答えを出すか」は未検証だった(cmd_3800 §4 limitation)。本cmdはGSチャンピオンではなくGS探索空間(paramsテーブル全76,680〜行)から本番現行12体と**パラメータ完全一致**(safe_haven/top_n/rebalance/lookback、unit=months→period*21換算規約で照合)のpattern_idを12体全てで一意に発見し、monthly_return_openを全期間171ヶ月で突合した。**結果は二極化**: 単一期間lookback PF(玄武3体・朱雀3体)は166〜171/171の高一致率(玄武-鉄壁は171/171完全一致、最大差分4.9e-11)。**複数期間加重lookback PF(青龍3体・白虎3体、lookback項2〜3個の加重平均)はパラメータ完全一致にもかかわらず不一致が大幅増加**(白虎165〜168/171、青龍137〜157/171=最悪は約20%の月で不一致、最大差分0.22)。band境界の僅差(単一期間PFで観測された1件程度の乖離)では説明できない規模であり、**GSエンジンの多期間加重lookback計算ロジックと本番PipelineEngineの間に未特定の相違がある可能性が高い**。原因箇所(重み正規化/起点日ズレ/合成順序等)は本cmd範囲では未特定。詳細 → `docs/research/cmd_3803_same_param_parity.md`。

シン玄武-鉄壁ライブ試験登録+fullrecalculate完全一致(cmd_3804, 2026-07-09): 殿厳命(23:12, blt_20260709_231431)。cmd_3800/cmd_3803は本番`monthly_returns`の既存(過去計算済み)行を読んで突合したのみで、「登録→実ライブfullrecalculate」という本番PipelineEngineの実行経路そのものは未検証だった。本cmdは唯一config完全一致+出力完全一致(171/171)が確認済みのシン玄武-鉄壁を、既存本番PFと全く同一のpipeline_config(MomentumFilter+AbsoluteMomentumFilter+SafeHavenSwitch、threshold_band=0.005)で複製し、`シン玄武-鉄壁_試験登録cmd3804`として本番へ新規登録(hide_portfolio/hide_signal=true)、事前に本番全102PFを`portfolio_archive`へバックアップ(cmd_3753機構、102/102一致)した上でportfolio_id指定なしfullrecalculateを実行(id=196、14:38:59〜15:15:29 UTC、約36.5分、status=completed/end_time確定をDB直接クエリで確認。L714/L715: acceptedは完了ではない)。**結果は完全一致**: (A)試験登録PF vs 既存本番シン玄武-鉄壁(同一config・同一エンジン・同一価格データ)= holding_signal 3586/3586日・monthly_return_open 173/173ヶ月ともに不一致0件・最大差分0.0。(B)試験登録PF vs cmd_3797 GS出力(pattern_id=DM7P_RXLU_T1_M_L0003)= monthly_return 171/171ヶ月不一致0件・最大差分4.929e-11(浮動小数点誤差レベル、cmd_3800/cmd_3803と同一水準)。**本番PipelineEngineは既知config入力に対しGSと同一の答えをライブ再計算経路でも再現することが直接証明された**(cmd_3800/cmd_3803の履歴データ突合を超える検証)。gs-parity-100-staged-plan.md Stage 1完了。詳細 → `docs/research/cmd_3804_trial_registration_parity.md`。

複数期間加重lookback乖離の根因特定完了(cmd_3805, 2026-07-09): cmd_3803で判明した青龍/白虎(複数期間加重lookback)の乖離について、GS側(`shin_shijin_l1_gs.py`/`grid_search_metrics_v2.py`)と本番側(`vectorized_momentum.py`/`absolute_momentum.py`/`safe_haven_switch.py`)のコードを比較。**GS側の計算ロジックにバグは無い**。本番`PipelineEngine`を同一日付・同一価格データで直接呼び出して検証した結果、GSの計算値(margin=0.003234833442463803、gate_state=band、TECL50%+XLU50%)と完全一致した(シン青龍-鉄壁2012-04時点)。**cmd_3803が観測した乖離の真因はGSエンジンではなく、本番`monthly_returns`が参照する`signal_decision_ledger`の凍結タイミング**: `cmd_3711`のhistorical_backfill(2026-07-06 14:57、threshold_band未適用時点)が全期間のholding_signalを2値判定(pass/fail)で確定・凍結し、3日後の`cmd_3771`のband適用(2026-07-09 16:51、threshold_band=0.005追加)を遡及的に反映していない。これはPI-P06/cmd_3703 design §4 targetの意図的仕様(確定済み月はledger優先、新計算との食い違いはsilent上書きせずdriftとしてCRITICAL記録)であり、バグではない。**影響**: `docs/research/gs-parity-100-staged-plan.md`(殿指示2026-07-09 23:38「100%一致のみ合格」)の前提「本番が正・GS側のみ修正」は再検討が必要。単一期間PF(玄武/朱雀)の高精度一致は、marginがband境界から離れておりledger凍結の影響を受けにくかった統計的偶然の可能性が高い。詳細 → `docs/research/cmd_3805_multi_lookback_divergence.md`。

band適用済みconfigでのledger再backfill完了(cmd_3806, 2026-07-10): 殿裁定(00:10 案A採用)。cmd_3805で特定した凍結を解消するため、対象24PF(cmd_3771でband適用済み)の`signal_decision_ledger`を全量削除(3495件)→`/admin/recalculate-sync`で部分再計算(recalculation_status id=197、40分50秒、完了はDB直接クエリで確認)→`execute_historical_backfill()`をcmd_3711と同一手段で再実行し band反映後の`signals`からledgerを再構築(3667件挿入、うち1件は無関係の既存ギャップPFの副次補完)。事前に本番全103PFを`portfolio_archive`へバックアップ(run_id=cmd_3806_pre_rebackfill_backup_20260710)。**削除→部分再計算→再backfillの順序が必須**(先にbackfillするとband反映前のsignals値を再凍結してしまう)。cmd_3803方式で12体を再突合した結果、**12体中8体が浮動小数点誤差レベル(171/171、diff≈5e-11)まで改善**(cmd_3803時点は1体のみ)。残り4体(朱雀-常勝/玄武-常勝/白虎-常勝/白虎-鉄壁)の乖離件数・乖離月はcmd_3803時点と完全に同一で不変であり、band/ledger凍結問題とは別の未特定要因と判明(「常勝」モードが3/4を占める)。**部分再計算の所要時間に関する教訓**: `include_parent_fof=true`は対象PFへの依存に応じ波及範囲が事実上全PF規模(24→実質49〜103PF)に拡大しうる。`precompute_raw`フェーズはrecalculation_statusのタイミング計測に含まれず(計測後に実行される)、DB上は進捗不可視のまま「running」が続く。停滞に見える場合はRender本番ログで実測進捗を直接確認せよ(recalculation_status/API状態だけでは判断できない)。詳細 → `docs/research/cmd_3806_ledger_rebackfill.md`。

monthly_trade matched_weight偽陽性分類(cmd_3808, 2026-07-10): cmd_3787のfail-closedガードは欠落ticker防御として有効だが、`missing_tickers=[] && matched_weight<1.0` は「全ticker価格照合成功だがweights辞書自体が1未満」でも発火する。Renderログで`Matched weight 0.5000 != 1.0, missing_tickers=[]`を392件確認。分類はデータ破損ではなく部分weight/非Cash表示weightの偽陽性。修正案は`matched_weight`を固定1.0ではなく`sum(weights)`と1e-9許容で比較し、`missing_tickers`非空だけをfail-closed対象にする。詳細 → `docs/research/cmd_3808_matched_weight_classification.md`。

根拠: `/mnt/c/Python_app/DM-signal/docs/design/gs-recalibration-plan.md`（commit `4828c134`, `78ed9bec`, `97e06904`）。

## 弱体化確率推定(P_det)

P(deterioration)=Φ(-Z)方式（3窓: 6/12/24ヶ月、6ラベル、HAC/winsorize）を採用。cmd_539でエンジン実装+7PFパイロット検証を完了し、cmd_540でローリングlong基準(K=120ヶ月)の検知力天井問題を分析してドリフトガード合議を完了。
詳細設計・裁定ログ: `MCP:deterioration_probability_design`（cmd_539, cmd_540）
P(det)と構造変化検定は別概念: P(det)=rolling recent vs longの方向付き悪化確率（生成過程変化を探索しない）、構造変化検定=break date探索。補完関係が自然。レジーム検出追加時はbreak検出と悪化方向判定を分離せよ → `lessons.yaml` L285参照

## §23 Deterioration Monitor 本番稼働

Render BE + cronで本番運用中。P(det)=Φ(-Z)方式、3窓(6/12/24ヶ月)、6段階ラベル(Stable/Watch/Caution/Warning/Danger/Critical)。フォルダフィルタ+ページナビ対応済。
設計詳細: `MCP:deterioration_probability_design` | エンジン実装: cmd_539 | ドリフトガード: cmd_540

## §24 G1/G2/P色丸ラベル(cmd_613)

Dashboard/Compare Summary/Deterioration Monitor/FAQの4ページで数値→色丸(緑/黄/オレンジ + 灰=INSUFFICIENT_DATA)に変換。直感的視認性を確保。

## §25 殿確定事項（2026-03-11 trade-rule/business_rules突合）

| # | 確定内容 | 影響先 |
|---|---------|--------|
| 1 | FoF参照日: 矛盾なし。「直近リバランス時のsignal_dateで確定したsignal」が正。「前月末」表現はリバランスタイミングにより不正確 → 避ける | RULE08, cmd_767 AC1 |
| 2 | wᵢ = 月初目標ウェイト。非リバランス月でも月初にリセット（暗黙的月次リバランス）。どの月からでもユーザーが公平に参加できる意図的設計 | RULE05/06, cmd_767 AC3 |
| 3 | Trade期間リターン: buy-and-holdではなく月次複利合成 R_trade=Π(1+R_月)-1。FoF×非月次シグナルで乖離。四神・忍法の再選定が必要 | cmd_768(critical) |
| 4 | SSOT 3層: Price table(L0データ) → calculate_monthly_return()(L1) → MonthlyReturn table(L2キャッシュ) | cmd_767 AC5 |
| 5 | business_rules.md §3.4 Loading Policy（Optimistic UI禁止）は古い。SWR許可 | cmd_765続行 |
| 6 | Safe Haven: コードとbusiness_rules.md §1.1完全一致。Cash=DTB3、safe_haven_asset設定でGLD/XLU等 | cmd_767 AC7 |

→ `projects/dm-signal.yaml` RULE05/06/08/SSOT階層を更新済み
→ `docs/rule/business_rules.md` は古い箇所あり。§3.4 Loading Policyは陳腐化

## §26 2026-03-12 性能・運用更新（cmd_804〜cmd_812）

| cmd | 結論 | 参照 |
|---|---|---|
| cmd_804 | CDP本番計測は16ページ全閾値PASS。最大改善は Monthly Returns warm `147→129ms (-12.2%)` | `queue/archive/reports/tobisaru_report_cmd_804_20260312.yaml` |
| cmd_805 | `/api/monthly-returns` の主因は `ticker_monthly_returns=0` による fallback 全Price scan。window query化で `months=12` は約 `-88%` 改善見込 | `queue/reports/hayate_report_cmd_805.yaml` / `context/dm-signal-core.md` §8 (`L255`) |
| cmd_806 | N+1を12箇所検出。最重要は `monthly_trade_calculator._build_entries()` で約 `170→3 queries`、約8秒短縮見込 | `queue/reports/hanzo_report_cmd_806.yaml` / `context/dm-signal-core.md` §8 (`L252`,`L254`) |
| cmd_808 | Monthly Returns Before計測は `2026-03-12 04:37 JST` 時点で進行中。比較用ベースライン取得フェーズ | `dashboard.md` 戦果/進行中セクション |
| cmd_810 | CDP preflight fail-fast を実装。ブラウザ未起動を約 `4.63s` で検知し、接続timeoutとコマンドtimeoutを分離 | `reports/cmd_810_fix_kagemaru.yaml` / `dashboard.md` |
| cmd_811 | CDPブラウザ未起動時の `auto_launch_browser` 実装完了。`preflight fail → 自動起動 → 再preflight → 計測続行` の到達経路を確認済み | `reports/cmd_811_impl_kagemaru.yaml` / `queue/archive/reports/kirimaru_report_cmd_811_review_2_20260312.yaml` |
| cmd_812 | 報告YAML欠損の真因は `report file` 未検証の auto-done hook。done通知は `ninja_done.sh` の検証付き経路へ統一が再発防止策 | `queue/archive/reports/hayate_report_cmd_812_20260312.yaml` / `context/infrastructure.md` (`L209`,`L210`) |

## §28 2026-03-12〜03-20 主要更新

| 領域 | 結論 | 参照 |
|---|---|---|
| シン四神v2確定 | 旧v1(191,796広探索→CPCV→32体)を全廃。DNA事前制約→データ駆動lookback→3モードチャンピオン直接選出。**12スロット設計**(4ファミリー×3モード)。GS結果(cmd_1018)では重複吸収後**10体**(朱雀・玄武の激攻=常勝同一→常勝消滅) | `context/dm-signal-research.md` §27 |
| シン忍法v2確定 | 10体×7忍法=173,625パターンGS。全**21体**ユニーク(吸収0)。最強: 加速D-激攻 CAGR 86.6% | `context/dm-signal-research.md` §27 シン忍法v2 |
| 本番登録計画 | 事故歴あり(cmd_1082: パリティ未検証で登録→汚染33体DELETE)→段階的チェックリストで進行中 | `context/checklist-shin-v2-registration.md` |
| CPCV廃止 | FoF材料に完成品基準を当てていた。殿裁定: 素材は一瞬のきらめきで十分(cmd_1078) | `context/dm-signal-research.md` §27 L415 |
| GS高速化 | 23h→42min(PPE+picks vectorize)→並列12min。numpy momentum cube追加最適化 | `context/gs-speedup-knowledge.md` |
| p̄検証 | PBarSelectionBlock実装+BT。月次戦術運用は無効(Sharpe 0/192全敗, cmd_1009)。p̄はFoFレイヤーの「計算と解釈の分離」原則に準拠 | `context/dm-signal-research.md` §27 L337 |
| パリティ修正 | FoF component_weights flush未配線修正(cmd_1096)、resample月末修正(cmd_1115)、valid_start_date全構成シンボル包含(cmd_1115) | `context/dm-signal-core.md` §4 L419/L427/L428 |
| 本番不変量(PI) | standard PFにpipeline_config必須(Cash fallback防止, PI-001)。PI-001〜PI-008運用開始 | `projects/dm-signal.yaml` production_invariants |
| PF健全性スイープ | 全122PF×5項目パス(cmd_1091)。定期実行候補 | `context/dm-signal-ops.md` §17 |
| 304キャッシュ修正 | 本番304 Not Modifiedキャッシュ不整合バグ緊急修正(cmd_1011) | — |
| FE Biome導入 | ESLint→Biome移行+PostToolUse Hook(cmd_971) | `context/dm-signal-frontend.md` |
| 金融ML知識辞書 | Vercelスタイル骨格構築+López de Prado全知見体系化(cmd_863-872) | `docs/knowledge-base/` |
| OOS検証配置 | ルールベース戦略のOOS検証はpipeline block(allocation)ではなくGS runner上位の評価層に配置。parity/registry無破壊で拡張可能。oos_r2をchampion選定補助指標化 | `lessons.yaml` L286参照 |
| GS出力先自動振り分け | run_077スクリプトはuniverse名からサブディレクトリを自動生成(例: shin_ninpo_v2_12body/)。cmd AC設計時にスクリプトの実際の出力先仕様を事前確認すべき | `lessons.yaml` L433参照 |
| WardTwoStageEWBlock実装 | TerminalBlockとしてbuilding_block.pyのWard+二段EWロジックを忠実移植+BlockType enum/registry登録完了(cmd_1437)。cold start時1/N EWフォールバック | `queue/archive/reports/hayate_report_cmd_1437_20260330.yaml` |

## §29 2026-03-28〜03-29 第2最適化サイクル（cmd_1463〜cmd_1478）

| 領域 | 結論 | 参照 |
|---|---|---|
| fullrecalculate性能 | **357.28s**(baseline 637.80s→-44%、初回11,818s→97.0%削減)。OPT-12~15全反映。L2:109.47s(-54.5%)、L3:214.01s(-40.9%) | `context/dm-signal-ops.md` §9 / `context/gunshi-fullrecalc-speed-analysis.md` |
| crash-safety | shutdown警告(cmd_1463)+DB永続化(recalculation_status)+pg_advisory_lock排他制御(cmd_1465)。2層排他(threading.Lock+pg_try_advisory_lock) | `context/dm-signal-ops.md` §6-7 |
| GP-124 signal整合性 | fullrecalculate後zero-signal自動検知。OPT-13(修正)+GP-124(検知)=二重防御(cmd_1477) | `context/dm-signal-ops.md` §6-7 |
| OPT-12~15(軍師直接) | gc.collect削減+dead code除去+ネステッドFoF回帰修正+signals flush INSERT化+component_weights commit集約 | `context/gunshi-fullrecalc-speed-analysis.md` |
| PI-016/017追加 | N+1 pre-load原則(PI-016)+StockData API 1000件制限(PI-017) | `projects/dm-signal.yaml` production_invariants |

## §30 2026-04-20〜04-21 主要研究更新

| 領域 | 結論 | 参照 |
|---|---|---|
| GSメモリ+速度最適化 | 7忍法横展開を完了。`workers=2` が安全圏へ復帰し、最大RSSは `kasoku_diff 8.5GB→5.5GB`、`nukimi 978→518MB`、`kawarimi 403→278MB`。`bunshin` は直列構造ゆえ SHM/PPE 非適用が正解 | `docs/research/gunshi_gs_memory_speed_optimization_20260420.md` |
| L2奥義 GS固定 vs WF動的比較 | L0選出方式だけを変えた 42体×42体比較で、WF系が champion 比較 `40勝-2敗 (95.2%)`、β調整 `α6指標×4試練` でも `48勝-0敗`。L2でも WF動的土台が優位 | `docs/research/l2_gs_vs_wf_comparison_20260421.md` |
| Vintage robustness設計 | 「現championが強いか」ではなく「L0→L1→L2の再選出機構が頑健か」を測る設計へ確定。2020/2022/2026 の3 vintageで IS-only 再選出→OOS測定、fold future contamination 禁止、`1 vintage = 1 cmd` | `docs/research/vintage_analysis_design_20260421.md` |

## §31 2026-04-28〜04-30 運用鮮度更新

| 領域 | 結論 | 参照 |
|------|------|------|
| L1 GSシン忍法 | cmd_2392でGSシン忍法21体を本番hide登録。fullrecalculate成功、既存20体diff=0、GSパリティ21/21 PASS | `context/dm-signal-ops.md` §32 |
| L2奥義 | cmd_2422で制約付きL2 champion 21体を選出し、cmd_2424で本番hide登録+fullrecalculate完了。完了判定はAPI statusだけでなくDB `recalculation_status`で二重確認 | `context/dm-signal-ops.md` §34 / `context/dm-signal-core.md` GSL2正規パス |
| knowledge-base methods | `docs/research/knowledge-base/methods/` にM79-M84を追加: DeepUnifiedMom, VAA/BAA, Hierarchical Momentum, Factor Momentum, ADTS/CADTS, Expert Aggregation WASA | `/mnt/c/Python_app/DM-signal/docs/research/knowledge-base/index.md` |

## §33 2026-05-01〜05-27 ソースcommit鮮度更新 (cmd_3090)

検証: `git -C /mnt/c/Python_app/DM-signal log --oneline --since=2026-04-30` で43commit確認。主要変更のみ索引化。

| 領域 | 結論 | 参照 |
|------|------|------|
| FoF表示/監査 | Monthly TradeのFoF表示はprecomputed weights / year_month月初Signal優先へ修正。signal change audit logging追加。FoF valid_start_date/lookback型も修正済み | `context/dm-signal-core.md` §21 / commits 85f42b3c〜c7e91634 |
| FoF cache/PF削除 | 2026-06-01のFoF signal_cache統合、PF config snapshot、legacy PF物理削除手順は運用層に反映済み | `context/dm-signal-ops.md` §40 / commits 89761e7d, 77372987, f84b7ad8 |
| 認証/CI | auth token count eviction削除。pytest GitHub Actions追加、PyYAML/依存導入、PostgreSQL service付きCIへ拡張 | `context/dm-signal-core.md` §22 / commits 2e9e1b7d〜86661769 |
| FE/指標 | Compare SummaryにAvg UWP/PTU/MaxDD UWP/TQQQ benchmark/right-tail metricsを追加。Drawdowns全件化はrevert済み。Monthly Trade masked表示修正 | `context/dm-signal-frontend.md` §2.6 |
| 用語/知識 | DM-Signal用語disambiguation拡張、UWP/PTU区別追加、method全件へinvestment knowledge links接続 | `context/dm-signal-research.md` §37 |
| 運用 | Homeに休日認識追加、価格backfill開始年を2000へ統一。fullrecalculateは別cmd必要 | `context/dm-signal-ops.md` §37-§38 |

## §34 2026-07-04〜07-05 source freshness照合

GA-179原因: `dm-signal.md`のlast_updatedは2026-07-04で、source監視対象に2026-07-04以後のDM-Signal commitが3件残っていた。恒久索引に反映すべき差分はcmd_3686の確定シグナル変更ntfy集約で、flush通知は個別POSTではなくバッチサマリー1通が正。詳細は `context/dm-signal-core.md` §21 FoF表示・監査系 / commit `0b034e3d`。
`tasks/lessons.md`のみの2件(`894736d4`, `a3059891`)は教訓登録・stale lesson整理であり、総合索引本文への追記対象外。分割contextではcore/frontend/researchにもsource ALERTが残るため、横展開は各分割contextの鮮度cmdで扱う。

## §35 2026-07-07 GA-189 ALERTは偽陽性(config/projects.yaml project_id衝突バグ)

GA-189で`dm-signal.md`が「source commits 3件」ALERTしたが、**内容更新は不要**(偽陽性)。根因: `config/projects.yaml`で`dm-fusion`(L17-22)と`dm-signal`(L2-16)が同一の`context_file: "context/dm-signal.md"`を宣言しており、`scripts/context_freshness_check.sh`の`EXPLICIT_CONTEXT_MAP`(1キー1値のdict)がYAML走査順で後勝ち上書きされ、`infer_project_id("context/dm-signal.md")`が`dm-fusion`を返す。`source_repo_for_context()`は`base.startswith(f"{project_id}.")`で"dm-signal.md".startswith("dm-fusion.")=Falseとなり本来のDM-Signalリポジトリ参照に失敗、root fallback(multi-agent-shogun自リポジトリのgit log)に落ちて無関係な3コミット(`6108be73d`/`8b91a001`/`39448c96`、いずれもinfra側の変更)を誤帰属していた。
一次確認: `dm-signal.md`が本来監視すべきDM-Signalリポジトリ側パス(`context/dm-signal-terminology.md`, `docs/knowledge-base/terminology/disambiguation.md`, `docs/rule/db-operations-runbook.md`)への実commitは`git -C /mnt/c/Python_app/DM-signal log --since="2026-07-07 00:00:00" -- <上記3パス>`で0件。内容更新不要と判断し、last_updatedのみ更新。
根本修正(`EXPLICIT_CONTEXT_MAP`の1:1制約解消 or dm-fusion専用context_file分離)はcontext_freshness_check.shの実装変更を伴うため本cmd範囲外。defense_candidateとして家老へ報告。

## 補助ポインタ

- プロジェクト核心知識: `projects/dm-signal.yaml`
- プロジェクト教訓: `projects/dm-signal/lessons.yaml`
- フロントエンド: `context/dm-signal-frontend.md`
- GS高速化知見: `context/gs-speedup-knowledge.md`
- L3堅牢性: `context/l3-robustness.md`

## 教訓索引（自動追記）

- （現在0件。L149-L272は振り分け済。L273-L301は振り分け済 → auto-ops§CDP計測(L274-276), ops教訓索引(L273), frontend§5/§6/§9(L277/280/284/287/292/300), core§2/§19.4(L296/283), research弱体化確率(L278/279/285)/GS(L286/299)/新§27持続性(L281/282/288/289/291/293-295/297-298/301)。L290はL285重複→統合）
- （L302-L309は振り分け済 → research§持続性(L302-305), research§SPA(L306), ops§16(L307/308), frontend§9(L309)）
- （L310-L321は振り分け済 → core§8(L310/311/314/315), core§5(L317), core§4(L318/320), ops§6-7(L319), ops§9(L321), infra WSL2(L316)。L312/L313はL311/L310重複→削除）
- （L322-L333は振り分け済 → research§持続性(L322-L324/L327-L328), core§3(L325), frontend§4(L326)/§8(L333), ops§6-7(L330/L332)/Ops索引(L329)。L331はL330重複→削除）
- （L334-L350は振り分け済 → research§持続性(L334-L337), research§GS(L338/L341-L343/L348), ops索引(L339/L344-L347/L349-L350), frontend§12(L340)）
- （L351-L378は振り分け済 → research§27シン四神(L351/352/354/355/356), research§GS結果(L358/359), research§パリティ(L361/378), gs-speedup§3(L366/369/372/373/374), gs-speedup§4(L364/365/367), gs-speedup§5(L360/363), gs-speedup§6(L368/370), ops教訓索引(L357[PI-002]), infra§レビュー(L375), infra§git(L377), infra§報告(L362), infra§知識管理(L353)。L371はL367重複→統合、L376はL374重複→統合）
- （L379-L388は振り分け済 → gs-speedup§3(4)(L380), gs-speedup§3(5)(L382), gs-speedup§3(6)(L383), gs-speedup§3(7)(L385), gs-speedup§4(L379/L384), gs-speedup§6(L381)。L386はL384重複→統合、L387はL382重複→統合、L388はL383重複→統合）
- （L389-L402は振り分け済 → research§パリティ(L389/L391/L392), gs-speedup§3(4)(L395), gs-speedup§3(5)(L398), gs-speedup§3(6)(L396), gs-speedup§3(7)(L390/L393/L394/L399), gs-speedup§4(L397/L401), gs-speedup§5(L402), infra§LLM(L400)）
- （L403-L407は振り分け済 → gs-speedup§3(4)(L403/L404/L407), gs-speedup§6(L405/L406)）
- （L408は振り分け済 → gs-speedup§3(1)）
- （L409-L410は振り分け済 → research§GS結果(L409), gs-speedup§4(L410)）
- （L411-L422は振り分け済 → gs-speedup§4(L411), core§8(L412), research§27(L413/L414/L415), gs-speedup§3(L416), ops§17(L417), infra§知識サイクル(L418), core§4(L419/L421), core§2[PI-008](L420), research教訓索引(L422)）
- （L423-L429は振り分け済 → research§パリティ検証。L426はL424重複→削除）
- （L430-L457は振り分け済 → research§パリティ(L430/L439/L440/L441/L442/L444/L448/L449/L452/L454), research§GS結果(L432/L433/L434/L435), core§19.2(L438/L445/L447), core§19.4(L431), gs-speedup§3(L451)/§4(L450), infra§知識管理(L436)/§報告(L437)。重複削除: L426=L424, L443=L440, L446=L441, L453=L451, L455=L454, L456=L450, L457=L452）
- （L458-L460は振り分け済 → gs-speedup§3(8)(L458), research§パリティ(L459)。L460はL458重複→削除）
- （L461/L473は振り分け済 → research§パリティ検証(L461/L473[PI-010])）
- （L474/L475は振り分け済 → ops§6-7 recalculate_fast.py(L474:事前計算データソース統一, L475:DTB3リサンプルPI-010同根)）
- （L476-L478は振り分け済 → research§パリティ検証(L476[PI候補]), ops§6-7(L477), core§19.4(L478)）
- （L479-L484は振り分け済 → research§パリティ(L479/L480/L482), core§19.4(L481), ops教訓索引(L483)。L484はL483重複→削除）
- （L485-L488は振り分け済 → research§パリティ検証(L485/L486/L487/L488)）
- （L493-L504は振り分け済 → research§24(L493), research§27(L494/L495/L498), core§13[PI-017](L496), core§5(L497), research§26(L499), core§1(L500/L501), ops§6-7(L502), ops§9(L503), ops索引(L504)）
- （L505-L515は振り分け済 → core§19.1(L511/L512:DB), core§19.2(L506/L507/L508:実装パターン/PI-018), core§19.2BB(L513:OPT-Aウェイト消失), ops索引(L505:deploy/L509:ツール/L510:ツール/L515:APIフィールド名), research§27(L514:Wardクラスタ固定化)）
- （L516-L529は振り分け済 → research§27 R28 ClSel教訓(L516-L523/L525-L527/L529), ops教訓索引ツール(L528)。L524はL525重複→統合）
- （L530-L534は振り分け済 → research§27(L530:OPTICS退化), core§19.2(L531:cache_value), research§29(L532:前処理注入ポイント), research§30(L533:PE gate閾値/L534:L1キャッシュ最適化)）
- （L535-L545は振り分け済 → research§30(L535/L537/L538/L539/L540/L541/L542), research§27(L544), gs-speedup§3(L543), ops索引(L536/L545)）
- （L546-L561は振り分け済 → research§35(L546/L549/L554/L559/L560/L561), research§34(L556/L557), research§28-30統合(L548/L550), ops索引(L552/L553/L558), core§19.2(L555)。L547はCLAUDE.md既記載→重複。L551はL549重複→削除）
- （L562-L563は振り分け済 → research§35(L562:ALM Ward K制約), research§31(L563:DNA制約IS効果)）
- （L564-L573は振り分け済 → research§35(L564:MINIMIZE_METRICSランタイムpatch/L566:ALM吸収メトリクス差異), research§32(L565:旧加速ratio/diff未分化), research§33(L567:多様性分析/L568:10目的相関冗長), research§34(L569:LTJ_inv早期fold NaN), gs-speedup§4(L570:npy sidecar), ops索引(L571:baseline_v2記述不一致), research GS結果(L572:runner正規パス), core§19.2(L573:bisect helper統一)）
- （L574-L589は振り分け済 → core§19.2(L574-L578:FoF月次bisect統一[PI:L573同根]), ops索引(L579/L582/L584:自動生成/L585:output_path記述/L589:tracemallocツール), research§35(L580:38メトリクス後計算/L587:METRIC_NAMES同期), research§GS結果(L581:unit_naming制約), research§パリティ(L586:golden当月DB更新), gs-speedup§4(L583:WSL2 p9 stall/L588:WFエンジンOOM 24.7倍膨張)）
- （L589-L605は振り分け済 → gs-speedup§4(L589:SHM二乗時間化/L592:import性能/L596:savetxt 59x/L597:fork RSS計測/L598:BytesIOパターン), ops§WF(L590:tracemalloc≠RSS/L591:parallel実測/L600:fromstring空セル), ops§GS(L593:C(n,k)スケーリング/L594:HASHSEED sorted()), core§忍法BB(L599:TrendReversalFilter early return), research§奥義(L601:MaxDD最悪値選出/L602:oikaze ID誤記/L604:IS前半≠全期間0/21/L605:CAGR系過適合リスク高)。L595/L603重複削除）
- （L606-L617は振り分け済 → ops§18 WF(L606:回帰テスト決定論), ops索引(L607:当月パリティ/L610:削除スコープ/L614:車輪再発明/L616:成果物所在/L617:gate_artifact_map), research§35(L613:超越条件C非現実+SPA/L615:Cell Bパラメータ縮退)。L608≡L607, L609≡L606, L611≡L610, L612≡L613重複→削除）
- （L618-L630は振り分け済 → infra教訓索引LLM(L618), research教訓索引奥義(L620), ops教訓索引ツール(L621/L624), infra git(L622), gs-speedup§4(L623/L625), gs-speedup§3(4)(L626), core§19.2(L627/L630:L573同根統合), ops教訓索引パリティ(L628/L629)。L619はL620重複→削除）
- （L631は振り分け済 → core§19.2 BB仕様・バグ修正(L631:TRF insufficient_candidatesでcurrent_tickersクリア禁止)）
- （L632は振り分け済 → ops教訓索引ツール。L633はAUTO-DEPRECATE(referenced=0)→振り分けスキップ）
- （L634-L637は振り分け済 → core§19.2(L635:deferred flush UPSERT), ops教訓索引(L634:DB/L636:運用/L637:運用)）
- （L638-L650は振り分け済 → ops§6-7(L638[PI-025]/L647/L648), research§35(L641/L643), ops索引(L644/L645/L649), infra索引(L646/L640:codd), frontend§12(L650)）
- （L639/L640は振り分け済 → core§19.2(L639:EqualWeight GSへpipeline import guard混入禁止), core§19.1(L640:DB経由CoDD比較は同一プロセス・同一データ)）
- （L642は振り分け済 → core§19.5(GS成果物globはcmd_id直後にninjutsu名が来る命名も対象)）
- （L651-L666は振り分け済 → frontend§12(L651/L653/L654/L655/L656), core§0(L652), ops§14(L657/L666), ops§33(L658/L659/L660/L661/L662/L664/L665), infra WSL2(L663)）
- （L667-L676は振り分け済 → research§GS結果(L667:robustness連動メタ列/L674:L1従属ラベル列), core§19.2(L669:monthly_returnセマンティクス[open-to-open]/L670:Oikaze first_signal EW/L671:Yotsume close cumulative+bootstrap), ops索引(L668:ALM DB preflight/L672:champion_list追記制御/L676:SQLite quick_check), ops§6-7(L675:recalculate-sync待機)。L673はL672重複→削除）
- （L677-L708は振り分け済 → ops索引(L677:SQLite検証/L678:合成ベンチ/L680:CLI引数照合/L684:output-dir alias/L688:Payload meta/L692:SSOT照合/L708:valid_start_date), ops§6-7(L690:sync完了判定/L701:fullrecalc復元), research§GS結果(L685:selector流用/L686:SQLite月次), research§パリティ(L699:NULL除外), research索引(L693:時間解像度), core§19.2(L694:top_n分離/L696:FoF top_n/L703:ticker×weight判定), frontend§12(L702:UUID漏れ/L704:precomputed weights/L705:月初Signal)。重複削除: L679≡L678, L681-L683≡L680, L689≡L688, L691≡L690, L695≡L694, L698≡L696, L700≡L699, L706≡L705。L687/L697/L707自動生成→削除）
- （L709-L720は振り分け済 → core§19.4(L709[PI]), ops§6-7(L714+L715統合), ops索引(L710/L713/L716/L717), frontend§12(L719+L720統合)。L711/L712/L718はAUTO-DEPRECATE→スキップ）
- （L721-L735は振り分け済 → ops教訓索引(L721/L723/L729/L730/L733/L735), core§19.2(L722/L734), research§38(L724/L725/L726/L728)。L727はL728重複→統合）
- （L737-L749は振り分け済 → ops索引(L737/L738統合:奥義BB命名正常挙動/L740:check_pf_config/L743:PF構成確認/L745:import分割/L747:UUID GS source_type), core§19.2(L739:pipeline_config構造/L741:BB忍法対応表/L742:パラメータ確認/L748:FoF components件数差), core§5(L744:API境界4層管理), ops§6-7(L749:models+migrations同期)。L746は自動生成→削除）
- （L750-L765は振り分け済 → research§27(L750/L751/L752/L753:シン四神相関分析), gs-speedup§3(L756/L758/L759/L760/L761:trial高速化手法), gs-speedup§4(L762:cache設計), ops索引(L763/L764:速度AC方法論)。L757/L765は自動生成→削除）
- （L766-L783は振り分け済 → ops§9(L766/L768:速度計測方法論), ops§12(L767:成果物パス命名), core§8(L769:α6キー名SSOT), infra教訓索引(L772:tracked限定集計盲点), ops§38(L773/L777/L780:CI import分割), core§5(L775/L781:分析関数性能), core§21(L782:FoFネストN+1), ops§6-7(L783:fullrecalculate確認手段[PI])）
- （L786-L801は振り分け済 2026-07-02 → frontend§12(L786:ComparisonChart Y軸/L796:localStorage storage event/L798:PAGE_APIS prefetch空/L801:Next共通chunk分割不能), ops§38(L789:mixed_format_commit回避), ops§49(L790:MTD cache), ops教訓索引(L791:scope別除去), ops§37(L793:cron envVars API検証/L794:cron UTC越境), ops§18(L799:計測クエリ入口BLOCK/L800:production Lighthouse証明限界), ops§19(L797:CDP cookie注入≠admin成立), infra教訓索引(L795:外部repo commit分類)。不変量候補なし）
- PD-054裁定(2026-07-02): 7023=Next App Router runtime不可避。App Router runtime削減設計には進まず、次方向は初期レンダー計算量削減(テーブル仮想化・チャート遅延・hydration削減)=fd9d/app chunks側。cmd_3660本番metrics計測はPerf 46→95/TBT 1724→55ms/CLS 0.743→0を確認。→ `/mnt/c/Python_app/DM-signal/docs/research/lighthouse_rounds/round_20260702_cmd3660_production_metrics_cls_close/manifest.json`
- （L818-L825は振り分け済 2026-07-08 → ops§6-7(L818:DB確認スクリプト経由), ops§32(L819:PF別設定参照/L822:Mockテスト横展開), ops§38(L820:pre-commit誤検知根本修正), ops教訓索引(L821:push状態先確認), research§24(L823:yotsume bak構造), gs-speedup§4(L824:GS CSVリーディングNaN), research§27(L825:相関全量安定性)。不変量候補なし）
- （L826-L830は振り分け済 2026-07-08 → research§27(L826:選出ツールの粒度差明示), ops§6-7(L827:FK依存復元のdb.flush), research§48(L828:GS-本番DTB3暦解像度差[PI-028]), infra教訓索引(L829:絶対パス直書きGuard16 BLOCK), research教訓索引(L830:小標本quantile交差分類不能)。不変量: PI-028追加）
- （L831-L843は振り分け済 2026-07-10 /lesson-sort → ops§33(L831/L835/L842/L843), ops§12(L832), ops§6-7(L833/L836), ops§39(L841), research§48(L834/L837/L838/L839)。L840はops教訓索引に既存。新規PIなし(DTB3系はPI-028既存でカバー)）
- （L851-L876は振り分け済 2026-07-12 /lesson-sort → ops§12(L851:matched_weight=sum比較), ops§9(L870:run不変値subprocess再取得禁止), ops§32(L857:env override差替え), research教訓索引(L874:オラクル機能的意味先検証)。L852はPI候補節に既存。L876はL1049と根重複+heredoc断定未検証のため非活性化を家老へ依頼済み。新規PIなし）
- （L887-L899は振り分け済 2026-07-14 /lesson-sort → research教訓索引(L887:非階層container敵対fixture), ops§76(L888:全量前preflight=既存本文とマージ), ops§32(L891:pytest node id実在収集固定/L899:subprocess ready timeout無条件継続禁止), ops§80(L897:bounded restore launcher貫通試験)。新規PIなし(全て手順・テスト教訓)）
- （L900/L901→ops§32に振り分け済み 2026-07-16）
- （L903→ops§9に振り分け済み 2026-07-17）
- （L908/L909/L918/L921は振り分け済 2026-08-01 /lesson-sort → ops§38(L908:pytest plugin root namespace固定), ops§6-7(L909:バックフィルas-of入力切断), ops§32(L918:launcher結合実行/相対パスBLOCK), core§19.2(L921:open-to-open bootstrap/live MTD独立境界)。新規PIなし）
- （L929/L932/L934/L935/L938/L943は振り分け済 2026-08-03 /lesson-sort → ops§12(L929:parity範囲=設計cohort), research教訓索引(L932:軸別総数一致/L938:decision month≠actual date), ops§6-7(L934:効力日列名≠SSOT), ops§32(L935:形式的分類和禁止), ops教訓索引(L943:prepare後成果不変順序)。新規PIなし(L934は設計書§0.6-1/trade-rule.md正本転記済みで重複回避)）
- （L946/L947/L950/L953/L1551/L1553は振り分け済 2026-08-10 /lesson-sort → ops§32(L946:preflight母数同一計数生成/L950:as_of-load-through時計分離/L953:fixture ID分類軸一意化/L1551:外部repo偵察の正本二値確認/L1553:test_necessityのrepo境界contract), ops§12近傍L943隣(L947:scope fingerprint=private-index所有path集合)。新規PIなし(全て手順・テスト規律教訓)）
- （L1554/L1587/L1596/L1598/L1599は振り分け済 2026-08-18 /lesson-sort → ops§37(L1554:価格完全性の期待グリッド外れ値除外), ops§89(L1587:initial signal基準日=effective start SSOT), ops§96(L1596:保存展開値は本番同値性確認後昇格), ops§100(L1598:exact tie/float僅差の分離→6段キー), infra教訓索引A(L1599:verification taskのno-code identity+runner契約)）
- L1602: 包含範囲の段数ACは式で検算する（cmd_4355）
- L1603: JSON-only研究証跡では行単位forward rankを保存し統計検定の再現境界を明示する（cmd_4374）

## §34 GS D1価格入力パリティ (cmd_3793, 2026-07-09)

- `analysis_runs/experiments.db.daily_prices` は `download_all_prices.py grid-search` 後に `sync_experiments_prices.py` で本番PostgreSQL `prices` / `economic_indicators(DTB3)` と同期する。cmd_3793では同期後 `gs_price_preflight.py` が14/14 ticker PASS、missing/mismatch 0を確認。
- GS実行前は `python3 scripts/analysis/grid_search/gs_price_preflight.py` を必須実行する。不一致時はexit 1で停止し、全一致時のみexit 0。詳細 → `/mnt/c/Python_app/DM-signal/docs/research/cmd_3793_d1_price_sync.md`

## §36 GS D4残4忍法ベンチマーク (cmd_3795, 2026-07-09)

- kawarimi(270,900pat)/nukimi(586,950pat)/yotsume(45,150pat)は現行`cmd_3774_pf_l1_champions_21.yaml`(21体)でフル実行し、既存E1(チャンク伝播)+E2(GC条件化)最適化のみで全て2分45秒以内・exit 0完了。5分超過なし、E3級追加最適化は現時点で不要。
- `run_077_weighted_yotsume.py`は現行universeでも自身のデフォルトuniverseでも実行不能(2系統の失敗を確認)。(1)`cmd_3774_pf_l1_champions_21.yaml`(champion_pattern_ids形式)→`all()`の空虚な真によりsource_type誤変換→KeyError。(2)デフォルト`okugi_shin_ninpo_20.yaml`→記載UUIDが本番monthly_returnsに現存せず(PF再登録で陳腐化)ValueError。`gsl2_shin_ninpo_21.yaml`(components形式、cmd_2394由来)でのみ実測成功(45,150pat, 46s, RSS464MB)。標準7忍法ローテーションに組込むには分岐条件修正+universe差替えが必要(decision_candidate、未修正)。詳細 → `/mnt/c/Python_app/DM-signal/docs/research/cmd_3795_d4_bench.md`

## §37 Phase B L1旧3基準GS (cmd_3798, 2026-07-09)

- 入力preflight: `scripts/analysis/grid_search/gs_price_preflight.py` が14/14 ticker PASS。universeは`config/portfolio_universes/cmd_3798_l0_a_current_12.yaml`、cmd_3797 `A_current`(CAGR/MaxDD/NHF)のL0旧基準12体。
- 7忍法直列実行は全てexit 0。出力は`outputs/grid_search/20260709/L1/cmd_3798_phase_b/`、ログは`outputs/analysis/cmd_3798_logs/`。行数: bunshin 781 / oikaze 17550 / kasoku_diff 84240 / kasoku_ratio 84240 / kawarimi 28116 / nukimi 45150 / yotsume 3906。
- 旧3基準チャンピオン21体を選出済み。特記事項: kasoku_ratioは激攻(CAGR最大)と常勝(NHF最大)が同一`kasoku_ratio_N4_0352_10M_11M_ratio_N1_R1`。詳細 → `/mnt/c/Python_app/DM-signal/docs/research/cmd_3798_phase_b_l1.md`

## §38 残存4体15ヶ月パリティ乖離 (cmd_3811, 2026-07-10)

- cmd_3806後も残った4体15ヶ月は常勝モード固有バグではない。15件中7件はPipelineEngine直接実行=GSで本番monthly_returnsのみ乖離、7件は直接Pipeline/GS/本番ledgerの比較基準が三者不一致、1件(玄武-常勝2023-12)は本番=PipelineでGSのみ乖離。
- 主因は`signal_decision_ledger` historical_backfillがband時の50% safe haven weightを`decision_ticker_weights`として保持せず、`decision_holding_signal`文字列を等ウェイト展開すること。非リバランス月は直接Pipeline再評価ではなく直近決定持ち越し基準で比較する必要がある。
- 詳細 → `/mnt/c/Python_app/DM-signal/docs/research/cmd_3811_remaining_divergence.md`、機械証跡 → `/mnt/c/Python_app/DM-signal/outputs/analysis/cmd_3811_remaining_divergence.json`

## §39 玄武-常勝2023-12 GS/本番乖離=DTB3暦解像度band境界フリップ (cmd_3813, 2026-07-10)

- cmd_3811で残った「玄武-常勝2023-12のみ本番=PipelineでGSだけ乖離」を数値トレースし確定。原因はPI-028と同一構造: GS `MomentumCache`がDTB3(risk_free/reference_asset)を株式取引日マスターカレンダーへ強制リインデックスしてから378日rollingを取る(`grid_search_metrics_v2.py:813,1047-1132,1195-1300`)のに対し、本番PipelineEngineはDTB3ネイティブ発表日暦で378日rollingを取る(`absolute_momentum.py:272-327`, `data_loader.py:53`)。
- 実測: abs_mom(SPXL)は完全一致(0.069647...)。rf_mom(DTB3)がGS=0.06485872673910675/本番=0.06462168371748911で乖離(delta=-2.37e-4)。margin(abs_mom-rf_mom)がGS=0.004788(band圏内)/本番=0.005026(pass圏)とthreshold_band=0.005の境界をまたぎ、GSはband(XLU50%+TQQQ50%→0.07674...)、本番はpass(XLU100%→0.01376...)に分岐した。
- GS本体グリッドサーチ(944K+パターン)は`shin_shijin_l1_gs.py:1740-1741`で`pipeline_config=None`を強制しnumpy_fast経路のみを通る。PipelineEngine経由パスのDTB3日付補正はこの経路に適用されない。
- 波及範囲: 171ヶ月中2023-12の1ヶ月のみ(玄武-常勝)。同ファミリーの玄武-激攻/鉄壁は乖離0件(marginがband境界から離れているため未発現)。系統的ではない。
- 詳細 → `/mnt/c/Python_app/DM-signal/docs/research/cmd_3813_genbu_gs_divergence.md`、機械証跡 → `/mnt/c/Python_app/DM-signal/scripts/oneshot/cmd_3813_genbu_gs_divergence.py`

## §40 GS MomentumCache DTB3ネイティブ暦rolling化=PI-028実害修正完了 (cmd_3814, 2026-07-10)

- cmd_3813偵察の修正候補(a)を実装完了。`MomentumCache`にDTB3専用のnative calendar cache(`_build_dtb3_native_cache`、既存`_build_vix_native_cache`と同一設計)を新設し、`daily_prices`から`ticker='DTB3'`のみでネイティブ発表日系列を読み直す。Phase1(`_build_cache_fast`のmomentum_matrix注入)とPhase2(`_build_dtb3_rolling_matrix`/`get_dtb3_rolling`のthreshold_band判定)が同一キャッシュを共有し、算出日カレンダーが統一された。`get_dtb3_rolling`は辞書直引きから`bisect`による「date以前で直近のDTB3発表日」検索へ変更(本番`get_momentum_value_at_date`と同一セマンティクス)。
- **修正後、玄武-常勝2023-12を含む171/171完全一致(誤差1e-11オーダー)を実測確認**。玄武-激攻/鉄壁も171/171維持(デグレなし)。既存最強回帰テストcmd_3755 AC2(`verify_gs_band_parity_pi009.py`、7PF×threshold_band注入×実PipelineEngine突合)も全PASS(max_abs_diff=0.00e+00)、既存パリティを一切崩していない。
- **影響範囲を全gridDB(4family, 191,796パターン, threshold_band=0.005で生成済み)で網羅集計**: distinct DNA group(absolute_asset+lookback_terms_json, 9,589組・間引きなし)ごとに旧margin/新marginを全171ヶ月で算出。境界近傍(|margin∓band|<2.4e-4になる月が1回でもある)=92,892パターン(48.4%、緩い上限)。**実際にpass/band/fail分類が新旧で変わる「実フリップ」=6,684パターン(3.5%)**。系統別ではDM2(青龍系)が実フリップの82%を占め偏りが大きい。DM7+(玄武系)は今回修正したDNA groupを共有する24パターン全てが該当。
- 現行本番102PFはthreshold_band未設定(band不発稼働、§既出)のため、この影響範囲は「将来threshold_bandを本番適用した場合にGS選出結果へ及ぶリスク」の定量値であり、現行本番の実害ではない。
- 詳細 → `/mnt/c/Python_app/DM-signal/docs/research/cmd_3814_dtb3_native_calendar.md`、回帰テスト → `/mnt/c/Python_app/DM-signal/backend/tests/test_dtb3_native_calendar_parity.py`、機械証跡 → `/mnt/c/Python_app/DM-signal/scripts/oneshot/cmd_3814_{verify_dtb3_native,genbu_parity_recheck,boundary_impact_scan}.py`

## §41 DTB3修正済み4family再GS+12体最終突合 (cmd_3815, 2026-07-10)

- cmd_3814修正済みエンジンでDM2/DM3/DM6/DM7Pをthreshold_band=0.005込みで全量再GS。直前`gs_price_preflight.py`は14/14 PASS、missing/mismatch 0。出力は`/mnt/c/Python_app/DM-signal/outputs/grid_search/20260710/L0/shin/`、全4family合計191,796パターンで20260709既存gridDBと同数。
- cmd_3806同一手法で本番現行12体の同一パラメータ突合を再実行した結果、完全一致は4/12(玄武-常勝、玄武-鉄壁、白虎-激攻、玄武-激攻以外は残乖離あり)。大工程L0 Stage 2は未完了。残乖離はcmd_3812(ledger weights)・cmd_3814(DTB3 native暦)だけでは説明不能として別根因切り分けが必要。
- 2026-07-10 04時台のSIGNAL CHANGE 1件は`signal_change_log.id=66123`、PF=`秘奥義-変わり身-激攻`、signal_date=2014-10-31。旧TECL/TQQQ各50%から新XLU50%+TECL/TQQQ各25%へ変化し、cmd_3812 weighted ledger rebuildによるband safe-haven weight復元が理由。詳細 → `/mnt/c/Python_app/DM-signal/docs/research/cmd_3815_final_parity.md`、機械証跡 → `/mnt/c/Python_app/DM-signal/outputs/analysis/cmd_3815_same_param_parity.json`

## §42 残存8体72ヶ月の3点突合根因確定=cmd_3812のledger優先ロジックが潜在staleデータを活性化 (cmd_3816, 2026-07-10)

- cmd_3815で残った8体72ヶ月の乖離を、cmd_3811と同一の3点突合(本番DB値/PipelineEngine直接実行値/GS値)で全数追跡した。静的diff(cmd_3806/3812/3815の乖離月集合比較)により**cmd_3814(GS DTB3暦再生成)は玄武-常勝2023-12(cmd_3813/3814で別途解決済み)を除き本cmd範囲の72ヶ月に一切影響していない**ことを確定(`FIXED_BY_3814`が全PFで空集合)。原因は**cmd_3812のledger weights再backfill**に一本化される: 67/75行が`NEW_IN_3812_PERSISTS_AFTER_3814`、64/75行が`PIPELINE_GS_MATCH_PROD_DIVERGES`(ライブPipelineEngine実行値とGS値が一致し本番保存値のみ乖離)。
- **根本メカニズム**: `backend/app/jobs/generators/monthly_returns.py` L344-349がledger保存weightsを無条件優先するようcmd_3812で変更されたが、`backend/scripts/build_signal_decision_ledger_historical_backfill.py` L163-180の`_extract_signal_weights`は`signals.momentum_data.weights`を**現在保存されている値のまま**コピーする設計(docstring L13「as recorded today」)。多くの履歴月・直近月(2026-04含む)で`signals`保存値はband混合weightsのままだが、現在の本番価格データで`absolute_momentum.py`のmarginを再計算すると明確に`fail`域(閾値0.005を大きく超える負値)で単一資産100%が正しい。この不整合はcmd_3812以前は等ウェイトフォールバックの陰に隠れており、ledger優先化で表面化した。
- 残り11/75行(14.7%)は`ALL_DIVERGE`(GS値もライブ実行と不一致)でband遷移直後の月に集中する別要因→**cmd_3818(2026-07-10)で根因確定**(下記§42.1)。
- 次アクション(未着手): `signals.momentum_data`の全履歴再生成、またはledger優先ロジックへのband再検証の要否は実装判断が必要。
- 詳細 → `/mnt/c/Python_app/DM-signal/docs/research/cmd_3816_residual_divergence.md`、機械証跡 → `/mnt/c/Python_app/DM-signal/outputs/analysis/cmd_3816_residual_divergence.json`、スクリプト → `/mnt/c/Python_app/DM-signal/scripts/oneshot/cmd_3816_residual_divergence.py`

### §42.1 ALL_DIVERGE 11行の根因確定=「band遷移」ではなく検証スクリプトのrebalance_trigger非対応 (cmd_3818, 2026-07-10)

- 11行全てが朱雀(bimonthly_even)・白虎(quarterly_jan)の4PF(常勝/鉄壁)のみに集中し、monthlyの玄武・青龍は0行。**「band遷移直後」は見かけ上の相関で、真因は非monthlyリバランスPFの参照日解決**。
- `cmd_3811_remaining_divergence.py`/`cmd_3816_residual_divergence.py`の`month_bounds()`(両ファイル共通の同名関数)は`rebalance_trigger`を一切参照せず、常に「返り月の直前営業日」を参照日として`PipelineEngine.execute_pipeline(target_date=...)`を呼ぶ。非monthly PFの非リバランス月ではこれが誤った参照日になる。
- 正しい参照日解決は`backend/app/services/rebalance.py`の`get_last_rebalance_month_end_business()`(`_resolve_signal_month()`経由)。これで11行全件のtarget_dateを補正して`PipelineEngine`を再実行した結果、**11/11行が1e-6以内でGS値と完全一致**(`corrected_matches_gs=True`)。**GS(`shin_shijin_l1_gs.py` L1011-1031の`carried_idx`/`rebalance_masks`機構)は正しい**、検証スクリプト側にバグがあった。
- 本番保存値との残差(11/11行で依然prod≠corrected)は新規根因ではなく、§42既出の「ledger優先ロジック+staleスナップショット」機構と同一(cmd_3817が並行して着手済み)。
- 詳細 → `/mnt/c/Python_app/DM-signal/docs/research/cmd_3818_band_transition_divergence.md`、機械証跡 → `/mnt/c/Python_app/DM-signal/outputs/analysis/cmd_3818_band_transition_trace.json`、スクリプト → `/mnt/c/Python_app/DM-signal/scripts/oneshot/cmd_3818_band_transition_trace.py`

## §43 Matched weight WARN run単位自動集計+ntfy通知=恒久監視完成 (cmd_3820, 2026-07-10)

- WARN根絶設計書(`docs/research/matched-weight-warn-eradication-design.md`)§3手順6を実装。`monthly_trade_impl.py`のMatched weight WARN(matched_weight != 1.0)を、既存`signal_change_log_buffer`と同型のミュータブルリスト集約パターンでrun単位にプロセス内カウンタ化(ログgrep不要)。0件時は通知抑制、1件以上ならCRITICALログ+既存confirmed signal change alertと同一ntfy経路(`NTFY_ALERT_TOPIC`)へ`[MATCHED WEIGHT WARN]`バッチ通知1回のみ送信。fullrecalculate/部分再計算/precomputeいずれの経路でも自動適用(`precompute_raw_for_portfolios`が生成する`MonthlyTradeCalculator`単一インスタンスをrun全体で使い回す既存構造を利用)。
- WARN=0達成(cmd_3812)後の再発を人手のログ確認に頼らず即検知する防御階層Level5が完成し、設計書§3の手順1-6が全て完了。
- 新規ユニットテスト14件(0件/1件以上の通知分岐含む)追加、既存テスト含め該当スコープ96件全PASS。全件テスト実行(1614 passed)で1件の既存FAIL(`test_recalculate_status.py::test_status_resets_after_completion`)を検出したが、`git stash`で本cmd変更を退避しても同一失敗が再現することを実証し、本cmdと無関係のpre-existing environment依存(DBに残存する"running"行への依存)と確定。
- 詳細・テスト証跡 → `/mnt/c/Python_app/DM-signal/docs/research/cmd_3820_warn_monitor.md`

## §44 precompute全量最速化 Phase P1: 評価器2道具凍結+immutable baseline (cmd_3819, 2026-07-10)

- **評価器2道具を凍結**（`scripts/oneshot/cmd_3819_precompute_bench.py`=全量ベンチPF別/ビルダー別秒割り+RSSピーク+3回中央値、`cmd_3819_precompute_parity.py`=canonical JSON hash+Pythonオブジェクト等価2判定の突合ゲート、`--export`で凍結スナップショット化可）。凍結commit `c956e4e7f2dd6d335c4e7a5eafbd95c0b58a3814`。P2(/goalループ)のgoal忍者はこの2ファイル変更禁止
- **ローカルPostgresはDocker不可、pgserver方式**: このヘッドレス環境ではDocker Desktop WSL2統合が機能しない（GUI操作を要し完了不可、実測確認済み）。sudo・Docker不要の`pgserver`パッケージ(PyPI, prebuilt PG16.2バイナリ同梱)を`$HOME/dm-signal-cmd3819-localpg/venv`に隔離導入。ネイティブext4上で稼働（`/mnt/c`は9pで低速、ベンチが歪むため不使用）。同梱pg_dumpはSSL非対応ビルドのため本番接続にはpsycopg2 COPY BINARYストリーミング方式(`cmd_3819_baseline_provision.py`)を使用。他PJでローカルPostgresが要る場合の再利用可
- **binary COPYは列順一致必須**: 本番の物理列順とSQLAlchemy `Base.metadata.create_all()`の宣言順が食い違うと値がずれてUTF8デコードエラー等の破損を起こす（実測）。export/restore双方で`Base.metadata`由来の明示列リストを使うことで解消
- 詳細・凍結hash証跡・baseline snapshot・初回ベンチ数値・理論下限推定 → `/mnt/c/Python_app/DM-signal/docs/research/cmd_3819_precompute_p1.md`

## §46 precompute全量最速化 P2: H2 canonical parity FAIL 868件は日付ドリフト、id=206検証法自体が非等価 (cmd_3825, 2026-07-10)

- **cmd_3821のcanonical parity FAIL 868件はH2のバグではない**: baseline(2026-07-09)とrerun(2026-07-10)が別日だったための`as_of_date`/`computed_for`等の日付依存フィールド差分。H2単体(monthly_return_cacheの3ビルダー共有)はfresh clone同日apples-to-apples(2699/2699, mismatch 0)で既に無罪と確認済み(hayate cmd_3821)。今回100%無改造git HEADコードで再検証し同一結論を再確認
- **id=206候補DB vs 実本番fullrecalculate結果の突合(candidate_id206系)は方法論自体が非等価**: standalone `precompute_raw_for_portfolios()`単体実行は、`recalculate_fast`のライブパイプライン内実行と厳密には同値でない(FoF PF 2体で15行中13-14行不一致、標準PFは1行のみ)。**100%無改造コードでも同じ29件の不一致が再現**(`/tmp/dm-signal-cmd3825-pristine-check`検証)。cmd_3825のスコープ外、standaloneモードのFoF固有差異として別cmd起票が必要
- **正しい検証法はapples-to-apples(pristine standalone vs candidate standalone、同一実行方式)**。この方式でH2単体=0/45不一致(完全無罪)、フルwarm-context+canonical slicing=11/45不一致(実バグ)と判明
- **canonical variant slicing機能(cmd_3825で追加された非H2拡張)を実バグと確定・削除**: 1回計算した"canonical"結果を他パラメータへスライス流用する最適化が`performance`(年数カットオフの基準日リベースを無視)と`monthly_trade`(limit値のスライスは実際のクエリ意味と不一致)で出力を壊す。`monthly_returns`/`annual_returns`は偶然ソート順が一致し無事だったが、機構自体が不健全なため`backend/app/jobs/precompute_raw.py`から全面削除(explicit/minimal diff優先)
- **`MonthlyTradeCalculator`の共有price_cacheに日付レンジ網羅チェック欠如を発見・修正**: 既存のFoF分岐は`has_ticker()`(ticker存在有無のみ)でギャップ判定していたが、これはticker自体はキャッシュにあってもその月に必要な特定日付がカバーされているかは保証しない。共有/warmキャッシュが個別PFの必要レンジと異なる窓で構築されると特定日のprice lookupが静かに失敗し、`missing_tickers`全件+`matched_weight=0.0`+`price_movement=None`という壊れ方をする。標準PF分岐には元々この安全網自体が存在しなかった(FoF分岐のみ)。`_ensure_price_cache_coverage()`を新設し両分岐に追加、`_date_lists`で実際の日付網羅を確認しギャップのみmerge-load(38-39s、無条件全件reload版の91sから復帰)
- **最終形: フルwarm-context(portfolio_preload/signal_preload/rolling系preload/drawdown_preload/perf_price_cache全て) + canonical slicing削除 + price_cache網羅修正 = 0/45不一致(apples-to-apples)**。関連テスト(test_precompute_raw.py 3件更新含む11件、周辺calculator/endpoint系192件)全PASS
- **凍結評価器(cmd_3819)による最終103PF全量確認完了**: ベンチ3回=677.59/649.78/623.02s、**中央値649.78s（baseline 1180.64s比 44.96%短縮）**。パリティ初回=2699/2699 common、missing/extra=0、mismatch=3件(PF単体2696件は完全一致、残3件は無改造の`compare_returns_bulk`/`metrics_summary_bulk`)
- **殿裁定(cmd_karo_hotfix_cmd3825_bulk_parity_zero, 2026-07-10)「スコープ外」除外を却下、全行完全一致の不変条件を要求**。根因を一意特定: `CREATE DATABASE ... TEMPLATE`直後はシーケンス未整備で、precompute_raw.pyのbulk書込み(unmodified)がtry/exceptで丸ごとrollbackする既存挙動と組合わさり、片側cloneの初回bulk INSERTがPK衝突→サイレントrollback→テンプレートの古いbulk行のまま残存(=新旧コードの差ではなくstale-vs-fresh入力の差)。同一snapshot hash(portfolios/monthly_returns/signals)+bulk builder単体実行(無改造コード、両clone間でhash完全一致)で確定。**恒久修正**: `cmd_3819_baseline_provision.py`の`clone_from_template()`に`fix_sequences()`を追加、全serial列を`setval`で自動修復(凍結2ファイルbench.py/parity.py自体は無改造)。**再検証(1回のみ)で真のゼロを達成: 2699/2699 common、mismatch=0**
- **AC4(速度ロードマップ)**: 649.78sは100PF≦30s目標比**21.7倍**、bulk単体実行(無改造)が数分規模で総時間の相当割合を占める可能性大(未定量)。次段優先順位: ①bulk/per-PF loop時間split計測(前提) → ②H1並列化(bulk側が優勢ならbulk対象へ再スコープ) → ③H5 upsert batching(標準モードにはdefer_commit無し) → ④H6 GC調整(他PJ前例のみ、要実測確認)。3PF fixture優先、apples-to-apples手法を毎回適用
- 詳細・iteration log・数値根拠 → `/mnt/c/Python_app/DM-signal/docs/research/cmd_3825_h2_parity_fix.md`

## §45 fresh signals再backfillではcmd_3816残差は解消せず + 2014-10-31往復フリップ検出 (cmd_3817, 2026-07-10)

- cmd_3817は24PF ledger backup→ledger 3495行削除→signals再計算→fresh signalsからledger 3495行backfill→monthly_returns反映再計算を本番で実行したが、cmd_3815同一手法の最終突合は**改善なし**。完全一致は`3/12`、一致月`1977/2052`、ミスマッチ`75`でcmd_3816時点と同一。単純なfresh-signals rebackfillでは残差は解消しない。
- 実行上の注意: 1回目のrecalc `id=201` は修正deploy完了前に走ったため無効化し、deploy後にledger削除からやり直した。最終有効シーケンスは`id=204`(signals再計算完了 2026-07-10T00:53:03Z)→backfill 3495行→`id=205`(monthly_returns/precompute完了 2026-07-10T01:37:20Z)。
- 追加補足の`signal_change_log`確認で、PF `65db7b53-9e62-4217-b8bb-65cf5445b606` / `秘奥義-変わり身-激攻` / `2014-10-31` の直近3件が `TECL/TQQQ 50/50 -> XLU50+TECL/TQQQ25 -> TECL/TQQQ50/50 -> XLU50+TECL/TQQQ25` の往復フリップであることを検出。最終値はband理論制約(選択資産合計0.5+safe haven 0.5=1.0)を満たすが、一方向再構築ではないため非決定性バグ候補として扱う。
- 詳細 → `/mnt/c/Python_app/DM-signal/docs/research/cmd_3817_fresh_signals_rebackfill.md`、機械証跡 → `/mnt/c/Python_app/DM-signal/outputs/analysis/cmd_3815_same_param_parity.json` `/mnt/c/Python_app/DM-signal/outputs/analysis/cmd_3816_residual_divergence.json`

## §35 GS D3出力パリティ再検証 (cmd_3794, 2026-07-09)

- **PI-009 GS-vs本番エンジン突合はD1価格同期の影響を受けない**: cmd_3755(T1)の5/7 PASS結果と、D1同期済みprices再検証後の結果は完全一致(5/7 PASS、変化なし)。2 FAIL(DM-safe/DM-safe-2、共に2009-05・gate_state=band)は価格陳腐化ではなく別要因と確定。
- **PI-009突合スクリプトが参照するDBはexperiments.dbではなくgs_prefetch.db**: `scripts/analysis/grid_search/verify_gs_band_parity_pi009.py`(cmd_3755作成)は`analysis_runs/gs_prefetch.db`(`prefetch_gs_data.py`で生成)を読む。D1(cmd_3793)は`experiments.db`のみ同期対象で`gs_prefetch.db`は対象外だったため、D3実施前は`gs_prefetch.db`も本番と14/14 FAIL(TQQQ最大diff 0.20)で陳腐化していた。`prefetch_gs_data.py`再実行(本番→ローカルcache読取専用、`.gitignore`対象)で14/14 PASSへ復元してから再検証した。GS入力価格系列は**experiments.db(L0系)とgs_prefetch.db(PI-009突合系)の2系統**が別々に本番同期を要する。
- 2 FAILの共通構造: 3資産universe(`QQQ/GLD/XLU`or`QLD/GDX/XLU`)+`safe_haven_asset=GLD`+`top_n=2`。PASSの5PFは全て2資産(`TQQQ/TECL`)+`top_n=1`。原因は`top_n=2`のband gate下でのマルチアセット重み配分ロジック差の疑い(follow-up cmd要)。詳細 → `/mnt/c/Python_app/DM-signal/docs/research/cmd_3794_d3_parity_recheck.md`

## 因果リンク

- ← [[infrastructure]] インフラが支えるメインPJ
- → [[dm-signal-core]] コアパイプライン詳細
- → [[dm-signal-ops]] 運用詳細
- → [[dm-signal-research]] 研究詳細
- → [[dm-signal-frontend]] フロントエンド詳細
- → [[cmd_absorb_refactor_after_20260506]] 吸収ルールリファクタリング後の実装(cmd_1080: シン忍法v2完成後)
- → [[cmd_absorb_refactor_spec_20260506]] 吸収ルールリファクタリング仕様書(シン忍法v2 absorption設計)
- → [[dm_signal_refactor_mission]] BE4分割リファクタ全工程完了(2026-06-13)。WP-0(契約18)+WP-1(FE/BE削除)+WP-2(EP11+ブロック4種+Kalman)+WP-3(AC1 price_ratio+AC2 4モジュール分割+AC3縮小版FE参照除去)。本番数値不変証明済み。→ `/mnt/c/Python_app/DM-signal/.agent/task-force/execution-log.md`
- → [[cmd_4294_dm_signal_page_data_api_map]] FE全21 route→API→BE handler→table→L1/L2/L3/L5生成層の現物対応表・Mermaid依存図・既知表示欠け切り分け（2026-08-11）。→ `docs/research/cmd_4294_dm-signal-page-data-api-map.md`(DM-signal repoの原本はrollback 233c2303(2026-08-13)で本番treeから消えたため、git履歴からMAS側へ全文複製)
- → [[cmd_4295_dm_signal_ssot_audit_map]] FE表示項目→API→BE生成元の項目台帳、重複生成候補、FE再計算分類（2026-08-12）。→ `docs/research/cmd_4295_dm-signal-ssot-audit-map.md`(DM-signal repoの原本はrollback 233c2303(2026-08-13)で本番treeから消えたため、git履歴からMAS側へ全文複製)
