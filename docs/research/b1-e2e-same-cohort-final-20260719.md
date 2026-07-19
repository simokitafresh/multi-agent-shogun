# B1同一cohort最終計測（2026-07-19）

## 結論

`local_pass_e2e_unproven` — **BLOCK**。fixed-SHA CIはGREENだが、比較可能なcanonical cohortはbefore `N=0`、after `N=0`。p50/p95、blocked-agent-seconds、品質合格成果/時、倍率を算出しない。

## fixed-SHA境界

| 項目 | 一次証跡 |
|---|---|
| SHA | `09f87ddba342d3e5b6f1ad7c13346dbc2e5c63d4` (`git show`: 2026-07-19 07:07:40 JST) |
| GitHub Actions run | `29662918337`, workflow=`Multi-CLI Test Suite`, conclusion=`success` |
| GREEN cutover | `2026-07-18T22:14:56Z` = `2026-07-19 07:14:56 JST` |
| GitHub headSha | `09f87ddba342d3e5b6f1ad7c13346dbc2e5c63d4` |
| 確認コマンド | `gh run view 29662918337 --json databaseId,headSha,status,conclusion,createdAt,updatedAt,workflowName,url` |

## 抽出query

正本: `docs/research/infra-throughput-outcome-design-20260718.md` §8.1-8.3。同じqueryを両windowへ適用し、専用配備・sampling・外れ値除去は行っていない。

```text
parse logs/deploy_task.log transactions from DEPLOY_WALL_EVENT name=parse_args through DEPLOY_RECEIPT; windows before=[2026-07-18T00:00:00Z,2026-07-18T22:14:56Z), after=[2026-07-18T22:14:56Z,source_end]; require canonical fields and exact phase_set=parse_args,task_mutations,delivery,post_verify,post_delivery; no exclusions or sampling
```

- query SHA256: `88b860514fa4fea2db3c9d2d0c40cd3d9c5807dc3001f30e2ef75a5338f21008`
- source: `logs/deploy_task.log`
- source timestamp: `2026-07-19 10:49:55.218559500 +0900`
- source bytes: `891459`
- source SHA256: `fe345ac36abcaf9e216805b4bde994db9a4c977a7226a8367e39f9b0e6ef067f`
- source line境界: before `2-7462`; after `7474-8086`
- observed time境界: before `2026-07-18 22:36:05 JST`〜`2026-07-19 06:59:40 JST`; after `2026-07-19 08:11:11 JST`〜`2026-07-19 10:49:54 JST`

## 全件集計

| 検査 | before | after |
|---|---:|---:|
| raw transaction | 50 | 4 |
| canonical valid N | 0 | 0 |
| invalid_schema | 50 | 4 |
| phase mismatch | 50 | 4 |
| valid cohort内duplicate event_id | 0/0 | 0/0 |
| raw duplicate event_id | event_id欠落のため判定不能 | event_id欠落のため判定不能 |
| task_type×concurrencyセル一致 | 両field欠落のため判定不能 | 両field欠落のため判定不能 |

全54 transactionがcanonical必須field（`event_id`, source ISO timestamps/lines, `git_sha`, `environment_id`, `cmd_id`, `task_id`, `task_type`, `blocked_agents`, `concurrency`, terminal/quality result, FP/FN/SKIP）を単一transaction recordとして持たない。さらに観測phase_setは契約外`preflight`を含み、完走行では`post_delivery`が2回現れるため、全54/54がexact phase contract不一致である。

## 判定

| 指標 | before | after | 判定 |
|---|---:|---:|---|
| N | 0 | 0 | 各20不足（各不足20） |
| p50 / p95 | 算出禁止 | 算出禁止 | valid N不足 |
| blocked-agent-seconds | 算出禁止 | 算出禁止 | `blocked_agents`欠落 |
| 品質合格成果/時 | 算出禁止 | 算出禁止 | terminal/quality契約欠落 |
| FAIL / SKIP / FP / FN | 算出禁止 | 算出禁止 | canonical品質field欠落 |
| 改善倍率 | 算出禁止 | 算出禁止 | cohort比較不能 |

AND条件（p95 -20%以上、blocked-agent-seconds -20%以上、品質合格成果/時 1.20倍以上、FAIL/SKIP/FP/FN全0）は評価不能。速度値をraw receiptから代用するとschema・仕事量・SHA/window混在を隠すため、PASSへ昇格しない。

## 次の自然発火条件

現cutoverのbefore側はcanonical recordが0件のため、時間経過だけでは成立しない。canonical writer/extractorが正本§8.1の全fieldとexact phase_setを自然運用で出力する境界を新たに固定し、その境界のbefore/afterで同一`task_type×concurrency`セルが各20件以上、invalid_schema=0、duplicate event_id=0、phase mismatch=0になった時だけ同一queryを再実行する。専用配備で件数を作らない。

## 変更境界

変更は本研究文書1件のみ。運用script、既存log、queue YAMLは変更していない。

origin: `[[fixed_SHA_CI_GREEN_09f87dd]] -> [[canonical_cohort_schema欠落]] -> [[local_pass_e2e_unproven]]`
