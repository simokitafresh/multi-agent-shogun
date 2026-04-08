# cmd_323 R3-Task1 調査報告（blind_id: A）

対象: `scripts/cmd_complete_gate.sh`

## 1. 全体処理フロー（入力→判定→出力/副作用）

1. 入力検証
- 第1引数`CMD_ID`必須、`cmd_*`形式必須。違反時は`exit 1`（L12-23）。

2. 実行環境初期化
- `GATES_DIR`, `YAML_FILE`, `TASKS_DIR`, `LOG_DIR`, `GATE_METRICS_LOG`を設定（L25-29）。
- `mkdir -p "$GATES_DIR" "$LOG_DIR"`でディレクトリ作成（L30）。

3. 動的ゲートセット構築
- `detect_task_types`で`queue/tasks/*.yaml`から`parent_cmd`一致タスクを走査し、`task_type`を収集（L104-124）。
- 常時必須ゲート: `archive`, `lesson`（L135）。
- 条件付きゲート:
  - reconタスクが1つでもあれば`report_merge`追加（L141-143）。
  - implementタスクが1つでもあれば`review_gate`追加（L144-146）。
- `ALL_GATES`に統合（L148）。

4. 事前副作用（ベストエフォート）
- `parent_cmd`一致タスクの各忍者reportに対して`auto_draft_lesson.sh`を実行（L150-169）。
- 失敗はWARNで継続（non-blocking）。

5. 緊急override分岐
- `queue/gates/<cmd_id>/emergency.override`が存在すれば全ゲートをバイパス（L172-187）。
- `ntfy.sh`通知、`gate_yaml_status.sh`（WARN only）、`update_status`、`append_changelog`を実行して`exit 0`。

6. 通常ゲート判定（ALL_CLEAR初期値=true）
- `.done`ファイルの存在確認で必須/条件付きゲートを判定（L201-217）。
- 欠落時は`MISSING_GATES`と`BLOCK_REASONS`へ記録し`ALL_CLEAR=false`。

7. 追加整合性チェック（主にYAML/レポート系）
- `related_lessons`キー存在チェック（WARNのみ、L219-254）。
- `related_lessons`ありタスクは`lesson_referenced`非空必須（BLOCK対象、L255-329）。
- `related_lessons.reviewed:false`残存チェック（BLOCK対象、L331-369）。
- `lesson_candidate`構造/値チェック（多くがBLOCK対象、L371-458）。
- `skill_candidate`チェック（WARNのみ、L460-522）。
- `decision_candidate`チェック（WARNのみ、L523-584）。
- プロジェクト`tasks/lessons.md`内のdraft残存チェック（BLOCK対象、L586-629）。
- `karo` inbox既読10件以上で`inbox_archive.sh karo`実行（WARN only、L630-650）。
- pending decisionの`resolved && context_synced:false`検出（WARN only、L652-680）。
- recon系cmdで知識基盤未反映を警告（WARN only、L682-730）。

8. 最終判定
- `ALL_CLEAR=true`: `CLEAR`をmetricsへ追記し、`gate_yaml_status.sh`→`update_status`→`append_changelog`、さらに`lesson_update_score.sh`でhelpful加点（ベストエフォート）して`exit 0`（L734-795）。
- `ALL_CLEAR=false`: `BLOCK`をmetricsへ追記、理由を連結出力。加えてBLOCK原因パターンに応じて`lesson_write.sh --status draft`で自動draft教訓を生成し`exit 1`（L796-879）。

## 2. 関数一覧（役割・I/O・依存・呼出関係）

| 関数 | 行 | 入力 | 出力/副作用 | 依存 | 呼出元 |
|---|---:|---|---|---|---|
| `update_status` | 33-49 | `cmd_id` | `queue/shogun_to_karo.yaml`の対象cmd `status: pending -> completed`置換。`flock`で排他 | `sed`, `grep`, `flock` | override経路(L184), CLEAR経路(L743) |
| `append_changelog` | 52-101 | `cmd_id` | `queue/completed_changelog.yaml`へ`id/project/purpose/completed_at`追記。20件超で剪定 | `awk`, `grep`, `head`, `tail`, `mv`, `date` | override経路(L185), CLEAR経路(L744) |
| `detect_task_types` | 104-124 | `cmd_id` | `"<has_recon> <has_implement>"`をstdout返却 | `grep`, `sed`, `tr` | メイン(L138) |
| `record_block_reason` | 127-132 | `reason` | `BLOCK_REASONS[]`へ追加 | bash配列 | 各BLOCK判定箇所 |

呼出フロー要約:
- 起動直後に`detect_task_types`→ゲート集合決定。
- 判定途中でBLOCK条件が発生するたびに`record_block_reason`。
- 最終分岐でCLEAR/OVERRIDE時のみ`update_status`と`append_changelog`。

## 3. ゲート判定ロジック（PASS/BLOCK条件）

### 3.1 PASS（exit 0）
- 条件A: `emergency.override`存在（強制PASS, L172-187）。
- 条件B: `ALL_CLEAR=true`で最終到達（L734-795）。
  - 必須/条件付きゲート`.done`が全て存在。
  - BLOCK対象チェックに一つも違反しない（`lesson_referenced`空、`reviewed:false`残存、`lesson_candidate`不正、draft残存など）。

### 3.2 BLOCK（exit 1）
- `.done`欠落（L212-216）。
- `related_lessons`ありなのに`lesson_referenced`が空/不正（L318-321）。
- `related_lessons.reviewed:false`が残存（L359-363）。
- `lesson_candidate`欠落/構造不正/found:true時の`lesson.done`不整合（L429-453）。
- project配下`tasks/lessons.md`にdraft教訓が残存（L614-617）。

### 3.3 WARNのみ（BLOCKしない）
- `related_lessons`キー欠落（L246-249）。
- `skill_candidate`/`decision_candidate`欠落や不正（L505-516, L568-579）。
- `inbox_archive.sh`失敗・pending decision未同期・recon知識未反映（L630-730）。

## 4. YAML操作の方式

### 4.1 テキスト処理系（行指向）
- `sed`でstatus置換（L45）。
- `awk`で`purpose/project/CMD_PROJECT/CMD_PURPOSE`抽出（L60-71, L590-594, L686-690）。
- `grep`で件数/存在チェック（L94, L112, L611, L635 等）。

特徴:
- 速いがフォーマット依存（インデントやキー出現順、文字列部分一致）になりやすい。

### 4.2 Python+PyYAML（構造解析）
- `python3 -c` + `yaml.safe_load`で`related_lessons`, `lesson_referenced`, `lesson_candidate`, `skill_candidate`, `decision_candidate`, `pending_decisions`, `config/projects.yaml`を解析（L232-241, L266-276, L285-300, L341-355, L392-415, L480-499, L543-562, L598-606, L657-669, L759-775）。

特徴:
- 構造への耐性が高い。現状は多数の小さいPythonワンライナーを繰り返し実行している。

## 5. エッジケース（3件以上）

1. `update_status`の範囲置換終端が曖昧
- `sed -i "/^  - id: ${cmd_id}$/,/^  - id: /..."`は終端に次エントリが必要（L45）。
- 対象cmdが最終エントリの場合、実装依存で置換範囲が意図通りでないリスク。

2. `grep -q "parent_cmd: ${CMD_ID}"`が部分一致
- 例: `cmd_32`が`cmd_323`にもヒットする可能性（L154, L225, L261, L337, L377, L466, L529, L753）。
- 異cmdタスクを誤って集計/判定する恐れ。

3. `set -e`下で`ntfy.sh`失敗がoverride成功を潰す
- override経路の`ntfy.sh`は`if`で包まれておらず失敗時に即終了し得る（L177）。
- 「緊急overrideで必ず通す」設計意図と衝突。

4. `append_changelog`の`entry_count`取得が`0\n0`混入余地
- `grep -c ... || echo 0`（L94）は過去教訓L019系の典型。0件時の扱いがシェル実装依存で不安定化しやすい。

5. `lesson_done`のsource判定が先頭行限定
- `grep '^source:'`で抽出（L425）。YAMLのインデント付き`source:`やネスト構造だと誤検知/未検知。

## 6. 改善提案（行番号付き、実行可能）

### 提案1: `parent_cmd`完全一致化（誤マッチ防止）
- 対象: L112, L154, L225, L261, L337, L377, L466, L529, L753
- 現状: `grep -q "parent_cmd: ${CMD_ID}"`
- 改善案:
  - `grep -Eq "^\s*parent_cmd:\s*${CMD_ID}\s*$" "$task_file"`
  - 可能ならPython側に寄せて`task.parent_cmd == CMD_ID`の構造比較。
- 効果: Wave跨ぎ/部分一致による誤判定を防止（L048系再発予防）。

### 提案2: override経路の通知をnon-blocking化
- 対象: L177
- 現状: `bash ntfy.sh ...`失敗で`set -e`により処理全体が落ちる可能性。
- 改善案:
  - `if ! bash "$SCRIPT_DIR/scripts/ntfy.sh" "..."; then echo "WARN: ntfy failed"; fi`
- 効果: 緊急時の通過保証を壊さない。

### 提案3: `update_status`をインデント非依存・末尾安全に
- 対象: L40-46
- 現状: `^  - id:` / `^    status:`に固定依存。
- 改善案:
  - Python+PyYAMLで対象cmdを検索し`status`更新後にatomic write。
  - 既存シェル維持なら`awk`でブロック抽出し末尾エントリも安全に処理。
- 効果: L034/L010系のフォーマット変動耐性を確保。

### 提案4: Pythonワンライナー集約で性能・可読性改善
- 対象: L232以降の多数`python3 -c`
- 現状: 毎回プロセス起動でオーバーヘッド大、保守点在。
- 改善案:
  - `scripts/gates/cmd_gate_helpers.py`に集約し、1回実行で必要情報をJSON出力。
- 効果: 実行時間短縮、判定ロジックのテスト容易化。

## 7. 依存外部スクリプト一覧（本スクリプトから呼出）

- `scripts/auto_draft_lesson.sh`（L160）
- `scripts/ntfy.sh`（L177）
- `scripts/gates/gate_yaml_status.sh`（L179, L738）
- `scripts/inbox_archive.sh`（L640）
- `scripts/lesson_update_score.sh`（L778）
- `scripts/lesson_write.sh`（L824, L839, L862）

以上。
