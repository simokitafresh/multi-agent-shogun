# Gate FAIL率推移+FAIL理由分布 (2026-04-30)

軍師idle自走 — gate_fire_log.yaml定量分析

## FAIL率推移

| 期間 | FAIL | 全件 | 率 |
|------|------|------|-----|
| 全体 | 742 | 4277 | 17.3% |
| 直近100件 | 11 | 100 | 11.0% |

**35%改善**。gate蓄積+FIXヒント追加(S137)+消火撤去(S136)の複合効果。

## 直近FAIL理由Top5 (直近100件中11件)

| 理由 | 件数 | 対策状態 |
|------|------|---------|
| lesson_candidate no_lesson_reason欠落 | 4 | FIXヒント実装済み(gate_report_format_main.py L113) |
| YAML parse error | 3 | autofix UNFIXABLE。hanzo cmd_karo_ci_fix_env_change固有 |
| assumption_invalidation MISSING | 2 | FIXヒント実装済み。hayate cmd_2434で自力修正→PASS |
| verdict/binary_checks矛盾 | 1 | GP-128で検出済み |
| knowledge_candidate str→dict | 1 | FIXヒント実装済み |

## 因果鎖

全11件FAIL→全件自力修正or家老介入→PASS。免疫系(FAIL→検出→自力修正→PASS)が正常動作。
残存FAIL=FIXヒントで忍者が修正できる範囲。構造的ブロッカーなし。

## 三層学習ループ健全性

- 第一層(個): FAIL→自力修正→PASSサイクル正常。retry平均~1.2回
- 第二層(対): workaround率0%(直近20件超clean)
- 第三層(全): FAIL率35%改善。gate蓄積効果
