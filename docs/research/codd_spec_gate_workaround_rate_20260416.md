# CoDD Spec: gate_workaround_rate.sh 高速化

- **対象**: `scripts/gates/gate_workaround_rate.sh`
- **作成**: 2026-04-16 tobisaru (cmd_1970)
- **before**: avg=50ms, min=43ms, max=56ms (20回計測, gate_log path)
- **cmd_1951基準**: 135ms (14回発火 × startup gate)
- **目標**: 40ms以下

---

## Before 計測 (コンポーネント別)

| コンポーネント | 時間 | 比率 |
|--------------|------|------|
| python3 startup | ~22ms | 44% |
| grep -P + awk + awk pipeline | ~6ms | 12% |
| shell overhead (set -e, SCRIPT_DIR, read等) | ~22ms | 44% |
| **合計** | **~50ms** | 100% |

計測コマンド:
```bash
# 全体: 20回計測 → avg=50ms
# python3 startup単体: time python3 -c 'pass' → 22ms
# grep+awk pipeline: time grep -P '\tCLEAR\t' logs/gate_metrics.log | awk ... | tail → 6ms
```

---

## ボトルネック分析

### 1. python3 -c '...' (22ms)
現在の実装はkaro_workarounds.yaml解析に`python3 -c '...'`をインライン起動している。
Python3のinterpreter起動だけで22ms消費しており、実際の処理(ファイルI/O+解析)は4ms程度。
Pythonに渡すのは行パーサ(yaml.safe_loadは使っていない)であり、awk で代替可能。

### 2. grep -P + awk + awk の3プロセス連鎖 (6ms)
```bash
grep -P '\tCLEAR\t' "$GATE_LOG" | awk -F'\t' '{print $2}' | awk '!seen[$0]++' | tail -n "$LAST_N"
```
3プロセス(grep+awk+awk)を起動している。awkの1プロセスに統合可能。

### 3. 環境変数経由でCLEAR_CMDSをpythonに渡す方式
`CLEAR_CMDS="..."|python3` の間にサブシェル展開がある。
awkでgatelog+WA_FILEを連続処理すれば中間変数不要。

---

## リファクタリング方針

### 変更点
1. **grep+awk+awk → awk 1本** (gate_metrics.logの処理)
   - `-F'\t'`, `$3 == "CLEAR"`, `!seen[$2]++`でCLEAR cmd_id抽出
   - `tail -n N`相当をawkのEND処理で代替

2. **python3 → awk** (karo_workarounds.yaml解析)
   - 行ベースパーサをawk関数で再実装
   - `- cmd_id:` を起点にエントリ開始検出
   - `workaround:` / `category:` フィールド抽出
   - gate_log path / fallback pathをawk内で分岐

3. **2ファイルを1回のawk呼び出しで処理**
   - `awk ... "$GATE_LOG" "$WA_FILE"` (FNR==NR = gate_log pass)
   - gate_log不在時は `awk ... "$WA_FILE"` のみ

### 機能保持
- 出力形式: `LEVEL|RATE|WA_COUNT|TOTAL|CATS|SOURCE` (不変)
- 閾値: OK=<15%, WARN=15-30%, ALERT=>30% (不変)
- --last N 引数 (不変)
- fallback path (gate_log不在時) (不変)
- エラー時: `ERROR|0|0|0|awk_error|unknown` (不変)

### 機能維持の注意点
- Python実装の「wa=true が false より優先(同一cmd複数エントリ時)」→ awk で同様に実装
- category内訳ソートはPython版もhash順(dictの挿入順)であり、awk版も同等

---

## After 期待値

| コンポーネント | Before | After |
|--------------|--------|-------|
| awk (gate_log pass) | 6ms | 5ms |
| awk (WA_FILE pass) | - | 5ms |
| shell overhead | 22ms | 18ms |
| python3 起動 | 22ms | 0ms (削除) |
| **合計** | **50ms** | **~28ms** |

期待改善: -44% (50ms→28ms), 1.8x
