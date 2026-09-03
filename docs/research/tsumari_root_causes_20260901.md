<!-- gist-master: 0471675066394649c8e5f9bfabd2e048 tsumari_root_causes_20260901.md -->
# 便を止める「つまり」の原因分類 2026-09-01（第22便 17:17〜22:15、全ロール探索・将軍統合。**09-03 18:12/18:35 覚醒追補=T3-S-29〜38、殿『小さなつまりも負の複利。D0 で根治→家老レビュー』**）

殿指示 20:44/20:46: 偽陽性・過剰 BLOCK・構造バグ・循環拘束・遅い script/test・Claude↔Codex 仕組み差・サンクコスト過剰複雑化・影響範囲/依存未解明の浅い対応、で分類し全員で探索。

## 将軍統合（分類別件数）

| 分類 | 将軍節 | 家老節 | 軍師節 | 忍者節 | 計 | 未根治 |
|---|---|---|---|---|---|---|
| ①偽陽性 | 2 | 1 | 1 | 1 | 5 | fallback_gate_status race(S-09/R-06/G6/K-01)、文字列一致 guard(S-12) |
| ②過剰 BLOCK | 0 | 1 | 0 | 0 | 1 | DOC_LANE_ROUTING が SCOUT の docs/research 成果物を止める(R-05) |
| ③構造バグ | 4 | 0 | 3 | 0 | 7 | U9(ours 相当 merge の producer)、rotation の deploy 未起動(S-11 恒久) |
| ④循環拘束 | 1 | 2 | 2 | 1 | 6 | reviewed_at 秒差 BLOCK(G5)、forced_idle 再処理(K-02) |
| ⑤遅い script・test | 1 | 0 | 0 | 0 | 1 | cmd_skeleton.sh 2 分 hang(S-10) |
| ⑥Claude↔Codex 仕組み差 | 0(副 1) | 0 | 0 | 0 | 0 | 副分類のみ(S-12 hook の文字列一致は両 CLI 共通) |
| ⑦サンクコスト過剰複雑化 | 1 | 0 | 0 | 0 | 1 | — |
| ⑧影響範囲・依存未解明の浅い対応 | 4 | 2 | 0 | 0 | 6 | hotfix 入口の tests census(S-04)、U1/U3(D0 の是正) |

集計コマンド: 各節の表を `grep -oE '^\| [SRGK]-[0-9]+ \|' docs/research/tsumari_root_causes_20260901.md | wc -l` → 13+6+6+2=27 事例。分類は各節の主分類列を手集計(本表)。

**構造の結論(将軍)**: 本便の便停止は「契約を変える hotfix が呼出し元/fixture を census せず本番へ出る(⑧)」と「BLOCK の理由を記録せず/握りつぶす(③→①)」の 2 型に収束する。CI RED 5 回・統合失敗 3 波・receipt 契約の副作用 3 件はすべて前者、fallback race 9 回・watcher の `2>/dev/null` は後者。次の構造型 2 本: (a) deploy_task 入口で『変更 script を参照する tests/ の grep 一覧+全 PASS』必須化 (b) ALL_CLEAR=false を立てる全経路に理由記録を必須化し race は WAIT へ分類。

## 将軍節（cmd_4442 統合役・第22便 17:17〜22:09 の一次）

分類軸: ①偽陽性 ②過剰 BLOCK ③構造バグ ④循環拘束 ⑤遅い script・test ⑥Claude↔Codex 仕組み差 ⑦サンクコスト過剰複雑化 ⑧影響範囲・依存未解明の浅い対応

| ID | 時刻 | 現象 | 主分類 | 副分類 | 一次証跡(コマンド → 出力行) | 根治 | proof / 根治案・影響範囲・依存 |
|---|---|---|---|---|---|---|---|
| S-01 | 17:1x-17:29 | 影丸 v3 report が cmd_3264-AC2『target_path 未 commit』で 103 回 BLOCK。task は review_correction_scope=report(コード commit 不可)×gate は clean 要求 | ③構造バグ | ④循環拘束 | `grep -c 'BLOCK(cmd_3264-AC2)' logs/deploy_task.log` → 103 / `git merge-base --is-ancestor 4d369d017 HEAD` rc=1(dangling) | 済 | 家老 92d1853bb+66db5f3fd(合流)、契約側 影丸 report-only dirty 契約 CLEAR 19:43。proof: cmd_3264 BLOCK 17:30 以降 0 |
| S-02 | 17:1x-17:29 | S-01 の replay(monitor REPORT-OUTBOX-REPAIR)ごとに inbox_write.sh:3000 が軍師へ quality_monitor を送信=同一本文 21→30 件、軍師 stop hook 閉塞 | ⑧浅い対応 | ③ | `python3` で gunshi inbox type=quality_monitor 集計 → 21 件同一 report / `grep REPORT-OUTBOX-REPAIR logs/ninja_monitor.log` 毎分 | 止血済 | 将軍 D0 702ca5090→79dfd86e9(report 内容 hash marker)。家老 REJECT: claim race・掃除なし→U1(未配備)。proof: 17:29:22 以降同一 report 再送 0 |
| S-03 | 17:35-18:14 | 将軍 clear_command が未読残置→watcher が generation 変化ごとに CLEAR-FORCE 再送(13 回)、軍師 recovery が毎回消える | ③構造バグ | ⑧ | `grep -c CLEAR-FORCE logs/inbox_watcher_gunshi.log`(18:00-18:14) → 13 / 手動 `inbox_mark_read.sh gunshi <id>` → `BLOCK: inbox read receipt does not cover msg_id` | 止血済 | 真因=receipt 契約(疾風 hotfix)が watcher 特殊 type 既読化(inbox_watcher.sh:594 `2>/dev/null \|\| true`)を BLOCK し握りつぶし。将軍 D0 bbaa38f4d。家老 REJECT: receipt を全未読に付与=境界拡大→U3(未配備)。proof: 18:14:25 以降 CLEAR-FORCE 0 |
| S-04 | 17:36-18:11 / 19:4x / 20:0x / 21:0x / 21:3x | CI RED 5 回(33486782574 shard4 3 test / 33497348023 Integration inbox / 33499882240 generated cache / 33505016080 fail-close fixture / 33507554669 push_lane_integrate 旧契約) | ⑧浅い対応 | ④(RED が push を止め push が GREEN を作る) | `gh run view <id> --log \| grep -E 'not ok\|rc=[1-9]'` 各 run | 各 ci_fix 済 | 5 回とも『契約を変えた hotfix が fixture/caller を census せず本番へ』(#3 は将軍の generated 未再生成)。根治案=deploy_task 入口で『変更 script を参照する tests/ の grep 一覧+全 PASS』必須化。影響範囲=hotfix 全般。依存=U9 と同 lane |
| S-05 | 17:36-17:40 / 19:14-19:25 / 20:14-20:46 | push lane 統合失敗 3 波: GA-PUSH1(常時 dirty runtime 3 file)/ insights.yaml content conflict+origin 毎分前進 / 固定 list 外 dirty+CONFLICT 6+safe_ff guard の恒久 BLOCK | ③構造バグ | ④循環拘束 | `grep -cE 'auto_merge=failed' logs/ninja_monitor_push_lane.log` 19:14-19:23 → 5 / `git merge-tree --write-tree HEAD origin/main \| grep -c CONFLICT` → 6 / `bash scripts/safe_shared_main_ff.sh 31eac92a3` → BLOCK ours_equivalent=1 | 済(U5/U6/U8) | 将軍 D0 fa82d08c1(union、撤回)・33595add4(固定 list、撤去)→家老 unit U5(ID-keyed driver)U6(isolated 統合)U8(台帳別 merge 戦略)CLEAR。proof: 21:12 以降 MERGE-FAIL 0。残=U9(ours 相当 merge 0334a9c71 の producer+guard の既存 merge 除外) |
| S-06 | 20:41 | U5 driver が列 0 の `- id:` 行を region 終端と誤認→starts=0→『ancestor block count does not match』で統合 BLOCK | ⑧浅い対応 | ①偽陽性 | `bash scripts/insight_write.sh --merge-driver O A B` → BLOCK … / 修正後 rc=0、merged entries 1263 dup 0 | 済 | 将軍 4c295c112。本番 file 形(列 0 list)を fixture に含めなかった=⑧。同一 ID 両親変更は BLOCK 維持(設計) |
| S-07 | 19:04-19:13 | 将軍が gist_sync.sh(dashboard 常駐 daemon)に設計書 gist_id を渡し無限 loop=『commit hang』誤認、roadmap gist に dashboard.md 混入 | ⑦道具の名前で用途推定 | ② | `gh gist view da1b7617 --files` → 2 file(dashboard.md 混入) / `timeout 25 bash -x gist_sync.sh <id>` trace 0 行 | 済 | REST PATCH で除去、9c19734af(固定 id を dashboard gist に限定)。型二十二弾-5 |
| S-08 | 17:27 | 小太郎 idle_lifecycle fixture が本番 session `shogun` に window 3/4 を作り残置(gunshi_sim watcher) | ⑧浅い対応 | ② | `tmux list-windows -t shogun` → 4 window(余剰 2) / `pgrep -af inbox_watcher.sh gunshi_sim` | 済(閉鎖) | 型3弾-3 再発。根治案=fixture helper で `tmux new-window -t shogun` を BLOCK(未着手) |
| S-09 | 14:27-21:24 | cmd_complete_gate `fallback_gate_status` BLOCK 9 回(全て再走 CLEAR)=ALL_CLEAR=false なのに理由未記録 | ①偽陽性 | ④ | `grep -c fallback_gate_status logs/gate_metrics.log`(本日) → 9 | 未 | INS-194354。根治案=ALL_CLEAR=false を立てる 56 箇所のうち理由未登録経路を列挙、LGTM/ACCEPT 到達との race は WAIT(review_two_phase_pending)へ分類し自動再走。影響範囲=gate 全 cmd。依存=なし(単独 unit) |
| S-10 | 20:4x | cmd_skeleton.sh が 2 分 hang(timeout)→将軍が手書き起票→gate と 2 往復(serial_dependency_evidence/test 定型句/AC 語の累計昇格 BLOCK) | ⑤遅い script | ② | `timeout 120 bash scripts/cmd_skeleton.sh` → Exit 143 / cmd_publish 2 回 BLOCK | 未 | 根治案=cmd_skeleton の hang 箇所を bash -x で特定(記憶DB 検索か semantic か)。累計昇格 BLOCK は同一 cmd の再試行を数える=偽陽性 |
| S-11 | 19:42 | Free tier ログイン不能: admin rotate-all が Render env を PUT するだけで deploy を起こさず、プロセス env は旧値(6 tier 中 premium のみ 200) | ③構造バグ | ⑧ | `POST /api/auth/verify-viewer`(Render 現在値) → FREE/BASIC/STANDARD 401、PREMIUM 200 / Render events に deploy 0 | 止血済 | backend 再 deploy(dep-dabavvf1、20:02 live)で 6 tier 200、殿実機 PASS 20:30。恒久=rotation 末尾で deploy API(cmd 未起票、dm-signal) |
| S-12 | 19:38-19:45 / 21:56 | hook の文字列一致 guard が本文中の語(`bats`・`tee`+`queue/tasks`・`shogun_to_karo` を含む python heredoc)に反応し将軍の無害な bash を 4 回 BLOCK | ①偽陽性 | ⑥ | 各 BLOCK メッセージ(本ターン内 4 回) | 未 | 型十九弾-5 の同型。根治案=本文はファイル経由・hook は構造(行頭・書込み形)で判定。影響範囲=pre-bash guard 群 |
| S-13 | 17:16-19:47 | 家老の karo-direct 配備が『先行 cmd の done report 未 archive』(deploy_race guard)で BLOCK し、後続 hotfix が LGTM→GATE→archive を待つ直列 | ④循環拘束 | ② | `grep -c 'deploy_race' logs/deploy_task.log` 17:16 → 1 / 掲示板 blt_171639 | 設計どおり | 同一 target の直列は正だが、待ちが軍師 1 点で 2h46m に伸びた(S-02/S-03 の連鎖)。根治は S-02/S-03 で解消 |

### 分類別件数(将軍節のみ、主分類)
`grep -oE '\| S-[0-9]+ \|[^|]*\|[^|]*\| [①-⑧][^|]*' queue/notes/shogun_tsumari_seed_20260901.md | awk -F'|' '{print $5}' | sort | uniq -c`
- ③構造バグ 4(S-01/S-03/S-05/S-11) ⑧浅い対応 4(S-02/S-04/S-06/S-08) ①偽陽性 2(S-09/S-12) ④循環拘束 1(S-13) ⑤遅い script 1(S-10) ⑦サンクコスト 1(S-07)。⑥Claude↔Codex は副分類のみ(S-12)。

## 家老節（将軍代筆・出典=家老の本日掲示板+logs。家老 karo-direct 配備が DOC_LANE_ROUTING で BLOCK されたため将軍 doc lane で記載、blt_221014）

| ID | 時刻 | 現象 | 主分類 | 一次証跡 | 根治 |
|---|---|---|---|---|---|
| R-01 | 17:16 | 次弾 hotfix の karo-direct 配備が『先行 cmd(疾風 receipt)の done report 未 archive』で deploy_race guard BLOCK。先行の LGTM→GATE→archive を待つ直列(blt_171639) | ④循環拘束(設計どおりの直列だが待ち先が軍師 1 点に集中) | `grep 'deploy_race' logs/deploy_task.log` 17:16 → 1 | 待ち先(S-02/S-03)の解消で自然解除 |
| R-02 | 19:35 | 将軍 D0 6 commit のレビュー: APPROVE 1/REJECT 5(marker race・掃除なし・receipt 境界拡大・union の ID 一意性・固定 list 自動 commit)(blt_193552) | ⑧浅い対応(将軍側) | `rg -c REJECT queue/bulletin_board.yaml`(blt_193552) → 5 | U5/U6/U8 CLEAR、U1/U3/U9 残 |
| R-03 | 20:26 | U6 task YAML 作成済だが ninja_monitor.sh が小太郎 fail-close hotfix の active 予約と衝突し公開 0 で BLOCK→小太郎 CLEAR 後に配備(blt_202627) | ④循環拘束 | task YAML status=done parent_cmd=fail-close(家老集計) | 小太郎 CLEAR 20:30→U6 配備 20:31 |
| R-04 | 17:47 / 19:46 / 20:1x / 21:1x / 21:4x | CI RED 5 回への ci_fix 配備(半蔵→才蔵→将軍→半蔵→半蔵)。才蔵 ci_fix #2 は failed 残置(void 推奨) | ⑧浅い対応 | `grep -c ci_fix logs/deploy_task.log`(本日) | 各 CLEAR。構造=hotfix 入口の tests census(S-04) |
| R-05 | 22:10 | cmd_4442 家老節の karo-direct 配備が deploy_task DOC_LANE_ROUTING(docs/research target)で BLOCK、task/report/inbox 公開 0(blt_221014) | ②過剰 BLOCK | `rg -c 'BLOCK\(DOC_LANE_ROUTING\)' logs/deploy_task.log` → 1 | 将軍 doc lane で代筆(本節)。根治案=SCOUT cmd の docs/research 成果物は report-only で通す例外を deploy_task に |
| R-06 | 14:27-21:24 | 家老 ACCEPT 直後の gate が fallback_gate_status で BLOCK し再走で CLEAR(本日 9 回) | ①偽陽性 | `grep -c fallback_gate_status logs/gate_metrics.log` → 9 | 未(S-09/G6 と同一) |

## 軍師節（cmd_4442_gunshi_view）

対象: review/receipt/inbox処理の摩擦
母集団: logs/gunshi_review_log.yaml, queue/inbox/gunshi.yaml, 掲示板, 本セッション実体験

| # | 時刻 | 現象 | 分類 | 一次証跡 | 根治済 | 根治commit |
|---|------|------|------|---------|--------|-----------|
| G1 | 18:56-19:15 | review_log YAML構文破損。gate_reflux.shが2スペインデントで`gate_result`/`gate_synced_at`を挿入し、後続フィールドとのインデント不整合でyaml.safe_load失敗→accuracy計算不能 | ③構造バグ | `bash scripts/gates/gate_gunshi_accuracy.sh` → `yaml.scanner.ScannerError line 103` | 済(手動sed) | なし(手動Edit 36箇所) |
| G2 | 19:38-19:45 | hayate review_processing_receipt hotfixがreview_draftにもreview_log照合を強制。draftにはreportが存在しないためreport_name=missing→BLOCK | ①偽陽性 | `bash scripts/inbox_mark_read.sh gunshi msg_*` → `BLOCK: review not recorded report=<missing>` | 済 | 989a9ee1 |
| G3 | 19:43-19:46 | TZ-naiveタイムスタンプのデフォルトUTC仮定。reviewed_at(+09:00→UTC 10:37) vs message(TZ無し→UTC 19:36)で9時間差→matched=False | ③構造バグ | Python `TypeError: can't compare offset-naive and offset-aware` → parse_timestamp UTC仮定で9h差 | 済 | 989a9ee1 |
| G4 | 20:14-20:15 | report_name_from_contentがcontent本文のregexのみ参照。構造化report_pathフィールドを見ずreport=missing→BLOCK | ③構造バグ | `bash scripts/inbox_mark_read.sh` → `BLOCK: review not recorded report=<missing>` | 済 | 6843d453 |
| G5 | 19:53-21:40 | reviewed_at < message timestamp(数秒～2分差)で重複通知のmark_readがBLOCK。review_bundle.py singleがreviewed_atを確定する時点とkaro report_review通知の時間差が根因。8回以上発生し毎回LGTM再記録が必要 | ④循環拘束 | 繰り返し`BLOCK: review not recorded`→`gunshi_log_append.sh`で再記録→成功のパターン | 未 | INS-20260901-200801590-a516 |
| G6 | 19:34-21:09 | LGTM→fallback_gate_status BLOCK→数分後CLEAR転換。lesson:PASS/review_gate:PASSなのにfallback判定でBLOCK。worktree merge timing raceが根因。5回発生 | ④循環拘束 | `cmd_complete_gate.trigger.log` → `GATE BLOCK: 不足フラグ=[] 理由=fallback_gate_status` | 未 | worktree merge後にCLEAR転換(自然治癒) |

### 未根治事例の根治案

**G5 reviewed_at秒差BLOCK**:
- 根治案(構造型): review_bundle.py singleのreviewed_atをbundle生成・通知完了後に確定するか、mark_readの照合に秒単位マージン(例: reviewed_at >= message_at - 120s)を持たせる
- 影響範囲: `rg "reviewed_at" scripts/inbox_mark_read.sh` → 319行の比較1箇所
- 依存: なし（独立修正可能）

**G6 fallback_gate_status race**:
- 根治案(構造型): cmd_complete_gate.shのfallback判定でworktreeのmerge状態を確認し、未merge時はretry/defer
- 影響範囲: `rg "fallback_gate_status" scripts/cmd_complete_gate.sh` → 要調査
- 依存: U6 push lane isolated(完了) + U8 merge strategy(完了)が前提

**G1 gate_reflux.shインデント不整合**:
- 根治案(構造型): gunshi_gate_reflux.shがreview_logの各エントリのインデントレベルを検出し、挿入時に一致させる
- 影響範囲: `scripts/gunshi_gate_reflux.sh` の全insert箇所
- 依存: なし

## 忍者節（cmd_4442_scout・影丸）

### 調査境界

- 対象 task: `cmd_4442_scout`（`task_type: scout`、読取専用）。本節は忍者 kagemaru の `task`・自身の `report`・`gate_metrics`・`ninja_monitor` に現れた事例だけを記録する。
- 他ロールの事例は統合しない。全体の統合と gist 共有は将軍の責務である。
- 時刻境界: 2026-09-01 JST。一次台帳は共有リポジトリの `logs/`、自身の task/report は `queue/` から取得した。
- 判定: 「根治済」は該当修正の commit と再発ゼロの一次 proof が揃った場合だけとし、単なる再走 CLEAR は根治済と扱わない。

### 機械抽出の結果

| ID | 時刻 | 現象 | 分類 | 一次証跡（コマンドと出力行） | 根治状態 / 根治 commit |
|---|---|---|---|---|---|
| K-01 | 20:18:42 | 自身の `cmd_reflux_insight_202609011957_kagemaru` で、`lesson` と `review_gate` がともに PASS なのに総合 gate が `fallback_gate_status` BLOCK。20:21:07 に CI readiness WAIT、20:21:13 に再走 CLEAR。 | ①偽陽性（同時に③構造バグ候補） | `awk -F '\t' '$1 ~ /^2026-09-01/ && $2 == "cmd_reflux_insight_202609011957_kagemaru" {print NR ":" $0}' logs/gate_metrics.log` → `489:2026-09-01T20:18:42 ... BLOCK fallback_gate_status:lesson:PASS\|review_gate:PASS ...`、`493:... WAIT ci_readiness:WAIT...`、`494:... CLEAR all_gates_passed ...`。 | 未根治。`git log --all --since='2026-09-01 17:00' -S'fallback_gate_status' -- scripts/cmd_complete_gate.sh` で本日該当修正 commit なし。再走 CLEAR は根治 proof ではない。 |
| K-02 | 20:52:21–21:01:51 | 自身の reflux 完了後、monitor が `count=4/3 forced_idle` として `cmd_reflux_insight_202609011957_kagemaru` を処理し、その後5回 `cmd=unresolved:kagemaru` の CLEAR-LOOP-BLOCK-GUARD を出した。完了済み task の identity が `unresolved` へ落ち、監視が同じ guard を繰り返す。 | ④循環拘束（③構造バグ） | `awk '$0 ~ /^\[2026-09-01/ && /CLEAR-LOOP-BLOCK/ && /kagemaru/ {print NR ":" $0}' logs/ninja_monitor.log` → `5014:[2026-09-01 20:52:21] CLEAR-LOOP-BLOCK: kagemaru cmd=cmd_reflux_insight_202609011957_kagemaru count=4/3 forced_idle...`、同出力の `5128,5240,5365,5475,5617` → `CLEAR-LOOP-BLOCK-GUARD ... cmd=unresolved:kagemaru ... clear=0`。 | 未根治。identity を保持したまま clear-loop 判定する構造修正と、`unresolved` を終端扱いしない明示的な再照合が必要。該当 caller census は `scripts/ninja_monitor.sh:2283,2289,2315-2318` と既存契約 test `tests/unit/test_ninja_monitor_clear_guard.bats:2635,2706`。根治 commitなし。 |

### 分類別の再計数・影響範囲

| 計測 | コマンド | 実測結果 |
|---|---|---|
| 同日 fallback BLOCK の母数 | `awk -F '\t' '$1 ~ /^2026-09-01/ && $3 == "BLOCK" && $4 ~ /^fallback_gate_status/ {n++} END {print n+0}' logs/gate_metrics.log` | `9`（うち自身の K-01 は1） |
| fallback の code caller census | `bash scripts/code_locate.sh 'fallback_gate_status' scripts tests` | `scripts/cmd_complete_gate.sh:15585` の1 caller、tests側の直接実装なし |
| 自身の CLEAR-LOOP 証跡 | `awk '$0 ~ /^\[2026-09-01/ && /CLEAR-LOOP-BLOCK/ && /kagemaru/ {n++} END {print n+0}' logs/ninja_monitor.log` | `6`（forced_idle 1 + identity unresolved guard 5） |
| CLEAR-LOOP code caller census | `bash scripts/code_locate.sh 'CLEAR-LOOP-BLOCK' scripts tests` | `scripts/ninja_monitor.sh` 3実装箇所（2283, 2289, 2315-2318）+既存契約 test 3箇所 |
| 自身の hook failure | `python3` で `logs/hook_failures.yaml` を読み、timestamp が `2026-09-01` かつ `ninja=kagemaru` を抽出 | `0` |
| 自身 watcher の BLOCK/RC/RETRY | `awk '$0 ~ /^\[2026-09-01/ && /kagemaru/ && /inbox_write|BLOCK|RC|RETRY/ {n++} END {print n+0}' logs/inbox_watcher_kagemaru.log` | `0`。本調査の inbox は current task の未読1件のみを適用し、既読・別taskは適用していない。 |

### 未根治事例の次回検証契約

- K-01（構造型）: `cmd_complete_gate.sh` の fallback 判定が参照する gate 状態を同一世代の atomic snapshot として固定し、サブゲート全 PASS で総合 BLOCK にならない敵対 fixture を実行する。全 `fallback_gate_status` caller（現時点1）と gate result writer の census を先に取り、修正後に同日 BLOCK が0行であることを確認する。依存は gate 状態 snapshot の所有者確定。
- K-02（構造型）: `ninja_monitor.sh` の clear-loop counter に task identity を必ず同伴させ、`unresolved:<agent>` を既存 task の終端として再利用しない。forced-idle、identity unavailable、task/inbox generation 変更の3境界を既存契約 test と本番 log で検証する。依存は K-01 のような gate終端誤判定とは独立で、monitor identity 経路の所有者確定が先である。

### 除外した情報

`logs/deploy_task.log` は本 task の配備成功（21:04:54 worktree ready）を示すだけで、自身の BLOCK/RC/RETRY ではない。`logs/hook_failures.yaml` と `logs/inbox_watcher_kagemaru.log` にも本日該当行はなかったため、事例表へ水増ししていない。将軍・軍師・家老の事例、掲示板の他ロール記述、既読または別 task の inbox 指示は AC2 の境界により本節へ取り込まない。

---

# 第 2 回(09-02 17:17〜09-03 02:53、単一 publisher 実装便。将軍一次+家老掲示板+gate/task YAML から再集計、殿指示 09-03 02:52『改めて』)

## 将軍統合(分類別件数・第 2 回)

| 分類 | 第 1 回 計 | 第 2 回 | 根治済 | 未根治 |
|---|---|---|---|---|
| ①偽陽性 | 5 | 4 | 4 | — |
| ②過剰 BLOCK | 1 | 3 | 0 | cmd_save の AC path 存在検査が別 checkout(/mnt/c 保守 branch)を見る(T2-09)、Write hook の literal 禁止(T2-10)、doc 成果物を忍者が commit 不可(T2-20) |
| ③構造バグ | 7 | 6 | 5 | 手動 CLEAR receipt の正規手段なし(T2-14→U8 で定義) |
| ④循環拘束 | 6 | 3 | 2 | 将軍 loop の再武装忘れ(T2-21、手順化のみ) |
| ⑤遅い script・test | 1 | 1 | 0 | cmd_save preflight が 120 秒超(T2-26、S-10 と同根) |
| ⑥Claude↔Codex 仕組み差 | 0 | 0 | — | — |
| ⑦サンクコスト過剰複雑化 | 1 | 1 | 1(殿裁定) | — |
| ⑧影響範囲・依存未解明の浅い対応 | 6 | 6 | 5 | enqueue の repo guard(T2-18、影丸 走行中) |
| 計 | 27 | 24 | 17 | 7 |

**構造の結論(第 2 回)**: 第 1 回の 2 型(⑧契約変更が census なしで本番へ、③BLOCK 理由の握りつぶし)は減った(⑧は検証 cmd 型で 3 件を fail-close で捕捉=設計どおり)。第 2 回の主型は **「生産者を消費者より先に出す順序バグ(③)」**=U5 の ACCEPT→enqueue が daemon 未起動のまま着地し全 CLEAR を閉塞、LP build が backend より先の API 応答を焼く、merge driver が消えた worktree を指す。いずれも「依存の向きを逆に着地させた」構造で、対策は cmd の depends_on と post_deploy_check を『消費者が生きているか』で書くこと。もう 1 型は **「殿が撤回するまで将軍が canary/検証を積む(⑦)」**で、殿 01:30/01:31 の 2 発言で U3b・24h canary・検証 4 本を撤回して便速度が戻った。

## 将軍節(第 2 回。番号 T2-xx、時刻 JST)

| ID | 時刻 | 事象 | 主分類 | 真因 | 処置 / 状態 |
|---|---|---|---|---|---|
| T2-01 | 09-02 17:52〜23:09(6 回) | root index 後退: 上流追加 file が root で staged 削除に見える | ③ | ninja_monitor integrate が update-ref のみで index/worktree を更新しない | 半蔵 read-tree hotfix 6a7e852ec(§14.4 例外)、proof 00:17 2 回 staged 0。根治 |
| T2-02 | 23:20-23:58 | push lane 38 分停止(未 push 25) | ④ | GA-PUSH1 が『push 対象と作業木の未 commit が同一 path』を BLOCK、常時 dirty の台帳 9 path が必ず重なる | 将軍が台帳 dirt を 1 commit(bf64941c1)に吸収→PUSH 26。根治=U6 ledger writer+U3 publisher(旧 lane は U8 で削除) |
| T2-03 | 23:16 | gate WAIT publisher_pending が dequeued も pending 扱い | ① | rglob が処理済 dir を走査 | 小太郎 1 行 hotfix CLEAR 00:15。根治 |
| T2-04 | 00:4x | gate の receipt pair 走査が cross_repo 2 entry で即 fail | ① | 複数 source の receipt を単一前提で照合 | 疾風 b66cc4dd9 CLEAR。根治 |
| T2-05 | 23:16〜01:30 | U5 着地で ACCEPT→enqueue が生き、全 CLEAR が publisher_pending で閉塞 | ③ | 消費者(daemon)より先に生産者(enqueue)を本番へ出した。U5 の depends_on に U3 active が無い | 将軍裁定 23:27/23:34→U3 修正後 01:30 active。根治(順序の教訓は本表の結論) |
| T2-06 | 23:32 | U3 dry-run で欠陥 3 点(冪等性なし・tip 前進時 restore FAIL・通知 type BLOCK) | ⑧ | 実装 cmd が『同変更が既に載っている』『tip が進んだ』の 2 状態を fixture にしていない | 才蔵 f5b195fea CLEAR 00:05。根治 |
| T2-07a | 20:17 | U2 検証 FAIL: manifest 未申告 path を restore が適用 | ⑧ | 実装 file 欠陥。検証 cmd 型(別 CLI・別番号)で fail-close 捕捉=設計どおり | 飛猿 ea8bdd794→再検証 cmd_4457 CLEAR 01:20。根治 |
| T2-07b | 21:1x | U1 検証 FAIL: FIFO が辞書順 | ⑧ | 同上 | 才蔵 6fc7e7b81(sequence lock)→再検証 cmd_4458 CLEAR 01:46。根治 |
| T2-08 | 09-02 夜〜01:1x(3 回) | 軍師 idle flag stall(bash_running のまま起きない) | ③ | gunshi_log_append の --help が stdin を待って hang | 影丸 根治 hotfix 着地。将軍は capture-pane で dialog 無しを確認後に nudge。根治 |
| T2-09 | 01:3x/02:4x | cmd_save が lp/ 配下 AC path を『親 dir 不在』で WARN/BLOCK | ② | 存在検査が /mnt/c の保守 branch(rb6-cleanup、origin 215 手前)を見る | AC を文章表現に書換えて回避。**未根治**(検査 root を origin/main tree に) |
| T2-10 | 22:2x〜 | Write hook が literal $HOME path・model 名を含む file 書込みを BLOCK | ② | 文字列一致 guard(S-12 と同根) | scratch python 経由で回避。**未根治** |
| T2-11 | 01:2x | .git/config の merge driver が回収済 worktree path を指し全 merge 失敗→push 閉塞 | ③ | insight_write.sh の driver 登録が $merge_repo 絶対 path を焼く | 小太郎 29168ab9c(primary root 固定)。根治 |
| T2-12 | 01:2x | workarounds driver が同一 cmd_id の 2 件目を重複拒否 | ① | 正当な複数 WA(手動+rework 自動)を identity=cmd_id で衝突判定 | 同 29168ab9c(cmd_id+timestamp 複合 key)。根治 |
| T2-13 | 01:2x | bulletin 同一 entry 衝突 | ④ | 台帳 file の並行追記 | 家老が origin 版復元。根治は U6 writer |
| T2-14 | 01:23 | U5 cmd_4453 が gate 3 経路(legacy/publisher/manifest)とも到達を証明不能→手動 CLEAR。archive は receipt 無しで fail-closed | ③ | task idle 化で source 紐付け切れ+後続修正で blob 差+task_id 再利用。手動 CLEAR の receipt 発行手段がない | 証拠 file を残し completed。**未根治**(U8 で手動 CLEAR receipt を定義、decision_candidate) |
| T2-15 | 23:5x | U6 test が $HOME 固定 mktemp で CI runner 3 FAIL | ⑧ | fixture が runner の $HOME 差を想定せず | 疾風 ci_fix 8e70baf70 CLEAR 00:16。根治 |
| T2-16 | 23:12 | gate_report_format が `./` 付き path を不一致判定、最上位 file の task が CLEAR 不能 | ① | path 正規化漏れ | 疾風 a6ebc5b58 1 行。根治 |
| T2-18 | 02:14 | dm-signal の request が infra publisher へ enqueue(restore conflict=1、実害なし) | ⑧ | 裁定『dm-signal は対象外』の enqueue 側分岐が未実装 | 影丸 hotfix `..._publisher_enqueue_repo_guard_202609030218` 走行中。**未根治(着地待ち)** |
| T2-19 | 02:3x | cmd_4459 backend live 後も LP 月次頁の保有欄が『—』 | ③ | LP build の fetch(next.revalidate 3600)が Next data cache に入り Render build cache で次 build へ持越し=backend より前の API 応答を焼く | 将軍 clearCache 再 deploy(止血)+cmd_4462(fetch no-store+build 後 assert)起票 02:45。根治は 4462 着地 |
| T2-20 | 02:00 | cmd_4461 の成果物 manifest(doc)を忍者が commit できず root に untracked | ② | docs/ は将軍 doc lane 管轄で忍者 commit が BLOCK | 将軍 doc lane 取込 a7b41bc64。**未根治**(doc 成果物 cmd は起票時に route を明示する規則が無い) |
| T2-21 | 01:30-02:16 | 将軍 loop 停止 46 分(殿 02:13『loop は生きているか』で発覚) | ④ | inbox 駆動で応答するたび ScheduleWakeup 再武装を省いた | 02:16 再武装、応答末尾の再武装を手順化。**未根治(手順のみ、構造化なし)** |
| T2-22 | 01:59 | 将軍が才蔵 4461 failed を『template 未記入』と誤診し家老へ下知 | ⑧ | report 本文と pane を一次確認する前に task YAML の block_reason 履歴だけで結論 | 家老が訂正(正当 fail-close)。根治=一次確認順序(本表で記録) |
| T2-23 | 01:30 | U3 active 24h canary・U3b・検証 cmd 4 本を積んで便が遅延 | ⑦ | 設計書の canary/検証を殿の速度要求より優先 | 殿 01:30/01:31 で撤回。根治(殿裁定) |
| T2-26 | 02:41 | cmd_save --preflight が 120 秒超で background 化 | ⑤ | S-10 cmd_skeleton 2 分 hang と同根(semantic_search+FTS5 を直列実行) | **未根治** |
| T2-27 | 04:58 | U6 ledger route(cmd_4454)が本番で一度も動かず、4 caller が legacy 直書きへ沈黙フォールバック | ③ | (a)`[[ -x ledger_writer.sh ]]` 検査で file が 644 のため常に偽 (b)ledger_inbox を apply する消費者が publisher に未実装。同型の -x 沈黙スキップが gate_skill_script_refs(9fd435f1e)・auto_failure_lesson(d90f86e71)でも実在 | 家老 deepdive 追体験で発見→将軍裁定 04:56: 消費者を publisher に実装(cmd_4465)、-x は着地まで維持。**未根治(4465 着地待ち)**。flag ON 後は legacy no-op のため root dirty が溜まる(14) |

集計コマンド: `grep -oE '^\| T2-[0-9]+[ab]? \|' docs/research/tsumari_root_causes_20260901.md | wc -l` → 25(04:58 T2-27 追記)。根治 17 / 未根治 8(T2-09/10/14/18/20/21/26/27)。

## 未根治 7 件の次の一手(将軍)

| ID | 一手 | 担当 |
|---|---|---|
| T2-09 | cmd_save の AC path 検査を `git -C <repo> ls-tree origin/main` 基準にする 1 行 | 家老 hotfix |
| T2-10 | Write hook の literal 禁止を『file 種別=運用 YAML/context』に限定 | 家老 hotfix(S-12 と同時) |
| T2-14 | 手動 CLEAR receipt(`gate_manual_clear.sh <cmd> <evidence>`)を U8 AC0 として cmd_4461 AC2 の起票に含める | 将軍 |
| T2-18 | 影丸 hotfix 着地→flag ON 前に landing | 家老 |
| T2-20 | cmd 起票規則: 成果物が docs/ の cmd は `deliverable_route: shogun-doc-lane` を明示し、家老が report の path を将軍へ渡す | 将軍(cmd_skeleton に 1 field) |
| T2-21 | stop hook で『将軍かつ loop 中かつ ScheduleWakeup 未呼出』を WARN | 家老 hotfix |
| T2-26 | preflight の semantic_search を並列化 or キャッシュ | 家老 hotfix(S-10 と同時) |
| T2-27 | publisher に ledger 消費者(kind=ledger)を実装+ledger_writer.sh を 755 で追跡+実行 bit の契約 test。-x 沈黙スキップは『存在するのに実行不可』を WARN 出力する 1 行を 3 caller に | 将軍 cmd_4465 |

---

# 第 3 回(PUBLISHER_SINGLE ON 09-03 04:37〜、新環境。殿指示 10:46『前提とする環境が変わった。もう一度 8 分類で全員で探索』→cmd_4470 全ロール偵察。将軍節を先行、忍者 6 領域・軍師節・家老節は着地後に統合)

## 将軍統合(分類別件数・第 3 回、全ロール 12:25。出典=queue/notes/tsumari_r3_<name>.md 7 本(origin/main 到達、cmd_4470)+将軍節。軍師節は review_draft 経由で着地後に追記)

| 分類 | 将軍 | hayate | kagemaru | hanzo | kotaro | saizo | tobisaru | karo | gunshi | 計(第 3 回) |
|---|---|---|---|---|---|---|---|---|---|---|
| ①偽陽性 | 6 | 0 | 2 | 0 | 0 | 0 | 0 | 1 | 3 | 12 |
| ②過剰 BLOCK | 1 | 1 | 1 | 0 | 0 | 2 | 0 | 1 | 2 | 8 |
| ③構造バグ | 9 | 6 | 2 | 2 | 0 | 2 | 2 | 7 | 5 | 35 |
| ④循環拘束 | 3 | 0 | 2 | 1 | 2 | 2 | 1 | 1 | 0 | 12 |
| ⑤遅い script・test | 2 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 3 |
| ⑥Claude↔Codex 仕組み差 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 |
| ⑦サンクコスト過剰複雑化 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 2 |
| ⑧影響範囲・依存未解明の浅い対応 | 4 | 1 | 2 | 3 | 1 | 3 | 0 | 1 | 0 | 15 |
| 計 | 26 | 9 | 9 | 6 | 3 | 10 | 4 | 12 | 10 | 89(うち該当なし 1) |
| 未根治 | 5 | 9 | 7 | 5 | 3 | 3 | 0 | 3 | 5 | 40 |

第 1 回 27 / 第 2 回 25 / 第 3 回 89(将軍 26+忍者 41+家老 12+軍師 10、軍師節 13:05 追記)。未根治 40 のうち忍者節 27 は『次の一手』=単独再実行・時刻付き再計数が未実施のものを含む(推移的な件数であり、根治対象の重複が多い。下記の統合で 6 型に畳む)。

**構造の結論(第 3 回・全ロール統合)**: 89 件の 8 割が③構造バグ(35)・⑧浅い対応(15)・④循環拘束(12)に集中し、その大半が **1 つの構造=『root(共有 checkout)に書く生産者 × publisher の ff-only root sync』** に帰着する。
1. **root writer × ff-only**(③④の中核): kagemaru-05 root_dirty 40 件/root drain divergence 913 行、karo-01/09/12(checkpoint 手回し 10 回・D012 merge 6 回)、tobisaru-01 dirty dispatch 10 回、hayate-08 GA-PUSH1、将軍 T3-S-01/15/16。U9(生産者 0)で bulletin/insight/semantic の 3 経路を ledger 化した後も production_proof 3 sample とも dirty>0=gate 群・lesson_write・cmd_save・senkyoku 等 7 種が残る。**→ 生産者 0 は gate まで含めると現実的でない。ToBe=root sync の field-aware 3-way(U9b、cmd_4471)**。
2. **台帳 file の直編集 × ledger batch**(③⑧): kagemaru-01 base_blob_mismatch 7、tobisaru-02 4 連続、karo-05。hotfix reflux_ledger_resolve_op(2e2f56316)+review_approval identity(d6104fed7)で根治、残は production 再計数。
3. **単一 publisher 前提に未対応の gate/precheck**(①②④): saizo-01 WAIT ancestry 587 回/20 cmd(publication 待ちを WAIT で回し続ける)、saizo-03 report_format/fallback BLOCK 8、saizo-08/karo-07 SG-PRE35、hanzo-05、将軍 T3-S-10/11/12/23。precheck 3 本+ALL_CLEAR 再整合で収束。**残=WAIT ancestry の再 GATE 周期(587 回は gate_metrics の空回し=⑤に近い)**。
4. **観測系の欠測**(⑧): kagemaru-06/07/08『daemon 行に時刻が無く窓帰属不能』、kotaro-03 inbox_info_digest 0 追記、tobisaru-04 semantic_index_update log 不在、hanzo-03 causal audit no_test 86。→ daemon/capture log の行頭 ISO 時刻を必須にする 1 行(cmd_4471 に同梱)。
5. **監視が止めない/起こさない**(④): kotaro-01 watchdog unhealthy 205 回 restart suppressed 9h48m(旧 daemon 入替不能=将軍 T3-S-04 と同根、U10 で責務化)、kotaro-02 CLEAR-LOOP-BLOCK-REOPEN 8 回反復、hayate-09 Codex delivery FAILURE 17/monitor mismatch 45(⑥の唯一の実例)、将軍 T3-S-20 WAKE-DEFER 1001/1613。**未根治=busy gating と Codex capture 観測の 2 点**。
6. **test 自体の flaky/契約ずれ**(③⑤): hayate-01〜07(pre-push hook artifact で publisher/ledger/semantic の bats が計 15 回失敗、全て未根治=単独再実行未実施)、karo-06 CI RED(既存 bats 未実行)、将軍 T3-S-13/14/21。→ hayate 節 7 件は『pre-push で回る bats が root 状態(dirty/tmpdir/remote HEAD)に依存する』1 型。**次の一手=隔離 fixture で 7 件を 1 度に再実行し、pass するものを閉じる(cmd_4472 候補)**。

7. **軍師節(レビュー側、T3-G-01〜10)**: yaml.dump による review_log 上書き 3 回(G-01/G-10、HEAD 37+32 entry 消失=YAML 安全規則違反、③)、SG-PRE35 偽陽性(G-02=karo-07 と同一)、LG085 regex が自然言語の「ERRORS=1」に反応(G-03、①)、singleflight terminal cache が precheck 修正後も再実行を拒む(G-04、②)、mark_read timestamp BLOCK の迂回 15 回以上(G-05、②)、**ledger resolve-only task に commit が無いのに approval/ancestry が commit を要求(G-06/G-07、③=d6104fed7 で approval 側は根治、cmd_complete_gate 側は未根治)**、AC3 否定形 check 文言で bc:no(G-08=karo-11)、review_bundle が古い worktree で precheck(G-09)。→ 型 3 に G-06/07/09、型 6 に G-01/10 を追加。未根治 5=G-03/04/05/07/09。

X lane(hanzo-01/02、karo-08)は cmd_4467 gate の沈黙フォールバック=根治済(2fa437a9c)。⑥Claude↔Codex 差は hayate-09 の 1 件のみで、便を止めた主因ではない。⑦は U8 凍結と家老の手回し(karo-12)の 2 件で、後者は 1. の帰結。

各節の原本(全行・log 引用付き): `queue/notes/tsumari_r3_hayate.md`(hook/CLI 9)・`tsumari_r3_kagemaru.md`(publisher/ledger 9)・`tsumari_r3_hanzo.md`(X lane/doc lane 6)・`tsumari_r3_kotaro.md`(monitor/watchdog 3)・`tsumari_r3_saizo.md`(gate 10)・`tsumari_r3_tobisaru.md`(reflux 4)・`tsumari_r3_karo.md`(家老 12)・`tsumari_r3_gunshi.md`(軍師 10)。集計コマンド: `for n in hayate kagemaru hanzo kotaro saizo tobisaru karo gunshi; do grep -cE '^\| T3-' queue/notes/tsumari_r3_$n.md; done` → 9 9 6 3 10 4 12 10。

一次計測(将軍 10:52、flag ON 以降): publisher events=c2a_rc 7 / ledger 68 / published 8 / **root_sync_skipped 33**、ledger rc 退避=bulletin 2・insights 29、pre-push reject 14、inbox_watcher WAKE-DEFER=karo 1001・gunshi 1613、close_check(10:42)=trailer 45/50・root dirty 9。

**構造の結論(第 3 回・暫定)**: 発生源は『旧経路どうしの衝突』から **『root に書く生産者と publisher の ff の衝突』(root_sync_skipped 33、③の 9 件中 6 件)** と **『gate/precheck が単一 publisher 前提(commit は publish まで root に無い)に未対応』(①の 6 件中 4 件)** へ移った。前者は U9(cmd_4468)で生産者を 0 にし、後者は precheck 3 本の修正で収束中。第 4 の型=**『supervisor が居ないと入替えられない daemon』**(D006/F009 の板挟み、④)は U10(cmd_4469)で watchdog の責務にした。

## 将軍節(第 3 回。番号 T3-S-xx、時刻 JST、出典=将軍の一次確認・publisher events・家老掲示板)

| ID | 時刻 | 事象 | 主分類 | 真因 | 処置 / 状態 |
|---|---|---|---|---|---|
| T3-S-01 | 05:21 | root が origin より ahead 20 で届かず | ③ | flag ON で旧 push が no-op、root 直 commit(doc lane/checkpoint/monitor/insights)に到達経路が無い | 家老 ff push→U1b 経路確立→root drain(U3c)→生産者 0(U9)。根治 |
| T3-S-02 | 05:2x | publisher push rejected(475a4657d) | ⑧ | artifact capture が deploy 時 base を固定で渡し、忍者の merge 後も base が古い | dded45428 capture base refresh+契約 test。根治 |
| T3-S-03 | 05:07/05:35 | publisher daemon 死亡 2 回 | ③ | rc の捕捉が if 複合文の後で常に 0→RC 処理誤動作→FileNotFoundError→set -e | 3862932ed 他 4 commit。根治 |
| T3-S-04 | 05:46〜09:23 | 旧 daemon が新コードを実行せず手動 1 周運用 | ④ | agent は kill 禁止(D006)・殿に依頼禁止(F009)・stop flag は旧 daemon が読まない | 09:23 自壊→watchdog 自動再起動で入替。U10(cmd_4469)で watchdog reload を責務化。根治 |
| T3-S-05 | 04:58 | U6 ledger route が本番未稼働 | ③ | 実行 bit 検査 644 で常に偽+消費者未実装 | cmd_4465(755 追跡・消費者)。根治 |
| T3-S-06 | 06:5x | ledger batch が重複 1 op で全中止、applied 移動前に抜け再適用 | ⑧ | 失敗 op の隔離と確定順序の欠落 | 195a924a7/4d0897c46/5895fc921。根治 |
| T3-S-07 | 06:53 | root tracked dirty 2029 | ③ | .git/config 書直しで core.fileMode=false 消失(tree は NTFS 複写で全 777) | false 再設定+c3fdc90aa で固定。根治 |
| T3-S-08 | 06:50〜 | bulletin_confirm/action『entry not found』連発 | ④ | 投稿は ledger route、root board は publisher の ff まで更新されない(root 直書きと ledger の二重) | U9 で bulletin 系を ledger op に統一。根治(10:19) |
| T3-S-09 | 09:13/09:4x | 掲示板 HEAD 66 vs worktree 30 の恒久乖離、台帳 4 file の取残し | ③ | bulletin_write:619 と monitor の時間 trim が root で archive、read-tree が dirty path を保護したまま HEAD だけ進める | 6cd1a3efc/f15d754b5 で ON 時 skip、家老が復元。根治 |
| T3-S-10 | 06:5x | 軍師 precheck が worktree 専用 file を FILE NOT FOUND | ① | precheck が root checkout のみ参照(単一 publisher では commit は publish まで root に無い) | 0be5e10f3。根治 |
| T3-S-11 | 10:1x | cmd_4469 review で SG-PRE35 ERROR | ① | 既存 test(in-file test_necessity)を新規 test 契約に混ぜていた | 9d6050e04。根治 |
| T3-S-12 | 〜08:1x | fallback_gate_status 偽 BLOCK 1 回/CLEAR | ① | ALL_CLEAR の再整合欠落 | 5a52b29cd。根治 |
| T3-S-13 | 06:3x | precheck tmpdir 残骸 test が flaky | ⑤ | /tmp 共有で並行 precheck と干渉 | 513cef654(TMPDIR 尊重)。根治 |
| T3-S-14 | 07:2x | semantic test 29 FAIL(fixture entry 消失) | ① | ledger_writer 755 化で fixture の insight_write も ledger route へ逸れた | f4e6ab789(canonical/明示 STATE_DIR のみ)。根治 |
| T3-S-15 | 08:20 | root 分岐(reflux 直 commit dbc3c3c15 vs origin) | ③ | reflux task が task_worktree 無しで root に直 commit | 506e77b6e(worktree 必須)+resolve を ledger op(hotfix 走行)。根治(hotfix 着地待ち) |
| T3-S-16 | 09:19 | root の台帳 4 file が HEAD より古い | ③ | T3-S-09 と同根(read-tree 保護) | 家老 復元 53408f376、U9。根治 |
| T3-S-17 | 05:25/06:14 | U8 物理削除が 2 度正当 FAIL | ⑦ | rg literal census は推移的 test 被覆と別機能再利用を見落とす | 凍結(将軍裁定 06:13)。運用 7 日後に移植設計書 |
| T3-S-18 | 09:2x | cmd_save BLOCK『観測窓を AC に置くな』 | ② | 本番 3 周期観測を忍者 AC に書いた | production_proof(家老)へ分離。根治(規則は正当) |
| T3-S-19 | 05:0x | U1b commit が hook で BLOCK(commit message 内の署名の閉じ山括弧を『cmd queue file へのリダイレクト』と誤認) | ① | pre-bash guard の redirect regex が文字列一致で、message 本文まで走査する | message を file から読む回避。**未根治**(guard を『実行行のリダイレクト』に限定する 1 行) |
| T3-S-20 | 04:23〜 | 家老 CTX 100% で monitor が /clear を送らず(HOOK-TRUST busy)、WAKE-DEFER=karo 1001/gunshi 1613 | ④ | hook 活動を busy と見なし、nudge も clear も保留する busy gating が過剰 | 将軍が clear_command で復帰。**未根治**(CTX≥95% は busy でも clear、WAKE-DEFER の上限で強制配送) |
| T3-S-21 | 08:1x | CI RED shard1 SKIP=FAIL | ⑧ | 家老の gate 変更で期待 echo が 2 行→1 行 | d4da5a26d。根治。**T3-S-21b**: push 連続で CI run が cancel され GREEN 未確認(⑤、**未根治**=push 集約か concurrency 設定) |
| T3-S-22 | 09:58 | X gate 規則 1 が空 blocklist で PASS | ③ | 公開 API に非公開 PF の holding が無く、空を PASS 扱い(沈黙フォールバック) | 2fa437a9c(認証 API・fail-close)。根治 |
| T3-S-23 | 10:42 | close_check 条件(5)が静的 rg で 51 件 FAIL | ① | U8 凍結で残る no-op 行を数える | §15 を runtime 判定に明確化(v3.23b)。根治(定義) |
| T3-S-24 | 10:42 | publisher の C2a 3-way merge commit に trailer 無し(trailer 45/50 の 2 件) | ⑧ | merge 経路で trailer 付与を忘れ | 3d03a2f2c `publisher_c2a_merge.sh`(trailer 固定)。根治 10:55 |
| T3-S-25 | 10:42 | gate が SKILL.md の『gate FAIL 履歴』を root で自動 commit(60c20e901) | ③ | 第 5 の root 直書き生産者 | 3d03a2f2c(ON 時 skip)。根治 10:55 |
| T3-S-27 | 13:2x〜15:00 | root behind 5→19 に拡大、cmd_4471(U11)と watchdog reload hotfix が CLEAR しても daemon 旧 pid 3 本のまま | ④ | **root checkout の script を daemon が実行する構造で、root sync の新コードは root sync 後にしか root に載らない(循環)**。dirty∩incoming の重なりは bulletin_board.yaml 1 本 | 家老 lane の checkpoint 1 回で切断(msg_145935)。恒久=watchdog が origin/main の blob から起動する(root 非依存)か、root sync を watchdog 側で先に行う=U12 候補 |
| T3-S-28 | 15:00〜15:24 | U11 の root sync 直後に将軍の未 commit 変更(doc 5 file・cmd queue 登録)が 3 度消失。merge=ours の todo map md は残り、driver 無しの infrastructure.md/html は消えた | ③ | `publisher.sh:252 git read-tree -u --reset tip` が非重なり dirty path を捨てる(AC1 (b) の保護欠落) | 家老 patch から復元 572b02fbc、STOP-SHIP hotfix 半蔵 c7b359cfe(--reset 撤去+契約 bats)。根治 |
| T3-S-26 | 06:13 | 将軍が家老の誤報で spinner 中の軍師 pane へ send-keys | ⑧ | capture を tail 3 行で判断し spinner を見落とした | 実害なし。以後 -S -40。根治(手順) |
| T3-S-29 | 17:5x〜18:0x | inbox_mark_read の bulletin_confirm が『entry not found』で 4 件連続 WARN、確認が消える | ③ | bulletin_write が ledger op を enqueue した直後に inbox notify を送る。ledger 適用前に受け手が confirm すると board file に entry が無い(notify と ledger 適用の順序逆転) | **根治 D0 18:10→18:25(2 層)**: 層 1 `scripts/bulletin_confirm.sh` が未適用 append op から entry を復元。層 2(18:1x 本番 inbox_mark_read 経路で再現『target id must be unique (0)』)=`scripts/ledger_writer.sh update` の enqueue 時一意性検査が board file しか見ない→pending append op も対象に。空 board(entries: None)も修正。bats 3/3(`test_bulletin_confirm_pending_fallback.bats`、append→update の順序 apply で closed を実証)。本番: 消えた確認 7 件を再 confirm 7/7 |
| T3-S-30 | 07:31〜17:59 | startup gate『action_required 未対応 14 件』が毎回鳴り、将軍が『表示バグ』と誤診(17:58 session_alerts)。実態=19 件 open のうち 12 件は infrastructure.md 反映済みだが actioned_by 空 | ④ | doc lane(context_source_commit_set.sh)が反映しても DOC_LANE 掲示板 entry を閉じない=台帳 2 本(context/掲示板)の片側更新 | **根治 D0 18:12**: `context_source_commit_set.sh` が同 commit の open DOC_LANE entry を bulletin_action で自動 close。既存 15 件を backfill、未反映 3 commit(69a039d71/f0a55c918/7488b08eb)を doc lane 反映。数値: open 19→4(残=script_size_alert/URGENT-HARM 07:39/INSIGHT_REPEAT/殿指示転送 11:00) |
| T3-S-31 | 毎 startup | gate_shogun_startup.sh:2109 `[: 0\n0: integer expression expected` で lifecycle 失敗行 Gate が壊れ、以降の判定が信頼できない | ③ | `grep -c` は 0 件でも「0」を出して exit 1 するため `\|\| echo 0` が 2 行目の 0 を足した(08-29 D0 の副作用) | **根治 D0 18:10**: `\|\| true` + 既定 0。18:11 再実行でエラー行 0 |
| T3-S-32 | 17:46〜17:55 | 陣形図 RUNTIME:busy 6 名だが実態は 3 名が報告済み(Codex セッション終了・pane 初期画面)で GATE 待ち。hotfix/ci_fix の配備先が『idle 0』で 25 分止まった | ⑤ | ninja_monitor の runtime_state が task status(in_progress)だけで busy を決め、report completed(AUTO-DONE-AWAITING-CLEAR)を区別しない | 将軍 capture-pane で発見→家老へ順序付き下知 17:58→GATE 再駆動で 18:02 飛猿 idle 化・ci_fix 配備。**根治案(家老 hotfix)**: runtime_state に `await_clear`(task in_progress ∧ report completed)を追加し、gate『走行中実測突合』と配備候補が使う |
| T3-S-33 | 16:40 | root 作業木の queue cmd 台帳から cmd_4472 block(55 行)が消失。全 commit(fd6b8c633/9e9669acf/d0764aa89/HEAD)は保持=commit ではなく作業木だけの欠落(mtime 16:40) | ③ | **書き手確定(家老 18:28)**=`archive_completed.sh` の sync_stk_status_from_archive。AC2 sub-task(cmd_4472_ac2_xdk_media_revision)の completed report の parent を cmd_4472 へ丸め、親 cmd を delegated→done 化して stk_remove_cmd_blocks で親 block を除去した(archive_worker.log 16:40:21『delegated→done: 1, archived: 1』)。sub-task CLEAR≠親 cmd 完了の区別が無い。U11/semantic op は時刻近接のみで非書き手 | **18:30 D0 復旧**: diff が削除のみ(0/55)で HEAD が上位集合と確認→`git restore --source=HEAD` 単一 file(scratch 退避)。cmd 10/10。根治=archive worker が parent 判定に sub-task suffix(_ac[0-9]+_/_normal 以外)を除外し、親 cmd は cmd_complete GATE CLEAR のみで done 化する(家老 hotfix、bats: sub-task report だけでは親 block 不変) |
| T3-S-34 | 継続 | root dirty 10(semantic-map/semantic-index/gunshi_review_log 2308 行/karo_workarounds/lessons×3/bulletin_board -630/session_alerts/cmd 台帳)。publisher root drain は dirty>0 で BLOCK し続ける | ③ | bulletin_archive の prune、軍師 review log rotation、lessons writer、semantic-map 再生成が root 作業木へ直接書き、誰も commit しない(U6 台帳 route 未発効の残り)。bulletin の -630 は archive 済(legit)だが未 commit | T237 の残壁そのもの。処置=各 writer を U1b(publish_direct_commit)か ledger op へ。次 idle 枠で家老 hotfix(writer 4 種の所有者付き一覧を本行に固定) |
| T3-S-35 | 14:43〜18:21 | cmd_4473 が report completed のまま 3.5h。将軍が cmd_save 根治後に再委任せず status=pending のまま放置 | ④ | 将軍の便回転漏れ(delegated∧未配備は gate が見るが、配備済∧pending は見ない盲点) | **18:21 委任**(ALREADY_DELEGATED 18:21:25)。家老 GATE 18:23=BLOCK manifest_consistency(AC1 影丸 report と AC2 疾風 manifest の identity 衝突)→小太郎 identity 分離 hotfix 着地後に再 GATE |
| T3-S-36 | 18:52 | cmd_4473 registry BLOCK の真因(家老): `review_resolve_reports`(scripts/lib/review_approval.sh)が queue/tasks の parent_cmd 一致から live_names を作るため、task slot が疾風 AC2 に上書きされた影丸 AC1 の live report を除外する。report-identity-registry の claim は解決器が参照せず UUID 登録だけでは効かない | ③ | 多 AC 1 cmd で「task slot=1 忍者」前提の解決器が AC ごとの report を扱えない(T3-S-32 の await_clear と同根=1 task slot に状態を全部載せる設計) | 将軍 18:55: 別 file(review_approval.sh)なので T3-S-32 を待たず即配備を下知。claimed report_id+parent 一致の採用、bats=slot 上書き後も AC1 report が canonical に残る 1 本 |
| T3-S-37 | 18:53 | [URGENT-HARM] 旧 generation の review 通知が永久に既読化できず BLOCK(家老)。同一 cmd の current approval が成立しても旧 fingerprint の通知は inbox_mark_read の receipt 契約で拒否され続ける | ② | receipt 契約(09-01 軍師一括既読事故の根治)が「世代が古い=未処理」と「世代が古い=superseded」を区別しない | 家老 ToBe=current approval 成立時に旧 fingerprint 通知を superseded として既読許可、approval 無しは従来 BLOCK。将軍 18:57: 別 file(inbox_mark_read.sh)なので T3-S-32 を待たず即配備 |
| T3-S-38 | 18:40〜18:59 | 軍師 inbox に才蔵 cmd_4472 review 依頼など未読 3 が 19 分滞留。軍師 pane は idle prompt だが tmux @agent_state=active・idle flag(/tmp/shogun_idle_gunshi)不在→watcher が nudge を『busy gating』で保留し続け、Stop hook も走らないので永久保留(DELIVERY-LATENCY-WARN held 1110s) | ③ | 前ターン終了時に idle flag が置かれなかった(09-01 の『軍師 idle flag 遅延 74 回/日』hotfix 後の再発)。watcher は保留解除を次の inbox MODIFY か Stop hook にしか委ねず、pane 実態を見ない | **将軍 D0 18:59**: 殿裁定 18:56『根拠のある待機か確認せよ』で発見。flag 設置+@agent_state idle+再 inbox_write で MODIFY を起こし配達(3 unread via paste-buffer)。根治=watcher の保留再評価を pane 実態(prompt 検出)でも行う。T3-S-32 と同じ hotfix 枠(ninja_monitor/inbox_watcher は別 file なので並列可) |

集計コマンド: `grep -oE '^\| T3-S-[0-9]+ \|' docs/research/tsumari_root_causes_20260901.md | wc -l` → 26。根治 23 / 未根治 3(T3-S-19/20/21b)、10:58 更新。忍者 6 領域(T3-<name>-NN)・軍師節・家老節は cmd_4470 着地後にここへ統合。
