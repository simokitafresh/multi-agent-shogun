# cmd_1985 DM-Signal パリティ検証手段 audit

<!-- created: 2026-04-16 -->
<!-- author: saizo -->
<!-- scope: recon -->

## §1 結論

- 現在の「パリティ検証関連3本」は `scripts/parity_check.sh`、`backend/scripts/snapshot_recalc_results.py`、`backend/scripts/compare_snapshots.py` の組で把握できる。
- ただし3本とも、殿定義の「全期間 holding position 完全一致 + 全期間 monthly return 完全一致」をそのまま満たす道具にはなっていない。
- `fullrecalculate` 本体 (`backend/app/jobs/recalculate_fast.py`) と `/admin/recalculate-sync` には dry-run フラグは存在しない。
- よって CoDD Phase 4 の §5 本番防御層は、現状の `parity_check.sh` 単独前提では不足。`monthly_return_open` + 月次 `holding_signal` を基準にした専用比較へ差し替える必要がある。

## §2 調査対象3本

### 2.1 `multi-agent-shogun/scripts/parity_check.sh`

**目的**
- PF名/UUID または `--all` を受け、multi-agent-shogun 側から本番 PostgreSQL と `analysis_runs/experiments.db` を突合するラッパー。コメント上の目的は「PF登録後のパリティ検証」([scripts/parity_check.sh](/mnt/c/tools/multi-agent-shogun/scripts/parity_check.sh:2))。

**入力**
- CLI引数: `<PF名 or UUID> ...` または `--all` ([scripts/parity_check.sh](/mnt/c/tools/multi-agent-shogun/scripts/parity_check.sh:5))
- 環境/ファイル:
  - `DM_SIGNAL_PATH` / `ENV_PATH` / `EXPERIMENTS_DB` ([scripts/parity_check.sh](/mnt/c/tools/multi-agent-shogun/scripts/parity_check.sh:14))
  - `backend/.env` から `DATABASE_URL` を抽出 ([scripts/parity_check.sh](/mnt/c/tools/multi-agent-shogun/scripts/parity_check.sh:35))

**出力**
- 標準出力に PASS/FAIL/SKIP 詳細
- exit code は 0=全PASS / 1=FAILあり ([scripts/parity_check.sh](/mnt/c/tools/multi-agent-shogun/scripts/parity_check.sh:9))

**使い方**
```bash
bash scripts/parity_check.sh "シン青龍-激攻"
bash scripts/parity_check.sh --all
```

**制約**
- 比較対象の月次列が `monthly_return_open` ではなく `return_open` / `return_close` になっている ([scripts/parity_check.sh](/mnt/c/tools/multi-agent-shogun/scripts/parity_check.sh:150))。現行の `MonthlyReturn` モデル正本は `monthly_return_open` / `monthly_return` であり、殿定義の Open 系月次比較とずれる ([models.py](/mnt/c/Python_app/DM-signal/backend/app/db/models.py:147))。
- holding position 比較も `signals.holding_signal` と、`experiments.db.monthly_returns.signal` から「最大ウェイト1銘柄」を抜く近似であり、FoF の複数構成・全月完全一致の判定器ではない ([scripts/parity_check.sh](/mnt/c/tools/multi-agent-shogun/scripts/parity_check.sh:213))。
- before/after の「コード変更前後」比較ではなく、「本番DB vs experiments.db」比較。CoDD Phase 4 の本番最適化回帰検証に直結しない。

### 2.2 `DM-Signal/backend/scripts/snapshot_recalc_results.py`

**目的**
- recalculate 関連テーブルを JSON スナップショットとして保存し、最適化前後比較のベースラインを作る ([snapshot_recalc_results.py](/mnt/c/Python_app/DM-signal/backend/scripts/snapshot_recalc_results.py:2))。

**入力**
- CLI引数: `--output/-o` で出力先 JSON 指定 ([snapshot_recalc_results.py](/mnt/c/Python_app/DM-signal/backend/scripts/snapshot_recalc_results.py:255))
- `backend/.env` の `DATABASE_URL`。なければ localhost fallback ([snapshot_recalc_results.py](/mnt/c/Python_app/DM-signal/backend/scripts/snapshot_recalc_results.py:53))

**出力**
- JSON snapshot。`signals`, `monthly_returns`, `annual_returns`, `trade_performance`, `drawdown_periods`, `rolling_returns_summary`, `portfolio_metrics` を保存 ([snapshot_recalc_results.py](/mnt/c/Python_app/DM-signal/backend/scripts/snapshot_recalc_results.py:197))。

**使い方**
```bash
cd /mnt/c/Python_app/DM-signal/backend
python scripts/snapshot_recalc_results.py -o snapshots/baseline.json
```

**制約**
- `monthly_returns` スナップショットに `monthly_return_open` が入っていない。保存しているのは `monthly_return`, `cumulative_return`, `benchmark_return`, `benchmark_cumulative`, `in_market` のみ ([snapshot_recalc_results.py](/mnt/c/Python_app/DM-signal/backend/scripts/snapshot_recalc_results.py:83))。
- 同じく `monthly_returns.holding_signal` も保存していない ([snapshot_recalc_results.py](/mnt/c/Python_app/DM-signal/backend/scripts/snapshot_recalc_results.py:83))。
- したがって、この snapshot 単体では殿定義の「全期間 holding position + all monthly_return_open」を再現できない。

### 2.3 `DM-Signal/backend/scripts/compare_snapshots.py`

**目的**
- 2つの snapshot JSON を読み、Cronjob vs Full Recalculate 差分をテーブル単位で出す ([compare_snapshots.py](/mnt/c/Python_app/DM-signal/backend/scripts/compare_snapshots.py:2))。

**入力**
- CLI引数: `baseline`, `fullrecalc`, 任意で `--output/-o` ([compare_snapshots.py](/mnt/c/Python_app/DM-signal/backend/scripts/compare_snapshots.py:189))

**出力**
- 標準出力に summary
- 任意で詳細 JSON ([compare_snapshots.py](/mnt/c/Python_app/DM-signal/backend/scripts/compare_snapshots.py:208))

**使い方**
```bash
cd /mnt/c/Python_app/DM-signal/backend
python scripts/compare_snapshots.py snapshots/baseline.json snapshots/fullrecalc.json
python scripts/compare_snapshots.py snapshots/baseline.json snapshots/fullrecalc.json -o snapshots/diff.json
```

**制約**
- `monthly_returns` 比較項目は `monthly_return`, `cumulative_return`, `benchmark_return`, `benchmark_cumulative`, `in_market`, `holding_signal` で、`monthly_return_open` を比較していない ([compare_snapshots.py](/mnt/c/Python_app/DM-signal/backend/scripts/compare_snapshots.py:96))。
- しかも upstream の snapshot 側が `monthly_returns.holding_signal` を保存していないため、`holding_signal` 比較設定は実質空振りになる ([snapshot_recalc_results.py](/mnt/c/Python_app/DM-signal/backend/scripts/snapshot_recalc_results.py:83), [compare_snapshots.py](/mnt/c/Python_app/DM-signal/backend/scripts/compare_snapshots.py:98))。
- float 比較は 6桁丸め (`round(..., 6)`) で行う ([compare_snapshots.py](/mnt/c/Python_app/DM-signal/backend/scripts/compare_snapshots.py:25))。殿定義の厳格比較より緩い。

## §3 fullrecalculate dry-run 調査

### 3.1 `/admin/recalculate-sync`

- 公開パラメータは `start_date`, `portfolio_id`, `include_nested_fof`, `include_parent_fof`, `mode` のみ ([etl_trigger.py](/mnt/c/Python_app/DM-signal/backend/app/api/etl_trigger.py:285))。
- `dry_run` は存在しない。
- endpoint はバックグラウンドで `_recalculate_sync_background()` を起動し、そのまま `recalculate_history_fast(...)` を実行する ([etl_trigger.py](/mnt/c/Python_app/DM-signal/backend/app/api/etl_trigger.py:355), [etl_trigger.py](/mnt/c/Python_app/DM-signal/backend/app/api/etl_trigger.py:375))。

### 3.2 `recalculate_history_fast()`

- 関数シグネチャは `start_date`, `end_date`, `batch_size`, `portfolio_ids`, `include_nested_fof`, `include_parent_fof`, `mode` のみ ([recalculate_fast.py](/mnt/c/Python_app/DM-signal/backend/app/jobs/recalculate_fast.py:1228))。
- `dry_run` / `write=False` / `rollback_only` の類は存在しない。

### 3.3 結論

- CoDD設計書 §3/§4 の「Step 10.5: dry run(計算のみ・書込みなし)」をそのまま実行する現物経路は未実装。
- 現時点で fullrecalculate の検証は「実書き込み後に差分検証」前提であり、書込み前 dry-run 防御層は空白。

## §4 殿定義との照合

殿定義:
- 一致 = **全期間の保有ポジション完全一致**
- かつ **全期間の monthly return 完全一致**

現物との差分:
- `parity_check.sh`
  - before/after 比較ではない
  - `monthly_return_open` を見ない
  - holding position を FoF完全形では見ない
- `snapshot_recalc_results.py` + `compare_snapshots.py`
  - before/after 比較には使える
  - ただし `monthly_return_open` と月次 `holding_signal` が抜けている
  - 丸め 6桁で厳密性が不足

結論:
- **既存3本だけでは殿定義を満たせない。**

## §5 補助的に使える既存ツール

### 5.1 `scripts/analysis/grid_search/verify_all_portfolios.py`

- active **standard** PF を production DB から読み、GSシミュレーションと `monthly_return_open` + `holding_signal` を比較する ([verify_all_portfolios.py](/mnt/c/Python_app/DM-signal/scripts/analysis/grid_search/verify_all_portfolios.py:75))。
- `--numpy-fast` 切替あり ([verify_all_portfolios.py](/mnt/c/Python_app/DM-signal/scripts/analysis/grid_search/verify_all_portfolios.py:226))。
- ただし対象は `type='standard'` のみ ([verify_all_portfolios.py](/mnt/c/Python_app/DM-signal/scripts/analysis/grid_search/verify_all_portfolios.py:258))、FoFや fullrecalculate before/after 比較には直結しない。
- return tolerance は `0.0001` で、殿定義より緩い ([verify_all_portfolios.py](/mnt/c/Python_app/DM-signal/scripts/analysis/grid_search/verify_all_portfolios.py:203))。

### 5.2 `dump_all_pf_golden.py`

- 本番 PostgreSQL から全 active PF の `monthly_return_open` + `holding_signal` を JSON dump する ([dump_all_pf_golden.py](/mnt/c/Python_app/DM-signal/scripts/analysis/grid_search/dump_all_pf_golden.py:2))。
- フィールドは殿定義に近い ([dump_all_pf_golden.py](/mnt/c/Python_app/DM-signal/scripts/analysis/grid_search/dump_all_pf_golden.py:46))。
- ただし compare 側がない。生成だけで終わる。

### 5.3 `dump_all_pf_holding_signals_golden.py`

- latest month の `holding_signal` だけを dump する ([dump_all_pf_holding_signals_golden.py](/mnt/c/Python_app/DM-signal/scripts/analysis/grid_search/dump_all_pf_holding_signals_golden.py:2))。
- 全期間比較には足りない。

## §6 CoDD Phase 4 向け提案

### 6.1 既存ツールだけで当面回す最善手

1. before: `dump_all_pf_golden.py` で全PFの `monthly_return_open` + `holding_signal` baseline を作る。
2. deploy + `recalculate-sync` 実行。
3. after: 同じ dump を再生成。
4. 新規 comparator で全期間比較する。
5. 補助として `snapshot_recalc_results.py` + `compare_snapshots.py` を回し、周辺テーブル回帰も拾う。

理由:
- 殿定義に最も近い既存出力は `dump_all_pf_golden.py` 側だから。
- `parity_check.sh` は Phase 4 主判定器ではなく、spot check 補助に下げるのが妥当。

### 6.2 新規実装案（推奨）

**案A: `snapshot_recalc_results.py` / `compare_snapshots.py` の拡張**

- `snapshot_monthly_returns()` に以下を追加
  - `monthly_return_open`
  - `cumulative_return_open`
  - `holding_signal`
- `compare_snapshots.py` の `monthly_returns.compare_fields` を Open 系中心へ更新
- 6桁丸めを廃止し、`monthly_return_open` は `abs(diff) < 1e-6`、`holding_signal` は exact compare
- optional で `--portfolio-id` / `--portfolio-type` を追加し、fullrecalculate改善対象だけ狙えるようにする

**案B: 専用 comparator 新設**

- 例: `backend/scripts/verify_fullrecalc_parity.py`
- 入力:
  - baseline JSON (`dump_all_pf_golden.py` 形式)
  - after JSON
- 判定:
  - `portfolio_id + year_month` 単位で `monthly_return_open`
  - 同キーで `holding_signal`
  - record add/remove も FAIL
- 長所: 殿定義を最短で表現できる
- 短所: snapshot 系と機能重複

**推奨判断**
- 既存資産を活かすなら **案A**
- 最短で安全 gate を作るなら **案B**

## §7 `codd_dmsignal_python_strategy.md` §5 への反映案

現在の §5 は `parity_check.sh` をレベルB必須としている ([codd_dmsignal_python_strategy.md](/mnt/c/tools/multi-agent-shogun/docs/research/codd_dmsignal_python_strategy.md:176)) が、現物仕様と殿定義が合っていない。

反映案:

```md
| 防御 | レベルA | レベルB |
|------|---------|---------|
| PI整合確認 | AC推奨 | AC必須 |
| 既存テスト全PASS | AC必須 | AC必須 |
| baseline dump (`monthly_return_open` + `holding_signal`) | 不要 | AC必須(before) |
| before/after parity compare (全期間) | 不要 | AC必須(after) |
| snapshot compare (周辺テーブル回帰) | 任意 | AC推奨 |
| fullrecalculate後の再確認 | 不要 | AC必須 |
| 本番deploy | 不要 | 直列配備(DB排他ルール) |
```

補足:
- `parity_check.sh` は補助道具へ格下げ
- Step 10.5 の dry-run は「未実装」と明記
- dry-run が必要なら新規 shadow validator / snapshot comparator 実装を Phase 4 着手条件にする

## §8 最終判断

- 現在ある3本は「完全に無価値」ではない。
- しかし **Phase 4 の本番防御層を `parity_check.sh` 一発で済ませる設計は危うい**。
- 着手前に最低限必要なのは:
  - `monthly_return_open` と月次 `holding_signal` を全期間比較できる before/after comparator
  - dry-run 未実装の明文化
  - snapshot 比較は補助、主判定は殿定義準拠へ移すこと
