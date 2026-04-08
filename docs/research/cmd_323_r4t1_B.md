# cmd_323 R4-Task1(B): lesson_write.sh 仕様調査

> 調査者: kagemaru (影丸) | 出典: cmd_323 | 日付: 2026-02-25

---

## §1 全体処理フロー

### 1.1 引数解析（L1-54）

```
lesson_write.sh <project_id> "<title>" "<detail>" "<source_cmd>" "<author>" [cmd_id] [--strategic]
```

| 位置引数 | 変数名 | 必須 | デフォルト |
|---------|--------|------|-----------|
| $1 | PROJECT_ID | YES | - |
| $2 | TITLE | YES | - |
| $3 | DETAIL | YES | - |
| $4 | SOURCE_CMD | no | "" |
| $5 | AUTHOR | no | "karo" |
| $6 | CMD_ID | no | "" |
| $7 | STRATEGIC | no | "" |

スキャンフラグ（位置非依存、`$@`全走査）:
- `--force`: 重複チェックバイパス（FORCE=1）
- `--status draft|confirmed`: ステータス指定（デフォルト: confirmed）

バリデーション:
1. PROJECT_ID/TITLE/DETAIL 空チェック → exit 1
2. PROJECT_ID が `cmd_*` パターンなら拒否（引数順序間違い防止）
3. DETAIL 10文字未満なら拒否（品質ゲート cmd_158由来）

### 1.2 プロジェクトパス解決（L56-70）

`config/projects.yaml` をPython3+PyYAMLで読み、`PROJECT_ID`に一致するエントリの`path`を取得。
→ `LESSONS_FILE="$PROJECT_PATH/tasks/lessons.md"` をSSOT（単一真実源）として決定。

### 1.3 flock排他書き込み（L87-167）

**3回リトライループ** with `flock -w 10 200`:
- fd 200 を `${LESSONS_FILE}.lock` に対して取得
- タイムアウト10秒、失敗時1秒sleep後リトライ
- 最大3回失敗で exit 1

flock内でPython3スクリプトが実行される:

1. **最大ID検索**: `## N.` と `### LNNN:` の2パターンからmax IDを特定
2. **重複タイトルチェック**: `SequenceMatcher`で既存教訓タイトルと比較、類似度>75%なら拒否（`--force`で回避可能）
3. **エントリ生成**: `### LNNN: title` + メタデータ行 + detail行
4. **ファイル末尾追記**: `open(lessons_file, 'a')` でappend
5. **ID書き出し**: 一時ファイル`LESSON_ID_FILE`に新IDを書き出し（flock外で使用）

### 1.4 sync_lessons.sh呼び出し（L169）

flock成功後、`sync_lessons.sh`を呼んでSSOT(lessons.md)→キャッシュ(lessons.yaml)同期。
sync_lessons.sh自体も独自flock(`${CACHE_FILE}.lock`)で排他制御。

### 1.5 context自動追記（L170-237）

`config/projects.yaml`の`context_file`フィールドからcontext/*.mdのパスを取得し:

1. **dedup**: `grep -qF`で同一LESSON_IDが既にcontextにあればスキップ
2. **flock**: fd 201 で `${CONTEXT_FULL_PATH}.lock` を取得（10秒タイムアウト）
3. **Python3挿入ロジック**:
   - context内の`## ...教訓...`または`## ...Lesson...`セクションを検索
   - 最後の教訓セクション末尾に1行追記: `- LNNN: title（cmd_xxx）`
   - セクション未発見時は`## 教訓索引（自動追記）`を新設

### 1.6 --strategic処理（L239-254）

`--strategic`フラグ指定時、`pending_decision_write.sh`を呼んでMCP昇格候補として登録。
将軍確認待ちのpending decisionエントリを生成。

### 1.7 完了フラグ（L255-261）

`CMD_ID`が指定されている場合、`queue/gates/${CMD_ID}/lesson.done`を作成。
`cmd_complete_gate`が教訓書き込み完了を検知するためのフラグ。

---

## §2 flock排他制御の仕組み

### 2.1 ロックファイル

| ロック対象 | ファイル | fd |
|-----------|---------|-----|
| lessons.md書き込み | `${LESSONS_FILE}.lock` | 200 |
| lessons.yamlキャッシュ (sync_lessons.sh) | `${CACHE_FILE}.lock` | 200 |
| context/*.md追記 | `${CONTEXT_FULL_PATH}.lock` | 201 |

### 2.2 取得/解放タイミング

```
flock -w 10 200  ← 10秒待ち排他ロック取得
  Python3: lessons.md read → duplicate check → append
flock解放（サブシェル終了時に自動解放）
  ↓
sync_lessons.sh（独自flock）
  ↓
context追記（独自flock fd 201）
```

**重要**: lessons.mdへの書き込みとsync/context追記は**直列実行だが別ロック**。
lessons.md flock解放後にsync_lessons.shが走るため、理論上その間に別プロセスがlessons.mdを変更すると、syncが中途半端な状態を読む可能性がある（後述エッジケース§4参照）。

### 2.3 競合時の挙動

- `flock -w 10`: 10秒以内にロック取得できなければ失敗（exit 1がサブシェルから返る）
- リトライ: 最大3回（attempt 0,1,2）、各リトライ間1秒sleep
- 3回全失敗: exit 1 + エラーメッセージ
- sync_lessons.shのflock: 単一リトライ（失敗=即exit 1）
- context追記のflock: タイムアウト時はWARNのみでexit 0（非致命的）

---

## §3 context自動追記の仕組み（cmd_300由来）

### 3.1 対象contextファイルの決定

```
config/projects.yaml → projects[].context_file → context/{project}.md
```

例: project_id=dm-signal → `context/dm-signal.md`

### 3.2 挿入位置ロジック

Python正規表現: `r'^(##\s+.*(?:教訓|[Ll]esson).*)'`

1. contextファイル内の`## ...教訓...`/`## ...Lesson...`セクションを全検索
2. **最後の**マッチのセクション末尾（次の`## `見出しの直前）に挿入
3. セクション未発見時: ファイル末尾に`## 教訓索引（自動追記）`新設

### 3.3 追記フォーマット

```
- LNNN: タイトル（cmd_xxx）
```

全角括弧`（）`使用。source_cmdがあれば付加。

### 3.4 dedup保護

`grep -qF -- "- ${NEW_LESSON_ID}:"` で既存チェック。完全一致（Fixed string）検索。

---

## §4 エッジケースの特定

### EC-1: lessons.md flock解放→sync間のレースコンディション

**状況**: lesson_write.shのflockはlessons.md書き込み後に解放され、その後sync_lessons.shが呼ばれる。
2つのlesson_write.shプロセスが近接タイミングで実行された場合:

```
プロセスA: flock取得 → 書込(L054) → flock解放 → sync開始
プロセスB:                                  flock取得 → 書込(L055) → flock解放 → sync開始
                                                                                    ↑ A's syncがL054まで読んで
                                                                                      B's書込を見逃す可能性
```

**影響**: lessons.yamlキャッシュが一時的に最新状態を反映しない（次回syncで自動修復）。
**深刻度**: LOW（キャッシュは次回lesson_write時に再syncされる）。

### EC-2: context_fileフィールド未設定時

`config/projects.yaml`の`context_file`が空/未定義の場合:
- CONTEXT_FILE変数が空文字列になり`-n`チェックで安全にスキップされる
- **影響なし**（正常動作）

### EC-3: 「教訓」セクションの正規表現が曖昧マッチする可能性

`r'^(##\s+.*(?:教訓|[Ll]esson).*)'` は以下にもマッチする:
- `## DM-signal教訓リスト` (意図通り)
- `## Lessons Learned from API` (意図通り)
- `## パフォーマンス教訓整理` (意図通り)
- `## 前回のLesson概要` (おそらく意図通りだが要確認)

**最後のマッチのセクション末尾**に追記するため、教訓セクションが複数ある場合は最後のものが対象。
意図しないセクションにマッチしても、最後の教訓セクションが正しいものであれば問題ない。

### EC-4: SequenceMatcherの重複検出が不完全

類似度閾値75%は以下を見逃す:
- 同一概念だがまったく異なる表現（例: "DB直接接続" vs "PostgreSQL直結"）
- 短いタイトル同士の比較（"WSL2注意" vs "WSL注意" = 高類似度だが別内容の可能性）
- **L006教訓との関連**: まさにこの問題を指摘している

### EC-5: Python3 YAML解析でのシェル変数インジェクション

L57-65のプロジェクトパス取得:
```python
python3 -c "
with open('$SCRIPT_DIR/config/projects.yaml', encoding='utf-8') as f:
    ...
if p['id'] == '$PROJECT_ID':
```

`$SCRIPT_DIR`と`$PROJECT_ID`がシェル展開でPythonコード内に直接埋め込まれる。
PROJECT_IDにシングルクォートやPythonコードが含まれると、インジェクションが成立する。
**ただし**: PROJECT_IDバリデーション（L42-47の`cmd_*`チェック）は存在するが、一般的な危険文字チェックはない。
`inbox_write.sh`のL043/L047教訓と同系統の問題。

### EC-6: LESSONS_FILE不存在時の不完全エラーハンドリング

L76-79で`[ ! -f "$LESSONS_FILE" ]`チェックがあるが、flock取得中にファイルが削除された場合:
- Pythonのopen()がFileNotFoundErrorで失敗
- サブシェルがexit 1を返す
- リトライループで3回再試行されるが、同じエラーが繰り返される

### EC-7: confirmed時のstatus出力欠落（L033教訓）

L150-152:
```python
if status == "draft":
    entry += f'- **status**: draft\n'
```

`status == "confirmed"`のときは**status行が出力されない**。
sync_lessons.shはSSOT内にstatus行がなければYAMLにもstatus生成しない（L033教訓の原因）。

---

## §5 改善提案

### 改善1: lessons.md書き込みとsync_lessons.shをflock内で一括実行

**Before** (現在):
```bash
if (
    flock -w 10 200 || exit 1
    # Python: lessons.md append
) 200>"$LOCKFILE"; then
    # sync_lessons.sh ← flock外
```

**After** (提案):
```bash
if (
    flock -w 10 200 || exit 1
    # Python: lessons.md append
    # sync_lessons.sh をflock内で呼ぶ（ただしsyncは独自flockを持つためネストに注意）
) 200>"$LOCKFILE"; then
```

**理由**: EC-1のレースコンディション解消。ただしsync_lessons.shが独自flockを使うため、デッドロック回避のために同一fdを使わない設計が必要。現状でも実害は低いため、優先度LOW。

### 改善2: PROJECT_IDのサニタイズ強化

**Before** (現在):
```bash
if [[ "$PROJECT_ID" == cmd_* ]]; then
    echo "ERROR: ..."
```

**After** (提案):
```bash
# cmd_*チェックに加え、安全文字のみ許可
if [[ ! "$PROJECT_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "ERROR: PROJECT_IDは英数字・ハイフン・アンダースコアのみ: $PROJECT_ID" >&2
    exit 1
fi
```

**理由**: EC-5のインジェクション防止。L043/L047教訓と同系統の問題を根本解決。

### 改善3: confirmed statusも明示的に出力

**Before** (L150-152):
```python
if status == "draft":
    entry += f'- **status**: draft\n'
```

**After**:
```python
entry += f'- **status**: {status}\n'
```

**理由**: L033教訓の根本原因解消。confirmed時もstatus行を出力することで、sync_lessons.shがstatus情報を正確に同期できる。

### 改善4: source_cmd重複チェックの追加

**Before**: タイトル類似度チェックのみ。
**After**: `--force`未指定時、同一source_cmdからの登録がある場合にWARNING表示。

```python
if not force and source_cmd:
    for eid, etitle in existing:
        # 既存エントリからsource_cmdも抽出して比較
        ...
```

**理由**: L006教訓が指摘する「異なるcmdからの同一内容」は防げるが、「同一cmdからの二重登録」は現状防げない。source_cmdベースの二重チェックが有効。

---

## §6 ファイル間依存関係

```
lesson_write.sh
  ├── reads: config/projects.yaml (プロジェクトパス解決)
  ├── reads+writes: {project_path}/tasks/lessons.md (SSOT)
  ├── calls: scripts/sync_lessons.sh (キャッシュ同期)
  │     └── reads: {project_path}/tasks/lessons.md
  │     └── writes: projects/{id}/lessons.yaml
  ├── reads+writes: context/{project}.md (教訓索引追記)
  ├── calls: scripts/pending_decision_write.sh (--strategic時)
  └── writes: queue/gates/{cmd_id}/lesson.done (CMD_ID指定時)
```

---

## §7 注入教訓との対照

| 教訓ID | 調査での確認結果 |
|--------|-----------------|
| L006 | §4 EC-4で確認。SequenceMatcherの75%閾値による不完全な重複検出。改善4で対応提案 |
| L034 | 本スクリプトでは`python3 + re`パーサーを使用しており、awk/sedの固定インデント依存は該当しない。ただしsync_lessons.shの正規表現パーサーは同様のリスクあり |
| L033 | §4 EC-7で確認。confirmed時のstatus行欠落が根本原因。改善3で対応提案 |
| L021 | 本スクリプトではdeclare -Aは使用していない。該当なし |
| L010 | 本スクリプトではgrepによるstatus行マッチは使用していない。ただしgrep -qFでのdedup（L189）は先頭マッチではなく部分一致（安全側） |
