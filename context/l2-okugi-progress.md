# L2奥義 56ブロック進行表
<!-- last_updated: 2026-04-12T21:10:00+09:00 -->
<!-- updated_by: shogun -->

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
| 2-1 | bunshin | ❌ | — | — | — |
| 2-2 | oikaze | ❌ | — | — | — |
| 2-3 | kasoku_diff | ❌ | — | — | — |
| 2-4 | kasoku_ratio | ❌ | — | — | — |
| 2-5 | kawarimi | ✅ | 部分 | GS: okugi_shin_ninpo_20body/tmp_1822_kawarimi_monthly_fast.csv (503MB) | — |
| 2-6 | nukimi | ✅ | 部分 | GS: okugi_shin_ninpo_20body/tmp_1822_nukimi_monthly_fast.csv (941MB) | — |
| 2-7 | yotsume | ❌ | — | — | — |

**② 完了: 0/7** — GS(monthly)残5本。WF選出は全忍法のmonthly揃い後に一括実行

---

### ③ シンALM×シン (シンBB・ALM忍法21体・GS固定選出)
GS dir: okugi_shin_alm/ → 選出: champion_selector

| # | 忍法 | GS(R) | 選出 | 成果物所在 | 完了日 |
|---|------|:-----:|:----:|-----------|-------|
| 3-1 | bunshin | ✅ | — | GS: okugi_shin_alm/cmd_1871_shin_alm_bunshin_grid_results_fast.csv (2.0MB, 7526行) | — |
| 3-2 | oikaze | ❌ | — | — | — |
| 3-3 | kasoku_diff | ❌ | — | — (cmd_1871ファイルは旧universe42体で生成→無効。列数1.15M≠有効基準7526) | — |
| 3-4 | kasoku_ratio | ❌ | — | — | — |
| 3-5 | kawarimi | ❌ | — | — | — |
| 3-6 | nukimi | ❌ | — | — | — |
| 3-7 | yotsume | ❌ | — | — | — |

**③ 完了: 0/7** — GS残6本(oikaze, kasoku_diff, kasoku_ratio, kawarimi, nukimi, yotsume)

---

### ④ シンALM×ALM (シンBB・ALM忍法21体・WF動的選出)
GS dir: okugi_shin_alm/ (③と共有, monthly_fast必須) → 選出: WFエンジン

| # | 忍法 | GS(M) | 選出 | 成果物所在 | 完了日 |
|---|------|:-----:|:----:|-----------|-------|
| 4-1 | bunshin | ✅ | — | GS: okugi_shin_alm/cmd_1871_shin_alm_bunshin_grid_monthly_fast.csv (11MB) | — |
| 4-2 | oikaze | ❌ | — | — | — |
| 4-3 | kasoku_diff | ❌ | — | — (cmd_1871ファイルは旧universe42体で生成→無効。1.6GB/列数1.15M≠有効基準7526) | — |
| 4-4 | kasoku_ratio | ❌ | — | — | — |
| 4-5 | kawarimi | ❌ | — | — | — |
| 4-6 | nukimi | ❌ | — | — | — |
| 4-7 | yotsume | ❌ | — | — | — |

**④ 完了: 0/7** — ③のGS完了で自動的にmonthlyも生成される

---

### ⑤ ALMシン×シン (ALM-BB・シン忍法21体・GS固定選出)
GS dir: okugi_alm_shin/ → 選出: champion_selector

| # | 忍法 | GS(R) | 選出 | 成果物所在 | 完了日 |
|---|------|:-----:|:----:|-----------|-------|
| 5-1 | bunshin | ✅ | — | GS: okugi_alm_shin/metrics_bunshin_results_fast.csv (1.7MB, 7526行) | — |
| 5-2 | oikaze | ❌ | — | — | — |
| 5-3 | kasoku_diff | ❌ | — | — | — |
| 5-4 | kasoku_ratio | ❌ | — | — | — |
| 5-5 | kawarimi | ❌ | — | — | — |
| 5-6 | nukimi | ❌ | — | — | — |
| 5-7 | yotsume | ❌ | — | — | — |

**⑤ 完了: 0/7** — GS残6本(oikaze, kasoku_diff, kasoku_ratio, kawarimi, nukimi, yotsume)

---

### ⑥ ALMシン×ALM (ALM-BB・シン忍法21体・WF動的選出)
GS dir: okugi_alm_shin/ (⑤と共有, monthly_fast必須) → 選出: WFエンジン

| # | 忍法 | GS(M) | 選出 | 成果物所在 | 完了日 |
|---|------|:-----:|:----:|-----------|-------|
| 6-1 | bunshin | ✅ | — | GS: okugi_alm_shin/metrics_bunshin_monthly_fast.csv (13MB) | — |
| 6-2 | oikaze | ❌ | — | — | — |
| 6-3 | kasoku_diff | ❌ | — | — | — |
| 6-4 | kasoku_ratio | ❌ | — | — | — |
| 6-5 | kawarimi | ❌ | — | — | — |
| 6-6 | nukimi | ❌ | — | — | — |
| 6-7 | yotsume | ❌ | — | — | — |

**⑥ 完了: 0/7** — ⑤のGS完了で自動的にmonthlyも生成される

---

### ⑦ ALMALM×シン (ALM-BB・ALM忍法21体・GS固定選出)
GS dir: okugi_alm_alm/ → 選出: champion_selector

| # | 忍法 | GS(R) | 選出 | 成果物所在 | 完了日 |
|---|------|:-----:|:----:|-----------|-------|
| 7-1 | bunshin | ✅ | — | GS: okugi_alm_alm/cmd_1876_alm_alm_bunshin_grid_results_fast.csv (2.0MB, 7526行) | — |
| 7-2 | oikaze | ✅ | — | GS: okugi_alm_alm/cmd_1876_alm_alm_oikaze_grid_results_fast.csv (117MB, 270901行) | 2026-04-12 |
| 7-3 | kasoku_diff | ❌ | — | — | — |
| 7-4 | kasoku_ratio | ✅ | — | GS: okugi_alm_alm/cmd_1876_alm_alm_kasoku_ratio_grid_results_fast.csv (349MB, 1.15M行) | 2026-04-12 |
| 7-5 | kawarimi | ❌ | — | — | — |
| 7-6 | nukimi | ❌ | — | — | — |
| 7-7 | yotsume | ❌ | — | — | — |

**⑦ 完了: 0/7** — GS残4本(kasoku_diff, kawarimi, nukimi, yotsume)

---

### ⑧ ALMALM×ALM (ALM-BB・ALM忍法21体・WF動的選出)
GS dir: okugi_alm_alm/ (⑦と共有, monthly_fast必須) → 選出: WFエンジン

| # | 忍法 | GS(M) | 選出 | 成果物所在 | 完了日 |
|---|------|:-----:|:----:|-----------|-------|
| 8-1 | bunshin | ✅ | — | GS: okugi_alm_alm/cmd_1876_alm_alm_bunshin_grid_monthly_fast.csv (12MB) | — |
| 8-2 | oikaze | ✅ | — | GS: okugi_alm_alm/cmd_1876_alm_alm_oikaze_grid_monthly_fast.csv (411MB) | 2026-04-12 |
| 8-3 | kasoku_diff | ❌ | — | — | — |
| 8-4 | kasoku_ratio | ✅ | — | GS: okugi_alm_alm/cmd_1876_alm_alm_kasoku_ratio_grid_monthly_fast.csv (1.7GB) | 2026-04-12 |
| 8-5 | kawarimi | ❌ | — | — | — |
| 8-6 | nukimi | ❌ | — | — | — |
| 8-7 | yotsume | ❌ | — | — | — |

**⑧ 完了: 0/7** — ⑦のGS完了で自動的にmonthlyも生成される

---

## 集計

| 状態 | ブロック数 |
|------|----------|
| ✅ 全完了(DB登録済み) | 7 (①全7) |
| G GS完了・選出待ち | 10 |
| ❌ GS未完了 | 37 |
| 部分(GS済・選出途中) | 2 (②-5, ②-6) |
| **合計** | **56** |

GS実行残量(ペア共有): ②5本 + ③④6本 + ⑤⑥6本 + ⑦⑧4本 = **21本**

## 変更履歴

- 2026-04-12 21:10 56ブロック構造+成果物所在マッピングに全面改修(将軍)。なぜなぜ7回(成果物追跡不在)の対策
- 2026-04-12 20:xx 将軍確認: 1795_ファイル全て無効(旧universe)
- 2026-04-12 19:52 初版作成(将軍)
