# FoF Weight Breakdown Cash表示バグ — 設計書 v5

## 概要

admin画面のFoF設定ページ「Weight Breakdown」に、本来存在しないはずの「Cash 100%」が表示された。
35/101 FoFが影響。monthly trade画面やリターン計算には影響なし。admin表示のみの問題。
再計算で解消済み。根本修正が必要。

## 背景知識

### DM-Signalのポートフォリオ構造

```
Standard PF (77件): 個別の投資戦略。ティッカー(TQQQ/XLU/GLD等)を保有
  └─ パイプライン: MomentumFilter → SafeHavenSwitch → EqualWeight
     └─ 全銘柄脱落時 → SafeHavenSwitchが実資産(XLU/GLD等)に退避。Cashにはならない

FoF (101件): 複数のStandard PFを束ねるファンド・オブ・ファンズ
  └─ パイプライン: MomentumFilter系 → EqualWeight
     └─ コンポーネントPFの中から上位N件を選出
     └─ SafeHavenSwitchがない ← Standard PFとの構造的差異
```

### fof_component_weights テーブル

FoFの日次コンポーネントウェイトを記録するテーブル。admin画面のWeight Breakdown表示専用。
リターン計算やsignalsテーブルは参照しない。

書込み: `recalculate_fof.py` → `_flush_fof_component_weights` (UPSERT方式)
読取り: admin API `/fof-weights/{id}` → `WeightBreakdown.tsx`

### パイプラインの「Cash」

パイプラインのselection blockが全コンポーネントを脱落させた場合、ターミナルブロック(EqualWeight等)が
signal="Cash", weights={"Cash": 1.0} を返す。これは「選出できなかった」ことを示すフォールバック値。

L0 (trade-rule.md §2.2): 全178PFにsafe_haven_assetとして実資産(XLU/GLD等)が設定されており、
Cash保有が発生する正規設定は本番に存在しない。**Cash = 常にバグの兆候。**

## Why — なぜ発生したか

### 直接原因

4/10のcommit `66e65ff3` がTrendReversalFilter(変わり身)のロジックを変更。
候補不足(insufficient_candidates)時に `current_tickers = set()` (空)を設定するようにした。
batch計算とsequential計算のパリティ修正が目的で、修正自体は正しい。

**副作用**: FoFパイプライン実行時、TRFが候補不足 → current_tickers空 → EqualWeight → signal="Cash" → weights={"Cash": 1.0} → fof_component_weightsにcomponent_id='Cash'がINSERT。

4/14のcommit `0a735680` でこのset()を撤去。新規Cash行の生成は停止。

### 残存原因

`_flush_fof_component_weights`はUPSERT方式（INSERT or UPDATE）。
unique key = (portfolio_id, date, component_id)。

**不要になった行のDELETEがない。** Cash行がINSERTされた後、コード修正でCashが生成されなくなっても、既存のCash行はDBに残り続ける。再計算してもUPSERTは新しい行の追加/更新のみ行い、古いCash行には触れない。

### cronjobによる蓄積

Render上のcronjob `sync-fof` が毎日01:40 UTC(10:40 JST)に自動実行。
4/10のデプロイ後、cronjobが毎日Cash行を追加。4/14の修正デプロイまでの4日間、Cash行が蓄積。

### 影響が限定的だった理由

fof_component_weightsはadmin UI表示専用テーブル。signalsテーブルのholding_signalは月初リバランス日のみ更新されるため、daily cronjobの非リバランス日ではCashがsignalsに波及しなかった。結果、monthly trade画面やリターン計算は正常のまま。

## As-Is — 現状

### 問題箇所

1. **`_flush_fof_component_weights` (fof_flush.py L94)**: UPSERT方式。stale行のDELETEなし
2. **`recalculate_fof.py` L929**: weights辞書を無検証でcomponent_weights_batchに書込み。component_idがUUIDかどうかチェックしない
3. **`WeightBreakdown.tsx` L134**: portfolioに該当しないcomponent_idをID先頭8文字+"..."で表示。不正データを正常のように見せる

### Cash発生パス(ローカルテスト実証済み)

| selection block | データなし→Cash | 実証 |
|----------------|----------------|------|
| MultiViewMomentumFilter | YES | ✅ |
| SingleViewMomentumFilter | YES | ✅ |
| TrendReversalFilter | YES | ✅ |

### 本番DB状態(再計算後)

全項目0件。殿による手動DELETE+再計算で浄化済み。現時点でクリーン。

## To-Be — あるべき姿

flush時にstale行を自動削除。admin UIが不正データを表示しない。

## What — 変更内容

### 必須修正(1件)

**`_flush_fof_component_weights`にstale行DELETE追加。**

flush実行前に、対象portfolio_idの対象期間の既存行を全DELETE → 新データをINSERT。
これにより、コード修正後の再計算/cronjobで不要なCash行が自動的に消滅する。

```python
# Before flush: DELETE existing rows for this portfolio in the date range
db.execute(
    delete(FoFComponentWeight).where(
        FoFComponentWeight.portfolio_id == portfolio_id,
        FoFComponentWeight.date >= min_date,  # weights batchの最小日付
    )
)
```

### 防御的修正(2件)

1. **`recalculate_fof.py` L929**: `comp_id in component_ids_set` バリデーション追加。UUID以外のkeyを書込み前に排除
2. **`WeightBreakdown.tsx`**: allPortfoliosに存在しないcomponent_idを非表示。DBに不正データがあってもUIが防御

### 将来検討(必須ではない)

- 13箇所の`current_tickers = set()`パスにlogger.error追加（Cash fallbackのサイレント処理を可視化）
- selection block変更時のfof_component_weights影響テスト追加

## How — 実装手順

1. `fof_flush.py` `_flush_fof_component_weights`にDELETE追加
2. `recalculate_fof.py` L929にcomponent_ids_setバリデーション追加
3. `WeightBreakdown.tsx`に非portfolio filterr追加
4. テスト: flush後にCash行が残存しないことを確認
5. deploy + cronjob sync-fof実行で自動浄化確認

## 時系列まとめ

| 日付 | 事象 |
|------|------|
| 4/7 | `04f74830` momentum lookup bisect修正 |
| 4/10 | `66e65ff3` TRF insufficient_candidates→set()追加 **← バグ導入** |
| 4/10〜14 | cronjob sync-fofが毎日Cash行を生成・蓄積 |
| 4/14 | `0a735680` TRF set()撤去 **← バグ修正。しかし既存Cash行は残存(UPSERT DELETE不在)** |
| 4/14 | 殿がadmin画面でCash 100%発見 |
| 4/14 | 殿による手動DELETE+再計算でDB浄化 |

## 検証済みの事実

| 確認項目 | 結果 | 方法 |
|---------|------|------|
| Cash設定のあるPF | 0/178件 | DB全量検査 |
| admin以外の影響 | なし | 殿確認 |
| MVMF/SVMF/TRF Cash発生 | 実証済み | ローカルテスト |
| UPSERT DELETE不在 | 確認済み | fof_flush.pyコード確認 |
| 再計算後DB Cash行 | 0件 | DB確認 |
| 66e65ff3が直接原因 | 確認済み | git diff |
| 0a735680で修正済み | 確認済み | git diff |

## 再発リスク評価

**直接原因(66e65ff3)は修正済み。しかし構造的に再発しうる。**

| リスク要因 | 状態 | 再発時の影響 |
|-----------|------|------------|
| 13箇所の`current_tickers = set()`パス | **現存** | 将来のcommitで再活性化→Cash行生成 |
| UPSERT DELETE不在 | **未修正** | Cash行が入ったら手動DELETE以外で消えない |
| cronjob毎日自動実行 | **常時稼働** | バグ導入→発見まで毎日Cash行蓄積 |

**flush DELETE追加(What必須修正)が未実施の場合**: 同種のバグ再発時にadmin表示異常が再現し、手動介入が必要。
**flush DELETE追加後**: 仮にCash行が入っても次回再計算/cronjobで自動消滅。手動介入不要。
