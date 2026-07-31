# 隠れたインフラバグ・Gate/Hook品質 修正設計書

- 作成日: 2026-07-30
- 作成者: 家老
- 覚醒更新: 2026-07-31
- 更新者: 将軍
- 版: v2.2 Gate 0A contract revision 3
- 基準commit: `48048e465322753420b808584d13bbdf3190f965`
- 再基線候補commit: `55b3df6d4`（2026-07-31 18:25 JST時点。実装開始前に再取得必須）
- repository observed HEAD: `f3478e625235b364a187d7c2f6412a78d8add4c7`
- code baseline: `55b3df6d4d937c7683ef1ca9a83393760d593e47`
- HEAD drift: 2/2はcontextのみ（`context/lord-conversation-index.md`, `context/semantic-map.md`）、caller影響0/2
- 対象: `multi-agent-shogun` の制御面、gate、hook、配備、完了、CI、知識還流
- 状態: Gate 0A contract authoring revision 3 — Wave 0 probe開始前
- canonical manifest: `docs/research/hidden-infrastructure-gate-hook-canonical-manifest-20260731.yaml`

## 0. 結論

### 0.1 v2.0の判定

**方向は正しいが、v1.0のまま実装開始してはならない。**

理由は、基準commit以後にhotfix・台帳修正・test高速化が継続し、発見事項の一部が
すでに変化している可能性があること、またv1.0の共通primitive設計自体に以下の
未定義境界があったことである。

1. 複数ファイルmutationを「1 transaction」と呼ぶが、write-ahead journal、
   generation、再起動時reconciliationが未定義。
2. 異常終了時の「自動復元」はprocessが死んだ瞬間には実行できない。次回起動時の
   recovery ownerと収束規則が必要。
3. 非同期jobの再駆動は、dashboard・通知・archive等の副作用にidempotency keyが
   なければ二重実行を生む。
4. 共通primitiveへの一括置換は、primitive自身を新しい単一点障害にする。
   shadow判定→差分計測→caller単位切替→旧経路撤去の移行契約が必要。
5. FP=0/FN=0はfixture母集団が未定義なら品質証明にならない。

よって最初の実装単位は修正Waveではなく、**Gate 0: 現HEAD再基線化と状態機械の
固定**とする。旧R/V番号は履歴IDとして保持し、現HEADで再現したものだけを
`OPEN_CONFIRMED`へ昇格する。

### 0.2 採用する上位原理

- 状態は文字列やmarkerの存在ではなく、`subject_id + generation + phase +
  terminal_receipt`で識別する。
- 複数ファイル変更は原子的とは称さない。WALにintentを先記録し、各stepを冪等化し、
  crash後のreconcilerが必ず旧状態または新状態のどちらかへ収束させる。
- receiptは「processが起動した」「親がexit 0」ではなく、対象generationの成果物hash、
  side-effect ledger、terminal phaseを含む。
- retry可能な副作用は全て同一idempotency keyでexactly-once相当に収束させる。
- 新primitiveは旧経路とshadow比較し、差分0を確認したcallerから段階移行する。
- 防御を強くするだけでなく、通常経路のwall time・lock wait・失敗回復時間を計測し、
  品質改善がスループットを破壊していないことを確認する。

### 0.3 元監査の分類

本監査は「怪しいコード」を列挙するのではなく、次の3区分へ分ける。

1. **再現済み欠陥**: 隔離probeで現行挙動が二値FAIL。修正waveへ入れる。
2. **構造リスク**: 現時点で事故未再現だが、単一点障害・責務重複・観測欠落がある。追加probeを先に作る。
3. **正当な防御/観測ノイズ**: BLOCKや警告は多いが設計どおり。削除せず、上流で発火原因を消す。

6忍者の独立監査で17件を抽出し、うち再現済み13件、追加検証が必要4件へ分類した。
個別事故に見えるが、共通根因は次の4つである。

1. **identityの曖昧さ**: cmd ID部分一致、lock path二重実装、singleflight identity不一致。
2. **所有権移転の非原子性**: task source→target、review受付→dispatch、親→非同期tail。
3. **受付と完了の混同**: `AUTO_DEPLOY_OK`、marker、親process exit 0をterminal receiptとして扱う。
4. **SSOT分裂**: 永続contractとCI inventory、hook matcherと実装、手動知見と自動昇格条件。

したがって修正単位は各論hookの追加ではなく、共通primitiveの導入とcaller置換とする。

ただしcaller置換前に、§2.3の再基線化と§3.4の設計欠陥を閉じる。

## 1. 監査方法

### 1.1 独立6レーン

| レーン | 対象 | 主な問い |
|---|---|---|
| A | gate / hook | FP、FN、fail-open、exit code、責務重複 |
| B | inbox / watcher / lock | Lost Update、重複配送、prompt誤入力、無駄待機 |
| C | deploy / lifecycle | ghost、stale、再配備、auto-clear、状態乖離 |
| D | report / review / complete | 偽CLEAR、永久BLOCK、lock競合、非同期tail |
| E | tests / CI / quality metrics | focused漏れ、SKIP隠蔽、local/CI非対称、fixture汚染 |
| F | insight / lesson / memory / semantic | 未resolve、誤dedupe、三層未貫通、観測盲点 |

各レーンは兄弟報告を参照せず、固定commitと自作probeだけで検証する。

### 1.2 二値品質軸

各候補は以下を必須記録する。

- 再現: yes/no
- false positive: N/D
- false negative: N/D
- fail-open: yes/no
- 変更対象と行番号: あり/なし
- 波及先: 列挙済み/未列挙
- focused test: PASS/FAIL/SKIP
- Level 5以上の防御: あり/なし
- rollback: 自動/手動/不可

## 2. 横断ベースライン

### 2.1 直近gate BLOCK

直近2,000行内のBLOCKは166件。

| reason | 件数 | 比率 | 初期解釈 |
|---|---:|---:|---|
| `review_two_phase_pending` | 77 | 46.4% | 二段レビュー防御。発火タイミングと重複実行を監査 |
| `context_freshness_own_commit_unreflected` | 35 | 21.1% | 正当防御か、context境界の過検出かを監査 |
| `sg7_bundle_missing_or_invalid` | 14 | 8.4% | bundle生成/消費の原子性を監査 |
| CI関連 | 17 | 10.2% | local/remote identityと待機設計を監査 |
| その他 | 23 | 13.9% | 個別再現で分類 |

### 2.2 静的coverage

- gate scripts: 56本
- test files: 205本
- gate名と直接一致するtestが見つからないscript: 33本
- pending insights: 30件

名称不一致は未テストの証明ではない。caller経由の間接coverageを追跡してから欠陥判定する。

### 2.3 現HEADドリフト（2026-07-31覚醒再確認）

基準commit以後にも制御面の変更が入っている。少なくとも以下を確認した。

| commit | 現在設計への影響 |
|---|---|
| `aed5dfb9b` | active pointer一時ファイルraceを是正。R03-R05/V03の再現条件を変え得る |
| `35e2bd029` | terminal receipt rcをtotal化。R10の現状態を変え得る |
| `714d44816` | completion tailをsingle-flight化。R08の再現条件を変え得る |
| `7b050c825` | backlink scanの正本を統一しfail-close化。SSOT分裂クラスの実装例 |
| `2def66ea2` | Q6 latest-invalid fallbackを是正。matcher/最新状態クラスの実装例 |
| `55b3df6d4` | 軍師CS checklistのinline adversarial review受付を是正 |

したがって「再現済み13件」は基準commitでの事実であり、現HEADで13件OPENを意味しない。
各項目は次の状態機械へ移す。

```text
BASELINE_FINDING
  → REPRODUCED_AT_HEAD
  → OPEN_CONFIRMED
  → SHADOW_FIXED
  → MIGRATED
  → CLOSED_REMEASURED

BASELINE_FINDING
  → NOT_REPRODUCED_AT_HEAD
  → SUPERSEDED_WITH_EVIDENCE
```

`NOT_REPRODUCED_AT_HEAD`を「直った」と即断しない。修正commit、現行caller、同一入力の
三点が一致した場合だけ`SUPERSEDED_WITH_EVIDENCE`へ進める。

## 3. 発見事項

### 3.1 再現済み

| ID | 重大度 | 現象 | 根因・二値証跡 | 修正方針 |
|---|---|---|---|---|
| R01 | CRITICAL | inbox appendとmark-readが相互排他されず、未読が消失 | `inbox_write.sh`独自sanitize lockと`lock_path.sh`のDJB2 lockが別path。並行probeでLost Update 1/1 | lock path生成を共通lib一択にし、同一inboxのlock identity一致をcontract化 |
| R03 | HIGH | 同じtask IDがsource/target双方でactive | copy後にsourceをtombstone化せず2/2二重active | temp構築→target rename→source tombstoneを1 transactionにし、active count=1をcommit条件化 |
| R04 | HIGH | deploy失敗rc=7後もghost assignedが残る | rollbackがcaller公開状態を戻さない。2/2 | durable deploy receiptまでrollbackをarmedに保つ |
| R05 | HIGH | `in_progress` taskをauto-deploy対象へ再選択 | `status != done`というdenylist。1/1 | `pending/idle` allowlist、unknown statusはfail-close |
| R06 | HIGH | 完了判定が別cmdのCLEAR/dashboardを誤認 | `index($0,id)`/`grep -F`の部分一致。`cmd_12`が`cmd_123`を1/1誤認 | typed TSV列の完全一致と共通`correlated_clear` helper |
| R07 | HIGH | review dispatch即死後、永久に再試行不能 | durable dispatch前に`.done`/trigger marker公開 | pgrpまたはrc0 receipt確認後だけmarkerを原子的公開。失敗時は未公開 |
| R08 | HIGH | completion親exit0後、tail失敗が不可視で部分完了固定 | queuedとterminal completedを同一視 | durable completion job/receiptとsupervisor再駆動。状態をqueued/completedに分離 |
| R09 | HIGH | 永続contractの過半がpush CI未実行 | audit parserでは177中97欠落。軍師の別matcherではBats宣言数に+2差があり、母数parser自体も非SSOT。少なくとも97件の欠落は確認済み | `test_necessity`からrunner別inventoryを生成し、canonical parserでCI所属N/Nを強制 |
| R10 | HIGH | task/file並行時にterminal rcが競合 | 同一sampleのreceipt publicationとrc identity境界不一致。既存contract 1/1 FAIL | leader immutable rc sidecarを正本化し、joiner/issuerは同値だけ読む |
| R11 | HIGH | 手動投入aliasがsource policy前に自動昇格 | curated AC5知見を即時採用する意図で作られた例外が、provenanceなしで一般化 | 意図は維持し、署名済み`source_class=curated_manual`だけをallowlist。無署名手動入力はpending |
| R13 | MEDIUM | local test cacheがunstaged依存source変更後も古いPASSを再利用可能 | fingerprintがgit index objectのみ | dirty tracked sourceのworktree hashをcache keyへ追加 |
| R14 | MEDIUM | hook実装のWrite/Edit branchがmanifest上到達不能、単体rc=1 | trackerをRead matcherだけへ接続。combined hookはrc=2で防御維持 | combined hookを唯一owner化。manifest静的検証でbranch到達性とCodex exit 1を禁止 |
| R15 | MEDIUM | 運用ノイズをindex無変更でも`resolved`化 | 「吸収済み」を実変更と同一視 | `discarded_noise`状態、reason/evidence必須。resolvedはartifact receipt必須 |

### 3.2 追加反復が必要

| ID | 候補 | 現状 | 採否基準 |
|---|---|---|---|
| V01 | insight write concurrency race | task run 1/2 FAIL、隔離再実行1/1 PASS | 同一条件30回で1件以上再発ならR16へ昇格。0/30なら環境差を追加計測 |
| V02 | nudge重複・遅延 | 15:56台にUI `inbox3→inbox1`、実体0件後に新着が競合。単なる表示遅延との分離未完 | watcher event ID、送信時unread、受信時unreadの三点traceで重複率を計測 |
| V03 | auto-deploy lock domain分裂 | `/mnt/c`本番では外側`${TARGET_YAML}.lock`と内側`lock_path()`の`/tmp/hash`が別物。`/tmp`隔離probeのself-deadlockは本番再現にならない | `/mnt/c`隔離fixtureで競合writerを注入しLost Update/偽成功を30回計測。確認前にCRITICAL扱いしない |
| V04 | prompt直前nudge注入 | 2026-07-26に実害記録あり。現commitでもidle確認後からsend直前まで再確認がないが、固定commit上の二値probeは未実施 | confirmation fixtureで送信0/30、通常idle fixtureで送信30/30を確認後に確定へ昇格 |

### 3.3 維持すべき既存防御

- 二段review順序、cmd単位flock、FAIL_CLOSE時のgate非起動、archive再実行checkpointは正常。
- manual curated aliasの即時採用には「人手で確定したAC5知見を待たせない」という因果がある。例外削除ではなくprovenanceを型にする。
- CI RED時のcache無効化自体は正常。localだけdirty source identityを補う。

### 3.4 v1.0設計そのものにあった隠れた欠陥

| ID | 重大度 | 欠陥 | v2.0での修正 |
|---|---|---|---|
| N01 | CRITICAL | 複数ファイル変更を「1 transaction」としたが、OS上の単一原子操作ではない | WAL + generation + step receipt + startup reconcilerを契約化 |
| N02 | CRITICAL | crash時のautomatic rollback ownerが不在 | 次回起動時のreconcilerを唯一ownerとし、旧/新いずれかへ収束 |
| N03 | HIGH | durable job再駆動時の副作用重複境界がない | subject/generation/actionのidempotency keyとside-effect ledger |
| N04 | HIGH | 共通primitiveへの一括置換が新SPOFを作る | shadow→差分0→caller単位canary→段階移行→旧経路撤去 |
| N05 | HIGH | receiptがrc中心で、成果物・副作用とのidentity結合が弱い | artifact hash、terminal phase、side-effect IDsをreceiptへ含める |
| N06 | HIGH | FP/FN=0の母集団・negative controlが未定義 | 正例・反例・境界例の固定corpusと件数を先に採番 |
| N07 | HIGH | probabilistic raceへ正常系反復だけを要求 | 全mutation pointのcrash/競合/freshness fault matrixを追加 |
| N08 | MEDIUM | primitive強化による速度劣化の停止条件がない | wall/lock wait/recovery timeのbefore-afterと退行停止条件 |
| N09 | MEDIUM | `P0/P1問題`が本文のseverity体系に未定義 | severityはCRITICAL/HIGH/MEDIUMへ統一 |
| N10 | MEDIUM | `remote ahead/behind 0`が他agent並行作業に依存 | fixed SHAのisolated checkpointへ限定し、共有treeの状態をACから除外 |

### 3.5 必須状態スキーマ

全primitiveは少なくとも次の共通語彙を使う。caller独自の`done`、marker、文字列grepを
terminal判定へ使わない。

| field | 意味 |
|---|---|
| `subject_type` | cmd/task/review/completion/delivery |
| `subject_id` | 完全一致する正規ID |
| `generation` | 同一subjectの再試行を区別する単調ID |
| `phase` | intended/prepared/published/terminal/rolled_back |
| `attempt_id` | 実行試行の一意ID |
| `artifact_hash` | 対象成果物のidentity |
| `idempotency_key` | 副作用の重複収束キー |
| `terminal_result` | CLEAR/BLOCK/FAILED。queuedはterminalではない |
| `recorded_at` | receipt記録時刻 |

### 3.6 故障注入行列

各修正は正常系だけでなく、対象stepの直前・直後を全て試す。

| fault | 必須結果 |
|---|---|
| lock取得前/後にprocess停止 | owner不明のまま進まず、再起動後に収束 |
| WAL記録後・最初のmutation前に停止 | intentを検出し安全に再開または取消 |
| source更新後・target公開前に停止 | active ownerが二重にならない |
| target公開後・source tombstone前に停止 | generation比較で一方だけが実行可能 |
| terminal receipt前に親exit | completedを公開しない |
| receipt後・通知前に停止 | 同一idempotency keyで通知が一度に収束 |
| stale usage/cache/marker注入 | latest valid generation以外をterminal扱いしない |
| watcher二重起動 | 同一eventの永続副作用が一度に収束 |

## 4. 修正Wave設計

### Gate 0A: 成果契約の固定（全Waveの入口）

- 固定HEAD、canonical 17 ID、caller inventory、probe receipt schema、判定軸を契約として固定する。
- Gate 0Aはcontract authoringであり、runtime終端判定はR01の既存read-only receipt以外行わない。
- superseded判定には修正commit、現行caller、同一入力再測定の三点を必須化する。
- 全caller・writer・readerを表にし、同一ファイル直列条件をファイル名で固定する。
- 状態スキーマ、WAL、receipt、idempotency keyの所有者を一意化する。
- fixture corpusの正例・反例・境界例を採番し、FP/FNの分母を固定する。
- `Gate 0A contract authoring → Wave 0 probe → Gate 0B closure → durable-state foundation`の順序を崩さない。Gate 0Bで17/17のexecuted receiptを閉じるまでfoundation実装へ進まない。

#### Gate 0A observed receipt disposition（revision 3）

期待契約と観測結果を分離する。`selected`はcanonical manifest対象、`discovered`はcallerを
一つ以上現HEADで解決した対象、`executed`はpositive reproducerとnegative controlの双方に
実在receiptがある対象だけを数える。したがって未実行をPASSへ算入しない。

固定code baseline `55b3df6d4d937c7683ef1ca9a83393760d593e47`に対し、caller差分0を確認した
R01だけをread-only runtime probeで再実行した。positiveは`inbox_write.sh`固有lockと
`lock_path.sh`の同一target比較が`equal=no`、negative controlはcanonical同士が
`equal=yes`。出力SHAはmanifest receiptに固定した。本番queue/tmux/ntfy/network変更は0。

`runtime_classification`はprobe観測（`OPEN_CONFIRMED / SUPERSEDED_WITH_EVIDENCE /
NEEDS_NEW_PROBE`）、`remediation_status`は実装進捗（`ACTIVE /
PARTIALLY_SUPERSEDED / SUPERSEDED`）であり、互いに直交する。前者から後者を
推定しない。未probeのlegacy reachabilityは`unknown`とする。

| runtime_classification | 件数 | 意味 |
|---|---:|---|
| `OPEN_CONFIRMED` | 1 | R01。positive/negative receipt双方あり |
| `SUPERSEDED_WITH_EVIDENCE` | 0 | 修正commit+現caller+同一入力再測定の三点を満たすものなし |
| `NEEDS_NEW_PROBE` | 16 | callerは発見済みだが固定baseline runtime receiptなし |

計数は`receipt entries=17, executed receipts=1`（`selected=17, discovered=17, executed=1`）。callerは固定母数を前提にせず、definition/callsite/reader/writerの実行行を再導出した。コメント・変数宣言は0件、
対応record 44、classified 44、missing 0である。finding別discovery command・候補総数・採用/除外理由を固定し、R08は実行可能なbounded awkで後処理範囲の行末`&`を抽出して22/22を採用（未分類0）。実生成点9355/9984/9992を用い、R07は実書込行492-493、R11 classifier、V02 dispatch、V04 idle条件を実行行で列挙した。全`file:line+role`はmanifest
`caller_inventory`を正本とする。残る16件はWave 0で決定的barrierを作るまでOPEN扱いしない。

#### Gate 0 durable-state contract

- WAL rootは隔離可能な単一rootとし、recordは`schema_version, subject_id, generation,
  fence_token, phase, payload_hash, checksum`を持つ。appendは同一filesystemのtempへ全体を書き、
  file `fsync` → atomic rename → directory `fsync`の順とする。checksum/schema不一致は
  quarantine rootへ隔離し、active状態に使用しない。
- generationはWAL lock内のcompare-and-incrementでのみ採番する。reconcilerはlease付き
  fence tokenを取得した単一ownerだけがmutationでき、全writer/readerは現fenceの一致を
  mutationと実行の直前に再確認する。lease失効から`2 * lease_ttl`以内に新ownerが
  reconciliationを開始し、`3 * lease_ttl`以内にterminalまたは明示BLOCKへ収束する。
- commit pointは`terminal receipt + artifact hash + side-effect ledger + current fence`の同一
  generation一致時のみ。`intended→prepared→published→terminal`を正常遷移、
  `intended/prepared`は取消または再開、`published`はartifact/owner一致時のみterminalへ
  roll-forward、不一致は`rolled_back`へ収束する。terminalとrolled_backからの再実行は
  新generationを必須とする。

#### Gate 0 delivery / ownership contract

- local side effectはWAL transactionに包含できるものだけとする。external deliveryはtransactional
  outboxへ先に永続化し、keyは`subject + generation + action + target + payload_hash`とする。
  状態は`reserved/inflight/applied/failed`。provider receiptありはreceipt照合で再調停、なしは
  providerごとにat-least-onceまたはat-most-onceをmanifestに明記し、exactly-onceと称さない。
- owner移転のsafetyは常に`executable_owner_count <= 1`、livenessは終端で
  `eventually executable_owner_count == 1`。atomic active pointerのCASとfencing readを実行前に
  必須とし、source/targetの文字列statusだけでownerと判定しない。
- shadowはimmutable snapshotまたはsandbox WAL上のread-only計算に限定する。live mutationを
  dual-runしない。comparator差分0/Nの後、副作用なしreader→1 caller→低影響callerの
  順でcanaryし、1差分またはbudget超過で旧pointerへrollbackする。新旧schemaは
  migration中に双方read可能とし、全caller移行、rollback window終了、旧path reachable=0
  の三条件後だけ旧経路を撤去する。

#### Gate 0 isolation, corpus, and performance contract

- fault injectionは必ずredirectしたqueue/log/WAL rootで実行し、tmux/ntfy/networkはfakeに置換する。
  preflightでreal rootとfake endpointを二値確認し、実行前後の本番queue/tmux/ntfy/network
  fingerprint一致を必須とする。不一致は即時BLOCKして成果に算入しない。
- canonical manifestの各findingは`primitive/caller/edge/failpoint/expected durable prefix/invariant`
  を持つ。deterministic barrierで全edgeを選択し、`selected/discovered/executed`を別々に
  計数する。`executed`はpositive reproducer PASSとnegative control PASSのreceiptが実在する
  findingだけであり、最終Gate 0では三者17/17を要求する。母集団の縮小は禁止。
- detector新設は検知後にfail-closed遮断または自動実行するactionを必須とする。
  before/afterは既存gate fire logの同一固定corpusを使い、`FP/negative total`と
  `FN/positive total`を分子/分母で記録する。既存遮断条件の緩和は0件とする。
- performance baselineは実装前にbaseline SHA、workload、concurrency、warm/cold別、
  sample `n >= 30`、p50/p95/p99/max/timeoutを固定する。wall/lock-waitはp95が
  `max(5%, 20ms)`、recoveryはp95が`max(10%, 1s)`を超えたら停止し旧pointerへ
  rollback。timeout増加、sample減少、load縮小での通過は禁止する。

#### Gate 0 wave dependency and serialization

`Gate0A contract authoring → Wave0 probe → Gate0B closure → durable-state/WAL/reconciler foundation → Wave1A → Wave1B →
Wave2A → Wave2B → Wave3 → Wave4`を必須依存とする。Wave2Aは汎用outbox/reconcilerと
Wave1B owner transaction完了後のみ、Wave2BはR01 lock identityとV04 prompt-safe
primitive完了後のみ開始する。同一fileまたは同一callerを変更するWaveはmanifestの
`serialization_key`が一致するものを並列化せず、先行Waveのterminal receipt後に開始する。
Gate 0内はAC1とAC2のみ並列可。AC3（review/local-Gist同一性とscope検査）は
AC1とAC2の両方がterminal PASSとなった後にのみ開始する。

#### Review disposition (blt_20260731_183730_a3d7d7)

| # | disposition | 反映節 | 二値検証 |
|---:|---|---|---|
| 1 | ACCEPTED | durable-state contract | WAL必須field/atomicity/recovery table/livenessが全存在 |
| 2 | ACCEPTED | delivery contract | local/external分離、outbox 4状態、provider semanticsが全存在 |
| 3 | ACCEPTED | ownership contract | safety `<=1`とliveness `eventually 1`が別契約 |
| 4 | ACCEPTED | shadow contract | live dual mutation禁止、canary/rollback/撤去条件が全存在 |
| 5 | ACCEPTED | canonical manifest | canonical 17/17、legacy map 2/2、caller未分類0 |
| 6 | ACCEPTED | isolation contract | root redirect/fake/preflight/real-state fingerprintが全存在 |
| 7 | ACCEPTED | corpus contract + manifest | edge全数、selected/discovered/executedの分離計数、最終17/17契約 |
| 8 | ACCEPTED | performance contract | SHA/load/n/warm-cold/percentile/budget/rollbackが全存在 |
| 9 | ACCEPTED | dependency contract | durable foundation先行、2A/2B依存、serialization keyが全存在 |

### Wave 0: 観測とfixture（Gate 0後・依存なし・並列）

- 再現fixtureを本番repo・共有queueから隔離する。
- `OPEN_CONFIRMED`だけの修正前FAILを隔離probeとして固定し、V01を反復、V02にevent trace、V04にconfirmation fixtureを追加する。
- R09は同一canonical parserで宣言母数NとCI所属数を再採番する（現監査177、別matcherで+2差）。
- gate/hook候補はFP/FN母数を固定する。
- 全mutation pointへ§3.6のfault injectionを割り当てる。
- 通常経路のwall、lock wait、recovery timeをbefore値として固定する。
- 全量testはWave最終checkpointの1回のみ。途中は対象focused testだけを実行する。

### Wave 1A: identity primitive（同一ファイルは直列）

- `lock_path.sh`を唯一のlock identity生成器にしR01を修正。
- typed exact-match helperでR06を修正。
- immutable rc receipt primitiveを作成する。R10のcaller置換はWave 3で行う。
- primitive単体PASSだけで採用しない。既存readerとshadow実行し差分0を確認する。
- primitive自身のparse error・書込失敗・stale generationをfail-closeさせる。
- caller置換はWave 1B以降で一callerずつ行う。

### Wave 1B: task ownership transaction（R03-R05、V03採用時は同時修正）

- `auto_deploy_next.sh`の複数mutationを共通transaction helperへ置換。
- transaction helperはWALへintentを先記録し、各mutationをgeneration付きで冪等化する。
- commit条件: mutation rc全0、target receipt一致、source tombstone、active count=1、
  terminal WAL receipt一致。
- 異常終了時は「そのprocessが自動復元」と称さず、startup reconcilerが旧状態または
  新状態のどちらかへ収束させる。
- V03不採用時はlock-domain変更を本Waveへ混ぜず、確認済みR03-R05だけを修正する。

### Wave 2A: terminal receipt（R07-R08、Wave 1A exact identity後）

- review markerとcompletion checkpointはterminal receipt後だけ公開する。
- 非同期tailをdurable job化し、supervisorがterminal checkpointまで再駆動する。
- dashboard、archive、品質記録、通知は同一idempotency keyを使い、再駆動しても一度に収束させる。
- receiptはsubject/generation/artifact hash/side-effect ledgerを結合する。
- timeout延長・marker残置・failure ignoreは禁止。

### Wave 2B: safe delivery（V02、V04採用後）

- pane送信を中央関数一択にし、送信直前のconfirmation prompt検出を必須化。
- watcher event ID→nudge→inbox unreadのcorrelationを永続化し、重複・遅延を別計数する。

### Wave 3: CI/test SSOT（R09、R10、R13）

- `test_necessity`付き永続contract testだけからBats/Python inventoryを自動生成し、
  localとCIの実行集合を同一化する。一時実装testをinventoryへ残さない。
- 目標はcanonical parserで永続contract CI所属N/N、未所属0（現監査では80/177、未所属97）。
- Wave 1Aのimmutable rc receiptを`run_tests.sh`のleader/joiner/issuer callerへ置換し、R10を閉じる。
- SKIPはFAIL、未選択は「未検証」として別計数する。
- test cacheはworktree source・runner・fixture・env identityをfingerprintへ含める。

### Wave 4A: hook ownership（R14）

- combined hookを唯一ownerとし、到達不能な重複branchを除去する。
- manifest generatorでmatcher到達性、実体存在、Codex BLOCK exit=2、exit=1件数0を強制する。

### Wave 4B: knowledge provenance（R11、R15、V01）

- curated manual知見は署名済みprovenanceのみ即時昇格させ、既存の意図を保持する。
- pending在庫を「実装待ち」「裁定待ち」「resolved」「discarded_noise」に型付けする。
- 三層貫通はdurable receiptで完了判定する。

### Final checkpoint

- 各Waveでは対象focused testだけを実行し、固定SHAで全量testを共有1回だけ実行。
- FAIL=0、SKIP=0。
- 各修正の修正前FAIL→修正後PASSを全件再計測。
- 固定corpus上のgate FP/FNを修正前後比較し、分子/分母を記録。
- §3.6のfault matrixを全対象で完走し、未実行0。
- 通常経路のwall、lock wait、recovery timeに未承認退行がない。
- fixed SHAのisolated checkpointでCI GREENを確認し、共有treeのahead/behindを成果判定へ使わない。
- 既存防御4種が全て維持されることを敵対fixtureで確認。

## 5. 共通Acceptance Criteria

1. 基準commitの全R/Vを現HEADで再測定し、`OPEN_CONFIRMED /
   SUPERSEDED_WITH_EVIDENCE / NEEDS_NEW_PROBE`の未分類を0にする。
2. CRITICAL/HIGH問題は正常系だけでなく§3.6の該当fault injectionを全て通し、
   二重active・二重副作用・terminal偽公開を0にする。
3. gate/hook変更は固定corpusの正例・反例・境界例でFP=0、FN=0を分子/分母付きで確認する。
4. state変更はsubject identity、generation、lock identity、WAL、terminal receipt、
   idempotency key、crash後reconciliation境界を明記する。
5. focused testはFAIL=0、SKIP=0。永続testには具体的`test_necessity`を宣言する。
6. 全量testは最終checkpointで1回だけ実行し、全忍者による重複実行を禁止する。
7. 修正後のpending insight・WA・gate metricsへ知見を還流し、強くてニューゲーム可能にする。
8. canonical parser確定後、`test_necessity`付き永続contractのCI所属をN/N、
   未所属0へ改善する。旧監査値は再採番前提で目標値へ固定しない。
9. task ownershipのactive countは全failure injection点で常に1、またはrollback後の元状態と一致する。
10. queuedとcompletedを別状態として観測でき、terminal未達jobは自動再駆動される。
11. retry可能な全副作用が同一idempotency keyで一度に収束する。
12. 新primitiveはshadow差分0とcaller単位canaryを経て移行し、一括置換しない。
13. fixed SHA isolated checkpointで検証し、共有treeのahead/behindを成果判定へ混ぜない。
14. wall、lock wait、recovery timeをbefore/afterで比較し、未承認退行0。

## 6. 軍師レビュー依頼事項

軍師は以下を敵対的に判定する。

1. 再現なしの推測を確定問題へ混ぜていないか。
2. gateを弱めて見かけのBLOCK率だけ下げていないか。
3. timeout/retry/ignoreによる自動消火がないか。
4. Level 4で止まり、Level 5入力生成へ到達していない項目がないか。
5. Wave間依存と同一ファイル直列条件に穴がないか。
6. 最終checkpointが途中のtry回数を不必要に落としていないか。
7. WAL/reconcilerが途中状態を必ず旧または新の一方へ収束させるか。
8. retryがdashboard・通知・archive等の副作用を二重化しないか。
9. 共通primitiveが新しいSPOFになっていないか。shadow/canary/rollback境界は十分か。
10. 現HEADでsupersededなR/Vを再実装しようとしていないか。
11. fault corpusとFP/FN母集団は、実装に都合のよい例だけへ縮んでいないか。
12. 品質強化が通常経路のwall/lock wait/recovery timeを悪化させていないか。

## 7. レビュー履歴

| round | reviewer | verdict | 指摘 | 反映 |
|---|---|---|---|---|
| 0 | 軍師 | LGTM | R10のprimitive/caller置換Wave、V03不採用時scopeを明示。R12は現commitの二値probeなし | Wave 1A/1B/3へ反映。R02→V03、R12→V04へ降格。4共通根因、既存防御維持、ACは妥当 |
| 1 | 将軍 | REQUEST_CHANGES | 現HEADドリフト、非原子的transaction、crash recovery owner不在、retry副作用、primitive SPOF、FP/FN母集団、性能予算の欠落 | v2.0でGate 0、状態スキーマ、WAL/reconciler、idempotency、shadow/canary、fault matrix、性能ACを追加 |
| 2 | 軍師 | REQUEST_CHANGES | `blt_20260731_183730_a3d7d7`の9点 | v2.1 Gate 0 contractとcanonical manifestに9/9反映。再レビュー待ち |
