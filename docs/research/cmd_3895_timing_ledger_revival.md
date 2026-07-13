# cmd_3895 timing ledger revival

## 結論

`run_tests.sh all|unit`の完走を既存台帳へ自動接続した。writerは14列batchを`flock`内で再読込し、一時ファイルから`mv`するため、並行writerのlost updateと途中公開を防ぐ。

## schemaとlifecycle

`run_id, repo, commit_sha, suite_root, runner, test_file, test_id_count, wall_sec, status, skip_count, cache_hit, source_fingerprint, measured_at, resource_tags`。

- 根拠: `docs/research/cmd_3894_test_asset_inventory.md` §3-1と設計書v1.4.3 D1'。
- all/unit全体がPASSした後だけbatch publishする。中断・FAILはpublishしない。
- cache hit行は利用量として記録するが、wall比較とsuite鮮度から除外する。
- affected/fileはsuite全体を代表しないためsuite鮮度を更新しない。
- `gate_test_health.sh`は直近2完走runのsuite wall/per-file悪化と、既定168時間のwriter停止をWARNする。通常経路は台帳read-onlyでテストを起動しない。
