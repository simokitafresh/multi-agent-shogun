# GA-226 context freshness / reverted-result stale index

## 結論

- `gate_context_freshness.sh` がchecker既定の1件を3件へ上書きしていたため、未反映source commitがmerge/squash後に3件未満になるとcontext未編集でもALERTが消え得た。
- 既定閾値を1へ戻し、context先頭の`source_commit`境界より後に1件でもsource変更があればALERTを維持する。時刻経過やmergeだけでは解除せず、contextが新境界を記録した時だけOKになるfixtureを追加した。

## cmd_3843 → cmd_3845一次履歴

| 時刻(JST) | commit | 事実 |
|---|---|---|
| 2026-07-11 12:41-13:12 | `fd7d9c8c`, `b1bb8ab7`, `63ce763f` | TradePerformanceメモ化系列を実装 |
| 2026-07-11 13:32 | `77524534`, `c4d84a58`, `565d936d` | 上記3 commitをrevert |
| 2026-07-11 13:35 | `9aef473d` | 全量照合FAILとrollbackを恒久資料へ記録 |

全102PF・11,040行の旧/新7runは相互exactだったが、本番baselineに554行/24PF、約1e-16差。性能はold median 113.379sからnew median 124.623sへ9.917%退行した。従ってcmd_3843は現行実装ではない。

## 因果

`[[GA-226]] -> [[source_commit件数閾値3]] -> [[merge後ALERT自然消滅]] -> [[source_commit境界1件強制]]`

`[[cmd_3843]] -> [[全量パリティFAILと性能退行]] -> [[cmd_3845_revert]] -> [[stale_context修正]]`
