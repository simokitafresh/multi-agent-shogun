# Vintage Analysis Design — L0→L1→L2 Re-selection Robustness
<!-- session: 2026-04-21, author: shogun, reviewed_by: gunshi (blt_20260421_224142) -->

> **⚠ CONTAMINATED (2026-04-22)**: この設計書はL0(狭義GS=四神パラメータ選出)の再選出を含んでいない。
> cmd_2227/cmd_2228はこの設計書に基づき実行されたが、L0が全期間GSで選出されたままのため結果は汚染されている。
> 出力は`outputs/analysis/vintage/2020_contaminated/`に退避済み。
> L0再選出を含む正しい設計で作り直す必要がある。

## §1. Purpose

Verify that the L0→L1→L2 selection **mechanism** is robust, not just the current champions.
At each vintage year, re-select L0→L1→L2 using only IS data, then measure OOS performance.

Lord's words: 「調べたいのは今のL0-L2の仕組みがロバストかだろ？」

## §2. Design (Method B — Re-selection)

Re-select champions at each vintage using IS-only data. Fix champions. Measure OOS.
GS re-execution NOT required — existing CSV period slicing + ranking recalculation.

### 3 Vintages (Lord-selected)

| Vintage | IS data | OOS period | Market regime |
|---------|---------|------------|---------------|
| 2020 | ~2019-12 | 2020-01 to 2020-12 | COVID shock (Bear→rapid recovery) |
| 2022 | ~2021-12 | 2022-01 to 2022-12 | FRB rate hikes (sustained Bear) |
| 2026 | ~2025-12 | 2026-01 to present (~4 months) | Current (direct validation) |

Lord's words: 「特別な年を抜き出そう。2020はコロナショック、2022はFRBの利上げ、2026は直近」
Lord's words: 「2025年までのデータで選んだものが2026年の今日まではどうだったかもやらないか？」

### Target systems

| System | Full name | L1 champions | L2 patterns |
|--------|-----------|:---:|:---:|
| wf-SSS | WF Shin-BB × Shin-Ninjutsu | 21 bodies | 323,575 |
| wf-ASS | WF ALM-BB × Shin-Ninjutsu | 21 bodies | 3,536,750 |

### Existing monthly return CSVs

| System | File | Period | Months |
|--------|------|--------|:---:|
| wf-SSS | `outputs/analysis/wf_l2_okugi/wf_l2_ss_21_monthly_returns.csv` | 2012-04 to 2026-02 | 167 |
| wf-ASS | `outputs/analysis/wf_l2_okugi/wf_l2_as_21_monthly_returns.csv` | 2015-04 to 2025-11 | 128 |

## §3. Re-selection Pipeline (per vintage)

### Step A: L0 period slicing
- Input: `outputs/grid_search/{ninjutsu}/{ninjutsu}_grid_monthly_fast.csv`
- Process: Filter `year_month <= IS_cutoff_date`, recalculate 3 metrics (CAGR/MaxDD/NHF)
- Tool: pandas (gs_data_loader.py is library)

### Step B: L1 champion selection
- Input: Step A metrics
- Process: champion_selector.py logic (3-objective direct selection)
- Note: champion_selector.py has hardcoded paths → vintage wrapper needed
- Output: vintage L1 champion JSON

### Step C: L2 WF champion selection
- Input: L1 champion monthly returns + IS period filter
- Process: WF logic (IS=36mo, OOS=12mo, step=4mo)
- **CRITICAL: exclude folds where OOS_end > IS_cutoff_date (future contamination)**
- Output: vintage L2 selection timeline

### Step D: OOS measurement
- Input: L2 champion + OOS period monthly returns
- Process: β-adjusted α6 metrics (cmd_1880 logic) + regime analysis (cmd_1934 logic)
- Note: verify SPY data covers IS/OOS periods

## §4. Risks (gunshi review)

| Risk | Severity | Mitigation |
|------|----------|-----------|
| WF fold future contamination | **HIGH** | Filter: fold OOS_end <= IS_cutoff_date |
| All 6 tools lack argparse | MEDIUM | Create vintage_pipeline.py wrapper, import existing logic |
| L0 metric calculation drift | MEDIUM | Call champion_selector.py internal functions directly |
| 2020 vintage low fold count (~18) | LOW | Acceptable but note in results |
| SPY data coverage | LOW | Available from 2012. Verify before run |

## §5. CMD structure

1 vintage = 1 CMD (OOM prevention. Lord: 「まとめると失敗したときに全て消えてしまう。急がば回れだ」)

| CMD | Content |
|-----|---------|
| Pre-cmd | vintage_pipeline.py scaffold (tool-sharpening first) |
| Vintage 2020 | L0→L1→L2 re-select + OOS 2020 |
| Vintage 2022 | L0→L1→L2 re-select + OOS 2022 |
| Vintage 2026 | L0→L1→L2 re-select + OOS 2026-01~today |

## §6. Output CSV naming

```
outputs/analysis/vintage/{vintage_year}/
  vintage_{year}_{ss|as}_l0_metrics.csv
  vintage_{year}_{ss|as}_l1_champions.json
  vintage_{year}_{ss|as}_l2_timeline.csv
  vintage_{year}_{ss|as}_oos_alpha6.csv
  vintage_{year}_{ss|as}_oos_regime.csv
  vintage_{year}_summary.md
```

## §7. AC checklist (per vintage CMD)

- AC1: IS period data slicing + L0 metric recalculation complete
- AC2: L1 champion selection complete (3 modes × 7 ninjutsu = 21 bodies per system)
- AC3: L2 WF champion selection complete (fold filter verified: no future contamination)
- AC4: OOS α6 metrics + regime analysis complete
- AC5: commit+push
