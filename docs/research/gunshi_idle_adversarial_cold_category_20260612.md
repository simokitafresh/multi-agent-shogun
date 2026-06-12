# Adversarial冷え観点分析 — 3セッション連続WARN根因と対処
<!-- generated: 2026-06-12T15:50:00+09:00 by gunshi idle analysis -->

## 問題

startup gateで「CS観点チェックリスト/冷え観点WARNあり」が3セッション連続(2026-06-10〜12)。
gate_gunshi_cs_checklist.shが11件のdraft/reportでadversarial観点がfinding_categoriesに未反映と検出。

## 根因分析

### 冷え判定ロジック(gate_gunshi_cs_checklist.sh L318-401)
- 直近10件のdraft/reportレビュー中に、adversarial観点が1件も使われていない場合「冷えている」と判定
- 冷え状態のまま次のレビューでadversarialをfinding_categoriesに含めていなければWARN

### 対象11件の内訳

| cmd_id | review_type | 内容 | adversarial該当性 |
|--------|-------------|------|-------------------|
| cmd_3319 | draft/report | cycle health計測修理(awk構造) | 計測ロジックのみ。セキュリティ関連なし |
| cmd_3320 | draft/report | PI原理層追記(projects YAML) | 文書追記のみ。コード変更なし |
| cmd_3321 | draft/report | TZ cutover docs明記 | 文書のみ。コード変更ゼロ |
| cmd_3322 | draft/report | beforeスナップショット採取(本番読取) | 読取りのみ。破壊的操作なし |
| cmd_3323 | draft/report | 起票検査FP計測・分類(分析のみ) | 分析のみ。コード変更はscope外 |
| cmd_3324 | draft/report | AC2ファサード化(scripts+backend) | **report側でadversarial適用済み** |
| cmd_3325 | draft/report | MTD As-of表示PR1(frontend) | フロント表示のみ。入力処理なし |

### 結論

- 11件中10件はセキュリティ関連コード変更を含まず、adversarial観点の適用が不適切
- cmd_3324のreport側は既にadversarialを含んでいる
- **遡及追記は虚偽記載となるため不実施**
- WARNの根因はadversarial観点が「冷えている」こと自体ではなく、直近のcmdがdocs/分析/フロント表示に偏りadversarial該当cmdが少なかったこと

### 対処（実施済み+今後）

1. **実施済み**: cmd_karo_hotfix_skill_fail_rate_escalation(本セッション)でadversarial追記。入力堅牢化=adversarial観点の実質的検証
2. **今後**: scripts/対象cmdのレビュー時、セキュリティ関連でなくても「壊れた入力への耐性」をadversarial観点として意識的に検証・記載する
3. **構造的対策**: §5.6のルール「セキュリティ関連コード変更時はadversarial明記」に加え、「入力バリデーション/エスケープ/エラーハンドリング堅牢化もadversarial該当」をレビュー時に自問する

## 数値

- adversarial使用率: 直近10件中2/10(20%) → WARN閾値
- 冷えWARN連続: 3セッション(2026-06-10〜12)
- 対象cmd中セキュリティ関連: 1/7 cmd(cmd_3324のみ)
- 遡及追記: 0件(虚偽記載防止)
- 本セッション追記: 1件(cmd_karo_hotfix→adversarial追加)
