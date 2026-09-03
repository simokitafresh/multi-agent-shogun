# tsumari 第 3 回・家老節(配備・merge・checkpoint・hotfix の視点)

- 書き手: 家老(karo)
- 窓: 2026-09-03T04:37(PUBLISHER_SINGLE flag ON)〜11:25
- 一次証拠: 家老 session の実行結果(掲示板 blt_20260903_091357/091751/094337/100909/102615/112139、inbox msg_id、git log origin/main、publish_queue/events.jsonl)。推測語なし。
- 分類: 偽陽性 / 過剰 BLOCK / 構造バグ / 循環拘束 / 遅い script・test / Claude↔Codex 仕組み差 / サンクコスト過剰複雑化 / 影響範囲・依存未解明の浅い対応

## 抽出コマンドと件数

| 対象 | コマンド | 件数 |
|---|---|---|
| D012 isolated merge(karo lane) | `git log --since=2026-09-03T04:37 --format=%s origin/main \| grep -c 'c2a-merge\|merge .* (karo lane'` | 6(c12d3be7d, 84720014e, ecc579dbb, a1b74df38, 11c36a9a9 + 0812 の lock-run merge) |
| 台帳 checkpoint(U1b) | `git log --since=2026-09-03T04:37 --author=karo --format=%s origin/main \| grep -c 'checkpoint'` | 10(adfe68672, 65f52c33a, bd3cf9ecd, 30da3c27b, 8c32989d1 期, 11b85dc89, f3e301039, 9875c365a, df31b9da7 ほか) |
| karo-direct hotfix 配備 | `ls queue/gates \| grep -c cmd_karo_hotfix_.*20260903` | 9(publisher_single_flag_file, run_tests_task_mode, lp_showcase, root_drain, worktree_reclaim, ci_fix publisher_single_flag, x_post_gate_blocklist, reflux_ledger_resolve_op, 他) |
| 家老 D0 修正 commit | `git log --since=2026-09-03T04:37 --format=%s origin/main \| grep -cE 'gate_gunshi_report_precheck\|insight_write\|bulletin_write\|publish_artifact\|ninja_monitor: PUBLISHER\|skill_gate_feedback\|publisher_c2a_merge'` | 8 |
| CI RED(家老起因) | `gh run list --workflow test.yml --status failure --limit 20` の sha 506e77b6e | 1(run 33695410178) |

## 事例表

| ID | 時刻 | 事象 | 主分類 | 副分類 | 真因 | 根治 | 次の一手 |
|---|---|---|---|---|---|---|---|
| T3-K-01 | 09:10-09:15 | reflux dirty dispatch blocked(insights.yaml dirty)で疾風 reflux が配備不能。root behind 1 で U1b ff-only rc=8 | 構造バグ | 循環拘束 | root writer(semantic_index_update の INS status resolve)が root を汚し、publisher ledger batch が同 file を変える。root sync は ff-only fail-close(将軍 08:22 裁定) | 未根治(4468 は index.md のみ ledger 化、INS status 書換えは root 残存) | 4468 AC1(b) の残り=INS status 書換えを ledger resolve op へ(insight_resolve.sh 既存)。着地まで家老が patch 退避→ff→再適用→U1b で周期 checkpoint |
| T3-K-02 | 09:15 | bulletin_board.yaml が worktree 30 件 vs HEAD 66 件(wt_only 0/head_only 36)で恒久乖離 | 構造バグ | 影響範囲未解明 | bulletin_write.sh:619 が entries>50 で bulletin_archive --max-keep 30 を root で実行(publisher が commit する HEAD と食い違う)。ninja_monitor の時間 archive も同型 | 根治済(65f52c33a, f15d754b5: flag ON では trim skip) | archive 自体を ledger op にする(4468 AC1(c) の bulletin_archive 分が未着地) |
| T3-K-03 | 09:20 | gate_skill_script_refs が FOLLOWUP_QUEUE_WARN『entry must contain id, cmd_id…』で 1 セッション連続 ALERT | 構造バグ | 偽陽性 | insight_write.sh が SKIP/AGGREGATE 経路でも空 entry file を ledger_append し ledger_writer が die | 根治済(5f1a13a44) | ledger_writer 側でも空 entry を no-op にする二重防御は不要(呼出し側で閉じた) |
| T3-K-04 | 09:17-09:25 | publisher『missing artifact』で kotaro 0912 が C2a 前に RC。hanzo 0740/saizo 0754 も同型 | 構造バグ | Claude↔Codex 仕組み差 | ninja_monitor lifecycle worker が子に SHOGUN_STATE_DIR=/tmp を渡し、capture が /tmp/publish_queue/artifacts に書く一方 request/publisher は ~/.local/share を見る | 根治済(30da3c27b: bare /tmp は永続既定へ)。ただし 11:19 hanzo 1044 で再発(再 capture・再 enqueue で回収、再現条件を追跡中) | publish_artifact.sh の state dir 解決を publisher_queue.sh と同一関数に統合(lib 化) |
| T3-K-05 | 09:25-10:40 | reflux insight task の C2a base_blob_mismatch(queue/insights.yaml)が 0812/0912/0920/1014 の 4 連続 | 構造バグ | 循環拘束 | reflux が台帳 file を直編集して commit、artifact base と tip の間で ledger batch が同 file を変更 | 根治=hotfix cmd_karo_hotfix_reflux_ledger_resolve_op_202609031005 CLEAR(10:58)。回収は isolated clone 3-way→script 化(publisher_c2a_merge.sh 3d03a2f2c、trailer 固定) | 着地後の reflux で C2a RC 0 件を events.jsonl で確認(fp_measurement) |
| T3-K-06 | 09:33-09:44 | CI RED run 33695410178: test_publisher_single_flag test1/5 が SKIP echo 行数 -eq 2 を期待 | 構造バグ | 影響範囲未解明 | 家老 D0(c9c92254a/d4da5a26d)が push_task_repositories の SKIP echo 回数を変えたが既存 bats を回さなかった(家老は bats 実行禁止=karo-retest guard) | 根治済(才蔵 ci_fix、86c033bdc、GATE CLEAR 09:44) | 家老 D0 は commit 前に pre-push affected tests を頼る。gate script 変更は忍者 hotfix へ回す |
| T3-K-07 | 10:06-10:14 | cmd_4469 レビューで SG-PRE35 ERROR『test_necessity path is not an actual new test』 | 偽陽性 | 構造バグ | precheck が shared HEAD に既存の test(in-file 宣言あり)を新規 test 契約の validate_entries に混ぜる | 根治済(9d6050e04) | precheck の全 SG-PRE で『shared HEAD 不在=worktree commit』を report commit 基準で読む方針を統一(SG-PRE3 は 0be5e10f3 で済) |
| T3-K-08 | 09:52-10:38 | cmd_4467 x_post_gate 規則 1 が公開 showcase 由来 blocklist で非公開 PF holding を検知できず、空でも PASS | 影響範囲・依存未解明の浅い対応 | 構造バグ | cmd 設計が公開 API 前提、fail-close 未定義 | 根治済(hotfix x_post_gate_blocklist_fail_close、GATE CLEAR 10:38) | P1(投稿)前に本番 API で Basic PASS/非 Basic FAIL を毎回計測 |
| T3-K-09 | 10:47-11:10 | 家老 U1b の push が『origin が先に進んだ』で 3 回失敗(rc=8/ref lock)、将軍 U1b も同型で root ahead 2/behind 4 | 循環拘束 | 構造バグ | U1b は fetch→ff→commit→push を lock 内で行うが lock 外で origin が進む(publisher batch が数分おき) | 未根治(将軍 11:07 hotfix 列: U1b 失敗時に publisher_c2a_merge を自動再試行) | publish_direct_commit.sh の push 失敗分岐で publisher_c2a_merge.sh を 1 回呼ぶ |
| T3-K-10 | 11:07-11:09 | recon2(--yaml 配備)の小太郎/飛猿が shared root に直 commit(root ahead 2) | 構造バグ | 影響範囲未解明 | karo-direct --yaml 配備は task_worktree_required を持たず、ninja_scope_commit が root で commit する | 部分根治(a/f は task_worktree_required: true で配備。既発 2 commit は 11c36a9a9 で統合) | deploy_task.sh が --yaml 配備にも task_worktree を既定で切る(hotfix 列) |
| T3-K-11 | 11:16-11:18 | 才蔵 b/疾風 e の report が verdict FAIL(AC3『未解消条件があれば BLOCK 報告』を忠実に実行) | 過剰 BLOCK | 偽陽性 | 家老の AC3 文言が『BLOCK 報告=FAIL』を誘発(偵察成果は完了) | fail-close ACCEPT で解放、note は origin 到達 | 偵察 task の AC3 は『未解消条件を列挙したか(yes/no)』の二値に直す(karo-direct テンプレ) |
| T3-K-12 | 04:37-11:25 | 台帳 checkpoint(U1b)を家老が 10 回、D012 isolated merge を 6 回手で回した | サンクコスト過剰複雑化 | 循環拘束 | root 直書き生産者が 7 種残り(semantic_index INS status、rework auto capture、lessons last_synced、cmd-chronicle/senkyoku、gunshi_review_log、compact_state、shogun_to_karo)、root sync が ff-only | 未根治(U9 production_proof: sample1 dirty=7、sample2 dirty=8) | 残 7 種を ledger op か『root 非 tracked』へ寄せる cmd。dirty 0 になるまで checkpoint は周期作業 |

## 集計

| 主分類 | 件数 |
|---|---|
| 構造バグ | 7 |
| 偽陽性 | 1 |
| 過剰 BLOCK | 1 |
| 循環拘束 | 2 |
| 影響範囲・依存未解明の浅い対応 | 1 |
| サンクコスト過剰複雑化 | 1(T3-K-12) |
| 遅い script・test | 0 |
| Claude↔Codex 仕組み差 | 0(副分類で 1) |

根治済 6 / 部分根治 1 / 未根治 5(T3-K-01, 04 再発分, 09, 10 恒久策, 12)。
