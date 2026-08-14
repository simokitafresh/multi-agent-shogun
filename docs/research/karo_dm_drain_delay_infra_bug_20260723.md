# DM drain遅延・インフラバグ疑義調査（2026-07-23）

- 調査者: karo
- 観測区間: 2026-07-22 23:37〜2026-07-23 00:49 JST
- 対象: page-style MECE後半軸、cmd_4122、LG043偽陽性修正、cmd_4123配備
- origin: `[[殿指示_この作業で時間がかかった原因を利他調査]] -> [[DM_drain_遅延]] -> [[インフラバグ候補]]`

## 結論

遅延は忍者の実装速度だけではない。支配項は、同一HEADに対するSG7後CI再要求、report再レビューの世代を識別しないdedupe、実報告全量をリプレイしないgate fixture、誤idle/stale通知、30秒級context freshness timeout、28〜70秒のdeploy制御面、3.6〜34.8秒のdashboard完了tailである。

## 実測

| 項目 | 実測 | 一次証跡 |
|---|---:|---|
| 完了済みDM-Signal CI | 431秒 + 424秒 = 855秒（14分15秒） | GitHub Actions run `29931375970`, `29932638136` の startedAt→updatedAt |
| 追加CI | run `29935006296` 実行中 | G/IのSG7が前CI後に生成され `workflow run predates SG7 review` BLOCK |
| deploy制御面4回 | 28.158 + 31.866 + 37.250 + 69.565 = 166.839秒 | 各 `DEPLOY_RECEIPT wall_ms`（L、LG043初回、cmd_4123、LG043追補） |
| 5 cmdのdashboard tail | 3.577, 34.754, 4.765, 6.316, 18.893秒、合計68.305秒 | 各 `completion_tail.log` の `PASS dashboard ... wall_ms` |
| context freshness timeout | 対象6 cmd中4 cmdで発生 | 各 `cmd_complete_gate.trigger.log` の `context_freshness own-commit check timeout/error` |
| CI predates BLOCK | G/Iの2 cmd | 各 gate trigger log |
| LG043手戻り | 初回contract 11/11 PASS後もL実報告をBLOCK | L実文=`未確認0`、初回fixture=`未確認0を確認` |

## 確定バグ／強い疑義

### P0-1 ninja_monitorの誤idle判定（確定）

`ninja_idle`通知自身のpane証拠が `hayate • Working (1m 47s) · 1 background` なのに、本文は `idle(新規)` と判定した。active task上書き・二重配備を誘発し得るため速度だけでなく正しさのバグ。paneのworking/busyをidle分類より優先する二値契約が必要。

### P0-2 意図的deferを認識しないstale_cmd反復（確定）

cmd_4121は殿指示で意図的pending/deferredだが、`cmd_4121が5時間pending` が少なくとも00:07と00:48の2回届いた。defer理由・再開条件・通知済み世代をstale判定が参照していない。

### P0-3 report再レビューdedupeが世代を識別しない（確定）

LG043修正後にG/I/Lへ同じ `report_review` を送ると、過去メッセージと同一扱いで `pending duplicate suppressed` となり再レビューが起動しなかった。`verify_request`へtypeを変えて初めて配送された。dedupe keyへ `review_generation` / gate engine commit / prior verdict fingerprintを含めるべき。

### P0-4 gate修正が実報告コーパスを全量リプレイしない（確定）

初回LG043修正はfixture 7→11全PASSでも、L報告の実文 `未確認0` を再現せず、`未確認0を確認` のみを固定した。結果、G/Iは直ったがLだけ再BLOCKし追補hotfixが必要になった。修正対象となった全report pathを回帰コーパスへそのまま流す契約が必要。

### P1-1 SG7時刻とCI鮮度の結合が同一HEADへ全量CIを再要求（強い疑義）

run `29932638136` はHEAD `ace6d961...`でGREENだったが、G/Iのreport-only再レビューが後刻だったため同じHEADにrun `29935006296`を再要求した。コード不変のreport-only再レビューでは、`code_head_sha + implementation_review_fingerprint`を鮮度正本にし、報告文のみのSG7時刻で7分CIを無効化しない設計を検討すべき。

### P1-2 context freshness timeoutが遅く、かつfail-open（強い疑義）

6 cmd中4 cmdでtimeout/error後にBLOCKをskipした。待ち時間を払いながら防御も成立しない最悪の組合せ。検索対象をcommit listで有界化し、結果cache化、timeout時は別workerへ非同期化して最終checkpointで確定させるべき。

### P1-3 deploy制御面が短時間hotfixに対して重い（確定）

5分見積のLG043追補deployが69.565秒。内訳はpreflight 11.349秒、task_mutations 44.232秒（report publication 11.312秒を含む）。同一2ファイル・同一projectの追補でもlesson/semantic/report生成をフル再実行している。generation-aware cacheと同系統follow-up fast pathが必要。

### P1-4 cmd_complete dashboard tailの分散が大きい（確定）

5回合計68.305秒、最遅Jは34.754秒で最速Hの9.7倍。Jではsnapshot refresh WARNも発生。dashboardは完了判定後の派生物なので、正本更新と表示再生成を分離し、single-flight非同期workerへ寄せる候補。

### P2-1 direct cmdのstatus lookupノイズ（確定）

direct recon/hotfixのcmd-completeで `not found in shogun_to_karo.yaml` を毎回ERROR表示しつつnon-blocking PASSする。既知正常系をERROR扱いするため真の異常を埋める。direct/archived証跡を先に識別してSKIPへ分類すべき。

### P2-2 inbox unread数と実体の競合（疑義）

注入contextが未読1を示す一方、直後の実YAMLは0件だった事例が複数あった。archiveとsnapshot間の世代差が疑われる。unread countへsource mtime/generationを付けるべき。

## 優先修正案

1. `ninja_monitor`: pane working/busy証拠が1件でもあればidle通知0件にするcontract。
2. inbox dedupe: `report_id + report_fingerprint + engine_commit + review_generation`をkey化。
3. gate修正テンプレート: 対象となった全production reportをfixtureへ直接入力し、FP 0/全TP維持を強制。
4. CI freshness: report-only SG7とimplementation reviewを分離し、同一code HEADのGREEN再利用を許可。
5. context freshness/deploy/dashboardを各々phase_ms計測し、P95 ratchetを設定。
6. stale_cmd: `deferred_until` / `defer_reason` / `notify_generation`を正本フィールド化。

## 二値完了条件

- 誤idle再現1→0、working paneへのidle通知0件。
- 意図的defer cmdの反復stale通知2→0。
- engine更新後の同report再レビューがtype変更なしで1回配送される。
- G/I/L実報告コーパス全3件がLG043 CLEAR、真陽性4系統はBLOCK。
- 同一HEAD report-only再レビュー後の追加CI回数1→0。
- context freshness timeout 4/6→0/6。
- 5分hotfix deploy 69.565秒→P95 20秒以下、dashboard tail P95 34.754秒→10秒以下。

## 01:17〜01:31 追加追跡 — 複数忍者で同型再現

| 軸/処理 | 実作業 | 全体/後処理 | 構造遅延率 | 一次証拠 |
|---|---:|---:|---:|---|
| L軸 | 256秒 | 全体4,121秒、作業後3,865秒 | 93.8% | deploy/report/gate/skill logs |
| I軸 | commitまで305秒 | 全体1,727秒、commit後1,422秒 | 82.4% | task session attempt=8、commit `08413f20` |
| G軸 | 約8分 | CLEARまで102分 | 約92% | report gate 11回（FAIL 8/PASS 3） |
| F軸 | 配備後535秒 | target/reflux/receipt/lockで反復 | — | GA-220、receipt、commit lock 15.220秒 |
| cmd_4124 | 実装・境界7/7・commit完了 | JestがDrvFs D-state 8分51秒以上、別runnerもadmission待ち8分超 | — | `p9_client_rpc`、`locks_lock_inode_wait` |

### P0-5 inspection scopeとcommit scopeの型混同（4忍者で再現）

F/G/Iで、読取監査範囲`target_path=frontend`と成果物`planned_paths=docs/research`が混在し、正しいdocs commitを「target_path履歴なし」で3〜7回反復BLOCKした。`deploy_task.sh`がcommit契約へtarget pathを流し、gateのPython実装とshell実装も判定が不一致。個人ミスではなく生成契約のSSOT不整合である。

### P0-6 completion/review event非直結と同一FAIL増幅

Lはreport gate PASSからreview済completion nudgeまで62分06秒。Gでは同一report gateが11回、同じtarget false BLOCKが7連続。`report fingerprint + task generation + FAIL reason`が不変でも再実行される一方、terminal事実がreview/completion producerへ直結していない。

### P0-7 dashboard並列完了の排他設計不成立

G/I/Lの3並列`cmd_complete`で、Gはattempt 3成功23.285秒、Iはattempt 1成功33.902秒、Lは3回全失敗52.120秒後、再実行17.910秒で成功した。`dashboard_update.sh`のlock待ちは10秒だが更新critical section自体が17〜34秒のため、正しい並列呼出しが構造的にtimeoutする。

### P0-8 DrvFs test hangとheavy admissionの無期限待機

cmd_4124のJestは`STAT=Dl/WCHAN=p9_client_rpc`で8分51秒以上無出力。正規runnerにhang上限・receipt・ext4 fallbackがない。別`run_tests task`もsingle-flight leader表示後に`flock -w 3600`へ入り、owner/queue age/heartbeatなしで8分超待機した。実行開始表示とadmission取得順序も逆で、観測者が「実行中」と誤認する。

### P1-5 task/report契約の非原子的更新

cmd_4124はtask ACを最新裁定へ更新しても、report templateの`ac_version_read`、binary checks、planned pathsが旧値のまま残った。task更新とreport契約再生成が同一transactionでないため、正しい実装でもgate矛盾を作る。

### P1-6 private indexとreflux guardの循環

`ninja_scope_commit`はprivate indexへaddするが、GA-220 prepareはshared indexのstaged docsを要求する。正規helperだけではprepare不能となる循環をF/G/cmd_4124で再現。reflux prepareをprivate-index transaction内へ統合すべきである。

## 即時修繕配備（karo-direct、4並列）

| 忍者 | 修繕cmd | 対象 |
|---|---|---|
| 影丸 | `cmd_karo_hotfix_recon_scope_contract_20260723` | inspection/owned path型分離、gate SSOT |
| 半蔵 | `cmd_karo_hotfix_completion_event_dedupe_20260723` | event直結、同一FAIL dedupe |
| 小太郎 | `cmd_karo_hotfix_dashboard_completion_singleflight_20260723` | dashboard single-flight/待機queue |
| 斎蔵 | `cmd_karo_hotfix_test_runner_drvfs_admission_20260723` | D-state timeout/receipt/ext4 fallback、admission可観測化 |

4件ともtask/report原子公開とnudge到達を確認し、各ペインで作業開始を目視した。なお配備自体も並列で90〜151秒を要し、preflight 27〜77秒、task mutation 61〜68秒が支配したため、既報のdeploy制御面遅延を再確認した。
