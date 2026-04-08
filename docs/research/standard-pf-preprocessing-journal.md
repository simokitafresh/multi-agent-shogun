# Standard PF 前処理研究日誌
<!-- last_updated: 2026-04-01T01:35:00+09:00 -->

> **この文書の読み方**: 結論を拾い読みするな。Phase 0から順に読め。各Phaseで「この時点で我々は何を知っていて何を知らなかったか」を意識しながら追え。殿の言葉は全て転換点。その前後で将軍の視界が変わる。その変化を体験することが目的。
>
> **ルール**: タイムスタンプはISO 8601秒精度+TZ。事実だけ書くな、思考の変遷を書け。驚きの瞬間を省略するな。除外理由も残す(車輪の再発明防止)。

---

## [2026-03-31T19:30:00+09:00] Phase 0 — 天井にぶつかった

数週間、FoF(Fund of Funds)レベルの構造最適化に没頭していた。ClSel(Cluster Selection)研究R21-R30で、Ward+TwoStageEWが65体でも頑健(Sharpe優位70.8%, MaxDD優位95.9%)。OPTICS+MP denoisingも試したがN=20小集団ではOPTICSが単一クラスタに退化(cmd_1623)。我々は上位構造の改善を追い続けていた。

だが、行き詰まっていた。FoFの天井が見えていた。Ward構造がリターンの97.2%を支配し、モメンタム効果はわずか2.8%(R21結論)。いくらFoFを磨いても、残り2.8%の中での最適化にすぎない。

そこで殿が方向を転じた。

> 「やるべきはstandardPFつまりデュアルモメンタムに前処理を行うと何かしらの改善傾向は出るのかを調べたいな。もっと基本を掘り下げたい」

この一言で視界が変わった。FoFは上位構造。だが**その部品であるstandard PF**のmomentum計算には前処理が一切ないのではないか？ 基礎が改善されれば全PFに複利的に波及する。天井は部品の精度で決まっていたのかもしれない。

だがこの時点では「前処理がない」は仮説でしかなかった。本当に一切ないのか？ 想像ではなく確認する必要がある。

---

### [2026-03-31T19:45:00+09:00] 偵察 — 確認してから考える

半蔵+影丸の2名偵察(cmd_1627)を実行。本番コードを直接読ませた。

偵察が返した事実は衝撃的だった:
- **全7選択BBが前処理ゼロ。** raw close → pct_change → 加重平均。フィルタリング、平滑化、デノイズ、一切なし
- 全BBが同一の`calculate_composite_momentum_vectorized`(vectorized_momentum.py L7-24)を使う
- 注入ポイントは5箇所特定された: (A)ブロック内(推奨), (B)base.py共通層, (C)計算基盤層, (D)選出ロジック内, (E)新規BB

仮説どころか、予想以上だった。学術的には考えられないほどナイーブ。金融系のmomentum文献では何らかの前処理を入れるのが普通なのに、我々は完全に「素」だった。

ここで確信が生まれた: **改善余地は確実にある。問題は「どの前処理がdual momentum構造に合うか」だ。**

→ `queue/reports/hanzo_report_cmd_1627.yaml` / `queue/reports/kagemaru_report_cmd_1627.yaml`

---

## [2026-03-31T20:00:00+09:00] Phase 1 — 殿と候補を絞る

### 2方向が見えた

偵察結果を殿に報告した。殿はすぐに焦点を定めた:

> 「リターン系列のノイズ除去だな。absolute momentumにも使えるのでは？それにGerber的閾値フィルタ」

この一言で2方向が分離した:
1. **入力の浄化** — momentum計算に渡す価格/リターン系列のノイズを除去する
2. **判定の安定化** — BUY/CASH切替のゲートにヒステリシス(閾値)を持たせる

これは重要な分離だった。前者はmomentumの「計算」に介入し、後者はmomentumの「使い方」に介入する。全く別のレイヤー。

殿が更に問うた:

> 「Exponential weightingは忍法の加速とかが同じ方向では？」

将軍は偵察結果を参照して回答: 加速BBは短期/長期momentum ratio/diff(二次導関数)。EMA平滑化は入力浄化(一次)。構造的に別レイヤーであり、組合せ可能。偵察を先にやっていたから即答できた。

> 「MP法以外にも前処理の方法はなかったっけ？」

将軍が知っている候補を並べた: Ledoit-Wolf shrinkage、Gerber statistic、EMA平滑化、Winsorization、対数リターン。**この時点では将軍の知識範囲内で考えていた。** 学術文献の広域サーベイは後のPhase 3まで発想すらなかった。ここに盲点があった。

### [2026-03-31T20:05:00+09:00] OAS vs LW — 思い込みを潰す

> 「Ledoit-WolfよりもOASのほうが全方面で優っているのか？」

殿のこの問いは、将軍が暗黙に持っていた「OAS > LW」という印象を検証させた。調べた結果: OASは正規分布+高p/n比で最適。金融データは非正規(ファットテール)→LWがsafe default。**OASは「全方面で優る」わけではなかった。** 条件次第。我々のデータは金融データ→LW一択。

### [2026-03-31T20:10:00+09:00] Winsorization却下 — これが後の選別基準になった

> 「リターン系列のWinsorizationは乗り換え前提のシステムとは相性が悪そうだな」

殿はdual momentumの生命線を見抜いていた。ゲート判定(`momentum(asset) < momentum(DTB3) → 全CASH`)において、テール(大きな下落=crash)こそがCASH切替のシグナル。テール振幅をキャップしたら、crashの深刻度が見えなくなり、切替が遅れる。

**この判断が以降の全候補の選別基準になった**: 「テール情報はノイズかシグナルか？」。Winsorization(テール=ノイズ)→却下。だが後にJump Detection(統計的に異常なジャンプのみ選択除去)は候補に残った。同じ「テール対応」でも、切り方が違えば結論が変わる。Phase 3でサーベイした時にこの基準が何度も使われることになる。

### [2026-03-31T20:20:00+09:00] 知識辞書から先に — 殿の段取り

> 「先に知識辞書の充実を図ろう」

殿は研究の前に理論基盤を固める判断をした。cmd_1624(Gerber M14 + Shrinkage M15)、cmd_1625(OPTICS M16 + DM-Signal解釈D07)を起票。この段取りのおかげで、研究cmdの設計時に知識辞書を参照でき、設計品質が上がった。

---

## [2026-03-31T20:30:00+09:00] Phase 1.5 — 将軍の失敗

### 殿の優先度を無視した

殿: 「Ledoit-WolfとGerber閾値が本命の二つだったはず」

将軍はこの時点でGerber閾値(cmd_1628)とEMA平滑化(cmd_1629)を先に起票していた。殿が「本命」と明言したLWを書かず、簡単なEMAを先に入れてしまった。

殿: **「順番を守ろう。」**

これは静かな言葉だが、重い指摘だった。将軍がEMAを先にしたのは「実装が簡単で結果が早く出る」から。つまり将軍の都合。殿が「本命」と明示したものを差し置いて、将軍の判断で順番を変えた。鎖の原理に反する。

**なぜこの失敗が起きたか**: 3アプローチの設計が必要なLWより、単純なEMAの方が「すぐ起票できる」。スピードを殿の優先度より上に置いた。Phase 0で「天井にぶつかった」から焦りがあったのかもしれない。だが殿の優先度が全て。

修正: cmd_1630(LW研究)を即座に起票。この失敗を将軍教訓として記録。

---

## [2026-03-31T20:50:00+09:00] Phase 2 — 4つの実験を走らせる

Phase 1で候補が4つに絞られた。ここから実験フェーズに入る。殿の「別々にやらないとどれがどのような効果をもたらしたかがわからない」という指示に従い、**1変数ずつ分離検証**する設計。

### 配備の時系列

| 時刻(+09:00) | cmd | 忍者 | 内容 |
|------|-----|------|------|
| 20:50 | cmd_1628 | 半蔵(才蔵初版→半蔵書換) | Gerber閾値フィルタ。k=[0.0, 0.25, 0.5, 0.75, 1.0] |
| 21:01 | cmd_1629 | 疾風 | EMA平滑化。span=[0, 5, 10, 21, 42] |
| 21:10 | cmd_1630 | 影丸 | LW shrinkage。3アプローチ(A:リスク調整/B:shrinkage/C:ノイズ耐性ゲート) |
| 21:19 | cmd_1631 | (配備待ち) | Fractional Differentiation。d=[d_opt, 0.3, 0.5, 0.7] |

### 比較基盤 — なぜこの指標か

**対象PF**: reference_assetモード使用のstandard PF群(AbsoluteMomentumゲート判定を行うstandard PFの代表)。

**比較5指標**: (1)CAGR (2)Sharpe (3)MaxDD (4)whipsaw(シグナル反転回数) (5)現行一致率

whipsawを入れた理由を説明する。whipsawとはBUY→CASH→BUY→CASH...の無駄な売買。前処理の主目的はノイズ除去であり、ノイズ除去の直接的指標はwhipsaw削減。CAGRが変わらなくてもwhipsawが半減すれば、それは安定性の実質的改善。

一致率を入れた理由: シグナルが現行と全く違えば、それは前処理ではなく別戦略。別戦略が良い成績でも、それは「前処理が効いた」ではなく「別のものが良かった」。

**制約**: 本番コード変更なし(研究スクリプトのみ)。walkforward(PI-009準拠は本番化時)。

### 各研究の設計思想

**cmd_1628 Gerber閾値** — 「小さな差は無視する」

momentum差 = momentum(asset) - momentum(DTB3)。|差| < k*σ(差分のrolling std)なら**現状維持**。大きな差のみシグナル変更を許可。信号処理のヒステリシスと同じ原理。σスケールで市場ボラティリティに自動適応。

cmd仕様はmomentum差レベルのgate-level threshold。知識辞書M14の伝統的Gerber Statistic(日次リターンレベルのGS0/GS1/GS2)とは適用レベルが異なる。この区別が後に才蔵の初版誤りを生む(Phase 2.5で記述)。

**cmd_1630 LW 3アプローチ** — 「共分散推定の3つの使い方」

- **A**: momentum_i / σ_i(LW) — 高ボラ資産の過大評価を抑制
- **B**: shrunk_momentum = α*momentum + (1-α)*mean — 極端値を平均に引き寄せてランキング安定化
- **C**: z = (mom_asset - mom_ref) / σ_LW(diff) > threshold — Gerber閾値と同方向だがσ推定が違う

standard PFのticker数は5-15程度。LW共分散行列の次元が小さいのでshrinkage効果は限定的かもしれない。**だがそれ自体が検証結果として価値がある。** 「small-Nではshrinkage不要」が結論なら、本番化時にLWは不要と即判断できる。否定的結果も情報。

**cmd_1629 EMA平滑化** — 「最も安価な実験」

close → EMA(span) → pct_change(lookback)。DTB3(value列=年率%)にはEMA適用しない。

ベースライン。これで効果が出なければ単純な平滑化は不十分。効果が出れば、より高度な手法(L1/Kalman)に進む根拠。最も安い実験で「前処理は効くか？」にYES/NOを出す。

**cmd_1631 Fractional Differentiation** — 「差分演算そのものを変える」

López de Prado AFML Ch.5。d=1(現行pct_change)→d<1で長期記憶を保持。他の3手法は「momentum計算の前後の加工」だが、FDは**計算基盤(差分演算)自体の置換**。最も根本的。金融ML文献で賛否両論あるが、だからこそ我々のデータで検証する価値がある。

---

## [2026-03-31T21:13:00+09:00] Phase 2.5 — 最初の結果が返ってきた

### EMA結果 — 予想を超えた発見

疾風(hayate)が最初に完了した。5PF × 5span = 25条件。

この時点での期待: 「EMAはシンプルだから効果は限定的だろう。大きな改善は本命のLW/Gerberに期待」と思っていた。

結果を開いた:

| PF | span=0(現行) CAGR/Sharpe | 最良span | CAGR変化 | Sharpe変化 | Whipsaw変化 | MaxDD |
|----|--------------------------|----------|---------|-----------|------------|-------|
| DM2 | 40.0% / 1.02 | **span=21** | +2.7% | +1.3% | 36→23 (**-36%**) | -61.0% 不変 |
| DM3 | 10.9% / 0.46 | **span=42** | **+112%** | **+45%** | 56→53 (-5%) | -78.8→**-63.2%** |
| DM5 | 41.6% / 1.08 | **span=5** | +5.0% | +2.3% | 51→52 (微増) | -55.5% 不変 |
| DM6 | 50.4% / 1.21 | **span=0** | **全span劣化** | **全span劣化** | — | — |
| DM7+ | 26.7% / 1.02 | **span=5** | +11.3% | +4.8% | 8→6 (-25%) | -26.1% 不変 |

→ `outputs/analysis/standard_pf_preprocessing/ema_smoothing_results.yaml` / commit 802904f2

### [2026-03-31T21:15:00+09:00] 驚いたこと

**DM3のCAGRが2倍になった。** 10.9% → 23.1%。最もシンプルなEMAで。Sharpe +45%。MaxDDも15pp改善。

「効果は限定的だろう」という予想が完全に外れた。DM3はノイズに極端に脆弱だったのだ。span=42(約2ヶ月)のEMAをかけて初めてトレンドが安定する。言い換えると、**DM3の現行成績は「真の戦略能力」よりかなり低かった。** ノイズに振り回されて本来のパフォーマンスが出ていなかった。最も安価な前処理で、最大の改善が出た。殿の直感が正しかった — standard PFの前処理は効く。

**DM6が全span劣化した。** これも予想外だった。DM6はlookback=15日の超短期PF。EMAのラグ(遅延)がシグナル精度を致命的に落とす。5日のEMAですら15日lookbackに対して遅延が大きすぎる。**短いlookbackにはEMA平滑化は有害。** これは「前処理は万能ではない」ことを意味し、重要な制約条件。

**DM7+はほぼ不変。** lookback=504日の超長期PF。5-42日のEMAは504日に対して微小。長期PFには前処理の影響が薄い。当然と言えば当然だが、確認できた。

### [2026-03-31T21:18:00+09:00] パターンが見えた

3つの結果を並べると法則が浮かぶ:
- **中程度lookback(DM3: 63日?)** → 劇的改善
- **短すぎlookback(DM6: 15日)** → 劣化(ラグ害)
- **長すぎlookback(DM7+: 504日)** → 不変(影響微小)

**前処理の効果はlookback長に依存する。** これは今後の全手法に共通するはず。DM6型のPFには固定パラメータの平滑化は使えない。

そして: **最適spanがPFごとに全く違う。** DM3=42, DM5=5, DM7+=5。全PFに統一パラメータは使えない。この事実が「適応的平滑化(Kalman Filter)」の必要性を直接的に示している。KalmanならSNRに応じて平滑度を自動調整するから、DM6型でもDM3型でも同一アルゴリズムで対応できるはず。

**MaxDDはDM3以外ほぼ不変。** 平滑化ではドローダウンの深さは防げない。ドローダウンは1回のcrashイベントで決まる。平滑化はノイズを減らすが、crashを防がない。ドローダウン改善には別アプローチ(レジーム検出?ジャンプ除去?)が必要。

**この時点で将軍の頭にあった次の問い**:
1. より高度な平滑化(L1/Kalman)ならDM3は更に改善するか？
2. KalmanならDM6の劣化を回避できるか？
3. 平滑化以外のアプローチ(Gerber/LW/FD)の結果は？

---

## [2026-03-31T21:25:00+09:00] Phase 3 — 知らないものがあるかもしれない

### 殿の問い — 盲点への気づき

> 「前処理系で面白いものはないかな？学術的なものを広く検索してみてほしい」

Phase 2の4手法は将軍の知識範囲内で選んだものだった。EMAで予想外の大きな効果が出たことで、殿は「我々が知らないもっと良い手法があるのでは」と考えた。

**将軍はここまで、自分の知識内で設計していた。** LW、Gerber、EMA、FD — 全て将軍が知っていた手法。学術文献にはもっと多くの前処理手法が存在する。EMAというシンプルな手法でDM3が2倍になったなら、学術的に洗練された手法ならもっと大きな効果がありうる。知っているものだけで設計することの危険を殿が指摘した。

3エージェント並列で広域検索を実行:
1. 信号処理系 — ウェーブレット、デノイジング、SNR改善
2. 推定量系 — カルマンフィルタ、EMD、ロバスト推定量、エントロピー
3. 先端手法 — HP/バンドパス、SSA、VMD、レジームスイッチング、2023-2025最新論文

### [2026-03-31T21:30:00+09:00] 発見 — 我々は3つの方向を見落としていた

サーベイで14の手法が引っかかった。それを「何を変えるか」で分類したとき、**Phase 2の4手法がカバーしていない3つの空白地帯**が見えた。

```
前処理の種類          Phase 2(実行中)           Phase 3で発見(空白地帯)
──────────────────────────────────────────────────────────────
入力平滑化            EMA(cmd_1629✓)            L1 Trend / Kalman / Savitzky-Golay
振幅ノイズ除去        Gerber閾値(cmd_1628)      Jump Detection
共分散推定            LW shrinkage(cmd_1630)    Volatility Scaling(LWの簡易版)
差分演算変更          FD分数次差分(cmd_1631)    —
周波数分解            — ★空白                   SSA / VMD / Band-Pass
信頼度ゲート          — ★空白                   Entropy(PE/Shannon/Transfer/SampEn)
レジーム検出          — ★空白                   HMM / SJM(Statistical Jump Model)
```

**空白1: 周波数分解** — EMAは時間軸の平滑化。だが周波数分解は価格データを「トレンド+ノイズ+季節性」に分離する。全く直交するアプローチ。

**空白2: 信頼度ゲート** — ここが最大の発見だった。今までの全手法は「信号を加工する」。エントロピーゲートは「**信号を信頼すべきかを判定する**」。メタフィルタ。発想が根本的に違う。EMAもGerberもLWも「信号を変える」が、エントロピーは「この信号を使うべきか？」と問う。

**空白3: レジーム検出** — 市場の状態(トレンド/レンジ/クラッシュ)を判定し、前処理のパラメータをレジームに応じて切り替える。前処理自体ではなく「いつどう前処理するか」の判断層。

### [2026-03-31T21:32:00+09:00] 各手法の評価 — EMA結果を踏まえて

以下、「なぜ我々のdual momentumに対して面白いか」を記録する。Phase 2.5のEMA結果(lookback依存性、固定span限界、MaxDD不変)が全ての評価の基準になっている。

#### A. EMAの上位互換

**L1 Trend Filter** (Bruder, Dao, Roncalli 2013 SSRN:2289097 / Dao 2014 arXiv:1403.4069)

EMAの弱点: 全時点を等しく平滑化する → トレンド転換点でもぼかす → ラグ。DM6劣化の原因。

L1は**区分線形トレンド**を抽出する。折れ点(レジーム転換)は鮮明に残り、その間を直線で結ぶ。ラグ最小。**momentum戦略の文脈で直接テスト済み**(Bruder 2013)。金融で検証された手法。

DM3でEMAが効いたなら、L1はDM3で更に効くはず。DM3のノイズ構造が「ランダムにフラフラ→突然トレンド変化」なら、折れ点検出に特化したL1がEMAを上回る。実装: `cvxpy`凸最適化、パラメータ=lambdaのみ。

**Kalman Filter** (Benhamou 2018 arXiv:1808.03297)

EMAの弱点: spanが固定。DM3=42, DM5=5が最適で統一不可。かつ同一PF内でもSNRが変動する。

KalmanはSNRに応じて平滑度を**自動調整**。Benhamou (2018)でMA系を「dramatically improve」と報告(S&P500先物)。

**DM6問題への特別な期待**: DM6はEMAの全spanで劣化した。Kalmanなら「SNR高い局面(トレンド明確)→ほぼ平滑化しない」「SNR低い局面(レンジ)→強く平滑化する」。DM6のlookback=15日でも、ラグを自動抑制できるはず。

**Savitzky-Golay** (Savitzky & Golay 1964) — 局所多項式フィット。形状保持。L1/Kalmanの後方に位置づけ。金融での検証事例が薄い。

#### B. 空白地帯を埋めるもの

**Jump Detection** (Lee-Mykland 2008 RFS / Barndorff-Nielsen-Shephard 2006)

Gerber閾値の逆方向。Gerberは「小さい差はノイズ」。Jump Detectionは「大きすぎる1日の変動がノイズ(一回限りのイベント)」。

Phase 1でWinsorizationを却下した。理由: テール振幅のキャップがcrash情報を損失。だがJump Detectionは「ランダムにキャップ」ではなく「統計的にジャンプと判定されたイベントだけ除去」。殿のWinsorization却下理由に抵触しない、より精密な手法。Winsorization却下の判断基準がここで活きた。

**Entropy-Based Confidence Gate** — サーベイ最大の発見

```
現行:  momentum(asset) >= momentum(DTB3)                    → BUY
提案:  momentum(asset) >= momentum(DTB3) AND entropy < thr  → BUY
```

低エントロピー(市場が一方向)→momentum信号が信頼できる→実行。高エントロピー(市場がランダム)→momentum信号はノイズ→CASH維持(信号を無視)。

**なぜこれがGerberと直交するか**: Gerberは「momentum差の振幅」でフィルタ。エントロピーは「リターン系列の構造」でフィルタ。別の次元。同時適用可能。二重フィルタ。

Permutation Entropy(PE, Bandt & Pompe 2002)が最有力: パラメータ少ない、計算軽い、非線形対応。PE低下がcrash前のハーディング(群集行動)を捕捉する可能性。

Transfer Entropy(Liu et al. 2020)は最も高度: 「自己因果性 vs ニュース駆動性」でmomentum有効/無効を判定。だが実装が複雑。PEで先にエントロピーゲート自体の有効性を検証すべき。

**SJM — Statistical Jump Model** (Shu, Yu & Nystrup 2024 J Asset Mgmt) — HMM改良。ジャンプペナルティでレジーム持続性を強制。momentum戦略のトレンド持続仮定と整合。2024年最新。

#### C. 周波数分解系

**SSA** (Hassani & Thomakos 2010) — 非パラメトリック。SVDベースのトレンド抽出。仮定なし。2024年Deloitte研究でSharpe 1.88。パラメータ: window length Lのみ。

**VMD** (Dragomiretskiy & Zosso 2014 IEEE TSP) — EMDの数学的厳密版。高ボラ期間で予測精度向上報告。K+alphaの2パラメータ。

**Band-Pass CF** (Christiano & Fitzgerald 2003 IER) — 6-18ヶ月帯域抽出。momentum horizonに直接対応。one-sidedでリアルタイム可。

#### D. ロバスト推定量

**Median Momentum** (Huang et al. 2015 IJCAI) — 日次リターンの方向多数決。振幅完全無視。Winsoризationとは違い情報を「キャップ」ではなく「無視」。だがcrash初日を見逃すリスク。

**Trimmed Mean** — テール除外。Jump Detectionの簡易代替。除外割合1-2%なら影響限定的。

---

### [2026-03-31T21:35:00+09:00] 除外と保留の記録 — 車輪の再発明防止

殿の指示:
> 「除外の経緯も残しておかなければ後日また車輪の再発明で同じ作業をする羽目になるぞ」

**完全除外(再検討不要)**

| 手法 | 除外理由 |
|------|---------|
| HP Filter | Hamilton(2018)が「使うな」。端点バイアスで直近値が歪む。L1 Filterが上位互換かつmomentum検証済み |
| Deep Momentum Networks (Lim 2019) | ブラックボックス。PI-009準拠不可。BBアーキテクチャと設計思想が相容れない |
| Momentum Transformer (Wood 2022) | 同上。Attention weightで解釈可能だがBBに組込不可 |
| Winsorization | 殿却下(Phase 1)。テール情報=dual momentumのcrash切替シグナル。キャップは切替遅延 |

**保留(条件付き将来検討)**

| 手法 | 保留理由 | 再検討条件 |
|------|---------|-----------|
| Savitzky-Golay | L1/Kalmanが先。金融検証事例薄い | L1/Kalman結果後 |
| EEMD/CEEMDAN | VMDが数学的に厳密。EMD系はmode mixing問題 | VMD結果後 |
| Band-Pass (CF) | SSA/VMDも同カテゴリ(周波数分離)。3つ同時不要 | SSA/VMD結果後 |
| Sample Entropy | PEと同カテゴリ。PEの方が計算軽い。PEで先にゲート有効性検証 | PE結果後 |
| Shannon Entropy Gate | 離散化(bin幅)依存。PEがロバスト。ただしGupta(2025)でGold/USD 30-60%報告 | PE結果後 |
| Transfer Entropy | 概念最高度。実装最複雑。PE/SJMで先にレジーム判定を検証 | PE/SJM結果後 |
| Trimmed Mean | Jump Detectionの簡易代替。JDが計算高コストなら検討 | JD結果後 |
| Median Momentum | crash初日見逃しリスク。dual momentumの生命線と相性悪い | 他全手法後 |
| 対数リターン | FDの方が根本的(差分次数vs関数形) | FD結果後 |
| CUSUM Filter | Gerber閾値と目的近い(振幅vsα累積ベース) | Gerber結果後 |
| Denoised+Detoned Correlation | FoFレベル向き。standard PFでは1対1比較で相関行列不要 | FoF研究再開時 |
| Volatility Scaling (Barroso 2015) | LW Approach Aの簡易版。LW結果で判断 | LW結果後 |
| Graph Signal Processing (Ma 2023) | 実装複雑。グラフ構造にドメイン知識必要 | 当面不要 |

---

## [2026-03-31T21:48:00+09:00] Phase 2.5 続 — Gerber結果到着

### cmd_1628 Gerber閾値 — 半蔵(hanzo)完了

才蔵の初版は日次リターンレベルのGS1フィルタを実装していた(知識辞書M14の伝統的Gerber Statistic)。だがcmd仕様はmomentum差レベルのgate-level threshold。半蔵が検出し全面書換え。Phase 2の設計思想で書いた「cmd仕様とM14の違い」がまさにここで問題になった。

書換え後: 65PF × 5k = 325件のwalkforward完了。commit 6d694b88。

→ `outputs/analysis/standard_pf_preprocessing/gerber_threshold_study_results.yaml`

半蔵の教訓候補: 「cmd仕様のGerber適用レベル(gate vs return)を実装前に確認すべし」

### [2026-03-31T22:00:00+09:00] Gerber結果の衝撃 — 本命が劣化した

この時点での期待: Gerber閾値は殿の「本命の二つ」の一つ。ヒステリシスでwhipsawを抑制し、CAGR/Sharpeを改善するはず。

結果を開いた:

| PF | k=0.0(≈現行) CAGR | k=0.25 CAGR | k=0.5 | k=0.75 | k=1.0 | Whipsaw(k=0→1.0) |
|----|-------------------|-------------|-------|--------|-------|-------------------|
| DM2 | 40.0% | **31.4%(-21%)** | 30.9% | 25.6% | 24.2% | 36→26(-28%) |
| DM3 | 10.9% | 9.8%(-10%) | **6.2%(-43%)** | 2.8%(-74%) | 2.8% | 57→39(-32%) |
| DM5 | 41.6% | 35.2%(-15%) | 34.1% | 31.7% | **28.8%(-31%)** | 52→42(-19%) |
| DM6 | 50.4% | **29.0%(-43%)** | 25.8% | 20.3% | 21.3% | 44→19(-57%) |
| DM7+ | 26.7% | **32.1%(+20%)** | 32.1% | 32.4% | **41.8%(+56%)** | 8→20(+150%) |

**予想が裏切られた。** 殿の本命だったGerber閾値は、DM2/DM3/DM5/DM6の全てで**kを上げるほど劣化**した。whipsawは確かに削減されている(DM6: -57%)。だがwhipsaw削減がCAGR改善に繋がっていない。

**なぜ劣化したか**: ゲートが「小さな差はノイズ」として無視する。だがその「小さな差」の中に**本物のシグナル変更**も含まれていた。特にDM6(短期lookback=15日)では差分の変動が大きく、k=0.25でもCAGRが-43%。ノイズと真シグナルの分離ができていない。σスケールだけでは不十分。

**だがDM7+は例外的に+56%改善。** k=1.0でCAGR 26.7→41.8%。whipsawは8→20と**増加**している。一見矛盾する。

なぜDM7+だけ改善したか: DM7+はlookback=504日の超長期PF。504日windowでの差分はゆっくり動く。k=1.0のゲートは「504日差分が1σ以内なら現状維持」。つまり**長期トレンドが明確に変わるまでBUY継続**。これはトレンドフォローを強化する方向に働く。短期PFでは差分の変動が速いためゲートが真シグナルまでブロックするが、長期PFでは差分が安定しているためゲートがノイズだけをブロックできる。

**EMAのlookback依存性と同じ構造が見えた**: 前処理効果はlookback長に依存する。EMAは中lookbackで有効、Gerberは超長期lookbackで有効。短期lookbackには両方とも有害。

---

## [2026-03-31T22:03:00+09:00] Phase 2.5 続 — LW結果到着

### cmd_1630 Ledoit-Wolf — 影丸(kagemaru)完了

65PF × 8configs(baseline + A + B + C×5threshold) = 520 walkforward runs。commit 9529e010。

→ `outputs/analysis/standard_pf_preprocessing/ledoit_wolf_study_results.yaml`

### [2026-03-31T22:10:00+09:00] LW結果 — 仮説が確認された

Phase 2の設計時に書いた仮説: 「standard PFのticker数は5-15程度。LW共分散行列の次元が小さいのでshrinkage効果は限定的かもしれない。**だがそれ自体が検証結果として価値がある**」

結果:

| PF | baseline CAGR | A(リスク調整) | B(shrinkage) | C最良(ゲート) | 分析 |
|----|--------------|-------------|-------------|-------------|------|
| DM2 | 40.9% | 40.8%(不変) | **40.9%(完全同一)** | **42.8%(thr=1.0, +1.9pp)** | Cのみ微改善 |
| DM3 | 9.4% | 9.4%(不変) | **9.4%(完全同一)** | 全thr劣化 | 効果なし |
| DM5 | 35.7% | 35.7%(不変) | **35.7%(完全同一)** | 全thr劣化 | 効果なし |
| DM6 | 38.8% | 38.8%(不変) | **38.8%(完全同一)** | 39.1%(thr≥0.5, +0.3pp) | 微小 |
| DM7+ | 30.8% | 30.8%(不変) | **30.8%(完全同一)** | **30.8%(全thr完全同一)** | 完全不変 |

**Approach B(shrinkage)は全65PFでbaseline完全一致。** match_rate=1.000、whipsaw同数、CAGR同値。LWのshrinkage強度αが極めて小さく、momentumが全く変化していない。

**仮説が完全に確認された。** small-N(5-15 tickers)ではLW shrinkageの効果はゼロ。LWは高次元(数百銘柄)の共分散推定に効く手法であり、5-15次元の共分散行列には「shrinkageする必要がない」ほど推定が安定している。

**Approach A(リスク調整)も実質無効。** momentum/σ_LWで正規化しても、ランキングがほとんど変わらない。理由は同上: σ_LWとsample σがほぼ同一(shrinkageが効いていないから)。

**Approach C(ノイズゲート)はDM2でわずかに有効。** thr=1.0でCAGR +1.9pp、Sharpe 0.97→1.01、MaxDD -64.3→-61.9%。ゲートの閾値効果はGerberの結果と合わせて「DM2には閾値フィルタがわずかに効く」ことを示唆。ただしGerber(k=0.25)がDM2を-21%劣化させたのと矛盾する。LWゲートとGerberゲートでσの推定方法が違うため、同じ「閾値フィルタ」でも結果が異なる。

---

## [2026-03-31T22:12:00+09:00] Phase 4 — 3手法の横比較と驚き

### 本命がベースラインに負けた

| PF | EMA最良 | LW最良 | Gerber最良 | 勝者 |
|----|---------|--------|-----------|------|
| DM2 | +2.7%(span=21) | +1.9%(C thr=1.0) | **劣化** | EMA |
| DM3 | **+112%**(span=42) | **無効** | **劣化** | EMA(圧勝) |
| DM5 | +5.0%(span=5) | **劣化** | **劣化** | EMA |
| DM6 | **劣化**(全span) | +0.3%(微小) | **劣化** | 引分(全手法ほぼ無効) |
| DM7+ | +11.3%(span=5) | **完全不変** | **+56%**(k=1.0) | Gerber(大幅改善) |

**最もシンプルなEMAが最も広く効いた。** 殿の「本命」だったLW/Gerberは、EMAに完敗。これは予想の真逆。

### この結果をどう解釈するか

なぜシンプルなEMAが本命に勝ったのか。

**LWが無効な理由**: small-N問題。設計時の仮説通り。これは「LWが悪い」のではなく「適用領域が違う」。LWは数百銘柄の共分散推定用。5-15 tickersには不要。

**Gerberが大半で劣化した理由**: ゲート判定が「ノイズ」と「真シグナル」を分離できていない。σスケールでは不十分。momentum差の振幅だけでは判定精度が足りない。**ただしDM7+では有効** — lookbackが十分に長ければ差分が安定しゲートが機能する。

**EMAが広く効いた理由**: momentum計算の入力(close価格)を直接平滑化する。最も上流で介入する。ゲートやshrinkageは下流の判定・ランキングに介入するが、**ノイズの源泉は入力にある**。源泉を叩くEMAが最も効いた。

### 見えてきたパターン

1. **入力平滑化 > 判定フィルタ > 共分散推定** — ノイズの源泉に近いほど効果が大きい
2. **lookback長で有効な手法が異なる** — EMAは中lookback、Gerberは超長期、短期は全手法無効
3. **DM6(短期)は全手法が効かない** — 固定パラメータの手法ではラグが致命的。適応的手法(Kalman)の必要性がさらに明確に
4. **DM3が前処理の「リトマス試験紙」** — 最もノイズ脆弱なPF。EMAだけで+112%。これがさらに改善するかがL1/Kalmanの評価基準になる

### 保留手法の再検討条件が更新された

LW結果を受けて:
- **Volatility Scaling(Barroso 2015)**: LW Approach Aが無効 → Volatility Scalingも恐らく無効(同じ方向)。**保留→ほぼ除外**
- **CUSUM Filter**: Gerberが大半で劣化 → 同系統のCUSUMも期待薄。**ただしDM7+でGerberが有効だったので、長期PF限定なら検討余地**

---

## [2026-03-31T22:25:00+09:00] Phase 2.5 完結 — FD結果到着、4手法全て出揃う

### cmd_1631 Fractional Differentiation — 小太郎(kotaro)完了

5PF × 5d値(baseline/d_opt/0.3/0.5/0.7)。

→ `outputs/analysis/standard_pf_preprocessing/fractional_diff_results.yaml`

| PF | baseline CAGR | d_opt | d=0.3 | d=0.5 | d=0.7 |
|----|--------------|-------|-------|-------|-------|
| DM2 | 40.0% | 37.3%(-7%) | 37.3% | 37.2% | 38.8% |
| DM3 | 10.9% | 37.3% | 37.3% | **41.3%** | 23.4% |
| DM5 | 41.6% | 37.3%(-10%) | 37.3% | 37.2% | 34.3% |
| DM6 | 50.4% | 37.3%(-26%) | 37.3% | 34.7% | 32.6% |
| DM7+ | 26.7% | 11.1%(-58%) | 12.6% | 15.8% | 11.4% |

**深刻な問題を発見。** d_optとd=0.3で全PFのCAGR/Sharpe/MaxDD/whipsawが**完全同一**(37.3%/0.8583/-0.7466/whipsaw=0)。全PFが同じシグナルを出している。whipsaw=0は「一度もシグナル変更なし」= 常にBUY維持。

d<1の分数次差分で系列が非定常に近づき、FFD値が全資産で単調増加→常にBUY。match_rate_vs_baseline=27%前後で現行とは全く異なるシグナル。DM3のd=0.5でCAGR 41.3%は一見改善だが、match_rate=27%で**別戦略**になっている。

**結論: FDはstandard PFの前処理としては使えない。** pct_changeの代替としてのFFDは、momentum計算の構造と合わない。除外リストに追加。

---

## [2026-03-31T22:28:00+09:00] Phase 4 — 4手法全結果と殿の問い

### 4手法の最終横比較

| 手法 | 有効PF | 最大改善 | 無効/劣化 | 判定 |
|------|--------|---------|-----------|------|
| **EMA** | DM2/DM3/DM5/DM7+ | DM3 +112% | DM6(短期) | **最有力** |
| **Gerber** | DM7+のみ | DM7+ +56% | 大半で劣化 | 長期PF限定 |
| **LW** | なし | DM2 +1.9pp | small-Nで無力 | standard PFでは不要 |
| **FD** | なし | — | 全PF劣化/異常 | 不適切。却下 |

入力平滑化(EMA) > 判定フィルタ(Gerber) > 共分散推定(LW) > 差分変更(FD)。ノイズの源泉に近い手法ほど効果が大きい。

### [2026-03-31T22:30:00+09:00] 殿の指摘 — 5PFで一般化するな

> 「シン四神もstandardPFなのは理解しているか？シン四神でも同じ結果が出るか？」

EMA研究(cmd_1629)は5PFだけだった。Gerber/LWは65PF全部を対象にしていたが、EMAだけ5PF。シン四神12体を含む65PF全体でEMAを検証しないと、一般化はできない。5PFの結果をシン四神に適用するのは確認なき想像。

殿: **「どうせなら65PF全部でやるのを標準化しないか？」**

修正: cmd_1632(EMA 65PF拡張)を起票。今後の全研究cmdは**65PF全部を標準**とする。5PFだけの研究は二度とやらない。

---

## [2026-03-31T22:38:00+09:00] Phase 5 — 視界が変わった瞬間

### 殿の問い — 最終形を見ろ

> 「デュアルモメンタムをアセットとして扱うFoFやネステッドFoFが俺らにはある。」

この一言で研究のスコープが根本から変わった。

**今まで見ていたもの**: standard PFのmomentum計算に前処理を適用 → standard PF単体のCAGR/Sharpe改善。Layer 0だけ。

**見えていなかったもの**: 我々のシステムは多層構造。

```
Layer 0: 個別資産の価格 → momentum計算 → standard PF → リターン系列
Layer 1: standard PFのリターン → momentum計算 → FoF → リターン系列
Layer 2: FoFのリターン → momentum計算 → Nested FoF → 最終出力
```

**各レイヤーにmomentum計算がある。各レイヤーに前処理の余地がある。**

DM3のCAGR +112%は第一層の結果にすぎない。DM3を含むFoFのリターンがどう変わるかを見ていない。最終出力で測っていない。**最終形で測らなければ、改善したかどうか分からない。**

さらに殿が射程を広げた:

> 「レイヤー毎の研究とレイヤーを重ねたペアとしての研究、そして全てのレイヤーを通した全体の研究。よくみれば我らの三層学習ループと同じだ。」

**三層学習ループとの対応**:

```
三層学習ループ          前処理研究の三層
─────────────────────────────────────────────────────────
第一層 = 個             各レイヤー単独の前処理効果
(各自の仕事)           L0: standard PFにEMA → CAGR +112%
                        L1: FoFのmomentum計算に前処理 → ?

第二層 = 対             レイヤーペアの伝播効果
(二者の組)             L0→L1: standard PF前処理がFoFシグナルをどう変えるか
                        L1→L2: FoF前処理がNested FoFをどう変えるか

第三層 = 全             全レイヤー通しの最終出力
(鎖全体)               前処理済みL0 → 前処理済みL1 → Nested FoF
                        最終リターン/Sharpe/MaxDDで計測
```

三層を**同時に並列で**見る。第一層を終えてから第二層ではない。

**効果の伝播パターン**:
- **間接波及**: L0の前処理でstandard PFのリターン改善 → FoFの入力品質が自動的に上がる
- **直接適用**: FoFのmomentum計算にも前処理を適用 → FoF内の判定品質が上がる
- **乗算効果**: 間接波及×直接適用。各レイヤーの改善が独立に効く。掛け算。

**lookback依存性がレイヤーごとに異なる可能性**:
- L0: 日次データ、lookback数十〜数百日 → EMAが圧勝
- L1: 月次データ、lookback数ヶ月(短い) → Gerber/Entropyが効くかも？
- 同じ前処理でもレイヤーによって最適なものが違いうる

### この研究の本当のスコープ

「standard PF前処理研究」ではない。**「多層momentum計算システムの各レイヤーにおける最適前処理の特定と、レイヤー間伝播効果の定量化」**。

殿: 「何が効果をもたらすかはまだ分からない。切りがなくて最高に面白いな！」

---

## [2026-04-01T00:00:00+09:00] Phase 8 — 第二バッチ結果: L1が圧勝、Kalmanが問いを投げた

### cmd_1632 EMA 65PF — 5PFパターンは本物だった

65PF全数でのEMA結果(commit bd88221d)。5PFで見た傾向が65PF全体でも再現された。DM3 +112%は5PFの偶然ではない。

| PF | baseline | 最良span | CAGR | 変化 |
|----|----------|---------|------|------|
| DM2 | 40.0% | span_21 | 41.1% | +2.8% |
| DM3 | 10.9% | span_42 | **23.1%** | **+112%** |
| DM5 | 41.6% | span_5 | 43.7% | +5.0% |
| DM6 | 50.4% | 全滅 | 28.6%最悪 | **全劣化** |
| DM7+ | 26.7% | span_5 | 29.7% | +11.3% |

→ `outputs/analysis/standard_pf_preprocessing/ema_smoothing_results_full.yaml`

### cmd_1633 L1 Trend Filter — EMAの3倍以上の改善

L1 Trend Filter結果(commit影丸完了)。EMAの上位互換仮説を検証。

| PF | baseline | λ=1 | λ=10 | λ=100 | λ=1000 | 最良 |
|----|----------|-----|------|-------|--------|------|
| DM2 | 40.0% | 40.1% | 42.7% | **44.1%** | 41.0% | λ=100 **+10%** |
| DM3 | 10.9% | 12.4% | 12.1% | 23.8% | **52.6%** | λ=1000 **+383%** |
| DM5 | 41.6% | 43.1% | 44.7% | **50.6%** | 47.0% | λ=100 **+22%** |
| DM6 | 50.4% | 34.6% | 37.4% | 12.4% | 1.2% | **全劣化(壊滅的)** |
| DM7+ | 26.7% | 29.5% | 29.7% | 28.5% | **31.3%** | λ=1000 +17% |

→ `outputs/analysis/standard_pf_preprocessing/l1_trend_filter_results.yaml`

**DM3のCAGRが10.9%→52.6%。5倍近い。** EMAの23.1%(+112%)を遥かに超えた。

だがPhase 6の警告が鳴り響く:
- **λ感度が極めて高い**: DM3でλ=100→23.8%, λ=1000→52.6%。隣のパラメータで2倍変わる
- **DM6は壊滅的**: λ=1000でCAGR 1.2%(baseline 50.4%)。-98%。EMA劣化(-43%)より遥かに酷い
- **ユニバーサルλは存在しない**: DM2/DM5はλ=100最良、DM3/DM7+はλ=1000最良、DM6は全λで劣化

L1はEMAの「上位互換」ではない。**EMAの延長線上にある、より強力だがより危険な平滑化。** 効果が大きい分、失敗も大きい。折れ点保存(ラグ最小)の利点はDM6で発揮されなかった — L1のラグがEMAより小さいはずなのに、DM6の劣化はEMAより酷い。ラグ以外の原因がある。

### cmd_1634 Kalman Filter — 「平滑化は不要」と言ったデータ

Kalman Filter結果(commit 48c938de)。Phase 6 B3原則(auto推定=overfitゼロ)の試金石。

| PF | baseline | auto(B3) | qr_0.01 | qr_0.1 | qr_1.0 |
|----|----------|---------|---------|--------|--------|
| DM2 | 40.0% | 40.0%(不変) | 39.8% | 39.0% | **41.1%(+3%)** |
| DM3 | 10.9% | **12.2%(+12%)** | **17.4%(+60%)** | 11.1% | 12.6% |
| DM5 | 41.6% | 38.8%(-7%) | 39.3%(-5%) | 39.2%(-6%) | 35.4%(-15%) |
| DM6 | 50.4% | 46.4%(-8%) | 27.6%(-45%) | 38.0%(-25%) | **48.6%(-4%)** |
| DM7+ | 26.7% | 26.7%(不変) | 29.3%(+10%) | **29.7%(+11%)** | 29.5%(+10%) |

→ `outputs/analysis/standard_pf_preprocessing/kalman_filter_results.yaml`

- **B3(auto推定)全PF平均CAGR=33.9%。best fixed(qr_0.1)=35.2%。auto推定は-1.3pp**
- auto推定のQ/R比は2.8-6.5に収束 = **「ほとんど平滑化するな」とデータが言っている**
- DM3 auto: +12%のみ。EMA +112%、L1 +383%と比較にならない

**ここに深い矛盾がある。**

Kalmanのauto推定は「予測誤差最小化」を目的関数にしてQ/Rを最適化する。その結果は「ほぼ平滑化しない」。だがEMA/L1は手動パラメータで大きく平滑化すると、戦略パフォーマンスが劇的に改善する。

**予測精度の最適化 ≠ 戦略収益の最適化。** Kalmanが最小化するのは「明日の価格の予測誤差」。EMA/L1が改善するのは「momentum信号の品質」。これは別の目的関数。価格の正確な予測が最良の投資判断を生むとは限らない。ノイズを強く削った「不正確」な系列が、momentum判定には最適かもしれない。

この矛盾はPhase 6の問いを深める: **EMA/L1の改善は「本物の信号品質向上」か、それとも「偶然にバックテストに合ったパラメータ」か？** Kalmanが「不要」と言った平滑化が巨額の利益を生む。どちらが正しいのか。

### cmd_1635 Entropy Gate PE — ほぼ不発

Entropy Gate PE結果(疾風完了)。メタフィルタ(信号を信頼すべきかの判定)方向の検証。

→ `outputs/analysis/standard_pf_preprocessing/entropy_gate_pe_results.yaml`

**問題**: ほぼ全configでno_gateと同一結果。PE閾値0.8/0.9はほぼ発火しない。唯一発火するthr=0.7は大幅劣化(DM7+ -42%、DM6 -26%)。

- **実装の構造的疑問**: no_gateでもwhipsaw=0(全PF)。EMA研究のDM2 whipsaw=36と整合しない。月次walkforward粒度の可能性。日次walkforwardと直接比較できない
- **暫定結論**: PE単体でのメタフィルタは現時点で効果なし。ただし実装の粒度問題を解決してから最終判断

### [2026-04-01T00:10:00+09:00] 7手法横比較 — Phase 8完了時点

| 手法 | 種類 | DM3(リトマス紙) | DM2 | DM5 | DM6 | DM7+ | overfitリスク |
|------|------|----------------|-----|-----|-----|------|-------------|
| **L1 Trend** | 入力平滑化 | **+383%** | +10% | +22% | **-98%** | +17% | **極高**(λ感度大) |
| **EMA** | 入力平滑化 | **+112%** | +3% | +5% | -43% | +11% | 高(span選択) |
| Kalman(auto) | 入力平滑化 | +12% | ±0% | -7% | -8% | ±0% | **ゼロ** |
| Gerber | 判定フィルタ | -43% | -21% | -31% | -43% | **+56%** | 高(k選択) |
| Entropy PE | メタフィルタ | — | ±0% | ±0% | ±0% | ±0% | — |
| LW | 共分散推定 | ±0% | +1.9pp | ±0% | +0.3pp | ±0% | 低 |
| FD | 差分変更 | 異常 | 異常 | 異常 | 異常 | 異常 | — |

**パターンが明確になった**:

1. **入力平滑化の強度と改善幅は比例する。** L1(強い平滑化) > EMA(中程度) > Kalman auto(ほぼ素通し)。だが強い平滑化はDM6を壊滅させる
2. **改善が大きい手法ほどoverfitリスクが高い。** L1のλ感度は極めて高い。EMAのspan感度も高い。overfitリスクゼロのKalman autoは改善もゼロ
3. **lookback依存は全手法共通。** 中長期lookback(DM3=126日, DM5=42日, DM7+=504日)で有効、短期(DM6=15日)で有害。手法を変えても構造は同じ

### 未解決の問い

- **Kalmanの矛盾**: 予測精度最適化が「平滑化不要」と言い、手動平滑化が巨額の利益を出す。どちらが信号の「真の品質」を反映しているのか？
- **DM6問題**: 全平滑化手法で劣化。短期lookbackでは何が効くのか？ 平滑化以外のアプローチ(エントロピーゲート、ジャンプ除去、レジーム検出)が必要か？
- **OOS検証**: L1 +383%はoverfitか本物か？ データ前半/後半分割で検証が必要
- **ユニバーサルパラメータ**: per-PF最適化なしで機能するパラメータは存在するか？

---

---

## [2026-03-31T22:50:00+09:00] Phase 6 — 殿の警告: 二つの罠

> 「ルックアヘッドバイアスと過剰最適化。この2つには気をつけろ。」

Phase 4までの結果に浮かれていた。DM3 +112%、DM7+ +56%。だが殿はその裏にある構造的リスクを指摘した。

### ルックアヘッドバイアス — パラメータ選択の見えないbias

我々のwalkforwardは時系列を尊重している(expanding window, 過去データのみで判定)。momentum信号自体にlook-ahead biasはない(cmd_276で検証済み、→ `context/dm-signal-research.md` §20)。

**だが、前処理パラメータの選択にbiasがある。**

EMA span=[0,5,10,21,42]の5つを試し、DM3ではspan=42が最良と報告した。しかしこの「42が最良」は全walkforward結果を見た後の判断。本番で使うなら、walkforward開始前にspanを決めなければならない。最良パラメータの事後選択 = パラメータ選択のlook-ahead bias。

信号のlook-ahead bias(cmd_276)は「未来の価格を使っていないか」。パラメータのlook-ahead biasは「結果を見てからパラメータを選んでいないか」。後者は前者より遥かに見えにくい。

### 過剰最適化 — 多重比較の罠

5 spans × 65 PFs = 325件。4手法 × 複数パラメータで既に1000+件のバリエーション。これだけ試せば、偶然にも「改善」に見える組合せが必ず見つかる(多重比較問題)。

DM3のspan=42で+112%は本物か？ 検証する方法は3つ:

1. **パラメータ感度**: span=42だけが良くてspan=21/10が劣化なら、overfitの疑い。近傍パラメータでも改善が続くなら、robustな改善
2. **OOS検証**: データ前半でパラメータ選択 → 後半でそのパラメータを検証。後半でも改善が残るか？
3. **ユニバーサルパラメータ**: 全PFで同一paramを使って改善するか？ per-PFチューニングなしで

### [2026-03-31T22:52:00+09:00] 研究設計原則 — Phase 6以降の全CMDに適用

殿の警告を受け、以下を今後の全研究CMDの共通要件とする:

| # | 原則 | 具体的AC要件 |
|---|------|-------------|
| B1 | **パラメータ感度テーブル** | 最良だけでなく全パラメータでの結果を報告。近傍パラメータとの差を明示 |
| B2 | **ユニバーサル最良パラメータ** | 全PF平均で最良のパラメータを特定。per-PFベストとユニバーサルベストを両方報告 |
| B3 | **自動パラメータ推定を優先** | Kalman(Q/R自動推定)のように、データからパラメータが決まる手法を優先。手動チューニングが必要な手法は感度報告必須 |
| B4 | **OOS分割(段階的)** | 将来的にデータ前半/後半分割でパラメータ選択を検証。まず第一層の全手法が揃ってから横断OOS検証を実施 |

**B3が最も重要。** 自動推定パラメータは構造的にlook-ahead biasを持たない。Kalman FilterのQ/R自動推定、PEの理論最適embedding dimensionなど。手動パラメータ(EMA span, Gerber k, L1 lambda)は感度テーブルで「偶然か本物か」を判定する必要がある。

**Phase 4の結果への影響**: EMAの結果は「span感度が高い or 低い」で信頼度が変わる。cmd_1632(65PF拡張)の結果で、span感度を65PF全体で確認する。DM3のspan=42が偶然なら、65PF中の大半でspan=42が無効のはず。

---

## [2026-03-31T22:55:00+09:00] Phase 7 — 三層研究CMD設計

### 設計方針

Phase 5の三層構造 × Phase 6のbias対策を統合。第一層(個)の次のバッチとして3手法を設計。

**手法選択の根拠**:
- **L1 Trend Filter**: EMAの上位互換候補。区分線形→ラグ最小。momentum文献で直接検証済み(Bruder 2013)。lambda=手動パラメータ → B1+B2必須
- **Kalman Filter**: 自動パラメータ推定(B3)。DM6問題(全手法で劣化)への最有力対策。SNR適応型 → overfitリスク構造的に低い
- **Entropy Gate PE**: 全く別方向(メタフィルタ)。信号を加工するのではなく信号の信頼度を判定。Phase 3 空白2を埋める。理論最適m=5-7で手動チューニング最小

### cmd_1633: L1 Trend Filter 65PF(Layer 0)

EMAの上位互換を検証。EMAは全時点を等しく平滑化するがL1は折れ点を保存。DM6(短期)でEMAが全滅した原因が「ラグ」なら、L1で解決しうる。

- 対象: 65 standard PF(cmd_1632と同一)
- lambda = [0, 1, 10, 100, 1000] (0=no filter, baseline)
- 結果: l1_trend_filter_results.yaml
- **B1**: lambda感度テーブル(65PF × 5lambda)
- **B2**: ユニバーサル最良lambda + per-PF最良lambdaを両方報告
- 実装: cvxpy凸最適化。ema_smoothing_study.pyをベースに平滑化関数をL1に置換
- 325件(65×5)。EMAと同規模

### cmd_1634: Kalman Filter 65PF(Layer 0)

自動パラメータ推定 = Phase 6のB3原則に最も合致。DM6問題への最有力候補。

- 対象: 65 standard PF
- mode_1: auto-estimated Q/R (主実験。パラメータ手動設定なし)
- mode_2: fixed Q/R ratios [0.01, 0.1, 1.0] (auto推定との比較用)
- 結果: kalman_filter_results.yaml
- **B3**: auto推定モードがメイン。「パラメータなしで前処理が効くか」の試金石
- **B1**: fixed Q/Rの感度テーブル(auto推定の妥当性検証用)
- 実装: pykalman or 手書きKalman。ema_smoothing_study.pyベース
- 260件(65×4mode)

### cmd_1635: Entropy Gate PE 65PF(Layer 0)

全く別方向。信号加工ではなく「信号を使うべきかの判定」。Phase 3 空白2を埋める。

- 対象: 65 standard PF
- PE parameters: m=5(理論最適), τ=1, window=[21, 42, 63]
- threshold: [no_gate, 0.7, 0.8, 0.9](PE値の閾値)
- 結果: entropy_gate_pe_results.yaml
- **B1**: window×threshold感度テーブル
- **B2**: ユニバーサル最良window+threshold
- 動作: PE > threshold → CASH維持(momentum信号を無視)。PE ≤ threshold → 通常判定
- 実装: scipy.stats不要。Permutation Entropy(Bandt & Pompe 2002)は50行以下で実装可能
- 780件(65×12configs)

---

## [2026-04-01T01:15:00+09:00] Phase 9 — 学術文献探索(直近5年)

殿の指示: 「先に進みすぎず、参考になりそうな直近5年ほどの論文を探索してみないか？」

### 発見1: Valeyre (2025) — 単一EMAが最適、複雑化は cherry-picking

> Valeyre, S. (2025). "Breaking the Trend: How to Avoid Cherry-Picked Signals." arXiv:2504.10914

**我々の研究に直撃する論文。** CTAのトレンドフォロー戦略において、1つのシンプルなEMAだけで最適な性能が出る。複数の複雑な指標をブレンドすると、cherry-picking(=過剰最適化)のリスクに晒される。理論的なSharpe公式(Grebenkov & Serror 2014)との実証的フィットが示されている。

**我々への示唆**: L1 Trend Filter(+383%)がEMA(+112%)を大幅に上回った。だがValeyreの結論は「EMAで十分であり、それ以上の複雑化は過適合の危険」。L1のλ感度の高さ(Phase 8で指摘)は、まさにcherry-pickingパラメータの兆候かもしれない。

**ただし注意**: Valeyreの対象はCTA(先物クロスセクショナルmomentum)。我々はETF dual momentum(時系列momentum)。文脈が異なる。結論が直接適用可能かは検証が必要。

### 発見2: Levy & Lopes (2021) — Dynamic Momentum Learning

> Levy, B.P.C. & Lopes, H.F. (2021). "Trend-Following Strategies via Dynamic Momentum Learning." arXiv:2106.08420

56先物契約でlookback期間の**時変的重要度**を動的に学習。binary classifierがlookbackの「速度」を逐次切替。

**我々への示唆**: DM6(15日)とDM7+(504日)で最適な前処理が異なる問題。Levy方式なら「今は短期lookbackが有効な局面か」を自動判定し、前処理パラメータを適応的に切替えられる。固定パラメータの限界(Phase 8で明確)に対する有力な解。

### 発見3: Bailey & López de Prado — PBO + Deflated Sharpe Ratio

> Bailey, D.H. et al. (2014). "The Probability of Backtest Overfitting." SSRN:2326253
> Bailey, D.H. & López de Prado, M. (2014). "The Deflated Sharpe Ratio." SSRN:2460551

**Phase 6の殿の警告を定量化するフレームワーク。**

- **PBO (Probability of Backtest Overfitting)**: in-sampleでベストだった設定がout-of-sampleで中央値以下になる確率。CSCV (Combinatorially Symmetric Cross-Validation)で計測
- **DSR (Deflated Sharpe Ratio)**: 試行回数・非正規性を考慮してSharpe Ratioを補正。「何回試したか」が最重要情報

**我々への適用**: 7手法×5-8パラメータ×65PF = 数千回の試行。PBO/DSRで「DM3 L1 λ=1000の+383%は偶然か本物か」を定量判定できる。López de Pradoは我々のFDの参考文献(AFML)の著者でもある — 彼自身が過適合を最も警戒している。

### 発見4: "Revisiting the Structure of Trend Premia" (Oct 2025)

> arXiv:2510.23150

20日と500日のhorizonが支配的。中期(60-125日)はunderperform。

**我々への示唆**: DM7+(504日)でGerber +56%/EMA +11%が有効で、DM6(15日短期)が全手法劣化するパターンと整合。**中期(DM3=126日)でEMAが+112%なのは、この論文の知見に反する** — 中期は一般にunderperformとされるが、我々のDM3では前処理で劇的改善。DM3の「ノイズ脆弱性」が特異なのか、ETF dual momentumが先物と構造的に違うのか。

### 発見5: Nystrup & Kolm — Greedy Online Classifier

> Nystrup, P. & Kolm, P.N. (2020). "Greedy Online Classification of Persistent Market States." SSRN:3594875

リアルタイムでレジーム(Bull/Normal/Crisis)を分類。ジャンプペナルティで状態の持続性を強制。SJM(Shu et al. 2024)の先行研究。

### 発見6: "When the Rules Change" (2026)

> arXiv:2601.05716

Adaptive Kalman Filter + Markov-Switching。韓国株市場2020-2024。市場ボラティリティに連動する測定ノイズ分散。

**我々のKalman auto推定(cmd_1634)のQ/R比が2.8-6.5に収束した問題**への解の方向: 固定Q/Rではなくレジーム依存Q/Rなら、トレンド局面で強い平滑化、レンジ局面で軽い平滑化。

### [2026-04-01T01:20:00+09:00] 文献探索の総括 — 何が見えたか

**3つの方向が浮上した**:

1. **シンプルで十分かもしれない(Valeyre)**: 1つのEMAが最適。複雑化=cherry-picking。我々のL1 +383%は過適合の疑い濃厚。EMAの+112%すらparameter snoopingの可能性がある。PBO/DSRで定量検証が急務

2. **適応的手法が鍵かもしれない(Levy, arXiv:2601.05716)**: 固定パラメータの限界はPhase 8で明白。lookback期間やQ/Rをレジームに応じて動的に切替える方法が、DM6問題を解決しうる唯一の方向

3. **中期momentumの特異性(arXiv:2510.23150)**: 20日/500日が支配的、中期はunderperform。だがDM3(126日)は前処理で劇的改善。この「中期の特異な応答性」が我々のstandard PF固有の現象なのか、ETF dual momentumの構造的特徴なのか

### [2026-04-01T01:30:00+09:00] 追加探索 — 30本の論文から見えた7つの知見

広域サーベイで30本以上の2020-2026論文を精査。特に重要な新発見:

**発見7: Boubaker et al. (2021) — FDAでTSMOM Sharpe 0.07→0.75**

> Boubaker, S., Liu, Z., Lu, S. & Zhang, B. (2021). "Trading signal, functional data analysis and time series momentum." Finance Research Letters, 42. DOI:10.1016/j.frl.2021.101852

Functional Data Analysis(関数データ解析)で離散価格を滑らかな曲線に変換し、1階/2階微分からmomentum信号を生成。24コモディティ(2010-2018)でTSMOM Sharpe 0.07→0.75。**2009年以降消滅したTSMOMの収益性を復活させた。**

**我々への示唆**: EMA/L1は離散的な平滑化。FDAは「曲線として」扱う根本的に異なるアプローチ。derivative-based signalは我々のpct_change→weighted averageとは全く違う信号を生成する。

**発見8: Goulding, Harvey & Mazzoleni (2024) — 転換点が致命傷**

> Goulding, C.L., Harvey, C.R. & Mazzoleni, M. (2024). "Breaking Bad Trends." Financial Analysts Journal, 80(1). DOI:10.1080/0015198X.2023.2270084

転換点(turning points)がTSMOMの弱点。リターンをBull/Correction/Bear/Reboundの4phaseに分類し、slow(12M)/fast(1M)momentumの重みを動的切替。43先物市場(1990-2022)。

**我々への示唆**: DM6の全手法劣化は「短期lookbackでは転換点の頻度が高すぎる」が原因かもしれない。Phase分類→動的切替は、固定パラメータの限界を超える方向。

**発見9: Arian et al. (2024) — CPCVが最良のOOS検証法**

> Arian, H.R., Norouzi, D. & Seco, L.A. (2024). "Backtest overfitting in the machine learning era." Knowledge-Based Systems, 300. DOI:10.1016/j.knosys.2024.112357

CPCV(Combinatorial Purged Cross-Validation)がK-Fold、Purged K-Fold、Walk-Forwardより過適合検出で優位。PBO最低、DSR最高。

**我々への適用**: OOS検証のフレームワーク選択。単純な前半/後半分割ではなくCPCVを使うべきか。

**発見10: Shi & Lian (2025) — 手法より時間軸が重要**

> Shi, C. & Lian, X. (2025). "Trend Following Strategies: A Practical Guide." SSRN:5140633

中国先物(1999-2019)でフィルタタイプ(手法)よりtime horizon(時間軸)選択の方が重要。multi-scaleの組合せが最良(年率16.24%, Sharpe 0.88)。

**Phase 8の知見「lookback長が前処理効果を支配」と完全に整合。** 我々がEMA/L1/Kalman/Gerberで見た差は、手法の差というよりlookbackとの相性の差。

**発見11: Kang (2026) — Adaptive Kalman+MSはOOS一般化が脆弱**

> Kang, S. (2026). arXiv:2601.05716. 韓国株2020-2024。

Adaptive Kalman+Markov Switching: in-sampleでSharpe 1.08, Calmar 0.92。**だがOOS一般化は脆弱。** in-sampleの規則性がOOSで再現しない。

**我々への警告**: 適応的Kalman(レジーム連動)を次候補に挙げていたが、OOS脆弱性を示す論文がある。期待を下げるべき。

### [2026-04-01T01:35:00+09:00] 文献探索の7大知見

| # | 知見 | 根拠 | 我々の研究への影響 |
|---|------|------|------------------|
| 1 | **シンプルで十分** | Valeyre(2025): 1-EMA最適 | L1の+383%はoverfitの疑い |
| 2 | **手法より時間軸** | Shi(2025): horizonが支配的 | lookback依存はuniversal |
| 3 | **転換点が致命傷** | Goulding(2024): turning point | DM6問題の説明。Phase分類が解 |
| 4 | **FDAで劇的改善** | Boubaker(2021): Sharpe 0.07→0.75 | derivative-based signalは未探索 |
| 5 | **Adaptive Kalman脆弱** | Kang(2026): OOS一般化失敗 | 適応Kalman優先度を下げる |
| 6 | **CPCVが最良OOS法** | Arian(2024): PBO最低 | OOS検証にCPCVを使うべき |
| 7 | **multi-scale組合せが最良** | Shi(2025), Levy(2021) | 単一lookbackではなく動的組合せ |

### 次の手の方向性

文献探索で方向が明確になった:

- **急ぐべきでない。** Valeyreが「シンプルで十分」と言い、PBO/DSRが「試行回数を報告せよ」と言う。手法を増やす前に、既存結果の頑健性を検証すべき
- **OOS検証(Phase 6 B4)が最優先。** EMA 65PF結果があるので、CPCV(Arian 2024)またはデータ分割でEMAの+112%がoverfitか本物か判定
- **PBO/DSRの計算。** 既に7手法×複数パラメータの結果がある。PBOフレームワークで全体の過適合確率を算出
- **FDAは新方向として有望。** Boubaker(2021)のSharpe 0.07→0.75は最大の改善報告。EMA/L1とは直交するアプローチ
- **適応的Kalman(レジーム連動)は優先度を下げる。** Kang(2026)がOOS脆弱性を示した

---

## 知識基盤 (参照先)

| ID | 内容 | 場所 |
|----|------|------|
| M13 | MP Denoising (Random Matrix Theory) | `docs/research/knowledge-base/methods/m13_mp_denoising.md` |
| M14 | Gerber Statistic (GS0/GS1/GS2) | `docs/research/knowledge-base/methods/m14_gerber_statistic.md` |
| M15 | Shrinkage Estimators (LW/OAS/GraphicalLasso) | `docs/research/knowledge-base/methods/m15_shrinkage_estimators.md` |
| M16 | OPTICS Clustering | `docs/research/knowledge-base/methods/m16_optics_clustering.md` |
| D07 | 共分散前処理 DM-Signal解釈 | `docs/research/knowledge-base/interpretation/d07_covariance_preprocessing.md` |
| cmd_1627 | BB前処理偵察(注入ポイント) | `queue/reports/hanzo_report_cmd_1627.yaml` / `kagemaru_report_cmd_1627.yaml` |

## 学術文献 (サーベイで発見)

| 手法 | 主要文献 | 金融での検証 |
|------|---------|-------------|
| L1 Trend Filter | Bruder, Dao, Roncalli (2013) SSRN:2289097; Dao (2014) arXiv:1403.4069 | S&P500 momentum直接テスト |
| Kalman Filter | Benhamou (2018) arXiv:1808.03297 | S&P500先物。MA系を大幅上回る |
| Jump Detection | Lee & Mykland (2008) RFS; Barndorff-Nielsen & Shephard (2006) | 金融データで検証済み |
| Permutation Entropy | Bandt & Pompe (2002) PRL; Zunino et al. (2009) | 市場効率性分析 |
| Shannon Entropy Gate | Gupta et al. (2025) arXiv:2503.06251 | Gold/USD 30-60%年リターン |
| Transfer Entropy | Liu et al. (2020) Entropy/MDPI | 2003-2014 3レジーム検出 |
| SSA | Hassani & Thomakos (2010); Gianfrancesco et al. (2025) MDPI | Sharpe 1.88 |
| VMD | Dragomiretskiy & Zosso (2014) IEEE TSP; Chen et al. (2024) | S&P500/DJIA予測 |
| SJM | Shu, Yu & Nystrup (2024) J Asset Mgmt | downside risk削減 |
| Volatility Scaling | Barroso & Santa-Clara (2015) JFE | momentum crash防御 |
| Savitzky-Golay | Savitzky & Golay (1964) | 金融応用は新しい |
| Median Momentum | Huang et al. (2015) IJCAI | ポートフォリオ選択 |
| Band-Pass (CF) | Christiano & Fitzgerald (2003) IER | マクロ→金融応用可 |
| Fractional Diff | López de Prado (2018) AFML Ch.5 | 金融MLの基礎文献 |
| **Cherry-Pick回避** | **Valeyre (2025) arXiv:2504.10914** | **CTAで1-EMAが最適。複雑化=cherry-picking** |
| Dynamic Lookback | Levy & Lopes (2021) arXiv:2106.08420 | 56先物。動的lookback切替。速度適応 |
| PBO/DSR | Bailey & López de Prado (2014) SSRN:2326253/2460551 | backtest過適合確率。試行回数補正 |
| Trend Premia構造 | arXiv:2510.23150 (Oct 2025) | 20d/500d支配的。中期underperform |
| Greedy Online Classifier | Nystrup & Kolm (2020) SSRN:3594875 | リアルタイムレジーム分類+ジャンプペナルティ |
| Adaptive Kalman+MS | arXiv:2601.05716 (Jan 2026) | ボラ連動Q/R+Markov Switching。韓国株 |
| Network Momentum | arXiv:2501.07135 (Jan 2025) | クロスセクショナルmomentum spillover |
| **FDA Smoothing** | **Boubaker et al. (2021) FRL** | **TSMOM Sharpe 0.07→0.75。最大改善報告** |
| Breaking Bad Trends | Goulding, Harvey, Mazzoleni (2024) FAJ | 転換点=弱点。4phase動的切替 |
| CPCV | Arian, Norouzi, Seco (2024) KBS | 最良OOS検証法。PBO最低 |
| Momentum手法vs時間軸 | Shi & Lian (2025) SSRN:5140633 | 手法<horizon。multi-scale最良 |
| Slow Momentum+CPD | Wood, Roberts, Zohren (2021) arXiv:2105.13727 | CPDでSharpe +33% |
| Zakamulin & Giner | (2020) Quant Finance 20(6) | MA>MOM。弱トレンドで差拡大 |
| Overfit Detection Framework | Goyle (2024) SSRN:5331456 | momentum(J,K,N)パラメータ過適合検出 |
