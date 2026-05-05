# test_select.sh リファクタリング CoDD Spec

## 問題（ボトルネック関数+計測値）

`scripts/test_select.sh` は変更ファイルから関連 bats を選ぶ 191 行の差分 aware test selector。
Phase 1 before 計測では、入力 1 ファイルでも毎回約 10-12 秒かかっている。

主因は L2 の静的解析で、各 test file の `source|bash|.` 参照ごとに `find "$REPO_ROOT/scripts" "$REPO_ROOT/lib" -name "$script_base"` を実行していたこと。
現行リポジトリでは `tests/unit/test_*.bats` が 163 件、テスト内 shell 参照が 299 件、`scripts/lib` 配下 shell が 232 件ある。

## 定量プロファイル（実測 before）

計測環境: `/mnt/c/tools/multi-agent-shogun`, WSL2, 2026-05-06。
各ケース 5 回実行し、`date +%s%N` 差分で ms 計測。

| 入力 | stdout行数 | stderr行数 | before平均 |
|------|------------|------------|------------|
| `scripts/deploy_task.sh` | 15 | 1 | 11827ms |
| `scripts/gates/gate_report_format.sh` | 25 | 1 | 10184ms |
| `scripts/test_select.sh` | 1 | 1 | 10014ms |
| `tests/unit/test_yaml_field_set.bats` | 1 | 1 | 10602ms |
| `README.md` | 0 | 2 | 10120ms |

構造カウント:

| 指標 | 値 |
|------|----|
| `tests/unit/test_*.bats` | 163 |
| テスト内 `source|bash|.` shell参照 | 299 |
| `scripts/lib` shell ファイル | 232 |
| `scripts/test_select.sh` 内 `find` 呼び出し | 2 |
| `scripts/test_select.sh` 内 `grep` 呼び出し | 2 |

## リファクタリング対象

R1: `scripts/lib` の shell ファイルを 1 回だけ `find` し、basename → relative path の bash associative array を構築する。
期待効果: 299 回規模の `find` を 1 回に削減し、WSL2 `/mnt/c` 上のファイル走査コストを削る。

R2: focused regression test `tests/unit/test_test_select.bats` を追加する。
期待効果: selector 自身の変更、gate script 変更、未知ファイル WARN の既存契約を固定する。

## 実施順序

1. before 計測を spec に保存。
2. R1 を実装。
3. `bash scripts/test_select.sh scripts/test_select.sh` で出力確認。
4. `bats tests/unit/test_test_select.bats` を実行。
5. before/after 比較表を報告 YAML に記録。
6. after 設計書を `docs/research/` に保存。

## 制約

- 出力契約は維持する: stdout は test file 1 行 1 件、stderr は WARN/INFO。
- 未知ファイルは WARN して exit 0。フォールバック全テスト実行はしない。
- `scripts/gates/*`, `deploy_task.sh`, `cmd_complete_gate.sh`, `cmd_save.sh`, `report_field_set.sh` の特別扱いは変更しない。
- 処理対象を代表点へ縮小しない。既存の全 `tests/unit/test_*.bats` と全 `scripts/lib` shell を対象にする。
