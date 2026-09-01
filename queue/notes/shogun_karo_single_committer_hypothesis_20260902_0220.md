# 将軍→家老 協議依頼(2026-09-02 02:20) — 殿仮説『忍者はコミットしない。コミットは家老/将軍のみ』の検証

task_id=commander_directive subject_task_id=consult_single_committer_20260902 parent_cmd=cmd_4442

[MEM: memory_db knowledge:0e462891 tsumari 結論 ⑧(契約変更の census 漏れ) / S-05(push lane 統合失敗 3 波)]
殿発言 02:16: 「問題の真因はバラバラにコミットが行われるからではないか。忍者はコミットしない。コミットは家老もしくは将軍が行えばほとんどのトラブルが起きる可能性が低くなるのではないか。この仮説を検証して家老と協議してくれ」

## 1. 一次計測(origin/main、2026-09-01 02:00〜09-02 02:16 の 24h)
`git log --since="2026-09-01 02:00" --format='%h|%P|%s' origin/main` → **469 commit / merge 93(20%)**
| 生成者 | 件数 | 備考 |
|---|---|---|
| insights auto-commit(reflux dirty-guard) | 79 | daemon |
| 忍者 task commit(cmd_*_normal/full/exact) | 76 | **16%** |
| push_lane integrate(root 統合 merge) | 48 | daemon |
| 将軍 todo map / context / instructions / docs | 70 | 将軍 |
| autopush: source-only(忍者 worktree→origin 直接公開) | 37 | daemon |
| postclear checkpoint / ledger auto-commit / batch auto-commit | 53 | daemon |
| ancestry integrate + reflux ancestry merge | 8+ | daemon(criss-cross の発生源) |
push lane log 累計: `push_failed` **59**、`auto_merge=failed|INTEGRATE-MERGE-FAIL` **95**。
本日の実害: 内容消失 2 回(20594ec4e / 16d831ed9)、root worktree 旧版 4 回、GA-PUSH1 BLOCK 3 回、CI RED 7 回(うち census 漏れ 5)。

## 2. 検証結果
- 「忍者が commit する」こと自体は全 commit の 16% で、消失 2 件・旧版 4 件・統合失敗 95 件の**直接の発生源は daemon lane(autopush 37+ancestry 8+root 統合 48+auto-commit 98)**である。
- ただし殿仮説の本質=**『main への独立した公開者(publisher)が複数いる』こと**と読むと**正しい**。忍者 worktree ごとの autopush と reflux ancestry merge が main の系譜を分岐させ(criss-cross、merge-base 複数)、root 統合が git 意味論上「正当に」内容を落とす(16d831ed9 は `git merge-tree` の純 3-way でも消える=guard では防げず、系譜を一本化しないと再発)。
- 反証点: 公開者を 1 系統(家老 lane 直列+将軍 doc lane)にすれば merge 93→ほぼ 0、criss-cross 0、stale worktree(root ref だけ進む現象)0、GA-PUSH1(自分の未 commit と他者 commit の重複)0 になる。防げないもの=契約変更の census 漏れ(CI RED)、報告書式 FAIL。
- 現行の複雑化(U5/U6/U8/U9/ancestry guard/insights-id driver/GA-PUSH1/postclear checkpoint)は**すべて多重公開者の副作用への対症**=殿の言う『サンクコストで過剰に複雑化』の典型。一本化すれば大半が不要になる(削るのではなく不要になる)。

## 3. 将軍案(協議のたたき台)
- **忍者: commit も worktree 公開もしない。** 成果=worktree 内の diff(`git diff` patch)+報告 YAML。報告に `patch_path`(または worktree の `git write-tree` id)と対象 path を記録。
- **家老: 唯一の code publisher。** LGTM/ACCEPT 後に `karo_apply_commit.sh <task>`(patch を root に apply→scope 限定 commit→push)を直列実行。1 task=1 commit=1 push。CI RED は push 直後に判明し直前 commit へ紐付く。
- **将軍: doc/map/context のみ**(現状どおり、家老 lane と path が重ならない)。
- daemon lane(autopush/ancestry/postclear/auto-commit/insights auto-commit)は**停止**。台帳(insights/bulletin/workarounds/lessons)は家老 commit に同梱(台帳 merge driver 不要)。
- 忍者 worktree は「patch を作る作業場」に格下げ: base=最新 origin/main を deploy 時に固定、apply 時に conflict なら家老が忍者へ rebase 差し戻し(明示・可視)。

## 4. 家老への問い(1 通で返答せよ)
1. 上記 §2 の計測・因果に反証はあるか(特に『忍者 commit 16%』と『daemon lane が発生源』)。
2. §3 で壊れる既存契約を列挙せよ(commit_hash 報告契約、gate の ancestry/receipt 検査、reflux、ci_fix の source_commit、ninja_scope_commit 系の bats)。移行 unit の分解案(順序・件数)。
3. 速度: 家老直列 publish の 1 task あたり所要(見積)と、6 忍者並走時の待ち行列。許容か。
4. 代替案があれば(例: 忍者 commit は許すが公開者は家老のみ=autopush 停止だけで足りるか)。その場合 criss-cross は消えるか。
