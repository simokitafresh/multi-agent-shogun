<!-- gist-master: a73798d8a4cbdf967d1cd5b47201b331 partial-turnover-experiment-asis-tobe-5w1h_20260805.md -->
# 段階的リバランス(Partial Turnover) — 実験設計書 AsIs/ToBe 5W1H v1.14 【Phase 1: 75体完走・方法論確定】

> v1.14(2026-08-06 02:45 才蔵実測+殿下知): Phase 1は指定75/75PF・375/375セルを完走し、alpha=0 parity 75/75、mismatch/weight failure/禁止参照/本番書込0。試行錯誤は実験値でなく完了証跡の組立順序が原因と確定し、専用commit→実hash/path確認→report記録→最終gateを正順序として§4.1へ恒久化

> v1.13(2026-08-06 02:09 殿指示): Phase 0(12体)PASS確認済み。Phase 1としてL0(12)+L1(21)+L2(21)+L3(21)=75体×5α=375セルに展開。分析軸: 忍法7種別+モード3種別(激攻/常勝/鉄壁)の効果差。history.py方式(v1.12確定)を継続

> v1.12(2026-08-06 01:28 将軍最終調査+殿スクリーンショット確認): 本番表示にバグなし。history.py方式(holding_signal再帰展開+均等合算)を確定

> v1.11(2026-08-06 01:10 三者独立調査・家老一次結果): FoF非unit真因確定。`expand_portfolio_to_tickers()`の選択後再正規化不在。monthly_returnsもdisplay_ticker_weightsも使わない方式へ

> v1.10(2026-08-06 01:00 指定12PF実測同期): `cmd_partial_turnover_phase0_v19`は指定12/12PF・5α=60/60セルを完走し、指定外PF0・全102PF実行0・本番書込0・FAIL0・SKIP0を維持した。一方、FoF 4体の`display_ticker_weights`にweight合計非unit 35行、α=0 parity不一致29/2,096行(max abs diff=0.1713575056)を検出し、PF単位parityは8/12。軍師レビューと家老ACCEPTを経て正式FAIL-closeし、補正・fallback・FoF展開・102PF展開は行っていない。次のデータソース方式は殿の追加指示までBLOCK。

> v1.9(2026-08-06 00:27 飛猿BLOCK+DB再確認): Standard PFのdisplay_ticker_weightsはNULL(DB実測)。ticker×weight取得を2経路に明確化: Standard=`holding_signal`カンマ分割→均等1/N weight、FoF/ネステッドFoF=`momentum_data->>'display_ticker_weights'`。両経路ともDB格納済みデータのみ使用、FoF展開ロジック不要は不変

> v1.8(2026-08-06 00:05 殿指摘+DB一次確認): v1.7 BLOCKを解除。FoFのticker×weightは`display_ticker_weights`に確定値として保存済み。**Standard PFはNULL(v1.9で是正)**

> v1.7(2026-08-05 23:33 本番read-only一次確認): BLOCK(holding_signal=UUID列挙8/12)。**v1.8で解除済み — display_ticker_weightsが正解**

> v1.6(2026-08-05 23:18 殿指示・大幅簡素化): モメンタム計算・FoF展開・パイプライン再現は全て不要。既存のholding_signal(ticker×weight確定済み)をそのまま利用する方式に全面変更。「1カ月遅れシグナルのリターンを計算して元と比較するだけ」(殿)

> v1.5(2026-08-05 23:11 軍師draft review反映): 存在しない`PipelineEngine.expand()`参照を除去。本番ticker×weight展開の正本を明記

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

## §2 ToBe — 段階的リバランス実験(v1.6 大幅簡素化)

### 原理(殿方式)

**既存のholding_signal(ticker×weight確定済み)をそのまま利用する。** モメンタム計算・FoF展開・パイプライン再現は一切不要。

各PFについて2つのmonthly_returnを計算するだけ:
- **R_current**: 当月のholding_signalのticker×weightで計算したリターン(=本番の値)
- **R_lagged**: **前月**のholding_signalのticker×weightで**当月**の日次価格から計算したリターン(=1カ月遅れ)

段階的リバランスのリターン = `α × R_lagged + (1-α) × R_current`

```
例: あるPFの8月
  7月のholding_signal = QQQ 50% + GLD 50%  (確定済み)
  8月のholding_signal = XLU 75% + GLD 25%  (確定済み)

  R_current = 8月のXLU 75%+GLD 25%のリターン (=本番monthly_return)
  R_lagged  = 8月のQQQ 50%+GLD 50%のリターン (=7月シグナルで8月の価格を計算)

  α=0.5: 段階的リターン = 0.5 × R_lagged + 0.5 × R_current
```

**R_laggedさえ作れば、αは自由自在に動かせる。**

### 実験パラメータ

| パラメータ | 値 | 意味 |
|---|---|---|
| α (前月維持率) | [0.0, 0.25, 0.5, 0.75, 1.0] | 0.0=現行、1.0=前月全維持 |
| 現在の対象PF | §2.6の指定75体 | L0=12、L1-L3=各21。全102体は実行禁止 |
| 期間 | 全期間(各PFのdata_start_date〜最新) | パラメータ空間縮小禁止 |

### 計測指標(3指標)

各PFについて「現行(α=0) vs 段階的(α>0)」のpaired同期間比較。PF間の相対比較は目的ではない。

| 指標 | 判定基準 |
|---|---|
| CAGR | α=0との差 |
| シャープレシオ | α=0より改善するか |
| MaxDD | α=0と比較して悪化しないか |

### パリティ検証

α=0のR_currentは本番monthly_returnsと一致するはず。差 ≤ 1e-12(IEEE 754ノイズ)で検証。FAILなら計算ロジックのバグ。

### 指定12PFの実測結果(v1.10)

| 二値項目 | 実測 | 判定 |
|---|---:|---|
| 指定PF / 指定外PF | 12/12 / 0 | PASS |
| Standard / FoF | 4/4 / 8/8 | PASS |
| αセル / duplicate / missing | 60/60 / 0 / 0 | PASS |
| 全102PF実行 / 本番書込 | 0 / 0 | PASS |
| FoF weight合計非unit | 35行(4PF) | FAIL |
| α=0 parity | 8/12PF、29/2,096行不一致 | FAIL |
| 最大絶対差 | 0.1713575056 | FAIL |

結論: Standard 4PFの`holding_signal`均等1/N経路は成立したが、FoFの`display_ticker_weights`直接経路は全履歴でunitかつ本番月次と一致するという前提を満たさない。無断の正規化や別経路への切替はせず、本方式をFAIL-closeする。

### FoF非unitの因果(v1.11)

```text
全候補custom weightsを合計1へ正規化
  → holding_signalの選択IDだけを残す
  → 残存massを再正規化しない
  → 選択外候補のmassが消失
  → L2のdisplay合計<1
  → L3へ再帰伝播
```

- 実装位置: `backend/app/services/price_ratio_impl.py` の`expand_portfolio_to_tickers()`。正規化後の`selected_pf_ids` filter後に再正規化がない。
- 完全再現: L2 bad 17/17行で`actual_display_sum == Σ(parent_weight × child_selected_mass)`。
- 代表例: 奥義-GS-分身-激攻 2012-03-01は`0.75 = 0.5×1.0 + 0.5×0.5`。
- 月次確定式: `_generate_monthly_returns()`が月初の展開weightを別途求め、`Σ weight × (price_ratio - 1)`を保存する。verified ledger weightが存在するときだけそちらを優先する。
- 境界: 保存済みdisplayをmonthly_returnsの入力SSOTとみなさない。展開関数の修正、既存月次の正当性、実験用weightの採用方式は別々に二値検証するまで未決。

## §2.5 Phase 0対象PF(12体・殿指定、完了済み)

**全102体は殿の追加指示があるまで実行禁止。**

| 分類 | PF名 |
|---|---|
| オリジナル | Ave-X, 劇薬DMオリジナル |
| L0 | シン青龍-激攻, シン朱雀-激攻, シン白虎-激攻, シン玄武-激攻 |
| L1 | GSシン分身-激攻, GSシン四つ目-激攻 |
| L2 | 奥義-GS-分身-激攻, 奥義-GS-四つ目-激攻 |
| L3 | 秘奥義-分身-激攻, 秘奥義-四つ目-激攻 |

## §2.6 Phase 1対象PF(75体・殿指定、完了済み)

| 層 | 対象 | PF数 | DB type |
|---|---|---:|---|
| L0 | シン四神4種×3モード | 12 | standard |
| L1 | GSシン忍法7種×3モード | 21 | fof |
| L2 | 奥義7種×3モード | 21 | fof |
| L3 | 秘奥義7種×3モード | 21 | fof |
| 合計 | 指定L0-L3のみ | **75** | standard 12 + fof 63 |

**全102PFへの実験は未許可のまま。** オリジナルPFと指定75以外はPhase 1で実行していない。

### Phase 1実測結果(v1.14)

| 二値項目 | 実測 | 判定 |
|---|---:|---|
| 対象 / 層別 | 75/75 / 12+21+21+21 | PASS |
| αセル / duplicate / missing / FAIL / SKIP | 375/375 / 0 / 0 / 0 / 0 | PASS |
| alpha=0 parity / mismatch | 75/75 / 0 | PASS |
| weight failure / 禁止参照 / fallback | 0 / 0 / 0 | PASS |
| 指定外実験 / 全102実行 / 本番書込 | 0 / 0 / 0 | PASS |
| target date / production fullrecalculate logical date | 2026-08-03 / 2026-08-03 | PASS |

結果正本: `/mnt/c/Python_app/DM-signal/docs/research/partial-turnover-phase1-75pf-results-20260806.md`、実装commit: `d14a4ec3ce8457ce17ef702079028dbb9c58a367`。

## §3 実験手順(4ステップ) — v1.12 history.py方式

**データソース**: `display_ticker_weights`と`expand_portfolio_to_tickers`は使わない。本番表示と同じ`history.py L224-237`方式(holding_signal再帰展開+均等1/N合算+同一ticker合算)を再現する。

```
Step 1: データ取得(本番DB read-only)
  - 75体の全期間signals(holding_signal + portfolio_id)
  - FoFのcomponent_portfolios(portfolios.config->>'component_portfolios')
  - 日次ETF価格(pricesテーブル)
  - 本番monthly_returns(パリティ検証用)

Step 2: ticker×weight展開(history.py方式再現) + R_lagged計算
  - 全PF共通の展開ロジック:
    1. PFのholding_signalを取得
    2. Standard PF → holding_signalカンマ分割 = ticker一覧。均等1/N weight
    3. FoF → holding_signalカンマ分割 = コンポーネントPF UUID一覧
       → 各コンポーネントPFのholding_signalを再帰取得(Standardに到達するまで)
       → 全Standard tickerを均等weight(1/component数/ticker数)で合算
       → 同一tickerのweightを合算 → 合計1.0
    4. パリティ: α=0でR_currentを本番monthly_returnsと比較(差≤1e-12)
  - R_lagged: 前月のticker×weightで当月の日次リターンを積み上げ
  - R_current: 本番monthly_returnsをそのまま使用

Step 3: α混合
  - 各α: 段階的リターン = α × R_lagged + (1-α) × R_current
  - α=0の結果 = R_current = 本番monthly_returns(パリティ検証)

Step 4: 3指標計算+殿に報告
  - 75体×5αのCAGR/シャープレシオ/MaxDDテーブル生成
  - L0-L3、忍法7種、モード3種の記述統計を生成
  - 結果を殿に報告。追加指示を待つ
```

## §4 実装分解(v1.14)

| # | 内容 | 依存 |
|---|---|---|
| 1 | 75体のholding_signal+component_portfolios+prices+monthly_returns取得→ローカルキャッシュ | なし |
| 2 | history.py方式のticker×weight展開(holding_signal再帰→均等合算) + R_lagged計算 + パリティ検証 | 1 |
| 3 | 5α混合 + 3指標計算 + 層/忍法/モード集計 + 結果テーブル生成 | 2 |

**1忍者で完結。** データ取得→展開+計算→報告の直列3ステップ。並列分割不要。

### §4.1 才蔵の試行錯誤から確定した正しい方法論

#### 完了証跡の組立

初回の詰まりは実験値ではなく、報告とcommitの順序にあった。binary checks・verdict・operational simulationを埋めても、未commitの計画pathを仮HEADとして`cross_repo_commits`へ記すと、commit hash実在性・所有path・commit subject契約が同時にBLOCKする。

正しい順序:

1. 対象scopeだけを専用commitする。
2. 40桁の実hashを取得する。
3. `git show --name-only <hash>`で申告pathをそのcommitが所有することを確認する。
4. report YAMLへ実hash・所有path・binary evidenceを記録する。
5. 最終gateを実行し、最後にcompletedへ遷移する。

#### read-only launcherと再帰SQL

read-only launcherが`WITH`先頭のSQLを拒否した場合、再帰SQL本体を書き換えず外側`SELECT`で包む。これによりread-only判定を満たしつつ、Phase 0で確定したhistory.py再帰展開の意味を変えない。

- origin: `[[cmd_partial_turnover_phase1_normal]] -> [[未commit仮HEADの証跡誤記]] -> [[専用commit_実hash_path確認_最終gate]]`
- origin: `[[read_only_launcher_WITH拒否]] -> [[外側SELECTラップ]] -> [[再帰SQL不変で375セル完走]]`

## §5 decision ledger

| 項 | 状態 |
|---|---|
| 段階的リバランス実験の実施 | 殿発案2026-08-05 15:57。殿裁可済み(22:46) |
| α探索範囲 [0.0, 0.25, 0.5, 0.75, 1.0] | 確定 |
| Phase 0対象PF | §2.5の指定12体。完了 |
| Phase 1対象PF | **§2.6の指定75体。75/75・375/375完了** |
| 対象PF = 全102体 | 将来候補。**殿が明示的に追加指示するまで実行禁止** |
| 対象期間 = 全期間 | 確定 |
| 本番コード変更 | 禁止。実験スクリプトのみ |
| ticker×weightデータソース | **v1.12確定: history.py L224-237方式**(holding_signal再帰展開+均等1/N+同一ticker合算)。display_ticker_weightsもexpand_portfolio_to_tickersも使わない。本番表示と同一ロジック(殿スクリーンショット確認: XLU 100%) |
| v1.10 FAIL-close | display_ticker_weights直接経路は非unit+parity不一致で棄却。v1.12で別方式に切替 |
| Phase 1完了証跡 | commit `d14a4ec3`。専用commit→実hash/path確認→report→最終gateを標準順序とする |

## §6 因果リンク

- origin: `[[殿発案_段階的リバランス_20260805]] -> [[半分ずつ入替の効果検証]] -> [[全PF全期間バックテスト実験設計]]`
- → [[dmsignal_operations]] DM-Signal運用。月次リバランスの現行方式
- → [[fof-acceleration-oscillation-experiment]] FoF加速度フィルタ振動問題。段階的リバランスが振動緩和効果を持つ可能性
- → [[production_parity]] パリティ検証。α=0で本番一致を確認してからα>0の実験
- → [[殿裁定_サイズ調整のみ_20260608]] 「シグナルはルールで判定する。やるのはサイズ調整のみ」
- → [[専用commit_実hash_path確認_最終gate]] 才蔵の完了証跡組立から確定した正順序
- → [[外側SELECTラップ]] read-only launcher制約下で再帰SQLを不変に保つ方法
