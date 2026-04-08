# cmd_323 R4-Task1: lesson_write.sh 仕様調査レポート
- **調査者**: tobisaru (Sonnet 4.6 / blind_id: C)
- **対象ファイル**: `scripts/lesson_write.sh`, `scripts/sync_lessons.sh`
- **lib/依存**: `scripts/lib/` 配下のファイルは lesson_write.sh から source されていない（完全自己完結スクリプト）
- **日付**: 2026-02-25

---

## §1 全体処理フロー (AC1)

```
[引数解析] → [フラグスキャン] → [バリデーション] → [プロジェクト解決]
    → [flock取得(3リトライ)] → [ID採番+重複チェック+SSOT追記]
    → [sync_lessons.sh呼出] → [context自動追記] → [--strategic処理]
    → [lesson.done書込]
```

### 1-1. 引数解析 (L1-L16)

| 位置引数 | 変数 | デフォルト |
|----------|------|-----------|
| `$1` | `PROJECT_ID` | — (必須) |
| `$2` | `TITLE` | — (必須) |
| `$3` | `DETAIL` | — (必須) |
| `$4` | `SOURCE_CMD` | — (任意) |
| `$5` | `AUTHOR` | `karo` |
| `$6` | `CMD_ID` | `""` |
| `$7` | `STRATEGIC` | `""` |

フラグ (位置に関係なく全引数スキャン):
- `--force`: 重複チェックをバイパス
- `--status draft|confirmed`: status指定 (デフォルト: `confirmed`)

### 1-2. バリデーション (L36-L54)

1. `PROJECT_ID`, `TITLE`, `DETAIL` が空でないこと
2. `PROJECT_ID` が `cmd_` で始まっていないこと (引数順序誤りの検出)
3. `DETAIL` の文字数が10以上であること (summary品質ゲート)
4. `--status` が `draft` または `confirmed` であること

### 1-3. プロジェクト解決 (L57-L79)

- `config/projects.yaml` を Python で読み込み `project_id` に一致する `path` を取得
- SSOT: `{project_path}/tasks/lessons.md`
- ロックファイル: `{lessons_file}.lock`
- 一時ファイル: `mktemp` で生成 → `trap EXIT` で自動削除

### 1-4. flock + Python 処理 (L91-L165)

flock内でPythonが以下を実行:
1. `lessons.md` 全文読み込み
2. max ID採番: `## N.` パターンと `### L{N}:` パターンの両方で最大値を取得
3. 重複チェック: SequenceMatcher ratio > 0.75 の既存エントリがあればエラー終了
4. エントリ構築:
   ```
   \n### L{new_id}: {title}\n
   - **日付**: {timestamp}\n
   - **出典**: {source_cmd}\n  (source_cmdが非空の場合のみ)
   - **記録者**: {author}\n
   - **status**: draft\n       (--status=draft の場合のみ)
   - {detail}\n
   ```
   **※ confirmed の場合は status 行なし** (L033の指摘する設計)
5. `lessons.md` に追記 (open append)
6. 一時ファイルに `new_id_str` を書き込み

### 1-5. flock後の処理 (L168-L261)

```
flock成功後:
  ├─ sync_lessons.sh {PROJECT_ID}  → lessons.yaml を再生成
  ├─ Context自動追記 (cmd_300実装) → context/*.md の教訓セクションに1行追記
  ├─ --strategic の場合 → pending_decision_write.sh で MCP昇格候補を登録
  └─ CMD_ID が非空の場合 → queue/gates/{cmd_id}/lesson.done を作成
```

---

## §2 flock排他制御の仕組み (AC2)

### ロックの取得と解放

```bash
# ロックファイルのfd番号: 200
flock -w 10 200 || exit 1
# ... Python処理 ...
) 200>"$LOCKFILE"   # ← サブシェル終了時に自動でfd200がclose → ロック解放
```

| 項目 | 内容 |
|------|------|
| ロックファイル | `{LESSONS_FILE}.lock` (= `lessons.md.lock`) |
| fd番号 | 200 |
| 待機タイムアウト | 10秒 (`-w 10`) |
| ロック方式 | 排他ロック (flock デフォルト) |
| 解放タイミング | サブシェル `(...)` の終了時にfd200がclose → OS が自動解放 |

### 競合時の挙動 (L91-L272)

```
attempt=0, max_attempts=3

while attempt < 3:
    flock -w 10 ... → タイムアウトすると exit 1
    if (サブシェル成功):
        break (exit 0)
    else:
        attempt++
        if attempt < 3:
            sleep 1 → リトライ
        else:
            エラーメッセージ → exit 1
```

- 最大3回リトライ、各リトライ間に1秒待機
- Python内でのエラー (`sys.exit(1)`) は `set -e` によりサブシェル全体を失敗させる → リトライをトリガー
- **ロックファイルは削除されない** (OSレベルでflockが解放されるため機能上は問題ない)

### Context追記の別ロック (L190-L230)

Context追記には **別途fd 201** を使用:
```bash
flock -w 10 201 || { echo "WARN: context lock timeout" >&2; exit 0; }
) 201>"${CONTEXT_FULL_PATH}.lock"
```
- ロックタイムアウト時は `exit 0` (警告のみ、エラー扱いしない)
- これにより lessons.lock の内側でネストしたロックを取得する設計

---

## §3 context自動追記の仕組み (AC3)

### 追記対象の決定

```python
# config/projects.yaml から context_file フィールドを取得
CONTEXT_FILE = projects.yaml → p['context_file']
# 例: "context/infra.md" → $SCRIPT_DIR/context/infra.md
```

### 重複チェック

```bash
if ! grep -qF -- "- ${NEW_LESSON_ID}:" "$CONTEXT_FULL_PATH"; then
    # 追記処理
fi
```
- 同一 LESSON_ID が既にあればスキップ (L006教訓を反映した設計)

### 挿入位置の決定 (Python CTXEOF ブロック)

```python
# section_pattern: "## ...教訓..." または "## ...Lesson..." にマッチ
matches = list(section_pattern.finditer(content))

if matches:
    last_match = matches[-1]   # 最後の教訓セクション見出しを使用
    after_section = content[last_match.end():]
    next_heading = re.search(r'^## ', after_section, re.MULTILINE)
    if next_heading:
        # 次の##見出しの直前に挿入
        insert_pos = last_match.end() + next_heading.start()
        new_content = content[:insert_pos].rstrip('\n') + '\n' + entry + '\n\n' + content[insert_pos:]
    else:
        # ファイル末尾に追記
        new_content = content.rstrip('\n') + '\n' + entry + '\n'
else:
    # 教訓セクションがない場合: 新規セクションを作成してEOFに追記
    new_content = content.rstrip('\n') + '\n\n## 教訓索引（自動追記）\n\n' + entry + '\n'
```

### エントリ形式

```
- L{ID}: {title}（{source_cmd}）
```
- source_cmd が空の場合は `（source_cmd）` の部分は省略
- 括弧は全角: `\uFF08` / `\uFF09`

---

## §4 エッジケース (AC4)

### EC-1: confirmed status がSSOTに記録されない (L033)

**影響**: `--status confirmed`（デフォルト）時、SSOT の `lessons.md` に `**status**: confirmed` 行が書かれない。`sync_lessons.sh` はこの行がなければ YAML に `status` フィールドを出力しない。
**結果**: `lessons.yaml` の confirmed エントリに `status:` フィールドが存在しない（L033が指摘する27件欠落問題の根本原因）。

### EC-2: 重複検出がタイトル文字列のみ依存 (L006)

**影響**: 同一 `source_cmd` から複数回呼び出されても、タイトルが異なれば重複とみなされず複数エントリが登録される。また SequenceMatcher は意味的類似性でなく文字列編集距離を測るため、同義だが表記が異なるタイトルは通過する。
**例**: 「WSL2 CRLF問題」と「Write tool CRLF混入」は ratio < 0.75 → 両方登録される

### EC-3: Python処理の途中失敗でSSOTが中途半端に書き込まれるリスク

`set -e` により Python の `sys.exit(1)` はサブシェル全体を失敗させるが、Python `open(lessons_file, 'a')` での書き込み途中でクラッシュした場合（OOM等）、部分書き込みが発生する可能性がある。flock は保持したままOSがプロセスをKillするとflockは解放されるが、SSOTは破損した状態が残る。
**現状**: atomic writeでなくappendのため、partial writeは理論的に発生しうる。

### EC-4: ロックファイルの永続蓄積

`lessons.md.lock` と `context_file.lock` は一度作成されると削除されない。大量の教訓登録後も影響はないが（OSはflockを管理するのでファイル内容は不要）、`/tmp` のような場所でない限りディレクトリに残り続ける。

### EC-5: `--strategic` ブロックでのNEW_LESSON_ID二重読み込み (L240-L244)

```bash
if [ "$STRATEGIC" == "--strategic" ]; then
    NEW_LESSON_ID=""        # ← 変数を空にリセット
    if [ -f "$LESSON_ID_FILE" ]; then
        NEW_LESSON_ID=$(cat "$LESSON_ID_FILE")   # ← 同一tempファイルを再読み
    fi
```
context追記ブロックでも同じ処理を行った後であり、変数リセット→再読みは冗長。tempファイルが削除されている場合（trapが発火後）はIDが取得できず、--strategicが無効になる。ただし、trapはEXITのみで通常フローではスクリプト終了まで削除されない。

### EC-6: `config/projects.yaml` に `context_file` フィールドがない場合

```bash
CONTEXT_FILE=$(python3 -c "...print(p.get('context_file', ''))...")
if [ -n "$CONTEXT_FILE" ]; then ...
```
空文字が返るため、context追記はスキップされる。エラーにならないがサイレントスキップで気づきにくい。

---

## §5 改善提案 (AC5)

### 改善1: confirmed status を明示的にSSOTに書く (L033根本修正)

**問題**: L033に記載の通り、status=confirmed がSSOTに書かれずYAMLに反映されない。

**Before** (L150-151):
```python
if status == "draft":
    entry += f'- **status**: draft\n'
```

**After**:
```python
entry += f'- **status**: {status}\n'
```

**効果**: 全エントリに `status:` フィールドが明示される。`sync_lessons.sh` のパーサーがstatus未検出時に`confirmed`をデフォルト設定する案B（L033推奨）との二択だが、SSOT側での修正の方がデータ品質が高い。

---

### 改善2: source_cmd重複チェックの追加 (L006補完)

**問題**: 同一 `source_cmd` から複数の教訓が登録されると、意図的な複数登録と誤登録の区別がつかない。

**Before**: タイトル類似度チェックのみ

**After**: existing リスト構築時に `source` も保持し、同一source_cmdからの再登録を警告:
```python
# 既存エントリの source を収集
existing = []
for m in re.finditer(r'^### L(\d+): (.+)$', content, re.MULTILINE):
    lesson_id_str = f'L{int(m.group(1)):03d}'
    # source を取得: 見出し直後の **出典**: 行から
    ...
    existing.append((lesson_id_str, title, source))

# source重複チェック (force=Falseの場合のみ)
if not force and source_cmd:
    for eid, etitle, esrc in existing:
        if esrc == source_cmd:
            print(f'WARN: {source_cmd}から既に教訓が登録されています: {eid}: {etitle}', file=sys.stderr)
            print(f'複数登録する場合は --force フラグを追加してください', file=sys.stderr)
            sys.exit(1)
```

---

### 改善3: Python ブロックのatomic write化 (EC-3対策)

**問題**: `open(lessons_file, 'a')` は partial write のリスクがある。

**Before**:
```python
with open(lessons_file, 'a', encoding='utf-8') as f:
    f.write(entry)
```

**After**: `tempfile.mkstemp` + `os.replace` でatomic write:
```python
import tempfile, shutil
with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', suffix='.tmp',
                                  dir=os.path.dirname(lessons_file), delete=False) as tmp:
    tmp.write(content + entry)
    tmp_path = tmp.name
os.replace(tmp_path, lessons_file)
```
（ただし、既存データ全体を再書き込みするためファイルサイズが大きい場合は注意。append-only要件と競合するが、flock内では完全に排他されているため安全。）

---

## §6 lib/ ファイルとの関係

`scripts/lib/` には `cli_lookup.sh`, `model_detect.sh`, `safe_rm.sh` が存在するが、`lesson_write.sh` から `source` している箇所は **ゼロ**。完全に自己完結したスクリプト。`sync_lessons.sh` も同様に lib/ を source していない。

---

## §7 AC達成状況

| AC | 達成 | 補足 |
|----|------|------|
| AC1 | ✅ | §1で全体フロー文書化 |
| AC2 | ✅ | §2でflock仕組み解説 (fd番号/タイムアウト/リトライ/自動解放) |
| AC3 | ✅ | §3でcontext追記の対象決定/重複チェック/挿入位置/フォーマット解説 |
| AC4 | ✅ | §4でEC-1〜EC-6の6件特定 (要求3件以上) |
| AC5 | ✅ | §5で改善1〜3の3件、Before/After付きで具体的に記載 (要求2件以上) |
