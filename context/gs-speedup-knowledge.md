# GS高速化×完全一致 — 知見集約ドキュメント（索引）
<!-- last_updated: 2026-03-17 kasoku ratio/diff 2分割恒久化 + R5チャンク分割基準追加 -->
<!-- Vercel分割: 詳細 → docs/research/gs-speedup-details.md -->

> 管理責任: 家老(karo)
> 目的: 各忍法GSスクリプトの高速化知見を蓄積し、次の忍者のタスクYAML注入元とする

---

## §1 完全一致の定義（殿裁定 2026-02-18 20:19）

| # | 条件 | 検証方法 |
|---|------|----------|
| 1 | CSV行数が逐次版と高速化版で同一 | wc -l |
| 2 | 全14列(pattern_id〜new_high_ratio)のmd5sumが完全一致 | md5sum |
| 3 | 月次リターン時系列CSVのmd5sumが完全一致 | md5sum |

- 逐次版 = 高速化コード無効(pd.Series直接計算)
- 高速化版 = NumPyベクトル化+前処理キャッシュ
- **両方の出力が1bitも違わないこと**が合格条件

---

## §2 入力データパス（殿指示: 忍者に推測させるな）

正本入力（cmd_160裁定, cmd_163再確認）:
- **max_cagr系コンポーネントCSV**: `/mnt/c/Python_app/DM-signal/outputs/grid_search/max_cagr_fof_components_DM*.csv`
  - 例: `.../max_cagr_fof_components_DM2.csv`, `...DM3.csv`, `...DM6.csv`, `...DM7plus.csv`
- **newhigh系mode結果CSV**: `/mnt/c/Python_app/DM-signal/outputs/grid_search/066_newhigh_mode_results_DM*.csv`
  - DM単体/複合(例: `...DM2.csv`, `...DM2_DM3.csv`, `...DM2_DM3_DM6_DM7_plus.csv`)
- **max_maxdd系mode結果CSV**: `/mnt/c/Python_app/DM-signal/outputs/grid_search/max_maxdd_mode_results_DM*.csv`
  - 例: `...DM2.csv`, `...DM3.csv`, `...DM6.csv`, `...DM7plus.csv`

汚染データ（使用禁止）:
- `064_champion_monthly_returns.csv` は cmd_163 で `archive/contaminated/` へ退避済み

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

## §3 高速化手法（L041 + kagemaru知見）

### (1) pd.Series演算 → NumPy配列一括演算に置換
- ループ内のpd.Series.get()を143月×N回呼ぶ → ndarray一括演算に変更
- Python loopがボトルネック。NumPy化でC言語レベルの速度に

### (2) 月次リターン前処理をループ外で事前キャッシュ化
- パターンループの外で1回だけ前処理を実行
- 各パターンではキャッシュ済みデータを参照するのみ

### (3) get_sim_contextで全コンポーネントのmatrix(ndarray)を1回構築しnumpyスライス
- 全コンポーネント(bunshinなら12個)の月次リターンを143×N のndarrayとして1回構築
- 各パターンではnumpyスライスで必要列を取得

### (4) subset context前計算を先に最適化（cmd_1030）
- L366: pattern内loopよりsubset context前計算を先に最適化すべし。wall-clock支配はsimulate_patternのfor-loopよりget_*_contextのprecomputed_picks/momentum cacheに集中
- L380: kasoku ctx buildの主犯はprecomputed_picks構築(84.8%=79.34ms/93.54ms)。momentum計算は11msで支配的でない（cmd_1034）
- L395: picks構築ボトルネックはscore matrix数に比例(kasoku 306 vs yotsume 10)。アルゴリズム転用では改善しない。numpy vectorizeが正攻法（cmd_1037）

### (5) Numba適用はpure kernelに絞れ（cmd_1030）
- L369: subset cache削減後はNumba候補をpure kernel(simulate_pattern hot loop, momentum kernel)に絞らぬと費用対効果が崩れる。pandas境界がブロック
- L382: kernel-only 14.3xだがPython→ndarray pack毎回で0.42x逆効果。pack済みpicks事前保存する設計に限定（cmd_1034。L387統合）
- L398: 5忍法(bunshin除)のsimulate_pattern inner loop完全同一構造。共有@njitカーネル化で14-22x(kernel単体)。ただしctx build 84.8%天井でcombined 1.3-1.5x（cmd_1037）

### (6) GS並列化 PPE（cmd_1030-1031）
- L372: context buildがボトルネック、ThreadPool無効、ProcessPoolExecutor 6 workers最適
- L373: 月次解像度GS dedupはbuild_grid canonicalizationに閉じ込めよ（cmd_1031）
- L374: GS PPEはsubset_id単位chunkingを維持せよ。pattern単位分割だとcache localityを捨てる（cmd_1031）
- L383: PPE result pickleがoverhead最大要因(50Kで877ms=51%)。metrics-only returnでndarray転送不要に（cmd_1034。L388統合）
- L396: PPE result pickleの92.1%はndarray(168 float64)。shared_memoryで50Kスケール877ms→96ms削減見込。パリティ完全一致確認済み（cmd_1037）

### (7) vectorized batch simulation（cmd_1034-1037）
- L385: boolean mask方式でsim phase 3.36x高速化。ただしctx build支配(85ms vs sim30ms)でcombined 1.23x。mask構築65%がforward-fill依存でpure numpy不可→Cython/Numba候補（cmd_1034）
- L390: yotsume batch sim(3D mask)はregression。4視点union+forward-fill構造にはboolean mask不適合（cmd_1035）
- L393: serialがbatchより速い場合あり: grouped順+context cacheが効く150pat規模では逐次呼出しの方がbatch(毎回context構築)より速い（cmd_1035）
- L394: batch sim適用判断基準: 制御フロー線形 AND ctx build支配率>50%の忍法にのみ有効。yotsumeは-225%regression（cmd_1037）
- L399: picks構築ボトルネック解消にはデータ表現変更(list→bool mask)が鍵。データ形式変更の連鎖的高速化(picks+sim mask両方)が大きい（cmd_1037）

### 月次リターンCSV出力（build_monthly_returns_df）
- wide形式: 1列目=year_month, 残列=pattern_id
- 値=月次リターン(float)、NaNなし
- 逐次版・高速化版それぞれで出力し、md5比較

---

## §4 ハマりポイント

### align_months月セット不一致リスク（kagemaru発見 — 最重要）

**問題**: 高速版はget_sim_contextが全コンポーネント共通月でmatrixを構築する。逐次版でサブセットのみでalign_monthsすると共通月セットが変わり、md5不一致になる。

**解決**: main()で全コンポーネント共通のcommon_monthsを事前計算し、逐次版にも高速版にも同じ月セットを渡す。これにより同一月セットが保証される。

**教訓**: 逐次版と高速化版で「入力データの前提」を揃えないと出力が一致しない。align_monthsの呼び出し箇所と引数を必ず確認せよ。

### subset cache GS の計測の罠（cmd_1029-1030）
- L364: subset単位キャッシュを持つGSはランダムpat単価で全量時間を外挿するな。grouped/random比=0.05-0.07で4-20x過大評価になりうる
- L365: チャンクプロトタイプの計測値を全量見積りに使うな。プロトタイプ0.490ms/pat vs AC3ベンチマーク4.936ms/pat(10倍差)
- L367: 月次解像度重複パターン10D/15D/20D/1Mは数学的同一。kasoku30.7%,oikaze16.7%,kawarimi16.0%が重複（cmd_1030。L371はL367に統合）

### PPE/profiler計測の罠（cmd_1033-1037）
- L379: PPE異常診断ではfull-script benchmarkとcore _run_mp計測を分離すべし。data load/preflight外オーバーヘッドを分離しないとPPE効率を誤診する（cmd_1033）
- L384: in-loop perf_counter profilerはoverhead+60%(0.178ms vs native 0.111ms/pat)。内訳比率は方向性有用だが絶対値は膨張する。native runtime必須（cmd_1034。L386統合）
- L397: GS忍法ndarray(16KB-750KB)は全てL2/L3内。cache missはボトルネックではない(<5%)。Python interpreter overhead支配。ループ排除が本命（cmd_1037）
- L401: 正確性修正(tiebreak+normalize)は全性能最適化に先行すべき。パリティ基準が不正確だと最適化後の検証自体が無効（cmd_1037）

---

## §5 適用記録サマリ

> 各エントリの詳細(改修内容/ハマりポイント/再現手順/R3-R4実験) → `docs/research/gs-speedup-details.md`

### R2（cmd_161: 高速化移植+mode CSV移行）

| 忍法 | 担当 | パターン | comp | 結果 | fast(s) | seq(s) | 倍率 | 共通月 | 詳細§ |
|------|------|---------|------|------|---------|--------|------|--------|-------|
| bunshin | kagemaru | 781 | 12 | ✅PASS | 0.0 | 1.4 | — | 143 | §1 |
| oikaze v1 | hanzo | 100 | 12 | ⚠️無効 | 0.113 | 0.692 | 6.11x | 143 | §2 |
| oikaze v2 | hanzo | 100 | 8 | ✅PASS | 0.115 | 0.863 | 7.49x | 173 | §3 |
| kawarimi | sasuke | 100 | 8 | ✅PASS | 0.205 | 1.075 | 5.23x | 173 | §4 |
| nukimi | kirimaru | 100 | 8 | ✅PASS | 0.181 | 1.087 | 6.02x | 173 | §7 |
| nukimi_c | hayate | 100 | 8 | ✅PASS | 0.160 | 0.789 | 4.91x | 173 | §9 |
| kasoku | saizo | 100 | 8 | ✅PASS | 0.272 | 1.387 | 5.10x | 173 | §11 |

### R3（cmd_165: precomp picks/vectorization）

| 忍法 | 担当 | パターン | comp | 結果 | fast(s) | baseline(s) | 倍率(vs base) | 有効手法 | 詳細§ |
|------|------|---------|------|------|---------|-------------|--------------|---------|-------|
| bunshin | sasuke | 500 | 12 | ✅PASS | 0.017 | 0.025 | 1.45x | fixed-arity vec | §5 |
| kawarimi | kotaro | 100 | 12 | ✅PASS | 0.037 | 0.206 | 5.54x | precomp picks | §6 |
| nukimi | sasuke | 500 | 12 | ✅PASS | 0.114 | 0.651 | 5.71x | precomp picks | §8 |
| nukimi_c | kirimaru | 500 | 12 | ✅PASS | 0.126 | 0.658 | 5.23x | precomp picks | §10 |
| kasoku | kirimaru | 500 | 12 | ✅PASS | 0.127 | 0.577 | 4.54x | precomp picks | §12 |
| oikaze | kirimaru | 500 | 12 | ✅PASS | 0.093 | 0.123 | 1.32x | precomp picks+common_months | §13 |

### R4（cmd_165: さらなる最適化探索）

| 忍法 | 担当 | パターン | 結果 | fast(s) | R3(s) | 倍率(vs R3) | 有効手法 | 詳細§ |
|------|------|---------|------|---------|-------|------------|---------|-------|
| nukimi | kirimaru | 500 | ✅PASS | 0.053 | 0.114 | 2.15x | R3継承(追加変更なし) | §14 |
| kasoku | sasuke | 500 | ✅PASS | 0.089 | 0.127 | 1.43x | PeriodIndex indexer | §15 |

**R3手法選択の指針（L049）**:
- picks系（Pre-computed picks + 純Python）→ kawarimi, nukimi, kasoku（選出ロジックあり）
- vectorization系（fixed-arity vectorization）→ bunshin（選出ロジックなし、単純平均）
- oikaze: picks系+common_months固定が有効

**R4結論**: multiprocessingは0.05秒級GSで全て逆効果（プロセス生成~50msが支配）

### R5（cmd_1025-1032: 大規模GS高速化+PPE導入）

- L360: 大規模GS(100万超)はチャンク分割+中間CSV保存+忍者並列実行。READ-onlyのためDB排他不要（cmd_1025）
- L363: 大規模GSの対策順位は実測ボトルネック寄与で評価せよ。kasoku支配率90.6%（cmd_1027）
- PPE(ProcessPoolExecutor 6 workers)導入済み（cmd_1031）。Grid dedup差し戻し済み（cmd_1032、PI-001）

- L402: cmd_1029計測値は最適化前基準。cmd_1035以降はcmd_1035値を基準にすべし。kasoku 4.936→0.714、nukimi 1.426→0.440（cmd_1036）

**チャンク分割の基準（殿指示 2026-03-17）**: 1チャンク実行時間 ≤ 5分。分割単位は `(method, subset_id)`。
kasoku ratio/diff は独立実行可能 → 最大分割粒度: method(2) × subset_id(N) のうち5分以内になる組合せ。

| 忍法 | パターン | PPE6 ms/pat | 直列時間 | 5minチャンク数 |
|------|---------|------------|---------|--------------|
| kasoku-ratio | 6,336,648 | 1.89 | 3.3h | 40 |
| kasoku-diff | 6,336,648 | 1.89 | 3.3h | 40 |
| nukimi | 3,230,448 | 0.46 | 24.6min | 5 |
| oikaze | 1,490,976 | 0.48 | 11.9min | 3 |
| kawarimi | 1,490,976 | 1.24 | 30.8min | 7 |
| yotsume | 248,496 | 0.31 | 1.3min | 1 |
| bunshin | 41,416 | 0.14 | ~6s | 1 |

---

## §6 忍法間の差異まとめ

| 項目 | bunshin | oikaze | kawarimi | nukimi | kasoku-ratio | kasoku-diff | yotsume |
|------|---------|--------|----------|--------|-------------|-------------|---------|
| 配分方式 | 均等配分(1/N) | モメンタムtop_n | top_n+bottom_n和集合 | 単一窓(base-skip)top_n | 短期/長期ratio cutoff | 短期-長期diff cutoff | 4視点和集合top_n |
| モメンタム計算 | 不要 | 必要(lookback窓) | 必要(period_months軸) | 必要(base-skip窓) | 必要(長短2窓) | 必要(長短2窓) | 必要(4skip×base窓) |
| パターン数(32体) | 41,416 | 1,490,976 | 1,490,976 | 3,230,448 | 6,336,648 | 6,336,648 | 248,496 |
| ms/pat(grouped) | 0.14 | 1.19 | 1.33 | 1.43 | 4.94 | 4.94 | 0.61 |
| ms/pat(PPE6) | — | 0.48 | 1.24 | 0.46 | 1.89 | 1.89 | 0.31 |
| 直列見込(grouped) | ~6s | 29.5min | 33min | 76.7min | 8.7h | 8.7h | 2.5min |
| 直列見込(PPE6) | ~6s | 11.9min | 30.8min | 24.6min | 3.3h | 3.3h | 1.3min |

### kasoku ratio/diff 2分割の事実（恒久化 2026-03-17 殿指示）

`run_077_kasoku.py` は1本のスクリプトだが、内部で **ratio** と **diff** の2メソッドを直列実行する。
- **ratio**: `score = short_momentum / long_momentum`（倍率）
- **diff**: `score = short_momentum - long_momentum`（差分）
- パターン空間は同一(153ペア × 18 lookback × 18 period × size2-4)だがスコア系列が異なるため**結果は独立**
- 合計 12,673,296 = 6,336,648(ratio) + 6,336,648(diff)
- **並列分割時の最小単位は `(method, subset_id)`** — ratio/diffは独立実行可能

※ nukimi_cはnukimiに統合済み（殿裁定 2026-02-19）。詳細 → `docs/research/gs-speedup-details.md` §16

### 忍法間共有化の影響（cmd_1030）
- L368: 忍法間共有化の性能インパクトはcontext build(0.058%)でなくsimulate_pattern(99.94%)が支配的。共有化の主価値は保守性向上
- L370: momentum計算は通常(oikaze/kasoku/kawarimi: cumret.pct_change)とskip(nukimi/yotsume: cum比率)の2系統に分類可能
- L381: cross-subset momentum共有は理論231x削減でも実時間8.1%のみ(110.4s→101.5s)。picks計算(80.7%)がsubset依存で共有不可（cmd_1034）

---

## §7 更新ルール（殿指示）

1. 毎回のトライ後にこのドキュメントを更新する
2. 省略するな。原文のまま記録
3. 成功も失敗も記録する。失敗は特に重要
4. 各忍者の知見は次の忍者のタスクYAMLに全注入する
5. 1回目の知見→2回目に注入→2回目の知見も追記→3回目に注入→…知識が厚くなる
