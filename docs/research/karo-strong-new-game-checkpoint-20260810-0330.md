# 家老 強くてニューゲーム復帰点 — 2026-08-10 03:30 JST

- status: active
- owner: karo
- source: 殿指示「今 クリアされても 今より強くてニューゲームができるようにせよ」
- current_goal: DM-Signal月次リターン実装・CI復旧・制御面高速化を、小粒度で止めずに完遂する
- updated_at: 2026-08-10 03:30 JST
- origin: `[[今クリアされても強くてニューゲーム]] -> [[infra-throughput-outcome-design-20260718]] -> [[strong_new_game_completion_contract]]`

## 復帰直後の結論

速度は一工程の短縮ではなく全体スループットで判定する。CI六分割は5 shardを88–93秒にしたが、単一node 292.92秒により最遅shardは394秒となり失敗。次の一手は分割数追加ではなく、そのtest本体の高速化である。

同時に、忍者へ次taskを即配備すると旧taskのfinal setterが新taskへ書き込み、旧report reviewが新taskの`ac_version`を参照してBLOCKする競合を確認した。高速回転そのものが露出させた制御面バグであり、旧reportを改変せず`parent_cmd`正本へ照合先を直す。

## 2026-08-10 03:30時点の実行レーン

| 忍者 | task | 一次/直近状態 | 復帰後の扱い |
|---|---|---|---|
| 疾風 | `cmd_4276_full` | report到着、format GATE PASS、レビュー待ち | review結果到着後、個別にcompletion GATE→将軍報告 |
| 影丸 | `cmd_4277_full` | acknowledged/busy | Dashboard 2-slot実装を継続 |
| 半蔵 | `cmd_karo_ci_fix_dm_signal_run_31326903152_normal` | in_progress/busy | CI 38 failuresの根治。stale receipt再生成による停止時間も構造穴として保持 |
| 才蔵 | `cmd_karo_slow_test_fof_golden_speed_cycle1_normal` | acknowledged/busy | 292.92秒node本体を最低10%高速化。golden hash/件数/schema不変 |
| 小太郎 | `cmd_karo_review_overlap_contract_fix_20260810_normal` | in_progress/busy | old reportとnew live taskの契約分離を根治 |
| 飛猿 | `cmd_4275_full` | report LGTM、format GATE PASS | formal bundle/completion GATEを個別処理 |

この表は復帰起点であり、`queue/karo_snapshot.txt`とpane一次状態が常に優先する。

## 確定済み成果

1. `cmd_4271` T-δ3: commit `745d50cf032c8c1aad1ac0196a0ddf73079300be`、対象1+56 PASS、GATE CLEAR、個別掲示済み。
2. `cmd_4273` T-γ4: commit `84292989bc6c6d32af89be116abc939224e5d172`。8,951 pair = unchanged 6,883 + correction-derived 2,068、PF 78、GATE CLEAR。cutoverは未実行。
3. `cmd_4267`: commit `6aad2808...`、2 PASS/FAIL0/SKIP0、GATE CLEAR。
4. `cmd_4269`: commits `c01d05ab...` + `bc8f1955...`、GATE CLEAR。
5. `cmd_4274` T-ε1: source `2512bc58...` + tests `3b801ea6...`、4 PASS/SKIP0、軍師LGTM。formal bundleのみoverlap契約バグで未閉鎖。
6. 家老completion高速化: `context_freshness_check.sh`を75.01→25.01秒（-66.7%）、git call約53→27、出力8行不変、61/61 PASS、commit `e467540244ece96cdd6ab2f166ba332610929a90`。
7. DM-Signal統合push: merge `542a534506c54f17bcc3128b7cf25e605e592401`。CI sharding `b4b09e6e4de3d0f12b482a37a5f1631acb4533b7`は単一slow nodeにより方式FAILと確定。

## 未解決の構造穴

1. `review-bundle`がold reportの契約をlive worker taskから解決し、次task配備後に偽BLOCKする。小太郎が`parent_cmd`正本へ修正中。
2. old task final setterがnew task statusを書き換える競合。`cmd_4277`は家老がassignedへ復旧済みだが、再発防止は小太郎scopeで未完。
3. `ninja_monitor`がreport/commit/LGTM済み`cmd_4274`を「37分未配備」と誤判定。completed evidenceを認識する修正が未完。
4. commit helperが他agent commitによるHEAD前進でreceiptをstale判定し、同一task testを再実行して忍者を停止させる。変更保護は必要だが、再実行コストを毎回払う現方式は高速回転違反。未解決として保持する。
5. CI run `31326903152`は38 failed / 1870 passed / 8 xfailed / 6 xpassed、353.62秒。半蔵の根治と再push/GREEN確認が未完。
6. `cmd_4274`とdashboard高速化reportは実装LGTMだが、overlap fix完了後のformal bundle再実行が必要。

## /new後の再開順

1. Recovery完遂後、inbox未読をID単位で処理する。
2. snapshotと全6 paneを一次確認し、この文書との差分だけ更新する。
3. 報告到着順にformat GATE→軍師review→completion GATE→`/cmd-complete`→将軍へ個別掲示する。複数cmdをまとめない。
4. 小太郎のoverlap fix完了後、`cmd_4274`とdashboard高速化のformal bundleを旧report不変・新task不変で再実行する。
5. 才蔵のslow test高速化はgolden不変量を残し、292.92秒を最低10%短縮する。分割でボトルネックを移動させない。
6. 半蔵のCI 38 failures修正後、隔離統合→push→CI GREENを確認する。他5人の作業は止めない。
7. completion報告の必須数値文言は `集計コマンド=...。出力行(生)=...。1件の定義=...。` とする。

## clear-ready二値条件

- [x] active 6 lane、担当、次行動を外部化
- [x] 完了済み成果と未完を分離
- [x] スループットの実ボトルネックを数値保存
- [x] 旧report/new task overlapを未解決の構造穴として保存
- [x] 復帰順を一次確認→到着順処理で固定
- [x] compact state 2正本のpointer更新（2026-08-10 03:32 JST）
- [x] 三層記憶貫通: L1=`knowledge:617fe5aa5c7b4ac1`、L2=`strong_new_game_completion_contract` alias直撃、L3=3/3リンク到達、health GATE `STATUS: PASS`

未完taskの存在は状態保存失敗ではない。復帰後に迷わず同じ因果と数値から再開できることが、強くてニューゲームの完了条件である。

## 03:37到着差分

- `cmd_4276`: 軍師LGTM。4 passed / 0 skipped、oracle fixture再利用、生産コード変更なし。
- 半蔵CI修正: 軍師LGTM。38 failures=9群合計38、115 passed / 0 skipped + harness 147 passed。report format GATEは再実行PASS。
- `cmd_4277`: 軍師LGTM。Jest 11 PASS / SKIP0、build exit 0、FE 3ファイル。
- 上記は実装レビュー完了であり、completion GATE・個別将軍報告は未完として保持する。
