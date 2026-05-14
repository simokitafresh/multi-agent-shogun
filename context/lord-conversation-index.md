# Lord Conversation Index
<!-- last_updated: 2026-05-14 auto-generated -->
<!-- generated_by: scripts/conversation_retention.sh -->
<!-- generated_at: 2026-05-14T15:25:37+09:00 -->

## 最新やり取り（直近24h）
- 2026-05-14T15:25:36+09:00 | terminal | response | 殿、**cmd_2719 GATE CLEAR**。FEユニットテスト導入完了。 **本セッション成果**: | cmd | 内容 | 状態 | |-----|------|------| | cmd_2720 | 遡及学習BLOCK軽量…
- 2026-05-14T15:20:10+09:00 | ntfy | outbound | 【将軍】context鮮度ALERT: doc-style-guide.md(35日),growth-loop.md(23日),gs-speedup-knowledge.md(24日),gstack-knowledge.md(35日),g…
- 2026-05-14T15:16:43+09:00 | ntfy | outbound | 【家老】cmd_2719 初回配備開始 (title=整備 — FEユニットテスト導入(Vitest+Testing Library)(P2-5), ninja=kagemaru) 整備 📋 https://gist.github.com…
- 2026-05-14T15:15:50+09:00 | terminal | response | 殿、本セッションの成果を報告する。 **完了cmd**: | cmd | 内容 | 状態 | |-----|------|------| | cmd_2720 | infra改善 — 遡及学習BLOCK軽量ack機構 | **CLEAR*…
- 2026-05-14T15:13:36+09:00 | ntfy | outbound | 【家老】cmd_2720 完了 📋 https://gist.github.com/simokitafresh/6eb495d917fb00ba4d4333c237a4ee0c
- 2026-05-14T15:13:14+09:00 | terminal | inbound | 再起票しよう
- 2026-05-14T15:13:03+09:00 | terminal | response | 殿、**cmd_2720 GATE CLEAR**。遡及学習BLOCK軽量ack機構が完成した。 これにより、連続起票時の既知パターンBLOCKは: - **Before**: lesson_write_shogun.sh → 新規LS作…
- 2026-05-14T15:12:53+09:00 | ntfy | outbound | 【INFOバッチ】 2026-05-14 15:12:17|cmd_2720
- 2026-05-14T15:12:52+09:00 | ntfy | outbound | 【将軍】context鮮度ALERT: doc-style-guide.md(35日),growth-loop.md(23日),gs-speedup-knowledge.md(24日),gstack-knowledge.md(35日),g…
- 2026-05-14T15:07:19+09:00 | ntfy | outbound | 【将軍】context鮮度ALERT: doc-style-guide.md(35日),growth-loop.md(23日),gs-speedup-knowledge.md(24日),gstack-knowledge.md(35日),g…

## 未解決確認事項
- 【家老】cmd_2720 初回配備開始 (title=infra改善 — 遡及学習BLOCK軽量ack機構(既知パターン教訓確認の簡素化), ninja=hayate) infra改善 📋 https://gist.github.com/simokitafresh/6eb495…
- 殿、報告する。 **cmd_2720 起票・委任完了** — 遡及学習BLOCK軽量ack機構 前セッションで20cmd連続起票時に毎回踏んだ「既知パターンの教訓記録→即supersede→物理削除」のCTX浪費ループを解消する仕組み。既存の`cmd_publish.sh` p…
- /clear準備完了。 **本セッション最終成果:** | カテゴリ | 件数 | 内容 | |----------|------|------| | **infra改善** | 4件CLEAR | cmd_2699-2704(draft_review修正/effectiven…
- 掲示板確認結果を報告する。 **軍師のBLOCK全量品質監査（blt_133145）が最重要:** | 発見 | 内容 | 深刻度 | |------|------|--------| | 免疫系正常 | FAIL率 W16:58% → W20:7.5%（**7.8倍改善**）…
- 掲示板を確認せよ
- **本セッション成果:** | cmd | 内容 | 状態 | |-----|------|------| | cmd_2701 | rebalancer PJ登録 | **CLEAR** | | cmd_2702 | rebalancer万全偵察 | **突合完了**(P0:…
- 【karo】復帰済み。cmd_2702/2703完了済み確認。CI RED→GREEN復帰見込(Unit Tests PASS、E2E待ち)。WAデータDUPLICATE 7件自動修復。idle自走開始。
- blockにゲートの品質問題やインフラバグは潜んでいないかもう一度確認しよう。2703の効果は出ているか？

## 殿の直近裁定・方針（直近24h）
- 2026-05-14T14:44:35+09:00 | 殿指示: rebalancerプロジェクト改良着手。PJ登録(cmd_2701)+万全偵察(cmd_2702,24件発見P0:3/P1:8/P2:13)。P0全3件+P1全8件+P2-3(a11y)+P2-4(i18n)=16件CLEAR。infra修正4件(cmd_2699-2704:draft…
- 2026-05-14T12:49:55+09:00 | 次、cmd_2702（万全偵察）。cmd_2701完了待ちだが、偵察はdraft→cmd_2701 CLEAR後に昇格すればよい。ただし`status: on_hold`禁止（殿裁定）なので、cmd_2701のCLEAR後に起票する。 殿、cmd_2701（PJ登録）を配備した…

## 参照cmd
- cmd_2695
- cmd_2697
- cmd_2699
- cmd_2701
- cmd_2702
- cmd_2703
- cmd_2704
- cmd_2705
- cmd_2706
- cmd_2707
- cmd_2708
- cmd_2709
- cmd_2710
- cmd_2711
- cmd_2712
- cmd_2713
- cmd_2714
- cmd_2715
- cmd_2716
- cmd_2717
- cmd_2718
- cmd_2719
- cmd_2720

## 参照先
- `queue/lord_conversation.jsonl`（一次データ）
- `logs/lord_conversation_archive/*.jsonl`（24h超過・200件超過の退避先）
