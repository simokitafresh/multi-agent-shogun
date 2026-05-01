# SG7 gate_prediction 構造的盲点分析

- 分析者: 軍師 (gunshi)
- 日付: 2026-05-02
- 起源: idle自走Step 2(review_log傾向分析) → LGTM→BLOCK 7件発見

## 発見

直近review_log (cmd_2443-2453) にgate_result: BLOCKが7件。全てverdict: LGTMで軍師がAPPROVEした報告。
karo_workarounds上は全7件clean/workaround:false（家老の手動修正なし）。

### BLOCK出所

- gate_report_format: cmd_2453のみ初回FAIL(knowledge_candidate items空, 18秒で忍者自己修正→PASS)
- **cmd_complete_gate.sh**: 残り6件+cmd_2453 = 7件全ての最終BLOCKソース
- 通知経路: cmd_complete_gate.sh L4725-4727 → inbox_write.sh → gunshi inbox → gate_sync → review_log

### 根因: SG7 gate_prediction のカバレッジ不足

SG7バンドルが予測する検査:
- gate_report_format PASS (report_format)
- commit_verified (files_modified)
- lesson_extraction (lesson_candidate存在)

cmd_complete_gate.shの追加検査(SG7未カバー):
1. **empty_lessons_useful** — 教訓注入済み(related lessons)なのにuseful空リスト → BLOCK
2. **lesson_done_source** — lesson完了ソース検証
3. **draft_lessons count** — cmd定義の教訓数と報告の教訓数の不一致
4. **missing_gate:report_merge** — report_merge.done未生成
5. **ac_version_mismatch** — タスクYAMLのAC版と報告のac_version_read不一致
6. **lesson_candidate format** — found/reason/items等の構造検証
7. **binary_checks_fail** — bc結果に"no"含む
8. **purpose_validation_fit_false** — 目的適合性チェック

### 定量

- SG7 gate_prediction accuracy: 直近10件で7件BLOCK予測不能 = **30%** (3/10のみCLEAR正解)
- cmd_complete_gate BLOCK→karo WA率: 0% (7件中7件clean) → BLOCKは自動解消される性質のものが多い

### 因果鎖

SG7がgate_report_formatのみ予測 → cmd_complete_gateの追加検査を見逃す → LGTM→BLOCKの偽陽性蓄積 → accuracy統計が過大評価される(LGTM時に「GATE通過する」と思っているが実際はBLOCK)

### 改善案

**Option A: SG7 gate_prediction拡張** — lessons_useful完全性+lesson_done_source+draft_lessons数のチェックをSG7バンドルに追加。report review時に手動確認。

**Option B: cmd_complete_gate dry-run呼出し** — SG7評価時にcmd_complete_gate.shをdry-runモードで実行し、BLOCK予測を自動化。ただしdry-runモードが存在するか未確認。

**Option C: gate_gunshi_report_precheck拡張** — PRE項目にlessons_useful完全性チェックを追加。既存PRE1-11に+2-3項目。自動化Level 4。

推奨: **Option C**（最もimpact/cost比が高い。既存gateに1行原理を追加）。
PRE項目候補:
- PRE12: lessons_useful空チェック(related lessons注入済み && useful空 → WARN)
- PRE13: lesson_done_source存在チェック(lesson_candidate.found=true && lesson_done_source不在 → WARN)

### 注記

7件全てkaro WA=0。BLOCKは忍者自己修正or家老自動処理で解消。
SG7盲点ではあるが、実運用上の被害は限定的。accuracy向上のための改善。
