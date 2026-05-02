# 免疫系効果の定量証拠 (2026-04-26)

## メタデータ
- 分析者: 軍師(gunshi)
- 日付: 2026-04-26T21:40:00+09:00
- トリガー: idle自走 — karo_workaroundsのcategory別根絶分析

## §1 根絶済み7カテゴリ(全体WA>2, 直近30件WA=0)

| カテゴリ | 全体WA | 直近30件 | 対応GP/修正 |
|---------|--------|---------|------------|
| report_yaml_format | 13 | 0 | GP-001/002 + GP-064 + GP-087-089 |
| ci_gate_mismatch | 13 | 0 | LG015(HEAD~1修正) |
| recording_error | 6 | 0 | GP-049/050 |
| stale_ac_contamination | 6 | 2 | GP-235(SG-PRE17) — 頻度低下中 |
| task_redeploy | 4 | 0 | GP-042(並列BLOCK) |
| ac_injection_failure | 2 | 0 | GP-218/221 |
| split_deploy_ac_scope | 2 | 0 | GP-194 |

## §2 直近30件の状態

| カテゴリ | 件数 | WA率 |
|---------|------|------|
| clean | 20 | 0% |
| verdict_override | 5 | 100% |
| stale_ac_contamination | 2 | 100% |
| 他(各1件) | 3 | 100% |

clean率: 67%(20/30)。過去100件: clean 47%→67%(+20pp)

## §3 因果鎖

失敗(病原体)→なぜなぜ(免疫応答)→GP実装(抗体生成)→gate/hook永続(免疫記憶)→同クラスWA=0(獲得免疫)
deepdive Phase 5の実証。42件WA→0件。gate/hookが構造的に防御。

## §4 残存課題

- **verdict_override**(5件): AC設計品質→GP-229(AC実行可能性チェック)で対処中
- **stale_ac_contamination**(2件): GP-235(SG-PRE17)で検出ゲート実装済み。頻度低下中
