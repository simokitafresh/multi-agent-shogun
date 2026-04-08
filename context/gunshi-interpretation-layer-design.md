<!-- last_updated: 2026-04-09 -->
# 知識辞書 解釈層(dm-signal/)強化設計
<!-- cmd: 将軍相談 2026-04-03 | author: gunshi -->

## §1. 現状分析

### 一次知識層 vs 解釈層

| 層 | ファイル数 | カバー範囲 |
|----|----------|-----------|
| methods/ | 63件 | 学術手法の純知識 |
| dm-signal/ | 8件 | DM-Signal固有の適用解釈 |
| **カバー率** | **~18手法/63** | **約29%** |

### dm-signal/現有ファイルと対象手法

| ファイル | 対象 | 充実度 |
|---------|------|--------|
| covariance-preprocessing-interpretations.md | M13-M16(4件) | 中(M14 Gerber=一次層未作成) |
| flair-interpretation.md | M17 FLAIR | 高(新規作成) |
| meta-structure.md | メタ(PF=戦略) | 高 |
| methods-a-interpretations.md | 前半5件 | 中 |
| methods-b-interpretations.md | 後半6件 | 中 |
| portfolio-interpretations.md | PF構築系 | 中 |
| preprocessing-interpretations.md | FD等3件 | 低(FD中心) |
| sources-architecture-interpretations.md | sources+arch | 中 |

## §2. ギャップ分析(将軍指摘4領域)

### Gap 1: 前処理研究9手法のDM-Signal適用判定(最重要)

9手法(EMA/L1/Kalman/Gerber/FD/PE/JD/SSA/FDA)の研究結論がdm-signal/に未還流。

**存在する知見**(dm-signal-research.md §26-§30):
- EMA span=5: Standard PF CAGR+112%(cmd_1632)。FoF間接波及で朱雀+11%だがdepth=2/3で逆転(L538)
- L1 lam=10: Standard PF CAGR+383%(cmd_1633)。22/65PFにoverfit警告(neighbor gap>5pp)
- FDA K=32,lam=0: DM3 CAGR+232%だがMatch49.5%(cmd_1666)
- OOS検証(cmd_1660): EMA train/test差7.9pp(IS+15.2→OOS+7.3)。L1 train/test差41.5pp
- **FoF結論(L-PreprocessingFoFConclusion): 9手法全てbaseline負け。判断ロジック改善が次方向**

**不在**: dm-signal/に上記結論の適用判定マトリクスがない。次回前処理系cmdで忍者が同じ轍を踏むリスク。

### Gap 2: GS研究知見の解釈

**存在する知見**(dm-signal-research.md §25):
- R21: Ward寄与97.2%(Sharpe)、モメンタム2.8%。Ward構造が支配的価値源泉
- R12: K*=5(最適)、K=4次善。K3→6脱落なし安定構造
- selection blockパラメータ空間: 35万パターン(7忍法)のGS結果。cmd_1711で可視化中

**不在**: これらがdm-signal/に体系的にまとまっていない。「Ward改善>>>selection block改善」の戦略含意が解釈層にない。

### Gap 3: 殿の裁定の解釈層反映

**存在する裁定**:
- PI-021: 本番既存パイプラインは不変。変更ではなく機能追加のみ(`memory/dialogue_preprocessing_research_20260331.md` L1242)
- パリティ条件: ゴールデンデータ方式(本番DB 1回取得→固定ファイル。`dashboard.md` + `lord-conversation-index.md`)
- PI-009: GS=本番同一エンジン必須(MCP dm_signal_decisions)

**不在**: dm-signal/にこれらの制約が明文化されていない。忍者が実装時に参照できない。

### Gap 4: 知識部品の転用パターン

殿指摘: FLAIRの周期検出をlookback依存性解明に転用。

**本質**: 一次知識の「部品」(アルゴリズムの構成要素)を、元の用途と異なるDM-Signal文脈に読み替える。これが解釈層の最高付加価値。

**現状**: flair-interpretation.md §3にselection block応用を記載。しかし他の手法でこのパターンは皆無。

## §3. 優先順位(因果推論に基づく)

| 優先度 | 対象 | 因果鎖 | 影響度 |
|--------|------|--------|--------|
| **P1** | 前処理研究結論 | 未登録→次cmd忍者が再探索→FoF前処理を再実行→時間浪費 | **高**(研究サイクル短縮) |
| **P2** | 殿の裁定(PI) | 未登録→忍者がPI-021違反実装→本番破壊リスク | **高**(本番安全) |
| **P3** | GS研究知見 | 未体系化→selection block改善に過大投資→Ward改善を見逃す | **中**(研究方向) |
| **P4** | 転用パターン | P1-P3完了後に自然発生。各エントリに§転用候補を設けることで構造化 | **低**(P1-P3依存) |

## §4. 設計案

### エントリ標準フォーマット(提案)

```markdown
# {手法名} DM-Signal解釈

## §1. 適用判定
- verdict: 有効 / 条件付き有効 / 不適 / 未検証
- 対象: Standard PF / FoF / selection block / Ward

## §2. 検証結果
- cmd番号、定量結果、OOS結果

## §3. 制約
- 殿の裁定、PI、禁則

## §4. 転用候補
- この手法の部品を別用途に使えるか
```

### 新規ファイル案(3件)

**P1: `preprocessing-research-conclusions.md`**
- 9手法×{Standard PF, FoF}適用判定マトリクス
- OOS検証結果(EMA +7.3pp, L1要追加検証)
- **結論: FoF前処理は全手法baseline負け。次はselection block改善**
- 転用: FLAIRの周期検出→lookback依存性解明

**P2: `production-invariants.md`**
- PI-021: 既存不変、追加のみ(出典: dialogue_preprocessing L1242)
- PI-009: GS=本番同一エンジン(出典: MCP dm_signal_decisions)
- パリティ条件: ゴールデンデータ方式(出典: lord-conversation-index)
- 忍者が実装cmdで参照すべき制約の一覧

**P3: `gs-research-interpretations.md`**
- Ward寄与97.2%(R21) → selection block改善の期待値上限=2.8%
- K*=5安定構造(R12)
- lookback依存性→FLAIRとの接続点
- cmd_1711結果(パラメータ空間構造)反映待ち

### 実装方法

cmd 3本(P1/P2/P3各1本)を推奨。P4は各エントリの§4に埋込み。
P1+P2は既存知見の整理のみ(scout_exempt)。P3はcmd_1711結果待ち。
