# Lord Conversation Index
<!-- last_updated: 2026-06-11 auto-generated -->
<!-- generated_by: scripts/conversation_retention.sh -->
<!-- generated_at: 2026-06-11T00:19:40+09:00 -->

## 最新やり取り（直近24h）
- 2026-06-11T00:19:31+09:00 | terminal | response | Top5全てdm-signal教訓。GA-038(infra系hotfix)報告にdm-signal教訓10件が注入され全部useful=false=**project fallbackの誤マッピング**疑い。タスクYAMLで確認。 [m…
- 2026-06-11T00:19:25+09:00 | ntfy | outbound | 【将軍】context鮮度ALERT: cmd-chronicle.md(source更新),memory-db-schema.md(source更新)
- 2026-06-11T00:15:59+09:00 | terminal | response | チェックはバックグラウンド実行中。並行してinboxを処理する。 [meta] stop_reason=tool_use
- 2026-06-11T00:13:57+09:00 | terminal | session_summary | 殿指示: CLI最新版切替(Fable5)/Gmail証票投入はCMDで/起票摩擦の分析と劣化LLM対策(雛形+gate FP根治5件)/洗脳監査(質問形範囲縮小=LS052)/kagemaru遅すぎ→真因gws cold start直列…
- 2026-06-11T00:12:46+09:00 | ntfy | outbound | 教訓効果率ALERT: 100.0%
- 2026-06-11T00:08:41+09:00 | terminal | inbound | 今クリアされても今より強くてニューゲームできるようにせよ
- 2026-06-11T00:08:11+09:00 | terminal | inbound | 今クリアされても今より強くてニューゲームできるようにせよ
- 2026-06-11T00:08:04+09:00 | terminal | inbound | いまクリアされても今より強くてニューゲームできるようにせよ
- 2026-06-11T00:04:12+09:00 | ntfy | outbound | 【monitor】将軍CTX:55%。/compactをご検討ください
- 2026-06-10T23:33:23+09:00 | ntfy | outbound | 【monitor】将軍CTX:55%。/compactをご検討ください

## 未解決確認事項
- Top5全てdm-signal教訓。GA-038(infra系hotfix)報告にdm-signal教訓10件が注入され全部useful=false=**project fallbackの誤マッピング**疑い。タスクYAMLで確認。 [meta] stop_reason=too…
- 家老確認完了。gate再実行でALERT解消確認、L771登録済み。idle待機。 [meta] stop_reason=tool_use
- 報告完了。 --- **作業完了サマリ** **AC1** PASS — `context/dm-signal-research.md` に §38を追記。cmd_3218/3220/3224の主要結果を索引層スタイル(結論1-2行+参照先)で反映。last_updated: …
- 殿、報告する。 ## 記憶DBは無傷だった——真因はcacheの作り方 家老の調査結果: 正本・cache共に`quick_check=ok`、**破損なし・復旧不要**。22:27のmalformedは、semantic_search独自のcache更新が生`cp`でDB本体…
- cmd_3276 draftレビュー完了。**verdict=APPROVE**(confidence HIGH)。 **実測検証(4点一致):** - shortage_list=35件 / monthly_status.memo列実在 / 294セル全not_obtaine…
- **cmd_3276 完了。** 全AC PASS、gate PASS、家老へ報告済み。idle待機に入る。 ## 結果サマリ | AC | 結果 | 証拠 | |----|------|------| | AC1 パース分類 | ✅ | 35通 = own_list 2 / …
- saizoがbody_snippetの実態を自分で照会中=補足が効いている（snippet切断を自ら確認してから全文取得設計に進む流れ）。 軍師補足2点（snippet切断=全文取得必須/非リストメール混在=パース不能分類が実発動）をsaizoへ伝達済み。軍師のdraftレビュ…
- どのWARNがカウントされたか全文で確認する。 [meta] stop_reason=tool_use

## 殿の直近裁定・方針（直近24h）
- 該当なし

## 参照cmd
- cmd_326
- cmd_327
- cmd_3218
- cmd_3219
- cmd_3231
- cmd_3244
- cmd_3245
- cmd_3267
- cmd_3268
- cmd_3269
- cmd_3270
- cmd_3271
- cmd_3272
- cmd_3273
- cmd_3274
- cmd_3275
- cmd_3276

## 参照先
- `queue/lord_conversation.jsonl`（一次データ）
- `logs/lord_conversation_archive/*.jsonl`（24h超過・200件超過の退避先）
