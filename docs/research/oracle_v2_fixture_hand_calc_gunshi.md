# オラクルv2 Fixture手計算表 — 軍師独立計算

> 本ファイルは§3.8#4に基づく軍師側の独立手計算。家老側と2名独立で突合して凍結する。
> **オラクル自身で生成禁止** — 全期待値は本手計算から導出する。

## 確定仕様(v2.2殿裁定)

- 月次リターン区間: 当月初回取引日(執行日) → 翌月初回取引日
- Close系列: P_start = position_start_date close, P_end = position_end_date close
- Open系列: P_start = position_start_date open, P_end = position_end_date open
- Return = Σ wᵢ × (P_end/P_start - 1)
- 営業日 = SPY prices存在日 (business_day_utils.py L54-58)
- weights = 月初確定holding展開 (position_start_date時点)
- 価格 = prices.close/open (配当調整済み=adjusted。stock data API側で調整、DM-signal側は関与しない。§3.8#2殿確認2026-08-03 01:52)

## Fixture対象月

| # | 月 | 種別 | 選定理由 | PF |
|---|---|---|---|---|
| F1 | 2022-04 | 境界分割(執行ずれ) | §1c実例。4/1金→4/4月=執行日 | basicデュアルモメンタム |
| F2 | 2023-01 | 1日非営業日 | 1/1日=非営業日。執行日≠暦月1日 | basicデュアルモメンタム |
| F3 | 2022-03 | 通常月 | 3/1火=営業日。baseline | basicデュアルモメンタム |
| F4 | TBD | Partial(PF開始月) | §0.5規約1 | basic開始月を本番DBで特定 |
| F5 | 2026-08 | MTD | as_of固定(家老F10) | basicデュアルモメンタム |

## 手計算手順(1 fixture月あたり)

1. 本番DBからSPY prices日付で当月初回取引日(position_start)を特定
2. 翌月初回取引日(position_end)を特定
3. 当該PFのposition_start日のholding_signalからweights展開
4. 各ticker × 2系列(close/open)の価格をposition_start, position_endで取得
5. price_ratio = P_end / P_start を各tickerで計算
6. Return = Σ wᵢ × (ratio - 1) をclose系列・open系列で各1値算出
7. 期待値を本表に記録

## 手計算結果

### F1: 2022-04 境界分割月 (basicデュアルモメンタム)

- position_start_date: TBD (本番SPY prices確認要)
- position_end_date: TBD
- holding_signal: TBD
- weights: TBD
- 価格: TBD
- **Close Return**: TBD
- **Open Return**: TBD

### F2: 2023-01 1日非営業日月 (basicデュアルモメンタム)

(同構造。本番DB実測後に記入)

### F3: 2022-03 通常月 (basicデュアルモメンタム)

(同構造。本番DB実測後に記入)

### F4: Partial月

(PF開始月を特定後に記入)

### F5: 2026-08 MTD

(as_of固定値を決定後に記入)

## 状態

- [x] 確定仕様の文書化
- [x] P_start/P_end定義の現物照合 (return_calculator.py L245-249)
- [x] 営業日SSOTの現物照合 (business_day_utils.py L54-58)
- [x] Priceモデルの現物照合 (models.py L30-43, adjusted_closeなし)
- [ ] F1-F5の本番DB実測 ← 次手(/db-check)
- [ ] 手計算実施
- [ ] 家老側手計算との突合
- [ ] 凍結

## コード現物照合証跡

| §3.8# | 項目 | 現物 | 結果 |
|---|---|---|---|
| 1 | 営業日SSOT | business_day_utils.py L54-58 SPY基準 | ✅確認済み |
| 2 | 配当調整 | models.py L30-43 + 殿確認01:52 | ✅配当調整済み(adjusted)。stock data API側で調整、DM-signal側は関与しない |
| 3 | P_start/P_end | return_calculator.py L245-249 close/open × start/end | ✅系列別定義確定 |
| 7 | weights空fallback | return_calculator.py L212-225 weights空→return=0.0 | ⚠️fallback禁止と衝突(§3.8#7記載通り) |
| 11 | S1満月P_end | 不採用(S2確定) | ✅解消 |
