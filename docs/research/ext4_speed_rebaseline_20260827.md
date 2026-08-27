# ext4 移設後の速度再基準(2026-08-27 22:40)

meta: cmd=cmd_karo_hotfix_t87_ext4_speed_rebaseline_20260827(T87) / 計測=半蔵 / doc lane=将軍(22:59) / raw=`logs/ext4_speed_rebaseline_hanzo_20260827.raw.log`, tests=`logs/ext4_speed_rebaseline_hanzo_20260827.tests.log` / before 正本=`docs/research/9p_root_fix_runbook_20260827.md` §1, `scripts/cdp/cmd_4401_publish_timing.md`

## §1 結論

9p(drvfs `/mnt/c`)が本日までの git/flock/stat 律速の支配要因であり、cmd_4408 の ext4(`/home`)移設で解消した。同一手順・同一計装(cmd_4401 phase 計装+ninja_scope_commit phase 計装、対象 script の tree hash 不変)で各 3 回計測。

| 指標 | 9p before | ext4 after(3回) | 平均 | 削減 |
|---|---|---|---|---|
| publish_total | 3770ms | 236/221/224 | 227ms | −94% |
| ninja_scope_commit git_commit | 9487ms | 175/176/167 | 173ms | −98% |
| ninja_scope_commit scope_sync | 5846ms | 93/64/61 | 73ms | −99% |
| git status | 60-120s | 90/86/76 | 84ms | −99.9% |
| git push(実 push・no-op、origin/main==HEAD) | timeout 3回 | 1178/1030/1189 | 1132ms | timeout 0 |
| git push --dry-run(補助) | — | 15/12/15 | 14ms | — |
| deploy_task 配備 wall(将軍観測 22:26) | 199-397s | 23855/21697 | 22.8s | −89% |

全 12 主測定 rc=0、欠測 0。contract test: cmd_publish 4/4 SKIP0、ninja_scope 79/79 SKIP0。

## §2 残る律速(ext4 上・上位 3 件)

1. 実 push 1132ms — ネットワーク+GitHub 往復。pre-push hook は別計測(defense_overhead.jsonl pre_push_total)。
2. publish 外側差分 約 604ms — cmd_publish の phase 計装外(起動・hook・preflight)。次弾は外側の計装追加で名指し。
3. scope git_commit 173ms — 9p 由来の read_tree/index 同期(T60 の 1081ms)は消えた。残りは git 本体。

判断: 旧 T60(git_commit/scope_sync の本質短縮)は前提消失で終了。次弾は (2) の外側計装のみ。T12(publish 13 分の分解)も同様に前提消失。

## §3 因果

`[[9p_git_flock_RPC待ち]] -> [[殿裁定_ext4移設やれ_20260827_1422]] -> [[cmd_4408_ext4_migration]] -> [[ext4_speed_rebaseline_20260827]]`

殿下問 13:50「D-state 9 プロセス=9p 上の git/flock 負荷をどう解決するか」→ 移設(14:22『やれ』)→ cutover 22:00 → 本再基準。9p 基準値は歴史値として runbook に残し、以後の before は本表を用いる。
