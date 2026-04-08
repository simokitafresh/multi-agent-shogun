# cmd_493 Knowledge Decontamination Report (AC4 Verification)

## 1. Scope
- parent_cmd: `cmd_493`
- verifier: `hayate`
- verification timestamp: `2026-03-04T00:04:59+0900`
- inputs:
  - `queue/reports/sasuke_report_cmd_493.yaml`
  - `queue/reports/tobisaru_report_cmd_493.yaml`
  - `queue/reports/kagemaru_report_cmd_493.yaml`
  - `queue/reports/saizo_report_cmd_493.yaml`
  - `queue/archive/reports/tobisaru_report_cmd_492_20260302.yaml`
  - `git -C /mnt/c/Python_app/DM-signal show --name-only 29c8009`

## 2. AC1: context/*.md → docs/research link reachability

対象: `context/dm-signal-core.md`, `context/dm-signal-ops.md`, `context/dm-signal-research.md`, `context/dm-signal-frontend.md`

- unique refs checked: `13`
- missing: `0`

| ref | resolved root |
|---|---|
| `docs/research/core-db-tables.md` | DM-Signal |
| `docs/research/core-param-catalog.md` | DM-Signal |
| `docs/research/core-local-analysis.md` | DM-Signal |
| `docs/research/core-api-endpoints.md` | DM-Signal |
| `docs/research/core-directory-structure.md` | DM-Signal |
| `docs/research/cmd_484_dm-signal-supplemental-catalog-2.md` | DM-Signal |
| `docs/research/cmd_485_dm-signal-environment-catalog.md` | DM-Signal |
| `docs/research/cmd_488_dm-signal-claude-config-catalog.md` | DM-Signal |
| `docs/research/frontend-components.md` | DM-Signal |
| `docs/research/frontend-api-spec.md` | DM-Signal |
| `docs/research/frontend-deploy.md` | DM-Signal |
| `docs/research/cmd_494_signal-pending-display-fix.md` | multi-agent-shogun |
| `docs/research/cmd_499_march-holding-signal-validation.md` | multi-agent-shogun |

判定: `PASS`（参照到達不能リンクなし）

## 3. AC2: projects/dm-signal.yaml path/function validation

検証対象: `key_files` + `api` セクション

- path refs checked: `55`
- path missing: `1`
- function refs checked: `1`
- function missing: `0`

### Missing path (1)
- `outputs/grid_search/*_champion_monthly_returns.csv`
  - 現行在庫: `246_*_grid_monthly_fast.csv` は存在、`*_champion_monthly_returns.csv` は非存在

### Function check
- `_sanitize_momentum_data()` → `backend/app/api/signals.py:28` で定義確認

判定: `PARTIAL PASS`（1件のみ実在不一致）

## 4. AC3: Fix count summary (severity / file)

集計ルール:
- `saizo` は報告YAMLの `fix_count` をそのまま採用
- `sasuke` / `tobisaru` は cmd_492 の「消失リンク=critical」分類に対応づけ
- `kagemaru` は cmd_492指摘ID(Y-07,Y-08,Y-01,Y-02,Y-09,Y-10,C-07,C-03,Y-04,Y-05)への対応として集計（報告本文からの推定）
- `kotaro` は報告YAML未検出のため、commit `29c8009` のファイルのみ計上（severity未分類）

### Severity summary

| severity | fixed count |
|---|---:|
| critical | 12 |
| major | 13 |
| minor | 3 |
| unclassified | 4 |
| total | 32 |

### File summary

| file (or file group) | critical | major | minor | source |
|---|---:|---:|---:|---|
| `docs/research/core-*.md` (5 files) | 5 | 0 | 0 | sasuke report |
| `docs/research/{parity,spa,edge,gs-results}.md` (4 files) | 4 | 0 | 0 | tobisaru report |
| `projects/dm-signal.yaml` | 1 | 5 | 2 | kagemaru report + cmd_492 mapping |
| `context/dm-signal-core.md` | 0 | 1 | 1 | kagemaru report + cmd_492 mapping |
| `docs/rule/trade-rule.md` | 1 | 0 | 0 | saizo report |
| `docs/rule/api-usage-guide.md` | 1 | 0 | 0 | saizo report |
| `docs/rule/{shijin-pf-creation-runbook,ninpou-fof-creation-runbook,local-postgresql-guide,database-info,return-consistency-verification,local-verification-guide}.md` | 0 | 6 | 0 | saizo report |
| `docs/architecture/Performance.md` | 0 | 1 | 0 | saizo report |
| `docs/skills/{building-block-pattern,database-schema,fof-pipeline-troubleshooting,portfolio-analysis-verification}.md` | 0 | 0 | 0 | commit 29c8009 (severity不明) |

## 5. Final verdict

- AC1: `PASS`
- AC2: `PARTIAL PASS`（`*_champion_monthly_returns.csv` の参照のみ未実在）
- AC3: `PASS`（severity別・ファイル別サマリー作成完了）
- AC4: `PASS`（本レポート作成完了）

追加所見:
- `projects/dm-signal.yaml` 全体文字列を対象にした参考チェックでは、`_load_all_prices()` と `_precompute_pipeline_signals()` の関数名参照が現行 `recalculate_fast.py` に存在しない。`recalculate_phases` 説明行の鮮度確認対象。
