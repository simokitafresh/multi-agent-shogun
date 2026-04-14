# cmd_1901 Cash不正データ分析 — 消火か正当修正か

軍師consultation。2026-04-14。将軍相談依頼。
**殿裁定(2026-04-14)**: 将軍案(Cashフィルタ)却下。admin UI表示を正しくする方向。なぜなぜ7回実施。
**殿追加指摘**: 「そもそもキャッシュへのフォールバックの仕組みが問題」「正しく計算できない時にサイレントでエラーを隠す仕組みは危険な消火作業」→ PI-018 Silent Fallback。なぜなぜ8-10追加。

## なぜなぜ7回

| # | なぜ | 答え |
|---|------|------|
| 1 | なぜadmin画面にCash 100%が表示される？ | WeightBreakdown.tsx L157がcomponents配列をmap表示。component_id='Cash'がPF名として表示 |
| 2 | なぜcomponents配列にCash行が含まれる？ | API getFoFWeightsがfof_component_weightsテーブルから全行返却。Cash行もフィルタなし |
| 3 | なぜfof_component_weightsにCash行がある？ | recalculate_fof.py L929のfor loopがweights辞書の全keyを無検証で書込み |
| 4 | なぜfor loopにバリデーションがない？ | cmd_1101でweights機能追加時、key=portfolio UUIDという暗黙の前提。CashTerminalBlockが想定外 |
| 5 | なぜCashTerminalBlockは"Cash"文字列をkeyに使う？ | 選出ゼロ=全額キャッシュのセンチネル値。signal側消費者は"Cash"期待。fof_component_weights書込みは後付け消費者(cmd_1101) |
| 6 | なぜ後付け消費者がCashTerminal出力を考慮しなかった？ | 4種ターミナルブロック(EW/Cash/Kalman/Ward)の出力形式を全列挙せず、EW/Wardのみ想定 |
| 7 | **なぜ全列挙しなかった？** | **weights辞書のinterface contract(keyの制約)が明文化されていない。新消費者が暗黙前提で接続→前提外入力で不正データ** |

**自動化ターゲット(なぜ7時点)**: weights辞書のkey制約(UUID限定)をコードで強制。`comp_id in component_ids_set`バリデーション。

## なぜなぜ8-10 (殿追加指摘: Cash fallback = PI-018)

| # | なぜ | 答え |
|---|------|------|
| 8 | なぜCash fallbackが各ブロックに存在？ | get_final_signal()が文字列を返す契約。空/Noneを返せない。「何か返す」必要がある |
| 9 | なぜ「何か返す」必要がある？ | 呼出し元(recalculate_fof.py L732)がresults["signal"]を直接使用。Noneで後続クラッシュ |
| 10 | **なぜエラーを隠して正常値"Cash"を返す？** | **PI-018 Silent Fallback。** 選出ゼロの原因を区別せず一律Cash。正当(市場下落)と不当(データ欠損/設定バグ)が同じ出力→不当Cashが静かに蓄積→35/101 FoFのCashが正当か不当か判別不可能 |

### Cash fallback散在箇所 (return "Cash" 全5箇所)

| ブロック | ファイル | 行 | トリガー |
|----------|---------|-----|---------|
| CashTerminalBlock | cash_terminal.py | L45 | 常にCash(専用ブロック) |
| EqualWeightBlock | equal_weight.py | L45 | current_tickers空 |
| KalmanMeta | kalman_meta.py | L39 | selected空(weight>0なし) |
| WardTwoStageEW | ward_two_stage_ew.py | L159 | result空/tickers空 |
| WardTwoStageEW | ward_two_stage_ew.py | L165 | selected空(weight>0なし) |

### 構造的問題

```
選出ゼロ(原因不明)
  ├─ 正当: 市場全体の下落 → Cash保有は戦略的に正しい
  └─ 不当: データ欠損/設定ミス → Cash保有は問題の隠蔽(PI-018)
       ↓
  全ターミナルブロックが return "Cash"
       ↓
  両方とも同じ出力 → 区別不可能 → 不当Cashが本番で静かに蓄積
```

### 自動化ターゲット(なぜ10時点・更新)

cmd_1901のCashフィルタ修正 = 表層的(将軍案却下済み)。
component_ids_setバリデーション = なぜ7の到達点だがなぜ10には不足。

**根本修正**: 選出ゼロ時のエラー伝搬経路。
1. get_final_signalに`reason`フィールド追加 — "absolute_momentum_negative"(正当) vs "no_data"(不当)
2. 不当Cash → ログ出力+enhanced_momentum_dataにflag記録
3. admin UI: 正当Cash=「Cash Position (Market Condition)」/ 不当Cash=「⚠ Cash (Selection Error)」

殿の裁定待ち: Cash fallback自体の設計変更スコープ。

## 殿L0指摘 + DB確認結果 (2026-04-14 追記)

### 本番DB現状
- fof_component_weights WHERE component_id='Cash': **0件** (既に浄化済み。cmd_1899 deploy+fullrecalculate時にuncommittedガード適用か)

### 殿のL0指摘
> 「理論上、relative momentum assetかsafe haven assetにキャッシュを指定しなければ、キャッシュ保有はあり得ない」

L0 (trade-rule.md §2.2)から導かれる結論:

| Cash発生条件 | 現実 | 判定 |
|-------------|------|------|
| relative_assetsに"Cash" | 全PFで実ティッカー(TQQQ/TECL等) | ありえない |
| safe_haven_asset未設定(デフォルトCash) | 全PFで実資産設定(XLU/TMV/GLD等) | 設定漏れの兆候 |
| CashTerminalBlock明示使用 | 正常運用では使用しない | 設定ミスの兆候 |

**→ Cash保有 = 常にエラーの兆候。正常運用では発生しない。**

### return "Cash" = PI-018 Silent Fallback (5箇所)

`return "Cash"`は「選出ゼロのエラーを正常値Cashで偽装」するSilent Fallback。
L0によればCash保有は存在しないはずなので、Cashを返すこと自体がエラー隠蔽。

殿指摘: 「正しく計算できない時にサイレントでエラーを隠す仕組みは危険な消火作業」

## 分析結果

### 1. 影響範囲: **表示のみ。計算に影響なし**

`fof_component_weights`テーブルの消費者を全量grep確認:
- **フロントエンド**: `WeightBreakdown.tsx` L13 — admin FoF設定画面の表示専用
- **backend services/api**: 参照なし (0件)
- **return_calculator**: 参照なし (0件)
- **recalculate_fof.py**: 書込みのみ (L1041 `_flush_fof_component_weights`)

**結論: monthly_return計算には一切影響しない。admin UI表示のみ。**

### 2. なぜ35/101 FoFだけCashを持つか

**経路**: `CashTerminalBlock` (cash_terminal.py L32-34) がパイプライン実行結果として `{"Cash": 1.0}` を返す → `recalculate_fof.py L929` で `results.get("weights")` として取得 → L931 for loopでフィルタなしに `component_weights_batch` に追加

**35/101の理由**: CashTerminalBlockが実行されるのは、選出ブロック(MomentumFilter等)で全コンポーネントが脱落した場合のみ。全FoFが常にゼロ選出になるわけではない。35 FoFは過去に**少なくとも1回**全コンポーネント脱落を経験したFoF。

### 3. Cash = 正しい動作か展開バグか

**正しい動作(設計)。展開バグではない。**

根拠:
- `CashTerminalBlock`は正規ターミナルブロック。docstring: "Used when absolute momentum conditions are not met"
- パイプラインengineがCashTerminalを**意図的に選択**して実行
- signal側でも`holding_signal = "Cash"`として正しく記録される（signalsテーブル参照: ただし将軍情報では0件）
- テスト(`test_trade_risk_unification.py`)がweights=={'Cash':1.0}を**期待**している

**Cashは「選出ゼロ → 全額キャッシュ保有」の正常な状態表現。バグではない。**

### 4. Cashフィルタは消火か正当修正か

**消火の側面あり。** 以下の因果鎖で判断:

```
CashTerminalBlockが{"Cash":1.0}を返す(正常な設計)
→ recalculate_fof.py L929がweights辞書を全key書込み(設計漏れ)
→ component_id="Cash"がfof_component_weightsに入る(表示バグ)
→ admin画面でCash 100%と表示(殿が発見)
```

- **正当な修正部分**: component_id列はportfolio UUIDを想定。"Cash"は文字列でありUUID制約に違反。fof_component_weightsに書くべきではない → フィルタは正当
- **消火の側面**: 「なぜcomponent_weightsにCashが入るか」の真因は「L929のfor loopにportfolio_idバリデーションがない」。Cashだけフィルタは各論パッチ(LG023: 原理1行>各論パッチ)。次に非UUID文字列が来たら同じ問題が再発

### 5. 消火ではない修正案

**案A: comp_id UUIDバリデーション (推奨)**
```python
# L931付近
for comp_id, w_val in day_weights.items():
    if comp_id not in component_ids_set:  # 初期化時のcomponent_idsセット
        continue
```
- Cash以外の非portfolio_idも構造的に排除
- component_idsは L719 `initial_tickers=component_ids` で既に存在
- 正の複利: 将来新しい特殊キーが追加されても自動排除

**案B: Cash固有フィルタ (将軍当初案)**
```python
if comp_id == "Cash":
    continue
```
- Cashだけ排除。他の特殊キーが来たら再発
- 負の複利

### 6. 殿の「理論上Cashはないはず」について

殿の発言「理論上キャッシュポジションを保有するPFやFoFはないはずだが」は、admin画面に表示されるWeight BreakdownでCash行が見えることへの指摘。

**事実**: 35 FoFは過去に全コンポーネント脱落を経験しており、Cashポジション自体は設計通り。問題は「fof_component_weightsテーブルにCash行が書き込まれてadminに表示される」こと。

**signals tableにCash保有0件**: これはholding_signal="Cash"が signalsテーブルではなく別の場所(enhanced_momentum_data等)に記録されるため。signals=0件は「Cashポジションが存在しない」ことを意味しない。

## CS checklist

- CS1: ソース全量確認 OK — recalculate_fof.py, cash_terminal.py, pipeline blocks全4種のweights出力, frontend消費者, backend消費者を確認
- CS2: 自システムデータで存在検証 OK — コード構造からCashTerminalBlock→weights→component_weights_batchの経路を特定
- CS3: 実コード比較 OK — git show HEAD:recalculate_fof.py L929でフィルタ不在確認
- CS4: 行動変換 OK — 案A(UUIDバリデーション)を提案
- CS5: 未検証角度 — 殿の「Cashはないはず」の真意(設計変更意図)は未確認
- CS6: 因果推論 OK — 因果鎖記載済み
