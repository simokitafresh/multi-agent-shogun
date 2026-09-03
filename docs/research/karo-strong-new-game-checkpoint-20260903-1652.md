# 家老 強くてニューゲーム復帰点 — 2026-09-03 16:52 JST

## 0. 正本宣言

- role: `karo`
- status: `active_work_owned_checkpointed`
- created_at: `2026-09-03T16:52:00+09:00`
- source: 殿指示 2026-09-03 16:48「いまクリアされても今より強くてニューゲームできるようにせよ」
- predecessor: `docs/research/karo-strong-new-game-checkpoint-20260831-1752.md`（歴史記録。変更禁止）
- origin: `[[殿指示_強くてニューゲーム_20260903_1648]] -> [[publisher単一化U10_U11]] -> [[XDK_media_AC2]] -> [[家老判断2件の教訓統合]] -> [[karo_checkpoint_20260903_1652]]`
- 復帰後は保存値を未来の事実として使わない。inbox→task/report→pane→fetch後origin/main→publisher eventsの順に一次再測定する。

## 1. 復帰直後の絶対順序

1. AGENTS.mdの家老Recoveryを全手順完走する。
2. 本ファイルのSHA-256をcommit/blobまたは保存artifactと照合する。
3. `bash scripts/inbox_read.sh karo` で未読を読み、各IDを個別処理する。
4. `queue/karo_snapshot.txt` と全paneを突合する。snapshotだけで判断しない。
5. `git fetch -q origin` 後、`git rev-list --left-right --count origin/main...main` と `git branch -r --contains <source>` を確認する。local `main` のancestor判定をremote到達証拠に使わない。
6. `cmd_karo_hotfix_u11_unknown_reason_branch_202609031635` のGATE終端を確認する。source `78ce1d7ff0a8bdcadba13cc4987801111b9c3e5a`、軍師LGTM・家老ACCEPT済み、16:50時点はpublication ancestry待ち。
7. 順序配備の第2件 `deploy_task --yaml` task_worktree既定化（root writer #9）を影丸または最初のidle忍者へ配備する。第1件U11のGATE終端前に並列開始しない。
8. 第2件完了後、第3件publisher rc31の`origin/main` ancestor→`already_published`分岐を配備する。
9. 完了報告在庫（hayate/hanzo/tobisaru）と才蔵`cmd_4472`をcurrent-generation review→ACCEPT→GATE→archiveまで閉じる。
10. `09-04 09:23 JST`以降にsingle-publisher after_snapshotを実測する。close_checkの旧restarts=7は入替前を含むため、入替後windowのrestarts=0を別計測する。

## 2. 16:50時点の一次状態

- Karo inbox unread: `0`（16:51到着のgate通知もID単位で処理済み）。
- MAS HEAD / origin/main: `484512e01dcaed29806604b819f801f31008a289` / 同一。
- MAS relation `origin/main...main`: `0 0`。
- dirty: tracked `9`、untracked `8`（他者・ledger生成物を含む。広域stash/reset/clean禁止）。
- pending decisions: `2`。
  - `PD-141`: workaround category `infra::general` 4件の構造対策。
  - `PD-142`: review_approval系testの`SHOGUN_STATE_DIR`隔離欠落。
- publisher pid file: `1745359`、開始 `2026-09-03 16:17:40 JST`。
- publisher raw process: 親`1745359` + pipeline子`1745368/1745369`。daemon identityは親1本として扱う。
- watchdog log: 16:17〜16:26は毎分 `PUBLISHER-GENERATIONS: count=1 state=current`。16:15のreload 2件以後は継続reloadなし。
- close_check 16:34（将軍実測）: 条件5 PASS、root 0/0、dirty 8、trailer 196/217、欠落21、restarts 7（入替前込み）。

## 3. 稼働中・未終端task

1. `cmd_karo_hotfix_u11_unknown_reason_branch_202609031635_normal` — 小太郎、実装完了。
   - source: `78ce1d7ff0a8bdcadba13cc4987801111b9c3e5a`
   - report: `queue/reports/kotaro_report_cmd_karo_hotfix_u11_unknown_reason_branch_202609031635.yaml`
   - result: events現行形式39件中unknown 38 / not_descendant 1。原因は`update-ref` CAS競合がreason未設定で最終fallbackへ落ちたこと。
   - fix: `head_moved` / `postsync_verify_mismatch`を明示し、driver 3-wayでCASをworktree/index更新前へ移動。
   - tests: `14/14 PASS`, FAIL0, SKIP0。軍師LGTM・家老ACCEPT済み。GATE publication待ち。
2. `cmd_4472_ac2_xdk_media_revision_202609031607_normal` — 影丸、GATE CLEAR・idle。
   - source: `9ab88228d9d3f9e88381bb6a4e1dca7479d78456`
   - XDK OAuth2自動refresh、`draft/gate/approve/post`、`--media <png>`、201/401、creds absent exit2。
   - tests: `18/18 PASS`, SKIP0。
   - OAuth doc handoffはRCで補完済み。`context_update_candidates.content`にcallback/scope/token保存更新/secret値0を記録。
3. `cmd_4473_normal` — 疾風、taskはin_progressだがreport completed。
   - Agent Readiness AC1/AC2実装は完了。current-generation GATE終端を再確認する。
4. `cmd_karo_hotfix_watchdog_stopflag_delivery_202609031532_normal` — 半蔵、report completedだがtask in_progress。
   - source `aba10ce9...`、stop flag配送・legacy supervisor収束・14/14 PASS。
   - 本番は新publisher親1本へ収束済み。GATE/archive終端を確認する。
5. `cmd_4472_normal` — 才蔵、in_progress。
   - AC1台帳/gate側。旧実装commit `b281c33e...`、split peer manifest上書き構造で報告が止まった履歴あり。
   - AC2 XDK/mediaは独立revisionで完了したため、才蔵taskへ混入させない。
6. `cmd_karo_hotfix_inbox_unread_source_202609031435_normal` — 飛猿、report completedだがtask in_progress。
   - source `7b2f666e...`、task test 1405/1405、対象60/60、SKIP0。GATE/archive終端を確認する。

## 4. 順序配備待ち

### 第2件: root writer #9

- 目的: `deploy_task.sh --yaml` hotfix/impl taskも既定でtask worktreeを生成し、忍者がshared rootで直commitできない構造にする。
- 発端: 小太郎watchdog parent_pid hotfix `3516dfc` がtask worktreeなしでroot HEADへ直commitし、origin/mainとahead1/behind1になった。
- 必須AC:
  - `--yaml` taskの`task_worktree_required=true`・worktree path・marker・edit wrapperを自動注入。
  - source commitはtask worktreeにのみ作られ、shared root HEAD不変。
  - normal/hotfix/impl、既存worktreeあり、target absent、delivery rollbackをfixture化。
  - root writer数の変更前→後を数値化、FAIL0/SKIP0。
- 主対象: `scripts/deploy_task.sh`, deploy task contract tests。

### 第3件: publisher rc31 already_published

- 目的: request artifact欠落時でも、report/source commitがfetch後`origin/main`のancestorなら既存`already_published` eventへ寄せ、家老通知を出さない。
- 判定境界: local `main` ancestorは禁止。必ずfetch後`origin/main`。
- fixture:
  - origin ancestor + artifact missing → already_published、通知0。
  - local mainのみancestor / origin非ancestor → rc31維持、通知1。
  - commit不明・fetch失敗 → fail-close。
- 主対象: `scripts/publisher.sh`, `tests/unit/test_publisher.bats`。

## 5. 本日確立した因果

- watchdog reload eventだけではdaemonへ届かない → 永続stateのatomic stop flag → request境界exit → supervisor再起動。
- 旧daemon3本のうちflag非対応generationが残る → owner PID/start identity再確認後のsupervisor収束 → 親1本。
- `pgrep publisher.sh`は2段pipe子も拾う → root PID filter → raw3 / daemon1。
- U11 `reason=unknown`はdriver有無ではなく`update-ref` CAS競合の未分類 → `head_moved`明示 + 更新前CAS。
- local `main`にsourceがある ≠ remote到達 → fetch後`origin/main` ancestryが正本。
- 軍師LGTM + binary yes ≠ artifact実在 → XDK OAuth handoff本文欠落を家老RCで捕捉。
- 忍者receipt済み途中レビューで家老が再試験 → report fingerprint churn。以後wave最終checkpoint以外は再走禁止。

## 6. 今回環境へ埋め込んだ家老教訓

- `LK009`へ統合: remote到達はfetch後`origin/main` ancestry + remote containsで二重確認。local mainは不可。
- `LK-A06`へ統合: current-generation Ninja receiptがFAIL0/SKIP0なら家老途中再試験禁止。家老実走はwave最終checkpointのみ。
- 既存35件上限を守り、新規教訓を増やさず同根クラスタへ圧縮した。

## 7. 禁則

- 家老が通常実装を抱えない。実装は忍者へ配備する。
- polling禁止。inbox/eventで再開する。
- 運用YAMLへ`yaml.dump`/`yaml.safe_dump`禁止。field helperを使う。
- report YAML直接編集禁止。`report_field_set.sh`を使う。
- lessons YAML直接編集禁止。`lesson_write*.sh`を使う。
- `git reset --hard`, `git checkout -- .`, `git restore .`, `git clean -f`, manual kill, force push禁止。
- shared rootでcherry-pick/rebase/revert/mergeをしない。C2aは`publisher_c2a_merge.sh`、root更新は安全ff経路。
- local `main`をremote到達証拠にしない。
- Ninja test receiptを家老が途中再走で置換しない。
- `read:true`やreport completedをGATE CLEARとみなさない。
- 過去checkpointのcreated_at/hashを変更しない。新版は新規ファイル。

## 8. 二値検証コマンド

```bash
bash scripts/inbox_read.sh karo
git fetch -q origin
git rev-list --left-right --count origin/main...main
git branch -r --contains <source_sha>
sed -n '1,20p' queue/karo_snapshot.txt
tail -n 1 ~/.local/share/multi-agent-shogun/publish_queue/events.jsonl
tail -n 60 logs/daemon_watchdog.log
bash scripts/gates/gate_report_format.sh <report>
```

## 9. 完了条件

- [x] role・禁則・全未終端task・順序配備3件を記録。
- [x] inbox・task/report・pane・Git・publisher・pending decisionを一次採取。
- [x] 家老判断ミス2件を既存教訓へ統合し、Recovery自動注入対象にした。
- [x] DM-Signal project/contextを再読し、現作業がinfraであることを確認。
- [ ] 第2件worktree既定化と第3件rc31 ancestor分岐を順次GATE CLEAR。
- [ ] U11 source着地後、本番eventsで`reason=unknown`増分0を確認。
- [ ] 09-04 09:23以降のafter_snapshotで入替後restarts=0を確認。
- [ ] 本ファイルのSHA-256・三層記憶receipt・掲示板pointerを外部証跡として固定する。
