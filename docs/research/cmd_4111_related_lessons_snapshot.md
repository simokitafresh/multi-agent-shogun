# cmd_4111 related_lessons memory snapshot SSOT

## 結論

`deploy_task_lesson_memory_boost_fast.py` の独自SQLite backupを廃止し、`memory_db_cache.sh` がatomic publishした共有ext4 snapshotを直接読む構成へ統一した。

## 二値計測

| 境界 | 修正前 | 修正後 | 判定 |
|---|---:|---:|---|
| related_lessons注入全体（cmd_4110 cProfile） | 37.771秒 | 共有snapshot query 0.57秒 | PASS（目標2.712秒以内） |
| memory snapshot処理 | 20.403秒（全体の87.1%、721MB `sqlite3.Connection.backup`） | Python側backup呼出0件 | PASS |
| Python境界fixture | 独自cache directory生成 | cache directory生成0、9/9 PASS・SKIP0 | PASS |

計測コマンドは `prepare_memory_db_for_read` で解決したproduction共有snapshotを `query_lesson_boosts` に渡した。結果は300 eventsを返し、wall 0.57秒だった。

## 品質境界

- hit: 最後にatomic publish済みの完全snapshotを直接readする。
- stale: `memory_db_cache.sh` が旧完全版を即返し、refreshを非同期起動する。
- cold: 正本DBをfail-safeで返し、共有snapshotを非同期warmする。
- next generation: refresh後の次回resolveで新しいatomic generationを読む。
- 二重copy防止: Python実装から`prepare_snapshot`、identity marker、`sqlite3.Connection.backup`を全削除した。

## テスト帰属

focused Python境界は9/9 PASS・FAIL0・SKIP0。`run_tests.sh task queue/tasks/hayate.yaml`は243件を実行し、今回境界外かつ既存dirty差分に帰属する`test_deploy_task_ac_handling.bats`で7 FAIL、SKIP0だったため、当該FAILをcmd_4111の実装判定には混入しない。
