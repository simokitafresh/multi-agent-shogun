# waive_ac盲点 — 手段の免除≠目的の免除

殿指示(2026-04-16): 「今クリアされても今より強くてニューゲームできるようにせよ。なぜなぜ7回」

## 事実

- cmd_1948(①×①): 成果物cmd_1948_*が0件。CSVは全て⑤_*データ。忍者が①フィルタ未適用
- GATE CLEAR: 家老が成果物現物確認なしでgate通過（タイミング: 軍師FAIL到着前）
- gate_report_format.sh: 報告YAMLフォーマットのみ検証。成果物の実在・命名は検証対象外

## なぜなぜ7回

| # | なぜ | 回答 |
|---|------|------|
| 1 | なぜ成果物不在がGATEを通過した？ | gate_report_format.shはfiles_modifiedの実在を検証しない |
| 2 | なぜ実在を検証しない？ | IMPL cmdはcommit検証(git log --grep)で間接確認。RESEARCH cmdはcommit不要で検証経路がない |
| 3 | なぜRESEARCH cmdに代替検証がない？ | cmd_1946でwaive_ac導入時に免除のみ設計、代替検証を設計しなかった |
| 4 | なぜ代替検証を設計しなかった？ | waive_ac=「正当なno」の表現。gateが「no」を通す設計。免除=検証不要と等式化 |
| 5 | なぜ免除=検証不要？ | commit checkの目的を「commitを強制すること」と捉えた。本来の目的は「成果物が確定状態にあること」 |
| 6 | なぜ目的をすり替えた？ | 手段(commit)と目的(成果物確定)を混同 |
| 7 | **根因: 手段の免除≠目的の免除。waive_acで手段(commit)を免除したが、目的(成果物確定)の代替検証経路を埋め込まなかった** |

## 因果鎖

```
waive_ac導入(cmd_1946) → commit check免除 → 成果物検証経路消失
→ cmd_1948: 忍者が①フィルタ未適用 → cmd_1948_*不在
→ gate_report_format.sh: report verdict PASSのみで通過
→ GATE CLEAR(誤判定) → 家老が次cmd配備 → 負の複利
```

## 改善案(3層)

| 層 | 対象 | 変更 | 防御Level |
|----|------|------|----------|
| 1 | gate_report_format.sh | RESEARCH cmdのfiles_modified実在チェック | L4 |
| 2 | gate_report_format.sh | files_modifiedファイル名にparent_cmd含有チェック | L4 |
| 3 | gate_gunshi_report_precheck.sh PRE3 | commit不在時のfiles_modified実在代替チェック | L4 |

## 一般原理

**手段を免除するとき、目的を達成する代替手段を同時に埋め込め。**
免除は手段のスキップであり、目的のスキップではない。
