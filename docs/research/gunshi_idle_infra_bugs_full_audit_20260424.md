# インフラバグ全量監査

## 調査日
2026-04-24 殿指示

## 調査方法
- karo_workarounds 全489件(WA=112件)をカテゴリ分類
- 活性(4/15以降)vs沈静化(4/15��前)を判定
- 各カテゴリの根因特定+現在の修正状態を確認

## 結果サマリ

### 修正済み・沈静化（再発なし）
| カテゴリ | 件数 | 最終発生 | 修正 |
|---------|------|---------|------|
| report_yaml_format | 16→21 | 4/19 | **本セッ��ョンP1-P8で全量対処** |
| ci_gate_mismatch | 13 | 4/6 | LG015(HEAD~1→git log --grep)で根治 |
| stale_ac_contamination | 6 | 4/11 | reset_stale_fields(L188)+STALE_RESET_DONE gate |
| recording_error | 6 | 4/7 | ��出し構文エラー修正済み |
| task_redeploy | 4 | 3/30 | AC上書きロジック修正済み |
| commit_missing | 4 | 4/15 | Codex CLI構造問題→Opus復帰で解消 |
| ac_injection_failure | 2 | 3/26 | MAX_INJECT修正(a9326c35) |

### 活性（直近2週間に発生、再発リスクあり）
| カテゴリ | 件数 | 最終発生 | 根�� | 状態 |
|---------|------|---------|------|------|
| verdict_override | 9 | 4/15 | AC固定値/waive運用 | △ 運用起因。構造修��困難 |
| uncategorized | 8 | 4/22 | 混在(test_root 5件+target_path漏れ+MAX_INJECT) | △ 個別修正済み |
| yaml_field_set上書き | 1 | 4/20 | verdict→resultフィールド上書き | **要調査** |
| stale_report | 2 | 4/22 | deploy_notice二重挿入 | **要調査** |
| scope_mismatch | 2 | 4/19 | deploy_task stale chunkフィールド | △ reset_stale_fieldsで対処���みのはず |

### 未修正インフラバグ（構造的に再発しうる）

#### BUG-1: yaml_field_set verdictがresultフィールドを上書き（4/20, 1件）
- **現象**: yaml_field_set.shでverdictを書込むとresultフィールドが上書きされYAML破損
- **根因**: 未調査。AWK経路のキーマッチングが`result`と`verdict`で混同する可能性
- **影響**: 報告YAMLのresult.summaryが消失
- **優先度**: HIGH（データ消失）

#### BUG-2: deploy_notice二重挿入（4/22, 1件, cmd_2235）
- **現象**: deploy_task.shがstale notice(STALE TASK INVALID...)を��重挿入→YAML破損
- **根因**: apply_patchで重複deploy_notice継続行が残る
- **影響**: task YAMLパース失敗→忍者が作業不能
- **優先度**: MEDIUM（task YAML破損だが���配備��回復可能）

## 総合判定
- 112件WA中、直近30件で2件のみ（WA率6.7%）→大幅改善
- 沈静化24カテゴリ（構造修正済み）
- 活性2件（BUG-1, BUG-2）が残存する可能性あり
