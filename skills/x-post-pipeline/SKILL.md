---
name: x-post-pipeline
description: |
  What: X(@TokyoJibika)運用の自動化 v2(2026-09-04 殿裁定)。方針=「投資を数学・確率・検証で考える人のアカウント。その人が作っているものがDM-Signal」。
  stock_ledger.yaml(64本、category A-G+shift)、slot_calendar.yaml(平日08:30/18:30×5=週10、2週20slotのA→G ローテ)、system_prompt_v5_1.txt(本人 author corpus 優先)、
  x_post.sh(draft→gate→approve→post、token keeper)、queue/x_rewrites/(殿の添削=最優先教師データ)、docs/research/x_corpus/(本人 X 967件+note 64記事)を使う。
  TRIGGER: /x-post-pipeline、X投稿の下書き作成、殿の添削の保存、投稿ストックの投稿、台帳・calendar の参照、X token/認可
  DO NOT TRIGGER: note記事本体の編集、dm-signal側の変更
allowed-tools:
  - Read
  - Bash
---

# X Post Pipeline (v2 — author corpus 段階)

正本の順序: 方針 `docs/research/x_editorial_doctrine_20260904.md` → 設計書 `docs/research/x_account_ops_automation_asis_tobe_5w1h_20260903.md` §16/§17 → 分析 `docs/research/x_author_corpus_analysis_20260904.md` → 本 SKILL。

## What
- `stock_ledger.yaml`: 記事 1 件=1 entry(url/title/published/usable_numbers/**category A-G**/**shift=起こす認識変化**)。frames は旧枠の残骸で参照しない。
- `slot_calendar.yaml` v2: 平日 08:30/18:30 JST ×5=週 10 slot、2 週 20 slot で 1 周。A 常識を壊す/B DM 啓蒙/C 検証至上/D 数学小ネタ/E そこまで疑うか検証/F DM-Signal 検証・実績(15%)/G 直接誘導(5%)。各 slot に shift/question/ledger_key。
- `system_prompt_v5_1.txt`(x_post.sh 既定): 教師データ優先順位=殿の添削(`queue/x_rewrites/*.yaml`) > 本人 X(`docs/research/x_corpus/x/`) > note ショートコラム > How to > prompt。Voice(X: 口語言い切り 56%/です・ます 35%、僕、改行 2 回、数字は 1 組)と Reasoning(note: 他人の言葉→疑い→設計→数字→短い解釈)を分けて合成。negative patterns、語彙の層(抽象名詞はカタカナ、指標は英語略号、動作は和語口語)、数字 fail-close。
- `x_post.sh draft <slot A-G> <ledger_key>` → `gate <draft_id> <slot>` → `approve <draft_id>`(要操作 topic へ ntfy_action、殿 y で `.approved`)→ `post <draft_id> [--media png]`(post 前に `x_token_refresh.py` 必須、成功時に rotate した token を env へ永続化)。
- `x_post_gate.sh <file> <slot>`: Rule 1 ticker/Rule 2 単独倍率(下落・損失文脈は除外)/Rule 3 URL/Rule 4 免責があれば FAIL/Rule 5 禁止語(株と債券・現金に退避 含む)/Rule 6 内部用語/Rule 7 分類別の宣伝混入(A-E に DM-Signal・Basic・プラン・登録で FAIL、F に登録・料金・無料で FAIL)。
- token: `x_token_keeper.sh`(cron */30)が refresh を無人で回す。3 回失敗で PKCE URL を生成し listener(`x_oauth_listener.py`、置換方式で env 更新)を立て、要操作 topic へ 1 回送る。**env の X_REFRESH_TOKEN は必ず 1 行**(T3-S-65: 旧行で refresh すると X が grant を revoke する)。
- corpus: `note_corpus_fetch.py`(note API→docs/research/x_corpus/note/)、`x_fetch_author_corpus.py`(X API、public_metrics 付き)、`x_corpus_via_grok.py`(Grok x_search、月次窓)。
- 添削の保存: `queue/x_rewrites/_template.yaml` の形(original_llm/human_rewrite/delta_notes/tags/kpi)。殿版と無修正承認(approved_as_is)を区別する。
- 投稿ストック: `queue/x_drafts/<date>_R<round>-<slot>-<n>.txt` + `.approved`。gate PASS 済みのみ。
- レビュー面: `scripts/x_drafts_render.py <md> <html> <title>` → artifact(殿の直しはコメント→`Artifact comments` で読む)。

## Growth Engine(v1、2026-09-04 14:51 殿指示。Content Engine の上位)
- 定義: `growth_schema.yaml`(funnel_stage reach/follow/trust/convert、audience 5 段、topic ladder 7 段、metadata schema、初期配分 reach 8/follow 4/trust 6/convert 2 を 4 週固定、series trust_system 9 本、Reach 素材 R01-R10、Conversation Entry、KPI 取得可否)。設計書 `docs/research/x_growth_engine_asis_tobe_5w1h_20260904.md`。
- 付与: `python3 scripts/x_ops/x_growth_tag.py` が `queue/x_rewrites/R4-*.yaml` へ `growth:` を書き、`queue/x_live_oos/ledger.yaml` へ事前 metadata を登録する。
- 定時投稿: `scripts/x_ops/x_slot_post.sh`(cron 平日 08:30/18:30 JST)が slot_calendar の順(pointer=queue/x_live_oos/slot_pointer.txt)で承認済み未投稿 draft を 1 本投稿し台帳へ post_id を書く。在庫が無い slot は繰り下げ+ntfy。
- 計測: `scripts/x_ops/x_kpi_snapshot.py`(cron 毎時 15 分)が 24h/7d に public+non_public(profile_clicks/link_clicks)を台帳へ書き、followers 日次を `account_daily.jsonl` へ。推測値は書かない。投稿別 follow・note PV は取得不能。
- v1.1(15:01): 第 3 マガジン m8357970d6430『俺たちはどう生き延びるか』63 本=Reach 一次資料(`docs/research/x_corpus/note/m8357970d6430/`)。3 軸=content_category×funnel_stage×content_lane(9)。entry lane 5・bridge 6・series 候補 5・hook_type に story/scenario/irony。ブランド=『数字を見て生き延びる方法を考える人。投資は DM、実装が DM-Signal』。Reach 投稿単体で DM-Signal へつなげない。バム persona(ヤーマン)は note 専用。
- v1.2(15:11 殿裁定): 4 format=Short(発見)/Long(信頼)/Thread(会話・深読み。x_post.sh post <draft> --reply-to <parent_id>)/Series Entry(フォロー・再接触)。content_units と physical_posts を分ける。calendar に format 列(08:30 Short、火木 18:30 Long、水 Thread、金 Series)。台帳=queue/x_live_oos/{ledger,thread_ledger,series_ledger}.yaml、format 別集計=x_kpi_snapshot.py --summary。事前登録が正本、事後付け替え禁止。
- v1.3(16:07 殿裁定): KPI は kpi_availability.yaml の 4 状態(observable_post_level / observable_account_level / external_attribution / unavailable)で管理。0 と null を混ぜない(null=取得不能/帰属不能、np_null_reason 併記)。投稿別 follow・非フォロワー imp・dwell・note PV/post は unavailable。follow は account_daily の followers_delta_day/week のみ。DM-Signal 直リンクは campaign_id(作成時発行)で external_attribution(showcase_events 拡張、未実装)。分析は Observed/Inferred/Unavailable を分け、因果を断定しない。
- 禁止: 40 投稿貯まるまで比率・型の最適化をしない。Growth のために本文を書き換えない。自動 reply spam。

## When
- 新しい下書きを作る時: slot_calendar の shift/question と ledger の usable_numbers を渡し、v5.1+添削 few-shot で生成→gate→artifact で殿確認→添削を保存→ストックへ。
- 殿の添削が来た時: `queue/x_rewrites/` に保存し、差分の規則を分析 §12/§13 と v5.1 に足す。
- 投稿する時: slot 順に `x_post.sh post`。post 前 refresh は自動。失敗時は keeper のログ `logs/x_token_keeper.log`。

## NOT When
- 未登録の数字(分析 §9 の一覧)を本文に入れない。記事本文にあっても台帳に無ければ使わない。
- 株・債券・現金・特定 ETF で仕組みを具象化しない(候補/退避先の抽象で書く)。
- A〜E で DM-Signal を主語にしない。免責・言い訳・「月 1 回見るだけ」・Basic 説明を書かない。
- 本人の文体を想像しない。X の実例と殿の添削を読んで合わせる。
- 本番 token に対して新しい token 操作を手動で試さない(fixture で回す)。
