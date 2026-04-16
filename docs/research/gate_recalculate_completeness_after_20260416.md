# gate_recalculate_completeness.sh After 計測 (2026-04-16)

## 要約

- 対象: `scripts/gates/gate_recalculate_completeness.sh`
- before: `7.40s`, しかも `.env` の `\r` 混入で `database "dm_signal\r" does not exist` 失敗
- after: `2.74s` (`PASS`)
- 改善率: `-63.0%`

## 根因

1. `.env` 読み取りが `grep | sed` のままで、CRLF環境だと `DATABASE_URL` 末尾に `\r` が残る
2. SQLAlchemy起動 + 複数クエリ往復で、接続以外の固定費が無駄に大きい
3. Render Postgres への接続自体が支配的で、特に host解決/接続経路の影響が大きい

## 実装内容

- `.env` 読み取りを `awk` に置換し、`DATABASE_URL` の末尾 `\r` を除去
- `SQLAlchemy` をやめて `psycopg2` 直結へ変更
- `signals` / `monthly_returns` / `fof_component_weights` の確認を単一SQLへ統合
- `getent ahostsv4` ベースの `hostaddr` 解決 + `/tmp/gate_recalculate_completeness_hostaddr.cache` で再利用
- `GATE_RECALCULATE_LIB_ONLY` を追加し、helper関数の unit test を可能化

## 計測ログ

### Before

```text
elapsed=7.40 user=0.29 sys=0.09 maxrss=49296
ERROR: (psycopg2.OperationalError) ... database "dm_signal\r" does not exist
```

### After

```text
Active portfolios: 181 (standard=77, fof=104)
PASS: All 181 portfolios have signals
PASS: All 181 portfolios have monthly_returns
PASS: All 104 FoFs have component_weights
=== VERDICT: PASS — All data complete ===
elapsed=2.74 user=0.06 sys=0.02 maxrss=26624
```

## テスト

- `bats tests/unit/test_gate_recalculate_completeness.bats`
- `bash -n scripts/gates/gate_recalculate_completeness.sh`
- 実機確認: `bash scripts/gates/gate_recalculate_completeness.sh`

## 残課題

- 支配的ボトルネックは依然として Render Postgres へのリモート接続
- 現状でも `2.7s` 級で、目標 `500ms` には未達
- ここから先はスクリプト内最適化より、接続経路の固定化/常駐化/近接実行の設計改善が主対象
