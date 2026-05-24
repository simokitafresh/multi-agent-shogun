---
name: file-rename
argument-hint: "[drive-folder|local-path]"
description: |
  PDF、画像、Google Docsなどの内容を全件確認してから、Drive上またはローカル上のファイルを安全にリネームするスキル。
  TRIGGER: /file-rename、ファイル名整理、Driveリネーム、PDF/画像/ドキュメントの内容確認後リネーム、実体を見て名前を付ける作業
  DO NOT TRIGGER: 内容確認不要の単純mv、コードファイルの一括rename/refactor、Drive移動のみ、ファイル削除、ファイル内容の編集、OCR精度改善単独
user-invocable: true
---

# File Rename

PDF、画像、Google Docs、ローカル文書を「中身を見てから」命名する。名前だけ、サムネイルだけ、作成日時だけで判断してはならない。

## What

- Drive上のファイル: `gws files list` で対象を列挙し、承認後に `gws files update` でファイル名を更新する。
- ローカルファイル: `ls` / `find` で対象を列挙し、承認後に `mv` でファイル名を更新する。
- 内容確認台帳を作り、全件について「確認方法」「読めた内容」「提案名」「根拠」を残す。

## When

- PDF、画像、Google Docs、スキャン資料、資料写真など、ファイル名だけでは中身が分からないものを整理するとき。
- Driveフォルダまたはローカルディレクトリ内の複数ファイルを、人間が後で探せる名前へ揃えるとき。
- 誤リネームが業務上の混乱につながるため、実行前承認が必要なとき。

## Not When

- 内容確認なしで機械的に拡張子やprefixだけを変える場合。
- ソースコードのモジュール名、import、参照を含むリファクタリングrename。
- ファイルの削除、移動、共有権限変更、本文編集だけが目的の場合。
- 依頼者が明示的に「承認不要で実行」と指示しても、内容確認が必要な資料リネームではこのスキルの承認ステップを省略しない。

## Procedure

### Step 1: 対象を列挙する

Driveの場合:

```bash
gws files list --query "'<folder_id>' in parents and trashed=false" --fields "files(id,name,mimeType,webViewLink)"
```

ローカルの場合:

```bash
find "<target_dir>" -maxdepth 1 -type f | sort
```

対象外ファイル、既に適切な名前のファイル、サブディレクトリを分ける。対象件数を最初に数え、以降の台帳件数と一致させる。

### Step 2: 全件の内容を確認する

全件必須。読めないファイルを推測で命名してはならない。

| 種別 | 確認方法 |
|------|----------|
| PDF | PyMuPDFで各ページまたは代表ページを画像化し、Read toolで内容を読む。テキストPDFならテキスト抽出も併用してよいが、画像確認を省略しない。 |
| 画像 | Read toolで直接確認する。小さい文字がある場合は拡大またはOCRを併用する。 |
| Google Docs | `gws` でPDFへexportし、PDFとして画像化してRead toolで確認する。 |
| Google Sheets/Slides | PDFまたは適切な形式へexportし、表示内容を確認する。 |
| その他ローカル文書 | 直接読める形式なら内容を読む。読めない場合は変換方法を探し、確認不能なら停止して報告する。 |

PDF画像化の例:

```bash
python3 - <<'PY'
import fitz
from pathlib import Path

pdf = Path("input.pdf")
out = Path("preview_pages")
out.mkdir(exist_ok=True)
doc = fitz.open(pdf)
for i, page in enumerate(doc, start=1):
    pix = page.get_pixmap(matrix=fitz.Matrix(2, 2))
    pix.save(out / f"{pdf.stem}_page_{i:03d}.png")
PY
```

Google Docs exportの例:

```bash
gws files export "<file_id>" --mime-type "application/pdf" --output "<safe_tmp_name>.pdf"
```

内容確認台帳の形式:

```markdown
| original | source | content_checked | observed_content | proposed_name | reason | status |
|----------|--------|-----------------|------------------|---------------|--------|--------|
```

`content_checked` は `yes` / `blocked` の二値にする。`blocked` が1件でもあればリネーム実行へ進まない。

### Step 3: 過去の命名パターンを検索する

リネーム案を作る前に、同じジャンルと同じ場所の過去パターンを `data/multi_agent_shogun_memory.db` から検索する。保存先はJSONLではなくSQLiteの `rename_patterns` テーブル。

`rename_patterns` テーブル:

```sql
id INTEGER PRIMARY KEY,
genre TEXT NOT NULL,
subtype TEXT,
template TEXT NOT NULL,
example_original TEXT NOT NULL,
example_renamed TEXT NOT NULL,
source_location TEXT NOT NULL,
file_created_at TEXT,
file_added_at TEXT,
renamed_at TEXT NOT NULL,
created_at TEXT NOT NULL
```

FTS5検索テーブルを併用し、`genre` と `source_location` を優先して絞る。`source_location` はDriveならDrive folder URL、ローカルならディレクトリパスにする。同じ場所のファイルは同じ命名パターンになる傾向があるため、場所一致を強く扱う。

日付はISO 8601形式へ統一する。`file_created_at` はファイル自体の作成日時、`file_added_at` は対象フォルダ/ディレクトリに追加された日時、`renamed_at` は実際にリネームした日時を保存する。取得できない日時は推測で埋めずNULLにする。

検索例:

```bash
sqlite3 data/multi_agent_shogun_memory.db <<'SQL'
SELECT genre, subtype, template, example_original, example_renamed, source_location,
       file_created_at, file_added_at, renamed_at
FROM rename_patterns
WHERE genre = :genre
  AND source_location = :source_location
ORDER BY created_at DESC
LIMIT 10;
SQL
```

FTS5検索例:

```bash
sqlite3 data/multi_agent_shogun_memory.db <<'SQL'
SELECT rp.genre, rp.subtype, rp.template, rp.example_original, rp.example_renamed,
       rp.source_location, rp.file_created_at, rp.file_added_at, rp.renamed_at
FROM rename_patterns_fts fts
JOIN rename_patterns rp ON rp.id = fts.rowid
WHERE rename_patterns_fts MATCH :query
ORDER BY rp.created_at DESC
LIMIT 10;
SQL
```

該当パターンがあれば、内容確認台帳の `reason` に参照した `template` と `source_location` を書く。該当がなければ「過去パターンなし」と明記し、推測で既存パターンを捏造しない。

### Step 4: リネーム案を作る

- 名前は内容を表す固有語を優先し、曖昧な `document`, `image`, `scan`, `misc` を避ける。
- 同一テーマの連番は `YYYY-MM-DD_topic_01.ext` のように自然順で並ぶ形式にする。
- 元拡張子を維持する。拡張子変更が必要な場合はリネームではなく変換作業として分ける。
- Driveでは同名衝突を事前確認する。ローカルでは `test -e "<new_path>"` で衝突を確認する。

INSERT前に以下を正規化する。

- `genre` は小文字ひらがなへ統一する。英字・カタカナ・漢字の揺れを同じ概念として混在させない。
- `subtype` は同一 `genre` 内で一意な表記に揃える。既存レコードに同義の `subtype` があれば新表記を作らない。
- `file_created_at` / `file_added_at` / `renamed_at` / `created_at` はISO 8601形式に統一する。
- `source_location` は末尾スラッシュなしに統一する。Drive folder URLもローカルディレクトリパスも同じ規則で保存する。

ファイル日付は対象種別に応じて自動取得する。

| 種別 | `file_created_at` / `file_added_at` の取得方法 |
|------|-----------------------------------------------|
| Drive上のファイル | `gws files get` または `gws files list --fields` で `createdTime` / `modifiedTime` を取得する。Drive APIでフォルダ追加日時を直接取れない場合は `file_added_at` をNULLにし、`modifiedTime` を追加日時として代用しない。 |
| 写真・画像 | EXIF `DateTimeOriginal` を優先する。EXIFがなければファイルシステム時刻だけで撮影日時を推測しない。 |
| CamScanner | ファイル名に埋め込まれた日時をパースする。パース不能ならNULLにする。 |
| PDF | PDFメタデータの `CreationDate` を取得し、ISO 8601へ変換する。取得不能ならNULLにする。 |

### Step 5: 殿に提示して承認を得る

実行前に必ず以下を提示する。

```markdown
対象件数: N
確認完了: N/N
blocked: 0

| original | proposed | reason |
|----------|----------|--------|
```

承認なしに `gws files update` または `mv` を実行してはならない。承認後も、提示した表にないファイルは変更しない。

### Step 6: 承認後に実行する

Driveの場合:

```bash
gws files update "<file_id>" --name "<approved_name>"
```

ローカルの場合:

```bash
mv -- "<old_path>" "<new_path>"
```

ローカル実行前チェック:

```bash
test -e "<old_path>"
test ! -e "<new_path>"
```

大量件数では1件ずつ成功/失敗を記録する。途中失敗した場合は停止し、成功済み・未実行・失敗を分けて報告する。

### Step 7: リネーム学習ログを記録する

リネーム実行後、承認済みの命名パターンを `rename_patterns` に記録する。実行していない案や却下された案は記録しない。

記録例:

```bash
sqlite3 data/multi_agent_shogun_memory.db <<'SQL'
INSERT INTO rename_patterns (
  genre, subtype, template, example_original, example_renamed, source_location,
  file_created_at, file_added_at, renamed_at, created_at
) VALUES (
  :genre,
  :subtype,
  :template,
  :example_original,
  :example_renamed,
  :source_location,
  :file_created_at,
  :file_added_at,
  :renamed_at,
  :created_at
);
SQL
```

`template` には再利用可能な形を保存する。例: `YYYY-MM-DD_invoice_{vendor}_{amount}.pdf`。個別ファイル名そのものだけを保存せず、次回検索で使える抽象度にする。
INSERT直前に `genre`、`subtype`、日付4列、`source_location` の正規化結果を確認し、正規化できない値は推測補完せずNULLまたは停止で扱う。

### Step 8: 実行後検証

Driveの場合:

```bash
gws files list --query "'<folder_id>' in parents and trashed=false" --fields "files(id,name)"
```

ローカルの場合:

```bash
find "<target_dir>" -maxdepth 1 -type f | sort
```

検証結果で、承認済みの旧名が残っていないこと、新名が存在すること、件数が変わっていないことを確認する。

## Failure Handling

- 内容確認不能: 停止し、対象ファイル、試した方法、次に必要な変換/OCR手段を報告する。
- 同名衝突: 停止し、衝突先を提示して別名承認を得る。
- Drive API失敗: 失敗ファイルID、エラー、成功済み件数を報告する。再実行時は成功済みをスキップする。
- ローカル `mv` 失敗: 失敗パスと現在の `ls` 結果を確認し、推測で再実行しない。

## Verification Checklist

- 対象ファイル数と内容確認台帳の行数が一致している。
- `content_checked=yes` が全件で、`blocked=0`。
- PDFはPyMuPDF画像化後にRead toolで確認している。
- 画像はRead toolで確認している。
- Google DocsはPDF export後に確認している。
- Step 3前に `rename_patterns` を `genre` + `source_location` で検索している。
- リネーム案を殿に提示し、承認を得ている。
- `file_created_at` / `file_added_at` / `renamed_at` をISO 8601形式で取得・記録している。
- INSERT前に `genre`、`subtype`、日付、`source_location` を正規化している。
- リネーム実行後に `rename_patterns` へ実例とテンプレートを記録している。
- 実行後にDrive listまたはローカルfindで結果を確認している。
