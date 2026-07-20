# deploy publication 残存 phase 計測（2026-07-20）

## 結論

22:08:06–22:09:42 の同一5並列waveから、連続する mutation 計測3本を抽出した。既存の計測対象7 phaseは各run 7/7、`subprocesses` 欠落0、重複0、全てrc=0だった。ただし外側 `task_mutations` に対して未計装区間が25.0–32.3秒（59.5–65.0%）残る。次の最速候補は、未計装injector群を個別に高速化する前に、同一candidate YAMLへの逐次publicationを1回のbatch publicationへまとめる方式である。欠落・重複0を維持するため、既存7 receiptと最終atomic `mv` は残す。

## 一次データと方法

- source: `logs/deploy_task.log`
- window: 2026-07-20 22:08:06–22:09:42 JST
- mutation receipt: `TASK_MUTATION_PHASE`
- outer receipt: `DEPLOY_WALL_EVENT name=task_mutations`
- subprocess数はreceiptの機械可読値を採用。7 phase × 3 run = 21/21行に値あり。
- 同時waveのためrun_idがない2本はouter receiptとの個体対応が不能。恣意的対応を避け、先頭2本は集合として比較し、未帰属量は最小/最大レンジで示す。

## 3回計測

単位はms。各セルは `wall/subprocesses`。

| phase | run A | run B | run C |
|---|---:|---:|---:|
| entrance_gates | 47/0 | 35/0 | 91/0 |
| scout_gate | 96/0 | 82/0 | 204/0 |
| task_modifiers | 1,087/0 | 897/0 | 1,682/0 |
| related_lessons | 5,204/0 | 1,912/0 | 3,835/0 |
| semantic_context | 1,888/0 | 1,952/0 | 2,053/0 |
| memory_context | 1,217/0 | 1,110/0 | 1,381/0 |
| report_publication | 7,756/0 | 8,096/0 | 8,151/0 |
| 計装済み合計 | 17,295 | 14,084 | 17,397 |

outer `task_mutations` は対応waveで40,960ms、42,043ms、49,731ms。run A/Bの個体対応を入れ替えても未帰属は23,665–27,959ms、run Cは32,334ms。安全側の全体レンジは23,665–32,334ms、割合は57.8–65.0%。

## 二値確認

| check | result |
|---|---:|
| mutation run数 | 3/3 |
| 期待phase行 | 21/21 |
| wall_ms欠落 | 0/21 |
| subprocesses欠落 | 0/21 |
| phase名重複（各run内） | 0/3 |
| rc非0 | 0/21 |
| report scan | 3/3（各1） |
| outer residual receipt | 0ms（全deploy receipt） |
| task_mutations内部の未帰属 | 3/3あり（23,665–32,334ms） |

## 候補比較

| 優先 | 候補 | 観測根拠 | 欠落・重複契約 | 推奨 |
|---:|---|---|---|---|
| 1 | 未計装injector群のcandidate YAML更新をbatch化 | 未帰属57.8–65.0%が最大 | 既存7 receiptとatomic `mv`を維持すれば0/0 | 採用候補 |
| 2 | report_publication追加短縮 | 3回とも7,756–8,151ms | receipt 1、report scan 1を維持 | 次点 |
| 3 | related_lessons追加短縮 | 1,912–5,204ms | receipt 1を維持 | 変動が大きく第3候補 |

候補1の採用条件は、隔離fixtureで3回実行し、task/report/inboxの欠落0、重複0、既存7 phase receipt 21/21、最終YAML syntax 3/3 PASSを同時に満たすこと。単に計装を増やすだけでは速度は上がらないため、まず逐次YAML publication回数を数えてbatch化し、同じreceiptでbefore/afterを比較する。

## 因果

`[[cmd_karo_next_throughput_tobisaru_2207]] -> [[task_mutations未計装57.8-65.0pct]] -> [[candidate_yaml_batch_publication]]`
