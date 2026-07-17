# Campaign Lane残課題 解決設計書

- status: REVIEWED_APPROVED
- date: 2026-07-17
- owner: karo
- reviewers: gunshi（計測・品質・失敗モード）, shogun（目的・優先順位・完了条件）
- source: `campaign-lane-general-skill-asis-tobe-5w1h_20260716.md` §11
- scope: §11の残課題6件。inbox Phase Aの採用済みbatch ACKを起点に、未解決部分をreadyへ到達させる。
- non-goals: 品質契約の緩和、人判断の自動化、依存候補の同一round投入、専用計測runの常態化。

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

P0/P1は全laneの前提であり並列化しない。P2の4 adapterは互いに独立なため、各候補の入出力契約を凍結後にcampaignで並列化できる。P3はpytest writerとP0を前提にする。P4は通常業務で十分な採否標本が蓄積してから実行する。

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

## §5 実装順序と並列境界

| Step | 実装物 | 前提 | 並列可否 |
|---|---|---|---|
| 1 | fixed-SHA checkpoint | なし | 単独。全後続の品質底線 |
| 2 | outcome ledger + normal writer helper | Step 1 | 単独。schema凍結 |
| 3 | inbox episode writer/adapter | Step 2 | 単独。ID契約競合を避ける |
| 4 | partial 4 adapter | Step 2 | 4本並列可。共通ファイル編集は禁止 |
| 5 | pytest live 2 round | Step 1, 2 | partial adapterと並列可 |
| 6 | precision集計・状態遷移 | Step 3〜5の標本 | 単独 |

campaignへ投入するのは、前提が揃い、互いの入力・SSOT・対象ファイルを変えない候補だけ。独立候補2件が無ければserialへ黙ってfallbackせずBLOCKする。

## §6 最終Acceptance Criteria

1. 6残課題の各行に、実装commit、fixed SHA、CI run、before/after、quality結果が紐づく。
2. ready laneは全てclean checkout real-path `next`、並行予約、rollback、live handoffをPASSする。
3. 通常業務10 eventでwriter欠損0・重複0。専用計測run 0。
4. inbox burst 20 episode以上でdrain p95とP0 first-ack p95を算出し、loss/誤ACK/重複実行0。
5. pytest live chainが2 round連続完走し、敵対roundを採用しない。
6. adapter精度がlaneごとに可視化され、100% FP adapterがactiveに残らない。
7. fixed-SHA checkpointが別SHA GREEN・dirty PASS・SKIP 1を全てBLOCKする。
8. 全required CI GREEN、FAIL 0、SKIP 0。未達が1件でもあれば「残課題解決済み」と記載しない。

## §7 Review依頼

### 軍師

- 指標定義に観測バイアスや分母誤りがないか。
- FP/FN定義と退役閾値が品質低下を隠さないか。
- inbox episode境界・競合・loss検知に抜けがないか。
- 敵対fixtureとrollback条件が十分か。

### 将軍

- 解く順序が「正しい結果を最短で供給」に一致するか。
- WHATと完了条件が明確で、HOWの過剰拘束になっていないか。
- 人判断を必要とするlaneを自動化し過ぎていないか。
- 残課題6件を完了と呼べる最終ACに穴がないか。

## §8 Review履歴

- 2026-07-17 軍師: APPROVE。指標、FP/FN退役、episode競合、敵対fixtureの4観点OK。INFO「μ/λの移動窓が未定義」を受け、§4.2へwarm-up 10秒後の固定60秒window定義を追加。
- 2026-07-17 将軍: APPROVE。P0→P4の依存順、§2/§6の二値完了条件、人判断BLOCK境界、最終AC8項目を確認し穴なし。軍師INFO反映後の§4.2も確認済み。

## 因果リンク

`[[inbox write高速化]] -> [[consumer backlog残存]] -> [[batch ACK採用]] -> [[drain-time p95 writer]]`

`[[dirty worktree local PASS]] -> [[clean checkout CI FAIL]] -> [[fixed-SHA checkpoint]]`

`[[成功例だけの台帳]] -> [[adapter FP不可視]] -> [[precision較正]] -> [[100% FP退役]]`

origin: `[[campaign-lane §11残課題]] -> [[軍師・将軍協議]] -> [[campaign-lane residual resolution design]]`
