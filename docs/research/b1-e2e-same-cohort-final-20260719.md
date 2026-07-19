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

正本: `docs/research/infra-throughput-outcome-design-20260718.md` §8.1-8.3。同じqueryを両windowへ適用する。inclusive rawを先に数えた後、本計測を開始するための自己観測transactionだけを自然蓄積cohortから分離する。sampling・外れ値除去は行わない。

```text
parse logs/deploy_task.log transactions from DEPLOY_WALL_EVENT name=parse_args through DEPLOY_RECEIPT; windows before=[2026-07-18T00:00:00Z,2026-07-18T22:14:56Z), after=[2026-07-18T22:14:56Z,source_end]; require canonical fields and exact phase_set=parse_args,task_mutations,delivery,post_verify,post_delivery; report inclusive raw first, then exclude only the current measurement task transaction cmd_karo_recon2_b1_e2e_same_cohort_final_20260719104917 from natural cohort; no sampling or outlier removal
```

- query SHA256: `d53a42c0a3d45cd456b887469a5de2ae53752d81fc4bf4200c44a44d41c731f1`
- source: `logs/deploy_task.log`
- source timestamp: `2026-07-19 10:49:55.218559500 +0900`
- source bytes: `891459`
- source SHA256: `fe345ac36abcaf9e216805b4bde994db9a4c977a7226a8367e39f9b0e6ef067f`
- source line境界: before `2-7462`; after inclusive `7474-8086`; after自然蓄積 `7474-7938`; 自己観測 `7940-8086`（cmd識別行 `7942-8076`を包含）
- bounded SHA256: before `240470b78bd1dcc31ec3a0c7a08e05118a8b752af8842a21d8b4a616091c7ffa`; after自然蓄積 `710b987826839eb4b9d2c5941c69424195dbdf94ece54879a8334ea83a8e30f3`; 自己観測 `62e24d077a053db348dd81e357591b20733324c5d0d5706266ef831f5bf28388`
- observed time境界: before `2026-07-18 22:36:05 JST`〜`2026-07-19 06:59:40 JST`; after自然蓄積 `2026-07-19 08:11:11 JST`〜`2026-07-19 08:53:12 JST`; 自己観測 `2026-07-19 10:49:39 JST`〜`10:49:54 JST`

## 全件集計

| 検査 | before | after |
|---|---:|---:|
| inclusive raw transaction | 50 | 4 |
| 自己観測transaction | 0 | 1 |
| 自然蓄積raw transaction | 50 | 3 |
| canonical valid N（自然蓄積） | 0 | 0 |
| invalid_schema（自然蓄積） | 50 | 3 |
| phase mismatch（自然蓄積） | 50 | 3 |
| valid cohort内duplicate event_id | 0/0 | 0/0 |
| raw duplicate event_id | event_id欠落のため判定不能 | event_id欠落のため判定不能 |
| task_type×concurrencyセル一致 | 両field欠落のため判定不能 | 両field欠落のため判定不能 |

inclusive raw 54件のうちafter 1件は、本計測task `cmd_karo_recon2_b1_e2e_same_cohort_final_20260719104917` 自身の配備（transaction `7940-8086`）であり、自然発火した仕事ではないため自然cohortから分離した。残る自然蓄積53 transactionはcanonical必須field（`event_id`, source ISO timestamps/lines, `git_sha`, `environment_id`, `cmd_id`, `task_id`, `task_type`, `blocked_agents`, `concurrency`, terminal/quality result, FP/FN/SKIP）を単一transaction recordとして持たない。さらに観測phase_setは契約外`preflight`を含み、完走行では`post_delivery`が2回現れるため、自然蓄積53/53がexact phase contract不一致である。

## 判定

| 指標 | before | after | 判定 |
|---|---:|---:|---|
| N | 0 | 0 | 各10不足（各不足10） |
| p50 / p95 | 算出禁止 | 算出禁止 | valid N不足 |
| blocked-agent-seconds | 算出禁止 | 算出禁止 | `blocked_agents`欠落 |
| 品質合格成果/時 | 算出禁止 | 算出禁止 | terminal/quality契約欠落 |
| FAIL / SKIP / FP / FN | 算出禁止 | 算出禁止 | canonical品質field欠落 |
| 改善倍率 | 算出禁止 | 算出禁止 | cohort比較不能 |

AND条件（p95 -20%以上、blocked-agent-seconds -20%以上、品質合格成果/時 1.20倍以上、FAIL/SKIP/FP/FN全0）は評価不能。速度値をraw receiptから代用するとschema・仕事量・SHA/window混在を隠すため、PASSへ昇格しない。

## 次の自然発火条件

現cutoverのbefore側はcanonical recordが0件のため、時間経過だけでは成立しない。canonical writer/extractorが正本§8.1の全fieldとexact phase_setを自然運用で出力する境界を新たに固定し、その境界のbefore/afterで同一`task_type×concurrency`セルが各10件以上、invalid_schema=0、duplicate event_id=0、phase mismatch=0になった時だけ同一queryを再実行する。専用配備で件数を作らない。

## 変更境界

変更は本研究文書1件のみ。運用script、既存log、queue YAMLは変更していない。

origin: `[[throughput-mece-design-20260718]] -> [[infra-throughput-outcome-design-20260718]] -> [[b1-e2e-same-cohort-final-20260719]]`
