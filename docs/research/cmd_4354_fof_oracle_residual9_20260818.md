# cmd_4354 FoF oracle residual-9 closure

- run409 readonly snapshot: `DM-Signal/docs/research/cmd_4352_fof_tiebreak_expected_diff_final.md` (signals/monthly_returns/fof_component_weights; acquired 2026-08-18 02:42 JST).
- Production boundary: `recalculate_fof.py:1371-1381` passes the first production signal date as `PipelineEngine.target_date`; the score still uses the preceding monthly row.
- Oracle correction: `cmd_4350`/`cmd_4342` now use the first non-skipped signal date of `decision_month` for stages ②〜⑥ instead of `month_end(year_month)`.
- Guard14: `readonly_query` only; production write 0.

## Root cause / ownership

The nine residuals were oracle-side. The oracle used the preceding month-end for the comparator history boundary, while production used the next decision signal date. Because stages using `include_target=False` then saw a different last observation, the tie-break result shifted. Candidate collection, score month, production block, and nested propagation were otherwise aligned. No production code or DB row was changed.

## Residual-9 table

Tuple order is `selection_score, 12M, CAGR, MaxDD, previous_holding, inception`. The six-stage values below are equal after the boundary correction; the arrow records the pre-fix oracle selection to run409 selection.

| # | PF / depth | score month → decision date | candidate collection | oracle → run409 | six-stage evidence | difference / owner |
|---:|---|---|---|---|---|---|
| 1 | GSシン加速R-常勝 / 1 | 2012-05 → 2012-06-01 | fd8f131a, fa26dd07, 67dabcbb, c31251e4 | c31251e4 → fa26dd07 | c31251e4=(1,NA,-0.0419139,0.00362748,true,2012-04-30); fa26dd07=(1,0.428495,0.465684,0.0950694,false,2010-10-31) | month_mapping / oracle |
| 2 | 奥義-GS-加速D-常勝 / 2 | 2013-06 → 2013-07-01 | 7091c52b, 6f17572f, 249bef05, 4695ddb9 | 7091c52b → 249bef05 | 7091c52b=(0,NA,-0.245439,0.0893264,true,2013-04-30); 249bef05=(0,0.473168,0.504502,0.0677967,false,2012-02-29) | month_mapping / oracle |
| 3 | 奥義-GS-加速R-常勝 / 2 | 2013-06 → 2013-07-01 | 7091c52b, 6f17572f, 249bef05, 4695ddb9 | 7091c52b → 249bef05 | 7091c52b=(1,NA,-0.245439,0.0893264,true,2013-04-30); 249bef05=(1,0.473168,0.504502,0.0677967,false,2012-02-29) | month_mapping / oracle |
| 4 | 秘奥義-加速R-常勝 / 3 | 2014-05 → 2014-06-02 | cc60f363, a0fa05c5, b1ef6669, 51a06edf | 51a06edf → b1ef6669 | 51a06edf=(1,NA,0.218864,0.00129767,true,2014-03-31); b1ef6669=(1,NA,0.353254,0.0737642,false,2013-09-30) | month_mapping / oracle |
| 5 | 秘奥義-加速R-常勝 / 3 | 2014-06 → 2014-07-01 | cc60f363, a0fa05c5, b1ef6669, 51a06edf | b1ef6669 → a0fa05c5 | b1ef6669=(1,NA,0.413788,0.0737642,true,2013-09-30); a0fa05c5=(1,NA,0.505068,0.0313508,false,2014-01-31) | month_mapping / oracle |
| 6 | 秘奥義-加速R-常勝 / 3 | 2014-07 → 2014-08-01 | cc60f363, a0fa05c5, b1ef6669, 51a06edf | a0fa05c5 → cc60f363 | a0fa05c5=(1,NA,0.368213,0.0313508,true,2014-01-31); cc60f363=(1,NA,0.386638,0.116723,false,2013-09-30) | month_mapping / oracle |
| 7 | 秘奥義-加速R-常勝 / 3 | 2014-08 → 2014-09-02 | cc60f363, a0fa05c5, b1ef6669, 51a06edf | cc60f363 → a0fa05c5 | cc60f363=(1,NA,0.397828,0.116723,true,2013-09-30); a0fa05c5=(1,NA,0.659139,0.0313508,false,2014-01-31) | month_mapping / oracle |
| 8 | 秘奥義-加速R-常勝 / 3 | 2014-12 → 2015-01-02 | cc60f363, a0fa05c5, b1ef6669, 51a06edf | a0fa05c5 → cc60f363 | a0fa05c5=(1,NA,0.411034,0.0707265,true,2014-01-31); cc60f363=(1,0.278106,0.488308,0.116723,false,2013-09-30) | month_mapping / oracle |
| 9 | 秘奥義-追い風-鉄壁 / 3 | 2016-06 → 2016-07-01 | f2d9631d, 96b3ec70, f16fcd15, b1ef6669 | b1ef6669+f2d9631d → 96b3ec70+b1ef6669 | f2d9631d=(0.0157995,NA,0.210284,0,true,2016-05-31); 96b3ec70=(0.0157995,0.699359,0.536568,0.114085,false,2014-03-31); b1ef6669=(0.0347789,0.333538,0.332113,0.168785,true,2013-09-30) | month_mapping / oracle |

## AC2 full-row result

- Output rows: **8,570**
- MATCHED: **8,513**
- MISMATCH: **0**
- MISSING: **57** (permitted not-yet-arrived decision months)
- All-six-stage-tie mismatches: **0**
- Oracle-side residuals closed: **9/9**
- Production-side residuals: **0/9**

DM-Signal CSV: `docs/research/cmd_4354_fof_oracle_residual9_20260818.csv`.
