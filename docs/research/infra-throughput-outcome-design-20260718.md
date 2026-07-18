# Infra Throughput Outcome Design — 2026-07-18

status: design-complete / implementation-paused  
owner: karo + shogun consultation  
scope: 2026-07-18の忍者インフラ報告、decision_candidate、家老一次観測  
existing lifecycle SSOT: `docs/research/infra-throughput-mece-20260717.md`

## 1. 結論

品質合格スループットを「固定品質で合格した成果数 / 壁時計時間」とする。個別スクリプトの局所速度ではなく、成果が `input → task → execution → report → gate → done` を通過する全体時間を最適化する。

将軍初案の5分類はMECEではなかった。C3とC4が通知を重複所有し、deploy/task transactionとtarget/global readinessの受け皿が無かったため、以下6分類へ補正する。

分類規則は一つだけである。

> 最初に破れた不変量をprimary categoryにする。遅延・9P・通知などの下流影響はtagに留め、二重計上しない。

## 2. MECE 6分類

| ID | カテゴリ | 所有する境界 | 所有しないもの |
|---|---|---|---|
| C1 | Storage/worktree substrate | 9P、Git metadata、index/object、worktree registry、scope外materialize | session identity、task遷移 |
| C2 | Lord input identity/routing | prompt生成、turn identity、意図paneへのexactly-once到達 | 作成後の内部通知 |
| C3 | Internal event transport | 作成済みeventのdedup、priority、outbox、配送、hook | task/reportの状態遷移 |
| C4 | Cmd/task/report lifecycle transaction | deploy、task mutation、report、review child、gate、AUTO_DONE | reflux候補選択、CI状態の意味 |
| C5 | Knowledge reflux lifecycle | lesson/insight/promotionの予約、昇格、defer、消化 | 一般report state machine |
| C6 | Verification/readiness semantics | target checkとglobal workflow、fixture安全、判定型 | test実行時間そのもの |

既存7段階ライフサイクルは時系列SSOTとして維持する。本書のC1〜C6はカテゴリ集中攻略の責任境界であり、両者を置換しない。

## 3. 全報告の一意root issue台帳

集計: 26件。修正済9、部分修正4、未修正13。残件あり17。  
内訳: 忍者報告root 22件 + 家老が報告横断で分離した4件（session contract、deploy再入、review child retry、target/global semantics）。

### C1 Storage/worktree substrate — 5件

| ID | 状態 | root issue | 一次値 / 修正 |
|---|---|---|---|
| C1-01 | 部分修正 | `/mnt/c` git commit全index lstat/D-state | total 82.173s、pre-hook前73.245s、1925 tracked中1923 lstat。auto-maintenance約3分→0は`c909aa605`、全index refresh残存 |
| C1-02 | 未修正 | full worktree addの9P hydrationとregistry肥大 | checkout約180s、直後D約1900/??22、worktree 81、prunable 28、list 7.77s、status 7.25s |
| C1-03 | 部分修正 | scope commit rc0とHEAD/diff/receiptの収束race | single-flight系`5f63ad8eb`等の後もrc0・hashなし・HEAD旧・diff残存を再観測。親processのdurable再検証なし |
| C1-04 | 修正済 | context freshness旧cache schemaが複数git log timeout | `55a5e330`、65/65。shadow 10回p95 1.276〜3.445s |
| C1-05 | 部分修正 | deploy 150〜305sの共有I/O/control-plane | `a9647608f`,`b8583338f`,`fb619776a`。直近receipt 74.191s、目標未達。live cold/warm 3+3未完了 |

### C2 Lord input identity/routing — 2件

| ID | 状態 | root issue | 一次値 / 修正 |
|---|---|---|---|
| C2-01 | 修正済 | cross-pane routeとretry/replay identity | `61415c7af`でCodex turn_id採用。全9pane arm、実入力1、invocation_total 1、wrong-pane 0 |
| C2-02 | 未修正 | one-shot auditが外部UserPromptを3波要求 | 外部入力待ち742s、audit flow 946s。共通turn ledger/daemon未実装 |

### C3 Internal event transport — 2件

| ID | 状態 | root issue | 一次値 / 修正 |
|---|---|---|---|
| C3-01 | 修正済 | watcher lease/priorityと同一集合通知dedup | `e42ffe0c1`,`b58658756`。同一failed/stall集合の副作用1回 |
| C3-02 | 修正済 | precommit hook固定費とtruthful receipt不足 | `ca2060c28`,`29315534d`,`89fa5a3bb`。影丸実測precommit 3.914s |

### C4 Cmd/task/report lifecycle transaction — 9件

| ID | 状態 | root issue | 一次値 / 修正 |
|---|---|---|---|
| C4-01 | 修正済 | canonical report IDとevent retry exactly-once | `3a305a0f5`〜`1b6df4e4c`。20並列stored 1/duplicate 0、82/82 |
| C4-02 | 修正済 | report_notification_missing FP/stale identity | FP 2→0。世代/fingerprint照合を追加 |
| C4-03 | 修正済 | no-code/report commit contract偽BLOCK | `e7ab41112`,`73e12f31e`,`eb378791f`。41/41、FP0/FN0 |
| C4-04 | 修正済 | revision batchの非原子的更新とpush境界 | remote `2141270ae`、1commit/1path、対象8/8、差分0 |
| C4-05 | 未修正 | report→gate固定費 | commit→gate 212s、commit→report/gate 133s。outcome <60s未達 |
| C4-06 | 未修正 | exec session_id喪失で未完了processを完了扱い | worktree addのsession未回収1件、後続Git writeが未完成indexへ衝突 |
| C4-07 | 未修正 | awaiting evidenceをSTALL/pending report gateし、PASS→AUTO_DONEが遅い | pending gate誤実行、false STALL、PASS→AUTO_DONE 679s |
| C4-08 | 未修正 | direct deployのroot/nested境界と同一deploy再入でtask mutationが二重実行 | `hayate.yaml`再入parse FAILに加え、CI修正配備でroot形式sourceへnested注入し`saizo.yaml` parse FAILを再現。nested source再投入で復旧したが構造境界は未修正 |
| C4-09 | 未修正 | report parent保存後のreview child自動retryがない | manual same-event retryでchild 0→1→1。通常経路のrepair trigger 0/1 |

### C5 Knowledge reflux lifecycle — 6件

| ID | 状態 | root issue | 一次値 / 修正 |
|---|---|---|---|
| C5-01 | 未修正 | source/generated cache foreign dirtyによる反復BLOCK | L900〜L885群とL901。source +1151行、cache 123行級。deferはするが所有差分未収束 |
| C5-02 | 未修正 | old-generation supplement混入と候補世代不整合 | fingerprint抑止のみ。generation正本化commitなし |
| C5-03 | 未修正 | karo_direct refluxのcmd spec不在でformal approval不能 | 軍師がanalysis_resultへ退避。approval marker/SG7を自動生成できない |
| C5-04 | 部分修正 | 同一lessonの反復dispatch | L901は6忍者へ連続配備。`3d4d670f`を既存dirtyと分離適用した`a7e7f42c`は10/10・並列4 dispatch1・terminal再配備0だが、global CI GREEN待ちでorigin/main未統合 |
| C5-05 | 修正済 | 既存enforcement metadataのatomic writer欠落 | `e852b3edc`で`lesson_write --promote`追加。foreign dirty自体はC5-01 |
| C5-06 | 未修正 | 候補が実際にはLevel4/5未到達 | L891/L875等。偽昇格せずdecision backlog化したが実防御未実装 |

### C6 Verification/readiness semantics — 2件

| ID | 状態 | root issue | 一次値 / 修正 |
|---|---|---|---|
| C6-01 | 未修正 | test fixture symlink write-through | tracked実sourceを2行へ上書き1件。diff復旧のみ、pre-test symlink BLOCKなし |
| C6-02 | 未修正 | target GREENとglobal workflow GREENの混同 | target 8/8 PASS後、global CI 390sで別test FAIL。別field/型なし |

## 4. カテゴリ別アウトカム

計測窓はrolling 7日間の全イベントとする。単発値をp50/p95と呼ばない。母数、source timestamp、対象集合を必須記録する。

| ID | 二値PASS条件 | 2026-07-18 baseline | 目標 | 計測source |
|---|---|---|---|---|
| C1 | latency閾値、scope逸脱0、stale registry 0 | commit n=1:82.173s、prehook73.245s。deploy直近n=1:74.191s。registry81/stale28 | deploy p50<30s/p95<60s、commit p50<10s/p95<20s、scope逸脱0、stale0 | `logs/deploy_task.log`、scope receipt、Trace2、worktree dry-run |
| C2 | 各turn_idが意図paneへexactly once | wrong-pane既往1、外部入力待ち742s | replay/drop/wrong-pane 0、外部追加入力0 | prompt ledger、hook pane、intended pane |
| C3 | 作成済eventのdrop/重複/priority inversion 0 | 制御面CTX 86%、exactness母数未計装 | 3指標0、delivery p95<5s、CTX<20% | inbox/outbox ledger、event_id→effect ledger |
| C4 | identity保持、atomic、再入安全、eventual completion | session喪失1、再入破損1、AUTO_DONE679s、child repair trigger0/1 | identity100%、破損0、AUTO_DONE p95<5s、child repair100%、report→gate p95<60s | deploy transaction ledger、task revision、report/gate timestamps |
| C5 | 候補が一度だけ予約されterminalへ遷移 | L901重複6忍者、promotion在庫198〜200、週次率未計測 | duplicate0、reservation conflict0、foreign-dirty再投入0、週次消化率>50% | reservation/completion/deferred ledger |
| C6 | target/globalを別型で保持しfixture破壊0 | conflation1、symlink破壊1 | conflation0、両field欠落0、head SHA mismatch0、fixture破壊0 | GitHub job/workflow、gate decision ledger、pre-test guard |

横断品質条件は `FAIL=0 / SKIP=0 / FP=0 / FN=0 / duplicate=0 / 通知喪失=0 / 安全境界低下=0`。速度目標だけでPASSにしない。

## 5. 集中攻略順序

カテゴリを混ぜず、各waveのoutcomeが満たされてから次へ進む。

1. C4 transaction closure: session保持、deploy再入排他、event-driven AUTO_DONE、child repair trigger。
2. C1 substrate: ext4 gitdir/worktree/commit-tree比較、full worktree廃止、registry収束。
3. C5 reflux: `a7e7f42c`をglobal CI GREENでorigin/mainへ統合、formal review direct spec、foreign dirty所有差分収束。
4. C6 semantics: target/global型分離、symlink fixture guard。
5. C2/C3: one-input-one-waveと全event outcome計装。

各waveで途中の可逆試行回数を最大化し、最終checkpointでのみ全契約・敵対試験・レビューを一度通す。

## 6. 停止時点

本書作成後は殿の指示どおり新規実装・追加配備を停止する。進行中成果は以下の状態で凍結する。

- `a7e7f42c`: `3d4d670f`の原子reservationを既存dirtyと分離統合。家老独立10/10 PASS、global CI GREEN待ちでorigin/main未統合。C5-04=部分修正。
- `eb378791f`: 41/41 PASS、GATE CLEAR、完了処理済み。
- L901 6回目配備: 即時停止・変更0件を確認。以後は`a7e7f42c`の原子reservation契約で再配備0を検証する。
- 設計再開時はWave 1(C4)から開始し、個別hotfixを先行させない。

## 7. 一次証跡

- `archive/inbox/karo_20260718.yaml:469,608,615,622,677,823,988,1001,1008`
- `queue/bulletin_board.yaml:367`
- `queue/reports/hayate_report_cmd_karo_hotfix_reflux_lesson_reservation_202607181221.yaml`
- `queue/reports/kotaro_report_cmd_karo_ci_fix_29628061796_deploy_template_commit_contract_202607181216.yaml`
- `queue/reports/kagemaru_report_cmd_karo_hotfix_prompt_event_identity_replay_202607181120.yaml`
- `queue/reports/hanzo_report_cmd_karo_hotfix_deploy_305s_control_plane_202607181110.yaml`

## 因果リンク

- `[[L901_6重配備]] -> [[非原子reservation]] -> [[atomic_promotion_reservation]]`

- `[[殿指示_MECE_throughput_design]] -> [[近視眼的hotfix]] -> [[カテゴリ集中+アウトカム計測]]`
- `[[品質合格スループット]] -> [[最初に破れた不変量]] -> [[C1-C6集中攻略]]`
