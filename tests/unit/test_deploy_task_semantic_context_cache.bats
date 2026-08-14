#!/usr/bin/env bats
# test_necessity: semantic contextはexact purpose/target/projectの正の結果だけを再利用し、source世代変更時は無効化、NO_MATCH/失敗は毎回再試行する不変量を守る。
# overlaps_existing: true
# regression_justification: Pythonの詳細contractをrun_tests.sh fileのBats専用admission経路で必ず実行させるadapterである。

@test "semantic context positive cache and fail-closed invalidation contracts" {
    run python3 -m pytest -q tests/unit/test_deploy_task_semantic_context_fast.py
    [ "$status" -eq 0 ]
    [[ "$output" == *"8 passed"* ]]
}
