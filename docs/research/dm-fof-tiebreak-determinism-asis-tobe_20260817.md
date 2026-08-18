<!-- gist-master: 1e0cab30de1efc851d4048858e8ece6d dm-fof-tiebreak-determinism-asis-tobe_20260817.md -->
# FoF子PF選択の決定性 AsIs/ToBe — 浮動小数点ノイズで確定履歴が動く穴を「同値帯ε+根拠あるtie-break」で閉じる

## 原則（親文書と同じ。殿裁定 2026-08-15 / 2026-08-17 01:42）

- ToBeは構造的に不可能でない限り妥協しない。AsIsは現実のコードそのもの。変更履歴は書かない（見出し=版+タイムスタンプ、粒度は末尾注釈）。
- 裁定は「事実→制約→判断→効果」の因果で記す。
- **実装は殿の指示まで行わない**（2026-08-17 12:35 殿「決定ではなくチャットとして会話しよう」／12:39「今は情報待ちだね」）。情報待ち=cmd_4330(read-only偵察: 現行の比較キー・同値時の順序決定・価格取込み精度・修正3案の影響範囲)。

発端: 2026-08-17 10:47 JST SIGNAL CHANGE ALERT 6,477件/35 FoF PF/2014-06〜2026-06 → 三段確認(cmd_4329)で「価格は変わった、ただし浮動小数点ノイズ級」「cronとfullは一致」「35 FoF全体に広域連鎖(子PF選択の入替)」が確定。
関連: `dm-production-code-rollback-plan_20260813.md` §-1(復帰点・cron注意)、`dm-monthly-trade-pending-simplify-asis-tobe_20260817.md`(ledgerの将来=廃止方向)。

## AsIs **v0.9** — 2026-08-17 12:45+09:00（事実はcmd_4329確定・機構はcmd_4330偵察中のため仮説）

| 項目 | 事実(一次) | 出典 |
|---|---|---|
| 価格差の実態 | 旧DB(08-16世代) vs 新DB(08-17世代): 13銘柄74,977行×2、key欠損0。**11銘柄30,003行/120,012 OHLCセルに差**、GLD/^VIX/volumeは差0。相対差 **min 5.96e-08 / p50 1.52e-07 / p95 5.66e-07 / max 1.88e-06**(LQD 2010-07-19 close 60.84331130981445→60.843196868896484)。配当/分割調整の桁ではない=**浮動小数点表現の揺れ** | cmd_4329 AC1(影丸・12:13) |
| 価格取込み | `sync_layers.py:62 sync_prices` は毎日 FULL_HISTORY_START から全期間再取得、`etl/loader.py:17-42 save_prices` が同一PKのclose等を上書き。source=stockdata_api。price_history表なし(過去世代は旧DBにしか残らない) | cmd_4328 AC3 / cmd_4329 |
| 外部ソースの履歴版 | StockData API=履歴版なし(open/high/low/close/volume/source/last_updated のみ)。EODHD/Tiingo=raw+adjustedの**現行**系列は取得可、過去as-of版なし | cmd_4329 AC1(実レスポンス) |
| cron vs full | run400(full)後もsignalsは sync-fof値と6,477/6,477一致(old一致0)=両経路の計算は同じ。monthly_returns/fof_component_weightsは世代snapshotが無く差分unknown | cmd_4329 AC2 |
| 変化の中身 | 35 FoF全体・2014-06〜2026-06に広域。差分銘柄関連4,807/非関連1,670。中身は**子PF選択の入替**(GSシン加速R-激攻: シン玄武-激攻→なし249、なし→激攻229、常勝→激攻186、激攻→常勝147 …) | cmd_4329 AC3 |
| 標準PF | 変化0行(alertなし) | cmd_4328/4329 |
| **仮説(cmd_4330で確定待ち)** | 子PFは保有が重なる月にリターンが**完全同値**になる(同じETF・同じ比率)。FoFの子選択の比較値が同値のとき、順序が浮動小数の最下位ビット(=価格ノイズ)で決まっている。標準PF(ETF同士)は同値が起きにくいので反転しない | 将軍推定 |
| 過去の対処=ledger | cmd_3706/3711で`signal_decision_ledger`(確定月凍結・DRIFT BLOCK)を導入=**出力を凍結して症状を止めた**。fullが再生成しない行を作り(08-16原則と衝突)、PITR切替で消え(現在0行)、バンド期再構築で正しい再計算を止めた前科(cmd_3817/3827) | context/dm-signal-ops.md §81系 |

## AsIs **v1.0** — 2026-08-17 12:50+09:00（cmd_4330 read-only偵察・影丸・GATE CLEAR 12:43。機構が現物で確定）

| 項目 | 現物 | 出典 |
|---|---|---|
| FoFの子PF選択 | `ComponentPriceBlock`が子PFの`MonthlyReturn.cumulative_return`をprice_dataへ注入し、pipeline_config `selection=[MomentumAccelerationFilter(top_n=1, method=ratio, numerator_period=10D, denominator_period=63D)]`, `terminal=EqualWeight`。月次データでは10D→1ヶ月・63D→3ヶ月に変換し **score = (close/close[-1]−1) / (close/close[-3]−1)**(1ヶ月リターン÷3ヶ月リターンの比) | cmd_4330 AC1 |
| 同値時の順序決定 | `momentum_acceleration_filter.py:135-142`: scoreだけで降順sortし **cutoff以上を全採用**。二次key(PF ID等)は**存在しない**。exact tieなら同率候補を**全部selected**(top_n=1でも2体保有になる) | cmd_4330 AC1 |
| 反転の実態(GSシン加速R-激攻・候補4子PF) | 2013-09: old 玄武-常勝5.079373775712119 vs 玄武-激攻5.079373775712077(差4.2e-14)→new でも同差で順位維持／**2015-04: old 激攻−0.187830685322682 vs 常勝−0.187830685322683(差1.1e-15)→new は完全同値でexact tie→両方selected**／**2016-12: old 激攻0.971402849738493 vs 常勝0.971402849738493(差1.1e-16、激攻rank1)→new 常勝0.971402849738497 vs 激攻…488(差8.9e-15、常勝rank1)=1位が入替**。他候補(青龍/朱雀)は桁違いに離れている | cmd_4330 AC2(新旧DB readonly再計算) |
| 仮説の修正 | 候補の**cumulative_return自体の差は0.0485〜0.1230**で価格ノイズ級ではない(旧仮説否定)。同値になるのは**ratio score**(1M/3M)であり、同じ保有区間を持つ2子PFが同じ比を出す。差1e-14〜1e-16=**float演算の丸めだけの差**で、価格の最下位ビットが揺れると順位が入替わる | cmd_4330 AC2 |
| 取込み経路 | `client.py:89-140` PriceEntry float → prices float8、`data_fetcher.py:35-102` 全期間再取得、`etl/loader.py:17-42` (symbol,date)全列上書きUPSERT | cmd_4330 AC3 |
| 修正3案の5要件表 | 報告YAML `queue/reports/kagemaru_report_cmd_4330.yaml` AC3 | 同 |

**確定した機構**: 比較値=ratio score(1M/3M)、同値判定=浮動小数の完全一致のみ、tie-break=なし(同率は全採用)。∴ 1e-14級の差で「単独保有⇄2体等分保有⇄逆の単独保有」が揺れる。**標準PFが動かないのはETF同士のscoreがこの精度で並ばないから**。

## AsIs **v1.1** — 2026-08-17 14:50+09:00（cmd_4331 read-only偵察・影丸・GATE CLEAR 13:55。全FoF棚卸し+6段キー乾式適用）

| 項目 | 現物/実測 | 出典 |
|---|---|---|
| FoF母集団 | 74 PF(`portfolios.type='fof'`)。selection block有=57(MomentumAcceleration 18／Momentum 9／MultiView 9／SingleView 9／TrendReversal 9／WeightedMultiView 3)、**無=17**(Ave-X・裏Ave-X・New Fund of Funds×4・劇薬DM×2・分身×9)。terminalは全てEqualWeight | cmd_4331 AC1 |
| 選択層の位置 | 共通dispatchは`backend/app/services/pipeline/engine.py:109-142` `PipelineEngine.execute_pipeline()`だが**ranking/cutoff/tie-breakは所有しない**。各block(`momentum_filter.py:141-147`／`momentum_acceleration_filter.py:135-142`／`multi_view_momentum_filter.py:203-210`／`single_view_momentum_filter.py:167-174`／`weighted_multi_view_momentum_filter.py:205-211`／`trend_reversal_filter.py:154-163`)が個別にsort・cutoff(`>=cutoff`全採用)・union/voteを実装。**共通top-N/tie-break helperは存在しない** | cmd_4331 AC1 |
| GS共有 | run_077_kasoku_ratio.py:858-860,1447-1449／run_077_oikaze.py:8-16／run_l1plus_backtest.py:32-66 がproduction blockをparity referenceとして参照するが、**vectorized fast pathは独自にscore/cutoffを計算**(併存) | cmd_4331 AC1 |
| score gap分布(scalar filter 45PF) | rank1/rank2の7,077観測: 相対<1e-9=982、exact同値=888、現行の同率全採用(expansion)=792月。MAF 18PFが754/697/697で大半 | cmd_4331 AC2 |
| 標準PF対照 | 24 PF(全てMomentumFilter)4,178観測: 相対<1e-9=**0**、exact=**0** → **ε=相対1e-9の本番データ根拠** | cmd_4331 AC2 |
| 6段キー乾式適用 | scalar 36PF: 変化837月(現行expansion 792月)。**全74 FoF: 適用月9,141・評価15,910・変化949月**(MAF722／Momentum55／MultiView30／SingleView60／Trend82／Weighted0／no-block 0)。段別解決: ②12M 4,511／③設定来CAGR 668／④MaxDD 0／⑤現保有 7／⑥設定来早い方 7、②skip(12M未満)264 | cmd_4331 AC3 |
| データ充足 | 12M・設定来CAGR・MaxDDは子PF`monthly_returns.cumulative_return`からpoint-in-timeで計算可(未来行不要)。no-block 17 PFは選択スコアの対象外で、実装カバレッジ74/74を主張する前に別途整理が要る | cmd_4331 AC3 |
| 既存テスト | test_momentum_acceleration_filter／test_pipeline_engine／test_grid_search_consistency／test_multi_view_momentum_filter／test_single_view_momentum_filter 等が拡張対象(本cmdではテスト未作成) | cmd_4331 AC3 |

**確定した設計制約**: (1)tie-breakは**共通選択層**として置く必要があり、各filterがscored candidatesを露出→共通層で6段比較→multi-view union/vote・TrendReversal top/bottomの意味は明示的に保つ。(2)GS fast pathは同じ共通層を通すか、parity testで同一結果を強制する。(3)導入時の組み替え規模=949月/74PF(scalar 837月)。根拠正本: `docs/research/cmd_4331_fof_tiebreak_dryrun_20260817.md`(DM-Signal repo `6b3537fd`)、`queue/reports/kagemaru_report_cmd_4331.yaml`。

## AsIs **v1.2** — 2026-08-17 19:30+09:00（手①②実装の進捗と、変わり身の選択部が別パターンである事実）

| 項目 | 現物/実測 | 出典 |
|---|---|---|
| 手① 加速フィルタ | 共通関数 `backend/app/services/pipeline/selection.py` `select_top_n_with_ties(scored, top_n)` 新設・加速フィルタ差替済み。同率全採用のまま(挙動不変) | cmd_4334 commit `e44a7bb7`・家老レーンfull md5一致 |
| 手②a Momentum／SingleView | 選択部を共通関数へ差替済み(2ファイル・+6/-18行のみ)。近接pytest 36 passed／0 skip、同値性4/4一致 | cmd_4335 commit `783668bb`・GATE CLEAR 18:57 |
| 手②b 四つ目／新四つ目 | 視点ループ内(合成前)で共通関数へ差替済み。union／vote集計は不変 | cmd_4336 commit `ff77e7eb`・家老レーン検証中 |
| **変わり身(TrendReversal)** | **選択部は同率全採用ではない**: `trend_reversal_filter.py:154-160` = score降順sort→`momentum_results[:select_n]`(上位N個をきっちり切る)＋`momentum_results[-select_n:]`(下位N個)→union。同点でもN個で切る。共通関数`select_top_n_with_ties`をそのまま当てると同点時に採用数が増え挙動が変わる | 将軍現物確認 19:00 `sed -n 150,166p` |
| 標準PF executor | 手①②の対象外(FoF専用block経路のみ)。標準PF24はnear-tie 0 | AsIs v1.1のまま |

**確定した設計制約(追加)**: (4)変わり身を挙動不変で共通層へ通すには、共通関数側に「同点包含のON/OFF」と「昇順(下位枝)」の入力が要る。同点包含=`True`が既存5フィルタ、`False`が変わり身の現行挙動。手③で6段キー(同率全採用廃止)へ切り替えると変わり身も同じ層で同点が解決されるので、この拡張は手③で自然に吸収される。

## AsIs **v1.3** — 2026-08-17 20:20+09:00（手②c実装・手③準備A/B完了・準備C走行中）

| 項目 | 現物/実測 | 出典 |
|---|---|---|
| 手②b 四つ目／新四つ目 | 本番検証PASS: 4表count+md5がbaselineと完全一致(monthly 15977/c3331388・signals 333025/e03c0a2c・weights 25094/dab5148e・metrics 196/cda1b38a、20:11:45 JST) | cmd_4336 GATE CLEAR 19:48・掲示板blt_20260817_201205 |
| 手②c 変わり身 | 実装済み: `selection.py` `select_top_n_with_ties(scored, top_n, *, include_ties=True, ascending=False)`、`trend_reversal_filter.py` top枝=`include_ties=False`／bottom枝=`include_ties=False, ascending=True`。test_trend_reversal_filter+test_selection_deterministic 21 passed、等価性7/7 | commit `2f0b4f7a`(cmd_4337)。GATE前: cmd_4337は将軍のAC1テストパス誤記(不在ファイル指定)でfailed→回復cmd_4340も検証のみなのにtask_type=fullでcommit契約BLOCK→task_type=verificationで再配備中(20:16) |
| 手③準備A previous_tickers | 実装済み: `PipelineContext.previous_tickers`、`execute_pipeline(..., previous_tickers=None)`、`recalculate_fof.py`月初呼出しでprev_holding_signalを分解して注入。読み手blockなし=挙動不変 | commit `5d12c79f`(cmd_4338)。家老レーン検証中 |
| 手③準備B 6段キーcomparator | 実装済み(未配線): `selection.py` `SCORE_EPS=1e-9`・合成ε `abs(a-b) <= SCORE_EPS*max(abs(a),abs(b),1.0)`・`compare_candidates(a,b,*,price_data,target_date,previous_tickers)`・`select_top_n_deterministic(...)`。12Mは13観測以上時のみ(`_twelve_month_return`)。契約テスト`test_selection_deterministic.py` 7系統(将軍再実行7 passed 20:06) | commit `16f05e8f`(cmd_4339)。GATE CLEAR 20:05 |
| 手③準備C 期待差分 | cmd_4331の乾式スクリプトは一時実行で未保存(集計値のみ残存)。本番comparatorを全74 FoF子PF月次系列へread-only乾式適用しPF×月CSV+md集計を保存、cmd_4331集計(949月・PF別)と突合するcmd_4342を配備中 | cmd_4342 in_progress(tobisaru) |
| インフラ | run_tests.sh外部backend taskはcontract test未宣言だとBLOCK rc=2の二択構造→cmd_4336/4337でDIVERGENT。近接テスト自動探索の中間経路をcmd_4341で追加中(軍師提案) | cmd_4341 in_progress(saizo) |

**手③の残条件**: 準備A(cmd_4338)GATE CLEAR・準備C(cmd_4342)の期待差分ファイル・手②c(cmd_4340)GATE CLEAR。揃えば手③=各blockの`select_top_n_with_ties`呼出しを`select_top_n_deterministic`へ差し替える配線1か所の単一commit(殿合図)。

## AsIs **v1.4** — 2026-08-18 00:25+09:00（手③実装・本番live・full run404走行中）

| 項目 | 現物/実測 | 出典 |
|---|---|---|
| 手②c 変わり身 | GATE CLEAR(cmd_4340 20:35)。手②=全6フィルタの共通層集約完了 | commit `2f0b4f7a` |
| 手③準備A/B/C | 全てGATE CLEAR。準備C=本番comparator乾式で**959月**変化(cmd_4331集計949との差+10はcmd_4331が集計値のみ保存で月別旧新集合なしのため未確定。**cmd_4342 CSVを期待差分の正**とする将軍判断) | commit `5d12c79f`/`16f05e8f`/`b0e7e7c9`、`docs/research/cmd_4342_fof_tiebreak_expected_diff.csv`(8,570行) |
| **手③ 6段キー切替** | **実装完了・報告PASS**: 6ブロック7か所の呼出しを`select_top_n_deterministic`へ差替(bottom枝=score符号反転規則、cmd_4342スクリプト259行と同一)、既存テスト期待値を6段規則へ更新、関連テスト68件FAIL0/SKIP0、期待差分CSVとPF×月照合**不一致0件**。docstring修正(将軍doc lane) | commit `54e3e663`+`2f3e3c82`(cmd_4344)、origin/main `57127ffd`(同内容) |
| 本番配備 | Render deploy `dep-da1i16s9…`(23:54)は**GitHub本体障害**(githubstatus 13:40Z〜Partial System Outage: API degraded/Actions・Issues・PR major)でclone不能→build_failed。再deploy `dep-da1iacid0e5s73bdc3l0`(00:13 JST)が**live**(57127ffd)。家老がfull run404を実行・監視中 | Render API deploys / render logs build / githubstatus API |
| 手③合否(未) | (a)変化=cmd_4342 CSVとPF×月一致 (b)同一入力でfull 2回目md5一致 (c)標準PF24変化0 (d)full時間≤復帰点2倍。SIGNAL CHANGE ALERT 1回は受容済み | 家老レーン(run404完走後) |
| 戻し方 | `git revert 54e3e663 2f3e3c82`→push→deploy→full 1回でbaseline md5(monthly c3331388/signals e03c0a2c/weights dab5148e/metrics cda1b38a)へ戻る | rollback計画書§-1 |
| インフラ副産物 | cmd_4341 run_tests近接テスト(bce0cfaa)・cmd_4343 dashboard自動更新既定OFF(3ad81b23)・cmd_4345 gate exit75再試行/cmd_4346 precheck統合/cmd_4347 GATE-STALL検知(通知storm→将軍hotfix 53af18b5)/cmd_4348 全デーモン75分停止の偵察 =忍者実装済み・レビュー中 | 各cmd |

## AsIs **v1.5** — 2026-08-18 06:55+09:00（手③完了: 合否確定・本番収束実証・補正2本・oracle最終値）

| 項目 | 現物/実測 | 出典 |
|---|---|---|
| 本番 | **f519002b**(手③ 54e3e663+2f3e3c82 ／補正1 cmd_4349 a88f300f ／補正2 cmd_4351 f519002b)。Render live 02:11 JST。cron `dm-signal-sync-fof`(01:40 UTC)は同一経路(sync_fof→recalculate_history_fast L3_fof→_recalculate_fof_history→PipelineEngine→blocks→select_top_n_deterministic)、run409以降のcron初回=08-18 10:40 JST(変更0件を家老が確認予定) | Render API / sync_layers.py 300-320 / recalculate_fast.py 3824 |
| 合否(b) 収束 | **PASS**: run408(初回)→run409(2回目)で4業務表count/md5完全一致・signal_change 0(monthly 15977/93315437・signals 333025/61192e83・weights 22937/2e0c2a9c・metrics 196/6ee0bd4d)、標準PF同値 | 掲示板blt_20260818_023420 |
| 合否(c)(d) | (c)標準PF24のsignal変更0 PASS／(d)run409 527.8s=復帰点412sの1.28倍 PASS | 同上 |
| 合否(a) 期待差分 | 補正oracle(cmd_4350伝播版+cmd_4352期間換算)vs run409: **MATCHED 8,504／MISMATCH 9／MISSING 57**(観測可能の99.9%)。残9=GSシン加速R-常勝2012-05(1)・奥義-GS-加速D/R-常勝2013-06(2)・秘奥義-加速R-常勝2014-05〜2015-01(5、expected/actualが1か月ずれて連なる型)・秘奥義-追い風-鉄壁2016-06(1)=**oracle側の境界定義(depth3の月対応/伝播タイミング)、本番別要因0** | `docs/research/cmd_4352_fof_tiebreak_expected_diff_final.md`(DM-Signal repo 43f3a16b) |
| 補正1 cmd_4349 | 5選択ブロックが`list(context.current_tickers)`(set順)を渡していた=P6違反。6ブロックを`ordered_current_tickers`(component_order安定順)へ。全同値候補(2013-05/06 奥義2PF: 保有・リターン完全同一)の初回選択が決定的に | 掲示板blt_20260818_005951 |
| 補正2 cmd_4351 | 12M欠損時のpairwise stage-skipが比較器を非推移(朱雀>白虎(12M)・白虎>玄武(skip→CAGR)・玄武>朱雀(skip→CAGR)の循環)にし24順列で勝者が分散(GSシン加速R-常勝2012-08/09)。②③④のデータ欠損skipを候補集合単位へ→各段全順序。設計pitfall Cを『集合の全員が13観測以上の時のみ②』へ更新 | 掲示板blt_20260818_014407 |
| oracle補正 | cmd_4350=nested伝播(下位FoFの新6段結果を上位入力へ)、cmd_4352=lookback期間換算をdays-only config(days:10→max(days//21,1)=1月)で本番block同一に。cmd_4342の乾式は全階層固定+0月換算で不一致550→補正後9 | cmd_4350 2c5ce30d／cmd_4352 43f3a16b |
| 導入時の履歴組み替え(受容済み) | run404(手③初回)28,293行/46PF、run406(補正1初回)82/3PF、run408(補正2初回)222/4PF。以後の再実行は0 | 殿ntfy 00:26/01:36/02:23 |
| 手④ | GS fast path(run_077/l1)のparity未着手 | — |

**設計への反映(ToBe v0.3→v0.4相当・本文は不変で注釈)**: (i)②③④の欠損skipは候補集合単位(全順序保証) (ii)6段全同値の最終決着はcomponent_order(pipeline_configの記載順)であってset順・ID順ではない (iii)期待差分oracleはnested伝播+本番同一の期間換算が必須。

## AsIs **v1.7** — 2026-08-18 09:05+09:00（「完全解決」への残件表）

| 残件 | 状態 | 担当/出典 |
|---|---|---|
| 手④ GS高速版(scripts/analysis/grid_search/run_077_*.py 7本 + l1 fast path)の子PF選択を`select_top_n_deterministic`へ統一・parity赤→緑 | cmd_4353初回(影丸)=adapter実装+contract 3/3 PASS+本番pipeline無変更(f70475c8)・legacy108セル vs production36セル=72差分(赤取得)、**AC2/AC3は環境境界でFAIL**(GS scripts腐敗: bunshin import欠落／kasoku module欠落／kawarimi・nukimi・oikaze DB rows 0／yotsume引数衝突、run_tests scope未mapping)。将軍08:00下知: (a)GS 7本起動回復→(b)parity oracleをrun409 readonly snapshotへ→(c)gs-bench-gate。**再配備中(08:19 assigned)** | 家老 |
| 残9 oracle境界(depth3で1か月ずれ型) | **完了(cmd_4354・疾風 08:21)**: 残9全件=oracle側のmonth_mapping差(oracle target_dateをdecision_monthの最初のproduction signal日へ整合)。修正版oracle vs run409 全8,570行=**MATCHED 8,513／MISMATCH 0／MISSING 57(未到来)**。本番側要因0・本番書込み0。DM commit 4a486bcb／infra 157f00df(PI-P09更新)。成果物 `docs/research/cmd_4354_fof_oracle_residual9_20260818.md` → **合否(a)=100%(観測可能全件)・手③CLOSE** | 家老レビュー→GATE |
| cron `dm-signal-sync-fof` run409以降初回=08-18 10:40 JST の変更0確認 | 家老checkpoint継続 | 家老 |
| gist/CI | GitHub回復(07:03 `gh api commits/main`=ad167c50応答)。本版でgist再同期 | 将軍 |

**完全解決の定義**: 上表4行が全て閉じ、設計書手順表①〜④が全て「完了」であること。本番pipelineは手③で確定済み(f519002b)であり、手④は本番不変(GS研究用のみ)。

## ToBe **v0.3** — 2026-08-17 13:05+09:00（殿チャット12:51-12:59で確定した6段キー。実装は殿合図まで）

### 方針: 出力を凍結するのではなく、関数を決定的にする
- 「同一入力→同一出力」(復帰点契約)を、**入力の最下位ビットの揺れ**にも耐える形へ拡張する。手段はledger(出力凍結)ではなく、**比較そのものに同値帯εと根拠あるtie-breakを持たせる**。
- **①は「そのPFのpipeline_configが定める選択スコア」であり、加速(1M/3M比)はGSシン加速R系の一例にすぎない**(殿13:08「たまたま加速で著名なだけで他のどのパターンでも出る」)。同値問題は選択スコアの種類に依らず、同じ保有履歴を持つ子PF同士なら**どの選択フィルタでも**起きる。∴ tie-break(②〜⑥)は特定フィルタの中ではなく、**FoFの子PF選択(top_n採用)を行う共通層**に置き、全フィルタ(Momentum/MomentumAcceleration/その他)で同じ規則が効くようにする。
- ②以降は時間軸が中期→長期→痛み→慣性と並ぶ: 中期モメンタム(12M)→長期実績(設定来CAGR)→MaxDD→現保有維持。tie-breakは後付け規則ではなく「強さの定義の解像度を一段ずつ下げる」形。

### 比較の6段キー(確定案・殿12:59「モメンタムを取り入れたい。12ヶ月トータルリターン→設定来CAGR→以下同じ」)
| 段 | キー | 同値帯 | 根拠 |
|---|---|---|---|
| ① | **そのPFのpipeline_configが定める選択スコア**(config依存。例: GSシン加速R系はMomentumAcceleration ratio=1M/3M、他のFoFはそれぞれの選択フィルタ) | ε(相対1e-9級) | 現行の設計思想をそのまま主キーに。cmd_4330実測(加速R系の例): 同値側の差1e-16〜1e-14、非同値側≥1e-1 |
| ② | **12ヶ月トータルリターン**(=同一期間ならCAGRと同順位)。**両者とも12ヶ月以上の履歴がある時だけ**使う。どちらかが満たなければこのキーはスキップ | ε | 標準的な中期モメンタム窓。12M vs 11Mのような不公平比較をしない |
| ③ | **設定来(inception以来)CAGR**(殿裁定12:51) | ε | 長期実績。全期間なので必ず比較可能。同値=設定来ずっと同じ履歴のみ |
| ④ | **MaxDD が小さい方** | ε | 同じ強さなら痛みが少ない方(=Calmar)。履歴が完全同一でない限り決着 |
| ⑤ | **現保有を維持**(前月に持っていた方) | — | 区別不能なら動かない。取引コスト0・履歴の連続性 |
| ⑥ | 初月(前保有なし)のみ: **設定来が早い方**(実績が長い方) | — | ⑤が効かない唯一の場面の最終規則。ID順は使わない |

- 全キーは **point-in-time**(その月末まで・未来を見ない)。as-ofは主スコアと同じ。
- 実装位置: 特定フィルタ(momentum_acceleration_filter.py)ではなく、**選択結果をtop_nへ絞る共通層**(全選択フィルタが通る箇所)。フィルタごとに二次keyを持たせない(重複実装と不整合の元)。
- **同値=同率全採用ではなく、次のキーで1体に絞る**(top_n=1の契約を守る。現行の「同率を全部selected」は廃止)。
- **価格は丸めない・取込みは触らない**(殿裁定12:51「シンプルに比較側で十分」)。εは比較値側にだけ置く。

### 期待効果と副作用
- 効果: 価格の浮動小数点ノイズで確定履歴が動かなくなる。復帰点の「full 1回で収束」が入力ノイズにも成立。ledgerなしで整合が保てる。
- 副作用: 導入時に一度、確定履歴が決定的に組み替わる(alertが1回出る)。以後は安定。
- 注意: εを大きくしすぎるとCAGRが実質主キーになりFoFの設計思想(直近の強さ)を変える。ε=ノイズを吸う最小に留め、cmd_4330 AC2の候補間差分布で決める。

### 副作用と対策・ロールバック契約 — 2026-08-17 15:15+09:00（殿14:55「副作用は起きないか？ロールバック地点と復旧方法は明確か？」／14:59「計算方法が違う。うまくいかなければrollback計画書のやり方でいく」／15:00「副作用は設計書に記載し、先に対策を明確に」）

**原理**: 手①②は「配線を1本にまとめる」だけで**副作用ゼロを設計目標**にし、手③で**1回だけ意図して**計算方法を切り替える。副作用は「起きない」ではなく「起きる場所と回数を固定し、検知と戻し方を先に決める」。

| 手 | 内容 | 起こり得る副作用 | 対策(事前) | 検知(二値) | 戻し方 |
|---|---|---|---|---|---|
| ① | 共通選択関数を新設し、加速フィルタ1本だけをそこへ差替(中身は現行=同率全採用のまま) | 差替ミスで採用子PFが変わる／multi-view・trendの前に触らないので意味変化なし | 関数の入出力を「候補+score→採用集合」に固定。現行blockのsort・cutoff・`>=`全採用をそのまま移す。関数単体テストで現行blockと同一出力を全FoF×全月で突合(cmd_4331の乾式frameを再利用) | push→deploy→full 1回→**4表md5がrollback計画書§-1 15:10 baselineと完全一致** | `git revert`→push→deploy→full 1回→md5一致。DB PITR不要 |
| ② | 残り5フィルタを1体ずつ差替 | **最大の落とし穴**: 四つ目/新四つ目(4視点→union/vote)・変わり身(top+bottom枝)は「並べて取る」が視点/枝ごとに走る。共通関数を「合成後」に当てると意味が変わる | 各フィルタで「視点/枝ごとに共通関数→既存の合成」を明示(cmd_4331 AC1の行番号が対象)。1体1層・都度full | 同上md5一致(各手) | 同上(その手だけrevert) |
| ③ | 共通関数の中身を6段キー(ε相対1e-9→12M→設定来CAGR→MaxDD→現保有→設定来早い方、同率全採用廃止)へ切替 | **意図した副作用**: FoF 74PFの確定履歴が乾式949月(scalar 837月)組み替わる→SIGNAL CHANGE ALERT 1回、メンバー画面の過去保有・monthly_returns・signals・fof_component_weights・metricsが再生成。標準PF24は変化0(near-tie 0)。no-block 17PFは影響なし。12M/CAGR/MaxDDの計算追加でfull時間が伸びる可能性 | 殿12:51受容済み(1回組み替え・メンバー納得)。切替は**単一commit・単一flag相当**にし部分適用を作らない。事前にcmd_4331の乾式結果(PF別変化月)を「期待差分」として保存 | (a)変化件数=乾式949月と一致(PF別) (b)同一入力でfull 2回目md5一致(収束) (c)標準PF変化0 (d)full所要時間が復帰点の2倍以内 | `git revert`→push→deploy→full 1回→md5がbaselineへ戻る(決定的関数なので戻りも決定的)。SIGNAL CHANGE ALERTがもう1回出るのは受容 |
| ④ | GS高速版(run_077/l1 fast path)を共通関数へ | ③〜④の間はGS結果と本番が不一致(GSは研究用・本番出力ではない) | ④まで一気通貫でなく、③後にGS parityテストを先に赤にしてから④で緑にする | parityテストPASS | revert |
| 共通 | — | 取込み(prices)不変・DBスキーマ不変・frontend不変・API契約不変。cron sync-fofは共通関数を経由するので手③後は新規則で動く | 触らない範囲を明記(スコープ外) | `git diff --stat -- frontend backend/app/etl` = 0 | — |

**ロールバック地点と復旧(正本=rollback計画書§-1・15:10版)**: 地点=各手のpush直前origin/main(手①前=backend `46a1f213`/frontend `55b81b43`/DB run400世代 baseline md5 monthly `c3331388`・signals `e03c0a2c`・weights `dab5148e`・metrics `cda1b38a`)。復旧=コードrevert→push→deploy→full 1回→baseline SQLで一致。新規コード禁止・PITR不要(派生表はfullが全再生成)。実行者は将軍単独、家老・忍者は止める。

### 実装前の前提条件とpitfall — 2026-08-17 15:25+09:00（殿15:06「他のコーディングLLMの立場で俯瞰。家老にも同ポジションで。主導権は将軍、家老の意見はコードと理論で将軍が確認。シンプルが一番、過剰な防御案は拒否」）

将軍がコード現物で確認した事実(file:line)。家老の俯瞰(掲示板 blt_20260817_151253)は5点とも将軍が現物で照合し、③は事実で反証(下記)。

| # | 前提条件(確定事実) | 現物 | 実装への帰結 |
|---|---|---|---|
| P1 | **FoFと標準PFは別実装**。FoF=block class群(`engine.execute_pipeline`)を月初リバランス日のみ実行。標準PF=純関数executor(Momentum/MAF/Reversal/AbsMom/SafeHavenのみ対応)。executorにもMAFのsort+`>=cutoff`全採用が複製されている | `jobs/recalculate_fof.py:1371`／`jobs/recalculate_fast.py:2001`／`services/pipeline/executor.py:12-17,148-150` | 共通関数はblock class側に置く。**executor(標準PF)は触らない**＝標準PF変化0が構造で保証(近似同値0/4,178)。あえて共通化しない |
| P2 | block class経路の本番呼出は`recalculate_fof.py:1371`の1か所。他は`scripts/`のGS・parity・oneshot 10か所 | `rg "execute_pipeline\("` | `execute_pipeline`へ**任意引数1本**(`previous_tickers`)を足しても既存呼出は無影響 |
| P3 | **⑤現保有維持の入力**はcontextに無い(`PipelineContext`=current_tickers/component_order/price_data/momentum_data)。前月保有は日次ループの`prev_holding_signal`にカンマ区切り子PF ID文字列で存在 | `services/pipeline/base.py:106-115`／`recalculate_fof.py:1321,1393-1406`／`engine.py:184`(signal=`","`join) | `execute_pipeline(previous_tickers=set(prev_holding_signal.split(",")))`→`context.previous_tickers`。DB追加読込なし |
| P4 | **②③④⑥の材料**は注入済み: `ComponentPriceBlock`が子PF`cumulative_return`を`close`列DataFrame(index=月末)で`context.price_data`へ | `component_price.py:19-27` | 12M=`close[t]/close[t-12]`(13観測)、設定来CAGR=first index〜t、MaxDD=`close`水準の高値更新からの下落率、⑥=first index。DBアクセス不要 |
| P5 | **キャッシュ窓は設定来を含む**(家老③「DB fallback既定730日で設定来を保証しない」は**反証**): FoF再計算は常に`2000-01-01`起点の全期間(fullも部分modeも`fof_full_start=date(2000,1,1)`、cron `POST /admin/sync-fof`のstart_date既定`2000-01-01`)。`global_component_cache`はstart_date−730日〜end_dateを一括ロードし全候補cache時はDB fallbackを読まない。730日fallbackはcache欠落時のみ | `recalculate_fast.py:3823`／`api/etl_trigger.py:684`／`jobs/constants.py:10,30`／`recalculate_fof.py:874-881`／`component_price.py:33-41` | 設定来キーはcacheから計算可。**将来start_dateを遅らせる呼出を作らない**(作れば設定来キーが窓依存になる)＝実装ではなく契約として明記 |
| P6 | 既存のtie-break痕跡は`trend_reversal_filter.py:78-80`の`component_order`安定ソートのみ(順序安定化であり同値解決ではない) | `base.py:110`／`engine.py:92` | 共通関数の入力順はこの並びを保つ(変えると変わり身の結果が動く)。⑥は配列順ではなく設定来(first index)。ID/配列順は一度も使わない |
| P7 | 選択結果は`intermediate_results[block_id]={selected, all_scores}`と`context.momentum_data`(→`signals.momentum_data`列)へ流れる | `momentum_acceleration_filter.py:139-150` | 出力の形は変えない(表示契約) |

| # | pitfall(実装LLMが踏む順) | 対策(シンプル側) |
|---|---|---|
| A | **相対εは0近傍で効かない**(0と1e-12は相対差1)。乾式も相対のみ(floor 1e-300)。家老④と一致 | 判定=`abs(a-b) <= 1e-9 * max(abs(a), abs(b), 1.0)`(絶対+相対の合成・定数1つ)。加速R系実測(同値側≤1e-14／非同値側≥1e-1)を両方満たす |
| B | ratio scoreの分母ガード`abs(den)<1e-6`で`num/1e-6`(±1e6級)に張り付く | 触らない。合成εの相対項で同値判定は破綻しない |
| C | ②12Mは「両者13観測以上」の時のみ(乾式と同じ・skip 264件)。片方不足を負けにすると新設PFが構造的に選ばれない。家老③後半(12/13の表記揺れ)→**13観測(12ヶ月リターン1本が両者で計算できる)に固定** | 関数内で明示 |
| D | multi-view(4視点→union/vote)・変わり身(top+bottom枝)は**視点/枝ごと**に共通関数を当てて既存の合成を保つ。合成後に当てると意味が変わる。家老⑤と一致 | `multi_view_momentum_filter.py:203-210`／`trend_reversal_filter.py:153-169`の各枝で呼ぶ |
| E | 既存テストは同率全採用を期待(`test_weighted_multi_view_momentum_filter.py:134-163` top_n=1・3者同値→3者各1/3 等)。家老⑤と一致 | 手①②では変えない(挙動不変)。手③で期待値を6段規則へ更新 |
| F | 手①②の合否=full 1回で4表md5一致(15:10 baseline SQL)。FoFは月初のみ再計算なので差替ミスは月初1行から連鎖し必ずmd5に出る | 追加観測なし |
| G | nested FoF: 依存順は既存(`recalculate_fast.py:169`)。共通関数は親子で同じ関数が走るだけ | 順序制約は増えない |

**設計判断(推薦・シンプル)**: 新規ファイル1本 `backend/app/services/pipeline/selection.py`(`select_top_n(scored, top_n, *, previous, price_data, target_date)`・εは定数)＋`execute_pipeline`引数1本＋各blockの`sort…selected=`数行を関数呼出しへ置換。executor.py・取込み・DB・frontend・GS(手④まで)は不変。新gate/新hook/観測拡張/新fixtureなし。


### 手②c 変わり身の配線 — 2026-08-17 19:30+09:00（殿19:22「artifactと設計書も更新。そのうえで進めてよい」）

事実→制約→判断→効果:
- 事実: 変わり身の選択部は切り取り型(AsIs v1.2)。設計書v0.3の手②表「残り5フィルタを1体ずつ差替」はこの違いを見落としていた。
- 制約: 手①②は挙動不変が目標。`select_top_n_with_ties`をそのまま当てると同点時に変わり身の採用数が変わる。
- 判断: 手②cで共通関数に引数2つを足す — `include_ties: bool`(同点包含。既定True=既存5フィルタ不変)と`ascending: bool`(下位枝用。既定False)。変わり身のtop枝=`include_ties=False, ascending=False`、bottom枝=`include_ties=False, ascending=True`。既存5フィルタの呼出しは引数省略で不変。合否は既存と同じ「full 1回で4表md5がbaseline一致」。
- 効果: 全6フィルタが1つの選択層を通る。手③はこの層の中身を6段キーへ切り替えるだけで全フィルタに効く。`include_ties`は手③で同率全採用が廃止されるため役目を終える(6段キーが同点を解決)。

| 手 | 内容 | 検知(二値) | 戻し方 |
|---|---|---|---|
| ②c | `selection.py`へ`include_ties`／`ascending`引数追加(既定値=現行挙動)＋変わり身の2枝を配線 | 既存test_trend_reversal_filter FAIL0/SKIP0＋full 1回md5一致 | その手だけrevert |

### ledgerとの比較(殿12:39「ledgerより今回の方向性の方が筋が良いと思う。どう思う？」→ 同意)
| 観点 | ledger(出力凍結) | 同値帯ε+tie-break(関数の決定化) |
|---|---|---|
| 何を直すか | 症状(確定月が動く)を止める | 原因(比較がノイズ依存)を消す |
| fullとの関係 | fullが再生成しない行を作る(08-16原則と衝突)、バックフィル運用が要る | fullの内側で完結、再生成で同じ答え |
| 復旧・切替耐性 | PITR切替で消える(今回0行)、再構築で正しい再計算を止めた前科 | 何もしなくても同じ |
| 説明可能性 | 「その時そう決めた」を保存 | 「なぜその子か」を規則で説明できる |
| 残る用途 | 監査ログとしてはsignal_change_logで足りる | — |

## 未決（殿裁定待ち・cmd_4330の結果後）
1. ~~比較キーの正体と現行の同値時挙動~~ → **確定(cmd_4330)**: ratio score(1M/3M)、同率は全採用(2体保有化)、二次keyなし。
2. ~~εの値~~ → **裁定(殿12:51)**: 相対1e-9級の同値帯で可(比較値に帯・価格は丸めない)。
3. ~~CAGRの定義~~ → **裁定(殿12:51)**: **inception以来**のCAGR(point-in-time=その月末まで)。
4. ~~最終キー~~ → **裁定(殿12:59)**: 12ヶ月トータルリターン→設定来CAGR→MaxDD小→現保有維持→初月は設定来が早い方(6段キー・ToBe v0.3)。
5. ~~価格取込み側~~ → **裁定(殿12:51)**: シンプルに比較側のみ。取込みは触らない。
6. ~~導入時の1回組み替え~~ → **裁定(殿12:51)**: 受容。メンバーも株価自体が遡及で変動することに納得済み。

## 裁定の因果連鎖 — 2026-08-17 12:45+09:00

| # | 殿の意見(時刻) | 事実 | 制約 | 判断 | 効果 | Obsidian |
|---|---|---|---|---|---|---|
| 1 | 浮動小数点程度の価格差は実際にあり、その影響で保有シグナルが変わる(12:35) | cmd_4329: 相対差1e-7級で6,477件反転 | 外部APIに履歴版なし・取込みは同一PK上書き | 事実として受容し、対処は関数側 | 現実に合った前提 | `[[cmd_4329]] -> [[価格差はfloatノイズ級]]` |
| 2 | 丸め=何桁？丸めるとtieが発生する(12:35) | 丸め境界の両側に必ず値が落ちる | 「変わらない桁」は原理的に存在しない | 価格を丸めず、比較値に同値帯εを置く | ノイズを吸いつつ情報を削らない | `[[丸めはtieを作る]] -> [[同値帯ε]]` |
| 3 | tie-breakには根拠が要る。PF順は理屈でない。強いもの=過去CAGRが高い方(12:35) | 子PFは保有重複月に完全同値 | 並び順/IDは並べ替えで整合が壊れる | 2段目=point-in-time共通期間CAGR、3段目=現保有維持 | 説明可能・決定的 | `[[殿意見_強いもの_過去CAGR_20260817]] -> [[3段キー]]` |
| 5 | 2はε案でよい／3のCAGRは設定来／5は比較側で十分／6は受容。メンバーも株価の遡及変動に納得(12:51) | cmd_4330で比較キー・同値差が確定 | 二重対策は複雑さを増やす | ε=相対1e-9級、CAGR=設定来、取込みは触らない、導入時1回の組み替えは受容 | 実装が比較関数1か所で閉じる | `[[殿裁定_未決2356_20260817]]` |
| 6 | せっかくなのでモメンタムを取り入れたい。12ヶ月トータルリターン(CAGRでも同じ)→設定来CAGR→以下同じ(12:59) | 主スコアが1M/3Mの加速 | tie-breakも同じ思想で並べるべき。12M未満の子は比較不能 | ②12M(両者12M以上ある時のみ)を挿入、時間軸短→長で6段 | 後付け規則ではなく思想の解像度を下げる形。IDに一度も頼らない | `[[殿裁定_12Mモメンタム挿入_20260817]] -> [[6段キー]]` |
| 7 | 現行主スコアはたまたま加速で著名なだけで、他のどのパターンでも出る。加速がデフォルトに見える表現は良くない(13:08) | 同値問題は選択スコアの種類に依らず起きる(同じ保有履歴の子PF同士) | 特定フィルタに二次keyを埋めると他フィルタで再発・不整合 | ①=config依存の選択スコアと一般化、tie-breakは共通層へ | 全FoF・全フィルタで同じ決定性 | `[[殿指摘_加速はデフォルトでない_20260817]] -> [[tie-breakは共通層]]` |
| 4 | 以前はledgerを設定したが今回の方向性の方が筋が良い(12:39) | ledgerは出力凍結・再生成外・PITRで消失・前科あり | 08-16原則「fullが再生成しない行を作らない」 | ledgerではなく関数の決定化 | 復帰点契約と整合、ledger廃止方向と一致 | `[[殿意見_ledgerより関数決定化_20260817]] -> [[ledger廃止方向]]` |

## チャット記録（殿×将軍・要旨）— 2026-08-17 12:45+09:00
- 10:47 殿ntfy SIGNAL CHANGE ALERT 6,477件 → 将軍: sync-fof cron停止+full run400(誤診) → 11:03 訂正: 真因はsync-pricesの全履歴upsert、cron再開
- 11:33 殿「まず本当に価格が変わったか、cronとfullの差分、どのPFがどう変わり連鎖したか、特定PF特定タイミングか」→ cmd_4329
- 11:37 殿「price historyはStockData/EODHD等でも調べられるか調査」→ cmd_4329 AC1へ追加
- 12:13 cmd_4329結果: ノイズ級の価格差で広域反転。将軍: tie-breakのノイズ依存を示唆 → cmd_4330(機構偵察)起票
- 12:35 殿「浮動小数点程度の価格差は実際にあり保有シグナルが変わる。丸め=何桁？丸めるとtieが発生。tie-breakには根拠が要る。PF順は理屈でない。強いもの=過去CAGRが高い方はどうか。決定ではなくチャット」
- 12:37 将軍: 丸めは価格でなく比較値に同値帯ε／FoFだけ反転する理由=子PFの完全同値／CAGR tie-breakに賛成+条件3つ(point-in-time・共通期間・最終キー=現保有維持)／εは最小に
- 12:39 殿「artifactにまとめよ。今は情報待ち。ledgerより今回の方向性の方が筋が良い。どう思う？」→ 本書+同意(上表)+artifact 58f94a75
- 12:51 殿「2はその案でいい。3のCAGRはinception以来。4の最終キーに他のアイデアは？5はシンプルに比較側で十分。6は受容。メンバーも株価の遡及変動には納得」→ 未決2/3/5/6裁定、4は議論継続
- 12:55 将軍: 最終キー候補6案(現保有維持/長い実績/低DD/単純さ/等分/ID)を比較、推薦=MaxDD小→現保有維持→初月は設定来早い方
- 12:59 殿「せっかくなのでモメンタムを取り入れたい。過去12ヶ月のトータルリターン(CAGRでも同じ)→設定来CAGR→以下同じ」→ 将軍賛成+詰め3点(12M未満は両者12M以上の時のみ／各キーにε／point-in-time)→6段キー確定案
- 13:01 殿「まず設計書とartifactに落とそう」→ ToBe v0.3
- 13:08 殿「現行主スコアはたまたま加速で著名なだけで他のどのパターンでも出る。加速がデフォルトに見える表現は良くない」→ ①を『pipeline_configが定める選択スコア(config依存)』へ一般化、tie-breakは全フィルタ共通層に置くと明記
- 12:43 cmd_4330 GATE CLEAR → AsIs v1.0(ratio score/同率全採用/二次keyなし、2015-04 exact tie両選択・2016-12 1位入替の実測)、ToBe v0.2(ε=相対1e-9級提案)
- 16:44 殿「今デプロイされた。もう起票を始めよう」→ 手①cmd_4334(e44a7bb7)・手②a cmd_4335(783668bb・GATE CLEAR 18:57)。18:56 殿「進めてくれ」→ 手②b cmd_4336(ff77e7eb)。19:22 殿「もう少しわかりやすく」→変わり身の別パターンを説明→「artifactと設計書も更新。そのうえで進めてよい」→ AsIs v1.2＋手②c追記→cmd_4337起票
- 19:36 殿「準備は先に始めていいのでは？」→ 手③準備A cmd_4338(5d12c79f)・準備B cmd_4339(16f05e8f・GATE CLEAR 20:05)。19:46 cmd_4337 failed(将軍AC1誤記→LS-A09(37))→回復cmd_4340→commit契約BLOCK→verification再配備。19:55 殿「dirtyなせいでgate clearやpushが遅れているならインフラバグだ。迂回は負の複利」→ 軍師提案run_tests近接探索=cmd_4341。20:05 準備C cmd_4342起票。20:11 手②b本番PASS。20:15 殿「リアルな進捗」→20:19「artifactと設計書を更新して」→ AsIs v1.3
- 22:03 殿「進めてほしい」→手③cmd_4344起票→22:21配備→23:20家老「docstring旧契約残存」→将軍doc lane 2f3e3c82→push→23:54 Render build_failed(GitHub障害)→将軍が真因訂正(credential切断ではない)→00:13 再deploy live→full run404。23:54 cmd_4347のGATE-STALL検知が履歴gate全件通知storm→将軍hotfix 53af18b5。00:20 殿「いまクリアされても今より強くてニューゲームできるようにせよ」→本版
- 08-18 00:35〜02:55: run404 (a)550不一致→原因=oracleのnested伝播欠落(cmd_4350) ／ run405 (b)FAIL 2PF×21日→全同値候補のset順依存(cmd_4349) ／ run406 82件→GSシン加速R-常勝は非推移(12M欠損pairwise skip)→cmd_4351 ／ run408 222件=全順序化の1回組み替え→run409で0件=(b)PASS ／ oracle期間換算差122件→cmd_4352→(a)8,504/9/57。殿裁定00:45「GitHub不安定の間は安易なrevert/deploy禁止」、殿01:02承認、殿06:46「cronも対応しているか」→同一経路を確認
- 13:04-13:23 cmd_4331起票→DOC_LANE_ROUTING偽陽性BLOCK→殿13:19「偽陽性は即時根治」→根治(caac794c)→再委任。13:55 GATE CLEAR → AsIs v1.1(全74 FoF棚卸し・共通helper不在・標準PF near-tie 0・6段乾式949月変化)。14:45 殿「まずはartifact,設計書、gistをアップデート」→ 本版

## 注釈 — 2026-08-17 12:45+09:00
- AsIs v1.7(08-18 09:05)=残9→MISMATCH 0(cmd_4354)で(a)100%・手③CLOSE。手④はGS環境腐敗が露呈しcmd_4353再配備中。
- AsIs v1.6(08-18 07:15)=GitHub回復・手④cmd_4353委任・完全解決の残件表(手④/残9 oracle/cron10:40/gist)。本番不変。
- AsIs v0.9はcmd_4330で機構が確定したらv1.0へ。ToBe v0.1はε・比較キー・CAGR定義が決まったらv0.2へ。
- AsIs v1.1(14:50)=cmd_4331の全FoF棚卸し・乾式適用。ToBe v0.3は不変(共通選択層の要請がAsIsで裏付けられた)。実装は殿合図で1体1層。
- AsIs v1.5(08-18 06:55)=手③完了。(b)(c)(d)PASS・(a)99.9%(残9=oracle境界)。補正1(cmd_4349 component_order)・補正2(cmd_4351 全順序化)・oracle補正(4350/4352)。本番f519002b。手④未着手。
- AsIs v1.4(08-18 00:25)=手③実装済み(54e3e663/2f3e3c82)・本番live 00:13・full run404走行中・合否(a)-(d)待ち。手④(GS)は未着手。
- AsIs v1.3(20:20)=手②c実装(2f0b4f7a)・準備A(5d12c79f)・準備B(16f05e8f GATE CLEAR)・準備C(cmd_4342走行)。ToBe不変。
- AsIs v1.2(19:30)=手①②a②b実装済み＋変わり身が切り取り型である事実。ToBe v0.3に手②c(共通関数へ引数2つ・変わり身配線)を追記。6段キー本体は不変。
