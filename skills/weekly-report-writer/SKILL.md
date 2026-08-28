---

<!-- script_refs_checked_at: 2026-07-16T23:40:33+0900
<!-- cmd_karo_hotfix_skill_refs_eight_202607162132検分: note_draft.sh現HEAD+作業差分を確認。CDP未応答は隔離profile自動起動、起動不能/reCAPTCHA未解決はexit 1(FAIL)。末尾skill-auto-improve追記はexit後でI/F不変。週報Markdown生成後の単一file引数契約を維持。 -->
name: weekly-report-writer
argument-hint: "[week:YYYY-Www]"
quality_metric: "将軍系: 週報生成cmdのcmd_save.shチェック通過率(q1-q4 BLOCKなしで保存できた割合)"
description: |
  【将軍専用】家老・忍者は使用禁止。将軍以外が呼んだ場合は即座に中断せよ。
  What: DM-Signal Weekly Report を再現生成するスキル。DM-Signal API から compare-returns(8期間トレーリングリターン一括) / signals / deterioration を取得し、xAI Grok x_search でXの最新情報を補完して週報Markdownを書く。
  TRIGGER: /weekly-report、週報 project:dm-signal、ウィークリーレポート project:dm-signal、DM-Signal週報 project:dm-signal
  When: `/mnt/c/Python_app/DM-signal/marketing-director/content/weekly_report/YYYY-MM-DD_weekly.md` に週報Markdownを生成する時に使う。
  NOT When: 月報、note記事、X単体調査、またはDM-Signal以外のレポート生成では使わない。
allowed_projects: [dm-signal]
allowed-tools:
  - Bash
  - Read
  - Write
---

<!-- script_refs_checked_at: 2026-07-16T23:40:33+0900
<!-- 2026-07-16再検分: note_draft.sh 31cfcb906/7127ab894/1421d3c92/5a7543ad9。Chrome未起動時は隔離profileを自動起動し、起動不能時のみexit 1(FAIL)。■行は個別bulletとして解釈後、<br>で1行改行する。単一Markdown引数とCDP_PORT契約は不変。 -->
<!-- 検分: note_draft.sh 8e4872513 reCAPTCHA guard内部強化。呼び出し契約 `CDP_PORT=9234 bash scripts/note_draft.sh "$OUT_FILE"`、週報Markdown生成後のnote下書き保存契約は不変 -->
<!-- script_refs_checked_at: 2026-07-16T23:40:33+0900

Script refs verified: 2026-06-12. `note_draft.sh` の契約は `CDP_PORT=9234 bash scripts/note_draft.sh "$OUT_FILE"` のまま。932936059は外部reCAPTCHA画像チャレンジ未解決を運用FAILではなくSKIPとして`skill_execution_log.yaml`へ記録し、exit 0で返す変更。Gate20も同じ外部reCAPTCHAチャレンジ由来の`note-draft`結果をFAIL率分母から除外する。週報Markdown生成後のnote下書き保存呼び出し・Chrome未起動時SKIP・通常PASS/FAILログの契約変更なし。
Script refs verified: 2026-06-16 cmd_karo_skill_refs_update_20260616. `note_draft.sh` 直近変更(6ac00607e)はshellcheckコメント形式修正(markdown list→shell comment)のみ。引数・CDP_PORT・通常PASS/FAILログの契約変更なし。
Script refs verified: 2026-06-26 af9e4c7b3+cc2dae45c. `note_draft.sh` 直近変更はMarkdown bold→strong変換(内部修正)+batch commit。`CDP_PORT=9234 bash scripts/note_draft.sh "$OUT_FILE"` の呼び出し契約は変更なし。

# /weekly-report

## 使い方

```bash
/weekly-report
```

任意オプション:

- `REPORT_DATE=YYYY-MM-DD` を事前 export すると対象日を固定できる
- `MARKET_MEMO_FILE=/abs/path/to/memo.md` を事前 export すると、殿の市場メモを「今週のマーケット」に優先採用する

## このSkillがやること

1. DM-Signal API から対象PFの `signals` `monthly-returns` `deterioration` を取得する
2. `MARKET_MEMO_FILE` が無ければ、Grok `x_search` で市場トピックを収集する
3. 2026-03-10 号と同じ構成で週報Markdownを書く
4. 出力先を自動で
   `/mnt/c/Python_app/DM-signal/marketing-director/content/weekly_report/YYYY-MM-DD_weekly.md`
   に設定する

## 絶対ルール

### データ
- 構成ティッカー、ウェイト、raw signal を記事に書かない
- API が返す `tickers` `expanded_tickers` `signal` は執筆素材ではなく検算用データとして扱う
- 対象PFはメンバーシップ4体 + シン四神激攻4体 + GSシン忍法6体 = 14体のみ。範囲外PFを載せるな
- Python スクリプトは増やさない。下記の Bash + `curl` + `jq` で完結させる

### 書き方
- **表組禁止** — 全セクション■箇条書きでインラインにデータを並べる
- **タイプ分類なし** — 守り型/バランス型/攻め型を書かない
- **UIに記載のない情報を書くな** — DM-signal UIやDocsに明記されていない分類・評価・解釈は禁止（★MVP、強い/弱い等の定義なき形容）
- **G1/G2はDocs準拠** — G1=短期トレンド、G2=長期ドリフト。実データに基づく事実描写のみ
- **リンク不要** — X投稿URL等のリンクは記事に含めない
- **投資助言表現禁止** — 買い/売り推奨、価格目標、断定的な煽りは禁止
- **指数は週間レンジ/週間変動で出す** — 日次変動はdailyになるため不可

### 地政学・ニュース
- **双方の視点を入れる** — 西側報道だけに依存しない。アラビア語・ペルシャ語でもx_search
- **戦争・紛争は1行でマーケット影響に絞る** — 戦争レポートではない
- **裏を取れ** — Grokが生成した情報をそのまま載せるな。x_searchで事実確認

## 事前確認

以下が無ければ停止:

```bash
command -v curl >/dev/null
command -v jq >/dev/null
test -f /mnt/c/Python_app/DM-signal/backend/.env
test -f "$SHOGUN_ROOT/config/xai_api.env"
```

## 実行手順

### Step 1: 変数を確定する

`backend/.env` は行全体を `source` しない。不要な行で副作用が出るため、必要変数だけ `grep` で抜く。

```bash
export DM_SIGNAL_ROOT=/mnt/c/Python_app/DM-signal
export SHOGUN_ROOT="$(git rev-parse --show-toplevel)"
export DM_SIGNAL_BASE_URL="${DM_SIGNAL_BASE_URL:-https://dm-signal-backend.onrender.com}"
export REPORT_DATE="${REPORT_DATE:-$(TZ=Asia/Tokyo date +%F)}"
export OUT_DIR="$DM_SIGNAL_ROOT/marketing-director/content/weekly_report"
export OUT_FILE="$OUT_DIR/${REPORT_DATE}_weekly.md"
export WORK_DIR="/tmp/weekly-report-${REPORT_DATE}"

mkdir -p "$OUT_DIR" "$WORK_DIR/monthly"

export ADMIN_USER="$(grep '^ADMIN_USER=' "$DM_SIGNAL_ROOT/backend/.env" | cut -d= -f2-)"
export ADMIN_PASS="$(grep '^ADMIN_PASS=' "$DM_SIGNAL_ROOT/backend/.env" | cut -d= -f2-)"
export XAI_API_KEY="$(grep '^XAI_API_KEY=' "$SHOGUN_ROOT/config/xai_api.env" | cut -d= -f2-)"
```

### Step 2: 対象PFを定義する

```bash
MEMBERSHIP_PFS=(
  "DM-safe"
  "劇薬DMオリジナル"
  "Ave-X"
  "裏Ave-X"
)

SHIJIN_PFS=(
  "シン青龍-激攻"
  "シン朱雀-激攻"
  "シン白虎-激攻"
  "シン玄武-激攻"
)

NINPO_PFS=(
  "GSシン分身-激攻" "GSシン分身-鉄壁" "GSシン分身-常勝"
  "GSシン四つ目-激攻" "GSシン四つ目-鉄壁" "GSシン四つ目-常勝"
)

ALL_PFS=("${MEMBERSHIP_PFS[@]}" "${SHIJIN_PFS[@]}" "${NINPO_PFS[@]}")
```

### Step 3: APIから生データを取得する

```bash
curl -fsS -u "$ADMIN_USER:$ADMIN_PASS" \
  "$DM_SIGNAL_BASE_URL/api/portfolios/get" \
  > "$WORK_DIR/portfolios.json"

curl -fsS -u "$ADMIN_USER:$ADMIN_PASS" \
  "$DM_SIGNAL_BASE_URL/api/signals" \
  > "$WORK_DIR/signals.json"

curl -fsS -u "$ADMIN_USER:$ADMIN_PASS" \
  "$DM_SIGNAL_BASE_URL/api/deterioration" \
  > "$WORK_DIR/deterioration.json"
```

UUID はハードコードしない。`/api/portfolios/get` から名前で引く。

```bash
resolve_pf_id() {
  jq -r --arg name "$1" '
    .data.portfolios[]
    | select(.name == $name)
    | .id
  ' "$WORK_DIR/portfolios.json"
}

extract_monthly_returns() {
  local pf_name="$1"
  local pf_id
  pf_id="$(resolve_pf_id "$pf_name")"
  test -n "$pf_id" && test "$pf_id" != "null"
  curl -fsS -u "$ADMIN_USER:$ADMIN_PASS" \
    "$DM_SIGNAL_BASE_URL/api/monthly-returns/${pf_id}?years=1" \
    > "$WORK_DIR/monthly/${pf_id}.json"
  printf '%s\t%s\n' "$pf_name" "$pf_id" >> "$WORK_DIR/portfolio_map.tsv"
}

: > "$WORK_DIR/portfolio_map.tsv"
for pf in "${ALL_PFS[@]}"; do
  extract_monthly_returns "$pf"
done
```

### Step 4: 記事用の集計を作る

#### 4-1. Signals は鮮度確認だけに使う

記事に raw signal を書かない。`signal_pending` と `as_of` の確認だけ行う。

```bash
jq -r '
  .data
  | "signals_as_of\t\(.as_of)",
    (.portfolios[] | [.name, (.signal_pending // false)] | @tsv)
' "$WORK_DIR/signals.json" > "$WORK_DIR/signal_check.tsv"
```

#### 4-2. 共通: 3期間集計関数 (今月MTD / 先月 / 過去1年累積)

```bash
fmt_pct='
  def pct:
    if . == null then "N/A"
    else (((. * 10000) | round) / 100 | tostring) + "%"
    end;
  def cum1y:
    if length == 0 then "N/A"
    else (reduce .[] as $r (1; . * (1 + $r))) | ((. - 1) * 10000 | round) / 100 | tostring + "%"
    end;
'

extract_3period() {
  local pf_name="$1" out_file="$2"
  local pf_id
  pf_id="$(awk -F '\t' -v name="$pf_name" '$1 == name {print $2}' "$WORK_DIR/portfolio_map.tsv")"
  jq -r --arg name "$pf_name" "$fmt_pct
    .data.monthly_returns
    | sort_by(.year, .month)
    | {
        prev: (.[-2] // null),
        latest: (.[-1] // null),
        cum1y: ([.[-12:][] | .portfolio.return // 0] | cum1y)
      }
    | [
        \$name,
        (.latest.portfolio.return | pct),
        (.prev.portfolio.return | pct),
        .cum1y
      ]
    | @tsv
  " "$WORK_DIR/monthly/${pf_id}.json" >> "$out_file"
}
```

#### 4-3. メンバーシップPF (今月 / 先月 / 1年)

```bash
: > "$WORK_DIR/membership.tsv"
for pf in "${MEMBERSHIP_PFS[@]}"; do
  extract_3period "$pf" "$WORK_DIR/membership.tsv"
done
```

#### 4-4. シン四神 激攻4体 (今月 / 先月 / 1年)

```bash
: > "$WORK_DIR/shijin.tsv"
for pf in "${SHIJIN_PFS[@]}"; do
  extract_3period "$pf" "$WORK_DIR/shijin.tsv"
done
```

#### 4-5. GSシン忍法6体 (今月 / 先月 / 1年)

```bash
: > "$WORK_DIR/ninpo.tsv"
for pf in "${NINPO_PFS[@]}"; do
  extract_3period "$pf" "$WORK_DIR/ninpo.tsv"
done
```

#### 4-6. Deterioration のラベル / G1 / G2

```bash
PF_NAMES_JSON="$(printf '%s\n' "${ALL_PFS[@]}" | jq -R . | jq -s .)"

jq -r --argjson names "$PF_NAMES_JSON" '
  def num:
    if . == null then "N/A"
    else (((. * 1000) | round) / 1000 | tostring)
    end;
  .data.portfolios
  | map(select(.name as $n | $names | index($n)))
  | .[]
  | [
      .name,
      .label,
      (.g1_slope_12 | num),
      (.g2_p_erosion_12 | num),
      (.p12 | num),
      (.prev_label // "N/A")
    ]
  | @tsv
' "$WORK_DIR/deterioration.json" > "$WORK_DIR/deterioration.tsv"
```

### Step 5: 市場情報を用意する

殿の市場メモがあるなら最優先。無ければ Grok `x_search` を使う。

#### 5-A. 市場メモがある場合

```bash
test -n "${MARKET_MEMO_FILE:-}"
cp "$MARKET_MEMO_FILE" "$WORK_DIR/market_source.md"
```

#### 5-B. 市場メモがない場合

`/v1/responses` を使う。パラメータ名は `messages` ではなく `input`。
**3回に分けて取得する**: (1)市場概況 (2)要人発言+米国+日本 (3)地政学（多言語）
※「将軍の短観」はGrokではなく、Step 4で取得したAPIデータ（MTD実績+Deterioration）を基に将軍が書く。

```bash
# (1) 市場概況
cat > "$WORK_DIR/x_prompt_market.txt" <<'EOF'
日本語で、今週の市場概況をまとめる。
対象: S&P500 / Nasdaq / 米国債(2y/10y/30y) / ドル円 / WTI / 金 / ビットコイン
全て週間変動（週初vs週末）で出すこと。日次変動は不可。
投資助言表現は禁止。
EOF

curl -fsS https://api.x.ai/v1/responses \
  -H "Authorization: Bearer $XAI_API_KEY" \
  -H 'Content-Type: application/json' \
  -d "{
    \"model\": \"grok-4-1-fast\",
    \"input\": $(jq -Rs . < "$WORK_DIR/x_prompt_market.txt"),
    \"tools\": [{\"type\": \"x_search\"}]
  }" \
  > "$WORK_DIR/x_market.json"

jq -r '.output[] | select(.type == "message") | .content[] | select(.type == "output_text") | .text' \
  "$WORK_DIR/x_market.json" > "$WORK_DIR/market_source.md"

# (2) 要人発言 + 米国 + 日本
cat > "$WORK_DIR/x_prompt_regions.txt" <<'EOF'
日本語で、今週について以下3点を簡潔に（各2-3行）。リンク不要。投資助言禁止。
1. 要人発言（FRB議長、ECB総裁、日銀総裁など中央銀行・政府高官）
2. 米国（経済指標、政策、注目イベント）
3. 日本（経済指標、政策、日経平均の週間変動）
EOF

curl -fsS https://api.x.ai/v1/responses \
  -H "Authorization: Bearer $XAI_API_KEY" \
  -H 'Content-Type: application/json' \
  -d "{
    \"model\": \"grok-4-1-fast\",
    \"input\": $(jq -Rs . < "$WORK_DIR/x_prompt_regions.txt"),
    \"tools\": [{\"type\": \"x_search\"}]
  }" \
  > "$WORK_DIR/x_regions.json"

jq -r '.output[] | select(.type == "message") | .content[] | select(.type == "output_text") | .text' \
  "$WORK_DIR/x_regions.json" > "$WORK_DIR/regions_source.md"

# (3) 地政学（多言語で双方の視点）
cat > "$WORK_DIR/x_prompt_geopolitics.txt" <<'EOF'
Search X in English, Arabic, and Farsi for this week's major geopolitical events
that affect financial markets. Report both sides of any conflict.
Keep it to 2-3 bullet points focused on market impact. No links. Report in Japanese.
EOF

curl -fsS https://api.x.ai/v1/responses \
  -H "Authorization: Bearer $XAI_API_KEY" \
  -H 'Content-Type: application/json' \
  -d "{
    \"model\": \"grok-4-1-fast\",
    \"input\": $(jq -Rs . < "$WORK_DIR/x_prompt_geopolitics.txt"),
    \"tools\": [{\"type\": \"x_search\"}]
  }" \
  > "$WORK_DIR/x_geopolitics.json"

jq -r '.output[] | select(.type == "message") | .content[] | select(.type == "output_text") | .text' \
  "$WORK_DIR/x_geopolitics.json" > "$WORK_DIR/geopolitics_source.md"
```

**重要**: Grokの出力をそのまま採用するな。x_searchの結果は素材。事実確認が取れたものだけ記事に採用する。

### Step 6: 週報を書く

**全セクション■箇条書き。表組禁止。リンク不要。**

以下のテンプレートで `OUT_FILE` を作る。

```markdown
# DM-Signal Weekly — {{REPORT_DATE}}

## マーケット

■ S&P500 週間X.X%、NASDAQ 週間X.X%
■ 2y Xbp X.XX%、10y Xbp X.XX%、30y Xbp X.XX%
■ ドル円 XXX.XX–XXX.XX、WTI 週間X.X%、金 週間X.X%、₿ 週間X.X%
■ {{地政学ネタ — 双方の視点、マーケット影響に絞って1行}}
■ {{その他マーケットニュース}}

## 要人発言

■ {{中央銀行・政府高官の発言。事実のみ}}
■ {{目立った発言がなければ「なし」と明記}}

## 米国

■ {{経済指標・政策・注目イベント。数値は予想対比で}}

## 日本

■ {{日経平均の週間変動。経済指標・政策}}

---

## メンバーシップPF（X/X時点）

■ DM-safe X月X.XX%（X月X.XX%、直近1年X.XX%）
■ 劇薬DMオリジナル X月X.XX%（X月X.XX%、直近1年X.XX%）
■ Ave-X X月X.XX%（X月X.XX%、直近1年X.XX%）
■ 裏Ave-X X月X.XX%（X月X.XX%、直近1年X.XX%）

---

## シン四神（激攻・X/X時点）

■ シン青龍-激攻 X月X.XX%（X月X.XX%、直近1年X.XX%）
■ シン朱雀-激攻 X月X.XX%（X月X.XX%、直近1年X.XX%）
■ シン白虎-激攻 X月X.XX%（X月X.XX%、直近1年X.XX%）
■ シン玄武-激攻 X月X.XX%（X月X.XX%、直近1年X.XX%）

---

## GSシン忍法（X/X時点）

■ GSシン分身-激攻 X月X.XX%（X月X.XX%、直近1年X.XX%）
■ GSシン分身-鉄壁 X月X.XX%（X月X.XX%、直近1年X.XX%）
■ GSシン分身-常勝 X月X.XX%（X月X.XX%、直近1年X.XX%）
■ GSシン四つ目-激攻 X月X.XX%（X月X.XX%、直近1年X.XX%）
■ GSシン四つ目-鉄壁 X月X.XX%（X月X.XX%、直近1年X.XX%）
■ GSシン四つ目-常勝 X月X.XX%（X月X.XX%、直近1年X.XX%）

---

## 将軍の短観

**将軍口調で書く**（〜でござる、〜なり、〜されたし、〜にあらず 等）。データ解説ではなく、将軍が戦況を見立てる語り口。

箇条書きの羅列ではなく、将軍が戦況を語るように自然な文章で書く。
段落構成: (1)メンバーシップ4PFの全体感 (2)シン四神から注目1体+警戒1体（旧・新スタンダード共通の文脈）
(3)GSシン分身から注目1体（新スタンダード・裏アドオン特典の文脈）(4)GSシン四つ目から注目1体（プレミアム特典の文脈）
(5)G1/G2/P(det)の全体所見。各段落は改行で区切る。■は使わない。
■ G1（短期トレンド）: {{APIのg1_slope_12から読み取れる所見。将軍口調}}
■ G2（長期ドリフト）: {{APIのg2_p_erosion_12から読み取れる所見。将軍口調}}
■ P(det)（弱体化確率）: {{APIのp12から読み取れる所見。将軍口調}}

---

*Data: DM-Signal ({{データ日付}}) / 投資助言ではありません*
```

**書き方の注意**:
- タイプ分類（守り型/攻め型等）を書かない
- 対象PF以外（bam-2等）を載せない
- DM-signal UIやDocsにない情報を書かない（★MVP、定義なき強弱等）
- Grokの出力を鵜呑みにしない。事実確認が取れたものだけ採用

### Step 7: 最終検査

保存後、以下を満たすか確認する:

```bash
test -f "$OUT_FILE"
rg -n "買い|売り|目標株価|エントリー推奨|おすすめ" "$OUT_FILE" && echo "NG: advice wording"
```

目視確認:

- 8セクション構成か（マーケット/要人発言/米国/日本/メンバーシップPF/シン四神/GSシン忍法/将軍の短観）+Deterioration Monitor+免責
- メンバーシップ4PF+シン四神激攻4体+GSシン忍法6体=14体が全て載っているか
- 各PFに3期間（今月/先月/1年）のリターンが記載されているか
- 表組が一切ないか（■箇条書きのみ）
- タイプ分類（守り/攻め/バランス）が残っていないか
- 範囲外PF（bam-2等）が混入していないか
- リンクが残っていないか
- 指数が週間変動になっているか（日次になっていないか）
- UIやDocsにない独自解釈が混入していないか
- raw signal / ticker / weight が記事本文に出ていないか
- 出力先が `marketing-director/content/weekly_report/YYYY-MM-DD_weekly.md` になっているか

### Step 8: note.comに下書き保存

CDP経由でnote.comに下書き保存する。手順は共通リファレンス参照:
→ `memory/reference_cdp_note_com.md`

```bash
CDP_PORT=9234 bash scripts/note_draft.sh "$OUT_FILE"
```

未ログイン時は`.env.note`の`NOTE_EMAIL`/`NOTE_PASSWORD`で自動ログインする。CDP未応答時は隔離profile付きChromeを自動起動する。reCAPTCHAが出た場合はチェックボックスをCDP座標クリックし、画像チャレンジでは`/tmp/note_recaptcha_challenge.png`を撮影して最大120秒待機する。Chrome起動不能またはreCAPTCHA未解決はSKIPせずFAIL(exit 1)として記録する。ProseMirrorエディタがスピナーで停止している場合は`Page.reload`で最大2回リトライする。実行結果は`skill_execution_log.yaml`にPASS/FAILで記録される。

## トラブル時

- `401 Invalid authentication credentials`
  - `backend/.env` の `ADMIN_USER` `ADMIN_PASS` を確認する。`grep + cut -d= -f2-` で取得する際は `tr -d '[:space:]'` で末尾空白を除去必須（空白混入で401になる）
  - 月次パスワードローテ後に stale なことがある。資格情報が古いままなら続行しない
- `jq: Cannot iterate over null`
  - API が失敗して HTML/401 を返していることが多い。先に `curl -i` でヘッダを見る
- X検索が空
  - `config/xai_api.env` の `XAI_API_KEY` を確認する
  - `model` は `grok-4-1-fast`、`tools` は `[{\"type\":\"x_search\"}]` を維持する
- note.com SKIP: `reCAPTCHA state unclear; waiting 120s`
  - note_draft.shが120秒待ちに入る場合、invisible reCAPTCHAでログインボタンクリック後にバックグラウンド検証が通っていない
  - 2026-06-29修正済み: dispatch_click座標クリック + quick_url待ち(8s)でスキップ
  - PowerShell WebSocketがWSL2でハングする場合: Python websocketモジュール(`pip install websocket-client`)で直接CDP操作が確実
- note.com「メールアドレスおよびパスワードをご確認ください」
  - パスワード二重入力の可能性。note_draft.shが先にsetValue+click→手動で追加入力すると二重になる。フィールドをselectAll+Backspaceで一度クリアしてから入力せよ
  - emailフィールドはtype="text" id="email"。`input[type="email"]`セレクタでは見つからない
- Chrome起動時は `--remote-allow-origins=*` 必須（WebSocket 403回避）

## 完了条件

- `OUT_FILE` が生成されている
- 9セクション構成（マーケット/要人発言/米国/日本/メンバーシップPF/シン四神/GSシン忍法/Deterioration Monitor/将軍の短観）+免責
- 全14体にMTD+複数期間リターン（MTD/1M/3M/6M/1Y/ALLの中から適切に選択）が記載されている
- 全セクション■箇条書き（表組なし）
- compare-returns（8期間トレーリングリターン一括） / signals / deterioration / x_search を全て使用している
- 構成ティッカーが本文に出ていない
- リンクが本文に出ていない
- 指数が週間変動になっている

<!-- script_refs_checked_at: 2026-07-16T23:40:33+0900

Script refs verified: 2026-07-16. `note_draft.sh` はChrome CDP未起動時にPython層のChrome自動起動(launch_browser+cmd.exeフォールバック)へ委ねる。旧Step 0のSKIP(exit 0)は殿裁定2026-07-16で「バグ」と判定され除去。Chrome未起動時もスキルは自動起動を試行し、起動失敗時のみFAIL(exit 1)となる。`CDP_PORT=9234 bash scripts/note_draft.sh "$OUT_FILE"` の呼び出し契約は変更なし。

## 関連スキル

- [[monthly-report-writer]] — 月次レポート（週報の月間版。より詳細な長期パフォーマンス分析含む）
- [[x-research]] — X/Twitter検索調査のみ実行する場合（週報生成を伴わない単体調査）

Script refs verified: 2026-06-26 af9e4c7b3. `note_draft.sh` 直近変更はMarkdown bold→strong変換の内部修正。週報Markdown生成後の `CDP_PORT=9234 bash scripts/note_draft.sh "$OUT_FILE"` 呼び出し契約は変更なし。

<!-- script_refs_checked_at: 2026-07-16T23:40:33+0900
