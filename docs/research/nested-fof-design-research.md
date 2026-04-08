# ネステッドFoF設計 調査統合メモ
<!-- cmd_1410 偵察の背景知識 -->
<!-- generated: 2026-03-26 by shogun (3-agent parallel research) -->

## 目的

21体シン忍法v2を材料として、ネステッドFoF（FoF of FoF）を構築する。
第一目標: トータルリターン（幾何リターン）最大化。
制約: 材料は21体のみ。配分ルールは無制限（本番DBに存在しないルールもOK）。
必須: 過適合でないことの証明。説明可能性。

## 核心理論

### 幾何リターンの公式
G ≈ μ - σ²/2
分散σ²を下げると、算術リターンμが同じでもトータルリターン（幾何リターン）が上がる。
Kelly基準は幾何リターン最大化の唯一の数学的最適。

### プロスペクト理論の克服
人間はMaxDD（損失）に2倍敏感（Kahneman & Tversky 1979）。
→ 鉄壁モード偏重、早すぎる利確、激攻回避。
ルールベース = 感情排除。設計者バイアスも排除（MaxDD重視しすぎない）。

## 配分手法スペクトラム（過適合リスク順）

| 手法 | パラメータ数 | 共分散必要？ | リターン予測必要？ | 過適合リスク |
|------|------------|------------|----------------|------------|
| Equal Weight (1/N) | 0 | No | No | 最小 |
| Inverse Volatility | 0(推定値) | 対角のみ | No | 極めて低 |
| HRP | 0(構造発見) | あり(逆行列不要) | No | 極めて低 |
| HERC | 0(+gap統計) | あり(逆行列不要) | No | 極めて低 |
| NCO | 構造+CV | あり(小行列逆のみ) | 任意 | 低 |
| Risk Parity / ERC | 共分散 | あり | No | 低 |
| Max Diversification | 共分散 | あり | No | 低 |
| Min Variance | 共分散 | あり(逆行列必要) | No | 中 |
| Mean-Variance | 共分散+期待リターン | あり(逆行列必要) | **Yes** | **高** |

### なぜHRPが構造的に過適合に強いか（López de Prado 2024, ADIA Lab理論証明）
1. 逆行列計算なし → Markowitzの数値不安定性を回避
2. 期待リターン推定なし → 最大の推定誤差源を排除（共分散誤差の22-56倍）
3. 階層分解 → 1クラスタの不安定性が他に伝播しない
4. 再帰的二分割 → 配分決定がローカル（グローバルではない）

### DeMiguelの1/Nベンチマーク（2009, 2024確認）
均等配分は大半の最適化手法を打ち負かす。
理由: 推定誤差ゼロ。サンプルサイズが小さいほど1/Nの優位性が増す。

## 過適合排除の検証パイプライン（4フェーズ19ステップ）

### Phase 0: 設計規律
- 経済的合理性があるか（理論ベースか）
- パラメータ最小化（パーシモニー原則）
- 事前登録（ルールを事前に明文化してからバックテスト）

### Phase 1: 統計的検出
- CPCV（Combinatorial Purged Cross-Validation）→ PBO（Probability of Backtest Overfitting）→ DSR（Deflated Sharpe Ratio）→ SPA（Superior Predictive Ability）→ Walk-Forward → レジーム分割検証

### Phase 2: 頑健性
- パラメータ感度分析（隣接パラメータで急激に劣化しないか）
- Monte Carloシャッフル（日付シャッフルで同等のSRが出るならランダム）
- Bootstrap CI（シャープレシオの信頼区間）
- サブサンプル安定性（前半/後半で結果が変わらないか）

### Phase 3: ライブ検証
- ペーパートレード → 少額 → フル展開

## ルール進化ロードマップ

R1: EW全21体（パラメータ0）→ ベースライン
R2: EW少数精鋭（理論ベース選抜）→ 最強の少数組合せ
R3: 逆ボラティリティ（パラメータ0）→ σ²低減でG向上
R4: HRP/HERC（構造発見）→ クラスタ構造活用
R5: Kelly分数（理論式）→ 幾何リターン最大化
R6: レジーム連動（パラメータ1）→ 市場環境適応
R7: モメンタム of 忍法（パラメータ1）→ 勝ち忍法傾斜
R∞: 知見統合 → ラルフループ収束解

各ルールの進化条件:
1. 前ルールのCAGR超え（第一目標）
2. 元の材料21体個別の最強を超え
3. WF OOS ≥ IS×70%
4. PBO < 0.15

## 主要論文・参照

- López de Prado (2016): HRP原論文 "Building Diversified Portfolios that Outperform Out-of-Sample"
- López de Prado (2019): NCO "A Robust Estimator of the Efficient Frontier" SSRN 3469961
- Antonov, Lipton, López de Prado (2024, ADIA Lab): HRP理論証明
- Raffinot (2018): HERC "The Hierarchical Equal Risk Contribution Portfolio" SSRN 3237540
- DeMiguel et al. (2009): 1/N vs optimal "Optimal vs Naive Diversification"
- Bailey & López de Prado: PBO "Probability of Backtest Overfitting" SSRN 2326253
- Sierpinski Graph Portfolios (2025): arXiv 2503.12328
- Barbell CTA Structure (2025): arXiv 2510.23150v2
- Statistical Jump Model (2024): arXiv 2402.05272v2
- GT-Score (Sheppert 2025): arXiv 2602.00080
- 過適合詳細: docs/research/overfitting-detection-prevention-2025.md

## Python実装ライブラリ

- skfolio (2025): HRP, HERC, NCO。scikit-learn互換
- Riskfolio-Lib (v7.2): HRP, HERC, NCO, HCAA。32リスク尺度対応
- arch: SPA, StepM, MCS（Bootstrap系検定）
- pypbo: PBO計算
