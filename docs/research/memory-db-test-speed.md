# memory DB test speed cycle

## 改善候補

| 優先 | 対象 | 実測・根拠 | 判断 |
|---|---|---|---|
| 1 | [[test_memory_db.bats]] concurrent readers | reader出力先の作成が起動後だったため20件すべてがredirect前に失敗可能で、完走数の検証もなかった | L389と同型の偽PASSを解消し、done marker 20/20を強制 |
| 2 | [[test_memory_db.bats]] query tests | FTS/default/guardの3テストが個別にimportを再実行し、基準計測で804–1111ms | master fixtureへのquery行共有を次候補とする |
| 3 | [[test_memory_db.bats]] cache generation | 4000行DBに対する20 readers×2秒とcache再生成5回が3242msで最大支配項 | 品質契約を縮小せず、production側cache生成の高速化へ切替候補 |

## 直接参照

- テスト本体: [[test_memory_db.bats]]
- 被テスト実装: [[memory_db_live_insert.py]]
- 検索CLI: [[memory_db_query.sh]]

`tests/unit/test_memory_db.bats` の reader はSQLite `mode=ro` 接続で `SELECT count(*) FROM events` を反復する。修正後は各readerが正常完走した場合だけ `.done` を生成し、20件すべての存在を二値検証する。
