# origin/main 単一 publisher 化 — AsIs / ToBe / 5W1H 設計書 v1.0

- 作成: 2026-09-02 02:30 将軍(殿指示 02:16『忍者はコミットしない。コミットは家老/将軍のみ』→02:18『コミットのやり方・スキル・構造の検証』→02:24『AsIs/ToBe 5W1H 設計書。不要になる複雑さを先に検証』)
- 協議: 家老回答 blt_20260902_021944(single publisher + local commit artifact)。協議記録=`queue/notes/shogun_karo_single_committer_hypothesis_20260902_0220.md` §1-6
- 因果: `[[殿仮説_単一committer_20260902]] -> [[多重publisher_criss-cross]] -> [[single_publisher_local_commit_artifact]]`
- 一次データ取得日時: 2026-09-02 02:16-02:28(origin/main 24h log、push lane log、scripts 行数/関数数)

## §0 結論(1 行)
origin/main へ書く主体を**家老の publisher 1 本(直列 queue)**に限定し、忍者は worktree 内 local commit(成果物)まで、将軍の doc も同 queue を通す。これで merge 93/日→0、criss-cross 0、内容消失 0、root worktree 旧版 0 となり、多重 publisher の副作用に対して積まれた **約 4,900 行・bats 221 本・merge driver 5 本・pre-push guard** が不要になる。

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
※ 削除は U8(canary 後)でのみ行う。殿裁定 07-21『削るな、速くしろ』との整合: ここで削るのは「速くするために足した機構」ではなく「多重 publisher の副作用を抑えるための機構」であり、根(多重 publisher)を無くすことで**存在理由が消える**もの。存在理由が残る機構(CI RED census、report gate、receipt 契約)は触らない。

## §2 ToBe
### 2.1 原則
1. origin/main へ commit を到達させる主体は **publisher 1 プロセス**(家老 lane、直列 lock+FIFO queue)のみ。将軍・家老の doc/hotfix も同 queue。
2. 忍者は自分の worktree で **local commit(immutable 成果物)** まで。origin DAG に忍者の ancestry は入らない。
3. publisher は source commit を merge/cherry-pick せず、`base..source` の **scope 限定内容(path/blob)を最新 remote tip へ適用し新しい直線 commit** を作る(家老案)。conflict=忍者へ rebase 差し戻し(可視)。
4. 台帳(insights/bulletin/workarounds/lessons/semantic-map)は publisher 内の **独立 batch commit**(code commit と混ぜない、因果時刻を保つ)。
5. 1 task = 1 published commit = 1 push。CI は published_sha に紐付く。

### 2.2 フロー
```
忍者 worktree: 作業 → ninja_scope_commit(最小形) → local commit S → 報告 YAML(source_sha=S, base=B, paths)
                                                     ↓ LGTM(軍師)+ACCEPT(家老)
publisher(家老 lane, 直列):  fetch tip T → isolated tree@T → apply diff(B..S | paths) → commit P → push → 報告に published_sha=P
台帳 writer: 書込みは従来どおり file へ → publisher が N 分毎/ task 完了毎に batch commit "ledger: …" → push
将軍 doc: root で編集 → `publish_request docs` → 同 queue → publisher が commit+push
```

### 2.3 5W1H
| | AsIs | ToBe |
|---|---|---|
| **Who** | 公開者 11 script・実質 5 主体(忍者 autopush/gate/monitor/将軍/家老) | publisher 1(家老 lane)。忍者=local commit、将軍=publish_request |
| **What** | merge 93/日、統合失敗 95、消失 2、旧版 4、GA-PUSH1 3 | 直線履歴(merge 0)、消失 0、旧版 0、GA-PUSH1 0 |
| **When** | 各 lane が非同期に push(CI 待ち・age 600s・ADMIT) | LGTM+ACCEPT 直後に queue 投入、直列で ≈18s/task(p90 40s)、6 同着でも最後尾 ≈108s |
| **Where** | root 共有 worktree+clean clone+isolated worktree+6 忍者 worktree の 9 箇所から origin へ | publisher の isolated tree 1 箇所のみが origin へ。root は publisher の後追い checkout(worktree 同期を publisher が行う) |
| **Why** | 忍者成果の即時公開と CI 相関を各 lane で独立に担保しようとした結果、公開者が増殖 | 公開者を 1 本にすれば merge 意味論の問題(criss-cross/3-way 後退)が構造的に消える |
| **How** | autopush 4 経路+push_lane+ancestry merge+merge driver 5+GA-PUSH1+safe_ff | `publisher.sh`(lock+queue+apply+commit+push+root sync)1 本と最小 `ninja_scope_commit` |

### 2.4 契約(二値)
- C1: origin/main の新規 commit の親数は常に 1(`git log --merges origin/main --since=<canary 開始>` = 0)。
- C2: 公開された commit の tree は、対応する忍者 source commit の scope path について blob 一致(path/blob receipt)。
- C3: 公開後 10 分以内に root worktree の HEAD == origin/main かつ `git status --short | grep -c '^M '` = 0。
- C4: 1 task の LGTM+ACCEPT → published_sha 記録までの p90 ≤ 60s。
- C5: 公開者 script は 1 本(`grep -lE 'git (-C [^ ]+ )?push' scripts/*.sh` = publisher のみ)。

## §3 移行(家老案 8 unit、順序固定・各 unit 二値 AC・canary=infra hotfix lane)
| U | 内容 | AC(二値) | 不要化される複雑さ |
|---|---|---|---|
| U1 | publisher 単一 lock+FIFO queue(`scripts/publisher.sh`、`queue/publish/` に request、flock) | 並行 request 6 件で published 順序=投入順 ∧ 同時 push 0 | — |
| U2 | 忍者 local commit→patch/tree manifest(報告に source_sha/base/paths) | 報告 gate が manifest を検証 PASS | ninja_scope_commit option ≥ 20 |
| U3 | remote tip へ scope 限定適用→published_sha 生成(merge/cherry-pick 不使用) | criss-cross fixture で published tree の regression 0 | safe_ff/ancestry guard |
| U4 | gate を source_sha→published_sha+path/blob receipt へ更新 | 旧 ancestry 検査 0 参照 | source-only receipt・ancestry 検査 |
| U5 | LGTM+ACCEPT 後のみ publish(それ以前は queue 投入不可) | 未承認 request の publish 0 | — |
| U6 | reflux/台帳 writer を同 queue の batch へ | 台帳 commit が code commit と分離 ∧ merge driver 未使用 | .gitattributes 6 rule・driver 5・insights auto-commit |
| U7 | autopush 4 経路/ancestry/push_lane/postclear auto-commit を flag 停止(`PUBLISHER_SINGLE=1`) | 停止後 24h で origin merge 0 ∧ push_failed 0 | push_lane 596 行・autopush 1,182 行(停止) |
| U8 | canary 7 日後に旧 gate/tests/hook を削除 | bats 全 GREEN ∧ 削除 script 参照 0(rg) | 上記の物理削除・GA-PUSH1・SKILL 縮退 |
canary 判定: U7 後 24h で C1-C5 全 PASS → dm-signal PJ へ拡大。

## §4 リスク・未決
- publisher が単一障害点: daemon_watchdog で監視、queue はファイルなので publisher 停止中も request は残る(復帰後に順次)。
- 忍者 worktree の base が古いまま長時間作業→apply conflict 増: deploy 時に base=最新 tip 固定+conflict は差し戻し(明示)。
- 将軍の直接 commit 廃止(殿裁定事項): 将軍は `publish_request` を出す。map/artifact の即時性は request→publish ≈18s で影響なし。
- CI RED は publisher が push 直後に判定し、RED なら次 request を hold(ci_fix のみ通す)= 現行『CI RED 中の他作業』裁定を維持。

## §5 レビュー依頼(家老)
観点: (1)§1.3 不要化 inventory の過不足(削ってはいけないものが混ざっていないか、殿 07-21『削るな速くしろ』との整合) (2)§2.3/2.4 の契約が二値か (3)§3 の順序・AC・canary 範囲 (4)壊れる契約の列挙漏れ(blt_021944 の 13 項目と突合)。
