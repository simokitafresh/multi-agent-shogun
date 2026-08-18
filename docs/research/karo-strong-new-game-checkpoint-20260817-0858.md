# 家老 強くてニューゲーム復帰点 — 2026-08-17 08:58 JST

- created_at: 2026-08-17 08:58 JST
- status: completed_gate_clear
- owner: karo
- source: 殿指示「いまクリアされても今より強くてニューゲームできるようにせよ」
- project: infra（DM本番復帰点は前checkpointを継承）
- origin: `[[殿指示_強くてニューゲーム_20260817_0852]] -> [[infra_reflux_wave_20260817]] -> [[ac_version改竄検知_rootfix]] -> [[strong_new_game_completion_contract]]`

## 復帰直後の結論

飛猿の `cmd_reflux_insight_202608170804_tobisaru_exact` はSG7 LGTM→家老ACCEPT→GATE CLEAR→`cmd-complete` COMPLETEまで完了した。対象insight resolve commitは `4727e045597a8be817dc8a48c7698f232f314d15`、taskはidle、報告はarchive済み互換symlink、家老inboxは未読0件。remote/mainはまだ`4c1efa6154...`で、共有`context/semantic-map.md`の外部dirty重複によりpushは正しくSKIPされた。差分を消してpushしてはならない。

## 2026-08-17 08:58 JSTの一次状態

| 対象 | 確定値 |
|---|---|
| role | karo（tmux `@agent_id`実測） |
| 家老inbox | unread 0、`queue/inbox/karo.yaml`は`messages: []` |
| 稼働lane | tobisaru 1名、`cmd_reflux_insight_202608170804_tobisaru_exact` |
| 飛猿task | `completed`、AC version `0d791684` |
| 飛猿実装 | commit `4727e045597a8be817dc8a48c7698f232f314d15`、`queue/insights.yaml`のみ |
| 飛猿report | `queue/reports/tobisaru_report_cmd_reflux_insight_202608170804_tobisaru.yaml`、status `completed`、verdict `PASS`、fingerprint `5187940de87cbc2a697c0fd73e288d00543463a4900ea1ba123f577b363f230c` |
| 完了処理 | SG7 `APPROVE`、家老`ACCEPT`、GATE `CLEAR` 2026-08-17 09:10:30、`cmd-complete` `COMPLETE` 09:12、task `idle`、報告archive済み |
| 飛猿後着差分 | commit後に外部writerが3 insightを追加。`INS-20260817-085222042-3fa6`、`INS-20260817-085303334-237d`、`INS-20260817-085642407-8e62`。飛猿成果へ混入せず、未commitのまま保持 |
| 次reflux dispatch | `cmd_reflux_insight_202608170900_hayate`と`cmd_reflux_insight_202608170903_kagemaru`は同じdirty target検知で配備前BLOCK。両taskとも旧taskの`idle`のまま。targetをcleanにするため後着3 IDを消してはならない |
| idle | hayate、kagemaru |
| 旧failed | hanzo、saizo、kotaro。今回のBLOCKではなく、勝手に再配備・閉鎖しない |
| infra remote/main | `4c1efa6154b30d9549a55eeaa806457297ad0bde`（`git ls-remote`実測） |
| 共有infra HEAD | `02e7f16e8445dabcf3caac14922f61ca33ea5a05`、originに対してleft/right=`17/33`。remote正本と分岐 |

後着差分の因果: `[[殿指示_強くてニューゲーム_20260817_0852]] -> [[後着差分3_ID保持]] -> [[tobisaru_review_pending]] -> [[strong_new_game_completion_contract]]`

配備BLOCKの因果: `[[後着差分3_ID保持]] -> [[reflux_dirty_dispatch_blocked]] -> [[差分削除禁止]] -> [[strong_new_game_completion_contract]]`

## 今セッションで完了した強化

1. `cmd_karo_hotfix_ac_version_tamper_detection_202608170704`を根治。`cmd_complete_gate.sh`がtaskの現在ACをdeploy時と同じ正規化で再計算し、task YAMLの後付け・書換えをBLOCKする。正常1/1 PASS、改竄2/2 BLOCK、false positive 0。全対象suite 190/190 PASS、SKIP 0。source `189f5fbb`、remote integration `dc55ebb3`。
2. `cmd_reflux_insight_202608170738_hayate`をGATE CLEAR。対象INS `INS-20260817-023016651-11a5`をresolved化し、在庫`7/7/0/14 -> 6/7/0/13`。remote integration `868f408169bbf1988a125fefa5ab448239a223e2`。
3. `cmd_reflux_backlink_202608170750_kagemaru`をGATE CLEAR。`docs/research/karo_inbox_deploy_delay_infra_bug_20260723.md` incoming `0 -> 2`、在庫`6/7/0/13 -> 6/6/0/12`、82/82 PASS、SKIP 0。remote integration `4c1efa6154b30d9549a55eeaa806457297ad0bde`。
4. GATE自動triggerのrc/busyはCLEAR/BLOCKではないことを再確認。trigger logが`busy; terminal ... not established`なら保持者不在を確認後、正規`cmd_complete_gate.sh <cmd>`を実行する。busyをCLEAR扱いしない。
5. `cmd-complete`の非同期tailはdashboard・archive・ntfy・inbox_archiveの`COMPLETE`まで確認した。起動コマンドの即時成功だけで完了宣言しない。

## remote統合で得た再開知識

- 共有mainはremote/mainと分岐している。共有mainからpushしない。
- 成果commitの親にremote未収載の運用YAML生成commitがある場合、盲目的cherry-pickをしない。remote基点の隔離worktreeへ、元のID・ts・resolved_atを保持した完全entryを反映する。
- `context/semantic-map.md`は生成器が同時刻の外部入力でscope外差分を生み得る。review済みSSOT差分と生成mapの対象行だけを公開commitへ固定し、post-commit生成差分は別状態として保持する。
- pre-push GA-PUSH1が同一pathの未commit差分をBLOCKした場合、escape hatchを使わない。確定commitを指すclean公開専用worktreeからpushする。
- 今回作った隔離worktreeには未確定生成差分が残るものがある。外部差分として保持し、cleanup・reset・broad restoreしない。
- 飛猿commit後の`queue/insights.yaml`追加3件はstable IDが新規であり、`post_commit_allowed_fields`の単純なカウンタ更新ではない。他者hunkとして保持し、飛猿commitの再作成・amend・全file stageで混ぜない。

## DM本番復帰点の継承

DM本番の最新確定復帰点は `docs/research/karo-strong-new-game-checkpoint-20260817-0005.md`。Render Live/origin main `131e5dbb`、backend baseline `3e28b617`、PITR新DB、run398 completed、run396との4業務hash exactという確定値を継承する。本セッションでは本番DBを再測定していないため、将来値として流用せず、本番確認が必要な時だけ`db-check` readonly経路で再測定する。

## /new後の最初の一手

1. 家老Recoveryを全手順完走し、startup gateのALERTを処理する。
2. `queue/compact_state/karo.yaml`のpointer/hashを本書と照合する。
3. inboxを読み、未読をメッセージID単位で処理する。
4. `queue/tasks/tobisaru.yaml`がidle、報告がarchive symlink、GATE CLEAR、completion checkpoint COMPLETEであることを再取得する。
5. `git diff -- queue/insights.yaml`で上記3 IDだけが後着差分として残ることを確認する。
6. 飛猿cmdは完了済み。再配備・重複review依頼・重複cmd-completeをしない。
7. hayateへの09:00 refluxとkagemaruへの09:03 refluxは未配備である。後着差分を安全に正本化する方式が確定するまで手動配備しない。
8. 完了後はGATE CLEAR→`cmd-complete` tail COMPLETE→remote integration→`git ls-remote`の順で数値確認する。

## 禁則

- 飛猿taskを重複配備しない。
- draft review APPROVEをSG7完了レビューLGTMと誤認しない。
- GATE rc=75/busyをCLEARと誤認しない。
- shared mainやdirty隔離worktreeをreset・cleanupしない。
- semantic-mapの後着差分を捨ててscopeを整えるふりをしない。
- queue/insights.yamlの後着3 IDを飛猿成果へ混入・破棄しない。
- `clean_target_then_retry`を「差分を消せ」と解釈しない。dirty解消は正本化・世代統合で行い、履歴削除で行わない。
- DM本番run398値を再測定なしに「現在値」と呼ばない。

## clear-ready二値条件

- [x] 現在の唯一のactive task、task status、commit、report statusを一次確認した。
- [x] inbox unread 0を確認した。
- [x] infra remote/main SHAを`git ls-remote`で確認した。
- [x] 完了済み3成果と検証数値を固定した。
- [x] shared HEADとremoteの分岐を固定した。
- [x] dirty/生成差分の保持条件を固定した。
- [x] DM本番は旧復帰正本への継承として分離した。
- [x] /new後の最初の一手と二重配備禁止を固定した。
- [x] created_atを新規時刻で保持し、旧checkpointを上書きしていない。
- [x] Obsidian因果originを記録した。

「今より強い」とは、/new後に飛猿を二重配備せず、busyをCLEAR扱いせず、共有分岐や生成差分を消さず、確定remote成果と進行中laneを同時に守って次の一手へ進める状態である。
