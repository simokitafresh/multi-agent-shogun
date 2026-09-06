<!-- gist-master: 131e8c6545f630bedd6c3a4a9731c420 dm-signal-research-data-backlog_20260905.md -->
# DM-Signal 研究データ基盤 — F1 以外の backlog(記録のみ。実装しない)v1.4(2026-09-06 03:10 I8 根因確定 102/2) / v1.3(2026-09-06 00:40 I8→cmd_4480 delegated) / v1.2(2026-09-06 00:25 I7 実測 0・I8 新四つ目 parity 104 を追記) / v1.1(2026-09-05 22:55 家老 R3-3: A2 は実装予定表記へ) / v1.0(2026-09-05 22:45)

- 出自: `dm-signal-research-data-foundation-asis-tobe_20260905.md` v0.4 の F2〜F4・A1〜A11・D2〜D4 を、殿 22:29『複雑さはすべて捨てろ』と家老 R2-6『F1 主設計書に残さない。情報は削除せず別 backlog へ』により移設。本文は v0.4(commit 5498c0f9b)から移したもので、内容の再検討はしていない。
- 着手条件: 殿が個別に指示した時だけ。本 backlog から自動的に cmd を起票しない。

## 進捗ビジュアル(将軍 loop 更新 2026-09-06 10:10)

**I8 根因/B1〜B5** `██░░░░░░░░ 1/6` ✅完了 🟡走行中 ⏳待ち 🔴要判断

| 項目 | 状態 | 現在値 |
|---|---|---|
| I8 新四つ目 parity 104 | ✅ 根因確定 | 102=投票比例 weight、残 2=015e74dc/0206995c の 2014-04(root signal 不在) |
| B1 F2 holding_signal_expanded | ⏳ 記録のみ | D4 は除外で決着(殿 11:46→cmd_4483: 母集団 75 PF、L2 21)。target_weight 拡張の設計は cmd_4482(cancelled)本文に保存 |
| B2 F3 signal_decision_ledger | ⏳ 中立 | 変更なし |
| B3 F4 layer_of 一元化 | ⏳ 記録のみ | |
| B4 A1〜A11 | ⏳ 記録のみ | |
| B5 I1〜I8 | 🟡 | I8 のみ動いた。I1〜I7 は据え置き |

## B1 F2 `holding_signal_expanded`(monthly_returns に展開後 JSON 列を併記)
- F1 が外部 long table として機能すれば不要(同じ情報)。F1 を DB 表へ昇格する第 2 段で「long table か列追加か」を 1 回だけ決める。二重に持たない。

## B2 F3 `signal_decision_ledger` の扱い(中立。家老 R2-5)
- 事実: `app/jobs/generators/monthly_returns.py` L28/L252-263 が「確定月は ledger の決定値を優先、空なら no-op」で読む現役参照。writer/reader は recalculate_fof / recalculate_fast / signal_flush / safe_bundle_v2 / writer_inventory / portfolio_restore / monthly_trade_impl の 7 file+API router(main.py L43/L426)+models の append-only guard+`projects/dm-signal.yaml` PI-P06 SSOT 宣言。08-12 T7.5(c13a56fe/0e9d158d)は guard detect-only 化と alert 撤去。08-16 PITR rollback 以後 0 行=全経路 no-op。
- 選択肢: (a) 復活=07-07 cmd_3711 と同じ再バックフィル / (b) 廃止=依存撤去 cmd。**F1 は分析 materialization であり、runtime の確定月上書き防止を担う ledger の代替ではない(家老 R2-5)。∴ 既定方向を置かず (a)/(b) 中立。** 着手時はまず影響範囲(pending 表示・確定境界)の偵察 cmd。

## B3 F4 階層ラベル関数 `layer_of(portfolio)` の一元化
- L0〜L3 判定(名前規則)を `backend/app/services/` に 1 関数(または `portfolios.config.layer` 1 キー)として置く。全研究 script・admin・LP が同じ関数を呼ぶ。

## B4 アイデア A1〜A11(v0.4 §4 から移設)

| # | アイデア | 何が楽になるか | 既存に乗せる先 |
|---|---|---|---|
| A1 | ticker→asset class 参照表 YAML 1 本 | 全研究で同じ分類 | `analysis_runs/foundation/asset_class.yaml` |
| A2 | 対象 PF 集合の版管理(日付付き YAML) | 対象 78 が変わっても再現可能 | F1 AC7 の universe_manifest として実装予定(cmd_4479 CLEAR 後に『実装済み』へ追記。家老 R3-3) |
| A3 | 研究用 readonly view カタログ 1 ページ | §2 走査の再発防止 | 将軍 doc lane |
| A4 | signal_change_log 健全性チェック(同日往復 I2、未出現 I3) | turnover 前提の監視 | verification tables v076 系 |
| A5 | 空表の可視化(0 行の表を admin/debug に一覧) | I4 の誤認防止 | `app/api/debug.py` |
| A6 | 月次 PIT 1 行サマリ log | X 投稿・Live OOS の手集計を消す | F1 第 2 段 |
| A7 | PF 相関行列の月次 materialize | 階層間の賭けの重複を一発で | F1 派生 |
| A8 | fof_component_weights の actual_weight/drift 観測 | 未活用の数値列 | SQL のみ |
| A9 | portfolio_config_snapshots 差分ログ(2026-06〜) | 設定変更の因果 | SQL のみ |
| A10 | 展開ロジックの一元化(history.py 1 段 / price_ratio_impl L1237-1317 再正規化不在 / trades_impl / monthly_trade_impl / oracle)。**正本は F1 の再帰規則(d14a4ec3 `_resolve_weights`)であり display_ticker_weights ではない(v0.4 A10 の『正本は display』は誤記を訂正)** | 規則変更が 1 箇所 | `backend/app/services/fof/` |
| A11 | semantic alias の時系列訂正(『FoF 展開不要で display_ticker_weights を使え』08-06 v1.8 → v1.10 で棄却) | 古い裁定が最新として返る事故の防止 | `context/semantic-map.md`(**v0.5 で正本訂正済み**) |

## B5 本番の不整合 I1〜I7(v0.4 §2.5 から移設。修正は別 cmd)
| # | 事象 |
|---|---|
| I1 | `fof_component_weights` JSON 4 列 24,348 行 全 NULL |
| I2 | `signal_change_log` 同日往復の二重行 |
| I3 | `signal_change_log` に現れる対象 PF 66/78(L0 10/12・L1 17/21・L2 21/24・L3 18/21、nonce *-ro9)。※ 殿裁定 11:46 で母集団は 75(L2 21)へ。新四つ目 3 体の change_log 有無は cmd_4483 の manifest excluded で再計上 |
| I4 | `signal_detail_history` 0 行、`signal_decision_ledger` 0 行(0 行=未使用ではない。B2) |
| I5 | 月初 `signals.holding_signal` と `monthly_returns.holding_signal` の不一致(F1 で計測) |
| I6 | `display_ticker_weights` 非 unit 35 行・α=0 parity 不一致 29/2,096(08-06 v1.10) |
| I7 | component holding_signal 欠落で展開不能な PF-月(F1 で計測。**実測 0**、00:19) |
| I8 | cmd_4479 F1 の α=0 parity: 12,268 PF-月 一致 / 104 不一致、不一致は全て `奥義-GS-新四つ目` 3 体(00:19 才蔵 honest FAIL、verify_parity.md)。他 75 PF は再現一致。新四つ目の本番 monthly_return は同月 holding_signal の静的展開+区間複利では再現できない(component 構成・signal 有効日・生成経路の差が候補、未確認) | **cmd_4480 CLEAR 03:05**: explained 102=投票比例 FoF weight(fof_component_weights.target_weight 非1/N)を F1 が 1/N 展開しているため。**unexplained 2(残 I8)**: 015e74dc-26f3-47c5-98ea-414dc4fdf579/2014-04(常勝)、0206995c-5aef-4da5-aca7-5bef7a1f4845/2014-04(鉄壁)=初月で root signal 行・fof_component_weights 0 行。仮説=初月は signals 生成前に monthly_returns 計算(未検証)。正本 analysis_runs/cmd_4480_shin_yotsume_parity/root_cause_summary.md |

## 因果リンク
- ← [[dm-signal-research-data-foundation-asis-tobe_20260905]] v0.4 → 本 backlog(移設)
- origin: "[[殿指示_複雑さを捨てろ_20260905_2229]] -> [[家老R2-6_F1以外を別文書へ]] -> [[research-data-backlog]]"
