# cmd_1974 post_recalculate_checks.sh 高速化 spec

## 1. before

- profiling SSOT: `docs/research/codd_infra_script_profiling.md`
- measured: `scripts/post_recalculate_checks.sh` = `5489ms` (`timeout`, cmd_1951)
- local repro:
  - `bash scripts/post_recalculate_checks.sh` = `6.154s`
  - 失敗内容: `.env` が CRLF のため `DATABASE_URL` 末尾に `\r` が混入し、`database "dm_signal\r" does not exist`

## 2. bottleneck

1. `.env` 読み取りが `grep|cut` で CRLF 非対応。接続前に DSN が壊れ、失敗時でも 6 秒級の接続待ちを踏む。
2. `psycopg2.connect()` がホスト名解決込みだと初回 `5.866s` から `10.803s` と大きくぶれる。`hostaddr` 指定時は `0.707s` まで短縮できた。
3. Python 本体が `portfolio` ごとに `monthly_returns` / `MAX(date)` / `holding_signal` を個別クエリし、181 PF環境で N+1 になっている。

## 3. optimization candidates

1. robust env loader:
   - `awk` 1回で `DATABASE_URL=` を取得し `\r` を除去
   - `DATABASE_URL` 環境変数優先 + `POST_RECALCULATE_CHECKS_LIB_ONLY=1` で単体テスト可能化
2. hostaddr-assisted connect:
   - `urlparse` + `socket.gethostbyname()` で IPv4 を解決し、`psycopg2.connect(..., hostaddr=...)`
   - 失敗時は plain connect にフォールバックして動作維持
3. batch query refactor:
   - `portfolios` 1回取得
   - `monthly_returns` を全件 1回取得して `portfolio_id` ごとにグループ化
   - `signals` は `MAX(date)` join で最新行のみ取得し、最新日付と `holding_signal` を共用

## 4. chosen changes

- 採用: 1, 2, 3
- 非採用:
  - DB schema/index 変更: infra script 高速化の範囲外
  - 接続プール常駐化: 単発スクリプトで運用複雑性に対して見返りが小さい

## 5. results

- before: `6.154s` (CRLF混入で接続失敗)
- after: `2.225s` (同一DB/同一データ、出力ロジック維持)
- 改善率: `-63.9%` (`3.1x`)
- 追加観測:
  - `connect()` plain = `10.803s`
  - `connect(hostaddr=resolved_ipv4)` = `0.707s`
  - query timings: `portfolios 0.483s`, `monthly_returns 0.317s`, `latest_signals join 0.359s`
- 備考: 目標 `500ms` には未達。残差の主因は remote PostgreSQL 接続と本番データ読み出しコストで、スクリプト内ロジック由来の無駄は主に除去済み。

## 6. verification

- `bash -n scripts/post_recalculate_checks.sh`
- `bats tests/unit/test_post_recalculate_checks.bats`
- `bats tests/unit/test_parity_check.bats`
- `bash scripts/affected_tests.sh scripts/post_recalculate_checks.sh tests/unit/test_post_recalculate_checks.bats`

