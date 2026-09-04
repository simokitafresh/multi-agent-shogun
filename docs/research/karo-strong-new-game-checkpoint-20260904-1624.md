# 家老 強くてニューゲーム復帰点 — 2026-09-04 16:24 JST

## 0. 正本宣言

- role: `karo`
- status: `ready_for_new_game_no_active_tasks`
- created_at: `2026-09-04T16:24:00+09:00`
- source: 殿指示 2026-09-04 16:24「いまクリアされても今より強くてニューゲームできるようにせよ」
- predecessor: `docs/research/karo-strong-new-game-checkpoint-20260903-1703.md`（歴史記録。変更禁止）
- origin: `[[殿指示_強くてニューゲーム_20260904_1624]] -> [[CLEARだけでは未完了]] -> [[五重終端条件]] -> [[GA571_GA573連鎖根治]] -> [[karo_checkpoint_20260904_1624]]`
- 復帰後は保存値を未来の事実として使わない。`inbox_read → task YAML → capture-pane → fetch後origin/main → gate/archive receipt` の順に一次再測定する。

## 1. 復帰直後の絶対順序

1. AGENTS.mdの家老Recoveryを全手順完走する。
2. 本ファイルのSHA-256を`queue/compact_state_karo.yaml.target_sha256`と照合する。
3. `bash scripts/inbox_read.sh karo`で未読を読み、各IDを個別処理する。
4. 全忍者についてtask YAML・pane・`@current_task`を突合する。snapshotだけで判断しない。
5. 完了判定は五重条件とする: `gate_worker.clear.json`、`archive.done`、task `idle`、task worktree `cleaned`、inbox未読0。
6. `git fetch -q origin`後に`git rev-list --left-right --count origin/main...main`を確認する。worker SHAが非祖先でも、source publication receiptと対象pathの現物一致を確認する。
7. pending decisions `PD-038(shelved) / PD-141(pending) / PD-142(pending)`を再読する。裁定を推測しない。
8. dirty差分は他者・ledger・X運用の所有物。広域stash/reset/cleanをしない。

## 2. 16:24時点の一次状態

- Karo inbox unread: `0`。
- 忍者6名: hayate/kagemaru/hanzo/saizo/kotaro/tobisaru全員`idle`、現task IDなし。
- 直近5 cmdは全て`gate_worker.clear.json + archive.done`成立:
  - `cmd_karo_ci_fix_33807468742_hot_reload_third`
  - `cmd_karo_ci_fix_33833338308_review_approval_rc_contract`
  - `cmd_karo_hotfix_t3s64_test_notification_isolation`
  - `cmd_karo_hotfix_ga571_prepush_x_post_contract_202609041452`
  - `cmd_karo_hotfix_ga573_startup_contamination_contract_202609041533`
- dangling source `3c7f94f85` / `aba10ce9a` はpublish lock＋isolated cloneのancestry mergeで`origin/main`祖先化済み。
- T3-S-64漏出3件はproduction inboxから0件へ除去済み。原記録を`archive/inbox/karo_20260904.yaml`に保持し、同じ3 IDを`logs/inbox_info_digest.jsonl`へ冪等移管済み。
- `gate_shogun_startup.sh`: `fixture由来 0件 / IDs=none`。
- pending decisions: active 3件（PD-038 shelved、PD-141/PD-142 pending）。

## 3. 本セッションで閉じた因果

1. hot-reload watcherはmtime/sizeだけでは同サイズ・同mtime更新を見逃す → content fingerprintをidentityへ追加 → adversarial 20反復、post 377/377 PASS、SKIP0。
2. review_approval CI 19件FAIL → `89c273f4f`のlegacy RC互換回帰を単独revertで確定 → production fail-closeを弱めず870/870 PASS、SKIP0。
3. 将軍追補後にreport snapshot ACが旧値 → SG-PRE10が正当差異をBLOCK → task現行AC=report読込ACの場合だけWARNへ降格(`bd60ace73`)。
4. review_logが`timestamp`のみ持つ世代を`reviewed_at`だけで検索 → mark_readが永久BLOCK → reviewed_at優先・欠落時timestamp fallback(`4c058a3d0`)。
5. test実行中のpublisher失敗通知がproduction inboxへ3件漏出 → test mailbox rootを分離しstartup汚染detector追加 → 対象183件PASS、SKIP0。
6. X投稿transportをXDKからurllibへ変更したが旧fixtureを残した → pre-pushで9/38 FAIL(GA-571/572) → urllib境界fixtureへ更新、99/99 PASS、SKIP0(`3b5309eb5`)。
7. 汚染detectorの偽陽性33件を本文grep全廃で直した結果、T3-S-64型真陽性も消失 → `task=<id>`形式だけを拾う第3経路 → 20/20 PASS、FP/FN=0/0(`8b79e935a`)。
8. CLEAR済みでもtask/archive/worktreeが残存 → `/cmd-complete`で疾風・影丸を終端化。影丸はsource-only receipt欠落をcanonical writerで復旧しarchive/worktree cleanup完了。

## 4. 今回得た強い完了契約

- `CLEAR`は品質判定であり、完了全体ではない。
- 完了は `CLEAR ∧ archive ∧ task idle ∧ worktree cleaned ∧ inbox unread 0` の五重条件でのみ宣言する。
- source SHAがremote祖先でも、task worktree markerの`published_commit`またはgeneration-bound source receiptが欠ければarchiveは正しくBLOCKする。
- publisherの一時失敗通知だけで失敗確定しない。後続receipt・remote tip・ancestryを確認する。
- hook alertは件数ごとに新cmdを増殖させず、hook SHA・失敗test・根因が同じなら既存taskへ統合する。
- 偽陽性修正は「拾うべき実incident 1件」と「拾ってはいけない正常例 1件」を同一変更で必ず再検証する。
- 完成済reportを家老が補正する場合、正式RCでrevision_requestedへ戻してからreport_field_setを使う。完成報告の直接変更は禁止。

## 5. 保存すべき現行dirty

- tracked: `context/infrastructure.md`, `projects/dm-signal/lessons.yaml`, `projects/infra/lessons.yaml`, `queue/session_alerts_shogun.txt`, `queue/shogun_todo_map_timestamps.tsv`, X live OOS/growth関連。
- untracked: `.tmp-tobisaru-receipt-*`, archive chronicle、既存research文書、`queue/archive/`。
- 上記は本checkpointのcleanup対象ではない。所有権不明のため削除・stash・resetしない。

## 6. 禁則

- 運用YAMLへ`yaml.dump`/`yaml.safe_dump`禁止。`yaml_field_set.sh`を使う。
- report YAML直接編集禁止。`report_field_set.sh`を使う。
- lessons YAML直接編集禁止。`lesson_write*.sh`を使う。
- inbox直接編集・一括既読化禁止。`inbox_read.sh`→各IDの`inbox_mark_read.sh`。
- shared rootでcherry-pick/rebase/revert/mergeしない。publisher lock＋isolated cloneを使う。
- local mainをremote到達証拠にしない。fetch後origin/mainとreceiptを使う。
- `git reset --hard`, `git checkout -- .`, `git restore .`, `git clean -f`, force push、manual kill禁止。
- 過去checkpointのcreated_at/hashを変更しない。新版は新規ファイル。

## 7. 二値検証コマンド

```bash
bash scripts/inbox_read.sh karo
git fetch -q origin
git rev-list --left-right --count origin/main...main
python3 -c 'import yaml; print([(n,(yaml.safe_load(open(f"queue/tasks/{n}.yaml")) or {}).get("task",{}).get("status")) for n in "hayate kagemaru hanzo saizo kotaro tobisaru".split()])'
test -f queue/gates/<cmd_id>/gate_worker.clear.json
test -f queue/gates/<cmd_id>/archive.done
rg --no-ignore 'publisher request failed task=cmd_(rc_report_success_normal|rc_revoke_f1_normal|karo_rc_revoke_generation_normal)' queue/inbox
```

## 8. 完了条件

- [x] 全忍者idle・現taskなし・inbox未読0を一次確認。
- [x] 直近5 cmdのCLEAR/archiveを確認。
- [x] dangling 2 commitのremote ancestryを確認。
- [x] T3-S-64 production汚染0・digest 3件を確認。
- [x] 今回の因果・五重終端条件・禁則を新規checkpointへ固定。
- [x] 本ファイルSHAをcompact_stateへ反映し、三層記憶・remote publicationを確認する。
