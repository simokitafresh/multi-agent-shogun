# cmd_323 R3-Task1 ブラインドレビュー: cmd_complete_gate.sh仕様調査2出力比較

- **対象**: scripts/cmd_complete_gate.sh (880行)
- **タスク**: 仕様調査（処理フロー、関数、ゲート判定、YAML操作方式、エッジケース、改善提案）
- **注意**: Output Bが欠損（報告YAMLがWave2タスクで上書きされたため）。A/Cの2出力のみ

---

## Output A

### 全体構造
8段階の処理フロー:
1. 入力検証(L12-23) → 2. 環境初期化(L25-30) → 3. 動的ゲートセット構築(L104-148) → 4. 事前副作用(auto_draft_lesson, L150-169) → 5. 緊急override(L172-187) → 6. ゲート判定(L201-217) → 7. 追加整合性チェック(L219-730) → 8. 最終判定(L734-879)

### 関数一覧
4関数: update_status(L33-49), append_changelog(L52-101), detect_task_types(L104-124), record_block_reason(L127-132)
外部依存6スクリプト: auto_draft_lesson.sh, ntfy.sh, gate_yaml_status.sh, inbox_archive.sh, lesson_write.sh, lesson_update_score.sh

### ゲート判定
- PASS: emergency.override存在 or ALL_CLEAR=true
- BLOCK: .done欠落, lesson_referenced空, reviewed:false残存, lesson_candidate不整合, draft教訓残存
- WARN: skill/decision_candidate欠落, inbox_archive, 未反映PD, recon知識未反映

### YAML操作方式
- sed: status置換(L45) — 4space固定
- awk: purpose/project抽出 — 柔軟マッチ(`[ ]*`)
- python3 -c: related_lessons, lesson_referenced等 — 構造解析
- grep: parent_cmd一致, 件数チェック

### エッジケース (6件)
1. **update_statusの範囲置換終端が曖昧** — 最終エントリで置換範囲不定
2. **parent_cmd部分一致** (9箇所) — cmd_32がcmd_323にもヒット
3. **set -e下でntfy.sh失敗がoverride成功を潰す** — if未包囲
4. **changelog entry_count取得の`0\n0`混入余地** — grep -c + || echo 0 (L019系)
5. **lesson_doneのsource判定が先頭行限定** — ネスト構造で未検知リスク
6. **(暗黙)**: detect_task_typesの全タスク走査言及なし

### 改善提案 (4件)
1. parent_cmd完全一致化 (L112等9箇所) — `$`追加
2. override経路のntfy non-blocking化 (L177) — if包囲
3. update_statusのインデント柔軟化 (L40,45) — Python or `[ ]*`
4. Pythonワンライナー集約 — cmd_gate_helpers.pyに統合

---

## Output B

**欠損** — 報告YAMLがWave2タスク(ninja_monitor.shレビュー)で上書きされたため、Output Bのデータは利用不可。

---

## Output C

### 全体構造
16段階のパイプライン:
引数バリデーション → ディレクトリ初期化 → auto_draft_lesson → 緊急override → .doneフラグチェック → related_lessons注入チェック → lesson_referenced検証 → reviewed:false残存 → lesson_candidate検証 → skill_candidate検証(WARN) → decision_candidate検証(WARN) → draft教訓存在チェック → inbox_archive強制(WARN) → 未反映PD検出(WARN) → 調査恒久化チェック(WARN) → 最終判定(CLEAR/BLOCK)

テキスト版フロー図付き。

### 関数一覧
4関数: update_status(L33-49), append_changelog(L52-101), detect_task_types(L104-124), record_block_reason(L127-132)
外部依存6スクリプト: auto_draft_lesson.sh, gate_yaml_status.sh, ntfy.sh, inbox_archive.sh, lesson_write.sh, lesson_update_score.sh (ブロック性の分類付き)

### ゲート判定
**4カテゴリに分類:**
- 3.1 必須ゲート: archive, lesson
- 3.2 条件付きゲート: report_merge(reconあり時), review_gate(implementあり時)
- 3.3 ブロッキングチェック: lesson_referenced, reviewed:false, lesson_candidate, draft教訓
- 3.4 非ブロッキング(WARN): skill/decision_candidate, inbox_archive, 未反映PD, 穴4
- 3.5 緊急override

### YAML操作方式 (3カテゴリに分類 + 詳細テーブル)
- **4.1 awk/sed方式**: update_status(4space固定), append_changelog(柔軟マッチ), CMD_PROJECT/PURPOSE(柔軟)
  → **同一ファイル内でインデント対応が不統一**と指摘
- **4.2 Python yaml.safe_load方式**: 10箇所の一覧
- **4.3 grep/head方式**: parent_cmd一致等6パターン

### エッジケース (6件)
1. **EC-1: update_statusの4space固定インデント依存 (HIGH)** — L034教訓直結。同ファイル内のawk(柔軟)との不統一を明示
2. **EC-2: parent_cmd部分一致 (MEDIUM)** — 全9箇所特定
3. **EC-3: Python -cシェル変数展開 (MEDIUM, L047)** — 11箇所特定。os.environ推奨
4. **EC-4: changelog剪定の行数固定前提 (LOW)** — 4行/エントリ前提のtail -n 80
5. **EC-5: detect_task_types全タスク走査 (LOW)** — 完了済みタスク残存時の誤検出リスク
6. **EC-6: grep -cの0件時挙動 (LOW, L019)** — 各箇所の安全性を個別分析(L94=safe, L611=safe)

### 改善提案 (3件)
1. update_statusインデント柔軟化 (L40,45) — 案A(sed `[ ]*`) vs 案B(Python yaml)。Before/Afterコード付き
2. parent_cmd完全一致化 (全9箇所) — 案A(行末`$`追加) vs 案B(正規表現)。全9箇所リスト付き
3. Python -cのos.environ経由化 (11箇所) — Before/Afterコード付き

### 教訓参照テーブル
L034, L010, L001, L009/L007の適用箇所を明記
