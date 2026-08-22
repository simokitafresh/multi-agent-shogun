<!-- gist-master: 4df581b5103f7f339ba51a5212d8f6f3 dm-signal-hmm-regime-experiment-v0-original_20260823.md -->
<!-- 殿原文(2026-08-23 08:47下問)・改変禁止。5指標v0-original(dae809c3)と同じ正本方式 -->
# DM-Signal HMM Regime実験 — 概念設計

## 目的

arXiv:2605.27848 の着想をDM-Signal向けに再構成し、

「市場レジーム情報が、既存のDual Momentum FoF selectionに
追加的な予測情報を与えるか」

を検証する。

DM-SignalではFoF自体がDual Momentum戦略を束ねたアセットであり、
毎月リバランスされる。

したがってHMMを新しい主戦略にはしない。
既存Momentum selectionの補助情報として価値があるかだけを見る。

## 中心仮説

H1: 市場レジームによって、FoF間の将来performanceの相対順位が変化する。
H2: その差は、既存Momentum selectionを通過した候補群の中でも残る。
H3: HMM regimeをsecond-stage filterとして使えば、既存selection単独よりrisk-adjusted performanceを改善できる。
H4: 改善があるとしても、HMMをMomentumより先に使うより、Momentum後の補助情報として使う方が有効である。

## 原論文から引き継がないもの

- SPY / TLT / GLDの直接rotation
- 日次売買
- RL
- Deep Learning
- 複雑なfeature engineering

DM-Signalの既存構造を維持したまま、HMM regimeの追加情報価値だけを検証する。

## 実験原則

最大の条件はPoint-in-Timeである。
各月の判断には、その月末時点までに利用可能だった情報しか使わない。
HMMについても、未来データを使って過去stateを後から分類してはならない。
特に未来情報を利用するsmoothingは使わず、その時点で利用可能なfiltered stateを使う。
HMMの観測は日次でもよいが、意思決定はDM-Signalに合わせて月次とする。

## Phase 1 — Regimeに情報があるか

まだselectionは変更しない。
各月末のHMM regimeと、その後のFoF performanceを対応させる。
確認するのは「Quiet / Transition / Stress等のregimeによって、将来のFoF間順位が変わるか」である。
forward horizonは 1M / 3M / 6M / 12M を見る。
重要なのは絶対returnではなくcross-sectional差。
Stressでは全FoFが悪かった、というだけでは不十分。
Stressになると「どのFoFが相対的に強いか」が変わる必要がある。

## Phase 1で見るもの

- Regime別FoF forward return
- Regime別FoF forward rank
- Regime間のrank correlation
- Regime別のrank dispersion
- Regime別MaxDD
- Regime別FoF間相関
- 各Regimeのsample数

もしRegime間でFoF順位がほぼ変わらないなら、HMMをselectionへ使う理由はない。

## Phase 2 — Momentumと独立した情報か

Phase 1で差が見つかっても、それが既存Momentumで既に説明されている可能性がある。
そこで既存selectionで上位候補を作った後、その候補群だけで再度、Regime × forward performance を見る。
問いは「Momentum順位が高いFoF同士を比較しても、Regimeによって将来順位が変わるか」である。
ここで効果が消えるなら、HMMは既存Momentum情報の再表現に近い。
ここでも差が残るなら、追加情報として価値がある可能性がある。

## Phase 3 — Selectionに使う

Phase 1、Phase 2を通過した場合のみ実施する。
Control: 既存Momentum selection
Experimental: 既存Momentum selection → 上位候補集合を固定 → HMM regime情報で候補内をrerank → portfolio構築
HMMを先に使ってからMomentumを使う順序も比較対象にしてよいが、PrimaryはMomentum firstとする。

## Regime適性の考え方

特定Regimeで過去平均returnが最大だったFoFをそのまま選ぶ方式は避ける。
危機Regimeはsampleが少なく、一度の大きなreturnに強く依存する可能性があるためである。
基本は「そのRegimeで過去に相対的に何位だったか」というcross-sectional rankを使う。
極端な絶対returnより、Regime内での相対的な強さを見る。

## 相関について

RegimeごとにFoF間相関も観測する。
目的は、Stress時にFoF群がほぼ同じ動きをして実質的に1 asset化するのか、あるいは逆に差が拡大するのか、を確認すること。
ただし相関をselection ruleとして再利用することが目的ではない。

## 評価

総期間のCAGRだけで判断しない。
既存指標: CAGR / Sharpe / Calmar / MaxDD / Volatility / Avg UWP / VDrag
さらに: selection turnover / Regime別performance / Regime transition時のperformance / Regime別FoF順位

## 採用条件

1. RegimeによってFoFの将来順位が変化する
2. Momentum conditioning後にも差が残る
3. 複数forward horizonで方向が概ね一致する
4. 改善が特定の少数危機月だけに依存しない
5. Stress時のMaxDD / Calmar等に意味のある改善がある
6. Quiet時の成長率を大きく毀損しない
7. turnover増加が過大でない
8. 完全PITで再現する
9. 改善理由をRegime別に説明できる

## STOP条件

- Regime間でFoF順位がほぼ変わらない
- Momentum上位候補内ではRegime効果が消える
- 改善が1つの危機イベントだけで発生する
- turnover増加で改善が相殺される
- HMM設定を変えないと結果が出ない
- PIT条件で効果が消える

## 実験の考え方

順番は必ず: 市場Regimeに情報があるか → Momentumと独立した情報か → selectionに使えるか
最初からバックテスト結果の最大化を目的にしない。
本質は「HMMで儲かるか」ではなく「Dual Momentum FoF群の相対的なEdgeは市場Regimeによって変化するのか」を検証することである。
