# cmd_3797: GS再キャリブレーション計画 Phase A再実行 — L0四神全量GS(バンド込み・同期済みprices)+新旧チャンピオン比較

- 親cmd: cmd_3797 | 実行者: tobisaru | 実行日: 2026-07-09
- 設計書: `docs/research/l0-3objective-newold-comparison-design.md` v1.1 §2
- 再実行理由: cmd_3762/3763(2026-07-08)のPhase A初回実行は、GS専用ローカルEODHDスナップショットで行われ本番PostgreSQL pricesとパリティが取れていないことがcmd_3785で判明(殿裁定2026-07-09 13:40「違う株価データで行ったGSは全て無効」)。cmd_3793(D1)でGS入力price DB(`analysis_runs/experiments.db`)を本番と再同期したため、本cmdでPhase Aを同期済みpricesにより再実行する。

## §1 前提確認(AC1前半)

`scripts/analysis/grid_search/gs_price_preflight.py` (デフォルト`analysis_runs/experiments.db`, 14銘柄):

```
PASS: 14/14 tickers match production prices
```

全14ティッカーで `missing_in_local=0` `missing_in_prod=0` `close_mismatches=0` `open_mismatches=0`。D1(cmd_3793)の同期が本cmd実行時点でも維持されていることを確認した。

## §2 L0四神全量GS実行(AC1後半)

```
.venv/bin/python scripts/analysis/grid_search/shin_shijin_l1_gs.py \
  --threshold-band 0.005 --price-db analysis_runs/experiments.db --skip-parity
```

- 空間: 191,796パターン(DM2=76,680 / DM3=38,340 / DM6=76,680 / DM7+=96)。前回(cmd_3762)と完全同一、縮小なし
- 実測: wall clock 4:26(266s)、RSS最大1.53GB、exit 0。E7ベンチマーク実測(246s)と同水準
- 出力: `outputs/grid_search/20260709/L0/shin/{gs_DM2,gs_DM3,gs_DM6,gs_DM7P}.db` + `meta.yaml`

```
$ ls -l outputs/grid_search/20260709/L0/shin/
-rwxrwxrwx 1408565248 gs_DM2.db
-rwxrwxrwx  697565184 gs_DM3.db
-rwxrwxrwx 1407254528 gs_DM6.db
-rwxrwxrwx    2490368 gs_DM7P.db
-rwxrwxrwx        2659 meta.yaml
```

### §2.1 `--skip-parity`を用いた理由(重要な副次発見)

`--skip-parity`を付けずに初回実行したところ、スクリプト内蔵の本番PF現物パリティ検証(`run_parity_check`、cmd_1018由来のAC1)がDM2で失敗した(`ValueError: parity failed for DM2: 10 mismatches (first 2015-08 diff=0.112921)`)。

調査の結果、これは**この検証経路(`simulate_strategy_vectorized`のpipeline_config直読パス)がcmd_3755で追加されたthreshold_band三状態ゲートに未対応の既存(legacy)チェックである**ことが判明した:

1. 本番DM2の`pipeline_config`には既に`threshold_band: 0.005`が設定済み(工程1=cmd_3771で2026-07-08にバンド適用済みの24PFの1つ)。`db-check`スキル経由でread-only確認済み。
2. threshold_bandロジックの正規実装(`shin_shijin_l1_gs.py`の`simulate_phase2_batch()`、cmd_3755導入)は、専用パリティツール`verify_gs_band_parity_pi009.py`で**本cmd実行と同日(2026-07-09)にD1同期済みpricesを用いて再検証済み**(cmd_3794「D3出力パリティ再検証」)であり、**DM2は7PF中の1つとして max_abs_diff=0.00e+00 で完全一致(PASS)**。
3. cmd_3762(前回のPhase A実行、20260708)も同じ理由で`--skip-parity`を使用していた(`meta.yaml: parity: skipped: true`)ことを確認済み。前例と整合。
4. 既知の未解決差異(DM-safe/DM-safe-2の2009-05、top_n=2のband境界マルチアセット重み配分ロジック差、cmd_3772/cmd_3794で根本原因まで特定済み)は、DM2/DM3/DM6/DM7+(本cmdの対象4系統)には該当しない。

結論: **`run_parity_check`はthreshold_band対応前のlegacyチェックであり、本cmdのGS計算経路(`simulate_phase2_batch`)の正確性は既に別の専用ツールで検証済み**。`--skip-parity`の使用は前例踏襲かつ根拠ありと判断した。今回新たに確認できた事実として「同チェックは本番PFにthreshold_bandが設定されると必ず(DM2のような2資産/top_n=1の単純な系統でも)mismatchを出す」という点をlesson化する(§5)。

## §3 チャンピオン選出(Step 2)

`scripts/oneshot/cmd_3797_shin_14metrics.py`(14指標算出、cmd_3762と同一定義・関数を再利用)→`scripts/oneshot/cmd_3797_champion_selection.py`(選出、cmd_3756のロジックを再利用)。

- 14指標CSV: `outputs/analysis/cmd_3797_shin_all_patterns_14metrics.csv`(191,796行、`rolling_1y_low`欠損0件)
- 選出結果: `outputs/analysis/cmd_3797_champion_selection.csv`(24行=4DM系×3モード×2基準)
- サマリ: `outputs/analysis/cmd_3797_champion_selection_summary.md`

| 基準 | 対象指標(4DM系×3モード=12体) |
|------|------------------------------|
| 旧(A_current) | CAGR(激攻) / MaxDD(鉄壁) / NHF(常勝) — 現行本番と同じ基準 |
| 新(B_worstyr_avguwp) | CAGR(激攻) / WorstYear(不倒) / AvgUWP(不沈) — cmd_3716推薦・PD-060確定名 |

CAGRチャンピオン(激攻)は両基準共通のため実差分は4DM系×2モード=8体。

## §4 新旧比較(Step 3, C1-C4)

`scripts/oneshot/cmd_3797_comparison_c1_c4.py`(cmd_3763のロジックを再利用)。出力: `outputs/analysis/cmd_3797_c1_c4_results.json` + `cmd_3797_c2_correlation.csv` / `cmd_3797_c3_fof_metrics.csv` / `cmd_3797_c3_fof_correlation.csv` / `cmd_3797_c4_param_distance.csv`。

### C1: 単体品質 — 新基準は対象指標を8スロット中6で改善

| 四神 | 指標 | 旧(A_current) | 新(B_worstyr_avguwp) | 差分 |
|---|---|---:|---:|---:|
| 青龍 | worst_year_return(鉄壁→不倒) | -0.2181 | -0.0697 | **+0.1485** |
| 朱雀 | worst_year_return | -0.1457 | -0.0303 | **+0.1154** |
| 白虎 | worst_year_return | -0.1070 | +0.0057 | **+0.1126** |
| 玄武 | worst_year_return | -0.0637 | -0.0637 | ±0.0000(近似パターン、下記C4参照) |
| 青龍 | avg_uwp(常勝→不沈、月) | 3.4706 | 2.9615 | **-0.5090(短縮)** |
| 朱雀 | avg_uwp | 3.8462 | 3.8462 | ±0.0000(C4: 同一パターン選出) |
| 白虎 | avg_uwp | 3.3056 | 2.8214 | **-0.4841(短縮)** |
| 玄武 | avg_uwp | 4.2414 | 3.8529 | **-0.3884(短縮)** |

対象指標そのものの改善は6/8スロットで明確。残り2スロット(玄武worst_year・朱雀avg_uwp)はC4で確認の通り旧新がほぼ同一パターンを選出したための実質タイ。

非CAGR体のCAGR percentile(単体としての激攻からの見劣り)は旧新で大差なし(旧48-100th、新37-100th)。ただし白虎(DM6)は旧鉄壁(maxdd champion)がcagr_percentile 100.0thと、旧基準内でも既にCAGR最良に近い値を選んでおり、design書§4-1が指摘した「旧基準の欠陥=MaxDD体の単体品質低下」は本再実行データでは白虎に限り再現しなかった(前回cmd_3762データでは64.7thだった既知チャンピオンの参考値と対照的。GSデータセット自体が価格移行で変わったため、直接比較は不可)。詳細値は`cmd_3797_champion_selection_summary.md`参照。

### C2: 相関構造(月次リターン、選出後PF間)

| 範囲 | 旧(A_current) | 新(B_worstyr_avguwp) |
|---|---:|---:|
| 12体全体・最悪ペア | 0.1238 | **0.1867**(改善) |
| 青龍 内3体・最悪ペア | 0.5418 | 0.7649(悪化) |
| 朱雀 内3体・最悪ペア | 0.7756 | 0.6812(改善) |
| 白虎 内3体・最悪ペア | 0.6180 | 0.7628(悪化) |
| 玄武 内3体・最悪ペア | 0.6617 | 0.6491(ほぼ同水準) |

四神をまたいだ12体全体の分散効果(worst_of_12)は新基準が明確に優位。一方、四神**内**3体間の相関は新基準の方が高いケースが2/4(青龍・白虎)あり、「新基準は四神内の3モードの多様性をやや犠牲にして四神間の分散を改善する」という非対称な効果が見える。設計書§4-1の懸念(「指標相関が低くても選出PF相関は高い可能性」)は四神内相関において部分的に的中。

### C3: 合成FoF比較(四神ごと均等ウェイト月次合成)

| 四神 | 指標 | 旧 | 新 |
|---|---|---:|---:|
| 青龍 | CAGR / MaxDD / WorstYear / AvgUWP | 0.4668 / -0.5171 / -0.0418 / 4.07 | 0.4774 / -0.5990 / -0.0928 / 4.21 |
| 朱雀 | 同上 | 0.3550 / -0.5680 / -0.1292 / 4.95 | 0.3447 / -0.6087 / -0.1222 / 4.17 |
| 白虎 | 同上 | 0.5287 / -0.3441 / -0.0061 / 3.17 | 0.4554 / -0.5212 / -0.1807 / 3.31 |
| 玄武 | 同上 | 0.3694 / -0.3268 / -0.1422 / 3.75 | 0.3663 / -0.3268 / -0.1422 / 3.88 |

四神合成FoF(3体均等ウェイト)としてのMaxDD/WorstYearは、新基準の方が**青龍・朱雀・白虎で悪化**している(個々の不倒/不沈体は単体で改善しても、合成後は旧鉄壁/常勝体の方がドローダウン耐性が高い)。個体最適化(C1)と合成後パフォーマンス(C3)で結論が逆転する四神があることは、L1-L3合成方式(等ウェイム/月次リバランス)次第で新基準の優位性が消える可能性を示す重要な非対称性。四神間相関(worst_of_4)は新基準がやや優位(0.2467→0.3212)。

### C4: 顔ぶれ差分

- 重複率: 旧新24行中`pattern_id`ベースoverlap=5(うちCAGR共通4 + 非CAGR重複1 [朱雀-常勝/不沈が同一パターン]) / Jaccard=0.2632
- 非CAGR8スロット中、同一パターン選出は2件(朱雀常勝→不沈、玄武激攻は対象外・鉄壁→不倒は別パターンだがlookback構成同一で速度差のみ)
- lookback加重平均日数の変化幅(weighted_avg_days_distance)は13.2日(白虎-常勝→不沈)〜337.9日(朱雀-鉄壁→不倒)まで四神ごとに大きくばらつく。詳細 → `outputs/analysis/cmd_3797_c4_param_distance.csv`

## §5 教訓・波及メモ

- **L(new): legacyパリティ(`run_parity_check`/cmd_1018)はthreshold_band非対応**。本番PFにbandが設定されると(工程1完了後は必ず)このチェックはFAILする。今後この経路を使う調査は`--skip-parity`必須、代わりに`verify_gs_band_parity_pi009.py`(PI-009)でGS計算経路の正確性を確認せよ。→ `context/dm-signal.md`へ還流
- 前回(cmd_3762/3763)のPhase A結論(C1-C4の定性的傾向)は、本再実行でも**大枠は再現**(新基準は個体の対象指標を改善、四神間相関は改善するが四神内相関は一部悪化、合成FoF後の優劣は四神により逆転しうる)。ただし価格が変わったため個々の数値(cagr/maxdd等)は前回と単純比較不可。
- 現行本番12チャンピオンのlookbackパラメータ空間差(trading_days複数項加重)は標準カタログと不一致のため、価格・バンド変更影響とパラメータ空間差分は分離不能——この結論(cmd_3762_prod_champion_percentile_note.md)は変わらず有効(パラメータ構造自体の議論であり価格に依存しない)。

## §6 未実施・スコープ外

- 「現行本番チャンピオンパラメータが新GS空間のどの順位に落ちるか」の再計算(§5参照、前回結論を流用・再実行不要と判断)
- L1-L3への基準採用の最終裁定(本cmdは比較材料の提供のみ。設計書§2 Step 4は殿裁定待ち)
- 本番PFへの反映(Phase A自体が「本実験はローカル完結で本番PFに触れない」設計のため対象外)

## 因果リンク

- [[cmd_3785_gs_price_parity_invalid]] -> [[殿裁定20260709_1340_全ロールバック]] -> [[cmd_3797_phase_a再実行]]
- [[cmd_3793_d1_price_sync]] -> [[cmd_3797_gs_price_preflight_pass]]
- [[cmd_3755_threshold_band_vectorized]] -> [[cmd_3772_dtb3_calendar_root_cause]] -> [[cmd_3794_d3_pi009_recheck]] -> [[cmd_3797_skip_legacy_parity_decision]]
- [[l0-3objective-newold-comparison-design_v1.1]] -> [[cmd_3797_c1_c4再実行]] -> [[L1-L3基準裁定]]
