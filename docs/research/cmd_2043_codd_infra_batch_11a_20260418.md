# cmd_2043: CoDD Infra Batch 11-A (2026-04-18)

## Summary

- Target:
  - `scripts/lesson_harvest.sh`
  - `scripts/post_recalculate_checks.sh`
  - `scripts/model_switch_preflight.sh`
- Goal: 既存 CoDD 高速化の再改善。WSL2 `/mnt/c` 上で支配的な full YAML load / 余分な DB round-trip / 二重 grep を削る。

## Results

| Script | Task Baseline | Live Before | After | Change |
|--------|---------------|-------------|-------|--------|
| `scripts/lesson_harvest.sh` | `10.57s` | `5.57s` median (3 runs) | `3.55s` median (3 runs) | lessons 台帳読込を `yaml.safe_load` 全件から `rg` title抽出へ置換 |
| `scripts/post_recalculate_checks.sh` | `2.23s` | `2.50s` median (3 runs) | `2.15s` median (3 runs) | `monthly_returns` / `signals` を一括集計クエリへ統合 |
| `scripts/model_switch_preflight.sh` | `1.23s` | `0.45s` median (3 runs) | `0.34s` median (3 runs) | hardcode scan を `rg --glob` 1本へ寄せて二重 grep を除去 |

## Implementation

### `scripts/lesson_harvest.sh`

- `projects/*/lessons*.yaml` の登録済み title 収集を `rg -n '^\s+title:'` へ置換
- report archive 側の `rg` 一括走査は維持し、/mnt/c で逆効果だった candidate file 二段階化は採用しない
- `skill_candidate.found: true` を lesson と誤認しない回帰テストを追加

### `scripts/post_recalculate_checks.sh`

- `load_monthly_returns()` / `load_latest_signals()` を廃止
- `portfolios` 読込時に `monthly_stats` / `latest_signals` CTE を left join
- Python 側は `month_count`, `gap_count`, `latest_signal_date`, `latest_holding_signal` をそのまま参照

### `scripts/model_switch_preflight.sh`

- hardcode scan を `git grep | grep -Ev` から `rg --glob '!…'` へ変更
- 除外対象を glob で前段に寄せ、余分なパイプを削除

## Validation

- `bash -n scripts/lesson_harvest.sh`
- `bash -n scripts/post_recalculate_checks.sh`
- `bash -n scripts/model_switch_preflight.sh`
- `bats tests/unit/test_lesson_harvest.bats tests/unit/test_post_recalculate_checks.bats`
- Bench:
  - `for i in 1 2 3; do /usr/bin/time -f 'lesson_harvest %e' bash scripts/lesson_harvest.sh >/tmp/lesson_harvest.after2.$i; done`
  - `for i in 1 2 3; do /usr/bin/time -f 'post_recalculate %e' bash scripts/post_recalculate_checks.sh >/tmp/post_recalculate.final.$i; done`
  - `for i in 1 2 3; do /usr/bin/time -f 'model_switch %e' bash scripts/model_switch_preflight.sh hayate >/tmp/model_switch_preflight.final2.$i; done`
