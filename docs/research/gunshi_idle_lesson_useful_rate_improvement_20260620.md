# 教訓有効率(useful rate)改善分析
<!-- generated: 2026-06-20T16:25:00+09:00 by gunshi idle analysis -->

## 計測値

- gate_lesson_health.sh判定: useful率 18.5% (5/27件, 直近30cmd)
- startup gate表示: 26.5% (9/34件) — 計測窓の差異
- lesson_impact.tsv feedback行: 217件
- reports内lessons_useful not_useful合計: 319件 (直近60報告)

## 上位not useful教訓 (20回以上)

| ID | not useful回数 | when設定 | how設定 | title |
|----|---------------|---------|--------|-------|
| L696 | 24 | 未設定 | 未設定 | set-e下でALERT集計script呼出し時は終了値捕捉を明示する |
| L660 | 24 | 未設定 | 未設定 | gate_skill_script_refs WARNは対象外ファイルの更新漏れを示す |
| L602 | 23 | あり(汎用的) | あり | karo_directのtraining配備はdeploy_task.sh --directを使え |
| L342 | 22 | あり(汎用的) | あり | ホワイトリスト.gitignoreではscriptsディレクトリ内の新規ファイルもgit add -f必須 |
| L690 | 22 | あり(限定的) | あり | cwd非依存スクリプトはscript_dir基準でパス解決せよ |
| L705 | 21 | あり(限定的) | あり | HEAD確認時はcommit statだけで対象実装有無を判断しない |
| L614 | 21 | 未設定 | 未設定 | script名抽出regexはハイフン付きファイル名を含める |

## 根因分析

### 構造1: when/how未設定 → キーワードマッチのみで注入

L696, L660, L614はwhen/howが「未設定」。deploy_task.shのinject_related_lessons()はtech_terms()でJaccard類似度を計算し、スコア上位を注入する。when/howがないとキーワードベースの弱いマッチに依存し、タスクと無関係な教訓が注入される。

### 構造2: whenが汎用的すぎる → 全タスクにマッチ

L342「新規ファイル作成時」、L602「タスク配備やデプロイ手順を変更する時」は条件が広すぎ、ほぼ全cmdで注入対象になる。

### 構造3: 注入→not useful→feedbackが蓄積しない

lesson_impact.tsvのfeedback行は217件だが、上位not useful教訓のfeedback記録は0-1件。record_lesson_feedback.shはGATE処理時に呼ばれるが、全cmdのfeedbackが蓄積するわけではない。USEFUL_RATE_THRESHOLD=0.40フィルタが機能するには十分なfeedback蓄積が必要だが、蓄積速度が遅い。

## 対策案

### 即時実行可能(D0)
1. **when/how未設定教訓3件にwhen/howを追加**: L696, L660, L614のwhenを限定的条件に修正。関連性の低いタスクへの注入を減らす

### cmd起票提案
2. **注入ロジックでwhen未設定教訓のスコアを降格**: deploy_task.sh inject_related_lessonsでwhen未設定の教訓にペナルティを付与
3. **lesson_impact.tsvへのfeedback蓄積を加速**: cmd_complete_gate以外のタイミングでもfeedbackを記録(例: 家老がreview完了時にbatch記録)

## 因果リンク

- → [[LG027]] referenced率≠useful率 — 同根の計測対象ズレ問題
- → [[gate_lesson_health]] ALERT発火 — useful率18.5%がトリガー
- → [[deploy_task.sh inject_related_lessons]] 注入ロジックの精度問題
