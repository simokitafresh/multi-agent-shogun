# 将軍→家老 hotfix 下知(2026-09-02 01:42) — origin/main 20594ec4e(ancestry 統合 merge)が公開済み commit の内容を落とした

task_id=commander_directive subject_task_id=cmd_karo_hotfix_ancestry_merge_content_loss_20260902 parent_cmd=cmd_karo_hotfix_u9_ours_merge_guard_20260902

[MEM: memory_db knowledge:0e462891 tsumari ⑧ / S-05 残(ours 相当 merge 0334a9c71)]

## 一次証跡(01:38-01:42 実測)
- 01:25 push lane が root を `750b8453d`(integrate origin c7710efaf)へ進め、将軍 commit 02c45f090(roadmap v1.3+map 01:17)/2ebb8c274(map 01:22)/0016fb9ab(infrastructure.md U9)を含む履歴が公開(ADMIT 01:14 以降)。
- 01:35 origin/main に `7691d6a2b`(autopush: source-only insights ID merge)→`20594ec4e`(integrate cmd_reflux_insight_202609020124_kotaro ancestry、parents=7691d6a2b + 77c80312b)。
- `git diff --stat <merge-base(fd1f562b3,20594ec4e)> 20594ec4e -- <3 doc file>` → roadmap 7 行/map 4 行が**削除方向**に変化(range 内に 3 file を触る非 merge commit は 0)=merge 20594ec4e の tree が公開済み内容を持たない ours 相当 merge。
- 01:38 root の push_lane 自動統合 `3c6bbe356`(fd1f562b3 × 20594ec4e)は無競合で origin 側の削除を採用 → HEAD から infrastructure.md U3/U9 節(grep 3→0)、roadmap cmd_4444(1→0)、map 01:22 追補(1→0)が消失。
- 将軍が worktree 現物(正しい版)から `03f154709` で復元(grep 3/1/1)。origin へは push lane が運ぶ。
- U9(593cfb27a)の『既公開 merge は BLOCK 除外』は本件のような**公開後に発覚する ours 相当 merge**を通す。公開前(autopush/ancestry 統合の生成時)に止める必要がある。

## 是正(1 unit・忍者 1 名・karo-direct、影丸 T224 の後でも可だが優先度は同等)
- AC1: reflux/autopush lane の『integrate … ancestry』merge 生成時に、両親いずれかに対して**内容が後退する file**(merge tree が parent A の変更を parent B 側で無かったことにする=ours 相当)を検出したら push せず `ANCESTRY-MERGE-REGRESSION paths=` を log し lane を停止する(safe_shared_main_ff.sh の ours-equivalent 判定を共通 lib 化して再利用。新規実装は禁止)。
- AC2: 本件 fixture(公開済み 3 commit を含む base に対し古い tree の worktree から ancestry merge を作る)で BLOCK 1、正常 fixture で rc=0、bats ≥2(test_necessity 付き)。
- AC3: 20594ec4e の生成経路(小太郎 reflux lane が古い worktree base から merge を組んだ理由)を task に 1 行で記録し、同経路の他 lane(hayate/hanzo reflux)を census して件数を報告 YAML に生貼付。
