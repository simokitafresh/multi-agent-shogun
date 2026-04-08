<!-- last_updated: 2026-03-30 -->
# Ward二段EW ネステッドFoF 本番完全稼働チェックリスト

> 言い訳一切不可。全項目PASS以外は失敗。「多分大丈夫」「論理的に同じはず」は不合格。
> 全てDBクエリ・API・CDPで**現物確認**せよ。

## ★最重要（これが全ての目的）

**1. 既存の全123体(65 standard + 58 FoF)が、従来と完全に同じリターン・保有・シグナルで表示されていること。**
**2. 新Ward FoFが、旧忍法15体を構成PFとしてWard二段EWで正しく加重されたリターン・保有を表示していること。**

1件でもズレ/異常があれば全体FAIL。

## 前提

- 目的: 旧忍法15体を構成PFとする**新しいネステッドFoF(FoF of FoF)**を本番DBに新規作成する
- **既存FoFの変更は一切行わない。新規エンティティの追加のみ**
- WardTwoStageEWBlock は既にコードに存在(cmd_1443 AC1で作成済み、BlockType.WARD_TWO_STAGE_EW として登録済み)
- performance fix(is_custom_weight gating)もデプロイ済み(commit 9d845ad4)
- terminal_block: `{"type": "WardTwoStageEW", "config": {"k": 5, "lookback_months": 36}}`
- selection_pipeline: 空(blocks: []。全15体がWard計算に参加)
- rebalance_trigger: monthly
- 構成PF: 旧忍法15体(加速/四つ目/変わり身/抜き身/追い風 × 常勝/激攻/鉄壁)

## Z. 既存PF完全不変の証明（最優先で実行）

fullrecalculate実行後、他の何よりも先にこのセクションを完了せよ。

- [ ] **Z1**: 全123体のmonthly_returnがスナップショットと完全一致
  - fullrecalculate前にスナップショット取得 → 後に比較
  - **差異0件**。1件でもズレたら即停止・報告

- [ ] **Z2**: 全123体のholding_signalがスナップショットと完全一致
  - **差異0件**

- [ ] **Z3**: 全123体のcumulative_returnがスナップショットと完全一致

- [ ] **Z4**: CDPでアプリを開き、既存PF（非忍法）3体以上の画面を確認
  - リターンチャート、保有シグナル、ポジションが従来通り表示
  - 目視で異常がないこと

- [ ] **Z5**: CDPでアプリを開き、旧忍法PF 3体以上の画面を確認
  - リターン・シグナル表示が従来と同一であること

## A. 新Ward FoFのDB設定が正しい

- [ ] **A1**: 新Ward FoFがDBに存在する(type="fof", is_active=True)
- [ ] **A2**: component_portfolios = 旧忍法15体のUUID全て(15個、欠けなし)
  - 本番DBからSELECTで旧忍法15体のIDを取得して使う（推測するな）
- [ ] **A3**: terminal_block.type = "WardTwoStageEW"
- [ ] **A4**: terminal_block.config.k = 5, lookback_months = 36
- [ ] **A5**: selection_pipeline.blocks = [](空。全15体通過)
- [ ] **A6**: rebalance_trigger = "monthly"
- [ ] **A7**: 既存123体のconfig JSONが一切変更されていない
  - 特にterminal_block, component_portfolios, selection_pipelineを確認

## B. fullrecalculate実行・速度

- [ ] **B1**: fullrecalculate(portfolio_id指定なし)が正常完了する（エラーなし）
- [ ] **B2**: 合計所要時間が15分以内
- [ ] **B3**: FoF層(L3_fof)が10分以内

## C. Ward計算の動作確認

- [ ] **C1**: 新Ward FoFの最新リバランス日のweightsがWard二段EWで計算されている
  - 15体がk=5クラスタに分類され、weight = (1/n_clusters) × (1/|cluster|)
  - **1/N均等(1/15 ≈ 0.0667)ではないことを確認**（Wardが発動した証拠）

- [ ] **C2**: weightsのキーが旧忍法15体のUUIDと完全一致(15個)

- [ ] **C3**: weights合計が1.0(誤差1e-10以内)

- [ ] **C4**: 非リバランス日のweightsが前回リバランス日からcarry-forwardされている
  - 月中の任意の日と前月末のweightsが一致
  - **⚠ cmd_1568発見**: OPT-A(cmd_1450)で非リバランス日momentum_data={skipped:true}→weightsキー消失→EWフォールバック。修正=recalculate_fof.py:866でweightsキー保持(L513)

- [ ] **C5**: weights_signatureが計算されている(Noneではない)

## D. リターン検算

- [ ] **D1**: 新Ward FoFのmonthly_returnを手動検算
  - 構成FoF(旧忍法)のmonthly_return × weight の加重合計 = Ward FoFのmonthly_return
  - 最低3ヶ月分

- [ ] **D2**: cumulative_returnが月次リターンの複利累積と一致

## D2.5 パフォーマンス定量評価（cmd_1570/cmd_1577）

Ward FoF vs 1/N EW全期間141ヶ月比較:
| 指標 | Ward | EW | 優位 |
|------|------|-----|------|
| 12M累積 | +54.93% | +54.68%(+0.25%) | ≒同等 |
| Sharpe | 2.00 | 1.98 | Ward微優位 |
| MaxDD | 22.56% | 21.59% | **EW優位** |
| Sortino | 5.48 | 5.50 | EW優位 |
| Calmar | 2.68 | 2.76 | EW優位 |
**総合判定: Ward非優位(1/4指標のみ)。PD-004裁定済: Ward FoFはkeep。**

## D2.7 パラメータ感度（cmd_1576）

K=5/LB=36(本番) vs K=4/LB=24(研究最適): Sharpe差0.1%未満(2.0801 vs 2.0793)。パラメータズレは軽微。
R19(99セルGS)真最適=K=4/LB=30。後方伝播検証不在が根因だが**Ward自体の付加価値がほぼゼロのため実質影響なし**。

## D2.9 Ward固定化根因（cmd_1578）

相関距離の構造的狭さ: separability=0.33(<0.5、全期間全k)。全ペア距離mean=0.61。
シンv2は旧より高相関(距離26%狭)でWardさらに不安定(ARI安定性45.5% vs 旧63.6%)。
**結論: Ward法のメカニズム自体の構造的限界。パラメータ調整では解決不能。**

## E. フロントエンド表示（CDP確認）

- [ ] **E1**: 既存PF（非忍法）のシグナル・リターン・保有が従来通り
- [ ] **E2**: 旧忍法PFのシグナル・リターン・保有が従来通り
- [ ] **E3**: 新Ward FoFが画面に表示され、リターンチャート・保有ポジションが正常
- [x] **E4**: Admin FoF管理画面でWeightBreakdown表示が正常（cmd_1573完了。`/api/portfolios/{id}/fof-weights`正式化+WeightBreakdown.tsx）

## F. 日次ETL後の継続確認

- [ ] **F1**: 次回日次ETL実行後、全PF/FoFのシグナル・リターンが正常
  - ETL後にZ1〜Z3相当のDB検証を再実行
