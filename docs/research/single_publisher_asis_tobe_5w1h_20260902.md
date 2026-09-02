<!-- gist-master: 77538fe909ed4d3b83b61b4baf99cacf single_publisher_asis_tobe_5w1h_20260902.md -->
# origin/main 単一 publisher 化 — AsIs / ToBe / 5W1H 設計書 v2.4(家老 v2.3 REJECT 観点 22-24 を反映、14:12)

- 作成: 2026-09-02 02:30 将軍(殿指示 02:16『忍者はコミットしない。コミットは家老/将軍のみ』→02:18『コミットのやり方・スキル・構造の検証』→02:24『AsIs/ToBe 5W1H 設計書。不要になる複雑さを先に検証』)
- 協議: 家老回答 blt_20260902_021944(single publisher + local commit artifact)。協議記録=`queue/notes/shogun_karo_single_committer_hypothesis_20260902_0220.md` §1-6
- 因果: `[[殿仮説_単一committer_20260902]] -> [[多重publisher_criss-cross]] -> [[single_publisher_local_commit_artifact]]`
- 一次データ取得日時: 2026-09-02 02:16-02:28(origin/main 24h log、push lane log、scripts 行数/関数数)

## §0 結論(1 行)
origin/main へ書く主体を **lease 1 本で直列化された writer**(publisher daemon=家老 lane、および lease 取得+root 同期を条件とする将軍・家老の直接 commit)に限定し、忍者は worktree 内 local commit(成果物)まで、daemon・台帳は publisher 経由とする。これで merge 93/日→0、criss-cross 0、内容消失 0、root worktree 旧版 0 となり、多重 publisher の副作用に対して積まれた **約 4,900 行・bats 221 本・merge driver 5 本・pre-push guard** が不要になる。

### §0.1 殿裁定の記録(2026-09-02 13:07-13:20、事実→制約→判断→効果)
| 時刻 | 事実 | 制約 | 判断(殿) | 効果 |
|---|---|---|---|---|
| 13:07-13:10 | v1.7 家老 APPROVE 済み、root に 13:08 起動の MERGE_HEAD が残置し将軍 doc commit が BLOCK(§1.2 root 旧版の実例) | 07-21『削るな速くしろ』(削除は U8 のみ) | **採用** | U1 起票へ |
| 13:12 | 将軍の直接 commit 廃止案に対し殿『gist や小修正も禁止か。将軍と家老のみではだめか』 | gist は Gist API で git commit ではない。§2.1 原則 6 は既に『将軍 doc・家老 hotfix も同じ lease を取る』と規定 | **D10: 将軍・家老の直接 commit は lease 取得+commit 前 root 同期を条件に存続。忍者・daemon・台帳は publisher 経由** | 一本化の定義=直列 writer(lease)1。主体 3(daemon/将軍/家老)でも lease が 1 なら成立。将軍 code D0 の速度を落とさない |
| 13:14 | canary を infra→dm-signal の 2 段にする案に対し殿『DM-signal 側のリスクは。小さく可逆なら一気にやるべきでは』 | dm-signal は push→Render 自動 deploy。誤りは (a)push しない=fail-closed (b)内容差=C2a+paths 限定で publisher バグに限定、復旧=revert push 数分。DB は backend 起動時の create_all+run_migrations で変わり得る(R13 で分離) | **D9: canary は infra と dm-signal の両 repo を同時。unit 順序(U1→U2→U4→U5→U3 dry-run 24h→active→U6→U7→U8)は崩さない** | 一気にやるのは対象 repo、unit の飛ばしではない。dm-signal 側の消失リスク残存期間 0 |

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
1. origin/main へ commit を到達させる経路は **lease 1 本**で直列化する。lease を取れる主体は publisher daemon(家老 lane、FIFO queue)と、将軍・家老の直接 commit wrapper(U1b)の 2 種のみ。忍者・daemon 群・台帳 writer は lease を取れない(publisher 経由)。
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
将軍/家老 直接 commit: root で編集 → `scripts/publish_direct_commit.sh -m <msg> -- <paths>`(lease 取得→root ff 同期→scope commit→push→lease 解放、U1b)。将軍が queue に載せたい時は kind=doc request も可(任意)
```

### 2.3 5W1H
| | AsIs | ToBe |
|---|---|---|
| **Who** | 公開者 11 script・実質 5 主体(忍者 autopush/gate/monitor/将軍/家老) | lease 1 本: publisher daemon(家老 lane)+直接 commit wrapper(将軍・家老)。忍者=local commit、daemon/台帳=publisher 経由 |
| **What** | merge 93/日、統合失敗 95、消失 2、旧版 4、GA-PUSH1 3 | 直線履歴(merge 0)、消失 0、旧版 0、GA-PUSH1 0 |
| **When** | 各 lane が非同期に push(CI 待ち・age 600s・ADMIT) | LGTM+ACCEPT 直後に queue 投入、直列で ≈18s/task(p90 40s)、6 同着でも最後尾 ≈108s |
| **Where** | root 共有 worktree+clean clone+isolated worktree+6 忍者 worktree の 9 箇所から origin へ | publisher の isolated tree と、lease 付き直接 commit(将軍・家老、root)の 2 箇所のみが origin へ。root は publisher の後追い ff 同期(U1b は同期後に commit) |
| **Why** | 忍者成果の即時公開と CI 相関を各 lane で独立に担保しようとした結果、公開者が増殖 | 公開者を 1 本にすれば merge 意味論の問題(criss-cross/3-way 後退)が構造的に消える |
| **How** | autopush 4 経路+push_lane+ancestry merge+merge driver 5+GA-PUSH1+safe_ff | `publisher.sh`(lock+queue+apply+commit+push+root sync)1 本と最小 `ninja_scope_commit` |

### 2.4 契約(二値)
- C1: origin/main の新規 commit の親数は常に 1(`git log --merges origin/main --since=<canary 開始>` = 0)。
- C2: 公開された commit の tree は、対応する忍者 source commit の scope path について blob 一致(path/blob receipt)。
- C2a: 適用前に **全変更 path で tip blob == base blob** を検証し、1 path でも異なれば publish 0 件+RC(忍者へ rebase 差し戻し)。最新 tip の同 path 変更を上書きしない(家老レビュー 2)。
- C3: 公開後 10 分以内に root worktree の HEAD == origin/main かつ `git status --porcelain --untracked-files=no | wc -l` = 0(tracked の staged/unstaged/MM。untracked は対象外=現 root に 5,981 file あり到達不能なため。ただし untracked と ff で入る path の衝突は U3 で同期前 BLOCK)。
- C4: 1 task の LGTM+ACCEPT → published_sha 記録までの p90 ≤ 60s。
- C5: **lease を持たない push は origin に到達しない**。一次防御=credential(D13: 既定の git 認証は read-only、書込み認証は publisher/wrapper が lease 保持中だけ環境変数で注入)、二次=pre-push hook の lease 検査(U1c、hook が届く場所での早期通知)。同一 Unix user 内では『悪意の迂回』は防げず、防ぐのは『hook の無い clone/script からの誤 push』(§13 H1、観点 23)。判定=lease なし push の 403/BLOCK 件数 = 試行件数。
- C6: 忍者成果物(source_tree+patch)は **report_received 時点**(H7)で `$STATE_DIR/publish_queue/artifacts/<task>/` へ**複製**され、忍者 pane の停止・/new・worktree cleanup 後も publisher が復元・公開できる。
- C7: 台帳 batch commit は既存 entry の `created_at`/`ts` を 1 件も変更しない(歴史修正禁止 08-07)。
- C8: publisher 系の状態(request/lease/emergency_grant/artifacts/ledger_inbox)は**すべて `$STATE_DIR/publish_queue/`・`$STATE_DIR/ledger_inbox/` 配下**にあり、これらが tracked root へ書く file = 0(`git status --porcelain` に publisher 状態由来の行 0)。

## §3 移行(家老レビュー 3 の順序: U1→U2→U4→U5→U3(dry-run→active)→U6→U7→U8、各 unit 二値 AC、canary=infra と dm-signal の両 repo 同時(殿裁定 D9))
| U | 内容 | AC(二値) | 不要化される複雑さ |
|---|---|---|---|
| U1 | non-publish queue: `$STATE_DIR/publish_queue/` に request(FIFO、flock、lease 発行)。この段階では公開せず並び順と lease のみ | 並行 request 6 件で queue 順序=投入順(FIFO 逆転 0)∧ lease の max concurrent holders = 1 ∧ overlap interval pairs = 0 ∧ lease が remote-ref+candidate SHA+expiry に結び付く | — |
| U1b | 将軍・家老の直接 commit wrapper `scripts/publish_direct_commit.sh`(lease 取得→root ff 同期(D8)→`ninja_scope_commit.sh`→push→lease 解放) | 6 並行 wrapper で lease 同時保持 1 ∧ 同期失敗時 commit 0(fail-closed)∧ commit 後 60s 以内 root HEAD==origin ∧ porcelain 0 | 将軍・家老の手動 push、pre-push 手動対処 |
| U1c | C5 早期通知: `.githooks/pre-push`(`scripts/sync_git_hooks.sh` で `.git/hooks/` と publisher isolated tree・DM-signal repo へも複製、H1)に lease 検査(lease file の ref+sha+expiry+hmac が push 対象と一致しなければ exit 1)。CLI 非依存 | lease なし push 0/N BLOCK ∧ lease あり push N/N PASS ∧ Claude pane・Codex pane・素の bash の 3 経路で同結果 | GA-PUSH1 dirty-tree guard(M5) |
| U2 | 忍者成果物=source_tree+patch_sha(報告に source_sha/base/paths)+**report_received 時点**で artifacts/ へ複製(C6、H7) | 報告 gate が manifest を検証 PASS ∧ 複製後に worktree 削除しても publisher が復元可 | ninja_scope_commit option ≥ 20 |
| U4 | gate を dual-read(旧 source_sha 契約と新 published_sha+path/blob receipt の両方を受理) | 旧・新 fixture 両方 PASS | — |
| U5 | LGTM+ACCEPT を queue の admission 条件にする(未承認 request は投入不可) | 未承認 request N 件で queue admitted = 0 ∧ 承認済 N 件で admitted = N(publisher 未稼働でも計測可能な admission 判定) | — |
| U3 | publisher を dry-run(publish せず C2a/C2 判定 log のみ)→ 24h 判定差 0 で active 化。remote tip へ scope 限定適用→published_sha 生成(merge/cherry-pick 不使用) | criss-cross fixture で published tree の regression 0 ∧ C2a fixture: tip==base → publish 1 ∧ blob 一致、tip!=base → publish 0 ∧ RC 1 ∧ dry-run 24h の比較母数 N と mismatch=0 を生貼付 | safe_ff/ancestry guard |
| U6 | reflux/台帳 writer を同 queue の batch へ | 台帳 commit が code commit と分離 ∧ merge driver 未使用 | .gitattributes 6 rule・driver 5・insights auto-commit |
| U7 | autopush 4 経路/ancestry/push_lane/postclear auto-commit を flag 停止(`PUBLISHER_SINGLE=1`) | 停止後 24h で **C1-C8 全 PASS(各 C の実測 receipt を報告に生貼付)** | push_lane 596 行・autopush 1,182 行(停止) |
| U8 | canary 7 日後に旧 gate/tests/hook を削除(旧 test の不変量は新 contract test へ移植済みであること+`deletion_justification`) | bats 全 GREEN ∧ 削除 script 参照 0(rg) ∧ 移植不変量 100% | 上記の物理削除・GA-PUSH1 overlap 部・SKILL 縮退(pre-push の lease 強制・品質検査は残す) |
canary 判定: **(v1.8 殿裁定 D9)** infra と dm-signal の両 repo を U1 から同時に対象とし、U3 dry-run 24h は両 repo で並行して取り判定差 0 で同時 active 化。U7 後 24h で **C1-C8 全 PASS(両 repo それぞれの receipt)** で canary 成立。dm-signal 固有の追加検知(U3b、R11): publish 後に Render deploy(backend=dm-signal-backend / frontend=dm-signal-frontend、render.yaml の name で service id を解決)の状態を API で poll(timeout 15 分)し、live 後に smoke `GET /healthz`=200(render.yaml healthCheckPath と同一)∧`GET /api/public/showcase`=200 を確認。失敗で次 request を hold し kind=revert(対象 published_sha を `git revert` した request)のみ admit。U8 は 10 file 超の削除が見込まれるため、**削除 manifest(path・不変量の移植先・deletion_justification)を作り殿確認の上、1 batch 最大 10 file** で実施(Tier 2 STOP-AND-REPORT 準拠)。

## §4 リスクと対策(v1.3 で各リスクに二値の検知+復旧を付与)
| # | リスク | 対策(構造) | 検知(二値) | 復旧 |
|---|---|---|---|---|
| R1 | publisher 単一障害点(停止・hang) | daemon_watchdog 管理下、lease は expiry 付き(既定 120s)で自動失効。queue はファイル(`$STATE_DIR/publish_queue/<seq>_<task>.request`)なので停止中も request は残る | `$STATE_DIR/publish_queue/` の最古 request age > 300s で startup gate ALERT | watchdog が再起動→queue 先頭から再開(request は冪等: published_sha 記録済みなら skip) |
| R2 | 忍者 base が古く apply conflict(C2a 差し戻し)が増える | deploy 時に base=最新 tip を task YAML に固定、作業 60 分超は stale 警告(base 再固定はしない) | 差し戻し率 = RC 件数 / request 件数 を lane log で計測、> 20%/日で ALERT | tip blob != base blob なら**自動再 apply 禁止**、publish 0+RC のみ(C2a と完全一致)。stale 警告後の継続作業も RC で回収 |
| R3 | 将軍 doc/map の即時性低下 | publish_request は kind=doc なら将軍投入=承認(LGTM 不要)、publisher は FIFO で ≈18s | request→published p90 ≤ 60s(C4) | 遅延時は request 残置で自動追いつき |
| R4 | CI RED の帰属 | 1 request=1 commit=1 push=1 CI run。RED は request に `ci_status=red` を記録するだけで publish は継続、ci_fix request は先頭へ(H6) | RED 中の publish 停止 = 0(停止したら設計違反) | ci_fix の GREEN で `ci_status` 更新。RED 起因の revert は kind=revert request |
| R5 | 台帳の追記競合(insights/bulletin/workarounds/lessons) | writer は `$STATE_DIR/ledger_inbox/`(**STATE_DIR 配下が絶対境界**。tracked root への書込み 0 を二値化)に追記のみ(1 entry=1 file、ID 付き)。publisher が取り込み時に ID 重複を検出 | 同一 ID 二重 entry = 0(検出時は後着を `duplicate/` へ退避し ALERT) | 手動判定(本日 03:23 の INS-6b07 型) |
| R6 | 移行中の二重経路(旧 autopush と新 publisher が同時に生きる) | U7 まで旧経路は `PUBLISHER_SINGLE` flag で段階停止。U3 dry-run 中は新 publisher は push しない | origin merge 件数/日(C1)を U3 開始から日次記録、U7 後 0 | flag を戻せば旧経路復帰(可逆) |
| R7 | lease 偽装・迂回 push(人手・CI・hook 外) | pre-push は lease token(ref+SHA+expiry の HMAC)不在を BLOCK。環境変数 escape hatch は**設けない**。緊急時は殿承認 file(`$STATE_DIR/publish_queue/emergency_grant`: 対象 SHA+署名+単発 expiry)のみ | 承認 file なしの lease 外 push = 0、grant 使用は jsonl 記録 | grant 失効後は通常 queue へ戻す。誤 push は publisher の forward restore commit で回収 |
| R8 | root worktree と origin の乖離(旧版 staged の再発) | publisher が push 後に root を ff のみで同期し、worktree/index も更新(C3)。**unexpected dirty は他者 WIP**: 同期 BLOCK→所有者特定→artifact 退避→root 同期→**所有者専用の非 root worktree へ再適用**(root には再適用 0。所有者が root しか持たない場合は新しい隔離 worktree を作って適用し、root は clean mirror を維持)。publisher の commit へは投入しない。公開が必要なら別 request+承認 | C3 違反(porcelain ≠ 0 が 10 分超)、SYNC-BLOCK 記録に paths/所有者あり、WIP の publish 混入 = 0。**復旧完了 = root porcelain 0 ∧ artifact hash == owner worktree 適用後 hash** | 退避 artifact から owner worktree へ再適用(公開は承認済 request のみ) |
| R9 | 忍者成果物の消失(pane 停止/new/worktree cleanup) | LGTM 時に artifacts/ へ複製(C6) | 複製なしの cleanup = 0 | artifacts/ から再 apply |
| R10 | U8 での過剰削除(『削るな速くしろ』違反) | 削除 manifest+不変量移植先+deletion_justification+殿確認+1 batch ≤10 file | manifest 未記載の削除 = 0 | 削除 manifest から **forward restore commit を publisher 経由で作成**(D012 整合、revert 直接実行はしない) |
| R11 | (v1.8→v2.0) dm-signal で publish 後の Render deploy 失敗・smoke 落ち | U3b `scripts/publisher_deploy_check.sh`: published_sha ごとに Render API(service=render.yaml name→id)で deploy 状態 poll(timeout 15 分)→live 後 smoke(`/healthz` 200 ∧ `/api/public/showcase` 200)。結果を request に `deploy_status`/`smoke_status` として記録 | deploy≠live(timeout 含む)または smoke≠200 が 1 件 | 次 request hold、kind=revert のみ admit(D7 同型)。revert push→再 deploy で復旧、`deploy_status=live ∧ smoke=200` で hold 解除 |
| R13 | (v2.0) published commit に DB migration が含まれ revert で DB が戻らない | request 生成時に paths に `backend/app/db/` 配下(実体: `migrations.py`=run_migrations、`models.py`=`Base.metadata.create_all` の入力、`init_db.py`)があれば `db_migration=true` を付け、admit 条件に家老 ACCEPT の `migration_ack: true`(逆 migration の path または『不可逆・受容』の明記)を追加 | db_migration=true ∧ migration_ack 無しの admitted = 0 | migration_ack の逆 migration を kind=revert request と同時に投入。無い場合は殿へ報告(不可逆) |
| R12 | (v1.8) 将軍・家老の直接 commit が root 旧版を再生産 | lease 取得 script が commit 前に root を tip へ ff 同期し dirty は所有者退避(D8) | 直接 commit 後 60s 以内に root HEAD==origin ∧ porcelain 0(C3 と同基準) | 同期失敗は commit BLOCK(fail-closed)、退避 artifact から再適用 |

## §6 未決事項の決定(v1.5、将軍決定。殿裁定事項は明示)
| # | 事項 | 決定 | 根拠 |
|---|---|---|---|
| D1 | publisher の実行主体 | ninja_monitor とは別 daemon `scripts/publisher.sh`(daemon_watchdog 登録)。家老は監督(queue 監視・差し戻し判断)であり手動 commit はしない | 家老 pane の CTX/待ちに publish を依存させない。家老 lane=責務、daemon=実行 |
| D2 | queue 形式 | `$STATE_DIR/publish_queue/<epoch>_<seq>_<task_id>.request`(**tracked root の外**。`STATE_DIR=${SHOGUN_STATE_DIR:-$HOME/.local/share/multi-agent-shogun}` 固定、/tmp 配下は publisher 起動 rc=2(H2)。root 配下に置く場合は .gitignore 登録を AC 化)(YAML: task_id, source_sha, source_tree, patch_sha, base, paths[], approvals{gunshi,karo}, kind=code/doc/ledger) | ファイル=永続、FIFO は名前順、flock 1 本。queue が root を dirty 化しない(C3 整合) |
| D3 | lease | `$STATE_DIR/publish_queue/lease.<sha1(remote_url)>`(remote_url, ref, candidate_sha, expiry, hmac。repo ごとに別 file、H5)。TTL 120s、取得・更新できるのは publisher daemon と直接 commit wrapper(U1b)のみ。忍者 worktree からの取得は wrapper が拒否 | R1/R7 |
| D4 | apply 方式 | `git diff base..source -- paths` の patch を isolated tree@tip へ `git apply --index`、C2a 事前検査で tip blob==base blob | merge/cherry-pick を使わない=criss-cross 0 |
| D5 | doc/map の承認 | kind=doc は将軍投入=承認(LGTM 不要)だが **path allowlist**(docs/、context/、queue/shogun_todo_map.md 等)を強制し、allowlist 外 path を含む doc request の admit = 0(code 偽装 0 を AC 化)。kind=code は LGTM+ACCEPT 必須 | R3、偽装防止 |
| D6 | 台帳 batch 間隔 | task 完了毎+最大 5 分毎、1 batch=1 commit "ledger: <ledgers> <n entries>" | C7・因果時刻 |
| D7 | CI RED 時 | **記録のみ、publish は止めない**(殿裁定 08-30『CI green を待つのは諸悪の根源』、H6)。ci_fix request は FIFO を追い越し先頭へ。hold は R11(deploy 失敗/smoke)と R13(migration 未 ack)のみ | 裁定整合。RED は ci_fix lane が並行で解く |
| D8 | root 同期 | publisher が push 後に root で ff+worktree/index 同期。unexpected dirty は同期 BLOCK+所有者/paths 記録+artifact 退避→root 同期→**所有者専用の非 root worktree へ再適用**(root へは 0、必要なら隔離 worktree 新設。復旧完了 = root porcelain 0 ∧ artifact hash == owner worktree 適用後 hash) | C3、他者 WIP は退避+再適用で保全・未レビュー公開 0 |
| D9 | canary 範囲 | **殿裁定 13:14: infra と dm-signal の両 repo を同時**(unit 順序は不変)。v1.7 案『infra→U5 後に dm-signal』は撤回 | dm-signal 側の誤りは fail-closed か revert 数分で可逆。**DB は『非接触』ではない**(家老レビュー観点 10): backend 起動時に `app/main.py`→`db/init_db.py`→`run_migrations()` が走るため、published commit が `backend/app/db/` 配下(migrations.py / models.py / init_db.py)を含めば deploy で DB が変わり revert では戻らない。対策=R13(migration 含有 request の分離)。段階化は判定期間を倍にし消失リスクを残すだけ |
| D10 | 将軍・家老の直接 commit | **殿裁定 13:12: 存続**。条件=lease 取得+commit 前 root ff 同期(D8 同処理)+lease 保持中 push(C5)。忍者・daemon・台帳は publisher 経由。v1.7 案『廃止し kind=doc request』は撤回。gist(Gist API)は本設計の対象外 | 一本化の定義は『直列 writer(lease)=1』であり主体数ではない。家老レビュー『2 publisher は一本化でない』は lease 無しの直接 commit への指摘で、lease 付きなら充足 |
| D11 | 旧 field の扱い | `commit_hash` は `source_sha` の別名として U4 dual-read 期間のみ受理、U8 で `published_sha` 必須へ | 移行の可逆性 |
| D13 | push 認証の分離(H1) | **最終決定は殿**(§13 も同じ)。同一 Unix user(全 pane・daemon が simokitafresh)のため file mode では権限分離にならない(観点 23)。∴目的を『悪意の迂回防止』ではなく『hook の無い clone/script からの誤 push を構造的に 403 にする』と定義し直す。案 A(推奨): git の `credential.https://github.com.helper` を read-only fine-grained PAT(contents:read、両 repo)の store へ差替え(既定=読み取り)。書込み PAT(contents:write)は `$STATE_DIR/publish_queue/push_token`(mode 600)に置き、publisher/wrapper が lease 保持中だけ `GIT_CONFIG_PARAMETERS` で helper を差し替えて push。gh CLI の token(scopes gist/repo/workflow)は gh api 用に不変=`gist_share.sh`/`gist_sync.sh` は `gh api` のみで git を使わない(rg 0)ため無影響、CI は GITHUB_TOKEN で無影響、Render は pull で無影響。副作用=殿の手動 push は殿専用 token または wrapper 経由。案 B: publisher を別 Unix user で常駐(殿が作成・systemd user unit)し書込み token をその user だけに置く=真の権限分離だが、agent は sudo 不可(D005)のため起動・更新・log 閲覧が殿依存になる | 案 A は可逆(helper 設定を戻す)。案 B は構造最強だが運用が殿に依存 |
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
- **STATE_DIR は tracked root の外**: `STATE_DIR` は `SHOGUN_STATE_DIR` 環境変数(`scripts/inbox_watcher.sh` と同じ解決順: `SHOGUN_STATE_DIR`→`IDLE_FLAG_DIR`→`/tmp`)。root 配下に queue/lease/artifacts を作った時点で FAIL。
- **成果物の定義**: 自分の worktree の local commit(`ninja_scope_commit.sh -- <paths>`)まで。push 禁止(pre-push が BLOCK する。BLOCK されたら正常=報告に書く)。
- **停止条件(共通)**: (a) 触ってよい file 以外に差分が出た (b) bats が 1 本でも FAIL/SKIP (c) 仕様に無い判断が必要になった。いずれも**止めて報告**、推測で進めない。
- **報告 YAML**: `source_sha`(local commit 40 桁)、`base_sha`(task YAML の値をそのまま)、`paths[]`(変更 path 全列挙)。commit_hash 欄は source_sha と同値を書く(U4 dual-read 期間)。

### 9.1 unit 別仕様
| U | 作る file(新規) | 触ってよい既存 file | 入出力(関数/CLI 契約) | 禁止 | 二値完了(bats 名) | 停止条件 |
|---|---|---|---|---|---|---|
(全 unit 共通 AC、§12): **同一 unit を Claude 忍者 1 名と Codex 忍者 1 名の双方で実行し、両者の bats が PASS**(家老は 2 名へ同 task を配備し、報告 2 本の bats 結果を突合。片方 FAIL は unit 未完了)。
| U1 | `scripts/publisher_queue.sh`(enqueue/dequeue/peek/lease-acquire/lease-release/lease-status)、`tests/unit/test_publisher_queue.bats` | なし | `enqueue <request.yaml>`→`$STATE_DIR/publish_queue/<epoch>_<seq>_<task_id>.request` を作り stdout に path。`dequeue`→FIFO 先頭 path(空なら rc=3)。`lease-acquire <remote_url> <full_ref> <sha|pending>`→lease file(remote_url, ref=refs/heads/main 形式, candidate_sha, expiry, hmac)作成(既存有効 lease あれば rc=4)。`lease-update <sha>`(pending→確定、保持者のみ)。`lease-release`。publisher(U3)も同順序: acquire(pending)→commit-tree→update(sha)→push→release。全操作 `flock` 下 | publish(push)しない。root へ書かない。既存 script を import しない | 並行 6 request で順序=投入順(逆転 0)∧ lease 同時保持 1 ∧ TTL 120s 経過で失効 ∧ root porcelain 差分 0。bats 6 本 | STATE_DIR が root 配下を指す |
| U1b | `scripts/publish_direct_commit.sh`、`tests/unit/test_publish_direct_commit.bats` | なし(内部で `scripts/ninja_scope_commit.sh` と `scripts/publisher_queue.sh lease-*` を呼ぶだけ) | `publish_direct_commit.sh -m <msg> -- <paths>`: (1) 呼出し元 cwd が root でなければ rc=7 (2) `lease-acquire <remote_url> refs/heads/main pending`(candidate=pending で取得。rc=4 なら 30s 間隔で最大 4 回再試行、超えたら rc=4) (3) `git fetch origin` → root で `git merge --ff-only origin/main`(失敗=dirty 衝突なら rc=8、commit しない) (4) `ninja_scope_commit.sh -m <msg> -- <paths>` (5) `lease-update <新 HEAD sha>`(candidate を commit 後の SHA に確定。pending のままの push は U1c が BLOCK) (6) `git push origin main`(pre-push が `ref==refs/heads/main ∧ candidate==local_sha` を検証) (7) `lease-release`。全 rc≠0 で lease-release を必ず実行(trap) | 忍者 worktree から呼ばれたら rc=7。`git merge`(非 ff)・stash・reset を書かない | 6 並行で lease 同時保持 1 ∧ ff 失敗時 commit 0 ∧ 成功時 60s 以内 root HEAD==origin ∧ porcelain 差分 0(自分の paths 以外) ∧ rc≠0 経路で lease file 残存 0。bats 6 本 | (3) の ff 失敗の理由が dirty 以外 |
| U1c | `.githooks/pre-push` 内の関数 `prepush_lease_check`(追記)、`tests/unit/test_prepush_lease.bats` | `.githooks/pre-push`(関数 1 つ追記+呼出し 1 行。GA-PUSH1 区間は触らない=M5 で削除) | stdin の `<local_ref> <local_sha> <remote_ref> <remote_sha>` ごとに `$STATE_DIR/publish_queue/lease.<sha1(remote_url)>`(remote_url は `git config --get remote.<name>.url`)を読み、`lease.ref==remote_ref(refs/heads/main 全形)∧ lease.candidate_sha==local_sha(pending は不一致扱い)∧ expiry>now ∧ hmac 一致` でなければ `exit 1`(git 標準)。hmac 鍵は `$STATE_DIR/publish_queue/lease.key`(publisher 初期化時に生成、mode 600) | 環境変数による bypass を書かない(R7)。CLI 名で分岐しない | lease なし push 0/N ∧ lease あり(update 済) N/N ∧ pending のまま 0/N ∧ 期限切れ 0/N ∧ 別 repo の lease では 0/N ∧ Claude pane・Codex pane・素の bash の 3 経路で同結果。bats 7 本 | lease.key が無い(publisher 未初期化)=rc=1 で止めて報告 |
| U3b | `scripts/publisher_deploy_check.sh`、`tests/unit/test_publisher_deploy_check.bats` | `scripts/publisher.sh`(push 成功後に **background で起動**(`nohup … &`、published_sha ごとの lock file)し queue 処理は継続。repo が dm-signal の時のみ) | `publisher_deploy_check.sh <published_sha>`: (1) `render.yaml` の `name:`(dm-signal-backend / dm-signal-frontend)を Render API `GET /v1/services?name=` で id に解決 (2) `GET /v1/services/<id>/deploys?limit=5` で `commit.id==published_sha` の deploy を最大 15 分 poll(30s 間隔)、`status==live` で次へ、`failed|canceled|timeout` で rc=9 (3) smoke `GET https://<backend host>/healthz`=200 ∧ `GET /healthz/deep`=200(現行 backend の実在 route。`/api/public/showcase` は route 0 件のため使わない)で rc=0、他は rc=10 (4) 結果を request file に `deploy_status:`/`smoke_status:` として追記。rc≠0 なら `$STATE_DIR/publish_queue/hold` を作る(publisher は hold 存在中 kind=revert 以外を admit しない) | API key は `RENDER_API_KEY` env のみ(backend/.env を source しない、LS-A09 Guard14) | fixture(mock API)で live→rc0 ∧ failed→rc9+hold ∧ smoke 500→rc10+hold ∧ hold 中の非 revert admit 0 ∧ check 走行中も publisher の次 request が進む(C4 に影響 0)。bats 6 本 | render.yaml の name が API に 0 件 |
| U2 | `scripts/publish_artifact.sh`(capture/restore)、`tests/unit/test_publish_artifact.bats` | `scripts/gates/gate_report_format.sh`(manifest 検証 1 関数追加のみ) | `capture <task_id> <worktree> <base> <source_sha>`(呼出し元=`scripts/inbox_write.sh` の report_received 経路に 1 行、H7)→`$STATE_DIR/publish_queue/artifacts/<task_id>/{patch.diff,manifest.yaml}`(manifest: source_sha, source_tree, patch_sha, base, paths[])。`restore <task_id> <dest_tree>`→patch 適用。gate は報告の source_sha/base/paths と manifest 一致を検証 | worktree を削除しない。root へ適用しない | capture 後に worktree を rm しても restore で tree id 一致 ∧ manifest 不一致は gate FAIL。bats 5 本 | patch が空(paths 0) |
| U4 | `tests/unit/test_gate_dual_read.bats` | `scripts/cmd_complete_gate.sh`(report 読取り 1 関数: `commit_hash` 無く `published_sha`+receipt があれば受理。**autopush 4 関数 `source_only_path_snapshot_generic` / `source_only_cumulative_equivalence` / `source_only_insights_id_merge` / `source_only_lessons_id_merge` は不変更**) | 旧報告(commit_hash)と新報告(published_sha+path/blob receipt)の両 fixture で CLEAR | 上記 4 関数へ差分 0(`git diff -U0 -- scripts/cmd_complete_gate.sh` の hunk header に 4 関数名が 0 件) | 旧 fixture PASS ∧ 新 fixture PASS ∧ autopush 関数 hunk 0 ∧ `commit_hash` 読み手(`grep -rl commit_hash scripts/ .claude/hooks`、before=31 file)の分類表(判定/表示)を報告に添付し判定側全てに dual-read(H4)∧ gate が queue 内 request に対し `WAIT:publisher_pending` を返す(H8)。bats 6 本 | 差分が読取り関数外に及ぶ |
| U5 | `scripts/publisher_admit.sh`、`tests/unit/test_publisher_admit.bats` | `scripts/publisher_queue.sh`(enqueue 前に admit を呼ぶ 1 行)、`scripts/review_approval.sh`(`karo:ACCEPT` 分岐の末尾で `publisher_queue.sh enqueue <request>` を呼ぶ 1 行=ACCEPT が enqueue の唯一の caller、観点 22) | `admit <request.yaml>`→`review_approvals/reports/<key>/{gunshi,karo}.yaml` の両方存在で rc=0、不足なら rc=5+不足名。kind=doc(将軍投入)は将軍 identity+path allowlist(`docs/ context/ queue/shogun_todo_map.md`)で rc=0、allowlist 外 path 混入は rc=6。**R13**: paths に `backend/app/db/` 配下(migrations.py・models.py・init_db.py 等、create_all/run_migrations の入力)が 1 つでもあれば request に `db_migration: true` を書き、`review_approvals/reports/<key>/karo.yaml` に `migration_ack:` (値=逆 migration の path、または文字列 `irreversible_accepted`)が無ければ rc=11 | 承認 file を自分で作らない | 未承認 N 件 admitted 0 ∧ 承認 N 件 admitted N ∧ doc allowlist 外 admitted 0 ∧ db_migration=true∧migration_ack 無し admitted 0 ∧ migration_ack 有り admitted 1。bats 7 本 | 承認 file の path 規約が現物と違う |
| U3 | `scripts/publisher.sh`(daemon: loop{dequeue→lease→isolated tree@tip→C2a 検査→apply→commit→(dry-run なら log のみ/active なら push)→root ff 同期→lease-release})、`tests/unit/test_publisher.bats`、`scripts/daemon_watchdog.sh` への監視対象追加(既存の ninja_monitor 監視関数と同型の `watchdog_publisher_healthy` 1 関数) | `scripts/daemon_watchdog.sh`(1 関数追加) | `PUBLISHER_MODE=dry-run|active`(既定 dry-run)。C2a: 全 paths で `git rev-parse tip:<path>` == manifest の base blob、不一致は request を `rc/` へ移動+家老 inbox 1 通。commit は `git commit-tree`(親 1)。root 同期は `git -C root merge --ff-only origin/main`。同期前に `git -C root status --porcelain -uall` を取り、(a) tracked 差分(` M`/`M `/`MM`/`A `/`D `)が 0 ∧ (b) `git diff --name-only HEAD origin/main` の path 集合と `git status --porcelain -uall | grep '^??'` の path 集合の交差が 0 なら同期実行(交差≥1 は同期 BLOCK+家老 inbox、untracked は退避も削除もしない)。(a) が非 0 なら **同期しない**(BLOCK)で以下を順に: (1) 所有者解決: 各 dirty path を `queue/tasks/*.yaml` の `task_worktree_target_paths`/`task_worktree_source_paths`/`target_path` と突合。一致 1 名=owner、一致 0 または 2 名以上=unknown(**退避も戻しもせず BLOCK のまま家老 inbox 1 通**、C3 未達を記録) (2) owner 確定 path のみ `git diff -- <paths>` を `wip/<owner>_<ts>.unstaged.patch`、`git diff --cached -- <paths>` を `wip/<owner>_<ts>.staged.patch` に保存(2 file とも作成、空でも作る) (3) owner の worktree=`queue/tasks/<owner>.yaml` の `task_worktree_path`(無ければ `task_worktree_workdir`、両方無ければ unknown 扱いで (1) の BLOCK)で `git apply --check` を staged→unstaged の順に PASS 確認 (4) PASS したら owner worktree へ `git apply`(staged 分は `--index`)、成功を `git -C <worktree> diff --stat` で確認 (5) 確認後に root の該当 path だけ `git checkout -- <paths>`(staged 分は先に `git restore --staged -- <paths>`)で戻し、家老 inbox 1 通(owner・paths・patch path)。untracked は退避対象外(触らない)。(3)(4) が FAIL なら (5) を行わず BLOCK のまま(D8) | merge/cherry-pick/rebase を使わない。active で push する前に dry-run 24h の receipt(判定差 0)を家老が確認 | criss-cross fixture で親 1 の commit ∧ C2a 不一致で publish 0+RC ∧ dry-run で push 0 ∧ root 同期後 tracked porcelain 0 ∧ staged add(`A `)を含む WIP 退避で `restore --staged`→`checkout` 後に root から file が消えず owner worktree に staged で存在 ∧ untracked 衝突で同期 BLOCK。bats 10 本 | `git merge`/`cherry-pick` を書きたくなった |
| U6 | `scripts/ledger_writer.sh`(append)、`tests/unit/test_ledger_writer.bats` | `scripts/insight_write.sh`・`scripts/bulletin_write.sh`・`scripts/lesson_write.sh`・`scripts/karo_workaround_log.sh`(各 1 行: root file 追記→`ledger_writer append <ledger> <entry.yaml>` へ) | op=`append`/`update <id> <field>=<value> --expect <field>=<old>`/`resolve <id> --expect status=<old>`→`$STATE_DIR/ledger_inbox/<ledger>/<ts>_<seq>.yaml`(op・対象 id・expected 値・op 発行時の entry hash を含む)。**構造制約**: (a) 台帳ごとの可変 field allowlist(insights: status/resolved_reason/action_artifact/resolved_at/fix_known、lessons: status/retired_at/retire_reason、bulletin: status/actioned_by/confirmed_by、workarounds: status)以外への update は ledger_writer が rc=12 で拒否(id/ts/created_at/本文は allowlist 外=C7 を構造で担保) (b) CAS: publisher は取込み時に entry の現在値が op の expected と一致する時だけ適用、不一致は op を `rejected/` へ移し家老 inbox 1 通(古い op が新世代を上書きしない、観点 24)。append は末尾追加、`ledger: <names> <n>` commit(H3)。`insight_resolve.sh`・reflux の promotion/insight 経路・`lesson_write.sh --retire` は update/resolve op へ付替え。reflux task の写像: `deploy_task.sh` の target validation に `$STATE_DIR/ledger_inbox/<ledger>/` を allow(それ以外の STATE_DIR path は不可)、忍者の報告 `files_modified` は op file の path、`commit_contract: ledger_op`(no-code)、gate は op file 内に publisher が書き戻す `published_sha`(op を取り込んだ batch commit)を dual-read の published_sha として扱う(U4 と同じ受理経路) | 既存 entry の ts/created_at を変更しない(C7) | 各 writer で root porcelain 差分 0 ∧ 取込み後 ID 重複 0 ∧ 既存 ts/created_at/id 変更 0(allowlist 外 update は rc=12)∧ expected 不一致 op は適用 0+rejected/ に 1 ∧ 同一 id への旧 op→新 op の順で新値が残る ∧ root の queue/*.yaml を直接編集する script = 0 ∧ reflux fixture(target=ledger_inbox)が deploy validation PASS・報告 ledger_op が gate PASS。bats 12 本 | 4 writer 以外の root 書込み元が見つかった(止めて列挙報告) |
| U7 | なし | `scripts/cmd_complete_gate.sh`・`scripts/ninja_monitor.sh`(各 autopush/push_lane 入口に `[ "${PUBLISHER_SINGLE:-0}" = 1 ] && return 0` の 1 行ずつ) | flag ON で旧経路が no-op | 関数本体を消さない(削除は U8) | flag ON 24h で C1-C8 全 PASS(receipt 生貼付) | flag ON 中に merge が 1 件でも出た |
| U8 | `docs/research/single_publisher_cleanup_manifest_20260902.md`(§10 を実行結果で更新) | §10 manifest に列挙した file のみ | manifest 1 行=1 削除単位。各行の移植先 contract test が GREEN であることを削除前に確認 | manifest に無い file を触らない。1 batch 10 file 超 | bats 全 GREEN ∧ 削除 script 参照 0(rg) ∧ manifest 全行 done。1 batch ごとに報告 | 参照 0 でない file が 1 つでもある |

## §10 クリーンアップ manifest(U8 で実行。1 行=1 file または 1 関数群、忍者は判断せず上から実行。殿確認後に着手、1 batch ≤10 行)
移植先 test は U1-U6 で**新規作成する file 名**(現時点で不在。U8 着手条件=全て実在かつ GREEN。`test -e` で 0 件でも欠ければ U8 着手不可)。
| # | 対象(path / 関数) | 削除/縮退 | 不変量 | 移植先 test(U で作成) | deletion_justification |
|---|---|---|---|---|---|
| M1 | `scripts/cmd_complete_gate.sh` 関数 `source_only_path_snapshot_generic` `source_only_cumulative_equivalence` `source_only_insights_id_merge` `source_only_lessons_id_merge` `report_source_only_equivalence_state` | 削除 | 公開 tree の scope path blob==source(C2) | `tests/unit/test_publisher.bats`(U3) | publisher が唯一の公開経路(U7 で 24h no-op) |
| M2 | `scripts/ninja_monitor.sh` 関数 `check_push_lane` `push_lane_publish_one` `push_lane_integrate_remote` `push_lane_ci_unknown_fallback` `push_lane_ci_cached_fallback` `push_lane_waiting_ancestry_cmds` `push_lane_regate_waiting_cmds` ほか `push_lane_*` 全 17 | 削除 | CI RED 時の hold(R4) | `tests/unit/test_publisher.bats`(U3) | 同上 |
| M3 | `scripts/safe_shared_main_ff.sh` | 削除 | merge 後退検出→merge 0 なら対象なし(C1) | `tests/unit/test_publisher.bats` C1 case | merge が発生しない |
| M4 | `.gitattributes` の `merge=` 6 rule と `.git/config` の driver(bulletin-id / insights-id / karo-workarounds-id / ours / semantic-index-regenerate) | 削除 | 台帳 ID 重複 0・ts 不変(C7) | `tests/unit/test_ledger_writer.bats`(U6) | 台帳は直線 batch commit |
| M5 | `.githooks/pre-push` の GA-PUSH1 dirty-tree guard 区間 | 削除(lease 検査 U1c は残す) | lease なし push BLOCK(C5) | `tests/unit/test_prepush_lease.bats`(U1c) | publisher は clean isolated tree から push |
| M6 | `scripts/ninja_scope_commit.sh` option `--patch` `--base-blob` `--reflux-mode` `--reflux-evidence` `--repair-index` と single-flight / identity sidecar 区間 | 縮退 | 成果物 manifest の一致 | `tests/unit/test_publish_artifact.bats`(U2) | 忍者は自分の worktree のみ |
| M7 | `scripts/gates/gate_report_format.sh` の cross_repo_commits 自動生成・commit_contract planned path 突合・source_sha ancestry 検査・source-only receipt 検査 | 縮退(published_sha+receipt のみ) | 報告↔公開の同定 | `tests/unit/test_gate_dual_read.bats`(U4) | 多経路同定が不要 |
| M8 | `scripts/ninja_monitor.sh` 関数 `auto_commit_*`(8 関数)と postclear checkpoint、`scripts/cmd_complete_gate.sh` の insights/lessons auto-commit 呼出し | 削除 | 台帳 batch(C7) | `tests/unit/test_ledger_writer.bats`(U6) | publisher batch に統合 |
| M9 | `skills/ninja-commit/SKILL.md` | 縮退(手順 5 行) | — (手順書。契約 test なし) | なし(縮退後の手順 5 行を家老が目視) | 契約 metadata 縮退に追従。test 移植対象外 |
| M10 | `tests/unit/test_push_lane_integrate.bats` `test_push_lane_settle_age.bats` `test_safe_shared_main_ff.bats` `test_cmd_complete_gate_source_publish.bats` `test_cmd_complete_gate_convergence.bats` | 削除 | 各 file の @test を 1 本ずつ『移植済み/不要(機構削除)』に分類した表を manifest 実行結果に残す | M1-M3 の移植先 | 機構削除に伴う契約 test |
| M11 | `tests/unit/` の `test_cmd_complete_gate.bats` `test_cmd_complete_gate_auto_lesson_write.bats` `test_cmd_complete_gate_ci_readiness.bats` `test_cmd_complete_gate_ci_result_type.bats` `test_cmd_complete_gate_context_freshness_block.bats` `test_cmd_complete_gate_gunshi_verdict_precheck.bats` `test_cmd_complete_gate_small_consolidated.bats` `test_cmd_complete_gate_subsystems.bats` `test_cmd_complete_gate_task_idle.bats` `test_cmd_complete_gate_warning_levels.bats` `test_ninja_scope_commit.bats`(11 file)のうち M1/M6/M7 の関数・option を参照する @test | 部分削除 | 同上 | M1/M6/M7 の移植先 | 依存 test のみ。file は残す |
残すもの(削除禁止): `.githooks/pre-push` の lease 検査、YAML/shell/deleted-ref 品質検査(pre-commit)、CI RED census、report gate 本体、receipt 契約、D001-009 guard。

## §11 速度・件数の検証(before の入力は **snapshot 固定**: `$HOME/.local/share/multi-agent-shogun/single_publisher_before_snapshot_20260902/`(push_lane.window.log / pre_push.window.log / merges.window.txt / commits.window.txt / bats_files.txt、窓 2026-09-01T13:25〜09-02T13:25 で抽出済み)。sha256 は `docs/research/single_publisher_before_snapshot_20260902/SHA256SUMS`。生 log は後追い追記で件数が動く(家老実測 n=39→43→45)ため、計測は snapshot file に対して行う。after も同様に窓抽出→snapshot→sha256 を残す)
| 指標 | 計測コマンド(窓 S/E を環境変数で与える) | before | after 合格(二値) |
|---|---|---|---|
| merge 件数 | `wc -l < $SNAP/merges.window.txt`(抽出: `git log --merges origin/main --since="$S" --until="$E" --format='%H %P'`) | **141**(同窓 commit 644=`commits.window.txt`) | = 0 |
| push 失敗 | `grep -cE 'push_failed\|PUSH-FAIL' $SNAP/push_lane.window.log` | **100** | = 0 |
| 遠隔統合 INTEGRATE | `grep -c INTEGRATE $SNAP/push_lane.window.log` | **382** | = 0 |
| GA-PUSH1 BLOCK | `grep -rh GA-PUSH1 logs/*.log \| awk -v s="${S:0:16}" -v e="${E:0:16}" '{t=substr($0,2,16)} t>=s && t<=e' \| grep -c BLOCK` | **0**(窓内。累計 29 は窓外) | = 0(機構は M5 で削除) |
| pre-push wall ms | `grep -oE 'pre_push_wall_ms=[0-9]+' $SNAP/pre_push.window.log \| cut -d= -f2 \| sort -n \| awk '{a[NR]=$1} END{print NR, a[int(NR/2)+1], a[int(NR*0.9)]}'`(snapshot は 2 log 合算・`=na` 除外済み) | **n=45 中央値 366 / p90 1,300** | p90 ≤ 600 |
| LGTM+ACCEPT→published | publisher log の `admitted_ts`→`published_ts`(U3 で出力)p90 | 旧経路は同定不能(=AsIs の欠陥) | p90 ≤ 60s(C4) |
| root porcelain 0 到達 | 各 published_sha について 60s 間隔で `git -C root status --porcelain \| wc -l` | 旧版 4 件/日(§1.2 と同手順) | 全 published_sha で 10 分以内に 0(C3) |
| 対象 bats | `wc -l < $SNAP/bats_files.txt` / `grep -c '^@test' <§10 の 16 file>` | **270 file / 対象 16 file 598 test** | §10 で削除指定の file は rg 参照 0 ∧ 残 file の test 全 GREEN ∧ 移植先 test(§10 列)全 GREEN |
| 内容消失 | §1.2 と同手順: 窓内の各 merge について `git show <merge>:<path>` と親の blob を突合し消失 path を数える | 2 件/日 | = 0 |
最終ゴール(二値): §10 manifest 全行 done ∧ 本表 after が全行合格 ∧ C1-C8 全 PASS(両 repo)∧ bats 全 GREEN。ここまでで 1 工程。途中の CLEAR は途中成果。

## §12 multi-CLI 境界
前提(殿厳命 2026-08-01『共通化するのは成果の評価基準のみ、実行機構は CLI 固有』、殿指示 2026-09-02 13:25『どのロールがどの CLI/モデルでも必要十分に同じレベルで作業を続けられる』): 本設計の成果基準(C1-C8・§11)は CLI 共通、実行機構は下表の通り層ごとに CLI 依存の有無を固定する。
| 層 | 置き場所 | CLI 依存 | 規則 |
|---|---|---|---|
| publisher / queue / lease / artifact / ledger_writer | bash script(`scripts/`)+`$STATE_DIR` file | **無**(どの CLI の pane からも同じ CLI 契約で呼ぶ) | CLI 名・pane・tmux 変数を読まない。identity は lease file と git config user のみ |
| C5 lease なし push の BLOCK | **git の pre-push hook**(`.githooks/pre-push`) | **無**(Claude/Codex/人手/CI すべて同一経路) | Claude hook(`.claude/hooks`)や Codex hook(`.codex/hooks.json`)には置かない。CLI hook は案内(WARN)のみ |
| 忍者への案内(誤操作の早期通知) | Claude=`.claude/hooks`、Codex=`.codex/hooks.json`(BLOCK は exit 2) | **有**(CLI 固有に別実装、script も共用しない) | 共通なのは成果基準だけ: 『lease なしの commit/push 操作を pane 上で検知したら案内文を出す』。実装は Claude 用・Codex 用を各 CLI の担当が別 file で書く(殿厳命 08-01)。判定の正しさは両 CLI で同じ fixture(lease あり/なし×commit/push)を通す bats で比較する |
| §9 忍者仕様の語彙 | 設計書・task YAML | — | CLI 固有語(各 CLI の tool 名・permission mode 名・session reset コマンド名・slash command 名)を書かない。file path・シェルコマンド・bats 名のみで書く。違反は家老レビューで REJECT |
| 検証 | canary(U1-U8) | — | §9.1 の共通 AC の通り、**各 unit を Claude 忍者 1 名+Codex 忍者 1 名で実行し双方 PASS**。差が出たら差自体を §7 ピットフォールへ追記 |
既知の CLI 差(一次): Codex は hook BLOCK=exit 2(exit 1 は CLI クラッシュ)、Codex は作業中も `› Ask Codex` を常設(ready 判定は busy marker 不在まで、scripts/lib/cli_ready.sh)、Claude は Stop hook で idle flag、Codex は respawn-pane -k が唯一の確実 reset(殿裁定 05-20)。publisher 側はこれらに依存しない設計とし、依存が必要な箇所(idle 判定等)は本設計の対象外に置く。

## §13 将軍セルフレビュー(影響範囲・依存・因果を現物で確認: 事実→設計への影響→修正)
| # | 事実(一次) | 設計への影響(因果) | 修正(節) |
|---|---|---|---|
| H1(殿裁定=D13、§6 と同一) | 有効な pre-push は `.git/hooks/pre-push`(`core.hooksPath`=`.git/hooks`、`scripts/sync_git_hooks.sh` が `.githooks/` から複製)。cmd_complete_gate の autopush は **clean clone** から push し hook 0 本。DM-signal repo は `.git/hooks/pre-commit` のみで pre-push 無し。push 認証は全 pane 共通の `gh auth git-credential`(global) | **C5 を hook で守る設計は clone を作れば素通り**(今日の autopush がその実例)。hook は『無自覚の構造型』ではなく『インストールされた所だけ効く表示型』。∴ C5 の真の強制は credential にしか置けない | **D13(殿裁定)**: push 権限の分離。書込み token(fine-grained PAT、contents:write、両 repo)は publisher と直接 commit wrapper だけが `$STATE_DIR/publish_queue/push_token`(mode 600)から読み `GIT_ASKPASS`/credential helper で使う。全 pane 共通の gh credential は **read-only token** へ落とす(fetch/clone は可、push は 403)。hook(U1c)は早期通知として残す。同一 Unix user では file mode が権限分離にならない(観点 23)ため、D13 の目的は『誤 push の構造的 403』。案 A/B と副作用の全列挙は §6 D13 |
| H2 | `SHOGUN_STATE_DIR` は未設定で、inbox_watcher の解決順により `STATE_DIR=/tmp`。/tmp は 08-27 WSL 再起動で全消失した実績(worktree 全滅) | R1『停止中も request は残る』が /tmp では偽。lease.key・artifacts・ledger_inbox も再起動で消える | D2/D3/C6/C8 の `$STATE_DIR` を **`${SHOGUN_STATE_DIR:-$HOME/.local/share/multi-agent-shogun}`(実在・永続)に固定**し、/tmp 配下なら publisher 起動時 rc=2。U1 AC に『再起動相当(dir を別 path へ mv して戻す)後も request/lease/artifacts が読める』を追加 |
| H3 | `queue/insights.yaml` は 1 file 1,308 entry(resolved 1,284)で、`insight_resolve.sh`/reflux task は **既存 entry の status を in-place 更新**する。reflux は `target=queue/insights.yaml` を忍者 task の編集対象として配備し dirty-guard(fingerprint)で排他している | U6 の『writer は append-only の ledger_inbox』では resolve/reflux の**更新**を表現できない。さらに reflux 忍者 commit と publisher の台帳 batch が同一 file を触るため C2a(tip blob==base blob)が常時失敗し RC が増殖する。M1 で insights ID merge を消すと衝突の受け皿も消える | U6 を拡張: ledger_inbox の op を `append`/`update(id, fields)`/`resolve(id)` の 3 種にし、`insight_resolve.sh`・reflux の promotion/insight 経路・`lesson_write.sh --retire` を update op へ付替え(root file を直接編集する経路 0 を U6 AC)。reflux task の `target` は `queue/insights.yaml` から `$STATE_DIR/ledger_inbox/insights/` へ変え dirty-guard は不要化。恒久解(U9 候補)=1 entry 1 file 化 |
| H4 | `commit_hash` を読む script は **31 file**(`grep -rl commit_hash scripts/ .claude/hooks \| wc -l`。v2.2 の 44 は重複 dir を含めた誤計数、家老実測 36 は母集団差) | U4『読取り 1 関数』は過小。ancestry/blob 判定に使う読み手が他にもある(shogun_commit_verdict、review_bundle、gate_report_format、todo_map 等) | U4 AC に census を追加: 同コマンドの全 file を『判定に使う/表示のみ』に分類した表を報告に添付し、判定に使う全てを dual-read。分類表の file 数 = コマンド出力数で二値 |
| H5 | 両 repo とも remote 名 `origin`・branch `main`(URL は multi-agent-shogun / DM-signal) | D3 の lease key(ref)だけでは 2 repo の lease が同名衝突し、一方の publish 中に他方を誤 BLOCK/誤許可 | D3 の lease を `remote_url + ref + candidate_sha + expiry + hmac` に拡張、lease file は repo ごと(`lease.<sha1(remote_url)>`)。U1 AC に 2 repo 同時 lease で干渉 0 を追加 |
| H6 | 殿裁定 08-30 19:29『CI green を待つのは諸悪の根源』。現行 gate の ci_readiness は記録のみ(非ブロック)へ改修済み | D7/R4『RED 中は hold し ci_fix のみ admit』は **CI 待ちの再導入**で裁定に反する。RED の間 5 忍者分の publish が queue に滞留する(08-30 19:00-19:29 と同構造) | D7/R4 を『RED は記録のみ。publish は止めない。ci_fix request は FIFO を追い越して先頭へ(優先度 1 段)』に変更。hold は R11(dm-signal deploy 失敗/smoke 落ち)と R13(migration 未 ack)だけ |
| H7 | worktree の消失経路は archive 後の cleanup(`archive_completed.sh cleanup_task_worktree_marker`)と、STAGE1 誤終端 respawn(T152 実例: report completed 直後に respawn で成果消失) | U2『LGTM 時に artifacts へ複製』は LGTM より前(report 直後)に respawn が来ると間に合わない | U2 の capture を **report_received 時点**(`inbox_write.sh` の report_received 経路、または `gate_report_format` PASS 直後)へ前倒し。AC『report 直後に worktree を rm しても restore で tree id 一致』 |
| H8 | 報告 gate(`cmd_complete_gate`)は report の commit の origin/main 祖先化を要求(check_report_commit_main_ancestry、Gate 10.1c)。publisher 化後、祖先化は publisher が push して初めて成立 | gate CLEAR が publisher の遅延に直列依存する新しい WAIT が生まれる(publisher 停止=全 cmd CLEAR 停止)。R1 の検知(最古 request age>300s)で見えるが gate 側に『publisher 待ち』の状態名が無いと『GATE が壊れた』と誤診される | U4 に WAIT 種別 `WAIT:publisher_pending(request=<path>)` を追加し、gate は request が queue に存在すれば BLOCK ではなく WAIT を返す。startup gate の便回転チェックに publisher queue 長を表示 |

## §5 レビュー履歴
- v1.0 → 家老 REJECT(blt_20260902_023241、方向 APPROVE・修正 5): ①inventory の残すもの明示 ②C2a/C3 porcelain 0/C5 lease BLOCK ③順序 U1→U2→U4→U5→U3→U6→U7→U8 ④成果物 3 つ組と旧 field 写像 ⑤C6/C7。→ v1.1 に全反映。
- v1.1 → 家老 REJECT(blt_20260902_023509、前回 5/5 反映確認・新規 6): ①台帳 writer は root 外 queue に統一 ②fingerprint と patch_sha は別物で両方保持、cross_repo は組で保持 ③U1 AC=max holders 1/overlap 0/FIFO 逆転 0、lease=ref+SHA+expiry ④U5 AC=未承認 N→admitted 0、承認 N→N ⑤U3 AC に C2a fixture+dry-run 母数 N/mismatch 0 ⑥canary C1-C7、U8 削除 manifest+殿確認+1 batch ≤10、原則番号修正。→ v1.2 に全反映。
- v1.2 → 家老 **APPROVE**(blt_20260902_024632、6/6 反映を現物差分で確認)。
- v1.3(殿指示 03:36 で R/D/P/A 4 節追加)→ 家老 覚醒 REJECT(blt_20260902_034259、新規 8): R2×C2a 矛盾/R7 bypass 廃止/R8・D8 dirty 退避+forward restore/R10 forward restore/D2 STATE_DIR・D5 allowlist/A1×A3 統合/A8 言い換え禁止→構造 field/A9 rollback_plan field+P4 原因訂正。→ v1.4 に全反映。
- v1.4 → 家老 REJECT(blt_20260902_034658、前回 8/8 反映確認・新規 4): ①publisher 状態 path を STATE_DIR へ統一(C8 追加) ②unexpected dirty=他者 WIP は publish へ投入せず所有者の未 commit WIP として再適用 ③ledger_inbox の絶対境界明記 ④履歴の時系列整列。→ v1.5 に全反映。
- v1.5 → 家老 REJECT(blt_20260902_034931、前回 4/4 反映確認・新規 2): ①canary/U7 を C1-C8 へ ②WIP 復元先を所有者専用の非 root worktree に限定(復旧完了の二値化)。→ v1.6 に全反映。
- v1.6 → 家老 REJECT(blt_20260902_041733、新規 2): ①U7 AC を C1-C8 全 PASS(実測 receipt)へ ②履歴の時系列再整列。→ v1.7 に全反映。
- v1.7 → 家老 **APPROVE**(blt_20260902_041853、計 7 往復)。→ 殿裁定 3 点(13:07-13:20)を v1.8 に反映(§0.1)。
- v1.9 → 家老 **REJECT**(blt_20260902_133722、観点 9-15 全 7 点: 直接 commit/C5 unit 不在・DB 非接触は偽(init_db→run_migrations)・撤回残存 8 行・path 不在 3・manifest が機能群で移植先 0/4・§11 窓非固定・両 CLI AC 0+guard script 共用)。→ v2.0 で全反映(U1b/U1c/U3b 追加、R13、§10 path 単位 11 行、§11 固定窓、共通 AC)。
- v2.0 → 家老 **REJECT**(blt_20260902_134504、観点 16-18: 残存 3 行・§11 placeholder・§9 に U1b/U1c/U3b 行 0・M11 未列挙・R13 の path 不在(実体 migrations.py、models.py も create_all で DB 接触)・U3 退避が staged/untracked を扱わず owner 解決規則なし)。→ v2.1 で全反映。
- v2.1 → 殿指示 13:48『家老を超える深さでセルフレビュー』→ §13 H1-H8(将軍、現物確認)→ v2.2。H1 は D13 として殿裁定へ。
- v2.1 → 家老 **REJECT**(blt_20260902_135206、観点 19-21: §11 生 log で n 不一致=再現不能・untracked 5,981 で C3 到達不能+staged 境界 fixture 無し・lease の ref/SHA が commit 前後で必ず不一致・smoke 経路 0 件・15 分 poll が publisher を塞ぐ)。→ v2.3(snapshot 固定、C3 tracked 限定+untracked 衝突 BLOCK、lease pending→update、smoke /healthz+/healthz/deep、deploy check を background)。
- v2.3 → 家老 判定(blt_20260902_140011、観点 19/20/21/25 PASS、22/23/24 REJECT: C5/C6 正本が旧記述、H4 計数、ACCEPT→enqueue caller 未指定、push_token は同一 uid で分離にならず gist 系 API への副作用未列挙、update op に allowlist/CAS 無し・reflux 写像未定義)。→ v2.4。
- v1.8(13:25 家老レビュー依頼 msg_132320)→ 殿指示 13:23『実装は忍者。性能の劣る LLM が混乱・誤解しない設計書。クリーンアップと速度検証まで最終ゴール』→ v1.9 で §9-§11 追加(v1.8 レビューは v1.9 に差替え)。

## §5.1 レビュー依頼(家老、v2.4)
観点(v2.4): (26) 観点 22-24 の反映(C5/C6 正本、H4=31 のコマンド一致、U5 の ACCEPT caller、D13 の目的再定義と案 A/B・副作用列挙、U6 の allowlist/CAS と reflux 写像)が現物と矛盾しないか (27) D13 案 A で『既定 read-only』にした時に壊れる git 書込み経路の全列挙(rg `git push` 呼出し元 §1.1 の 11 script)が U7 の flag 停止対象と一致するか
観点(v2.3): (25) v2.1 REJECT 3 点の反映(snapshot の SHA256SUMS と値の再現、C3 の untracked 限定と衝突 BLOCK、lease pending→update→push の順序が U1b/U1c/U3 で一致、smoke route の実在、deploy check の非同期化で C4 不変)
観点(v2.2): (22) §13 H1-H8 の事実が現物と一致するか(hook path・clean clone・credential・STATE_DIR・insights 1 file・commit_hash 44 file・lease 同名・08-30 裁定・worktree 消失経路・gate 祖先化)、および各修正が他節(C5/D2/D3/D7/R4/U2/U4/U6/U1c)へ矛盾なく反映されているか (23) H1 D13(credential 分離)の副作用(殿の手動 push・CI・gist・fetch)の列挙漏れ (24) H3 の update op が C7(ts 不変)と両立するか、reflux の dirty-guard 廃止で失うものが無いか
観点(v2.1): (19) v2.0 REJECT 3 点の反映を現物で確認(残存 rg 0、§11 コマンドを copy&paste 実行で n=39/366/1300 再現、§9 に U1b/U1c/U3b の 6 欄、M11 11 file 列挙、R13 が backend/app/db/ 配下全体) (20) U3 の owner 解決(task_worktree_target_paths/source_paths/target_path 突合、0 or 2+ =BLOCK)と staged/unstaged 2 patch+untracked 不触の手順で C3 が到達可能か、到達不能の場合の BLOCK 状態が二値で残るか (21) U1c の hmac 鍵配置と U3b の Render API 契約(name→id、deploys の commit.id)が現行 API と一致するか
観点(v2.0): (16) v1.9 REJECT 7 点の反映を現物差分で確認(撤回残存 rg 0、path `test -e` 全 OK、§11 コマンドを窓固定で再実行して値一致、§10 各行の対象 path/関数名が現物に実在) (17) R13(migration)の admit 条件が二値で、dm-signal の init_db→run_migrations 経路を正しく前提にしているか (18) U1b wrapper と D8 同期が『忍者作業中の root path を壊さない』か(WIP 退避手順 (1)-(5) の停止点)
観点(v1.9 新規): (12) §9 の unit 仕様は忍者が推測なしに着手・完了・停止できるか(触る file/作る file/入出力/禁止/二値/停止条件の 6 欄に空・曖昧語が無いか、家老が task YAML へそのまま写せるか) (13) §10 manifest の移植先 test が各行に実在し、残すもの(C5 lease/品質検査/CI census/report gate/receipt/D001-009)が manifest に混入していないか (14) §11 の before 値と計測コマンドが再現可能か、after 目標が二値か (15) §12 multi-CLI 境界: C5 が git pre-push(CLI 非依存)に置かれているか、§9 に CLI 固有語が 0 か、両 CLI 忍者での PASS が各 unit の AC に入っているか
観点(v1.8 新規): (9) D10 lease 付き直接 commit(将軍・家老)が C1/C3/C5 と矛盾しないか、R12 の同期 script は D8 と同一実装で足りるか (10) D9 両 repo 同時 canary で R11(Render deploy/smoke hold)の検知が二値か、dm-signal 側に publisher 非接触でない経路(migration/recalc)が混入しないか (11) §0.1 裁定記録が事実→制約→判断→効果で欠落なく、v1.7 案の撤回が本文全体で整合しているか(残存する『廃止』『U5 後』表現 0)
(以下 v1.7 観点、参考)
観点: (5) §4 R1-R10 の検知・復旧が二値か (6) §6 D1-D12 のうち将軍が決めてよい範囲を越えていないか(殿裁定は D9/D10 のみ) (7) §7 P1-P10 に本日事象の漏れ (8) §8 A1-A10 が deploy_task/karo-direct の現行 gate と矛盾しないか。
観点: (1)§1.3 不要化 inventory の過不足(削ってはいけないものが混ざっていないか、殿 07-21『削るな速くしろ』との整合) (2)§2.3/2.4 の契約が二値か (3)§3 の順序・AC・canary 範囲 (4)壊れる契約の列挙漏れ(blt_021944 の 13 項目と突合)。
