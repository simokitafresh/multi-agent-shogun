# DREAM-GATE 3件 因果分析+cmd起票提案 (2026-05-07)

## 1. draft_lessons 32回BLOCK

**因果鎖**:
1. 忍者がlesson_candidate.found=true報告 → auto_draft_lesson.shがdraft登録 → 家老がlesson_review.shでconfirm/deleteせず次cmdへ
2. draftが蓄積 → cmd_complete_gate.shの own_draft_count>0 でBLOCK
3. 忍者は解消不能（「家老に報告して待機せよ」表示）。家老がlesson_reviewを忘れる限り繰り返し

**既存対策**: cmd_complete_gate BLOCK判定済み、循環防止(auto_draft_lesson skip)済み、cmd-complete SKILL Step 1にlesson_review配置済み
**未対策**: lesson_review.shの**強制実行**なし。家老が「なければスキップ」と判断しレビューを飛ばすとdraftが蓄積

**cmd起票提案**: cmd_complete_gate.shの前にdraft件数チェックを追加し、draft>0の場合はlesson_review完了をGATE前提条件として強制

## 2. report_format 11回BLOCK

**因果鎖**:
1. 忍者がテンプレートの構造体フィールド(knowledge_candidate等)をEdit toolで文字列として上書き/FILL_THIS残存で報告完了
2. gate_report_format_main.pyが型チェック+プレースホルダ検出でFAIL → 1-3回リトライで通過
3. 11回のcmd_complete_gate BLOCK(report_format起因)

**既存対策**: gate_report_format_main.py型検証済み、report-write SKILL手順明示済み、gate_report_autofix_main.pyにlesson_candidate list→dict変換あり
**未対策**: knowledge_candidate/self_gate_checkのstr→dict自動変換がautofix未実装

**cmd起票提案**: gate_report_autofix_main.pyにknowledge_candidate/self_gate_checkのstr→dict自動変換追加

## 3. lesson_done_missing 5忍者x10回

**因果鎖**:
1. 忍者がlesson_candidate.found=true報告 → auto_draft_lesson.shが何らかの理由(title空/project空等)でskip → lesson.doneファイル未生成
2. cmd_complete_gate.sh: found=trueなのにlesson.done不在 → lesson_done_missing BLOCK
3. 家老がlesson_check.sh手動実行するまでGATE停止

**既存対策**: lesson_write.sh正常登録時にlesson.done自動生成、lesson_check.sh手動救済スクリプト
**未対策**: auto_draft_lesson skip時にlesson.doneが発行されない

**cmd起票提案**: auto_draft_lesson.shのskip分岐でlesson.doneを「source: auto_draft_skip, reason: {skip理由}」として発行
