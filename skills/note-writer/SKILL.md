---

<!-- script_refs_checked_at: 2026-08-18T13:55:00+0900 (note_figure_render.sh / note_image_insert.py 追加・Step 7を artifact→画像 方式へ更新)
<!-- cmd_karo_hotfix_skill_refs_eight_202607162132検分: note_draft.sh現HEAD+作業差分を確認。CDP未応答は隔離profile自動起動、起動不能/reCAPTCHA未解決はexit 1(FAIL)。末尾skill-auto-improve追記はexit後でI/F不変。`CDP_PORT=9234 bash scripts/note_draft.sh "$OUT_FILE"`を維持。 -->
name: note-writer
argument-hint: "[topic|draft_path]"
description: |
  将軍専用。テーマを受け取りnote.com向けMarkdown記事を生成・保存する。
  バムスタイル（ですます調）でDM-signal機能解説・投資分析手法・アプリ紹介を読者目線で執筆。
  TRIGGER: /note-article、ユーザー向け記事、note記事、機能紹介記事、投資分析記事
  DO NOT TRIGGER: 開発裏話・将軍書簡形式の記事（→[[sengoku-writer]]）、
  週報生成（→weekly-report）、月報生成（→[[monthly-report-writer]]）、X検索調査（→x-research）
quality_metric: "当該スキル起点cmdのcmd_save.shチェック通過率（q1-q3 BLOCKなし、q4_depth WARNINGなしの割合）"
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
  - AskUserQuestion
---

<!-- script_refs_checked_at: 2026-07-30T18:48:52+0900
<!-- 2026-07-16再検分: note_draft.sh 31cfcb906/7127ab894/1421d3c92/5a7543ad9。Chrome未起動時のexit 0(SKIP)を廃止し、隔離profileを自動起動、起動不能時はexit 1(FAIL)。■行は個別bulletとして解釈後、<br>で1行改行する。`CDP_PORT=9234 bash scripts/note_draft.sh "$OUT_FILE"`の引数契約は不変。 -->
<!-- 検分: note_draft.sh 8e4872513 reCAPTCHA guard内部強化。呼び出し契約 `CDP_PORT=9234 bash scripts/note_draft.sh "$OUT_FILE"`、Markdown→note下書き保存契約は不変 -->
<!-- script_refs_checked_at: 2026-07-30T18:48:52+0900

Script refs verified: 2026-06-30 a519e6365+dad84ea2c. `note_draft.sh` 直近変更はinvisible reCAPTCHA対応(dispatch_click+quick_url待ち)とコメント形式修正。`CDP_PORT=9234 bash scripts/note_draft.sh "$OUT_FILE"`、Markdown→note下書き保存、PASS/FAIL/SKIP記録の契約は変更なし。

# /note-article — ユーザー向けnote記事スキル

## 使い方

```
/note-article [テーマ]
```

テーマ例:
- 「弱体化確率の見方」
- 「DM-safeの使い方」
- 「Ave-7のリバランス解説」

## 手順

### Step 1: テーマ確認

テーマが曖昧なら殿に確認する。記事の対象読者と伝えたいポイントを明確にする。

### Step 2: 素材収集

以下のテンプレートを読み込む:
- `marketing-director/templates/writing-style-guide.md` — バムの文体ガイド（トーン・用語集・構成パターン）
- `marketing-director/templates/note-markdown-rule.md` — noteプラットフォームのMarkdown完全仕様

テーマに関連する素材を収集する:
- `marketing-director/content/articles/` から既存記事（トーン合わせ）
- `context/dm-signal*.md` から機能・仕様の背景
- `projects/dm-signal.yaml` からプロジェクト知識

### Step 3: 執筆

以下のルールで執筆する。

## 文体ガイド（要点）

詳細 → `marketing-director/templates/writing-style-guide.md`

- **ですます調**、簡潔な文、読者への自然な語りかけ
- 一文は短く。無駄な修飾語を削る
- 心理的課題から導入する（読者の不安・迷いに触れる）
- 欲望は忍ばせる（「使うべき」と直接言わず、効果を示唆する）
- 断定と推測を使い分ける
- 内部用語は記事に出さない（用語集に従いメンバー向け表記に変換）

## noteプラットフォーム制約（要点）

詳細 → `marketing-director/templates/note-markdown-rule.md`

- 見出しは `##` と `###` のみ（h1はタイトル用、h4以下は無効）
- **表は使用禁止**（noteはMarkdown表をサポートしない → リスト形式で表現）
- 区切り線は `---` のみ（3文字。4文字以上は認識されない）
- 絵文字禁止
- 画像のMarkdown記法は使用不可（エディタUIで挿入）
- KaTeX数式: インライン `$${式}$$`、ディスプレイ `$$`改行`$$`

## 禁止パターン（太字・句読点）

noteはCommonMark仕様に従うため、太字の配置に制約がある。

```markdown
# 変換されない（禁止）
**「鍵括弧内の太字」**
**(括弧内の太字)**
**テキスト。**
**テキスト、**
**【】内**

# 変換される（正しい）
**鍵括弧の外**に書く
「**鍵括弧の中**」
**重要なポイント**。
**ボラティリティドラッグ（VDrag）**
**Why（なぜ）**
```

### 見出し vs 太字（2026-06-25実証）

指標名や用語に（英語名）を付ける場合、`###`見出しでは末尾の`）`で正しく変換されないことがある。`**`太字なら全角括弧を含んでも変換される。指標名は`**太字**`を使え。

## AI文体の排除

以下のパターンを検出したら書き直す:

- 意義の過剰強調（「画期的な」「重要な転換点」）
- 三の法則（毎回3つ並べる癖）
- 否定的並列（「〜だけでなく…でもある」）
- 同義語の循環（「触媒/パートナー/基盤」）
- フィラー（「〜を達成するためには」→「〜するには」）
- ダッシュの多用
- 太字の乱用
- チャットボット残骸（「参考になりましたか？」「いかがでしたか？」）

魂のある文章を書くこと:
- 文の長さを変える。短い文。そして長い文
- 不完全さを許す。脱線や補足は人間的
- 具体的な感情を書く。「懸念される」ではなく具体的に

## 構造テンプレート

```
## [導入 — 読者の課題に触れる見出し]

（問題提起。読者が「あるある」と感じる状況。心理的な不安や迷いに触れる）

---

## [本題 — 解決策・機能の紹介]

（何がどう解決するのか。具体的な仕組みの説明）

---

## [使い方 — 2〜3セクション]

（具体的な操作方法。スクリーンショットがあれば挿入指示を添える）

---

## [まとめ]

（要点の整理。箇条書きで簡潔に）

---

参考になれば幸いです。
```

投資免責は、記事内容が投資に関係する場合のみ付ける。

## 保存先

```
/mnt/c/Python_app/DM-signal/marketing-director/content/articles/
```

ファイル名: `note-{テーマの英語要約}.md`

## 文字数の目安

- コラム: 2,000〜3,500文字
- 解説記事: 3,500〜5,500文字

### Step 3.5: natural-japanese フル検査（AI臭除去・省略厳禁）

元リポジトリ: https://github.com/coji/natural-japanese
設計思想: 「検出は機械、判断は人間(またはAI)」。検出結果は疑いであり、直すか理由をつけて残すかを判断する。

初回セットアップ（セッション内1回）:
```bash
python3 -m venv /tmp/uv-env && /tmp/uv-env/bin/pip install uv -q
cd /tmp && git clone --depth 1 https://github.com/coji/natural-japanese.git
```

共通実行パス:
```bash
NJ="/tmp/natural-japanese/skills/natural-japanese/scripts"
UV="/tmp/uv-env/bin/uv run --no-project"
```

#### Step 3.5a: lint（必須・省略禁止）

```bash
cd /tmp/natural-japanese && $UV $NJ/lint.py "$OUT_FILE" --genre essay --json
```

- `--genre essay`はnote/ブログ記事に必須（コーパス校正済み閾値プロファイルに切替わる）
- `--json`で全指標を取得し、findings以外の数値も必ず確認する

**収束ループ**: lint→修正→再lint→findings 0件まで繰り返す。1回で終わるな。

**核心指標と閾値**:
- `burstiness`: -0.24以上が目標（ソースコード実測閾値）。文長のメリハリ
- `nominal_ending_ratio`: 0.1以上。体言止めゼロはAI典型パターン
- `paragraph_sentence_count_cv`: 0.4以上が望ましい。段落長のばらつき
- `bold_per_1000_chars`: 太字の乱用検出

**リズム改善手法**（burstinessが低い場合）:
- 超短文（5〜10モーラ）を要所に挿入: 「全敗でした。」「割に合わない。」
- 長文（60モーラ超）と混在させてメリハリを作る
- 体言止めを自然に混ぜる: 「〜の一途。」「〜の源泉。」

**主要検出カテゴリ**:
- `forbidden_phrase`: LLM常套句（「根本的な」「大切なのは」「いかがでしょうか」等）
- `antithesis_repetition`: 「〜ではなく」の反復
- `low_burstiness`: 文長リズムの均質性
- `translationese`: 翻訳調（「〜することができる」「〜を持つこと」等）

#### Step 3.5b: terms（必須）

```bash
cd /tmp/natural-japanese && $UV $NJ/terms.py "$OUT_FILE"
```

カタカナ複合語/ASCII略語/固有名詞を初出順に抽出する。判定ではなく素材抽出。
- 「説明手掛かり: なし」の用語を確認し、初出で括弧内説明を追加するか、理由をつけて不要と判断する
- 内部用語（PF, L0-L3等）はメンバー向け表記に変換するか文脈説明を添える
- 製品名・一般語は説明不要と判断してよい

#### Step 3.5c: outline（必須）

```bash
cd /tmp/natural-japanese && $UV $NJ/outline.py "$OUT_FILE"
```

見出し構造とテンプレ見出し検出。確認ポイント:
- boilerplate_heading（「まとめ」等）が多すぎないか
- 見出しの長さ・体言止め率に過度な均質性がないか
- 見出しだけ読んで論旨が通るか（文体憲法§2）

#### Step 3.5d: 収束判定

以下を全て満たすまでStep 3.5a-cを繰り返す:
- lint findings: 0件
- burstiness: -0.24以上
- nominal_ending_ratio: 0.1以上
- terms: 全未説明用語に対処済み（説明追加 or 理由つき不要判断）
- outline: boilerplate見出し・構造問題なし

### Step 4: 殿に提示

下書きを殿に見せ、フィードバックを受ける。「他に入れたい話は？」と聞く。

### Step 5: 保存

承認後、articlesフォルダに保存する。

### Step 6: note.comに下書き保存

CDP経由でnote.comに下書き保存する。実行は共通ヘルパー `scripts/note_draft.sh` に委譲する。

引数はMarkdownファイル1件のみ。`CDP_PORT` 未指定時は9234を使う。

```bash
CDP_PORT=9234 bash scripts/note_draft.sh "$OUT_FILE"
```

内部では `auto-ops/cdp/cdp_helper.py` の `launch_browser` / `get_tab` / `js_eval` / `navigate` / `cdp_send` / `screenshot` / `_is_cdp_alive` を使う。CDP_PORTに応答がなければ `launch_browser`(PowerShell)→`cmd.exe` fallbackで隔離プロファイル付きChromeを自動起動する。起動不能はFAIL(exit 1)。未ログイン時は `.env.note` の `NOTE_EMAIL` / `NOTE_PASSWORD` で自動ログインする。reCAPTCHAが出た場合はチェックボックスをCDP座標クリックし、画像チャレンジでは `/tmp/note_recaptcha_challenge.png` を撮影して最大120秒待機する。未解決ならFAIL(exit 1)として記録する。

Markdown→note.com変換ルール（2026-07-30更新 commit ee255047）:
- `# タイトル` → titleのtextareaに設定（本文に含めない）。`#` が無い場合は最初の `##` をfallback titleに使う
- `## 見出し` → `<h2>` 大見出しとして本文HTMLに入れる
- `### 見出し` → `<h3>` 小見出しとして本文HTMLに入れる
- `https://` で始まる行 → `<a>` リンクとして本文HTMLに入れる（note.comが自動でOGPカード化する場合あり）
- `---` → `<hr>` として本文HTMLに入れる
- 通常テキストと `- リスト項目` → 連続分を1つの `<p>` にまとめ、行間は `<br>` でつなぐ
- 空行とコードフェンス行 → スキップ
- 本文は `.ProseMirror.note-common-styles__textnote-body` → `div.ProseMirror` → `div[contenteditable]` の3段fallbackでエディタを検出し、`innerHTML` で挿入して `input` / `change` eventを発火する
- ProseMirrorエディタがスピナーで停止している場合、`Page.reload` で最大2回リトライする（`wait_for_prosemirror`）
- 下書き保存ボタン押下後、最終URLを `[note_draft] Done: ...` に出力し、`skill_execution_log.yaml` にPASS/FAIL/SKIPを記録する

### Step 6.5: 元ネタartifactの更新（固定工程・省略禁止）

記事の元ネタ(研究成果・実験結果)に対応するartifactが既に存在する場合、**note記事執筆の前にそのartifactを最新内容へ更新せよ**（殿指示2026-08-23: 「artifactも更新して。そのあとでnoteの記事を書こう」。同日「artifactも作成して」=記事系成果はartifactデリバリがデフォルト）。artifactが無い場合は作成する。更新は正本HTMLをEdit→Artifactツールでurl指定再公開（url無指定は新URL発行事故）。記事とartifactの数値・結論が食い違う状態で公開に進むな。

### Step 7: 図表を「artifact→画像」で入れる（noteの表組・カード非対応を回避し記事品質を上げる）

noteはMarkdown表・カード・フロー図を組めない。**比較表・フロー・スケール図はartifactでHTML/SVGとして設計し、PNGにして本文へ挿入する**（殿指示2026-08-18: 「artifactを画像として使うやり方でキャッチーになる」）。実証: FoF決定性記事(図3枚)・5人の投資家記事(図6枚)。

**7-1. 図をartifactで設計する**
- 記事の論点ごとに1枚: 「桁スケール図」「三方式比較表」「段階フロー」「ペルソナ別フロー」「一枚まとめグリッド」など。文章で表しにくい構造を優先
- artifact正本(`docs/dashboard/*.html`)に「note記事用の図」節として置き、そこから**自己完結HTML断片**(ライト固定・外部CSS/フォント/画像なし・幅600〜1000px)を切り出す。CSS変数は実値へ展開するか、`:root`のライト定義だけ残す
- 数値は一次データ(実測値)を入れる。図の見出しに「図N」を付けると本文の参照が安定する

**7-2. PNGへ描画する**
```bash
bash scripts/note_figure_render.sh <fragment.html> <out.png> [width_px=600] [max_height_px=1800]
```
- Windows Chrome headless(隔離profile・D009)・device-scale 2・下余白を背景色基準で自動トリム(`scripts/lib/png_trim_bottom.py`、PIL不要)
- 出力先: `marketing-director/content/images/note-{テーマ}/figN.png`。**Readツールで必ず目視**(ラベル背景の幅不足・切れ・uppercase化(`text-transform`でε→E)を確認)

**7-3. 本文にマーカー文を書く**
- 各図の直後に来る段落の先頭を一意な文にする(例: 「上図はスコア差を対数目盛に並べたものです」「A氏の順番を図にしました」)。**同じ書き出しを繰り返さない**(natural-japanese `repeated_sentence_lead`)
- `■画像:`等のマーカー記法は書かない(note_draft.shが壊す)

**7-4. 下書き保存→画像挿入→キャプション**
```bash
CDP_PORT=9234 bash scripts/note_draft.sh "$OUT_FILE"          # → editor URL
python3 scripts/note_image_insert.py <editor_url> <spec.json> --port 9234
```
`spec.json`: `[{"marker":"上図は…","file":"C:\\Python_app\\DM-signal\\…\\fig1.png","caption":"図の説明(=ALT相当)"}]`
- マーカー文の先頭へcaretを置き「画像」ボタン→`Page.setInterceptFileChooserDialog`でOSダイアログを抑止→`fileChooserOpened.backendNodeId`へ`DOM.setFileInputFiles`(fallback: `input[type=file]`)→figcaptionへ`Input.insertText`でキャプション→下書き保存→**別タブで再読込しimgs数・各figの直後文・captionを検証**(PASS/FAILをJSONで出力)
- **キャプションは必須**(殿2026-08-18: 「画像の下のキャプションはALTと同じ意味」)。図の順番・要点を1文で。**既に記入済みのfigcaptionには書かない**(スクリプトは非空ならskip。殿が手で入れた文を連結事故で汚した2026-08-18の実証)。下書きは自動保存されるため「下書き保存」ボタンが見つからなくても再読込で永続化を確認する

**7-5. 実証済みの罠**
- 「画像」ボタンclickはWindowsのファイル選択ダイアログを開く。抑止しないと**そのタブのrendererが固まりCDPが応答しなくなる**(2026-08-18実証。閉じるには`#32770`クラスのダイアログへWM_CLOSE)。7-4のスクリプトは抑止済み
- Enter+ArrowUpで空行を作る旧方式は、折返し段落内でArrowUpが1行上へ動き**文の途中に画像が入る**。caret直挿しで段落を分割させる方式に変更(旧手順は廃止)
- note_draft.shは節内の連続行を1つの`<p>`(`<br>`区切り)へまとめる。マーカーは段落先頭でなくても良い(text nodeのindexで位置決め)
- `aria-label="メニューを開く"`はトップバーの「…」であり画像挿入の「+」ではない
- ProseMirror外からのDOM操作(移動・結合)は保存されないことがある。位置修正は削除→再挿入で行う
- 画像アップロード後4〜6秒待ってから次へ。連続挿入時は`figures`数の増分で成功判定
- Chromeプロセス残留や旧タブのハングは`/json/close/<id>`で閉じ、必要なら`taskkill /F /IM chrome.exe`後に再起動

**リンク挿入の補足**: note_draft.shが`https://`行を`<a>`へ変換するがProseMirrorが無視する場合がある。欠落分はDOMで`<p><a href>`を挿入し`input`イベントを発火

<!-- script_refs_checked_at: 2026-07-30T18:48:52+0900
