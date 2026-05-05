# test_select.sh After設計書（リファクタリング後のas-is）

## 現在の構造

対象: `scripts/test_select.sh`

| 領域 | 責務 |
|------|------|
| 変更ファイル取得 | 引数ありなら引数、なしなら staged+unstaged diff を `sort -u` |
| L1 命名規則マッチ | `test_foo.bats` から `scripts/foo.sh`, `scripts/gates/foo.sh`, `scripts/lib/foo.sh` 等を対応付ける |
| L2 静的参照マッチ | test file 内の `source|bash|.` 参照を shell basename で対応付ける |
| L3 特別扱い | hooks, gates, deploy_task, cmd_complete_gate, cmd_save, report_field_set の広い関連テストを追加 |
| L4 fallback | script stem と `test_<stem>*.bats` の部分一致 |
| WARN/出力 | マッピングなしは WARN、関連テストは stdout に sort 済みで出力 |

## 最適化パターン

L2 は `SCRIPT_PATHS_BY_BASENAME` を使う。
`find "$REPO_ROOT/scripts" "$REPO_ROOT/lib" -name '*.sh'` を 1 回だけ実行し、basename → relative path list の索引を作ってから、各 test file の shell 参照を引く。

この構造により、テスト内 shell 参照 N 件に対して `find` を N 回実行する旧方式を避ける。
WSL2 `/mnt/c` では repeated `find` が支配的なため、selector の基本方針は「全体索引を 1 回作って bash 配列で引く」。

## 禁止パターン

- L2 の参照ごとに `find "$REPO_ROOT/scripts" "$REPO_ROOT/lib" -name "$script_base"` を呼ばない。
- WARN なしで未知ファイルを黙って捨てない。
- 未知ファイル時に全テストへフォールバックしない。pre-push の diff-aware 契約が崩れる。
- `scripts/gates/*` の変更を basename 直撃だけに狭めない。gate 系は広い関連テストが必要。

## 計測値

| 入力 | before平均 | after平均 | 改善率 |
|------|------------|-----------|--------|
| `scripts/deploy_task.sh` | 11827ms | 3609ms | -69.5% |
| `scripts/gates/gate_report_format.sh` | 10184ms | 4092ms | -59.8% |
| `scripts/test_select.sh` | 10014ms | 3823ms | -61.8% |
| `tests/unit/test_yaml_field_set.bats` | 10602ms | 4089ms | -61.4% |
| `README.md` | 10120ms | 4058ms | -59.9% |

After値は cmd_2584 報告 YAML の Phase 5 表を正とする。
