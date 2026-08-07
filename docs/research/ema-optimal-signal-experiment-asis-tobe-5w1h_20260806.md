<!-- gist-master: 54672858b2c18d60877eba4e8dac5e95 ema-optimal-signal-experiment-asis-tobe-5w1h_20260806.md -->
# EMA最適シグナル実験 — Valeyre (2026) 検証完了・レーン終了 AsIs/ToBe 5W1H v3.0 【CLOSED】

> **結論**: Valeyre (2026) arXiv:2504.10914 の「単一EMAが最適シグナル」は、我らのDM-Signal ETF universeには当てはまらない。42パターン全てで現行矩形窓がEMAを上回った。**現行方式の妥当性が実験的に裏付けられた。**
> **v3.0**: Phase 0完了。§5レーン終了条件該当によりCLOSED(2026-08-07)。
> **v2.1**: dead code回避修正(差替え対象をL346-352へ変更、月次EMA近似)。殿裁可2026-08-07。
> **v2.0**: 殿指示2026-08-07「レーン方式で行うスタイルにアップデート」。レーン正本=gist f777582a41c66e95a53d1cc993bc5a1c

## §0 本質（1行）

**半減期スイープ台帳がPF×半減期の弾を選び、idle忍者が弾を撃ち、Sharpe/CAGR/MaxDD計測結果が次の弾と最適半減期を決める閉ループ。**

```
半減期×PF計測台帳 ──優先選定──▶ タスク自動生成(品質契約焼込) ──idle検知──▶ 自動配備
     ▲                                                              │
     └──── 計測還流(Sharpe差分・飽和検知) ◀── 実装→レビュー→GATE ──────┘
```

## §1 AsIs（現状）

### 現行のモメンタム計算
- **追い風(MomentumFilter)**: 固定lookback窓（例: 6ヶ月）の単純リターンでPFをランキング。窓の中は等ウェイト、窓の外はゼロ（矩形窓）
- **AbsoluteMomentumFilter**: 同様に固定lookback窓のリターンが閾値を超えるかでリスクオン/オフを判定
- **GS探索空間**: lookback_months をパラメータとしてグリッドサーチ済み。チャンピオンのlookback値は忍法・モード別に異なる

### Valeyreの知見（70先物universe、1990-2023）
- **最適シグナル**: 単一EMA(η=1/112、半減期78日)
- **理論公式**: η_opt = λ√(1 + 2β₀²/λ) で解析的に導出
- **パラメータ**: λ=1/180(平均回帰180営業日)、β₀=0.12(トレンド強度12%)
- **Sharpe**: ARP構築で1.24（EMA 112日）、近傍で緩やか(100日=1.25、150日=1.21)
- **多時間スケール否定**: MACD(3スケール)はSharpe 1.18で単一EMA以下、相関0.99

### ギャップ
- Valeyreのuniverseは**70先物**(株指数/債券/FX/商品)、ポートフォリオ構築は**ARP**(相関逆平方根加重)
- 我らのuniverseは**ETF約20銘柄**、ポートフォリオ構築は**1/N等ウェイト**
- λ(平均回帰速度)とβ₀(トレンド強度)はuniverse固有であり、移植不可(論文自身が指摘)
- **矩形窓 vs EMA**: 同じモメンタム時間スケールでも窓の形状が異なる。EMAが矩形窓より実際に優れるか未検証

## §2 ToBe（目標）

### 実験で答える問い（3つ）
1. **EMA vs 矩形窓**: 同程度の時間スケールで、EMAシグナルは現行lookback(矩形窓)シグナルより優れるか？
2. **最適半減期**: 我らのETF universeでの最適半減期は78日か、それとも異なる値か？
3. **層別効果**: L0/L1/L2/L3で効果に差があるか？

### 成功基準
- 各層1体以上のPFでEMA vs 現行のCAGR/Sharpe/MaxDD比較が完了
- 半減期スイープ(40-150日)で我らのuniverseの最適値を特定
- 現行GS lookbackチャンピオンとEMA最適値の関係を定量的に記述

## §3 5W1H

### Who（誰が）
- **将軍**: レーン起票（本設計書）と最終検分のみ
- **家老**: 台帳からタスク自動生成+idle検知自動配備+完了処理。cmd起票不要
- **忍者**: 弾の実装と二値報告（改善なしも数値で正直に）
- **軍師**: レビューとボトルネック特定

### What（何を）
- **既存道具の最大活用**: `scripts/analysis/grid_search/run_077_oikaze.py`を基盤とする。新規スクリプトは作らない
- Phase 0: run_077_oikazeの`calc_momentum_series`をEMA方式に差し替えたバリアント(`run_077_oikaze_ema.py`)を作成。選出・リバランス・計測パイプラインはそのまま流用
- Phase 1以降: 台帳駆動でPF×半減期の組合せを自動配備

### Where（どこで）
- ローカル実行。本番DBはread-only接続（段階的リバランス実験と同一パターン）
- SQLiteキャッシュに価格データを保存し、繰り返し実行を高速化

### When（いつ）
- idle忍者検知の瞬間に常時。レーンは将軍・殿の在席と無関係に自走する

### Why（なぜ）
- Valeyreの理論的最適性が我らのuniverseにも成立するなら、現行忍法のlookback設計に理論的裏付けが得られる
- 成立しないなら、我らのuniverse固有の最適パラメータを特定できる
- いずれにせよ、現行パイプラインの設計妥当性を定量的に評価できる

### How（どうやって）— レーン方式6要素

## §4 レーン構成要素

### 要素1: 一次計測台帳

```
docs/research/ema-experiment-ledger.tsv
列: pf_name | layer | half_life_days | CAGR | Sharpe | MaxDD | CAGR_diff | Sharpe_diff | MaxDD_diff | signal_match_rate | status | ninja | timestamp
```

- 初期行: Phase 0で道具完成後に全対象PF×21パターン(0=現行矩形窓, 1,2,...,20ヶ月の半減期)を生成
- **書き手は自動**: 実験スクリプトが結果を台帳に自動追記。手動更新なし

### 要素2: 優先選定

- Phase 0: L1全量GS(42パターン)で道具作成+検証。L0はGS対象外(理論ベースDNA)
- Phase 1: Sharpe差分の絶対値が大きいPF×半減期から優先配備
- 選定根拠（実測値・PF名・半減期）をタスクへ記録

### 要素3: 品質契約テンプレ

```yaml
# タスクに焼き込む品質契約
binary_checks:
  original_sha_unchanged: "yes/no — run_077_oikaze.py(元コード)のSHA256がb7e8aabc966b2151b76851aa9e6cc6c648b1073228dd157f890bab273a3292f6と一致"
  ema_is_copy_not_modify: "yes/no — run_077_oikaze_ema.pyはrun_077_oikaze.pyのcp複製から作成(元ファイル未変更)"
  production_mutation_zero: "yes/no — 本番DBへのINSERT/UPDATE/DELETE = 0"
  metrics_complete: "yes/no — CAGR/Sharpe/MaxDD全3指標が計算済み"
  baseline_comparison: "yes/no — 現行シグナル(α=0)との差分が記録済み"
  ledger_updated: "yes/no — 台帳に結果行が追記済み"
  warmup_excluded: "yes/no — EMA初期252営業日を除外して評価"
```

### 要素4: idle自動配備

- ninja_monitorの既存idle検知に接続
- 台帳のstatus=pendingの行から優先順で1件取り出し→task YAML生成→配備
- 段階的リバランス実験レーンと同一パターン

### 要素5: 安全ガード

- (a) idle限定配備: busy忍者への配備禁止
- (b) completed再配備防止: 同一PF×半減期の重複実行禁止
- (c) in-flight同一PF直列化: 同一PFの並列実行禁止（SQLiteキャッシュ競合防止）
- (d) production mutation = 0: read-only強制。DBへの書込み禁止

### 要素6: 計測還流+飽和終端

- 各弾の完了後にSharpe差分を台帳に記録
- **飽和検知**: 全PF×全半減期の結果が揃ったらレーン自動終了
- **中間判断**: Phase 0結果で「EMAが全半減期で現行以下」なら Phase 1に進まずレーン終了

## §5 フェーズ構成

### L0はGS対象外（殿裁定）

L0(シン四神12体)は理論ベースでユニークDNAを持つ4家×3モード。GSで最適化するとDNAが歪む。EMA実験の対象はL1〜L3のみ。

### Phase 0: 道具作成 + L1全量GS（手動配備）

- **対象**: L1(シン忍法) — L0の12体を構成PFとしてEMA追い風で選別
- **目的**: run_077_oikaze_ema.pyの作成と動作検証。L1全量42パターン(21半減期 × top_n(1,2))を1タスクで実行
- **配備**: 家老がidle忍者1名に手動配備（道具がまだ存在しないため自動配備不可）
- **成果物**:
  - `scripts/analysis/grid_search/run_077_oikaze_ema.py` — EMA版追い風GSスクリプト
  - L1のGS結果CSV(42パターン)
  - 半減期-Sharpe曲線プロット
  - 既存矩形窓追い風チャンピオンとの比較表

- **AC**:
  - AC1: 42パターンの月次リターンテーブルが出力される（production mutation = 0）
  - AC2: 各半減期のCAGR/Sharpe/MaxDDが計算され、既存追い風チャンピオンとの差分が記録される
  - AC3: 半減期-Sharpe曲線が出力され、ピーク位置（我らの最適半減期）が特定される

### Phase 1: L2/L3へ拡大（レーン自動配備）

- **対象**:
  - L2(奥義): L1チャンピオン群を構成PFとして、EMA追い風で選別。42パターン
  - L3(秘奥義): L2チャンピオン群を構成PFとして、EMA追い風で選別。42パターン
- **配備**: Phase 0で作成した道具+台帳を使い、家老が台帳駆動で自走配備
- **終了条件**: L1+L2+L3 = 126パターンの結果が台帳に揃う、または飽和検知

### Phase 0 → Phase 1 進行判断

- Phase 0(L1)の結果で最良半減期のSharpeが既存追い風チャンピオン以下 → **レーン終了**（アイデアとしてとどめる）
- Phase 0(L1)の結果で最良半減期のSharpeが既存追い風チャンピオンを上回る → **Phase 1開始**(L2/L3へ拡大)

## §6 実装方針 — run_077_oikaze.pyの活用

### 既存道具が持つもの（そのまま流用）
- 本番DB読込+月次リターンベースの計算パイプライン (L317-445)
- lookback期間パラメータ化+グリッドサーチ (PARAM_GRID_1, L149-175)
- top_n選出→等ウェイト→月次リターン計算 (L523-534)
- CAGR/Sharpe/MaxDD出力+CSV保存
- 並列実行(ProcessPoolExecutor)

### ★絶対原則: 元コード不変（殿厳命 2026-08-07）

**`run_077_oikaze.py`（元の追い風コード）は一切変更してはならない。**

正しい手順:
1. `cp run_077_oikaze.py run_077_oikaze_ema.py`（単純複製）
2. 複製先(`run_077_oikaze_ema.py`)のみを実験用に改修
3. 元ファイルのSHA256不変を確認: `b7e8aabc966b2151b76851aa9e6cc6c648b1073228dd157f890bab273a3292f6`

**実験用Valeyre版はこの実験にのみ使うもの。本番パイプラインへの混入禁止。**

### 変更点（複製先のみ — v2.1修正: dead code回避）

> **v2.1修正(2026-08-07 殿裁可)**: Phase 0前提検証(半蔵)で`calc_momentum_series`(L317)がmain()実行パス上のdead codeと判明。`build_global_sim_context`(L346)が`cumulative_returns`非None時に`cum_series.shift(lb_months)`で直接計算し、calc_momentum_seriesのelse分岐(L360)に到達しない。加えてL1 componentの本番データは月次粒度(monthly_returnsテーブル)のみで日次EMA不可。∴差替え対象をL346-352の直接計算箇所へ変更し、月次EMA近似を適用する。

**差替え対象**: `build_global_sim_context` 内 L346-352の直接モメンタム計算
```python
# 現行(矩形窓・L346-352):
# momentum = cum_series / cum_series.shift(lb_months) - 1.0
# ↓ EMA方式に差し替え(月次近似)

def calc_ema_momentum_monthly(cum_series: pd.Series, half_life_months: int) -> pd.Series:
    """月次cumulative returnシリーズに対するEMAモメンタム。
    half_life_months=0の場合は現行矩形窓(比較ベースライン)を返す。"""
    if half_life_months == 0:
        # ベースライン: 現行lookback_monthsの矩形窓をそのまま返す
        return cum_series / cum_series.shift(lb_months) - 1.0

    # 月次リターンを計算
    monthly_ret = cum_series.pct_change()

    # EMA減衰係数(月次)
    eta = math.log(2) / half_life_months
    n = len(monthly_ret)
    ema = np.zeros(n)
    warmup = min(12, n)  # 12ヶ月ウォームアップ

    for t in range(n):
        r = monthly_ret.iloc[t] if not np.isnan(monthly_ret.iloc[t]) else 0.0
        if t == 0:
            ema[t] = r
        else:
            ema[t] = (1 - eta) * ema[t-1] + eta * r

    result = pd.Series(ema, index=cum_series.index)
    result.iloc[:warmup] = np.nan  # ウォームアップ期間はNaN
    return result
```

### パラメータグリッドの読み替え
- 現行PARAM_GRID_1: `lookback_months` (1,2,3,...18ヶ月)
- EMA版: `half_life_months` (0=現行矩形窓, 1,2,3,...,20ヶ月の21パターン) をlookback_months枠に流し込む。0は比較ベースライン(矩形窓そのまま)
- 月次粒度のためhalf_life_monthsで直接指定(日次変換不要)

### 作成するファイル
- `scripts/analysis/grid_search/run_077_oikaze_ema.py` — run_077_oikaze.pyをコピーし、build_global_sim_context内L346-352の直接計算を上記月次EMA関数に差し替え+パラメータグリッドを半減期21パターンに変更。それ以外は一切変更しない

## §7 リスクと制約

- 本番DB負荷: read-only + SQLiteキャッシュ。段階的リバランス実験と同一パターン
- 日次データ不足: EODHD価格データ(本番移行済み)を使用。2010年以降で十分な期間
- EMA初期値依存: warmup期間(最初の252営業日=1年)を除外して評価
- lookback比較の公平性: 現行lookbackの「等価半減期」を計算して同一軸で比較

## §8 前提知識（家老・忍者向け）

### Valeyre論文の核心
- トレンドは1つの時間スケールのAR(1)/OU平均回帰過程で十分にモデル化可能（R²=0.98）
- 単一EMA(112営業日/半減期78日)が理論的に最適なシグナル
- EMA = 過去リターンに「最近ほど重く、古いほど軽い」指数減衰重みをつける平滑化。半減期 = 重みが50%に減衰する日数
- 複雑な指標バスケットはcherry-pickingリスクを増すだけ
- ただし70先物+ARP構築での結果であり、我らのETF+1/N構築にそのまま移植できるかは未検証

### 現行パイプラインとの関係
- 追い風(MomentumFilter)は固定lookback窓（矩形窓）でランキング。EMAは指数減衰窓
- EMAの利点: 窓の端でシグナルが急変しない（whipsaw軽減）
- 実験はread-only研究スクリプト。本番パイプラインは変更しない

### 段階的リバランス実験との関係
- 同一フレームワーク（本番DB read-only、SQLiteキャッシュ、ticker×weight分解）
- 段階的リバランスは「シグナルに逆らう」→ 75PFで否定済み
- EMA実験は「シグナル計算方法を変える」→ 別の問い

## §9 decision ledger

| 項 | 状態 |
|---|---|
| 実験承認 | 殿発案2026-08-06 |
| レーン方式採用 | 殿指示2026-08-07 |
| Phase 0対象PF | L1(L0シン四神12体をconstituent) |
| 半減期探索範囲 | 0(現行矩形窓)+1-20ヶ月=21パターン（v2.1: 月次近似に変更。殿裁可2026-08-07） |
| Phase 0 v1 | BLOCKED — calc_momentum_series(L317)がdead code。半蔵がAC1前提検証で発見(2026-08-07) |
| Phase 0 v2.1 | 完了 — 差替え対象をL346-352へ変更。影丸が42パターン実行。commit d5117fadd |
| Phase 1拡大判断 | **レーン終了** — §5終了条件該当。全EMAがbaseline未達(2026-08-07) |
| 元コード不変 | 確認済み — SHA256=b7e8aabc(3時点不変: 複製前/複製後/実行後) |

## §10 実験結果

### Phase 0 結果（L1全量42パターン・2026-08-07 影丸実行）

**全敗。42パターン全てで矩形窓(baseline)がEMAを上回った。**

- top_n=1: baseline Sharpe **1.131** → 最良EMA(HL20) 1.014 (差 **-0.117**)
- top_n=2: baseline Sharpe **1.171** → 最良EMA(HL11) 1.014 (差 **-0.157**)
- 成果物: `outputs/grid_search/ema_experiment_phase0_v2_l1/ema_phase0_v2_l1_oikaze_grid_results.csv` (42行)
- 曲線: `outputs/grid_search/ema_experiment_phase0_v2_l1/ema_phase0_v2_l1_half_life_sharpe_curve.png`
- production mutation = 0 (grep INSERT/UPDATE/DELETE = 0件)
- batch vs serial md5完全一致

### レーン終了判断

§5の終了条件「Phase 0(L1)結果で最良半減期のSharpeが既存追い風チャンピオン以下 → レーン終了」に該当。Phase 1(L2/L3拡大)には進まない。

### なぜEMAが負けたか

1. **データ粒度**: Valeyreは日次リターン×連続時間モデル。我らは月次粒度。月に1データ点ではEMAの「滑らかさ」の恩恵が消える
2. **ユニバース**: 70先物(株/債券/FX/商品の多様クラス) vs ETF約20銘柄(株式系中心)。相関構造が異なる
3. **構築方法**: ARP(相関逆平方根加重) vs 1/N等ウェイト。リスク配分の思想が別物

### 得られた知見

- Valeyre (2026)の「単一EMAが最適」は70先物×日次×ARP構築に固有の結論
- 我らのETF×月次×1/N構築では現行矩形窓方式がEMAより優れている
- **現行lookback方式の妥当性が42パターンの網羅的実験で裏付けられた**
- note記事として公開済み: `marketing-director/content/articles/note-ema-vs-rectangular-window.md`

### 副産物: dead code発見

Phase 0 v1(半蔵)で`calc_momentum_series`(L317)がmain()実行パス上のdead codeであることを発見。`build_global_sim_context`(L346)のcumulative_returns分岐が実際の計算パス。run_077_oikaze.pyの構造理解が深まった。

### 副産物: gate構造修正

karo_direct起源cmdがcmd_complete_gate.shのSG7バンドル検証でBLOCKする構造問題を発見→飛猿がcmd_karo_*免除を実装(commit 12f00d6bb)で恒久修正。

## §11 進捗台帳

| Phase | 弾 | 対象 | 半減期 | 状態 | 結果 |
|---|---|---|---|---|---|
| P0 v1 | 道具作成(半蔵) | L1 | — | BLOCKED | calc_momentum_series=dead code発見。AC1前提検証で即停止 |
| P0 v2.1 | 道具作成+L1全量GS(影丸) | L1 | 21半減期×top_n(1,2)=42パターン | **完了** | 全EMAがbaseline未達。Sharpe差 -0.117〜-0.157 |
| P1 | L2全量GS | L2(奥義) | 42パターン | **中止** | §5終了条件によりレーン終了 |
| P1 | L3全量GS | L3(秘奥義) | 42パターン | **中止** | §5終了条件によりレーン終了 |
| — | L0 | (対象外) | — | N/A | 理論ベースDNA。GS不可(殿裁定) |

## 因果リンク

- origin: `[[殿発案_EMA実験_20260806]]` -> `[[投資辞書M85_breaking_the_trend]]` -> `[[Valeyre_arXiv_2504_10914]]`
- result: `[[EMA全敗_矩形窓優位確定_20260807]]` -> `[[現行lookback方式妥当性裏付け]]`
- dead_code: `[[calc_momentum_series_dead_code_discovery]]` -> `[[build_global_sim_context_L346実行パス確定]]`
- gate_fix: `[[sg7_bundle_karo_direct_exempt]]` -> `[[cmd_complete_gate_12f00d6bb]]`
- pattern: `[[台帳駆動攻略レーン]]`（gist f777582a41c66e95a53d1cc993bc5a1c）
- related: `[[段階的リバランス実験]]`（同一実験フレームワーク）
- related: `[[gs_ninpo_research]]`（既存GS lookbackとの比較）
- note: `[[note_ema_vs_rectangular_window]]`（メンバー向け記事）
