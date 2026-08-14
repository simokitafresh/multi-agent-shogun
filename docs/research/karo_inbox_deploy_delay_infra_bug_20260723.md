# inbox処理・配備遅延RCA（2026-07-23）

## 結論

今回の遅延は忍者の実装速度ではなく、配備control-planeの高い固定費と、分割偵察/実装を正しく表現できない複数guardの不整合が支配した。`logs/deploy_task.log`の02:39:32〜03:05:13を一次集計すると、11試行で845,858ms（14.10分）、うちBLOCK 5試行が275,109ms（32.5%）を消費した。

## 数値

| 区分 | 件数 | wall_ms | 構成比 |
|---|---:|---:|---:|
| 成功 | 6 | 570,749 | 67.5% |
| BLOCK | 5 | 275,109 | 32.5% |
| 合計 | 11 | 845,858 | 100% |

phase累計はtask_mutations 527,559ms（62.4%）、preflight 236,873ms（28.0%）、post_delivery 55,803ms、delivery 16,898ms、post_verify 7,750ms、parse_args 558ms。成功配備だけでも82,802〜138,834msを要した。

## BLOCK 5件の因果

1. 89,652ms: `deploy_task.sh hayate /tmp/*.yaml`という誤引数をpath-like cmd_idとして受理し、既存task/reportを高コスト変換した後に不変reportでBLOCK。CLIが早期型検査しない。
2. 65,685ms + 88,559ms: deploy側は同parentのparallel recon/recon2を許可したが、最終`inbox_write`のduplicate gateは同parentを拒否。高コストtask mutation後に最終段で矛盾判定し、2回ともtransaction rollback。
3. 14,210ms: cmd_4125実装配備を、完了済みAC3偵察reportがあるだけで「completed peer重複」と誤認。task_type/assigned_acsを区別しない。
4. 17,003ms: 重複回避の`cmd_4125_impl` suffixではscout gateが元cmdの偵察2件を探索できず0/2判定。`issued_cmd_id`/scout evidenceを見ない。

BLOCK合計275,109msは、path型検査とguard契約統一を高コストmutation前へ移せば原理上ほぼ除去できる。

## 同時に発見した後段偽陽性

- SG-PRE25が分割AC3監査へparent command全体の実装ファイル変更を要求。担当外ファイルの`files_modified`捏造を誘発する。
- LG048は偽陽性ではなかった。一次再実行で疾風`3×82=246`、才蔵`3×4=12`・`5×8=40`のN×M一致を検出し、意味検算証跡を正当に要求した。家老が`semantic_concepts`注入検査と誤認した判断を撤回し、両忍者へ再計算を指示した。
- report gateがtask直下`commit_contract`欠落時にreport側`required:false`を無視し、no-code偵察へ架空commitを要求。

## 即時行動

- SG-PRE25 assigned_acs限定: 小太郎へ`cmd_karo_hotfix_sgpre25_split_scope_20260723`配備済み。
- report commit_contract fallback: 半蔵commit `b1f409f695a7e2b74c2a006bd3d71e35085d5e1f`、report gate PASS、軍師LGTM。
- cmd_4125本実装: `cmd_4125_impl` + `issued_cmd_id=cmd_4125` + 実在する偵察2報告のevidenceで影丸へ配備済み。
- LG048二件: 当初の偽陽性判断を撤回。疾風・才蔵へ`classification_axis/recount/actual/result`の意味検算を指示し、軍師へ訂正済み。

## 次の構造修正

1. `deploy_task.sh`は`--yaml`なしのpath-like第2引数をparse_argsで即BLOCKし、既存taskへ触れない。
2. duplicate判定をdeploy/inbox_writeで同一関数へ統一し、`task_type + assigned_acs + issued_cmd_id`をidentityに含める。
3. completed peer guardは同一AC所有範囲だけを重複とし、scout→implの自然遷移を許可する。
4. scout gateは`issued_cmd_id`で元cmdのscout reportを参照し、suffix運用でも2/2を保持する。
5. report publication/protected-path列挙を遅延化・索引化し、task mutation固定費を削る。

## 利他の観点

各忍者へ報告YAMLの嘘・空証跡・架空commitを要求して通過させると、次の担当者も同じ時間を失う。今回は報告側を曲げず、検知器・identity・配備順序の欠陥として修正へ変換した。これにより将来の全家老・全忍者の待ち時間と誤修正を減らす。

origin: `[[inbox連打とcmd_4125配備]] -> [[guard間identity不整合と高固定費]] -> [[845858ms中275109msがBLOCK浪費]] -> [[配備control_plane根治]]`

## cmd_4126後段遅延追補（03:01〜03:40）

### 実測

- 忍者の偵察完了報告: 03:01:32。偵察実働は配備02:51:14→報告02:57:32の約6分18秒。
- report gate初回FAIL: 02:58:22。no-code reconへcommitを要求し、02:59:29、03:00:00、03:00:43、03:19:34の計5回BLOCK。
- snapshot identity修繕後PASS: 03:34:31。初回報告からPASSまで約36分59秒。
- 軍師レビューFAIL: 03:36:15。SG-PRE25参照証跡不足とLG048意味検算不足の2件。
- 飛猿修正版report: 03:39:58。SG-PRE25はVED除外、LG048は`6×103=618`がSHA断片・行番号・hash断片の偶然一致と一次再計数し、両検査PASS。
- 全体: 忍者実働約6分18秒に対し、初回報告02:57:32→修正版03:39:58の後段待ち・手戻りは約42分26秒。

### 根因

1. `commit_contract`正本がmutable live taskとreport snapshotで分裂し、no-code reconの`required:false`を無視した。架空commitを作らなかった飛猿の判断は正しい。
2. SG-PRE25のcommand参照は、read-only参照をreport templateへ事前投影せず、レビュー時に`files_modified`欠落として初めて発火した。今回は`verified_existing_dependency`3件の追記でPASSしたが、Level5事前供給不足である。
3. LG048は検出自体が正しく、`6×103=618`は仕様上の直積ではなく異種numeric tokenの偶然一致だった。問題は検出ではなく、semantic_validation雛形が初回reportへ自動注入されずレビュー往復を要した点である。
4. 家老が報告修正を手動再配備した際、`status=assigned`だけを更新し`deployed_at`を更新しなかった。monitorは旧completed reportを今回分と誤認して`done`へ戻し、03:37:39に`report_notification_missing`偽陽性を発火した。03:40に`status=in_progress`+`deployed_at=03:37:33`へ補正後、monitor実走で旧report誤昇格0件・status維持を確認した。
5. `cmd_4125_impl`再検証の617件中1 FAILはDrvFsではなく`tests/unit/test_cmd_publish_preflight.bats`。commit `4f4aae961`で殿裁定に従いlesson-cap呼出しを撤去した一方、旧testが`cmd_shared_preflight`呼出し各1件を要求し続けた。対象test実走は2/3 PASS・1 FAIL、失敗行37、実コード呼出し0件であり、撤去済み契約testの残存が真因。軍師の「DrvFs」帰属は一次reportに基づき訂正依頼済み。

### 利他的な構造修正

- report revision再配備を専用helperへ集約し、`status`・`deployed_at`・`reviewed`・通知を同一原子操作にする。直接field更新を禁止する。
- recon配備時、command参照のうち変更対象外を`verified_existing_dependency`雛形へ自動投影する。
- LG048候補を報告前gateで検出した時点でsemantic_validation雛形とnumeric token出自を自動提示する。
- 飛猿のfailed/手戻りは`infrastructure_contract_mismatch`として修行・品質統計から除外する。
- lesson-cap撤去に追従し、不要になったshared preflight source/lib/testを削除して全unit FAIL0へ戻す。

origin: `[[cmd_4126偵察6分]] -> [[report契約分裂とretry鮮度欠落]] -> [[後段42分26秒]] -> [[report_revision原子化]]`
