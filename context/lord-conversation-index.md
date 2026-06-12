# Lord Conversation Index
<!-- last_updated: 2026-06-13 cmd_karo_hotfix_context_freshness_alerts_20260613 -->
<!-- generated_by: scripts/conversation_retention.sh -->
<!-- generated_at: 2026-06-13T01:09:45+09:00 -->

## 最新やり取り（直近24h）
- 2026-06-13T01:09:26+09:00 | terminal | inbound | マージ許可する
- 2026-06-13T01:08:14+09:00 | ntfy | outbound | 【軍師CRITICAL】先送り3セッション連続検出。起動は許可するが即対処必須
- 2026-06-13T01:07:40+09:00 | ntfy | outbound | 【家老】cmd_karo_hotfix_context_freshness_alerts_20260613 初回配備開始 (title=(untitled), ninja=kagemaru)
- 2026-06-13T01:03:17+09:00 | terminal | inbound | すぐやれ
- 2026-06-13T01:02:08+09:00 | ntfy | outbound | 【INFOバッチ】 2026-06-13 00:53:38|cmd_karo_hotfix_speed_pre_write_edit_20260613 2026-06-13 00:55:07|cmd_karo_hotfix_speed_s…
- 2026-06-13T01:00:19+09:00 | terminal | inbound | 確認したのか？
- 2026-06-13T00:59:31+09:00 | terminal | inbound | よい
- 2026-06-13T00:57:10+09:00 | terminal | inbound | 結局idle忍者は何名だ？
- 2026-06-13T00:57:05+09:00 | ntfy | outbound | 📊 Dashboard更新: 稼働4名 CLEAR率99% 連勝90
- 2026-06-13T00:56:13+09:00 | ntfy | outbound | 📊 Dashboard更新: 稼働4名 CLEAR率99% 連勝89

## 未解決確認事項
- 【SessionEnd ALERT】/clear前確認で問題検出 agent=shogun issues=clear_prep_check ALERT 殿の言葉 inbound=97件 clear_prep_check=ALERT [G0.殿/clear指示] WARN: 直近…
- **処理完了。家老の自走hotfix「startup_lesson_skill_health」のGATE CLEAR通知であった。** 将軍startup gateの教訓・スキル健全度系の残項目を家老が自前で塞いだもの（本日の家老自走hotfixはこれで8本目）。確認・既読化済…
- **軍師の掲示板、確認して行動まで完了した。内容は「スクリプト速度改善提案Top10」— 全10件を取りこぼしなく処理した。** ## 軍師の投稿（blt_20260612_205402） hookコストの効果量（頻度×実行時間×重要度）ランキング。セッション合計約81秒のレイ…
- kotaro review完了確認。既にreview_log記録+karo送信済み。GATE CLEARも反映済み。 全処理完了。idle待機。 [meta] stop_reason=end_turn
- lefthook管理。lefthook.ymlで検査が接続されているか確認する。 [meta] stop_reason=tool_use
- cmd_3335とcmd_3336のバックグラウンドレビューの完了を確認してからgate_result更新する。レビュー未完の場合はレビュー完了後にまとめてgate-sync。 バックグラウンドエージェントの完了通知を待つ。idle待機。 [meta] stop_reason=…
- 変更内容を確認。`CMD_SAVE_PREFLIGHT_ONLY`フラグでwrite系操作をガードしている。silent_failureパターンの観点: 1. **preflight時にCMD_BLOCK_CACHEを書き換え**: depends_on/originが未記入の…
- 【SessionEnd ALERT】/clear前確認で問題検出 agent=shogun issues=clear_prep_check ALERT 殿の言葉 inbound=57件 clear_prep_check=ALERT [G0.殿/clear指示] WARN: 直近…

## 殿の直近裁定・方針（直近24h）
- 該当なし

## 参照cmd
- cmd_3
- cmd_2818
- cmd_2920
- cmd_3222
- cmd_3298
- cmd_3300
- cmd_3302
- cmd_3305
- cmd_3306
- cmd_3307
- cmd_3308
- cmd_3309
- cmd_3310
- cmd_3311
- cmd_3312
- cmd_3313
- cmd_3314
- cmd_3315
- cmd_3316
- cmd_3317
- cmd_3318
- cmd_3319
- cmd_3320
- cmd_3321
- cmd_3322
- cmd_3323
- cmd_3324
- cmd_3325
- cmd_3326
- cmd_3327

## 参照先
- `queue/lord_conversation.jsonl`（一次データ）
- `logs/lord_conversation_archive/*.jsonl`（24h超過・200件超過の退避先）
