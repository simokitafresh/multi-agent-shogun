# 軍師セッションRCA 2026-07-18

## セッション概要
- 期間: 08:05-15:22 (7h17m)
- レビュー件数: 76件(review_log記録、archive移動分除く)
- 実作業: 168分(41%) / idle待機: 241分(59%)
- レビュー速度: 2.2分/件(実作業時間ベース)

## インフラバグ発見4件
| ID | 現象 | 影響 | 根因 | 対処 |
|----|------|------|------|------|
| BUG-G1 | 重複レビュー依頼10件+ | CTX+10-20分 | inbox_write二重送信 | 家老報告済み |
| BUG-G2 | reflux L901無限ループ6回 | 30分浪費+RC3件 | selector未push反映 | LG057候補 |
| BUG-G3 | precheck FP高頻度15件 | 7.5分 | LG044 task_type未考慮 | FP改善候補 |
| BUG-G4 | approval不可karo_direct3件 | 迂回送信 | review_approval検索先 | 家老報告済み |

## 主要レビュー実績
- 偵察: 影丸Track A(56/56遷移3穴), 飛猿Track B(5/5×7/7×5/5 3件)
- hotfix: 才蔵prompt replay(163/163), 影丸shared index(52/52), 疾風preflight(14/14→14/14)
- CI fix: 小太郎report identity(12/12), 飛猿clear_reopen(70/70), 才蔵deploy ac_handling(151/151)
- LGTM撤回: 半蔵cross-pane(FN=1 Codex identity空)→影丸RC2で根治(36/36+E2E)
- MECE設計書: C6穴(monitor loop)+目標値根拠不在2件を指摘
- C1集中: 疾風commit p50=9.974→1.940s(80.6%削減)達成

## 最大損失
idle待機241分(59%) = 忍者作業速度が軍師スループットを支配

origin: [[軍師セッションRCA_20260718]] -> [[idle待機59%]] -> [[lesson_candidate_3件]]
