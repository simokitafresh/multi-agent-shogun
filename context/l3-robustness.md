# L3堅牢性検証 — 知見と方針の永久保存
<!-- last_updated: 2026-04-09 -->

> 管理責任: 家老(karo)
> 最終更新: 2026-03-16（cmd_992 鮮度確認）
> 目的: L3検証の経緯・方針転換・最終結論・次のhowを一元記録する

---

## 1. 概要 — L3検証とは何か

L3検証は、L2忍法FoF（5忍法×3モード=最大15体）の堅牢性を検証する仕組みである。

DM-signalの研究レイヤー構造:

| Layer | 名前 | 内容 |
|-------|------|------|
| L0 | 基本PF | 個別DM戦略のパラメータGS（172,818パターン） |
| L1 | 四神FoF | L0チャンピオンをGreedy Forward Selectionで組合せ（青龍/朱雀/白虎/玄武） |
| L2 | 忍法FoF | 5忍法(分身/追い風/抜き身/変わり身/加速)×3モード(激攻/鉄壁/常勝)で四神を乗り換え |
| L3 | 堅牢性検証 | L2忍法FoFが過剰最適化でないことを検証する |

L3の問いは「L2忍法の優位性は本物か、それとも多層ネストによる偶然の積み上げか」である。

---

## 2. 当初アプローチ（WF合議 — cmd_176）

### 2.1 合議の概要

cmd_176でOpus 4名(hayate, kagemaru, hanzo, saizo)+Codex 2名(sasuke, kirimaru)の6名合議を実施。テーマはL3堅牢性検証の設計。

### 2.2 Q0分析: WHY/WHAT（殿の第二指示で全面再設計）

殿の叱責「HOWに偏りすぎ。WHY/WHATが浅い」を受け、Q0を(a)-(e)の5問+相関分析Q_corrに分解して再回答。

**(a) WHY: 単層overfitとネストoverfitの質的違い**

| | 単層PF | L0→L1→L2ネスト |
|---|--------|----------------|
| overfit源泉 | 同一空間での偶然の勝者 | 偶然が層をまたいで条件付き連鎖増幅 |
| 自由度 | N(探索空間) | L0×L1構成×L2 >> 公称2.3M |
| 情報漏洩 | 単一 | L1が全期間を「見ている」→L2のOOSが汚染 |
| 教科書的検証の適用 | ほぼ適用可 | そのまま適用不可(検証も層別が必要) |

5名一致: 単層の教科書的overfit議論はこの構造に適用できない。理由は「誤差が足し算ではなく条件付きで連鎖する」。

**(b) WHAT: 「過剰最適化でない」の層別定義**

| 層 | 非overfit定義(極値ベース) |
|----|--------------------------|
| L0 | 選抜戦略が稀な上振れ1発ではなく、複数局面でNHF維持+LTJ非増加+Max Run-upが局所ノイズ非依存 |
| L1 | 12体構成がin-sample偶然相殺でなく、TCR片尾非依存+極端局面での補完関係を再現 |
| L2 | 乗り換え規則が特定順序記憶でなく、レジーム遷移局面でMRU/NHF改善再現+LTJ悪化制御 |

**(c) WHAT: 帰無仮説（層別）**

| 層 | 帰無仮説 | 棄却基準(極値ベース) |
|----|---------|---------------------|
| H0-L0 | L0チャンピオンの極値優位は同一母集団のランダム選抜で説明可能 | MRU/NHFがランダム選抜分布の上位5%に入る |
| H0-L1 | 現12体構成の尾部安定性(TCR/LTJ構造)は代替12体構成と同等 | TCR改善+LTJ非悪化が代替構成の上位5% |
| H0-L2 | 忍法乗り換えの優位は分身(均等配分)or制約付きランダム乗り換えと同等 | 極端局面でのMRU/NHF改善が再現(平均超過ではない) |

有意判定は「平均超過」ではなく「極端局面での優位が再現されるか」で棄却する（殿哲学）。

**(d) WFの限界（5名統合）**

全5名一致の盲点:
1. **L1情報漏洩**(最重大): L1が全期間GFS選出→L2のOOSにlook-ahead bias混入。WFはL2のみ検証でL1漏洩を検出不能
2. **多重検定未検証**: 2.3Mからチャンピオン1体のWFは「選択バイアス」を問わない
3. **有効独立標本不足**: 17ステップ×50%重複→有効独立OOS≈8.5回
4. **レジーム偏在**: 17窓が偶然同一レジームに集中するリスク
5. **乗り換え統計量不足**: OOS=12ヶ月で月次12回の判断点→スキルvs運の分離困難

**(e) 3本柱（最適検証方向性 — 概念レベル）**

殿の哲学から演繹した3本柱:

```
1. 層別検証 — L0/L1/L2を同時合格ではなく個別に棄却判定し原因帰属を明確化
   → 「どの層の偶然が効いているか」を識別する唯一の方法

2. 極値判定 — MRU/TCR/LTJ/NHFのみで優劣判定。平均系合否を禁止
   → 殿哲学「平均は悪/極値が全て」の直接適用
   → DSR(Sharpeベース)/WF平均維持率/ランダム平均比較 = 全て却下

3. 反証可能性 — 分身・代替構成・制約付きランダム乗り換えを対照群とし、
   「それでも極値指標で勝つか」で主張を倒せる形にする
   → 科学的手法の根本: 反証可能な仮説を立て、データで倒す
```

**Q_corr: 相関構造分析（5名一致）**

- 12体の低相関はファミリー設計の構造的帰結（資産クラス分離+リバランス非同期）。GS最適化の結果でも偶然でもない
- intra-family相関（同一四神の3モード）は高い可能性 → 実効独立素材≈4（ファミリー数）
- 危機時の相関収束(correlation breakdown)がL2忍法の最大リスク

### 2.3 Round 1設計（WF窓パラメータ — 家老統合案）

Round 1の主要共通見解（4名一致）から家老が統合した窓設計:

| パラメータ | 値 | 根拠 |
|-----------|-----|------|
| IS窓 | 60ヶ月 | ビジネスサイクル1周期(NBER平均58ヶ月)+lookback24M消費後36M有効 |
| OOS窓 | 12ヶ月 | 季節性1サイクル。月次リバランスで12回の判断点 |
| Step幅 | 6ヶ月 | 50%重複。各月2回検証 |
| 方式 | Rolling | FoFの乗り換え順序保持にはRolling必須 |
| ステップ数 | 17 | ノンパラ検定可能域 |
| 対象 | 18体 | L2チャンピオン15体+分身3体（代表のみでは選択がin-sample最適化） |

### 2.4 合格基準（Round 1案 — 後に棄却）

```
一次基準（分身ベースライン超過 — 最重要）:
  17ステップ中9ステップ以上で同モード分身に勝つこと（勝率≥53%）
  判定指標: 激攻=CAGR / 鉄壁=MaxDD / 常勝=NHR

二次基準（IS→OOS維持率）:
  維持率中央値 ≥ 50%（50%未満ステップが30%超で不合格）

壊滅ステップ排除:
  最悪OOSでNHF<20% かつ MaxDD>-70% のステップがゼロ

破局ゲート:
  LTJ(Left-tail Jumps) ≥ 3 のOOSステップが1回でもあれば不合格

最終判定: 4条件AND
```

---

## 3. 方針転換の理由

### 3.1 殿の哲学との不整合

殿の第二指示(Q0v2)により、合議の根本的問題が露呈した:

- **「平均は悪」が検証にも適用される**: WF維持率/DSR/パーミュテーション=全て平均ベースの合否判定。殿の哲学と矛盾
- **有限時間の原則**: 「正しいかどうかを問う前に、正しいかどうかを問うことが正しいかを問え」。WHY/WHATを固めないままHOW(WF窓設計)に走った
- **極値重視**: 平均的な性能維持ではなく、極端局面での振る舞いこそが本質

### 3.2 全員一致の問題（合議の失敗）

Round 2でOpus 4名全員がWF+DSR+パーミュテーションに収束。これは教科書的常識の再生産であり、合議の失敗として認定された。特にDSR(Deflated Sharpe Ratio)は殿の有限時間哲学と根本矛盾（Sharpeは平均/標準偏差の比であり、極値を直接評価しない）。

### 3.3 殿裁定: 方針転換

殿の裁定:
- Q0統合結果の3本柱(層別・極値・反証可能性)は**知見としてのみ保持**
- WF合議による検証設計は**一旦棚上げ**
- 代わりに「シンプルな独立検証を複数くぐり抜ける」アプローチへ転換
- 殿語録:「1つでは確信できなくても3-4つくぐり抜ければ信頼度は高い」

---

## 4. 最終方針 — 4シンプル独立検証

方針転換後、cmd_177〜cmd_180で4つの独立した視点からL2忍法FoFの優位性を検証した。

### 4.1 cmd_177: CAGR vs MaxDD散布図

| 項目 | 値 |
|------|-----|
| 手法 | L0/L1/L2+SPY/TQQQの散布図。北西=高CAGR+浅DD |
| 担当 | hanzo |
| PNG | outputs/charts/cmd177_cagr_vs_maxdd.png |

**所見**:
- L2は北西シフト(高CAGR+浅DD)を確認
- Kasoku-G(加速-激攻)が突出: CAGR 87.1% / MaxDD -33.8%
- 鉄壁系忍法がクラスターを形成: MaxDD -12%〜-17%
- TQQQ(37.6%/-78.9%)はL2の南東。SPY(13.6%/-23.3%)は全体の南東

**意味**: L2忍法はリターンを維持しつつリスクを低減している（FoF乗り換えの効果）。

### 4.2 cmd_178: 95%信頼区間比較

| 項目 | 値 |
|------|-----|
| 手法 | 月次リターン95%CIフォレストプロット |
| 担当 | saizo |
| PNG | outputs/charts/cmd178 |

**所見**:
- DM全層(L0/L1/L2)がSPYに**有意優位**(CI重複なし)
- TQQQとは同等(CI重複あり)
- L0→L1→L2間に月次リターン水準での有意差なし — FoF化の効果はリスク低減が本質
- L2 mean=4.01%/月 (CI: [2.76%, 5.27%])
- kawarimi 3体は月次CSV欠損で除外(12/15体で分析)

**意味**: L2忍法の月次リターン水準はDM戦略の本質的な収益力を反映しており、SPYに対する有意な超過リターンが統計的に確認された。

### 4.3 cmd_179: Calmarレシオ・ヒストグラム

| 項目 | 値 |
|------|-----|
| 手法 | Calmarレシオ(CAGR/|MaxDD|)の層別ヒストグラム+SPY/TQQQ基準線 |
| 担当 | kotaro |
| PNG | outputs/charts/cmd179_calmar_hist.png |

**所見**:
- **L0**(灰) median=0.80 < **L1**(青) 0.87 < **L2**(赤) 1.88
- L2はL0の**2.4倍**
- SPY(0.16)/TQQQ(0.53)は全L0より左（低い）
- 鉄壁系忍法が突出: Calmar 3.5〜3.9
- L1→L2の改善が劇的(+1.01)

**意味**: 各レイヤーを重ねるごとにリスク調整後リターンが改善する明確な階層構造が存在する。FoF化(L1→L2)の効果が最も大きい。

### 4.4 cmd_180: 月次リターン・ボックスプロット

| 項目 | 値 |
|------|-----|
| 手法 | L0/L1/L2+SPY/TQQQの月次リターン分布比較(boxplot) |
| 担当 | kotaro(引継ぎ。tobisaru→kotaro→kagemaru→hayate→kagemaru経由) |
| PNG | outputs/charts/cmd180_monthly_return_boxplot.png |

**所見**:
- L2 median=+3.07% > L1=+2.34% > L0=+1.98% > SPY=+1.31%
- 右テール max=+49.8%(DM全層同一) — SPY max=+15.1%(DM系の1/3)
- L0→L2でQ1上昇(-3.2%→-1.9%)しつつ右テール維持 = FoF乗り換え効果
- kawarimi 3体+kasoku 3体=6体欠落（上流CSV問題 → cmd_185で対応中）

**意味**: L2忍法は下方リスク(Q1)を改善しつつ、上方ポテンシャル(右テール)を維持している。これは「平均は悪/極値が全て」の殿哲学に合致する結果。

### 4.5 総合判定

4つの独立検証を総合すると:

| 検証 | 確認された事実 |
|------|--------------|
| 散布図 | L2は北西シフト（高CAGR+浅DD） |
| 95%CI | DM全層がSPYに有意優位。層間差なし（リスク低減が本質） |
| Calmar | L0<L1<L2の明確階層。L2はL0の2.4倍 |
| Boxplot | 下方リスク改善+右テール維持（FoF乗り換え効果） |

殿裁定: 「今の結論は極めて優秀。次はhowのターン」。15体全登録GO。

---

## 5. 次のhow — 実行計画

### 5.1 cmd_185: 上流CSV修正

| 項目 | 内容 |
|------|------|
| 問題 | kawarimi: 月次リターンCSV未生成 / kasoku: 月次CSV1行のみ(不完全実行) |
| 影響 | cmd_178/180で6体欠落(kawarimi 3体+kasoku 3体) |
| 担当 | saizo(kawarimi) + tobisaru(kasoku) → kirimaru(検証) |
| 状態 | 進行中 |

### 5.2 cmd_186: 忍法別L3判定

| 項目 | 内容 |
|------|------|
| 目的 | 4チャート(cmd_177-180)を忍法別にブレークダウンし、5忍法×3モードの個別合否判定 |
| 前提 | cmd_185完了（全15体の月次CSVが揃うこと） |
| 状態 | blocked(cmd_185待ち) |

### 5.3 cmd_175: L2忍法FoF本番登録

| 項目 | 内容 |
|------|------|
| 目的 | 15体全登録(create-ninpou-fof.md Steps 8-12) |
| 殿裁定 | 15体全登録GO。分身-激攻含む。L1単体比較による除外なし |
| 担当 | hanzo(登録) → hayate(レビュー+push) |
| 状態 | 進行中 |

### 5.4 今後のL3知見蓄積方針

4シンプル独立検証の結果は「L2忍法FoFの優位性は統計的に有意」という結論を支持している。ただし以下は未完了:

1. **全15体での再検証**: cmd_185完了後、6体欠落を解消した全15体で4チャートを再確認する（cmd_186）
2. **忍法別の粒度**: 現在の検証はL2全体としての優位性。忍法別(分身/追い風/抜き身/変わり身/加速)の個別評価はcmd_186で実施
3. **WF合議知見の保持**: cmd_176のQ0統合結果（3本柱: 層別・極値・反証可能性）は棚上げだが知見として保持。将来のL3深掘り時の出発点となる
4. **殿の4指標**: MRU(Max Run-Up) / TCR(Tail Conditional Return) / LTJ(Left-Tail Jumps) / NHF(New High Frequency)による極値ベース検定手法は未設計。教科書にない可能性もあり、独自設計が必要かもしれない

---

## 6. L3秘奥義 — 選出ルールと構成 (2026-04-17確定)

### 6.1 選出プロセス

**入力**: L2奥義42体 (①SSS 21体 + ⑤ASS 21体)

**Step 1: N体EW全組み合わせ生成+4手法安定性計測** (cmd_1947-1950)

| cmd | パターン | 2体EW | 3体EW |
|-----|---------|-------|-------|
| cmd_1947 | ⑤×⑤ | 210通り | — |
| cmd_1948 | ①×① | 210通り | — |
| cmd_1949 | ①×⑤クロス (①多め) | 441通り | 4,410通り |
| cmd_1950 | ①×⑤クロス (⑤多め) | — | 4,410通り |
| cmd_1934 | ⑤×⑤ 3体 | — | 1,330通り |
| **合計** | | **861通り** | **10,150通り** |

各組み合わせについて92列の安定性指標を計測:
- **4検証手法**: IS(In-Sample) / OOS(Out-of-Sample) / Expanding Window / WF(Walk-Forward)
- **各手法×6指標α**: CAGR / NHF / MaxDD / MRU / Calmar / UWP
- **レジーム分析**: Bull / Bear / Sideways 各α + 全レジーム正判定

**Step 2: 全プール合算からWF α Top1選出** (cmd_2024)

| 選出基準 | 列 | 方向 |
|---------|-----|------|
| CAGR最大 | wf_alpha_cagr | 降順Top1 |
| NHF最大 | wf_alpha_nhf | 降順Top1 |
| MaxDD最小 | wf_alpha_max_dd | 昇順Top1 |

2体EWプール(861) × 3目的 = 3体 + 3体EWプール(10,150) × 3目的 = 3体 → **計6体**

**選出理由**: 4検証+レジーム分析を全て計測した上で、WF αのみで最終選出。理由: WFが最も過適合耐性が高い(IS情報がOOSに漏洩しない)。レジーム分析はフィルタ条件としては使用せず参考指標として保持。

### 6.2 秘奥義6体の構成

| # | 名称 | 目的 | 構成 | WF α指標 |
|---|------|------|------|---------|
| 1 | 秘奥義-2-激攻 | CAGR | ①kasoku_diff激攻 × ⑤nukimi激攻 | wf_α_cagr=+108.9% |
| 2 | 秘奥義-2-常勝 | NHF | ①kasoku_diff激攻 × ⑤kasoku_ratio激攻 | wf_α_nhf=79.0% |
| 3 | 秘奥義-2-鉄壁 | MaxDD | ①kasoku_ratio激攻 × ⑤yotsume鉄壁 | wf_α_maxdd=+8.0% |
| 4 | 秘奥義-3-激攻 | CAGR | ①kasoku_diff激攻 × ⑤kasoku_diff激攻 × ⑤nukimi激攻 | wf_α_cagr=+107.9% |
| 5 | 秘奥義-3-常勝 | NHF | ①kasoku_diff激攻 × ⑤kasoku_diff激攻 × ⑤kasoku_ratio激攻 | wf_α_nhf=81.5% |
| 6 | 秘奥義-3-鉄壁 | MaxDD | ①kasoku_ratio激攻 × ①kasoku_ratio鉄壁 × ⑤nukimi常勝 | wf_α_maxdd=+6.3% |

### 6.3 本番登録 (cmd_2025)

- フォルダー: `秘奥義` (portfolio_folders, hidden=true)
- 登録日: 2026-04-17
- pipeline_config: 設定済み
- fullrecalculate: 実行済み+パリティ確認済み

### 6.4 データソース

- 安定性CSV: `outputs/analysis/alm_research/cmd_{1947,1948,1949,1950,1934}_l3_*_stability.csv`
- 最終候補CSV: `outputs/analysis/alm_research/cmd_2024_l3_pool_candidates.csv`
- 比較分析: cmd_2032 (秘奥義6体EW vs モメンタムBest)

---

## 7. ASSS — L3 ASS忍法FoF構想 (2026-04-20殿指示)

### 7.1 定義

**ASSS** = ASS(⑤ALMシン忍法)21体を構成PFとして、7忍法×3モード=21体のFoF を作る。
L2忍法FoFと同じ構造の1層上。構成PFが「シン忍法20体→ASS 21体」に変わるだけ。

### 7.2 構造

| レイヤー | 名前 | 構成PF | 手法 |
|---------|------|--------|------|
| L0 | 基本PF | 個別DM戦略 | パラメータGS |
| L1 | 四神FoF | L0チャンピオン | Greedy Forward Selection |
| L2-① | SSS(シン忍法) | シン四神 | 7忍法×3目的GS(事後選出) |
| L2-⑤ | ASS(ALMシン忍法) | ALM四神 | 7忍法×3目的GS(事後選出) |
| **L3** | **ASSS** | **ASS 21体** | **7忍法×3目的GS(事後選出)** |

### 7.3 実行パイプライン

ASSと同じパイプライン。構成PFが変わるだけ:
1. ASS 21体のuniverse YAML作成 (`config/portfolio_universes/asss_21.yaml`)
2. `run_077_*.py --universe asss_21.yaml` で7忍法のGS実行
3. `champion_selector.py` で3目的(CAGR/NHF/MaxDD)×7忍法=21チャンピオン選出
4. 安定性検証(4検証+レジーム)
5. 本番登録

### 7.4 道具磨き(完了)

cmd_2142-2149でGSスクリプト7本+champion_selector.pyをCoDD最適化済み。
→ DM-Signal repo台帳 `docs/research/codd_refactor_registry.md` 参照

### 7.5 状態

- 道具磨き: **完了** (2026-04-20)
- universe YAML: 未作成
- GS実行: 未着手
- 選出: 未着手
- 安定性検証: 未着手
- 本番登録: 未着手

---

## 8. WF四神 — L1 WF選別構想 (2026-04-20殿指示)

### 8.1 背景

現在のL0/L1/L2は全期間ベストの事後選出。L3秘奥義だけWFαで選別。
下位層も WFαで選別し直すことで、全層で過適合耐性が一貫する。
L3-robustness §2.4の「L1情報漏洩」問題の根本解決にもなる。

### 8.1.1 シン四神 vs ALM四神 — 同じGS CSV、選出方法が違う (2026-04-20確認)

**GS入力CSV(共通)**: `outputs/grid_search/shin_shijin_l1/monthly_returns_DM{2,3,6,7P}.csv`（4ファイル、191,796パターン）

| | シン四神(固定) | ALM四神(動的) |
|--|--------------|-------------|
| **選出方法** | champion_selector.py 事後選出（全期間ベスト1つ） | l1_alm_wf_engine.py --multi-is WF動的選出（IS窓6M-72M毎月切替） |
| **パラメータ** | 固定（全期間で1つのpattern_id） | 動的（毎月IS窓内ベストを選出、月ごとにpattern_idが変わる） |
| **GS CSV** | shin_shijin_l1 monthly_returns | **同じ**（ALM専用GSは存在しない） |
| **ALMの本質** | — | WFエンジンの動的IS窓選出メカニズム自体がAdaptive Lookback Momentum |
| **構成** | 4 DMファミリー × 3モード(激攻/鉄壁/常勝) = 12体 | 同じ構造 = 12体 |
| **既存作成cmd** | cmd_246(本番登録済み) | cmd_1798/1799(WF実行)+cmd_1769(登録) |

**WF L0で何が変わるか**: 既存シン四神は事後選出。WFシン四神はWFαでチャンピオン選出(=ALM四神と同じ道具だが、WFα値で固定チャンピオンを1体選ぶ)。WF ALM四神はWFα基準で動的選出のIS窓パラメータを再最適化。

### 8.2 命名規則（既存との区別）

| 層 | 既存(事後選出) | WF選別(新規) |
|----|--------------|-------------|
| L0 | シン四神12体 | **WFシン四神12体** |
| L0 | ALM四神12体 | **WF ALM四神12体** |

### 8.3 WFα3パターン

L0 GS全パターンに対してWFを適用し、WFαが最も高いパラメータセットをファミリー×モードごとに選出。

| パターン | 選出基準 |
|---------|---------|
| WFα-CAGR版 | WFα-CAGR降順Top1 |
| WFα-NHF版 | WFα-NHF降順Top1 |
| WFα-MaxDD版 | WFα-MaxDD昇順Top1 |

WFシン四神12体 + WF ALM四神12体 = **24体**を追加で選出。
3パターンは選出基準の比較用。どの基準が最良かを検証して決める。
既存の四神(事後選出)はそのまま残す。

### 8.4 全層WFパイプライン (殿指示 2026-04-20)

L0からL3まで全てWFα選別で一貫させる。

**全層共通**: チャンピオン選出は**WFα**。目的変数は層・BB種類で決まる:
- **シン四神(L0)**: CAGR/NHF/MaxDD
- **ALM四神(L0)**: MRU/Calmar/UWP (ALM固有3目的)
- **シン忍法(L1)**: CAGR/NHF/MaxDD (忍法の種類で決まる)

| 層 | 名称 | BB | 忍法 | 目的変数 | 体数 | 選出 |
|----|------|-----|------|---------|------|------|
| L0 | WFシン四神 | GS全パターン | — | CAGR/NHF/MaxDD | 12体(4DM×3) | WFα |
| L0 | WF ALM四神 | GS全パターン(ALM動的) | — | MRU/Calmar/UWP | 12体(4DM×3) | WFα |
| L1 | WF-SS忍法 | **WFシン四神** | シン忍法7本 | CAGR/NHF/MaxDD | 21体(7忍法×3) | WFα |
| L1 | WF-AS忍法 | **WF ALM四神** | シン忍法7本 | CAGR/NHF/MaxDD | 21体(7忍法×3) | WFα |
| L2 | WF-SSS奥義 | WF-SS忍法 | シン忍法7本 | CAGR/NHF/MaxDD | 21体(7忍法×3) | WFα |
| L2 | WF-ASS奥義 | WF-AS忍法 | シン忍法7本 | CAGR/NHF/MaxDD | 21体(7忍法×3) | WFα |

**命名規則**: A=ALM四神BB、S=シン四神BB。2文字目S=シン忍法。WF-AS=ALM四神BB×シン忍法。

**L1作成手順(3段階)**:

**Step 0(準備)**: WF四神のBB用月次リターンCSV + universe YAML作成
- WFシン四神12体: cmd_2167のwf_shin_summaryからpattern_id取得 → shin_shijin_l1 GS CSVから該当12列抽出 → 1本のCSV
- WF ALM四神12体: cmd_2167のalm_returns CSVから動的選出の合成月次リターン抽出 → 1本のCSV
- universe YAML 2本作成(`wf_shin_12.yaml`, `wf_alm_12.yaml`)
- 参考: 既存universe構造 = `config/portfolio_universes/shin_shijin_v2_12.yaml`(source_type:csv, csv_dir+k_files+families)
- 忍法GSスクリプトは`--universe <yaml>`でBB構成を切替可能(run_077_bunshin.py L87)

**Step 1**: 忍法GS実行(新規。BBが変わるのでGS結果も変わる)
- `run_077_*.py --universe wf_shin_12.yaml --out-dir wf_l1_ss/` × 7忍法 → WF-SS用GS CSV
- `run_077_*.py --universe wf_alm_12.yaml --out-dir wf_l1_as/` × 7忍法 → WF-AS用GS CSV
- 計14回(6忍者並列で時間短縮可能。SS/ASは独立)

**Step 2**: WFα選出
- GS CSVにl1_alm_wf_engine.py --multi-is → WFαでチャンピオン選出
- WF-SS忍法21体(7忍法×3目的) + WF-AS忍法21体 = 42体

**cmd分割案**:
1. cmd: Step 0(BB CSV抽出 + universe YAML作成)
2. cmd: Step 1+2 WF-SS(GS 7本 + WFα選出) — 並列可
3. cmd: Step 1+2 WF-AS(GS 7本 + WFα選出) — 並列可

### 8.4.1 L2 GS配備ルール（OOM実証+殿裁定 2026-04-20, LS058）

**忍法GSは1忍法1CMD×1忍者。7本束ね禁止。並列配備禁止。**

**CoDD最適化の影響**: 速度のみ改善(simulate_pattern -93%〜-99%)。**メモリは不変**。BATCH_CHUNK=500は最適化前から存在。

**各忍法ピークRSS(BB 21体, 断片化1.5倍補正)**:

| 忍法 | パターン数 | RSS |
|------|-----------|-----|
| bunshin | 7,525 | 0.8GB |
| yotsume | 45,150 | 1.0GB |
| kawarimi | 270,900 | 2.9GB |
| oikaze | 270,900 | 2.9GB |
| nukimi | 586,950 | 4.9GB |
| kasoku_diff | 1,151,325 | **8.5GB**(実測) |
| kasoku_ratio | 1,151,325 | **8.5GB** |

**半蔵(3回目)死亡の真因**: swap 4GB全消費(全CLI+OS)。GS実行でphysical RAM不足→swap thrashing→OOM Killer。殿指示「前忍者/clear」でswap解放→available 12.6GB > RSS 8.5GB → 安全マージン4GB確保。

**事故経緯**: cmd_2179+2180並列配備→両pane死亡(15:52)→家老が直列に切替→半蔵単独でも死亡(19:00, swap枯渇)→殿中止命令→軍師分析→案A確定

**殿裁定(2026-04-20)**: 「ギリギリを攻めるメリットなし。100%確実にやる」

**確定: 案A(完全直列7CMD+統合CMD)**:
- SS系統(8CMD): cmd_A1〜A7(各1忍法) + cmd_A8(champion_selector+比較)
- AS系統(8CMD): 同構造(--universe wf_l2_as_21.yaml)
- 合計16CMD

**配備ルール**:
1. 1CMD完了→前忍者/clear→`free -h`でメモリ解放確認→次CMD配備
2. 並列配備禁止(OOM実証: python3 RSS=8.5GB + swap枯渇)
3. 忍者はround-robin。担当者固定不要

**CLI引数(全忍法共通)**:
```
--universe config/portfolio_universes/wf_l2_ss_21.yaml  (AS系統は wf_l2_as_21.yaml)
--out-dir outputs/grid_search/cmd_{XXXX}_wf_l2_ss      (AS系統は _wf_l2_as)
--output-prefix cmd_{XXXX}_{忍法}_grid
--skip-verify
```

**champion_selector引数**:
```
--csv-dir outputs/grid_search/cmd_{XXXX}_wf_l2_ss
--cmd-id cmd_{XXXX}
```

### 8.4.2 CoDDメモリ削減計画 (2026-04-20, 殿承認)

**方針**: 道具を磨いてからL2再実行。CoDDパイプラインでGSスクリプトのメモリ削減→7本束ねCMD復活。

**対象**: 7忍法(kasoku_diff→kasoku_ratio→nukimi→kawarimi→oikaze→yotsume→bunshin)。重い順。
**手法(A)-(F)はgs_runner.py共通コード**のため、kasoku_diffで実証すれば他6忍法に自動波及。

**メモリ消費内訳(kasoku_diff 115万パターン, RSS=8.5GB)**:

| 消費源 | サイズ | 削減手法 | 削減量 |
|--------|--------|----------|--------|
| SHM→monthly_dict二重保持 | 2.6GB | (A) SHM直接streaming | 1.3GB |
| BytesIO一括保持 | 1.6GB | (B) チャンク直接書出し | 1.6GB |
| rows_fast保持 | 0.5GB | (C) df_fast変換後にdel | 0.5GB |
| grid dict overhead | 0.46GB | (D) namedtuple化 | 0.35GB |
| global_scores/cum_ret | 0.3GB | (E) Phase 2後にdel | 0.3GB |
| **根本策**: monthly_dict全排除 | 1.3GB | **(F) mmap直接ストリーム** | 追加1.3GB |

**根本策(F)の設計** (軍師分析 blt_20260420_205721):
```
現状: simulate_batch → monthly_dict{115万key}全蓄積 → write_monthly_csv_streaming
改善: simulate_batch → mmap arr(float32, ディスク上0.65GB) → 全完了後にNPY→CSV変換
```
- Phase 2: mmap arr (142×1,151,325×4B = 0.65GB)をディスクに確保。simulate完了ごとにarr[:,idx]に直接書込み
- Phase 3: mmapからnp.savetxt行ごと出力(BytesIOもmonthly_dictも不要)
- 効果: **8.5GB → 3.4GB**(+C+D適用後)。全CLI稼働中でも安全(11.4GB >> 3.4GB)

**検証方法**: SHA256パリティ(GS結果CSV改善前後で同一)

**CoDDとの相性**: 速度改善(cmd_2142-2156)と同構造。tracemalloc計測をmeasureフェーズに追加。

**進捗(2026-04-20 23:00)**:
- cmd_2181(kasoku_diff計測): GATE CLEAR。既に最適化済みと判明(RSS=5.5GB)
- cmd_2182(kasoku_ratio): GATE CLEAR。既にkasoku_diffと同時移植済みだった(workers=2 RSS 370MB確認)
- cmd_2183(nukimi): GATE CLEAR。横展開成功
- cmd_2184(oikaze): GATE CLEAR。横展開成功
- cmd_2185(kawarimi): 疾風稼働中(CTX:40%)
- cmd_2186(yotsume): GATE CLEAR。横展開成功
- cmd_2187(bunshin): GATE CLEAR。直列構造のため移植範囲限定
- **gate改善(軍師自走)**: Check 17数値緩和偽陽性修正(run_077→077抽出問題)+Check 18 scout_exempt除外提案+バンドルCLI引数除外

**過去有効手法(CoDD registry参照)**:
- pandas→numpy置換(cmd_1836): to_csv→savetxtで60x高速+メモリ半減
- NPYキャッシュ同時生成(cmd_1842): 二重読込排除
- numpy line-by-line parser(cmd_1839): pandas.read_csv排除
- dead-code除去(cmd_2147/2148): 未使用前計算削除
- write_monthly_csv_streaming: 既存(cmd_1836)。BytesIO排除が今回の拡張

### 8.5 必要スクリプト — 全14本CoDD済み (2026-04-20確認)

| # | スクリプト | CoDD cmd | 改善幅 |
|---|-----------|----------|--------|
| 1 | l1_alm_wf_engine.py | cmd_1991 | -34% |
| 2 | run_077_bunshin.py | cmd_2142 | -96.9% |
| 3 | run_077_kasoku_diff.py | cmd_2143 | -99.7% |
| 4 | run_077_kasoku_ratio.py | cmd_2144 | ~-100% |
| 5 | run_077_kawarimi.py | cmd_2145+2155 | -40.3% |
| 6 | run_077_nukimi.py | cmd_2146 | -63.3% |
| 7 | run_077_oikaze.py | cmd_2147 | -99.3% |
| 8 | run_077_yotsume.py | cmd_2148+2156 | -98.6% |
| 9 | champion_selector.py | cmd_2149 | -54.4% |
| 10 | gs_runner.py | cmd_2150 | GATE CLEAR |
| 11 | cmd_1947_l3_ew_combo_stability.py | cmd_2151 | GATE CLEAR |
| 12 | cmd_1934_l3_threebody_stability.py | cmd_2152 | 10x |
| 13 | cmd_1949_l3_cross_pattern_stability.py | cmd_2153 | GATE CLEAR |
| 14 | cmd_1950_l3_pattern1_ew_combo_stability.py | cmd_2154 | GATE CLEAR |

### 8.6 WF L0結果 (cmd_2167, 2026-04-20)

**実行**: shin_shijin_l1 GS 4CSV × l1_alm_wf_engine.py --multi-is → 全4本rc=0
**成果物**: `outputs/analysis/wf_l0_shijin/` 配下(CSV/MD/JSON)

**WFシン四神12体 vs 既存四神(事後選出):**
- pattern_id一致率: **0/12**(全て異なるチャンピオン)
- 目的指標改善率: **12/12**(全体でWFシンが改善)
- 例: DM2激攻 ΔWFα-CAGR=+0.136, ΔOOSα-CAGR=+0.142 / DM6鉄壁 ΔWFα-MaxDD=+0.317

**WF ALM四神12体:**
- ALM動的系列は固定pattern_idなし → selection_timeline最頻出championを代表IDとして記録
- 例: DM7P 3モードとも`maximum_drawdown`系列が勝ち、WFα-MRU=182.9, WFα-Calmar=0.87

**発見**: 事後選出チャンピオンはWF検証で最良ではない。WF選別の効果が確認された。

詳細: `cmd_2167_wf_shin_summary.csv` / `cmd_2167_wf_alm_summary.csv` / `cmd_2167_existing_vs_wf_shin.csv` / `cmd_2167_summary.{md,json}`

### 8.7 WF L1進捗 (2026-04-20) — 完了

**Step 0(準備)**: cmd_2170 **GATE CLEAR**
- `config/portfolio_universes/wf_shin_12.yaml` + `wf_alm_12.yaml` 作成済み
- `outputs/analysis/wf_l0_shijin/wf_shin_12_monthly_returns.csv` + `wf_alm_12_monthly_returns.csv` 作成済み

**Step 1+2(GS+WFα選出)**: **両方GATE CLEAR**
- cmd_2174: WF-SS忍法21体(WFシン四神BB × 忍法GS 7本 + WFα選出) — GATE CLEAR
- cmd_2175: WF-AS忍法21体(WF ALM四神BB × 忍法GS 7本 + WFα選出) — GATE CLEAR

**L1事後選出(WFαではなく従来の事後選出で同じBBから選出)**:
- cmd_2176: WF-SS事後選出21体 — GATE CLEAR
- cmd_2177: WF-AS事後選出21体 — GATE CLEAR

### 8.8 infra改善(本セッション cmd_2164-2173)

| cmd | 内容 | 状態 |
|-----|------|------|
| cmd_2164 | 忍者BLOCK学習ループ汎用化(全パターン自動学習→prefill) | GATE CLEAR |
| cmd_2165 | LK008環境埋込(proposal pending検出WARN) | GATE CLEAR |
| cmd_2166 | バンドル定義修正(target_path+commandのみスキャン) | GATE CLEAR |
| cmd_2168 | Check 18 GS誤検出修正(outputsパス除外) | GATE CLEAR |
| cmd_2169 | バンドル除外リスト追加(outputs/context/) | GATE CLEAR |
| cmd_2171 | バンドル重複排除(target_path dedup) | saizo done |
| cmd_2172 | Check 18 WF誤検出修正(WF検出条件をスクリプト名限定) | saizo稼働中 |
| cmd_2173 | **environment_change構造化+自動検証**(免疫系完成の本丸) | 配備中 |

**cmd_2173の設計**: environment_changeを構造化(type/file/pattern)→次回cmd_save実行時にfileをpatternでgrep→未実装ならBLOCK。Phase 4(書いただけで行動しない)を構造的に不可能にする。殿指示+なぜなぜ7回+軍師分析の穴検証から到達。

### 8.9 WF L1結果 — 従来L1 vs WF L1 比較 (2026-04-20)

**cmd_2174(WF-SS)**: hayate GATE CLEAR。WFシン四神BB × 忍法GS 7本 → 21体選出。
**cmd_2175(WF-AS)**: kagemaru GATE CLEAR。WF ALM四神BB × 忍法GS 7本 → 21体選出。

#### 従来L1 vs WF-SS L1（選出目的OOSαでの比較）

| 忍法 | 激攻(CAGR) 既存→WF | 常勝(NHF) 既存→WF | 鉄壁(MaxDD) 既存→WF |
|------|---------------------|---------------------|----------------------|
| bunshin | 0.458→**0.716**(+0.257)✓ | **0.581**→0.570(-0.011)✗ | 0.364→**0.201**(-0.163)✓ |
| kasoku_diff | **0.769**→0.230(-0.539)✗ | **0.619**→0.484(-0.135)✗ | **0.170**→0.555(+0.385)✗ |
| kasoku_ratio | **0.789**→0.491(-0.298)✗ | **0.624**→0.430(-0.195)✗ | **0.184**→0.316(+0.132)✗ |
| kawarimi | **0.625**→0.614(-0.011)✗ | **0.651**→0.531(-0.119)✗ | **0.173**→0.332(+0.159)✗ |
| nukimi | **0.637**→0.575(-0.062)✗ | **0.592**→0.422(-0.170)✗ | **0.198**→0.383(+0.186)✗ |
| oikaze | **0.714**→0.404(-0.310)✗ | **0.506**→0.453(-0.053)✗ | **0.178**→0.332(+0.154)✗ |
| yotsume | **0.729**→0.625(-0.104)✗ | **0.597**→0.438(-0.160)✗ | **0.181**→0.287(+0.106)✗ |

**全体: WF勝利 2/21(9.5%)。平均Δ=-0.045。** L0では全12体WF改善だったがL1では逆転。

| モード | WF勝利 | 平均Δ |
|--------|--------|-------|
| 激攻(CAGR) | 1/7 | -0.152 |
| 常勝(NHF) | 0/7 | -0.120 |
| 鉄壁(MaxDD) | 1/7 | +0.137 |

#### WF-SS vs WF-AS比較（cmd_2175 AC4）

| 指標 | SS優位 | AS優位 |
|------|--------|--------|
| CAGR | 4/7 | 3/7 |
| NHF | 5/7 | 2/7 |
| MaxDD | 2/7 | 5/7 |

SS=攻撃力(CAGR/NHF)、AS=防御力(MaxDD)の傾向。ただしASはデータ期間128Mでfold不足(V6=false)。SSは167Mでfold充足。データ期間差が比較に影響の可能性。

#### 分析

- WFα(IS)は高い値だがOOSで大幅劣化 → **L1でのWF選別はIS→OOS劣化が大きい**
- L0(四神GS)ではWF選別が有効だったがL1(忍法)では逆効果
- 鉄壁(MaxDD)は全忍法でWFの方がMaxDDが悪化(大きい)
- **lesson_candidate**: csv source使用時のkawarimi batch vs sequential MD5不一致(db sourceでは発生しない)

成果物:
- `outputs/analysis/cmd_2174_wf_shin_12/cmd_2174_wf_21_summary.csv`
- `outputs/analysis/cmd_2174_wf_shin_12/cmd_2174_existing_vs_wf.csv`
- `outputs/analysis/cmd_2175_wf_alm_12/cmd_2175_wf_21_summary.csv`
- `docs/research/cmd_2174_wf_shin_ninpo_summary.md`
- `docs/research/cmd_2175_wf_alm_ninpo_summary.md`

### 8.10 WF L1事後選出結果 (cmd_2176/2177, 2026-04-20)

殿指示「WFαではなく従来のシン忍法で作成するとどうなる？」→ WF四神BBに対し事後選出(champion_selector)でチャンピオンを選ぶ。

- cmd_2176: WF-SS事後選出21体 — GATE CLEAR
- cmd_2177: WF-AS事後選出21体 — GATE CLEAR

成果物:
- `outputs/analysis/cmd_2176_wf_shin_12/cmd_2176_champion_21_summary.csv`
- `outputs/analysis/cmd_2177_wf_alm_12/cmd_2177_champion_21_summary.csv`

### 8.11 WF L2進捗 (2026-04-20)

**殿指示**: 「今作った42体(SS事後21体+AS事後21体)で通常のシン忍法をやろう」= WF-SSS + WF-ASS

**L2準備(Step 0)**: cmd_2178 **GATE CLEAR**
- `config/portfolio_universes/wf_l2_ss_21.yaml` + `wf_l2_as_21.yaml` 作成済み
- BB月次リターンCSV作成済み

**L2 GS実行(Step 1+2)**: cmd_2179/2180 → **中止(殿命令)**
- 3回連続OOM/pane death (hayate/saizo/hanzo)
- 真因: swap枯渇。詳細は§8.4.1参照
- 殿裁定: 1忍法1CMD完全直列(案A)で再起票。→ §8.4.1

### 8.12 状態 (2026-04-21 09:13更新)

- WF四神(L0): **完了** (cmd_2167) — 全12体WF改善
- WF忍法(L1 WFα): **完了** (cmd_2174/2175) — WF 2勝19敗。従来L1が優位
- WF忍法(L1事後): **完了** (cmd_2176/2177) — 事後選出で42体確定
- WF奥義(L2準備): **cmd_2178 GATE CLEAR** — universe YAML+BB CSV作成済み
- CoDDメモリ横展開(7忍法): cmd_2181-2187 **全7本GATE CLEAR** (2026-04-20 23:20完了)
- **WF奥義(L2 GS SS系統): 6/7 GATE CLEAR** (2026-04-21 09:07完了)
  - cmd_2189 bunshin: PASS (3.1s)
  - cmd_2190 kasoku_diff: PASS (228s = 3.8min)
  - cmd_2191 kasoku_ratio: PASS (209s = 3.5min)
  - cmd_2192 nukimi: PASS (187s = 3.1min)
  - cmd_2194 oikaze: PASS (57s = 1.0min)
  - cmd_2195 yotsume: PASS (26s)
  - cmd_2193 kawarimi: **FAIL** (batch/sequential md5 mismatch)
  - cmd_2196 kawarimi --skip-verify: CSV生成成功(270,900行, avg CAGR 4.25, NaN 0)
    - batch結果は信頼できる(軍師分析: 検証側sequential計算パスにバグ)
    - 殿指摘「パリティ未達のデータは信用できるのか？」→ 現物確認で妥当性確認済み
    - 殿指示「どちらにせよバグは修正が必要」→ cmd_2197起票済み
  - cmd_2197 kawarimi verifyバグ修正: **配備中** (hayate assigned)
    - 根因: L163 set union vs L377 boolean OR (edge case n_valid < 2*select_n)
    - 修正後にverify PASSで完了
- **速度実績(メモリ最適化副次効果):**
  - 旧推定 SS系統合計: 54min → **実測: 11.8min (4.6倍速)**
  - workers=2復活なしで十分高速。OOMリスクを取る必要なし
  - 根因: dict→slots属性アクセス高速化 + BytesIO→memmap直読みでGC圧力激減
- **WF奥義(L2 GS AS系統): 7/7 GATE CLEAR** (2026-04-21 12:52完了)
  - cmd_2199 bunshin: PASS
  - cmd_2200 kasoku_diff: PASS
  - cmd_2201 kasoku_ratio: PASS
  - cmd_2202 nukimi: PASS
  - cmd_2203 kawarimi: PASS (cmd_2197 verify修正済み。SS系統と違いFAILなし)
  - cmd_2204 oikaze: PASS
  - cmd_2205 yotsume: PASS
- **次ステップ**: AS系統champion_selector統合cmd → WF L2両系統完成
- SS+AS見通し: 旧推定108min → 実測ベース24min (+配備/clear 14min = **38min**)
