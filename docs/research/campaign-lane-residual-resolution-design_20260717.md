# Campaign Lane残課題 解決設計書

- status: IMPLEMENTATION_IN_PROGRESS_F1_READY
- plan_review_status: PARALLEL_PLAN_REVIEWED_APPROVED
- date: 2026-07-17
- owner: karo
- reviewers: gunshi（計測・品質・失敗モード）, shogun（目的・優先順位・完了条件）
- reviewed_payload_sha256: `62d0c58bdca6fab1d36561d85bedb43a9be761d3463bdefcca6353582739fcf3`（設計レビュー対象。以下の進捗追記前）
- source: `campaign-lane-general-skill-asis-tobe-5w1h_20260716.md` §11
- scope: §11の残課題6件。inbox Phase Aの採用済みbatch ACKを起点に、未解決部分をreadyへ到達させる。
- non-goals: 品質契約の緩和、人判断の自動化、依存候補の同一round投入、専用計測runの常態化。

## §0 実装進捗（2026-07-17T18:06:00+09:00）

結論: **残課題6件の解決は未完了**。F1投入前の基盤3段（S0/S0b/S0c）はすべてGATE CLEARし、S0cのcmd-complete全工程も完了した。次は追加設計や先行hardeningを挟まず、同一fingerprintのruntime manifestでF1の6 adapterを並列実装する。

| Checkpoint | 現在状態 | 実装証拠 | 二値計測 | GATE / 次条件 |
|---|---|---|---|---|
| S0 共通契約凍結 | **CLEAR** | 実装`1653a44a3`、固定SHA`9192bf61ada7bb3c44ceecf5cf86599df0b8ec81` | S0 pytest 9/9 + 既存Bats 15/15 = **24/24 PASS**, FAIL 0, SKIP 0 | `cmd_4034` GATE CLEAR（15:58:21） |
| S0b shard lifecycle bridge | **CLEAR** | `eaccaa6173d53c94b6d57af46a72f588d9cf55a8`。materialize→deploy→report→result、terminal HEAD/dirty/scope検証 | bridge 17/17 + universal 7/7 + lane 15/15 + S0 9/9 + bash構文1/1 = **49/49 PASS**, FAIL 0, SKIP 0 | `cmd_4039` GATE CLEAR（17:16:13）、cmd-complete全工程PASS |
| S0c fingerprint最終補修 | **CLEAR** | 固定SHA`799370d1b968724862cee6ae9f1d05a822298c1e`。schema+helper SHA+SDK SHA、runtime mismatch BLOCK、`test_command`/`read_only_paths_json` task接続 | S0 10/10 + bridge 21/21 + universal 7/7 + lane 15/15 = **53/53 PASS**, FAIL 0, SKIP 0。runtime fingerprint=`5e5cbdf07ee17a947ea7d3e14d489498d1c7dd3eee57e85323a10e689d735eb5` | `cmd_4040` GATE CLEAR、軍師SG7 LGTM、家老ACCEPT、cmd-complete全工程PASS |
| F1 6 adapter並列実装 | **READY_TO_START** | I1/A1/A2/A3/A4/T1のownership設計済み | 未計測 | 同一fingerprint、runtime idle worker N≥2、`shard-work --plan` coverage 100%・競合0を確認して即開始 |
| S1 統合checkpoint | **NOT_STARTED** | item ID昇順統合設計済み | 未計測 | F1 coverage 100%、missing/duplicate/conflict 0が開始条件 |
| F2 live campaign計測 | **NOT_STARTED** | 計測契約のみ | before/after未取得 | S1 fixed-SHA CI GREEN後 |
| S2 精度較正・最終AC | **NOT_STARTED** | precision/FP退役契約のみ | TP/FP/FN/TN未取得 | laneごと20件以上、AC1-12全PASSが必要 |

現時点で未達の最終証拠は、F1の実並列speedup/dispatch/overhead、6残課題のbefore/after、fixed-SHA required CI GREEN、live 2 round、lane別20件以上のprecision、最終AC1-12である。したがって「残課題解決済み」「CI GREEN」「速度改善達成」とはまだ記載しない。

次の一手は、CLEARした固定SHAとfingerprintでruntime manifestを生成し、`shard-work --plan`のcoverage/ownership/N≥2確認後にF1を開始することである。

## §1 結論

残課題は一括実装せず、共通checkpointを先に作り、通常業務writer、決定的adapter、live貫通、精度較正の順で解く。

```text
P0 固定SHA checkpoint
  ↓
P1 通常業務writer + inbox drain計器
  ↓
P2 partial 4 laneの決定的subset adapter
  ↓
P3 pytest live campaign貫通
  ↓
P4 adapter精度較正・退役
```

P0とP1の共通契約までは直列で凍結する。その後はP1 inbox、P2の4 adapter、P3 pytestを「共通ファイルを編集しない6 shard」として動的に並列化する。各shardは固有実装・固有test・機械可読な結果だけを返し、catalog接続は統合checkpointで一度だけ行う。P4は通常業務で十分な採否標本が蓄積してから実行する。

## §2 現状と完了定義

| # | 残課題 | 現状 | 完了の二値条件 |
|---|---|---|---|
| 1 | inbox `drain_time_p95` writer/adapter | batch ACKのみ採用。15件p95 420→30ms。consumer全体drain未計測 | 通常burst 20件以上でepisode writer欠損0、backlog 15→0 p95を算出、adapterが1件以上を選定し、loss/誤ACK/重複実行0のままbefore/afterを記録 |
| 2 | partial 4 laneをready化 | context-freshness / insight-queue / lesson-backlog / memory-candidatesがpartial | 各laneでclean checkout `next` が決定的候補を返し、競合予約1/重複0、失敗rollback、品質fixture PASS、判断対象はBLOCK |
| 3 | 通常業務writer接続 | 専用計測に依存するlaneが残る | 専用run 0でも通常フロー10回中10回ledger追記、重複0、workflow失敗増加0、writer無効時も本処理契約不変 |
| 4 | pytest live chain | writer/adapter単体はready、実機反復未貫通 | 生成→idle配備→改善→record→次標的を異なるnodeidで2 round連続完走。FAIL/SKIP/悪化は採用0・rollback 1 |
| 5 | adapter精度/FP退役 | 採否台帳はあるが共通precisionなし | laneごとにTP/FP/FN/TNを20件以上で算出。FP率100%は自動停止、precision閾値未達はcalibratingへ降格、改善後だけ再開 |
| 6 | 固定SHA clean clone checkpoint | 今回は手動運用で実証。共通gate未実装 | dirty worktree結果を採用不可にし、固定SHA clean clone対象テスト+全量+SKIP0+CI headSha一致GREENを機械判定 |

## §3 共通データ契約

### §3.1 Campaign outcome ledger

全laneが次のappend-only JSONLへ採否を記録する。既存lane固有台帳は維持し、これは横断較正用の派生台帳とする。

```json
{"lane_id":"inbox-drain","candidate_id":"batch-ack","round":1,"selected_at":"...","baseline":420.0,"after":30.0,"objective":"minimize","quality":"pass","decision":"accepted","reason_code":"both_p50_p95_improved","fixed_sha":"...","ci_run_id":29556512608}
```

必須キーは `(lane_id,candidate_id,round)`。flock内再読込で重複をBLOCKする。`decision` は `accepted | rejected | rolled_back | blocked` の4値だけとし、曖昧な「試行済み」を禁止する。

### §3.2 通常業務writer契約

- 通常フローの既存成功後にappendする。writer失敗で本処理の成功を偽装しない。
- 専用計測runを要求しない。既存hook/job/report completionから一次値を採る。
- 一意キーでidempotent。並行writeはflock+atomic publish。
- source SHA、開始/終了時刻、quality、対象IDを必須にする。
- sourceが無い場合は0や推定値を記録せず、`measurement_missing`を明示してadapterをBLOCKする。

## §4 Phase設計

### §4.1 P0 固定SHA checkpoint（残課題6）

入口は候補commit SHA、対象test manifest、quality contract。隔離cloneで次を順に強制する。

1. remote base SHAと候補SHAを固定し、対象外diff 0を検証。
2. 対象testを実行し、FAIL 0 / SKIP 0。
3. 全量testを実行し、FAIL 0 / SKIP 0。
4. push後、Actions `headSha == candidate SHA` と全required job GREENを検証。
5. どれか1つでも不一致ならready/acceptedへ遷移させない。

出力は `fixed_sha`, `target_result`, `full_result`, `skip_count`, `ci_run_id`, `ci_conclusion`。共有worktree PASS、別SHA CI GREEN、cancelled runを成功として使うことを禁止する。

敵対fixture:

- clean cloneにgitignored設定が無い。
- テストが追跡外fixtureを暗黙参照する。
- push直後にmainが進み、別SHAのGREENを誤採用する。
- 全量PASSだがSKIPが1件ある。

### §4.2 P1 inbox drain計器 + 通常writer（残課題1・3）

`backlog episode`を、agentごとに `unread 0→1以上` で開始し、同じepisodeの `unread→0` で終了する区間と定義する。watcherが一次eventをappendし、集計器がepisodeを構成する。ageイベントを一意message latencyと混同しない。

記録項目:

- `agent_id`, `episode_id`, `started_at`, `drained_at`, `peak_unread`
- `arrival_count`, `ack_count`, `p0_first_ack_ms`
- `read_ms`, `triage_ms`, `ack_ms`, `review_wait_ms`
- `message_ids_sha256`, `loss_count`, `wrong_ack_count`, `duplicate_execution_count`

adapterは支配時間が最大のphaseだけを候補化する。`review_wait_ms`が支配項ならコード高速化を出さず、責務分離・別laneへBLOCK付きで送る。semantic coalescingとbatch ACK、priority triageとdigestは同一roundに入れない。

採用SLO:

- load fixture: backlog 15、arrival burst継続。
- primary: drain p95 ≤120秒。
- guard: P0 first-ack p95 ≤10秒。
- capacity: controlled burstの開始10秒をwarm-upとして除外し、その後の固定60秒monotonic windowで `λ = arrival_count / 60`、`μ = successful_ack_count / 60` とし、`μ >= 2 × λ`。初期backlog 15件はλの分子に含めず、同じwindow内のACKはμへ含める。
- quality: loss / wrong ACK / duplicate execution = 0。

### §4.3 P2 partial 4 adapter（残課題2）

#### context-freshness

`CONTEXT_CACHE_BYPASS=1`の再検証でstaleが再現し、source commitとcontext pathが一意な対象だけを返す。曖昧なsource mappingはBLOCK。更新後はstale_source_countが1以上減ることを採用条件にする。

#### insight-queue

自動対象は既存 `fix_known` と、機械的な `duplicate/superseded/already_fixed` のみに限定する。設計判断・本番判断・人間の価値判断を含むinsightは候補化せずBLOCK。priority順を保持する。

#### lesson-backlog

origin欠落、完全重複、`superseded_by`確定、既存lessonへの機械mergeだけを候補化する。内容の正誤・恒久ルール化・deprecation判断は自動化しない。処理後はdraft_count減少と因果リンク保持を両方確認する。

#### memory-candidates

自動対象はhash一致duplicate、既知矛盾キー一致、Obsidianリンク欠落の機械追記だけ。意味的昇格・殿の好み判定はBLOCK。三層のうち1層だけ成功した場合はrollbackまたは未完了として残し、partial successを完了扱いしない。

各adapter共通のready gate:

- clean checkout `next` p95 ≤1秒。
- 候補0件は理由付き正常停止、parse失敗はfail-closed。
- 同時2 processで予約成功1、duplicate 0。
- deploy失敗で予約rollback。
- 対象外変更0、品質fixture FAIL 0 / SKIP 0。

### §4.4 P3 pytest live chain（残課題4）

実機で異なるnodeidを2件選び、次を2 round連続で通す。

```text
normal pytest writer
  → timing ledger
  → pytest-speed adapter next
  → capability一致idle ninjaへ配備
  → p50/p95改善 + expectation不変
  → fixed-SHA checkpoint
  → outcome record
  → 次nodeid
```

悪化、FAIL、SKIP、expectation緩和を注入する敵対roundを別途1回実行し、採用0・rollback 1・次候補継続を確認する。nodeid数や探索対象を計算量理由で縮小しない。

### §4.5 P4 adapter精度・退役（残課題5）

定義:

- TP: adapter選定後、品質PASSかつprimary metric改善で採用。
- FP: adapter選定後、再現不能・悪化・品質FAILで棄却/rollback。
- FN: ledgerに改善可能な対象があったがadapterが候補0としたもの。
- TN: 改善余地なしを正しく停止。

20候補以上の同一cohortで `precision=TP/(TP+FP)`、`FP rate=FP/(TP+FP)`、`useful rate=accepted/deployed` を計算する。

状態遷移:

```text
active --precision<50%--> calibrating
active --FP=100%かつn>=5--> retired
calibrating --同一cohort precision>=70%--> active
retired --新fixtureでTP>=3かつFP=0--> calibrating
```

退役は履歴削除ではなくadapterを停止し、reason codeと最後のcohortを残す。成功例だけでprecisionを計算しない。

## §5 忍者並列実装パッケージ

### §5.1 Critical pathとwave DAG

```text
S0 契約凍結（1忍者）
   fixed-SHA checkpoint + outcome ledger helper + adapter SDK + contract fingerprint
                              │
                              ▼
F1 独立実装fan-out（ready shardを2〜6忍者へ動的配備）
   ├─ I1 inbox-drain writer/adapter
   ├─ A1 context-freshness adapter
   ├─ A2 insight-queue adapter
   ├─ A3 lesson-backlog adapter
   ├─ A4 memory-candidates adapter
   └─ T1 pytest live-chain harness
                              │
                              ▼
S1 統合checkpoint（1忍者）
   item ID順commit取込 → scope/contract検証 → catalog一括接続 → target/full test
                              │
                              ▼
F2 campaign実測（独立candidateをshard-workで2〜N並列）
                              │
                              ▼
S2 precision集計・状態遷移（1忍者）
```

S0/S1/S2は共有SSOTを変更するため直列、F1/F2だけを並列にする。F1開始条件はS0のfixed SHA、contract fingerprint、対象path、固有test commandが確定していること。依存が残るitemを同一waveへ入れず、ready itemまたは適合idle workerが2未満ならserialへ黙ってfallbackせずBLOCKする。

### §5.2 1 shardの完結契約

各itemは配備前に次のフィールドを固定する。worker名・CLI名・LLM名は契約へ入れず、実行時のidle/capabilityだけで割り当てる。

| Field | 二値契約 |
|---|---|
| `id` | wave内で一意かつ再実行しても不変 |
| `weight` | 正数。一次見積り（対象file数+test数+外部fixture数）から算出 |
| `capability` | `shell-gate` / `adapter` / `pytest-live` の作業能力だけを表す |
| `contract_fingerprint` | S0のschema・helper・SDK SHAから生成し、実行時不一致ならBLOCK |
| `owned_paths` | itemだけが変更できる実装・test path。wave内の積集合は空 |
| `read_only_paths` | 参照可、変更不可の共通契約・既存SSOT |
| `test_command` | 当該itemだけのFAIL 0 / SKIP 0を返すコマンド |
| `result_path` | `output_dir/result.json`。commit SHA、files、test数、FAIL、SKIP、elapsedを必須化 |

忍者は`owned_paths`外を変更せず、共通helper/catalogの不足を見つけた場合は勝手に補修せず`result.json.reason_code=blocked_dependency`、process exit non-zeroで返す。universal shard coreのstatusへ未対応の第6状態を追加せず、`merged.json`上は`fail`として保存する。家老はこのreason codeだけをS0修正へ戻し、fingerprintを更新して全未完了itemを再計画する。これにより、並列中の共通契約ドリフトを禁止する。

### §5.3 排他的file ownership

以下は実装時の提案pathであり、S0で存在・命名を確定してからF1へ渡す。

| Item | owned_paths | read_only/shared |
|---|---|---|
| I1 inbox-drain | `skills/campaign-lane/adapters/inbox_drain.py`, `tests/unit/test_campaign_inbox_drain.py` | watcher、inbox ACK、ledger helper |
| A1 context-freshness | `skills/campaign-lane/adapters/context_freshness.py`, `tests/unit/test_campaign_context_freshness.py` | `scripts/context_freshness_check.sh` |
| A2 insight-queue | `skills/campaign-lane/adapters/insight_queue.py`, `tests/unit/test_campaign_insight_queue.py` | insight SSOT/既存resolve script |
| A3 lesson-backlog | `skills/campaign-lane/adapters/lesson_backlog.py`, `tests/unit/test_campaign_lesson_backlog.py` | lesson SSOT/`lesson_write.sh` |
| A4 memory-candidates | `skills/campaign-lane/adapters/memory_candidates.py`, `tests/unit/test_campaign_memory_candidates.py` | 三層記憶writer/semantic index |
| T1 pytest-live | `skills/campaign-lane/adapters/pytest_live.py`, `tests/unit/test_campaign_pytest_live.py` | pytest timing ledger/task generator |

F1中は全忍者が次を編集禁止とする: catalog、outcome ledger helper、adapter SDK、既存SSOT writer、他itemのowned path。共通catalogへの6回の並行追記は行わず、各itemの`result.json`をS1がitem ID順に一括接続する。ownership重複検査が1件でも検出したmanifestは配備前にBLOCKする。

### §5.4 shard-work manifest生成契約

manifestは配備直前の一次状態から家老が生成する。`workers`はその時点のidleかつcapability適合者だけをsnapshot化し、固定の忍者名や固定人数を設計へ埋め込まない。`N=min(eligible workers,max_workers)`、N<2はBLOCKする。下例の`max_workers: 6`はready item数による上限であり、6人固定を意味しない。

```yaml
items:
  - id: I1-inbox-drain
    weight: 5
    capability: adapter
    path: skills/campaign-lane/adapters/inbox_drain.py
    contract_fingerprint: <S0_SHA256>
    owned_paths: [<implementation>, <unit_test>]
  - id: A1-context-freshness
    weight: 3
    capability: adapter
    path: skills/campaign-lane/adapters/context_freshness.py
    contract_fingerprint: <S0_SHA256>
    owned_paths: [<implementation>, <unit_test>]
  # A2, A3, A4, T1も同じ契約。依存itemは含めない。
workers: <runtime idle/capability snapshot>
max_workers: 6
command: >-
  bash scripts/campaign_lane_shard_item.sh
  {item_id} {item_path} {worker_id} {workdir} {output_dir}
state_dir: queue/shard_state/campaign-lane-residual-<S0_SHA>
timeout: 1800
```

実行順は必ず`shard_work.sh MANIFEST --plan`→計画のexactly-once/coverage/ownership検証→`--run`。universal shard coreが渡す`workdir`は隔離directoryであってsource checkoutではないため、`campaign_lane_shard_item.sh`は作業開始前にS0 fixed SHAをそこへmaterializeし、`HEAD == S0 SHA`かつdirty 0を検証する。source展開に失敗したitemは実装を始めず`fail(reason_code=source_materialize_failed)`とする。同一workerのlive予約競合、coordinator競合、capability全体未充足も成功扱いせずBLOCKする。`merged.json`は実行結果の完全性証拠であり、品質PASSの証拠ではない。

### §5.5 retry・統合・品質checkpoint

1. `success`かつ同一fingerprintのitemは保持し、core既定の`fail|skip|timeout|cancel`だけを再配備する。`blocked_dependency`は`fail`のreason codeとして扱う。
2. retryで成功itemを再実行しない。item契約またはcommandが変わった場合だけfingerprintを変え、影響itemを再実行する。
3. S1はclean integration branchへitem ID昇順でcommitを取り込み、各commitで`owned_paths`外diff 0と固有test FAIL 0 / SKIP 0を確認する。
4. conflictが1件でも起きたら場当たり的に解消せず、ownershipまたは共通契約の欠陥としてF1を停止しS0へ戻す。
5. 全item取込後にcatalogを1commitで接続し、adapter契約test→対象test→全量test→fixed-SHA CIの順で通す。
6. partial successは保存するがwave完了とは呼ばない。`expected == actual`、missing 0、duplicate 0、全item success、FAIL 0、SKIP 0でのみF2へ進む。

### §5.6 並列化そのものの計測

速度改善は実装機能だけでなく実装lane自体もbefore/afterを残す。

| Metric | 定義 | 合格条件 |
|---|---|---|
| wall speedup | `(Σ shard_elapsed + integration_elapsed) / (fanout_elapsed + integration_elapsed)` | 2 worker時`>1.3x`、4以上時`>2.0x` |
| dispatch latency | manifest確定→全選択worker開始のp95 | ≤10秒 |
| coordination overhead | `(fanout_elapsed - max(shard_elapsed)) / fanout_elapsed` | ≤20% |
| assignment integrity | missing / duplicate / capability mismatch / live double-reservation | 全て0 |
| merge integrity | conflict / owned_paths外変更 / contract mismatch | 全て0 |
| retry efficiency | 成功済みitemの不要再実行数 | 0 |

比較対象のserial equivalentは各shardの実測elapsed合計に同一integration checkpointの実測elapsedを1回だけ加え、推定工数を使わない。並列側も同じintegration elapsedを1回だけ含め、fan-outだけを置換した同一仕事量で比較する。適合workerが少ない日は合格閾値を緩めず、Nと実測値をそのまま記録する。

## §6 最終Acceptance Criteria

1. 6残課題の各行に、実装commit、fixed SHA、CI run、before/after、quality結果が紐づく。
2. ready laneは全てclean checkout real-path `next`、並行予約、rollback、live handoffをPASSする。
3. 通常業務10 eventでwriter欠損0・重複0。専用計測run 0。
4. inbox burst 20 episode以上でdrain p95とP0 first-ack p95を算出し、loss/誤ACK/重複実行0。
5. pytest live chainが2 round連続完走し、敵対roundを採用しない。
6. adapter精度がlaneごとに可視化され、100% FP adapterがactiveに残らない。
7. fixed-SHA checkpointが別SHA GREEN・dirty PASS・SKIP 1を全てBLOCKする。
8. 全required CI GREEN、FAIL 0、SKIP 0。未達が1件でもあれば「残課題解決済み」と記載しない。
9. F1 manifestのitem coverage 100%、missing/duplicate/ownership重複/capability mismatch 0。
10. retryは失敗itemだけを対象とし、同一fingerprintの成功item再実行0。
11. S1統合conflict 0、owned_paths外diff 0、catalog接続commit 1件。
12. 並列実装before/afterが§5.6の全指標を満たす。満たさなければ機能実装がPASSでも並列化成果は未達とする。

## §7 Review依頼

### 軍師

- F1の6 itemが実際に独立で、hidden dependencyや共有SSOT競合がないか。
- ownership、fingerprint、retry、S1 checkpointが部分失敗や品質低下を隠さないか。
- §5.6のspeedup/overhead分母と閾値に観測バイアスがないか。
- `merged.json`完全性と実装品質を混同しないgateになっているか。

### 将軍

- S0→F1→S1→F2→S2が最短critical pathで、直列化/過剰並列化がないか。
- worker割当が人数・名前・CLI/LLMに固定されず、ready workへ追随するか。
- WHATと二値完了条件が忍者の裁量を奪い過ぎず、統合事故を防ぐ十分条件か。
- 残課題6件と「並列実装の速度成果」の双方を完了と呼べる最終ACか。

## §8 Review履歴

- 2026-07-17 軍師: APPROVE。指標、FP/FN退役、episode競合、敵対fixtureの4観点OK。INFO「μ/λの移動窓が未定義」を受け、§4.2へwarm-up 10秒後の固定60秒window定義を追加。
- 2026-07-17 将軍: APPROVE。P0→P4の依存順、§2/§6の二値完了条件、人判断BLOCK境界、最終AC8項目を確認し穴なし。軍師INFO反映後の§4.2も確認済み。
- 2026-07-17 忍者並列実装計画・初回レビュー: 両者APPROVEだったが、将軍回答が旧Step/AC1-8、軍師回答がAC9-11までを参照し、現物SHAとの不一致を検出したため採用せず再レビューへ戻した。
- 2026-07-17 軍師・固定SHA再レビュー: APPROVE。AC12とwall speedup分母の誤読を訂正し、hidden dependency、ownership、fingerprint、partial retry、`merged.json`と品質gateの分離を確認。
- 2026-07-17 将軍・固定SHA再レビュー: SHA `7e0beba7...`一致でAPPROVE。S0→F1→S1→F2→S2、runtime worker割当、AC1-12を確認。
- 2026-07-17 最終差分: universal shard実装契約との照合で、S0 SHA materialize、unsupported status排除、max_workersの意味、同一仕事量speedup式を追加。payload SHA `62d0c58b...`に対し、軍師は実装安全性4点、将軍は構造・AC非破壊6点を別々にAPPROVE。

## 因果リンク

`[[inbox write高速化]] -> [[consumer backlog残存]] -> [[batch ACK採用]] -> [[drain-time p95 writer]]`

`[[dirty worktree local PASS]] -> [[clean checkout CI FAIL]] -> [[fixed-SHA checkpoint]]`

`[[成功例だけの台帳]] -> [[adapter FP不可視]] -> [[precision較正]] -> [[100% FP退役]]`

origin: `[[campaign-lane §11残課題]] -> [[軍師・将軍協議]] -> [[campaign-lane residual resolution design]]`

## 因果リンク

- ← [[campaign-lane-general-skill-asis-tobe-5w1h_20260716]] §11残課題が起点
- → [[growth-loop]] campaign-laneの品質合格スループット向上
- → [[infrastructure]] infra platform上のcampaign制御面
