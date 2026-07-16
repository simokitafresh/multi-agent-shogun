# 台帳駆動 Campaign Lane 汎用スキル化 — As-Is / To-Be / 5W1H

更新日: 2026-07-16  
状態: 汎用controller実装済み / 応用候補catalog登録済み / 各候補adapterは未接続  
参照元: [台帳駆動・自走攻略レーン設計パターン v2.2](https://gist.github.com/simokitafresh/f777582a41c66e95a53d1cc993bc5a1c)

## §0 結論

「一次計測台帳が次の標的を選び、idle実行者が改善し、結果が次の選定へ戻る」閉ループを、テスト高速化専用処理から `campaign-lane` 汎用スキルへ分離した。

汎用化したのは次の判断契約である。

- `minimize` / `maximize` / `target` の目的関数
- adapterが供給する数値priorityによる決定的選定
- `best_so_far` とround内複数計測のobjective方向best
- `min_rounds=2` / `max_rounds=3` / 累積budget
- 悪化不採用、stale拒否、品質FAIL除外、飽和停止
- idle人数に応じた可変Nと既存 `shard-work` へのhandoff
- 同一target・同一round重複と並行二重recordの排除

新しいworker管理箱やmonitorは作っていない。実行は既存のidle検知・配備・`shard-work`を使う。

## §1 As-Is / To-Be

| 観点 | As-Is | To-Be |
|---|---|---|
| 対象 | Bats単体テスト速度に固定 | 数値化できる任意の候補群 |
| 目的関数 | wall秒の最小化のみ | minimize / maximize / target |
| 選定 | 専用ledgerのwall降順 | adapter由来priority降順 + ID安定順 |
| round | test専用callback | 共通min2/max3・budget契約 |
| baseline | 単一`last_wall`を継承する穴あり | 全有効計測からobjective方向bestを導出 |
| 並列数 | 固定人数化の誘惑 | `N=min(独立候補, capability適合idle worker, budget内)` |
| 実行 | 専用generatorが直接配備 | controllerは判断のみ、実行は`shard-work`へ委譲 |
| 状態 | タスク固有YAML/TSV | catalog YAML + append-only measurement JSONL |
| 安全性 | 後追いで重複guard追加 | stale・duplicate・in-flight・SEALED・主観評価を入口BLOCK |
| 応用 | 文書上の候補列挙 | 機械可読catalog 12件 + readiness validator |

## §2 5W1H

- **Why**: idle能力を遊ばせず、改善の選定と停止を人間の記憶・特定CLI・特定LLMから切り離すため。
- **What**: 数値台帳から候補を選び、複数roundを回し、best-so-farと飽和条件で停止する汎用スキル。
- **Who**: adapter=計測正規化、`campaign-lane`=判断、`shard-work`=分割実行、既存配備系=worker起動、担当者=品質契約付き改善。
- **When**: 対象列挙可能・数値優先可能・1弾10分以内・成果を二値検証可能、の4条件を満たすとき。
- **Where**: `skills/campaign-lane/`をClaude/Codex共通正本とし、既存の配備・monitor・shard基盤へ相乗りする。
- **How**: catalog検証 → measurement検証 → priority選定 → shard handoff → record → best/stop再判定。

## §3 責務境界

```text
通常業務runner / gate / API
        │ 自動計測
        ▼
一次台帳 ── adapter ──► 正規化measurement JSONL
                              │
                              ▼
                       campaign-lane
                   validate / select / record / status
                              │ HANDOFF
                              ▼
                         shard-work
                可変N・LPT・隔離・retry・lossless merge
                              │
                              ▼
                     既存idle配備経路
```

`campaign-lane`はworkerを起動せず、paneを監視せず、候補commandも実行しない。`shard-work`は既知集合の単発分割を担当し、campaignの継続・停止判断はしない。

## §4 スキル構成

```text
skills/campaign-lane/
├── SKILL.md
├── agents/openai.yaml
└── scripts/campaign_lane.py
```

実行入口:

```bash
python3 skills/campaign-lane/scripts/campaign_lane.py validate CATALOG.yaml MEASUREMENTS.jsonl
python3 skills/campaign-lane/scripts/campaign_lane.py select   CATALOG.yaml MEASUREMENTS.jsonl
python3 skills/campaign-lane/scripts/campaign_lane.py record   CATALOG.yaml MEASUREMENTS.jsonl --result '{...}'
python3 skills/campaign-lane/scripts/campaign_lane.py status   CATALOG.yaml MEASUREMENTS.jsonl
```

## §5 Runtime catalog契約

```yaml
objective: minimize
min_rounds: 2
max_rounds: 3
budget: 10
measurement_not_before: "2026-07-16T00:00:00+09:00"
candidates:
  - id: target-a
    cost: 2
    priority: 90
    capability: test
    independent: true
  - id: target-b
    cost: 2
    priority: 80
    capability: test
    independent: true
workers:
  - id: worker-1
    idle: true
    capabilities: [test]
  - id: worker-2
    idle: true
    capabilities: [test]
```

`priority`はadapterが一次計測から生成する。catalog記載順、worker名、CLI名、LLM名で優先順位を変えてはならない。

## §6 Measurement契約

1行1eventのappend-only JSONLとする。

```json
{"target":"target-a","round":1,"status":"success","quality":"pass","value":4.285,"cost":2,"measured_at":"2026-07-16T19:00:00+09:00"}
```

不変量:

- キーは `(target, round)`。同一targetのR1/R2/R3は許可し、同一round重複はBLOCKする。
- `measurement_not_before`より古い計測はBLOCKする。
- `quality_fail`、非数値、失敗計測をbestへ採用しない。
- concurrent recordはflock内で再読し、成功1件・重複BLOCK1件にする。
- minimizeは最小、maximizeは最大、targetは目標への距離最小を採用する。
- round内で複数回計測した場合も、最後の値ではなくobjective方向bestを使う。

## §7 停止条件

| 条件 | 結果 |
|---|---|
| target到達 | `TARGET_REACHED` |
| 累積costがbudget到達 | `BUDGET_EXHAUSTED` |
| min2後に改善なし | `SATURATED` |
| round 3到達 | `MAX_ROUNDS` |
| SEALED本番・主観評価・依存候補 | `BLOCK` |
| budget内に独立候補2件を収容不能 | `BLOCK` |
| capability適合idle workerが2名未満 | `BLOCK` |

serialへの無言fallbackはしない。人数は6人固定ではなく、その時点の適合idle人数から決める。

## §8 応用候補catalog

機械可読正本: `config/campaign_lane_catalog.yaml`  
validator: `python3 scripts/validate_campaign_lane_catalog.py`

2026-07-16時点:

| readiness | 件数 | 意味 |
|---|---:|---|
| ready | 2 | writer→台帳→adapter→task→報告の全辺が接続済み |
| partial | 9 | 台帳またはwriterはあるが、決定的adapterなどが不足 |
| blocked | 1 | 外部環境または一次writer未確認 |

登録済み12候補:

1. 本体スクリプト速度
2. pytestテスト速度
3. SKILL.md鮮度
4. context鮮度
5. 因果backlinks=0
6. insight queue
7. detector false-positive率
8. 教訓backlog
9. workaround率
10. CI runtime
11. 三層記憶候補backlog
12. 報告gate失敗率

`ready=2`は script-speed と pytest-speed のwriter→台帳→adapter貫通を実測した値である。残る候補も、対象固有adapterと通常業務からの自動writerが揃うまでreadyへ上げない。

## §9 テスト証跡

| 対象 | 結果 | 主な敵対fixture |
|---|---:|---|
| campaign-lane skill validation | 1/1 PASS | frontmatter・構成 |
| generic controller | 15/15 PASS | priority逆転、累積budget、stale、duplicate、同target R1-R3、並行record、品質FAIL、SEALED |
| 既存test-speed callback | 22/22 PASS | R2計測4.285/5.196→best 4.285、順序逆転、valid 0件BLOCK、previous best保持 |
| 応用候補catalog | 12/12 fields PASS | lane_id重複0、ready=2 / partial=9 / blocked=1 |

確認コマンド:

```bash
python3 /home/simokitafresh/.codex/skills/.system/skill-creator/scripts/quick_validate.py skills/campaign-lane
bats tests/unit/test_campaign_lane.bats
bats tests/unit/test_test_speed_task_generator.bats
python3 scripts/validate_campaign_lane_catalog.py
```

## §10 改善された具体例

既存速度レーンでは、同一roundで4.285秒と5.196秒を計測したのに、最後の5.196秒を次roundのbestとして継承していた。

修正後:

```text
previous best: 9.818
valid measurements: [4.285, 5.196]
round best: 4.285
next best_so_far: min(9.818, 4.285) = 4.285
last observation: 5.196（観測履歴として別保存）
```

これにより、計測回数を増やした結果baselineが悪化する逆転を防いだ。

## §11 残課題

1. §8の残候補ごとのadapterを作り、`ready=2`を実測で引き上げる。
2. 専用計測runを増やさず、通常業務経路へ自動writerを接続する。
3. 最初のready候補で、生成→idle配備→改善→record→次round→飽和までを実機貫通させる。
4. adapterの選定精度とfalse-positive率を計測し、100% FPなら較正または退役する。
5. 完了処理・計測経路・選定器のうち最弱リンクを毎cycleで更新する。

## §12 Source map

- `skills/campaign-lane/SKILL.md`
- `skills/campaign-lane/scripts/campaign_lane.py`
- `tests/unit/test_campaign_lane.bats`
- `config/campaign_lane_catalog.yaml`
- `scripts/validate_campaign_lane_catalog.py`
- `scripts/test_speed_task_generator.sh`
- `tests/unit/test_test_speed_task_generator.bats`
- `docs/research/ledger-driven-campaign-lane-pattern_20260714.md`

## 因果リンク

`[[ledger-driven-campaign-lane-pattern_20260714]] -> [[campaign-lane]] -> [[shard-work]] -> [[adaptive-idle-workers]]`


origin: [[家老自走cmd_20260716]]
