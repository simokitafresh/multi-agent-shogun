# 冷え観点(numbers/simulation) zero_streak根因分析+遡及適用
<!-- generated: 2026-06-20T09:30:00+09:00 by gunshi idle analysis -->

## 問題

startup gateのAdaptive Gating集計で:
- numbers: 0/10件(zero_streak=10)
- simulation: 0/10件(zero_streak=10)

gate_gunshi_cs_checklist.shが18件のdraft/reportでfinding_categoriesに冷え観点(numbers/simulation)が未反映とWARN。3セッション連続で先送りCRITICALに到達(2026-06-17 memory_db記録)。

## 対象エントリ分析

| cmd系統 | 件数 | numbers適用可能性 | simulation適用可能性 |
|---------|------|-------------------|---------------------|
| cmd_3461(SSOT棚卸し偵察) | 12 | YES: 対象ファイル数(33件)・検出パターン数の検算 | YES: 6名並列でファイル競合チェック |
| cmd_karo_recon_startup_defer_escalation | 2 | MARGINAL: 対象少数 | MARGINAL: 単独配備 |
| cmd_karo_hotfix_context_freshness_ga099 | 2 | NO: 対象1ファイル、数値論点なし | NO: 単独配備、手順単純 |
| cmd_karo_hotfix_context_saxo_ga100 | 1 | NO: 対象1ファイル | NO: 単独配備 |
| cmd_karo_hotfix_hook_yaml_dump_ga101 | 1 | NO: 対象5ファイル、数値論点なし | YES(記録済み): AC依存関係確認 |

## 根因

**真因=惰性省略(deepdive Phase 4: 早期終了本能の再現)**

cmd_3461系は6忍者並列の大量偵察cmdで、1件あたりのレビュー深度が浅くなった。
「hotfix/偵察だからnumbers/simulationは不要」という判断が12件連続で繰り返された。

しかし実際には:
- numbers: SSOT棚卸し結果の「33ファイルにハードコード」「22ファイルにtmux名分散」等の数値は検算可能だった
- simulation: 6名が同一リポジトリで並列走査する際のファイル競合・scope重複はシミュレーション対象だった

一方、hotfix系(context freshness/saxo)は本当にnumbers/simulationの論点がない。
問題は「論点がない」と「惰性で省略した」の区別が記録に残らないこと。

## 対策

### 即時(D0): finding_categories記録ルールの明確化

全レビューでnumbers/simulationを以下のいずれかで記録する:
- 論点あり → finding_categoriesに追加 + observationsに数値/シミュレーション結果
- 論点なし → finding_categoriesに追加しない代わりに、brainwash_checkに「numbers:N/A(対象1ファイル、数値主張なし)」等の除外理由を1行明記

これにより「惰性省略」と「意図的除外」が区別可能になる。

### 構造的(提案): brainwash_checkへの冷え観点除外理由必須化

[[gate_gunshi_cs_checklist]] (`scripts/gates/gate_gunshi_cs_checklist.sh` L272: `cold_category_missing`変数)の冷え観点WARNロジックを拡張:
- finding_categoriesにnumbers/simulationがない場合、brainwash_checkに除外理由が記載されているか確認
- 除外理由なし → WARN → BLOCK(段階的)
- 除外理由あり → OK(意図的除外として許容)

## 数値

- 冷え観点WARN対象: 18件(cs_checklist出力)
- うちnumbers適用可能だった: 12件(cmd_3461系)
- うちsimulation適用可能だった: 12件(cmd_3461系)
- 惰性省略率: 12/18 = 67%
- 先送りセッション数: 3(2026-06-17 CRITICAL到達)

## 因果リンク

- origin: [[冷え観点zero_streak]] -> [[cmd_3461大量レビュー惰性省略]] -> [[Phase4早期終了本能再現]]
- → [[deepdive_why_chain_20260321]] Phase 4(L80-) 「早期終了本能」: 「これで十分」が限界まで確認する努力を早期終了させる(L102)。12件連続省略の駆動力と同構造
- → [[gate_gunshi_cs_checklist]] L272-405: `cold_category_missing`変数の判定ロジック。対策実装ターゲット(brainwash_check除外理由チェック追加箇所)
- → [[LG027]] 計測対象のズレ(referenced率≠useful率と同構造: finding_categories記録≠観点使用)
