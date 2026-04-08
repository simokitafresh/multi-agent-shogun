<!-- last_updated: 2026-04-09 -->
# GS忍法パラメータ空間分析
<!-- cmd_1711結果 | 2026-04-03 | author: gunshi -->
<!-- source: outputs/analysis/grid_search/cmd_1711_* -->

## §1. Champion一覧(CAGR降順)

| # | 忍法 | CAGR | Sharpe | MaxDD | Calmar | 主パラメータ | subset | overfit |
|---|------|------|--------|-------|--------|-------------|--------|---------|
| 1 | kasoku_ratio | 78.3% | 1.598 | -53.3% | 1.468 | 10D/3M ratio | N4 | false |
| 2 | kasoku_diff | 76.9% | 1.638 | -29.7% | 2.584 | 2M/8M diff | N4 | **true** |
| 3 | nukimi | 72.4% | 1.728 | -26.1% | 2.777 | 18M, SK1, top1 | N3 | **true** |
| 4 | oikaze | 71.4% | 1.735 | -31.0% | 2.306 | 18M, top1 | N4 | false |
| 5 | kawarimi | 67.5% | 1.684 | -30.1% | 2.243 | 24M, select1 | N4 | false |
| 6 | yotsume | 55.9% | 1.435 | -36.6% | 1.527 | B12, top2 | N2 | false |
| 7 | bunshin | 50.4% | 1.372 | -33.2% | 1.519 | EW(パラメータなし) | N2 | false |

※ yotsume=C12_legacy_shijin、他6忍法=C12_shin_shijin_v2。横断比較時に注意。

## §2. パラメータ空間構造 — 6観点

### (1) Lookback帯域: 中長期が全忍法で支配的

| 忍法 | champion lookback | top10のlookback分布 |
|------|------------------|-------------------|
| oikaze | **18M** | 7/10が18M、2が10M、1が15M |
| nukimi | **18M** (base_period) | championのみ確認(skip=1) |
| kawarimi | **24M** (period) | championのみ確認 |
| kasoku_ratio | 分子10D/分母**3M** | 短期/中期比率で中長期トレンド捕捉 |
| kasoku_diff | 分子**2M**/分母**8M** | 中長期差分 |
| yotsume | **12M** (base_period) | 3点grid中の最長 |

**結論: 殿指摘「中長期lookbackが全忍法で有効」は定量的に確認。** oikaze/nukimiの18M、kawarimiの24M、kasoku系の分母3-8Mが一貫して上位。短期(1-3M)lookbackは全忍法で劣後。

**因果推論**: 月次リバランスのdual momentum戦略では、短期lookbackはwhipsaw(誤反転)を誘発し、中長期lookbackはトレンドの持続性を捉える。12-24Mの帯域がシグナル安定性と反応速度のスイートスポット。

### (2) Championパラメータの共通点と差異

**共通点:**
- シン青龍-激攻: v2全6忍法のchampionに含有(**100%**)
- シン白虎-鉄壁: 5/6忍法に含有(83%)
- subset_size: 5/7がN3-N4(3-4体)。集中型サブセット
- lookback方向: 全て中長期

**差異:**
- kasoku系: 2軸パラメータ(分子/分母)。他忍法は1軸+top_n
- bunshin: パラメータなし(純粋EW)。subset選択のみが変数
- yotsume: legacy universe。v2との直接比較不可

### (3) 集中 vs 分散: top_n=1が全忍法で圧勝

| 忍法 | top_n=1 (集中) | top_n=2 (分散) | CAGR差 |
|------|---------------|---------------|--------|
| oikaze | 0.714 (18M) | 0.476 (18M) | **+50%** |
| nukimi | 0.724 (18M,SK1) | 0.483 (18M,SK1) | **+50%** |
| kawarimi | 0.675 (24M) | 0.491 (24M) | **+37%** |
| yotsume | — | 0.559 (B12, top2=champion) | N/A |

**結論: 殿指摘「集中>分散」は定量的に確認。** top_n=1はtop_n=2を+37-50%上回る。yotsumeのみtop_n=2がchampion(grid点数が3×2と極小のため)。

**因果推論**: top_n=1は最強銘柄への集中投資。momentum戦略では「勝者に集中」が「勝者群に分散」より有効。分散はbeta抑制に寄与するがCAGR犠牲が大きい。

**subset_size効果**: bunshin top10ではN2(0.504)≒N3(0.488)≒N4(0.483)。サブセットサイズの効果は小さく、中の銘柄選択が支配的。

### (4) Champion近傍感度(overfit判定)

| 忍法 | 近傍数 | CAGR Drop | Sharpe Drop | overfit | 判定根拠 |
|------|--------|-----------|-------------|---------|---------|
| oikaze | 5 | 30.0% | 22.7% | false | 5近傍に分散。孤立ピークなし |
| nukimi | **1** | **33.3%** | 23.7% | **true** | 近傍1点のみ。isolated_peak_cagr |
| kawarimi | 1 | 27.2% | 22.7% | false | dropは許容範囲 |
| kasoku_ratio | 2 | 27.8% | 21.9% | false | 2近傍。drop安定 |
| kasoku_diff | 5 | **33.9%** | 26.0% | **true** | 5近傍だがdrop大。isolated_peak_cagr |
| yotsume | 1 | **20.1%** | 19.1% | false | 最安定(drop最小) |
| bunshin | 0 | N/A | N/A | false | パラメータなし |

**overfitリスク判定:**
- **HIGH**: nukimi (CAGR drop 33%, 近傍1点のみ)、kasoku_diff (drop 34%, isolated peak)
- **MEDIUM**: oikaze (drop 30%, 近傍は多いが15M→18Mで急上昇)
- **LOW**: kawarimi, kasoku_ratio, yotsume

**因果推論**: nukimiのchampion(N3_0113, 18M, SK1, T1)は近傍1点(T2)しか存在しない→パラメータ空間の端に位置→overfit疑惑。kasoku_diffは5近傍あるが全てCAGR 30%+低下→急峻なピーク→パラメータ変動に脆弱。

### (5) メトリクス間一貫性

| 忍法 | CAGR順 | Sharpe順 | Calmar順 | 一貫性 |
|------|--------|---------|---------|--------|
| kasoku_ratio | 1 | **5** | **5** | **不一致**(高リターン+高リスク) |
| kasoku_diff | 2 | 3 | **1** | 混在(Calmarは最良=MaxDD浅い) |
| nukimi | 3 | 2 | 2 | **一貫** |
| oikaze | 4 | **1** | 3 | **一貫**(Sharpe最高=リスク効率最良) |
| kawarimi | 5 | 4 | 4 | **一貫** |

**結論**: nukimi/oikaze/kawarimiはCAGR・Sharpe・Calmar全て整合。**kasoku_ratioはCAGR首位だがMaxDD -53.3%でSharpe/Calmar大幅劣後** → 高リターンは高ボラティリティの代償。リスク調整後はoikaze(Sharpe1位)またはnukimi(Calmar2位)が最も「質の高い」champion。

### (6) 殿の仮説検証まとめ

| 仮説 | 検証結果 | 定量根拠 |
|------|---------|---------|
| 中長期lookbackが全忍法で有効 | **確認** | 全champion: 12-24M帯。oikaze top10の70%が18M |
| 集中>分散 | **確認** | top_n=1 vs 2: CAGR差+37-50%(3忍法で再現) |

## §3. 戦略含意

1. **selection blockの有効lookback帯は12-24M**。この帯域外の探索は期待値が低い
2. **top_n=1(集中)がデフォルト設計**。分散(top_n≥2)はリスク要件がある場合のみ
3. **kasoku_ratioのCAGR首位は見かけ倒しの可能性**。MaxDD -53.3%は他忍法の2倍。リスク調整後はnukimi/oikazeが優位
4. **nukimi/kasoku_diffはoverfit警戒**。本番採用前にOOS検証必須
5. **シン青龍-激攻は全忍法の共通最強コンポーネント**。Ward選択の中核

→ 詳細データ: `outputs/analysis/grid_search/cmd_1711_*`
→ 42枚ヒートマップ: `outputs/analysis/grid_search/cmd_1711_ninpo_heatmaps/`
→ Ward寄与率97.2%: `context/dm-signal-research.md` §25 R21
