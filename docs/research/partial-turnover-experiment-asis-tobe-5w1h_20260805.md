<!-- gist-master: b70512e1263db4a80042acb63c39778c partial-turnover-experiment-asis-tobe-5w1h_20260805.md -->
# 段階的リバランス(Partial Turnover) — 実験設計書 AsIs/ToBe 5W1H v1.5

> v1.5(2026-08-05 23:11 軍師draft review反映): 存在しない`PipelineEngine.expand()`参照を除去。本番ticker×weight展開の正本を`backend/app/services/price_ratio_impl.py:1045`の`expand_portfolio_to_tickers()`、独立oracleを`backend/scripts/analysis/monthly_return_oracle.py:51`の`expand_weights()`と明記。read-only直接SQLの許可経路を`/mnt/c/tools/multi-agent-shogun/scripts/db_capability_launcher.py readonly_query`へ固定

> v1.4(2026-08-05 22:40 殿裁定): 現在の実行許可scopeは§2.5で指定した12体のみ。全102体は殿が明示的に追加指示するまで実行禁止。初期実験の結果から全量へ自動遷移せず、指定PFの結果を殿へ報告して次の指示を待つ

> v1.3(2026-08-05 22:33 家老REVISE 4指摘修正): B1 初期12体はsmoke test(parity+pipeline検証)に限定、結果に関係なく全102体へ進む。B2 α=1.0復元→5α。B3 §0 L0定義とオリジナル分類の包含矛盾を解消(102体=L0 16+オリジナル4+L1 33+L2 24+L3 25)。B4 parity許容差≤1e-12・paired同期間・ノイズ帯・指標優先順位を定義

> v1.2(2026-08-05 18:57 殿指示): §2.5初期実験(12体)を追加。小規模で効果の方向性を確認してから全量展開する二段構成に変更

> v1.1(2026-08-05 17:14 殿指摘反映): PF層別体数を本番DB実測値に修正(L0=20/L1=33/L2=24/L3=25)。v1.0は旧データ(L0=12/L1=20/L2=21/L3=12)を使用していた

> v1.0(2026-08-05 16:16 殿発案): 月次リバランス日に前月ポジションの一部を維持し、新シグナルのポジションと混合する効果を実験

## §0 前提知識 — この実験を理解するために必要な背景

### DM-Signalのリバランス方式(現行)

DM-Signalは月次デュアルモメンタム投資システムである。毎月の**リバランス日**に:
1. モメンタム指標で保有すべきETFを判定（= **holding_signal**）
2. 前月のポジションを**100%売却**
3. 新シグナルのポジションを**100%買付**

### holding_signalの構造

全てのPF（Standard/FoF/ネステッドFoF）は最終的に**ticker×weight**に分解される:

```
例1: Standard PF「シン青龍-激攻」
  holding_signal = TQQQ 50%, UPRO 50%
  → ticker×weight: {TQQQ: 0.5, UPRO: 0.5}

例2: FoF「奥義-GS-変わり身-鉄壁」
  holding_signal = component_pf_uuid1, component_pf_uuid2
  → 各コンポーネントを再帰展開
  → 最終ticker×weight: {XLU: 0.375, GLD: 0.125, TLT: 0.25, TMF: 0.25}

例3: ネステッドFoF「秘奥義-加速R-鉄壁」
  holding_signal = component_fof_uuid
  → FoFを展開 → さらにStandardを展開
  → 最終ticker×weight: {XLU: 0.75, GLD: 0.25}
```

### PF階層 — 本番DB実測 2026-08-05

| 分類 | 名称 | 本番体数 | 構成 | DB type |
|---|---|---|---|---|
| L0 | シン四神(12体)+basic DM系(4体) | 16体 | 個別ETF直接保有 | standard |
| オリジナル | Ave-X, 裏Ave-X, 劇薬DM*, DM-safe* | 4体 | 独自構成のFoF(L0-L3階層外) | standard 4 + fof 4 混在 |
| L1 | シン忍法/GSシン* | 33体 | L0をBBで加工(MomentumFilter等) | fof |
| L2 | 奥義 | 24体 | L1を構成PFとするFoF | fof |
| L3 | 秘奥義 | 25体 | L2を構成PFとするネステッドFoF | fof |

合計: standard 24体 + fof 78体 = **102体**(DB実測一致)

**注**: オリジナル(Ave-X/劇薬DM等)はL0-L3の階層構造(シン四神→シン忍法→奥義→秘奥義)とは別系統。DB typeはstandard/fof混在だが、本実験では全てticker×weightに展開するため区別不要。

### リバランス頻度

- monthly(毎月) — 大半のPF
- bimonthly(隔月) — 一部
- quarterly(四半期) — 一部

非リバランス月は前月のポジションをdriftで保有し続ける。

### 月次リターン計算

月次リターンは**リバランス日の各ticker×weightの日次リターンを積み上げ**て算出される:
```
monthly_return = Π(1 + Σ(weight_i × daily_return_i)) - 1
```
weightは月初のリバランス日に決定され、月中は変化しない(buy-and-hold前提)。

## §META — 5W1H

| 項 | 内容 |
|---|---|
| WHY | 現行の一括100%入替はターンオーバーが大きく、特にレバレッジETF(TQQQ/UPRO/TMF)で月初のインパクトが集中する。前月シグナルに一定の持続性がある場合、段階的入替がリスク調整後リターンを改善する可能性がある。また、FoF加速度フィルタ振動問題(本日発見)のような境界近傍での急激な切替を緩和する効果も期待される |
| WHAT | 月次リバランス日に前月ポジションのα%を維持し、新シグナルの(1-α)%を買付する方式（段階的リバランス/Partial Turnover）の効果を**全PF全期間バックテスト**で検証する |
| WHO | 実験実行=忍者(家老配備)。実験設計=将軍 |
| WHEN | 殿裁可後 |
| WHERE | 実験スクリプト=`/mnt/c/Python_app/DM-signal/scripts/analysis/`配下。**本番コード変更なし** |
| HOW | 下記§ToBe実験設計 |

## §1 AsIs — 現行方式

### リバランスフロー(一括入替)

```
月初リバランス日:
  1. モメンタム計算 → 新holding_signal決定
  2. 新holding_signalをticker×weightに展開
  3. ポートフォリオ = 新ticker×weight × 100%

  例: 7月=QQQ50%+GLD50% → 8月=XLU75%+GLD25%
  8月のポートフォリオ: XLU 75%, GLD 25%
  (QQQは0%。7月の保有は完全に消える)
```

### リターン計算

```python
# 現行: 月初のholding_signalのticker×weightで月末まで保有
for each_day in month:
    daily_pf_return = sum(weight[ticker] * daily_return[ticker] for ticker in holdings)
monthly_return = product(1 + daily_pf_return for each_day) - 1
```

## §2 ToBe — 段階的リバランス実験

### 原理

**前月ポジションのα%を維持し、新シグナルの(1-α)%で買付する。**

```
月初リバランス日:
  1. モメンタム計算 → 新holding_signal決定
  2. 前月ticker×weight × α + 新月ticker×weight × (1-α) = 混合ticker×weight
  3. ポートフォリオ = 混合ticker×weight

  例(α=0.5): 7月=QQQ50%+GLD50% → 8月=XLU75%+GLD25%
  混合: QQQ×0.5×50% + GLD×0.5×50% + XLU×0.5×75% + GLD×0.5×25%
       = QQQ 25% + GLD 25% + XLU 37.5% + GLD 12.5%
       = QQQ 25% + XLU 37.5% + GLD 37.5%  (同一ticker合算)
```

### 特殊ケース

**同一シグナルの場合**: 7月=QQQ100% → 8月=QQQ100%
→ 混合後もQQQ 100%。α の値に関係なく結果は同じ。

**Cash含みの場合**: 7月=Cash → 8月=TQQQ50%+UPRO50%
→ α=0.5なら: Cash 50% + TQQQ 25% + UPRO 25%
→ Cashポジション(=無リスク)が混合に残る。

**FoF/ネステッドFoFの場合**: 全てticker×weightに展開してから混合する。
FoFのholding_signal(コンポーネントPF UUID)ではなく、展開後のETF ticker×weightで混合する。

### 実験パラメータ

| パラメータ | 値 | 意味 |
|---|---|---|
| α (前月維持率) | [0.0, 0.25, 0.5, 0.75, 1.0] | 0.0=現行(一括入替)、1.0=前月全維持(リバランスしない) |
| 現在の対象PF | §2.5の指定12体 | 殿が指定したPFだけで実験 |
| 将来候補 | 全102体 | 殿の追加指示があった場合のみ実行 |
| 期間 | 全期間(各PFのdata_start_date〜最新) | パラメータ空間縮小禁止(殿厳命) |

### 計測指標(v1.3 B4修正+殿指示: 3指標に絞る)

**パリティ許容差**: α=0の結果と本番monthly_returnsの差 ≤ 1e-12(IEEE 754ノイズ=既存パリティ基準L392準拠)。パリティFAILなら実験全体を停止し展開ユーティリティのバグを修正する。

**比較方法**: 全指標は**paired同期間比較**(同一PF×同一期間でα=0 vs α>0)。PFごとのdata_start_dateが異なるため、期間を揃えないと比較が無効。

| 指標 | 説明 | 判定基準 |
|---|---|---|
| CAGR | 年率換算リターン | α=0(現行)との差。同一PF×同一期間のpaired比較 |
| シャープレシオ | リスク調整後リターン | α=0より改善するか。同一PF×同一期間のpaired比較 |
| MaxDD | 最大ドローダウン | α=0と比較して悪化しないか。同一PF×同一期間のpaired比較 |

**比較の本質**: 各PFについて「現行一括リバランス(α=0) vs 段階的リバランス(α>0)」の2者比較。PF間の相対比較は目的ではない。

### 追加分析

1. **層別傾向**: L0/オリジナル/L1/L2/L3で段階的リバランスの効果傾向に差があるか

## §2.5 初期実験 — 12体で効果の方向性を確認(殿指示 v1.2追加)

### 目的

現在の実行許可scopeは以下の**指定12体×全期間**のみ。効果の方向性(改善/悪化/中立)を確認して殿へ報告する。**全102体は殿の追加指示があるまで実行しない**。

### 対象PF(12体)

| 分類 | PF名 | 選定理由 |
|---|---|---|
| オリジナル | Ave-X | 独自構成のFoF。多銘柄で分散効果を検証 |
| オリジナル | 劇薬DMオリジナル | 独自構成のFoF。レバレッジETF主体(ターンオーバーインパクト大) |
| L0 | シン青龍-激攻 | シン四神激攻4体(L0の主力。銘柄宇宙が共通で層別比較に最適) |
| L0 | シン朱雀-激攻 | 同上 |
| L0 | シン白虎-激攻 | 同上 |
| L0 | シン玄武-激攻 | 同上 |
| L1 | GSシン分身-激攻 | L1代表(分身=TrendReversalFilter系) |
| L1 | GSシン四つ目-激攻 | L1代表(四つ目=MultiViewMomentumFilter系) |
| L2 | 奥義-GS-分身-激攻 | L2代表(FoF。L1分身を構成PFに持つ) |
| L2 | 奥義-GS-四つ目-激攻 | L2代表(FoF。L1四つ目を構成PFに持つ) |
| L3 | 秘奥義-分身-激攻 | L3代表(ネステッドFoF。L2分身を構成PFに持つ) |
| L3 | 秘奥義-四つ目-激攻 | L3代表(ネステッドFoF。L2四つ目を構成PFに持つ) |

**注**: Ave-Xと劇薬DMオリジナルはtypeがFoFだが、L0-L3の階層構造(シン四神→シン忍法→奥義→秘奥義)とは別系統のオリジナルPFであるため、L0-L3とは別軸で扱う。

### 初期実験の目的と判定基準(v1.3 B1修正)

**目的**: 指定12体でパイプライン検証と効果計測を行う。結果は殿へ報告し、全102体へは自動的に進まない。

| 検証項目 | 判定基準 |
|---|---|
| α=0パリティ | 12体全てで本番monthly_returnsとの差 ≤ 1e-12。FAILなら展開ユーティリティのバグ修正 |
| ticker×weight展開 | Standard/FoF/ネステッドFoF全層で正常展開。エラー0件 |
| blend関数 | 同一ticker合算・Cash混合・同一シグナルの各特殊ケースが正常動作 |
| 計測指標計算 | 7指標全てが計算可能(NaN/Inf 0件) |

**PASSとは上記4項目全てOK。PASS/FAILいずれも結果を殿へ報告し、追加指示を待つ。**

### 初期実験の手順

```
1. 12体のデータ取得(Phase 1と同じ手順。対象を12体に限定)
2. α=[0.0, 0.25, 0.5, 0.75, 1.0]の5段階で12体×全期間バックテスト(正本5αを継承)
3. 計測指標7項目を12体×5αで計算
4. 判定基準に照らして指定12体内の結果を分類
5. 結果を殿に報告して追加指示を待つ。全102体へ自動遷移しない
```

## §3 実験実行手順

### Phase 0: 初期実験(12体) ← v1.2追加

```
1. 本番DBから12体のデータ取得(read-only)
2. ticker×weight展開ユーティリティ作成+α=0パリティ検証
3. 12体×5αバックテスト実行
4. smoke test 4項目判定(parity/展開/blend/指標計算)
5. PASS/FAILと効果値を殿へ報告 → 追加指示待ち
```

### Phase 1: データ準備(read-only) — 殿が全102体を追加指示した場合のみ

```
1. 本番DBから以下を取得(read-only):
   - 全102体のportfolio_id + pipeline_config + rebalance_trigger
   - 全期間のholding_signal(signals テーブル)
   - 全期間のprices(日次ETF価格)
   - 全期間のmonthly_returns(ベースライン比較用)
2. ローカルSQLiteにキャッシュ(本番DBへの負荷軽減)
3. Phase 0で作成済みのticker×weight展開ユーティリティを再利用
4. 展開結果をα=0で計算し、本番monthly_returnsとのパリティ検証(完全一致)
```

### Phase 2: バックテスト実行 — 殿が全102体を追加指示した場合のみ

```
1. 各αで全102体の月次リターンを再計算:
   for each pf:
     prev_weights = {}  # 初月は空
     for each month:
       new_signal = get_holding_signal(pf, month)
       new_weights = expand_to_ticker_weights(new_signal)
       mixed = blend(prev_weights, new_weights, alpha)
       monthly_ret = calculate_return(mixed, daily_prices[month])
       prev_weights = mixed  # 翌月の「前月」になる

2. α=0の結果が本番monthly_returnsと完全一致することを検証(パリティ)
3. 計算結果をローカルDBに保存(α, pf_id, year_month, monthly_return, cumulative_return, weights)
```

### Phase 3: 分析・報告

```
1. 全PF×全αのCAGR+シャープレシオ+MaxDDテーブルを生成(各PFでα=0 vs α>0のpaired比較)
2. 層別(L0/オリジナル/L1/L2/L3)の傾向サマリ
3. 結果をgistで殿に報告
```

## §4 実装分解

| # | 内容 | 依存 | 並列可能 |
|---|---|---|---|
| 1 | データ取得+ticker×weight展開ユーティリティ+パリティ検証(Phase 1) | なし | — |
| 2 | バックテストエンジン(blend関数+月次リターン再計算)(Phase 2) | 1 | — |
| 3a | L0(20体)×5α バックテスト実行(殿の追加指示後のみ) | 2 | ✅ |
| 3b | L1(33体)×5α バックテスト実行(殿の追加指示後のみ) | 2 | ✅ |
| 3c | L2(24体)×5α バックテスト実行(殿の追加指示後のみ) | 2 | ✅ |
| 3d | L3(25体)×5α バックテスト実行(殿の追加指示後のみ) | 2 | ✅ |
| 4 | 分析・可視化・報告(Phase 3) | 3a-3d | — |

3a-3dは独立で並列可能(4忍者)。

## §5 decision ledger

| 項 | 状態 |
|---|---|
| 段階的リバランス実験の実施 | 殿発案2026-08-05 15:57。裁可待ち |
| α探索範囲 [0.0, 0.25, 0.5, 0.75, 1.0] | 提案。裁可対象 |
| 現在の実行対象PF | **§2.5の指定12体のみ(殿裁定2026-08-05 22:40)** |
| 対象PF = 全102体 | 将来候補。**殿が明示的に追加指示するまで実行禁止** |
| 対象期間 = 全期間 | 提案(パラメータ空間縮小禁止)。裁可対象 |
| 本番コード変更 | 禁止。実験スクリプトのみ |
| ticker×weight展開のFoF再帰ロジック | 本番正本=`backend/app/services/price_ratio_impl.py:1045`の`expand_portfolio_to_tickers()`。独立oracle=`backend/scripts/analysis/monthly_return_oracle.py:51`の`expand_weights()`。`PipelineEngine.expand()`は存在しないため参照禁止 |

## §6 因果リンク

- origin: `[[殿発案_段階的リバランス_20260805]] -> [[半分ずつ入替の効果検証]] -> [[全PF全期間バックテスト実験設計]]`
- → [[dmsignal_operations]] DM-Signal運用。月次リバランスの現行方式
- → [[fof-acceleration-oscillation-experiment]] FoF加速度フィルタ振動問題。段階的リバランスが振動緩和効果を持つ可能性
- → [[production_parity]] パリティ検証。α=0で本番一致を確認してからα>0の実験
- → [[殿裁定_サイズ調整のみ_20260608]] 「シグナルはルールで判定する。やるのはサイズ調整のみ」
