---
name: prose-polish
description: |
  将軍専用。殿が書いた日本語の文章(note 記事・随筆・一人称の物語・詩的な散文)を、殿との対話で 1 手ずつ推敲し note 下書きへ上げる。
  natural-japanese(coji)の lint は「検出器」として先に回すが、判定は詩の原理(反復=韻律、句点連打=打撃音、空白=呼吸、横線=場面転換、見出し=散文の札)で行う。lint の数値を目標にしない。
  TRIGGER: /prose-polish、文章を整えたい、推敲、ブラッシュアップ、natural language で整える、note の下書きを直す、AI 臭は減ったがインパクトが無い、余韻、呼吸、行間、詩でもあるべき
  DO NOT TRIGGER: DM-signal 機能解説記事の新規執筆(→note-writer)、将軍書簡形式(→sengoku-writer)、週報/月報、設計書レビュー、コードのリファクタ
argument-hint: "[note preview URL | draft_path]"
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - WebFetch
---

# /prose-polish — 文章のブラッシュアップ(natural-japanese の先にある推敲)

## 何を可能にするか

natural-japanese の lint は AI 臭を機械的に検出する。しかし lint の閾値へ合わせると、意図的な反復や句点の連打が「均された散文」になり、インパクトと余韻が消える(2026-09-02 実証: v1 で findings 9→0 にした結果、殿『最初より AI 臭は減ったがインパクトが少ない。これは詩でもあるべきだ。中原中也と一緒だ』)。本スキルは **検出は機械、判断は詩の原理** で行い、縦画面(スマホ)の読者の呼吸まで設計する。

正本の事例と v0→v5 の全差分 → `docs/research/prose_polish_case_apartment_interest_20260902.md`。索引 → `context/prose-polish.md`。

## 入力と出力

- 入力: note preview URL(`https://note.com/preview/<id>?prev_access_key=...`)または Markdown path。殿の推敲指示(自然言語)。
- 出力: `docs/notes/<slug>_<date>_v<N>.md` を版ごとに残す(v0=無修正原文)。note の **別下書き** として毎版アップし URL を返す。commit は `ninja_scope_commit.sh`。
- 失敗時: WebFetch で本文が取れない→殿へ「本文を貼ってほしい」と 1 行。CDP が落ちている→`note_draft.sh` は隔離 profile を自動起動、それでも失敗なら exit 1 の内容をそのまま報告。

## 手順(順序厳守。0→1→2 の前に意見を書くな)

### Step 0: 原文の確保と数値検算
1. WebFetch で全文を取り、`docs/notes/<slug>_<date>_v0.md` に **無修正で** 保存。先頭に `<!-- 原文取込 <ts> preview <id> -->`。
2. 文章中の数値(金額・利率・年数・比率)は python で再計算し、整合を先に確認する。数字を直す必要があるか無いかを最初に言えるようにする。
3. タイトルは preview に出ないことがある。**殿に聞く前に仮題を付けず、まず殿が示したタイトルを使う**。示されていなければ仮題であることを明記。

### Step 1: natural-japanese を検出器として回す(省略禁止)
```bash
python3 -m venv /tmp/uv-env && /tmp/uv-env/bin/pip install uv -q   # 初回
cd /tmp && git clone --depth 1 https://github.com/coji/natural-japanese.git  # 初回
NJ=/tmp/natural-japanese/skills/natural-japanese/scripts; UV="/tmp/uv-env/bin/uv run --no-project"
cd /tmp/natural-japanese && $UV $NJ/lint.py <md> --genre essay --json > /tmp/nj_v0.json
$UV $NJ/terms.py <md>; $UV $NJ/outline.py <md>
```
- 読むのは `stats`(burstiness / nominal_ending_ratio / paragraph_sentence_count_cv / bold / emoji / low_specificity)と findings のカテゴリ。
- **findings を潰す作業に入るな**。ここで得るのは「どこが機械的に見えるか」の地図だけ。`repeated_sentence_lead` の検出文自身が『人間の意図的な反復技法との区別がつかないため参考情報』と言っている。
- terms の「説明手掛かり: なし」は、専門語(NOI 等)の初出に一言添える候補。これは直してよい(唯一、無条件で採用する修正)。

### Step 2: 詩の原理で判定する(ここが natural-japanese の先)
lint の findings を 1 件ずつ「AI 臭」か「技法」かに振り分ける。判定基準:

| 検出 | 技法として残す条件 | 直す条件 |
|---|---|---|
| 文頭反復(「でも」「また上がった」) | 主人公が現実を一段ずつ飲み込む階段になっている。回数が増えるほど感情が積む | 同じ接続詞が論理の接着剤としてだけ使われ、削っても意味が変わらない |
| 句点連打の名詞列挙(「給湯器。エアコン。退去。」) | 打撃音・列挙の速度が場面の意味(出費が次々来る)と一致 | 情報の羅列で、読者の視線を止める意図がない |
| burstiness 不足 | 短文主体が声の統一(語り手の息)になっている | 長短の差が無く、どの文も同じ長さで説明している |
| 「俺/僕」「親父/父」の揺れ | 感情が乗る場面は「親父」、事実は「父」のように使い分いている | 無意識の混在 |

**やってはいけない(v1 の失敗)**: burstiness を上げるために長文を足す。縦画面では長文が息苦しさになる。反復を減らす。名詞の連打を一文に溶かす。

### Step 3: 縦画面の呼吸を設計する
スマホでは一段落が画面の半分を占める。感情の転換点が段落の真ん中に埋まらないように **段落を割る**。
- 転換点は独立行にする: 「ある日、気づいた。」「父から相続した現金で、父から相続したアパートを維持している。」「少し変な感じがした。」は 3 行。
- **息を置く場所**=全角スペース 1 文字の行(`　`)。段落と段落の間に見える空白行になる。使いどころ: 一区切りついた直後(「人生を上がれた気がした。」の後)、結びの直前(「『これでお前も安心だ』。」と最終文の間)。
- **時間・場面が跳ぶ場所**=横線(`---`→`<hr>`)。10 年後、金利が上がった各段、売却、決済後。詩では字下げや空白で場面を切り替える。note ではこれが横線に相当する(殿 2026-09-02 18:11)。
- **見出しは付けない**。「売却決定」「エンディング」は物語を外から説明する札で余韻を壊す。金利の刻みの見出しも同じ(殿『詩に一段落毎にタイトルを振るか？振らないだろ』)。見出しが持っていた情報(金利 2.5%→3.5%…)は本文に溶かす: 「また上がった。3.5％。」。
- タイトルと本文冒頭が同文なら本文側を外す。

### Step 4: note の別下書きへ上げる(版ごと)
```bash
{ echo "# <タイトル>"; echo; cat docs/notes/<slug>_v<N>.md; } > <scratch>/note_upload_v<N>.md
NOTE_DRAFT_PARAGRAPHS=1 CDP_PORT=9234 bash scripts/note_draft.sh <scratch>/note_upload_v<N>.md
```
- **`NOTE_DRAFT_PARAGRAPHS=1` 必須**。既定の変換は空行区切りの段落を 1 つの `<p>` に `<br>` 結合するため段落の余白が消える(2026-09-02 実測、fe8245955 で追加)。
- 毎版 **新しい下書き**になる。前版の下書き ID を「削除してよい」と殿へ伝える。元の下書きには触らない。
- `Body: inserted N` が Sections 数と一致することを確認する(不一致=段落結合モードで送っている)。

### Step 5: 殿の 1 指示=1 版で回す
- 殿の指示は自然言語で来る(「余韻をぶち壊す」「呼吸が苦しい」「横線だろうな」)。1 指示につき 1 版を作り、変更点を 1〜3 行で報告し、URL と削除可の旧版 ID を添える。
- 各版は `docs/notes/` に残し commit する。差分は `diff v(N-1) vN` で示せるようにしておく。
- 殿が「とてもよい」と言った版が最終。lint の findings が残っていてよい(意図的反復)。最終版の stats を記録する。

## 二値チェック
- v0 が無修正で保存されている(diff 0)。
- lint / terms / outline の 3 つを v0 に対して実行した証跡(JSON と出力)がある。
- 最終版で `Body: inserted N` == Sections。
- 各版に対応する note 下書き URL が報告にある。
- 数値検算の結果(整合/不整合)を最初の報告に書いた。

## 事例(v0→v5 の要約。全文は docs/research)
| 版 | 殿の言葉 | 処置 | 結果 |
|---|---|---|---|
| v1 | 「natural language を使って整えたい」 | lint findings 9→0(反復 8→4、長文 3 追加) | 「AI 臭は減ったがインパクトが少ない」=失敗 |
| v2 | 「詩でもあるべきだ。中原中也と一緒だ。繰り返しのリズム感を削除しすぎ」「縦画面で行間がなさすぎるのもつらい」 | 反復・連打を全復元、段落 33→51、空白 4 | 呼吸が戻る |
| v3 | 「売却決定やエンディングといった項目が余韻をぶち壊す」 | 末尾 2 見出し削除 | |
| v4 | 「詩に一段落毎にタイトルを振るか？振らないだろ」 | 見出し全廃、金利を本文へ | |
| v5 | 「詩の世界ではスペースや行下げで場面を切り替える。note なら横線」 | 場面転換 8 箇所を横線、呼吸 4 箇所は空白のまま | 「とてもよい文章になった」 |

## 関連
- [[note-writer]] Step 3.5(natural-japanese の実行手順の正本) / [[sengoku-writer]]
- `context/prose-polish.md`(索引) / `docs/research/prose_polish_case_apartment_interest_20260902.md`(事例正本)
- origin: `[[殿指示_note推敲_20260902]] -> [[lint最適化でインパクト消失_v1]] -> [[詩の原理で判定_v2-v5]] -> [[prose-polish]]`
