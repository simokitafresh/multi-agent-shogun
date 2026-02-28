# GS高速化×完全一致 — 知見集約ドキュメント（索引）
<!-- last_updated: 2026-02-26 -->
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

---

## §6 忍法間の差異まとめ

| 項目 | bunshin | oikaze | kawarimi | nukimi | kasoku |
|------|---------|--------|----------|--------|--------|
| 配分方式 | 均等配分(1/N) | モメンタムtop_n | top_n+bottom_n和集合 | 単一窓(base-skip)top_n | 加速度cutoff |
| モメンタム計算 | 不要 | 必要(lookback窓) | 必要(period_months軸) | 必要(base-skip窓) | 必要(長短2窓+ratio) |
| 月次リターン長 | 全月固定 | 可変→固定NaN埋め | 可変→固定NaN埋め | 可変→固定NaN埋め | 可変→固定NaN埋め |
| tie-breaking | なし | あり(top_n) | あり(top_n+bottom_n各別) | あり(top_n) | あり(cutoff閾値全選出) |
| 固有要素 | なし | lookback窓,加重平均 | bottom_n,候補不足時前回維持 | skip_months処理 | ゼロ除算保護,閾値全選出 |
| 最速記録(C12/500) | 0.017s | 0.093s | 0.037s | 0.053s(R4) | 0.089s(R4) |
| 対逐次版倍率 | 60.28x | 54.23x | 24.59x | 82.4x(R4) | 61.5x(R4) |

※ nukimi_cはnukimiに統合済み（殿裁定 2026-02-19）。詳細 → `docs/research/gs-speedup-details.md` §16

---

## §7 更新ルール（殿指示）

1. 毎回のトライ後にこのドキュメントを更新する
2. 省略するな。原文のまま記録
3. 成功も失敗も記録する。失敗は特に重要
4. 各忍者の知見は次の忍者のタスクYAMLに全注入する
5. 1回目の知見→2回目に注入→2回目の知見も追記→3回目に注入→…知識が厚くなる
