# gate_fire_log Traceback記録改善 + AC self-verification FAIL分析 (2026-05-10)

## 1. Traceback記録改善 (D0完了)

- **問題**: gate_fire_log.yamlにPython Tracebackが記録される際、1行目(`Traceback (most recent call last):`)のみ記録。実際のエラーメッセージが失われ診断不能
- **原因**: gate_report_format.sh L117のawkが`exit`で1行目のみ取得
- **修正**: Tracebackパターン検知時に最終行(実際のエラー)を取得 (commit cc020f3e)
- **検証**: syntax check PASS, 16 bats全PASS, 家老LGTM

## 2. AC self-verification missing FAIL分析

- **データ**: gate_fire_log全体で70件の`AC self-verification missing`FAIL
- **パターン**: 0/N ACs — 全ACのbinary_checksが未記入で報告提出
- **直近7件の根因**: deploy_task.shのACカウントバグ(commit 4e4f0bb0 2026-05-10 15:17で修正)
  - `count_acs_from_value()`が新AC形式(list[dict])でlen=1→ac_count=0→テンプレート未注入
  - 13:26〜15:17の間はbinary_checksテンプレートが注入されず忍者が空`{}`で報告
  - 修正後(16:09〜)は正常注入復活確認
- **既存GP-002(bc事前生成)は機能中**: テンプレート注入の前提(ACカウント>0)が壊れたのが原因

## 3. deploy_task.log YAML parseエラー

- 5件のNINJA_WP ERROR: task YAML parseエラー
- shogun_to_karo.yaml内のエスケープされていない`|`文字がYAML parseを破壊
- 非致命的(non-fatal)として続行。運用影響なし

## 因果鎖

Level5化の大量commit(0b4b64d4等) → ACカウント関数が新形式に未追従 → ac_count=0 → binary_checksテンプレート注入条件不成立 → 忍者が空bcで報告 → gate FAIL 7件 → 忍者が自己修正(免疫Level4が機能) → 修正commit(4e4f0bb0) → 注入復活
