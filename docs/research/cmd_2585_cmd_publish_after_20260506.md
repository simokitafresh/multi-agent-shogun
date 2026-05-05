# cmd_publish.sh After設計書（リファクタリング後のas-is）

## 現在の構造

対象: `scripts/cmd_publish.sh`

関数:

- `count_active_shogun_lessons()`: `projects/infra/lessons_shogun.yaml` の active lesson 件数を `awk` で単一整数として返す。
- `count_cmd_save_blocks_for_cmd()`: `logs/cmd_design_quality.yaml` の `entries` を `awk` で entry block scan し、対象cmdの `cmd_save` 由来 `BLOCK` 件数を返す。
- `shogun_lesson_exists_for_cmd()`: 前cmdの教訓記録有無を `source_cmd` または本文参照で確認する。
- `run_publish_preflight()`: lesson上限と前cmd BLOCK未還流を cmd_save 前に検査する。

## 最適化パターン

- 小さな scalar YAML scan は Python/PyYAML を起動せず `awk` で処理する。
- 件数取得で `grep -c ... || echo 0` を使わない。0件時に `grep` が status 1 を返し、stdout が `0\n0` になり得る。
- entry block scan は `- cmd_id:` を entry boundary とし、必要フィールドだけ保持して `END` で最後の entry を flush する。

## 禁止パターン

- pre-flight hot path で `python3` を起動しない。cmd起票のたびに startup cost が乗る。
- `grep -c` の exit status をそのまま `|| echo 0` と組み合わせない。出力値と終了値の意味がずれる。
- 運用YAMLの status 更新経路を `yaml_field_set` 以外へ置換しない。

## 計測値

Before（5 tests, `bats tests/unit/test_cmd_publish_preflight.bats`）:

| run | elapsed |
|---|---:|
| 1 | 0.658s |
| 2 | 0.698s |
| 3 | 0.714s |
| 4 | 0.625s |
| 5 | 0.692s |
| average | 0.677s |
| average/test | 0.135s |

After（6 tests。quoted YAML regression と 0 lesson regression を追加後）:

| run | elapsed |
|---|---:|
| 1 | 0.785s |
| 2 | 0.813s |
| 3 | 0.747s |
| 4 | 0.928s |
| 5 | 0.855s |
| average | 0.826s |
| average/test | 0.138s |

解釈: テストを5件から6件へ増やしたため総時間は増加。1テスト平均は同等範囲で、今回の主成果は Python 起動除去と `grep -c` 二重0出力の防止。

## 検証

- `bash -n scripts/cmd_publish.sh`: PASS
- `bats tests/unit/test_cmd_publish_preflight.bats`: 6/6 PASS

## CoDD生成結果

CoDD pipeline:

- `codd init`: PASS
- `codd plan --init`: PASS（4 waves / 7 artifacts）
- `codd generate`: wave 1-3 generated, wave 4 failed（org monthly usage limit）
- `codd validate`: FAIL（wave 4未生成 + generated node_id naming warnings）

保存した生成物:

- `docs/research/cmd_2585_codd_generated_system_design.md`
- `docs/research/cmd_2585_codd_generated_adr_awk_replacement.md`
- `docs/research/cmd_2585_codd_generated_awk_block_scanner.md`
- `docs/research/cmd_2585_codd_generated_preflight_sequence.md`

最終実装の正本は本 after 設計書と `docs/research/cmd_2585_cmd_publish_refactor_spec.md`。CoDD生成物には「5テスト」「200ms短縮目標」など生成時点の前提が残るため、最終計測値は本書の表を正とする。
