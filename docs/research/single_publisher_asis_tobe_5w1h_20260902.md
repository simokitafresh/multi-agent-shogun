<!-- gist-master: 77538fe909ed4d3b83b61b4baf99cacf single_publisher_asis_tobe_5w1h_20260902.md -->
# origin/main 単一 publisher 化 — AsIs / ToBe / 5W1H 設計書 v1.9(v1.8=殿裁定 3 点反映 13:25 → 殿指示 13:23『実装は忍者。性能の劣る LLM が混乱しない設計書。クリーンアップと速度検証まで完了して最終ゴール』を §9-§11 で反映、13:30)

- 作成: 2026-09-02 02:30 将軍(殿指示 02:16『忍者はコミットしない。コミットは家老/将軍のみ』→02:18『コミットのやり方・スキル・構造の検証』→02:24『AsIs/ToBe 5W1H 設計書。不要になる複雑さを先に検証』)
- 協議: 家老回答 blt_20260902_021944(single publisher + local commit artifact)。協議記録=`queue/notes/shogun_karo_single_committer_hypothesis_20260902_0220.md` §1-6
- 因果: `[[殿仮説_単一committer_20260902]] -> [[多重publisher_criss-cross]] -> [[single_publisher_local_commit_artifact]]`
- 一次データ取得日時: 2026-09-02 02:16-02:28(origin/main 24h log、push lane log、scripts 行数/関数数)

## §0 結論(1 行)
origin/main へ書く主体を**家老の publisher 1 本(直列 queue)**に限定し、忍者は worktree 内 local commit(成果物)まで、将軍の doc も同 queue を通す。これで merge 93/日→0、criss-cross 0、内容消失 0、root worktree 旧版 0 となり、多重 publisher の副作用に対して積まれた **約 4,900 行・bats 221 本・merge driver 5 本・pre-push guard** が不要になる。

### §0.1 殿裁定の記録(2026-09-02 13:07-13:20、事実→制約→判断→効果)
| 時刻 | 事実 | 制約 | 判断(殿) | 効果 |
|---|---|---|---|---|
| 13:07-13:10 | v1.7 家老 APPROVE 済み、root に 13:08 起動の MERGE_HEAD が残置し将軍 doc commit が BLOCK(§1.2 root 旧版の実例) | 07-21『削るな速くしろ』(削除は U8 のみ) | **採用** | U1 起票へ |
| 13:12 | 将軍の直接 commit 廃止案に対し殿『gist や小修正も禁止か。将軍と家老のみではだめか』 | gist は Gist API で git commit ではない。§2.1 原則 6 は既に『将軍 doc・家老 hotfix も同じ lease を取る』と規定 | **D10: 将軍・家老の直接 commit は lease 取得+commit 前 root 同期を条件に存続。忍者・daemon・台帳は publisher 経由** | 一本化の定義=直列 writer(lease)1。主体 3(daemon/将軍/家老)でも lease が 1 なら成立。将軍 code D0 の速度を落とさない |
| 13:14 | canary を infra→dm-signal の 2 段にする案に対し殿『DM-signal 側のリスクは。小さく可逆なら一気にやるべきでは』 | dm-signal は push→Render 自動 deploy。誤りは (a)push しない=fail-closed (b)内容差=C2a+paths 限定で publisher バグに限定、復旧=revert push 数分、DB は publisher 非接触 | **D9: canary は infra と dm-signal の両 repo を同時。unit 順序(U1→U2→U4→U5→U3 dry-run 24h→active→U6→U7→U8)は崩さない** | 一気にやるのは対象 repo、unit の飛ばしではない。dm-signal 側の消失リスク残存期間 0 |

## §1 AsIs(実測)
### 1.1 公開者(origin/main へ commit/push する主体)
| 主体 | 経路 | 24h 件数 | 所在 |
|---|---|---|---|
| 忍者 6 名 | worktree で `ninja_scope_commit.sh` → local commit(origin へは直接入らない) | 76 | scripts/ninja_scope_commit.sh(1,870 行・関数 27・option 43) |
| cmd_complete_gate(autopush) | clean clone に source-only snapshot/cumulative/insights/lessons の 4 経路で commit→push | 37 | scripts/cmd_complete_gate.sh L2047-2975(関数 19、約 1,182 行) |
| ninja_monitor push_lane | root の unpushed を CI 判定付きで push、remote_tip_not_ancestor なら isolated worktree で merge(U6) | 48(統合 merge)+PUSH | scripts/ninja_monitor.sh(関数 18、約 596 行) |
| reflux/ancestry | 『integrate … ancestry』『merge: preserve reflux source ancestry』merge | 8 | cmd_complete_gate/ninja_monitor |
| daemon auto-commit | insights auto-commit 79、ledger auto-commit 19、postclear checkpoint 27、batch context auto-commit 7 | 132 | ninja_monitor / cmd_complete_gate / clear 系 |
| 将軍 | root で `ninja_scope_commit.sh` → push lane 経由 | 70 | 同上 |
| 家老 | root で hotfix 等の commit(少) | — | 同上 |
合計: **469 commit / merge 93(20%)**。`git commit|push` を実行する script **11 本**、`git push` を持つ script **4 本**。

### 1.2 実害(2026-09-01〜02)
| 事象 | 件数 | 機構 |
|---|---|---|
| 内容消失(公開済み commit の内容が merge で消える) | 2(20594ec4e / 16d831ed9) | 忍者 worktree の古い base から autopush→ancestry merge で criss-cross(merge-base 2 個)→root 統合が純 3-way でも内容を落とす |
| root worktree 旧版(HEAD だけ進み worktree/index が旧版で staged) | 4 | U6 isolated 統合が ref のみ前進 |
| GA-PUSH1 BLOCK(未 commit と push 対象 commit の path 重複) | 3 | 台帳 daemon の常時 dirty × 他 lane の同 path commit |
| push_failed / 統合失敗(累計) | 59 / 95 | 上記の複合 |
| CI RED(契約変更の fixture census 漏れ) | 7 | 公開者と無関係(本設計の対象外・別根) |

### 1.3 AsIs の複雑さ(=本設計完成後に不要になる候補)
| 部品 | 規模(実測) | 存在理由 | ToBe で |
|---|---|---|---|
| cmd_complete_gate.sh autopush 群(source-only snapshot/cumulative equivalence/insights ID merge/lessons ID merge) | 関数 19・約 1,182 行・`ancestry` 70 箇所 | 忍者 worktree の成果を gate が直接公開するため | **不要**(publisher が唯一の公開経路) |
| ninja_monitor.sh push_lane(CI-CHECK/WAIT/INTEGRATE/AUTOCOMMIT-LEDGERS/DIRTY-WARN/CI-UNKNOWN-ADMIT) | 関数 18・約 596 行・118 箇所 | root の未 push を自動 push・遠隔 tip との統合 | **不要**(publisher が push、統合は発生しない) |
| safe_shared_main_ff.sh(ours 相当 merge 検出・既公開除外・ancestry regression BLOCK) | 437 行 | 多重 merge の後退検出 | **不要**(merge が無い) |
| .gitattributes merge 戦略(insights-id/ours/bulletin-id/karo-workarounds-id/semantic-index-regenerate)+driver 5 本 | 6 rule・driver 5 | 台帳 content conflict の自動解決 | **不要**(台帳は publisher 内 batch commit で直線) |
| pre-push GA-PUSH1 dirty-tree guard | 166 行 | push 対象と未 commit の重複防止 | **不要**(publisher は clean な isolated tree から push) |
| ninja_scope_commit.sh の option 群(--patch/--base-blob/--reflux-mode/--reflux-evidence/--repair-index/receipt/single-flight/identity sidecar) | option 43 のうち共有 index 対策由来 ≥ 20 | 共有 root index の他者 stage 混入対策 | **縮退**(忍者は自分の worktree のみ。scope 限定 add+commit の最小形へ) |
| /ninja-commit SKILL.md | 216 行(検分メモ 15+、FAIL 履歴 20) | 契約メタデータの手順説明 | **縮退**(手順 5 行: scope 確認→commit→hash 記録) |
| 報告契約の commit メタデータ(commit_hash 40 桁、cross_repo_commits 自動生成、commit_contract planned path 突合、source_sha ancestry 検査、source-only receipt) | gate_report_format FAIL の主因(2026-08-15〜27 連続) | 多経路公開の同定 | **縮退**(published_sha 1 本+path/blob receipt) |
| postclear checkpoint / ledger auto-commit / insights auto-commit / batch context auto-commit | 24h 132 commit | dirty-guard 回避・/clear 前保全 | **不要**(publisher batch に統合。/clear 前保全は worktree 内 local commit で足りる) |
| 関連 bats | 10 file・221 test | 上記の契約固定 | **縮退**(publisher 契約 test ≈ 30 本へ) |
不要化の合計(概算): **script 約 4,900 行(1,182+596+437+166+ninja_scope_commit 縮退分 ≈ 1,000+driver/auto-commit 群 ≈ 1,500)、bats ≈ 190 本、merge driver 5、hook 1、gate 検査項目 ≥ 6**。
※ 残すもの(家老レビュー 1): pre-push の **publisher identity(lease)強制**、YAML/shell/deleted-ref の品質検査は残す。旧 test は新 contract へ**不変量を移植**し、7 日 canary+`deletion_justification` の後にのみ削除する。**行数削減は目標であり AC ではない。AC=残存不変量 100%。**
※ 削除は U8(canary 後)でのみ行う。殿裁定 07-21『削るな、速くしろ』との整合: ここで削るのは「速くするために足した機構」ではなく「多重 publisher の副作用を抑えるための機構」であり、根(多重 publisher)を無くすことで**存在理由が消える**もの。存在理由が残る機構(CI RED census、report gate、receipt 契約)は触らない。

## §2 ToBe
### 2.1 原則
1. origin/main へ commit を到達させる主体は **publisher 1 プロセス**(家老 lane、直列 lock+FIFO queue)のみ。将軍・家老の doc/hotfix も同 queue。
2. 忍者は自分の worktree で **local commit(immutable 成果物)** まで。origin DAG に忍者の ancestry は入らない。成果物の定義(家老レビュー 4)=**`source_tree`(local commit の tree id)+`patch_sha`(base..source の scope 限定 patch の sha256)+`published_sha`(publisher が生成した直線 commit)**の 3 つ組。旧契約 field の写像: `commit_hash`→`source_sha`(local commit id、参照のみ)/ test receipt の `source_head`→`source_tree` / **task・AC fingerprint は指示契約の同一性、`patch_sha` は成果物の同一性=別物として両方保持** / `cross_repo_commits`→ `{repo, ref, source_sha, published_sha, path receipt}` の組(path 一覧だけに縮退しない)/ ci_fix の `source_commit`→`published_sha` / worktree cleanup→artifact 複製(C6)後に許可。
3. publisher は source commit を merge/cherry-pick せず、`base..source` の **scope 限定内容(path/blob)を最新 remote tip へ適用し新しい直線 commit** を作る(家老案)。conflict=忍者へ rebase 差し戻し(可視)。
4. 台帳(insights/bulletin/workarounds/lessons/semantic-map)は publisher 内の **独立 batch commit**(code commit と混ぜない、因果時刻を保つ)。writer は root worktree へ書かず **`$STATE_DIR/ledger_inbox/`(絶対境界)へ追記**し、publisher が batch 時に取り込む(家老レビュー 2: root porcelain を常時 0 にするため)。
5. 1 task = 1 published commit = 1 push。CI は published_sha に紐付く。
6. remote ref ごとに writer は 1 つ(lease)。lease は **remote-ref+candidate SHA+expiry** に結び付け、環境変数だけでは偽装できない。将軍 doc・家老 hotfix も同じ lease を取る。 **(v1.8 殿裁定 D10)** 将軍・家老は publisher queue を経由せず root で直接 commit してよいが、必ず (a) lease を取得し (b) commit 直前に root を origin tip へ ff 同期(D8 と同じ処理、dirty があれば所有者退避)し (c) push は lease 保持中に自分で行う(または publisher に委ねる)。lease を持たない直接 commit の push は C5 で BLOCK。

### 2.2 フロー
```
忍者 worktree: 作業 → ninja_scope_commit(最小形) → local commit S → 報告 YAML(source_sha=S, base=B, paths)
                                                     ↓ LGTM(軍師)+ACCEPT(家老)
publisher(家老 lane, 直列):  fetch tip T → isolated tree@T → apply diff(B..S | paths) → commit P → push → 報告に published_sha=P
台帳 writer: root 外 `$STATE_DIR/ledger_inbox/<ledger>/<ts>.yaml` へ追記のみ → publisher が N 分毎/ task 完了毎に取り込み batch commit "ledger: …" → push(root worktree へは書かない)
将軍 doc: root で編集 → `publish_request docs` → 同 queue → publisher が commit+push
```

### 2.3 5W1H
| | AsIs | ToBe |
|---|---|---|
| **Who** | 公開者 11 script・実質 5 主体(忍者 autopush/gate/monitor/将軍/家老) | publisher 1(家老 lane、daemon)+lease 付き直接 commit(将軍・家老、v1.8 D10)。忍者=local commit、daemon/台帳=publisher 経由 |
| **What** | merge 93/日、統合失敗 95、消失 2、旧版 4、GA-PUSH1 3 | 直線履歴(merge 0)、消失 0、旧版 0、GA-PUSH1 0 |
| **When** | 各 lane が非同期に push(CI 待ち・age 600s・ADMIT) | LGTM+ACCEPT 直後に queue 投入、直列で ≈18s/task(p90 40s)、6 同着でも最後尾 ≈108s |
| **Where** | root 共有 worktree+clean clone+isolated worktree+6 忍者 worktree の 9 箇所から origin へ | publisher の isolated tree 1 箇所のみが origin へ。root は publisher の後追い checkout(worktree 同期を publisher が行う) |
| **Why** | 忍者成果の即時公開と CI 相関を各 lane で独立に担保しようとした結果、公開者が増殖 | 公開者を 1 本にすれば merge 意味論の問題(criss-cross/3-way 後退)が構造的に消える |
| **How** | autopush 4 経路+push_lane+ancestry merge+merge driver 5+GA-PUSH1+safe_ff | `publisher.sh`(lock+queue+apply+commit+push+root sync)1 本と最小 `ninja_scope_commit` |

### 2.4 契約(二値)
- C1: origin/main の新規 commit の親数は常に 1(`git log --merges origin/main --since=<canary 開始>` = 0)。
- C2: 公開された commit の tree は、対応する忍者 source commit の scope path について blob 一致(path/blob receipt)。
- C2a: 適用前に **全変更 path で tip blob == base blob** を検証し、1 path でも異なれば publish 0 件+RC(忍者へ rebase 差し戻し)。最新 tip の同 path 変更を上書きしない(家老レビュー 2)。
- C3: 公開後 10 分以内に root worktree の HEAD == origin/main かつ `git status --porcelain | wc -l` = 0(staged/unstaged/MM/untracked すべて。台帳 writer は root 外 queue へ書くため達成可能)。
- C4: 1 task の LGTM+ACCEPT → published_sha 記録までの p90 ≤ 60s。
- C5: **publisher lease を持たない push は pre-push hook が全て BLOCK**(shell/Python/hooks/CI/人手を問わず)。`grep` による script 数の計測は補助指標。
- C6: 忍者成果物(source_tree+patch)は LGTM 時点で `$STATE_DIR/publish_queue/artifacts/<task>/` へ**複製**され、忍者 pane の停止・/new・worktree cleanup 後も publisher が復元・公開できる。
- C7: 台帳 batch commit は既存 entry の `created_at`/`ts` を 1 件も変更しない(歴史修正禁止 08-07)。
- C8: publisher 系の状態(request/lease/emergency_grant/artifacts/ledger_inbox)は**すべて `$STATE_DIR/publish_queue/`・`$STATE_DIR/ledger_inbox/` 配下**にあり、これらが tracked root へ書く file = 0(`git status --porcelain` に publisher 状態由来の行 0)。

## §3 移行(家老レビュー 3 の順序: U1→U2→U4→U5→U3(dry-run→active)→U6→U7→U8、各 unit 二値 AC、canary=infra hotfix lane)
| U | 内容 | AC(二値) | 不要化される複雑さ |
|---|---|---|---|
| U1 | non-publish queue: `$STATE_DIR/publish_queue/` に request(FIFO、flock、lease 発行)。この段階では公開せず並び順と lease のみ | 並行 request 6 件で queue 順序=投入順(FIFO 逆転 0)∧ lease の max concurrent holders = 1 ∧ overlap interval pairs = 0 ∧ lease が remote-ref+candidate SHA+expiry に結び付く | — |
| U2 | 忍者成果物=source_tree+patch_sha(報告に source_sha/base/paths)+LGTM 時に artifacts/ へ複製(C6) | 報告 gate が manifest を検証 PASS ∧ 複製後に worktree 削除しても publisher が復元可 | ninja_scope_commit option ≥ 20 |
| U4 | gate を dual-read(旧 source_sha 契約と新 published_sha+path/blob receipt の両方を受理) | 旧・新 fixture 両方 PASS | — |
| U5 | LGTM+ACCEPT を queue の admission 条件にする(未承認 request は投入不可) | 未承認 request N 件で queue admitted = 0 ∧ 承認済 N 件で admitted = N(publisher 未稼働でも計測可能な admission 判定) | — |
| U3 | publisher を dry-run(publish せず C2a/C2 判定 log のみ)→ 24h 判定差 0 で active 化。remote tip へ scope 限定適用→published_sha 生成(merge/cherry-pick 不使用) | criss-cross fixture で published tree の regression 0 ∧ C2a fixture: tip==base → publish 1 ∧ blob 一致、tip!=base → publish 0 ∧ RC 1 ∧ dry-run 24h の比較母数 N と mismatch=0 を生貼付 | safe_ff/ancestry guard |
| U6 | reflux/台帳 writer を同 queue の batch へ | 台帳 commit が code commit と分離 ∧ merge driver 未使用 | .gitattributes 6 rule・driver 5・insights auto-commit |
| U7 | autopush 4 経路/ancestry/push_lane/postclear auto-commit を flag 停止(`PUBLISHER_SINGLE=1`) | 停止後 24h で **C1-C8 全 PASS(各 C の実測 receipt を報告に生貼付)** | push_lane 596 行・autopush 1,182 行(停止) |
| U8 | canary 7 日後に旧 gate/tests/hook を削除(旧 test の不変量は新 contract test へ移植済みであること+`deletion_justification`) | bats 全 GREEN ∧ 削除 script 参照 0(rg) ∧ 移植不変量 100% | 上記の物理削除・GA-PUSH1 overlap 部・SKILL 縮退(pre-push の lease 強制・品質検査は残す) |
canary 判定: **(v1.8 殿裁定 D9)** infra と dm-signal の両 repo を U1 から同時に対象とし、U3 dry-run 24h は両 repo で並行して取り判定差 0 で同時 active 化。U7 後 24h で **C1-C8 全 PASS(両 repo それぞれの receipt)** で canary 成立。dm-signal 固有の追加検知: publish 後の Render deploy が失敗または主要 EP smoke(200)が落ちたら publisher は次 request を hold し revert request のみ admit(R4 と同型、R11)。U8 は 10 file 超の削除が見込まれるため、**削除 manifest(path・不変量の移植先・deletion_justification)を作り殿確認の上、1 batch 最大 10 file** で実施(Tier 2 STOP-AND-REPORT 準拠)。

## §4 リスクと対策(v1.3 で各リスクに二値の検知+復旧を付与)
| # | リスク | 対策(構造) | 検知(二値) | 復旧 |
|---|---|---|---|---|
| R1 | publisher 単一障害点(停止・hang) | daemon_watchdog 管理下、lease は expiry 付き(既定 120s)で自動失効。queue はファイル(`$STATE_DIR/publish_queue/<seq>_<task>.request`)なので停止中も request は残る | `$STATE_DIR/publish_queue/` の最古 request age > 300s で startup gate ALERT | watchdog が再起動→queue 先頭から再開(request は冪等: published_sha 記録済みなら skip) |
| R2 | 忍者 base が古く apply conflict(C2a 差し戻し)が増える | deploy 時に base=最新 tip を task YAML に固定、作業 60 分超は stale 警告(base 再固定はしない) | 差し戻し率 = RC 件数 / request 件数 を lane log で計測、> 20%/日で ALERT | tip blob != base blob なら**自動再 apply 禁止**、publish 0+RC のみ(C2a と完全一致)。stale 警告後の継続作業も RC で回収 |
| R3 | 将軍 doc/map の即時性低下 | publish_request は kind=doc なら将軍投入=承認(LGTM 不要)、publisher は FIFO で ≈18s | request→published p90 ≤ 60s(C4) | 遅延時は request 残置で自動追いつき |
| R4 | CI RED の帰属 | 1 request=1 commit=1 push=1 CI run。RED なら publisher は次 request を hold し ci_fix request のみ admit | RED 中の非 ci_fix publish = 0 | ci_fix GREEN で hold 解除 |
| R5 | 台帳の追記競合(insights/bulletin/workarounds/lessons) | writer は `$STATE_DIR/ledger_inbox/`(**STATE_DIR 配下が絶対境界**。tracked root への書込み 0 を二値化)に追記のみ(1 entry=1 file、ID 付き)。publisher が取り込み時に ID 重複を検出 | 同一 ID 二重 entry = 0(検出時は後着を `duplicate/` へ退避し ALERT) | 手動判定(本日 03:23 の INS-6b07 型) |
| R6 | 移行中の二重経路(旧 autopush と新 publisher が同時に生きる) | U7 まで旧経路は `PUBLISHER_SINGLE` flag で段階停止。U3 dry-run 中は新 publisher は push しない | origin merge 件数/日(C1)を U3 開始から日次記録、U7 後 0 | flag を戻せば旧経路復帰(可逆) |
| R7 | lease 偽装・迂回 push(人手・CI・hook 外) | pre-push は lease token(ref+SHA+expiry の HMAC)不在を BLOCK。環境変数 escape hatch は**設けない**。緊急時は殿承認 file(`$STATE_DIR/publish_queue/emergency_grant`: 対象 SHA+署名+単発 expiry)のみ | 承認 file なしの lease 外 push = 0、grant 使用は jsonl 記録 | grant 失効後は通常 queue へ戻す。誤 push は publisher の forward restore commit で回収 |
| R8 | root worktree と origin の乖離(旧版 staged の再発) | publisher が push 後に root を ff のみで同期し、worktree/index も更新(C3)。**unexpected dirty は他者 WIP**: 同期 BLOCK→所有者特定→artifact 退避→root 同期→**所有者専用の非 root worktree へ再適用**(root には再適用 0。所有者が root しか持たない場合は新しい隔離 worktree を作って適用し、root は clean mirror を維持)。publisher の commit へは投入しない。公開が必要なら別 request+承認 | C3 違反(porcelain ≠ 0 が 10 分超)、SYNC-BLOCK 記録に paths/所有者あり、WIP の publish 混入 = 0。**復旧完了 = root porcelain 0 ∧ artifact hash == owner worktree 適用後 hash** | 退避 artifact から owner worktree へ再適用(公開は承認済 request のみ) |
| R9 | 忍者成果物の消失(pane 停止/new/worktree cleanup) | LGTM 時に artifacts/ へ複製(C6) | 複製なしの cleanup = 0 | artifacts/ から再 apply |
| R10 | U8 での過剰削除(『削るな速くしろ』違反) | 削除 manifest+不変量移植先+deletion_justification+殿確認+1 batch ≤10 file | manifest 未記載の削除 = 0 | 削除 manifest から **forward restore commit を publisher 経由で作成**(D012 整合、revert 直接実行はしない) |
| R11 | (v1.8) dm-signal で publish 後の Render deploy 失敗・smoke 落ち | publisher は published_sha ごとに Render deploy 状態と主要 EP smoke を記録 | deploy failed または smoke≠200 が 1 件 | 次 request hold、revert request のみ admit(D7 同型)。revert push で数分復旧 |
| R12 | (v1.8) 将軍・家老の直接 commit が root 旧版を再生産 | lease 取得 script が commit 前に root を tip へ ff 同期し dirty は所有者退避(D8) | 直接 commit 後 60s 以内に root HEAD==origin ∧ porcelain 0(C3 と同基準) | 同期失敗は commit BLOCK(fail-closed)、退避 artifact から再適用 |

## §6 未決事項の決定(v1.5、将軍決定。殿裁定事項は明示)
| # | 事項 | 決定 | 根拠 |
|---|---|---|---|
| D1 | publisher の実行主体 | ninja_monitor とは別 daemon `scripts/publisher.sh`(daemon_watchdog 登録)。家老は監督(queue 監視・差し戻し判断)であり手動 commit はしない | 家老 pane の CTX/待ちに publish を依存させない。家老 lane=責務、daemon=実行 |
| D2 | queue 形式 | `$STATE_DIR/publish_queue/<epoch>_<seq>_<task_id>.request`(**tracked root の外**。root 配下に置く場合は .gitignore 登録を AC 化)(YAML: task_id, source_sha, source_tree, patch_sha, base, paths[], approvals{gunshi,karo}, kind=code/doc/ledger) | ファイル=永続、FIFO は名前順、flock 1 本。queue が root を dirty 化しない(C3 整合) |
| D3 | lease | `$STATE_DIR/publish_queue/lease`(ref, candidate_sha, expiry, hmac)。TTL 120s、更新は publisher のみ | R1/R7 |
| D4 | apply 方式 | `git diff base..source -- paths` の patch を isolated tree@tip へ `git apply --index`、C2a 事前検査で tip blob==base blob | merge/cherry-pick を使わない=criss-cross 0 |
| D5 | doc/map の承認 | kind=doc は将軍投入=承認(LGTM 不要)だが **path allowlist**(docs/、context/、queue/shogun_todo_map.md 等)を強制し、allowlist 外 path を含む doc request の admit = 0(code 偽装 0 を AC 化)。kind=code は LGTM+ACCEPT 必須 | R3、偽装防止 |
| D6 | 台帳 batch 間隔 | task 完了毎+最大 5 分毎、1 batch=1 commit "ledger: <ledgers> <n entries>" | C7・因果時刻 |
| D7 | CI RED 時 | hold+ci_fix のみ admit(R4)。殿裁定 08-30『CI 待ち禁止』との整合: push 済み request は待たない、hold は次 request の admit のみ | 現行裁定と整合 |
| D8 | root 同期 | publisher が push 後に root で ff+worktree/index 同期。unexpected dirty は同期 BLOCK+所有者/paths 記録+artifact 退避→root 同期→**所有者専用の非 root worktree へ再適用**(root へは 0、必要なら隔離 worktree 新設。復旧完了 = root porcelain 0 ∧ artifact hash == owner worktree 適用後 hash) | C3、他者 WIP は退避+再適用で保全・未レビュー公開 0 |
| D9 | canary 範囲 | **殿裁定 13:14: infra と dm-signal の両 repo を同時**(unit 順序は不変)。v1.7 案『infra→U5 後に dm-signal』は撤回 | dm-signal 側の誤りは fail-closed か revert 数分で可逆、DB 非接触。段階化は判定期間を倍にし消失リスクを残すだけ |
| D10 | 将軍・家老の直接 commit | **殿裁定 13:12: 存続**。条件=lease 取得+commit 前 root ff 同期(D8 同処理)+lease 保持中 push(C5)。忍者・daemon・台帳は publisher 経由。v1.7 案『廃止し kind=doc request』は撤回。gist(Gist API)は本設計の対象外 | 一本化の定義は『直列 writer(lease)=1』であり主体数ではない。家老レビュー『2 publisher は一本化でない』は lease 無しの直接 commit への指摘で、lease 付きなら充足 |
| D11 | 旧 field の扱い | `commit_hash` は `source_sha` の別名として U4 dual-read 期間のみ受理、U8 で `published_sha` 必須へ | 移行の可逆性 |
| D12 | 忍者の worktree base | deploy 時 origin/main tip、task YAML に `base_sha` 固定。60 分超で再固定通知 | R2 |

## §7 実装 LLM(忍者 GPT/Claude)のピットフォール(本日の一次事象から)
| # | ピットフォール | 実例(本日) | 設計・AC での封じ方 |
|---|---|---|---|
| P1 | 契約変更を fixture/caller を census せずに出す | CI RED 7 回(#1-#6 は census 漏れ)、identity envelope guard で monitor 通知 191 BLOCK | AC に『変更 script を参照する tests/ と caller を rg で列挙し件数を生貼付、全 PASS』を必須(tsumari 結論 ⑧) |
| P2 | 共有 root index/worktree を触る(他者 stage 混入・旧版 staged) | 旧版 staged 4 回、GA-PUSH1 3 回 | 忍者は自分の worktree のみ(publisher が root 同期)。ninja_scope_commit 最小形は root で実行不可(worktree 判定で BLOCK) |
| P3 | 検証環境が本番と違う(shell PATH で PASS、cron で 127) | T188 backup cron node PATH | AC に『本番と同一 env(env -i、cron 行と同一コマンド)で実走』を要求。手動 PASS は証拠にしない |
| P4 | 報告契約の充足に失敗し task failed(書式は才蔵 ci_fix の hook_failures.details。影丸 legacy outbox は **live 証明(daemon 再起動後の本番 log 二値)未達**が原因で、metadata ではない) | 才蔵 ci_fix failed(書式)、影丸 legacy outbox failed(live 証明未達) | 契約を最小化(§1.3)。残す field は report_field_set.sh が自動生成(手書き禁止) |
| P5 | 古い base から publish(autopush/ancestry) | 後退 3 回 | 忍者は publish しない(ToBe 原則 2)。base_sha 固定(D12) |
| P6 | BLOCK を迂回する(type 変更・`|| true`・別経路) | watcher の握りつぶし(S-03)、status_update 迂回(07-26) | AC に『BLOCK 時は原因を報告、迂回コード 0 件を rg で証明』 |
| P7 | 同じ成果を 2 経路で公開(exact commit と canonical receipt) | INS-6b07 二重公開(03:23) | 1 task=1 request=1 published_sha(C5+D2)。receipt は published_sha を参照するのみ |
| P8 | 文字列一致 guard の偽陽性で止まり、作業を縮退する | 本文中の guard 語で将軍 bash が本日 5 回 BLOCK(本 v1.3 の投入時にも 1 回) | 本文はファイル経由(note/scratch script)にする手順を skill に明記。guard は構造判定へ(別 unit) |
| P9 | 『完了』を出力で判定する(commit=仕事) | 影丸 T224 live 再検証 FAIL(outbox 旧本文) | AC は本番 log の二値(BLOCK 0 行/10 分、daemon 起動時刻 > commit 時刻)で判定 |
| P10 | 巨大 monolith の一部変更で他機能を壊す | cmd_complete_gate 15,920 行・monitor 15,683 行 | publisher は新規 1 file(≤ 600 行目標)、旧 monolith には flag 追加のみ(U7) |

## §8 配備時の AC ルール(本日の deploy BLOCK 実測から。家老 karo-direct・deploy_task 共通)
| # | ルール | 根拠(実測) |
|---|---|---|
| A1 | 1 unit の AC は **2 本以下**。3 本以上が本当に不可分なら top-level `serial_dependency_evidence` で独立分割不能を示す(A3 と同一機構。言い換えでの回避はしない) | 本日 3AC shard BLOCK 2 回と evidence 追加 PASS の実測 |
| A2 | AC に path を書くときは **remote tip に実在する dir/file** のみ。新規 test file は既存 dir(tests/unit)を scope にし file 名は task 本文に書く | T188 hotfix 2 回目『remote-tip target path validation failed』、cmd_4443 ac_missing_parent_path 累計昇格 |
| A3 | serial 依存があれば `serial_dependency_evidence` を task に付ける | T188 hotfix 1 回目 |
| A4 | test/CI 系 AC は『選択実行コマンド=bash scripts/run_tests.sh task <task_yaml>(または file/affected)で FAIL 0・SKIP 0』の字句 | test_ci_execution_contract |
| A5 | 契約変更(script/hook/gate)を含む unit は AC に **caller/fixture census**(rg 件数生貼付+全 PASS)を必須 | P1、CI RED 7 回 |
| A6 | daemon/cron/hook を変える unit は AC に **本番同一 env での実走**(daemon 再起動+起動時刻 > commit 時刻、cron は env -i 同一コマンド)を必須 | P3、P9 |
| A7 | 本番 log で判定する AC は『<パターン> が 10 分で 0 行』のように **期間+件数**で書く | T224 CLEAR 条件 |
| A8 | **正確な語を使う。言い換えによる guard 回避は禁止**(gate 迂回の変形)。push を伴う task は `push_allowed: true` 等の構造 field を task に明示し、文字列 guard 側を構造判定(field 参照)へ改修する(別 unit)。それまで偽陽性に当たったら迂回せず原因を報告 | 家老レビュー 7: 言い換え=guard 回避。deepdive causal_tracing Phase 6 |
| A9 | hotfix task に **`rollback_plan` field**(AC 本文ではなく task top-level)。内容は flag off または forward restore(revert sha 直書きは禁止=D012/歴史修正禁止と整合) | 可逆性(殿 07-10)、D012 |
| A10 | 新規 test を残すなら `test_necessity` 必須、残さないなら同 task 内で削除(default-delete) | CLAUDE.md Test Rules |

## §9 忍者実装仕様(unit ごと。性能の劣る LLM が誤解しない形=触る file・作る file・入出力・禁止・二値完了・停止条件を全て列挙。家老はこの節を task YAML の AC/command へ**そのまま**写す)

### 9.0 全 unit 共通(task YAML の先頭に必ず入れる)
- **3 つの tree を混同するな**: (1) `root`=`/home/simokitafresh/multi-agent-shogun`(共有。忍者は**読み取りのみ**、書込み・commit・stash・checkout 禁止) (2) `自分の worktree`=deploy_task が作る `/tmp/...`(ここでだけ編集・commit) (3) `isolated tree`=publisher が作る一時 clone(忍者は触らない)。
- **旧経路を触るな**: `scripts/cmd_complete_gate.sh` の autopush 関数群、`scripts/ninja_monitor.sh` の push_lane、`scripts/safe_shared_main_ff.sh`、`.gitattributes` の merge driver は **U7 まで 1 行も変更禁止**(並走期間の二重経路を壊す)。変更が必要に見えたら止まって報告。
- **lease は環境変数ではない**: `$STATE_DIR/publish_queue/lease` file の中身(ref, candidate_sha, expiry, hmac)。環境変数で lease を名乗る実装は禁止。
- **STATE_DIR は tracked root の外**: `$STATE_DIR` 未設定なら `scripts/lib/state_dir.sh` から取る。root 配下に queue/lease/artifacts を作った時点で FAIL。
- **成果物の定義**: 自分の worktree の local commit(`ninja_scope_commit.sh -- <paths>`)まで。push 禁止(pre-push が BLOCK する。BLOCK されたら正常=報告に書く)。
- **停止条件(共通)**: (a) 触ってよい file 以外に差分が出た (b) bats が 1 本でも FAIL/SKIP (c) 仕様に無い判断が必要になった。いずれも**止めて報告**、推測で進めない。
- **報告 YAML**: `source_sha`(local commit 40 桁)、`base_sha`(task YAML の値をそのまま)、`paths[]`(変更 path 全列挙)。commit_hash 欄は source_sha と同値を書く(U4 dual-read 期間)。

### 9.1 unit 別仕様
| U | 作る file(新規) | 触ってよい既存 file | 入出力(関数/CLI 契約) | 禁止 | 二値完了(bats 名) | 停止条件 |
|---|---|---|---|---|---|---|
| U1 | `scripts/publisher_queue.sh`(enqueue/dequeue/peek/lease-acquire/lease-release/lease-status)、`tests/unit/test_publisher_queue.bats` | なし | `enqueue <request.yaml>`→`$STATE_DIR/publish_queue/<epoch>_<seq>_<task_id>.request` を作り stdout に path。`dequeue`→FIFO 先頭 path(空なら rc=3)。`lease-acquire <ref> <sha>`→lease file 作成(既存有効 lease あれば rc=4)。`lease-release`。全操作 `flock` 下 | publish(push)しない。root へ書かない。既存 script を import しない | 並行 6 request で順序=投入順(逆転 0)∧ lease 同時保持 1 ∧ TTL 120s 経過で失効 ∧ root porcelain 差分 0。bats 6 本 | STATE_DIR が root 配下を指す |
| U2 | `scripts/publish_artifact.sh`(capture/restore)、`tests/unit/test_publish_artifact.bats` | `scripts/gates/gate_report_format.sh`(manifest 検証 1 関数追加のみ) | `capture <task_id> <worktree> <base> <source_sha>`→`$STATE_DIR/publish_queue/artifacts/<task_id>/{patch.diff,manifest.yaml}`(manifest: source_sha, source_tree, patch_sha, base, paths[])。`restore <task_id> <dest_tree>`→patch 適用。gate は報告の source_sha/base/paths と manifest 一致を検証 | worktree を削除しない。root へ適用しない | capture 後に worktree を rm しても restore で tree id 一致 ∧ manifest 不一致は gate FAIL。bats 5 本 | patch が空(paths 0) |
| U4 | `tests/unit/test_gate_dual_read.bats` | `scripts/cmd_complete_gate.sh`(report 読取り 1 関数: `commit_hash` 無く `published_sha`+receipt があれば受理。**autopush 関数は不変更**) | 旧報告(commit_hash)と新報告(published_sha+path/blob receipt)の両 fixture で CLEAR | autopush/ancestry 関数へ差分 0(`git diff -- scripts/cmd_complete_gate.sh` の hunk が読取り関数のみ) | 旧 fixture PASS ∧ 新 fixture PASS ∧ autopush 関数 hunk 0。bats 4 本 | 差分が読取り関数外に及ぶ |
| U5 | `scripts/publisher_admit.sh`、`tests/unit/test_publisher_admit.bats` | `scripts/publisher_queue.sh`(enqueue 前に admit を呼ぶ 1 行) | `admit <request.yaml>`→`review_approvals/reports/<key>/{gunshi,karo}.yaml` の両方存在で rc=0、不足なら rc=5+不足名。kind=doc(将軍投入)は将軍 identity+path allowlist(`docs/ context/ queue/shogun_todo_map.md`)で rc=0、allowlist 外 path 混入は rc=6 | 承認 file を自分で作らない | 未承認 N 件 admitted 0 ∧ 承認 N 件 admitted N ∧ doc allowlist 外 admitted 0。bats 5 本 | 承認 file の path 規約が現物と違う |
| U3 | `scripts/publisher.sh`(daemon: loop{dequeue→lease→isolated tree@tip→C2a 検査→apply→commit→(dry-run なら log のみ/active なら push)→root ff 同期→lease-release})、`tests/unit/test_publisher.bats`、`config/daemon_watchdog` 登録 1 行 | `scripts/daemon_watchdog.sh`(登録 1 行) | `PUBLISHER_MODE=dry-run|active`(既定 dry-run)。C2a: 全 paths で `git rev-parse tip:<path>` == manifest の base blob、不一致は request を `rc/` へ移動+家老 inbox 1 通。commit は `git commit-tree`(親 1)。root 同期は `git -C root merge --ff-only`、dirty なら同期 BLOCK+所有者 paths を log(D8) | merge/cherry-pick/rebase を使わない。active で push する前に dry-run 24h の receipt(判定差 0)を家老が確認 | criss-cross fixture で親 1 の commit ∧ C2a 不一致で publish 0+RC ∧ dry-run で push 0 ∧ root 同期後 porcelain 0。bats 8 本 | `git merge`/`cherry-pick` を書きたくなった |
| U6 | `scripts/ledger_writer.sh`(append)、`tests/unit/test_ledger_writer.bats` | `scripts/insight_write.sh`・`scripts/bulletin_write.sh`・`scripts/lesson_write.sh`・`scripts/karo_workaround_write.sh`(各 1 行: root file 追記→`ledger_writer append <ledger> <entry.yaml>` へ) | append→`$STATE_DIR/ledger_inbox/<ledger>/<ts>_<id>.yaml`。publisher が 5 分毎/ task 完了毎に取込み `ledger: <names> <n>` commit | 既存 entry の ts/created_at を変更しない(C7) | 各 writer で root porcelain 差分 0 ∧ 取込み後 ID 重複 0 ∧ 既存 ts 変更 0。bats 6 本 | 4 writer 以外の root 書込み元が見つかった(止めて列挙報告) |
| U7 | なし | `scripts/cmd_complete_gate.sh`・`scripts/ninja_monitor.sh`(各 autopush/push_lane 入口に `[ "${PUBLISHER_SINGLE:-0}" = 1 ] && return 0` の 1 行ずつ) | flag ON で旧経路が no-op | 関数本体を消さない(削除は U8) | flag ON 24h で C1-C8 全 PASS(receipt 生貼付) | flag ON 中に merge が 1 件でも出た |
| U8 | `docs/research/single_publisher_cleanup_manifest_20260902.md`(§10 を実行結果で更新) | §10 manifest に列挙した file のみ | manifest 1 行=1 削除単位。各行の移植先 contract test が GREEN であることを削除前に確認 | manifest に無い file を触らない。1 batch 10 file 超 | bats 全 GREEN ∧ 削除 script 参照 0(rg) ∧ manifest 全行 done。1 batch ごとに報告 | 参照 0 でない file が 1 つでもある |

## §10 クリーンアップ manifest(U8 で実行。忍者は判断せず本表を上から実行する。殿確認後に着手、1 batch ≤10 file)
| # | 対象 | 削除/縮退 | 不変量の移植先(先に GREEN 必須) | deletion_justification |
|---|---|---|---|---|
| M1 | `scripts/cmd_complete_gate.sh` autopush 関数群(source-only snapshot / cumulative equivalence / insights ID merge / lessons ID merge、約 1,182 行) | 削除 | `tests/unit/test_publisher.bats`(C2 blob 一致・親 1) | publisher が唯一の公開経路。U7 で 24h no-op 済み |
| M2 | `scripts/ninja_monitor.sh` push_lane(CI-CHECK/WAIT/INTEGRATE/AUTOCOMMIT-LEDGERS/DIRTY-WARN/CI-UNKNOWN-ADMIT、約 596 行) | 削除 | `test_publisher.bats`(R4 hold)・`test_ledger_writer.bats` | 同上 |
| M3 | `scripts/safe_shared_main_ff.sh`(437 行) | 削除 | `test_publisher.bats`(merge 0 なら後退検出の対象が無い) | merge が発生しない |
| M4 | `.gitattributes` merge rule 6+driver 5 本 | 削除 | `test_ledger_writer.bats`(ID 重複 0) | 台帳は直線 batch commit |
| M5 | pre-push GA-PUSH1 dirty-tree guard(166 行) | 削除 | pre-push lease 検査(C5)は**残す** | publisher は clean isolated tree から push |
| M6 | `scripts/ninja_scope_commit.sh` の共有 index 対策 option(--patch/--base-blob/--reflux-mode/--reflux-evidence/--repair-index/single-flight/identity sidecar、≥20 option) | 縮退 | `test_publish_artifact.bats`(manifest 検証) | 忍者は自分の worktree のみ |
| M7 | 報告契約 metadata(cross_repo_commits 自動生成、commit_contract planned path 突合、source_sha ancestry 検査、source-only receipt) | 縮退(published_sha+receipt のみ) | `test_gate_dual_read.bats` 新 fixture | 多経路同定が不要 |
| M8 | postclear checkpoint / ledger auto-commit / insights auto-commit / batch context auto-commit | 削除 | `test_ledger_writer.bats` | publisher batch に統合 |
| M9 | `skills/ninja-commit/SKILL.md`(216 行→手順 5 行) | 縮退 | — | 契約 metadata 縮退に追従 |
| M10 | 関連 bats(10 file・221 test のうち M1-M8 の契約固定分 ≈190) | 削除 | 各行の移植先(≈30 本) | 不変量は移植済み。移植の対応表を manifest 実行結果に残す |
残すもの(削除禁止): pre-push の lease 強制(C5)、YAML/shell/deleted-ref 品質検査、CI RED census、report gate、receipt 契約、D001-009。

## §11 速度・件数の検証(before は 2026-09-02 13:25 実測。after は U7 flag ON 24h 後と U8 完了後の 2 回、同一コマンドで採る)
| 指標 | 計測コマンド | before(09-02 13:25) | after 目標 |
|---|---|---|---|
| merge 件数/24h | `git log --merges origin/main --since='24 hours ago' --oneline \| wc -l` | **141**(commit 643 中) | 0 |
| push 失敗/24h | `grep -hE 'push_failed\|PUSH-FAIL' logs/ninja_monitor_push_lane.log \| grep -c <日付>` | **100** | 0 |
| INTEGRATE(遠隔統合)/24h | `grep -h INTEGRATE logs/ninja_monitor_push_lane.log \| grep -c <日付>` | **382** | 0(機構削除) |
| GA-PUSH1 BLOCK/24h | `grep -rh GA-PUSH1 logs/*.log \| grep -c BLOCK` | **29** | 0(機構削除) |
| pre-push wall ms | `grep -oE 'pre_push_wall_ms=[0-9]+' logs/ninja_monitor.log`→median/p90 | **median 370 / p90 8,873**(n=19) | p90 ≤ 1,000 |
| LGTM+ACCEPT→published p90 | publisher log の request ts→published ts | (旧経路は同定不能=計測不能、これ自体が AsIs の欠陥) | ≤ 60s(C4) |
| root porcelain 0 到達 | 公開後 `git status --porcelain \| wc -l` を 60s 間隔 | 旧版 4 件/日(§1.2) | 公開後 10 分以内 0(C3) |
| bats file 数 / 関連 test 数 | `ls tests/unit/*.bats \| wc -l` / `grep -c ^@test` 対象 file | **270 file / 対象 513 test** | 対象 ≈30 |
| 内容消失 | §1.2 と同手順(公開済み commit の blob が後続 merge で消える) | 2 件/日 | 0 |
最終ゴール(二値): U8 manifest 全行 done ∧ §11 の after が全指標で目標到達 ∧ C1-C8 全 PASS(両 repo)∧ bats 全 GREEN。ここまでで 1 工程。途中の CLEAR は途中成果(型九弾-1)。

## §5 レビュー履歴
- v1.0 → 家老 REJECT(blt_20260902_023241、方向 APPROVE・修正 5): ①inventory の残すもの明示 ②C2a/C3 porcelain 0/C5 lease BLOCK ③順序 U1→U2→U4→U5→U3→U6→U7→U8 ④成果物 3 つ組と旧 field 写像 ⑤C6/C7。→ v1.1 に全反映。
- v1.1 → 家老 REJECT(blt_20260902_023509、前回 5/5 反映確認・新規 6): ①台帳 writer は root 外 queue に統一 ②fingerprint と patch_sha は別物で両方保持、cross_repo は組で保持 ③U1 AC=max holders 1/overlap 0/FIFO 逆転 0、lease=ref+SHA+expiry ④U5 AC=未承認 N→admitted 0、承認 N→N ⑤U3 AC に C2a fixture+dry-run 母数 N/mismatch 0 ⑥canary C1-C7、U8 削除 manifest+殿確認+1 batch ≤10、原則番号修正。→ v1.2 に全反映。
- v1.2 → 家老 **APPROVE**(blt_20260902_024632、6/6 反映を現物差分で確認)。
- v1.3(殿指示 03:36 で R/D/P/A 4 節追加)→ 家老 覚醒 REJECT(blt_20260902_034259、新規 8): R2×C2a 矛盾/R7 bypass 廃止/R8・D8 dirty 退避+forward restore/R10 forward restore/D2 STATE_DIR・D5 allowlist/A1×A3 統合/A8 言い換え禁止→構造 field/A9 rollback_plan field+P4 原因訂正。→ v1.4 に全反映。
- v1.4 → 家老 REJECT(blt_20260902_034658、前回 8/8 反映確認・新規 4): ①publisher 状態 path を STATE_DIR へ統一(C8 追加) ②unexpected dirty=他者 WIP は publish へ投入せず所有者の未 commit WIP として再適用 ③ledger_inbox の絶対境界明記 ④履歴の時系列整列。→ v1.5 に全反映。
- v1.5 → 家老 REJECT(blt_20260902_034931、前回 4/4 反映確認・新規 2): ①canary/U7 を C1-C8 へ ②WIP 復元先を所有者専用の非 root worktree に限定(復旧完了の二値化)。→ v1.6 に全反映。
- v1.6 → 家老 REJECT(blt_20260902_041733、新規 2): ①U7 AC を C1-C8 全 PASS(実測 receipt)へ ②履歴の時系列再整列。→ v1.7 に全反映。
- v1.7 → 家老 **APPROVE**(blt_20260902_041853、計 7 往復)。→ 殿裁定 3 点(13:07-13:20)を v1.8 に反映(§0.1)。
- v1.8(13:25 家老レビュー依頼 msg_132320)→ 殿指示 13:23『実装は忍者。性能の劣る LLM が混乱・誤解しない設計書。クリーンアップと速度検証まで最終ゴール』→ v1.9 で §9-§11 追加(v1.8 レビューは v1.9 に差替え)。

## §5.1 レビュー依頼(家老、v1.9)
観点(v1.9 新規): (12) §9 の unit 仕様は忍者が推測なしに着手・完了・停止できるか(触る file/作る file/入出力/禁止/二値/停止条件の 6 欄に空・曖昧語が無いか、家老が task YAML へそのまま写せるか) (13) §10 manifest の移植先 test が各行に実在し、残すもの(C5 lease/品質検査/CI census/report gate/receipt/D001-009)が manifest に混入していないか (14) §11 の before 値と計測コマンドが再現可能か、after 目標が二値か
観点(v1.8 新規): (9) D10 lease 付き直接 commit(将軍・家老)が C1/C3/C5 と矛盾しないか、R12 の同期 script は D8 と同一実装で足りるか (10) D9 両 repo 同時 canary で R11(Render deploy/smoke hold)の検知が二値か、dm-signal 側に publisher 非接触でない経路(migration/recalc)が混入しないか (11) §0.1 裁定記録が事実→制約→判断→効果で欠落なく、v1.7 案の撤回が本文全体で整合しているか(残存する『廃止』『U5 後』表現 0)
(以下 v1.7 観点、参考)
観点: (5) §4 R1-R10 の検知・復旧が二値か (6) §6 D1-D12 のうち将軍が決めてよい範囲を越えていないか(殿裁定は D9/D10 のみ) (7) §7 P1-P10 に本日事象の漏れ (8) §8 A1-A10 が deploy_task/karo-direct の現行 gate と矛盾しないか。
観点: (1)§1.3 不要化 inventory の過不足(削ってはいけないものが混ざっていないか、殿 07-21『削るな速くしろ』との整合) (2)§2.3/2.4 の契約が二値か (3)§3 の順序・AC・canary 範囲 (4)壊れる契約の列挙漏れ(blt_021944 の 13 項目と突合)。
