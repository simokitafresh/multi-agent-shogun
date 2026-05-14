---
name: weekly-report-writer
argument-hint: "[week:YYYY-Www]"
quality_metric: "将軍系: 週報生成cmdのcmd_save.shチェック通過率(q1-q4 BLOCKなしで保存できた割合)"
description: |
  What: DM-Signal Weekly Report を再現生成するスキル。DM-Signal API から signals / monthly-returns / deterioration を取得し、xAI Grok x_search でXの最新情報を補完して週報Markdownを書く。
  TRIGGER: /weekly-report、週報 project:dm-signal、ウィークリーレポート project:dm-signal、DM-Signal週報 project:dm-signal
  When: `/mnt/c/Python_app/DM-signal/marketing-director/content/weekly_report/YYYY-MM-DD_weekly.md` に週報Markdownを生成する時に使う。
  NOT When: 月報、note記事、X単体調査、またはDM-Signal以外のレポート生成では使わない。
allowed_projects: [dm-signal]
allowed-tools:
  - Bash
  - Read
  - Write
---

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
- 対象PFはメンバーシップPF + 四神12体のみ。範囲外PF（bam-2等）を載せるな
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
test -f /mnt/c/tools/multi-agent-shogun/config/xai_api.env
```

## 実行手順

### Step 1: 変数を確定する

`backend/.env` は行全体を `source` しない。不要な行で副作用が出るため、必要変数だけ `grep` で抜く。

```bash
export DM_SIGNAL_ROOT=/mnt/c/Python_app/DM-signal
export SHOGUN_ROOT=/mnt/c/tools/multi-agent-shogun
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
  "DM-safe-2"
  "劇薬DMスムーズ"
  "劇薬DMオリジナル"
  "Ave-X"
  "裏Ave-X"
)

SHIJIN_PFS=(
  "激攻-青龍" "鉄壁-青龍" "常勝-青龍"
  "激攻-朱雀" "鉄壁-朱雀" "常勝-朱雀"
  "激攻-白虎" "鉄壁-白虎" "常勝-白虎"
  "激攻-玄武" "鉄壁-玄武" "常勝-玄武"
)

ALL_PFS=("${MEMBERSHIP_PFS[@]}" "${SHIJIN_PFS[@]}")
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

#### 4-2. メンバーシップPFの MTD / 前月実績

```bash
fmt_pct='
  def pct:
    if . == null then "N/A"
    else (((. * 10000) | round) / 100 | tostring) + "%"
    end;
'

: > "$WORK_DIR/membership.tsv"
for pf in "${MEMBERSHIP_PFS[@]}"; do
  pf_id="$(awk -F '\t' -v name="$pf" '$1 == name {print $2}' "$WORK_DIR/portfolio_map.tsv")"
  jq -r --arg name "$pf" "$fmt_pct
    .data.monthly_returns
    | sort_by(.year, .month)
    | {prev: (.[-2] // null), latest: (.[-1] // null)}
    | [
        $name,
        (.latest.portfolio.return | pct),
        (.prev.portfolio.return | pct)
      ]
    | @tsv
  " "$WORK_DIR/monthly/${pf_id}.json" >> "$WORK_DIR/membership.tsv"
done
```

#### 4-3. 四神12体の近況

```bash
: > "$WORK_DIR/shijin.tsv"
for pf in "${SHIJIN_PFS[@]}"; do
  pf_id="$(awk -F '\t' -v name="$pf" '$1 == name {print $2}' "$WORK_DIR/portfolio_map.tsv")"
  jq -r --arg name "$pf" "$fmt_pct
    .data.monthly_returns
    | sort_by(.year, .month)
    | {prev: (.[-2] // null), latest: (.[-1] // null)}
    | [
        $name,
        (.latest.portfolio.return | pct),
        (.prev.portfolio.return | pct)
      ]
    | @tsv
  " "$WORK_DIR/monthly/${pf_id}.json" >> "$WORK_DIR/shijin.tsv"
done
```

#### 4-4. Deterioration のラベル / G1 / G2

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
🔥 {{地政学ネタ — 双方の視点、マーケット影響に絞って1行}}
■ {{その他マーケットニュース}}

## 要人発言

■ {{中央銀行・政府高官の発言。事実のみ}}
■ {{目立った発言がなければ「なし」と明記}}

## 米国

■ {{経済指標・政策・注目イベント。数値は予想対比で}}

## 日本

■ {{日経平均の週間変動。経済指標・政策}}

---

## メンバーシップPF（X/X時点 MTD）

■ DM-safe 3月X.XX%（2月X.XX%）
■ DM-safe-2 3月X.XX%（2月X.XX%）
■ 劇薬DMスムーズ 3月X.XX%（2月X.XX%）
■ 劇薬DMオリジナル 3月X.XX%（2月X.XX%）
■ Ave-X 3月X.XX%（2月X.XX%）
■ 裏Ave-X 3月X.XX%（2月X.XX%）
■ (SPY) 3月X.XX%（2月X.XX%）

---

## 四神12体（X/X時点 MTD）

■ 青龍 激攻X.XX% / 鉄壁X.XX% / 常勝X.XX%（2月: X.XX% / X.XX% / X.XX%）
■ 朱雀 激攻X.XX% / 鉄壁X.XX% / 常勝X.XX%（2月: X.XX% / X.XX% / X.XX%）
■ 白虎 激攻X.XX% / 鉄壁X.XX% / 常勝X.XX%（2月: X.XX% / X.XX% / X.XX%）
■ 玄武 激攻X.XX% / 鉄壁X.XX% / 常勝X.XX%（2月: X.XX% / X.XX% / X.XX%）

---

## 将軍の短観

**将軍口調で書く**（〜でござる、〜なり、〜されたし、〜にあらず 等）。データ解説ではなく、将軍が戦況を見立てる語り口。

■ {{メンバーシップ6PFを2-3組にまとめて短評。前月対比・SPY対比の文脈で。将軍口調}}
■ {{今月の一手: 四神から1体選び、注目理由を1行で。将軍口調}}
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

- 7セクション構成か（マーケット/要人発言/米国/日本/メンバーシップPF/四神12体/将軍の短観）+免責
- メンバーシップ6PF+SPYと四神12体が全て載っているか
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

未ログイン時は`.env.note`の`NOTE_EMAIL`/`NOTE_PASSWORD`で自動ログインする。reCAPTCHAが出た場合はチェックボックスをCDP座標クリックし、画像チャレンジでは`/tmp/note_recaptcha_challenge.png`を撮影して、ブラウザ上で解決されるまで最大120秒待機する。

## トラブル時

- `401 Invalid authentication credentials`
  - `backend/.env` の `ADMIN_USER` `ADMIN_PASS` を確認する
  - 月次パスワードローテ後に stale なことがある。資格情報が古いままなら続行しない
- `jq: Cannot iterate over null`
  - API が失敗して HTML/401 を返していることが多い。先に `curl -i` でヘッダを見る
- X検索が空
  - `config/xai_api.env` の `XAI_API_KEY` を確認する
  - `model` は `grok-4-1-fast`、`tools` は `[{\"type\":\"x_search\"}]` を維持する

## 完了条件

- `OUT_FILE` が生成されている
- 9セクション構成（マーケット/要人発言/米国/日本/メンバーシップPF/四神12体/Deterioration Monitor/将軍の短観/免責）
- 全セクション■箇条書き（表組なし）
- signals / monthly-returns / deterioration / x_search を全て使用している
- 構成ティッカーが本文に出ていない
- リンクが本文に出ていない
- 指数が週間変動になっている
