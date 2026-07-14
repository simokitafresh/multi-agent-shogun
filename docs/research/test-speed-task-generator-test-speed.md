# test_speed_task_generator Unit速度修行

## 結論

`test_test_speed_task_generator.bats`の非idle 6状態検証を、6回の子bash起動から1子bash内のループへ集約した。状態集合・hash不変条件・idle時の配備成功条件は維持する。

直接参照: [[test_test_speed_task_generator.bats]] / [[test_speed_task_generator.sh]] / [[run_timed_bats.sh]]

## 改善点3件

1. `tests/unit/test_test_speed_task_generator.bats` L128-148: 非idle 6状態ごとに`env -i ... bash -c`を起動していた。`bats --timing`では当該testが393msで第2位の支配項だったため、1子bash内の共有ループへ集約した。
2. `tests/unit/test_test_speed_task_generator.bats` L60-73: canonical target検証は3状態×2表現ごとに本体scriptを起動し、455msで最大の支配項である。次段では本体側に候補解析のbatch seamを設けない限り、契約を保った大幅短縮は難しい。
3. `tests/unit/test_test_speed_task_generator.bats` L10-110: generator系7testが同じledger/task fixtureを反復生成する。`setup_file`共有base化は候補だが、現状の各test専用`BATS_TEST_TMPDIR`分離を崩すリスクがあるため、先に子bash起動回数を削減した。

## 根拠と検証契約

- 修正前の直近台帳: 9 PASS、FAIL 0、SKIP 0、3.137秒（`logs/test_timing_ledger.tsv`）。
- リンク先 `scripts/run_timed_bats.sh` L15-18 はBatsの終了コードを保持し、L24-34はwall time・test数・skip数を台帳へ書く。このため検証は同wrapperを用いる。
- D7分類: behavior不変refactor。既存9testのcoverage、非idle 6状態、hash不変条件、idle成功条件を維持する。

因果: [[test_test_speed_task_generator.bats]] -> [[子bash反復起動]] -> [[test-speed-task-generator-test-speed]]
