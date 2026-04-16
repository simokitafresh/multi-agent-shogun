# cmd_1972 parity_check.sh 高速化 spec

## 1. before

- profiling SSOT: `docs/research/codd_infra_script_profiling.md`
- measured: `scripts/parity_check.sh --help` = `5495ms` (`timeout`, cmd_1951)
- local repro:
  - `bash scripts/parity_check.sh --help` = `6.05s`
  - 失敗内容: `database "dm_signal\r" does not exist`
  - stripped `psycopg2.connect(DATABASE_URL)` 初回 = `5.754s`, 2回目以降 = `1.195s / 0.779s`

## 2. bottleneck

1. `--help` でも usage fast-path がなく、本処理へ進み Python 起動 + Render PostgreSQL 接続まで到達する。
2. `.env` が CRLF でも `grep|cut` のまま `DATABASE_URL` を読むため、末尾 `\r` が残り DB 名誤認を起こす。

## 3. optimization candidates

1. shell fast-path:
   - `-h/--help` は shell だけで usage を返して即終了
   - 効果見込み: `~6s → <50ms`
2. robust env parsing:
   - `awk` で `DATABASE_URL=` を 1回で取得し `\r` を除去
   - 効果: `.env` CRLF でも誤接続を防止、`set -euo pipefail` 下の `grep` no-match 罠も回避
3. testability without behavior drift:
   - default path は維持しつつ `DM_SIGNAL_PATH/ENV_PATH/EXPERIMENTS_DB` override と `PARITY_CHECK_LIB_ONLY=1` を追加
   - 効果: helper 単体テスト可能、実運用 path は不変

## 4. chosen changes

- 採用: 1, 2, 3
- 非採用:
  - DB query 一本化や SQL 最適化: profiler の `--help` timeout には効かない
  - 接続プーリング/hostaddr cache: 単発スクリプトでは効果が限定的で scope 過大

## 5. acceptance mapping

- AC1: 本 spec に bottleneck + candidate 3本を記録
- AC2: `scripts/parity_check.sh` に fast-path + CRLF-safe loader 実装
- AC3: `--help` 実測で before/after を記録
- AC4: unit test追加 + `bats --jobs 4 tests/unit/test_parity_check.bats`
