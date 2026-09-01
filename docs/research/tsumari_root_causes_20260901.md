<!-- gist-master: 0471675066394649c8e5f9bfabd2e048 tsumari_root_causes_20260901.md -->
# 便を止める「つまり」の原因分類 2026-09-01（第22便 17:17〜22:15、全ロール探索・将軍統合）

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
