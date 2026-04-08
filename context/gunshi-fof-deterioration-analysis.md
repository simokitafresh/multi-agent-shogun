<!-- last_updated: 2026-04-09 -->
# FoF悪化構造分析 — EMA前処理のFoF伝播メカニズム

<!-- cmd_1700/1701/1703/1704の結果を統合分析。軍師分析(2026-04-03) -->

## §1 結論

FoF悪化の主因は**構成タイプ(激攻/常勝/鉄壁) × depth**の交互作用。単独変数では説明不十分。

| 変数 | 説明力 | 証拠 |
|------|--------|------|
| **構成タイプ** | **最大** | depth=1でも激攻=-0.135、鉄壁=-0.018。同一depthで7.5倍の差 |
| **depth** | 中（増幅器） | 激攻: depth=1→-0.135、depth=2→-0.239。鉄壁: depth=1→-0.018、depth=2→-0.066 |
| シグナル同期化 | 棄却 | r=-0.199(cmd_1701) |
| High(Max)選別 | 棄却 | 選択EMA5≈一律EMA5(cmd_1704) |

## §2 depth × 構成タイプ交差分析

```
            depth=1                    depth=2
激攻   n=11 avg=-0.135 improved=0%    n=5  avg=-0.239 improved=0%
常勝   n=10 avg=-0.052 improved=20%   n=5  avg=-0.148 improved=0%
鉄壁   n= 9 avg=-0.018 improved=33%   n=5  avg=-0.066 improved=0%
other  n= 6 avg=+0.003 improved=50%   n=7  avg=-0.074 improved=43%
depth=3: 旧忍法-Ward n=1 avg=-0.182 improved=0%
```

**読み方**: 行=構成タイプ（影響大）、列=depth（増幅器）。激攻はdepth=1で既に-0.135。鉄壁はdepth=2でも-0.066。構成タイプがdepthより強い。

## §3 因果メカニズム（3層）

### 層1: L0 PF個体レベル
EMAはlookback依存で効果が異なる（研究日誌Phase 2.5）:
- 中長期lookback(DM2/DM3/DM5): 改善(+2.7%〜+112%)
- 短期lookback(DM6=15d): **全span劣化**(-43%)
- 超長期(DM7+=504d): 微改善(+11%)

### 層2: FoF構成タイプ
- **激攻FoF**: 攻撃的PF(DM6系等短期lookback)を多く含む → 層1で劣化するPFの比率が高い → FoF全体が劣化
- **鉄壁FoF**: 防御的PF(長期lookback中心)を含む → 層1で改善するPFが多い → FoF劣化が軽微
- **otherFoF**: 混合構成。改善PFと劣化PFが相殺 → 平均でほぼ±0

### 層3: depth増幅
depth=1: L0のシグナル劣化 → FoFのリターン劣化（1段階）
depth=2: L0シグナル劣化 → L1 FoFリターン劣化 → L2 FoFのモメンタム入力劣化（2段階）
→ 劣化が層を経るごとに増幅（激攻: -0.135→-0.239、+77%増幅）

## §4 棄却済み仮説

### シグナル同期化仮説（cmd_1701）
「EMAでPF間シグナルが均一化→分散効果減少」→ r=-0.199(n=59)。弱い負の相関。棄却。
avg尖り削減量=0.001。月次BUY/CASHレベルではEMA span=5のシグナル変化は微小。

### High(Max)選別仮説（cmd_1704）
「delta_high>=0のPFだけにEMA5→FoF改善」→ 52/65PF通過(80%)で選別が緩い。C_vs_A=-0.091 ≈ B_vs_A=-0.087。棄却。

## §5 cross-sectional dispersion仮説（未検証）

将軍の有力仮説: EMAが全PFのリターンを平均方向に寄せる → cross-sectional dispersion(PF間リターン分散)縮小 → EqualWeight FoFの分散効果が減少。

**本分析との整合**: 鉄壁/常勝が激攻より軽微に悪化するパターンはdispersion仮説と整合しうる。ただし構成タイプの直接効果(層2)が支配的であり、dispersionが追加的な説明力を持つかは定量検証が必要。

検証方法: 各月のPFリターンcross-sectional std(baseline vs EMA5)を比較。FoF別にdispersion変化量とΔCAGRの相関を見る。

## §6 次の問い

1. **構成PFのlookback分布が支配的なら、PF別にEMAの適用/非適用を決めるべき** → cmd_1704の選別基準(delta_high)は無効だった。lookback長による選別が有効か？
2. **cross-sectional dispersion検証** → EMA前後のPFリターン分散変化を定量化
3. **depth=2で劣薬のみ改善した理由** → 劇薬FoFの構成PF特性を確認（防御的PF比率が高い？）

---
→ データソース: `outputs/analysis/standard_pf_preprocessing/fof_all59_preprocessing_results.yaml` (cmd_1700)
→ 棄却仮説: `outputs/analysis/standard_pf_preprocessing/signal_correlation_analysis.yaml` (cmd_1701)
→ rolling feature: `outputs/analysis/standard_pf_preprocessing/rolling_return_feature_analysis.yaml` (cmd_1703)
→ 選択適用: `outputs/analysis/standard_pf_preprocessing/fof_all59_selected_preprocessing_results.yaml` (cmd_1704)
