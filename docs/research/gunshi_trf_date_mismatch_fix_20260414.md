# FoF選択ブロック日付ミスマッチ — 根因分析+修正設計書

軍師分析 2026-04-14。将軍緊急調査依頼に基づく。

---

## §1 何が壊れているか

### 問題A（緊急・コードバグ）: 変わり身12体が全期間Cash 100%

| 忍法 | hs一致率 | 状態 |
|------|---------|------|
| **変わり身(3体)** | **0%** | **★全月Cash。本番壊れている** |
| 分身(3体) | 100% | 正常 |
| 追い風(3体) | 100% | 正常 |
| 加速D/R(6体) | 100% | 正常 |

影響PF: 変わり身(旧3+シン3) + 奥義変わり身3 + 奥義ALMシン変わり身3 = 12体

### 問題B（品質・スクリプトバグ）: 抜き身/四つ目が83-99%で完全一致しない

| 忍法 | hs一致率 | 不一致の性質 |
|------|---------|------------|
| 抜き身(3体) | 83-98% | 選択PFの入れ替わり(Cashではない) |
| 四つ目(3体) | 83-99% | 同上 |

不一致例: expected=PF-A, actual=PF-B。同じプールから**異なるPFが選ばれている**。

### 2つの問題は別根因

- **問題A**: TRFの**コードバグ**(dict.get()完全一致検索)。本番動線の問題。PI違反
- **問題B**: パリティスクリプトの**target_date設定ミス**。検証スクリプトの問題。productionは正常動作

---

## §2 根因（問題別）

**問題A**: TrendReversalFilterBlockがモメンタムキャッシュをdict.get()(完全一致)で検索。
productionのキャッシュは月末日キー(3/31)、検索日は営業日(3/3)→一致しない→全月None→Cash。
他の選択ブロック(MF/SVMF/MVMF)はget_momentum_value_at_date()(bisect)で正常動作。

**問題B**: パリティスクリプト(cmd_1898)がtarget_date=前月末日で選択ブロックを再実行。
productionは当月第1営業日を使用。skip_months=0ではbisect結果が偶然一致するが、
skip_months>0(抜き身SK3)では差が増幅され異なるモメンタム月を参照→選択PF反転。

---

## §3 なぜそうなるか

### 問題A: TRFがdict.get()を使う理由

```
04-03  TRF/MFにdict cache導入。両方ともdict.get()(完全一致)
04-07  bisect修正: MF/SVMF/MVMFの3ファイルを修正 ★TRFが漏れた★
04-10  commit 66e65ff3: TRFの候補不足時にset()追加 → Cash顕在化
```

dict.get()は月末キーと営業日target_dateが一致しないため常にNone:
```
cache:  {2025-01-31: v1, 2025-02-28: v2, 2025-03-31: v3}
target: 2025-03-03
dict.get(2025-03-03) → None（キーに3/3がない）
```

### 問題B: パリティスクリプトのtarget_date差異

追い風(skip=0)が100%でも抜き身(skip=3)が不一致になる理由:

```
■ skip=0(追い風): 差が吸収される
  パリティ: target=2/28 → bisect → 2/28  = 2月モメンタム
  production: target=3/3  → bisect → 2/28  = 2月モメンタム
  → 同じ → 100%

■ skip=3(抜き身): 差が増幅される
  パリティ: target=2/28, lookup=2/28-3mo=11/28 → bisect → 10/31 = 10月
  production: target=3/3,  lookup=3/3-3mo=12/3   → bisect → 11/30 = 11月
  → 異なる → 選択PF反転
```

---

## §4 なぜなぜ7回

### 問題A（コードバグ）

| # | 問い | 答え |
|---|------|------|
| 1 | 変わり身がCash 100% | commit 66e65ff3が候補不足時にCash化するコードを追加 |
| 2 | なぜ全月候補不足？ | TRFがdict.get()(完全一致)でモメンタム取得→全月None |
| 3 | なぜNone？ | キャッシュ=月末(3/31)、検索=営業日(3/3)。一致しない |
| 4 | なぜTRFだけdict.get()？ | 04-07のbisect修正がTRFに横展開されなかった |
| 5 | なぜ横展開漏れ？ | 同パターンの全ファイルをgrep確認する工程がなかった |
| 6 | **根因(構造)** | **同じ検索ロジックが5ファイルにコピペ散在。横展開の仕組みなし** |

### 問題B（スクリプトバグ）

| # | 問い | 答え |
|---|------|------|
| 1 | 抜き身/四つ目が83-99% | 少数月で選択PFが異なる |
| 2 | なぜ異なる？ | 参照するモメンタムの月がずれる |
| 3 | なぜずれる？ | パリティスクリプトとproductionのtarget_dateが異なる |
| 4 | なぜ異なるtarget？ | スクリプトL217: 前月末日。production: 当月第1営業日 |
| 5 | なぜ追い風は影響なし？ | skip=0ではbisect結果が偶然同じ月に着地。skip>0で差が増幅 |
| 6 | **根因** | **パリティスクリプトがproductionと異なるtarget_dateで再実行** |

### PI(本番不変量)による裏付け（問題Aのみ）

dm-signal-core.md L573-L578:
- L573: 「FoF月次キャッシュのlookupは**bisect helper統一**」[PI]
- L574: 「exact dict lookupすると**Cash全損**」[PI]

TRFバグ = PI違反。PIの対象リスト(MF/SVMF/MVMF)にTRFが漏れていた。

### signal ≠ holding_signal（殿指摘）

- **signal** = パイプラインが毎月計算する生出力
- **holding_signal** = リバランス月でなければ前月の保有を維持(dm-signal-core.md L268)
- パリティ基準はholding_signal一致(P1)

---

## §5 修正内容

### Phase 1: 緊急修正（変わり身12体Cash → 正常化）

**trend_reversal_filter.py 2箇所 + 潜在2箇所 = 計4箇所。** revert reset完了済み(12:17確認。HEAD=2482d9a0)。
全行番号は現HEADで grep確認済み(12:25)。

| # | 行 | Before | After | 効果 |
|---|----|----|----|----|
| A | L89 | dict.get()(完全一致) | get_momentum_value_at_date()(bisect) | キャッシュ参照の日付ミスマッチ解消 |
| B | L133 | dict.get()(完全一致) | get_momentum_value_at_date()(bisect) | 初回計算の日付ミスマッチ解消 |

L153の`context.current_tickers = set()`は66e65ff3で追加済みのため現存。修正不要。

```python
# Fix A: _lookup_cached を簡素化（MFのL85-87と同型にする）
# Before:
def _lookup_cached(cache_value: object) -> float | None:
    if isinstance(cache_value, dict):
        return cache_value.get(context.target_date)    # ← 完全一致=バグ
    val, _ = get_momentum_value_at_date(cache_value, context.target_date)
    return val

# After:
def _lookup_cached(cache_value: object) -> float | None:
    val, _ = get_momentum_value_at_date(cache_value, context.target_date)
    return val
# get_momentum_value_at_date()はdict/Series両対応(base.py L156-190)
```

### Phase 2: 品質修正（抜き身/四つ目を100%に）

**パリティスクリプトのtarget_dateをproductionと揃える。production動線は変更しない。**

```python
# cmd_1898_verify_okugi_alm_shin_parity.py L217
# Before: 前月末日
prior_month_end = (pd.Period(year_month, freq="M") - 1).to_timestamp(how="end").date()

# After: productionと同じ当月第1営業日
first_biz_day = pd.Timestamp(f"{year_month}-01") + pd.offsets.BDay(0)
context = PipelineContext(target_date=first_biz_day.date(), ...)
```

### 潜在バグ（Phase 1で同時修正。同パターン各1-2行。別cmdは横展開漏れ再発リスク）

| # | ファイル | 行 | Before | After |
|---|---------|----|----|-----|
| D1 | momentum_acceleration_filter.py | L82-86 | Fix Aと同型。dict分岐削除 | get_momentum_value_at_date()統一 |
| D2 | **jobs/**recalculate_fast.py | L390-393 | dict.get(target_date) | get_momentum_value_at_date() |

---

## §6 ゴールデンデータに関する注意

ゴールデンデータ(04-09生成)はTRFバグ状態で生成された。

| 忍法 | ゴールデンの状態 | 修正後の正しい状態 |
|------|----------------|------------------|
| 変わり身 | 全コンポーネント選択(バグ。非CashだがTop+Worstでもない) | Top+Worst選択(Phase 1) |
| 抜き身/四つ目 | productionは正常(前月モメンタム基準)。ゴールデンも正常 | 変化なし(Phase 2はスクリプト修正) |
| 分身/追い風/加速 | 正常 | 変化なし |

**→ Phase 1後の変わり身パリティ基準はゴールデンデータではなく、production API突合(P1基準)。**
fullrecalculate後にholding_signalがCashでないこと + 構成PFのUUIDが含まれていることを確認。

---

## §7 検証計画

### Phase 1検証
1. pytest backend/tests/ -k trend_reversal → 全PASS
2. push → Render deploy完了確認
3. fullrecalculate実行
4. 変わり身12体のholding_signalがCashでないことをAPI確認

### Phase 2検証
1. パリティスクリプトのtarget_date修正
2. 修正スクリプトで21体再検証 → 100%目標
3. deploy/fullrecalculate不要（スクリプト側の修正のみ）

### 推奨追加テスト
```python
def test_monthly_cache_date_mismatch():
    """target_date=月中日でもcacheからmomentum取得できること(FoF本番パス)"""
    context = PipelineContext(target_date=date(2025, 12, 28), ...)
    # キャッシュは月末日: {date(2025,12,31): 0.05}
    # bisectで2025-12-31を見つけて0.05を返すこと
```

---

## §8 予防策

| 対策 | 内容 |
|------|------|
| PI更新 | L574の対象リストにTRF/MAFを追加 |
| grep禁止パターン | `.get(context.target_date)` をblocks/内で禁止 |
| 日付ミスマッチテスト | 全選択ブロックでtarget_date≠月末のテスト追加 |

---

## §9 影響範囲まとめ

```
Phase 1(コード修正 cmd_1899): TRF 2箇所 + MAF 1箇所 + recalculate_fast 1箇所 = 計4箇所
                              + push + deploy + fullrecalculate → 変わり身12体正常化
Phase 2(スクリプト修正 別cmd): パリティスクリプトtarget_date修正 → 抜き身/四つ目100%化
                              (production動線は不変。Phase 1完了後に実行)
無影響: 分身/追い風/加速 — 既にbisect使用+100%一致
```
