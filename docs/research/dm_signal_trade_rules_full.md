# DM-Signal Trade Rules 詳細 (RULE01-11 / 誤解集 / SSOT階層)

> 移動元: `projects/dm-signal.yaml §(a)` (cmd_2295圧縮 2026-04-26)
> 正規ソース(Level 0): `/mnt/c/Python_app/DM-signal/docs/rule/trade-rule.md`
> 最終更新: 2026-01-28

## RULE01-11

| ID | 要約 |
|----|------|
| RULE01 | signal(生シグナル)とholding_signal(保有シグナル)は別物 |
| RULE02 | holding_signalはリバランス月の月初のみ更新される |
| RULE03 | リバランス月のholding_signalは前月末のsignalを採用する(当月初ではない) |
| RULE04 | シグナル変更(銘柄変更)とリバランス(比率調整)は独立概念 |
| RULE05 | Return = Σ wᵢ × (P_end / P_start - 1)。wᵢは月初目標ウェイト。非リバランス月でも月初にリセット。R_trade = Π(1+R_月) - 1 |
| RULE06 | 月初にウェイトを目標値にリセット。月中は価格変動でドリフト(日次リバランスではない) |
| RULE07 | FoFはティッカー×ウェイトに展開可能。展開後は標準PFと同じ計算ロジック |
| RULE08 | FoF展開は当月初営業日のholding_signalを参照する。直近リバランス時のsignal_dateで確定 |
| RULE09 | Open-to-OpenとClose-to-Closeは独立した計算系列。混在禁止 |
| RULE10 | シグナル判定は常にClose。リターン計算のみOpen/Close選択可 |
| RULE11 | 同一年月・同一PFのReturnはどのページでも完全一致 |

### Critical Notes
- RULE09: 同一計算内でOpen価格とClose価格を混ぜてはならない
- RULE10: モメンタム計算(シグナル判定)にOpenを使うことはない
- デフォルトはOpen-to-Open(Close-to-Closeではない)。実運用T+1始値執行に近い

## 計算整合性裁定 (2026-03-11 殿直接指示)

signals/returns/metricsなど全数値フィールドが全PF×全期間で許容誤差ゼロの完全一致であること。
これがBE変更の最低基準。BE変更implのACに必ず「実API diff検証」を含めよ。

## SSOT階層

| Level | 名前 | 役割 |
|-------|------|------|
| Level 0 (データ) | Price table | 全ての原点。営業日=Priceレコードが存在する日 |
| Level 0 (ルール) | trade-rule.md | 理論上の理想形(真に正しいルール定義) |
| Level 1a | calculate_monthly_return() | 月次リターンのSSOT関数 (return_calculator.py) |
| Level 1b | calculate_trade_period_return() | Trade期間リターンのSSOT関数(月次複利合成) (return_calculator.py) |
| Level 2 | MonthlyReturn table | Level 1aの事前計算キャッシュ。recalculate_fast.pyで生成 |
| Level 3 | UI表示層 | Level 1/2を使用する派生実装 |

## よくある誤解集

- 誤解1: signalが変わったら即座に保有も変わる → holding_signalはリバランス月初のみ更新
- 誤解5: 累積インデックスの比がリターン → 正しくはΣ wi × (P_end/P_start - 1)
- 誤解6: 日次複利積がリターン → 毎日リバランスを暗黙に仮定。月次リバランスは意図的設計
- 誤解7: FoFは当月シグナルを使う → 当月初営業日のholding_signal(直近リバランス時のsignal反映)
- 誤解11: OpenとCloseを混ぜて計算できる → 混在禁止
- 誤解12: シグナル判定にOpen価格を使用 → 常にClose
- 誤解14: デフォルトはClose-to-Close → Open-to-Openがデフォルト

## モメンタム計算正しい手順 (殿裁定 2026-02-15)

1. 構成tickerの共通データ期間を求める
2. lookback期間を考慮して計算開始日を決定
3. 計算する

Key insight: 共通期間内ならNaN行は存在せずpivot/per-tickerの差異は消える。
問題の根源はNaN行の扱いではなく、共通期間を先に確定していないこと。

## GS用語定義

| 用語 | 定義 |
|------|------|
| 狭義GS(四神作成スクリプト) | shin_shijin_l1_gs.py。パラメータ空間総当たり→チャンピオン選定 |
| 忍法スクリプト | run_077_*.py 7本。四神12体をコンポーネントとしFoFを構成 |
| GS(広義) | scripts/analysis/grid_search/全体。狭義GS+忍法7本+共通ライブラリ |
| 流れ | L0 GSチャンピオン→シン四神12体→L1忍法7本→シン忍法v2 21体→L2奥義EW合成 |
