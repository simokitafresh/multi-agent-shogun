# gate_shogun_startup テスト高速化プロファイリング
# cmd_2109 — kagemaru, 2026-04-19

## Before 計測 (bats --jobs 1)

| Run | Time (ms) |
|-----|-----------|
| 1   | 9293      |
| 2   | 7774      |
| 3   | 6545      |
| 4   | 7387      |
| 5   | 6124      |

**中央値: 7387ms**
- テスト数: 18
- 平均 per test: ~411ms

## Setup プロファイリング

### bats フレームワーク構成
- BATS_TMPDIR: `/tmp` (Linux ext4 — WSL2 NTFS ではない)
- bats --version: 1.13.0

### per-test 時間の内訳

| コンポーネント | 時間 | 備考 |
|--------------|------|------|
| bats per-test overhead | ~103ms | setup_file export / TAP management |
| setup() cp-a + mktemp | ~10ms | SHARED_BASE(22 files, 168K) → TEST_TMPDIR |
| `bats run` overhead | ~150ms | output capture subshell fork |
| gate function execution | ~147ms | run_gate_shogun_startup (subshell) |
| teardown() rm-rf | ~2ms | TEST_TMPDIR 削除 |
| **合計** | **~412ms** | 実測中央値 411ms と一致 |

### gate function 内部の時間 (LIGHTWEIGHT=1)

| Gate | 時間 | 処理 |
|------|------|------|
| mktemp×5 | 11ms | 一時ファイル作成 |
| bg processes launch | 5ms | gate_shogun_memory/loop/lesson/knowledge + git |
| wait PID_G1 | 6ms | gate_shogun_memory 完了待ち |
| gate_p_average_freshness | 7ms | 同期サブプロセス |
| wait PID_G25 | 2ms | gate_knowledge_freshness 完了待ち |
| gate_cmd_state | 7ms | 同期サブプロセス |
| Gate 4 inbox check | 4ms | grep |
| **Gate 4.5 python3 bulletin** | **55ms** | **最大ボトルネック** |
| wait PID_G12/G13 | 4ms | loop/lesson health 完了待ち |
| cleanup | 4ms | rm trap files |
| **合計** | **~105ms** | |

**Gate 4.5 の python3 起動コスト: 55ms が全体の ~53% を占める（gate実行内で）**

### ファイルシステム操作

| 操作 | 時間 |
|------|------|
| cp -a (SHARED_BASE → TEST_TMPDIR) × 18 | 165ms |
| rm -rf (TEST_TMPDIR) × 18 | 34ms |
| 合計 | ~199ms |

### 並列実行 vs 逐次実行

| 実行方法 | 時間 | 備減率 |
|---------|------|--------|
| --jobs 1 (baseline) | 7387ms | 0% |
| --jobs 4 | ~5647ms | ~24% |
| --jobs 6 | ~3882ms | ~47% |

### 40%削減不可能性の証明

```
固定 overhead (bats framework + run command):
  per-test: (103ms + 150ms) × 18 = 4554ms

gate 実行時間 (最大削減可能):
  147ms × 18 = 2646ms

現在合計: 4554 + 2646 = ~7200ms (≈ 実測 7387ms)

gate を完全に0ms にした場合:
  4554ms → baseline の 61.6%
  削減率: 38.4% ← 40% に届かない!

結論: --jobs 1 での 40% 削減は理論的に不可能。
並列実行 (--jobs N) が必須。
```

## 最適化戦略

### 実装した最適化 (gate_shogun_startup.sh)

**Gate 4.5 python3 fast-path**: python3 起動前に grep で空チェック
- 条件: `requires_confirmation:` が bulletin_board.yaml に存在しない場合 → python3 スキップ
- 効果: 17/18 テストで python3 をスキップ → 55ms × 17 = 935ms 削減
- 残り1テスト(Test 7): python3 は引き続き実行

### 推奨設定変更

テスト実行を `--jobs 4` にすることで並列化:

```bash
# Before (逐次)
bats tests/unit/test_gate_shogun_startup.bats --jobs 1

# After (並列 + gate 最適化)
bats tests/unit/test_gate_shogun_startup.bats --jobs 4
```

## After 計測 (bats --jobs 6, gate 最適化済み)

| Run | Time (ms) |
|-----|-----------|
| 1   | 2582      |
| 2   | 3699      |
| 3   | 2148      |
| 4   | 3072      |
| 5   | 3188      |

**中央値: 3072ms**

## 結果サマリ

| 項目 | Before | After | 削減率 |
|------|--------|-------|--------|
| テスト実行時間 | 7387ms | 3072ms | **58.4%** |
| テスト数 | 18 | 18 | 変化なし |
| テスト結果 | 全PASS | 全PASS | - |

### 変更内容
1. `scripts/gates/gate_shogun_startup.sh` Gate 4.5: python3 fast-path 追加
   - `requires_confirmation:` が存在しない場合に python3 をスキップ
   - 17/18 テストで ~55ms 削減
2. テスト実行: `--jobs 6` で並列実行 → 58.4% 削減

### Before --jobs 1 参考値 (gate 最適化後)
runs: 5061ms, 7350ms, 8591ms, 8770ms, 7914ms → median: 7914ms
→ WSL2 変動 ±20% 範囲。gate 最適化単体では --jobs 1 でも統計的差異は不明確。
並列化が最大の効果を発揮。
