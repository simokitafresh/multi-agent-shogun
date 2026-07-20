# scope helper bootstrap修正後の残存commit待機実測

- 実測日: 2026-07-20 JST
- 対象: `scripts/ninja_scope_commit.sh`
- 方法: 毎回新規の隔離Git fixtureを作り、正常・bootstrap中TERM・bootstrap中INT・2プロセス競合を各3回実行。競合のみpre-commitへ350ms sleepを置いてlock待機を確実に発生させた。
- 判定: terminal ledger欠落0、silent終了0、意図しないcommit 0。

| 条件 | run | rc | wall ms | terminal ledger | commit増分 |
|---|---:|---:|---:|---|---:|
| normal | 1 | 0 | 801 | rc=0, complete=true | 1 |
| normal | 2 | 0 | 378 | rc=0, complete=true | 1 |
| normal | 3 | 0 | 448 | rc=0, complete=true | 1 |
| TERM | 1 | 143 | 164 | phase=bootstrap, reason=TERM, complete=false | 0 |
| TERM | 2 | 143 | 168 | phase=bootstrap, reason=TERM, complete=false | 0 |
| TERM | 3 | 143 | 160 | phase=bootstrap, reason=TERM, complete=false | 0 |
| INT | 1 | 130 | 158 | phase=bootstrap, reason=INT, complete=false | 0 |
| INT | 2 | 130 | 155 | phase=bootstrap, reason=INT, complete=false | 0 |
| INT | 3 | 130 | 157 | phase=bootstrap, reason=INT, complete=false | 0 |
| contention (2 callers) | 1 | 0/0 | 2820 | 双方rc=0, complete=true | 2 |
| contention (2 callers) | 2 | 0/0 | 2890 | 双方rc=0, complete=true | 2 |
| contention (2 callers) | 3 | 0/0 | 2369 | 双方rc=0, complete=true | 2 |

## 次律速と最速候補

正常3回のhelper telemetryではlock_waitは2–5ms、post_checkは155–280msだった。したがって非競合時の次律速はlock取得ではなくpost_checkである。最速候補は、commit-tree/update-ref直後に既に証明済みの不変量と重複するpost_checkを棚卸しし、terminal ledger公開に必須な最小検査だけ同期実行、観測用の重複検査を後段へ移すこと。正常中央値448msに対し、post_check中央値235msが理論上の最大削減枠となる。

競合では2 caller合計2.369–2.890秒だが、両commitと両ledgerは3/3で正しく直列化された。安全性を落としてlockを外す候補は採らない。
