# モメンタム感度分析 第二弾 — 執行日感度分析 — v1.5

> シリーズ: 第一弾=月末N営業日前モメンタム感度分析(`month-end-n-day-momentum-sensitivity-asis-tobe-5w1h_20260731.md`) / **第二弾=本書(E感度)** / 第三弾=N×E二次元ロバストネス検証(`nxe-2d-robustness-asis-tobe-5w1h_20260801.md`)

## §0 セーブポイント

- 正本: 本ファイル
- 起点: 殿指示 2026-07-31「執行日だけの感度分析。モメンタム測定日は月末最終営業日close固定。シグナルはN=0に固定。変更するのは翌月の執行日だけ」
- 前提: 実験1(N日前=測定日感度, cmd_4198)が完了し、DM2/DM6ともN=0-7でロバストネス確認済み
- v1.0: 初版
- v1.1: 家老REQUEST_CHANGES 6件反映(共通closed cohort/signal-holding分離/欠損fail-closed/parity厳密化/provenance固定/指標AC化)
- v1.2: 家老2回目REQUEST_CHANGES 4件反映(fail-closed厳密化/provenance現物確立/MaxDD符号修正/SPY比較表+分割境界固定)
- v1.3: 家老3回目REQUEST_CHANGES 2件反映(cohort定義統一/provenance snapshot認定手順)
- v1.4: 家老4回目REQUEST_CHANGES 3件反映(signals SSOT是正/旧snapshot認定分岐削除→一本道/cohort除外timestamp基準化)
- v1.5: 家老5回目REQUEST_CHANGES 1件反映(signals月内重複の一意化規則+抽出SQL+key重複=0 AC化)

## §1 やること

DM2とDM6について、N=0の現行シグナルを固定したまま、執行日だけをE=0〜7営業日遅延させてopen-to-openリターンを比較する。

## §2 用語

- E: 執行遅延の営業日数。E=0=翌月第1営業日のopen(現行)。E=3=翌月第4営業日のopen
- シグナル(signal): N=0で計算された月次シグナル。relative momentum判定の結果(TQQQ/TECL/XLU/GLD)。全Eで不変
- ホールディング(holding_signal): リバランストリガーを適用した後の実際の保有銘柄。DM6 quarterly_janでは非リバランス月は前月のholdingを継続。全Eで不変
- 執行価格: 翌月第(1+E)営業日のopen
- 保有期間: 当月のE営業日目openから翌月の同じE営業日目openまで(entryとexitを同じEだけ平行移動)
- year_month: entry月(リターンが発生する保有期間の開始月)

## §3 実装方針

### 固定するもの

- モメンタム測定日: 月末最終営業日のclose(N=0)
- シグナル選択: N=0の現行ロジックそのまま(simulate_strategy_vectorized)
- デュアルモメンタム判定: 変更なし
- PF UUID: DM2=f8d70415-24f2-4b1a-a603-d0e86155255a、DM6=212e9eee-6acc-4f25-8a41-ea9fdf34a4e1
- リバランストリガー: DM2=monthly、DM6=quarterly_jan
- 売買コスト: 含めない(実験1と同条件)
- 配当: 価格データに反映済み(実験1と同条件)

### 変更するもの

- 執行日のみ: 翌月第(1+E)営業日のopen

### 保有期間

殿指示に従い、entryとexitの両方を同じEだけ平行移動する。

```
E=0: 翌月第1営業日open → 翌々月第1営業日open(現行と同一)
E=1: 翌月第2営業日open → 翌々月第2営業日open
E=3: 翌月第4営業日open → 翌々月第4営業日open
```

これにより各Eで保有期間がおおむね1ヶ月になり、執行日の効果だけを分離できる。

### 共通closed cohort

closed cohortの定義手順:

1. 各year_monthについて、E=0〜7の全てで必要なexit timestamp(翌月第(1+E)営業日)を算出する
2. exit timestampがsnapshot max price_date以下の年月のみ採用。超える月は構造的除外
3. 全E共通集合 = E=0〜7全条件のintersection(E=7が最も厳しいため自然にE=7基準で決まる)
4. 固定した共通集合に対して、全E×全PF保有資産×SPYのE営業日openが揃うか検証する
5. 1件でも欠損があれば即停止(fail-closed)。価格存在性でcohortを縮小しない

### signal_mapとholding_signalの分離

実験1のN=0結果からsignal_map(シグナル判定)とholding_map(リバランス適用後の保有銘柄)を分離して保持する。

- DM6 quarterly_jan: 非リバランス月のholding_signalはsignal_mapと異なる(前月holding継続)
- CSV出力: signal列とholding_signal列を両方出力
- 全Eでsignal/holding_signalが不変であることをexact mismatch=0で検証(AC化)

### 再利用する既存コード

実験1(cmd_4198)のスクリプトをベースにする。モメンタム再計算は不要。

- シグナル生成: 実験1のN=0結果をそのまま使用(signal_map/holding_map)
- 価格取得: load_prices(SQLite)から月内全取引日のopen価格を取得
- リターン計算: E日目openから翌月E日目openのリターンを算出
- SPY: 同じE日目open-to-openで算出

### Provenance(実験間再現性)

#### DB snapshot

発見済み現物:
- path: /mnt/c/Python_app/DM-signal/analysis_runs/gs_prefetch.db
- mtime: 2026-07-09T17:26:03+09:00
- size: 11870208 bytes
- SHA256: 9f4ec19fa837d3d903ef6fde054e9e7056246f005d6ddc087c8d19d113e7d199

ただしcmd_4198実行時にこのDBを使った証跡はreport/archive/commitに残っていない(commit 92d1eb18はスクリプト+成果CSVのみ、入力DB/signalsなし)。

#### production_signals

production_signalsファイルは不在。抽出手順を一意化する:
- 抽出元: 本番DB signalsテーブル(date, signal, holding_signal列。signals SSOT)
- 対象PF: DM2(f8d70415-24f2-4b1a-a603-d0e86155255a) + DM6(212e9eee-6acc-4f25-8a41-ea9fdf34a4e1)
- 月内重複の一意化: signalsは1PF・1月に日次複数行がある。月ごとにmax(date)の行を1件採用する
- 抽出SQL(read-only、決定的):
  ```sql
  SELECT DISTINCT ON (portfolio_id, to_char(date, 'YYYY-MM'))
    portfolio_id, to_char(date, 'YYYY-MM') AS year_month, signal, holding_signal
  FROM signals
  WHERE portfolio_id IN ('f8d70415-24f2-4b1a-a603-d0e86155255a', '212e9eee-6acc-4f25-8a41-ea9fdf34a4e1')
  ORDER BY portfolio_id, year_month, date DESC
  ```
- 抽出後AC: key(portfolio_id, year_month)重複=0。DM2/DM6各year_month行数=distinct key数
- 抽出内容: (portfolio_id, year_month, signal, holding_signal) のtuple形式テキスト
- 進行中月(closed cohort外)は抽出に含めてよいがcohort判定では除外
- 保存先: /mnt/c/Python_app/DM-signal/analysis_runs/production_signals.txt
- read-only抽出コマンド: 実装時に記録

#### Snapshot凍結手順(一本道)

旧cmd_4198のCSVにholding_signal列が保存されておらず、旧snapshotとの三重parity認定は不可能。したがって:

1. 発見DB+新規抽出production_signalsを単一凍結snapshotとする
2. このsnapshotでcmd_4198を再実行し、新cmd_4198 N=0の結果を得る(旧成果は参考値扱い)
3. 同一snapshotで実験2を実行し、E=0の結果を得る
4. 新cmd_4198 N=0と実験2 E=0のreturn/holding_signal/signal三重parity=0で両実験間の同一性を証明する
5. AC化: DB SHA256の前後一致(実行前後で変わっていないこと)+production_signals SHA256を記録

#### 記録する項目

- repo: /mnt/c/Python_app/DM-signal
- script: scripts/analysis/cmd_4199_execution_delay_sensitivity.py
- DB: 上記path (SHA256を実行前後で比較)
- production_signals: 上記path (SHA256を記録)
- venv: /mnt/c/Python_app/DM-signal/.venv
- refresh禁止: 実験2完了までgs_prefetch.dbを再prefetchしない

### 環境

- 実験1と同一。ローカル完結、本番コード無変更
- DB: gs_prefetch.db(既にprefetch済み。refresh禁止)
- 出力: CSV + 比較表

## §4 検証するE一覧

E_VALUES = [0, 1, 2, 3, 4, 5, 6, 7]

## §5 AC

- AC1: E=0 parity — closed cohort(現月除外)のDM2/DM6について、E=0のreturn_openが実験1 N=0の同一closed subset値と一致(abs<=1e-6)。holding_signal exact mismatch=0。signal exact mismatch=0。mismatch>0→E>0停止
- AC2: DM2/DM6それぞれE=0〜7のリターンがCSV出力。CSV列: pf_id/year_month/E/signal/holding_signal/return_open/SPY_return_open/excess_return。全Eでyear_month集合・行数が同一。missing=0
- AC3: cmd_4199_*プレフィックスの成果物として、E×PFのCAGR/Sharpe/MaxDD/累積リターン比較表(全期間)+前半/後半分割がdocs/researchに保存。PFとSPYの両方の指標+PF-SPY差分を出力。E=0との差分も表示。分割境界=共通closed cohortのlen//2で一意化。成果物現物確認(test -s)。殿の3問(§6)への明示回答を含む
- AC4: context/dm-signal-research.mdへ結果参照を還流

### 指標の数値定義

- CAGR: (1+cumulative_return)^(12/n_months) - 1
- Sharpe: mean(monthly_returns) / std(monthly_returns, ddof=1) * sqrt(12)。rf=0
- MaxDD: min(drawdown)。drawdown = wealth/peak - 1(0以下)。月次ベース。実験1と同一表現(負値)
- 累積リターン: prod(1+monthly_returns) - 1
- excess_return: PF monthly_return - SPY monthly_return(回帰アルファではない)

## §6 見るべき3点(殿指示)

1. E=0〜7の全域でSPY優位性が維持されるか
2. 特定のEで性能崩壊が起きないか
3. 執行遅延による性能水準の変動がどの程度か

最良のEを探す必要はない。AC3の比較表にこの3問への明示回答を含める。

## §7 結果の差が生じる要因(殿指示)

- 月初フロー(month-end rebalancing effect)
- 月初数日間の価格変動
- シグナルの短期的な減衰
- 執行を遅らせる機会損失

## §8 実験1との対比

- 実験1(N日前): 変動=シグナル計算日、固定=執行日(翌月初open)、保有期間=全N同一(月初open→翌月初open)、モメンタム再計算=必要
- 実験2(E日遅延): 変動=執行日、固定=シグナル(N=0)、保有期間=全E同一(E日目open→翌月E日目open)、モメンタム再計算=不要

## §9 欠損処理(fail-closed)

許容する除外は構造上exit未確定の末尾月のみ(E>0で翌月E営業日目が未到来)。

closed range(末尾除外後)内のPF保有資産/SPYのE営業日openが欠損した場合は、件数を出力した上で即停止する(黙って月を落とさない)。

出力する件数:
- 全月数(closed range)
- 採用月数
- 末尾除外月数(構造的除外のみ)
- data_missing(closed range内の価格欠損。AC化: data_missing=0)

## §10 因果リンク

- origin: `[[殿指示_執行日感度分析_20260731]] -> [[実験1_N日前ロバスト確認]] -> [[実験2_執行日感度]]`
- ← [[cmd_4198_N日前感度分析]]

---

# 実験結果 (cmd_4199 2026-07-31)

## §11 Snapshot検証

- DB SHA256 before/after: `9f4ec19fa837d3d903ef6fde054e9e7056246f005d6ddc087c8d19d113e7d199` (不変)
- production_signals SHA256: `ac4d63429877f55f7d2ffdc6bb00aa1fb3a30fb2c38d5bf18f170822cdfcb240`; rows=382; duplicate_keys=0
- E0三重parity: return=0, holding=0, signal=0 (同一snapshot証明)
- closed cohort: DM2=182ヶ月, DM6=194ヶ月; data_missing=0
- 分割境界: DM2=91, DM6=97 (len//2)

## §12 ポートフォリオ別の全結果

### DM2 (182ヶ月)

SPYベンチマーク(E=0): CAGR=0.1410, Sharpe=0.9703, MaxDD=-0.2331

| PF | E | PF CAGR | PF Sharpe | PF MaxDD | PF Cumul | Final Asset | SPY CAGR | PF-SPY CAGR | PF-SPY Sharpe | ΔE0 PF CAGR |
|----|---|---------|-----------|----------|----------|-------------|----------|-------------|---------------|-------------|
| DM2 | 0 | 0.4722 | 1.0674 | -0.6102 | 351.84 | 352.84 | 0.1410 | 0.3313 | 0.0971 | 0.0000 |
| DM2 | 1 | 0.5150 | 1.0624 | -0.6626 | 543.94 | 544.94 | 0.1411 | 0.3739 | 0.1268 | +0.0428 |
| DM2 | 2 | 0.5279 | 1.1052 | -0.6671 | 618.49 | 619.49 | 0.1415 | 0.3864 | 0.1293 | +0.0557 |
| DM2 | 3 | 0.5022 | 1.0679 | -0.6300 | 478.07 | 479.07 | 0.1404 | 0.3618 | 0.0396 | +0.0300 |
| DM2 | 4 | 0.5085 | 1.1462 | -0.5405 | 509.67 | 510.67 | 0.1407 | 0.3679 | 0.0527 | +0.0363 |
| DM2 | 5 | 0.5302 | 1.1889 | -0.5691 | 632.72 | 633.72 | 0.1395 | 0.3907 | 0.1274 | +0.0580 |
| DM2 | 6 | 0.5223 | 1.1348 | -0.5709 | 585.26 | 586.26 | 0.1400 | 0.3823 | 0.1120 | +0.0501 |
| DM2 | 7 | 0.5449 | 1.1899 | -0.5860 | 731.85 | 732.85 | 0.1397 | 0.4052 | 0.1162 | +0.0727 |

### DM6 (194ヶ月)

SPYベンチマーク(E=0): CAGR=0.1418, Sharpe=0.9646, MaxDD=-0.2331

| PF | E | PF CAGR | PF Sharpe | PF MaxDD | PF Cumul | Final Asset | SPY CAGR | PF-SPY CAGR | PF-SPY Sharpe | ΔE0 PF CAGR |
|----|---|---------|-----------|----------|----------|-------------|----------|-------------|---------------|-------------|
| DM6 | 0 | 0.5551 | 1.1813 | -0.4999 | 1258.01 | 1259.01 | 0.1418 | 0.4133 | 0.2167 | 0.0000 |
| DM6 | 1 | 0.5695 | 1.1516 | -0.4762 | 1460.42 | 1461.42 | 0.1417 | 0.4278 | 0.2161 | +0.0144 |
| DM6 | 2 | 0.5360 | 1.1333 | -0.5011 | 1030.65 | 1031.65 | 0.1417 | 0.3943 | 0.1531 | -0.0190 |
| DM6 | 3 | 0.4777 | 1.0771 | -0.5882 | 550.72 | 551.72 | 0.1409 | 0.3368 | 0.0494 | -0.0774 |
| DM6 | 4 | 0.3932 | 1.0365 | -0.5868 | 211.83 | 212.83 | 0.1414 | 0.2517 | -0.0670 | -0.1619 |
| DM6 | 5 | 0.4199 | 1.0667 | -0.5141 | 288.55 | 289.55 | 0.1400 | 0.2800 | 0.0040 | -0.1351 |
| DM6 | 6 | 0.4184 | 1.0324 | -0.5376 | 283.37 | 284.37 | 0.1396 | 0.2788 | 0.0064 | -0.1367 |
| DM6 | 7 | 0.4342 | 1.0620 | -0.4956 | 339.27 | 340.27 | 0.1387 | 0.2955 | -0.0137 | -0.1209 |

## §13 E=0との比較

### DM2

| PF | E | ΔPF CAGR | ΔPF Sharpe | ΔPF MaxDD | MaxDD変化 |
|----|---|----------|-----------|-----------|----------|
| DM2 | 0 | 0.0000 | 0.0000 | 0.0000 | 基準 |
| DM2 | 1 | +0.0428 | -0.0050 | -0.0524 | 悪化 |
| DM2 | 2 | +0.0557 | +0.0378 | -0.0569 | 悪化 |
| DM2 | 3 | +0.0300 | +0.0004 | -0.0198 | 悪化 |
| DM2 | 4 | +0.0363 | +0.0787 | +0.0697 | 改善 |
| DM2 | 5 | +0.0580 | +0.1215 | +0.0411 | 改善 |
| DM2 | 6 | +0.0501 | +0.0673 | +0.0393 | 改善 |
| DM2 | 7 | +0.0727 | +0.1225 | +0.0242 | 改善 |

### DM6

| PF | E | ΔPF CAGR | ΔPF Sharpe | ΔPF MaxDD | MaxDD変化 |
|----|---|----------|-----------|-----------|----------|
| DM6 | 0 | 0.0000 | 0.0000 | 0.0000 | 基準 |
| DM6 | 1 | +0.0144 | -0.0297 | +0.0237 | 改善 |
| DM6 | 2 | -0.0190 | -0.0480 | -0.0012 | 悪化 |
| DM6 | 3 | -0.0774 | -0.1042 | -0.0883 | 悪化 |
| DM6 | 4 | -0.1619 | -0.1448 | -0.0869 | 悪化 |
| DM6 | 5 | -0.1351 | -0.1146 | -0.0142 | 悪化 |
| DM6 | 6 | -0.1367 | -0.1489 | -0.0377 | 悪化 |
| DM6 | 7 | -0.1209 | -0.1193 | +0.0044 | 改善 |

## §14 ベンチマーク優位性の確認

### DM2

- 全EでCAGRがSPYを上回ったか: **YES**(最低E=0: 0.4722 vs SPY 0.1410)
- 全EでSharpeがSPYを上回ったか: **YES**(最低E=0: 1.0674 vs SPY 0.9703)
- 最も悪いE: CAGR→E=0(0.4722)、Sharpe→E=1(1.0624)
- 性能崩壊: なし。むしろE>0でCAGRが改善する傾向

### DM6

- 全EでCAGRがSPYを上回ったか: **YES**(最低E=4: 0.3932 vs SPY 0.1414)
- 全EでSharpeがSPYを上回ったか: **6/8**。E=4(PF-SPY Sharpe=-0.067)とE=7(PF-SPY Sharpe=-0.014)でSPY Sharpeを下回る
- 最も悪いE: CAGR→E=4(0.3932)、Sharpe→E=4(1.0365)
- 性能崩壊: E=4でCAGRが-16.2ppと大幅低下。ただしCAGR自体は39.3%でSPY(14.1%)を25.2pp上回る

### 総括表

| PF | Tested E | E CAGR>BM | E Sharpe>BM | Worst E(CAGR) | Worst E(Sharpe) | CAGR優位性 | Sharpe優位性 | 性能不変性 |
|----|----------|-----------|-------------|---------------|-----------------|-----------|-------------|-----------|
| DM2 | 8 | 8/8 | 8/8 | E=0(0.4722) | E=1(1.0624) | YES | YES(強い) | 中程度 |
| DM6 | 8 | 8/8 | 6/8 | E=4(0.3932) | E=4(1.0365) | YES | 概ね維持 | 中程度 |

## §15 Eに対する性能変動の大きさ

| PF | CAGR Min | CAGR Max | CAGR Range | Sharpe Min | Sharpe Max | Sharpe Range | Std CAGR | Std Sharpe |
|----|----------|----------|------------|------------|------------|--------------|----------|-----------|
| DM2 | 0.4722 | 0.5449 | 0.0727 | 1.0624 | 1.1899 | 0.1275 | 0.0239 | 0.0498 |
| DM6 | 0.3932 | 0.5695 | 0.1763 | 1.0324 | 1.1813 | 0.1489 | 0.0667 | 0.0533 |

DM2: E変動幅7.3pp、変動はN実験(8.0pp)と同程度
DM6: E変動幅17.6pp、N実験(3.3pp)の5倍以上。執行日感度がN感度より格段に大きい

## §16 極端に悪いEの確認

- DM2: 極端な悪化なし。E>0でCAGRが全般に上昇する傾向。原因は本実験だけでは特定できない
- DM6: **E=4が突出して悪い**(CAGR -16.2pp)。E=3〜7で一帯に悪化。ただしCAGR最悪39.3%でSPY(14.1%)は大幅超過。E=4,7ではSharpeがSPYを下回る

## §17 期間別の確認

SPYベンチマーク期間別: DM2前半CAGR=0.1205/後半=0.1618、DM6前半=0.1273/後半=0.1565

### DM2

| E | Period | PF CAGR | PF Sharpe | PF MaxDD | PF-SPY CAGR |
|---|--------|---------|-----------|----------|-------------|
| 0 | first_half | 0.4516 | 1.2426 | -0.3802 | +0.3311 |
| 0 | second_half | 0.4931 | 0.9985 | -0.6102 | +0.3313 |
| 1 | first_half | 0.4586 | 1.1248 | -0.4231 | +0.3365 |
| 1 | second_half | 0.5736 | 1.0517 | -0.6626 | +0.4132 |
| 2 | first_half | 0.4414 | 1.1373 | -0.3650 | +0.3201 |
| 2 | second_half | 0.6195 | 1.1190 | -0.6671 | +0.4577 |
| 3 | first_half | 0.4238 | 1.1263 | -0.3100 | +0.3029 |
| 3 | second_half | 0.5850 | 1.0693 | -0.6300 | +0.4248 |
| 4 | first_half | 0.4355 | 1.1920 | -0.2853 | +0.3118 |
| 4 | second_half | 0.5853 | 1.1458 | -0.5405 | +0.4274 |
| 5 | first_half | 0.4353 | 1.1969 | -0.3113 | +0.3108 |
| 5 | second_half | 0.6313 | 1.2129 | -0.5691 | +0.4766 |
| 6 | first_half | 0.4369 | 1.2002 | -0.3631 | +0.3120 |
| 6 | second_half | 0.6128 | 1.1323 | -0.5709 | +0.4575 |
| 7 | first_half | 0.4624 | 1.3109 | -0.3581 | +0.3371 |
| 7 | second_half | 0.6320 | 1.1647 | -0.5860 | +0.4778 |

### DM6

| E | Period | PF CAGR | PF Sharpe | PF MaxDD | PF-SPY CAGR |
|---|--------|---------|-----------|----------|-------------|
| 0 | first_half | 0.3811 | 1.0711 | -0.3265 | +0.2538 |
| 0 | second_half | 0.7509 | 1.2965 | -0.4999 | +0.5944 |
| 1 | first_half | 0.3846 | 1.0511 | -0.3901 | +0.2573 |
| 1 | second_half | 0.7791 | 1.2625 | -0.4762 | +0.6227 |
| 2 | first_half | 0.3680 | 1.0697 | -0.3104 | +0.2423 |
| 2 | second_half | 0.7247 | 1.2255 | -0.5011 | +0.5668 |
| 3 | first_half | 0.3521 | 1.0374 | -0.2972 | +0.2272 |
| 3 | second_half | 0.6150 | 1.1422 | -0.5882 | +0.4579 |
| 4 | first_half | 0.3108 | 1.0354 | -0.3419 | +0.1820 |
| 4 | second_half | 0.4807 | 1.0726 | -0.5868 | +0.3264 |
| 5 | first_half | 0.3264 | 1.0603 | -0.2851 | +0.1991 |
| 5 | second_half | 0.5201 | 1.1074 | -0.5141 | +0.3673 |
| 6 | first_half | 0.3273 | 1.0554 | -0.2604 | +0.2002 |
| 6 | second_half | 0.5156 | 1.0615 | -0.5376 | +0.3634 |
| 7 | first_half | 0.3073 | 1.0737 | -0.2313 | +0.1787 |
| 7 | second_half | 0.5734 | 1.1200 | -0.4956 | +0.4246 |

全E×両期間でSPY CAGRを上回る。最小超過=DM6 E=7 first_half +17.9pp。

## §18 月次リターン系列

CSV存在: **YES**
- ファイル: `docs/research/cmd_4199_execution_delay_returns.csv`
- 行数: 3,008行
- 列: `pf_id, year_month, E, signal, holding_signal, return_open, SPY_return_open, excess_return`
- 関連: `cmd_4199_execution_delay_metrics.csv`(16行), `cmd_4199_execution_delay_split_metrics.csv`(32行)

## §19 結果の要約

### 最終判定文

月初第1営業日から第8営業日まで執行基準日を変更しても、DM2およびDM6は全条件でSPYを上回るCAGRを維持した。

したがって、両戦略の収益優位性は特定の執行日にのみ依存しておらず、執行日変更に対してロバストである。

DM2はCAGR・Sharpeの両面で安定して優位性を維持した。DM6も絶対収益の優位性は維持したが、EによるCAGR変動幅は大きく、性能水準には一定の感度が認められた。

本実験は最適執行日の選定を目的とせず、執行日を現実的な範囲で変更しても戦略が崩壊しないことを確認した。

### Portfolio 1: DM2

- CAGR優位性のロバストネス: **Yes**(全EでSPY CAGRを大幅に上回る。最低E=0: +33.1pp)
- Sharpe優位性のロバストネス: **Yes**(全EでSPY Sharpeを上回る。8/8)
- 性能不変性のロバストネス: **中程度**(CAGR Range 7.3pp, Std 2.4pp。E>0で上昇傾向があり不変ではない)
- 極端に悪いE: **なし**（E=0が最低だがSPY大幅超過）
- 備考: 月初第1営業日より数営業日後を基準とするスケジュールの方が高い成績を示した。原因が月初フロー回避であるかは未検証

### Portfolio 2: DM6

- CAGR優位性のロバストネス: **Yes**(全EでSPY CAGRを上回る。最低E=4: +25.2pp)
- Sharpe優位性のロバストネス: **概ね維持**(6/8でSPY Sharpe超過。E=4で-0.067、E=7で-0.014。PF Sharpe自体は全Eで1.03以上)
- 性能不変性のロバストネス: **中程度**(CAGR Range 17.6pp, Std 6.7pp。CAGRの執行日感度が大きい)
- 極端に悪いE: **E=4**(CAGR -16.2pp。ただしSPY対比+25.2ppで崩壊ではない)
- 総合判定: 全Eで高いSharpe水準(1.03以上)を維持しリスク調整後優位性が大きく崩壊したとは言いにくいが、CAGRの執行日感度は無視できない

## §20 実験1との対比まとめ

| | DM2 N実験 | DM2 E実験 | DM6 N実験 | DM6 E実験 |
|--|----------|----------|----------|----------|
| CAGR Range | 8.0pp | 7.3pp | 3.3pp | 17.6pp |
| Sharpe Range | 0.10 | 0.13 | 0.08 | 0.15 |
| SPY CAGR優位 | 8/8 | 8/8 | 8/8 | 8/8 |
| SPY Sharpe優位 | 7/8 | 8/8 | 8/8 | 6/8 |
| 最悪ΔE0/ΔN0 | -8.0pp | +0(E=0が最低) | -2.8pp | -16.2pp |
| CAGR優位性 | YES | YES | YES | YES |
| Sharpe優位性 | 実質YES | YES(強い) | YES | 概ね維持 |
| 性能不変性 | 中程度 | 中程度 | 強い | **中程度** |

DM2は測定日・執行日ともに中程度の感度で、戦略優位性は強くロバスト。遅延側で改善する傾向がある。

DM6は測定日に非常にロバストだが、執行日にはCAGRの感度が大きい。Sharpe優位性は概ね維持されており(6/8でSPY超過、全Eで1.03以上)、リスク調整後優位性が大きく崩壊したとは言いにくい。

## §21 保有区間モデルの注記

本実験はentry/exitの両方を同じE日だけ平行移動している(設計書§3)。これは「保有区間をE日ずらした仮想世界」のモデルであり、「本番で執行をE日遅延させた場合」のモデルとは異なる。

具体的な差異:
- **本実験**: 月初第(1+E)営業日openでentry→翌月第(1+E)営業日openでexit。月初日目1〜Eのリターンはどのholdingにも帰属しない
- **本番遅延**: 日目1〜Eは旧holdingで保有継続。日目(1+E)で新holdingにスイッチ。リバランス月の切替境界に旧→新の遷移区間が存在する

非リバランス月(DM6の8/12ヶ月)では同一銘柄を継続保有するため、差は純粋にentry/exitの価格参照点のずれから生じる。リバランス月(4/12ヶ月)では、旧holdingで日目1〜Eを保有するリターンが本実験には反映されていない。

実測: E=0/E=4のholding_signal切替回数は44回で同一。非リバランス月でのholding変更は0件。

この差異は初期スクリーニングの結論(全EでSPY優位性維持)には影響しないが、DM6のCAGR感度(17.6ppレンジ)の一部はこのモデル差異に起因する可能性がある。正確な遅延執行シミュレーションには、リバランス月の旧holding遷移区間を含む別モデルが必要。
