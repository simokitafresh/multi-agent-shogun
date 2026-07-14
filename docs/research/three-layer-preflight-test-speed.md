# three-layer preflight Unit test speed

`tests/unit/test_three_layer_preflight.bats` は全27件の各`setup`で同一JSONLからSQLite DBを再importしていた。正規DBをLinux `/tmp`上で`setup_file`により一度生成し、各testの独立した`/tmp`パスへcopyする。fixture buildのsemantic indexも空fixtureへ束縛し、本番index走査を混入させない。欠落・破損ケースは従来どおり別パスを明示するため、三層検索とfail-closedの期待値は変えない。被テスト契約は [[three_layer_preflight.sh]]、DB生成契約は [[memory_db_import.py]] を参照する。

## 改善候補

1. `tests/unit/test_three_layer_preflight.bats` setup: 同一SQLite importを27回反復している。最高インパクトとして`/tmp`で1回生成+test別copyへ変更した。
2. `tests/unit/test_three_layer_preflight.bats` verify: 各testでhook scriptを新規Bashから起動する。関数抽出bundle化の余地はあるが、実CLI境界契約を失わない検証が必要。
3. `tests/unit/test_three_layer_preflight.bats` evidence作成: 類似JSONを各testで個別生成している。helper化で保守性を上げられるが、現時点のwall支配項ではない。

origin: [[cmd_training_test_speed_test_three_layer_preflight__20260714235557]] -> [[repeated-sqlite-import]] -> [[three-layer-preflight-test-speed]]
