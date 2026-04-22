# GP-219 効果分析: 教訓注入 archive→active 優先変更

## 問題
deploy_task.sh L1961がlessons_archive.yamlを優先 → archive-only教訓がフィルタ通過 → NOT_USEFUL量産

## 修正
lessons.yaml(active)優先に変更。archive-onlyの教訓は注入されなくなる。

## 定量効果(lesson_impact.tsv 2026-04-22以降)

| 指標 | before(GP-218のみ) | after(GP-219予測) |
|------|---------------------|-------------------|
| USEFUL | 21 | 21 |
| NOT_USEFUL(total) | 63 | 23(active-only) |
| NOT_USEFUL(archive-only) | 40 | 0(排除) |
| useful率 | 25.0% | 47.7% |

## NOT_USEFUL内訳
- 33種類のうち22種(67%)がarchive-only教訓
- 件数: 63件中40件(63%)がarchive-only
- Top3: L481(9件,archive-only), L097(5件,archive-only), L015(4件,auto-ops)

## 因果鎖
Vercel archive優先の誤適用(コメントに"archive has full data"と記載) → lessons_archive.yamlからも注入 → retired/deprecatedフラグなしのarchive-only教訓が通過 → GP-218のtarget_filesフィルタでも排除不能(target_files未設定教訓) → NOT_USEFUL量産 → useful率低下

## commit
a214faa1 — D0直接実装, S0 PASS, bats 15/15 PASS
