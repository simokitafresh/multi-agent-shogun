# GS高速化×完全一致 — 知見集約ドキュメント
<!-- last_updated: 2026-02-19 -->

> 管理責任: 家老(karo)
> 最終更新: 2026-02-19 01:45（nukimi_c正式廃止 — nukimi T1-T5拡張統合）
> 目的: 各忍法GSスクリプトの高速化知見を蓄積し、次の忍者のタスクYAML注入元とする

---

## 1. 完全一致の定義（殿裁定 2026-02-18 20:19）

| # | 条件 | 検証方法 |
|---|------|----------|
| 1 | CSV行数が逐次版と高速化版で同一 | wc -l |
| 2 | 全14列(pattern_id〜new_high_ratio)のmd5sumが完全一致 | md5sum |
| 3 | 月次リターン時系列CSVのmd5sumが完全一致 | md5sum |

- 逐次版 = 高速化コード無効(pd.Series直接計算)
- 高速化版 = NumPyベクトル化+前処理キャッシュ
- **両方の出力が1bitも違わないこと**が合格条件

---

## 1.5. 入力データパス（殿指示: 忍者に推測させるな）

正本入力（cmd_160裁定, cmd_163再確認）:
- **max_cagr系コンポーネントCSV**: `/mnt/c/Python_app/DM-signal/outputs/grid_search/max_cagr_fof_components_DM*.csv`
  - 例: `.../max_cagr_fof_components_DM2.csv`, `...DM3.csv`, `...DM6.csv`, `...DM7plus.csv`
- **newhigh系mode結果CSV**: `/mnt/c/Python_app/DM-signal/outputs/grid_search/066_newhigh_mode_results_DM*.csv`
  - DM単体/複合(例: `...DM2.csv`, `...DM2_DM3.csv`, `...DM2_DM3_DM6_DM7_plus.csv`)
- **max_maxdd系mode結果CSV**: `/mnt/c/Python_app/DM-signal/outputs/grid_search/max_maxdd_mode_results_DM*.csv`
  - 例: `...DM2.csv`, `...DM3.csv`, `...DM6.csv`, `...DM7plus.csv`

汚染データ（使用禁止）:
- `064_champion_monthly_returns.csv` は cmd_163 で `archive/contaminated/` へ退避済み
- 参照先として再導入しないこと

各忍法の出力先(`/mnt/c/Python_app/DM-signal/outputs/grid_search/`):
| 忍法 | 14列CSV | 月次リターンCSV | prefix |
|------|---------|----------------|--------|
| bunshin | 161_bunshin_grid_results_{fast,seq}.csv | 161_bunshin_grid_monthly_{fast,seq}.csv | 161_bunshin_grid |
| oikaze | 161_oikaze_grid_results_{fast,seq}.csv | 161_oikaze_grid_monthly_{fast,seq}.csv | 161_oikaze_grid |
| kawarimi | 161_kawarimi_grid_results_{fast,seq}.csv | 161_kawarimi_grid_monthly_{fast,seq}.csv | 161_kawarimi_grid |
| nukimi | 161_nukimi_grid_results_{fast,seq}.csv | 161_nukimi_grid_monthly_{fast,seq}.csv | 161_nukimi_grid |
| nukimi_c | 161_nukimi_c_grid_results_{fast,seq}.csv | 161_nukimi_c_grid_monthly_{fast,seq}.csv | 161_nukimi_c_grid |
| kasoku | 161_kasoku_grid_results_{fast,seq}.csv | 161_kasoku_grid_monthly_{fast,seq}.csv | 161_kasoku_grid |

---

## 2. 高速化手法（L041 + kagemaru知見）

### (1) pd.Series演算 → NumPy配列一括演算に置換
- ループ内のpd.Series.get()を143月×N回呼ぶ → ndarray一括演算に変更
- Python loopがボトルネック。NumPy化でC言語レベルの速度に

### (2) 月次リターン前処理をループ外で事前キャッシュ化
- パターンループの外で1回だけ前処理を実行
- 各パターンではキャッシュ済みデータを参照するのみ

### (3) get_sim_contextで全コンポーネントのmatrix(ndarray)を1回構築しnumpyスライス
- 全コンポーネント(bunshinなら12個)の月次リターンを143×N のndarrayとして1回構築
- 各パターンではnumpyスライスで必要列を取得

### 月次リターンCSV出力（build_monthly_returns_df）
- wide形式: 1列目=year_month, 残列=pattern_id
- 値=月次リターン(float)、NaNなし
- 逐次版・高速化版それぞれで出力し、md5比較

---

## 3. ハマりポイント

### align_months月セット不一致リスク（kagemaru発見 — 最重要）

**問題**: 高速版はget_sim_contextが全コンポーネント共通月でmatrixを構築する。逐次版でサブセットのみでalign_monthsすると共通月セットが変わり、md5不一致になる。

**解決**: main()で全コンポーネント共通のcommon_monthsを事前計算し、逐次版にも高速版にも同じ月セットを渡す。これにより同一月セットが保証される。

**教訓**: 逐次版と高速化版で「入力データの前提」を揃えないと出力が一致しない。align_monthsの呼び出し箇所と引数を必ず確認せよ。

---

## 4. 各忍法の適用記録

### bunshin（kagemaru — 2026-02-18）

| 項目 | 内容 |
|------|------|
| 担当 | kagemaru |
| タスク | subtask_161_bunshin_monthly_return_output |
| スクリプト | run_077_bunshin.py |
| パターン数 | 781 |
| コンポーネント数 | 12 |
| 結果 | **全AC PASS** |
| 14列CSV md5 | ec68daaa3cc1d9867669b396925786c1（一致） |
| 月次リターンCSV md5 | 97aa46be1b43e7d5024b0b8e9c30c133（一致） |
| 逐次版時間 | 1.4秒 |
| 高速版時間 | 0.0秒 |
| 合計時間 | 1.8秒 |
| データ期間 | 2014-03〜2026-01（143ヶ月） |
| 月次リターン形式 | wide形式(143行×782列) |

**改修内容（kagemaru記録）**:
1. get_sim_context: contextにmonths(PeriodIndex)追加
2. simulate_pattern: 返り値を(metrics, portfolio_returns)タプルに変更
3. simulate_pattern_sequential: 新規追加(matrixキャッシュ不使用、pd.Seriesから直接計算)
4. build_monthly_returns_df: 新規追加(月次リターン→DataFrame変換)
5. main: 5段階構成に改修(fast→seq→CSV出力→md5検証→meta.yaml)

**再現手順（kagemaru記録）**:
1. `cd /mnt/c/Python_app/DM-signal`
2. `python3 scripts/analysis/grid_search/run_077_bunshin.py`
3. 出力: `outputs/grid_search/161_bunshin_grid_{results,monthly}_{fast,seq}.csv`
4. Phase 4でmd5一致をスクリプト内で自動検証。戻り値0=PASS、1=FAIL
5. 当時の前提: `outputs/grid_search/064_champion_monthly_returns.csv` が存在すること（現行正本は本書1.5節のmode CSVs）
6. 同名ファイルが既存の場合はエラー終了(上書き防止)。再実行時は先にリネームまたは削除

### oikaze v1（hanzo — 2026-02-18 — ⚠️結果無効: 064_champion使用）

| 項目 | 内容 |
|------|------|
| 担当 | hanzo |
| タスク | subtask_161_oikaze_speedup_transfer |
| スクリプト | run_077_oikaze.py |
| 入力データ | `064_champion_monthly_returns.csv`（**汚染データ・使用禁止**） |
| パターン数 | 100（検証用） |
| コンポーネント数 | 12 |
| 結果 | 全6AC PASS → **殿裁定で無効**(入力データ不正) |
| 14列CSV md5 | 3fb58041b3df12a976b6afdd7b6c8161 |
| 月次リターンCSV md5 | 7309730dcaaced4502d346077f67512c |
| 逐次版時間 | 0.692秒 |
| 高速版時間 | 0.113秒 |
| 高速化倍率 | 6.11倍 |
| データ期間 | 2014-03〜2026-01（143ヶ月） |

### oikaze v2（hanzo — 2026-02-18 完了 — ✅正本mode CSVs使用）

| 項目 | 内容 |
|------|------|
| 担当 | hanzo |
| タスク | subtask_161_oikaze_speedup_v2 |
| スクリプト | run_077_oikaze.py |
| 入力データ | mode CSVs: joushou4(wide)+chishou4(long) = 8コンポーネント |
| パターン数 | 100（検証用） |
| コンポーネント数 | 8（gekkou4件除外: max_cagr月次リターンCSV未存在） |
| 結果 | **全7AC PASS** |
| 14列CSV md5 | b32408c028487e76406671e9f74bdd48（一致） |
| 月次リターンCSV md5 | c1f07b4b1975448b0684a6af822df700（一致） |
| 逐次版時間 | 0.863秒 |
| 高速版時間 | 0.115秒 |
| 高速化倍率 | **7.49倍** |
| 合計実行時間 | 1.1秒（3分制限内） |
| 共通月 | 173ヶ月 (2011-09..2026-01) |
| データ期間 | 各コンポーネント173-189ヶ月、align_monthsで共通化 |

**目的**: bunshin高速化手法の汎用性検証。kagemaruの知見を読んだだけで別の忍者が別の忍法に適用できるか → **v1で実証成功、v2で正本データでも再現確認**

**v2固有の知見（hanzo記録・原文）**:
1. COMPONENT_SOURCESを064_champion(単一CSV)からmode CSVs(8ファイル)に切替
2. joushou(newhigh) 4件: wide形式(066_newhigh_monthly_returns_DM{2,3,6,7_plus}.csv)
3. chishou(maxdd) 4件: long形式(max_maxdd_monthly_returns_DM{2,3,6,7plus}.csv, filter=god)
4. gekkou(max_cagr): max_cagr_monthly_returns_*.csv が存在しない → 除外
5. CANDIDATE_SET を C12(12件) → C8(8件) に変更
6. 旧出力ファイルをold_champion_*にリネームし再実行
7. newhigh=wide形式、maxdd=long形式の混在 → gs_csv_loaderのformat指定で対応
8. maxddのlong形式ではfilter_col="god", filter_val="{god名}"が必要
9. align_monthsで173ヶ月に共通化。各コンポーネントの期間差(173-189ヶ月)は自動吸収
10. 前回の高速化コード(get_sim_context, momentum_cube等)はそのまま動作。変更不要

**064_champion vs mode CSVs比較（hanzo記録・原文）**:
- 前回(064_champion): 共通月142ヶ月(2014-03..2026-01)、12コンポーネント
- 今回(mode CSVs): 共通月173ヶ月(2011-09..2026-01)、8コンポーネント
- 高速化倍率: 前回6.11x → 今回7.49x（コンポーネント減で改善）
- データ期間: mode CSVsの方が長い（2011-09開始 vs 2014-03開始）

**v2出力ファイル**:
- 161_oikaze_grid_results_fast.csv (100行)
- 161_oikaze_grid_results_seq.csv (100行)
- 161_oikaze_grid_monthly_fast.csv (172行x101列)
- 161_oikaze_grid_monthly_seq.csv (172行x101列)
- 161_oikaze_grid_results_fast.meta.yaml

**v1での改修内容（hanzo記録・原文、高速化手法の核心）**:
1. simulate_pattern(): 返り値をDict→Tuple[Dict, np.ndarray]に変更（月次リターン配列も返す）
2. simulate_pattern_sequential(): 新規追加（matrixキャッシュ不使用の逐次版）
3. _calc_momentum_at_month(): ヘルパー新規追加（逐次版のモメンタム計算）
4. build_monthly_returns_df(): 新規追加（月次リターン時系列CSV出力）
5. main(): dual-run(fast+sequential)パターンに改修 — Phase1(fast)/Phase2(seq)/Phase3(CSV)/Phase4(md5)/Phase5(meta)

**bunshinとの差異・ハマりポイント（hanzo発見 — 重要）**:

**(a) 月次リターン配列の可変長問題（oikaze固有）**:
- bunshinは全月で必ずリターンが出る（均等配分なので）
- oikazeはモメンタム未算出月（lookback不足）でリターンが出ない月がある
- → out_returns[:out_count]の可変長配列だとbuild_monthly_returns_dfで「All arrays must be of the same length」エラー
- → 固定長(common_months-1)のNaN埋め配列に変更して解決
- → calc_metrics_fastにはNaN除外後の配列を渡す

**(b) 逐次版のモメンタム計算**:
- bunshinはモメンタム計算不要（均等配分）
- oikazeは_calc_momentum_at_month()を新規作成し、close_seriesの全indexから該当月のlookback窓を取得
- get_sim_contextのcalc_momentum_series+reindexと同じ結果になることを確認

**(c) tie-breaking**:
- 高速版: np.lexsort((valid_local, -scores[valid_local]))でタイブレーク
- 逐次版: sorted(key=lambda x: (-x[1], components.index(x[0])))で同一ロジック

**高速化倍率がbunshinより低い理由（hanzo分析）**:
- bunshin: 55.5倍（計算部のみ）→ oikaze: 6.11倍
- oikazeはmomentum計算+top_n選択のループが残る（bunshinは単純均等配分）
- momentum_cubeの事前構築コスト(get_sim_context)がoikazeでは大きい
- とはいえ6倍は十分な改善

**再現手順（hanzo記録・原文）**:
1. run_077_oikaze.py を読む
2. simulate_pattern → Tuple[Dict, np.ndarray]返りに変更
3. simulate_pattern_sequential を追加(get_sim_context不使用、pd.Series直接計算)
4. _calc_momentum_at_month() ヘルパーを追加
5. build_monthly_returns_df() を追加
6. main()をPhase1(fast)/Phase2(seq)/Phase3(CSV)/Phase4(md5)/Phase5(meta)に改修
7. 月次リターン配列は固定長NaN埋め(可変長だとDataFrame構築でエラー)
8. align_months共通月を全12コンポーネントで事前計算(L041)
9. `python3 run_077_oikaze.py` で実行、PASS確認

### kawarimi（sasuke — 2026-02-18 完了 — ✅正本mode CSVs使用）

| 項目 | 内容 |
|------|------|
| 担当 | sasuke |
| タスク | subtask_161_kawarimi_speedup |
| スクリプト | run_077_kawarimi.py |
| 入力データ | mode CSVs: joushou4(wide)+chishou4(long) = 8コンポーネント |
| パターン数 | 100（検証用） |
| コンポーネント数 | 8（gekkou4件除外: max_cagr月次リターンCSV未存在） |
| 結果 | **全7AC PASS** |
| 14列CSV md5 | 078bd91cb9c80e61c0555c228ce9cc04（一致） |
| 月次リターンCSV md5 | eb192c0e5762b78305493b37eaeb0140（一致） |
| 逐次版時間 | 1.075秒 |
| 高速版時間 | 0.205秒 |
| 高速化倍率 | **5.23倍** |
| 合計実行時間 | 1.6秒（3分制限内） |
| 共通月 | 173ヶ月 (2011-09..2026-01) |

**改修内容（sasuke記録・原文）**:
1. run_077_kawarimi.py を 064_champion入力から mode CSVs入力へ全面移行
   - newhigh: wide形式 4ファイル
   - maxdd: long形式 4ファイル(filter_col/filter_val指定)
   - gekkou(max_cagr): 月次CSV欠落のため除外(C8運用)
2. NumPyベクトル化を実装
   - get_sim_contextでopen_matrix/momentum_cubeを事前構築
   - period_monthsごとのモメンタムを前処理
3. 逐次版(simulate_pattern_sequential)を併設し、同一common_monthsで比較
4. 月次リターンCSV(monthly_fast/monthly_seq)を出力しmd5比較を追加

**bunshinとの差異・ハマりポイント（sasuke記録・原文）**:

**(a) top_n + bottom_n の和集合選出（kawarimi固有）**:
- oikazeはtop_n単独選出だが、kawarimiはtop_n + bottom_nの和集合
- bottom側のtie-breakを明示:
  - fast: np.lexsort((valid_local, scores[valid_local]))
  - seq: sorted(key=(score asc, components.index))
  を揃えた

**(b) 候補不足時の前回選出維持（kawarimi固有）**:
- 候補不足(<2)時は「前回選出維持」
- この挙動はoikazeにはなくkawarimi固有

**(c) bunshinとの差異**:
- bunshinはモメンタム不要(等配分)だが、kawarimiはperiod_monthsごとのモメンタム前処理が必須
- momentum_cubeを期間軸付きで保持する実装にした

**(d) mode CSVs期間差の処理**:
- 全コンポーネント共通月(173ヶ月)を逐次版/高速版で共用して不一致リスクを回避

**再現手順（sasuke記録・原文）**:
1. `cd /mnt/c/Python_app/DM-signal/scripts/analysis/grid_search`
2. `python3 run_077_kawarimi.py`
3. 生成物:
   - `outputs/grid_search/161_kawarimi_grid_results_{fast,seq}.csv`
   - `outputs/grid_search/161_kawarimi_grid_monthly_{fast,seq}.csv`
4. ログのmd5一致(14列CSV + 月次CSV)がYESならPASS

### bunshin R3（sasuke — 2026-02-18 完了 — ✅正本mode CSVs C12使用）

| 項目 | 内容 |
|------|------|
| 担当 | sasuke |
| タスク | subtask_165_bunshin_r3 |
| スクリプト | run_077_bunshin.py |
| 入力データ | mode CSVs: joushou4(wide)+chishou4(long)+gekkou4(long) = 全12コンポーネント |
| パターン数 | 500（PATTERN_LIMIT） |
| グリッド全体 | 781パターン |
| コンポーネント数 | 12（C12） |
| 結果 | **全5AC PASS** |
| 14列CSV md5 | cbe7b7e1334ab32af420c82924a9ece6（一致） |
| 月次リターンCSV md5 | 64f74ebd10ef527e3e467a707080776c（一致） |
| R3ベースライン | 0.025秒 |
| R3最適化版 | **0.017秒** |
| 逐次版時間 | 1.029秒 |
| 高速化倍率 | 1.45x(vs baseline), 60.28x(vs seq) |
| R1記録 | 0.043秒(kagemaru) → **更新** |
| 共通月 | 173ヶ月 |

**★ bunshin固有の知見（R3で判明・L049）**:
- bunshin（均等配分）は**選出ロジックを持たない**ため、他忍法R3で効いた「純Pythonインナーループ」は**逆効果**
  - 純Pythonインナーループ: 0.024→0.029秒（悪化、0.83x）
- 有効だったのは**固定長分岐ベクトル化（fixed-arity vectorization）**:
  - NaN→0埋めfilled_matrix + valid_matrix(uint8)を事前計算
  - subset_size=2/3/4で固定されるため、N2/N3/N4ごとに加算式を固定化
  - np.nansum/np.sum(~isnan)を置換し、関数オーバーヘッドを削減
  - 結果: 0.025→0.017秒（1.45x）

**R3手法選択の指針（L049まとめ）**:
- picks系（Pre-computed picks + 純Python）→ kawarimi, nukimi, nukimi_c（選出ロジックあり）
- vectorization系（fixed-arity vectorization）→ bunshin（選出ロジックなし、単純平均）
- kasoku: picks系が有効（cutoff_score閾値選出、0.577→0.127s, 4.54x — kirimaru R3で実証）
- oikaze: 未検証（momentum top_n選出 → picks系？ sasuke R3で検証中）

**再現手順**:
1. `cd /mnt/c/Python_app/DM-signal`
2. `python3 scripts/analysis/grid_search/run_077_bunshin.py`
3. 出力: `outputs/grid_search/165_bunshin_grid_{results,monthly}_{fast,seq}.csv`
4. Phase 4でmd5一致を自動検証

### kawarimi R3（kotaro — 2026-02-18 完了 — ✅正本mode CSVs C12使用）

| 項目 | 内容 |
|------|------|
| 担当 | kotaro |
| タスク | subtask_165_kawarimi_r3 |
| スクリプト | run_077_kawarimi.py |
| 入力データ | mode CSVs: joushou4(wide)+chishou4(long)+gekkou4(long) = 全12コンポーネント |
| パターン数 | 100（検証用） |
| コンポーネント数 | 12（C12: 全コンポーネント） |
| 結果 | **全5AC PASS** |
| 14列CSV md5 | 70f9de5e0e886430a657601ec7e979e5（一致） |
| 月次リターンCSV md5 | eb192c0e5762b78305493b37eaeb0140（一致） |
| 逐次版時間 | 0.910秒 |
| 高速版時間(R3最適化) | **0.037秒** |
| R2記録(C8) | 0.205秒 |
| R3ベースライン(C12 NumPy版) | 0.206秒 |
| 対R2倍率 | **5.54倍** |
| 対逐次版倍率 | **24.59倍** |
| 共通月 | 173ヶ月 |
| グリッド全数 | 140,580 |

**R3で試した手法**:

**(1) Pre-computed picks + 純Pythonインナーループ（✅効果あり: 0.206s→0.037s, 5.57x）**:
- get_sim_contextでlexsort結果を(period_idx, select_n)ごとに事前計算
- simulate_patternではlookupのみ（lexsortの再実行を排除）
- 内部ループからnumpy呼び出しを完全排除
- open_matrixをPythonリスト化し、v==vでNaN判定（numpy不要）
- 小サブセット(2-4要素)ではnumpy関数呼び出しオーバーヘッド(~1-5μs/call)が実計算コスト(~10ns)を大幅に上回る
- 純Python演算+リストアクセスで関数呼び出しオーバーヘッドを排除

**(2) multiprocessing（❌未実施: 理論的に非効率）**:
- 計算時間0.037秒に対しプロセス生成オーバーヘッド~50ms
- オーバーヘッドが計算量を上回るため逆効果

**(3) メモリレイアウト最適化（❌効果なし）**:
- open_matrixはnp.column_stackで既にC-contiguous
- 追加最適化不要

**(4) Numba @jit（❌未実施）**:
- numbaモジュール未インストール（殿の指示で不使用）

**核心的発見（kotaro記録）**:
> NumPy高速化の次のフェーズは「NumPyを使わない」こと。
> 小サブセット(2-4コンポーネント)ではnumpy関数呼び出しオーバーヘッド(~1-5μs/call)が
> 実計算コスト(~10ns)を大幅に上回る。純Python演算+リストアクセスで
> 関数呼び出しオーバーヘッドを排除することで5.5倍の高速化を達成。
> 加えて、lexsort結果のキャッシュ化により同一コンテキストの複数パターン間で重複計算を排除。

**月次CSV md5がR2と同一(eb192c0e)の理由**:
- 先頭100パターンがN2サブセットでgekkou未使用のため

**再現手順（kotaro記録）**:
1. `cd /mnt/c/Python_app/DM-signal/scripts/analysis/grid_search`
2. `python3 run_077_kawarimi.py`
3. 出力: `outputs/grid_search/165_kawarimi_grid_{results,monthly}_{fast,seq}.csv`
4. Phase 4でmd5自動検証

### nukimi（kirimaru — 2026-02-18 完了 — ✅正本mode CSVs使用）

| 項目 | 内容 |
|------|------|
| 担当 | kirimaru |
| タスク | subtask_161_nukimi_speedup |
| スクリプト | run_077_nukimi.py |
| 入力データ | mode CSVs: joushou4(wide)+chishou4(long) = 8コンポーネント |
| パターン数 | 100（検証用） |
| コンポーネント数 | 8（gekkou4件除外: max_cagr月次リターンCSV未存在） |
| 結果 | **全7AC PASS** |
| 14列CSV md5 | 3a120a49edf46719f402df3ef47759dd（一致） |
| 月次リターンCSV md5 | e209257ce649c3ab380c22bfb7a6ca26（一致） |
| 逐次版時間 | 1.087秒 |
| 高速版時間 | 0.181秒 |
| 高速化倍率 | **6.02倍** |
| 合計実行時間 | 1.64秒（3分制限内） |
| 共通月 | 173ヶ月 (2011-09..2026-01) |

**改修内容（kirimaru記録・原文）**:
1. 入力を064_champion単一CSVからmode CSVs(8ファイル)へ切替
2. COMPONENT_SOURCESをwide(newhigh)+long(maxdd)混在specへ変更
3. get_sim_contextに共通月(common_months)指定を追加し、fast/seqで同一月セットを強制
4. 高速版(simulate_pattern)を固定長月次リターン配列出力へ変更
5. 逐次版(simulate_pattern_sequential)を新規追加
   - skip_months対応の_calc_momentum_with_skip_at_month()を追加
   - tie-breakをsorted(key=lambda x: (-x[1], components.index(x[0])))で統一
6. mainを5フェーズ化
   - Phase1 fast, Phase2 seq, Phase3 CSV出力, Phase4 md5検証, Phase5 meta出力
7. 100パターン制限(PATTERN_LIMIT=100)で実行し、3分制限内を確認

**bunshinとの差異・ハマりポイント（kirimaru記録・原文）**:

**(a) bunshinとの差異**:
- bunshinは「単純均等配分」でモメンタム計算自体が不要
- nukimiはbase-skipの実効モメンタム窓が必要なため、逐次版にもskipロジック実装が必須

**(b) oikazeとの差異**:
- oikazeは複数lookbackの加重平均モメンタム
- nukimiは単一窓(base-skip)のみで、_calc_momentum_with_skip_at_month()の窓切り出しが核心
- oikazeで問題化した「可変長月次リターン」はnukimiでも同様に起き得るため、固定長NaN埋めへ統一

**(c) 実装時の迷い**:
- subsetごとにalign_monthsするとfast/seqの比較軸がズレる懸念があった
- 解決として、全コンポーネント共通月(173ヶ月)を事前計算しfast/seq双方に注入した

**再現手順（kirimaru記録・原文）**:
1. `cd /mnt/c/Python_app/DM-signal`
2. `python3 scripts/analysis/grid_search/run_077_nukimi.py`
3. 出力: `outputs/grid_search/161_nukimi_grid_{results,monthly}_{fast,seq}.csv`
4. Phase 4のmd5がfast==seqであることを確認
5. 前提: mode CSV 8ファイルがoutputs/grid_search/に存在すること

### nukimi R3（sasuke — 2026-02-18 完了）

| 項目 | 内容 |
|------|------|
| 担当 | sasuke |
| タスク | subtask_165_nukimi_r3 |
| スクリプト | run_077_nukimi.py |
| 入力データ | mode CSVs: joushou4(wide)+chishou4(long)+gekkou4(long) = 12コンポーネント |
| パターン数 | 500 |
| コンポーネント数 | 12(C12) |
| 結果 | **全5AC PASS** |
| 14列CSV md5 | f7528aef6057f7975a0c2985dee9a119（一致） |
| 月次リターンCSV md5 | d3ef15376c468c69e595deb6157ebb24（一致） |
| R2記録(C8/100pat) | 0.181秒 |
| R3ベースライン(C12/500pat) | 0.651秒 |
| **R3高速版(C12/500pat)** | **0.114秒** |
| R3逐次版(C12/500pat) | 4.537秒 |
| 対ベースライン倍率 | **5.71倍** |
| 共通月 | 173ヶ月 |

**R3で試した手法**:

**(1) Pre-computed picks + 純Pythonインナーループ（✅効果あり: 0.651s→0.114s, 5.71x）**:
- (combo_idx, top_n_eff)ごとのpick事前計算
- open_matrix.tolist() + v==v NaN判定による純Python平均計算
- NumPy関数呼出しオーバーヘッド排除

**(2) top_n未正規化precompute（❌失敗: 0.099sだがmd5不一致）**:
- N2サブセットでtop_n=3キー欠落(500中165件失敗)
- 修正: top_n_eff=min(top_n, subset_size)でキー統一

**核心的発見（sasuke記録）**:
> N2/N3/N4混在グリッドではsubsetサイズ<top_nが起きる。
> precomputed picksのキーをtop_n_eff=min(top_n,subset_size)で統一しないと
> keyError/md5不一致が発生する。この正規化が全忍法に必要。

**再現手順（sasuke記録）**:
1. `cd /mnt/c/Python_app/DM-signal`
2. `python3 scripts/analysis/grid_search/run_077_nukimi.py`
3. 出力: `outputs/grid_search/165_nukimi_grid_{results,monthly}_{fast,seq}.csv`
4. Phase 4でmd5自動検証

### nukimi_c（hayate — 2026-02-18 完了 — ✅正本mode CSVs使用）

| 項目 | 内容 |
|------|------|
| 担当 | hayate |
| タスク | subtask_161_nukimi_c_speedup |
| スクリプト | run_077_nukimi_c_series.py |
| 入力データ | mode CSVs: joushou4(wide)+chishou4(long) = 8コンポーネント |
| パターン数 | 100（検証用） |
| コンポーネント数 | 8（gekkou4件除外: max_cagr月次リターンCSV未存在） |
| 結果 | **全7AC PASS** |
| 14列CSV md5 | d30671461c96f50b11a772cf6e0022c8（一致） |
| 月次リターンCSV md5 | 57d4b294c91f36d338069de211c18136（一致） |
| 逐次版時間 | 0.789秒 |
| 高速版時間 | 0.160秒 |
| 高速化倍率 | **4.91倍** |
| 合計実行時間 | ~1.4秒（3分制限内） |
| 共通月 | 173ヶ月 |

**改修内容（hayate記録・原文）**:
1. 入力データを064_champion(汚染)からmode CSVs(正本)に全面移行
2. COMPONENT_SOURCESをC12→C8(joushou4 wide + chishou4 long, gekkou除外)
3. BLOCK_NAMEをc_nukimiからnukimi_cに変更(出力名161_nukimi_c_grid_*)
4. get_sim_contextを全面改修: momentum_cube(3D ndarray)で全skip/effective組を事前構築
5. MOMENTUM_COMBOS/MOMENTUM_TO_INDEX追加: skip×effective組を事前列挙しインデックス化
6. rebalance_masksを事前計算(ループ内の関数呼出排除)
7. simulate_pattern返り値をDict→Tuple[Dict, np.ndarray]に変更
8. simulate_pattern_sequential新規追加(逐次版)
9. _calc_momentum_with_skip_at_month新規追加(逐次版skip計算)
10. calc_momentum_with_skip新規追加(前処理用一括計算)
11. build_monthly_returns_df新規追加(月次リターンCSV出力)
12. main()を5フェーズ化(fast/seq/CSV/md5/meta)
13. 旧コード削除: _cumret, get_momentum_matrix, old calc_metrics, csv.DictWriter

**nukimiとの差異（hayate記録・原文）**:
- 計算ロジックは完全同一。C-series固有のロジック差異なし
- パラメータのみ異なる: nukimi T1-T3 vs nukimi_c T1-T5
- 全グリッド: nukimi 66,150 vs nukimi_c 150,150パターン

**bunshinとの差異（hayate記録・原文）**:
- bunshinはモメンタム不要(等配分)。nukimi_cはbase-skip窓モメンタム必須
- bunshinは全月リターン出る。nukimi_cはlookback不足月NaN→固定長NaN埋め
- bunshinはtie-break不要。nukimi_cはlexsort(fast)/sorted(seq)で統一

**ハマりポイント（hayate記録・原文）**:
- 064_champion使用禁止(汚染データ退避済み)→mode CSVsのみ正本
- newhigh=wide/maxdd=long混在→gs_csv_loaderのformat指定で対応
- align_months共通月不一致→main()で全コンポ共通月を1回計算し両版に渡す(最重要)
- 月次リターン可変長→固定長NaN埋め+valid部分のみcalc_metrics_fastに渡す

**教訓参照（hayate記録）**:
- L041(bunshin知見), L042(mode CSVs形式), L043(kawarimi知見), L044(nukimi知見) → 全て事前読込み済み
- 5忍法知識継承により初回一発PASS

**再現手順（hayate記録・原文）**:
1. `cd /mnt/c/Python_app/DM-signal/scripts/analysis/grid_search`
2. `python3 run_077_nukimi_c_series.py`
3. 出力: `outputs/grid_search/161_nukimi_c_grid_{results,monthly}_{fast,seq}.csv`
4. Phase 4でmd5自動検証。戻り値0=PASS
5. 前提: mode CSV 8ファイル存在。既存出力は事前リネーム要

### nukimi_c R3（kirimaru — 2026-02-18 完了 — ※対象外だが配備済みのため完了）

| 項目 | 内容 |
|------|------|
| 担当 | kirimaru |
| タスク | subtask_165_nukimi_c_r3 |
| スクリプト | run_077_nukimi_c_series.py |
| 入力データ | mode CSVs: joushou4(wide)+chishou4(long)+gekkou4(long) = 12コンポーネント |
| パターン数 | 500 |
| コンポーネント数 | 12(C12) |
| 結果 | **全5AC PASS** |
| 14列CSV md5 | 461cd0189c52646f8522ea008aee482e（一致） |
| 月次リターンCSV md5 | 1549d4e9e382abbb1cacf602e2644e60（一致） |
| R2記録(C8/100pat) | 0.160秒 |
| R3ベースライン(C12/500pat) | 0.658秒 |
| **R3高速版(C12/500pat)** | **0.126秒** |
| R3逐次版(C12/500pat) | 4.775秒 |
| 対ベースライン倍率 | **5.23倍** |
| 共通月 | 173ヶ月 |
| 備考 | 殿指示で対象外(5忍法にnukimi_c含まず)だが配備済みのため完了 |

**R3で試した手法**:

**(1) Pre-computed picks + 純Pythonインナーループ（✅効果あり: 0.658s→0.126s, 5.23x）**:
- get_sim_contextで(combo_idx, top_n)ごとのpicksを事前計算
- open_matrixをlist化し、NaN判定をv==vで処理
- NumPy呼び出しオーバーヘッドを排除

**skill_candidate**: gs-precompute-picks-small-subset
- 小サブセットGSでpick結果を事前計算し、inner loopを純Python化する高速化手法
- kawarimi/nukimi_cの2忍法で再現し、C12/500でもmd5一致を保ったまま有効

**再現手順（kirimaru記録）**:
1. `cd /mnt/c/Python_app/DM-signal`
2. `python3 scripts/analysis/grid_search/run_077_nukimi_c_series.py`
3. 出力: `outputs/grid_search/165_nukimi_c_grid_{results,monthly}_{fast,seq}.csv`
4. Phase 4でmd5自動検証

### kasoku R3（kirimaru — 2026-02-19 完了 — ✅正本mode CSVs C12使用）

| 項目 | 内容 |
|------|------|
| 担当 | kirimaru |
| タスク | subtask_165_kasoku_r3 |
| スクリプト | run_077_kasoku.py |
| 入力データ | mode CSVs: joushou4(wide)+chishou4(long)+gekkou4(long) = 全12コンポーネント |
| パターン数 | 500（PATTERN_LIMIT） |
| コンポーネント数 | 12（C12） |
| 結果 | **全5AC PASS** |
| 14列CSV md5 | cef240cc1ef82e6bab59db6c158e32d8（一致） |
| 月次リターンCSV md5 | 2d92b67c55cd57b65a9712d811aa759f（一致） |
| R2記録(C8/100pat) | 0.272秒(saizo) |
| R3ベースライン(C12/500pat) | 0.577秒 |
| **R3最適化版(C12/500pat)** | **0.127秒** |
| R3逐次版(C12/500pat) | 5.896秒 |
| 対R2倍率 | **2.14倍**(0.272→0.127) |
| 対ベースライン倍率 | **4.54倍**(0.577→0.127) |
| 対逐次版倍率 | **46.4倍**(5.896→0.127) |
| 共通月 | 173ヶ月 |

**R3で試した手法**:

**(1) Pre-computed picks + 純Pythonインナーループ（✅効果あり: 0.577s→0.127s, 4.54x）**:
- (num_mc, den_mc, method, top_n_eff)ごとのpick tableを事前生成
- simulate_patternではlookupのみ（再ソートを排除）
- 内部ループからnumpy呼び出しを完全排除
- open_matrixをPythonリスト化し、v==vでNaN判定
- kasoku固有のcutoff_score閾値選出もpicks化に適合

**(2) NumPy row-scan baseline（❌ベースラインのみ: 0.577s）**:
- R2手法そのまま。C8→C12でオーバーヘッド増加

**核心的発見（kirimaru記録）**:
> kasokuでも小サブセット(N2/N3/N4)はprecomputed picks+純Python内ループが有効。
> C12/500で0.577s→0.127s(4.54x)かつmd5一致。cutoff_score閾値選出もpicks化と相性良好。

**skill_candidate**: gs-kasoku-precompute-picks
- 加速スコア行列から(num_mc,den_mc,method,top_n_eff)別にpick tableを事前生成し、月ループをlookup化する

**再現手順（kirimaru記録）**:
1. `cd /mnt/c/Python_app/DM-signal`
2. `python3 scripts/analysis/grid_search/run_077_kasoku.py`
3. 出力: `outputs/grid_search/165_kasoku_grid_{results,monthly}_{fast,seq}.csv`
4. Phase 4でmd5自動検証

### oikaze R3（kirimaru — 2026-02-19 完了 — ✅正本mode CSVs C12使用）

| 項目 | 内容 |
|------|------|
| 担当 | kirimaru |
| タスク | subtask_165_oikaze_r3 |
| スクリプト | run_077_oikaze.py |
| 入力データ | mode CSVs: joushou4(wide)+chishou4(long)+gekkou4(long) = 全12コンポーネント |
| パターン数 | 500（PATTERN_LIMIT） |
| コンポーネント数 | 12（C12） |
| 結果 | **全5AC PASS** |
| 14列CSV md5 | 4ad941244d184596513931f931cfe8dd（一致） |
| 月次リターンCSV md5 | f67a14b99553a172254b993c3a5aadac（一致） |
| R2記録(C8/100pat) | 0.115秒(hanzo) |
| R3ベースライン(C12/500pat) | 0.123秒 |
| **R3最適化版(C12/500pat)** | **0.093秒** |
| R3逐次版(C12/500pat) | 5.019秒 |
| 対R2倍率 | **1.24倍**(0.115→0.093) |
| 対ベースライン倍率 | **1.32倍**(0.123→0.093) |
| 対逐次版倍率 | **54.23倍**(5.019→0.093) |
| 共通月 | 173ヶ月 |

**R3で試した手法**:

**(1) Pre-computed picks + 純Pythonインナーループ（✅効果あり: 0.123s→0.093s）**:
- get_sim_contextで選出結果を事前計算
- simulate_patternではlookupのみ（再ソートを排除）
- 内部ループからnumpy呼び出しを完全排除
- R3主手法。目標0.115秒未満を達成

**(2) common_months固定をfast側get_sim_contextへ適用（✅効果あり: md5完全一致を実現）**:
- subset別align_monthsのままだとfast側月次配列長が混在しCSV組立で失敗
- mainで計算した全コンポ共通月(common_months)をfastのget_sim_contextにも強制
- cache keyにmonths signatureを追加し誤キャッシュを防止
- 172行固定で月次CSV出力成功

**(3) subset別align_months（❌失敗: md5不一致）**:
- build_monthly_returns_dfで配列長不一致(ValueError: All arrays must be of the same length)

**核心的発見（kirimaru記録）**:
> oikazeはsubset別align_monthsのままだとfast側月次配列長が混在し、CSV組立で失敗する。
> mainで計算した全コンポ共通月(common_months)をfastのget_sim_contextにも強制し、
> cache keyにmonths signatureを含めると、md5完全一致を維持したまま安定出力できる。

**改修箇所（kirimaru記録）**:
- run_077_oikaze.py: get_sim_contextにcommon_months引数を追加
- run_077_oikaze.py: cache keyへmonths signatureを追加し誤キャッシュを防止
- run_077_oikaze.py: simulate_patternにcommon_months引数を追加
- run_077_oikaze.py: main() fast実行からcommon_monthsを渡して月次長を固定

**skill_candidate**: gs-common-month-lockstep
- fast/seq双方へcommon_monthsを注入し、可変長月次出力不整合を予防する定型パターン

**再現手順（kirimaru記録）**:
1. `cd /mnt/c/Python_app/DM-signal`
2. `python3 scripts/analysis/grid_search/run_077_oikaze.py`
3. 出力: `outputs/grid_search/165_oikaze_grid_{results,monthly}_{fast,seq}.csv`
4. Phase 4のmd5一致(14列+月次)を確認
5. 前提: 同名出力ファイルが未存在であること

### nukimi R4（kirimaru — 2026-02-19 完了 — ✅正本mode CSVs C12使用）

| 項目 | 内容 |
|------|------|
| 担当 | kirimaru |
| タスク | subtask_165_nukimi_r4 |
| スクリプト | run_077_nukimi.py |
| 入力データ | mode CSVs: joushou4(wide)+chishou4(long)+gekkou4(long) = 12コンポーネント |
| パターン数 | 500 |
| コンポーネント数 | 12(C12) |
| 結果 | **全5AC PASS** |
| 14列CSV md5 | f7528aef6057f7975a0c2985dee9a119（一致） |
| 月次リターンCSV md5 | d3ef15376c468c69e595deb6157ebb24（一致） |
| R3記録(C12/500pat) | 0.114秒 |
| R4ベースライン(C12/500pat) | 0.053秒 |
| **R4高速版(C12/500pat)** | **0.053秒** |
| R4逐次版(C12/500pat) | 4.38秒 |
| 対R3倍率 | **2.15倍**(0.114→0.053) |
| 対逐次版倍率 | **82.4倍**(4.38→0.053) |
| 共通月 | 173ヶ月 |

**R4で試した手法**:

**(1) R3継承手法の現行R4実装検証（✅効果あり: 0.053s — R3記録0.114sを更新）**:
- precomputed picks + pure-python inner loop + cumprod momentum
- R3手法がそのまま有効。追加変更なしで記録更新

**(2) multiprocessing ProcessPool workers=2（❌逆効果: 0.134s）**:
- 単体0.049sに対してプロセス初期化オーバーヘッドが支配

**(3) multiprocessing ProcessPool workers=4（❌逆効果: 0.103s）**:
- workers=2より速いが単体0.049sより遅い

**(4) multiprocessing ProcessPool workers=8（❌逆効果: 0.148s）**:
- ワーカー増で逆に悪化

**(5) open_matrixメモリレイアウト確認（❌追加最適化余地なし）**:
- C_CONTIGUOUS=True, F_CONTIGUOUS=False。既に最適

**核心的発見（kirimaru記録）**:
> 単体実行が0.05秒級のGSではmultiprocessingは逆効果。
> workers=2/4/8すべて単体(0.049s)より遅い（0.134/0.103/0.148s）。
> プロセス生成オーバーヘッド(~50ms)が計算時間を支配する。

**再現手順（kirimaru記録）**:
1. `cd /mnt/c/Python_app/DM-signal`
2. `python3 scripts/analysis/grid_search/run_077_nukimi.py`
3. 出力: `outputs/grid_search/165_nukimi_grid_{results,monthly}_{fast,seq}.csv`
4. Phase 4でmd5自動検証

### kasoku R4（sasuke — 2026-02-19 完了 — ✅正本mode CSVs C12使用）

| 項目 | 内容 |
|------|------|
| 担当 | sasuke |
| タスク | subtask_165_kasoku_r4 |
| スクリプト | run_077_kasoku.py |
| 入力データ | mode CSVs: joushou4(wide)+chishou4(long)+gekkou4(long) = 12コンポーネント |
| パターン数 | 500 |
| コンポーネント数 | 12(C12) |
| 結果 | **全5AC PASS** |
| 14列CSV md5 | cef240cc1ef82e6bab59db6c158e32d8（一致） |
| 月次リターンCSV md5 | 2d92b67c55cd57b65a9712d811aa759f（一致） |
| R3記録(C12/500pat) | 0.127秒 |
| R4ベースライン(C12/500pat) | 0.110秒 |
| **R4高速版(C12/500pat)** | **0.089秒** |
| R4逐次版(C12/500pat) | 5.477秒 |
| 対R3倍率 | **1.43倍**(0.127→0.089) |
| 対逐次版倍率 | **61.5倍**(5.477→0.089) |
| 共通月 | 173ヶ月 |

**R4で試した手法**:

**(1) R3再計測（ベースライン取得: 0.110s — R3記録0.127sより速い）**:
- R3コードそのまま。環境差でR3記録より速いベースライン

**(2) PeriodIndex参照最適化（✅効果あり: 0.110s→0.089s, 19.1%短縮）**:
- get_kasoku_context内のperiod in/get_loc反復参照がボトルネック
- index.get_indexer(months)を先計算して同一ロジックのまま高速化
- md5完全一致を維持

**(3) multiprocessing workers=2（❌逆効果: 0.154s > serial 0.096s）**:
**(4) multiprocessing workers=4（❌逆効果: 0.166s > serial 0.096s）**:
**(5) multiprocessing workers=8（❌逆効果: 0.223s > serial 0.096s）**:
- 全workers数で単体実行より遅い

**(6) 内ループ方式比較（✅list維持が有利）**:
- list_inner_loop=0.0146s, numpy_row_inner_loop=0.0203s
- list方式維持が有利と確認

**核心的発見（sasuke記録）**:
> PeriodIndexの反復参照(period in + get_loc)が前処理ボトルネック。
> index.get_indexer(months)を先計算して同一ロジックのまま0.110→0.089s(19.1%短縮)。
> md5完全一致を維持。

**skill_candidate**: gs-periodindex-indexer-precompute
- pandas PeriodIndex参照を月位置indexer配列へ置換し、rolling windowの意味を保持したまま前処理を高速化する手筋

**再現手順（sasuke記録）**:
1. `cd /mnt/c/Python_app/DM-signal`
2. `python3 scripts/analysis/grid_search/run_077_kasoku.py`
3. 出力: `outputs/grid_search/165_kasoku_grid_{results,monthly}_{fast,seq}.csv`
4. Phase 4でmd5自動検証

### kasoku（saizo — 2026-02-18 完了 — ✅正本mode CSVs使用）

| 項目 | 内容 |
|------|------|
| 担当 | saizo |
| タスク | subtask_161_kasoku_speedup |
| スクリプト | run_077_kasoku.py |
| 入力データ | mode CSVs: joushou4(wide)+chishou4(long) = 8コンポーネント |
| パターン数 | 100（検証用） |
| コンポーネント数 | 8（gekkou4件除外: max_cagr月次リターンCSV未存在） |
| 結果 | **全7AC PASS**（家老独立検証でもmd5一致確認済み） |
| 14列CSV md5 | 68a63cca700c0f44f30a0cfeea226c84（一致） |
| 月次リターンCSV md5 | f76feea4c7aa6825f2ba8928db3d4424（一致） |
| 逐次版時間 | 1.387秒 |
| 高速版時間 | 0.272秒 |
| 高速化倍率 | **5.10倍** |
| 合計実行時間 | 2.3秒（3分制限内） |
| 共通月 | 173ヶ月 |

**改修内容（saizo記録）**:
1. データソース: 064_champion(C12) → mode CSVs(C8: joushou4+chishou4)
2. simulate_pattern: 返り値をTuple[Dict, np.ndarray]に変更(固定長NaN埋め月次リターン)
3. simulate_pattern_sequential: 同様にTuple返り + calc_metrics_fast使用 + common_months引数追加
4. build_monthly_returns_df: 新規追加(月次リターンCSV生成用)
5. main(): 5フェーズ化(fast→seq→CSV出力→md5検証→meta.yaml)
6. PATTERN_LIMIT=100, calc_metrics(旧逐次版)を削除しcalc_metrics_fastに統一
7. write_meta_yaml: MODE_CSV_FILESでプロヴェナンス情報を生成

**kasoku固有の知見（saizo記録）**:

**(a) cutoff_scoreによるtie-break処理が自然に一致**:
- kasokuはnp.lexsortで降順ソート後にcutoff_scoreで閾値以上を全選出
- 逐次版でもsorted+cutoff_scoreで同等の処理
- kawarimi(L043)のようなtop_n+bottom_n和集合選出問題がなく、自然に一致した

**(b) ratioメソッドのゼロ除算保護**:
- |mom_long|<1e-6 → ±1e-6置換でfast/seqで同一ロジック
- kasoku固有の加速度計算(momentum変化率)で除算が発生するため必要

**bunshinとの差異（saizo記録）**:
- bunshinはモメンタム不要(等配分)。kasokuは加速度(モメンタム変化率)ベースの選出
- bunshinは全月固定長リターン。kasokuはlookback不足月でNaN→固定長NaN埋め
- kasokuはパラメータ直積が最大(1530パターン全体)。100制限で実行

**再現手順（saizo記録）**:
1. `cd /mnt/c/Python_app/DM-signal`
2. `python3 scripts/analysis/grid_search/run_077_kasoku.py`
3. 出力: `outputs/grid_search/161_kasoku_grid_{results,monthly}_{fast,seq}.csv`
4. Phase 4でmd5自動検証。戻り値0=PASS
5. 前提: mode CSV 8ファイルがoutputs/grid_search/に存在すること

---

## 5. 失敗記録

（今回は成功。失敗記録なし）

---

## 6. 忍法間の差異まとめ

| 項目 | bunshin | oikaze | kawarimi | nukimi | nukimi_c | kasoku |
|------|---------|--------|----------|--------|----------|--------|
| 配分方式 | 均等配分(1/N) | モメンタムtop_n | top_n+bottom_n和集合 | 単一窓(base-skip)モメンタムtop_n | 同nukimi(C-series) | 加速度(momentum変化率)cutoff |
| モメンタム計算 | 不要 | 必要(lookback窓) | 必要(period_months軸) | 必要(base-skip窓) | 必要(base-skip窓) | 必要(長短2窓+ratio) |
| 月次リターン長 | 全月固定 | 可変→固定NaN埋め | 可変→固定NaN埋め | 可変→固定NaN埋め | 可変→固定NaN埋め | 可変→固定NaN埋め |
| 逐次版の複雑さ | 低 | 中(_calc_momentum_at_month) | 中(top+bottom tie-break) | 中(_calc_momentum_with_skip_at_month) | 中(同nukimi) | 中(cutoff_score+ratio) |
| tie-breaking | なし | あり(top_n) | あり(top_n+bottom_n各別) | あり(top_n) | あり(top_n) | あり(cutoff閾値全選出) |
| 固有要素 | なし | lookback窓,加重平均 | bottom_n選出,候補不足時前回維持 | skip_months処理 | 同nukimi(パラメータのみ差異) | ゼロ除算保護,閾値全選出 |
| 高速化倍率 | 55.5倍(計算部) | v2:7.49倍 | 5.23倍 | 6.02倍 | 4.91倍 | 5.10倍 |
| 高速版秒数(R2/C8) | — | 0.115s | 0.205s | 0.181s | 0.160s | 0.272s |
| 逐次版秒数(R2/C8) | — | 0.863s | 1.075s | 1.087s | 0.789s | 1.387s |
| **R3高速版秒数(C12/500pat)** | **0.017s** | **0.093s** | **0.037s** | **0.114s** | **0.126s**※ | **0.127s** |
| R3ベースライン(C12/500pat) | 0.025s | 0.123s | 0.206s | 0.651s | 0.658s※ | 0.577s |
| R3逐次版(C12/500pat) | 1.029s | 5.019s | 0.910s | 4.537s | 4.775s※ | 5.896s |
| R3担当 | sasuke | kirimaru | kotaro | sasuke | kirimaru※ | kirimaru |
| R3パターン数 | 500 | 500 | 100 | 500 | 500※ | 500 |
| R3有効手法 | fixed-arity vec | precomp picks+common_months | precomp picks | precomp picks | precomp picks※ | precomp picks |
| **R4高速版秒数(C12/500pat)** | — | — | — | **0.053s** | — | **0.089s** |
| R4ベースライン(C12/500pat) | — | — | — | 0.053s | — | 0.110s |
| R4逐次版(C12/500pat) | — | — | — | 4.38s | — | 5.477s |
| R4担当 | — | — | — | kirimaru | — | sasuke |
| R4有効手法 | — | — | — | R3継承(そのまま) | — | PeriodIndex indexer |
| R4 multiprocessing | — | — | — | ❌(0.103-0.148s) | — | ❌(0.154-0.223s) |
| 入力データ | mode CSVs(正本) | mode CSVs(正本) | mode CSVs(正本) | mode CSVs(正本) | mode CSVs(正本) | mode CSVs(正本) |
| コンポーネント数 | 12 | 8(gekkou除外) | 8(gekkou除外) | 8(gekkou除外) | 8(gekkou除外) | 8(gekkou除外) |
| 共通月 | 143 | 173 | 173 | 173 | 173 | 173 |
| 14列CSV md5 | ec68da... | b32408... | 078bd9... | 3a120a... | d30671... | 68a63c... |
| 月次CSV md5 | 97aa46... | c1f07b... | eb192c... | e20925... | 57d4b2... | f76fee... |

---

## 7. nukimi_c正式廃止（殿裁定 2026-02-19）

**結論**: nukimi_cはnukimiに統合。run_077_nukimi_c_series.pyはarchive/deprecated/へ移動。

**根拠（L054 — sasuke Codex調査）**:
- 戦略計算ロジック: **完全同一**（calc_momentum_with_skip, _calc_momentum_with_skip_at_month等、共通16関数中全て一致）
- パラメータ差分: PARAM_GRID_TOPNのみ（nukimi: T1-T3 → nukimi_c: T1-T5）
- 300パターン照合: mismatch = 0
- nukimiをT1-T5に拡張すれば、nukimi_cの全761,475パターンを完全包含（差集合0）

**実施内容**:
1. run_077_nukimi.py: PARAM_GRID_TOPNにT4(top_n=4), T5(top_n=5)を追加
2. run_077_nukimi_c_series.py → archive/deprecated/ へ移動(git mv)
3. フル計算パターン数: 2,763,641 → 2,002,166（76万パターン削減）

**影響**:
- §6比較表のnukimi_c列は「廃止(nukimiに統合)」
- 今後のGSではnukimi 1本でT1-T5全カバー
- 高速化知見(R3 precomp picks等)はnukimiにそのまま適用

---

## 更新ルール（殿指示）

1. 毎回のトライ後にこのドキュメントを更新する
2. 省略するな。原文のまま記録
3. 成功も失敗も記録する。失敗は特に重要
4. 各忍者の知見は次の忍者のタスクYAMLに全注入する
5. 1回目の知見→2回目に注入→2回目の知見も追記→3回目に注入→…知識が厚くなる
