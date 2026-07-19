# finalize段 工程別内訳（2026-07-19）

## §1 結論

直近週次窓のうち、同一の一次タイムスタンプ5種を欠損なく結合できた直近4 cmdを同一コホートとして集計した。finalize内の最大工程は「報告completed→軍師レビュー通知」中央値82.4秒、次点は「SG7 bundle生成→二相レビュー承認」74.1秒で、5工程中央値合計253.2秒の61.8%を占める。台帳全体のfinalize中央値403秒との差149.8秒は、欠損を含む全498件と完全観測4件という母集団差、および前後の未計装区間であり、工程へ恣意配賦しない。

## §2 集計契約

- 観測窓: `logs/loop_ledger.yaml` 最新snapshot（generated_at `2026-07-19T07:52:46Z`, window_days=14, completed=498）。
- コホート: 2026-07-19の直近CLEAR cmdから、report timestamp、review notify、SG7、review gate、CLEAR、archiveの全時刻が揃う4件。欠損除外は対象縮小による性能主張ではなく、工程内訳の同一分母を守るため。
- 中央値: 各cmdの隣接時刻差を秒へ変換後、工程ごとにmedian。mtimeは運用成果物の生成時刻、CLEARはappend-only gate logの記録時刻を使用。

## §3 数値表

| 工程 | 中央値秒 | 構成比 | タイムスタンプ出典（開始→終了） |
|---|---:|---:|---|
| 報告完了→軍師レビュー通知 | 82.4 | 32.5% | `queue/archive/reports/*_<cmd>_20260719.yaml:timestamp` → `queue/gates/<cmd>/gunshi_report_review_notify_*.done` mtime |
| 通知→SG7 bundle生成 | 46.5 | 18.4% | `gunshi_report_review_notify_*.done` mtime → `sg7_bundle.json` mtime |
| SG7生成→二相レビュー承認 | 74.1 | 29.3% | `sg7_bundle.json` mtime → `review_gate.done` mtime |
| 承認→GATE CLEAR | 15.5 | 6.1% | `review_gate.done` mtime → `logs/gate_metrics.log` CLEAR timestamp |
| CLEAR→archive完了 | 34.6 | 13.7% | `logs/gate_metrics.log` CLEAR timestamp → `archive.done` mtime |
| 合計 | 253.2 | 100.0% | 上記5工程 |

個票（秒）:

| cmd短縮名 | report→notify | notify→SG7 | SG7→review | review→CLEAR | CLEAR→archive | 合計 |
|---|---:|---:|---:|---:|---:|---:|
| gp239 | 96.1 | 47.7 | 41.6 | 13.6 | 28.7 | 227.7 |
| report-idempotent | 55.6 | 44.4 | 44.7 | 12.4 | 24.2 | 181.2 |
| inbox-e2e | 69.4 | 47.4 | 217.8 | 17.4 | 40.8 | 392.8 |
| idle-log | 95.4 | 45.6 | 103.6 | 17.4 | 40.6 | 302.6 |

## §4 根治候補（既存フローへ接続）

| 優先 | 支配工程 | 短縮候補 / 予想削減 | 変更対象 | 波及先・関連test | エッジケース / 順序制約 |
|---:|---|---|---|---|---|
| 1 | report→notify (82.4秒) | report completed atomic publishと同一eventで軍師review-ready通知を永続化し、watcher走査待ちを除く。中央値30–50秒削減見込み | `scripts/inbox_watcher.sh`（report completion dispatch周辺）、`scripts/ninja_monitor.sh`（fallback検知周辺） | report notification exactly-once、watcher handoff、respawn recoveryの既存unit/E2Eを拡張 | 親report retryで重複通知0、watcher停止時はdurable fallback、archive symlink後もcanonical report identityを維持。publish成功→event永続化→wake-upの順 |
| 2 | SG7→review (74.1秒) | gunshi LGTMとkaro ACCEPTを別pollで待たず、SG7 fingerprintをキーにapproval到着時の単一gate triggerへ合流。中央値25–45秒削減見込み | `scripts/cmd_complete_gate.sh:6009-6072`、review approval helper/dispatcher | review fingerprint、two-phase approval、duplicate trigger、revision generationの既存contract tests | revision後の旧fingerprint承認を再利用しない、片方欠損時CLEAR禁止、同時到着raceでtrigger exactly-once。SG7確定→両承認永続化→gate triggerの順 |
| 3 | notify→SG7 (46.5秒) | review通知時にbundle入力fingerprintを同梱し、受信側のreport再探索・再parseを避ける。中央値15–25秒削減見込み | review bundle生成経路、`scripts/inbox_watcher.sh` | canonical report identity v2、bundle repair/retry tests | report revisionとのTOCTOUをfingerprint不一致BLOCK、欠落childはretry repair。report publish→fingerprint→bundle生成の順 |
| 4 | CLEAR→archive (34.6秒) | 現行async archiveを維持しつつcompletion checkpointとarchiveの重複走査を1回のmanifestへ統合。中央値10–20秒削減見込み | `scripts/cmd_complete_gate.sh:9108-9135`、`scripts/archive_completed.sh:1674-1745` | archive idempotency、dashboard async、completion checkpoint tests | dashboard/ntfyをarchive待ちへ戻さない、archive失敗をCLEAR偽装しない、report読了後のみmove。CLEAR→manifest確定→async consumersの順 |

## §5 再現証跡

- `logs/loop_ledger.yaml`: completed 498、e2e median 1113秒、deploy 60秒、work 311秒、finalize 403秒。
- `logs/gate_metrics.log`: 対象4 cmdのCLEAR時刻とfinalize_sec。
- `queue/archive/reports/`: completed report timestamp。
- `queue/gates/<cmd>/`: review notify、SG7、review_gate、archive各成果物mtime。
- 計測結果: N=4/4完全観測、工程中央値合計253.2秒、上位2工程156.5秒（61.8%）。

origin: `[[finalize中央値403秒が最大税]] -> [[工程内訳偵察cmd_4085]] -> [[review通知待ち+二相承認待ちが61.8%]]`
