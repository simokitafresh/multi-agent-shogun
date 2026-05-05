# cmd_publish.sh リファクタリング CoDD Spec

## 問題（ボトルネック関数+計測値）

対象: `scripts/cmd_publish.sh`

`count_cmd_save_blocks_for_cmd()` が pre-flight ごとに `python3` を起動して `logs/cmd_design_quality.yaml` を読む。`test_cmd_publish_preflight.bats` は5テストすべてで `cmd_publish.sh` を起動するため、Python startup が累積する。

## 定量プロファイル（実測）

Before計測（2026-05-06, kagemaru, `bats tests/unit/test_cmd_publish_preflight.bats`）:

| run | elapsed |
|---|---:|
| initial | 0.779s |
| 1 | 0.658s |
| 2 | 0.698s |
| 3 | 0.714s |
| 4 | 0.625s |
| 5 | 0.692s |

I/O/外部プロセス候補:

| pattern | count |
|---|---:|
| `_yaml_field_get_in_block` | 2 |
| `yaml_field_set` | 3 |
| `python3` | 1 |
| `grep` | 3 |

missing queue fast-fail path: 0.015-0.018s。通常テストとの差分は pre-flight と stub 経路。

## リファクタリング対象

### R1: `count_active_shogun_lessons()` を awk count に置換

`grep -c '^- id:' file || echo 0` は0件時に `0\n0` を返す既知パターン。`awk` で常に単一整数を返す。

期待効果: 正確性改善。速度影響は小。

### R2: `count_cmd_save_blocks_for_cmd()` を Python YAML parse から awk block scanner に置換

`entries:` 配下の `- cmd_id: ...` entry blockごとに `cmd_id`, `gate_result`, `source` を走査し、`cmd_id == target`, `gate_result == BLOCK`, `source == cmd_save` の件数を数える。

期待効果: Python startup 削減。テスト全量で数百ms削減見込み。

## 実施順序

1. R1実装
2. `bats tests/unit/test_cmd_publish_preflight.bats`
3. R2実装
4. `bats tests/unit/test_cmd_publish_preflight.bats`
5. before/after比較
6. after設計書を `docs/research/` に保存

## 制約

- `cmd_publish.sh` の外部I/O契約は維持する。
- `cmd_save.sh` 実行前に pre-flight BLOCK する順序を維持する。
- `on_hold` は `cmd_save.sh` 成功まで保持する。
- YAML運用ファイルの書込みは既存 `yaml_field_set` 経路を維持する。
