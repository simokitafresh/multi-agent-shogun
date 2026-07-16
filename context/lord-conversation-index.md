# Lord Conversation Index
<!-- last_updated: 2026-07-17 auto-generated -->
<!-- generated_by: scripts/conversation_retention.sh -->
<!-- generated_at: 2026-07-17T08:39:07+09:00 -->

## 最新やり取り（直近24h）
- 2026-07-17T08:39:02+09:00 | terminal | response | 未読0件。inbox待機。 [meta] stop_reason=end_turn
- 2026-07-17T08:35:45+09:00 | ntfy | outbound | 【家老】cmd_reflux_promotion_202607170756_kotaro 完了
- 2026-07-17T08:35:36+09:00 | terminal | response | 未読0件。BLOCK解消済み。inbox待機。 [meta] stop_reason=end_turn
- 2026-07-17T08:33:42+09:00 | ntfy | outbound | 【将軍】cmd_reflux_promotion_202607170833_hayate 初回配備開始 (title=(untitled), ninja=hayate)
- 2026-07-17T08:30:04+09:00 | terminal | response | 未読0件。inbox待機。 [meta] stop_reason=end_turn
- 2026-07-17T08:23:22+09:00 | ntfy | outbound | test outside tmux warning
- 2026-07-17T08:23:21+09:00 | ntfy | outbound | test permission warning
- 2026-07-17T08:22:04+09:00 | terminal | response | `rg`はBash toolからは使える。PATHの違いを確認する。
- 2026-07-17T08:21:39+09:00 | terminal | response | 未読0件。inbox待機。 [meta] stop_reason=end_turn
- 2026-07-17T08:15:20+09:00 | terminal | response | 未読0件。inbox待機。 [meta] stop_reason=end_turn

## 未解決確認事項
- `rg`はBash toolからは使える。PATHの違いを確認する。
- inbox 14件は全て定型通知。Read+Grepで全文確認済み。bash BLOCK(preflight deadlock)のためinbox_mark_read実行不能。 [MEM: memory_db ts=2026-07-17 knowledge:24214495 "全…
- bash BLOCK継続。inbox 14件は全て定型通知、複数回Read確認済み。inbox_mark_read実行不能。全成果push済み。 [MEM: memory_db ts=2026-07-17 knowledge:24214495 "全成果push済み"] tool…
- inbox 14件はRead+Grepで複数回全文確認済み。全て家老自走パイプラインの定型通知(速度修行LGTM/GATE CLEAR + reflux promotion)。将軍作業影響なし。 bash BLOCK(記憶DBキャッシュ破損→preflight deadlock…
- inbox 14件は全て家老自走パイプラインの定型通知。Read+Grepで複数回全文確認済み。将軍作業影響なし。bash BLOCK(記憶DBキャッシュ破損)のためinbox_mark_read実行不能。 [MEM: memory_db ts=2026-07-17 knowl…
- bash BLOCK継続中。inbox 14件は全て家老自走パイプラインの定型通知(速度修行/reflux LGTM+GATE CLEAR)。内容確認済み。inbox_mark_read実行不能。 本セッション全成果(7 commit)push済み。/clearで記憶DBキャッ…
- inbox 10件の内容はRead+Grepで複数回確認済み。全て家老自走パイプラインの定型通知。将軍作業影響なし。 bash BLOCK(記憶DBキャッシュ破損)のためinbox_mark_read実行不能。この状態は/clearでのみ解消可能。 [MEM: memory_d…
- bash全面BLOCK継続中(記憶DBキャッシュ破損→preflight証跡発行不能)。inbox 10件はRead toolで内容確認可能だがinbox_mark_readが実行不能。 全件は家老自走パイプラインの定型通知(速度修行LGTM/GATE CLEAR + refl…

## 殿の直近裁定・方針（直近24h）
- 該当なし

## 参照cmd
- 該当なし

## 参照先
- `queue/lord_conversation.jsonl`（一次データ）
- `logs/lord_conversation_archive/*.jsonl`（24h超過・200件超過の退避先）
