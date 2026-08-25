# cmd_4403 最重量テスト単体短縮

- 実施日: 2026-08-25
- 対象: `tests/unit/test_cmd_complete_gate.bats`
- 目的: 検査内容を削除・緩和せず、テスト自身の支配的な実行経路を短縮する。

## AC1: タイミング正本からの機械抽出

抽出元は `logs/cmd_4392_local-test-timing.json`（測定時刻 `2026-08-25T02:16:31+09:00`、239/239、重複0、欠落0）。実行した抽出コマンド:

```bash
python3 - <<'PY'
import json
d=json.load(open('logs/cmd_4392_local-test-timing.json'))['measurement']
for x in sorted(d['records'], key=lambda x:x['duration_sec'], reverse=True)[:11]:
    print(f"{x['path']}\t{x['duration_sec']:.3f}\t{x['observed_test_count']}\t{x['result']}")
PY
```

生出力:

```text
tests/unit/test_cmd_complete_gate.bats	912.260	281	PASS
tests/unit/test_cmd_save_block_aggregation.bats	411.945	13	PASS
tests/unit/test_inbox_write.bats	372.646	118	PASS
tests/unit/test_gate_gunshi_report_precheck_cache.bats	369.317	6	FAIL
tests/unit/test_gate_gunshi_report_precheck.bats	368.094	29	PASS
tests/unit/test_cmd_skeleton.bats	330.954	14	FAIL
tests/unit/test_three_layer_preflight.bats	287.006	59	PASS
tests/unit/test_ninja_scope_commit.bats	278.773	79	PASS
tests/unit/test_auto_deploy_next.bats	278.097	4	PASS
tests/unit/test_review_approval.bats	270.445	13	PASS
tests/unit/test_run_tests.bats	263.413	66	PASS
```

今回の対象は正本降順の第1候補。テストの内部timing（修正後 receipt `logs/test_receipts/run_tests_20260825T075019_4058930.json`）は、281件の個別実行合計259.559秒、file wall-clock298.532秒、未帰属（setup/teardown・Bats/runner境界）38.973秒だった。`setup_file`、各`setup`、`teardown`のns markerをテストへ残し、次回計測で境界内訳を直接回収できるようにした。個別実行の最大はreceipt/gitretry系で、setup共通化の対象はsource-publication fixture群だった。

## AC2: 短縮内容とbefore/after

| 対象 | before (秒) | after (秒) | 短縮 (秒) | 短縮率 |
|---|---:|---:|---:|---:|
| `tests/unit/test_cmd_complete_gate.bats` | 912.260 | 298.532 | 613.728 | 67.3% |

変更はAC2 source-publication群のテスト実行経路だけ。`setup_file`で`push_task_repositories`の関数-only runnerを1回生成し、各fixtureは同じ本体関数を呼ぶ。通常のcompletion gate全体のsnapshot/reparseを各ケースで繰り返さなくなった。multi-task既存probe、AC3配線検査、overlap専用fixtureは維持した。assertion、検証対象、281ケースのテスト数は変更していない。

短縮合計613.728秒 / 対象群912.260秒 = 67.3%で、10%基準を超える。

## AC3: 実行結果・次バッチ

実行コマンド:

```bash
BATS_CACHE=0 BATS_MAX_TEST_JOBS=1 bash scripts/run_tests.sh file tests/unit/test_cmd_complete_gate.bats
```

結果: `281/281 PASS`, `FAIL=0`, `SKIP=0`, receipt `logs/test_receipts/run_tests_20260825T075019_4058930.json`, `rc=0`, `duration_ms=298532`。

次バッチ候補（タイミング正本降順、今回対象を除外）:

1. `tests/unit/test_cmd_save_block_aggregation.bats` — 411.945秒
2. `tests/unit/test_inbox_write.bats` — 372.646秒
3. `tests/unit/test_gate_gunshi_report_precheck_cache.bats` — 369.317秒（正本計測時FAIL18群の一つ。短縮前にFAIL原因を分離）
4. `tests/unit/test_gate_gunshi_report_precheck.bats` — 368.094秒
5. `tests/unit/test_cmd_skeleton.bats` — 330.954秒（正本計測時FAIL）
6. `tests/unit/test_three_layer_preflight.bats` — 287.006秒
7. `tests/unit/test_ninja_scope_commit.bats` — 278.773秒
8. `tests/unit/test_auto_deploy_next.bats` — 278.097秒
9. `tests/unit/test_review_approval.bats` — 270.445秒
10. `tests/unit/test_run_tests.bats` — 263.413秒

次バッチも降順で1 fileずつbefore/afterを取得し、各file後に239-file分布を再計測する。FAIL計測の対象は短縮実装と混ぜず、先にFAIL0/SKIP0の信頼境界を確定する。
