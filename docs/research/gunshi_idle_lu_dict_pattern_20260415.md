# lessons_useful dict→list WA パターン分析 2026-04-15
> gunshi idle自走 Step 1→Step 5 因果分析

## 対象事象
cmd_1921 影丸(kagemaru) — lessons_useful dict/list混在 → gate BLOCK → 家老workaround(report_field_set.sh)

## 因果鎖
忍者がEdit toolでlessons_useful構造を壊す(YAML dict記法 0:{id:X})
→ gate_report_format.sh BLOCK + FIXヒント表示(L188-189)
→ 忍者CTX or /clear → FIXヒント未到達
→ 家老がreport_field_set.shで手動修復
→ workaround 1件

## 既存防御の確認
| 防御 | 状態 | 効果 |
|------|------|------|
| gate_report_format.sh L188 | 存在 | BLOCK+FIXヒント。dict→listのPythonコマンド表示 |
| gate_report_autofix.sh | **撤去済** | GP-107消火4問で「Q1:内容不変でない」として撤去 |
| PostToolUse report guard | **不在** | GP-032 trackerにimplementedとあるがファイル不在 |
| ninja_weak_points | 存在 | deploy_task.shが弱点パターン注入。影丸WA率33%(report_yaml_format) |

## GP-107消火4問の再評価
numbered dict→list変換: `{0: {id:X,useful:true,reason:Y}, 1:...}` → `[{id:X,useful:true,reason:Y},...]`
- Q1: 内容不変か？ → **YES**。values()のリスト化のみ。キー(0,1,2)はYAMLのナンバリングアーティファクト
- Q2: 根本原因を隠すか？ → NO。忍者のYAML記法誤解が根因だが、テンプレートが正しく注入されているのに壊される
- Q3: 別の仕組みで根本対処できるか？ → PostToolUse hookでEdit直後に構文検証(根因に近い対処)
- Q4: 10回繰り返したら？ → 家老workaround 10回=負の複利

## 結論
1. GP-107撤去判定を再評価: numbered dict→list変換は内容不変。autofix復活が妥当(L4)
2. PostToolUse report edit guardの新規作成(根因対処。L4)
3. 両方とも軍師権限外→家老に提案

## 提案
- GP-196: gate_report_autofix.shにnumbered dict→list変換を復活(内容不変の構造変換のみ)
- GP-197: PostToolUse Edit hookでreport YAML構文検証(忍者がEdit直後にBLOCK)
