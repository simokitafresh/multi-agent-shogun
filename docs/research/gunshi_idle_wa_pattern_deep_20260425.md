# WA(workaround)パターン深掘り分析 2026-04-25

## メタデータ
- 分析者: 軍師(gunshi)
- 日付: 2026-04-25
- トリガー: idle自走 Step 1+5 (karo_workarounds分析→因果推論)
- 対象: logs/karo_workarounds.yaml 全149件

## §1 WA率推移

| 期間 | WA率 |
|------|------|
| entries[0-50] | 52% |
| entries[50-100] | 62% |
| entries[100-149] | 27% |
| 直近30件 | 30% |

改善傾向。第二層ループ(軍師レビュー+gate)の効果。

## §2 直近30件WA 9件の内訳

| category | 件数 | 根因 |
|----------|------|------|
| verdict_override | 5 | AC設計ミス(不可能条件含む) |
| stale_ac_contamination | 2 | deploy_task.sh旧AC残留 |
| gitignore_untracked | 1 | gitignore対象にcommit AC |
| scout_exempt_missing | 1 | scout_exempt未設定 |

## §3 verdict_override 6件の因果分析

共通根因: AC設計時に「忍者が正しくno判定する場合」を考慮していない。
- 推奨≠必須混同 → 忍者がno→FAIL→家老override
- gitignore対象にcommit AC → 不可能→override
- 進行中月のデータ差異 → 構造的にno→override
- 研究cmdのoutput commit → 対象外→override

因果鎖: AC設計品質低→忍者正当FAIL→家老override→WA計上→WA率上昇=負の複利

## §4 推奨

1. **verdict_override根因**: AC設計ルールに「全ACのbinary checkが物理的に可能か」を追加。draftレビュー時に軍師が検証(Step 3 simulation)
2. **stale_ac**: deploy_task.shに旧AC残留検出はコスト>効果(直近2件のみ)。教訓LK021で十分
3. **q8_縮小表現**: TP(正当検出)確認済み。将軍がWARN→修正→CLEARのフローで解消。ゲート正常動作
