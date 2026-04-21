# L2奥義 56ブロック進行表
<!-- last_updated: 2026-04-15T01:40:00+09:00 -->
<!-- updated_by: karo -->

> 全エージェント参照可。将軍が随時更新。
> **成果物所在が空欄の完了ブロックは gate_artifact_map.sh がWARN**

## 設計原則

- シン忍法3目的: CAGR / NHF / MaxDD
- ALM忍法3目的: MRU / calmar / UWP
- **各universe最大21体(7忍法×3目的)。6目的混合禁止(cmd_1871事故)**
- OOM対策: 1忍者1忍法直列。MP_WORKERS=1(commit 6efe2681)
- 1795_プレフィックスCSVは全て旧universe(42体)で生成→**無効。使用禁止**

## 2×2因子分析マトリクス

|  | シン選出(GS固定) | ALM選出(WF動的) |
|--|-----------------|----------------|
| **シンBB × シン忍法** | ① | ② |
| **シンBB × ALM忍法** | ③ | ④ |
| **ALM-BB × シン忍法** | ⑤ | ⑥ |
| **ALM-BB × ALM忍法** | ⑦ | ⑧ |

## GS入力データ

| GS dir | universe YAML | N | 使用パターン | universe CSV列数 |
|--------|--------------|---|------------|---------------|
| (①②: DB source) | okugi_shin_ninpo_20.yaml | 20 | ①② | — |
| okugi_shin_alm/ | okugi_shin_alm.yaml | 21 | ③④ | 22列 ✅ |
| okugi_alm_shin/ | okugi_alm_shin.yaml | 21 | ⑤⑥ | 22列 ✅ |
| okugi_alm_alm/ | okugi_alm_alm.yaml | 21 | ⑦⑧ | 22列 ✅ |

## 56ブロック全量

凡例: GS/選出列 ✅=完了 ❌=未完了 G=GS済・選出待ち
**成果物所在が「—」の完了(✅)ブロックはgate違反**

---

### ① シンシン×シン (シンBB・シン忍法20体・GS固定選出)
GS: cmd_1822 (DB source) → 選出: cmd_1844 (champion_selector) → DB登録: cmd_1856

| # | 忍法 | GS | 選出 | 成果物所在 | 完了日 |
|---|------|:--:|:----:|-----------|-------|
| 1-1 | bunshin | ✅ | ✅ | DB: 奥義-分身-{常勝/激攻/鉄壁} id=04a6/7d6c/f003 | 2026-04-11 |
| 1-2 | oikaze | ✅ | ✅ | DB: 奥義-追い風-{常勝/激攻/鉄壁} id=f3b9/bebf/3a67 | 2026-04-11 |
| 1-3 | kasoku_diff | ✅ | ✅ | DB: 奥義-加速D-{常勝/激攻/鉄壁} id=b2f4/96e9/a32d | 2026-04-11 |
| 1-4 | kasoku_ratio | ✅ | ✅ | DB: 奥義-加速R-{常勝/激攻/鉄壁} id=14f0/d08f/8114 | 2026-04-11 |
| 1-5 | kawarimi | ✅ | ✅ | DB: 奥義-変わり身-{常勝/激攻/鉄壁} id=38c7/ad8d/51ea | 2026-04-11 |
| 1-6 | nukimi | ✅ | ✅ | DB: 奥義-抜き身-{常勝/激攻/鉄壁} id=770d/2cdd/19e0 | 2026-04-11 |
| 1-7 | yotsume | ✅ | ✅ | DB: 奥義-四つ目-{常勝/激攻/鉄壁} id=34cc/1857/7480 | 2026-04-11 |

**① 完了: 7/7** — 本番DB登録済み21体(hide=true, active=true)

---

### ② シンシン×ALM (シンBB・シン忍法20体・WF動的選出)
GS: ①と共有 (monthly_fast必須) → 選出: WFエンジン

| # | 忍法 | GS(M) | 選出 | 成果物所在 | 完了日 |
|---|------|:-----:|:----:|-----------|-------|
| 2-1 | bunshin | ✅ | ✅ | GS: okugi_shin_ninpo_20body/cmd_1877_shin_ninpo_20_bunshin_grid_monthly_fast.csv (11MB, 151行) + WF: alm_research/okugi_shin_ninpo_20body/cmd_1877_l1_wf_alm_returns.csv (112行×6系列) + selection_timeline.csv (156エントリ) | 2026-04-13 |
| 2-2 | oikaze | ✅ | ✅ | GS: okugi_shin_ninpo_20body/cmd_1877_shin_ninpo_20_oikaze_grid_monthly_fast.csv (150行) + WF: alm_research/okugi_shin_ninpo_20body/cmd_1877_l1_wf_alm_returns.csv (112行×6系列) + selection_timeline.csv (156エントリ) | 2026-04-13 |
| 2-3 | kasoku_diff | ✅ | ✅ | GS: okugi_shin_ninpo_20body/cmd_1877_shin_ninpo_20_kasoku_diff_grid_monthly_fast.csv (1.7GB, 150行) + WF: alm_research/okugi_shin_ninpo_20body/cmd_1877_l1_wf_alm_returns.csv (112行×6系列) + selection_timeline.csv (156エントリ) | 2026-04-13 |
| 2-4 | kasoku_ratio | ✅ | ✅ | GS: okugi_shin_ninpo_20body/cmd_1877_shin_ninpo_20_kasoku_ratio_grid_monthly_fast.csv (1.7GB, 150行) + WF: alm_research/okugi_shin_ninpo_20body/cmd_1877_l1_wf_alm_returns.csv (112行×6系列) + selection_timeline.csv (156エントリ) | 2026-04-13 |
| 2-5 | kawarimi | ✅ | ✅ | GS: okugi_shin_ninpo_20body/tmp_1822_kawarimi_grid_monthly_fast.csv (503MB) + WF: alm_research/okugi_shin_ninpo_20body/cmd_1877_l1_wf_alm_returns.csv (112行×6系列) + selection_timeline.csv (156エントリ) | 2026-04-13 |
| 2-6 | nukimi | ✅ | ✅ | GS: okugi_shin_ninpo_20body/tmp_1822_nukimi_grid_monthly_fast.csv (941MB) + WF: alm_research/okugi_shin_ninpo_20body/cmd_1877_l1_wf_alm_returns.csv (112行×6系列) + selection_timeline.csv (156エントリ) | 2026-04-13 |
| 2-7 | yotsume | ✅ | ✅ | GS: okugi_shin_ninpo_20body/cmd_1877_shin_ninpo_20_yotsume_grid_monthly_fast.csv (63MB, 150行) + WF: alm_research/okugi_shin_ninpo_20body/cmd_1877_l1_wf_alm_returns.csv (112行×6系列) + selection_timeline.csv (156エントリ) | 2026-04-13 |

**② 完了: 7/7** ✅ — WF選出: 全7本完了

---

### ③ シンALM×シン (シンBB・ALM忍法21体・GS固定選出)
GS dir: okugi_shin_alm/ → 選出: champion_selector

| # | 忍法 | GS(R) | 選出 | 成果物所在 | 完了日 |
|---|------|:-----:|:----:|-----------|-------|
| 3-1 | bunshin | ✅ | ✅ | GS: okugi_shin_alm/cmd_1871_shin_alm_bunshin_grid_results_fast.csv (2.0MB, 7526行) + 選出: okugi_shin_alm/cmd_1877_shin_alm_champions.json (shared, 4.3KB, 7忍法×3目的) | 2026-04-13 |
| 3-2 | oikaze | ✅ | ✅ | GS: okugi_shin_alm/cmd_1877_shin_alm_oikaze_grid_results_fast.csv (115MB, 270901行) + 選出: okugi_shin_alm/cmd_1877_shin_alm_champions.json (shared, 4.3KB, 7忍法×3目的) | 2026-04-13 |
| 3-3 | kasoku_diff | ✅ | ✅ | GS: okugi_shin_alm/cmd_1877_shin_alm_kasoku_diff_grid_results_fast.csv (346MB, 1151326行) + 選出: okugi_shin_alm/cmd_1877_shin_alm_champions.json (shared, 4.3KB, 7忍法×3目的) | 2026-04-13 |
| 3-4 | kasoku_ratio | ✅ | ✅ | GS: okugi_shin_alm/cmd_1877_shin_alm_kasoku_ratio_grid_results_fast.csv (350MB, 1151325行) + 選出: okugi_shin_alm/cmd_1877_shin_alm_champions.json (shared, 4.3KB, 7忍法×3目的) | 2026-04-13 |
| 3-5 | kawarimi | ✅ | ✅ | GS: okugi_shin_alm/cmd_1877_shin_alm_kawarimi_grid_results_fast.csv (94MB, 270901行) + 選出: okugi_shin_alm/cmd_1877_shin_alm_champions.json (shared, 4.3KB, 7忍法×3目的) | 2026-04-13 |
| 3-6 | nukimi | ✅ | ✅ | GS: okugi_shin_alm/cmd_1877_shin_alm_nukimi_grid_results_fast.csv (177MB, 586951行) + 選出: okugi_shin_alm/cmd_1877_shin_alm_champions.json (shared, 4.3KB, 7忍法×3目的) | 2026-04-13 |
| 3-7 | yotsume | ✅ | ✅ | GS: okugi_shin_alm/cmd_1877_shin_alm_yotsume_grid_results_fast.csv (20MB, 45150行) + 選出: okugi_shin_alm/cmd_1877_shin_alm_champions.json (shared, 4.3KB, 7忍法×3目的) | 2026-04-13 |

**③ 完了: 7/7** — champion選出完了。shared artifact: `okugi_shin_alm/cmd_1877_shin_alm_champions.json`

---

### ④ シンALM×ALM (シンBB・ALM忍法21体・WF動的選出)
GS dir: okugi_shin_alm/ (③と共有, monthly_fast必須) → 選出: WFエンジン

| # | 忍法 | GS(M) | 選出 | 成果物所在 | 完了日 |
|---|------|:-----:|:----:|-----------|-------|
| 4-1 | bunshin | ✅ | ✅ | GS: okugi_shin_alm/cmd_1871_shin_alm_bunshin_grid_monthly_fast.csv (11MB) + WF: alm_research/okugi_shin_alm/cmd_1877_l1_wf_alm_returns.csv (88行×6系列) + selection_timeline.csv (120エントリ) | 2026-04-13 |
| 4-2 | oikaze | ✅ | ✅ | GS: okugi_shin_alm/cmd_1877_shin_alm_oikaze_grid_monthly_fast.csv (394MB, 126行) + WF: alm_research/okugi_shin_alm/cmd_1877_l1_wf_alm_returns.csv (88行×6系列) + selection_timeline.csv (120エントリ) | 2026-04-13 |
| 4-3 | kasoku_diff | ✅ | ✅ | GS: okugi_shin_alm/cmd_1877_shin_alm_kasoku_diff_grid_monthly_fast.csv (1.6GB, 126行) + WF: alm_research/okugi_shin_alm/cmd_1877_l1_wf_alm_returns.csv (88行×6系列) + selection_timeline.csv (120エントリ) | 2026-04-13 |
| 4-4 | kasoku_ratio | ✅ | ✅ | GS: okugi_shin_alm/cmd_1877_shin_alm_kasoku_ratio_grid_monthly_fast.csv (1.6GB, 125行) + WF: alm_research/okugi_shin_alm/cmd_1877_l1_wf_alm_returns.csv (88行×6系列) + selection_timeline.csv (120エントリ) | 2026-04-13 |
| 4-5 | kawarimi | ✅ | ✅ | GS: okugi_shin_alm/cmd_1877_shin_alm_kawarimi_grid_monthly_fast.csv (379MB, 126行) + WF: alm_research/okugi_shin_alm/cmd_1877_l1_wf_alm_returns.csv (88行×6系列) + selection_timeline.csv (120エントリ) | 2026-04-13 |
| 4-6 | nukimi | ✅ | ✅ | GS: okugi_shin_alm/cmd_1877_shin_alm_nukimi_grid_monthly_fast.csv (809MB, 125行) + WF: alm_research/okugi_shin_alm/cmd_1877_l1_wf_alm_returns.csv (88行×6系列) + selection_timeline.csv (120エントリ) | 2026-04-13 |
| 4-7 | yotsume | ✅ | ✅ | GS: okugi_shin_alm/cmd_1877_shin_alm_yotsume_grid_monthly_fast.csv (63MB, 125行) + WF: alm_research/okugi_shin_alm/cmd_1877_l1_wf_alm_returns.csv (88行×6系列) + selection_timeline.csv (120エントリ) | 2026-04-13 |

**④ 完了: 7/7** ✅ — WF選出: 全7本完了

---

### ⑤ ALMシン×シン (ALM-BB・シン忍法21体・GS固定選出)
GS dir: okugi_alm_shin/ → 選出: champion_selector

| # | 忍法 | GS(R) | 選出 | 成果物所在 | 完了日 |
|---|------|:-----:|:----:|-----------|-------|
| 5-1 | bunshin | ✅ | ✅ | GS: okugi_alm_shin/metrics_bunshin_grid_results_fast.csv (1.7MB, 7526行) + 選出: okugi_alm_shin/cmd_1877_alm_shin_champions.json (shared, 4.3KB, 7忍法×3目的) | 2026-04-13 |
| 5-2 | oikaze | ✅ | ✅ | GS: okugi_alm_shin/cmd_1877_alm_shin_oikaze_grid_results_fast.csv (100MB, 270901行) + 選出: okugi_alm_shin/cmd_1877_alm_shin_champions.json (shared, 4.3KB, 7忍法×3目的) | 2026-04-13 |
| 5-3 | kasoku_diff | ✅ | ✅ | GS: okugi_alm_shin/cmd_1877_alm_shin_kasoku_diff_grid_results_fast.csv (310MB, 1151325行) + 選出: okugi_alm_shin/cmd_1877_alm_shin_champions.json (shared, 4.3KB, 7忍法×3目的) | 2026-04-13 |
| 5-4 | kasoku_ratio | ✅ | ✅ | GS: okugi_alm_shin/cmd_1877_alm_shin_kasoku_ratio_grid_results_fast.csv (312MB, 1151325行) + 選出: okugi_alm_shin/cmd_1877_alm_shin_champions.json (shared, 4.3KB, 7忍法×3目的) | 2026-04-13 |
| 5-5 | kawarimi | ✅ | ✅ | GS: okugi_alm_shin/cmd_1877_alm_shin_kawarimi_grid_results_fast.csv (85MB, 270901行) + 選出: okugi_alm_shin/cmd_1877_alm_shin_champions.json (shared, 4.3KB, 7忍法×3目的) | 2026-04-13 |
| 5-6 | nukimi | ✅ | ✅ | GS: okugi_alm_shin/cmd_1877_alm_shin_nukimi_grid_results_fast.csv (158MB, 586950行) + 選出: okugi_alm_shin/cmd_1877_alm_shin_champions.json (shared, 4.3KB, 7忍法×3目的) | 2026-04-13 |
| 5-7 | yotsume | ✅ | ✅ | GS: okugi_alm_shin/cmd_1877_alm_shin_yotsume_grid_results_fast.csv (17MB, 45150行) + 選出: okugi_alm_shin/cmd_1877_alm_shin_champions.json (shared, 4.3KB, 7忍法×3目的) | 2026-04-13 |

**⑤ 完了: 7/7** — champion選出完了。shared artifact: `okugi_alm_shin/cmd_1877_alm_shin_champions.json`

---

### ⑥ ALMシン×ALM (ALM-BB・シン忍法21体・WF動的選出)
GS dir: okugi_alm_shin/ (⑤と共有, monthly_fast必須) → 選出: WFエンジン

| # | 忍法 | GS(M) | 選出 | 成果物所在 | 完了日 |
|---|------|:-----:|:----:|-----------|-------|
| 6-1 | bunshin | ✅ | ✅ | GS: okugi_alm_shin/metrics_bunshin_grid_monthly_fast.csv (13MB) + WF: alm_research/okugi_alm_shin/cmd_1877_l1_wf_alm_returns.csv (108行×6系列) + selection_timeline.csv (150エントリ) | 2026-04-13 |
| 6-2 | oikaze | ✅ | ✅ | GS: okugi_alm_shin/cmd_1877_alm_shin_oikaze_grid_monthly_fast.csv (456MB, 146行) + WF: alm_research/okugi_alm_shin/cmd_1877_l1_wf_alm_returns.csv (108行×6系列) + selection_timeline.csv (150エントリ) | 2026-04-13 |
| 6-3 | kasoku_diff | ✅ | ✅ | GS: okugi_alm_shin/cmd_1877_alm_shin_kasoku_diff_grid_monthly_fast.csv (1.9GB, 145行) + WF: alm_research/okugi_alm_shin/cmd_1877_l1_wf_alm_returns.csv (108行×6系列) + selection_timeline.csv (150エントリ) | 2026-04-13 |
| 6-4 | kasoku_ratio | ✅ | ✅ | GS: okugi_alm_shin/cmd_1877_alm_shin_kasoku_ratio_grid_monthly_fast.csv (2.0GB, 145行) + WF: alm_research/okugi_alm_shin/cmd_1877_l1_wf_alm_returns.csv (108行×6系列) + selection_timeline.csv (150エントリ) | 2026-04-13 |
| 6-5 | kawarimi | ✅ | ✅ | GS: okugi_alm_shin/cmd_1877_alm_shin_kawarimi_grid_monthly_fast.csv (442MB, 145行) + WF: alm_research/okugi_alm_shin/cmd_1877_l1_wf_alm_returns.csv (108行×6系列) + selection_timeline.csv (150エントリ) | 2026-04-13 |
| 6-6 | nukimi | ✅ | ✅ | GS: okugi_alm_shin/cmd_1877_alm_shin_nukimi_grid_monthly_fast.csv (943MB, 145行) + WF: alm_research/okugi_alm_shin/cmd_1877_l1_wf_alm_returns.csv (108行×6系列) + selection_timeline.csv (150エントリ) | 2026-04-13 |
| 6-7 | yotsume | ✅ | ✅ | GS: okugi_alm_shin/cmd_1877_alm_shin_yotsume_grid_monthly_fast.csv (73MB, 145行) + WF: alm_research/okugi_alm_shin/cmd_1877_l1_wf_alm_returns.csv (108行×6系列) + selection_timeline.csv (150エントリ) | 2026-04-13 |

**⑥ 完了: 7/7** — WF選出: bunshin✅ oikaze✅ kasoku_diff✅ kasoku_ratio✅ kawarimi✅ nukimi✅ yotsume✅。⑥全完了

---

### ⑦ ALMALM×シン (ALM-BB・ALM忍法21体・GS固定選出)
GS dir: okugi_alm_alm/ → 選出: champion_selector

| # | 忍法 | GS(R) | 選出 | 成果物所在 | 完了日 |
|---|------|:-----:|:----:|-----------|-------|
| 7-1 | bunshin | ✅ | ✅ | GS: okugi_alm_alm/cmd_1876_alm_alm_bunshin_grid_results_fast.csv (2.0MB, 7526行) + 選出: okugi_alm_alm/cmd_1877_alm_alm_champions.json (shared, 4.3KB, 7忍法×3目的) | 2026-04-13 |
| 7-2 | oikaze | ✅ | ✅ | GS: okugi_alm_alm/cmd_1876_alm_alm_oikaze_grid_results_fast.csv (117MB, 270901行) + 選出: okugi_alm_alm/cmd_1877_alm_alm_champions.json (shared, 4.3KB, 7忍法×3目的) | 2026-04-13 |
| 7-3 | kasoku_diff | ✅ | ✅ | GS: okugi_alm_alm/cmd_1877_alm_alm_kasoku_diff_grid_results_fast.meta.yaml + cache(arr/columns/index.npy)。CSV本体はfilter-repoで除去(346MB>100MB制限)。cache復元可能 + 選出: okugi_alm_alm/cmd_1877_alm_alm_champions.json | 2026-04-13 |
| 7-4 | kasoku_ratio | ✅ | ✅ | GS: okugi_alm_alm/cmd_1876_alm_alm_kasoku_ratio_grid_results_fast.csv (349MB, 1.15M行) + 選出: okugi_alm_alm/cmd_1877_alm_alm_champions.json (shared, 4.3KB, 7忍法×3目的) | 2026-04-13 |
| 7-5 | kawarimi | ✅ | ✅ | GS: okugi_alm_alm/cmd_1877_alm_alm_kawarimi_grid_results_fast.csv (93MB, 270901行) + okugi_alm_alm/cmd_1877_alm_alm_kawarimi_grid_monthly_fast.csv (396MB, 131行) + 選出: okugi_alm_alm/cmd_1877_alm_alm_champions.json (shared, 4.3KB, 7忍法×3目的) | 2026-04-13 |
| 7-6 | nukimi | ✅ | ✅ | GS: okugi_alm_alm/cmd_1877_alm_alm_nukimi_grid_results_fast.csv (176MB, 586951行) + 選出: okugi_alm_alm/cmd_1877_alm_alm_champions.json (shared, 4.3KB, 7忍法×3目的) | 2026-04-13 |
| 7-7 | yotsume | ✅ | ✅ | GS: okugi_alm_alm/cmd_1877_alm_alm_yotsume_grid_results_fast.csv (20MB, 45151行) + 選出: okugi_alm_alm/cmd_1877_alm_alm_champions.json (shared, 4.3KB, 7忍法×3目的) | 2026-04-13 |

**⑦ 完了: 7/7** ✅ — champion選出完了。shared artifact: `okugi_alm_alm/cmd_1877_alm_alm_champions.json`

---

### ⑧ ALMALM×ALM (ALM-BB・ALM忍法21体・WF動的選出)
GS dir: okugi_alm_alm/ (⑦と共有, monthly_fast必須) → 選出: WFエンジン

| # | 忍法 | GS(M) | 選出 | 成果物所在 | 完了日 |
|---|------|:-----:|:----:|-----------|-------|
| 8-1 | bunshin | ✅ | ✅ | GS: okugi_alm_alm/cmd_1876_alm_alm_bunshin_grid_monthly_fast.csv (12MB) + WF: alm_research/okugi_alm_alm/cmd_1877_l1_wf_alm_returns.csv (92行×6系列) + selection_timeline.csv (126エントリ) | 2026-04-13 |
| 8-2 | oikaze | ✅ | ✅ | GS: okugi_alm_alm/cmd_1876_alm_alm_oikaze_grid_monthly_fast.csv (411MB) + WF: alm_research/okugi_alm_alm/cmd_1877_l1_wf_alm_returns.csv (92行×6系列) + selection_timeline.csv (126エントリ) | 2026-04-13 |
| 8-3 | kasoku_diff | ✅ | ✅ | GS: cache(arr/columns/index.npy)復元可能。CSV本体はfilter-repoで除去(1.7GB>100MB制限) + WF: alm_research/okugi_alm_alm/cmd_1877_kasoku_diff_l1_wf_alm_returns.csv | 2026-04-13 |
| 8-4 | kasoku_ratio | ✅ | ✅ | GS: okugi_alm_alm/cmd_1876_alm_alm_kasoku_ratio_grid_monthly_fast.csv (1.7GB) + WF: alm_research/okugi_alm_alm/cmd_1877_l1_wf_alm_returns.csv (92行×6系列) + selection_timeline.csv (126エントリ) | 2026-04-13 |
| 8-5 | kawarimi | ✅ | ✅ | GS: okugi_alm_alm/cmd_1877_alm_alm_kawarimi_grid_monthly_fast.csv (396MB) + WF: alm_research/okugi_alm_alm/cmd_1877_l1_wf_alm_returns.csv (92行×6系列) + selection_timeline.csv (126エントリ) | 2026-04-13 |
| 8-6 | nukimi | ✅ | ✅ | GS: okugi_alm_alm/cmd_1877_alm_alm_nukimi_grid_monthly_fast.csv (845MB, 131行) + WF: alm_research/okugi_alm_alm/cmd_1877_l1_wf_alm_returns.csv (92行×6系列) + selection_timeline.csv (126エントリ) | 2026-04-13 |
| 8-7 | yotsume | ✅ | ✅ | GS: okugi_alm_alm/cmd_1877_alm_alm_yotsume_grid_monthly_fast.csv (66MB, 131行) + WF: alm_research/okugi_alm_alm/cmd_1877_l1_wf_alm_returns.csv (92行×6系列) + selection_timeline.csv (126エントリ) | 2026-04-13 |

**⑧ 完了: 7/7** ✅ — 全忍法GS+WF完了

---

## 集計

| 状態 | ブロック数 |
|------|----------|
| ✅ 完了 | 14 (①DB登録済み7 + ③選出完了7) |
| G GS完了・選出待ち | 30 |
| ❌ GS未完了 | 10 |
| 部分(GS済・選出途中) | 2 (②-5, ②-6) |
| **合計** | **56** |

GS実行残量: **0本(全完了)** — cmd_1877で全52ブロック完了(2026-04-13)

## 変更履歴

- 2026-04-13 11:01 ⑧8-6 nukimi WF ✅(kotaro, cmd_1877_block_51)
- 2026-04-13 10:46 ⑧8-5 kawarimi WF ✅(hanzo, cmd_1877_block_50)
- 2026-04-13 10:41 ⑧8-4 kasoku_ratio WF ✅(kagemaru, cmd_1877_block_49)
- 2026-04-13 10:10 ⑧8-3 kasoku_diff WF ✅(hayate, cmd_1877_block_48)
- 2026-04-13 09:41 ⑧8-1 bunshin WF ✅(kotaro, cmd_1877_block_46)
- 2026-04-13 09:39 ⑥6-7 yotsume WF ✅(hanzo, cmd_1877_block_45) — ⑥WF完了
- 2026-04-13 09:08 ⑥6-5 kawarimi WF ✅(hayate, cmd_1877_block_43)
- 2026-04-13 08:25 ⑥6-4 kasoku_ratio WF ✅(kotaro, cmd_1877_block_42)
- 2026-04-13 07:35 ⑥6-3 kasoku_diff WF ✅(hanzo, cmd_1877_block_41)
- 2026-04-13 06:51 ⑥6-2 oikaze WF ✅(kagemaru, cmd_1877_block_40)
- 2026-04-13 06:45 ⑥6-1 bunshin WF ✅(saizo, cmd_1877_block_39)
- 2026-04-13 06:40 ④4-7 yotsume WF ✅(hayate, cmd_1877_block_38) — ④WF完了
- 2026-04-13 06:33 ④4-6 nukimi WF ✅(kotaro, cmd_1877_block_37)
- 2026-04-13 05:41 ④4-3 kasoku_diff WF ✅(saizo, cmd_1877_block_34)
- 2026-04-13 04:40 ②2-5 kawarimi WF ✅(saizo, cmd_1877_block_29)
- 2026-04-13 03:22 ②2-7 yotsume GS(M) ✅(saizo, cmd_1877_block_24)
- 2026-04-13 03:17 ②2-4 kasoku_ratio GS(M) ✅(hayate, cmd_1877_block_23)
- 2026-04-13 03:10 ②2-3 kasoku_diff GS(M) ✅(tobisaru, cmd_1877_block_22)
- 2026-04-13 02:51 ⑤5-1〜5-7 champion ✅(saizo, cmd_1877_block_14)
- 2026-04-13 01:51 ⑤5-6/⑥6-6 nukimi ✅(hayate, cmd_1877_block_12)
- 2026-04-13 01:40 ⑦7-7/⑧8-7 yotsume ✅(kotaro, cmd_1877_block_18)
- 2026-04-13 01:14 ⑤5-7/⑥6-7 yotsume ✅(hanzo, cmd_1877_block_13)
- 2026-04-13 01:09 ③3-7/④4-7 yotsume ✅(kagemaru, cmd_1877_block_06)
- 2026-04-13 01:02 ⑦7-3/⑧8-3 kasoku_diff ✅(saizo, cmd_1877_block_15)
- 2026-04-13 00:52 ⑤5-4/⑥6-4 kasoku_ratio ✅(hayate, cmd_1877_block_10)
- 2026-04-13 00:40 ⑤5-3/⑥6-3 kasoku_diff ✅(tobisaru, cmd_1877_block_09)
- 2026-04-13 00:26 ⑤5-2/⑥6-2 oikaze ✅(kotaro, cmd_1877_block_08)
- 2026-04-13 00:22 ③3-5/④4-5 kawarimi ✅(hanzo, cmd_1877_block_04)
- 2026-04-12 23:40 ③3-4/④4-4 kasoku_ratio ✅(kagemaru, cmd_1877_block_03)
- 2026-04-12 21:10 56ブロック構造+成果物所在マッピングに全面改修(将軍)。なぜなぜ7回(成果物追跡不在)の対策
- 2026-04-12 20:xx 将軍確認: 1795_ファイル全て無効(旧universe)
- 2026-04-12 19:52 初版作成(将軍)
- 2026-04-13 02:07 ⑤5-5/⑥6-5 kawarimi ✅(kagemaru, cmd_1877_block_11)
- 2026-04-13 02:00 ⑦7-6/⑧8-6 nukimi ✅(saizo, cmd_1877_block_17)
- 2026-04-13 03:02 ②2-1 bunshin GS(M) ✅(hanzo, cmd_1877_block_20)
- 2026-04-13 02:59 ⑦7-1〜7-7 champion ✅(kagemaru, cmd_1877_block_19)
- 2026-04-13 03:25 ②2-1 bunshin WF選出 ✅(kagemaru, cmd_1877_block_25)
- 2026-04-13 02:41 ③3-1〜3-7 champion ✅(hayate, cmd_1877_block_07_v3)
- 2026-04-13 04:34 ②2-4 kasoku_ratio WF選出 ✅(hayate, cmd_1877_block_28)
- 2026-04-13 04:07 ②2-3 kasoku_diff WF選出 ✅(kotaro, cmd_1877_block_27)
- 2026-04-13 05:00 ②2-6 nukimi WF選出 ✅(kagemaru, cmd_1877_block_30)
- 2026-04-13 05:06 ④4-1 bunshin WF選出 ✅(kotaro, cmd_1877_block_32)
- 2026-04-13 05:05 ②2-7 yotsume WF選出 ✅(hanzo, cmd_1877_block_31) — ②WF完了
- 2026-04-13 03:30 ②2-2 oikaze WF選出 ✅(hanzo, cmd_1877_block_26)
- 2026-04-13 06:12 ④4-4 kasoku_ratio WF選出 ✅(kagemaru, cmd_1877_block_35)
- 2026-04-13 06:18 ④4-5 kawarimi WF選出 ✅(hanzo, cmd_1877_block_36)
- 2026-04-13 05:12 ④4-2 oikaze WF選出 ✅(hayate, cmd_1877_block_33)

## WF L2 SS+AS系統 GS+Champion統合 (cmd_2189-2207, 2026-04-21完遂)

2×2因子分析マトリクスの⑤⑥列（ALM-BB×シン忍法）でWF動的選出用のGS実行+champion事後選出。
道具磨き(cmd_2181-2187: メモリ最適化)の副次効果で4.6倍高速化。1忍法1CMD×直列配備(OOM対策)。

### SS系統（wf_l2_ss: シンBB×シン忍法21体, 142ヶ月）

| 忍法 | CAGR champion | NHF champion | MaxDD champion |
|------|:---:|:---:|:---:|
| kasoku_ratio | **137.5%** | 78.0% | 7.3% |
| kasoku_diff | **134.9%** | 78.0% | 7.5% |
| nukimi | 126.1% | 79.7% | 7.8% |
| kawarimi | 117.1% | **82.9%** | **6.9%** |
| oikaze | 115.1% | 75.9% | 8.5% |
| yotsume | 112.6% | 78.3% | 8.4% |
| bunshin | 96.6% | 78.2% | 7.5% |

成果物: `outputs/grid_search/wf_l2_ss/l2ss_wf_l2_ss_champions.json` (82秒)
cmd: cmd_2189-2195(GS 7忍法), cmd_2198(champion統合)

### AS系統（wf_l2_as: ALM-BB×シン忍法21体, 112ヶ月）

| 忍法 | CAGR champion | NHF champion | MaxDD champion |
|------|:---:|:---:|:---:|
| kasoku_diff | **163.5%** | 77.9% | 6.9% |
| kasoku_ratio | **143.2%** | **82.0%** | 7.9% |
| nukimi | 124.4% | 77.6% | 8.4% |
| oikaze | 120.0% | 75.7% | 10.3% |
| kawarimi | 112.4% | 80.8% | **6.8%** |
| yotsume | 107.3% | 75.2% | 9.7% |
| bunshin | 96.0% | 77.7% | 9.0% |

成果物: `outputs/grid_search/wf_l2_as/l2as_wf_l2_as_champions.json` (20秒)
cmd: cmd_2199-2205(GS 7忍法), cmd_2207(champion統合)

### 両系統の傾向
- CAGR: kasoku_diff/kasoku_ratioが両系統で首位。AS kasoku_diff **163.5%** が最高値
- NHF: kawarimi SS(82.9%), kasoku_ratio AS(82.0%)が突出
- MaxDD: kawarimi が両系統最小(SS 6.9%, AS 6.8%)
- AS系統はSS系統より処理4倍速(期間差: 112ヶ月 vs 142ヶ月)

## L3 β調整分析

| cmd | 内容 | 結果 | 成果物 |
|-----|------|------|--------|
| cmd_1896 | 2体EW β調整(α-CAGR) | 3486ペア×87ヶ月。α-CAGR Top10特定 | `outputs/analysis/alm_research/cmd_1896_l3_beta_adjusted.csv` |
| cmd_1902 | α版6指標拡張(NHF/MaxDD/MRU/Calmar/UWP) | 3486ペア全量。α-Calmar Top1=⑤kasoku_diff激攻×⑤kasoku_ratio鉄壁(16.39)。L0→L1→L2で5/6指標改善(MRUのみno) | `outputs/analysis/alm_research/cmd_1902_l3_alpha_6metrics.csv` |
| cmd_1934 | 3体EW全量探索(⑤×⑤) | C(21,3)=1330通り×4手法×6指標。Expanding/WF Top1=kasoku_diff激攻×kasoku_ratio激攻×kasoku_ratio鉄壁 | `outputs/analysis/alm_research/cmd_1934_l3_threebody_stability.csv` |

## L3 N体EW比較(殿指示 2026-04-16)

殿: 「6指標全部でN体を増やすことでどのような変化があるか調べたい」

### 実行計画(直列・OOMリスク回避)

| 順序 | cmd | universe | N体 | 通り数 | status | 殿の裁定 |
|------|-----|----------|-----|--------|--------|---------|
| 1st | cmd_1947 | ⑤×⑤ | 1/2/3体 | 21+210+1330 | GATE CLEAR | — |
| 2nd | cmd_1948 | ①×① | 1/2/3体 | 21+210+1330 | GATE CLEAR | — |
| 3rd | cmd_1949 | ①2⑤1+2体クロス | 2体441+3体4410 | 4,851 | 進行中 | 軍師スケーラビリティ確認済み(~39秒,1.9MB) |
| 4th | cmd_1950 | ①1⑤2 | 3体 | 4,410 | 待機 | cmd_1949完了後 |

### 殿の裁定(このセクション全体の経緯)
- 「並列にするとOOMリスクがある。5×5が完全に終了してから取り掛かろう」→ 直列実行
- 「1949を2つに分ければ1つあたり4410パターン。そうしたほうが安全」→ cmd_1949/1950分割
- 「1×5から1×1と5×5は除外するべき」→ クロスのみ(重複除外)
- 「軍師に道具磨きの必要がないか確認するべき」→ 軍師検証済み(docs/research/gunshi_cmd1934_scalability_42col_20260416.md)

### 成果物
| cmd | 出力ファイル |
|-----|------------|
| cmd_1947 | `outputs/analysis/alm_research/cmd_1947_l3_*.csv`, `cmd_1947_nbody_comparison_summary.md` |
| cmd_1948 | `outputs/analysis/alm_research/cmd_1948_l3_*.csv`, `cmd_1948_nbody_comparison_1x1_summary.md` |
| cmd_1949 | `outputs/analysis/alm_research/cmd_1949_l3_*.csv`, `cmd_1949_nbody_cross_1maj_summary.md` |
| cmd_1950 | `outputs/analysis/alm_research/cmd_1950_l3_*.csv`, `cmd_1950_nbody_cross_5maj_summary.md` |
