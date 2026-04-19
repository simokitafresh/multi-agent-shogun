# cmd_2110: test_report_template_gate_compat.bats プロファイリング
# 作成: kotaro / 2026-04-19

## Before 計測 (cold, 5回, 中央値)

| Run | Real時間 |
|-----|---------|
| 1   | 7.840s  |
| 2   | 7.582s  |
| 3   | 6.898s  |
| 4   | 8.055s  |
| 5   | 6.503s  |

**中央値 (ソート後3番目): 7.582秒**

条件:
- bats --jobs 1 (sequential)
- 51テスト
- 測定ツール: `{ time bats ... 2>/dev/null; } 2>&1 | tail -3`

## Setup プロファイリング

### コスト内訳

| 処理 | 推定コスト | 回数 | 合計 |
|------|-----------|------|------|
| python3 gate_report_format_combined.py | ~100ms/call | ~42 calls (_run_gate) | ~4,200ms |
| bash gate_report_format.sh (→python3) | ~100ms/call | ~5 calls (Fix22-28) | ~500ms |
| bash gate_report_autofix.sh (fast pathあり) | ~50ms/call | ~8 calls | ~400ms |
| bats フレームワーク overhead | ~37ms/test | 51 tests | ~1,890ms |
| setup() rm-rf + mkdir | ~3ms/test | 51 tests | ~150ms |
| setup_file() fixture生成 | ~20ms | 1 | ~20ms |
| **合計** | | | **~7,160ms** |

### 最大ボトルネック

**python3 起動コスト**: 各 `_run_gate` 呼び出しが独立したpython3プロセスを起動。
- python3 startup alone: 36ms
- yaml import追加: 74ms
- gate_report_format_combined.py (autofix+format両module import+処理): ~100ms/call
- 42回 × 100ms = **4,200ms** (全体の55%)

### 並列化の限界

`--jobs 4` 試験済み: 14.438秒 (worse)。
理由: WSL2 NTFSのI/Oシリアライズ。並列化は逆効果 (L508参照)。

### 最大削減余地

python3起動を削減するため「永続Pythonデーモン」アプローチを採用:
- setup_fileでpython3を1回起動→全テストで共有
- 各_run_gateはFIFO経由でデーモンにパスを送り結果を受信
- python3起動コスト: 42 × 100ms → 42 × ~10ms (IPC overhead)
- 期待削減: ~3,780ms (全体の50%削減)

## After 計測 → cmd_2110_test_report_template_gate_compat.bats参照
