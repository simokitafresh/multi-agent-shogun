---
name: monthly-report-writer
argument-hint: "[month:YYYY-MM]"
description: |
  【将軍専用】家老・忍者は使用禁止。将軍以外が呼んだ場合は即座に中断せよ。
  DM-Signal Monthly Report を月初に発行する skill。
  DM-Signal API から signals / monthly-returns(5年) / deterioration を取得し、
  xAI Grok x_search で先月の月間ニュースを補完して、
  `/mnt/c/Python_app/DM-signal/marketing-director/content/monthly_report/YYYY-MM_monthly.md`
  に月報Markdownを生成する。先月振り返り+当月見込み+長期(5年)推移の3層構成。
  TRIGGER: /monthly-report、月報 project:dm-signal、マンスリーレポート project:dm-signal、月次レポート project:dm-signal、DM-Signal月報 project:dm-signal
  DO NOT TRIGGER: 週報（→[[weekly-report-writer]]）、X検索のみ（→x-research）、
  note記事（→[[note-writer]] / [[sengoku-writer]]）
quality_metric: "当該スキル使用タスクのWA不発生率（logs/karo_workarounds.yamlに月報生成手順起因のworkaroundが記録されない割合）"
allowed_projects: [dm-signal]
allowed-tools:
  - Bash
  - Read
  - Write
---

# /monthly-report

## 使い方

```bash
/monthly-report
```

任意オプション:

- `REPORT_MONTH=YYYY-MM` を事前 export すると対象月を固定できる（デフォルト: 先月）
- `MARKET_MEMO_FILE=/abs/path/to/memo.md` を事前 export すると、殿の市場メモを優先採用する

## このSkillがやること

1. DM-Signal API から対象PFの `signals` `monthly-returns(5年)` `deterioration` を取得する
2. Grok `x_search` で先月の月間マーケット・ニュースを収集する
3. 先月振り返り+当月見込み+長期推移の3層構成で月報Markdownを書く
4. 出力先:
   `/mnt/c/Python_app/DM-signal/marketing-director/content/monthly_report/YYYY-MM_monthly.md`

## 絶対ルール

### データ
- 構成ティッカー、ウェイト、raw signal を記事に書かない
- API が返す `tickers` `expanded_tickers` `signal` は執筆素材ではなく検算用データとして扱う
- 対象PFはメンバーシップPF + 四神12体のみ。範囲外PF（bam-2等）を載せるな
- Python スクリプトは増やさない。Bash + `curl` + `jq` で完結させる

### 書き方
- **表組禁止** — 全セクション■箇条書きでインラインにデータを並べる
- **タイプ分類なし** — 守り型/バランス型/攻め型を書かない
- **UIに記載のない情報を書くな** — DM-signal UIやDocsに明記されていない分類・評価・解釈は禁止
- **G1/G2はDocs準拠** — G1=短期トレンド、G2=長期ドリフト。実データに基づく事実描写のみ
- **リンク不要** — URL等のリンクは記事に含めない
- **投資助言表現禁止** — 買い/売り推奨、価格目標、断定的な煽りは禁止
- **指数は月間変動で出す** — 月初vs月末の変動率。日次・週次変動は不可

### ニュース・地政学
- **月間まとめとして書く** — 週次の羅列ではなく、月を通した流れ・テーマで構成
- **双方の視点を入れる** — 西側報道だけに依存しない。多言語でx_search
- **戦争・紛争はマーケット影響に絞る** — 戦争レポートではない
- **裏を取れ** — Grokが生成した情報をそのまま載せるな

## 事前確認

以下が無ければ停止:

```bash
command -v curl >/dev/null
command -v jq >/dev/null
test -f /mnt/c/Python_app/DM-signal/backend/.env
test -f /home/simokitafresh/multi-agent-shogun/config/xai_api.env
```

## 実行手順

### Step 1: 変数を確定する

```bash
export DM_SIGNAL_ROOT=/mnt/c/Python_app/DM-signal
export SHOGUN_ROOT=/home/simokitafresh/multi-agent-shogun
export DM_SIGNAL_BASE_URL="${DM_SIGNAL_BASE_URL:-https://dm-signal-backend.onrender.com}"

# 発行月（デフォルト: 当月）。月初に発行し、先月を振り返る構成。
# ファイル名・タイトルは発行月（例: 4/1発行 → 2026-04_monthly.md）
if [ -z "${PUBLISH_MONTH:-}" ]; then
  PUBLISH_MONTH=$(TZ=Asia/Tokyo date +%Y-%m)
fi
export PUBLISH_MONTH

# 振り返り対象月（発行月の前月）
REVIEW_MONTH=$(TZ=Asia/Tokyo date -d "${PUBLISH_MONTH}-01 -1 day" +%Y-%m)
REVIEW_YEAR=$(echo "$REVIEW_MONTH" | cut -d- -f1)
REVIEW_MON=$(echo "$REVIEW_MONTH" | cut -d- -f2)

# 発行月（当月 = 見込みセクションの対象）
PUBLISH_YEAR=$(echo "$PUBLISH_MONTH" | cut -d- -f1)
PUBLISH_MON=$(echo "$PUBLISH_MONTH" | cut -d- -f2)

export OUT_DIR="$DM_SIGNAL_ROOT/marketing-director/content/monthly_report"
export OUT_FILE="$OUT_DIR/${PUBLISH_MONTH}_monthly.md"
export WORK_DIR="/tmp/monthly-report-${PUBLISH_MONTH}"

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

# 5年分の月次リターンを取得
extract_monthly_returns() {
  local pf_name="$1"
  local pf_id
  pf_id="$(resolve_pf_id "$pf_name")"
  test -n "$pf_id" && test "$pf_id" != "null"
  curl -fsS -u "$ADMIN_USER:$ADMIN_PASS" \
    "$DM_SIGNAL_BASE_URL/api/monthly-returns/${pf_id}?years=5" \
    > "$WORK_DIR/monthly/${pf_id}.json"
  printf '%s\t%s\n' "$pf_name" "$pf_id" >> "$WORK_DIR/portfolio_map.tsv"
}

: > "$WORK_DIR/portfolio_map.tsv"
for pf in "${ALL_PFS[@]}"; do
  extract_monthly_returns "$pf"
done
```

### Step 4: 記事用の集計を作る

#### 4-1. 先月の確定リターン + YTD

```bash
fmt_pct='
  def pct:
    if . == null then "N/A"
    else (((. * 10000) | round) / 100 | tostring) + "%"
    end;
'

# メンバーシップPF: 先月確定 + YTD
: > "$WORK_DIR/membership_monthly.tsv"
for pf in "${MEMBERSHIP_PFS[@]}"; do
  pf_id="$(awk -F '\t' -v name="$pf" '$1 == name {print $2}' "$WORK_DIR/portfolio_map.tsv")"
  jq -r --arg name "$pf" --arg yr "$REPORT_YEAR" --arg mo "$REPORT_MON" "$fmt_pct
    .data.monthly_returns
    | sort_by(.year, .month)
    | {
        target: (map(select(.year == ($yr | tonumber) and .month == ($mo | tonumber))) | first // null),
        ytd: [.[] | select(.year == ($yr | tonumber) and .month <= ($mo | tonumber))]
      }
    | {
        name: \$name,
        month_return: (.target.portfolio.return // null | pct),
        ytd_return: (if (.ytd | length) > 0
                     then ([.ytd[].portfolio.return // 0] | map(. + 1) | reduce .[] as $x (1; . * $x) | . - 1 | pct)
                     else \"N/A\" end)
      }
    | [\$name, .month_return, .ytd_return]
    | @tsv
  " "$WORK_DIR/monthly/${pf_id}.json" >> "$WORK_DIR/membership_monthly.tsv"
done
```

#### 4-2. 四神12体: 先月確定 + YTD

```bash
: > "$WORK_DIR/shijin_monthly.tsv"
for pf in "${SHIJIN_PFS[@]}"; do
  pf_id="$(awk -F '\t' -v name="$pf" '$1 == name {print $2}' "$WORK_DIR/portfolio_map.tsv")"
  jq -r --arg name "$pf" --arg yr "$REPORT_YEAR" --arg mo "$REPORT_MON" "$fmt_pct
    .data.monthly_returns
    | sort_by(.year, .month)
    | {
        target: (map(select(.year == ($yr | tonumber) and .month == ($mo | tonumber))) | first // null),
        ytd: [.[] | select(.year == ($yr | tonumber) and .month <= ($mo | tonumber))]
      }
    | {
        month_return: (.target.portfolio.return // null | pct),
        ytd_return: (if (.ytd | length) > 0
                     then ([.ytd[].portfolio.return // 0] | map(. + 1) | reduce .[] as \$x (1; . * \$x) | . - 1 | pct)
                     else \"N/A\" end)
      }
    | [\$name, .month_return, .ytd_return]
    | @tsv
  " "$WORK_DIR/monthly/${pf_id}.json" >> "$WORK_DIR/shijin_monthly.tsv"
done
```

#### 4-3. 長期振り返り: 年次リターン(5年分)

```bash
: > "$WORK_DIR/annual_returns.tsv"
for pf in "${MEMBERSHIP_PFS[@]}"; do
  pf_id="$(awk -F '\t' -v name="$pf" '$1 == name {print $2}' "$WORK_DIR/portfolio_map.tsv")"
  jq -r --arg name "$pf" "$fmt_pct
    .data.monthly_returns
    | group_by(.year)
    | map({
        year: .[0].year,
        annual: ([.[].portfolio.return // 0] | map(. + 1) | reduce .[] as \$x (1; . * \$x) | . - 1)
      })
    | sort_by(.year)
    | map([\$name, (.year | tostring), (.annual | pct)])
    | .[]
    | @tsv
  " "$WORK_DIR/monthly/${pf_id}.json" >> "$WORK_DIR/annual_returns.tsv"
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

### Step 5: 市場情報を用意する（月間まとめ）

殿の市場メモがあるなら最優先。無ければ Grok `x_search` を使う。
週報と異なり、**月間を通した流れ・テーマ**として構成する。

#### 5-A. 市場メモがある場合

```bash
test -n "${MARKET_MEMO_FILE:-}"
cp "$MARKET_MEMO_FILE" "$WORK_DIR/market_source.md"
```

#### 5-B. 市場メモがない場合

5回に分けて取得: (1)月間マーケット概況 (2)要人発言月間まとめ (3)米国経済指標+セクター (4)日本月間まとめ (5)地政学月間まとめ

```bash
# 先月の名前（例: "2026年3月"）
MONTH_LABEL="${REPORT_YEAR}年${REPORT_MON#0}月"

# (1) 月間マーケット概況
cat > "$WORK_DIR/x_prompt_market.txt" <<EOF
日本語で、${MONTH_LABEL}の月間マーケット概況をまとめる。
対象: S&P500 / Nasdaq / 米国債(2y/10y/30y) / ドル円 / WTI / 金 / ビットコイン
全て月間変動（月初vs月末）で出すこと。週次・日次変動は不可。
月を通した大きな流れ・転換点を中心に書く。
投資助言表現は禁止。リンク不要。
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

# (2) 要人発言 月間まとめ
cat > "$WORK_DIR/x_prompt_officials.txt" <<EOF
日本語で、${MONTH_LABEL}の中央銀行・政府高官の重要発言をまとめる。
FRB議長、ECB総裁、日銀総裁、各国財務大臣など。
月を通した政策スタンスの変化・一貫性に焦点を当てる。
個別の日付の発言羅列ではなく、月間のトーンとして要約する。
投資助言禁止。リンク不要。3-5行で簡潔に。
EOF

curl -fsS https://api.x.ai/v1/responses \
  -H "Authorization: Bearer $XAI_API_KEY" \
  -H 'Content-Type: application/json' \
  -d "{
    \"model\": \"grok-4-1-fast\",
    \"input\": $(jq -Rs . < "$WORK_DIR/x_prompt_officials.txt"),
    \"tools\": [{\"type\": \"x_search\"}]
  }" \
  > "$WORK_DIR/x_officials.json"

jq -r '.output[] | select(.type == "message") | .content[] | select(.type == "output_text") | .text' \
  "$WORK_DIR/x_officials.json" > "$WORK_DIR/officials_source.md"

# (3) 米国: 経済指標 + セクター別パフォーマンス
cat > "$WORK_DIR/x_prompt_us_indicators.txt" <<EOF
日本語で、${MONTH_LABEL}の米国経済指標を月間まとめとして書く。
個別の日付の羅列ではなく、月を通した景気トーンの変化として構成する。

A. 主要経済指標（実績値と市場予想対比を明記）:
   - 雇用統計（非農業部門雇用者数NFP、失業率、平均時給）
   - CPI / コアCPI（前月比・前年比）
   - PPI / コアPPI
   - 小売売上高
   - ISM製造業景況指数 / ISM非製造業景況指数
   - GDP（発表があれば。速報/改定/確報を区別）
   - 住宅関連（着工件数、中古住宅販売、ケース・シラー等）
   - 消費者信頼感指数（Conference Board / ミシガン大）
   - PCE価格指数（FRBの最重要インフレ指標）
B. 政策動向（FOMC決定、議事要旨、FF金利、QT状況）
C. その他重要イベント（決算シーズン動向、財政政策等）

予想対比で「上振れ」「下振れ」「一致」を明記すること。8-12行。投資助言禁止。リンク不要。
EOF

curl -fsS https://api.x.ai/v1/responses \
  -H "Authorization: Bearer $XAI_API_KEY" \
  -H 'Content-Type: application/json' \
  -d "{
    \"model\": \"grok-4-1-fast\",
    \"input\": $(jq -Rs . < "$WORK_DIR/x_prompt_us_indicators.txt"),
    \"tools\": [{\"type\": \"x_search\"}]
  }" \
  > "$WORK_DIR/x_us_indicators.json"

jq -r '.output[] | select(.type == "message") | .content[] | select(.type == "output_text") | .text' \
  "$WORK_DIR/x_us_indicators.json" > "$WORK_DIR/us_indicators_source.md"

# (3b) 米国: S&P500セクター別月間パフォーマンス
cat > "$WORK_DIR/x_prompt_us_sectors.txt" <<EOF
日本語で、${MONTH_LABEL}のS&P500セクター別月間パフォーマンスをまとめる。
全11セクターの月間変動率を出すこと:
Technology / Healthcare / Financials / Energy / Consumer Discretionary /
Consumer Staples / Industrials / Materials / Utilities / Real Estate / Communication Services

構成: 上位3セクター（月間リターン順）と下位3セクター、そしてセクターローテーションの
月間テーマ（リスクオン/オフ、ディフェンシブ/シクリカルの動き等）を簡潔に。
5-8行。投資助言禁止。リンク不要。
EOF

curl -fsS https://api.x.ai/v1/responses \
  -H "Authorization: Bearer $XAI_API_KEY" \
  -H 'Content-Type: application/json' \
  -d "{
    \"model\": \"grok-4-1-fast\",
    \"input\": $(jq -Rs . < "$WORK_DIR/x_prompt_us_sectors.txt"),
    \"tools\": [{\"type\": \"x_search\"}]
  }" \
  > "$WORK_DIR/x_us_sectors.json"

jq -r '.output[] | select(.type == "message") | .content[] | select(.type == "output_text") | .text' \
  "$WORK_DIR/x_us_sectors.json" > "$WORK_DIR/us_sectors_source.md"

# (4) 日本 月間まとめ
cat > "$WORK_DIR/x_prompt_japan.txt" <<EOF
日本語で、${MONTH_LABEL}の日本経済・市場を月間まとめとして書く。
週ごとの羅列ではなく、月を通した大きなテーマ・転換点で構成する。

- 日経平均の月間変動（月初→月末、月中の高値・安値）
- TOPIX月間変動
- 主要経済指標（CPI/コアCPI、鉱工業生産、機械受注、貿易統計等。発表があったもの）
- 日銀政策・金利動向（政策金利、国債利回り、YCC関連）
- 月間のテーマ（円安/円高トレンド、セクター動向、海外投資家の売買動向等）

5-8行。投資助言禁止。リンク不要。
EOF

curl -fsS https://api.x.ai/v1/responses \
  -H "Authorization: Bearer $XAI_API_KEY" \
  -H 'Content-Type: application/json' \
  -d "{
    \"model\": \"grok-4-1-fast\",
    \"input\": $(jq -Rs . < "$WORK_DIR/x_prompt_japan.txt"),
    \"tools\": [{\"type\": \"x_search\"}]
  }" \
  > "$WORK_DIR/x_japan.json"

jq -r '.output[] | select(.type == "message") | .content[] | select(.type == "output_text") | .text' \
  "$WORK_DIR/x_japan.json" > "$WORK_DIR/japan_source.md"

# (5) 地政学 月間まとめ（多言語で双方の視点）
cat > "$WORK_DIR/x_prompt_geopolitics.txt" <<EOF
Search X in English, Arabic, and Farsi for major geopolitical events in
${MONTH_LABEL} that affected financial markets. Report both sides of any conflict.
Summarize as monthly themes, not weekly events. Focus on market impact.
3-5 bullet points. No links. Report in Japanese.
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

### Step 5-C: 当月の見込み情報を取得する

```bash
NEXT_MONTH_LABEL="${CURRENT_YEAR}年${CURRENT_MON#0}月"

cat > "$WORK_DIR/x_prompt_outlook.txt" <<EOF
日本語で、${NEXT_MONTH_LABEL}の金融市場の注目イベント・スケジュールをまとめる。
- FOMC/日銀会合の日程と市場の織り込み状況
- 主要経済指標の発表予定（雇用統計、CPI、GDP等）
- 決算シーズンの状況
- 地政学リスクの継続要因
3-5行で簡潔に。投資助言禁止。リンク不要。
EOF

curl -fsS https://api.x.ai/v1/responses \
  -H "Authorization: Bearer $XAI_API_KEY" \
  -H 'Content-Type: application/json' \
  -d "{
    \"model\": \"grok-4-1-fast\",
    \"input\": $(jq -Rs . < "$WORK_DIR/x_prompt_outlook.txt"),
    \"tools\": [{\"type\": \"x_search\"}]
  }" \
  > "$WORK_DIR/x_outlook.json"

jq -r '.output[] | select(.type == "message") | .content[] | select(.type == "output_text") | .text' \
  "$WORK_DIR/x_outlook.json" > "$WORK_DIR/outlook_source.md"
```

**重要**: Grokの出力をそのまま採用するな。x_searchの結果は素材。事実確認が取れたものだけ記事に採用する。

### Step 6: 月報を書く

**全セクション■箇条書き。表組禁止。リンク不要。**

以下のテンプレートで `OUT_FILE` を作る。

```markdown
# DM-Signal Monthly — {{PUBLISH_MONTH}}

## {{PUBLISH_MONTH_LABEL}} の見込み

■ {{FOMC/日銀会合の日程と市場の織り込み状況}}
■ {{主要経済指標の発表予定}}
■ {{決算シーズンの状況}}
■ {{地政学リスクの継続要因}}

---

## {{REVIEW_MONTH_LABEL}} マーケット振り返り

■ S&P500 月間X.X%（月初XXXX→月末XXXX）、NASDAQ 月間X.X%
■ 米2年債 X.XX%→X.XX%（Xbp）、10年債 X.XX%→X.XX%（Xbp）、30年債 X.XX%→X.XX%
■ ドル円 XXX.XX→XXX.XX（月間X.X%）、WTI 月間X.X%、金 月間X.X%、BTC 月間X.X%
■ {{月を通した大きなテーマ — 1-2行で}}

## 要人発言

■ {{中央銀行・政府高官の月間トーン。政策スタンスの変化や一貫性}}
■ {{月間を通した金融政策の方向感}}

## 米国経済指標

■ 雇用: NFP X.Xk（予想Xk）、失業率X.X%（前月X.X%）、平均時給 前年比X.X%
■ インフレ: CPI 前年比X.X%/コアX.X%（予想X.X%）、PCE X.X%/コアX.X%、PPI X.X%
■ 景況感: ISM製造業XX.X（前月XX.X）、ISM非製造業XX.X、消費者信頼感XX.X
■ 消費: 小売売上高 前月比X.X%（予想X.X%）
■ 住宅: {{着工件数・中古販売等、発表があれば}}
■ GDP: {{発表があれば。速報/改定/確報を区別}}
■ FOMC: {{政策金利決定・議事要旨のポイント}}
■ {{月間の景気トーン — 上振れ/下振れの全体像を1-2行で}}

## 米国セクター

■ 上位: {{1位セクター名 月間+X.X%}} / {{2位}} / {{3位}}
■ 下位: {{ワースト1位 月間-X.X%}} / {{2位}} / {{3位}}
■ {{セクターローテーションのテーマ — リスクオン/オフ、ディフェンシブ/シクリカルの動き}}

## 日本

■ 日経平均 月初XX,XXX→月末XX,XXX（月間X.X%）、月中高値XX,XXX / 安値XX,XXX
■ TOPIX 月間X.X%
■ {{主要経済指標 — CPI、鉱工業生産、機械受注、貿易統計等。発表があったもの}}
■ {{日銀政策・金利動向}}
■ {{月間のテーマ — 円安/円高、海外投資家動向等}}

## 地政学

■ {{月間の地政学テーマ。マーケット影響に絞って。双方の視点}}

---

## メンバーシップPF — {{REVIEW_MONTH_LABEL}} 確定

■ DM-safe {{M月}}X.XX%（YTD X.XX%）
■ DM-safe-2 {{M月}}X.XX%（YTD X.XX%）
■ 劇薬DMスムーズ {{M月}}X.XX%（YTD X.XX%）
■ 劇薬DMオリジナル {{M月}}X.XX%（YTD X.XX%）
■ Ave-X {{M月}}X.XX%（YTD X.XX%）
■ 裏Ave-X {{M月}}X.XX%（YTD X.XX%）
■ (SPY) {{M月}}X.XX%（YTD X.XX%）

---

## 四神12体 — {{REVIEW_MONTH_LABEL}} 確定

■ 青龍 激攻X.XX% / 鉄壁X.XX% / 常勝X.XX%（YTD: X.XX% / X.XX% / X.XX%）
■ 朱雀 激攻X.XX% / 鉄壁X.XX% / 常勝X.XX%（YTD: X.XX% / X.XX% / X.XX%）
■ 白虎 激攻X.XX% / 鉄壁X.XX% / 常勝X.XX%（YTD: X.XX% / X.XX% / X.XX%）
■ 玄武 激攻X.XX% / 鉄壁X.XX% / 常勝X.XX%（YTD: X.XX% / X.XX% / X.XX%）

---

## 長期パフォーマンス（年次リターン）

■ DM-safe — {{Y-4年}}X.XX% / {{Y-3年}}X.XX% / {{Y-2年}}X.XX% / {{Y-1年}}X.XX% / {{Y年}}YTD X.XX%
■ DM-safe-2 — {{同上}}
■ 劇薬DMスムーズ — {{同上}}
■ 劇薬DMオリジナル — {{同上}}
■ Ave-X — {{同上}}
■ 裏Ave-X — {{同上}}
■ (SPY) — {{同上}}

---

## 将軍の短観

**将軍口調で書く**（〜でござる、〜なり、〜されたし、〜にあらず 等）。全データを読んだ読者への締め。

■ {{メンバーシップ6PFの月間総括。SPY対比・前月対比。将軍口調}}
■ {{四神12体の月間総括。注目の動きを2-3体ピックアップ。将軍口調}}
■ {{長期視点: 年次リターンの推移から見える傾向。将軍口調}}
■ G1（短期トレンド）: {{APIのg1_slope_12から読み取れる所見。将軍口調}}
■ G2（長期ドリフト）: {{APIのg2_p_erosion_12から読み取れる所見。将軍口調}}
■ P(det)（弱体化確率）: {{APIのp12から。ラベル変化があれば言及。将軍口調}}
■ {{当月への展望 — 見込みセクションのデータを踏まえて1-2行。将軍口調}}

---

*Data: DM-Signal ({{データ日付}}) / 投資助言ではありません*
```

**書き方の注意**:
- タイプ分類（守り型/攻め型等）を書かない
- 対象PF以外（bam-2等）を載せない
- DM-signal UIやDocsにない情報を書かない
- Grokの出力を鵜呑みにしない
- ニュースは月間のテーマ・流れで書く。週ごとの羅列は不可
- 長期パフォーマンスのデータが5年に満たないPFは、データがある年のみ記載

### Step 7: 最終検査

保存後、以下を満たすか確認する:

```bash
test -f "$OUT_FILE"
rg -n "買い|売り|目標株価|エントリー推奨|おすすめ" "$OUT_FILE" && echo "NG: advice wording"
```

目視確認:

- 11セクション構成か（マーケット振り返り/要人発言/米国経済指標/米国セクター/日本/地政学/メンバーシップPF/四神12体/長期パフォーマンス/当月見込み/将軍の短観）+免責
- メンバーシップ6PF+SPYと四神12体が全て載っているか
- **表組が一切ないか**（■箇条書きのみ）
- タイプ分類（守り/攻め/バランス）が残っていないか
- 範囲外PF（bam-2等）が混入していないか
- リンクが残っていないか
- **指数が月間変動になっているか**（日次・週次になっていないか）
- **ニュースが月間まとめになっているか**（週ごとの羅列になっていないか）
- UIやDocsにない独自解釈が混入していないか
- raw signal / ticker / weight が記事本文に出ていないか
- YTDと年次リターンが正しく計算されているか
- 出力先が `monthly_report/YYYY-MM_monthly.md` になっているか

## トラブル時

- `401 Invalid authentication credentials`
  - `backend/.env` の `ADMIN_USER` `ADMIN_PASS` を確認する
- `jq: Cannot iterate over null`
  - API が失敗して HTML/401 を返していることが多い。先に `curl -i` でヘッダを見る
- X検索が空
  - `config/xai_api.env` の `XAI_API_KEY` を確認する
  - `model` は `grok-4-1-fast`、`tools` は `[{"type":"x_search"}]` を維持する
- 5年分のデータがないPF
  - PF作成日以降のデータのみ存在。データがある年のみ記載する

## 完了条件

- `OUT_FILE` が生成されている
- 11セクション構成（マーケット振り返り/要人発言/米国経済指標/米国セクター/日本/地政学/メンバーシップPF/四神12体/長期パフォーマンス/当月見込み/将軍の短観）+免責
- 米国経済指標に主要指標（NFP/CPI/PCE/ISM/小売/住宅等）の実績値と予想対比が含まれているか
- 米国セクターに上位3+下位3セクターとローテーションテーマがあるか
- 全セクション■箇条書き（表組なし）
- signals / monthly-returns(5年) / deterioration / x_search を全て使用している
- ニュースが月間まとめとして書かれている（週次羅列ではない）
- 長期パフォーマンスに年次リターンが含まれている
- 当月見込みセクションがある
- 構成ティッカーが本文に出ていない
- リンクが本文に出ていない
- 指数が月間変動になっている
