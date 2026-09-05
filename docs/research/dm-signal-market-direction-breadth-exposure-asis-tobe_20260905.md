<!-- gist-master: e2219c69d927f32dc84d53e3e7daa97d dm-signal-market-direction-breadth-exposure-asis-tobe_20260905.md -->
# DM-Signal 体系の保有 ticker×weight を月ごとに見る — 1 表設計書 v1.3(2026-09-05 22:55 家老 R3-2 の分母定義を明記) / v1.2(2026-09-05 22:50 家老 R3 途中指摘: 分母は manifest 総数−I7 ではなく『その月に F1 CSV に行がある PF 数』。未開始 layer(L3 は 2013-12 前)は自然に 0 行) / v1.1(2026-09-05 22:50 家老 R2-7: is_mtd 列追加、contract test を AC1/AC2 の 2 本に) / v1.0(2026-09-05 22:35、殿 22:29『シンプルにデータを見たいだけだ。L0,L1,L2,L3,全体でどの ticker をどの weight で持っているかを知りたいだけだ。複雑さはすべて捨てろ』で v0.1〜v0.5 の 6 表・asset class・前月差・仮想 PF・裁定 4 点を全て撤去)

- 発端: 殿 19:32(市場方向性の PIT 観測)→ 22:29 で目的を 1 文に固定。
- 版履歴(歴史修正禁止のため記録のみ): v0.1 19:50 6 表設計 / v0.2〜v0.5 21:40〜22:40 weight 正本の訂正往復(display_ticker_weights 直接採用は 08-06 partial-turnover v1.10 で棄却済み→history.py L224-237 方式) / **v1.0 22:35 1 表へ縮約**。旧版本文は git 履歴(5498c0f9b 以前)にある。
- 入力の正本: 基盤設計書 `docs/research/dm-signal-research-data-foundation-asis-tobe_20260905.md` v0.6 F1 `holdings_monthly.csv`(PF × 月 × ticker × weight。展開規則・検算・対象 78 PF・manifest は全てそこにある)。本書は展開しない、DB を読まない、パラメータを持たない。

## §0.0 前提とスタイル

- 対象 78 PF(L0 シン四神 12 / L1 GSシン忍法 21 / L2 奥義-GS 24 / L3 秘奥義 21)。定義は基盤書 §2.4。
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
- 実行前提: cmd_4479(基盤 F1)CLEAR。F1 の manifest(78 PF・as-of)をそのまま同梱。

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
