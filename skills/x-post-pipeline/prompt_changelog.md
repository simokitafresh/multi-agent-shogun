# X 投稿パイプライン prompt/生成器 変更記録

殿指示 2026-09-04 18:55 §19: 実装が動いたら細かい違和感で毎日 system prompt を変えない。変更は理由付きでここに記録する。大きな方針変更は本人が実際に使って明確なズレを感じた時だけ。

| 日時 | 対象 | 変更 | 理由(殿の言葉) |
|---|---|---|---|
| 2026-09-04 14:38 | system_prompt v5→v5.1 | conversation gap/fact≠completeness/説明しすぎ禁止/Fact・Voice 分離 | 殿『少し荒い方が隙が出来てプラス』 |
| 2026-09-04 17:47 | x_round5_gen.py | 記事本文入力を廃止、neta_ledger 必須(rc=2) | 殿『記事の抜粋、使えるネタが 0』 |
| 2026-09-04 18:29 | x_claim_gen.py 新設 | claim_bank 1 行→Short、記事本文を渡さない、数字 fail-close | 殿『俺が何もしなくても無限に生成し続けるから意味がある』 |
| 2026-09-04 18:55 | x_claim_gen.py / claim_bank.yaml / slot_calendar v5 | 必須 4 項(belief/claim/why/audience)欠落は SKIP、`--format long`(claim→疑い→検証→数字→結論)、slot instruction に外部 Voice 移植禁止、18:30 の Series 連続を解除 | 殿『記事から投稿を作るな。ネタから投稿を作れ。外部バズから本人を作るな』 |

system prompt 本体(v5.1)は 18:55 で変更していない。
| 2026-09-04 19:14 | claim_bank.yaml / x_claim_gen.py / ledger | origin 必須(human_seed>existing_user_thesis>dm_signal_result>external_topic)、external_topic は ext_gate A-E+context 必須で無ければ SKIP、context(why_now)を発話動機として生成器へ渡す、quality 4 点(low/mid/high)、ledger に claim_origin、claim_candidates.yaml(viral=センサー)と claim_corrections.yaml(claim correction 保存)新設 | 殿『claim_bank を次の切り抜き工場にしない。外部バズは世間が何を気にしているかのセンサー』。system prompt v5.1 は不変 |
| 2026-09-04 19:28 | x_plan_calendar.py / x_claim_gen.py / ledger | format→stage/audience/hook/category の固定 mapping 撤廃、plan の editorial metadata を正本(欠落は SKIP)、empty slot 正式化、reuse_of/reuse_reason、Stage 1 承認なしで生成拒否、台帳に plan_id/event | 殿『カレンダーを埋めるな。編集計画を作れ』 |
| 2026-09-04 19:33 | event_rules.yaml / x_event_scan.py / x_claim_gen --event / poster v1.8 | イベント lane(予定+突発)。イベントは context、claim は bank から | 殿『event-driven も設計して実装しよう』 |
| 2026-09-04 19:45 | event_rules.yaml / x_event_scan.py | 為替・米 2y/10y・カーブ・JGB10・BEI trigger 追加、CPI 予定(要日付確認) | 殿『USD/JPY 急変 米 2 年/10 年金利 日本 10 年 金利カーブ あとはインフレ』 |
| 2026-09-04 19:52 | x_event_scan.py --intraday / x_topic_scan.py / event_rules | 為替・SPY 日中監視(30 分)、要人発言 topic 検知(毎時、X API counts)、Grok は context 要約のみ | 殿『為替はリアルタイムじゃないと変。要人発言のトピックも欲しい』 |
| 2026-09-05 01:35 | event_rules.yaml market_context / x_event_scan.py / claim_bank C35-C38 | 為替・金利を常時観測対象として記録+週次表、event context に市場環境 1 行、本人思想適用 claim 4 本(human_seed) | 殿『trigger を増やさず Market Context として常時観測。予測ではなく分解・観測・検証』 |
