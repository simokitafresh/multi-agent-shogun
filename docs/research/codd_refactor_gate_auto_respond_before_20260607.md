# gate_auto_respond.sh — before計測 & ボトルネック仮説

cmd: cmd_training_speed_gate_auto_respond_20260607181500_normal
date: 2026-06-07
agent: kagemaru

## before計測 (cold, /tmp/gate_auto_last_state_* 削除後)

| 試行 | real時間 |
|------|----------|
| 1 | 3.686s |
| 2 | 3.724s |
| 3 | 3.967s |
| **平均** | **3.79s** |

※ タスクYAMLには after:5367ms (前回修行済み後) と記載。現状は前回より改善済み可能性あり。

## 個別gate計測

| gate | real時間 | 備考 |
|------|----------|------|
| gate_lesson_health | 2.195s | 最大ボトルネック (701行) |
| gate_context_freshness | 1.273s | 第2ボトルネック (314行) |
| gh run list (CI check) | 0.648s | ネットワークI/O |
| gate_cmd_state | 0.019s | 軽量 |
| gate_p_average_freshness | 0.024s | 軽量 |

## ボトルネック仮説

### 主因: 5つのgateが順次実行
各ハンドラは完全独立（共有状態なし、異なるstate_file使用）。
現在の実行パターン: lesson_health → cmd_state → context_freshness → p_average → ci_red

### 最適化戦略: 並列実行化
5ハンドラをバックグラウンド実行 → wait → 出力集約:
- 理論計算: max(2.195, 0.019, 1.273, 0.024, 0.648) = 2.195s
- 期待削減: 3.79s → ~2.3s (約40%改善)

### 副因: subprocess起動コスト
bash起動コストがWSL2上で各呼び出しに~20ms程度。並列化後はさらに削減余地があるが、
gate内部の最適化は今回スコープ外。

## 並列化設計メモ

```bash
# 各ハンドラを一時ファイルへリダイレクトしてバックグラウンド実行
tmpdir=$(mktemp -d)
handle_lesson_health     > "$tmpdir/1" 2>&1 &
handle_cmd_state         > "$tmpdir/2" 2>&1 &
handle_context_freshness > "$tmpdir/3" 2>&1 &
handle_p_average_freshness > "$tmpdir/4" 2>&1 &
handle_ci_red            > "$tmpdir/5" 2>&1 &
wait
cat "$tmpdir/1" "$tmpdir/2" "$tmpdir/3" "$tmpdir/4" "$tmpdir/5"
rm -rf "$tmpdir"
```

注意点:
- should_act() は各gate固有のstate_fileを使用 → 並列化で衝突なし
- inbox_write.sh / ntfy.sh はflock使用 → 並列コール安全
- stdout順序: catで連結時に順序保証
