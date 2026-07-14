# stop-check-inbox-test-speed

origin: [[cmd_training_test_speed_test_stop_check_inbox__20260714233517]] -> [[wall-clock-sleep]] -> [[stop-check-inbox-test-speed]]

## 結論

`tests/unit/test_stop_check_inbox.bats` のmtime境界テストは、実時間の1秒待機ではなく比較対象mtime+1秒を明示設定する。整数mtimeの新旧契約を保ちつつ、2テストの固定2秒待機を除去する。

## 直接契約

- [[test_stop_check_inbox.bats]]: T-SCI-016/T-SCI-020で`touch -d "@<基準mtime+1>"`を使う。
- [[stop_check_inbox.sh]]: summary cacheとQ6 flagはいずれも`-nt`または整数mtimeの新旧比較で無効化する。
- 期待値、iteration、テスト件数は変更しない。通常実行と`bats -j 8`の双方でFAIL 0 / SKIP 0を要求する。

## 未採用の改善候補

1. 各testの`mktemp -d`とfixtureディレクトリ生成をmaster fixture複製へ置換する。
2. transcript payload生成のPythonプロセス4回を静的JSON fixtureへ置換する。
