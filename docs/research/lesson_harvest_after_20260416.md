# lesson_harvest.sh CoDD Spec + After Report (2026-04-16)

- cmd: cmd_1971
- 実施者: hayate
- CoDD Phase到達: Phase 5(before/after計測+実装+検証)。specは事後作成

## Summary

- Target: `scripts/lesson_harvest.sh`
- Goal: アーカイブ報告から未登録 lesson_candidate を収穫する hot path の高速化
- Result: `36.34s → 10.57s` (`-70.9%`, `3.4x`)

## Before

- Reproduction command:
  - `/usr/bin/time -f "real=%e user=%U sys=%S maxrss=%M" bash scripts/lesson_harvest.sh >/dev/null`
- Observed sample:
  - `real=36.34 user=16.30 sys=1.22 maxrss=23924`
- Bottlenecks:
  - `queue/archive/reports/*.yaml` 3605件を `yaml.safe_load` で全件パース
  - `projects/*/lessons*.yaml` は少数でも、報告側のフル YAML パースが支配的
  - `/mnt/c` 上の多数小ファイル読み取りで Python YAML デコードコストが積み上がる

## Optimization Candidates

1. `rg` を一次スキャナにして、必要行だけを抽出する
2. そのまま全件 `yaml.safe_load` を続けつつ `CSafeLoader` 等へ寄せる
3. 永続キャッシュを持ち、初回だけフルスキャンする

採用:
- 1 を採用。機能を変えずに一番リスクが低く、初回実行でも効く

見送り:
- 2 は YAML パース自体が hot path なので改善幅が足りない
- 3 はキャッシュ整合性設計が追加論点になり、今回のスコープを超える

## Implementation

- `rg -uuu` を使って report archive から以下の行だけを抽出
  - `worker_id`, `task_id`, `parent_cmd`
  - `lesson_candidate`, `skill_candidate`, `decision_candidate`
  - `found`, `title`, `detail`
- report 側は軽量な行パースで候補を組み立て、以下だけ YAML フォールバック
  - block scalar (`|`, `>`)
  - 文字列化 dict/list を含む行
  - title/detail が取り切れない行
- lessons 側は少数ファイルなので従来どおり YAML で正確に登録済み title を収集
- テスト用に `LESSON_HARVEST_REPO_ROOT` などの override を追加

## After

- Reproduction command:
  - `/usr/bin/time -f "real=%e user=%U sys=%S maxrss=%M" bash scripts/lesson_harvest.sh >/dev/null`
- Observed sample:
  - `real=10.57 user=4.10 sys=1.79 maxrss=52512`
- Improvement:
  - wall clock `-70.9%`
  - CPU user time `16.30s → 4.10s`

## Validation

- `bash -n scripts/lesson_harvest.sh`
- `bats tests/unit/test_lesson_harvest.bats`
- `bash scripts/lesson_harvest.sh >/dev/null`

## Remaining Gap

- 目標 500ms には未達
- 残りは `/mnt/c` 上の archive 全件走査 I/O が支配的
- 次に詰めるなら、archive 追加分だけを見る index/cache 化が本命
