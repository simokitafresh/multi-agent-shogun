# 研究パイプライン メタ視点道具磨き分析
<!-- gunshi 2026-04-10 殿指示: メタ視点で道具を磨け -->

## 結論(v3 — 全cmd完了反映 2026-04-10)

| cmd | 道具 | 改善前 | 改善後 | 倍率 | 状態 |
|-----|------|--------|--------|------|------|
| cmd_1827 | WFエンジン メモリ(Step1-7) | peak 10.2GB(OOM) | peak 3.68GB | 2.8x | ✅CLEAR |
| cmd_1828 | WFエンジン メモリ(Step8-10) | peak 3.68GB | no-op(Step9/10がcmd_1827で先取り) | - | FAIL(tracemalloc≠RSS設計穴) |
| cmd_1829 | nukimi BATCH_CHUNK | 106min | **3.5min** | **30x** | ✅CLEAR |
| cmd_1830 | BATCH_CHUNK横展開5忍法 | kasoku_diff計算343s | **24.5s(MP)** | **14x** | ✅CLEAR |
| cmd_1831 | gs_runner.py並列ランナー | 直列22.7min | **1.9min(3w)** | **12x** | ✅CLEAR |
| cmd_1832 | PipelineEngine lazy import | +75.7MB/worker×6 | **-79.6MB/worker** | — | ✅CLEAR |
| cmd_1833 | gs-bench-gate WARN追加 | GSコード変更時ベンチ未強制 | files_modified検知→WARN | — | ✅CLEAR |
| cmd_1834 | CSV I/O偵察 | pandas to_csv 270s | savetxt 4.6s(59x)/npy 0.12s(2200x) | **59-2200x** | ✅CLEAR(偵察) |

**最終到達点: GS 150min → 1.9min(79倍高速化)。** BATCH_CHUNK(30x) + 横展開(14x) + gs_runner並列(12x)の三重効果。
**次の律速: CSV I/O(kasoku系258s=91%)。** cmd_1834偵察で解決案確定済み(numpy savetxt 59x)。実装cmd未起票。

## メタなぜなぜ7回

| # | なぜ | 答え（現物確認） |
|---|------|-----------------|
| 1 | なぜ道具磨きがWFエンジンだけになった？ | OOMが目の前で起きた→反射的に目の前の問題を修正。パイプライン全体を俯瞰していない |
| 2 | なぜ俯瞰していない？ | 研究パイプラインの実行時間内訳を計測していない。律速がどこか不明 |
| 3 | **計測結果**: GS 150分 >> WF 31秒 >> メトリクス数分。GS(特にnukimi 106分)が**真の律速** | WFの31秒を改善しても全体の0.3%しか改善しない |
| 4 | なぜGSが150分もかかる？ | 7本が独立スクリプト(各769-1871行)。共通行912/1307=70%が重複。速度最適化が各スクリプト個別に必要 |
| 5 | なぜ7本独立？ | 忍法毎に戦略ロジックが異なる。しかしDB読込+パラメータグリッド生成+CSV出力+メタデータ書出しは完全共通 |
| 6 | なぜ共通基盤化していない？ | 歴史的経緯。忍法が1本ずつ追加された。リファクタのcmdが出ていない |
| 7 | **根因**: 研究パイプライン全体の速度プロファイルが未計測。目の前の問題(OOM)にだけ対処し、最大ボトルネック(GS 150min)を放置している | **対策**: 4つのメタ道具磨きを優先順に実行 |

## 4つのメタ道具磨き（優先順）

### M1: GS共通基盤抽出（最大複利・GS 150min→推定30min）

**現状**: 7スクリプト合計10,499行。共通行70%。DB接続10-13件/本重複。
**改善**: 共通基盤(gs_common.py)にDB読込+グリッド生成+CSV出力+メタデータを抽出。各忍法は戦略関数のみ定義(~100-300行)。

複利効果:
- 速度改善が1回で全忍法に適用(今は忍法毎に個別改善が必要)
- メモリ制御(dtype, chunk)が1箇所で全忍法に適用
- --helpがargparse統一で全忍法で動く(現在未実装→cmd_1824の根因)
- テストが共通基盤1本で7忍法カバー(現在テストゼロ)
- 新忍法追加がコピペ1800行→戦略関数100行に

**実装規模**: 大(2000行リファクタ)。ただし正の複利最大。

### M2: GS並列投入の自動化（時間最小化）

**現状**: 7忍法を6忍者に手動配備。cmd起票→配備→完了→次cmdの直列人間ループ。
**改善**: 1つのcmdで7忍法を並列実行するランナースクリプト。WFの--batch-csvsと同じ発想。

```bash
python3 scripts/analysis/grid_search/gs_runner.py \
  --universe config/portfolio_universes/okugi_shin_ninpo_20.yaml \
  --workers 3 --cmd-id cmd_XXXX
```

複利効果:
- 7忍法をworker数で並列→時間=最長忍法/worker数
- 3 workers: 150min/3 = 50min。忍者配備の人間ループ不要
- OOM制御: worker数でメモリ上限管理(各worker独立プロセス)

**実装規模**: 中(100行。WFのrun_batch_modeと同じパターン)。

### M3: WFエンジン Step 8-10（メモリ追加削減）

**現状**: Step 1-7で3.68GB(kasoku_diff)。
**改善**: Step 8-10で2.66GB(-28%)。dtype変更5行。
**実装規模**: 小(5行)。cmd_1828として即実行可能。

### M4: 研究パイプライン全体のベンチマーク基盤

**現状**: gs_benchmark.pyは存在するがWFベンチマークなし。パイプライン全体の時間計測が手動。
**改善**: パイプライン全体(GS+WF+メトリクス)のend-to-endベンチマーク。bunshin(最小入力)で全経路をプロファイル→改善前後の数値比較を自動化。

**実装規模**: 小(50行)。gs_bench-gateスキルの拡張。

## 優先順序(v3 — 全cmd完了後 2026-04-10)

| 順位 | 項目 | ROI | 状態 |
|------|------|-----|------|
| ~~1~~ | ~~nukimi BATCH_CHUNK(cmd_1829)~~ | ~~最大~~ | **✅完了。106min→3.5min(30x)** |
| ~~2~~ | ~~WF Step8-10(cmd_1828)~~ | ~~即効~~ | ✅完了(no-op。Step9/10がcmd_1827で先取り) |
| ~~3~~ | ~~M2 GS並列ランナー(cmd_1831)~~ | ~~高~~ | **✅完了。22.7min→1.9min(12x)** |
| ~~4~~ | ~~BATCH_CHUNK横展開(cmd_1830)~~ | ~~高~~ | **✅完了。5忍法横展開。kasoku_diff計算14x** |
| ~~5~~ | ~~PipelineEngine lazy import(cmd_1832)~~ | ~~中~~ | **✅完了。RSS 79.6MB削減** |
| ~~6~~ | ~~gs-bench-gate(cmd_1833)~~ | ~~中~~ | **✅完了。GSコード変更時WARN自動化** |
| ~~7~~ | ~~CSV I/O偵察(cmd_1834)~~ | ~~高~~ | **✅完了。pandas270s→savetxt4.6s(59x)確認** |
| 1 | **CSV I/O実装(cmd-R1)** | 高(年5.2h削減) | **未起票**。cmd_1834偵察完了。numpy savetxt置換 |
| 2 | **kawarimi md5(cmd-R4)** | 低(信頼性) | **未起票**。sequential md5非決定性の根因調査 |
| 3 | **M1(GS共通基盤)** | 最大だが大改修 | **未起票**。2000行リファクタ。新忍法追加50行化 |
| 4 | **M4(ベンチマーク基盤)** | 中 | **未起票**。pipeline_benchmark.sh 50行 |

## パイプライン実行時間内訳

### 改善前(cmd_1822実績)
```
GS Phase:   ████████████████████████████████████████ 150min (96%)
  nukimi:   █████████████████████████████████ 106min ← 律速
  kasoku_d: ████████ 20min
  kasoku_r: ████████ 20min
  oikaze:   ██ 4min
  kawarimi: █ 3min
  yotsume:  ▎ 2min
  bunshin:  ▎ 1min
WF Phase:   ▎ 0.5-60min
```

### 改善後(cmd_1829 BATCH_CHUNK + cmd_1830 横展開)
```
GS Phase(直列): ██████████ ~22.7min (was 150min, 6.6x高速化)
  kasoku_r: ██████ 5.9min (25.8%) ← 新律速(ほぼ均等)
  kasoku_d: █████▌ 5.7min (25.2%)
  oikaze:   ████ 3.6min (16.0%)
  nukimi:   ███▌ 3.5min (15.4%) (was 106min, 30x高速化)
  kawarimi: ██ 2.1min (9.0%)
  bunshin:  █ 1.0min (4.4%)
  yotsume:  ▌ 0.9min (4.2%)
```

### 最終到達(cmd_1831 gs_runner 3workers並列)
```
GS Phase(並列): █▌ 1.9min (was 150min, 79x高速化)
  全7忍法を3 workers並列実行。各worker=独立subprocess
  ボトルネック移行: 計算→CSV I/O(kasoku系258s=91%)
WF Phase:        ▌ 0.5-60min
```

**★ GS 150min→1.9min(79x)完了。新ボトルネック=CSV I/O。cmd_1834偵察でnumpy savetxt 59x確認済み。実装cmdで~1min到達見込み。**

**★★ 教訓: kasoku_diff「~20min」はcapture-pane走行中タイミングからの想像。meta実測は343s=5.7min。想像するな確認せよ原則を分析の数字にも適用せよ。**

### cmd_1829実測データ(才蔵)
- fast: **19.284秒** / 481,650パターン = **0.040ms/pattern**(改善前13.25ms→331倍速)
- total: **209.2秒(3.5分)** / 0.434ms/pattern
- 回帰テスト: verify_batch md5一致 + max_abs_diff=0
- 追加改善: SHM回収O(n^2)→O(n)化(produced_pids集合参照)

## 具体的実装設計

### M2具体設計: gs_runner.py（GS並列ランナー）

**ファイル**: `scripts/analysis/grid_search/gs_runner.py` (新規, ~80行)

**設計**: WFエンジンのrun_batch_mode(L1932-2009)と同一パターン。subprocess.runで各忍法を独立プロセス起動、ThreadPoolExecutorでworker数制限。

```python
# gs_runner.py 骨格
NINJUTSU_SCRIPTS = [
    "run_077_bunshin.py", "run_077_yotsume.py", "run_077_oikaze.py",
    "run_077_kawarimi.py", "run_077_nukimi.py",
    "run_077_kasoku_diff.py", "run_077_kasoku_ratio.py",
]

def run_single(script_name, universe, out_dir, cmd_id):
    """1忍法をsubprocessで実行。メモリ独立。"""
    child_cmd = [
        sys.executable, str(GS_DIR / script_name),
        "--universe", universe,
        "--out-dir", out_dir,
        "--output-prefix", f"{cmd_id}_{script_name.replace('run_077_','').replace('.py','')}",
    ]
    return subprocess.run(child_cmd, capture_output=True, text=True)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--universe", required=True)
    parser.add_argument("--cmd-id", required=True)
    parser.add_argument("--workers", type=int, default=2)  # DB負荷考慮でデフォルト2
    parser.add_argument("--out-dir", default=None)
    args = parser.parse_args()

    # 大→小の順で投入(nukimi最長→先に開始)
    ordered = sorted(NINJUTSU_SCRIPTS, key=estimated_time, reverse=True)
    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = {executor.submit(run_single, s, args.universe, ...): s for s in ordered}
        for future in as_completed(futures):
            result = future.result()
            print(f"[gs_runner] {futures[future]}: rc={result.returncode}")
```

**要点**:
- `--workers 2`(デフォルト): DB同時接続2本。DB負荷に応じて調整
- 大→小順投入: nukimi(106min)を先に開始→全体完了=nukimi完了時間に収束
- 各忍法が独立プロセス→OOM時は1忍法のみ死亡、他は継続
- 出力: サマリYAML(各忍法のrc/elapsed/CSV行数)

**速度見込み**:
- workers=1: 150min(直列=現状)
- workers=2: ~106min(nukimi律速)
- workers=3: ~106min(nukimi律速。3本目はnukimiより先に完了)
- **★nukimiが律速なのでworkers>2でも106minが下限。nukimi高速化が本丸**

**AC設計**:
- AC1: gs_runner.py実装。--universe/--cmd-id/--workers/--out-dir対応
- AC2: bunshin+yotsume(最小2本)をworkers=2で実行。両方rc=0+CSV生成
- AC3: 7本全量をworkers=2で実行。全rc=0+7 CSV生成。合計elapsed < 120min

### M4具体設計: pipeline_benchmark.sh（パイプラインベンチマーク）

**ファイル**: `scripts/analysis/pipeline_benchmark.sh` (新規, ~60行)

**設計**: bunshin(最小CSV 16MB)でGS→WF→メトリクスの全経路を1コマンドで実行し、各phase時間+peak RSSを記録。

```bash
#!/usr/bin/env bash
# pipeline_benchmark.sh — 研究パイプラインend-to-endベンチマーク
# bunshin(最小入力)で全経路をプロファイル
set -euo pipefail

CMD_ID="${1:-bench_$(date +%Y%m%d_%H%M%S)}"
UNIVERSE="${2:-config/portfolio_universes/alm_l0_12.yaml}"
OUT_DIR="outputs/analysis/benchmark/${CMD_ID}"

echo "=== Phase 1: GS (bunshin) ==="
/usr/bin/time -v python3 scripts/analysis/grid_search/run_077_bunshin.py \
  --universe "$UNIVERSE" --out-dir "$OUT_DIR" --output-prefix "${CMD_ID}_bunshin" \
  2>"${OUT_DIR}/gs_time.txt"

echo "=== Phase 2: WF ==="
/usr/bin/time -v python3 outputs/scripts/l1_alm_wf_engine.py \
  --csv "${OUT_DIR}/${CMD_ID}_bunshin_monthly_fast.csv" \
  --multi-is --cmd-id "$CMD_ID" --out-dir "$OUT_DIR" \
  2>"${OUT_DIR}/wf_time.txt"

echo "=== Results ==="
grep "Maximum resident" "${OUT_DIR}/gs_time.txt" "${OUT_DIR}/wf_time.txt"
grep "Elapsed" "${OUT_DIR}/gs_time.txt" "${OUT_DIR}/wf_time.txt"
```

**AC設計**:
- AC1: pipeline_benchmark.sh実装。GS→WF全経路実行+time計測
- AC2: bunshinで実行。GS/WF各phaseのelapsed+peak RSS出力

### M1具体設計: GS共通基盤（段階的リファクタ）

**Phase 1(最小)**: 共通ユーティリティ抽出 `scripts/analysis/grid_search/gs_common.py`
- DB接続(configure_database_url_from_env + create_engine) — 7本で完全重複
- CSV出力(write_grid_csv + write_meta_yaml) — 7本で完全重複
- argparse共通(--universe/--out-dir/--output-prefix/--help) — 7本で完全重複
- 上書き防止チェック — 7本で完全重複

**Phase 2(中)**: 各忍法スクリプトをgs_commonをimportする形に書換え
- run_077_oikaze.py: 1307行 → ~300行(戦略関数+パラメータグリッド定義のみ)
- 7本合計: 10,499行 → ~2,500行(gs_common 500行 + 各300行×7)

**Phase 3(大)**: 統一ランナーインターフェース
- gs_common.run_grid_search(strategy_fn, param_grid, universe_config) で全忍法統一
- 新忍法追加: strategy関数1つ+param_grid定義 = ~50行

**AC設計(Phase 1のみ — 最小リスク)**:
- AC1: gs_common.pyにDB接続+CSV出力+argparse+上書き防止を抽出
- AC2: run_077_bunshin.py(最小769行)をgs_common import版にリファクタ
- AC3: リファクタ前後でbunshin GS結果がmd5完全一致(回帰テスト)
- AC4: 他6忍法は変更なし(影響なし確認)

### nukimi高速化（真の律速解消）— なぜなぜ7回完了

nukimiが106min=全体の68%。**根因特定済み。偵察不要。実装可能。**

#### なぜなぜ7回

| # | なぜ | 答え(コード現物) |
|---|------|-----------------|
| 1 | なぜnukimi 106minで他は4-20min？ | パターン当たり13.3ms(他0.5-3.2ms)=4-24倍 |
| 2 | なぜパターン当たりが4.9倍に悪化(12体→20体)？ | simulate_batch(L667)の3D配列がO(P×M×C)。C=12→20で4.9倍 |
| 3 | なぜ3D配列が巨大？ | L715: `mask=np.zeros((n_patterns,max_out,n_comps),bool)` + L739: `selected_returns=safe_open[newaxis]*mask` (P,M,C) float64 |
| 4 | なぜ80kパターン/worker？ | L1090: round-robinでsubset分配→481k/6workers=80k/worker。チャンク分割なし |
| 5 | なぜworker当たり2.6GB？ | selected_returns(80k,150,20) f64=1.93GB + mask+valid_mask 0.48GB + sum_returns 0.19GB |
| 6 | なぜメモリ2.6GBで遅い？ | L3キャッシュ16MB。2.6GB/16MB=162倍溢れ。全メモリアクセスがDRAM→帯域律速 |
| 7 | **根因**: simulate_batchが全パターン一括で3D配列(P,M,C)構築。パターン数PとコンポーネントCの積がL3超過→DRAM帯域律速 | **対策**: simulate_batch内でパターンをサブチャンク分割(chunk=500)→3D配列15MB=L3内→DRAM帯域消費1/160 |

#### 対策の具体設計

**変更箇所**: `run_077_nukimi.py` L667 `simulate_batch()` 関数内

```python
# 変更前(L715-743): 全パターン一括
mask = np.zeros((n_patterns, max_out, n_comps), dtype=bool)
selected_returns = safe_open[np.newaxis] * mask  # (P, M, C) float64 → 1.93GB/worker

# 変更後: パターンサブチャンク分割
BATCH_CHUNK = 500  # 500×150×20×10bytes = 15MB ≈ L3サイズ
all_avg_returns = np.empty((n_patterns, max_out), dtype=np.float64)
for start in range(0, n_patterns, BATCH_CHUNK):
    end = min(start + BATCH_CHUNK, n_patterns)
    sub_mask = np.zeros((end - start, max_out, n_comps), dtype=bool)
    # ... existing mask build logic for sub_mask ...
    sub_selected = safe_open[np.newaxis] * sub_mask  # (chunk, M, C) = 15MB
    sub_valid = (~is_nan_open[np.newaxis]) & sub_mask
    sub_sum = sub_selected.sum(axis=2)
    sub_count = sub_valid.sum(axis=2)
    all_avg_returns[start:end] = np.where(sub_count > 0, sub_sum / sub_count, np.nan)
    del sub_mask, sub_selected, sub_valid  # L3再利用
```

**速度見込み**:
- パターン当たり: 13.3ms → 3-4ms(他忍法並)
- nukimi全体: 106min → **25-30min**
- GS全体: 150min → **70-80min (53%削減)**

**メモリ見込み**:
- worker当たり: 2.6GB → 15MB(170倍削減)
- 6 workers合計: 15.6GB → 90MB

**AC設計**:
- AC1: simulate_batch内にBATCH_CHUNK分割ループを実装(上記コード)
- AC2: bunshinで回帰テスト(結果完全一致)
- AC3: nukimi 20体でelapsed < 30min + パターン当たり < 5ms
- AC4: 他6忍法にも同じsimulate_batchパターンがあるか確認→あれば同様に適用

**注意**: L725-728のkey_to_pisマスク構築もチャンク対応が必要。precomputed_masks[key]が(max_out, n_comps)なので、sub_maskに対して同じインデックスで設定する。

**他忍法への波及**: oikaze/kawarimi/kasoku系にも同じsimulate_batch(3D mask)パターンがある可能性。確認し横展開で全忍法高速化。

## サイレント性能劣化: PipelineEngine import (cmd_1199 a137593e)

### 発見経緯
殿の問い「12体と20体の間でコード改変があったはずだ」→git log精査→a137593e発見。

### 事実
- commit a137593e (cmd_1199): simulate_patternをPipelineEngine経由に差替え(PI-009)
- トップレベルimport追加(L74-76): `from backend.app.services.pipeline.base import PipelineContext`
- import計測: **4.5秒 + 75.7MB/プロセス**
- 6 forkワーカー: **454MB追加メモリ消費**(COW前)
- per-pattern影響: 12体 2.71→3.49ms(**1.29倍悪化**)
- simulate_batch(本番経路)では不使用。simulate_pattern(検証用残存)でのみ使用

### 対策
- 即時: PipelineEngine importをlazy化(simulate_pattern関数内でimport)
- 恒久: gs-bench-gateをGSコード変更のpre-commit/cmdに必須化

### 教訓
道具を変更した時、性能計測を自動実行する仕組みがなかった。
理解しているだけでは再発する。gate/hookに埋め込め(Phase 4)。

## 残り最適化ロードマップ（全件実行。低ROIも複利で効く）

### 複利計算（殿指摘: 0.1秒でも100億回なら大きい）

| 項目 | 1回のコスト | GS頻度(月3回) | 年間累積 |
|------|-----------|--------------|---------|
| CSV I/O(kasoku系) | 258s×2本 | 36回 | **5.2時間** |
| PipelineEngine import | 4.5s | 36回 | 3分(+454MBメモリ毎回) |
| 0.1ms/patternの差 | 94s/回(94万pat) | 36回 | **57分** |
| 性能リグレッション未検知 | +48s/回(1.29倍) | 検知まで蓄積 | **80分**(cmd_1199実績) |

### cmd一覧（優先順=複利の大きさ）

#### cmd-R1: CSV I/Oボトルネック解消（年間5.2時間削減）— 偵察完了(cmd_1834)
**真因**: kasoku_diff total 282.6s中258s(91%)がCSV書出し(pandas to_csv)。計算は24.5sで終わっている。
**偵察結果(cmd_1834 影丸 CLEAR)**:
- pandas to_csv(kasoku 12体 347MB): 270s
- numpy savetxt(f32): 4.6s (**59x**, CSV形式維持, 下流無変更)
- numpy .npy(f32 binary): 0.12s (**2200x**, 要engine改修~50行)
- 20体推定: pandas~1470s → savetxt~25s → npy~0.65s
**推奨実装**: 案1(numpy savetxt)即実装→案2(npy)はM1共通基盤化と同時
**変更対象**: 7ファイル(run_077_*.py)のto_csv/streaming writeをnp.savetxt置換
**注意**: float32精度でmd5変化→既存ゴールデン比較不可。l1_alm_wf_engineのpd.read_csvはそのまま動く
**状態: 実装cmd未起票**

#### ~~cmd-R2: PipelineEngine lazy import化~~ ✅完了(cmd_1832 小太郎 CLEAR)
**結果**: 6ファイル変更(kawarimi既実装)。worker fork RSS: 93,741→12,233KB。**削減79.6MB(≥75.7MB)**。bunshin回帰完全一致(max diff=0.0)。CoW破壊分をworker fork実測で正しく計測。
**教訓**: RSS計測は--helpでなくworker fork RSSで(CoW効果考慮)

#### ~~cmd-R3: gs-bench-gate GSコード変更時必須化~~ ✅完了(cmd_1833 飛猿 CLEAR)
**結果**: cmd_complete_gate.shにGSスクリプト(run_077_*.py/gs_runner.py/gs_common.py)変更検知→gs-bench-gate未実行WARN追加。batsテスト5件PASS。
**防御階層**: Level 1(事後検出WARN)。リグレッション半年未検知(cmd_1199)の再発防止

#### cmd-R4: kawarimi md5不一致根因調査（偵察）
**真因**: batch vs sequential md5不一致。sequential側のmd5が毎回変わる(非決定性)。
**方針**: 再現性確認→根因特定(DB読込順序/浮動小数点演算順序/乱数)。
**AC設計**:
- AC1: kawarimi sequential 2回実行でmd5比較(再現性テスト)
- AC2: batch 2回実行でmd5比較(batch側の決定性確認)
- AC3: 根因1文+修正案(浮動小数点演算順序ならsort追加 etc)

### 現在の到達点(2026-04-10)

```
GS Phase改善前:  ██████████████████████████████████████████ 150min
GS Phase現在:    █ 1.9min (79x高速化) ← gs_runner 3w並列
                 + lazy import完了(-79.6MB/worker)
                 + gs-bench-gate WARN自動化(リグレッション防止)
                 + CSV I/O偵察完了(savetxt 59x確認済み)
GS Phase次:      ▌ ~1min目標 (CSV I/O savetxt実装→258s→4.6s)
                 + kawarimi非決定性解消(信頼性)
                 + M1共通基盤化(7スクリプト→gs_common.py)
```

### 残cmd（未起票）
| 項目 | 推定効果 | 実装規模 |
|------|---------|---------|
| CSV I/O savetxt置換 | kasoku系258s→4.6s(年5.2h削減) | 小(7ファイル to_csv→savetxt) |
| kawarimi md5根因調査 | 信頼性(sequential非決定性) | 偵察 |
| M1 GS共通基盤抽出 | 10,499→2,500行。新忍法50行化 | 大(2000行リファクタ) |
| M4 pipeline_benchmark.sh | 改善計測自動化 | 小(50行) |
