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

### Step 3: リネーム案を作る

- 名前は内容を表す固有語を優先し、曖昧な `document`, `image`, `scan`, `misc` を避ける。
- 同一テーマの連番は `YYYY-MM-DD_topic_01.ext` のように自然順で並ぶ形式にする。
- 元拡張子を維持する。拡張子変更が必要な場合はリネームではなく変換作業として分ける。
- Driveでは同名衝突を事前確認する。ローカルでは `test -e "<new_path>"` で衝突を確認する。

### Step 4: 殿に提示して承認を得る

実行前に必ず以下を提示する。

```markdown
対象件数: N
確認完了: N/N
blocked: 0

| original | proposed | reason |
|----------|----------|--------|
```

承認なしに `gws files update` または `mv` を実行してはならない。承認後も、提示した表にないファイルは変更しない。

### Step 5: 承認後に実行する

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

### Step 6: 実行後検証

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
- リネーム案を殿に提示し、承認を得ている。
- 実行後にDrive listまたはローカルfindで結果を確認している。
