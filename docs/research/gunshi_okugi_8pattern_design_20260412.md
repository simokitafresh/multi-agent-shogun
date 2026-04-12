# L2奥義8パターン — 設計書+ランブック
<!-- gunshi 2026-04-12 v4 -->

## 8パターン全体像

L2奥義 = L1チャンピオンをBBとした2層目FoF。2軸(BB方式×選出方式)の2×2 = 4組合せ × 2(L1素材=シンorALM) = **8パターン**。

### 2×2マトリクス

|  | L2選出=**シン**(事後GS固定) | L2選出=**ALM**(WF動的) |
|--|---------------------------|----------------------|
| **BB=シン忍法** | ①奥義シンシン | ②奥義シンALM |
| **BB=ALM忍法** | (③⑤⑦で3パターン) | (④⑥⑧で3パターン) |

BB=ALM忍法はL1素材が3種あるため展開:

| # | パターン名 | BB(L1素材) | L2選出 | L1素材cmd | GS CSV入力 |
|---|----------|-----------|-------|----------|-----------|
| ① | 奥義シンシン | シン忍法20体 | 事後(champion_selector) | cmd_1186系 | okugi_shin_ninpo_20body/ |
| ② | 奥義シンALM | シン忍法20体 | WF(l1_alm_wf_engine) | cmd_1186系 | okugi_shin_ninpo_20body/ |
| ③ | 奥義シンALM×シン | シン忍法→ALM WF選出 | 事後 | cmd_1867 | okugi_shin_alm/ |
| ④ | 奥義シンALM×ALM | シン忍法→ALM WF選出 | WF | cmd_1867 | okugi_shin_alm/ |
| ⑤ | 奥義ALMシン×シン | ALM忍法→事後選出 | 事後 | cmd_1868 | okugi_alm_shin/ |
| ⑥ | 奥義ALMシン×ALM | ALM忍法→事後選出 | WF | cmd_1868 | okugi_alm_shin/ |
| ⑦ | 奥義ALMALM×シン | ALM忍法→ALM WF選出 | 事後 | cmd_1863 | okugi_alm_alm/ |
| ⑧ | 奥義ALMALM×ALM | ALM忍法→ALM WF選出 | WF | cmd_1863 | okugi_alm_alm/ |

### L1体数と目的関数

| L1方式 | 目的関数(3つ) | 対応モード | 最大体数 |
|--------|-------------|----------|---------|
| **シン忍法** | CAGR / NewHigh(NHF) / MaxDD | 激攻 / 常勝 / 鉄壁 | 7忍法×3 = 21体(吸収後20体) |
| **ALM忍法** | MRU / Calmar / UWP | (殿裁定2026-04-06) | 7忍法×3 = 21体(吸収後19体) |

出典: `projects/dm-signal.yaml` modes定義 + `context/checklist-alm-registration.md` L13,L52,L86

## 前提条件（全パターン共通）

### 道具(2つ)
| 道具 | パス | 用途 |
|------|------|------|
| champion_selector.py | `outputs/scripts/champion_selector.py` | L2シン選出(事後GS固定) |
| l1_alm_wf_engine.py | `outputs/scripts/l1_alm_wf_engine.py` | L2 ALM選出(WF動的) |

### GS実行スクリプト(7本)
`scripts/analysis/grid_search/run_077_{bunshin,kasoku_diff,kasoku_ratio,kawarimi,nukimi,oikaze,yotsume}.py`

### リファレンス(既存L2実績)
`outputs/grid_search/okugi_shin_ninpo_20body/` — N=20で全7忍法GS完走。kasoku_diff 944,775パターン(peak ~1.9GB)。

## データフロー

```
[L1素材(cmd_1867/1868/1863)]
  ↓ 3目的分の月次リターン抽出
[統合CSV (year_month + 21列)]
  ↓ universe YAML作成
[run_077 × 7忍法 = GS CSV]
  ↓
[champion_selector(シン選出) or l1_alm_wf_engine(ALM選出)]
  ↓
[8パターンの月次リターン]
  ↓
[2×2因子分析(β調整)]
```

## ランブック

### Phase 0: universe CSV修正（OOM修正）

**現状**: okugi_shin_alm/okugi_alm_almの統合CSVが42列(6目的全列挙)。
**修正**: 3目的のみに絞り21列にする。

| universe | 現状列数 | 正しい列数 | 残す目的 |
|----------|---------|-----------|---------|
| okugi_shin_alm | 43(year_month+42) | **22(year_month+21)** | ALM3目的: max_run_up / calmar_ratio / underwater_period |
| okugi_alm_shin | 22(year_month+21) | 22 ✅ 修正不要 | シン3目的: cagr / nhf / maxdd |
| okugi_alm_alm | 43(year_month+42) | **22(year_month+21)** | ALM3目的: max_run_up / calmar_ratio / underwater_period |

**手順**:
```bash
cd /mnt/c/Python_app/DM-signal

# (A) okugi_shin_alm: ALM3目的のみ残す
# 元CSV: outputs/grid_search/okugi_shin_alm/okugi_shin_alm_monthly.csv
# 残す列: year_month + *__max_run_up + *__calmar_ratio + *__underwater_period (7忍法×3=21列)
python3 -c "
import pandas as pd
df = pd.read_csv('outputs/grid_search/okugi_shin_alm/okugi_shin_alm_monthly.csv')
keep = ['year_month'] + [c for c in df.columns if any(c.endswith(obj) for obj in ['__max_run_up','__calmar_ratio','__underwater_period'])]
df[keep].to_csv('outputs/grid_search/okugi_shin_alm/okugi_shin_alm_monthly.csv', index=False)
print(f'Columns: {len(keep)} (expect 22)')
"

# (B) okugi_alm_alm: 同様
python3 -c "
import pandas as pd
df = pd.read_csv('outputs/grid_search/okugi_alm_alm/okugi_alm_alm_monthly.csv')
keep = ['year_month'] + [c for c in df.columns if any(c.endswith(obj) for obj in ['__max_run_up','__calmar_ratio','__underwater_period'])]
df[keep].to_csv('outputs/grid_search/okugi_alm_alm/okugi_alm_alm_monthly.csv', index=False)
print(f'Columns: {len(keep)} (expect 22)')
"

# (C) universe YAML修正: families/patternsを21体に
# okugi_shin_alm.yaml と okugi_alm_alm.yaml のpatternsリストから
# cagr/nhf/maximum_drawdown列を削除し、max_run_up/calmar_ratio/underwater_period のみ残す

# (D) 検証
head -1 outputs/grid_search/okugi_shin_alm/okugi_shin_alm_monthly.csv | tr ',' '\n' | wc -l  # expect 22
head -1 outputs/grid_search/okugi_alm_alm/okugi_alm_alm_monthly.csv | tr ',' '\n' | wc -l  # expect 22
```

**注意**:
- okugi_alm_shinはcmd_1868がシン3目的(cagr/nhf/maxdd)で作成済みのため修正不要。
- 統合CSVを上書きする前に `cp *_monthly.csv *_monthly.csv.bak_42col` でバックアップせよ。

### Phase 1: 既存GS結果の削除

前回OOM + 42列GSで生成された不正なGS結果CSVを削除。

```bash
# 42列ベースのbunshin結果(124,272パターン)を削除
# okugi_shin_alm, okugi_alm_alm のGS結果CSV
rm outputs/grid_search/okugi_shin_alm/metrics_*_results_fast.csv 2>/dev/null
rm outputs/grid_search/okugi_shin_alm/metrics_*_monthly_fast.csv* 2>/dev/null
rm outputs/grid_search/okugi_alm_alm/metrics_*_results_fast.csv 2>/dev/null
rm outputs/grid_search/okugi_alm_alm/metrics_*_monthly_fast.csv* 2>/dev/null
# okugi_alm_shin: N=21で正しいが、元CSVの整合性確認後に再実行の方が安全
rm outputs/grid_search/okugi_alm_shin/metrics_*_results_fast.csv 2>/dev/null
rm outputs/grid_search/okugi_alm_shin/metrics_*_monthly_fast.csv* 2>/dev/null
```

### Phase 2: GS実行（③④⑤⑥⑦⑧の素材生成）

3パターン×7忍法 = 21 GS。**直列1本ずつ**(LG025: OOM防止)。

```bash
cd /mnt/c/Python_app/DM-signal

for universe in okugi_shin_alm okugi_alm_shin okugi_alm_alm; do
  for script in scripts/analysis/grid_search/run_077_*.py; do
    ninjutsu=$(basename "$script" .py | sed 's/run_077_//')
    echo "=== ${universe} × ${ninjutsu} ==="
    python3 "$script" \
      --universe "config/portfolio_universes/${universe}.yaml" \
      --out-dir "outputs/grid_search/${universe}/"
  done
done
```

**メモリ見積り(N=21)**: peak kasoku_diff 2,354MB(2x)。16GB - agent 2.1GB - OS 1GB = 余裕あり。

**検証**: 各忍法の`*_results_fast.csv`と`*_monthly_fast.csv`が生成されること。

### Phase 3: 8パターン選出

| # | パターン | 道具 | コマンド |
|---|---------|------|---------|
| ① | シンシン | champion_selector | `python3 outputs/scripts/champion_selector.py --csv-dir outputs/grid_search/okugi_shin_ninpo_20body --cmd-id cmd_XXXX_ss_shin` |
| ② | シンALM | WF engine | `python3 outputs/scripts/l1_alm_wf_engine.py --batch-csvs outputs/grid_search/okugi_shin_ninpo_20body/tmp_1822_*_monthly_fast.csv --multi-is --cmd-id cmd_XXXX_ss_alm` |
| ③ | シンALM×シン | champion_selector | `python3 outputs/scripts/champion_selector.py --csv-dir outputs/grid_search/okugi_shin_alm --cmd-id cmd_XXXX_sa_shin` |
| ④ | シンALM×ALM | WF engine | `python3 outputs/scripts/l1_alm_wf_engine.py --batch-csvs outputs/grid_search/okugi_shin_alm/*_monthly_fast.csv --multi-is --cmd-id cmd_XXXX_sa_alm` |
| ⑤ | ALMシン×シン | champion_selector | `python3 outputs/scripts/champion_selector.py --csv-dir outputs/grid_search/okugi_alm_shin --cmd-id cmd_XXXX_as_shin` |
| ⑥ | ALMシン×ALM | WF engine | `python3 outputs/scripts/l1_alm_wf_engine.py --batch-csvs outputs/grid_search/okugi_alm_shin/*_monthly_fast.csv --multi-is --cmd-id cmd_XXXX_as_alm` |
| ⑦ | ALMALM×シン | champion_selector | `python3 outputs/scripts/champion_selector.py --csv-dir outputs/grid_search/okugi_alm_alm --cmd-id cmd_XXXX_aa_shin` |
| ⑧ | ALMALM×ALM | WF engine | `python3 outputs/scripts/l1_alm_wf_engine.py --batch-csvs outputs/grid_search/okugi_alm_alm/*_monthly_fast.csv --multi-is --cmd-id cmd_XXXX_aa_alm` |

**①は既存(cmd_1844)。①のリファレンスがあるので再実行不要。**

### Phase 4: 2×2因子分析（β調整）

8パターンの月次リターンを共通期間で統一。SPY月次リターン(本番DB)でβ調整。

```
BB効果 = (ALM BB行) - (シンBB行) ← 同じ選出方式で比較
動的選出効果 = (ALM選出列) - (シン選出列) ← 同じBBで比較
```

β調整: 各パターンのCAGR_adj = CAGR_raw - β × SPY_CAGR。cmd_1870と同一手法。

## OOM根因と修正（付録）

**根因**: universe CSV 42列(6目的全列挙)→ C(42,k)で組合せ爆発。
**修正**: 21列(3目的)に修正。N=21ならrun_077変更不要。
**リファレンス**: okugi_shin_ninpo_20body(N=20)で全7忍法完走実績。

詳細: `docs/research/gunshi_okugi_gs_oom_design_20260412.md`

## 設計書作成日
- v1-v3: 2026-04-12 OOM分析版
- v4: 2026-04-12T16:50:00+09:00 — 8パターン全体設計書+ランブック。殿指摘反映(L1最大21体/既存L2参照/目的関数確認)
