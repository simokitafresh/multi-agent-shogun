# report_field_set.sh CoDD Spec + After Report (cmd_1966)

- cmd: `cmd_1966`
- 実施者: `saizo`
- CoDD Phase到達: `Phase 5` (before/after計測+実装+検証)。specは事後作成 (`2026-04-16`)

## 対象

- `scripts/report_field_set.sh`

## before 計測

- 条件:
  - 実テンプレート相当の報告 YAML を使用
  - 忍者 hot path に近い scalar 更新を測定
  - コマンド:
    - `bash scripts/report_field_set.sh <report> status test`
    - `bash scripts/report_field_set.sh <report> result.summary test`
- 実測:
  - `status`: `0.05s`, `0.06s`, `0.07s`, `0.08s`, `0.07s`
  - `result.summary`: `0.08s`, `0.06s`, `0.07s`, `0.08s`, `0.06s`
- 平均:
  - `status`: `0.066s` (`66ms`)
  - `result.summary`: `0.070s` (`70ms`)

参考:
- `cmd_1951` 全量プロファイリングでは `scripts/report_field_set.sh` が `40ms` / `73回` の A ランク hot path と記録済み
  - `docs/research/codd_infra_script_profiling.md`

## ボトルネック

1. `yaml_field_set.sh` と `lock_path.sh` を毎回即 `source` しており、simple scalar write でも初期化コストを払っていた。
2. `status` / `result.summary` のような単純な root/2-level 更新でも、汎用 slow path と post-read 検証を毎回通っていた。
3. retry ループで `seq`、一時ファイル生成で `mktemp` を毎回起動していた。

## リファクタ方針

1. 構造体・複数行・添字付きキーは既存の Python/slow path を維持し、simple scalar write だけ fast path 化する。
2. `yaml_field_set.sh` は slow path に入る時だけ遅延読込する。
3. retry ループと tmp path は bash builtin 中心に寄せ、外部コマンドを減らす。

## 実装

1. root / 2-level nested scalar 更新専用の awk fast path を追加。
2. `ensure_yaml_field_set_loaded()` を導入し、slow path 時のみ `yaml_field_set.sh` を `source`。
3. retry ループを `for ((...))` に変更し、tmp file を `${REPORT_PATH}.tmp.$$.$attempt` に固定。
4. fast path 成功時は slow-path 用 post-read 検証を省略し、構造更新時のみ従来検証を維持。

## after 計測

- 条件:
  - before と同一の報告 YAML
  - 同一コマンドを連続実行
- 実測:
  - `status avg=0.011s min=0.010s max=0.020s n=10`
  - `result.summary avg=0.011s min=0.010s max=0.020s n=10`

補足:
- 構造更新 path は今回の最適化対象外
  - `lessons_useful.0.reason avg=0.116s`
  - `binary_checks.AC1 avg=0.170s`

## 結果

- `status`: `66ms → 11ms` (`-83.3%`, `6.0x`)
- `result.summary`: `70ms → 11ms` (`-84.3%`, `6.4x`)
- 忍者の通常報告更新 hot path は `目標15ms` を下回り、`10-20ms` 帯へ到達

## 検証

- `bash -n scripts/report_field_set.sh`
- `bats tests/unit/test_report_field_set_validation.bats tests/unit/test_report_field_set_multiline.bats tests/unit/test_report_field_set_bc_validation.bats`
- `bats tests/test_gate_report_format.bats tests/unit/test_report_template_gate_compat.bats`

## 再利用パターン

- 構造更新と scalar 更新が混在する補助スクリプトは、scalar hot path だけを awk fast path に切り出すと効果が大きい。
- 共有ライブラリ `source` が必須でも、単純経路では遅延読込に分けると固定コストを落とせる。
- `flock` 下で tmp path が一意なら `mktemp` を省略できる。
