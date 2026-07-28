# 家老 強くてニューゲーム復帰点 — hot-script継続 (2026-07-28 21:01 JST)

## 結論

復帰後は `三層記憶 → queue/inbox/karo.yaml → queue/tasks + queue/reports → tmux capture-pane -S -30` の順で一次実態を再確認する。`queue/karo_snapshot.txt` は時刻付き補助キャッシュであり、それだけで完了・停止・再配備を判断しない。

第一弾12/12、第二弾9/9、第三弾#1/#2、throughput T4は完了。第四弾read-only AC1も4/4 GATE CLEARし、固定窓v3.0 snapshotまで作成済み。実装は殿裁可まで凍結する。並行して、inbox多重送信とRC時の成果破棄を生むインフラバグを3系統修正し、startup escalationの部分重複だけは才蔵がhotfix中である。

## 固定済み成果

| wave | 結果 | 一次証拠・固定値 | 再開時の扱い |
|---|---|---|---|
| 第一弾 | 12/12完了 | 全check終端、個別全量unitの重複実行を廃止 | 再実行しない |
| 第二弾 | 9/9完了 | commit `60a88c241`、unit `2712/2712`、snapshot v2.0 | 第二弾を主成果として保持 |
| 第三弾#1 | 完了 | GATE CLEAR済み | 再実行しない |
| 第三弾#2 | no-change完了 | CLEAR cohort N=456、min=77s、p50=591.5s、p95=6338.2s、max=56219s。`karo_accept`/`gunshi_lgtm`各N=20はwall_ms=0で実処理時間を観測不能 | 意味を読み替えずno-changeを維持 |
| throughput T4 | no-change完了 | gate_metrics 856行・505 cmd。estimated_minutes欠損856/856、archive欠損8145/8159、RC欠損480/505。相関計算不能 | 見積型分離を実装しない |
| 第四弾設計 | v1.3 + v3.0 snapshot | 設計commit `a1bbc3c11`、gist revision `9700daa0`。v3.0=`docs/research/hot-script-speedup-round4-v3-snapshot-20260728.md`、固定窓1,234行/hash `ce8fa311...4237` | 将軍が設計書v2.0+gistへ反映後も、殿裁可まで実装凍結 |
| inbox durable重複 | 修正完了 | same-cmd redeployのtask_assigned重複をcommit `a7c27dd41`で抑止 | 同一cmd retryで永続messageを増やさない |
| watcher/direct多重nudge + RC成果破棄 | 修正完了 | commit `1be8bee8f`。active watcher時はdirect retryを停止し、RC scope別に有効な既存計測を再利用。affected選択test 944/944、SKIP0、full_scope=0 | 「task指示の失効」と「成果全破棄」を混同しない |
| no-code COMMIT MISSING誤警告 | 修正完了 | commit `b40e11a3c`。`valid_commit_identity()`正本を再利用、選択test 10/10、SKIP0 | no-code文字列だけの無条件許可は禁止維持 |

第三弾#2の `cmd-complete` は20:23完了。throughput T4は20:25 GATE CLEAR、20:26 `cmd-complete` 完了。

## 現在地（21:01一次確認）

| lane | ninja | task正本 | scope | 出口 |
|---|---|---|---|---|
| 第四弾AC1 precheck | hayate | GATE CLEAR + cmd-complete済み | `scripts/gates/gate_gunshi_report_precheck.sh` | body_restが子累積58.1% |
| 第四弾AC1 inbox | hanzo | GATE CLEAR + cmd-complete済み | `scripts/inbox_write.sh` | delivery_verify BLOCK 393/443 |
| 第四弾AC1 publish | kotaro | GATE CLEAR + cmd-complete済み | `scripts/report_field_set.sh` のpublish_totalのみ | N=2,420、欠損0、母集団hash固定 |
| 第四弾AC1 cmd_save | tobisaru | GATE CLEAR + cmd-complete済み | `scripts/cmd_save.sh` | quality_gateが最大子区分 |
| startup escalation重複hotfix | saizo | GATE CLEAR + cmd-complete済み | commit `003f3c411`、選択test 7/7、SKIP0 | 本文完全一致ではなく未解消警告キー単位で重複抑止 |

4つのAC1は別ファイルのまま全て閉幕した。途中のunit全量実行は0、コード変更0、commit_hash識別子計装0、母集団縮小0。v3.0でも上位3標的は不変、`checks_main`だけ4位へ上昇し、4 scripts / 5 bulletsのscope増減はない。

## 第四弾の判断境界

1. AC1は観測だけ。対象file SHA256、line count、git HEAD、cutoffを最初に固定する。
2. 設計前提が一次コードと不一致なら、そのlaneは変更0で即報告する。
3. 全母集団のN・欠損N・p50/p95/max・原因分類を出す。代表点抽出は禁止。
4. 4報告を統合したv3.0 snapshotは作成済み。
5. v3.0結果は掲示板 `blt_20260728_205801_1a1b32` で将軍へ報告済み。将軍による設計書v2.0/gist反映を待つ。
6. code diffが1件でもあればAC1違反としてRCする。

## 復帰直後の順序保証

1. `queue/inbox/karo.yaml` の `read:false` を読み、各IDを個別に処理する。
2. startup escalation重複hotfix commit `003f3c411` とGATE CLEAR証跡を確認する。再配備しない。
3. `tmux capture-pane -S -30` 以上で実態を確認し、確認プロンプト中なら送信しない。
4. 将軍が第四弾設計書v2.0とgistへv3.0を反映したか掲示板・git・gist hashで確認する。
5. 殿裁可までは第四弾のコード実装とcommit_hash識別子計装を開始しない。
6. RC修正commit `1be8bee8f` とsame-cmd dedupe `a7c27dd41` がHEAD履歴にあることを確認する。
7. このファイルの時刻・task status・次の出口を更新し、三層記憶へ貫通させる。

## 復帰直後の二値チェック

- [ ] inbox未読をID単位で処理した
- [ ] startup escalation重複hotfix commit `003f3c411` とGATE CLEARを確認した
- [ ] startup escalationの同一キー重複が2→1、新規キー送信が1→1か確認した
- [ ] 第四弾v3.0 snapshotの窓1,234行/hashを再現した
- [ ] 第四弾実装・commit_hash計装が未開始か確認した
- [ ] 設計書v2.0とgist反映を確認した
- [ ] RC成果再利用commit `1be8bee8f`、same-cmd dedupe `a7c27dd41`、no-code修正 `b40e11a3c` の存在を確認した
- [ ] CLEAR後の完了処理を`/cmd-complete`で実行した
- [ ] 更新知見を三層記憶へ書き戻した

依存鎖: `[[hot_script第一弾_12_of_12]] -> [[hot_script第二弾_9_of_9]] -> [[第三弾_no_change計測]] -> [[第四弾_readonly_AC1_4lane]] -> [[第四弾_v3_snapshot]]`

origin: `[[殿指示_20260728_強くてニューゲーム]] -> [[全量テスト重複の再発防止]] -> [[karo_clear_recovery_checkpoint]]`
