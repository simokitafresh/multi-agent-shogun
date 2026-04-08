# cmd_323 R4-Task1 調査: `scripts/lesson_write.sh` 仕様

- 調査日: 2026-02-25
- 調査者: sasuke (codex)
- 対象: `scripts/lesson_write.sh`
- 関連: `scripts/sync_lessons.sh`, `scripts/pending_decision_write.sh`, `config/projects.yaml`

## 0. 依存関係確認（scripts/lib）

`lesson_write.sh` には `source scripts/lib/*` が存在しない。`rg` で `source`/`.` による `scripts/lib` 読込を確認したがヒットなし。

## 1. 全体処理フロー（引数解析 → 教訓登録 → context追記 → 完了）

1. 初期化・引数受取
- `PROJECT_ID/TITLE/DETAIL/SOURCE_CMD/AUTHOR/CMD_ID/STRATEGIC` を位置引数で受け取る（`scripts/lesson_write.sh:8-15`）。

2. オプション解釈
- `--force` を全引数走査で検出（`17-21`）。
- `--status <draft|confirmed>` を前引数方式で検出し、値検証（`23-33`）。

3. 入力バリデーション
- 必須引数（project/title/detail）未指定を拒否（`35-40`）。
- 第1引数が `cmd_*` の誤用を拒否（`42-47`）。
- `DETAIL` 10文字未満を拒否（`49-54`）。

4. プロジェクト解決
- `config/projects.yaml` を Python で読んで `PROJECT_PATH` を特定（`56-65`）。
- 未登録プロジェクトはエラー終了（`67-70`）。

5. SSOTファイル準備
- 書込先 `LESSONS_FILE=$PROJECT_PATH/tasks/lessons.md` を決定（`72`）。
- SSOT不存在ならエラー終了（`75-79`）。

6. 排他付き教訓登録（主処理）
- `LESSONS_FILE.lock` に `flock -w 10` でロック取得（`87-94`）。
- Python処理で最大ID探索（`111-124`）→ 新ID採番（`126-127`）。
- 類似タイトル重複チェック（`129-141`、`--force`で回避）。
- Markdownエントリ生成・追記（`143-156`）。
- 新規IDを一時ファイルへ書出し（`160-164`）。

7. 同期処理
- ロックブロック成功後に `sync_lessons.sh <project_id>` を実行（`168-169`）。
- これにより `projects/{project}/lessons.yaml` が再生成される（`scripts/sync_lessons.sh:26-29, 258-287`）。

8. context自動追記
- `config/projects.yaml` から `context_file` を取得（`176-184`）。
- contextファイル存在時、`- Lxxx:` の既存行を `grep -qF` で重複確認（`188-189`）。
- 未登録なら context専用lock（`flock -w 10 201`）で追記（`190-230`）。
- 「教訓/Lesson」を含む最後の `##` セクション直前に挿入、該当なしなら `## 教訓索引（自動追記）` 新設（`208-223`）。

9. オプション後処理
- `--strategic` 時は `pending_decision_write.sh create` を呼び出し（`239-253`）。
- `CMD_ID` 指定時は `queue/gates/<CMD_ID>/lesson.done` を生成（`255-260`）。

10. 競合時リトライ
- 主ロック取得失敗時は最大3回再試行（`264-270`）。

## 2. flock排他制御の仕組み

### 2.1 ロック対象と目的

- 主ロック: `LESSONS_FILE.lock`（`73`）
  - 目的: `lessons.md` への同時追記でID競合・行破損を防止。
- contextロック: `${CONTEXT_FULL_PATH}.lock`（`230`）
  - 目的: context索引への並行追記衝突を防止。
- sync側ロック: `projects/{project}/lessons.yaml.lock`（`scripts/sync_lessons.sh:27-40,317`）
  - 目的: cache YAML再生成の同時実行衝突を防止。

### 2.2 取得/解放タイミング

- 主ロックは `if ( flock ...; python ... ) 200>lock` のサブシェル範囲で保持（`92-167`）。
- 主ロック解放後に `sync_lessons.sh` と context追記が走る（`168`以降）。
- contextロックは context追記のサブシェル範囲のみ保持（`190-230`）。

### 2.3 競合時の挙動

- 主ロック: `-w 10` + 最大3回リトライ（`87-90, 93, 264-270`）。3回失敗で終了。
- contextロック: `-w 10` 失敗時は `WARN` を出して処理継続（`191`）。教訓登録自体は成功扱い。
- syncロック: `-w 10` 失敗で `ERROR` 終了（`sync_lessons.sh:40`）。

## 3. context自動追記の仕組み

1. `config/projects.yaml` の `context_file` を参照し、相対パスを `SCRIPT_DIR` 基準で絶対化（`176-187`）。
2. `- Lxxx:` が既に存在する場合は追記をスキップ（`188-189, 232`）。
3. 追記文字列は `- <LESSON_ID>: <TITLE>（<SOURCE_CMD>）` 形式（`204-206`）。
4. 挿入位置は「最後の教訓系セクション」に基づき算出（`208-223`）。
5. 教訓セクションがない context には自動で `## 教訓索引（自動追記）` を作成して追記（`223`）。

## 4. エッジケース（3件以上）

1. `status=confirmed` の明示書込なし
- `lesson_write.sh` は `draft` 時のみ `- **status**: draft` を出力（`150-151`）。
- 結果、`confirmed` は SSOT上で status欠落しうる（L033の事象）。

2. 類似度重複判定の閾値固定（0.75）
- 意味的重複でも表現差が大きいと通過、逆に短い似た題名で誤検知の可能性（`137-140`）。

3. `--status` 解析が位置引数に弱い
- `prev_arg` 走査は柔軟だが、予期しない引数順/重複時の最終値優先で意図しない設定になる余地（`26-29`）。

4. context追記失敗が非致命
- contextロック失敗や contextファイル欠落時は `WARN` のみ（`191, 235`）。
- SSOT登録成功と context未反映が分離する。

5. context重複検知がIDベースのみ
- `grep "- Lxxx:"` 検知のため、同一内容が別IDで登録された場合は重複追記される（L006と整合）。

6. プロジェクト解決は Python `-c` 文字列埋込
- `PROJECT_ID` は `cmd_*` 拒否のみで、引用符等を含む異常値の安全性を完全保証していない（`57-65`）。

## 5. 改善提案（Before/After）

### 提案1: 引数解析を `getopts`（または明示パーサ）へ統一

Before:
- `--force`/`--status` を独自ループで全引数走査（`17-29`）。

After:
- `getopts` で `-f`/`-s draft|confirmed` を厳密解析。
- 想定外オプションは即エラー。

効果:
- 引数順依存・多重指定時の曖昧性を排除。

### 提案2: statusを常に明示出力

Before:
- `draft` のみ status行出力（`150-151`）。

After:
- `confirmed` でも `- **status**: confirmed` を必ず出力。
  代替案: `sync_lessons.sh` 側で status欠落時に `confirmed` を補完（L033案B）。

効果:
- SSOT→YAML同期で status欠落が発生しない。

### 提案3: Python呼出の安全化（環境変数経由）

Before:
- `python3 -c "... '$PROJECT_ID' ..."` で文字列埋込（`57-65, 176-184`）。

After:
- `export PROJECT_ID` して here-doc Python内で `os.environ["PROJECT_ID"]` を参照。

効果:
- 引数由来文字列の解釈リスク低減、可読性向上。

### 提案4: 重複検知に source_cmd/要約ハッシュを追加

Before:
- 題名類似度のみ（`129-141`）。

After:
- `source_cmd` 一致 + 正規化タイトル + 正規化要約の組合せで重複判定。

効果:
- 同義語・言い換えによる重複登録を抑制。

## 6. 受入基準チェック

- AC1: 全体処理フローを記述済み（§1）
- AC2: flock排他制御を記述済み（§2）
- AC3: context自動追記を記述済み（§3）
- AC4: エッジケース6件を特定（§4）
- AC5: 改善提案4件を提示（§5）
