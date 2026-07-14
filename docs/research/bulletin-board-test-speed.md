# Bulletin board test speed

## 結論

`auto archives when bulletin exceeds threshold` の事前条件50件を公開CLIの50回起動ではなくfixtureで生成する。検証対象である51件目の書込み・30件保持・21件archiveという契約は維持する。

## 因果と直接リンク

- [[test_bulletin_board.bats]] の旧L280-L282は `bulletin_write.sh` を50回起動し、baseline 18.38秒中10.449秒を占めた。
- [[bulletin_write.sh]] L391-L394の「`ENTRY_COUNT` が50を超えたら `bulletin_archive.sh --max-keep 30`」を境界契約として検証する。
- [[bulletin_archive.sh]] は最低30件をhot bulletinへ残すため、変更後も `board=30 archive=21` を二値検証する。

origin: [[cmd_training_test_speed_test_bulletin_board__20260714232325]] -> [[50回の重複process起動]] -> [[archive境界fixture化]]
