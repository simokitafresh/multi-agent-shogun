# モメンタム感度分析 第三弾 — 測定日N×執行日E 二次元ロバストネス — AsIs/ToBe 5W1H設計書 v1.3 【✅レビュー反映済・実験GO】

> シリーズ: 第一弾=月末N営業日前モメンタム感度分析(`month-end-n-day-momentum-sensitivity-asis-tobe-5w1h_20260731.md` v3.4) / 第二弾=執行日感度分析(`execution-delay-sensitivity-asis-tobe-5w1h_20260731.md` v1.5) / **第三弾=本書(N×E直積)**

## §0 セーブポイント

- 正本: 本ファイル
- 起点: 殿指示 2026-08-01 03:27「予定どおり モメンタム測定日N × 執行日Eの二次元ロバストネス検証。目的は最良の組み合わせ探しではなく、測定日と執行日を同時に現実的な範囲でずらしても戦略優位性が維持されるかの確認」
- 前提: 実験1(N感度, month-end-n-day-momentum-sensitivity v3.4)と実験2(E感度, execution-delay-sensitivity v1.5)が完了済み。本実験は両者の直積
- v1.0: 初版(殿仕様の忠実転記+先行2実験の固定条件継承)
- **v1.3 (2026-08-02 20:52): 家老レビューREQUEST_CHANGES(blt_205112)の限定4修正を反映。①§2へ保有区間モデル限界(実験2 §21)を継承 ②§4へDM6×E=4近傍の事前脆弱候補を追加(全セル探索は維持) ③§4/§5へ独立標本数注記(DM6独立signal更新≈65回) ④AC1をThird common cohort基準へ改定(intersection cohort再集計比較・native公表値との完全一致は不要)。家老裁定: 反映確認後は追加設計往復なしで即GO**

## §1 やること

standard DM2(UUID: f8d70415-24f2-4b1a-a603-d0e86155255a)と standard DM6(UUID: 212e9eee-6acc-4f25-8a41-ea9fdf34a4e1)について:

モメンタム測定日N(月末N営業日前close)と執行遅延E(翌月第1+E営業日open)を同時に振り、N×E=8×8=64条件のopen-to-openリターンでロバストネス面を作る。DM2/DM6の2本×64セル=128系列。

**目的は最良点探しではない。** 全64条件でSPY超過が維持されるか、性能崩壊領域があるか、N・E単独では見えない相互作用(組み合わせ脆弱領域)があるかの確認。

## §2 用語

- N: モメンタム測定日。月末N営業日前のclose。N=0=月末最終営業日close(現行)。N_VALUES=[0,1,2,3,4,5,6,7]
- E: 執行遅延。翌月第(1+E)営業日のopen。E=0=翌月第1営業日open(現行)。E_VALUES=[0,1,2,3,4,5,6,7]
- セル(N,E): signal endpointをN日前closeで計算したシグナルを、翌月第(1+E)営業日openで執行した系列
- 保有期間: entryとexitを同じEだけ平行移動(実験2 §2と同一)。当月第(1+E)営業日openから翌月第(1+E)営業日openまで
- alpha: PF open-to-open − SPY open-to-open(同一期間・同一執行日規則)
- **保有区間モデルの限界(実験2 §21から継承)**: 本実験のE適用はentryとexitの両方を同じEだけ平行移動する「保有区間をE日ずらした仮想世界」のモデルであり、「本番で執行をE日遅延させた場合」(日目1〜Eは旧holdingで保有継続→日目1+Eで新holdingへスイッチ)のモデルとは異なる。リバランス月では旧holdingで日目1〜Eを保有するリターンが本実験に反映されない(DM6は8/12ヶ月が非リバランス月ゆえ影響はリバランス月4/12に限られる)。この差異は優位性維持の判定には影響しないが、E方向のCAGR感度の一部はモデル差異に起因しうる

## §3 実装方針

### 固定するもの(NとE以外は一切変更しない)

- モメンタム式: calculate_weighted_momentum_vectorized(periods/weights/unit現行のまま。実験1と同一)
- 対象資産: 各PFのpipeline_config現行のまま
- ポートフォリオ構築: simulate_strategy_vectorized + PipelineEngine(信号正本再利用。手書き再実装禁止。実験1 §3と同一)
- ポジション変換: absolute momentum>=DTB3の二値(実験1 v3.4是正と同一)
- リバランストリガー: DM2=monthly、DM6=quarterly_jan(非リバランス月は前月holding継続。実験2 §2と同一)
- 売買コスト: なし
- 配当: 価格データに反映済み
- 同一closed cohort: 全64セルで同一(定義は§4)
- 執行の平行移動: entryとexitを同じEだけ移動(実験2と同一)

### 変更するもの

- N: signal endpointのみ(実験1の機構)
- E: 執行営業日のみ(実験2の機構)

### 再利用する既存コード(実験1/2のstandalone scriptを直積合成)

DM-signal repo (`/mnt/c/Python_app/DM-signal`)、本番コードは変更しない。ローカルstandalone script:

- 価格取得(2段階): prefetch_gs_data.py の prefetch_daily_prices → ローカルSQLite(gs_prefetch.db) → grid_search_metrics_v2.py の load_prices(SQLite専用。本番DB接続を渡さない)
- シグナル: 実験1のN日前signal endpoint機構(N=0〜7の8系列を先に確定)
- 執行: 実験2のE遅延執行機構(各N系列に対しE=0〜7を適用)
- 実験1のsignals月内重複一意化規則・実験2のsignals SSOT/provenance snapshot手順をそのまま継承

### 共通closed cohort

実験2 §3の定義を直積へ拡張する:

1. 各year_monthについて、N=0〜7の全signal endpointとE=0〜7の全exit timestamp(翌月第(1+E)営業日)の**全てが価格データ内に存在する**月だけをcohortに含める
2. 1ヶ月でも欠けるならその月を全64セルから除外(fail-closed。セルごとの母集団差を作らない)
3. cohort除外はtimestamp基準(実験2 v1.4と同一)
4. 確定したcohort(開始月・終了月・月数)を結果に明記

## §4 出力

### 各セル(N,E)ごと — 64セル×2PF

- CAGR
- Sharpe
- MaxDD
- SPY CAGRとの差
- SPY Sharpeとの差

SPYも同一E執行規則のopen-to-openで計算する(セルの執行日とSPYの執行日を揃える)。

### 要約値 — PFごと

- 全64条件中、SPY CAGR超過の割合
- 全64条件中、SPY Sharpe超過の割合
- 最悪条件のCAGR(とそのN,E)
- 最悪条件のSharpe(とそのN,E)
- CAGRのレンジ(min/max)
- Sharpeのレンジ(min/max)
- 性能崩壊条件の有無(定義: SPY CAGR以下となるセル)

### 見るべき点(殿仕様)

1. 全64条件でSPY CAGR超過が維持されるか
2. 明確に性能崩壊する領域があるか
3. NまたはEの一方だけでなく、組み合わせによる脆弱領域があるか
4. DM2とDM6でロバストネス面がどう異なるか
5. 最良点ではなく、全体の最低値と分布を見る
6. **事前脆弱候補(実験2実測から・家老レビュー反映)**: DM6はE感度が大きく(CAGR Range 17.6pp・最悪E=4)、**DM6×E=4近傍×N変動**が組み合わせ脆弱領域の第一候補。ただし事前候補への絞り込みは行わず**全64セル探索を維持**する(パラメータ空間縮小禁止)
7. **独立標本数の注記(実験1 §19注記から・家老レビュー反映)**: 64セルはグリッドの数であり独立標本数ではない。特にDM6(quarterly_jan)はNによって変わる独立シグナル更新が約65回にとどまるため、セル間の差を統計検定的に扱う際は月次リターン数・セル数を独立標本として扱わないこと

## §5 判定の考え方(殿仕様)

- DM6のように性能レンジが広くても、全条件でSPYを大幅に上回るなら「性能水準には感度があるが、戦略優位性は二次元でもロバスト」
- 特定のN×E領域でSPY以下になるなら「単独のN・E検証では見えなかった相互作用がある」
- **判定時の2注意(家老レビュー反映)**: (a)E方向の感度評価には§2の保有区間モデル限界を添えて解釈する(CAGR感度の一部はモデル差異由来の可能性) (b)64セルを独立標本と見なした統計的主張はしない(§4注記7)

## §6 二値AC

- AC1(家老レビューで改定): パリティは**本実験の共通cohort(Third common cohort)を基準**とする。①Third common cohort内で(N=0,E=0)セルを再計算し、return/holding/signalのmismatch=0を必須とする ②実験1/実験2との比較は、実験1/2の結果を**同一intersection cohortで再集計した値**と行う(実験1/2のnative cohort公表値との完全一致は要求しない — cohort母集団が異なるため) ③Third cohortの期間・月数と、実験1/2の各native cohortからの除外月数を結果に記録する
- AC2: 64セル×2PFの全セルが同一closed cohortで計算され、セル間の月数差=0
- AC3: §4の全出力(セル5指標×128+要約7値×2)が欠損なく出力される(FAIL/欠損セル=0)

## §7 5W1H

- WHY: 単独N・単独Eでロバストと確認済みの戦略が、二次元同時摂動でも優位性を保つかの確認(相互作用の検出)
- WHAT: 8×8=64条件×DM2/DM6のCAGR/Sharpe/MaxDD/SPY差の面と要約値
- WHEN: 今セッション以降(殿の実行指示に従う)
- WHERE: ローカルstandalone script(DM-signal本番コード無変更)
- WHO: 配備は家老の判断
- HOW: 実験1のN機構×実験2のE機構の直積合成。既存コード最大再利用
