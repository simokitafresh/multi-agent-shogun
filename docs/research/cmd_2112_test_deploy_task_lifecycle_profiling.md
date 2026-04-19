# cmd_2112: test_deploy_task_lifecycle.bats プロファイリング結果

## Before 計測 (5回中央値)

```
実行: bats tests/unit/test_deploy_task_lifecycle.bats (sequential)
runs: 7.988, 7.104, 6.870, 6.877, 8.074s (sorted: 6.870, 6.877, 7.104, 7.988, 8.074)
中央値: 7.104s
テスト数: 36
```

## ボトルネック分析

### 1. python3起動コスト (推計 ~2,860ms)

| 関数 | 呼出回数/test | ms/call | 小計 |
|------|-------------|---------|------|
| `get_task_values()` | 2テストで複数回 | 143ms | ~700ms |
| `read_task_engineering_preferences()` | 3テスト | 143ms | ~429ms |
| `read_gate_blocks()` | 5テスト | 143ms | ~715ms |
| `read_task_gate_fail_top3()` | 4テスト | 143ms | ~572ms |
| GP-110テスト (34-36) | 3テスト | 143ms | ~429ms |
| **合計** | | | **~2,845ms** |

計測環境: WSL2/NTFS, python3 cold start = 143ms/call

### 2. grep+sed pipeline (推計 ~803ms)

`run_double_deploy_guard()` でgrep+sed×3パイプラインを複数回実行:
- 11テスト × 5パイプライン/test × 14.6ms/pipeline ≈ **803ms**

計測: grep+sed pipeline = 14.6ms/call, bash read = 0.125ms/call

### 3. mktemp/rm-rf (推計 ~393ms)

`setup()` で `mktemp -d`, `teardown()` で `rm -rf` を36テスト分実行:
- 36 × 10.9ms = **393ms**

BATS_TEST_TMPDIR使用により両方不要になる。

## 最適化方針

| 対象 | 手法 | 推計削減 |
|------|------|---------|
| `get_task_values()` | python3 → awk | ~700ms |
| `read_task_engineering_preferences()` | python3 → awk | ~429ms |
| `read_gate_blocks()` | python3 → awk | ~715ms |
| `read_task_gate_fail_top3()` | python3 → awk | ~572ms |
| GP-110テスト (34-36) | python3 → bash | ~429ms |
| `run_double_deploy_guard()` | grep+sed → bash read | ~803ms |
| `setup()/teardown()` | mktemp → BATS_TEST_TMPDIR | ~393ms |
| **合計** | | **~4,041ms** |

目標: before 7.104s の40%削減 → ≤4.262s

## After 計測

```
実行: bats tests/unit/test_deploy_task_lifecycle.bats (sequential)
runs: 4103, 4114, 4134, 4203, 4226ms (sorted: 4103, 4114, 4134, 4203, 4226)
中央値: 4.134s
削減率: 41.8% (before 7.104s → after 4.134s)
テスト数: 36 (before時点から変化なし、全PASS)
```

## 最適化結果サマリー

| 指標 | Before | After | 削減 |
|------|--------|-------|------|
| 中央値 | 7.104s | 4.134s | 2.970s (41.8%) |
| テスト数 | 36 | 36 | 変化なし |

目標: before比40%削減 → **PASS** (41.8% > 40%)
