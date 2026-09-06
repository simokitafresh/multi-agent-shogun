<!-- gist-master: e2219c69d927f32dc84d53e3e7daa97d dm-signal-market-direction-breadth-exposure-asis-tobe_20260905.md -->
# DM-Signal 体系の保有 ticker×weight を月ごとに見る — 1 表設計書 v1.7(2026-09-06 12:15 殿裁定 11:46 で対象 78→75 PF(L2 21)、is_suspect 列は cmd_4483 で撤去・再生成中) / v1.6(2026-09-06 03:10 cmd_4481 CLEAR 02:45・is_suspect 意味確定) / v1.5(2026-09-06 00:50 cmd_4481 delegated) / v1.4(2026-09-06 00:40 進捗整合: 入力 F1 CSV は 00:19 に生成済み(23,175 行、終端 approved_honest_fail)、新四つ目 3 体は is_suspect=true で別計上(家老 blt_002416 APPROVE)、実装 cmd は家老協議後に起票、cmd_4480 根因確定で is_suspect 解除) / v1.3(2026-09-05 22:55 家老 R3-2 の分母定義を明記) / v1.2(2026-09-05 22:50 家老 R3 途中指摘: 分母は manifest 総数−I7 ではなく『その月に F1 CSV に行がある PF 数』。未開始 layer(L3 は 2013-12 前)は自然に 0 行) / v1.1(2026-09-05 22:50 家老 R2-7: is_mtd 列追加、contract test を AC1/AC2 の 2 本に) / v1.0(2026-09-05 22:35、殿 22:29『シンプルにデータを見たいだけだ。L0,L1,L2,L3,全体でどの ticker をどの weight で持っているかを知りたいだけだ。複雑さはすべて捨てろ』で v0.1〜v0.5 の 6 表・asset class・前月差・仮想 PF・裁定 4 点を全て撤去)

- 発端: 殿 19:32(市場方向性の PIT 観測)→ 22:29 で目的を 1 文に固定。
- 版履歴(歴史修正禁止のため記録のみ): v0.1 19:50 6 表設計 / v0.2〜v0.5 21:40〜22:40 weight 正本の訂正往復(display_ticker_weights 直接採用は 08-06 partial-turnover v1.10 で棄却済み→history.py L224-237 方式) / **v1.0 22:35 1 表へ縮約**。旧版本文は git 履歴(5498c0f9b 以前)にある。
- 入力の正本: 基盤設計書 `docs/research/dm-signal-research-data-foundation-asis-tobe_20260905.md` v0.6 F1 `holdings_monthly.csv`(PF × 月 × ticker × weight。展開規則・検算・対象 78 PF・manifest は全てそこにある)。本書は展開しない、DB を読まない、パラメータを持たない。

## 進捗ビジュアル(将軍 loop 更新 2026-09-06 13:35)

**AC1〜AC3** `██████████ 3/3` ✅完了 🟡走行中 ⏳待ち 🔴要判断

| 項目 | 状態 | 現在値 |
|---|---|---|
| 単一表 layer_holdings_monthly | ✅ 75 PF 版 CLEAR 13:31(DM origin 0f2bfbcd) | 3,525 行、198 ヶ月、is_suspect 列なし、L2 分母 ≤21。**artifact 27c1995d に 13:16 実値公開**(docs/dashboard/layer-holdings-monthly.html、scripts/layer_holdings_render.py)。origin 収載後に hash 再照合 |
| is_suspect 3 体(新四つ目) → 母集団から除外・列撤去 | ✅ cmd_4483 CLEAR 13:31(is_suspect 列なし、L2 分母 ≤21) | 新四つ目 3 体は本表から除外し、is_suspect=false 側(75 PF)を正本として読む。列の物理削除は不要(false 側の行を使う) |
| 契約 test AC1/AC2(weight 和・pf_count) | ✅ | CI 上で PASS(DM-Signal origin e045d337) |

## §0.0 前提とスタイル

- 対象 75 PF(L0 シン四神 12 / L1 GSシン忍法 21 / L2 奥義-GS 21 / L3 秘奥義 21)。定義は基盤書 §2.4。殿裁定 2026-09-06 11:46『L2から新四つ目抜きの21体でやろう』で L2 24→21(新四つ目 3 体を母集団から除外、cmd_4483 で再生成。v1.6 までは 78 PF+is_suspect)。
- 保有 = `monthly_returns.holding_signal`(PIT)を展開した weight。基盤 F1 が作る。
- 本番に触るのは殿の明示 OK のみ(殿 22:27)。本書の実装は CSV を読んで CSV を書くだけで、DB 接続を持たない。
- 慌てて実装しない。基盤書が家老・軍師 APPROVE に到達し、F1 が CLEAR してから。

## §1 出力は 1 表だけ

`layer_holdings_monthly.csv`

| 列 | 意味 |
|---|---|
| year_month | 2010-04 〜 2026-09 |
| is_mtd | true = 月末未到達(2026-09 のような当月。F1 manifest の as-of から機械判定)。false = 確定月 |
| layer | L0 / L1 / L2 / L3 / ALL |
| ticker | XLU / TQQQ / GLD / TMV / TECL / Cash(基盤 F1 に現れたものだけ。手入力なし) |
| weight | その月にその階層の PF が持つ ticker の平均 weight = Σ(PF の weight) ÷ 階層の PF 数 |
| pf_count | 分母 = その月・その階層で F1 CSV に行がある PF 数(distinct portfolio_id)。未開始 layer は行が無いので出力しない |
| is_suspect | true = F1 の parity 不一致 3 体(奥義-GS-新四つ目-激攻/常勝/鉄壁)。**根因確定(cmd_4480 CLEAR 03:05)**: 3 体は投票比例 weight の FoF で、F1 の 1/N 展開が本番と一致しない(102/104)。よって true 側の weight は 1/N 近似値。列を外す条件は F1 が target_weight を読むこと(D4 殿裁定)。false 側が正本(v1.6) |

- 各 (year_month, layer) で weight の合計は 1.0。
- ALL は当月 eligible(行がある)PF の単純平均(階層をまたいで 1 PF=1 票)。全 78 が揃う月のみ 78。
- これだけで「今月は体系全体が XLU 6 割・GLD 3 割・TQQQ 1 割」のように読める。見たい形(横持ち・グラフ)は CSV を pivot するだけ。

## §2 作り方(1 行の group-by)

```
holdings_monthly.csv → groupby(year_month, layer, ticker).weight.sum() / pf_count(year_month, layer)
ALL 行 = 同じことを layer を無視して計算
```

- pandas 数行。パラメータ 0。ハードコード 0(ticker も layer も入力 CSV から出る)。
- 出力先: `analysis_runs/cmd_44xx_layer_holdings/layer_holdings_monthly.csv`。
- 実行前提: cmd_4479(基盤 F1)終端(00:3x approved_honest_fail、CSV 23,175 行は使用可)。F1 の manifest(78 PF・as-of)をそのまま同梱。
- 進捗(00:50): 実装 cmd_4481 を delegated(家老協議 blt_004146 (1) yes、忍者 1 名 15 分、配備は家老の順序で次空き)。

## §3 二値 AC(実装 cmd に渡す。3 つだけ)

| AC | 判定 |
|---|---|
| AC1 | 全 (year_month, layer) で Σweight = 1.0 ± 1e-9。違反 0 |
| AC2 | pf_count = F1 CSV の (year_month, layer) ごとの distinct portfolio_id 数 = 『当該 year_month に monthly_returns 行がある manifest 内 PF 数 − I7』(家老 R3-2 の定義と同値。F1 が I7 を行として出さないため)。全行一致、かつ ≤ manifest の layer 別 PF 数(12/21/24/21、ALL 78) |
| AC2b | is_mtd は as-of 月の行だけ true、それ以外 false(違反 0) |
| AC3 | script 内に DB 接続・config 読取・展開コードが 0 件(grep: create_db_engine / component_portfolios / display_ticker_weights = 0) |

contract test は AC1(Σweight=1)と AC2(pf_count 分母一致)の 2 本(別々の永続不変量、各 `test_necessity` 宣言)。実装用 test は同一 cmd 内で削除。

## §4 捨てたもの(再導入しない。必要になったら殿が言う)

Breadth(保有 PF 率)、ticker 別 Aggregate Exposure の別表、asset class 集約表、前月差 Δ、仮想等額 PF の return、裁定 4 点(XLU class / 期間始点 / 2 銘柄同時の扱い / 仮想 PF の return 定義)。いずれも §1 の 1 表から後で計算できる派生物であり、設計書に置くと目的(データを見る)より複雑さが先に立つ。

## §5 因果リンク
- ← [[殿指示_市場方向性PIT観測_20260905_1932]] → [[dm-signal-research-data-foundation-asis-tobe_20260905]] F1 `holdings_monthly` → **[[layer_holdings_monthly_1表]]**
- ← [[殿指示_複雑さを捨てろ_20260905_2229]]
- origin: "[[殿指示_市場方向性PIT観測_20260905_1932]] -> [[weight正本の訂正往復_v0.2-v0.5]] -> [[1表へ縮約_v1.0]]"
