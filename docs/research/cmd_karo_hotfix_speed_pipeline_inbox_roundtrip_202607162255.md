# inbox review round-trip CoDD before/after

- cmd: `cmd_karo_hotfix_speed_pipeline_inbox_roundtrip_202607162255`
- target: `scripts/inbox_write.sh`
- fixture: isolated `INBOX_WRITE_ROOT_OVERRIDE`, 60 read records per target (overflow path), identical payload and five independent runs per direction

## Before

| Direction | Samples (ms) | p50 | p95 |
|---|---|---:|---:|
| karo -> gunshi (`review_draft`) | 158.305, 152.673, 152.534, 150.296, 69.857 | 152.534 | 158.305 |
| gunshi -> karo (`review_result`) | 126.948, 104.567, 165.253, 100.347, 72.291 | 104.567 | 165.253 |

Dominant interval: overflow retention rebuilt the mailbox through awk extraction, Bash arrays, and per-record `printf` writes on DrvFs.

## Design and implementation

Keep persistence-first ordering, flock, every unread record, and the newest 30 read records. Replace only the overflow reconstruction with one awk selection/emission pass followed by the existing atomic replace/retry helper.

Async boundary: memory DB mirroring stays best-effort after YAML persistence. Durable append, retention, watcher nudge, and delivery evidence are not moved behind that boundary.

## After

| Direction | Samples (ms) | p50 | p95 | p95 delta |
|---|---|---:|---:|---:|
| karo -> gunshi (`review_draft`) | 120.875, 117.961, 94.248, 66.431, 60.279 | 94.248 | 120.875 | -23.7% |
| gunshi -> karo (`review_result`) | 49.941, 117.587, 93.002, 53.744, 47.092 | 53.744 | 117.587 | -28.8% |

Both directions are strictly shorter at p50 and p95. SLO is p95 <130ms in this fixture.

## Regression entry

- `tests/unit/test_inbox_write.bats`: retention, unread preservation, concurrent lost-update protection.
- `tests/unit/test_inbox_watcher_delivery_latency.bats`: nudge delivery and latency evidence.
- Re-run the five-sample fixture when overflow implementation or watcher delivery boundaries change.
