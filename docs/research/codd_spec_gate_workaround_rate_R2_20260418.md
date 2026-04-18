# CoDD Spec: gate_workaround_rate.sh 正規再改善 R2

- **対象**: `scripts/gates/gate_workaround_rate.sh`
- **作成**: 2026-04-18 hanzo (cmd_2092)
- **前回改善**: cmd_1970 (tobisaru) — python3+awk3本 → awk1本。before 50ms → after 26ms (-44%)
- **今回before**: median 36ms cold 5回計測 (2026-04-18)
  - gate_metrics.log: 958行 115K / karo_workarounds.yaml: 2349行 74K (前回より成長)
- **目標**: 30ms以下

---

## 定量プロファイル (実測)

| コンポーネント | 時間 | 比率 |
|--------------|------|------|
| bash起動 + 変数設定 | ~6ms | 17% |
| awk gate_metrics.log処理 (958行 全量) | ~21ms | 58% |
| awk karo_workarounds.yaml処理 (2349行) | ~15ms | 42% |
| IFS read + echo出力 | ~1ms | 3% |
| **合計 (cold median)** | **~36ms** | 100% |

### 計測コマンド
```bash
# 全体5回cold median: 36ms
# cat両ファイル(純I/O): 12ms
# awk gate_metricsのみ: 21ms
# awk karo_workaroundsのみ: 15ms
# tac+early_exit awk: 4ms (新手法)
```

### 発見: tac + early-exit が劇的に速い
```bash
# 現行: awk が全958行を処理してから末尾N件を取得 → 21ms
# 改善: tac で逆順出力 + awk が N件で exit → 4ms (-81%)
time tac logs/gate_metrics.log | awk -F'\t' -v last_n=10 '
  $3=="CLEAR" && !seen[$2]++ { lines[n++]=$2; if(n>=last_n) exit }
  END { for(i=n-1;i>=0;i--) print lines[i] }' > /dev/null
# → real 0m0.004s (4ms)
```

---

## ボトルネック分析

### 主ボトルネック: gate_metrics.log全量読込 (21ms)
- 現行: awk の FNR==NR パスで全958行スキャン
- 必要なのは「末尾から数えてN件のユニークCLEARエントリ」だけ
- CLEAR率 = 638/958 = 67% → last 15行あれば10 unique CLEARが確実に取れる
- **tacで末尾から読んでN件見つかり次第exit → ほぼ15行の読込で完了**

### WSL2制約（L508教訓）
- WSL2 NTFSはI/Oシリアライズが支配的
- tac はOSのファイルseekを使い末尾チャンク(~4KB)のみI/O → 115K全量I/O回避

---

## リファクタリング対象

### R1: tac + early-exit awk でgate_metrics.log処理を置換
**Before**: awk 1本で gate_log全量(958行) + wa_file(2349行) を処理
```awk
has_gate == "true" && FNR == NR {
    if ($3 == "CLEAR" && !seen[$2]++) clear_lines[clear_count++] = $2
    next
}
```

**After**: 2段階
1. `tac "$GATE_LOG" | awk early-exit` → `_CLEAR_IDS` 変数に取得 (4ms)
2. `awk -v clear_ids="$_CLEAR_IDS" ...` で wa_file のみ処理 (15ms)

**期待効果**: gate_log処理 21ms → 4ms (-17ms)

### R2: wa_seen_false 削除 (デッドコード除去)
```awk
# 現行: wa_seen_false を設定するが wa_count/cats に影響しない
} else if (!item_wa[i] && !(cmd in wa_seen_true) && !(cmd in wa_seen_false)) {
    wa_seen_false[cmd] = 1  # ← これを参照する処理が存在しない
}
```
`wa_seen_false` は設定されるが読まれない。`else if` ブロック全体が不要。

---

## 実施順序

1. R1実装: tac+early-exit + 2段階awk に分割
2. batsテスト実行 → 全PASS確認
3. R2実装: wa_seen_false ブロック削除
4. batsテスト実行 → 全PASS確認
5. after計測 (cold 5回 median)

---

## 制約

- 出力形式: `LEVEL|RATE|WA_COUNT|TOTAL|CATS|SOURCE` 不変
- 閾値: OK<15%, WARN15-30%, ALERT>30% 不変
- `--last N` 引数サポート 不変
- fallback path (gate_log不在時) 不変
- エラー時出力: `ERROR|0|0|0|awk_error|unknown` 不変
- API互換: gate_metrics.logの有無による分岐挙動 不変

---

## After期待値

| コンポーネント | Before | After |
|--------------|--------|-------|
| bash起動 | 6ms | 6ms |
| gate_log処理 (tac+awk) | 21ms | 4ms |
| wa_file処理 (awk) | 15ms | 15ms |
| その他 | 1ms | 1ms |
| **合計** | **36ms** | **~26ms** |

期待改善: **-28% (36ms→26ms, 1.38x)**
