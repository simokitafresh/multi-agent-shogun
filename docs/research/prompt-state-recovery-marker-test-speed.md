# prompt-state-recovery-marker-test-speed

origin: [[cmd_training_test_speed_test_prompt_state_recovery_marker__20260714235151]] -> [[real-three-layer-preflight-in-unit-test]] -> [[prompt-state-recovery-marker-test-speed]]

## 結論

[[test_prompt_state_recovery_marker.bats]] はrecovery markerのmtime契約だけを検証するため、三層検索を行う実preflightを起動しない。[[prompt_state_inject.sh]] の既定preflightは維持し、`PROMPT_STATE_PREFLIGHT_CMD`でtest dependencyを成功no-opへ束縛する。

## 契約

- production既定値は`/scripts/hooks/three_layer_preflight.sh`のまま。
- testは`/bin/true`を注入し、marker refresh/non-create/non-shogun/post-hook警告の5契約を全件維持する。
- 通常実行と`bats -j 8`でFAIL 0 / SKIP 0を確認する。

## 未採用の改善候補

1. testごとの`mktemp -d`と共通空fixture生成を`setup_file` master fixtureへ移す。
2. `/tmp/shogun_*` cleanup対象をtest-local namespace helperへ集約する。
