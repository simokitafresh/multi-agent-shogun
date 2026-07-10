# cmd_3830 nudge delivery guarantee

Date: 2026-07-10
Worker: hayate

## 結論

`inbox_watcher.sh` の INPUT-GUARD 保留は、実送信前に `fingerprint` / `debounce` を更新済みだったため、同一未読集合の次回確認が `FP-SAME` / debounce 扱いで抑止され得た。これを `deferred_nudge` 状態として明示し、保留時は送信済み状態をrollback、未読が残る限り次回 `DEFERRED-RETRY` で再送するよう修正した。

追加で、Codex の `agent_state=active` かつ `check_agent_busy=busy` の場合、非空入力行は生成中UIであり paste+Enter が queued message として安全に入るため、INPUT-GUARDをbypassして即時送達する。さらにidle promptの候補文はANSI dim (SGR 2) を一次情報として実入力と区別し、安全に送達する。通常色の実入力とClaude/非Codexは従来通り保護する。

## 実装

- `scripts/inbox_watcher.sh`
  - `DEFERRED_NUDGE_FILE` を追加。
  - INPUT-GUARD保留時に `record_deferred_nudge` を記録し、`FINGERPRINT_FILE` / `DEBOUNCE_FILE` を削除。
  - 同一fingerprintの未読が残る場合は `DEFERRED-RETRY` として送信。
  - 成功送信/未読0で `deferred_nudge` をclear。
  - Codex active+busyのみ `BUSY-CODEX-QUEUE` / `INPUT-GUARD-BYPASS` で即時queued送達。
  - Codex idle promptのANSI dim候補文を空入力扱いにし、blocked/goal停止中にも復旧nudgeを送達。
- `tests/unit/test_inbox_watcher_dedup.bats`
  - deferred retry成功とstate clear。
  - Codex active+busy+nonempty input = SEND。
  - stale `@agent_state=idle` でも Codex actual busy = SEND。
  - 非Codex active+busy = DEFER。
  - Codex dim idle suggestion = SEND、通常色の未送信入力 = DEFER。
  - 既存singleton/fingerprint/debounce/priority/input guard回帰を維持。

## AC対応

- AC1: INPUT-GUARD保留後、未読が残る限り同一fingerprintでも再送する機構を実装。`T-IWD-005A` で検証。
- AC2: `stop_check_inbox.sh` は家老・軍師・忍者を含む未読block/idle誘導を維持。`tests/unit/test_stop_check_inbox.bats` 36/36 PASS。
- AC3: watcher singletonは既存 `SINGLETON_LOCK_FILE` + fd 209 を維持。`T-IWD-001` / `T-IWD-007` で検証。
- AC4: `bulletin_write.sh` の再送・最終失敗記録・可視化は既存実装を検証。`tests/unit/test_bulletin_board.bats` 23/23 PASS。

## 検証結果

```text
bats tests/unit/test_inbox_watcher_dedup.bats tests/unit/test_inbox_watcher_delivery_latency.bats
→ 19/19 PASS

bats tests/unit/test_stop_check_inbox.bats tests/unit/test_bulletin_board.bats
→ 59/59 PASS

bash -n scripts/inbox_watcher.sh scripts/bulletin_write.sh scripts/hooks/stop_check_inbox.sh
→ PASS
```

## 因果

`[[殿指摘20260710_1427_家老に回答未達]] -> [[INPUT-GUARD保留nudgeの再注入不在]] -> [[通知配達保証の仕組み化]]`

`[[Codex idle候補文を未送信入力と誤認]] -> [[復旧nudge永久保留]] -> [[ANSI dim一次判定]]`
