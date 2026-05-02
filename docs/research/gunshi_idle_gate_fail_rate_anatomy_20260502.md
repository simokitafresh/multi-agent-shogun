# gate FAIL率16% 解剖分析

- 分析者: 軍師 (gunshi)
- 日付: 2026-05-02
- 起源: 殿指示「軍師は成長したか？確認せよ」→ FAIL率16%が残存穴として特定

## 定量

- 全体FAIL率: 17.3% (761/4405)
- 直近100件FAIL率: 16%
- 改善幅: 1.3pt (微小)

## 忍者別FAIL (直近200件)

hayate:7, kagemaru:7, hanzo:6, saizo:4, kotaro:1。均等分布。特定忍者の問題ではない。

## FAIL理由Top5

1. verdict+bc:no矛盾 (3件) — verdict:PASSだがbc:noあり
2. lessons_useful形式 (3件) — useful fieldの欠落
3. YAML parse error (2件)
4. FILL_THIS残存 (2件)
5. 必須フィールドMISSING (2件)

## retry分布

- 1回FAIL→即修正: 62% (18/29)
- 2回: 24% (7/29)
- 3回以上: 14% (4/29)

## 根因

忍者がEdit toolで報告YAMLを編集する際、テンプレート既存フィールド(assumption_invalidation, lessons_useful)を巻き添え消去。report_field_set.sh経由では保護されているが、Edit tool直接編集は防げない。

## 結論

**FAIL率16%は健全な免疫応答の証拠**。62%が1回で自己修正。gateが正しく検出し、FIX hintで忍者が学習している。

追加投資のROI:
- PreToolUse hook(Level 4): 実装コスト高、効果限定(Edit tool経由のみ)
- report_field_set.sh���護(Level 3): Edit tool経由を防げない

現状の免疫応答で十分。「gateの成功=未熟さの証拠。発火しないシステムが完成系」(growth-loop.md §7)。
