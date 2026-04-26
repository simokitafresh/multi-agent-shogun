## §29. 金融ML知識辞書 拡充 (cmd_1636-1653, cmd_1713, 2026-04-03追記)

前処理研究(§28)の文献サーベイ30+論文の知見が辞書に未記録だったことを契機に、一次知識層の大規模拡充を3波で実施。
guide.mdに純度ルール（一次知識層汚染防止）を追加後、全忍者6名並列投入×3波。

| Wave | cmd | エントリ数 | 領域 |
|------|-----|----------|------|
| 1 | cmd_1636-1641 | 25件 | トレンド推定(L1TF/Kalman/FDA/AdaptiveKalman)、エントロピー(PE/Jump/Shannon/Transfer)、信号分解(SSA/VMD/SG/CF)、適応的(DML/GOC/BBT/SlowMom+CPD)、リスク(JumpModel/VolScale/MedianMom/NetworkMom)、メタ知見(S02-S05/V04) |
| 2 | cmd_1642-1647 | 18件 | モメンタム正典(TSMOM/XSMOM/DualMom)、PF構築(MVO/Ward/RiskParity/BL/MaxDiv/Kelly)、ボラティリティ(GARCH/CVaR/EWMA)、ML基盤(Bootstrap/FeatImp/SeqBoot)。**cmd_1643(Crash/LifeCycle/RegimeSw)ファイル未作成** |
| 3 | cmd_1648-1653 | 18件 | cmd_1643穴埋め(M40/M41/M54)、資産価格(CAPM/FF3/Carhart/FF5/APT)、時系列(ARIMA/VAR/Cointegration)、統計検定(ADF/KPSS/Ljung-Box/Jarque-Bera/Granger) 、マイクロストラクチャー(Amihud/VPIN) |

**累計61エントリ**(methods/47 + validation/8 + portfolio/6 + sources/5 + pitfalls/3)。純度検証PASS（プロジェクト固有データ混入0件）。

### 2026-04-03 追加

| ID | エントリ | 概要 | ファイル |
|----|---------|------|---------|
| M17 | FLAIR (Factored Level And Interleaved Ridge) | `Level × Shape` 分解で周期構造を固定し、圧縮した `Level` のみを Ridge 予測する単一方程式型予測手法。一次知識層と DM-Signal 解釈層を分離して追加 | `docs/research/knowledge-base/methods/m17_flair.md` / `docs/research/knowledge-base/dm-signal/flair-interpretation.md` |

残課題 → `docs/research/research-todo.md`

## §29. Standard PF FDA Smoothing研究 (cmd_1666)
<!-- last_updated: 2026-04-01 -->

FDA(Functional Data Analysis) B-spline smoothingの5PFリトマス紙検証。Boubaker et al.(2021) FRL準拠。

| 条件 | K={4,8,16,32} × λ={0,1e-4,1e-2,1} = 16条件 × 5PF = 80件walkforward |
|------|------|
| 実装 | `scripts/analysis/standard_pf_preprocessing/fda_smoothing_study.py` (790行) |
| 結果 | `outputs/analysis/standard_pf_preprocessing/fda_smoothing_results.yaml` |

**DM3リトマス結果** (baseline: CAGR=0.109, Sharpe=0.456, MaxDD=-0.788):
- Best性能(K=32,λ=0): CAGR+232%, Sharpe+88%, MaxDD+31% — **ただしMatch49.5%(シグナル大幅乖離)**
- バランス(K=8,λ=0.01): CAGR+158%, Match41%
- 高Match(K=4,λ=0): CAGR+49%, Sharpe+23%, Match50.8%

**知見**: K増大は性能向上とMatch率低下のトレードオフ。DM7+のみK=32でMatch98.4%と例外的高整合。PFごとにK感度が大きく異なり一律パラメータ選択は不適。OOS検証(cmd_1660)で判定完了 → 下記§30参照。

## §30. EMA/L1 OOS検証 — overfit定量判定 (cmd_1660)
<!-- last_updated: 2026-04-01 -->

EMA平滑化(cmd_1632)とL1 Trend Filter(cmd_1633)のパラメータ選択がoverfitか本物かを2段階検証。

| Stage | 手法 | EMA結果 | L1結果 |
|-------|------|---------|--------|
| Stage1 IS/OOS split | 65PF×5params。劣化率<30%=ROBUST | universal span=5 **ROBUST**(median deg=-3.6%) | universal lambda=1 **ROBUST**(median deg=-7.7%) |
| Stage1 分布 | OVERFIT/SUSPECT/ROBUST | 4/18/43 | 7/14/44 |
| Stage2 PBO(CSCV 70組合せ) | Probability of Backtest Overfitting | **PBO=0.71 OVERFIT** | **PBO=0.54 OVERFIT** |
| DM3リトマス紙 | Stage1+Stage2 | EMA PBO=0.26 **ROBUST**(span=42, IS Sharpe=0.66→OOS=0.67) | L1 PBO=0.00 **ROBUST**(lambda=1000, IS=1.01→OOS=1.23) |

**結論**: 全体PFレベルではパラメータ選択にoverfit傾向あり(PBO>0.5)。ただしDM3は例外的にROBUST。assumption_invalidation: cmd_1632/1633の「overfit不明」前提を解消。

**性能知見**: L1 cvxpy計算で(ticker,lambda)キャッシュ適用 → 650→65回に削減、実行時間4h→1h(10倍高速化)。LC登録推奨。

→ `queue/reports/saizo_report_cmd_1660.yaml` | `outputs/analysis/standard_pf_preprocessing/oos_verification_results.yaml`

**研究実装教訓(§28-30統合)**: L532(gate/return-level照合)、L533(PE m=5閾値未到達)、L534(cvxpy cache 10x)、L535(cmd間前処理不一致)、L537(engine import必須)、L538/L539(ネスト深度増幅)、L540(fn cache id問題)、L541(depth_summary)、L542(用語テスト固定)、L543(rolling cumsum 50x)、L548(bulk metrics RFはPFごと月次軸)、L550(batch parityでbenchmark共通仮定禁止) — 全て§28-30の研究結果行に内包済み。詳細→projects/dm-signal/lessons.yaml

## §31. ファミリー別ALM + 5番目ファミリー候補 (cmd_1741)
<!-- last_updated: 2026-04-05 -->

absolute_assetでファミリー分類(DM2=LQD/DM3=TMF/DM6=^VIX/DM7+=SPXL)し、Max Run-up目的関数でALM実行。理論的低相関(駆動因子独立性)+危機時相関も分析。

**top候補: DM3** (alm_DM3_top5_win12m__max_run_up)。avg_corr_canonical=0.494(4ファミリー中最低=最分散)。inflation_2022=-0.089(負相関)。

→ `outputs/analysis/alm_research/cmd_1741_family5_analysis.yaml` | `cmd_1741_correlation_matrix.csv` | `cmd_1741_crisis_correlation.csv`
- L554: family ALM研究はmetricsと相関をベクトル化必須(cmd_1741)。L552/L553はinfra L439/L440と重複→削除
- L563: DNA制約(domain knowledge)は1M-12Mフルセットより高いIS max_run_upを3/4ファミリーで達成する（cmd_1759）

## §32. ALM L0×忍法7種 + 既存シン忍法比較 (cmd_1745)
<!-- last_updated: 2026-04-05 -->

ALM L0材料4本を忍法スクリプト7種で束ね、既存シン忍法20体と有限時間4指標で比較。orchestrator(425行)で自動実行。

**top結果: 抜き身-激攻/鉄壁がシン忍法を6/7指標で上回る**(beats_count=6)。四つ目-常勝はbaseline不在(吸収済み)。

→ `outputs/analysis/grid_search/cmd_1745_alm_ninpo_results.yaml` | `cmd_1745_vs_shin_ninpo.yaml`
- L565: 旧加速忍法はkasoku_ratio/kasoku_diffの区別なし。シン版以降からR/D分離（cmd_1761）

## §33. 6目的関数ALM×忍法7本 横比較 (cmd_1747)
<!-- last_updated: 2026-04-05 -->

6目的関数(max_run_up/tail_contribution/nhf/left_tail_jumps_inv/cagr/sharpe)×4ファミリーALM→24本L0→忍法7本→42パターン横比較。

**最汎用: tail_contribution目的が7/7 runner全て改善**。cagr目的=加速R beats6。LTJ_inv目的=抜き身 beats6。Max Run-up=6/7。

→ `outputs/analysis/grid_search/cmd_1747_cross_comparison.yaml` | `cmd_1747_ninpo_6obj_results.yaml`
- L567: tail_contributionは多様性低下要因。nhf/cagrが多様性貢献度最高（cmd_1763）[deprecated]
- L568: 10目的間Spearman相関全45ペアが冗長(|ρ|>0.8)。L0 4体からの選択プロセスが構造的要因（cmd_1764）

## §34. ALM L1 OOS検証 (cmd_1748)
<!-- last_updated: 2026-04-06 -->

6目的関数×忍法7種=42パターンのWF-OOS(IS=60M/OOS=12M/step=12M)。**41/42 ROBUST、1 OVERFIT(tail_contribution×加速R +80.8%)**。

| 目的関数 | ROBUST | OVERFIT | 特記 |
|----------|--------|---------|------|
| max_run_up | 7/7 | 0 | 劣化率-33.6%〜+5.2%。最安定 |
| tail_contribution | 6/7 | 1 | 加速R +80.8% OVERFIT |
| nhf | 7/7 | 0 | 全OOS>full-sample |
| left_tail_jumps_inv | 7/7 | 0 | 全ROBUST |
| cagr | 7/7 | 0 | OOS大幅超過(環境バイアス注意) |
| sharpe | 7/7 | 0 | OOS大幅超過(環境バイアス注意) |

→ `outputs/analysis/alm_research/cmd_1748_partial_*.yaml` (6ファイル)
- L556: GS CSVとALM L0 metricsのユニバース差がパリティ破壊（cmd_1748）
- L557: WF-OOS負の劣化率は過適合否定の十分条件ではない。市場環境バイアス要因（cmd_1748）
- L569: left_tail_jumps_inv早期fold(ウォームアップ期間)で全パターンNaN→OOSスキップで系列長短縮（cmd_1766）[deprecated]

## §35. ALM本番組込み設計 (cmd_1749-1753)
<!-- last_updated: 2026-04-06 -->
> **思考過程**: ALM研究→有限時間4指標→各論パッチ量産→原理1つへの到達 → `memory/dialogue_alm_finite_time_20260404.md`（経験的知識。圧縮禁止）

### 殿裁定 (2026-04-06)
- ALM定義: **L0で動的にlookback期間を変える**（PF選出ではない）
- Admin UI: **案A（表示切替）** — ☑ Adaptive チェックでLookback Periods→ALM CONFIG切替
- Dashboard追加表示: **不要**
- Monthly Trade変更: **不要**
- FE変更: **Admin画面のみ必要**（ユーザー向けページは変更なし）

### BE改修設計 (cmd_1750)
- **Hook場所: recalculate_fast.py（L0）が正。recalculate_fof.py（FoF）は別担当**
- Phase 3.7: ALM候補全LBのmomentum cache追加(+3.1MB/PF, +0.5s/PF)
- Phase 4: L1499月初リバランス直前にALM選出挿入
- fullrecalculate: **2パス方式**（Pass1: fallback LBでMR生成 → Pass2: ALM選出で正式シグナル）
- 日次ETL: 1パス（既存MR使用、追加コスト軽微）
- DBマイグレーション: **不要**（JSON列）
→ `docs/research/cmd_1750_alm_design.md`

### 盲点調査結果 (cmd_1751)
- FoFからALM PFは**透過的に動作**（MonthlyReturnテーブル統一構造）
- Daily cron: sync-standard(01:10UTC)→sync-fof(01:40UTC), mode=PORTFOLIO
- fullrecalculate自動cron: **なし（admin手動のみ）**
- Admin保存: 全124PF一括送信。pipeline_config=JSON列でスキーマレス
→ `docs/research/cmd_1751_fof_analysis.md` | `cmd_1751_cdp_findings.md`

### 実装順序
1. BE: recalculate_fast.py Phase 3.7/4改修 + 2パスfullrecalculate
2. BE: recalculate_fof.py Hook A (FoF側ALM対応)
3. FE: Admin PortfolioEditor.tsx Adaptive チェックボックス+ALM CONFIG
4. 検証: fullrecalculate + daily ETL動作確認

→ 統合設計書: `/mnt/c/Python_app/DM-signal/docs/research/alm-integration-design.md`

### ALM忍法 確定事項 (2026-04-06 殿裁定)
- **命名規則**: ALM-{忍法名}-{モード}（例: ALM-加速D-激攻）
- **3モード目的関数**: 激攻=max_run_up / 常勝=calmar / 鉄壁=UWP（殿裁定）
- **19体確定**（7忍法×3モード=21体 - 吸収2体）: ALM-加速R-鉄壁→常勝に吸収、ALM-分身-鉄壁→激攻に吸収
- **DNA制約版候補LBが3/4ファミリーで優位**（cmd_1759 L563）: DM3+23%/DM6+86%/DM7++56%
- L564: MINIMIZE_METRICSへのランタイムpatchでargmin方向を動的変更可能（cmd_1760）
- L566: ALM吸収はシン吸収と異なりメトリクスが変わる。目的関数が異なるため完全同一にならない（cmd_1762）
- **top_n**: DM2/DM6/DM7+=1、DM3=3（cmd_1759）
- L580: 38メトリクスは6目的維持+後計算添付が最速（cmd_1791）
- L587: METRIC_NAMES変更時はselect_champions_multi_isのmetrics_np dictも同期更新必須（cmd_1819）
- **Ward FoF**: K=3,LB=24がBest。K=5は4体<5クラスタで構造的不可能（cmd_1759 L562）
- **切替安定性**: max_run_up最不安定(20%/月)、left_tail_jumps_inv最安定(9%/月)（cmd_1759）
- **鉄壁4目的(cmd_1760)**: MDD目的がCalmar最高(2.78)。sortino目的の加速DがSharpe1.64(全体最高)
- **3世代比較gist**: https://gist.github.com/simokitafresh/ea687a966e627b5e454524004fdd747e
  - `alm_19_metrics_v2.md` — 19体完全版メトリクス
  - `alm_vs_shin_by_ninjutsu_v3.md` — 忍法別3世代比較(旧/シン/ALM、吸収反映)
  - `alm_vs_shin_full_38metrics.md` — 38メトリクス全量版

- L546: ALM foundation cacheは240 fixed seriesの完全性検証が必須（cmd_1737）
- L549: ALM batch統合ではobjective単位fallbackでparityを守る（cmd_karo_batch_R7）
- L554: family ALM研究はmetricsと相関をベクトル化必須（cmd_1741）
- L559: Pass2シグナルflush後のsignal_cache_opt6陳腐化リスク。ALM PF分のcache再構築必須（cmd_1752）CRITICAL
- L560: ALM buffer計算(L708-715)にcandidate_lookbacksのmax値を含める必要あり。378日不足（cmd_1753）
- L561: pipeline_config=Dict[str,Any]でalm_config未検証保存。ALM実装時にバリデーション追加必要（cmd_1753）
- L562: ALM L0 4体でWard FoFを組む場合K=5は構造的不可(体数<クラスタ数)（cmd_1759）
- L641: csv source universe使用時のkawarimi batch vs sequential MD5不一致（cmd_2175）
- L643: ALM忍法21体fold percentile中央値64.3はL0 WFシン四神(72.5)より低い（cmd_2218）
- L563: cmd_1762 BE第一弾完了(da14b6b7)。AlmConfig schema+Phase3.7 ALM cache+vectorized signals実装済み。注意: alm_config読取位置がblock config(実装)とPipelineConfig(schema)で分離→後続cmdで統一必要

### ALM L1: 忍法パラメータ動的選出（2026-04-06殿との設計議論）
- **ALM=lookback戦略のバリエーション**（固定/マルチプル/動的の延長。特別な仕組みではない）
- **忍法別ALM適性**: 加速R(75%)最強、変わり身(46%)最弱。全忍法一律ではなくL1増幅効果に差あり
- **ALM L1設計**: 加速Rのnum/denを動的選出(3パターンA/B/C)。全空間119,493パターン(サブセット含む)。事後フィルタ・事後ラベル
- **道具**: `l1_alm_wf_engine.py`(455行)構築中(cmd_1765/1766)
- **cmd_1763/1764発見**: 10目的間全45ペア相関>0.8(L0 4体共有構造)。目的関数の違いよりlookback戦略の違いが多様性の源泉
- → 詳細: `context/checklist-alm-registration.md` §設計原理
- L564: cmd_1763 ALM目的関数多様性分析完了(1d149a10)。Top1=MRU+NHF+CAGR(3.271)。cagr×MRU相関0.941(高)→実質多様性に注意。tail_contributionは多様性低下要因。calmar/UWPは6目的外→DC記録
- L565: cmd_1764 C(10,3)=120通り完了(e43cefd2)。Top1=MRU+NHF+CAGR(3.271)=cmd_1763と同一→6→10目的拡張で結論頑健。現行ALM Ward#12/120(上位10%)。冗長ペア45件=L0共有の構造要因。sortino欠損率69%→距離計算影響要確認
- L566: cmd_1765 L1 ALM WFエンジン骨格完了(1cbf703f)。CSV読込119,493列+30fold+6メトリクス。GS CSV早期NaN→fillna(0)修正。道具磨き完了→cmd B(タイムボックス60秒実行)が次
- **L0パリティ確定(2026-04-07)**: 12体全PASS (cmd_1774)。hs一致+ret差1e-11(<<1e-6)。momentum_dataにALMメタデータ(relative/absolute/risk_free/safe_haven)存在確認済み。fallbackではなくALM動的選出動作確認。
- **fullrecalculate完了(2026-04-07)**: 殿実行。recalculation_status id=43, 2026-04-07 10:37-10:44 JST (cmd_1787才蔵報告)。2パス方式正常動作。
- **FoF Cash化バグ修正(2026-04-07)**: cmd_1787で修正済み。原因=2026-04-03 perf commit(cdda5ea1/8f411ae9)でMVMF/SVMF/MFのmonthly cacheをdict{月末日:float}で保存→context.target_date(月初第1営業日)でexact .get()→val=None→全ticker除外→Cash。修正=bisect化(get_momentum_value_at_date統一)。commit 1a548111。
- **38メトリクス道具完成(2026-04-07)**: Phase A(cmd_1789→cmd_1791包含)/B(cmd_1791)/C(cmd_1791)完了。select_champions_multi_isが6 objectiveを維持したまま38メトリクスを後計算添付。selection_timeline=180行×47列。7忍法batch 200.65s(300秒制限内)。commit 1da2c487。
- **ALM四神hide維持(殿裁定 2026-04-07)**: global_visibility_settings hide_portfolio=trueのまま維持。パリティ確認済みだが殿裁定でStep 2e N/A扱い。
- **ALM四神フォルダ移動完了(2026-04-07)**: cmd_1792(疾風)でAdmin API経由で「ALM四神」フォルダ作成(folder_id=924734c6-a518-4985-b326-0aad7a68972f)+12体移動完了。非ALM folder_id差分=0。
- **ALM四神リネーム完了(2026-04-07)**: cmd_1788(才蔵)でDM番号→四神名(青龍/朱雀/白虎/玄武)にリネーム。commit saizo_report_cmd_1788.yaml timestamp 2026-04-07T20:05:15。
- **Step 3b WFエンジン36M固定実行(2026-04-08)**: cmd_1798(才蔵)。--multi-isフラグなしで実行→IS窓36M固定。all_success=true、7忍法×186エントリ×38メトリクス。commit 8e7d4b64。
- **Step 3b multi-is WF全量実行(2026-04-08)**: cmd_1799(小太郎)。67窓(6M-72M)×7忍法。IS窓多様性29-38種/忍法(36M固定でない)。213.76s。commit 7724bacb。→ Step 3c(champion確定)が次
- L613: 超越条件C(UWP<5M)は132ヶ月OOS期間に非現実的閾値。SPA全42セル非有意(p>0.4)。ISチャンピオン≒ランダム選択（cmd_1866）
- L615: Cell B(シン×ALM)の一部忍法はGSパラメータ数=1のためALM動的選出≡静的選出。2×2因子分析で縮退ケース注記必要（cmd_1869）

### ALM L2: 2×2因子分析結果 (cmd_1878)
<!-- last_updated: 2026-04-13 -->
- **BB効果**: ALM-BB vs シンBB = **+5.4pp**（GS側+7.2pp / WF側+3.7pp）
- **選出効果**: WF動的 vs GS固定 = **-12.9pp**（shin側-11.1pp / ALM側-14.6pp）
- **L1比較**: L1(BB+15pp/動的-27〜-41pp)→L2で傾向継続だが縮小（L2 GS固定にproduction_db+gs_static_champion混在が一因 → L620）
- **最優秀**: ⑤(ALM-BB×GS固定)×nukimi×激攻 CAGR=1.228 Sharpe=2.054
- **パターン別平均(CAGR)**: ⑤(0.819) > ⑥(0.772) > ③(0.730) > ①(0.707) > ⑧(0.516)最低
- **mode別選出効果**: 鉄壁のみWF優位(+4.4pp)。激攻は大幅WF劣位(-33.5pp)
- **縮退ケース(L615)**: bunshin(expected_patterns=1)はALM-WF≡GS固定(diff=+0.015)
→ 詳細: `queue/reports/kagemaru_report_cmd_1878.yaml` | CSV: `outputs/analysis/alm_research/cmd_1878_l2_okugi_comparison.csv`

### ALM L2: β調整分析 (cmd_1880)
<!-- last_updated: 2026-04-13 -->
- **α>0**: 168/168 (100%)。全体積が超過収益。
- **β調整後2×2効果(sign flip 0)**: BB効果・選出効果ともにrobust
  - static群: BB raw +7.2pp→beta_adj +8.0pp / selection raw -1.7pp→beta_adj -2.0pp
  - wf群: BB raw +3.7pp→beta_adj +3.8pp / selection raw -15.3pp→beta_adj -16.7pp
- **Top5完全一致**: raw/β調整後ともに⑤(nukimi/kasoku_diff/kawarimi/kasoku_ratio/oikaze)の激攻
- **最大順位上昇**: ⑦ oikaze/yotsume 鉄壁 各+21位（β低群=市場連動小→β調整で相対評価上昇）
- **最大順位下降**: ④ bunshin 常勝 -29位（β=1.82の高β群→β調整で下落）
- **⑧が最下位群独占**: ALM-BB×WF動的がβ高(β>1.7)+α低の構造的劣位
- **共通期間**: 88-161ヶ月（忍法/パターン依存）
→ 詳細: `outputs/analysis/alm_research/cmd_1880_l2_beta_adjusted_summary.md` | CSV: `outputs/analysis/alm_research/cmd_1880_l2_beta_adjusted_2x2.csv`

### ALM L2: 168体パターン間相関分析 (cmd_1893)
<!-- last_updated: 2026-04-14 -->
- **共通期間**: 87ヶ月(2018-08〜2025-10)、NaN率0%
- **8パターン間平均相関**: 0.63〜0.77（①ベースライン）
- **①vs各パターン**: ②0.77 > ⑤0.74 > ③0.70 > ⑦0.69 > ⑥0.68 > ④0.67 > ⑧0.63
- **仮説検証**: ①vs⑤(0.736) > ①vs③(0.701) → **確認**（同忍法BB違い > 目的関数違い）
- **多様性**: ⑧(ALM-BB×WF動的)が①と最も低相関(0.63)=追加価値最大。ただしβ調整では最下位群(cmd_1880)
→ 詳細: `outputs/analysis/alm_research/cmd_1893_correlation_summary.md` | CSV: `outputs/analysis/alm_research/cmd_1893_correlation_8x8.csv`

### ALM L3: 2体EW β調整分析 (cmd_1896)
<!-- last_updated: 2026-04-14 -->
- **入力**: 84体(GS固定①③⑤⑦) C(84,2)=3,486ペアEW。88ヶ月月次リターン
- **L3最良α**: 134.3%（①kasoku_diff激攻 + ⑤kasoku_diff激攻）> **L2最強α 101.2%**
- **L2超え**: 161/3,486件(4.62%)
- **Top10構成**: ①×⑤(5件) + ⑤×⑤(5件)のみ。③/⑦はTop10に入らず
- **③/⑦の最良rank**: ⑦ rank25(α=119.4%) > ③ rank43(α=115.8%)
- **結論**: L3はL2を上回る。追加候補は⑤で十分、③/⑦不要
→ 詳細: `outputs/analysis/alm_research/cmd_1896_l3_summary.md` | CSV: `outputs/analysis/alm_research/cmd_1896_l3_beta_adjusted.csv`

### CoDD適用: Phase 3完了 / Phase 4準備 (cmd_1947-1950, cmd_1986-1992)
<!-- last_updated: 2026-04-17 cmd_karo_context_freshness_1993 -->
- **Phase 3高速化完了**: yotsume `-98.6%`, nukimi `-63.3%`, oikaze `-99.3%`, l1_alm_wf `-81%`, bunshin `-78%`。レベルA上位5本のCoDD改善を完了。→ `docs/research/codd_refactor_registry.md` | `docs/research/codd_dmsignal_python_strategy.md` §0.5
- **N体EW比較を横並び化**: cmd_1947-1950系列で1/2/3体EWを同一評価軸に整列。alpha-CalmarはIS/OOS/Expandingで2-3体優位、WFは1体優位。→ `context/l2-okugi-progress.md` §L3 N体EW比較 | `context/senkyoku-log.md`
- **CoDD適用方式はハイブリッドで確定**: OSS版CoDDは `extract`/`measure` を使用し、spec/cProfile/実装/検証は手動で回す。`review`/`implement` は codd-pro 依存で対象外。→ `docs/research/codd_dmsignal_python_strategy.md` §0, §1
- **Phase 4は準備中**: 前提は `(1)` fullrecalculate read-only cProfile, `(2)` cmd_1985偵察結果の設計書反映(compare_recalc_results.py差分), `(3)` `--exclude-months` 実装。→ `docs/research/codd_dmsignal_python_strategy.md` §3.5

### Vintage 2020 OOS検証 (cmd_2228)
<!-- last_updated: 2026-04-22 cmd_2228 -->
- **ss完了**: `outputs/analysis/vintage/2020/vintage_2020_ss_*` 5成果物生成。α6は全objectiveで `alpha_positive=true`。`maximum_drawdown` が最良 (`alpha_annual=2.247561`, `beta_adj_cagr=2.637799`, `alpha_max_dd=0.093083`)。`cagr`/`max_run_up` は bear regime alpha が負で `regime_all_positive=false`。→ `queue/reports/saizo_report_cmd_2228.yaml`
- **as完了**: `outputs/analysis/vintage/2020/vintage_2020_as_*` 5成果物生成。α6は全objectiveで `alpha_positive=true`。`maximum_drawdown` が最良 (`alpha_annual=3.113478`, `beta_adj_cagr=3.621199`, `alpha_max_dd=0.117064`)。`nhf` のみ bull alpha `-0.048525` で `regime_all_positive=false`。`l2_timeline` 19行は IS短縮によるfold減少で設計内。→ `queue/reports/hayate_report_cmd_2228.yaml`
- **共通所見**: 実行入口は `scripts/analysis/alm_research/vintage_pipeline.py`。cmd本文の `outputs/scripts/vintage_pipeline.py` は stale。future contamination は `fold.oos_end <= cutoff` filter + `AssertionError` (`scripts/analysis/alm_research/vintage_pipeline.py` L160-L166付近) で担保。
- **summary+commit完了**: `outputs/analysis/vintage/2020/vintage_2020_summary.md` を新規作成。§3で ss/as alpha6 比較、§4で regime 比較を整理。`outputs/scripts/vintage_pipeline.py` → `scripts/analysis/alm_research/vintage_pipeline.py` の stale path 差分も明記。`DM-Signal` 側 commit は `742337c1`。`.gitignore` に `outputs/analysis/vintage/**/*_l0_metrics.csv` を追加し、2020/2022 の vintage 系成果物を整理。→ `queue/reports/kagemaru_report_cmd_2228.yaml`
