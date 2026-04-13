# kawarimi monthly_fast.csv 高速化設計書

> 作成: 軍師 2026-04-13
> 依頼: 家老相談 msg_20260413_013818_85619733
> 状態: 分析完了・設計案提示

---

## §1 問題定義

| 忍法 | fast_sec | total_sec | monthly時間 | 倍率(vs oikaze) |
|------|---------|-----------|-----------|----------------|
| oikaze | 37s | 67s | 30s | 1x |
| kasoku_diff | 108s | 247s | 139s | 4.6x |
| kawarimi | 47s | 1832s | 1785s(29.7min) | **59.5x** |

fast(results_fast)は全忍法同等速度。**月次リターン計算のみ59.5倍遅い。**

---

## §2 根因分析（コード現物比較）

### 2.1 kawarimi のホットパス

`run_077_kawarimi.py` L559-664 `simulate_pattern()`:
```
for i in range(max_out):  # ~300月ループ
    if should_rebalance(...):
        block.execute(ctx)  # TrendReversalFilterBlock.execute()
```

`trend_reversal_filter.py` L57-174 `execute()`:
```python
# L97: load_ticker_prices() を毎リバランス月で呼ぶ（キャッシュヒットでもスキップしない）
# L108-143: 各ティッカーのモメンタム計算
for ticker in tickers:
    if ticker in precomputed:
        val = _lookup_cached(precomputed[ticker])  # dict lookup
    else:
        moms = calculate_momentum_for_monthly_data(df_ticker, period_months)  # 再計算
        cached_moms = {d: float(v) for d, v in zip(...)}  # dict変換（L131）
        precomputed[ticker] = cached_moms
# L145-166: top N + worst N の和集合選出
```

### 2.2 oikaze のホットパス

`run_077_oikaze.py` L592-700 `simulate_pattern()`:
```
for i in range(max_out):  # 同じ月ループ
    if should_rebalance(...):
        block.execute(ctx)  # MomentumFilterBlock.execute()
```

`momentum_filter.py` L34-154 `execute()`:
```python
# L70-71: キャッシュに全ティッカーある場合 → load_ticker_prices()スキップ
# L103-134: Seriesオブジェクトを直接キャッシュ
# L141-149: top N のみ選出（和集合なし）
```

### 2.3 因果鎖（3段）

```
根因: TrendReversalFilterBlockが毎リバランス月でload_ticker_prices()をスキップせず再ロード
  → 中間: ~300リバランス × ~20ティッカー = 6000回のファイルI/O + momentum再計算
  → 結果: 1785秒（29.7分）

比較: MomentumFilterBlockは初回計算後にSeriesキャッシュヒット → 2回目以降I/Oゼロ
  → 30秒で完了
```

**59.5倍の差はselection方式(top N vs top+worst N和集合)の2倍ではなく、キャッシュ効率の差が支配的。**

---

## §3 差異サマリ

| 観点 | kawarimi (TrendReversalFilter) | oikaze (MomentumFilter) |
|------|-------------------------------|------------------------|
| 選出方式 | top N + worst N 和集合 | top N のみ |
| 計算量倍率 | 2x（和集合分） | 1x |
| キャッシュ形式 | dict `{date: float}` に変換 | pd.Series直接保存 |
| キャッシュヒット時 | dict lookupのみ（高速） | bisect lookupのみ（高速） |
| **load_ticker_prices()** | **毎リバランス月で呼出し（キャッシュ有無問わず）** | **全キャッシュヒット時スキップ** |
| CSV書込み | write_monthly_csv_numpy()（共通） | 同左 |

**支配的ボトルネック: load_ticker_prices()の毎月呼出し。** 2x選出差では1785s vs 30sは説明不可。

---

## §4 高速化設計案

### 案A: キャッシュヒット時のprice loading早期スキップ（推奨）

TrendReversalFilterBlock.execute() L85-100付近に、oikazeと同じ早期リターンロジックを追加:

```python
# 全ティッカーがキャッシュ済みならload_ticker_prices()をスキップ
precomputed = context.momentum_cache.setdefault(self.block_id, {})
all_cached = all(ticker in precomputed for ticker in tickers)
if not all_cached:
    load_ticker_prices(...)  # 初回のみ
```

**期待効果**: 初回リバランスのみI/O。2回目以降はキャッシュ参照のみ。oikaze同等の30-60秒に短縮見込み。

### 案B: dict変換廃止（補助的改善）

L131の `{d: float(v) for d, v in zip(...)}` dict変換を廃止し、pd.Seriesを直接キャッシュ:
- dict生成オーバーヘッドは微小だが、Seriesのままならbisect lookupも可能に
- 案Aと併用で最大効果

### 案C: simulate_pattern外でのモメンタム事前計算（大改修）

全パターン共通のモメンタムを事前計算してキャッシュに注入。simulate_pattern内ではlookupのみ:
- 最も高速だがrun_077_kawarimi.pyの構造変更が大きい
- リスクも大。完全一致検証必須

### 推奨: 案A + 案B の組合せ

理由:
1. 変更範囲がtrend_reversal_filter.pyの`execute()`メソッド内に限定
2. oikazeで実証済みのパターンの移植であり新規設計ではない
3. 完全一致検証が容易（fast/seq比較で検証可能）
4. 複利: 今後のWF/L2計算でも自動的に効果発揮

---

## §5 nukimi同一構造確認

`run_077_nukimi.py` L552-676: `simulate_pattern()` は同じ月次ループ構造。
SingleViewMomentumFilterBlockを使用 — キャッシュ戦略が同一かは要コード確認。
**kawarimi修正後にnukimiも同パターンで速度計測推奨。**

---

## §6 cmd化提案

### cmd分割案（LG021: 3基準準拠）

**cmd_A: trend_reversal_filter.pyキャッシュ早期スキップ実装**
- AC1: load_ticker_prices()呼出しをキャッシュヒット時にスキップ
- AC2: dict変換をSeries直接キャッシュに変更
- AC3: 完全一致検証(fast/seq md5sum一致)
- AC4: 速度計測(before/after)
- 見積: 1忍者、1-2時間

**cmd_B: nukimi速度計測+必要なら同パターン修正**
- cmd_A完了後に実施
- AC1: nukimi月次速度計測
- AC2: 遅い場合は同パターン適用+完全一致検証

---

## §7 CS観点チェックリスト

- CS1(ソース全量): run_077_kawarimi.py simulate_pattern() + trend_reversal_filter.py execute() + run_077_oikaze.py simulate_pattern() + momentum_filter.py execute() 全て現物読了 ✓
- CS2(自システムデータ): 家老計測データ(37s/1832s/1785s)が問題の存在を実証 ✓
- CS3(実コード比較): L97(load毎月) vs L70(キャッシュスキップ)の差異をコード行番号で特定 ✓
- CS4(行動変換): cmd_A/cmd_B分割案として提示 ✓
- CS5(未検証角度): nukimiの同一構造は推定。cmd_Bで計測検証 ✓
- CS6(因果推論): §2.3に3段因果鎖記載 ✓
