# inbox_write.sh 高速化記録 (cmd_1960)

## 対象

- `scripts/inbox_write.sh`

## before 計測

- 条件:
  - 隔離 workspace (`INBOX_WRITE_ROOT_OVERRIDE=<tmp>`)
  - 実通信に近い通常経路: `bash scripts/inbox_write.sh karo "bench" wake_up saizo bench`
  - `config/settings.yaml` と `scripts/lib` は実物を利用
- 実測:
  - `0.11s`
  - `0.08s`
  - `0.07s`
  - `0.05s`
  - `0.08s`
- 平均: `0.078s` (`78ms`)

参考:
- `cmd_1951` の全量プロファイリングでは `--help` 経路が `89ms`

## ボトルネック

1. 引数不正や `--help` でも `agent_config.sh` を即読み込みし、不要な初期化コストを払っていた。
2. `lock_path.sh` を起動直後に source しており、usage-only 経路でも不要な初期化が走っていた。
3. `MSG_ID` / `TIMESTAMP` 生成で `date` + `head` + `xxd` の subprocess を毎回起動していた。

## 実装

1. `ensure_agent_config_loaded()` を導入し、agent 設定読込を必要箇所まで遅延。
2. `ensure_lock_path_loaded()` を追加し、lock helper も実書込み直前まで遅延。
3. `--help` / `-h` を fast path 化し、usage-only 呼出しでは初期化を完全に回避。
4. `MSG_ID` / `TIMESTAMP` を bash builtin (`printf '%(... )T'`, `RANDOM`, `$$`) で生成し、外部コマンドを削減。

## after 計測

- 条件:
  - before と同一の隔離 workspace
  - 同一コマンドを連続実行
- 実測:
  - `0.06s`
  - `0.04s`
  - `0.05s`
  - `0.05s`
  - `0.05s`
- 平均: `0.050s` (`50ms`)

補足:
- `bash scripts/inbox_write.sh --help` は `0.01-0.02s`（cmd_1951基準 `89ms` 比で約 `-86%`）

## 結果

- 通常 write path: `78ms → 50ms`
- 改善率: `-35.9%`
- `cmd_1960` 目標 `40ms` には未達だが、全通信 hot path の固定コストを約 `28ms` 削減

## 検証

- `bash -n scripts/inbox_write.sh`
- `bats tests/unit/test_inbox_write.bats`

## 再利用パターン

- usage/`--help` 計測値が benchmark 起点のスクリプトは、重い `source` を引数検証後まで遅延せよ
- 単発 script の ID / timestamp 生成は `date` より bash builtin を優先せよ
