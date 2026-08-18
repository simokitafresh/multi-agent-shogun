# 家老 強くてニューゲーム復帰点 — 2026-08-18 06:50 JST

- created_at: 2026-08-18 06:50 JST
- status: active_checkpoint
- owner: karo
- source: 殿指示「今 クリアされても 今より強くてニューゲームができるようにせよ」
- project: infra + dm-signal
- origin: `[[殿指示_今クリアされても強くてニューゲーム_20260818_0647]] -> [[autopush空mapping境界根治]] -> [[reflux再公開依存順序]] -> [[cron6段キー本番検証_20260818_1040]]`

## 復帰直後の結論

現在の主依存鏖は「半蔵fixture根治の報告閉鎖 → 才蔵reflux再公開の再検証 → 対象insightのremote収載確認」である。半蔵の実装commit `3934ebc34b69238f92a16cc08405e43418354c65` は存在し、`test_ninja_monitor_training_auto.bats` へGATE_STALL配列2変数のbounded exclusionを2行追加済み。現taskは`acknowledged`、reportは`pending`である。実装をやり直さず、現taskの`related_lessons=L1309/L658/L1554`とreportの`lessons_useful`を一致させ、20/20 PASS・SKIP 0を再提出させる。

才蔵の`cmd_karo_hotfix_republish_reflux_0445_20260818`はcommit `57b2845a705a8d3ec8f90b90f92e870ee028ce6c` を持つが、修正前fixtureによる20件中1 FAILでreport FAIL/BLOCKED。半蔵cmdのGATE CLEAR後に正式RCし、同一commitを保持したままtask selectorを再実行する。修正後は対象insight `INS-20260817-162824938-39c8` がremoteで1件、`status=resolved`、reason保持、`republished_at`存在を数値確認する。

疾風の`cmd_reflux_backlink_202608180618_hayate`はcommit `01d95b5809e697d9b93260404a5ac53665641ee9`、incoming `0→1`、GATE CLEAR、`cmd-complete COMPLETE`、archive済み。再配備・再レビュー・再完了処理は不要。

## 2026-08-18 06:50 JSTの一次状態

| 対象 | 確定値 |
|---|---|
| 家老inbox | unread 0（2件の後着指示をID個別処理済み） |
| infra HEAD | `01d95b5809e697d9b93260404a5ac53665641ee9` |
| infra upstream/remote main | `ad167c5041cd0c147b46d62f94be9cbfc11dbabb` |
| infra分岐 | upstream...HEAD left/right=`29/126` |
| infra tracked dirty | 37件。他agent/外部writer差分を含む |
| 半蔵fixture根治 | task acknowledged / report pending / AC version `1ccbe19c` / commit `3934ebc34...` |
| 才蔵reflux再公開 | task failed / report FAIL BLOCKED / AC version `63077cb1` / commit `57b2845a7...` |
| 疾風backlink | task idle / incoming 1 / GATE CLEAR / `cmd-complete COMPLETE` |
| 影丸旧CI修正 | `cmd_karo_ci_fix_32045860437_normal` failed。現在の主依存鏖ではない |
| cmd_4352 | commit `43f3a16b` + docs `63d1b3e`。oracle 8504 matched / 9 mismatch / 57 missing、11 PASS、LGTM済み。正式完了は未閉鎖 |
| DM本番 | cmd_4351でcommit `f519002b`がlive/complete。本checkpointではDB現在値を再計測していない |

## 今セッションで環境へ残した強化

1. autopushのinsights mapping root修正で通常mappingのみをLGTMとした後、家老敵対実験で空mappingのrc=1 + ParserErrorを検出。追加修正commit `dd62b0d50`で根治済み。
2. 上記の再発防止を軍師教訓`LG099`として`projects/infra/lessons_gunshi.yaml`へ正式登録。YAML構造変更は通常値に加え`[]/{}/null`の3fixture、各rc期待一致、ParserError 0がLGTM条件となった。
3. dirtyは作業停止理由ではなく、source-only isolated clean snapshot公開経路で越える。差分削除・reset・別type迂回はしない。
4. GATEのrc=75/busyはCLEAR/BLOCKではない。正規自動triggerの終端を待ち、GATE CLEAR後も`completion_tail.log`の`COMPLETE`まで確認する。
5. 報告内の`lessons_useful`は作業者の旧記憶ではなく、現task YAMLの`related_lessons`集合に厳密に合わせる。配備transaction進行中の中間状態を最終状態と誤認しない。

## 後着した本番cron確認任務

2026-08-18 10:40 JSTのRender cron `dm-signal-sync-fof` (`crn-d5e8rabe5dus73fhlkjg`, 01:40 UTC, not_suspended) は`sync_fof() -> recalculate_history_fast(L3_fof) -> _recalculate_fof_history -> PipelineEngine -> select_top_n_deterministic`と進み、本番`f519002b`の6段キーと同一経路。run409以降cron未通過のため、10:40 JST通過後に以下を一次確認する。

- cron windowの`signal_change_log` = 0件。0でなければ全内訳を出す。
- 4表md5 = run409と完全一致。
- 結果を掲示板で将軍へ報告する。
- run408↔409の完全一致は過去証拠であり、10:40後の現在値の代替にしない。

## /new後の最初の一手

1. 家老Recoveryを全手順完走し、startup gateのALERTを処理する。
2. `queue/compact_state/karo.yaml`のpointerとSHA-256を本書に照合する。
3. inboxを読み、未読をID単位で処理する。
4. 半蔵reportの現状を確認する。未提出なら待ち、提出済みなら`related_lessons` 3/3、20/20 PASS、SKIP 0、commit `3934ebc34...`を照合する。
5. 半蔵を軍師LGTM → 家老ACCEPT → GATE CLEAR → `cmd-complete COMPLETE`まで閉鎖する。
6. その後だけ才蔵republishを正式RC再開し、修正済みtask selectorを再実行する。実装commit `57b2845a7...`を捨てない。
7. republishのGATE/push後にremoteの対象insight 1件を検証する。それまで原任務`cmd_reflux_insight_202608180445_hayate`を完了扱いしない。
8. 10:40 JSTを過ぎていればcron確認任務を実行し、本番DB一次値を掲示板で将軍へ報告する。
9. `cmd_4352`の正式完了が未閉鎖であることを忘れず、主依存鏖を崩さない範囲で閉鎖する。

## 禁則

- shared infra mainの37件dirtyをreset/restore/cleanup/一括stageしない。
- dirtyを理由にGATEやpushを遅らせず、isolated clean snapshot経路を使う。
- 半蔵の済commitを再実装しない。報告契約だけを現taskに合わせる。
- 半蔵閉鎖前に才蔵republishを再開しない。同じRED fixtureで再び失敗する。
- 才蔵commit `57b2845a7...`を廃棄・amend・他差分と混合しない。
- 過去のrun408/409一致を10:40後cronの証明に代用しない。
- YAML構造変更を通常値だけでLGTMにしない。`[]/{}/null`の3境界を必ず実行する。
- 疾風backlink任務を二重処理しない。

## 強くてニューゲーム二値条件

- [x] inbox unread 0と現active/failed/completed taskを一次取得した。
- [x] infra HEAD/upstream/remote/divergence/dirty数を固定した。
- [x] 半蔵fixture根治commit・task・report・AC versionを固定した。
- [x] 才蔵republishの済commitとBLOCK原因を固定した。
- [x] 疾風backlinkのGATE CLEAR・COMPLETE・incoming 1を固定した。
- [x] 新規軍師教訓LG099を正式登録した。
- [x] 10:40 JSTのcron後検証を件数・md5・報告先付きで固定した。
- [x] 依存順序・禁止事項・復帰後の最初の一手を固定した。
- [x] 旧checkpointを上書きせず新規作成した。

「今より強い」とは、/new後に半蔵の済実装を捨てず、才蔵の再公開を正しい依存順で閉鎖し、dirtyを消さず公開し、YAMLの空境界と10:40 cronの本番経路を未検証のまま完了扱いしない状態から再開できることである。
