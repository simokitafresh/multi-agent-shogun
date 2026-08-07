<!-- gist-master: NEW fof-acceleration-oscillation-experiment-asis-tobe-5w1h_20260805.md -->
# FoF加速度フィルタ振動問題 — 実験設計書 AsIs/ToBe 5W1H v2.0 【レーン方式】

> **v2.0(2026-08-07 殿指示)**: レーン方式にアップデート。台帳駆動+idle自動配備。cmd起票不要。
> v1.1(2026-08-05 12:12 軍師レビュー5指摘反映): 再現性条件(DBスナップショット/HEAD/seed)明記、判定閾値定義、案A集中度評価追加、案B初回確定誤り率追加、案Cパリティ基準明記
> v1.0(2026-08-05 12:00 殿指示): 本番コードは変更しない。3案(A/B/C)の効果を実験で検証する設計書

## §0 前提知識 — この問題を理解するために必要な背景

### DM-Signalのポートフォリオ階層構造

DM-Signalは月次リバランスのデュアルモメンタム投資システムである。ポートフォリオ(PF)は3層のFund of Funds(FoF)構造を持つ:

```
L3: 秘奥義（FoF of FoF）— L2から1〜2体を選択
 └─ L2: 奥義（FoF）— L1から1〜2体を選択
     └─ L1: シン四神/シン忍法（Standard PF）— 個別ETFを保有
         └─ L0: 個別ETF（SPY, QQQ, XLU, GLD, TLT, TMF等）
```

各層のPFは**holding_signal**（保有シグナル）を持つ:
- L1のholding_signal = 保有ETFのticker名（例: `QQQ`, `XLU,GLD`）
- L2/L3のholding_signal = 選択されたコンポーネントPFのUUID

### シグナル決定の仕組み

各PFは`pipeline_config`で定義された**ビルディングブロック(BB)**の直列パイプラインでシグナルを決定する:

```json
{
  "selection_pipeline": {
    "blocks": [
      {
        "type": "MomentumAccelerationFilter",
        "config": {
          "top_n": 1,
          "method": "ratio",
          "numerator_period": {"days": 231},
          "denominator_period": {"days": 252}
        }
      }
    ]
  },
  "terminal_block": {"type": "EqualWeight"}
}
```

`MomentumAccelerationFilter`は各コンポーネントPFの**加速度スコア**（231日リターン ÷ 252日リターン）を計算し、上位N体を選択する。

### FoFの「価格」データ

FoFのコンポーネントPFは個別銘柄ではないため、株価が存在しない。代わりに`monthly_returns`テーブルの**cumulative_return**（累積リターン）を「価格」として使う:

```python
# component_price.py L78
perf_dfs[row.portfolio_id].append({
    "close": row.cumulative_return,  # ← これが「価格」になる
})
```

### fullrecalculate

本番では定期的に`fullrecalculate`が走り、全PFのシグナル・累積リターン・月次リターンを全期間再計算する。この再計算は全期間のデータを最初から積み上げ直す。

## §1 AsIs — 発見された問題（2026-08-05実証）

### 現象

`秘奥義-加速R-鉄壁`（L3 FoF）のholding_signalが、fullrecalculateのたびに変わる:

| changed_at (UTC) | date | holding_signal |
|---|---|---|
| 08-03 14:22 | 08-01〜03 | **GS-抜き身-鉄壁** |
| 08-05 01:49 | 08-01〜03 | **GS-変わり身-鉄壁** |

同じ日付(08-01〜03)のconfirmed-monthシグナルが、recalcのたびに2つのコンポーネントPF間で振動する。

### 影響範囲

08-05のsignal_change_logを全件確認した結果、変わったのは**秘奥義-加速R-鉄壁の3行だけ**。他のFoF（11体）は変更なし。

| 秘奥義 | フィルタ種別 | top_n | 08-05で変更 |
|---|---|---|---|
| 秘奥義-加速R-鉄壁 | **MomentumAccelerationFilter** | **1** | **YES** |
| 秘奥義-四つ目-常勝 | MultiViewMomentumFilter | 2 | no |
| 秘奥義-四つ目-鉄壁 | MultiViewMomentumFilter | 2 | no |
| 秘奥義-抜き身-常勝 | SingleViewMomentumFilter | 2 | no |
| 秘奥義-抜き身-鉄壁 | SingleViewMomentumFilter | 2 | no |
| 秘奥義-追い風-常勝 | MomentumFilter | 2 | no |
| 秘奥義-追い風-鉄壁 | MomentumFilter | 2 | no |
| 秘奥義-分身-鉄壁 | なし(全保有) | - | no |
| 秘奥義-変わり身-鉄壁 | TrendReversalFilter | - | no |
| 秘奥義-追い風-鉄壁 | MomentumFilter | 2 | no |
| 秘奥義-鉄壁 | なし(全保有) | - | no |

唯一の`top_n=1 × MomentumAccelerationFilter`が振動している。

### 根本原因の因果チェーン

```
fullrecalculate実行
  → 全PFのcumulative_returnを全期間再計算
    → float64の乗算順序・pandas集約の内部実装に依存して最終桁に微少差(1e-15程度)
      → MomentumAccelerationFilter: val_num / val_den でスコア算出
        → GS-抜き身-鉄壁とGS-変わり身-鉄壁のスコアが僅差(境界近傍)
          → 最終桁の微少差でスコア順位が逆転
            → top_n=1で選択先が入れ替わる
              → holding_signalが振動
```

### タイブレーク仕組みの構造的欠陥

現行コード(`momentum_acceleration_filter.py` L139-142):
```python
cutoff_score = acceleration_results[min(top_n - 1, len(acceleration_results) - 1)][1]
selected = [item[0] for item in acceleration_results if item[1] >= cutoff_score]
```

top_n位のスコアと**float64で完全同値(bit一致)**なら均等保有になる設計。しかしfloat64で完全同値はほぼ起きないため、**タイブレークは事実上死んでいる**。

### 8/7時点の状況(v2.0追記)

- 08-07 SIGNAL CHANGE ALERT一次確認: 3PF×5日=15件は当月シグナルの正常な日次変動。秘奥義-加速R-鉄壁の振動は08-05以降追加のfullrecalculateが実行されていないため再発確認は未実施
- 本実験はread-onlyのため、振動の再発有無に関わらず実行可能(Phase 0のベースライン計測で再現性を確認する設計)
- **cumulative_return再計算は実質毎日**(殿指摘で確認2026-08-07): sync-standard(日次cron)が`recalculate_history_fast(mode=PORTFOLIO)`を呼び、cumulative_returnを全期間再積上げしてUPSERTする。sync-fof(日次cron)も同様。月初の`recalculate-sync`は保険的な全量再実行。∴ split遡及修正は翌日のsync cronで反映され、最大30日放置にはならない
- **振動の根本原因はsplit遡及ではなくfloat64の日次再積上げ差**: 日次sync cronが毎回cumulative_returnを全期間再積上げするからこそ、float64乗算順序差(pandas集約の内部実装依存)で微少差が日次で再生成され、境界近傍の加速度スコアが振動する。§1の根本原因チェーンと整合。因果: `[[sync_layers_daily_recalculate]]` → `[[recalculate_history_fast]]` → `[[cumulative_return全期間再積上げ]]` → `[[float64微少差日次再生成]]`

### L1(Standard PF)は安定している

GS-抜き身-鉄壁もGS-変わり身-鉄壁も、L1のholding_signal自体は8月を通じて安定(signal_change_logに08-05エントリなし)。問題はL1の値ではなく、**L3のFoFがどのL1を選ぶか**のフィルタ判定で起きている。

### モメンタムバンドは非適用

殿裁定によりモメンタムバンド(δ=0.5%・半々方式)は撤廃済み。仮にバンドがあっても、バンド境界付近では同じ振動が起きる(殿指摘)。バンドは根本解決にならない。

## §META — 5W1H

| 項 | 内容 |
|---|---|
| WHY | FoFのtop_n=1加速度フィルタが、cumulative_returnの浮動小数点微少差でrecalcのたびに振動する。confirmed-monthシグナルの不安定はユーザー向けmonthly trade表示の信頼性に影響する |
| WHAT | 3つの対策案(A: タイブレーク閾値/B: confirmed-month immutability/C: 丸め桁固定)の効果を**本番コード変更なし**の実験で検証する |
| WHO | **将軍**: レーン起票(本設計書)と最終検分のみ。**家老**: 台帳駆動で自走配備+完了処理。cmd起票不要。**忍者**: 弾の実行と二値報告。**軍師**: レビュー |
| WHEN | idle忍者検知の瞬間に常時。レーンは将軍・殿の在席と無関係に自走する |
| WHERE | 実験スクリプト=`/mnt/c/Python_app/DM-signal/scripts/analysis/`配下。本番コード変更なし |
| HOW | §3 レーン構成要素参照。台帳駆動+idle自動配備+飽和終端 |

## §2 ToBe — 3案の実験設計

### 共通実験基盤

**目的**: 3案それぞれが「振動を止められるか」「副作用はないか」を定量的に検証する。

**実験対象**: 秘奥義-加速R-鉄壁(唯一の振動PF) + 全秘奥義12体(副作用確認)

**再現性条件(v1.1追加 — 軍師指摘)**:
- **DBスナップショット**: Phase 1でローカルSQLiteにキャッシュした時点のタイムスタンプ+本番recalculation_status最新run_idを記録。全実験はこの固定スナップショットのみを使用
- **コードHEAD**: DM-Signal リポジトリの`git rev-parse HEAD`を記録。実験期間中にコード変更があった場合は記録済みHEADでcheckoutして実行
- **乱数seed**: ノイズ注入に`np.random.seed(42)`を固定。seed値は実験結果JSONに埋込み
- **試行回数**: 100回(各seed 0-99で実行。統計的有意性はp<0.05で判定)

**計測指標**:
1. **振動回数**: 同一日付のholding_signalがrecalc 100回中に何回変わるか。分母=100回×対象月数。判定閾値: 振動率0%(全月×全試行で変わらない)を合格とする
2. **パフォーマンス差**: 案適用前後のトータルリターン・MaxDD・シャープレシオの変化。判定閾値: トータルリターン差±0.1%以内かつMaxDD悪化0%を合格とする
3. **副作用**: 他の秘奥義11体のholding_signalに意図しない変更が起きないか。分母=11体×全月数。判定閾値: 変更0件を合格とする

**実験方法(共通)**:
1. 本番DBから全コンポーネントPFのcumulative_return時系列を取得(read-only)
2. MomentumAccelerationFilterのロジックをスタンドアロンで再現(本番コードをimportし、DB接続は読み取り専用)
3. cumulative_returnに人工的な微少ノイズ(±1e-14〜±1e-10)を加えて100回シミュレーション(seed固定)
4. 各案を適用した場合と未適用の場合でholding_signalの安定性を比較

### 案A: タイブレーク閾値の導入

**仮説**: スコア差がε以下なら同値扱いにして均等保有すれば、僅差での順位逆転による振動を吸収できる。

**実験パラメータ**:
- ε = [1e-6, 1e-4, 1e-3, 1e-2, 5e-2]（5段階）

**実装(実験スクリプト内のみ)**:
```python
# 現行: 完全同値のみ均等保有
cutoff_score = sorted_results[top_n - 1][1]
selected = [t for t, s in sorted_results if s >= cutoff_score]

# 案A: ε以内なら均等保有
cutoff_score = sorted_results[top_n - 1][1]
selected = [t for t, s in sorted_results if s >= cutoff_score - epsilon]
```

**計測項目**:
- 各εで振動回数が0になるか
- εを大きくしたときに意図しない均等保有(本来1体であるべきが2体以上になる)が増えないか
- **集中度(v1.1追加)**: 各月初で選択されるPF数の平均・最大値。top_n=1なのに平均2体以上選択されるεは過大
- **保有数分布(v1.1追加)**: 全期間の各月初で[1体/2体/3体/4体]の出現頻度。top_n=1の設計意図(集中投資)に対する乖離度を定量化
- εの適正範囲: 振動を止めつつ、真に優劣がある場合の選択力を維持するεの値

**副作用リスク**: εが大きすぎると、本来明確に1体を選ぶべき場面で2〜4体均等保有になり、FoFの集中投資効果が薄れる

### 案B: confirmed-month immutability保証

**仮説**: 月初に一度確定したholding_signalを、以降のrecalcで変更しなければ振動はゼロになる。

**実験パラメータ**:
- 確定タイミング = [月初1営業日目, 月初3営業日目, 月初5営業日目]
- 確定条件 = [初回計算値を採用, 最頻値を採用(3回計算の多数決)]

**実装(実験スクリプト内のみ)**:
```python
# confirmed-month判定: target_dateが翌月に入ったら前月シグナルを凍結
if is_confirmed_month(target_date, signal_date):
    return frozen_signal[signal_date]  # 凍結値を返す
else:
    return calculate_fresh(target_date)  # 通常計算
```

**計測項目**:
- 振動回数: 定義上0（凍結するため）
- 初回確定値 vs 最頻値 vs 最終計算値のパフォーマンス差
- 凍結のタイミングが早すぎると「まだ正しい価格が到着していない」リスク(L805教訓: 月初シグナル前に前月最終営業日価格の上流可用性をゲートせよ)
- **初回確定誤り率(v1.1追加)**: 各確定タイミングで凍結したシグナルが、月末時点の最終計算値と異なる月の割合。分母=全月数。判定閾値: 誤り率5%以下を合格とする
- **確定前後差(v1.1追加)**: 凍結しなかった場合(現行)と凍結した場合のholding_signalが異なる月数。0件なら「凍結は安全で振動だけ止まる」。多ければ「凍結が正しい計算結果を封じる副作用あり」

**副作用リスク**: 初回計算時に価格が未到着だった場合、誤ったシグナルが凍結される。また、バグ修正でcumulative_return計算ロジックが改善された場合、凍結済みシグナルには反映されない

### 案C: cumulative_returnの丸め桁固定

**仮説**: cumulative_returnをN桁で丸めれば、recalcのたびに生じる最終桁の微少差が消え、スコアが安定する。

**実験パラメータ**:
- 丸め桁数 = [6, 8, 10, 12, 14]（小数点以下）

**実装(実験スクリプト内のみ)**:
```python
# cumulative_returnを丸めてからスコア計算
rounded_cum_return = round(cumulative_return, precision)
# 以降、rounded_cum_returnを「価格」としてモメンタム計算
```

**計測項目**:
- 各桁数で振動回数が0になるか
- 丸めによるパフォーマンス計算精度への影響(monthly_returnの差分)
- 丸めが粗すぎると本来異なるスコアが同値に潰れ、誤った均等保有が発生しないか
- **パリティ基準(v1.1追加)**: 丸め前のcumulative_returnと丸め後のcumulative_returnの差を全期間×全PFで計測。パリティ判定基準: (1)holding_signal完全一致(ticker×weight) (2)monthly_return差 ≤ 1e-12(IEEE 754ノイズ許容=既存パリティ基準L392準拠)。この基準を満たさない丸め桁は不合格
- **丸め前後のスコア差分布(v1.1追加)**: 各月初の加速度スコアが丸めでどれだけ変わるかのヒストグラム。振動を止めるのに十分かつパリティを壊さない丸め桁の適正範囲を特定

**副作用リスク**: 丸め桁が少なすぎるとmonthly_returnの精度に影響し、パリティ検証(全期間の保有シグナル+monthly return完全一致)が崩れる。パリティ基準(holding_signal一致+monthly_return差≤1e-12)を満たすことが必須条件

## §3 レーン構成要素（v2.0）

### 要素1: 実験台帳

```
docs/research/fof-oscillation-experiment-ledger.tsv
列: phase | plan | param | vibration_rate | total_return_diff | maxdd_diff | sharpe_diff | side_effect_count | status | ninja | timestamp
```

- Phase 0(道具作成+ベースライン)完了後に案A/B/Cの全パラメータ行を生成
- **書き手は自動**: 実験スクリプトが結果を台帳に自動追記。手動更新なし

### 要素2: 優先選定

- Phase 0: 道具作成(データ取得+スタンドアロン再現+ベースライン計測)を1タスクで実行
- Phase 1: 案A/B/C × 各パラメータを台帳から優先配備。**3案は独立なので3忍者並列**

### 要素3: 品質契約テンプレ

```yaml
binary_checks:
  production_mutation_zero: "yes/no — 本番DBへのINSERT/UPDATE/DELETE = 0"
  baseline_reproduced: "yes/no — スタンドアロン再現が本番holding_signalと完全一致"
  vibration_measured: "yes/no — 振動回数が100回×全月初で計測済み"
  side_effect_zero: "yes/no — 他の秘奥義11体に意図しない変更0件"
  seed_fixed: "yes/no — np.random.seed記録済み"
  snapshot_recorded: "yes/no — DBスナップショットTS+HEAD SHA記録済み"
```

### 要素4: idle自動配備

- ninja_monitorの既存idle検知に接続
- 台帳のstatus=pendingの行から優先順で1件取り出し→task YAML生成→配備
- Phase 0は手動配備(道具がまだ存在しないため)、Phase 1以降は自動配備

### 要素5: 安全ガード

- (a) idle限定配備: busy忍者への配備禁止
- (b) completed再配備防止: 同一案×パラメータの重複実行禁止
- (c) production mutation = 0: read-only強制。本番コード変更禁止
- (d) 再現性固定: DBスナップショット+HEAD SHA+seed 42を全タスクに焼込み

### 要素6: 計測還流+終端条件

- 各弾の完了後に振動率・パフォーマンス差・副作用件数を台帳に記録
- **終端条件**: 全パラメータ行(案A×5 + 案B×6 + 案C×5 = 16パターン)の結果が揃ったらレーン自動終了
- **中間判断**: Phase 0ベースラインで振動再現に失敗(振動率0%)→ レーン終了(問題が自然解消)

## §3.5 フェーズ構成（v2.0）

### Phase 0: 道具作成 + ベースライン計測（手動配備）

- **目的**: データ取得+スタンドアロンフィルタ再現+ベースライン振動計測
- **配備**: 家老がidle忍者1名に手動配備
- **AC**:
  - AC1: 全秘奥義12体のcumulative_return全期間をローカルSQLiteにキャッシュ(production mutation=0)
  - AC2: スタンドアロン再現が本番holding_signalと完全一致することを確認
  - AC3: ノイズ注入100回×全月初でベースライン振動率を計測。振動月を特定

### Phase 1: 3案並列実験（レーン自動配備）

- **案A(タイブレーク閾値)**: ε×5パターン → idle忍者に自動配備
- **案B(confirmed-month immutability)**: タイミング3×条件2=6パターン → idle忍者に自動配備
- **案C(丸め桁固定)**: 桁数×5パターン → idle忍者に自動配備
- 3案は独立。3忍者並列可能

### Phase 0 → Phase 1 進行判断

- Phase 0でベースライン振動率 > 0% → Phase 1開始(問題再現確認)
- Phase 0でベースライン振動率 = 0% → **レーン終了**(問題が自然解消。根因は別にあった)

### Phase 2: 比較分析+報告

- 全16パターンの結果が揃ったら自動終端
- 振動率0% + パフォーマンス差最小 + 副作用0の最適案×パラメータを特定
- 殿に結果報告

## §4 進捗台帳

| Phase | 弾 | 対象 | パラメータ | 状態 | 結果 |
|---|---|---|---|---|---|
| P0 | 道具作成+ベースライン | 秘奥義12体 | ノイズ±1e-14×100回 | 未着手 | — |
| P1-A | 案A実験 | 加速R-鉄壁+11体 | ε=[1e-6,1e-4,1e-3,1e-2,5e-2] | — | — |
| P1-B | 案B実験 | 加速R-鉄壁+11体 | タイミング[1,3,5]×条件[初回,多数決] | — | — |
| P1-C | 案C実験 | 加速R-鉄壁+11体 | 丸め桁[6,8,10,12,14] | — | — |
| P2 | 比較分析 | — | — | — | — |

## §5 decision ledger

| 項 | 状態 |
|---|---|
| 実験の実施 | 殿発案2026-08-05 12:00 |
| レーン方式採用 | 殿指示2026-08-07 |
| 案A εの探索範囲 [1e-6〜5e-2] | v1.1提案。全範囲実行 |
| 案B 確定タイミング [1日/3日/5日]×条件[初回/多数決] | v1.1提案。全組合せ実行 |
| 案C 丸め桁 [6/8/10/12/14] | v1.1提案。全範囲実行 |
| ノイズ注入回数 100回 | v1.1提案 |
| 本番コード変更 | 禁止(殿指示)。実験スクリプトのみ |

## §6 因果リンク

- origin: `[[SIGNAL_CHANGE_ALERT_20260805]] -> [[秘奥義-加速R-鉄壁_振動]] -> [[float64微少差×top_n=1境界]] -> [[実験設計書(殿発案)]]`
- pattern: `[[台帳駆動攻略レーン]]`（gist f777582a41c66e95a53d1cc993bc5a1c）
- → [[MomentumAccelerationFilter]] `backend/app/services/pipeline/blocks/momentum_acceleration_filter.py`
- → [[ComponentPriceBlock]] `backend/app/services/pipeline/blocks/component_price.py` — cumulative_returnを「価格」として供給する入口
- → [[monthly_returns]] DBテーブル。cumulative_returnの格納先
- → [[signal_change_log]] 振動の検出源
- → [[殿裁定_バンド採用_20260706]] モメンタムバンド撤廃の経緯
- → [[L805]] 月初シグナル前に前月最終営業日価格の上流可用性をゲートせよ
- related: `[[EMA全敗_矩形窓優位確定_20260807]]`（同日のEMA実験レーンCLOSED。同じ実験フレームワーク）
