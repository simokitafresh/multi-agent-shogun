# Infra Throughput Outcome Design — 2026-07-18

status: wave-1-c1-active  
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

集計: 34件。修正済9、部分修正5、未修正20。残件あり25。  
内訳: 忍者報告root 30件 + 家老が報告横断で分離した4件（session contract、deploy再入、review child retry、target/global semantics）。

### C1 Storage/worktree substrate — 6件

| ID | 状態 | root issue | 一次値 / 修正 |
|---|---|---|---|
| C1-01 | 部分修正 | `/mnt/c` git commit全index lstat/D-state | porcelain出版を`5e01e0f1`+`2adcc03c`でcommit-tree/update-ref CASへ置換し45/45。fixture N=5 p50 1.940s/p95 2.120s。一方、実repo cold/warm commitは70.015s→24.643s、stale index.lock追加3回、9P Glob/rg 60s timeoutを観測。実repo p95<20sは未証明 |
| C1-02 | 部分修正 | full worktree addの9P hydrationとregistry肥大 | `e1f2929e`でregistry-plan/reconcileとcount-bound承認ガード追加。一次再計測worktree82/prunable28/list11.19s/status16.66s、実削除0。exact 28 pathは確保済み。combined初回43/44後、再実行44/44+対象test10/10で再現せず。stale0は殿承認後のみ |
| C1-03 | 部分修正 | scope commit rc0とHEAD/diff/receiptの収束race | `5e01e0f1`+`2adcc03c`でpre-commit→write-tree→commit-tree→update-ref CAS→post-checkを同一transaction化し45/45、fixture逸脱0。一方`e1f2929e`成功時もstdout hash空→再実行でno-change BLOCK。実repo cold/warm比70.015/24.643=2.84、phase内git subprocess/lstat上限と親process durable確認は未計装 |
| C1-04 | 修正済 | context freshness旧cache schemaが複数git log timeout | `55a5e330`、65/65。shadow 10回p95 1.276〜3.445s |
| C1-05 | 部分修正 | deploy 150〜305sの共有I/O/control-plane | `1f248cde`で676MB memory DB全hash 22.97sをmetadata identityへ変更しwave-cache単体cold/warm N6 p95 0.474s、270/270。ただしfull deploy E2E N6は未計測でrevision中。影丸配備は118s、memory_context 41.470s/report_publication9.581s/semantic_context6.411s |
| C1-06 | 未修正 | 共有mainのremote divergenceでpushがnon-fast-forward | 将軍セッションで2回、fetch+merge+conflict解決に約10分。push前remote generation/CASと共有worktree収束が未統一。C1中に記録 |

### C2 Lord input identity/routing — 2件

| ID | 状態 | root issue | 一次値 / 修正 |
|---|---|---|---|
| C2-01 | 修正済 | cross-pane routeとretry/replay identity | `61415c7af`でCodex turn_id採用。全9pane arm、実入力1、invocation_total 1、wrong-pane 0 |
| C2-02 | 未修正 | one-shot auditが外部UserPromptを3波要求 | 外部入力待ち742s、audit flow 946s。共通turn ledger/daemon未実装 |

### C3 Internal event transport — 4件

| ID | 状態 | root issue | 一次値 / 修正 |
|---|---|---|---|
| C3-01 | 修正済 | watcher lease/priorityと同一集合通知dedup | `e42ffe0c1`,`b58658756`。同一failed/stall集合の副作用1回 |
| C3-02 | 修正済 | precommit hook固定費とtruthful receipt不足 | `ca2060c28`,`29315534d`,`89fa5a3bb`。影丸実測precommit 3.914s |
| C3-03 | 未修正 | 同一reportのレビュー依頼が2経路から重複配送 | 軍師セッションで推定10件超、浪費10〜20分。`report_review`+`review_report`のevent identity/dedup不在疑い。C1中は記録のみ |
| C3-04 | 未修正 | LGTM info通知がaction不要の将軍CTXを消費 | 1セッション20件超。将軍通知はaction_required/escalationへ限定し、LGTM infoはledgerのみとする。C1中は記録のみ |

### C4 Cmd/task/report lifecycle transaction — 11件

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
| C4-10 | 未修正 | failed respawn逐次再実行がmonitor loopを占有しdone後処理を飢餓化 | failed 4名併存時、done→初回観測+199s、REPORT-FORMAT/AUTO_DEPLOY+303s、CODEX-RESPAWN+308s。failed個体の再起動自体は次周期も重複。C1中は記録のみ（`[[failed_respawn逐次再実行]] -> [[monitor_head_of_line_blocking]] -> [[done後処理303秒遅延]]`） |
| C4-11 | 未修正 | retro発火がtask終端後idleを作業時間へ算入し偽遅延化 | CI taskはdeployed→report 8分31秒でestimate10分内だがretro promptは33分34秒後に発火。「時間がかかった」一次根拠なし。deployed_at→min(done_at, report.timestamp, commit完了)へ限定すべき。C1中は記録のみ |

### C5 Knowledge reflux lifecycle — 6件

| ID | 状態 | root issue | 一次値 / 修正 |
|---|---|---|---|
| C5-01 | 未修正 | source/generated cache foreign dirtyによる反復BLOCK | L900〜L885群とL901。source +1151行、cache 123行級。deferはするが所有差分未収束 |
| C5-02 | 未修正 | old-generation supplement混入と候補世代不整合 | fingerprint抑止のみ。generation正本化commitなし |
| C5-03 | 未修正 | karo_direct refluxのcmd spec不在でformal approval不能 | 軍師がanalysis_resultへ退避。3件でapproval BLOCK。`review_approval.sh`の検索対象にdirect task正本がない。C1中は記録のみ |
| C5-04 | 部分修正 | 同一lessonの反復dispatch | L901は6忍者へ連続配備し約30分浪費+RC3件。selectorがpush前commitを反映しない疑い。`3d4d670f`を既存dirtyと分離適用した`a7e7f42c`は10/10・並列4 dispatch1・terminal再配備0だが、global CI GREEN待ちでorigin/main未統合 |
| C5-05 | 修正済 | 既存enforcement metadataのatomic writer欠落 | `e852b3edc`で`lesson_write --promote`追加。foreign dirty自体はC5-01 |
| C5-06 | 未修正 | 候補が実際にはLevel4/5未到達 | L891/L875等。偽昇格せずdecision backlog化したが実防御未実装 |

### C6 Verification/readiness semantics — 5件

| ID | 状態 | root issue | 一次値 / 修正 |
|---|---|---|---|
| C6-01 | 未修正 | test fixture symlink write-through | tracked実sourceを2行へ上書き1件。diff復旧のみ、pre-test symlink BLOCKなし |
| C6-02 | 未修正 | target GREENとglobal workflow GREENの混同 | target 8/8 PASS後、global CI 390sで別test FAIL。別field/型なし |
| C6-03 | 未修正 | review precheckのLG044/046/048が設計値を実不具合として高頻度FP | 約15件、約7.5分。WITH_CONCERNS+全yes矛盾とfixture集約疑い。C1中は記録のみ |
| C6-04 | 未修正 | campaign lane関連testの組合せ実行で結果が非決定 | 2file combined初回test31 FAILで43/44、同一combined再実行44/44・対象test単独10/10。fixture分離済みで再現せず、初回FAILのstage duration/TMPROOT/負荷証跡が消えたため分類不能。C1中は記録のみ |
| C6-05 | 未修正 | gist更新commandがrc上成功でも内容未更新 | `gh gist edit -f name < file`でsilent no-op、path指定時のみ更新。更新後content hash/remote readback検証がない。C1中は記録のみ |

## 4. カテゴリ別アウトカム

計測窓はrolling 7日間の全イベントとする。単発値をp50/p95と呼ばない。母数、source timestamp、対象集合を必須記録する。

| ID | 二値PASS条件 | 2026-07-18 baseline | 目標 | 計測source |
|---|---|---|---|---|
| C1 | latency閾値、scope逸脱0、stale registry 0 | commit dry-run N=5: p50 9.974s/p95 14.384s（6.810〜14.384s）。deploy成功receipt直近N=20: p50 41.026s/p95 234.965s（18.464〜266.209s）。registry82/stale28 | deploy p50<30s/p95<60s、commit p50<10s/p95<20s、scope逸脱0、stale0 | `logs/deploy_task.log`、scope receipt、Trace2、worktree dry-run |
| C2 | 各turn_idが意図paneへexactly once | wrong-pane既往1、外部入力待ち742s | replay/drop/wrong-pane 0、外部追加入力0 | prompt ledger、hook pane、intended pane |
| C3 | 作成済eventのdrop/重複/priority inversion 0 | 制御面CTX 86%、exactness母数未計装 | 3指標0、delivery p95<5s、CTX<20% | inbox/outbox ledger、event_id→effect ledger |
| C4 | identity保持、atomic、再入安全、eventual completion | session喪失1、再入破損1、AUTO_DONE679s、child repair trigger0/1、failed 4名併存done→AUTO_DEPLOY303s | identity100%、破損0、AUTO_DONE p95<5s、child repair100%、report→gate p95<60s | deploy transaction ledger、task revision、report/gate timestamps |
| C5 | 候補が一度だけ予約されterminalへ遷移 | L901重複6忍者、promotion在庫198〜200、週次率未計測 | duplicate0、reservation conflict0、foreign-dirty再投入0、週次消化率>50% | reservation/completion/deferred ledger |
| C6 | target/globalを別型で保持しfixture破壊0 | conflation1、symlink破壊1 | conflation0、両field欠落0、head SHA mismatch0、fixture破壊0 | GitHub job/workflow、gate decision ledger、pre-test guard |

横断品質条件は `FAIL=0 / SKIP=0 / FP=0 / FN=0 / duplicate=0 / 通知喪失=0 / 安全境界低下=0`。速度目標だけでPASSにしない。

## 5. 集中攻略順序

カテゴリを混ぜず、各waveのoutcomeが満たされてから次へ進む。

1. **Wave 1(NOW): C1 substrateのみ**。ext4 gitdir/worktree/commit-tree比較、full worktree廃止、registry収束。修正前baseline N>=5を必須とし、deploy p50<30s/p95<60s、commit p50<10s/p95<20s、scope逸脱0、stale registry 0を満たすまで他カテゴリを実装しない。
2. C2〜C6はC1完了後に殿と次Waveを選定する。C1中に得た他カテゴリ知見は本台帳へ記録のみ行う。

順序正本: gist `94145c4564055baa3f543028a69e948b` v1.2 §6（殿裁定2026-07-18 14:35）。旧C4先行順序は失効。

各waveで途中の可逆試行回数を最大化し、最終checkpointでのみ全契約・敵対試験・レビューを一度通す。

## 6. 停止時点

本書作成後は殿の指示どおり新規実装・追加配備を停止する。進行中成果は以下の状態で凍結する。

- `a7e7f42c`: `3d4d670f`の原子reservationを既存dirtyと分離統合。家老独立10/10 PASS、global CI GREEN待ちでorigin/main未統合。C5-04=部分修正。
- `eb378791f`: 41/41 PASS、GATE CLEAR、完了処理済み。
- L901 6回目配備: 即時停止・変更0件を確認。以後は`a7e7f42c`の原子reservation契約で再配備0を検証する。
- 設計再開時はWave 1(C1)から開始し、個別hotfixを先行させない。

## 7. 一次証跡

- `archive/inbox/karo_20260718.yaml:469,608,615,622,677,823,988,1001,1008`
- `queue/bulletin_board.yaml:367`
- `queue/reports/hayate_report_cmd_karo_hotfix_reflux_lesson_reservation_202607181221.yaml`
- `queue/reports/kotaro_report_cmd_karo_ci_fix_29628061796_deploy_template_commit_contract_202607181216.yaml`
- `queue/reports/kagemaru_report_cmd_karo_hotfix_prompt_event_identity_replay_202607181120.yaml`
- `queue/reports/hanzo_report_cmd_karo_hotfix_deploy_305s_control_plane_202607181110.yaml`

## 8. B1 deploy wall同一cohort E2E再計測契約

B0のN=20をそのままbeforeと呼ばない。B1前後を同一queryで再抽出し、仕事量同一性とsource timestampを先に固定してから速度を比較する。正本の目的関数・wave手順は `docs/research/throughput-mece-design-20260718.md` §8-9、本節はその再現可能な比較契約である。

### 8.1 固定field集合とevent identity

1行を1 deploy transactionとし、以下を欠く行はcohortへ入れず `invalid_schema` へ数える。

| field | 固定規則 |
|---|---|
| `event_id` | `deploy_receipt:<cmd_id>:<task_id>:<attempt>`。4要素一致を同一eventとし、重複はFAIL |
| `source_started_at/source_ended_at` | event開始とreceipt終了のUTC ISO-8601。window判定はstarted_atで統一 |
| `source_file/source_line_start/source_line_end` | `logs/deploy_task.log` の一次証跡位置 |
| `git_sha/environment_id` | 実行時SHAと環境。環境は `WSL2:/mnt/c:shogun:2` 固定 |
| `cmd_id/task_id/task_type` | before/afterで `task_type` 構成比を完全一致 |
| `phase_set` | `parse_args,task_mutations,delivery,post_verify,post_delivery`。欠落・余分・順序逆転はFAIL |
| `wall_ms/blocked_agents` | receipt総wallと仕事があり前進不能だったagent数。積をblocked-agent-seconds化 |
| `terminal_result/quality_result` | 両方PASSかつFAIL/SKIPなしだけを品質合格成果とする |

除外は `warmup=true`、運用者cancel、destructive safety停止、CI REDによるpush保留、`idle_no_work`、window境界跨ぎに限定する。timeout、retry、異常終了、品質FAIL/SKIPは除外せず分母へ残す。外れ値は除去禁止。並行負荷は `concurrency` で層別し、before/afterの `task_type×concurrency` セル件数を完全一致させる。

### 8.2 同一queryと二値判定

抽出器が生成するcanonical TSV（上記fieldに加え `concurrency,fp,fn,skip`）へ、次の同一コマンドをbefore/after各N20以上で実行する。3 timestampは実行前に固定する。

```bash
COHORT_TSV="artifacts/b1-deploy-wall/cohort.tsv"
BEFORE_START="2026-07-18T00:00:00Z"
CUTOVER="REPLACE_WITH_CI_GREEN_UTC"
AFTER_END="REPLACE_WITH_AFTER_WINDOW_UTC"
python3 - "$COHORT_TSV" "$BEFORE_START" "$CUTOVER" "$AFTER_END" <<'PY'
import csv, datetime as dt, json, math, sys
path, before_start, cutover, after_end = sys.argv[1:]
parse = lambda s: dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
b0, cut, a1 = map(parse, (before_start, cutover, after_end))
rows = list(csv.DictReader(open(path, newline=""), delimiter="\t"))
required = {"event_id","source_started_at","source_ended_at","source_file","source_line_start","source_line_end","git_sha","environment_id","cmd_id","task_id","task_type","phase_set","wall_ms","blocked_agents","concurrency","terminal_result","quality_result","fp","fn","skip"}
assert rows and required <= set(rows[0]), f"missing fields: {sorted(required-set(rows[0]))}"
assert len({r["event_id"] for r in rows}) == len(rows), "duplicate event_id"
expected = "parse_args,task_mutations,delivery,post_verify,post_delivery"
for r in rows:
    assert r["phase_set"] == expected, f"phase_set mismatch: {r['event_id']}"
    t, e = parse(r["source_started_at"]), parse(r["source_ended_at"])
    assert t < e and r["environment_id"] == "WSL2:/mnt/c:shogun:2"
    r["window"] = "before" if b0 <= t < cut else "after" if cut <= t < a1 else "out"
cohorts = {w:[r for r in rows if r["window"] == w] for w in ("before","after")}
assert all(len(v) >= 20 for v in cohorts.values()), {k:len(v) for k,v in cohorts.items()}
cells = lambda rs: sorted((r["task_type"], r["concurrency"]) for r in rs)
assert cells(cohorts["before"]) == cells(cohorts["after"]), "mixed workload cells"
def pct(xs,p):
    xs=sorted(xs); return xs[math.ceil(p*len(xs))-1]
def summarize(rs):
    wall=[int(r["wall_ms"])/1000 for r in rs]
    good=sum(r["terminal_result"] == r["quality_result"] == "PASS" and int(r["skip"]) == 0 for r in rs)
    hours=(max(parse(r["source_ended_at"]) for r in rs)-min(parse(r["source_started_at"]) for r in rs)).total_seconds()/3600
    return {"n":len(rs),"p50_s":pct(wall,.50),"p95_s":pct(wall,.95),"blocked_agent_seconds":sum(int(r["wall_ms"])*int(r["blocked_agents"])/1000 for r in rs),"quality_pass_per_hour":good/hours,"fail":sum(r["terminal_result"]!="PASS" or r["quality_result"]!="PASS" for r in rs),"skip":sum(int(r["skip"]) for r in rs),"fp":sum(int(r["fp"]) for r in rs),"fn":sum(int(r["fn"]) for r in rs)}
out={w:summarize(rs) for w,rs in cohorts.items()}
out["pass"]=(out["after"]["p95_s"] <= .8*out["before"]["p95_s"] and out["after"]["blocked_agent_seconds"] <= .8*out["before"]["blocked_agent_seconds"] and out["after"]["quality_pass_per_hour"] >= 1.2*out["before"]["quality_pass_per_hour"] and all(out[w][k] == 0 for w in ("before","after") for k in ("fail","skip","fp","fn")))
print(json.dumps(out,ensure_ascii=False,sort_keys=True))
raise SystemExit(0 if out["pass"] else 1)
PY
```

出力はbefore/after各 `N,p50,p95,blocked-agent-seconds,品質合格成果/時,FAIL,SKIP,FP,FN`。PASS条件はp95とblocked-agent-secondsが各20%以上減、品質合格成果/時1.20倍以上、FAIL/SKIP/FP/FN全0のANDである。

### 8.3 fail-closed順序

1. required CI GREENのUTCを `CUTOVER` として固定し、B1 SHA・log inode/size・query SHA256を記録する。
2. beforeを同じ抽出器で再生成し、N>=20、identity重複0、schema不正0、phase不一致0を確認する。
3. after N>=20まで通常業務を継続する。専用配備で件数を作らない。
4. cohort不足、SHA/window混在、外れ値除去、`task_type×concurrency` 不一致は即FAIL。少ない側の無作為抽出は禁止し、同一セルの自然蓄積を待つ。
5. GREEN後に上記コマンドを実行し、PASS時だけ正本§9へbefore/after/deltaを昇格する。


## 因果リンク

- `[[L901_6重配備]] -> [[非原子reservation]] -> [[atomic_promotion_reservation]]`

- `[[殿指示_MECE_throughput_design]] -> [[近視眼的hotfix]] -> [[カテゴリ集中+アウトカム計測]]`
- `[[品質合格スループット]] -> [[最初に破れた不変量]] -> [[C1-C6集中攻略]]`
