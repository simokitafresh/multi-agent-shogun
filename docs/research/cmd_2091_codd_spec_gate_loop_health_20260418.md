# CoDD Spec: gate_loop_health.sh — 正規CoDD再改善

**作成日**: 2026-04-18  
**担当**: kagemaru  
**対象**: `scripts/gates/gate_loop_health.sh` (313行)  
**cmd**: cmd_2091

---

## Before計測

- 計測条件: cold (スクリプト初回実行), 5回 median
- 計測結果:
  - Run 1: 444ms, Run 2: 430ms, Run 3: 442ms, Run 4: 430ms, Run 5: 453ms
  - **Median: 442ms**
- `time`コマンド確認: real 479-579ms (median ~524ms)

## プロファイリング結果

| Phase | 時間 |
|-------|------|
| Python startup | ~24ms |
| Read+parse gate_fire_log.yaml (1352 entries) | 19ms |
| Aggregate stats | 0.1ms |
| Reason counting | 5.5ms |
| Insights file read (211 entries) | 8.3ms |
| Workaround file read+parse (299 entries) | 3.4ms |
| Self-correction calc | 0.4ms |
| **合計 Python** | **~37ms** |
| **insight_write.sh × 6回 (SKIP)** | **~500ms** |
| bash setup | ~1ms |

**真のボトルネック**: `insight_write.sh` サブプロセス × 6回 ≈ 500ms

## ボトルネック根因

`insight_write.sh` は毎回 ~83ms かかるsubprocess。  
gate_loop_health.sh 内の dedup チェックが失敗し、全6件が SKIP にもかかわらず毎回呼び出される。

**dedup失敗の根因**:  
1. `gate_fire_log.yaml` の reasons フィールドには `\"yes\"` (1段エスケープ) が含まれる
2. `insight_write.sh` は `json.dumps()` で保存するため、YAML に `\\\"yes\\\"` (2段エスケープ) として書込まれる
3. gate_loop_health.sh は raw ファイル読み込みで `val.strip('"')` → `\"` が残る
4. `replace(\"→")` 1回パスでは `\\\"` → `\"` にしかならず、一致せず dedup 失敗

## 実装計画

### A: dedup修正 (主要改善)

**現在のコード** (L148-178):
```python
existing_insights = set()
try:
    with open(insights_file) as f:
        for line in f:
            s = line.strip()
            if s.startswith('insight:'):
                val = s[len('insight:'):].strip().strip('"')
                existing_insights.add(val)
except Exception:
    pass
```
↓
**改善後**: `json.loads()` でデコードして正しく格納
```python
import json
existing_insights = set()
try:
    with open(insights_file) as f:
        for line in f:
            s = line.strip()
            if s.startswith('insight:'):
                raw = s[len('insight:'):].strip()
                try:
                    val = json.loads(raw) if raw.startswith('"') else raw.strip("'")
                except Exception:
                    val = raw.strip('"')
                existing_insights.add(val)
except Exception:
    pass
```

**新しい dedup チェック** (msg を生成してから正規化不要に):
- `existing_insights` に完全デコード済みテキストを格納
- `msg in existing_insights` か `any(msg[:80] in ex for ex in existing_insights)` で十分

### B: regex コンパイル (minor)

現在: ループ内で `re.search(r'...', line)` × 5 = 毎行5回コンパイル  
改善後: ループ外で `re.compile()` → `pattern.search(line)` 

---

## 期待改善

| 条件 | Before | After | 削減 |
|------|--------|-------|------|
| 全insight既存 (SKIP) | ~464ms | ~65ms | ~86% |
| 新insight あり (N件) | ~464ms + N×83ms | ~65ms + N×83ms | ~400ms固定削減 |

## テスト

- `bash tests/gates/test_gate_loop_health.bats` 全PASS
- `bash scripts/gates/gate_loop_health.sh` 正常出力確認
- after計測: median 5回
