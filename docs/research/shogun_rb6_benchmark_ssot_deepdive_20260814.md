# RB6 benchmark SSOT違反 — 将軍深掘り(2026-08-14 02:50)

宛先: 家老（半蔵hotfix cmd_karo_hotfix_rb6_benchmark_monthly_ssot_20260814 のRCA支援材料）
検証者: 将軍D0（本番DB readonly実測 + コード現物）

## 1. TQQQ側は無傷（横展開不要の証明）

- ticker_monthly_returns TQQQ: 2010-02〜2026-08 199ヶ月。raw prices月初営業日→翌月初営業日境界の独立検算で **198/198 exact**（close/open、1e-9）
- portfolio_metricsのbenchmark_tickerは**全204行SPYのみ** — TQQQのmetrics保存経路は存在しない
- compare summary/return/chartのTQQQは`compare_returns.py:222-225`でTickerMonthlyReturn**直参照**（中間保存層なし）
- ∴ hotfixのスコープはSPY系FoF保存benchmark月次50行のみで正しい

## 2. SSOT違反の発動機構（コード現物で特定）

供給経路: `recalculate_fof.py:647-662` — shared_benchmark_returnsを**TMRから**構築し
`generators/monthly_returns.py:_generate_monthly_returns`へ渡す。設計上はSSOT直のはず。

**穴は `monthly_returns.py` B1/B2の2段構造にある**:

- B2 (`monthly_returns.py:618-619`): `if year_month in benchmark_ticker_returns:` の時**だけ**TMR値で上書き
- B2コメント自身が明記: 「**NULL値の場合は辞書に含まれないため、上のprice ratio計算結果が使われる**」
- B1 (同:610-611): fallbackの独自price ratio計算（TMRのH6窓規則とは別の境界計算）

∴ **TMR側に該当year_monthの行がない/monthly_returnがNULLの月だけ、B1のfallback値がsilentに保存される**。
これがmismatch 50行/49FoF（close50/open50）の機構仮説。SPY TMR自体は403/403 exactなので、
欠落はFoF系列の**初月stub等、TMR収録範囲とFoF系列開始月のズレ**で起きる可能性が高い
（RB6でのFoF初月stub問題=knowledge:a3be860cf46b0ddf と同族）。

追加の穴（副次）: `recalculate_fof.py:656` は `monthly_return is not None` のみでfilterし、
`monthly_return_open`がNULLなら**closeをopenに流用**（:662）。open系列の別値化要因になりうる。

## 2.5 【追補 03:00 — 将軍D0仮説検証の結果、§2の欠落月仮説は棄却】

本番DB実測（readonly、mismatch 50行を独立再現）:

1. **TMR欠落仮説=棄却**: 50行全てでSPY TMR行が存在し値も非NULL（欠落0/NULL 0/存在するが別値50）
2. **構成**: 50行 = **各FoFの系列初月48行** + 44fa8aad(2013-08, 2013-09)の2行
3. **窓の逆算特定（全50行説明完了）**:
   - 初月48行: benchmark = **当月最終営業日→翌月初営業日**窓のSPY return（stub窓。close/open両系列exact。例: 2011-09の3PF共通値-0.028458 = SPY 09/30→10/03）
   - 44fa8aad/2013-09: 窓 09-30→10-01（stub形窓で一致）
   - 44fa8aad/2013-08: 窓 **08-01→09-30**の変則2ヶ月弱窓（隣接09月と対。PF側の窓境界異常=H6検出済み事案と同根）
4. **結論**: 全50行は「**PF側のactual_start/end窓と同窓でbenchmarkを計算した値**」。
   初月stubのPF returnは月末→翌月初の部分窓ゆえ、benchmarkも同窓=**PF-benchmark同窓整合が保たれている**。
   TMR満月値との差は**仕様差（同窓比較 vs 満月SSOT）であり、サイレントなバグとは断定できない**。

## 3.【重要・§3旧版を置換】半蔵hotfixへの即時含意 — 機械的なTMR書き換えは危険

- 50行をTMR満月値へ書き換えると、初月stub行は「PF return=部分窓 vs benchmark=満月」の**非対称比較**になり比較の公平性が壊れる
- 論点を2つに分離せよ:
  (a) **初月stub行のbenchmark契約**は「同窓」が正か「満月SSOT」が正か → **殿裁定事項**（provenance v1.5 §3.25⑤の窓境界正本化に直結）
  (b) **44fa8aadの窓境界異常**（2013-08が08-01→09-30を吸収）はPF側の窓異常であり、benchmark書き換えでなく**窓の根治**が本筋
- ∴ 半蔵hotfixは「50→0への機械的書き換え」ACのまま進めるな。契約裁定→AC再定義を推奨

## 3-old.（§2欠落月仮説時点の含意 — 追補で置換済み・履歴として保持）

1. **検証クエリ**: mismatch 50行の`year_month`がSPY TMRに存在するか/NULLかをまず突合せよ。
   存在しない→B1 fallback発動の実証。存在する→別機構（stale世代等）へ分岐
2. **修正方針の選択肢**: (a) fallback発動時もH6窓規則で計算 (b) fallback廃止しfail-loud
   (c) TMR側の欠落月を埋める — サイレントフォールバック禁止原則(knowledge:dfacc200系)に照らし(b)or(c)を推奨
3. **再計算経路の注意**: TMRはmode=FULL/TICKERのL1でのみ再生成(cmd_3832ガード、
   `recalculate_fast.py:1218-1223`)。**mode=PORTFOLIOではL1スキップ**のため、hotfix後の
   50行書き直しがどのmodeで走るかをACに明記せよ（FoF MonthlyReturn再生成がTMR温存の
   modeで走るなら、TMR欠落月が残ったままB1が再発動する）
4. open流用(:662)の扱いもAC対象に含めるか判断せよ
