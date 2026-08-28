---
name: gs-bench-gate
description: |
  【忍者専用】将軍・家老・軍師は使用禁止。忍者以外が呼んだ場合は即座に中断せよ。
  GS共通コード変更時のパフォーマンス回帰検出ゲート。
  Phase before(ベースライン計測)とPhase after(変更後計測+比較+判定)の2段階。
  REGRESSIONならrevert→家老報告→作業停止。
  TRIGGER: /gs-bench-gate、GS共通コード変更前後のベンチマーク project:dm-signal、パフォーマンス回帰チェック project:dm-signal、gs_benchmark実行 project:dm-signal
  DO NOT TRIGGER: ベンチマーク結果の閲覧・分析（→outputs/analysis/直接参照）、
  忍法個別のデバッグ（→run_077_*.py直接実行）、グリッドサーチ実行（→run_077_*.py）、
  パラメータ過適合判定（→shogun-param-neighbor-check）
quality_metric: "当該スキル使用タスクのWA不発生率（logs/karo_workarounds.yamlにGSベンチ判定手順起因のworkaroundが記録されない割合）"
allowed_projects: [dm-signal]
allowed-tools:
  - Bash
  - Read
argument-hint: "before|after [--ninjutsu kasoku_diff|kasoku_ratio|nukimi|oikaze|kawarimi|yotsume|bunshin] [--patterns N]"
---

# /gs-bench-gate — GSパフォーマンス回帰検出ゲート

## 概要

GS共通コード（gs_shared*.py, pipeline/blocks/*.py, gs_runner.py, gs_data_loader.py,
gs_numba_kernels.py, /mnt/c/Python_app/DM-signal/scripts/analysis/grid_search/gs_benchmark.py）を変更する際に、パフォーマンス回帰を自動検出する。
コード変更の前後でベンチマークを実行し、ms/patの悪化率で判定する。

## 共通ファイルリスト（変更検出対象）

以下のglob patternに該当するファイルが変更された場合、本ゲートの実行が必要:

```
scripts/analysis/grid_search/gs_shared*.py
scripts/analysis/grid_search/pipeline/blocks/*.py
scripts/analysis/grid_search/gs_runner.py
scripts/analysis/grid_search/gs_data_loader.py
scripts/analysis/grid_search/gs_numba_kernels.py
/mnt/c/Python_app/DM-signal/scripts/analysis/grid_search/gs_benchmark.py
```

## Phase before（ベースライン計測）

引数: `/gs-bench-gate before [--ninjutsu NAME] [--patterns N]`

### 手順

1. **git diff検証**: 作業ツリーに未コミットの変更がないか確認

   ```bash
   cd /mnt/c/Python_app/DM-signal
   git diff --stat
   git diff --cached --stat
   ```

   - 共通ファイルに未コミットの変更がある場合: WARN表示。「変更前のベースラインを取るには、
     変更をstashするか、変更前の状態でbeforeを実行してください」と報告して停止。
   - 共通ファイル以外の変更のみ: 続行可。

2. **対象忍法の決定**:
   - `--ninjutsu` 指定あり: その忍法のみ
   - 指定なし: git diffで変更された共通ファイルから影響を受ける忍法を推定。
     推定不能なら全7忍法(kasoku_diff, kasoku_ratio, nukimi, oikaze, kawarimi, yotsume, bunshin)

3. **ベンチマーク実行**: 各対象忍法について

   ```bash
   cd /mnt/c/Python_app/DM-signal
   python /mnt/c/Python_app/DM-signal/scripts/analysis/grid_search/gs_benchmark.py \
     --ninjutsu {name} \
     --patterns {N:default 150} \
     --skip-ppe \
     --output outputs/analysis/gs_gate_before_{name}.json
   ```

   - `--skip-ppe` はbeforeでは常時有効（serial/serial-batchのみ計測、高速化のため）
   - パターン数のデフォルトは150（gs_benchmark.pyのデフォルトに従う）

4. **baseline JSON保存確認**:
   各忍法の `outputs/analysis/gs_gate_before_{name}.json` が生成されたことを確認。
   生成されなかった場合はERROR報告して停止。

5. **完了報告**:
   ```
   [gs-bench-gate before] DONE
   忍法: {name1}({ms_per_pat}ms/pat), {name2}({ms_per_pat}ms/pat), ...
   baseline JSON: outputs/analysis/gs_gate_before_{name}.json
   ```

## Phase after（変更後計測+比較+判定）

引数: `/gs-bench-gate after [--ninjutsu NAME] [--patterns N] [--threshold PCT]`

### 手順

1. **before JSON存在確認**:
   `outputs/analysis/gs_gate_before_{name}.json` が存在するか確認。

   - 存在しない場合: ERROR。「Phase beforeを先に実行してください」と報告して停止。

2. **共通コード変更検出**:

   ```bash
   cd /mnt/c/Python_app/DM-signal
   git diff --name-only HEAD
   ```

   共通ファイルリスト（上記参照）に該当する変更があるか確認。
   - 該当なし: 「共通コードに変更なし。ベンチマーク不要。」と報告してPASS終了。
   - 該当あり: 変更ファイル一覧を表示して続行。

3. **ベンチマーク実行**: 各対象忍法について

   ```bash
   cd /mnt/c/Python_app/DM-signal
   python /mnt/c/Python_app/DM-signal/scripts/analysis/grid_search/gs_benchmark.py \
     --ninjutsu {name} \
     --patterns {N:default 150} \
     --skip-ppe \
     --output outputs/analysis/gs_gate_after_{name}.json
   ```

4. **比較判定**: 各忍法について before vs after を比較

   比較対象メトリクス: `results.serial.ms_per_pattern`（serial-batchが存在すれば併記）

   ```
   delta_pct = (after_ms - before_ms) / before_ms * 100
   ```

   判定基準（`--threshold` で変更可、デフォルト10%）:
   - `delta_pct <= threshold`: **PASS** — 回帰なし
   - `delta_pct > threshold`: **REGRESSION** — 回帰検出

5. **結果出力**:

   PASS時:
   ```
   [gs-bench-gate after] PASS
   忍法      | before(ms/pat) | after(ms/pat) | delta
   ----------|----------------|---------------|------
   kasoku    | 0.809          | 0.795         | -1.7%
   nukimi    | 0.306          | 0.310         | +1.3%
   判定: 全忍法PASS（閾値: 10%）
   ```

   REGRESSION時: → 下記「REGRESSION時の手順」に従う。

## REGRESSION時の手順

パフォーマンス回帰が検出された場合、以下を**順番に**実行する:

### 1. revert（変更の巻き戻し）

```bash
cd /mnt/c/Python_app/DM-signal
git stash
```

- `git stash` で変更を退避（`git reset --hard` は使わない — Tier 1禁止）
- stash後、ベースライン状態に戻ったことを確認

### 2. 家老報告

```bash
bash "$SHOGUN_ROOT/scripts/inbox_write.sh" karo \
  "{ninja_name}、gs-bench-gate REGRESSION検出。{ninjutsu}: before={before_ms}ms/pat → after={after_ms}ms/pat (+{delta_pct}%)。変更をstashで退避済み。対処指示を待つ。" \
  report_received {ninja_name}
```

### 3. 作業停止

REGRESSION報告後は作業を停止し、家老からの指示を待つ。
自己判断で修正を試みてはならない。

## 注意事項

- **venv**: DM-Signalの仮想環境がactivateされている前提。
  未activate時は `source /mnt/c/Python_app/DM-signal/.venv/bin/activate` を先に実行。
- **DB接続**: gs_benchmark.pyはPostgreSQLへの接続が必要。
  `DATABASE_URL` 環境変数または `backend/.env` に設定されている前提。
- **計測ノイズ**: WSL2環境ではI/Oジッターが大きい。
  閾値10%はこのノイズを考慮した値。必要に応じて `--threshold` で調整可。
- **PPEスキップ**: ゲート判定ではserial/serial-batchのみ使用。
  PPEはプロセス起動オーバーヘッドが支配的で、小サンプルでは回帰検出に不適。
- **before/after JSONのクリーンアップ**: ゲートPASS後、
  `gs_gate_before_*.json` と `gs_gate_after_*.json` は手動で削除可。
  gitignore対象の `outputs/` 配下のため、コミットされない。
