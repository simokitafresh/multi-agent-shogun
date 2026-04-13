# 教訓効果率分析 2026-04-13

> 軍師idle自走サイクル。lesson_impact.tsv 2004件分析。

## §1 全体サマリ

| 指標 | 値 |
|------|-----|
| Total entries | 2004 |
| Injected useful率 | 258/342 = **75%** |
| Feedback USEFUL率 | 81/427 = **19%** |
| Withheld CLEAR/BLOCK | 488/461 (CLEAR優勢) |

## §2 低効果教訓Top5

| ID | NOT_USEFUL | USEFUL | useful率 | 根因 | 推奨 |
|----|-----------|--------|---------|------|------|
| L063 | 29 | 0 | 0% | universalタグ→全cmd注入。特定Pythonパターン限定 | タグ→python |
| L074 | 28 | 1 | 3% | universalタグ→全cmd注入。特定bashパターン限定 | タグ→bash |
| L608-613 | 12-13各 | 0 | 0% | cmd_1855バッチ登録。進行中月パリティ→GP-184で構造対処 | GP-184実装待ち |
| L094 | 10 | 0 | 0% | shutsujin_departure解決済み | retire |

## §3 高効果教訓

注入>=3回 & useful率>50%: L191/L493/L491/L097/L263/L205/L283/L572等(全100%)。
教訓注入→参照パイプラインは健全(75%)。

## §4 因果分析

feedback NOT_USEFUL 81%の根因:
1. universalタグの教訓が全cmdに注入→該当しないcmdでNOT_USEFUL蓄積
2. 解決済み教訓が未retireで注入継続
3. バッチ登録教訓(L608-613)がcmd設計問題→注入タイミングが遅い(GP-184が正解)

## §5 推奨アクション

1. L063/L074: タグをuniversal→python/bashに変更(家老:lesson_write.sh)
2. L094: retire(家老:lesson_write.sh --retire L094)
3. L608-613: GP-184実装で根本対処。教訓は参考情報として維持
