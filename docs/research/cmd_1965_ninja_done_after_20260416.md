# ninja_done.sh CoDD Spec + After Report (2026-04-16)

- cmd: cmd_1965
- 実施者: hayate
- CoDD Phase到達: Phase 5(before/after計測+実装+検証)。specは事後作成

## 対象

- `scripts/ninja_done.sh`

## before 計測

- 条件A: profiling互換の usage path
  - コマンド: `/usr/bin/time -f "%e" bash scripts/ninja_done.sh`
  - 実測: `0.02s`, `0.02s`, `0.03s`, `0.02s`, `0.02s`
  - 平均: `0.022s` (`22ms`)
  - 参考: `cmd_1951` 全量プロファイリングでは `68ms`
- 条件B: 実運用に近い success path
  - コマンド: `INBOX_WRITE_ROOT_OVERRIDE=<tmp> bash scripts/ninja_done.sh hayate cmd_1946`
  - 報告ファイル: `queue/archive/reports/hayate_report_cmd_1946_20260416.yaml`
  - 実測: `0.29s`, `0.23s`, `0.22s`, `0.20s`, `0.20s`
  - 平均: `0.228s` (`228ms`)

## ボトルネック

1. `field_get.sh` を起動直後に source しており、usage/help でも固定コストを払っていた。
2. `summary_is_present()` が `field_get + tr + sed` に依存し、success pathでも不要な subprocess が多かった。
3. success path の主要コストは `gate_report_format.sh` (`40-50ms`) と `inbox_write.sh` (`90-150ms`) で、`ninja_done.sh` 本体は前処理を極小化する必要があった。

## 実装

1. `field_get.sh` の常時 source を削除。
2. `summary_is_present()` を awk 1回の軽量パーサへ置換。
   - inline summary
   - quoted empty summary
   - block scalar (`>`, `>-`, `|`, `|-`)
   を判定対象に含めた。
3. `--help` / `-h` を fast path 化し、usage-only 経路では gate/inbox 初期化に触れないようにした。
4. `tests/unit/test_ninja_done.bats` を追加し、以下を固定した。
   - help path
   - 引数不足
   - 空 summary の拒否
   - archived report の block summary 受理
   - gate fail 時の通知抑止

## after 計測

- 条件A: usage path
  - コマンド: `/usr/bin/time -f "%e" bash scripts/ninja_done.sh`
  - 実測: `0.01s`, `0.00s`, `0.00s`, `0.00s`, `0.00s`
  - 平均: `0.002s` (`2ms`)
- 条件A-2: help path
  - コマンド: `/usr/bin/time -f "%e" bash scripts/ninja_done.sh --help`
  - 実測: `0.01s`, `0.00s`, `0.00s`, `0.00s`, `0.01s`
  - 平均: `0.004s` (`4ms`)
- 条件B: success path
  - コマンド: `INBOX_WRITE_ROOT_OVERRIDE=<tmp> bash scripts/ninja_done.sh hayate cmd_1946`
  - 実測: `0.18s`, `0.15s`, `0.16s`, `0.18s`, `0.17s`
  - 平均: `0.168s` (`168ms`)

## 結果

- usage path: `22ms → 2ms` (`-90.9%`)
- help path: `22ms相当 → 4ms`
- success path: `228ms → 168ms` (`-26.3%`)
- profiling目標 `30ms` は usage/help 経路で達成。success path は gate と inbox_write が支配的で、次の主戦場は `ninja_done.sh` ではなく下流2本。

## 検証

- `bash -n scripts/ninja_done.sh`
- `bats tests/unit/test_ninja_done.bats`
