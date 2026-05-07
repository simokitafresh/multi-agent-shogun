# 修正副作用スキャン: cmd_2593/2594/2595 (2026-05-07)

## 対象
- cmd_2593: auto_draft_lesson.sh skip時lesson.done生成 (commit 2897292c)
- cmd_2594: gate_report_autofix knowledge_candidate str→dict (commit 63b39bc1)
- cmd_2595: cmd-complete SKILL.md lesson_review強制 (commit ee08ec18+8a3101b1)

## 5パターン副作用チェック

| パターン | cmd_2593 | cmd_2594 | cmd_2595 |
|----------|----------|----------|----------|
| return 1波及 | なし(関数内exitなし) | なし(データ変換のみ) | N/A(SKILL.md) |
| set +eスコープ | なし(set -e維持) | なし(Python try-except) | N/A |
| フィルタ偽陰性 | cmd_*パターン非一致時は未生成(既知制約) | fast path+Python一致(偽陰性なし) | N/A |
| 上限値状態除外 | なし | なし | N/A |
| 非atomic更新 | lesson.done 1ステップ書込み | data dict内変換+最後に1回YAML書込み | N/A |

## 結論
**3cmd全て副作用なし。** 42%検出率は今回適用外。

## 軽微注記
cmd_2594のknowledge_candidate変換先にfound:falseが明示されていない。
gate_report_format_main.pyはfound=None(未設定)でチェックスキップするため動作影響ゼロ。
将来的にfound明示を追加するのが望ましいがP3(低優先)。
