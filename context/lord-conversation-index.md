# Lord Conversation Index
<!-- last_updated: 2026-07-17 auto-generated -->
<!-- generated_by: scripts/conversation_retention.sh -->
<!-- generated_at: 2026-07-17T19:13:26+09:00 -->

## 最新やり取り（直近24h）
- 2026-07-17T19:13:26+09:00 | terminal | response | Check 12と総合判定の間にCI状態チェックを追加。
- 2026-07-17T19:11:09+09:00 | terminal | inbound | いま長時間かかったのはなぜだ？調査して家老にインフ ラバグの疑いとして報告せよ
- 2026-07-17T19:10:51+09:00 | terminal | response | backlinks=0は修行候補(WARN)。campaign-lane設計書への[[リンク]]をsenkyoku-logかcmd-chronicleに追加する。
- 2026-07-17T19:10:50+09:00 | ntfy | outbound | 【家老】cmd_karo_hotfix_exec_drain_throughput_202607171910 初回配備開始 (title=(untitled), ninja=saizo)
- 2026-07-17T19:07:32+09:00 | terminal | inbound | いま長時間かかったのはなぜだ？調査して家老にインフラバグの疑いとして報告せよ
- 2026-07-17T19:06:46+09:00 | ntfy | outbound | 【gunshi】cmd_reflux_promotion_202607171906_kagemaru 初回配備開始 (title=(untitled), ninja=kagemaru)
- 2026-07-17T19:06:27+09:00 | ntfy | outbound | 【家老CRITICAL】先送り1セッション連続検出。起動は許可するが即対処必須
- 2026-07-17T18:58:34+09:00 | ntfy | outbound | 【家老】cmd_reflux_promotion_202607171858_hayate 初回配備開始 (title=(untitled), ninja=hayate)
- 2026-07-17T18:57:37+09:00 | terminal | inbound | 知識とは全員が共有し、いつでも自由に利用できる仕組みでなければならない。前提条件が異なるとバグが生じやすい
- 2026-07-17T18:56:17+09:00 | terminal | inbound | 我らの原理原則を家老と将軍にも伝え三層記憶に貫通させておこう。クリア後も変わらぬスタイルを維持するべきだ

## 未解決確認事項
- skill_refs GATE CLEAR確認。inbox処理完了 [MEM: memory_db ts=2026-07-17 "skill_refs GATE CLEAR"] [MEM: semantic concept=throughput_first] [MEM: obs…
- 軍師LGTM(saizo skill_refs修正)確認。hanzo=CI fix in_progress。kagemaru/hayate=done(reflux完了)。 陣形図: hayate+kagemaru idle。家老がF1(cmd_4042)配備時にidle忍者へ動…
- 軍師LGTM(hanzo reflux promotion)確認。kagemaru=cmd_4040 assigned(CTX9%、S0c作業開始)。 [MEM: memory_db ts=2026-07-17 "kagemaru cmd_4040 S0c assigned C…
- S0b CLEAR+cmd-complete完了。S0c(fingerprint全要素+runtime mismatch BLOCK)が次。確認して既読化。
- 確認完了。idle待機。
- 軍師LGTM(kagemaru reflux promotion)確認。hanzo=cmd_4039 in_progress(CTX41%)でS0b実装中。 D0自走セッション稼働中 [MEM: memory_db ts=2026-07-17 "hanzo cmd_4039 S…
- 新着inbox確認。
- 設計書§5.4のshard_work --runフローを確認。materialize→LLM忍者配備→terminal result→result.jsonの結合が設計書に明示されているか。 設計書§5.2のresult_pathフィールドに「commit SHA、files、…

## 殿の直近裁定・方針（直近24h）
- 該当なし

## 参照cmd
- cmd_3997
- cmd_4032
- cmd_4034
- cmd_4038
- cmd_4039
- cmd_4040
- cmd_4042

## 参照先
- `queue/lord_conversation.jsonl`（一次データ）
- `logs/lord_conversation_archive/*.jsonl`（24h超過・200件超過の退避先）
