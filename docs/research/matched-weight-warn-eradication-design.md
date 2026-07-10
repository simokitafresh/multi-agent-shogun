# Matched weight WARN根絶設計書 v1.0

- 起票: 将軍 2026-07-10 03:17 | 殿指摘「変わらずwarningがlogに表示されている。解決方法を覚醒して設計書にまとめよう」
- 対象WARN: `WARNING:app.services.monthly_trade_impl:Matched weight X != 1.0, missing_tickers=[...]`
- origin: `[[殿観測20260709_2359_matched_weight_WARN]] -> [[修正3本実装済み未反映]] -> [[warn-eradication-design]]`

## §0 覚醒ポイント（なぜ「変わらず」出ているのか）

**修正は3本とも実装完了している。しかし1本も本番に届いていない。**
cmd_3812は旧§42「殿個別裁可待ち」で push/deploy/再backfill を全て保留したまま報告完了しており（成果物に "pending individual Lord approval per §42" と明記）、殿裁定（02:41/02:46 裁可不要・CI同期待ち不要）の改定が実行中タスクに伝播していなかった。**実装+commit=完了ではない。本番プロセスに乗り、WARN件数=0を計測して初めて完了**（既知教訓「デプロイまで終わってるか？」と同型）。

## §1 As-Is — WARNの3根因と修正状態

| 層 | 根因 | 修正 | 状態 |
|---|---|---|---|
| データ層 | ledger historical_backfillが`decision_ticker_weights`を保存せず、monthly_returns生成が文字列を等ウェイト展開→band月の50/50構成が破壊され、weights合計が0.5等になる | cmd_3812: weights保存+復元実装（テスト73 passed） | **commit 8fc49267のみ。push/deploy/weights付き再backfill/部分再計算 全て未実施** |
| 表示層 | FoF表示展開(`monthly_trade.py:281-294`)が`expanded_tickers`書き換え後に`matched_weight`を再計算せず、古い中間値でガードが偽陽性発火 | cmd_3810: 表示基準再計算+回帰テスト | push済み(52b53017)だが**本番deploy未確認** |
| ログ層 | WARNにPF・年月・weights内訳がなく診断が遠回り | cmd_3810: ログ文脈強化 | 同上 |

- 副次: cmd_3814のGS DTB3修正(fa37c921)もローカルcommitのみ（mainがorigin比 ahead 2）。GS側のみで本番挙動には無関係だがpushは同時に済ませる

## §2 To-Be

- **完了定義: 本番fullrecalculate（または全量precompute）1回の実行ログで `Matched weight` WARN件数=0** をgrepで数値証明
- ガードのfail-closed性は維持（真のticker欠落時はNone+WARN。これは残すべき正当なWARN）

## §3 根絶手順（全て可逆=自走。§42v2適用）

1. **push**: DM-Signal main残り2 commits（cmd_3813記録+cmd_3814 GS修正）+cmd_3812/3810分をorigin/mainへ。CI起動はするが**同期待ちしない**（LK078。CI確認は家老が非同期でgh run view）
2. **deploy**: Render自走deploy→ヘルスチェック（/admin/recalculate-status応答+主要API 200）。失敗即revert
3. **データ修正**: ledger対象行バックアップ（退避行数の数値確認）→band適用24PFの**weights付き再backfill**→対象PFのみ部分再計算→DB直接クエリでcompleted確認（L714/715）
4. **12体再突合**: cmd_3803方式。期待値=玄武-常勝2023-12（DTB3・GS側要因=本番無関係）以外の**全乖離解消**
5. **WARN=0計測**: 手順3の部分再計算ログ（+次回cron全量再計算ログ）で`Matched weight`件数をgrep集計→**0件を数値記録**。0でなければ残存パターンを分類し本設計書を改定
6. **恒久監視**: ✅完了(cmd_3820, 2026-07-10 09:17 CLEAR) — run単位のmatched_weight_warn_countを再計算完了ログへ記録し、1件以上で[MATCHED WEIGHT WARN] ntfy通知(0件は抑制)。deploy済み(commit a74ad188, dep-d982ekp Live)。本番実運転で count=0+通知抑制の動作を実証済み(2026-07-09 23:38Z precompute 102PF rows=1533)

## §4 実行割当

- 手順1-5 = **cmd_3812の残AC（AC2/AC3）そのもの**。新cmd不要。家老へ§42v2適用で即続行を指示（kagemaruがrate limit時は別忍者へcommit 8fc49267+報告YAML注入で引き継ぎ）
- 手順6 = 小粒の新cmd（WARN件数監視の環境埋め込み）。手順5の結果を見て起票

## §5 再発防止（本事故の教訓）

- **裁定改定は実行中タスクへ即push型で伝播させる**: 恒久ルール改定時、将軍はcontext正本更新だけでなく、当該ルールを参照して保留中のタスク（grep: 保留/pending/裁可待ち）を洗い出しtask_supplementで解除通知する。今回それを怠り、§42改定後もcmd_3812が旧ルールで停止し続けた
- lesson_candidate: 「ルール改定時は正本更新+実行中タスクの保留解除通知をセットで行う。改定が届かない保留は洗脳#5の温床」

## 因果リンク

- [[殿裁定20260710_0241_可逆なら行動せよ]] -> [[cmd_3812旧§42で停止]] -> [[改定の実行中タスク伝播漏れ]]
- [[cmd_3810表示層修正]] + [[cmd_3812データ層修正]] -> [[deploy+再backfill+WARN0計測]] -> [[WARN根絶]]
